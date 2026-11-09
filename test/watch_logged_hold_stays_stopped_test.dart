// A hold logged on the phone stops on the watch and never comes back
// (plan 121a Phase 0a: probes, red first — no production code).
//
// Plan: `docs/plans/2026-11-05-121a-watch-hold-stuck-after-phone-log-plan/`
// Decision mapping:
//   D-1  a snapshot names only the delivered timers the phone still runs,
//        read from the bound state at compose time   → S-12101..S-12105b, S-12112
//   D-2  omission, never an explicit null            → S-12101, S-12106 (later run)
//   D-3  the value stays the delivered JSON          → S-12104
//   D-4  reconcile: clear a wrist clock the phone has already logged
//                                                     → S-12107, S-12108
//   D-5  remember a reconcile clear                  → S-12107, S-12108d
//   D-6  no wire, transport, Swift or Dart-engine change (no scenario of its own)
//   D-7  the ledger stays memory-only                → S-12107, S-12113
//   D-8  what "immediately" means                    → S-12102, S-12105
//   D-9  the Phase 0 gate (this file's red/green table is its evidence)
//   D-10 boundary with 121b (one interval per hold slot in every fixture here)
//   D-11 the delivered-timers accessor is deleted (Phase 1 residue sweep)
// Scenario mapping (the scenarios this run writes):
//   S-12101 the queued snapshot after the log names no hold, and applying it
//           stops the wrist hold                      → `S-12101 ...`
//   S-12102 the live clear, the late queued snapshot and the next snapshot
//           never bring the hold back                 → `S-12102 ...`
//   S-12103a a reinstalled watch applies the queued snapshot and never runs
//           the logged hold                           → `S-12103a ...`
//   S-12103b a reinstalled watch that asks for a snapshot gets one without
//           the logged hold                           → `S-12103b ...`
//   S-12104 the snapshot after the log carries exactly the elapsed the phone
//           still runs                                → `S-12104 ...`
//   S-12105 the rest opened after the log is owed, and the snapshot names
//           neither hold nor rest                     → `S-12105 ...`
//   S-12105b a delivered rest the phone closed while out of reach is not
//           named by the projection                   → `S-12105b ...`
//   S-12112 the projection reads the state, not the ledger → `S-12112 ...`
//   S-12106 a wrist-started hold the phone logged is stopped by the 43c
//           clear, never by a snapshot's omission      → `S-12106 ...`
//   S-12107 after a phone restart the wrist's running hold is cleared once
//           and only once                              → `S-12107 ...`
//   S-12108 a..g the reconcile's guards                → `S-12108a ...` etc.
//   S-12109 the end of the session is unchanged        → `S-12109 ...`
//   S-12110 H2 probe: the log while reachable stays stopped → `S-12110 ...`
//   S-12111 H2 probe: the wrist's revived copy is not adopted → `S-12111 ...`
//   S-12113 record: which frame stops the hold after a restart → `S-12113 ...`
//   S-12114 a second interval on the slot takes the hold off the snapshot
//                                                      → `S-12114 ...`
//   S-12115 a hold the wrist itself ended is not named → `S-12115 ...`
//
// The harness shape is copied from `test/watch_timer_push_test.dart`: the
// shipping graph `createWatchSync` over a fake radio plus the real Dart engine
// `WatchSessionEngine` over an in-memory store, so a phone frame is applied the
// way the watch app applies one. Plain `test()` only: no `testWidgets`, no
// FakeAsync. The phone's own timer manager stamps an interval with
// `DateTime.now()` (its clock is not injectable from `WorkoutState`), so the
// assertions compare a frame with the stored instance it came from rather than
// with the pinned graph clock.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which is
// the only way they reach a repository: the projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 11, 5, 9);

/// The session both devices know.
const String _sessionId = 's-w-121a';

/// The hold slot (a drill effort) and the timed slot after it.
const String _plankSlotId = 'sx-plank';

/// The second drill slot on the same exercise (S-12108f).
const String _plankSlot2Id = 'sx-plank2';
const String _runSlotId = 'sx-run';

/// A rest start unlike any default: the instant the phone logged the set.
final DateTime _restStart = DateTime.utc(2026, 3, 4, 5, 6, 7);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// Polls [condition] to a deadline (never a wall-clock threshold on the work).
Future<void> _waitFor(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// The two catalog entries the fixture's slots name.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-plank',
    name: 'Plank',
    capabilities: ['hold', 'time'],
  );
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Run',
    capabilities: ['time', 'distance'],
  );
}

/// The hold slot as the protocol spells it: a drill exercise.
Map<String, Object?> _slotPlank() => <String, Object?>{
  'sessionExerciseId': _plankSlotId,
  'exerciseId': 'ex-plank',
  'name': 'Plank',
  'effortKind': 'drill',
  'capabilities': ['hold', 'time'],
};

/// The timed slot that follows it in the ladder.
Map<String, Object?> _slotRun() => <String, Object?>{
  'sessionExerciseId': _runSlotId,
  'exerciseId': 'ex-run',
  'name': 'Run',
  'effortKind': 'timed',
  'capabilities': ['time', 'distance'],
};

/// The second drill slot on the same exercise (S-12108f): the phone runs its
/// hold while the mirror still holds the logged one for [_plankSlotId].
Map<String, Object?> _slotPlank2() => <String, Object?>{
  'sessionExerciseId': _plankSlot2Id,
  'exerciseId': 'ex-plank',
  'name': 'Plank 2',
  'effortKind': 'drill',
  'capabilities': ['hold', 'time'],
};

var _wristMessageCount = 0;

/// One `timer_state` frame as the wrist sends it. The scenarios of Phase 0b
/// (S-12106..S-12115) hand wrist frames to the phone with it.
Map<String, Object?> _wristTimerFrame(Map<String, Object?> timers) => {
  'protocolVersion': 1,
  'messageId': 'msg-wrist-timers-${_wristMessageCount++}',
  'sessionId': _sessionId,
  'type': 'timer_state',
  'origin': 'watch',
  'sentAt': utcIso(_now),
  'payload': {'timers': timers},
};

