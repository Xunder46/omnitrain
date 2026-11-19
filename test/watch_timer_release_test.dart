// An interval the phone took from the wire is given back when the wrist stops
// or replaces its timer (plan 244, D-24401/D-24402/D-24403).
//
// Plan: `docs/plans/2026-11-19-244-watch-hold-timer-never-outlives-its-stop-plan/
// 2026-11-19-244-watch-hold-timer-never-outlives-its-stop-plan.md`.
// Scenario mapping (the full graph: the shipping wiring over a fake radio, the
// real wrist engine over an in-memory store):
//   S-24411 the repro: the wrist stops its timer and nobody logged anything
//          → `S-24411 ...`
//   S-24412 the wire replaces the timer with another slot's → `S-24412 ...`
//   S-24413 control, the entry first: the logged interval stands → `S-24413 ...`
//   S-24414 control, the stop first: the entry fills the released interval
//          → `S-24414 ...`
//   S-24415 control, a pause and resume of the same interval → `S-24415 ...`
//   S-24416 control, the phone's own interval is never given back
//          → `S-24416 ...`
//   S-24417 a round the wrist stops with no entry → `S-24417 ...`
//   S-24418 the diagnostics lines → `S-24418 ...`
//
// The harness is the one `test/watch_timer_adoption_test.dart` builds: plain
// `test()` only, no `testWidgets`, no FakeAsync; every pass is closed by
// `flush()` rather than by waiting.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
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

/// The one timed slot the fixture puts in the ladder, and its effort id on the
/// phone (D-3: the wrist's slot id IS the phone's effort id).
const String _slotId = 'sx-run';

