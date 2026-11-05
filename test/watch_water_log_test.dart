// Plan 94 (PR 94a) Phase 3 — the phone applies the wrist's water taps.
//
// A wrist tap is an `observations_up` event of kind `water_glass` (D-2). The
// phone applies it once to the day the glass was tapped (D-3), through
// `NutritionState.applyWatchWaterTap` (D-12), acknowledges it in a receipt and
// answers with the day's count as a `water_down` (D-8(b), D-13).
//
// Scenario mapping (plan `docs/plans/2026-11-01-94-watch-water-logging-plan/`):
//   S-94a-10 .. S-94a-12 → group "NutritionState.applyWatchWaterTap"
//   S-94a-13 .. S-94a-17, S-94a-20 → group "WatchWaterLogBridge"
//   S-94a-18, S-94a-19 → group "WatchIncomingRouter water"
//
// Plain `test()` only (D-16): the persistence underneath is
// `MockWorkoutRepository`, and every clock is a local wall time converted to
// UTC so the expected days hold in any time zone.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_water_log_bridge.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/live_session_fixtures.dart';
import 'helpers/sync_protocol_harness.dart';

/// Fixture W: local calendar days (D-16).
final DateTime d = DateTime(2026, 11, 1);
final int dMs = d.millisecondsSinceEpoch;
final int pMs = DateTime(2026, 10, 31).millisecondsSinceEpoch;
final int nMs = DateTime(2026, 11, 2).millisecondsSinceEpoch;

/// The default phone clock: noon on `D`, local, as a UTC instant.
DateTime noonOnD() => DateTime(2026, 11, 1, 12).toUtc();

const String nutritionSessionId = 'nutrition-2026-11-01';

Map<String, Object?> tapEvent(String id, String change, DateTime local) => {
  'eventId': id,
  'entryId': id,
  'kind': 'water_glass',
  'loggedAt': isoUtc(local.toUtc()),
  'glassChange': change,
};

/// `tap(id, change, local)` of fixture W: one `water_glass` event in an
/// `observations_up` under the day's nutrition id.
Map<String, Object?> tap(
  String id,
  String change,
  DateTime local, {
  List<Map<String, Object?>> extraEvents = const [],
  Map<String, Object?> eventOverrides = const {},
  Map<String, Object?> payloadExtras = const {},
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-obs-$id',
  'sessionId': nutritionSessionId,
  'type': 'observations_up',
  'origin': 'watch',
  'sentAt': isoUtc(local.toUtc()),
  'payload': {
    'events': [
      ...extraEvents,
      {...tapEvent(id, change, local), ...eventOverrides},
    ],
    ...payloadExtras,
  },
};

Map<String, Object?> payloadOf(Map<String, Object?> envelope) =>
    asObject(envelope['payload']);

/// A phone: storage, the nutrition state over it, a recording radio and the
/// water bridge.
class _Phone {
  _Phone._(this.repository, this.nutrition, this.transport, this.bridge);

  final MockWorkoutRepository repository;
  final NutritionState nutrition;
  final RecordingMirrorTransport transport;
  final WatchWaterLogBridge bridge;

  static Future<_Phone> create({
    Map<int, int> volumes = const {},
    DateTime Function()? clock,
  }) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    for (final entry in volumes.entries) {
      await repository.saveWaterVolumeForDate(entry.key, entry.value);
    }
    final nutrition = NutritionState(repository);
    final transport = RecordingMirrorTransport();
    final bridge = WatchWaterLogBridge(
      nutrition: nutrition,
      repository: repository,
      validator: loadProtocolValidator(),
      transport: transport,
      clock: clock ?? noonOnD,
    );
    return _Phone._(repository, nutrition, transport, bridge);
  }

  List<String?> get sentTypes => [
    for (final frame in transport.sent) frame['type'] as String?,
  ];
}

/// The mirror of a phone holding no session: nothing a wrist sends is its own.
LiveSessionMirrorState _idleMirror() => LiveSessionMirrorState(
  transport: RecordingMirrorTransport(),
  validator: loadProtocolValidator(),
  snapshot: {
    'sessionId': 'no-session',
    'status': WatchSessionStatus.abandoned,
    'revision': 0,
    'currentExerciseIndex': 0,
    'exercises': const <Object?>[],
    'entries': const <Object?>[],
    'timers': const <String, Object?>{},
  },
);

