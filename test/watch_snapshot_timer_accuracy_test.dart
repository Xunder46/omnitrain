// A durable snapshot tells the watch what the phone's timers are doing now
// (plan 127 Phase 0a: red tests for the phone side — no production code).
//
// Plan: `docs/plans/2026-11-05-127-snapshot-timer-accuracy-plan/`
// Decision mapping:
//   D-1  a snapshot carries the phone's CURRENT timer, not the stored
//        delivered copy                                   → S-127-01..05, -22, -17
//   D-2  a refused start rides snapshots, with the replacement omission rule
//        for work kinds                                   → S-127-10, -14, -15, -17
//   D-3  54 D-1a still holds: a start the wrist ended is never named
//                                                         → S-127-12
//   D-4  owed live starts check the mirror at send time   → S-127-12, -13
//   D-5  a refused start asks for a snapshot (`onOwed`)   → S-127-11, -16
//   D-6  derived: a late start counts from its original start
//                                           (guard inside S-127-15)
//   D-7  no code: a wrist with no session gets the right timers from its first
//        snapshot                                         → S-127-20..22
//   D-8  the Dart twin drops an older snapshot            → S-127-34
//   D-9  the Phase 0 gate (this file's red/green table in the report)
//   D-10 no wire, transport or Swift change (no scenario of its own)
// Scenario mapping (the scenarios this run writes; S-127-30..33 belong to
// the other Phase 0 run, not here):
//   S-127-01 the paused hold rides the queued snapshot  → `S-127-01 ...`
//   S-127-02 a reinstalled watch applies it and is paused → `S-127-02 ...`
//   S-127-03 a resumed hold rides the queue as running  → `S-127-03 ...`
//   S-127-04 the refused pause going live later, and the older queued
//           snapshot, both leave the hold paused        → `S-127-04 ...`
//   S-127-05 a delivered pause names the exact delivered JSON
//                                                      → `S-127-05 ...`
//   S-127-10 a start the radio refused rides the first snapshot → `S-127-10 ...`
//   S-127-11 the flush race: the owed start triggers a new snapshot
//                                                      → `S-127-11 ...`
//   S-127-12 the wrist stopped the hold it did get: no restart
//                                                      → `S-127-12 ...`
//   S-127-13 the wrist paused its copy: the owed start is not sent
//                                                      → `S-127-13 ...`
//   S-127-14 the phone ends first: no snapshot names the hold and no live
//           start is attempted                         → `S-127-14 ...`
//   S-127-15 the snapshot and the late live start agree → `S-127-15 ...`
//   S-127-16 a reachable wrist gets no extra snapshots  → `S-127-16 ...`
//   S-127-17 a replacement interval is never named while the old one may
//           still be on the wrist                      → `S-127-17 ...`
//   S-127-20 probe: no session, start + log             → `S-127-20 ...`
//   S-127-21 probe: no session, start only              → `S-127-21 ...`
//   S-127-22 probe: no session, start + pause           → `S-127-22 ...`
//   S-127-34 end to end: the stale queued snapshot does not revive the hold
//                                                      → `S-127-34 ...`
//
// The harness shape is copied from `test/watch_logged_hold_stays_stopped_test.dart`
// (plan 121a Phase 0a): the shipping graph `createWatchSync` over a fake radio
// plus the real Dart engine `WatchSessionEngine` over an in-memory store, so a
// phone frame is applied the way the watch app applies one. Plain `test()`
// only: no `testWidgets`, no FakeAsync. The phone's own timer manager stamps
// an interval with `DateTime.now()` (its clock is not injectable from
// `WorkoutState`), so the assertions compare a frame with the stored instance
// it came from rather than with the pinned graph clock. Two extras on the
// radio: `lostAnswer` (a `timer_state` is recorded for the test to apply but
// answers `undelivered`) and `refuseNoSession` (an engine over an EMPTY store:
// `applyMessage` refuses session-scoped frames, the phone's answer is still
// delivered).

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
const String _sessionId = 's-w-127';

/// The hold slot (a drill effort) and the timed slot after it.
const String _plankSlotId = 'sx-plank';
const String _runSlotId = 'sx-run';

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// Settles several dispatch rounds, enough for every listener-triggered pass to
/// start; follow with [_waitFor] where a frame must arrive.
Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await _settle();
  }
}

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

/// An epoch instants as the protocol's UTC instant.
String _wireInstant(int epochMs) =>
    utcIso(DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true));

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it
/// cannot carry the way the platform channel does — never by throwing (D-83).
///
/// Plan 127's fixture radio (121a's, with two extras): while the wrist is out
/// of reach the durable frames the phone owes for good go to the OS queue
/// (`queued`), the way `WatchConnectivityTransport` queues them, and
/// `deliverQueued()` is the OS carrying them when the devices meet.
class _QueueingPhoneRadio implements WatchTransport, WatchLinkSource {
  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed.
  final List<Map<String, Object?>> attempted = [];

