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
      // session's rows pile up under it and the new session's interval must be
      // the only unfinished one.
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
        [TimedState.finished, TimedState.notStarted],
        reason: "the fixture: the old session's interval is history, the new "
            'one has not started',
      );

      // The identical timer map, for the new session: the memo that skipped the
      // old session's copy must not skip this one.
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.finished, TimedState.active],
        reason: 'S-6113 the memo belongs to a session, not to a timer',
      );
      expect(
        intervals.last.startedAtMs,
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
}
