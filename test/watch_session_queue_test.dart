// The phone's graph over the REAL transport: a queued copy keeps the debt, the
// devices meet, and static data is never pushed (plan 67a Phase 2, run E1).
//
// Plan:
// `docs/plans/2026-10-23-67a-phone-queues-workout-messages-plan/2026-10-23-67a-phone-queues-workout-messages-plan.md`
// (D-1, D-4).
// Scenario mapping:
//   S-9720 a queued copy keeps the debt   → `S-9720 ...`
//   S-9721 the devices meet               → `S-9721 ...`
//   S-9722 a watch food log while apart   → `S-9722 ...`
//   S-9723 static data is never pushed    → `S-9723 ...`
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the push it returns — over the real `WatchConnectivityTransport`,
// whose channel is a fake with the Phase 1 queue capability. The wrist side is
// the real engine over an in-memory store. Every window is closed by `flush()`
// rather than by waiting, and the tests are plain `test()` on a pinned clock:
// no `testWidgets`, no real `Future.delayed`.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_queue_control.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which is
// the only way they reach a repository: the projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

/// The phone's clock. Mutable so a scenario can advance it (S-9723).
DateTime _now = DateTime.utc(2026, 10, 23, 10);

/// Real time, but strictly increasing by at least a millisecond per read, so a
/// timer finished right after it started always ends after it began.
DateTime Function() _tickingClock() {
  var lastMs = 0;
  return () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    lastMs = nowMs > lastMs ? nowMs : lastMs + 1;
    return DateTime.fromMillisecondsSinceEpoch(lastMs);
  };
}

/// The session both devices know.
const String _sessionId = 's-1';

/// The slot the phone logs its sets on.
const String _firstSlot = 'sx-1';

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

List<String> _entryIds(Map<String, Object?> payload) => [
  for (final entry in _objects(payload['entries']))
    entry['entryId']! as String,
];

/// One ladder slot as the protocol spells it.
Map<String, Object?> _slot(
  String id,
  String exerciseId,
  String name,
  List<String> capabilities,
) => <String, Object?>{
  'sessionExerciseId': id,
  'exerciseId': exerciseId,
  'name': name,
  'effortKind': 'set',
  'capabilities': capabilities,
};

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// A catalog the phone can open a session from.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-squat',
    name: 'Squat',
    capabilities: ['sets', 'reps', 'load'],
  );
}

/// A library food as the phone's repository holds one.
Food _food(String id, String name) => Food(
  id: id,
  name: name,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 2,
  carbs: 20,
  fat: 1,
  createdAtMs: _now.millisecondsSinceEpoch,
  updatedAtMs: _now.millisecondsSinceEpoch,
);

/// The fake platform channel the real transport talks to: it implements the
/// Phase 1 core capability, so the transport can list and cancel what the OS
/// still holds.
class _Channel implements WatchMessageChannel, WatchQueueControl {
  bool reachable = true;

  /// Frames the live radio carried, in order.
  final List<Map<String, Object?>> sent = [];

  /// Frames handed to the OS queue, in order (a repeat of a messageId is
  /// recorded again).
  final List<Map<String, Object?>> queued = [];

  /// What the OS still holds, in queue order.
  final List<WatchQueuedTransfer> outstanding = [];

  /// The ids of every cancel call, in order.
  final List<List<String>> cancels = [];

  final StreamController<Map<String, Object?>> inbound =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<bool> reachabilityEvents =
      StreamController<bool>.broadcast();

  @override
  Future<bool> get isPaired async => true;
  @override
  Future<bool> get isReachable async => reachable;
  @override
  Stream<Map<String, Object?>> get messages => inbound.stream;
  @override
  Stream<bool> get reachability => reachabilityEvents.stream;
  @override
  Future<WatchLinkInfo> get info async =>
      WatchLinkInfo(paired: true, appInstalled: true, reachable: reachable);

  @override
  Future<void> send(Map<String, Object?> frame) async => sent.add(frame);

