// A timer the watch started reaches the phone's interval (plan 43b2 P2).
//
// Plan: `docs/plans/2026-10-20-43b2-shared-timer-phone-receives-plan/
// 2026-10-20-43b2-shared-timer-phone-receives-plan.md`, D-3 (delivery) and D-5
// (no echo).
// Scenario mapping:
//   S-6111 the wrist's running timer starts the phone's first unfinished
//          interval, once; a paused one carries its pause, a round its length
//                                                           → `S-6111 ...`
//   S-6112 ignored: stopped, no slot, an empty slot, another session, an
//          unheld slot, an ended phone session                → `S-6112a ...`,
//     `S-6112b ...`, `S-6112c ...`, `S-6112d ...`, `S-6112 a timer naming an
//     empty slot ...`, `S-6112 an ended phone session ...`
//   S-6113 the timer arrives before the phone holds the session, the same
//          timer is news again in a new session, and a stale one is not
//          re-applied onto the interval the phone started next → `S-6113 ...`
//   S-6114 nothing is echoed back, but the phone's pause travels → `S-6114 ...`
//   S-6115 the earlier start wins, whichever device made it → `S-6115 ...`
//   S-12171..S-12174 a stale wrist copy of a timer the phone already logged
//          never starts or rewinds the next interval and nothing else moves;
//          a genuine next start still adopts → `S-12171 ...`, `S-12172 ...`,
//     `S-12173 ...`, `S-12174 ...`
//   S-12631..S-12640 a wrist pause or resume of a timer the phone runs
//          reaches the phone → group 'S-1263x ...'
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the adoption it returns — over a fake radio; the wrist side is the
// real engine over an in-memory store, so a frame the phone sends is applied
// the way the watch app applies one. Every pass is closed by `flush()` rather
// than by waiting, and the tests are plain `test()`: no `testWidgets`, no
// FakeAsync.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
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

final DateTime _now = DateTime.utc(2026, 10, 19, 9);

/// The session both devices know.
const String _sessionId = 's-w-adopt';

/// The one slot the fixture puts in the ladder, and its effort id on the phone
/// (D-3: the wrist's slot id IS the phone's effort id).
const String _slotId = 'sx-run';

/// A round slot, for the frame that carries a round's own length.
const String _roundSlotId = 'sx-burpee';

/// The wrist's start, unlike every default: forty seconds before the pinned
/// clock, so a phone stamp of "now" cannot match it.
final DateTime _wristStart = _now.subtract(const Duration(seconds: 40));

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// A catalog the phone can adopt a timed slot for.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Run',
    capabilities: ['time', 'distance'],
  );
}

/// One ladder slot as the protocol spells it: a timed exercise.
Map<String, Object?> _slot() => <String, Object?>{
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-run',
  'name': 'Run',
  'effortKind': 'timed',
  'capabilities': ['time', 'distance'],
};