  /// The frames the OS is carrying: delivered when the devices meet.
  final List<Map<String, Object?>> queued = [];

  /// True while the wrist is out of range.
  bool unreachable = false;

  /// Extra 1: when true, a `timer_state` frame is not carried but the phone is
  /// FORCED to answer `undelivered` — the frame still exists (the wrist will
  /// apply it, the test does that itself from [lostFrames]).
  bool lostAnswer = false;

  /// The frames recorded by the `lostAnswer` extra; the test applies them.
  final List<Map<String, Object?>> lostFrames = [];

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
    if (lostAnswer && envelope['type'] == 'timer_state') {
      // The frame exists (the wrist applies it on its own), but the transport
      // told the phone nothing: it is refused for the phone's ledger.
      lostFrames.add(envelope);
      return WatchDelivery.undelivered;
    }
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

/// The `timers` object of a wire envelope (`payload.timers`), when there is one.
Map<String, Object?>? _timersOf(Map<String, Object?> envelope) {
  if (envelope['type'] != 'timer_state' &&
      envelope['type'] != 'session_snapshot') {
    return null;
  }
  final timers = _payload(envelope)['timers'];
  return timers is Map ? _asObject(timers) : null;
}

/// The `hold` JSON of [envelope], or null when it does not name a hold.
Map<String, Object?>? _holdOf(Map<String, Object?> envelope) {
  final timers = _timersOf(envelope);
  if (timers == null) return null;
  final hold = timers['hold'];
  return hold is Map ? _asObject(hold) : null;
}

/// Whether [envelope] names the hold running from [startedMs] on a slot.
bool _namesHoldRunningFrom(Map<String, Object?> envelope, int startedMs) {
  final hold = _holdOf(envelope);
  return hold != null &&
      hold['state'] == WatchTimerState.running &&
      hold['startedAt'] == _wireInstant(startedMs);
}

/// Whether [envelope] is a `timer_state` that clears the hold and nothing else.
bool _isHoldClear(Map<String, Object?> envelope) {
  if (envelope['type'] != 'timer_state') return false;
  final timers = _timersOf(envelope);
  if (timers == null) return false;
  return timers.length == 1 &&
      timers.containsKey('hold') &&
      timers['hold'] == null;
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
  /// interval per slot — the owner's one set.
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
    for (final slotId in [_plankSlotId, _runSlotId]) {
      final instances = phoneState.getTimedInstancesForEffort(slotId);
      expect(
        instances,
        hasLength(1),
        reason: 'the fixture: exactly one interval on $slotId',
      );
      expect(
        instances.single.state,
        TimedState.notStarted,
        reason: 'the fixture: the interval on $slotId has not started',
      );
    }

    // The app binds all three to the same state (`lib/main.dart`).
    graph.timerAdoption.bindWorkoutState(phoneState);
    graph.timerPush.bindWorkoutState(phoneState);
    graph.autoPush.bindWorkoutState(phoneState);
  }

