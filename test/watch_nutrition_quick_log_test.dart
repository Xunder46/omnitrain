// Watch nutrition quick-log — storage, derivation parity, engine entry point,
// and the surface.
//
// Plan: `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`.
// Scenario mapping:
//   S-001 quick-log a favorite food with the phone off   → `S-001 ...`
//   S-002 the phone applies it exactly once              → `S-002 ...`
//   S-003 frequents / favorites parity with the phone     → `S-003 ...`
//   S-004 portion adjustment changes the logged quantity  → `S-004 ...`
//   S-005 the entry survives a kill before sync           → `S-005 ...`
//   S-006 the surface needs no session                    → `S-006 ...`
//
// Process death is simulated the way the watch experiences it: a brand-new
// engine and state are constructed over the same storage and asked to restore.
// Nothing is handed across in memory, so anything the quick-log fails to
// persist is lost by construction.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/session_reconciler.dart';
import 'package:omnitrain/core/utils/foods_i_eat_order.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_screen.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/live_session_fixtures.dart';

const String _protocolRoot = 'watch/sync_protocol';
const String _contractPath = 'watch/contract/watch_nutrition_contract.json';

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _readJson(String relativePath) => _asObject(
  jsonDecode(
    File('${Directory.current.path}/$relativePath').readAsStringSync(),
  ),
);

/// Every schema document, keyed the way `$ref` addresses it — the same
/// documents the phone and both watch clients validate against.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// The message the phone would send: the valid `foods_down` fixture, which is
/// also the dataset the parity contract derives from.
Map<String, Object?> _foodsDown() =>
    _readJson('$_protocolRoot/fixtures/valid/foods_down.json');

Map<String, Object?> _nutritionContract() => _readJson(_contractPath);

List<String> _stringList(Object? value) =>
    ((value as List?) ?? const []).whereType<String>().toList(growable: false);