void main() {
  test('D-14 the twin names water_glass and does not emit it', () {
    expect(WatchObservationKind.waterGlass, 'water_glass');
    expect(WatchObservationKind.all, isNot(contains('water_glass')));
  });

  group('NutritionState.applyWatchWaterTap', () {
    test('S-94a-10 a wrist tap for today updates the open screen state, '
        'with one notify', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.saveWaterVolumeForDate(dMs, 500);
      final state = NutritionState(repository);
      await state.loadWaterForDate(dMs);
      var notifies = 0;
      state.addListener(() => notifies++);

      final applied = await state.applyWatchWaterTap(
        dateMs: dMs,
        tapId: 'w-1',
        add: true,
      );

      expect(applied, isTrue);
      expect(state.waterTodayMl, 750);
      expect(state.waterTodayGlasses, 3);
      expect(notifies, 1);
    });

    test('S-94a-11 a tap for another day leaves the cache alone', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.saveWaterVolumeForDate(dMs, 500);
      final state = NutritionState(repository);
      await state.loadWaterForDate(dMs);
      var notifies = 0;
      state.addListener(() => notifies++);

      final applied = await state.applyWatchWaterTap(
        dateMs: pMs,
        tapId: 'w-p',
        add: true,
      );

      expect(applied, isTrue);
      expect(state.waterTodayMl, 500);
      expect(notifies, 0);
      expect(await repository.getWaterVolumeForDate(pMs), 250);
    });

    test('S-94a-11 a state that never loaded a day is not touched by a tap '
        'for D', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.saveWaterVolumeForDate(dMs, 500);
      final fresh = NutritionState(repository);
      var notifies = 0;
      fresh.addListener(() => notifies++);

      final applied = await fresh.applyWatchWaterTap(
        dateMs: dMs,
        tapId: 'w-1',
        add: true,
      );

      expect(applied, isTrue);
      expect(fresh.waterTodayMl, 0);
      expect(notifies, 0);
      expect(await repository.getWaterVolumeForDate(dMs), 750);
    });

    test('S-94a-12 a phone tap and a wrist tap at the same moment both '
        'count', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = NutritionState(repository);
      await state.loadWaterForDate(dMs);

      await Future.wait([
        state.incrementWaterForDate(dMs),
        state.applyWatchWaterTap(dateMs: dMs, tapId: 'w-1', add: true),
      ]);

      expect(await repository.getWaterVolumeForDate(dMs), 500);
      expect(state.waterTodayMl, 500);
    });

    test('a write that throws does not block the writes after it', () async {
      final repository = _ThrowOnceRepository();
      await repository.initialize();
      final state = NutritionState(repository);
      await state.loadWaterForDate(dMs);

      final failed = state.incrementWaterForDate(dMs);
      final next = state.applyWatchWaterTap(
        dateMs: dMs,
        tapId: 'w-1',
        add: true,
      );

      await expectLater(failed, throwsStateError);
      expect(await next, isTrue);
      expect(await repository.getWaterVolumeForDate(dMs), 250);
      expect(state.waterTodayMl, 250);
    });
  });

  group('WatchWaterLogBridge', () {
    test('S-94a-13 the bridge applies, acknowledges, then sends the '
        'count', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      final validator = loadProtocolValidator();

      final result = await phone.bridge.receive(
        tap('w-1', 'add', DateTime(2026, 11, 1, 9)),
      );

      expect(result.outcome, WatchWaterLogOutcome.applied);
      expect(await phone.repository.getWaterVolumeForDate(dMs), 750);
      expect(phone.sentTypes, ['receipt', 'water_down']);
      expect(payloadOf(phone.transport.sent[0])['entryIds'], ['w-1']);
      final water = payloadOf(phone.transport.sent[1]);
      expect(water['day'], '2026-11-01');
      expect(water['glasses'], 3);
      expect(water['appliedTapIds'], ['w-1']);
      expect(
        phone.transport.sent[1]['messageId'],
        'msg-water-${noonOnD().millisecondsSinceEpoch}-3-1',
      );
      for (final frame in phone.transport.sent) {
        expect(validator.validateEnvelope(frame), isEmpty, reason: '$frame');
      }
    });

    test('S-94a-14 the same message twice changes nothing and is answered '
        'again', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      final envelope = tap('w-1', 'add', DateTime(2026, 11, 1, 9));

      await phone.bridge.receive(envelope);
      await phone.bridge.receive(envelope);

      expect(await phone.repository.getWaterVolumeForDate(dMs), 750);
      expect(phone.sentTypes, [
        'receipt',
        'water_down',
        'receipt',
        'water_down',
      ]);
      expect(payloadOf(phone.transport.sent[2])['entryIds'], ['w-1']);
      final water = payloadOf(phone.transport.sent[3]);
      expect(water['glasses'], 3);
      expect(water['appliedTapIds'], ['w-1']);
    });

    test('S-94a-15 both devices tapped while apart: nothing is lost', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      await phone.nutrition.loadWaterForDate(dMs);
      await phone.nutrition.incrementWaterForDate(dMs);
      expect(phone.nutrition.waterTodayMl, 750);

      await phone.bridge.receive(tap('w-2', 'add', DateTime(2026, 11, 1, 10)));
      await phone.bridge.receive(
        tap('w-3', 'add', DateTime(2026, 11, 1, 10, 5)),
      );

      expect(await phone.repository.getWaterVolumeForDate(dMs), 1250);
      expect(phone.nutrition.waterTodayGlasses, 5);
      final last = payloadOf(phone.transport.sent.last);
      expect(phone.transport.sent.last['type'], 'water_down');
      expect(last['glasses'], 5);
      expect(last['appliedTapIds'], ['w-2', 'w-3']);
    });

    test('S-94a-16 a glass tapped before midnight, delivered after, counts '
        'on the day it was tapped', () async {
      final phone = await _Phone.create(
        volumes: {dMs: 500, nMs: 0},
        clock: () => DateTime(2026, 11, 2, 0, 0, 30).toUtc(),
      );
      await phone.nutrition.loadWaterForDate(nMs);
      var notifies = 0;
      phone.nutrition.addListener(() => notifies++);

      await phone.bridge.receive(
        tap('w-4', 'add', DateTime(2026, 11, 1, 23, 59, 30)),
      );

      expect(await phone.repository.getWaterVolumeForDate(dMs), 750);
      expect(await phone.repository.getWaterVolumeForDate(nMs), 0);
      expect(phone.nutrition.waterTodayMl, 0);
      expect(notifies, 0);
      final water = payloadOf(phone.transport.sent.last);
      expect(phone.transport.sent.last['type'], 'water_down');
      expect(water['day'], '2026-11-02');
      expect(water['glasses'], 0);
      expect(water['appliedTapIds'], isEmpty);
    });

    test('S-94a-17 unknown or extra fields refuse the whole message', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      final at = DateTime(2026, 11, 1, 9);
      final envelopes = [
        tap('w-1', 'add', at, eventOverrides: {'volumeMl': 250}),
        tap('w-1', 'double', at),
        tap('w-1', 'add', at, payloadExtras: {'note': 'x'}),
      ];

      for (final envelope in envelopes) {
        final result = await phone.bridge.receive(envelope);
        expect(result.outcome, WatchWaterLogOutcome.refused);
      }

      expect(await phone.repository.getWaterVolumeForDate(dMs), 500);
      expect(phone.transport.sent, isEmpty);
      expect(await phone.repository.getAppliedWaterTapIds(dMs), isEmpty);
    });

    test('S-94a-20 (a) a minus at 0 is recorded and acknowledged', () async {
      final phone = await _Phone.create();

      await phone.bridge.receive(
        tap('w-7', 'remove', DateTime(2026, 11, 1, 9)),
      );

      expect(await phone.repository.getWaterVolumeForDate(dMs), 0);
      expect(await phone.repository.getAppliedWaterTapIds(dMs), ['w-7']);
      expect(phone.sentTypes, ['receipt', 'water_down']);
      expect(payloadOf(phone.transport.sent[0])['entryIds'], ['w-7']);
      final water = payloadOf(phone.transport.sent[1]);
      expect(water['glasses'], 0);
      expect(water['appliedTapIds'], ['w-7']);
    });

    test('S-94a-20 (b) a minus from a non-whole volume', () async {
      final phone = await _Phone.create(volumes: {dMs: 600});

      await phone.bridge.receive(
        tap('w-8', 'remove', DateTime(2026, 11, 1, 9)),
      );

      expect(await phone.repository.getWaterVolumeForDate(dMs), 350);
      final water = payloadOf(phone.transport.sent.last);
      expect(water['glasses'], 1);
      expect(water['appliedTapIds'], ['w-8']);
    });

    test('a message with no water tap is ignored and answered with '
        'nothing', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});

      final result = await phone.bridge.receive({
        'protocolVersion': SyncProtocolValidator.protocolVersion,
        'messageId': 'msg-lifecycle-1',
        'sessionId': 's-lifting',
        'type': 'session_lifecycle',
        'origin': 'watch',
        'sentAt': '2026-11-01T17:00:00Z',
        'payload': {'state': 'started', 'at': '2026-11-01T17:00:00Z'},
      });

      expect(result.outcome, WatchWaterLogOutcome.ignored);
      expect(phone.transport.sent, isEmpty);
    });
  });

  group('WatchIncomingRouter water', () {
    test('S-94a-18 taps never touch workout history', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      final library = FoodLibraryState(phone.repository);
      final router = WatchIncomingRouter(
        inbox: WatchSessionInbox(
          repository: phone.repository,
          validator: loadProtocolValidator(),
        ),
        mirror: _idleMirror(),
        nutrition: WatchNutritionLogBridge(
          nutrition: phone.nutrition,
          library: library,
          validator: loadProtocolValidator(),
          transport: phone.transport,
        ),
        water: phone.bridge,
      );

      final receipt = await router.receive(
        tap('w-5', 'add', DateTime(2026, 11, 1, 9)),
      );

      expect(receipt.inbox, WatchInboxOutcome.ignored);
      expect(receipt.session, MirrorOutcome.ignored);
      expect(receipt.nutrition, WatchNutritionLogOutcome.ignored);
      expect(receipt.water, WatchWaterLogOutcome.applied);
      expect(await phone.repository.getWatchInboxEntry('w-5'), isNull);
      expect(
        await phone.repository.getWatchInboxEntriesForSession(
          nutritionSessionId,
        ),
        isEmpty,
      );
      expect(await phone.repository.getWaterVolumeForDate(dMs), 750);

      // The same tap through a router built without a water bridge.
      final other = await _Phone.create(volumes: {dMs: 500});
      final withoutWater = WatchIncomingRouter(
        inbox: WatchSessionInbox(
          repository: other.repository,
          validator: loadProtocolValidator(),
        ),
        mirror: _idleMirror(),
        nutrition: WatchNutritionLogBridge(
          nutrition: other.nutrition,
          library: FoodLibraryState(other.repository),
          validator: loadProtocolValidator(),
          transport: other.transport,
        ),
      );

      final ignored = await withoutWater.receive(
        tap('w-5', 'add', DateTime(2026, 11, 1, 9)),
      );

      expect(ignored.inbox, WatchInboxOutcome.ignored);
      expect(ignored.session, MirrorOutcome.ignored);
      expect(ignored.nutrition, WatchNutritionLogOutcome.ignored);
      expect(ignored.water, WatchWaterLogOutcome.ignored);
      expect(await other.repository.getWaterVolumeForDate(dMs), 500);
      expect(other.transport.sent, isEmpty);
    });

    test('S-94a-19 food and water in one message: two receipts, one '
        'count', () async {
      final phone = await _Phone.create(volumes: {dMs: 500});
      await phone.repository.createFood(
        Food(
          id: 'food-oat',
          name: 'Oats',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: '100 g',
          protein: 13,
          carbs: 68,
          fat: 7,
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      );
      final library = FoodLibraryState(phone.repository);
      await library.loadFoods();
      await phone.nutrition.loadConsumedToday();
      final at = DateTime(2026, 11, 1, 9);
      final router = WatchIncomingRouter(
        inbox: WatchSessionInbox(
          repository: phone.repository,
          validator: loadProtocolValidator(),
        ),
        mirror: _idleMirror(),
        nutrition: WatchNutritionLogBridge(
          nutrition: phone.nutrition,
          library: library,
          validator: loadProtocolValidator(),
          transport: phone.transport,
          clock: () => at.toUtc(),
        ),
        water: phone.bridge,
      );

      final receipt = await router.receive(
        tap(
          'w-6',
          'add',
          at,
          extraEvents: [
            {
              'eventId': 'f-1',
              'entryId': 'f-1',
              'kind': 'nutrition_quick_log',
              'loggedAt': isoUtc(at.toUtc()),
              'foodId': 'food-oat',
              'servings': 1,
              'calories': 387,
            },
          ],
        ),
      );

      expect(receipt.loggedFood, isTrue);
      expect(receipt.water, WatchWaterLogOutcome.applied);
      expect(
        phone.nutrition.consumedToday.where(
          (row) => row.sourceFoodId == 'food-oat',
        ),
        hasLength(1),
      );
      expect(await phone.repository.getWaterVolumeForDate(dMs), 750);
      final receipts = phone.transport.payloadsOf('receipt');
      expect(receipts.map((p) => p['entryIds']), [
        ['f-1'],
        ['w-6'],
      ]);
      expect(phone.transport.payloadsOf('water_down'), hasLength(1));
    });
  });
}

/// Storage whose first water save throws: a failed write must not stall the
/// chain behind it (D-12).
class _ThrowOnceRepository extends MockWorkoutRepository {
  bool _thrown = false;

  @override
  Future<void> saveWaterVolumeForDate(int dateMs, int volumeMl) async {
    if (!_thrown) {
      _thrown = true;
      throw StateError('disk full');
    }
    return super.saveWaterVolumeForDate(dateMs, volumeMl);
  }
}