/// A hold timer as the wrist reports it.
Map<String, Object?> _wristHold({
  required DateTime startedAt,
  String state = 'running',
  String slot = _plankSlotId,
}) => {
  'kind': 'hold',
  'state': state,
  'startedAt': utcIso(startedAt),
  'accumulatedPauseMs': 0,
  'sessionExerciseId': slot,
};

/// Whether [envelope] is a `timer_state` that clears the rest and nothing
/// else.
bool _isRestClear(Map<String, Object?> envelope) {
  if (envelope['type'] != 'timer_state') return false;
  final timers = _payload(envelope)['timers'];
  if (timers is! Map) return false;
  final map = _asObject(timers);
  return map.length == 1 && map.containsKey('rest') && map['rest'] == null;
}

/// Whether [envelope] is a `timer_state` that clears the hold and nothing else.
bool _isHoldClear(Map<String, Object?> envelope) {
  if (envelope['type'] != 'timer_state') return false;
  final timers = _payload(envelope)['timers'];
  if (timers is! Map) return false;
  final map = _asObject(timers);
  return map.length == 1 && map.containsKey('hold') && map['hold'] == null;
}

/// Whether [envelope] is a `timer_state` that carries a rest.
bool _carriesRest(Map<String, Object?> envelope) {
  if (envelope['type'] != 'timer_state') return false;
  final timers = _payload(envelope)['timers'];
  return timers is Map && _asObject(timers)['rest'] != null;
}

/// The `timers` keys of a composed session message (the projection's shape).
List<String> _projectedTimerKeys(Map<String, Object?> projected) {
  final timers = projected['timers'];
  return timers is Map ? _asObject(timers).keys.toList() : <String>[];
}

/// The `timers` keys of a wire envelope (`payload.timers`).
List<String> _envelopeTimerKeys(Map<String, Object?> envelope) {
  final timers = _payload(envelope)['timers'];
  return timers is Map ? _asObject(timers).keys.toList() : <String>[];
}

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it
/// cannot carry the way the platform channel does — never by throwing (D-83).
///
/// Plan 121a's fixture radio: while the wrist is out of reach the durable
/// frames the phone owes for good go to the OS queue (`queued`), the way
/// `WatchConnectivityTransport` queues them, and `deliverQueued()` is the OS
/// carrying them when the devices meet.
class _QueueingPhoneRadio implements WatchTransport, WatchLinkSource {
  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed.
  final List<Map<String, Object?>> attempted = [];

  /// The frames the OS is carrying: delivered when the devices meet.
  final List<Map<String, Object?>> queued = [];

  /// True while the wrist is out of range.
  bool unreachable = false;

  WatchInboundHandler? _handler;

  final StreamController<WatchLinkInfo> _linkChanges =
      StreamController<WatchLinkInfo>.broadcast();

  WatchLinkInfo _info = const WatchLinkInfo(
    paired: true,
    appInstalled: true,
    reachable: false,
  );

  /// One link change, the way the platform reports the watch coming into or
  /// going out of reach.
  void emitLink({required bool reachable}) {
    _info = WatchLinkInfo(
      paired: true,
      appInstalled: true,
      reachable: reachable,
    );
    _linkChanges.add(_info);
  }