Map<String, Object?> _payloadOf(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// The phone's own view of the same data: `Food` and `FoodGroup` rows as the
/// app stores them, so the parity below is against the phone's real models
/// rather than against a copy of its rules.
List<Food> _phoneFoods(Map<String, Object?> payload) => [
  for (final row in (payload['foods']! as List).map(_asObject))
    Food(
      id: row['foodId']! as String,
      name: row['name']! as String,
      groupId: row['categoryId'] as String?,
      unitType: FoodUnitType.grams,
      referenceAmount: (row['referenceAmount']! as num).toDouble(),
      referenceLabel: row['referenceLabel']! as String,
      protein: 0,
      carbs: 0,
      fat: 0,
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
];

List<FoodGroup> _phoneGroups(Map<String, Object?> payload) => [
  for (final row in (payload['categories']! as List).map(_asObject))
    FoodGroup(
      id: row['categoryId']! as String,
      name: row['name']! as String,
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
];

/// A food as the phone's own library holds it, macros included, so what the
/// phone builds can be checked for the numbers it derives rather than only for
/// the ids it copies.
Food _food(
  String id,
  String name, {
  String? groupId,
  double referenceAmount = 100,
  String referenceLabel = 'g',
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) => Food(
  id: id,
  name: name,
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: referenceAmount,
  referenceLabel: referenceLabel,
  protein: protein,
  carbs: carbs,
  fat: fat,
  createdAtMs: 0,
  updatedAtMs: 0,
);

/// The phone half of S-002: the real `NutritionState` over a real repository,
/// with the bridge in front of it, so what "the phone applies it" means is
/// asserted against the phone's own day log rather than a stand-in.
class _PhoneNutritionHarness {
  _PhoneNutritionHarness(this.nutrition, this.bridge, this.repository);

  final NutritionState nutrition;
  final WatchNutritionLogBridge bridge;

  /// The phone's storage, which the router's session inbox stages into.
  final MockWorkoutRepository repository;

  static Future<_PhoneNutritionHarness> create({
    List<Food> foods = const [],
    List<FoodGroup> groups = const [],
    WatchMirrorTransport? transport,
  }) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    for (final group in groups) {
      await repository.createFoodGroup(group);
    }
    for (final food in foods) {
      await repository.createFood(food);
    }

    final library = FoodLibraryState(repository);
    await library.loadFoods();
    await library.loadFoodGroups();
    final nutrition = NutritionState(repository);
    await nutrition.loadConsumedToday();

    return _PhoneNutritionHarness(
      nutrition,
      WatchNutritionLogBridge(
        nutrition: nutrition,
        library: library,
        validator: _validator(),
        transport: transport,
      ),
      repository,
    );
  }
}

/// Deterministic clock: the engine and the surface read time only through their
/// injected clock, which is what lets the tests assert wall-clock values.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

class _Harness {
  _Harness({WatchSessionStore? store})
    : clock = _Clock(DateTime.utc(2026, 7, 13, 12)),
      store = store ?? InMemoryWatchSessionStore();

  final _Clock clock;
  final WatchSessionStore store;
  final List<Map<String, Object?>> emitted = [];

  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine engine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
  );

  /// An engine that has already restored, i.e. one that is running.
  Future<WatchSessionEngine> runningEngine() async {
    final live = engine();
    await live.restore();
    return live;
  }

  /// A nutrition state that has already restored its catalog.
  Future<WatchNutritionState> nutritionState(WatchSessionEngine engine) async {
    final state = WatchNutritionState(
      engine: engine,
      store: store,
      validator: _validator(),
      clock: clock.call,
    );
    await state.restore();
    return state;
  }

  /// The state a user sees once the phone has synced the food list.
  Future<WatchNutritionState> syncedNutritionState(
    WatchSessionEngine engine,
  ) async {
    final state = await nutritionState(engine);
    await state.applyFoodsDown(_foodsDown());
    return state;
  }

  /// The watch's own router over the same store — what receives the phone's
  /// replies, exactly as a synced session does on the device.
  WatchSyncOrchestrator orchestrator(
    WatchSessionEngine engine, {
    WatchNutritionState? nutrition,
    WatchSyncTransport? transport,
  }) => WatchSyncOrchestrator(
    transport: transport ?? _RecordingTransport(),
    paths: WatchSessionStartPaths(
      engine: engine,
      store: store,
      validator: _validator(),
      clock: clock.call,
    ),
    engine: engine,
    nutrition: nutrition,
  );
}

void main() {
  group('S-001 quick-logging a food with the phone out of reach', () {
    test('persists the observation and emits it for the phone', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-oatmeal');
      final record = await state.logSelected();

      expect(record.kind, WatchObservationKind.nutritionQuickLog);
      expect(record.payload['foodId'], 'food-oatmeal');
      expect(
        record.payload['servings'],
        closeTo(1.5, 1e-9),
        reason: "the food's remembered portion is what gets logged",
      );
      expect(
        record.payload['calories'],
        closeTo(285, 1e-9),
        reason: '190 kcal a serving, logged at 1.5 servings',
      );
      expect(record.payload['entryId'], record.payload['eventId']);

      final stored = await harness.store.readAll();
      expect(
        stored.observations.map((row) => row.recordId),
        contains(record.recordId),
        reason: 'the log reached storage before anything was emitted',
      );

      final envelope = harness.emitted.last;
      expect(envelope['type'], 'observations_up');
      expect(_validator().validateEnvelope(envelope), isEmpty);
    });

    test(
      'needs no session: the phone being away costs the user nothing',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        final state = await harness.syncedNutritionState(engine);

        state.select('food-banana');
        await state.logSelected();

        expect(engine.session, isNull);
        expect(
          harness.emitted.single['sessionId'],
          startsWith(WatchNutritionSession.prefix),
          reason:
              'a standalone quick-log carries the nutrition log\u2019s own id',
        );
      },
    );

    test(
      'says so on the wrist: the surface reports the log it just made',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        final state = await harness.syncedNutritionState(engine);

        state.select('food-banana');
        await state.logSelected();

        expect(state.confirmation, isNotNull);
        expect(state.confirmation, contains('Banana'));
      },
    );
  });

  group('S-002 the phone applies a quick-log exactly once', () {
    test(
      'a replayed event materialises one entry that matches the wrist',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        final state = await harness.syncedNutritionState(engine);

        state.select('food-oatmeal');
        final record = await state.logSelected();
        final envelope = harness.emitted.last;
        final phone = SyncSessionReconciler.fromSnapshot({
          'sessionId': 's-nutrition-2026-07-13',
          'status': WatchSessionStatus.active,
          'revision': 0,
          'currentExerciseIndex': 0,
          'exercises': const <Object?>[],
          'entries': const <Object?>[],
          'timers': <String, Object?>{},
        });
        phone.applyMessage(envelope);
        phone.applyMessage(envelope);

        final entries = (phone.convergedState()['entries']! as List)
            .map(_asObject)
            .toList();
        expect(
          entries,
          hasLength(1),
          reason: 'exactly once, however often it arrives',
        );
        expect(entries.single, equals(record.payload));
      },
    );

    test(
      'the phone\u2019s receipt is what lets the watch drop the row',
      () async {
        final payload = _payloadOf(_foodsDown());
        final wrist = _Harness();
        final engine = await wrist.runningEngine();
        final state = await wrist.syncedNutritionState(engine);

        state.select('food-egg');
        final record = await state.logSelected();
        expect(
          engine.pendingObservations(),
          hasLength(1),
          reason: 'a log with no session owes the phone a message',
        );

        // The phone takes it, and answers — over its own transport, not by a
        // call in this test. A receipt nobody sends is what let this row be
        // owed forever.
        final reply = RecordingMirrorTransport();
        final phone = await _PhoneNutritionHarness.create(
          foods: _phoneFoods(payload),
          groups: _phoneGroups(payload),
          transport: reply,
        );
        final taken = await phone.bridge.receive(wrist.emitted.last);

        expect(taken.acknowledgedEntryIds, [record.entryId]);
        final receipt = reply.sent.single;
        expect(receipt['type'], 'receipt');
        expect(receipt['origin'], 'phone');
        expect(_payloadOf(receipt)['entryIds'], [record.entryId]);

        final applied = await wrist
            .orchestrator(engine, nutrition: state)
            .receive(receipt);

        expect(
          applied,
          isTrue,
          reason: 'the receipt names a row the watch holds',
        );
        expect(
          engine.pendingObservations(),
          isEmpty,
          reason:
              'nothing is owed once the phone has taken responsibility for it',
        );
        expect(await engine.pruneConfirmed(), contains(record.recordId));
      },
    );

    test('a message the phone refuses to read is not acknowledged', () async {
      final payload = _payloadOf(_foodsDown());
      final reply = RecordingMirrorTransport();
      final phone = await _PhoneNutritionHarness.create(
        foods: _phoneFoods(payload),
        groups: _phoneGroups(payload),
        transport: reply,
      );

      // A receipt asserts the phone has the observation. A message the gate
      // refused was never read, so the phone holds nothing to assert — and a
      // receipt for it would tell the wrist to drop a row nobody took.
      final result = await phone.bridge.receive({
        'protocolVersion': SyncProtocolValidator.protocolVersion + 1,
        'messageId': 'msg-unreadable-1',
        'sessionId': 'nutrition-2026-07-13',
        'type': 'observations_up',
        'origin': 'watch',
        'sentAt': '2026-07-13T17:00:00Z',
        'payload': {
          'events': [
            {
              'entryId': 'e-nutrition-oatmeal-1',
              'eventId': 'e-nutrition-oatmeal-1',
              'kind': WatchObservationKind.nutritionQuickLog,
              'loggedAt': '2026-07-13T17:00:00Z',
              'foodId': 'food-oatmeal',
              'servings': 1.5,
            },
          ],
        },
      });

      expect(result.outcome, WatchNutritionLogOutcome.refused);
      expect(result.acknowledgedEntryIds, isEmpty);
      expect(
        reply.sent,
        isEmpty,
        reason: 'the wrist must keep owing what the phone could not read',
      );
    });

    test('a food the phone cannot place is not owed forever', () async {
      final payload = _payloadOf(_foodsDown());
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      state.select('food-oatmeal');
      final record = await state.logSelected();

      final reply = RecordingMirrorTransport();
      final phone = await _PhoneNutritionHarness.create(
        foods: [
          for (final food in _phoneFoods(payload))
            if (food.id != 'food-oatmeal') food,
        ],
        groups: _phoneGroups(payload),
        transport: reply,
      );

      final result = await phone.bridge.receive(wrist.emitted.last);

      expect(result.unplacedFoodIds, ['food-oatmeal']);
      expect(
        _payloadOf(reply.sent.single)['entryIds'],
        [record.entryId],
        reason:
            'the phone has seen it, so the wrist may stop resending it — a row '
            'nothing can resolve is not a row worth retrying forever',
      );
    });

    test('the phone\u2019s own day log gains one entry, sent twice', () async {
      final payload = _payloadOf(_foodsDown());
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      state.select('food-oatmeal');
      final record = await state.logSelected();

      final phone = await _PhoneNutritionHarness.create(
        foods: _phoneFoods(payload),
        groups: _phoneGroups(payload),
      );
      final envelope = wrist.emitted.last;

      final first = await phone.bridge.receive(envelope);
      final repeated = await phone.bridge.receive(envelope);

      expect(first.outcome, WatchNutritionLogOutcome.applied);
      expect(repeated.outcome, WatchNutritionLogOutcome.applied);
      final logged = phone.nutrition.consumedToday
          .where((row) => row.sourceFoodId == 'food-oatmeal')
          .toList();
      expect(
        logged,
        hasLength(1),
        reason: 'a re-delivered message is not a second meal',
      );
      expect(
        logged.single.amountConsumed,
        (record.payload['servings']! as num) * 100,
        reason:
            'the phone logs what the wrist says was eaten, in the food\u2019s '
            'own unit',
      );
    });

    test('a food the phone no longer has is reported, not invented', () async {
      final payload = _payloadOf(_foodsDown());
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      state.select('food-oatmeal');
      await state.logSelected();

      final phone = await _PhoneNutritionHarness.create(
        foods: [
          for (final food in _phoneFoods(payload))
            if (food.id != 'food-oatmeal') food,
        ],
        groups: _phoneGroups(payload),
      );

      final result = await phone.bridge.receive(wrist.emitted.last);

      expect(result.loggedFoodIds, isEmpty);
      expect(
        result.unplacedFoodIds,
        ['food-oatmeal'],
        reason:
            'the phone says what it could not place rather than guessing '
            'at macros it does not have',
      );
      expect(
        phone.nutrition.consumedToday.where(
          (row) => row.sourceFoodId == 'food-oatmeal',
        ),
        isEmpty,
      );
    });

    test('a quick-log is not filed under the session the phone is '
        'mirroring', () async {
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      state.select('food-egg');
      await state.logSelected();
      final envelope = wrist.emitted.last;
      expect(
        envelope['sessionId'],
        WatchNutritionSession.idFor(wrist.clock.now),
        reason: 'no workout is running, so the log names the day it was taken',
      );

      final transport = RecordingMirrorTransport();
      final mirror = LiveSessionMirrorState(
        transport: transport,
        validator: _validator(),
        snapshot: {
          'sessionId': 's-lifting',
          'status': WatchSessionStatus.active,
          'revision': 0,
          'currentExerciseIndex': 0,
          'exercises': const <Object?>[],
          'entries': const <Object?>[],
          'timers': <String, Object?>{},
        },
      );

      final outcome = await mirror.receive(envelope);

      expect(outcome, MirrorOutcome.ignored);
      expect(
        mirror.state['entries'],
        isEmpty,
        reason: 'another session\u2019s news is not this session\u2019s entry',
      );
    });

    test('the router hands what the mirror ignores to the day log', () async {
      final payload = _payloadOf(_foodsDown());
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      state.select('food-oatmeal');
      await state.logSelected();

      final phone = await _PhoneNutritionHarness.create(
        foods: _phoneFoods(payload),
        groups: _phoneGroups(payload),
      );
      final router = WatchIncomingRouter(
        inbox: WatchSessionInbox(
          repository: phone.repository,
          validator: _validator(),
        ),
        mirror: LiveSessionMirrorState(
          transport: RecordingMirrorTransport(),
          validator: _validator(),
          snapshot: {
            'sessionId': 's-lifting',
            'status': WatchSessionStatus.active,
            'revision': 0,
            'currentExerciseIndex': 0,
            'exercises': const <Object?>[],
            'entries': const <Object?>[],
            'timers': const <String, Object?>{},
          },
        ),
        nutrition: phone.bridge,
      );

      final receipt = await router.receive(wrist.emitted.last);

      expect(
        receipt.session,
        MirrorOutcome.ignored,
        reason:
            'the meal is not the workout\u2019s, so the mirror passes it on',
      );
      expect(receipt.loggedFood, isTrue);
      expect(
        phone.nutrition.consumedToday.map((row) => row.sourceFoodId),
        contains('food-oatmeal'),
        reason: 'one arriving message, filed by the phone\u2019s day log',
      );

      // A session\u2019s own news never reaches the day log.
      final sessionNews = await router.receive({
        'protocolVersion': SyncProtocolValidator.protocolVersion,
        'messageId': 'msg-lifecycle-1',
        'sessionId': 's-lifting',
        'type': 'session_lifecycle',
        'origin': 'watch',
        'sentAt': '2026-07-13T17:00:00Z',
        'payload': {'state': 'started', 'at': '2026-07-13T17:00:00Z'},
      });
      expect(sessionNews.session, MirrorOutcome.applied);
      expect(
        sessionNews.nutrition,
        WatchNutritionLogOutcome.ignored,
        reason: 'a session\u2019s own news is not a meal',
      );
    });

    test('a quick-log taken mid-session reaches the day log too', () async {
      final payload = _payloadOf(_foodsDown());
      final wrist = _Harness();
      final engine = await wrist.runningEngine();
      final state = await wrist.syncedNutritionState(engine);

      // A workout is running on the wrist, so the log rides that session and
      // the mirror will own the entry.
      await engine.createSession(modality: 'resistance_lifting');
      final sessionId = engine.session!.sessionId;
      state.select('food-almonds');
      final record = await state.logSelected();
      expect(
        record.sessionId,
        sessionId,
        reason: 'eating during a session is part of that session',
      );

      final phone = await _PhoneNutritionHarness.create(
        foods: _phoneFoods(payload),
        groups: _phoneGroups(payload),
      );
      final router = WatchIncomingRouter(
        inbox: WatchSessionInbox(
          repository: phone.repository,
          validator: _validator(),
        ),
        mirror: LiveSessionMirrorState(
          transport: RecordingMirrorTransport(),
          validator: _validator(),
          snapshot: {
            'sessionId': sessionId,
            'status': WatchSessionStatus.active,
            'revision': 0,
            'currentExerciseIndex': 0,
            'exercises': const <Object?>[],
            'entries': const <Object?>[],
            'timers': const <String, Object?>{},
          },
        ),
        nutrition: phone.bridge,
      );

      final receipt = await router.receive(wrist.emitted.last);

      expect(
        receipt.session,
        MirrorOutcome.applied,
        reason: 'the session owns the entry it logged',
      );
      expect(
        phone.nutrition.consumedToday.where(
          (row) => row.sourceFoodId == 'food-almonds',
        ),
        hasLength(1),
        reason:
            'a snack mid-workout is still food the user ate, and the day\u2019s '
            'numbers are wrong without it',
      );
    });
  });

  group('S-003 frequents / favorites parity with the phone', () {
    test('the phone\u2019s own rule produces the contract\u2019s order', () {
      final contract = _nutritionContract();
      final payload = _payloadOf(_foodsDown());

      final phoneOrder = [
        for (final section in foodsIEatSections(
          foods: _phoneFoods(payload),
          groups: _phoneGroups(payload),
        ))
          for (final food in section.foods) food.id,
      ];

      expect(phoneOrder, _stringList(contract['phoneOrder']));
    });

    test('the wrist derives the same list, recents first', () async {
      final contract = _nutritionContract();
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      expect(
        state.foods.map((food) => food.foodId).toList(),
        _stringList(contract['phoneOrder']),
        reason:
            'with nothing logged yet, the wrist shows the phone\u2019s order',
      );

      // Logged oldest first, as a user would: the list keeps the newest on top.
      final recents = _stringList(
        _asObject(contract['recentlyLoggedFoodIds'])['ids'],
      );
      for (final foodId in recents.reversed) {
        state.select(foodId);
        await state.logSelected();
      }

      expect(
        state.foods.map((food) => food.foodId).toList(),
        _stringList(contract['expected']),
        reason: 'what the wrist logs moves to the front, in recency order',
      );
    });

    test('a synced food carries what the wrist prints and logs', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      final oatmeal = state.food('food-oatmeal')!;
      expect(oatmeal.name, 'Oatmeal');
      expect(oatmeal.referenceAmount, closeTo(100, 1e-9));
      expect(oatmeal.referenceLabel, 'g');
      expect(oatmeal.caloriesAt(1.5), 285);
    });

    test(
      'the catalog is stored and an older view is not a newer truth',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        final state = await harness.syncedNutritionState(engine);

        final current = _foodsDown();
        final older = {
          ...current,
          'messageId': 'msg-foods-0',
          'sentAt': '2026-07-13T16:00:00Z',
          'payload': {
            ..._payloadOf(current),
            'generatedAt': '2026-07-13T16:00:00Z',
            'foods': [
              {
                'foodId': 'food-toast',
                'name': 'Toast',
                'categoryId': null,
                'referenceAmount': 1,
                'referenceLabel': 'slice',
                'caloriesPerServing': 80,
                'defaultServings': 1,
              },
            ],
          },
        };

        final result = await state.applyFoodsDown(older);

        expect(result.applied, isFalse);
        expect(
          result.decision.accepted,
          isTrue,
          reason: 'understood and dropped is not a rejection',
        );
        expect(state.food('food-toast'), isNull);
        expect(state.food('food-oatmeal'), isNotNull);
      },
    );

    test('a message the wrist cannot read is refused whole', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      final result = await state.applyFoodsDown({'type': 'foods_down'});

      expect(result.applied, isFalse);
      expect(result.decision.accepted, isFalse);
      expect(state.food('food-oatmeal'), isNotNull);
    });

    test('the orchestrator routes a synced list to the surface', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.nutritionState(engine);
      final orchestrator = WatchSyncOrchestrator(
        transport: _RecordingTransport(),
        paths: WatchSessionStartPaths(
          engine: engine,
          store: harness.store,
          validator: _validator(),
          clock: harness.clock.call,
        ),
        engine: engine,
        nutrition: state,
      );

      final applied = await orchestrator.receive(_foodsDown());

      expect(applied, isTrue);
      expect(
        state.foods.map((food) => food.foodId).toList(),
        _stringList(_nutritionContract()['phoneOrder']),
      );
    });

    test('the phone builds the list the wrist reads', () {
      final envelope = WatchReferenceSync.buildFoodsDown(
        generatedAt: DateTime.utc(2026, 7, 13, 17),
        groups: _phoneGroups(_payloadOf(_foodsDown())),
        foods: [
          _food('food-almonds', 'Almonds', protein: 6, carbs: 6, fat: 15),
          _food(
            'food-egg',
            'Egg',
            groupId: 'foodcat-protein',
            referenceAmount: 1,
            referenceLabel: 'egg',
            protein: 6.3,
            carbs: 0.6,
            fat: 5.3,
          ),
          _food(
            'food-banana',
            'Banana',
            groupId: 'foodcat-fruit',
            protein: 1.3,
            carbs: 23,
            fat: 0.3,
          ),
          _food(
            'food-oatmeal',
            'Oatmeal',
            groupId: 'foodcat-carbs',
            protein: 5,
            carbs: 34,
            fat: 3.5,
          ),
        ],
      );

      expect(
        _validator()
            .evaluateIncoming(
              envelope,
              receiverVersion: SyncProtocolValidator.protocolVersion,
            )
            .accepted,
        isTrue,
        reason: 'what the phone builds must pass the wrist\u2019s own gate',
      );

      final payload = _payloadOf(envelope);
      expect(
        (payload['foods']! as List)
            .map((row) => _asObject(row)['foodId'])
            .toList(),
        ['food-oatmeal', 'food-banana', 'food-egg', 'food-almonds'],
        reason:
            'the phone sorts by its own Foods I Eat rule before sending, so '
            'the wrist does not have to be told the rule',
      );
      expect(
        (payload['foods']! as List)
            .map(_asObject)
            .firstWhere(
              (row) => row['foodId'] == 'food-oatmeal',
            )['caloriesPerServing'],
        188,
        reason:
            'the energy the wrist prints is derived from the phone\u2019s '
            'macros, not typed in twice',
      );
      expect(
        (payload['foods']! as List)
            .map(_asObject)
            .firstWhere((row) => row['foodId'] == 'food-almonds')['categoryId'],
        isNull,
        reason: 'a food outside every group has no category to name',
      );
    });

    test('what the phone sends is what the wrist shows', () async {
      final phoneFoods = [
        _food(
          'food-banana',
          'Banana',
          groupId: 'foodcat-fruit',
          protein: 1.3,
          carbs: 23,
          fat: 0.3,
        ),
        _food(
          'food-oatmeal',
          'Oatmeal',
          groupId: 'foodcat-carbs',
          protein: 5,
          carbs: 34,
          fat: 3.5,
        ),
      ];
      final groups = _phoneGroups(_payloadOf(_foodsDown()));
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.nutritionState(engine);

      await state.applyFoodsDown(
        WatchReferenceSync.buildFoodsDown(
          generatedAt: harness.clock.now,
          foods: phoneFoods,
          groups: groups,
        ),
      );

      expect(
        state.foods.map((food) => food.foodId).toList(),
        [
          for (final section in foodsIEatSections(
            foods: phoneFoods,
            groups: groups,
          ))
            for (final food in section.foods) food.id,
        ],
        reason:
            'a phone that sends its own order hands the wrist the list the '
            'user would have seen on the phone',
      );
      expect(state.food('food-oatmeal')!.caloriesAt(1), 188);
    });
  });

  group('S-004 portion adjustment changes the logged quantity', () {
    test('a detent moves the portion by the contract\u2019s step', () async {
      final contract = _nutritionContract();
      final portion = _asObject(contract['portion']);
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-oatmeal');
      final before = state.servings;
      state.stepPortion(1);

      expect(
        state.servings - before,
        closeTo((portion['stepServings']! as num).toDouble(), 1e-9),
      );

      state.stepPortion(-1);
      expect(state.servings, closeTo(before, 1e-9));
    });

    test('the synced entry reflects the adjusted quantity', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-oatmeal');
      state.stepPortion(1); // 1.5 → 2.0
      final record = await state.logSelected();

      expect(record.payload['servings'], closeTo(2, 1e-9));
      expect(record.payload['calories'], closeTo(380, 1e-9));
      expect(_validator().validateEnvelope(harness.emitted.last), isEmpty);
    });

    test('the portion stays inside the contract\u2019s bounds', () async {
      final contract = _nutritionContract();
      final portion = _asObject(contract['portion']);
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-oatmeal');
      state.stepPortion(-99);
      expect(
        state.servings,
        closeTo((portion['minServings']! as num).toDouble(), 1e-9),
      );

      state.stepPortion(999);
      expect(
        state.servings,
        closeTo((portion['maxServings']! as num).toDouble(), 1e-9),
      );
    });

    test('a new selection starts from that food\u2019s own portion', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-oatmeal');
      state.stepPortion(2);
      state.select('food-egg');

      expect(state.servings, closeTo(2, 1e-9));
      expect(state.selected?.foodId, 'food-egg');
    });

    testWidgets('the two steppers carry a shape and a name', (tester) async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);
      state.select('food-oatmeal');

      await tester.pumpWidget(
        MaterialApp(home: WatchNutritionScreen(state: state)),
      );
      await tester.pump();

      for (final key in [
        WatchNutritionScreen.stepUpKey,
        WatchNutritionScreen.stepDownKey,
      ]) {
        final button = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(IconButton),
          ),
        );
        expect(
          button.style?.shape?.resolve(const <WidgetState>{}),
          isA<RoundedRectangleBorder>(),
          reason: 'every button carries its own shape, the watch included',
        );
        expect(
          button.tooltip,
          isNotNull,
          reason: 'a bare icon is not a name for the screen reader',
        );
      }

      final before = state.servings;
      await tester.tap(find.byKey(WatchNutritionScreen.stepUpKey));
      await tester.pump();
      expect(
        state.servings,
        closeTo(before + WatchNutritionPortion.stepServings, 1e-9),
      );
    });
  });

  group('S-005 a quick-log survives a kill before sync', () {
    test('the synced list survives a kill in Hive', () async {
      final tempDir = await Directory.systemTemp.createTemp('watch_nutrition_');
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      Hive.init(tempDir.path);

      final harness = _Harness(store: HiveWatchSessionStore());
      final state = await harness.syncedNutritionState(
        await harness.runningEngine(),
      );
      final expected = state.foods.map((food) => food.foodId).toList();

      // The kill: every box closes, and a brand-new store opens the same files.
      await Hive.close();
      Hive.init(tempDir.path);

      final rebooted = _Harness(store: HiveWatchSessionStore());
      final restored = await rebooted.nutritionState(
        await rebooted.runningEngine(),
      );

      expect(
        restored.foods.map((food) => food.foodId).toList(),
        expected,
        reason: 'the list is read back off the disk, not out of memory',
      );
      expect(restored.food('food-oatmeal')!.caloriesAt(1.5), 285);
      expect(restored.syncedAt, state.syncedAt);
    });

    test('a relaunch restores the entry and delivers it later', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      state.select('food-greek-yogurt');
      final record = await state.logSelected();

      // The kill: a fresh engine and a fresh state over the same storage.
      final relaunched = await harness.runningEngine();
      final restored = await harness.nutritionState(relaunched);

      expect(
        relaunched.pendingObservations(),
        hasLength(1),
        reason: 'the unacknowledged log is rebuilt from storage',
      );
      expect(
        relaunched.pendingObservations().single['payload'],
        equals({
          'events': [record.payload],
        }),
      );

      final transport = _RecordingTransport();
      final orchestrator = WatchSyncOrchestrator(
        transport: transport,
        paths: WatchSessionStartPaths(
          engine: relaunched,
          store: harness.store,
          validator: _validator(),
          clock: harness.clock.call,
        ),
        engine: relaunched,
      );
      await orchestrator.sync();

      expect(restored.foods, isNotEmpty);
      expect(
        transport.sent.map((message) => message['type']),
        contains('observations_up'),
        reason: 'the phone is handed the log it never received',
      );
    });

    test('a log taken mid-session travels with the session', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      await engine.createSession(modality: 'resistance_lifting');
      state.select('food-almonds');
      final record = await state.logSelected();

      expect(
        record.sessionId,
        engine.session!.sessionId,
        reason: 'eating during a session is part of that session',
      );
      expect(
        engine.entries.map((entry) => entry.recordId),
        contains(record.recordId),
      );
    });
  });

  group('S-006 the surface needs no session', () {
    testWidgets('it lists the synced foods, adjusts, and logs', (tester) async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);

      await tester.pumpWidget(
        MaterialApp(home: WatchNutritionScreen(state: state)),
      );
      await tester.pump();

      expect(find.text('Oatmeal'), findsOneWidget);
      expect(engine.session, isNull, reason: 'no workout is running');

      await tester.tap(find.text('Oatmeal'));
      await tester.pump();
      expect(find.text(state.portionLabel), findsOneWidget);

      await tester.tap(find.byKey(WatchNutritionScreen.logKey));
      await tester.pump();

      expect(
        find.textContaining('Oatmeal'),
        findsWidgets,
        reason: 'the confirmation names what was logged',
      );
      expect(
        engine.nutritionLog.map((row) => row.payload['foodId']),
        contains('food-oatmeal'),
      );
    });

    testWidgets('with nothing synced it says who fixes that', (tester) async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.nutritionState(engine);

      await tester.pumpWidget(
        MaterialApp(home: WatchNutritionScreen(state: state)),
      );
      await tester.pump();

      expect(find.textContaining('Sync'), findsOneWidget);
    });

    testWidgets('the watch home offers it with no workout running', (
      tester,
    ) async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      var opened = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: WatchStartScreen(
            paths: WatchSessionStartPaths(
              engine: engine,
              store: harness.store,
              validator: _validator(),
              clock: harness.clock.call,
            ),
            onOpenNutrition: () => opened++,
          ),
        ),
      );
      await tester.pump();

      final tile = find.text(WatchStartScreen.logFoodLabel);
      expect(
        tile,
        findsOneWidget,
        reason:
            'eating is not a training event: the tile is on the home screen',
      );

      await tester.tap(tile);
      await tester.pump();
      expect(opened, 1);
    });

    test('logging consults no permission: no sensor is involved', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      // No sensor recorder is injected anywhere on this path — nutrition
      // logging requires no Motion & Fitness or Health permission to work.
      final state = await harness.syncedNutritionState(engine);

      state.select('food-egg');
      await state.logSelected();

      expect(engine.nutritionLog, hasLength(1));
    });
  });

  group('protocol serialization', () {
    test('the event matches the shape the protocol fixture pins', () async {
      final fixture = _readJson(
        '$_protocolRoot/fixtures/valid/observations_up.json',
      );
      final fixtureEvent = (_payloadOf(fixture)['events']! as List)
          .map(_asObject)
          .firstWhere(
            (event) => event['kind'] == WatchObservationKind.nutritionQuickLog,
          );

      final harness = _Harness();
      final engine = await harness.runningEngine();
      final state = await harness.syncedNutritionState(engine);
      state.select('food-oatmeal');
      final record = await state.logSelected();

      expect(
        record.payload.keys.toSet(),
        fixtureEvent.keys.toSet(),
        reason: 'the wrist adds no field the fixture does not carry',
      );
      expect(
        record.payload['loggedAt'],
        isA<String>().having(
          (value) => RegExp(r'^\d{4}-\d{2}-\d{2}T.*Z$').hasMatch(value),
          'ISO-8601 UTC',
          isTrue,
        ),
      );
    });

    test('the kinds the wrist can emit are a closed set', () {
      expect(
        WatchObservationKind.all,
        unorderedEquals([
          'set',
          'timed',
          'round',
          'hold',
          WatchObservationKind.nutritionQuickLog,
        ]),
        reason:
            'what the phone can be sent is a list, not whatever a client '
            'happens to spell',
      );
    });
  });
}

class _RecordingTransport implements WatchSyncTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  bool get isPhoneReachable => true;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}