/// The same, for a counted exercise the phone tracks in rounds.
Map<String, Object?> _roundSlot() => <String, Object?>{
  'sessionExerciseId': _roundSlotId,
  'exerciseId': 'ex-burpee',
  'name': 'Burpees',
  'effortKind': 'round',
  'capabilities': ['rounds'],
};

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it cannot
/// carry the way the platform channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  final List<Map<String, Object?>> attempted = [];

  bool unreachable = false;

  WatchInboundHandler? _handler;

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
    if (unreachable) return WatchDelivery.undelivered;
    sent.add(envelope);
    return WatchDelivery.delivered;
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
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _PhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Map<String, Object?>> wristFrames;
  late List<Object> failures;

  /// The wrist's clock, moved only to stamp a timer in the past.
  late DateTime wristClock;

  /// The id the wrist mints for its next session — the same session until a
  /// test moves the wrist to a new one.
  late String wristSessionId;

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption bridge and to the timer adoption in
  /// `lib/main.dart`; the fixtures do the same.
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
    created.timerAdoption.bindWorkoutState(phoneState);
    return created;
  }

  /// The fixture: the wrist starts [_sessionId] with one timed slot, the phone
  /// adopts it (which gives the slot its first interval), and the phone then
  /// adds a second: two intervals that have not started.
  Future<void> fixture() async {
    await engine.createSession(modality: null, exercises: [_slot()]);
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    expect(graph.mirror.sessionId, _sessionId);

    await phoneState.addEntry(_slotId);
    expect(
      phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
      [TimedState.notStarted, TimedState.notStarted],
      reason: 'the fixture: two unstarted intervals',
    );
  }

  /// The wrist starts an `elapsed` timer at [at], for [slot] when given.
  Future<WatchTimerRecord> wristStartsElapsed(
    DateTime at, {
    String? slot = _slotId,
  }) async {
    wristClock = at;
    try {
      return await engine.startTimer(
        WatchTimerKind.elapsed,
        sessionExerciseId: slot,
      );
    } finally {
      wristClock = _now;
    }
  }

  /// The one timer frame the wrist emitted last.
  Map<String, Object?> lastTimerFrame() =>
      wristFrames.lastWhere((frame) => frame['type'] == 'timer_state');

  /// The last timer frame with [fields] folded into the timer it carries, for
  /// the values the wrist cannot stamp this way (a slot the wire would refuse,
  /// a pause it has no way to book). The harness builds the graph without a
  /// validator, so the mirror takes the frame all the same.
  Map<String, Object?> timerFrameWith(
    Map<String, Object?> fields, {
    String kind = WatchTimerKind.elapsed,
  }) {
    final frame = lastTimerFrame();
    final payload = _asObject(frame['payload']);
    final timers = _asObject(payload['timers']);
    return <String, Object?>{
      ...frame,
      'payload': <String, Object?>{
        ...payload,
        'timers': <String, Object?>{
          ...timers,
          kind: <String, Object?>{..._asObject(timers[kind]), ...fields},
        },
      },
    };
  }

  /// Hands the phone [frame] and lets the router and the mirror settle.
  Future<void> deliver(Map<String, Object?> frame) async {
    await radio.fromWrist(frame);
    await _settle();
  }

  /// The wrist's snapshot, optionally with an unrelated revision change.
  Map<String, Object?> snapshot({int? revision}) {
    final frame = engine.sessionSnapshot(messageId: 'msg-snapshot-$revision')!;
    if (revision != null) _asObject(frame['payload'])['revision'] = revision;
    return frame;
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> sentOfType(String type) => radio.ofType(type);

  /// Applies the phone's timer frames to the wrist engine, in the order they
  /// were sent, the way the watch app applies each frame it receives.
  Future<void> applyPhoneTimers() async {
    for (final frame in sentOfType('timer_state')) {
      await engine.applyMessage(frame);
    }
  }

  /// The phone's two intervals, still not started, and a revision that held.
  void expectNothingAdopted(int revisionBefore) {
    expect(
      phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
      [TimedState.notStarted, TimedState.notStarted],
      reason: 'no interval started',
    );
    expect(
      phoneState.watchRefreshRevision,
      revisionBefore,
      reason: 'no write, so no screen resync',
    );
  }

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _PhoneRadio(failures.add);
    graph = await startGraph();

    wristFrames = [];
    wristStore = InMemoryWatchSessionStore();
    wristClock = _now;
    wristSessionId = _sessionId;
    engine = WatchSessionEngine(
      wristStore,
      clock: () => wristClock,
      sessionIdFactory: () => wristSessionId,
      onEmit: wristFrames.add,
    );
  });

  group('S-6111 the wrist timer starts the first unfinished interval', () {
    test(
      'S-6111 the wrist\'s elapsed timer for the slot starts interval 0 on the '
      'wrist clock, once',
      () async {
        await fixture();
        final revisionBefore = phoneState.watchRefreshRevision;

        final wristTimer = await wristStartsElapsed(_wristStart);
        final frame = lastTimerFrame();
        await deliver(frame);
        await graph.timerAdoption.flush();

        final intervals = phoneState.getTimedInstancesForEffort(_slotId);
        expect(
          intervals.first.state,
          TimedState.active,
          reason: 'S-6111 the timestamp names an unfinished interval',
        );
        expect(
          intervals.first.startedAtMs,
          wristTimer.startedAt.millisecondsSinceEpoch,
          reason: "S-6111 on the wrist's clock, not the phone's",
        );
        expect(
          intervals.first.startedAtMs,
          _wristStart.millisecondsSinceEpoch,
          reason: 'S-6111 forty seconds before the pinned clock',
        );
        expect(
          intervals[1].state,
          TimedState.notStarted,
          reason: 'S-6111 the later interval is untouched',
        );
        expect(
          phoneState.watchRefreshRevision,
          revisionBefore + 1,
          reason: 'S-6111 the open screen resyncs once',
        );

        // The same frame again, and an unrelated snapshot change: neither is
        // a new timer, so neither writes.
        await deliver(frame);
        await graph.timerAdoption.flush();
        await deliver(snapshot(revision: 7));
        await graph.timerAdoption.flush();

        expect(
          phoneState.watchRefreshRevision,
          revisionBefore + 1,
          reason: 'S-6111 a repeated frame is not applied twice',
        );
        expect(failures, isEmpty);
      },
    );

    test('S-6111 a paused wrist timer is adopted paused', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      wristClock = _wristStart.add(const Duration(seconds: 12));
      final paused = await engine.pauseTimer(kind: WatchTimerKind.elapsed);
      wristClock = _now;
      expect(
        paused?.pausedAt,
        isNotNull,
        reason: "the fixture: the wrist's timer is paused",
      );

      // The pause the wrist books — the frame the engine emits carries none.
      await deliver(timerFrameWith(const {'accumulatedPauseMs': 7000}));
      await graph.timerAdoption.flush();

      final interval = phoneState
          .getTimedInstancesForEffort(_slotId)
          .first;
      expect(
        interval.state,
        TimedState.paused,
        reason: 'S-6111 a paused wrist timer leaves the interval paused',
      );
      expect(
        interval.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: "S-6111 with the wrist's start",
      );
      expect(
        interval.pausedAtMs,
        paused!.pausedAt!.millisecondsSinceEpoch,
        reason: "S-6111 and the wrist's pause stamp",
      );
      expect(
        interval.totalPausedDurationMs,
        7000,
        reason: "S-6111 and the pause the wrist had banked",
      );
      expect(failures, isEmpty);
    });

    test('S-6111 a round frame carries its length', () async {
      await seedExercise(
        repository,
        id: 'ex-burpee',
        name: 'Burpees',
        capabilities: ['rounds'],
      );
      await engine.createSession(modality: null, exercises: [_roundSlot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        phoneState.currentSession?.id,
        _sessionId,
        reason: "the fixture: the phone holds the wrist's round session",
      );

      final before = phoneState.getRoundsForEffort(_roundSlotId).single;
      expect(before.state, RoundState.notStarted);
      expect(
        before.plannedDurationSecs,
        isNot(75),
        reason: 'the fixture: the round does not already count 75 seconds',
      );

      wristClock = _wristStart;
      await engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 75000,
        sessionExerciseId: _roundSlotId,
      );
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final adopted = phoneState.getRoundsForEffort(_roundSlotId).single;
      expect(
        adopted.state,
        RoundState.active,
        reason: 'S-6111 the wrist round starts the phone\'s round',
      );
      expect(
        adopted.startedAtMs,
        _wristStart.millisecondsSinceEpoch,
        reason: "S-6111 on the wrist's clock",
      );
      expect(
        adopted.plannedDurationSecs,
        75,
        reason: "S-6111 the frame's plannedDurationMs is the round's length",
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6112 ignored timers', () {
    test('S-6112a a stopped timer is not applied', () async {
      await fixture();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristStartsElapsed(_wristStart);
      await engine.stopTimer(kind: WatchTimerKind.elapsed);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expectNothingAdopted(revisionBefore);
      expect(failures, isEmpty);
    });

    test('S-6112b a timer that names no slot is not applied', () async {
      await fixture();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristStartsElapsed(_wristStart, slot: null);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expectNothingAdopted(revisionBefore);
      expect(failures, isEmpty);
    });

    test('S-6112c a mirror holding another session than the phone\'s is not '
        'applied', () async {
      await fixture();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristStartsElapsed(_wristStart);
      final foreign = snapshot();
      foreign['sessionId'] = 's-w-other';
      _asObject(foreign['payload'])['sessionId'] = 's-w-other';
      await deliver(foreign);
      await graph.timerAdoption.flush();

      expect(
        graph.mirror.sessionId,
        's-w-other',
        reason: 'the fixture: the mirror moved off the phone\'s session',
      );
      expect(
        phoneState.currentSession?.id,
        _sessionId,
        reason: 'the fixture: the phone kept its own session',
      );
      expectNothingAdopted(revisionBefore);
      expect(failures, isEmpty);
    });

    test('S-6112d a timer naming a slot the phone does not hold is not '
        'applied', () async {
      await fixture();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristStartsElapsed(_wristStart, slot: 'sx-ghost');
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expectNothingAdopted(revisionBefore);
      expect(failures, isEmpty);
    });

    test('S-6112 a timer naming an empty slot is ignored', () async {
      await fixture();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristStartsElapsed(_wristStart);
      await deliver(timerFrameWith(const {'sessionExerciseId': ''}));
      await graph.timerAdoption.flush();

      expectNothingAdopted(revisionBefore);
      expect(failures, isEmpty);
    });

    test('S-6112 an ended phone session adopts nothing', () async {
      await fixture();
      await wristStartsElapsed(_wristStart);
      await phoneState.endSession();
      final revisionBefore = phoneState.watchRefreshRevision;
      expect(
        phoneState.hasActiveSession,
        isFalse,
        reason: "the fixture: the phone's session is over",
      );

      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expectNothingAdopted(revisionBefore);
      expect(
        _asObject(graph.mirror.state['timers'])['elapsed'],
        isNotNull,
        reason: 'the mirror holds the timer the phone had no session for',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6113 the timer arrives before the phone holds the session', () {
    test('S-6113 the WorkoutState listener applies the timer once the phone '
        'adopts the session', () async {
      // The fixture's rows are written by a state that holds the session; the
      // state the adoption is bound to comes up empty, as a phone starting
      // with the wrist's session already on disk does.
      await fixture();
      final lateState = WorkoutState(repository);
      expect(
        lateState.currentSession,
        isNull,
        reason: 'the fixture: the phone has not adopted the session yet',
      );
      graph.timerAdoption.bindWorkoutState(lateState);

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        lateState.currentSession,
        isNull,
        reason: 'S-6113 the timer came first and had no session to land in',
      );

      // The snapshot makes the phone adopt the session; the WorkoutState
      // listener is what applies the timer the mirror already holds.
      graph.adoption.bindWorkoutState(lateState);
      await deliver(snapshot());
      await _settle();

      expect(
        lateState.currentSession?.id,
        _sessionId,
        reason: 'the fixture: the snapshot is the phone\'s session now',
      );
      final intervals = lateState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.first.state,
        TimedState.active,
        reason: 'S-6113 the listener served the timer that came first',
      );
      expect(
        intervals.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: "S-6113 with the wrist's start",
      );
      expect(failures, isEmpty);
    });

    test('S-6113 the same timer for a NEW session is applied again', () async {
      // One interval to begin with: an effort id IS the slot id, so every
      // session's rows pile up under it; the old session's rows are dropped
      // below, so the new session's first interval is the adoption target.
      await engine.createSession(modality: null, exercises: [_slot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: one unstarted interval',
      );

      final first = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        first.startedAt.millisecondsSinceEpoch,
        reason: 'the fixture: the first session adopted the timer',
      );

      // The wrist ends its session and starts another, with the same slot; the
      // phone ends its copy first, so the new snapshot is a fresh adoption.
      await phoneState.endSession();
      // Production gives every session its own effort ids, so a finished row
      // of the old session is never visible to the next one (121b A-1): the
      // fixture shares the id, so it drops the old session's rows here.
      await repository.deleteTimedInstancesForEffort(_slotId);
      await phoneState.refreshEfforts([_slotId]);
      await engine.finishSession();
      wristSessionId = 's-w-adopt-2';
      await engine.createSession(modality: null, exercises: [_slot()]);
      await deliver(snapshot());
      await _settle();
      expect(
        phoneState.currentSession?.id,
        wristSessionId,
        reason: "the fixture: the phone holds the wrist's new session",
      );

      await phoneState.addEntry(_slotId);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted, TimedState.notStarted],
        reason: "the fixture: the old session's rows are gone, the new "
            'session holds two intervals that have not started',
      );

      // The identical timer map, for the new session: the memo that skipped the
      // old session's copy must not skip this one.
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.active, TimedState.notStarted],
        reason: 'S-6113 the memo belongs to a session, not to a timer',
      );
      expect(
        intervals.first.startedAtMs,
        _wristStart.millisecondsSinceEpoch,
        reason: 'S-6113 on the same wrist start as the old session',
      );
      expect(failures, isEmpty);
    });

    test('S-6113 a stale wrist timer is not re-applied onto the interval the '
        'phone started next', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: "the fixture: interval 0 runs on the wrist's start",
      );

      // The phone logs interval 0 and starts the next one itself. The wrist
      // applies neither, so its timer never leaves the mirror: every later
      // notification repeats the same stale frame.
      await phoneState.finishTimedEntry(_slotId, 0);
      await phoneState.startTimedEntry(_slotId, 1);
      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      final phoneStartMs = intervals[1].startedAtMs;
      expect(
        intervals.map((i) => i.state),
        [TimedState.finished, TimedState.active],
        reason: 'the fixture: the phone moved on to interval 1',
      );
      expect(
        phoneStartMs,
        greaterThan(wristTimer.startedAt.millisecondsSinceEpoch),
        reason: "the fixture: interval 1 started after the wrist's timer",
      );
      final revisionBefore = phoneState.watchRefreshRevision;

      // The unchanged frame is delivered again, and the mirror notifies for an
      // unrelated snapshot; neither is news, so neither writes.
      await graph.timerAdoption.flush();
      await deliver(snapshot(revision: 8));
      await graph.timerAdoption.flush();

      final after = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        after[1].startedAtMs,
        phoneStartMs,
        reason: "S-6113 the stale timer must not replace the phone's later "
            'start',
      );
      expect(
        after.map((i) => i.state),
        [TimedState.finished, TimedState.active],
        reason: 'S-6113 interval 1 is still the phone\'s running interval',
      );
      expect(
        phoneState.watchRefreshRevision,
        revisionBefore,
        reason: 'S-6113 nothing was adopted, so no screen resync',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6114 no echo', () {
    test('S-6114 an adopted timer is not sent back, and the phone\'s pause '
        'still travels', () async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);

      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: the phone adopted the wrist timer',
      );

      await graph.timerPush.flush();
      expect(
        sentOfType('timer_state'),
        isEmpty,
        reason: 'S-6114 the wrist already holds the timer, so nothing is sent',
      );

      await phoneState.pauseTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      final frames = sentOfType('timer_state');
      expect(
        frames,
        hasLength(1),
        reason: 'S-6114 the pause is news and travels as one frame',
      );
      final timer = _asObject(
        _asObject(_payload(frames.single)['timers'])['elapsed'],
      );
      expect(timer['state'], 'paused');
      expect(timer['sessionExerciseId'], _slotId);
      expect(failures, isEmpty);
    });
  });

  group('S-6115 the earlier start wins', () {
    test('S-6115 a wrist timer earlier than the phone\'s own start replaces it '
        'and is not sent back', () async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);

      // The phone's own start, thirty seconds after the wrist's.
      final phoneStartMs = _wristStart
          .add(const Duration(seconds: 30))
          .millisecondsSinceEpoch;
      await phoneState.startTimedEntry(_slotId, 0);
      final started = phoneState.getTimedInstancesForEffort(_slotId).first;
      await repository.updateTimedInstance(
        started.copyWith(startedAtMs: phoneStartMs, updatedAtMs: phoneStartMs),
      );
      await phoneState.refreshEfforts([_slotId]);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        phoneStartMs,
        reason: 'the fixture: the phone counts from its own start',
      );

      await graph.timerPush.flush();
      expect(
        sentOfType('timer_state'),
        hasLength(1),
        reason: "the fixture: the phone's start reached the wrist",
      );
      await applyPhoneTimers();
      expect(
        engine
            .timerFor(WatchTimerKind.elapsed)!
            .startedAt
            .millisecondsSinceEpoch,
        phoneStartMs,
        reason: 'the fixture: the wrist holds the phone\'s later start',
      );

      // The wrist's own timer, started earlier.
      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'S-6115 the earlier start replaces the phone\'s',
      );
      await graph.timerPush.flush();
      expect(
        sentOfType('timer_state'),
        hasLength(1),
        reason: "S-6115 the wrist's own earlier start is not overwritten",
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6116 a phone snapshot leaves the phone\'s timer running on the wrist',
      () {
    test('S-6116 the phone starts an interval, then answers a snapshot request; '
        'the wrist\'s clock keeps running', () async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);

      await phoneState.startTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();
      expect(
        engine.timerFor(WatchTimerKind.elapsed)?.state,
        WatchTimerState.running,
        reason: "the fixture: the phone's start reached the wrist",
      );

      // The wrist asks for the phone's session; the answer is a snapshot.
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final snapshots = radio.ofType('session_snapshot');
      expect(
        snapshots,
        isNotEmpty,
        reason: 'the fixture: the phone answered with a snapshot',
      );
      for (final frame in snapshots) {
        await engine.applyMessage(frame);
      }

      expect(
        engine.timerFor(WatchTimerKind.elapsed)?.state,
        WatchTimerState.running,
        reason: 'S-6116 a snapshot of the phone\'s session does not stop the '
            'timer the phone started',
      );
      expect(failures, isEmpty);
    });

    test('S-6116 once the phone ends its interval the next snapshot says '
        'nothing about it, and the clock stops', () async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);

      await phoneState.startTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();

      expect(
        engine.timerFor(WatchTimerKind.elapsed)?.state,
        isNot(WatchTimerState.running),
        reason: 'S-6116 the phone finished the interval, so the wrist stops',
      );
    });
  });

  group('S-6117 a second interval started on the wrist', () {
    test('S-6117 the exercise grows by one and the new interval runs',
        () async {
      await fixture();
      // The fixture's second interval is used and finished by the phone: only
      // the first is left to the wrist.
      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(intervals, hasLength(2));
      await phoneState.deleteTimedEntry(_slotId, 1);
      await phoneState.startTimedEntry(_slotId, 0);
      await phoneState.finishTimedEntry(_slotId, 0);
      expect(
        phoneState
            .getTimedInstancesForEffort(_slotId)
            .map((i) => i.state),
        [TimedState.finished],
        reason: 'the fixture: the only interval is finished',
      );

      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final after = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        after.map((i) => i.state),
        [TimedState.finished, TimedState.active],
        reason: 'S-6117 a second interval was added and started',
      );
      expect(after.last.startedAtMs, _wristStart.millisecondsSinceEpoch);
      expect(failures, isEmpty);
    });

    test('S-6117 a timer the phone already logged adds nothing', () async {
      await fixture();
      await phoneState.deleteTimedEntry(_slotId, 1);
      await phoneState.startTimedEntry(_slotId, 0);
      final started = phoneState.getTimedInstancesForEffort(_slotId).single;
      await phoneState.finishTimedEntry(_slotId, 0);

      wristClock = DateTime.fromMillisecondsSinceEpoch(
        started.startedAtMs,
        isUtc: true,
      );
      await engine.startTimer(
        WatchTimerKind.elapsed,
        sessionExerciseId: _slotId,
      );
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      expect(
        phoneState.getTimedInstancesForEffort(_slotId),
        hasLength(1),
        reason: 'S-6117 an interval that began with this timer is not news',
      );
    });
  });

  group('S-6118 an adopted interval slot arrives with its first interval', () {
    test('S-6118 a timed slot starts with one interval, not "1 of 0"',
        () async {
      await engine.createSession(modality: null, exercises: [_slot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();

      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'S-6118 the phone has an interval for the wrist to start',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-1217x a stale wrist copy of a logged timer', () {
    // S-12171's fixture up to the phone's finish: the wrist's timer T is
    // adopted by interval 0, the phone logs it and opens the rest before
    // interval 1. `graph.timerPush` is not bound, so the wrist keeps running
    // T — the phone's clear never reached it.
    Future<void> loggedFixture() async {
      await fixture();
      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );
      expect(
        intervals.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: "the fixture: interval 0 runs on the wrist's start",
      );
      await phoneState.finishTimedEntry(_slotId, 0);
      await phoneState.recordRestStart(_slotId, 1);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: 'the fixture: the phone logged interval 0, interval 1 has '
            'not started',
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId)[1].startedAtMs,
        0,
        reason: 'the fixture: interval 1 has no start',
      );
      expect(
        phoneState
            .getEntryRests(_slotId)
            .firstWhere((rest) => rest.entryIndex == 1)
            .restEndMs,
        isNull,
        reason: 'the fixture: the rest before interval 1 is open',
      );
    }

    void expectStaleCopyIgnored(String id) {
      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: '$id the stale copy must not write interval 1',
      );
      expect(
        intervals[1].startedAtMs,
        0,
        reason: '$id interval 1 keeps no start',
      );
    }

    test('S-12171 the wrist pauses its stale copy', () async {
      await loggedFixture();

      await engine.pauseTimer(kind: WatchTimerKind.elapsed);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12171');

      expect(
        phoneState.inProgressWorkTimers(),
        isEmpty,
        reason: 'S-12171 no work timer is in progress',
      );
      expect(
        phoneState
            .getEntryRests(_slotId)
            .firstWhere((rest) => rest.entryIndex == 1)
            .restEndMs,
        isNull,
        reason: 'S-12171 the rest the phone opened stays open',
      );
      expect(failures, isEmpty);
    });

    test('S-12172 the phone app restarts while the wrist still runs T',
        () async {
      await loggedFixture();

      graph.timerAdoption.dispose();
      graph = await startGraph();

      await deliver(snapshot());
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12172');
      expect(failures, isEmpty);
    });

    test('S-12173 redelivery, snapshot and resume of the stale copy',
        () async {
      await loggedFixture();

      await engine.pauseTimer(kind: WatchTimerKind.elapsed);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12173');

      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12173');

      await deliver(snapshot(revision: 9));
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12173');

      await engine.resumeTimer(kind: WatchTimerKind.elapsed);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expectStaleCopyIgnored('S-12173');
      expect(failures, isEmpty);
    });

    test('S-12174 the wrist genuinely starts the next interval', () async {
      await loggedFixture();

      final nextStart = _now.subtract(const Duration(seconds: 5));
      await wristStartsElapsed(nextStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals[1].state,
        TimedState.active,
        reason: 'S-12174 a start the phone never logged adopts interval 1',
      );
      expect(
        intervals[1].startedAtMs,
        nextStart.millisecondsSinceEpoch,
        reason: "S-12174 interval 1 runs on the wrist's new start",
      );
      expect(failures, isEmpty);
    });
  });

  group('S-1263x a wrist pause or resume reaches the phone', () {
    // The phone's clock is real time, the wrist's is `wristClock`: a timer the
    // phone started carries a real start, so the wrist's pause stamps are
    // taken from the real clock too.
    // The Swift wrist stamps whole milliseconds; a microsecond stamp would not
    // survive the phone's millisecond rows and would read as an echo.
    DateTime wristStampAfter5s() => DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch + 5000,
    );

    TimedInstance phoneInterval() =>
        phoneState.getTimedInstancesForEffort(_slotId).first;

    WatchTimerRecord wristElapsed() =>
        engine.timerFor(WatchTimerKind.elapsed)!;

    /// Started on the PHONE: interval 0 runs, the push is flushed and applied
    /// on the wrist.
    Future<void> phoneStartsAndWristHolds() async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);
      await phoneState.startTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();
      expect(wristElapsed().state, WatchTimerState.running,
          reason: 'the fixture: the wrist holds the phone timer');
    }

    /// Started on the WRIST: adopted by interval 0.
    Future<void> wristStartsAndPhoneHolds() async {
      await fixture();
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      graph.timerPush.bindWorkoutState(phoneState);
      await graph.timerPush.flush();
      expect(phoneInterval().state, TimedState.active,
          reason: 'the fixture: the phone runs the wrist timer');
    }

    void expectPhoneEqualsWrist(String id, {required bool paused}) {
      final wrist = wristElapsed();
      final phone = phoneInterval();
      expect(phone.state, paused ? TimedState.paused : TimedState.active,
          reason: '$id the phone follows the wrist');
      expect(phone.pausedAtMs, wrist.pausedAt?.millisecondsSinceEpoch,
          reason: '$id same paused-at');
      expect(phone.totalPausedDurationMs, wrist.accumulatedPauseMs,
          reason: '$id same accumulated pause');
    }

    Future<void> wristPauses(DateTime at) async {
      wristClock = at;
      await engine.pauseTimer(kind: WatchTimerKind.elapsed);
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
    }

    Future<void> wristResumes(DateTime at) async {
      wristClock = at;
      await engine.resumeTimer(kind: WatchTimerKind.elapsed);
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
    }

    test('S-12631 a timer the phone started: the wrist pauses, the phone '
        'pauses, nothing is echoed', () async {
      await phoneStartsAndWristHolds();
      final sentBefore = sentOfType('timer_state').length;

      await wristPauses(wristStampAfter5s());
      expectPhoneEqualsWrist('S-12631', paused: true);
      expect(phoneInterval().pausedAtMs, isNotNull);

      await graph.timerPush.flush();
      expect(sentOfType('timer_state').length, sentBefore,
          reason: 'S-12631 the adopted pause is not sent back');
      expect(failures, isEmpty);
    });

    test('S-12632 then the wrist resumes after a 12 s pause: the phone runs '
        'again with the same accumulated pause, no echo', () async {
      await phoneStartsAndWristHolds();
      final pausedAt = wristStampAfter5s();
      await wristPauses(pausedAt);
      final sentBefore = sentOfType('timer_state').length;

      await wristResumes(pausedAt.add(const Duration(seconds: 12)));
      expectPhoneEqualsWrist('S-12632', paused: false);
      expect(phoneInterval().pausedAtMs, isNull);
      expect(phoneInterval().totalPausedDurationMs, closeTo(12000, 50));

      await graph.timerPush.flush();
      expect(sentOfType('timer_state').length, sentBefore,
          reason: 'S-12632 the adopted resume is not sent back');
      expect(failures, isEmpty);
    });

    test('S-12633 a timer the wrist started: pause then resume reach the '
        'phone the same way', () async {
      await wristStartsAndPhoneHolds();
      await wristPauses(_now.add(const Duration(seconds: 5)));
      expectPhoneEqualsWrist('S-12633 pause', paused: true);

      await wristResumes(_now.add(const Duration(seconds: 17)));
      expectPhoneEqualsWrist('S-12633 resume', paused: false);
      expect(phoneInterval().totalPausedDurationMs, 12000);
      expect(failures, isEmpty);
    });

    test('S-12635 the loop: wrist pause reaches the phone; the phone resumes '
        'and the wrist follows with an equal accumulated pause', () async {
      await phoneStartsAndWristHolds();
      await wristPauses(wristStampAfter5s());
      expectPhoneEqualsWrist('S-12635 first half', paused: true);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await phoneState.resumeTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();
      expect(wristElapsed().state, WatchTimerState.running);
      expect(wristElapsed().accumulatedPauseMs,
          phoneInterval().totalPausedDurationMs,
          reason: 'S-12635 both sides equal after the phone resumes');
      expect(failures, isEmpty);
    });

    /// The same, for a wrist countdown (round or hold) instead of the elapsed
    /// timer.
    Future<void> wristPausesCountdown(String kind, DateTime at) async {
      wristClock = at;
      await engine.pauseTimer(kind: kind);
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
    }

    Future<void> wristResumesCountdown(String kind, DateTime at) async {
      wristClock = at;
      await engine.resumeTimer(kind: kind);
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
    }

    /// A drill slot whose hold the phone tracks as a timed instance.
    const String holdSlotId = 'sx-plank';

    Map<String, Object?> holdSlot() => <String, Object?>{
      'sessionExerciseId': holdSlotId,
      'exerciseId': 'ex-plank',
      'name': 'Plank',
      'effortKind': 'drill',
      'capabilities': ['hold'],
    };

    test('S-12634 a wrist pause and resume of the round reach the phone '
        'round', () async {
      await seedExercise(
        repository,
        id: 'ex-burpee',
        name: 'Burpees',
        capabilities: ['rounds'],
      );
      await engine.createSession(modality: null, exercises: [_roundSlot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();

      wristClock = _wristStart;
      await engine.startTimer(
        WatchTimerKind.round,
        plannedDurationMs: 75000,
        sessionExerciseId: _roundSlotId,
      );
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getRoundsForEffort(_roundSlotId).single.state,
        RoundState.active,
        reason: 'the fixture: the phone runs the wrist round',
      );

      await wristPausesCountdown(
        WatchTimerKind.round,
        _now.add(const Duration(seconds: 5)),
      );
      final wristPaused = engine.timerFor(WatchTimerKind.round)!;
      final paused = phoneState.getRoundsForEffort(_roundSlotId).single;
      expect(
        paused.state,
        RoundState.paused,
        reason: 'S-12634 the phone round pauses with the wrist',
      );
      expect(
        paused.pausedAtMs,
        wristPaused.pausedAt!.millisecondsSinceEpoch,
        reason: "S-12634 with the wrist's pause stamp",
      );
      expect(
        paused.plannedDurationSecs,
        75,
        reason: 'S-12634 the pause leaves the planned length alone',
      );

      await wristResumesCountdown(
        WatchTimerKind.round,
        _now.add(const Duration(seconds: 17)),
      );
      final resumed = phoneState.getRoundsForEffort(_roundSlotId).single;
      expect(
        resumed.state,
        RoundState.active,
        reason: 'S-12634 the phone round runs with the wrist',
      );
      expect(
        resumed.pausedAtMs,
        isNull,
        reason: 'S-12634 the resume clears the paused-at',
      );
      expect(
        resumed.totalPausedDurationMs,
        12000,
        reason: 'S-12634 the resume banks the wrist pause',
      );
      expect(
        resumed.plannedDurationSecs,
        75,
        reason: 'S-12634 the resume leaves the planned length alone',
      );
      expect(failures, isEmpty);
    });

    test('S-12634 a wrist pause and resume of the hold reach the phone '
        'hold', () async {
      await seedExercise(
        repository,
        id: 'ex-plank',
        name: 'Plank',
        capabilities: ['hold'],
      );
      await engine.createSession(modality: null, exercises: [holdSlot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();

      wristClock = _wristStart;
      await engine.startTimer(
        WatchTimerKind.hold,
        sessionExerciseId: holdSlotId,
      );
      wristClock = _now;
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(holdSlotId).first.state,
        TimedState.active,
        reason: 'the fixture: the phone runs the wrist hold',
      );

      await wristPausesCountdown(
        WatchTimerKind.hold,
        _now.add(const Duration(seconds: 5)),
      );
      final wristPaused = engine.timerFor(WatchTimerKind.hold)!;
      final paused = phoneState
          .getTimedInstancesForEffort(holdSlotId)
          .first;
      expect(
        paused.state,
        TimedState.paused,
        reason: 'S-12634 the phone hold pauses with the wrist',
      );
      expect(
        paused.pausedAtMs,
        wristPaused.pausedAt!.millisecondsSinceEpoch,
        reason: "S-12634 with the wrist's pause stamp",
      );

      await wristResumesCountdown(
        WatchTimerKind.hold,
        _now.add(const Duration(seconds: 17)),
      );
      final resumed = phoneState
          .getTimedInstancesForEffort(holdSlotId)
          .first;
      expect(
        resumed.state,
        TimedState.active,
        reason: 'S-12634 the phone hold runs with the wrist',
      );
      expect(
        resumed.pausedAtMs,
        isNull,
        reason: 'S-12634 the resume clears the paused-at',
      );
      expect(
        resumed.totalPausedDurationMs,
        12000,
        reason: 'S-12634 the resume banks the wrist pause',
      );
      expect(failures, isEmpty);
    });

    test('S-12638 a graph restart adopts the same paused wrist timer without '
        'writing', () async {
      await wristStartsAndPhoneHolds();
      await wristPauses(_now.add(const Duration(seconds: 5)));
      final before = phoneInterval();
      expect(
        before.state,
        TimedState.paused,
        reason: 'the fixture: the wrist pause reached the phone',
      );
      final startedAtMs = before.startedAtMs;
      final pausedAtMs = before.pausedAtMs;
      final totalPausedMs = before.totalPausedDurationMs;
      final revisionBefore = phoneState.watchRefreshRevision;

      graph.timerAdoption.dispose();
      graph = await startGraph();
      graph.timerPush.bindWorkoutState(phoneState);
      await deliver(snapshot(revision: 9));
      await graph.timerAdoption.flush();

      final after = phoneInterval();
      expect(after.state, TimedState.paused, reason: 'S-12638 still paused');
      expect(after.startedAtMs, startedAtMs, reason: 'S-12638 same start');
      expect(after.pausedAtMs, pausedAtMs, reason: 'S-12638 same paused-at');
      expect(
        after.totalPausedDurationMs,
        totalPausedMs,
        reason: 'S-12638 same accumulated pause',
      );
      expect(
        phoneState.watchRefreshRevision,
        revisionBefore,
        reason: 'S-12638 no write, so no screen resync',
      );
    });

    test('S-12638 a restart does not regress a phone resume onto the wrist '
        'older paused copy', () async {
      await wristStartsAndPhoneHolds();
      await wristPauses(_now.add(const Duration(seconds: 5)));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await phoneState.resumeTimedEntry(_slotId, 0);
      final resumed = phoneInterval();
      expect(
        resumed.state,
        TimedState.active,
        reason: 'the fixture: the phone resumed',
      );
      final accumulated = resumed.totalPausedDurationMs;
      final revisionBefore = phoneState.watchRefreshRevision;

      graph.timerAdoption.dispose();
      graph = await startGraph();
      graph.timerPush.bindWorkoutState(phoneState);
      await deliver(snapshot(revision: 9));
      await graph.timerAdoption.flush();

      final after = phoneInterval();
      expect(
        after.state,
        TimedState.active,
        reason: "S-12638 the wrist's older paused copy does not stop it",
      );
      expect(
        after.pausedAtMs,
        isNull,
        reason: "S-12638 the phone's resume is not undone",
      );
      expect(
        after.totalPausedDurationMs,
        accumulated,
        reason: "S-12638 the phone's larger accumulated pause is kept",
      );
      expect(
        phoneState.watchRefreshRevision,
        revisionBefore,
        reason: 'S-12638 nothing written, so no screen resync',
      );
    });

    test('S-12639 a wrist pause or resume never rewrites a finished '
        'interval', () async {
      await wristStartsAndPhoneHolds();
      await phoneState.finishTimedEntry(_slotId, 0);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: 'the fixture: interval 0 finished, interval 1 unstarted',
      );

      await wristPauses(_now.add(const Duration(seconds: 5)));
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: 'S-12639 the wrist pause never rewrites a finished interval',
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId)[1].startedAtMs,
        0,
        reason: 'S-12639 the wrist pause never starts the next interval',
      );

      await wristResumes(_now.add(const Duration(seconds: 17)));
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: 'S-12639 the wrist resume never rewrites a finished interval',
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId)[1].startedAtMs,
        0,
        reason: 'S-12639 the wrist resume never starts the next interval',
      );

      await wristPauses(_now.add(const Duration(seconds: 20)));
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason: 'S-12639 a second wrist pause never rewrites it either',
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId)[1].startedAtMs,
        0,
        reason: 'S-12639 and never starts the next interval',
      );
      expect(failures, isEmpty);
    });

    test('S-12640 a repeated wrist frame bumps the refresh revision once, '
        'not again', () async {
      await wristStartsAndPhoneHolds();
      final revisionBefore = phoneState.watchRefreshRevision;

      await wristPauses(_now.add(const Duration(seconds: 5)));
      final rev1 = phoneState.watchRefreshRevision;
      expect(
        rev1,
        greaterThan(revisionBefore),
        reason: 'S-12640 the pause writes once',
      );
      expect(
        phoneInterval().state,
        TimedState.paused,
        reason: 'S-12640 the pause reached the phone',
      );

      // The same pause frame again, and an unrelated snapshot change: neither
      // is a new timer, so neither writes.
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      await deliver(snapshot(revision: 9));
      await graph.timerAdoption.flush();
      expect(
        phoneState.watchRefreshRevision,
        rev1,
        reason: 'S-12640 a repeated frame is not applied twice',
      );

      await wristResumes(_now.add(const Duration(seconds: 17)));
      expect(
        phoneState.watchRefreshRevision,
        rev1 + 1,
        reason: 'S-12640 the resume writes once (pausedAtMs → running)',
      );
      expect(
        phoneInterval().state,
        TimedState.active,
        reason: 'S-12640 the phone runs the wrist timer again',
      );

      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.watchRefreshRevision,
        rev1 + 1,
        reason: 'S-12640 the redelivered resume is not applied twice',
      );
      expect(
        phoneInterval().state,
        TimedState.active,
        reason: 'the last assertion: still running',
      );
      expect(failures, isEmpty);
    });

    test('S-12636 both pause at once, the wrist 3 s earlier: the phone keeps '
        'its own stamp', () async {
      await phoneStartsAndWristHolds();
      // The phone pauses first: its frame is SENT but not yet applied on the
      // wrist, which has not seen it.
      await phoneState.pauseTimedEntry(_slotId, 0);
      final tP = phoneInterval().pausedAtMs!;
      await graph.timerPush.flush();

      // The wrist pauses itself 3 s EARLIER than the phone; its own frame is
      // delivered to the phone.
      await wristPauses(
        DateTime.fromMillisecondsSinceEpoch(tP)
            .add(const Duration(seconds: -3)),
      );
      expect(
        phoneInterval().state,
        TimedState.paused,
        reason: 'S-12636 the phone stays paused',
      );
      expect(
        phoneInterval().pausedAtMs,
        tP,
        reason: "S-12636 the phone keeps its own stamp, not the wrist's "
            'earlier one (D-5)',
      );

      // The wrist pause is adopted (refused), so nothing new is sent back.
      final sentBefore = sentOfType('timer_state').length;
      await graph.timerPush.flush();
      expect(
        sentOfType('timer_state').length,
        sentBefore,
        reason: 'S-12636 the refused wrist pause is not echoed',
      );

      // Then the phone's pause frame reaches the wrist: both converge on the
      // phone's stamp.
      await applyPhoneTimers();
      expect(
        wristElapsed().state,
        WatchTimerState.paused,
        reason: 'S-12636 the wrist ends paused with the phone',
      );
      expect(
        wristElapsed().pausedAt!.millisecondsSinceEpoch,
        tP,
        reason: "S-12636 the wrist row ends on the phone's stamp (D-5)",
      );
      expect(failures, isEmpty);
    });

    test('S-12636 both pause at once, the wrist 3 s later: the phone keeps '
        'its own stamp', () async {
      await phoneStartsAndWristHolds();
      // The phone pauses first: its frame is SENT but not yet applied on the
      // wrist, which has not seen it.
      await phoneState.pauseTimedEntry(_slotId, 0);
      final tP = phoneInterval().pausedAtMs!;
      await graph.timerPush.flush();

      // The wrist pauses itself 3 s LATER than the phone; its own frame is
      // delivered to the phone.
      await wristPauses(
        DateTime.fromMillisecondsSinceEpoch(tP).add(const Duration(seconds: 3)),
      );
      expect(
        phoneInterval().state,
        TimedState.paused,
        reason: 'S-12636 the phone stays paused',
      );
      expect(
        phoneInterval().pausedAtMs,
        tP,
        reason: "S-12636 the phone keeps its own stamp, not the wrist's "
            'later one (D-5)',
      );

      final sentBefore = sentOfType('timer_state').length;
      await graph.timerPush.flush();
      expect(
        sentOfType('timer_state').length,
        sentBefore,
        reason: 'S-12636 the refused wrist pause is not echoed',
      );

      await applyPhoneTimers();
      expect(
        wristElapsed().state,
        WatchTimerState.paused,
        reason: 'S-12636 the wrist ends paused with the phone',
      );
      expect(
        wristElapsed().pausedAt!.millisecondsSinceEpoch,
        tP,
        reason: "S-12636 the wrist row ends on the phone's stamp (D-5)",
      );
      expect(failures, isEmpty);
    });

    test('S-12637 both resume at once: the phone takes the wrist\u2019s '
        'larger accumulated pause', () async {
      await phoneStartsAndWristHolds();
      // The phone pauses, its frame is flushed AND applied on the wrist, so
      // the wrist holds the phone's pause.
      await phoneState.pauseTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await applyPhoneTimers();
      final tP0 = phoneInterval().pausedAtMs!;

      // The phone resumes first: its frame is SENT but not yet applied on
      // the wrist, which has not seen it.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await phoneState.resumeTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      // The wrist, not having seen the phone's resume, resumes 1 s later —
      // its frame carries accumulatedPauseMs 1000, larger than the phone's
      // (about 20). The later resume wins on the phone (D-5 / D-2a).
      await wristResumes(
        DateTime.fromMillisecondsSinceEpoch(tP0)
            .add(const Duration(seconds: 1)),
      );
      expect(
        phoneInterval().state,
        TimedState.active,
        reason: 'S-12637 the phone runs with the wrist resume',
      );
      expect(
        phoneInterval().pausedAtMs,
        isNull,
        reason: 'S-12637 the resume clears the paused-at',
      );
      expect(
        phoneInterval().totalPausedDurationMs,
        1000,
        reason: "S-12637 the wrist's larger accumulated pause wins (D-2a)",
      );

      // Known gap (plan Q1): after the phone's own resume frame is applied on
      // the wrist, the wrist shows the phone's earlier resume, so the two
      // clocks differ by the gap between the two presses (accepted until
      // either side next pauses). Only the phone side is asserted here.
      await engine.applyMessage(sentOfType('timer_state').last);
      expect(failures, isEmpty);
    });
  });
}