  @override
  Future<void> queue(Map<String, Object?> frame) async {
    queued.add(frame);
    final id = frame['messageId'];
    if (id is String && outstanding.any((held) => held.messageId == id)) return;
    final payload = frame['payload'];
    final change = payload is Map ? payload['changeId'] : null;
    outstanding.add(
      WatchQueuedTransfer(
        messageId: id is String ? id : '',
        type: frame['type'] is String ? frame['type'] as String : '',
        sessionId: frame['sessionId'] is String ? frame['sessionId'] as String : null,
        changeId: change is String ? change : null,
      ),
    );
  }

  @override
  Future<List<WatchQueuedTransfer>> outstandingTransfers() async =>
      List<WatchQueuedTransfer>.of(outstanding);

  @override
  Future<int> cancelTransfers(List<String> messageIds) async {
    cancels.add(List<String>.of(messageIds));
    final before = outstanding.length;
    outstanding.removeWhere((held) => messageIds.contains(held.messageId));
    return before - outstanding.length;
  }

  /// One frame from the wrist, delivered the way the platform delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    inbound.add(frame);
    await pumpEventQueue();
  }

  /// Everything the live radio carried of one type.
  List<Map<String, Object?>> liveOfType(String type) => [
    for (final frame in sent) if (frame['type'] == type) frame,
  ];

  /// The held transfers of one type.
  List<WatchQueuedTransfer> heldOfType(String type) => [
    for (final held in outstanding) if (held.type == type) held,
  ];
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _Channel channel;
  late WatchConnectivityTransport transport;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Object> failures;
  late NutritionState nutrition;
  late FoodLibraryState library;

  /// The phone graph a fresh app start builds, over [transport]. The app binds
  /// its own `WorkoutState` to the adoption and to the push in `lib/main.dart`;
  /// the scenarios bind the push themselves, once their fixture has settled.
  Future<WatchSyncGraph> startGraph() async {
    nutrition = NutritionState(repository);
    library = FoodLibraryState(repository);
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: nutrition,
      foodLibraryState: library,
      settingsState: phoneSettings,
      transport: transport,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
    ))!;
    created.adoption.bindWorkoutState(phoneState);
    return created;
  }

  /// The wrist starts [_sessionId] with one slot, and the phone adopts it: the
  /// fixture S-9720…S-9723 start from.
  Future<void> wristStartsSession() async {
    await engine.createSession(
      modality: null,
      exercises: [
        _slot(_firstSlot, 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
      ],
    );
    await channel.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    expect(graph.mirror.sessionId, _sessionId);
  }

  /// Records a rest at the index after [effortId]'s last group, which is what
  /// makes that set a logged set (D-1, I-1). A no-op for a slot holding no set
  /// row at all.
  Future<void> markLastSetLogged(String effortId) async {
    final groups = EntryRows.setGroups(
      await repository.getEffortObservations(effortId),
    );
    if (groups.isEmpty) return;
    await phoneState.recordRestStart(effortId, groups.last.number + 1);
  }

  /// The phone logs one set on [effortId] — the entry the session screen's Log
  /// writes, and then the rest that follows it (D-1, I-1): a set with no rest
  /// after it is a planned value and rides no frame (A1).
  Future<void> logSet(
    String effortId, {
    Map<String, dynamic>? previousValues,
  }) async {
    await phoneState.addEntry(effortId, previousValues: previousValues);
    await markLastSetLogged(effortId);
  }

  /// The fixture S-9720 and S-9721 start from: the wrist's session adopted, one
  /// set logged and pushed live, then the devices apart with a clean slate.
  Future<void> startWithOneSetLogged() async {
    await wristStartsSession();
    graph.autoPush.bindWorkoutState(phoneState);
    await logSet('sx-1', previousValues: {'reps': 8, 'weight': 62.5});
    await graph.autoPush.flush();
    channel.sent.clear();
    channel.queued.clear();
    channel.outstanding.clear();
    channel.cancels.clear();
    channel.reachable = false;
    expect(channel.reachable, isFalse, reason: 'the fixture: the devices are apart');
    expect(
      await graph.autoPush.hasUnsentChange(),
      isFalse,
      reason: 'the fixture: the live push was delivered, nothing is owed',
    );
  }

  /// S-9720's trigger: a second and a third set, each window closed by a flush.
  Future<List<Map<String, Object?>>> queueTwoSnapshots() async {
    await logSet('sx-1', previousValues: {'reps': 8, 'weight': 62.5});
    await graph.autoPush.flush();
    expect(
      await graph.autoPush.hasUnsentChange(),
      isTrue,
      reason: 'a queued copy is a carrier, not a delivery (D-1)',
    );
    await logSet('sx-1', previousValues: {'reps': 8, 'weight': 62.5});
    await graph.autoPush.flush();
    expect(
      await graph.autoPush.hasUnsentChange(),
      isTrue,
      reason: 'a queued copy is a carrier, not a delivery (D-1)',
    );
    return [
      for (final frame in channel.queued)
        if (frame['type'] == 'session_snapshot') frame,
    ];
  }

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository, clock: _tickingClock());
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    channel = _Channel();
    transport = WatchConnectivityTransport(
      channel: channel,
      onFailure: (error, stack) => failures.add(error),
    );
    addTearDown(transport.close);
    graph = await startGraph();

    wristStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: (_) {},
    );
  });

  group('S-9720 a queued copy keeps the debt', () {
    test(
      'S-9720 two sets while apart queue two snapshots, the newest only is '
      'held, and the debt stays owed',
      () async {
        await startWithOneSetLogged();
        final queuedSnaps = await queueTwoSnapshots();

        expect(queuedSnaps, hasLength(2), reason: 'one queued copy per window');
        expect(channel.liveOfType('session_snapshot'), isEmpty);
        expect(channel.cancels, [
          [queuedSnaps.first['messageId']],
        ], reason: 'the newer copy withdraws the older one (D-3)');
        final held = channel.heldOfType('session_snapshot');
        expect(held, hasLength(1));
        expect(held.single.sessionId, _sessionId);
        expect(
          held.single.messageId,
          queuedSnaps.last['messageId'],
          reason: 'the newest copy is the one the OS holds',
        );
        expect(
          _entryIds(_payload(queuedSnaps.last)),
          hasLength(3),
          reason: 'the newest copy carries all three logged sets',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-9721 the devices meet', () {
    test(
      'S-9721 a wrist request delivers the owed snapshot live, withdraws the '
      'queued copy, and clears the debt',
      () async {
        await startWithOneSetLogged();
        final queuedSnaps = await queueTwoSnapshots();

        channel.reachable = true;
        await channel.fromWrist(WatchTransportRequest.routinesFrame());
        await _settle();

        final live = channel.liveOfType('session_snapshot');
        expect(live, hasLength(1), reason: 'the owed snapshot is delivered live');
        expect(
          _entryIds(_payload(live.single)),
          hasLength(3),
          reason: 'the live copy carries the same three sets the queued one did',
        );
        expect(
          channel.heldOfType('session_snapshot'),
          isEmpty,
          reason: 'the queued copy is withdrawn after the live delivery (D-3)',
        );
        expect(await graph.autoPush.hasUnsentChange(), isFalse);
        await graph.autoPush.flush();
        expect(
          channel.liveOfType('session_snapshot'),
          hasLength(1),
          reason: 'the debt is cleared: no second live snapshot follows',
        );
        expect(queuedSnaps, hasLength(2));
      },
    );
  });

  group('S-9722 a watch food log while apart', () {
    /// The fixture: the phone's library holds Apple, the day log is loaded, the
    /// devices are apart, and no session exists. The graph from `setUp` is
    /// enough — the bridge reads the library's cache, so the load runs after
    /// the food exists.
    Future<void> apartWithApple() async {
      await repository.createFood(_food('food-apple', 'Apple'));
      await library.loadFoods();
      await nutrition.loadConsumedToday();
      channel.reachable = false;
    }

    /// The wrist's `observations_up` with one nutrition quick-log of Apple,
    /// two servings, delivered twice (the second a duplicate).
    Future<void> deliverAppleLogTwice() async {
      final frame = <String, Object?>{
        'protocolVersion': 1,
        'messageId': 'msg-apple-1',
        'sessionId': 's-none',
        'type': 'observations_up',
        'origin': 'watch',
        'sentAt': '2026-10-23T10:00:00Z',
        'payload': {
          'events': [
            {
              'eventId': 'evt-apple-1',
              'entryId': 'e-apple-1',
              'kind': 'nutrition_quick_log',
              'loggedAt': '2026-10-23T10:00:00Z',
              'foodId': 'food-apple',
              'servings': 2,
              'calories': 160,
            },
          ],
        },
      };
      await channel.fromWrist(frame);
      await channel.fromWrist(frame);
    }

    test(
      'S-9722 a quick log while apart lands one 200 g row and queues one '
      'receipt per delivery',
      () async {
        await apartWithApple();
        await deliverAppleLogTwice();

        await nutrition.loadConsumedToday();
        final rows = [
          for (final row in nutrition.consumedToday)
            if (row.sourceFoodId == 'food-apple') row,
        ];
        expect(
          rows,
          hasLength(1),
          reason: 'the duplicate updates the same row (one per food per day)',
        );
        expect(
          rows.single.amountConsumed,
          200,
          reason: '2 servings of the 100 g reference',
        );

        final receipts = [
          for (final frame in channel.queued)
            if (frame['type'] == 'receipt') frame,
        ];
        expect(
          receipts,
          hasLength(2),
          reason: 'one receipt per delivery, each queued (the devices are apart)',
        );
        expect(
          channel.liveOfType('receipt'),
          isEmpty,
          reason: 'nothing was delivered live',
        );
        for (final receipt in receipts) {
          expect(
            _asObject(receipt['payload'])['entryIds'],
            ['e-apple-1'],
            reason: 'the receipt names the observation the phone took on',
          );
        }
        expect(
          channel.queued.map((frame) => frame['messageId']).toSet(),
          hasLength(2),
          reason: 'each receipt carries its own fresh messageId',
        );
        expect(
          channel.heldOfType('receipt'),
          hasLength(2),
          reason: 'a receipt is never withdrawn and never replaces another',
        );
        expect(
          channel.cancels,
          isEmpty,
          reason: 'a receipt withdraws nothing (D-3)',
        );
        for (final frame in [...channel.sent, ...channel.queued]) {
          final type = frame['type'];
          if (type is String) {
            expect(
              type,
              isNot(endsWith('_down')),
              reason: 'static data travels only as the answer to a pull (D-4)',
            );
          }
        }
        expect(failures, isEmpty);
      },
    );

    test(
      'S-9722 when the devices meet, the receipts the OS holds are not touched',
      () async {
        await apartWithApple();
        await deliverAppleLogTwice();

        channel.reachable = true;
        await _settle();

        expect(
          channel.cancels,
          isEmpty,
          reason: 'the phone never withdraws a receipt (D-3)',
        );
        expect(
          channel.heldOfType('receipt'),
          hasLength(2),
          reason: 'both receipts stay held for the wrist',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-9723 static data is never pushed', () {
    test(
      'S-9723 a rest-ping change, a new food and a routine rename push no '
      'static frame',
      () async {
        // The fixture: rest ping 30, routine tpl-1 "Push A", foods Apple and
        // Oats. No session is adopted — the graph from setUp is enough.
        await phoneSettings.setRestPingInterval(30);
        await repository.createTemplate(
          WorkoutTemplate(
            id: 'tpl-1',
            ownerUserId: null,
            name: 'Push A',
            description: null,
            focusModality: null,
            primaryDisciplineId: null,
            note: null,
            isBuiltInDemo: false,
            createdAtMs: _now.millisecondsSinceEpoch,
            updatedAtMs: _now.millisecondsSinceEpoch,
          ),
        );
        await repository.createFood(_food('food-apple', 'Apple'));
        await repository.createFood(_food('food-oats', 'Oats'));

        // The trigger: rest ping 30 → 45, add food "Rice", rename tpl-1.
        await phoneSettings.setRestPingInterval(45);
        await repository.createFood(_food('food-rice', 'Rice'));
        final template = (await repository.getTemplateById('tpl-1'))!;
        await repository.updateTemplate(template.copyWith(name: 'Push B'));
        _now = _now.add(const Duration(seconds: 10));

        await graph.autoPush.flush();
        await _settle();

        for (final frame in [...channel.sent, ...channel.queued]) {
          final type = frame['type'];
          if (type is String) {
            expect(
              type,
              isNot(endsWith('_down')),
              reason: 'static data travels only as the answer to a pull (D-4)',
            );
          }
        }
        expect(failures, isEmpty);
      },
    );
  });
}