  /// H-start: the phone starts the hold slot's interval, the push delivers it,
  /// the wrist engine runs it. Returns the interval's start S_H.
  Future<int> holdStart() async {
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final startMs = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;
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

  /// A real pause is never asserted as a wall-clock threshold: the phone's
  /// pause and resume stamps come out of `DateTime.now()`, so this only makes
  /// the next stamp a strictly later millisecond than the previous one.
  Future<void> letHoldRun() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// Every timer frame the phone sent, in order.
  List<Map<String, Object?>> timerFrames() => radio.ofType('timer_state');

  /// The queued `session_snapshot` frames, in order.
  List<Map<String, Object?>> queuedSnapshots() => [
    for (final frame in radio.queued)
      if (frame['type'] == 'session_snapshot') frame,
  ];

  /// The sent `session_snapshot` frames, in order.
  List<Map<String, Object?>> sentSnapshots() =>
      radio.ofType('session_snapshot');

  /// A wrist app that has just been installed: an empty store, no session. It
  /// refuses session-scoped frames until the snapshot (refuseNoSession) and
  /// answers nothing the phone could see: what the radio says is the phone's
  /// only accounting.
  WatchSessionEngine freshWristEngine(List<Object> outbox) =>
      WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
        sessionIdFactory: () => _sessionId,
        onEmit: outbox.add,
      );

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
    radio.closeLink();
  });

  test('S-127-01 the paused hold rides the queued snapshot with the phone '
      'state, not the old delivered copy (D-1)', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // H-away, then the phone pauses. The pause frame is refused (timer_state
    // is live-only), so the snapshot is the one frame the OS queues — and it
    // must carry what the phone is doing NOW: paused.
    radio.unreachable = true;
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    final paused = phoneState.getTimedInstancesForEffort(_plankSlotId).single;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final snapshots = queuedSnapshots();
    expect(
      snapshots,
      hasLength(1),
      reason:
          'D-1: the pause changes the payload, so a snapshot is composed '
          'and the OS queues it while the wrist is away',
    );
    final hold = _holdOf(snapshots.single)!;
    expect(
      hold['state'],
      WatchTimerState.paused,
      reason:
          'D-1: the snapshot carries the phone state now, not the '
          'delivered RUNNING copy',
    );
    expect(
      hold['startedAt'],
      _wireInstant(sH),
      reason: 'the snapshot carries the hold the phone started (S_H)',
    );
    expect(
      hold['pausedAt'],
      _wireInstant(paused.pausedAtMs!),
      reason: 'the snapshot carries the phone pause stamp',
    );
    expect(hold['accumulatedPauseMs'], 0);
    expect(
      hold['sessionExerciseId'],
      _plankSlotId,
      reason: 'the snapshot names the slot the phone runs',
    );

    // The wrist applies the snapshot the way the watch app would.
    await engine.applyMessage(snapshots.single);
    final applied = engine.timerFor(WatchTimerKind.hold);
    expect(
      applied,
      isNotNull,
      reason: 'the snapshot names the hold, so the wrist adopts it',
    );
    expect(applied!.state, WatchTimerState.paused);
  });

  test('S-127-02 a reinstalled watch applies the queued snapshot and its hold '
      'is paused, not running (D-1)', () async {
    await wristStartsHoldSession();
    await holdStart();
    radio.unreachable = true;
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    // The watch app was reinstalled: an empty store, a fresh engine.
    final reinstallOutbox = <Object>[];
    final reinstall = freshWristEngine(reinstallOutbox);
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
      isFalse,
      reason: 'the phone still runs the hold, so the reinstall must hold it',
    );
    expect(
      hold!.state,
      WatchTimerState.paused,
      reason: 'D-1: the reinstalled watch shows the phone paused hold',
    );
  });

  test('S-127-03 the resumed hold rides the queued snapshot running with the '
      'new accumulated pause (D-1)', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // A pause delivered while reachable, so the wrist holds it paused.
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    for (final frame in radio.ofType('timer_state')) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.paused,
      reason: 'the fixture: the pause was delivered while reachable',
    );

    // H-away, then the phone resumes. The resume frame cannot travel; after
    // the fix the snapshot carries the resumed hold.
    radio.unreachable = true;
    await phoneState.resumeTimedEntry(_plankSlotId, 0);
    final resumed = phoneState.getTimedInstancesForEffort(_plankSlotId).single;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final snapshots = queuedSnapshots();
    expect(
      snapshots,
      hasLength(1),
      reason:
          'D-1: the resume changes the payload, so a snapshot is queued '
          'while the wrist is away',
    );
    final hold = _holdOf(snapshots.single)!;
    expect(
      hold['state'],
      WatchTimerState.running,
      reason: 'D-1: the snapshot carries the resumed hold',
    );
    expect(hold['startedAt'], _wireInstant(sH));
    expect(
      hold.containsKey('pausedAt'),
      isFalse,
      reason: 'the hold is no longer paused',
    );
    expect(
      hold['accumulatedPauseMs'],
      resumed.totalPausedDurationMs,
      reason: 'the snapshot carries the pause the phone folded in',
    );
    expect(
      resumed.totalPausedDurationMs,
      greaterThan(0),
      reason: 'the fixture: a real pause is longer than nothing',
    );

    // The wrist applies the snapshot: the hold runs again.
    await engine.applyMessage(snapshots.single);
    final applied = engine.timerFor(WatchTimerKind.hold);
    expect(applied!.state, WatchTimerState.running);
    expect(applied.startedAt.millisecondsSinceEpoch, sH);
  });

  test('S-127-04 the refused pause going live later and the older queued '
      'snapshot both leave the hold paused (D-1)', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // S-127-01 up to the refused pause.
    radio.unreachable = true;
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    // The wrist comes back into reach: the owed pause is re-offered and the
    // wrist applies it.
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _waitFor(
      () => radio.sent.any(
        (frame) =>
            frame['type'] == 'timer_state' &&
            _holdOf(frame)?['state'] == WatchTimerState.paused,
      ),
      'the re-offered paused hold',
    );
    for (final frame in radio.sent) {
      if (frame['type'] == 'timer_state') {
        await engine.applyMessage(frame);
      }
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.paused,
      reason: 'the owed pause reaches the wrist first and holds',
    );

    // THEN the OS delivers the snapshot it carried all along.
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.paused,
      reason:
          'the older queued snapshot leaves the hold paused: it carried '
          'the paused hold too',
    );
    expect(
      engine.timerFor(WatchTimerKind.hold)!.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'still the same interval',
    );
  });

  test('S-127-05 a delivered pause names the exact delivered JSON in the '
      'projection (guard)', () async {
    await wristStartsHoldSession();
    await holdStart();

    // Reachable pause, delivered.
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    final deliveredHold = _holdOf(timerFrames().last)!;
    expect(
      deliveredHold['state'],
      WatchTimerState.paused,
      reason: 'the fixture: the pause frame was delivered',
    );

    final projected = await graph.mirror.projectedSession();
    expect(projected, isNotNull, reason: 'the phone speaks for its session');
    final projectedTimers = _asObject(
      projected!['timers'] ?? const <String, Object?>{},
    );
    expect(
      projectedTimers['hold'],
      deliveredHold,
      reason:
          'an in-sync pause: the projection names exactly the delivered '
          "frame's JSON",
    );
  });

  test('S-127-10 a start the radio refused rides the first queued snapshot '
      '(D-2)', () async {
    await wristStartsHoldSession();
    // H-away from the start: the start cannot travel live.
    radio.unreachable = true;
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;
    await graph.timerPush.flush(); // refused, owed
    await graph.autoPush.flush();
    await _settle();

    // The OS carries the snapshot; a wrist that never saw the live start
    // (a fresh reinstall) applies it.
    final reinstallOutbox = <Object>[];
    final reinstall = freshWristEngine(reinstallOutbox);
    expect(
      queuedSnapshots(),
      hasLength(1),
      reason: 'D-2: the change composes a snapshot and the OS queues it',
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
    expect(hold, isNotNull, reason: 'D-2: the snapshot rides the owed start');
    expect(hold!.state, WatchTimerState.running);
    expect(
      hold.sessionExerciseId,
      _plankSlotId,
      reason: 'the snapshot names the slot the phone runs',
    );
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the snapshot counts from the phone start S_H',
    );
  });

  test('S-127-11 the flush race: the owed start triggers a new snapshot (D-5 '
      'onOwed)', () async {
    await wristStartsHoldSession();
    radio.unreachable = true;
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;

    // The debounced composed pass goes out BEFORE the timer flush: whatever it
    // queued cannot have the start (the refusal has not happened yet).
    await graph.autoPush.flush();
    await graph.timerPush.flush();
    await _drain();

    // D-5: refusing the start asks for one more pass, whose snapshot NAMES the
    // hold. Newest wins: the queue holds only that.
    final snapshots = queuedSnapshots();
    expect(
      snapshots,
      hasLength(1),
      reason:
          'D-5: the newest snapshot replaced whatever the first pass '
          'queued (newest wins)',
    );
    final hold = _holdOf(snapshots.single)!;
    expect(
      hold['state'],
      WatchTimerState.running,
      reason:
          'D-5: the snapshot composed after the refusal names the owed '
          'start',
    );
    expect(hold['startedAt'], _wireInstant(sH));
    expect(hold['sessionExerciseId'], _plankSlotId);
  });

  test(
    'S-127-12 the wrist stopped the hold it did get: no restart (D-3, D-4)',
    () async {
      await wristStartsHoldSession();

      // The radio "loses" the start answer: the frame exists (the wrist will
      // apply it), but the phone's ledger records the start as refused.
      radio.lostAnswer = true;
      await phoneState.startTimedEntry(_plankSlotId, 0);
      final sH = phoneState
          .getTimedInstancesForEffort(_plankSlotId)
          .single
          .startedAtMs;
      await graph.timerPush.flush();
      await graph.autoPush.flush();
      await _drain();
      radio.lostAnswer = false;
      expect(
        radio.lostFrames.single['type'],
        'timer_state',
        reason: 'the fixture: the start exists but went unaccounted',
      );

      // The wrist applies the lost frame, so it runs the hold.
      await engine.applyMessage(radio.lostFrames.single);
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.running,
        reason: 'the fixture: the wrist runs the hold it did get',
      );

      // The wrist ends it. Its stopped timer_state frame is handed to the phone,
      // the way the radio carries one.
      final afterStartAttempted = radio.attempted.length;
      await engine.stopTimer(kind: 'hold');
      final stoppedFrames = [
        for (final frame in wristFrames)
          if (frame['type'] == 'timer_state' &&
              _holdOf(frame)?['state'] == WatchTimerState.stopped)
            frame,
      ];
      expect(
        stoppedFrames,
        hasLength(1),
        reason: 'the fixture: the wrist emitted the stopped frame',
      );
      // Snapshots composed before the phone learns of the stop may carry the
      // owed start (the wrist did get it); only later ones are judged.
      final snapshotsBeforeStop = sentSnapshots().length;
      await radio.fromWrist(stoppedFrames.single);
      await _drain();
      expect(
        _holdOf(stoppedFrames.single)!['state'],
        WatchTimerState.stopped,
        reason: 'the fixture: the wrist ended its own hold (54 D-1a)',
      );

      // Reachable. Every listener-triggered flush runs, so whatever the phone
      // still owes is attempted now.
      radio.unreachable = false;
      radio.emitLink(reachable: true);
      await graph.timerPush.flushClears();
      await _drain();
      final liveAfterStop = radio.attempted
          .skip(afterStartAttempted)
          .where((frame) => _namesHoldRunningFrom(frame, sH))
          .toList();
      expect(
        liveAfterStop,
        isEmpty,
        reason:
            'D-3/D-4: nothing restarts a hold the wrist ended, not live and '
            'not on any trigger',
      );

      // The phone applies everything the radio carried: the mirror stays a
      // stopped hold.
      for (final frame in radio.sent) {
        if (frame['type'] == 'timer_state') {
          await engine.applyMessage(frame);
        }
      }
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.stopped,
        reason: 'the wrist hold stays stopped',
      );

      // Then the phone changes (the next interval starts) and every snapshot
      // composed after it must name no hold.
      await phoneState.startTimedEntry(_runSlotId, 0);
      await graph.timerPush.flush();
      await graph.autoPush.flush();
      await _drain();
      final snapshots = [
        ...sentSnapshots().skip(snapshotsBeforeStop),
        ...queuedSnapshots(),
      ];
      expect(
        snapshots.any((frame) => _holdOf(frame) != null),
        isFalse,
        reason:
            'D-3: no snapshot composed after the stop names the hold the '
            'wrist ended',
      );
    },
  );

  test('S-127-13 the wrist paused its copy: the owed start is not sent '
      '(D-4)', () async {
    await wristStartsHoldSession();
    // S-127-10 up to the queue: the start is owed (refused live) and the
    // snapshot that rides it was applied by the wrist.
    radio.unreachable = true;
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    final fromSnapshot = engine.timerFor(WatchTimerKind.hold);
    expect(
      fromSnapshot,
      isNotNull,
      reason: 'D-2: the snapshot delivers the owed start',
    );
    expect(
      fromSnapshot!.state,
      WatchTimerState.running,
      reason: 'the fixture: the wrist runs the hold its snapshot delivered',
    );

    // The user pauses on the wrist. The phone hears it.
    final afterPause = radio.attempted.length;
    await engine.pauseTimer(kind: 'hold');
    expect(
      wristFrames.where(
        (frame) => _holdOf(frame)?['state'] == WatchTimerState.paused,
      ),
      hasLength(1),
      reason: 'the fixture: the wrist emitted its paused copy',
    );
    await radio.fromWrist(
      wristFrames.lastWhere(
        (frame) => _holdOf(frame)?['state'] == WatchTimerState.paused,
      ),
    );
    await _drain();

    // Reachable. The owed start must NOT go out: the mirror holds this very
    // hold, same slot and start, now paused.
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await graph.timerPush.flushClears();
    await _drain();
    expect(
      radio.attempted
          .skip(afterPause)
          .any((frame) => _namesHoldRunningFrom(frame, sH)),
      isFalse,
      reason:
          'D-4: the owed start is dropped: the mirror already holds the '
          'same slot and start',
    );
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.paused,
      reason: 'the wrist stays paused',
    );
  });

  test(
    'S-127-18 a refused pause is still sent after the mirror echoes the '
    'running start the radio lost the answer for (D-4, review finding)',
    () async {
      await wristStartsHoldSession();

      // The start reaches the wrist but the phone books it as refused (owed).
      radio.lostAnswer = true;
      await phoneState.startTimedEntry(_plankSlotId, 0);
      final sH = phoneState
          .getTimedInstancesForEffort(_plankSlotId)
          .single
          .startedAtMs;
      await graph.timerPush.flush();
      await _drain();
      radio.lostAnswer = false;
      final lost = radio.lostFrames.single;
      await engine.applyMessage(lost);

      // The wrist reports its running copy to the phone: the mirror holds this
      // very hold, running, same slot and start.
      await radio.fromWrist({...lost, 'messageId': 'echo-s-127-18'});
      await _drain();

      // Out of reach, the phone pauses: the radio refuses the pause (owed).
      radio.unreachable = true;
      await phoneState.pauseTimedEntry(_plankSlotId, 0);
      await graph.timerPush.flush();
      await _drain();

      // Back in reach: the owed state must go out, naming the hold paused.
      radio.unreachable = false;
      final before = radio.attempted.length;
      radio.emitLink(reachable: true);
      await graph.timerPush.flushClears();
      await _drain();
      final sentAfter = radio.attempted
          .skip(before)
          .where((frame) => frame['type'] == 'timer_state')
          .map(_holdOf)
          .whereType<Map<String, Object?>>()
          .toList();
      expect(
        sentAfter.any(
          (hold) =>
              hold['state'] == WatchTimerState.paused &&
              hold['startedAt'] == _wireInstant(sH),
        ),
        isTrue,
        reason:
            'the phone paused, so the paused hold is sent when the wrist is '
            'reachable; the mirror knowing the start is not a reason to drop it',
      );
    },
  );

  test('S-127-14 the phone ends first: no snapshot names the hold and no live '
      'start is attempted (D-2 rule (ii))', () async {
    await wristStartsHoldSession();
    // S-127-10 up to before applying: the start is owed and the snapshot queues.
    radio.unreachable = true;
    await phoneState.startTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    // The phone ends the interval it started.
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    // The auto push may win the race: its snapshot is composed while the timer
    // push still owes the start (the ledger has not been pruned yet), and the
    // phone no longer runs it, so it must not be named (D-2 rule (ii)).
    await graph.autoPush.flush();
    await _settle();
    expect(
      queuedSnapshots(),
      isNotEmpty,
      reason: 'the fixture: the auto push composed a snapshot before the prune',
    );
    expect(
      _holdOf(queuedSnapshots().last),
      isNull,
      reason: 'D-2 rule (ii): the owed start of a logged interval is not named',
    );
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    // The newest queued snapshot must name no hold.
    final snapshots = queuedSnapshots();
    expect(
      snapshots,
      hasLength(1),
      reason: 'the fixture: the newest payload is queued once (newest wins)',
    );
    expect(
      _holdOf(snapshots.single),
      isNull,
      reason:
          'D-2 rule (ii): a start for an interval the phone already '
          'logged is never sent',
    );

    // The wrist applies it and runs nothing.
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(
      hold == null || hold.state != WatchTimerState.running,
      isTrue,
      reason: 'the engine shows no running hold',
    );

    // And the reachability trigger sends no start: the interval is logged.
    final attemptedBeforeEmit = radio.attempted.length;
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _drain();
    expect(
      radio.attempted
          .skip(attemptedBeforeEmit)
          .any(
            (frame) => frame['type'] == 'timer_state' && _holdOf(frame) != null,
          ),
      isFalse,
      reason: 'the logged interval is never started again',
    );
    for (final frame in radio.sent.where(
      (frame) => frame['type'] == 'timer_state',
    )) {
      await engine.applyMessage(frame);
    }
    final after = engine.timerFor(WatchTimerKind.hold);
    expect(
      after == null || after.state != WatchTimerState.running,
      isTrue,
      reason: 'no live start is attempted on emitLink(true)',
    );
  });

  test(
    'S-127-15 the snapshot and the late live start agree (D-2, D-6)',
    () async {
      await wristStartsHoldSession();
      radio.unreachable = true;
      await phoneState.startTimedEntry(_plankSlotId, 0);
      final sH = phoneState
          .getTimedInstancesForEffort(_plankSlotId)
          .single
          .startedAtMs;
      await graph.timerPush.flush();
      await graph.autoPush.flush();
      await _settle();

      // A wrist that never saw the live start applies the snapshot.
      for (final frame in radio.deliverQueued()) {
        await engine.applyMessage(frame);
      }
      final fromSnapshot = engine.timerFor(WatchTimerKind.hold);
      expect(
        fromSnapshot,
        isNotNull,
        reason: 'the fixture: the snapshot names hold',
      );
      expect(
        fromSnapshot!.startedAt.millisecondsSinceEpoch,
        sH,
        reason: 'D-6: the late start counts from its original start',
      );

      // Reachable: the owed live start also arrives. The wrist already holds the
      // same interval, so nothing changes.
      radio.unreachable = false;
      radio.emitLink(reachable: true);
      await _waitFor(
        () => radio.sent.any((frame) => _namesHoldRunningFrom(frame, sH)),
        'the owed live start',
      );
      for (final frame in radio.sent) {
        if (frame['type'] == 'timer_state') {
          await engine.applyMessage(frame);
        }
      }
      final hold = engine.timerFor(WatchTimerKind.hold);
      expect(hold, isNotNull, reason: 'one hold is on the wrist');
      expect(hold!.state, WatchTimerState.running);
      expect(
        hold.startedAt.millisecondsSinceEpoch,
        sH,
        reason:
            'the second arrival has the same values, so the start stays S_H',
      );
      expect(hold.sessionExerciseId, _plankSlotId);
    },
  );

  test(
    'S-127-16 a reachable wrist gets no extra snapshots (guard; D-5 baseline)',
    () async {
      await wristStartsHoldSession();
      radio.unreachable = false;

      // start, pause, resume, finish — all delivered. The timer push alone
      // (a delivered frame never calls onOwed, D-5) must not make the auto push
      // compose a snapshot: the count is read before the auto push runs.
      Future<void> timerPassAddsNoSnapshot() async {
        final before = sentSnapshots().length + queuedSnapshots().length;
        await graph.timerPush.flush();
        await _drain();
        expect(
          sentSnapshots().length + queuedSnapshots().length,
          before,
          reason: 'a delivered timer frame asks for no snapshot (D-5)',
        );
        await graph.autoPush.flush();
      }

      await phoneState.startTimedEntry(_plankSlotId, 0);
      await timerPassAddsNoSnapshot();
      await phoneState.pauseTimedEntry(_plankSlotId, 0);
      await timerPassAddsNoSnapshot();
      await phoneState.resumeTimedEntry(_plankSlotId, 0);
      await timerPassAddsNoSnapshot();
      await phoneState.finishTimedEntry(_plankSlotId, 0);
      await timerPassAddsNoSnapshot();
      await _drain();
      for (final frame in radio.ofType('timer_state')) {
        await engine.applyMessage(frame);
      }

      // The count baseline recorded on the unchanged code (base commit
      // b51b02ea934ac783523dc690aa5540957735a9cf): 4 snapshots were sent over
      // this scenario when this test first ran — the observed number, written as
      // a literal per the brief. D-5 (the onOwed callback) must not add more: a
      // delivered frame never calls it.
      const baselineSnapshotCount = 4;
      final snapshotCount = sentSnapshots().length + queuedSnapshots().length;
      expect(
        snapshotCount,
        baselineSnapshotCount,
        reason: 'a reachable wrist gets no snapshot per timer event',
      );
      // onOwed never called is guarded by the count
    },
  );

  test('S-127-17 a replacement interval is never named while the old one may '
      'still be on the wrist (D-2 omission)', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();

    // The slot gets a second interval (the fixture allows it for this test).
    radio.unreachable = true;
    await phoneState.addTimedEntry(_plankSlotId);
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phoneState.startTimedEntry(_plankSlotId, 1);
    final instances = phoneState.getTimedInstancesForEffort(_plankSlotId);
    expect(
      instances[0].state,
      TimedState.finished,
      reason:
          'the fixture: '
          'interval 0 is logged',
    );
    final sH2 = instances[1].startedAtMs;
    expect(sH2 > sH, isTrue, reason: 'the fixture: S_H2 is later than S_H');
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    // D-2: the old row (S_H) differs from the phone's now (S_H2) on the same
    // slot, so the snapshot names no hold: the old one is stopped by omission
    // and the new one is withheld.
    final snapshots = queuedSnapshots();
    expect(snapshots, hasLength(1), reason: 'the fixture: one queued snapshot');
    expect(
      _holdOf(snapshots.single),
      isNull,
      reason:
          'D-2: the replacement is never named while the old one may be '
          'on the wrist',
    );
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the old hold is stopped by the omission',
    );

    // Reachable: clear then start go live, in that order.
    radio.unreachable = false;
    radio.emitLink(reachable: true);
    await _waitFor(() => radio.sent.any(_isHoldClear), 'the re-offered clear');
    await _waitFor(
      () => radio.sent.any((frame) => _namesHoldRunningFrom(frame, sH2)),
      'the live start of the replacement',
    );
    final clearIndex = radio.sent.indexWhere(_isHoldClear);
    final startIndex = radio.sent.indexWhere(
      (frame) => _namesHoldRunningFrom(frame, sH2),
    );
    expect(
      clearIndex < startIndex,
      isTrue,
      reason: 'D-2b: the clear goes out before the start',
    );
    for (final frame in radio.sent) {
      if (frame['type'] == 'timer_state') {
        await engine.applyMessage(frame);
      }
    }
    final hold = engine.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'the replacement runs');
    expect(hold!.state, WatchTimerState.running);
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH2,
      reason: 'the engine hold runs from S_H2',
    );
  });

  test('S-127-20 probe: wrist with no session, start + log; the snapshot '
      'request is answered right (D-7)', () async {
    await wristStartsHoldSession();
    final probeOutbox = <Object>[];
    final probe = freshWristEngine(probeOutbox);

    // The phone starts the hold. The radio says delivered, but the wrist
    // engine refuses: it holds no session (refuseNoSession).
    await phoneState.startTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    for (final frame in radio.ofType('timer_state')) {
      expect(
        await probe.applyMessage(frame),
        isFalse,
        reason:
            'the fixture: a session-scoped frame is refused with no '
            'session, while the phone counted it delivered',
      );
    }

    // The phone logs it. Same delivery story.
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    for (final frame in radio.ofType('timer_state')) {
      expect(
        await probe.applyMessage(frame),
        isFalse,
        reason:
            'the fixture: the clear is refused, and counted delivered '
            'the same',
      );
    }

    // A fresh wrist asks for a snapshot; the phone answers it.
    final sentBefore = radio.sent.length;
    await radio.fromWrist(WatchTransportRequest.snapshotFrame());
    await _drain();
    final answers = [
      for (final frame in radio.sent.skip(sentBefore))
        if (frame['type'] == 'session_snapshot') frame,
    ];
    expect(
      answers,
      isNotEmpty,
      reason: 'the fixture: the phone answered the snapshot request',
    );
    expect(
      await probe.applyMessage(answers.first),
      isTrue,
      reason: 'the answer is a session snapshot, so it applies',
    );
    expect(
      probe.session?.sessionId,
      _sessionId,
      reason: 'D-7: the wrist with no session got its session from the answer',
    );
    final hold = probe.timerFor(WatchTimerKind.hold);
    expect(
      hold == null || hold.state == WatchTimerState.stopped,
      isTrue,
      reason: 'D-7: the logged hold rides no snapshot',
    );
  });

  test('S-127-21 probe: wrist with no session, start only; the answer names '
      'hold running from S_H (D-7)', () async {
    await wristStartsHoldSession();
    final probeOutbox = <Object>[];
    final probe = freshWristEngine(probeOutbox);

    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    for (final frame in radio.ofType('timer_state')) {
      expect(
        await probe.applyMessage(frame),
        isFalse,
        reason:
            'the fixture: the start was refused (no session) and counted '
            'delivered',
      );
    }

    final sentBefore = radio.sent.length;
    await radio.fromWrist(WatchTransportRequest.snapshotFrame());
    await _drain();
    final answers = [
      for (final frame in radio.sent.skip(sentBefore))
        if (frame['type'] == 'session_snapshot') frame,
    ];
    expect(answers, isNotEmpty, reason: 'the phone answers the request');
    await probe.applyMessage(answers.first);
    final hold = probe.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'D-7: the answer names the running hold');
    expect(hold!.state, WatchTimerState.running);
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the wrist counts from the phone start S_H',
    );
  });

  test('S-127-22 probe: wrist with no session, start + pause; the answer '
      'names hold paused (D-1, D-7)', () async {
    await wristStartsHoldSession();
    final probeOutbox = <Object>[];
    final probe = freshWristEngine(probeOutbox);

    // The start and the pause: both refused (the wrist engine refuses them,
    // it holds no session) and both counted delivered by the phone.
    await phoneState.startTimedEntry(_plankSlotId, 0);
    final sH = phoneState
        .getTimedInstancesForEffort(_plankSlotId)
        .single
        .startedAtMs;
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await phoneState.pauseTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _drain();
    for (final frame in radio.ofType('timer_state')) {
      expect(
        await probe.applyMessage(frame),
        isFalse,
        reason:
            'the fixture: a session-scoped frame is refused with no '
            'session, while the phone counted it delivered',
      );
    }

    final sentBefore = radio.sent.length;
    await radio.fromWrist(WatchTransportRequest.snapshotFrame());
    await _drain();
    final answers = [
      for (final frame in radio.sent.skip(sentBefore))
        if (frame['type'] == 'session_snapshot') frame,
    ];
    expect(answers, isNotEmpty, reason: 'the phone answers the request');
    await probe.applyMessage(answers.first);
    final hold = probe.timerFor(WatchTimerKind.hold);
    expect(hold, isNotNull, reason: 'D-1: the answer names the hold');
    expect(
      hold!.state,
      WatchTimerState.paused,
      reason: 'D-1: the answer carries the phone CURRENT state: paused',
    );
    expect(
      hold.startedAt.millisecondsSinceEpoch,
      sH,
      reason: 'the pause is a state of the same interval',
    );
  });

  test('S-127-34 end to end: the stale queued snapshot never revives the hold '
      '(D-8)', () async {
    await wristStartsHoldSession();
    final sH = await holdStart();
    await graph.autoPush.flush();
    await _drain();

    // H-log-away (121a flow): one clear refused, one snapshot queued.
    // The remaining snapshot that names the hold is the one the phone sent
    // while reachable before the log.
    radio.unreachable = true;
    await letHoldRun();
    await phoneState.finishTimedEntry(_plankSlotId, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await _settle();

    final sentBefore = sentSnapshots();
    final a = sentBefore.reversed.firstWhere(
      (frame) => _namesHoldRunningFrom(frame, sH),
    );
    final queued = queuedSnapshots();
    expect(
      queued.any((frame) => _holdOf(frame) == null),
      isTrue,
      reason: 'the fixture: the post-log snapshot names no hold (121a)',
    );
    for (final frame in radio.deliverQueued()) {
      await engine.applyMessage(frame);
    }
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason: 'the newer snapshot stopped the hold',
    );

    // The OS delivers A (older) out of order: the engine must refuse it whole.
    await engine.applyMessage(a);
    expect(
      engine.timerFor(WatchTimerKind.hold)!.state,
      WatchTimerState.stopped,
      reason:
          'D-8: a snapshot older than the newest applied is refused: the '
          'stale snapshot never brings the running hold back',
    );
  });
}