/// A round slot, for the wrist round the test stops.
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
  Future<WatchSyncGraph> startGraph({DiagnosticsLog? diagnostics}) async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
      diagnostics: diagnostics,
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
  /// a start it has no way to nudge). The harness builds the graph without a
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

  /// Stops the wrist's timer of [kind] at [at] — a clock later than its start —
  /// and hands the phone the stop frame it emitted.
  Future<void> wristStops(String kind, DateTime at) async {
    wristClock = at;
    await engine.stopTimer(kind: kind);
    wristClock = _now;
    await deliver(lastTimerFrame());
    await graph.timerAdoption.flush();
  }

  /// Pauses the wrist's `elapsed` timer at [at] and delivers the frame.
  Future<void> wristPauses(DateTime at) async {
    wristClock = at;
    await engine.pauseTimer(kind: WatchTimerKind.elapsed);
    wristClock = _now;
    await deliver(lastTimerFrame());
    await graph.timerAdoption.flush();
  }

  /// Resumes the wrist's `elapsed` timer at [at] and delivers the frame.
  Future<void> wristResumes(DateTime at) async {
    wristClock = at;
    await engine.resumeTimer(kind: WatchTimerKind.elapsed);
    wristClock = _now;
    await deliver(lastTimerFrame());
    await graph.timerAdoption.flush();
  }

  /// The wrist logs the timed entry it measured over [startedAt]..[endedAt]
  /// for the slot, and hands the phone the `observations_up` frame it emitted.
  Future<void> wristLogsTimedEntry(DateTime startedAt, DateTime endedAt) async {
    final entryId = 'sx-run-entry-${startedAt.millisecondsSinceEpoch}';
    await engine.appendObservation(<String, Object?>{
      'entryId': entryId,
      'eventId': entryId,
      'kind': 'timed',
      'loggedAt': utcIso(endedAt),
      'sessionExerciseId': _slotId,
      'exerciseId': 'ex-run',
      'startedAt': utcIso(startedAt),
      'endedAt': utcIso(endedAt),
      'distanceMeters': 1200.0,
    });
    final observed = wristFrames.last;
    expect(
      observed['type'],
      'observations_up',
      reason: 'the fixture: the wrist emits the entry it logged',
    );
    await radio.fromWrist(observed);
    await _settle();
  }

  /// Applies the phone's timer frames to the wrist engine, in the order they
  /// were sent, the way the watch app applies each frame it receives.
  Future<void> applyPhoneTimers() async {
    for (final frame in radio.ofType('timer_state')) {
      await engine.applyMessage(frame);
    }
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

  group('S-2441x the wrist stopped or replaced its timer', () {
    test('S-24411 the wrist stops its timer with no entry: the interval is '
        'given back', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.first.state,
        TimedState.active,
        reason: 'the fixture: the wrist timer adopted interval 0',
      );
      expect(
        intervals.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: "the fixture: on the wrist's start",
      );

      await wristStops(WatchTimerKind.elapsed, _now);

      final after = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        after.map((i) => i.state),
        [TimedState.notStarted, TimedState.notStarted],
        reason:
            'S-24411 the stop alone gives the interval back: the wrist '
            'logged nothing, so the stop does not say it was finished',
      );
      expect(
        after.first.startedAtMs,
        0,
        reason: 'S-24411 the released interval keeps no start',
      );
      expect(failures, isEmpty);
    });

    test('S-24412 the wire replaces the timer with another slot\'s: the first '
        'interval is given back, the new one runs', () async {
      await seedExercise(
        repository,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['time', 'distance'],
      );
      const rowSlotId = 'sx-row';
      final rowSlot = <String, Object?>{
        'sessionExerciseId': rowSlotId,
        'exerciseId': 'ex-row',
        'name': 'Row',
        'effortKind': 'timed',
        'capabilities': ['time', 'distance'],
      };

      await engine.createSession(modality: null, exercises: [_slot(), rowSlot]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        phoneState.currentSession?.id,
        _sessionId,
        reason: "the fixture: the phone's own session is the wrist's",
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: slot A holds its first interval',
      );
      expect(
        phoneState.getTimedInstancesForEffort(rowSlotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: slot B holds its first interval',
      );

      final firstTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: slot A runs on the wrist timer',
      );

      // Without stopping the first timer, the wrist starts the next one for
      // slot B: `startTimer` replaces the one `elapsed` timer the wire had.
      final secondTimer = await wristStartsElapsed(
        _wristStart.add(const Duration(seconds: 30)),
        slot: rowSlotId,
      );
      final frameTimers = _asObject(_payload(lastTimerFrame())['timers']);
      expect(
        _asObject(frameTimers[WatchTimerKind.elapsed])['sessionExerciseId'],
        rowSlotId,
        reason: 'the fixture: the wire names slot B alone now',
      );
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();

      final slotA = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        slotA.first.state,
        TimedState.notStarted,
        reason: 'S-24412 the interval the wire no longer names is given back',
      );
      expect(
        slotA.first.startedAtMs,
        0,
        reason: 'S-24412 the released interval keeps no start',
      );
      final slotB = phoneState.getTimedInstancesForEffort(rowSlotId);
      expect(
        slotB.first.state,
        TimedState.active,
        reason: 'S-24412 slot B runs on the new timer',
      );
      expect(
        slotB.first.startedAtMs,
        secondTimer.startedAt.millisecondsSinceEpoch,
        reason: "S-24412 on the new timer's start",
      );
      expect(
        firstTimer.startedAt.isBefore(secondTimer.startedAt),
        isTrue,
        reason: 'the fixture: the two starts are distinct intervals',
      );
      expect(failures, isEmpty);
    });

    test('S-24413 control, the entry first: the logged interval stands and '
        'the stop changes nothing', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      final startedAt = wristTimer.startedAt;
      final endedAt = startedAt.add(const Duration(minutes: 5));
      await wristLogsTimedEntry(startedAt, endedAt);

      var intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals,
        hasLength(2),
        reason: 'the fixture: the entry filled interval 0, none appended',
      );
      expect(
        intervals.first.state,
        TimedState.finished,
        reason: 'the fixture: the wrist entry finished interval 0',
      );
      expect(
        intervals.first.finishedAtMs,
        endedAt.millisecondsSinceEpoch,
        reason: "the fixture: the entry's own end stamps the interval",
      );
      expect(
        intervals.first.actualDurationSecs,
        300,
        reason: "the fixture: the entry's own duration stands",
      );
      expect(
        intervals[1].state,
        TimedState.notStarted,
        reason: 'the fixture: interval 1 untouched',
      );

      await wristStops(
        WatchTimerKind.elapsed,
        _now.add(const Duration(minutes: 6)),
      );

      intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals,
        hasLength(2),
        reason: 'S-24413 exactly two intervals, the stop added none',
      );
      expect(
        intervals.map((i) => i.state),
        [TimedState.finished, TimedState.notStarted],
        reason:
            'S-24413 the stop changed nothing: the interval the wire took '
            'was already logged, and a finished one is never released',
      );
      expect(
        intervals.first.finishedAtMs,
        endedAt.millisecondsSinceEpoch,
        reason: "S-24413 the entry's stamps stand",
      );
      expect(intervals.first.actualDurationSecs, 300);
      expect(failures, isEmpty);
    });

    test('S-24414 control, the stop first: the released interval is filled '
        'by the entry, none appended', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      await wristStops(WatchTimerKind.elapsed, _now);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted, TimedState.notStarted],
        reason: 'the fixture: the stop gave the interval back',
      );

      final startedAt = wristTimer.startedAt;
      final endedAt = startedAt.add(const Duration(minutes: 5));
      await wristLogsTimedEntry(startedAt, endedAt);

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals,
        hasLength(2),
        reason:
            'S-24414 still two intervals: the entry filled the released '
            'one, it did not append a third',
      );
      expect(
        intervals.first.state,
        TimedState.finished,
        reason: 'S-24414 the entry filled the first unfinished interval',
      );
      expect(
        intervals.first.finishedAtMs,
        endedAt.millisecondsSinceEpoch,
        reason: "S-24414 the entry's own end stamps the interval",
      );
      expect(
        intervals.first.actualDurationSecs,
        300,
        reason: "S-24414 the entry's own duration stands",
      );
      expect(
        intervals[1].state,
        TimedState.notStarted,
        reason: 'S-24414 interval 1 untouched',
      );
      expect(failures, isEmpty);
    });

    test('S-24415 control, a pause and resume of the same interval release '
        'nothing', () async {
      await fixture();

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      final pausedAt = _now.add(const Duration(seconds: 5));
      final paused = await engine.pauseTimer(kind: WatchTimerKind.elapsed);
      wristClock = _now;
      expect(
        paused?.pausedAt,
        isNotNull,
        reason: 'the fixture: the wrist paused its timer',
      );
      await wristPauses(pausedAt);
      var intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.paused, TimedState.notStarted],
        reason: 'S-24415 the same interval pauses; nothing is given back',
      );
      expect(
        intervals.first.pausedAtMs,
        paused!.pausedAt!.millisecondsSinceEpoch,
        reason: "S-24415 with the wrist's pause stamp",
      );
      expect(
        intervals.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'S-24415 the same start stands',
      );

      await wristResumes(pausedAt.add(const Duration(seconds: 12)));
      intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.active, TimedState.notStarted],
        reason: 'S-24415 the resume runs the same interval again',
      );
      expect(
        intervals.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'S-24415 still the same interval, never released',
      );
      expect(
        intervals.first.pausedAtMs,
        isNull,
        reason: 'S-24415 the resume clears the paused-at',
      );
      expect(failures, isEmpty);
    });

    test('S-24416 control, the phone\'s own earlier interval is never given '
        'back', () async {
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);

      // The phone's own start, forty seconds before the wire timer's.
      final phoneStartMs = _wristStart.millisecondsSinceEpoch;
      await phoneState.startTimedEntry(_slotId, 0);
      final started = phoneState.getTimedInstancesForEffort(_slotId).first;
      await repository.updateTimedInstance(
        started.copyWith(startedAtMs: phoneStartMs, updatedAtMs: phoneStartMs),
      );
      await phoneState.refreshEfforts([_slotId]);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        phoneStartMs,
        reason: 'the fixture: the phone counts from its own earlier start',
      );
      await graph.timerPush.flush();
      await applyPhoneTimers();
      expect(
        engine
            .timerFor(WatchTimerKind.elapsed)!
            .startedAt
            .millisecondsSinceEpoch,
        phoneStartMs,
        reason: "the fixture: the wrist holds the phone's own start",
      );

      // The wrist starts its own timer later: the wire start is later than
      // the phone's, so the earlier-start-wins rule refuses it.
      final wristTimer = await wristStartsElapsed(_now);
      expect(
        wristTimer.startedAt.isAfter(
          DateTime.fromMillisecondsSinceEpoch(phoneStartMs, isUtc: true),
        ),
        isTrue,
        reason: 'the fixture: the wire start is the later one',
      );
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        phoneStartMs,
        reason: 'S-24416 the wire start is refused; the phone start stands',
      );

      // The wrist stops the timer it started: nothing it took is running here.
      await wristStops(
        WatchTimerKind.elapsed,
        _now.add(const Duration(seconds: 30)),
      );

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.first.state,
        TimedState.active,
        reason: "S-24416 the phone's own interval stays active",
      );
      expect(
        intervals.first.startedAtMs,
        phoneStartMs,
        reason: 'S-24416 at its own start',
      );
      expect(failures, isEmpty);
    });

    test('S-24417 a round the wrist stops with no entry goes back to not '
        'started', () async {
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
      expect(
        phoneState.getRoundsForEffort(_roundSlotId).single.state,
        RoundState.notStarted,
        reason: 'the fixture: the round has not started',
      );

      wristClock = _wristStart;
      final wristTimer = await engine.startTimer(
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
        reason: 'the fixture: the wrist round started the phone round',
      );

      await wristStops(WatchTimerKind.round, _now);

      final round = phoneState.getRoundsForEffort(_roundSlotId).single;
      expect(
        round.state,
        RoundState.notStarted,
        reason: 'S-24417 the stopped round with no entry is given back',
      );
      expect(
        round.startedAtMs,
        0,
        reason: 'S-24417 the released round keeps no start',
      );
      expect(
        round.startedAtMs,
        isNot(wristTimer.startedAt.millisecondsSinceEpoch),
        reason: 'S-24417 the wrist start is gone',
      );
      expect(failures, isEmpty);
    });

    test('S-24418 the diagnostics lines: the adoption, the release and the '
        'entry, in order, with no names', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // The S-24411 flow: adopt, stop with no entry, the interval given back.
      await fixture();
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );
      await wristStops(WatchTimerKind.elapsed, _now);
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted, TimedState.notStarted],
        reason: 'the fixture: the stop gave the interval back',
      );

      // A second wrist timer adopts the released interval again ...
      final secondTimer = await wristStartsElapsed(
        _now.add(const Duration(seconds: 5)),
      );
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: the second timer adopted interval 0',
      );

      // ... and the wrist logs the entry for it, so the importer places it.
      final startedAt = secondTimer.startedAt;
      final endedAt = startedAt.add(const Duration(minutes: 5));
      await wristLogsTimedEntry(startedAt, endedAt);

      final events = log.events();
      final adopted = events
          .where((event) => event.kind == 'timer_adopted')
          .toList();
      final released = events
          .where((event) => event.kind == 'timer_released')
          .toList();
      final placed = events
          .where((event) => event.kind == 'entry_placed')
          .toList();

      expect(adopted, isNotEmpty, reason: 'S-24418 the adoption was recorded');
      expect(
        adopted.first.detail,
        allOf(contains('kind=elapsed'), contains('slot=$_slotId')),
        reason: 'S-24418 the timer_adopted line names the kind and the slot',
      );
      expect(
        released,
        hasLength(1),
        reason: 'S-24418 the one release was recorded',
      );
      expect(
        released.single.detail,
        allOf(contains('reason=stopped'), contains('reset=true')),
        reason: 'S-24418 the timer_released line names why and what it reset',
      );
      expect(
        placed,
        isNotEmpty,
        reason: 'S-24418 the importer placed the entry',
      );
      expect(
        placed.first.detail,
        allOf(contains('kind=timed'), contains('how=')),
        reason: 'S-24418 the entry_placed line names the kind and the how',
      );

      final adoptedIndex = events.indexOf(adopted.first);
      final releasedIndex = events.indexOf(released.single);
      final placedIndex = events.indexOf(placed.first);
      expect(
        adoptedIndex < releasedIndex,
        isTrue,
        reason: 'S-24418 the adoption line is before the release line',
      );
      expect(
        releasedIndex < placedIndex,
        isTrue,
        reason: 'S-24418 the release line is before the entry line',
      );

      for (final event in events) {
        expect(
          event.detail,
          isNot(contains('Run')),
          reason: 'S-24418 the log carries ids, never a name',
        );
      }
      expect(failures, isEmpty);
    });
  });

  group('S-2442x the boundaries and the bookkeeping the first round missed', () {
    test('S-24419 a refused adoption is never noted or given back', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // The S-24416 flow: the phone counts from its own earlier start.
      await fixture();
      graph.timerPush.bindWorkoutState(phoneState);
      final phoneStartMs = _wristStart.millisecondsSinceEpoch;
      await phoneState.startTimedEntry(_slotId, 0);
      final started = phoneState.getTimedInstancesForEffort(_slotId).first;
      await repository.updateTimedInstance(
        started.copyWith(startedAtMs: phoneStartMs, updatedAtMs: phoneStartMs),
      );
      await phoneState.refreshEfforts([_slotId]);
      await graph.timerPush.flush();
      await applyPhoneTimers();
      expect(
        engine
            .timerFor(WatchTimerKind.elapsed)!
            .startedAt
            .millisecondsSinceEpoch,
        phoneStartMs,
        reason: "the fixture: the wrist holds the phone's own start",
      );

      // The wrist starts its own timer at now: the wire start is later than
      // the phone's, so the earlier-start-wins rule refuses it.
      await wristStartsElapsed(_now);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.startedAtMs,
        phoneStartMs,
        reason: 'S-24419 the wire start is refused; the phone start stands',
      );

      // The wrist stops the timer it started: nothing it took is running here.
      await wristStops(
        WatchTimerKind.elapsed,
        _now.add(const Duration(seconds: 30)),
      );
      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.first.state,
        TimedState.active,
        reason: "S-24419 the phone's own interval stays active",
      );
      expect(
        intervals.first.startedAtMs,
        phoneStartMs,
        reason: 'S-24419 at its own start',
      );

      final events = log.events();
      expect(
        events.where((event) => event.kind == 'timer_adopted'),
        isEmpty,
        reason: 'S-24419 a timer the state refused is never noted as adopted',
      );
      expect(
        events.where((event) => event.kind == 'timer_released'),
        isEmpty,
        reason: 'S-24419 a timer the phone never took is never given back',
      );
      expect(failures, isEmpty);
    });

    test('S-24420 the wire names another slot\'s timer with the same start: '
        'the held slot is given back, the named slot runs', () async {
      await seedExercise(
        repository,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['time', 'distance'],
      );
      const rowSlotId = 'sx-row';
      final rowSlot = <String, Object?>{
        'sessionExerciseId': rowSlotId,
        'exerciseId': 'ex-row',
        'name': 'Row',
        'effortKind': 'timed',
        'capabilities': ['time', 'distance'],
      };

      await engine.createSession(modality: null, exercises: [_slot(), rowSlot]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: slot A holds its first interval',
      );
      expect(
        phoneState.getTimedInstancesForEffort(rowSlotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: slot B holds its first interval',
      );

      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: slot A runs on the wrist timer',
      );

      // The same timer, renamed to slot B: the same start, another slot.
      final renamed = timerFrameWith(const {'sessionExerciseId': rowSlotId});
      final elapsed = _asObject(
        _asObject(_payload(renamed)['timers'])[WatchTimerKind.elapsed],
      );
      expect(
        elapsed['sessionExerciseId'],
        rowSlotId,
        reason: 'the fixture: the wire names slot B now',
      );
      expect(
        elapsed['startedAt'],
        utcIso(wristTimer.startedAt),
        reason: 'the fixture: on the very same start',
      );
      await deliver(renamed);
      await graph.timerAdoption.flush();

      final slotA = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        slotA.first.state,
        TimedState.notStarted,
        reason:
            'S-24420 the slot the wire no longer names is given back, even '
            'though the start is the same',
      );
      expect(
        slotA.first.startedAtMs,
        0,
        reason: 'S-24420 the released interval keeps no start',
      );
      final slotB = phoneState.getTimedInstancesForEffort(rowSlotId);
      expect(
        slotB.first.state,
        TimedState.active,
        reason: 'S-24420 the slot the wire names now runs',
      );
      expect(
        slotB.first.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'S-24420 on the same start it was given',
      );
      expect(failures, isEmpty);
    });

    test('S-24421a a frame for the same slot 1000 ms off the held start is '
        'the same interval: nothing moves', () async {
      await fixture();
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      await deliver(
        timerFrameWith({
          'startedAt': utcIso(
            _wristStart.add(const Duration(milliseconds: 1000)),
          ),
        }),
      );
      await graph.timerAdoption.flush();

      final interval = phoneState.getTimedInstancesForEffort(_slotId).first;
      expect(
        interval.state,
        TimedState.active,
        reason: 'S-24421a 1000 ms is the same interval: not given back',
      );
      expect(
        interval.startedAtMs,
        _wristStart.millisecondsSinceEpoch,
        reason: "S-24421a still on the wrist's own start, not re-adopted",
      );
      expect(failures, isEmpty);
    });

    test('S-24421b a later start for the same slot is the wrist\'s next '
        'interval: the held interval is not given back and the new clock is '
        'not taken (S-6323)', () async {
      await fixture();
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      await deliver(
        timerFrameWith({
          'startedAt': utcIso(_wristStart.add(const Duration(seconds: 60))),
        }),
      );
      await graph.timerAdoption.flush();

      final intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.active, TimedState.notStarted],
        reason: 'S-24421b the held interval keeps running, nothing is taken',
      );
      expect(
        intervals.first.startedAtMs,
        _wristStart.millisecondsSinceEpoch,
        reason: 'S-24421b on the held start, not on the later one',
      );
      expect(failures, isEmpty);
    });

    test('S-24422 the adoption memory does not leak across sessions', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // The S-6113 flow: one interval to begin with, because an effort id IS
      // the slot id and the old session's rows are dropped below.
      await engine.createSession(modality: null, exercises: [_slot()]);
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        phoneState.currentSession?.id,
        _sessionId,
        reason: "the fixture: the phone's own session is the wrist's first",
      );
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).map((i) => i.state),
        [TimedState.notStarted],
        reason: 'the fixture: one unstarted interval',
      );

      // The wrist starts its timer and the phone adopts it; it is never
      // stopped.
      await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: the first session adopted the timer',
      );

      // The wrist ends its session and starts another with the same slot; the
      // phone ends its copy first, so the new snapshot is a fresh adoption.
      await phoneState.endSession();
      await repository.deleteTimedInstancesForEffort(_slotId);
      await phoneState.refreshEfforts([_slotId]);
      await engine.finishSession();
      wristSessionId = 's-w-adopt-2';
      await engine.createSession(modality: null, exercises: [_slot()]);
      await deliver(engine.sessionSnapshot()!);
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
        reason:
            "the fixture: the new session's intervals are all not started, "
            'the mirror holds no running timer for it',
      );

      final events = log.events();
      expect(
        events.where((event) => event.kind == 'timer_released'),
        isEmpty,
        reason:
            'S-24422 the first session\'s adoption is dropped at the switch, '
            'never released into the second',
      );
      expect(failures, isEmpty);
    });

    test('S-24423a an entry that fills the adopted interval is noted as '
        'filled', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // The S-24413 flow: the start adopted, the entry arrives, the interval
      // is filled.
      await fixture();
      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );

      final startedAt = wristTimer.startedAt;
      final endedAt = startedAt.add(const Duration(minutes: 5));
      await wristLogsTimedEntry(startedAt, endedAt);

      final placed = log
          .events()
          .where((event) => event.kind == 'entry_placed')
          .toList();
      expect(placed, isNotEmpty, reason: 'S-24423a the importer placed it');
      expect(
        placed.first.detail,
        allOf(contains('kind=timed'), contains('how=filled')),
        reason:
            'S-24423a the entry took the phone\'s unfinished interval, and '
            'the label says so',
      );
      expect(failures, isEmpty);
    });

    test('S-24423b an entry with no unfinished interval left is noted as '
        'appended', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // Two intervals, both finished by earlier wrist entries.
      await fixture();
      final firstStart = _wristStart;
      await wristLogsTimedEntry(
        firstStart,
        firstStart.add(const Duration(minutes: 5)),
      );
      await wristLogsTimedEntry(
        firstStart.add(const Duration(minutes: 10)),
        firstStart.add(const Duration(minutes: 15)),
      );
      var intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals.map((i) => i.state),
        [TimedState.finished, TimedState.finished],
        reason: 'the fixture: both intervals are finished by the entries',
      );

      // A third wrist entry with a new start: nothing is left to fill.
      final thirdStart = firstStart.add(const Duration(minutes: 20));
      await wristLogsTimedEntry(
        thirdStart,
        thirdStart.add(const Duration(minutes: 5)),
      );
      intervals = phoneState.getTimedInstancesForEffort(_slotId);
      expect(
        intervals,
        hasLength(3),
        reason: 'the fixture: the third entry appended its own interval',
      );

      final placed = log
          .events()
          .where((event) => event.kind == 'entry_placed')
          .toList();
      expect(placed, isNotEmpty, reason: 'S-24423b the importer placed it');
      expect(
        placed.last.detail,
        allOf(contains('kind=timed'), contains('how=appended')),
        reason:
            'S-24423b no unfinished interval was left, so the entry added '
            'its own, and the label says so',
      );
      expect(failures, isEmpty);
    });

    test('S-24423c an interval the phone logged itself first is noted as '
        'already logged', () async {
      final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
      graph.timerAdoption.dispose();
      graph = await startGraph(diagnostics: log);

      // The S-6341 flow: the wrist timer adopted, then the phone logs the
      // interval itself.
      await fixture();
      final wristTimer = await wristStartsElapsed(_wristStart);
      await deliver(lastTimerFrame());
      await graph.timerAdoption.flush();
      expect(
        phoneState.getTimedInstancesForEffort(_slotId).first.state,
        TimedState.active,
        reason: 'the fixture: interval 0 runs on the wrist start',
      );
      await phoneState.finishTimedEntry(_slotId, 0);
      final logged = phoneState.getTimedInstancesForEffort(_slotId).first;
      expect(
        logged.state,
        TimedState.finished,
        reason: 'the fixture: the phone logged the interval itself',
      );
      expect(
        logged.startedAtMs,
        wristTimer.startedAt.millisecondsSinceEpoch,
        reason: 'the fixture: on the same start the wrist will report',
      );

      // The wrist's entry with the SAME start arrives.
      final startedAt = wristTimer.startedAt;
      final endedAt = startedAt.add(const Duration(minutes: 5));
      await wristLogsTimedEntry(startedAt, endedAt);

      final placed = log
          .events()
          .where((event) => event.kind == 'entry_placed')
          .toList();
      expect(placed, isNotEmpty, reason: 'S-24423c the importer placed it');
      expect(
        placed.first.detail,
        allOf(contains('kind=timed'), contains('how=already_logged')),
        reason:
            'S-24423c the entry matched the interval the phone had already '
            'logged, and the label says so',
      );
      expect(failures, isEmpty);
    });
  });
}