  Future<void> closeLink() => _linkChanges.close();

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    attempted.add(envelope);
    if (!unreachable) {
      sent.add(envelope);
      return WatchDelivery.delivered;
    }
    if (WatchConnectivityTransport.isDurable(envelope)) {
      final type = envelope['type'] as String;
      // A newer copy replaces the waiting one (D-3 of plan 67a); a receipt and
      // an `exercise_push` are never withdrawn.
      if (const {
        'session_snapshot',
        'session_lifecycle',
        'structure_change',
      }.contains(type)) {
        queued.removeWhere((frame) => frame['type'] == type);
      }
      queued.add(envelope);
      return WatchDelivery.queued;
    }
    return WatchDelivery.undelivered;
  }

  /// The OS carrying the queued frames to the wrist: returns them and empties
  /// the queue.
  List<Map<String, Object?>> deliverQueued() {
    final carried = [...queued];
    queued.clear();
    return carried;
  }

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];

  @override
  Future<WatchLinkInfo> linkInfo() async => _info;

  @override
  Stream<WatchLinkInfo> get linkChanges => _linkChanges.stream;

  @override
  Stream<DateTime> get heard => const Stream.empty();
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _QueueingPhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Map<String, Object?>> wristFrames;
  late List<Object> failures;

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption, the auto push, the timer push and the
  /// timer adoption in `lib/main.dart`; the fixture binds the last three once
  /// it has settled.
  Future<WatchSyncGraph> startGraph() async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
    ))!;
    created.adoption.bindWorkoutState(phoneState);
    return created;
  }

  /// Fixture F-A: the wrist starts [_sessionId] with a drill slot and a timed
  /// slot, and the phone adopts it. The phone runs exactly one not-started
  /// interval on the hold slot — the owner's one set.
  Future<void> wristStartsHoldSession() async {
    await _seedCatalog(repository);
    await engine.createSession(
      modality: null,
      exercises: [_slotPlank(), _slotRun()],
    );
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    final efforts = [
      for (final segment in phoneState.segments)
        ...phoneState.getEffortsForSegment(segment.id),
    ];
    final plank = efforts.singleWhere((effort) => effort.id == _plankSlotId);
    expect(
      plank.effortKind,
      'drill',
      reason: 'the fixture: the hold slot logs as a drill effort',
    );
    final instances = phoneState.getTimedInstancesForEffort(_plankSlotId);
    expect(
      instances,
      hasLength(1),
      reason: 'the fixture: exactly one interval on the hold slot (D-10)',
    );
    expect(
      instances.single.state,
      TimedState.notStarted,
      reason: "the fixture: the owner's one set has not started",
    );

    // The app binds all three to the same state (`lib/main.dart`).
    graph.timerAdoption.bindWorkoutState(phoneState);
    graph.timerPush.bindWorkoutState(phoneState);
    graph.autoPush.bindWorkoutState(phoneState);
  }

  /// H-start: the phone starts the hold slot's interval, the push delivers it,
  /// the wrist engine runs it. Returns the interval's start S_H.
  Future<int> holdStart() async {
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final startMs =
        phoneState.getTimedInstancesForEffort(_plankSlotId).single.startedAtMs;
    await graph.timerPush.flush();
    for (final frame in radio.ofType('timer_state')) {
      await engine.applyMessage(frame);
    }
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(
      hold,
      isNotNull,
      reason: 'the fixture: the wrist runs the hold the phone started',
    );
    expect(hold!.state, WatchTimerState.running);
    expect(
      hold.sessionExerciseId,
      _plankSlotId,
      reason: 'the fixture: the hold belongs to the plank slot',
    );
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      startMs,
      reason: 'the fixture: the wrist counts from the phone start S_H',
    );
    return startMs;
  }

  /// A real pause before a log: the finish stamps `finishedAtMs` from the real
  /// clock, and a finish in the same millisecond as the start is a window of no
  /// length, which the wire does not carry (D-132). A real hold always runs
  /// longer than its start instant.
  Future<void> letHoldRun() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// H-log-away: the wrist goes out of reach, the phone logs the hold, and the
  /// flushes run. The live clear cannot travel; the durable snapshot queues.
  Future<void> holdLogAway() async {
    radio.unreachable = true;
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final clears = radio.attempted.where(_isHoldClear).toList();
    expect(
      clears,
      hasLength(1),
      reason: 'H-log-away: exactly one {hold: null} was attempted',
    );
    expect(
      radio.sent.contains(clears.single),
      isFalse,
      reason: 'H-log-away: the live clear did not travel (timer_state is '
          'live-only)',
    );
    expect(
      failures,
      isEmpty,
      reason: 'H-log-away: no push pass reported a failure',
    );
    expect(
      radio.queued.where((frame) => frame['type'] == 'session_snapshot'),
      hasLength(1),
      reason: 'H-log-away: exactly one snapshot waits in the OS queue',
    );
  }

  /// Every timer frame the phone sent, in order.
  List<Map<String, Object?>> timerFrames() => radio.ofType('timer_state');

  /// The `timers` object of [envelope].
  Map<String, Object?> timersOf(Map<String, Object?> envelope) =>
      _asObject(_payload(envelope)['timers']);

  /// The phone opens a rest on [effortId]'s entry [entryIndex] the way the
  /// session screen does, then pins its stamps to [_restStart] so no scenario
  /// reads the wall clock.
  Future<EntryRest> openPhoneRest({
    String? effortId,
    int entryIndex = 0,
    DateTime? startedAt,
    bool paused = false,
    DateTime? pausedAt,
    int accumulatedPauseMs = 0,
  }) async {
    final effort = effortId ?? _plankSlotId;
    final start = startedAt ?? _restStart;
    await phoneState.recordRestStart(effort, entryIndex);

    final stored = (await repository.getEntryRests(effort)).firstWhere(
      (rest) => rest.entryIndex == entryIndex,
    );
    final pinned = stored.copyWith(
      restStartMs: start.millisecondsSinceEpoch,
      restIsPaused: paused,
      restPausedAtMs: paused
          ? (pausedAt ?? start).millisecondsSinceEpoch
          : null,
      restPausedDurationMs: accumulatedPauseMs,
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    );
    await repository.updateEntryRest(pinned);
    await phoneState.refreshEfforts([effort]);
    return pinned;
  }

  /// The queued `session_snapshot` frames, in order.
  List<Map<String, Object?>> queuedSnapshots() => [
    for (final frame in radio.queued)
      if (frame['type'] == 'session_snapshot') frame,
  ];

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _QueueingPhoneRadio();
    graph = await startGraph();

    wristFrames = [];
    wristStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: wristFrames.add,
    );
  });

  tearDown(() {
    graph.timerPush.dispose();
    graph.autoPush.dispose();
    graph.timerAdoption.dispose();
  });

  test('S-12101 the queued snapshot after the log names no hold, and applying '
      'it stops the wrist hold', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();
    await holdLogAway();

    // (a) the projection every snapshot the phone composes goes through.
    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    expect(
      _projectedTimerKeys(projected!),
      isNot(contains('hold')),
      reason: 'D-1 (a): the projection names no hold the phone no longer runs',
    );

    // (b) the snapshot the OS is carrying.
    final snapshots = queuedSnapshots();
    expect(snapshots, hasLength(1), reason: 'the fixture: one queued snapshot');
    expect(
      _envelopeTimerKeys(snapshots.single),
      isNot(contains('hold')),
      reason: 'D-1 (b): the durable snapshot names no hold',
    );

    // (c) the wrist applies the snapshot the way the watch app would.
    await engine.applyMessage(snapshots.single);
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'the hold row the phone wrote is kept');
    expect(
      hold!.state,
      WatchTimerState.stopped,
      reason: 'D-1 (c): the snapshot stops the hold the phone wrote (D-2)',
    );
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the stopped row is still the interval the phone started',
    );
  });

  test('S-12102 the live clear, the late queued snapshot and the next '
      'snapshot never bring the hold back', () async {
    await wristStartsHoldSession();
    await holdStart();
    final preLogSent = radio.sent.length;
    await holdLogAway();

    // The wrist comes back into reach before the OS queue is drained: the
    // re-offered live clear travels first (43c D-3, plan 98 D-3).
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _waitFor(
      () => radio.sent.any(_isHoldClear),
      'the re-offered {hold: null} clear',
    );
    await engine.applyMessage(radio.sent.where(_isHoldClear).last);
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the live clear stops the hold',
    );

    // THEN the OS delivers the snapshot it carried all along.
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the late durable snapshot does not revive the logged hold',
    );

    // A phone change (the next interval starts) and the snapshot after it.
    await phoneState.startTimedEntry(_runSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();
    final snapshots = radio.ofType('session_snapshot');
    expect(snapshots, isNotEmpty, reason: 'the fixture: a snapshot followed');
    await engine.applyMessage(snapshots.last);
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(
      hold == null || hold.state == WatchTimerState.stopped,
      isTrue,
      reason: 'no snapshot after the log brings the hold back',
    );

    // No frame the phone sent after the log names the hold running from S_H.
    for (final frame in radio.sent.skip(preLogSent)) {
      if (frame['type'] != 'timer_state' &&
          frame['type'] != 'session_snapshot') {
        continue;
      }
      final timers = _payload(frame)['timers'];
      if (timers is! Map) continue;
      final holdJson = _asObject(timers)['hold'];
      if (holdJson is! Map) continue;
      expect(
        _asObject(holdJson)['state'],
        isNot(WatchTimerState.running),
        reason: 'no frame sent after the log names a running hold',
      );
    }
  });

  test('S-12103a a reinstalled watch applies the queued snapshot and never '
      'runs the logged hold', () async {
    await wristStartsHoldSession();
    await holdStart();
    await holdLogAway();

    // The watch app was reinstalled: an empty store, a fresh engine.
    final reinstallFrames = <Map<String, Object?>>[];
    final reinstall = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: reinstallFrames.add,
    );
    for (final frame in radio.deliverQueued()) {
      await reinstall.applyMessage(frame);
    }
    expect(
      reinstall.session?.sessionId,
      _sessionId,
      reason: 'the reinstall adopted the session the OS carried',
    );
    final hold = reinstall.timerFor(WatchTimerKind.hold);
    expect(
      hold == null || hold.state == WatchTimerState.stopped,
      isTrue,
      reason: 'the reinstalled watch never runs the logged hold (AC-2)',
    );
  });

  test('S-12103b a reinstalled watch that asks for a snapshot gets one '
      'without the logged hold', () async {
    await wristStartsHoldSession();
    await holdStart();
    await holdLogAway();

    final reinstall = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: (_) {},
    );
    radio.unreachable = false;
    final sentBefore = radio.sent.length;
    await radio.fromWrist(WatchTransportRequest.snapshotFrame());
    await _settle();
    final answers = [
      for (final frame in radio.sent.skip(sentBefore))
        if (frame['type'] == 'session_snapshot') frame,
    ];
    expect(
      answers,
      isNotEmpty,
      reason: 'the fixture: the phone answered the snapshot request',
    );
    await reinstall.applyMessage(answers.first);
    expect(
      reinstall.session?.sessionId,
      _sessionId,
      reason: 'the reinstall adopted the session the phone answered with',
    );
    final hold = reinstall.timerFor(WatchTimerKind.hold);
    expect(
      hold == null || hold.state == WatchTimerState.stopped,
      isTrue,
      reason: 'the answer names no hold the phone no longer runs (AC-2)',
    );
  });

  test('S-12104 the snapshot after the log carries exactly the elapsed the '
      'phone still runs', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // The next interval starts while the wrist is in reach: elapsed delivers.
    await phoneState.startTimedEntry(_runSlotId, 0);
    final sR =
        phoneState.getTimedInstancesForEffort(_runSlotId).single.startedAtMs;
    await graph.timerPush.flush();
    for (final frame in timerFrames()) {
      await engine.applyMessage(frame);
    }
    final deliveredElapsed = timersOf(timerFrames().last)['elapsed'];
    expect(
      deliveredElapsed,
      isNotNull,
      reason: 'the fixture: the elapsed start was delivered',
    );

    await holdLogAway();

    final snapshots = queuedSnapshots();
    expect(snapshots, hasLength(1), reason: 'the fixture: one queued snapshot');
    expect(
      timersOf(snapshots.single),
      equals({'elapsed': deliveredElapsed}),
      reason: 'D-1/D-3: the snapshot carries exactly the delivered elapsed, '
          'and nothing the phone no longer runs',
    );
    await engine.applyMessage(snapshots.single);
    final elapsed = engine.timerFor(WatchTimerKind.elapsed);
    expect(elapsed, isNotNull);
    expect(elapsed!.state, WatchTimerState.running);
    expect(
      elapsed.startedAt.millisecondsSinceEpoch,
      sR,
      reason: 'the elapsed the phone still runs keeps counting',
    );
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull);
    expect(hold!.state, WatchTimerState.stopped);
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the logged hold stays stopped',
    );
  });

  test('S-12105 the rest opened after the log is owed, and the snapshot names '
      'neither hold nor rest', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // H-log-away, but the session screen opens the rest after the log, before
    // the flushes run.
    radio.unreachable = true;
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await phoneState.recordRestStart(_plankSlotId, 0);
    final restStartMs = phoneState.inProgressRest()!.startedAtMs;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final clears = radio.attempted.where(_isHoldClear).toList();
    expect(
      clears,
      hasLength(1),
      reason: 'H-log-away: exactly one {hold: null} was attempted',
    );
    expect(
      radio.sent.contains(clears.single),
      isFalse,
      reason: 'H-log-away: the live clear did not travel',
    );
    expect(
      queuedSnapshots(),
      hasLength(1),
      reason: 'H-log-away: exactly one snapshot waits in the OS queue',
    );

    final snapshot = queuedSnapshots().single;
    final keys = _envelopeTimerKeys(snapshot);
    expect(
      keys,
      isNot(contains('hold')),
      reason: 'D-1: the snapshot names no hold the phone logged',
    );
    expect(
      keys,
      contains('rest'),
      reason: 'plan 127 D-2: the rest the radio refused is owed, so it rides '
          'the snapshot (it replaces 121a\'s "owed kinds are never named")',
    );
    await engine.applyMessage(snapshot);
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull);
    expect(
      hold!.state,
      WatchTimerState.stopped,
      reason: 'the snapshot stops the logged hold',
    );
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the stopped row is still the interval the phone started',
    );

    // The wrist comes back into reach: the owed rest is sent (plan 98 D-2).
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _waitFor(
      () => timerFrames().any(_carriesRest),
      'the owed rest frame',
    );
    await engine.applyMessage(timerFrames().where(_carriesRest).last);
    final rest = engine.timerFor(WatchTimerKind.rest);
    expect(rest, isNotNull, reason: 'the wrist runs the phone rest');
    expect(rest!.state, WatchTimerState.running);
    expect(
      rest.startedAt.millisecondsSinceEpoch,
      restStartMs,
      reason: 'the wrist rests from the phone rest start',
    );
  });

  test('S-12105b a delivered rest the phone closed while out of reach is not '
      'named by the projection', () async {
    await wristStartsHoldSession();

    // While reachable the phone opens a rest on the run slot and delivers it.
    await openPhoneRest(effortId: _runSlotId, entryIndex: 0);
    await graph.timerPush.flush();
    expect(
      timerFrames().where(_carriesRest),
      hasLength(1),
      reason: 'the fixture: the rest was delivered',
    );

    // Out of reach, the phone starts the hold: 98 D-1 closes every open rest.
    radio.unreachable = true;
    await phoneState.startTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await _settle();

    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    final keys = _projectedTimerKeys(projected!);
    expect(
      keys,
      isNot(contains('rest')),
      reason: 'D-1 (ii): the phone no longer runs the rest it delivered',
    );
    expect(
      keys,
      contains('hold'),
      reason: 'plan 127 D-2: the hold the radio refused is owed, so it rides '
          'the snapshot (it replaces 121a\'s "owed kinds are never named")',
    );
  });

  test('S-12112 the projection reads the state, not the ledger: no hold '
      'before the flush', () async {
    await wristStartsHoldSession();
    await holdStart();

    // Still reachable: the log lands, but the timer push has not flushed yet —
    // the auto push may win the race and compose a snapshot first.
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    expect(
      _projectedTimerKeys(projected!),
      isNot(contains('hold')),
      reason: 'D-1: the projection reads the phone state at compose time, not '
          'the delivered ledger',
    );
  });

  /// The mirror's copy of one wire timer, as the last wrist frame folded it.
  Map<String, Object?>? mirrorTimer(String kind) {
    final timers = _asObject(graph.mirror.state)['timers'];
    if (timers is! Map) return null;
    final held = _asObject(timers)[kind];
    return held is Map ? _asObject(held) : null;
  }

  /// The wrist starts the hold on [slotId] and the phone adopts it (the
  /// `adoptedInterval` pattern of `test/watch_timer_push_test.dart`): the
  /// slot's interval 0 goes active at the wrist's own start W, and nothing is
  /// echoed. Returns W in ms.
  Future<int> wristStartsHoldAdopted({String? slotId}) async {
    final slot = slotId ?? _plankSlotId;
    final started = await engine.startTimer(
      WatchTimerKind.hold,
      sessionExerciseId: slot,
    );
    await radio.fromWrist(wristFrames.last);
    await _settle();
    final w = started.startedAt.millisecondsSinceEpoch;
    final adopted = phoneState.getTimedInstancesForEffort(slot).single;
    expect(
      adopted.state,
      TimedState.active,
      reason: 'the fixture: the phone adopted the wrist hold (43b2)',
    );
    expect(
      adopted.startedAtMs,
      w,
      reason: "the fixture: the phone runs the wrist's own start",
    );
    await graph.timerPush.flush();
    expect(
      timerFrames(),
      isEmpty,
      reason: 'the fixture: the adopted timer is not echoed to the wrist',
    );
    return w;
  }

  /// S-12106's log away: out of reach, the phone logs the adopted hold, the
  /// durable snapshot queues, and the wrist's own row survives the snapshot
  /// (S-1310) — the guard the reconcile of D-4 builds on.
  Future<void> logAdoptedHoldAway() async {
    radio.unreachable = true;
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();
    final snapshots = queuedSnapshots();
    expect(
      snapshots,
      hasLength(1),
      reason: 'the fixture: one snapshot waits in the OS queue',
    );
    expect(
      _envelopeTimerKeys(snapshots.single),
      isNot(contains('hold')),
      reason: 'the fixture: the snapshot names no hold (D-1/D-2)',
    );
    await engine.applyMessage(snapshots.single);
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'the wrist-started row is kept');
    expect(
      hold!.state,
      WatchTimerState.running,
      reason: 'the fixture: a wrist-started row survives an omission (S-1310)',
    );
  }

  /// The phone restart of S-12107: the first graph's pushes are disposed and a
  /// second `createWatchSync` graph is built over the same repository, state
  /// and radio, with everything bound to [phoneState]. The adoption bridge has
  /// no `dispose`; the graph it belongs to simply stops being driven.
  Future<void> restartPhoneGraph() async {
    graph.timerPush.dispose();
    graph.autoPush.dispose();
    graph.timerAdoption.dispose();
    graph = await startGraph();
    graph.timerAdoption.bindWorkoutState(phoneState);
    graph.timerPush.bindWorkoutState(phoneState);
    graph.autoPush.bindWorkoutState(phoneState);
    radio.unreachable = false;
  }

  /// The shared fixture of S-12108 a..g: S-12106 up to before `emitLink`, then
  /// the phone restart of S-12107, with the wrist back in reach. [logAway]
  /// false keeps the phone's interval 0 active (S-12108b); [secondPlankSlot]
  /// adds the `sx-plank2` drill slot to the wrist session (S-12108f). Returns
  /// the wrist hold start W in ms.
  Future<int> restartedHoldFixture({
    bool logAway = true,
    bool secondPlankSlot = false,
  }) async {
    await _seedCatalog(repository);
    await engine.createSession(
      modality: null,
      exercises: [
        _slotPlank(),
        if (secondPlankSlot) _slotPlank2(),
        _slotRun(),
      ],
    );
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();
    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: 'the fixture: the phone runs the wrist session',
    );
    graph.timerAdoption.bindWorkoutState(phoneState);
    graph.timerPush.bindWorkoutState(phoneState);
    graph.autoPush.bindWorkoutState(phoneState);
    final w = await wristStartsHoldAdopted();
    if (logAway) await logAdoptedHoldAway();
    await restartPhoneGraph();
    // The restarted mirror knows no session until the wrist speaks: join it
    // with a snapshot that reports no timers, so a later wrist `timer_state`
    // is folded into the mirror (harness fix, 121a P0b).
    final joinSnapshot = engine.sessionSnapshot()!;
    await radio.fromWrist({
      ...joinSnapshot,
      'payload': {..._payload(joinSnapshot), 'timers': <String, Object?>{}},
    });
    await _settle();
    expect(
      graph.mirror.sessionId,
      _sessionId,
      reason: 'the fixture: the restarted mirror joined the wrist session',
    );
    return w;
  }

  test('S-12106 a wrist-started hold the phone logged is stopped by the 43c '
      'clear, never by a snapshot omission', () async {
    await wristStartsHoldSession();
    await wristStartsHoldAdopted();
    await logAdoptedHoldAway();

    // The wrist comes back into reach: the 43c clear travels (D-3 of 43c).
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _waitFor(
      () => radio.sent.any(_isHoldClear),
      'the 43c {hold: null} clear',
    );
    await engine.applyMessage(radio.sent.where(_isHoldClear).last);
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the 43c clear stops the wrist hold once the phone logged it',
    );
  });

  test('S-12107 after a phone restart the wrist running hold is cleared once '
      'and only once', () async {
    await wristStartsHoldSession();
    final w = await wristStartsHoldAdopted();
    await logAdoptedHoldAway();
    await restartPhoneGraph();

    final attemptedAtStart = radio.attempted.length;
    final wristSnapshot = engine.sessionSnapshot()!;
    await radio.fromWrist(wristSnapshot);
    await _settle();

    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist snapshot');
    expect(
      mirrorHold!['state'],
      'running',
      reason: 'the fixture: the wrist reports the hold running',
    );
    expect(
      mirrorHold['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w, isUtc: true)),
      reason: 'the fixture: the copy starts at W',
    );

    final clears = radio.attempted
        .skip(attemptedAtStart)
        .where(_isHoldClear)
        .toList();
    expect(
      clears,
      hasLength(1),
      reason: 'D-4: the restarted phone clears the hold it has already logged',
    );
    expect(
      radio.sent.contains(clears.single),
      isTrue,
      reason: 'the clear was attempted and sent (the wrist is in reach)',
    );
    await engine.applyMessage(clears.single);
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the clear stops the wrist hold',
    );

    // The same wrist frame repeats: D-5 remembers the clear.
    final attemptedBeforeRepeat = radio.attempted.length;
    await radio.fromWrist(wristSnapshot);
    await _settle();
    expect(
      radio.attempted.skip(attemptedBeforeRepeat).where(_isHoldClear),
      isEmpty,
      reason: 'D-5: no second clear for the same stale copy',
    );
  });

  test('S-12108a the reconcile ignores a mirror hold that started later '
      '(W+5000 ms)', () async {
    final w = await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    // The wrist began a NEW hold five seconds after the logged one.
    await radio.fromWrist(
      _wristTimerFrame({
        'hold': _wristHold(
          startedAt: DateTime.fromMillisecondsSinceEpoch(w + 5000, isUtc: true),
        ),
      }),
    );
    await _settle();

    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist frame');
    expect(
      mirrorHold!['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w + 5000, isUtc: true)),
      reason: 'the fixture: the mirror hold starts at W+5000 ms',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      isEmpty,
      reason: 'D-4 (v): the start does not match the logged interval, so no '
          'clear',
    );
  });

  test('S-12108b the reconcile clears nothing while the phone still runs the '
      'hold', () async {
    final w = await restartedHoldFixture(logAway: false);
    final attemptedAtStart = radio.attempted.length;

    final interval0 = phoneState.getTimedInstancesForEffort(_plankSlotId).single;
    expect(
      interval0.state,
      TimedState.active,
      reason: 'the fixture: interval 0 is still active (not logged)',
    );
    expect(interval0.startedAtMs, w, reason: 'the fixture: it runs from W');

    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      isEmpty,
      reason: 'D-4 (iii): the phone still wants the hold, so no clear',
    );
  });

  test('S-12108c the reconcile clears nothing for a mirror copy that is '
      'already stopped', () async {
    final w = await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    final frame = _wristTimerFrame({
      'hold': _wristHold(
        startedAt: DateTime.fromMillisecondsSinceEpoch(w, isUtc: true),
        state: 'stopped',
      ),
    });
    await radio.fromWrist(frame);
    await _settle();
    await engine.applyMessage(frame);

    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist frame');
    expect(
      mirrorHold!['state'],
      'stopped',
      reason: 'the fixture: the mirror holds the copy as stopped',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      isEmpty,
      reason: 'D-4 (ii): a stopped copy is not cleared',
    );
  });

  test('S-12108d after one delivered reconcile clear the repeated wrist frame '
      'sends no second clear', () async {
    final w = await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    final wristSnapshot = engine.sessionSnapshot()!;
    await radio.fromWrist(wristSnapshot);
    await _settle();
    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist snapshot');
    expect(
      mirrorHold!['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w, isUtc: true)),
      reason: 'the fixture: the copy is the logged hold, from W',
    );

    final clears = radio.attempted
        .skip(attemptedAtStart)
        .where(_isHoldClear)
        .toList();
    expect(
      clears,
      hasLength(1),
      reason: 'D-4: one reconcile clear for the logged hold',
    );
    expect(
      radio.sent.contains(clears.single),
      isTrue,
      reason: 'the clear was delivered',
    );
    await engine.applyMessage(clears.single);
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the clear stopped the wrist hold',
    );

    // The wrist frame repeats identically: D-5 remembers the clear.
    final attemptedBeforeRepeat = radio.attempted.length;
    await radio.fromWrist(wristSnapshot);
    await _settle();
    expect(
      radio.attempted.skip(attemptedBeforeRepeat).where(_isHoldClear),
      isEmpty,
      reason: 'D-5: the repeated frame sends no second clear',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      hasLength(1),
      reason: 'exactly one {hold: null} in total',
    );
  });

  test('S-12108e the reconcile never clears a rest', () async {
    await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    await radio.fromWrist(
      _wristTimerFrame({
        'rest': {
          'kind': 'rest',
          'state': 'running',
          'startedAt': utcIso(_now),
          'accumulatedPauseMs': 0,
        },
      }),
    );
    await _settle();

    final mirrorRest = mirrorTimer('rest');
    expect(mirrorRest, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist frame');
    expect(
      mirrorRest!['state'],
      'running',
      reason: 'the fixture: the mirror holds a running rest',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isRestClear),
      isEmpty,
      reason: 'D-4: rest is never reconciled, and no phone rest is open',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      isEmpty,
      reason: 'no hold clear either: the mirror holds no hold copy here',
    );
  });

  test('S-12108f the reconcile clears nothing while the phone runs a hold on '
      'another drill slot', () async {
    final w = await restartedHoldFixture(secondPlankSlot: true);
    final attemptedAtStart = radio.attempted.length;

    // The phone runs a hold on the other drill slot and delivers it.
    await phoneState.startTimedEntry(_plankSlot2Id, 0);
    await graph.timerPush.flush();
    final delivered = timerFrames().where((frame) {
      final hold = _asObject(_payload(frame)['timers'])['hold'];
      return hold is Map &&
          _asObject(hold)['sessionExerciseId'] == _plankSlot2Id;
    }).toList();
    expect(
      delivered,
      isNotEmpty,
      reason: 'the fixture: the sx-plank2 hold was delivered',
    );

    // The wrist reports its own hold for sx-plank, from W.
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();
    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist snapshot');
    expect(
      mirrorHold!['sessionExerciseId'],
      _plankSlotId,
      reason: 'the fixture: the mirror holds the stale sx-plank copy',
    );
    expect(
      mirrorHold['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w, isUtc: true)),
      reason: 'the fixture: the stale copy starts at W',
    );
    expect(
      radio.attempted.skip(attemptedAtStart).where(_isHoldClear),
      isEmpty,
      reason: 'D-4 (iii): the phone still wants a hold (sx-plank2), so a clear '
          'would stop a timer the phone did not log',
    );
  });

  test('S-12108g the reconcile clears a mirror hold within the start '
      'tolerance, copy earlier than the logged start (W-400 ms)', () async {
    final w = await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    await radio.fromWrist(
      _wristTimerFrame({
        'hold': _wristHold(
          startedAt: DateTime.fromMillisecondsSinceEpoch(w - 400, isUtc: true),
        ),
      }),
    );
    await _settle();

    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist frame');
    expect(
      mirrorHold!['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w - 400, isUtc: true)),
      reason: 'the fixture: the mirror hold starts at W-400 ms',
    );
    expect(
      phoneState.getTimedInstancesForEffort(_plankSlotId),
      hasLength(1),
      reason: 'the fixture: the adoption ignored the copy (it matches the '
          'logged interval within 1000 ms)',
    );

    final clears = radio.attempted
        .skip(attemptedAtStart)
        .where(_isHoldClear)
        .toList();
    expect(
      clears,
      hasLength(1),
      reason: 'D-4 (v): the start is within the 1000 ms tolerance of the '
          'logged interval, so one clear',
    );
  });

  test('S-12108h the reconcile ignores a mirror hold that started LATER than the '
      'logged interval (W+400 ms), a newer wrist timer (S-6329)', () async {
    final w = await restartedHoldFixture();
    final attemptedAtStart = radio.attempted.length;

    await radio.fromWrist(
      _wristTimerFrame({
        'hold': _wristHold(
          startedAt: DateTime.fromMillisecondsSinceEpoch(w + 400, isUtc: true),
        ),
      }),
    );
    await _settle();

    final mirrorHold = mirrorTimer('hold');
    expect(mirrorHold, isNotNull, reason: 'the fixture: the mirror folded the '
        'wrist frame');
    expect(
      mirrorHold!['startedAt'],
      utcIso(DateTime.fromMillisecondsSinceEpoch(w + 400, isUtc: true)),
      reason: 'the fixture: the mirror hold starts at W+400 ms',
    );
    expect(
      phoneState.getTimedInstancesForEffort(_plankSlotId),
      hasLength(1),
      reason: 'the fixture: the adoption ignored the copy (it matches the '
          'logged interval within 1000 ms)',
    );

    final clears = radio.attempted
        .skip(attemptedAtStart)
        .where(_isHoldClear)
        .toList();
    expect(
      clears,
      isEmpty,
      reason: 'D-4 (v): a copy that started after the logged interval is a '
          'newer wrist timer, so no clear',
    );
  });

  test('S-12109 the end of the session is unchanged', () async {
    await wristStartsHoldSession();
    await holdStart();
    await holdLogAway();

    // Every snapshot composed between the log and the end names no hold.
    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    expect(
      _projectedTimerKeys(projected!),
      isNot(contains('hold')),
      reason: 'D-1: the projection names no hold the phone no longer runs',
    );
    for (final snapshot in queuedSnapshots()) {
      expect(
        _envelopeTimerKeys(snapshot),
        isNot(contains('hold')),
        reason: 'D-1: the queued snapshot names no hold',
      );
    }

    // The end: no timer_state is attempted any more, and the ledger is empty.
    final attemptedBeforeEnd = radio.attempted.length;
    await phoneState.endSession(writeToHealth: false);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();
    expect(
      radio.attempted
          .skip(attemptedBeforeEnd)
          .where((frame) => frame['type'] == 'timer_state'),
      isEmpty,
      reason: 'the end attempts no timer_state (the existing _pushOnce rule)',
    );
  });

  test('S-12110 H2 probe: the log while reachable stays stopped across the '
      'next snapshots', () async {
    await wristStartsHoldSession();
    await holdStart();

    // The log while REACHABLE: the clear travels and is applied.
    final framesBefore = timerFrames().length;
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    final newFrames = timerFrames().skip(framesBefore).toList();
    expect(
      newFrames.where(_isHoldClear),
      hasLength(1),
      reason: 'the fixture: the clear travelled while the wrist was in reach',
    );
    for (final frame in newFrames) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the clear stops the hold the moment the phone logs it',
    );

    // Two phone changes, two autoPush snapshots, each applied.
    for (final change in [
      () => phoneState.startTimedEntry(_runSlotId, 0),
      () => phoneState.finishTimedEntry(_runSlotId, 0),
    ]) {
      await letHoldRun();
      await change();
      await graph.autoPush.flush();
      await _settle();
      final snapshots = radio.ofType('session_snapshot');
      expect(snapshots, isNotEmpty, reason: 'the fixture: a snapshot followed');
      await engine.applyMessage(snapshots.last);
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.stopped,
        reason: 'the hold stays stopped across the snapshot',
      );
    }
  });

  test('S-12111 H2 probe: the wrist revived copy is not adopted and is not '
      'named by a later frame', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();
    await holdLogAway();
    // The wrist applies the queued snapshot; today that revives the hold
    // (S-12101c), which is exactly the copy this probe has the wrist report.
    await engine.applyMessage(queuedSnapshots().single);

    // The wrist (reachable) reports its revived copy.
    radio.unreachable = false;
    final attemptedBefore = radio.attempted.length;
    await radio.fromWrist(
      _wristTimerFrame({
        'hold': _wristHold(
          startedAt: DateTime.fromMillisecondsSinceEpoch(sH, isUtc: true),
        ),
      }),
    );
    await _settle();

    final instances = phoneState.getTimedInstancesForEffort(_plankSlotId);
    expect(
      instances,
      hasLength(1),
      reason: 'the adoption must not grow the slot (D-10)',
    );
    expect(
      instances.single.state,
      TimedState.finished,
      reason: 'the logged interval stays logged',
    );
    expect(
      phoneState.inProgressWorkTimers().where((t) => t.wireKind == 'hold'),
      isEmpty,
      reason: 'the phone does not run the hold again',
    );
    for (final frame in radio.attempted.skip(attemptedBefore)) {
      if (frame['type'] != 'timer_state') continue;
      final timers = _payload(frame)['timers'];
      if (timers is! Map) continue;
      final holdJson = _asObject(timers)['hold'];
      if (holdJson is! Map) continue;
      expect(
        _asObject(holdJson)['state'],
        isNot(WatchTimerState.running),
        reason: 'no timer_state sent after the wrist frame names a running '
            'hold',
      );
    }
  });

  test('S-12113 record: which frame stops the hold after a phone restart',
      () async {
    await wristStartsHoldSession();
    await holdStart();
    await holdLogAway();
    await restartPhoneGraph();

    final sentBefore = radio.sent.length;
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();
    // Every session-bearing frame the phone sent after the wrist snapshot,
    // applied in order. NOTE(record): today no D-4 clear is composed (the
    // ledger was lost with the first graph), so the frame that stops the hold,
    // if any, can only be a snapshot's omission — which cannot stop a row the
    // wrist wrote, so the hold is expected to survive until Phase 1.
    final frames = radio.sent.skip(sentBefore).where((frame) {
      return frame['type'] == 'session_snapshot' ||
          frame['type'] == 'timer_state';
    }).toList();
    for (final frame in frames) {
      await engine.applyMessage(frame);
    }
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'the wrist row is kept');
    expect(
      hold!.state,
      WatchTimerState.stopped,
      reason: 'AC-4: the hold stops once the wrist is in reach again',
    );
  });

  test('S-12114 a second interval on the slot takes the logged hold off the '
      'snapshot', () async {
    await wristStartsHoldSession();
    await phoneState.addTimedEntry(_plankSlotId);
    var instances = phoneState.getTimedInstancesForEffort(_plankSlotId);
    expect(instances, hasLength(2), reason: 'the fixture: two intervals');

    // H-start on interval 0.
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)[0]
        .startedAtMs;
    await graph.timerPush.flush();
    for (final frame in timerFrames()) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.running,
      reason: 'the fixture: the wrist runs the hold from S_H',
    );

    // Out of reach: interval 0 is logged, interval 1 starts (S_H2 > S_H).
    radio.unreachable = true;
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    // A real pause so S_H2 is a later millisecond than S_H.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phoneState.startTimedEntry(_plankSlotId, 1);
    instances = phoneState.getTimedInstancesForEffort(_plankSlotId);
    expect(instances[0].state, TimedState.finished, reason: 'the fixture: '
        'interval 0 is logged');
    final sH2 = instances[1].startedAtMs;
    expect(sH2 > sH, isTrue, reason: 'the fixture: S_H2 is later than S_H');
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final snapshots = queuedSnapshots();
    expect(snapshots, hasLength(1), reason: 'the fixture: one queued snapshot');
    expect(
      _envelopeTimerKeys(snapshots.single),
      isNot(contains('hold')),
      reason: 'D-1: the delivered S_H no longer matches and S_H2 was never '
          'delivered, so the snapshot names no hold',
    );
  });

  test('S-12115 a hold the wrist itself ended is not named by the projection',
      () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // The wrist ends its own hold while the phone still runs interval 0.
    await radio.fromWrist(
      _wristTimerFrame({
        'hold': _wristHold(
          startedAt: DateTime.fromMillisecondsSinceEpoch(sH, isUtc: true),
          state: 'stopped',
        ),
      }),
    );
    await _settle();

    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    expect(
      _projectedTimerKeys(projected!),
      isNot(contains('hold')),
      reason: 'D-1 (v): the mirror holds this very hold as stopped, so the '
          'snapshot must not name it',
    );
  });
}
