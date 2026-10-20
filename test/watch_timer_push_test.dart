// The phone's work timers travel to the wrist (plan 43b3 P2).
//
// Plan: `docs/plans/2026-10-20-43b3-shared-timer-phone-sends-plan/`
// (D-2, D-2b, D-3, D-3b, D-4).
// Scenario mapping:
//   S-6211 a started interval travels as one timer_state frame carrying the
//          slot, state and startedAt, and a second pass sends nothing
//                                                          → `S-6211 ...`
//   S-6212 a pause and a resume travel with their bookkeeping → `S-6212 ...`
//   S-6213 finishing the interval clears it on the wrist  → `S-6213 ...`
//   S-6214 the wrist's earlier start is not overwritten, and a timer it already
//          holds equal is not echoed                    → `S-6214 ...` (×2)
//   S-6215 an undelivered frame is re-offered             → `S-6215 ...`
//   S-6216 the negatives: no active session, a set effort, no bound state
//                                                          → `S-6216 ...` (×3)
//   S-6217 a new interval replacing a delivered one clears first, then names it
//                                                          → `S-6217 ...`
// Plan 43c D-3 (the phone clears the clock the watch started):
//   S-6321 finishing an adopted interval clears the wrist clock
//                                                          → `S-6321 ...`
//   S-6322 the wrist logged first, so nothing is cleared   → `S-6322 ...`
//   S-6323 the mirror holds a different start for the slot → `S-6323 ...`
//   S-6324 the mirror holds the same start for another slot → `S-6324 ...`
//   S-6325 an undelivered clear is re-offered              → `S-6325 ...`
//   S-6326 the cleared mirror copy does not block the next interval
//                                                          → `S-6326 ...`
//   S-6327 the clear and the next interval in one pass     → `S-6327 ...`
//   S-6328 a second pass while the adopted interval runs sends nothing; the
//          phone's pause still travels                  → `S-6328 ...`
//   S-6329 after a clear, the wrist's next interval still wins → `S-6329 ...`
//   S-6330 a stopped wrist timer does not block the phone's own later start
//                                                          → `S-6330 ...`
//   S-6341 the wrist logs after the phone logged: one interval, no duplicate
//                                                          → `S-6341 ...`
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the timer push it returns — over a fake radio; the wrist side is
// the real engine over an in-memory store, so a phone frame is applied the way
// the watch app applies one. Every window is closed by `flush()` rather than by
// waiting, and the tests are plain `test()`: no `testWidgets`, no FakeAsync.
//
// The phone's own timer manager stamps an interval with `DateTime.now()` (its
// clock is not injectable from `WorkoutState`), so the assertions compare a
// frame with the stored instance it came from rather than with the pinned
// graph clock.

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
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which is
// the only way they reach a repository: the projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 10, 19, 9);

/// The session both devices know.
const String _sessionId = 's-w-timers';

/// The one slot the fixture puts in the ladder, and its effort id on the phone
/// (D-3: the wrist's slot id IS the phone's effort id).
const String _slotId = 'sx-run';

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

var _wristMessageCount = 0;

/// One `timer_state` frame as the wrist sends it.
Map<String, Object?> _wristTimerFrame(Map<String, Object?> timers) => {
  'protocolVersion': 1,
  'messageId': 'msg-wrist-timers-${_wristMessageCount++}',
  'sessionId': _sessionId,
  'type': 'timer_state',
  'origin': 'watch',
  'sentAt': utcIso(_now),
  'payload': {'timers': timers},
};

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it cannot
/// carry the way the platform channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed: the
  /// frame S-6215's first pass offered is only visible here.
  final List<Map<String, Object?>> attempted = [];

  /// True while the wrist is out of range: `send` carries nothing and answers
  /// `undelivered` without a failure.
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

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption and to the timer push in
  /// `lib/main.dart`; the scenarios bind the push themselves, once their
  /// fixture has settled.
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

  /// The wrist starts [_sessionId] with one timed slot, and the phone adopts
  /// it: the fixture every scenario starts from.
  Future<void> wristStartsTimedSession() async {
    await engine.createSession(modality: null, exercises: [_slot()]);
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    expect(graph.mirror.sessionId, _sessionId);
    final effort = phoneState
        .getEffortsForSegment(phoneState.segments.single.id)
        .single;
    expect(effort.id, _slotId, reason: 'D-3: the slot id is the effort id');
    expect(
      effort.effortKind,
      'timed',
      reason: 'the fixture: the slot logs as a timed effort',
    );
  }

  /// The phone starts one interval of the slot's effort and returns the stored
  /// instance the push must compose from.
  Future<InProgressWorkTimer> startInterval() async {
    await phoneState.startTimedEntry(_slotId, 0);
    final timers = phoneState.inProgressWorkTimers();
    expect(
      timers,
      hasLength(1),
      reason: 'the fixture: one in-progress work timer',
    );
    return timers.single;
  }

  /// Every timer frame the phone sent, in order.
  List<Map<String, Object?>> timerFrames() => radio.ofType('timer_state');

  /// The `timers` object of [envelope].
  Map<String, Object?> timersOf(Map<String, Object?> envelope) =>
      _asObject(_payload(envelope)['timers']);

  /// Applies the phone's timer frames to the wrist engine, in the order they
  /// were sent, the way the watch app applies each frame it receives.
  Future<void> applyPhoneTimers() async {
    for (final frame in timerFrames()) {
      await engine.applyMessage(frame);
    }
  }

  /// The mirror's copy of the [kind] timer, as the wrist last reported it.
  Map<String, Object?> mirrorTimer(String kind) =>
      _asObject(_asObject(graph.mirror.state['timers'])[kind]);

  /// The phone's interval [index] of the slot.
  TimedInstance interval(int index) =>
      phoneState.getTimedInstancesForEffort(_slotId)[index];

  /// The "adopted interval" fixture (plan 43c D-3): the wrist started an
  /// `elapsed` timer for the slot, the phone had an interval waiting, and the
  /// phone runs that timer as its own — nothing was echoed to the wrist.
  Future<WatchTimerRecord> adoptedInterval() async {
    await wristStartsTimedSession();
    // The app binds all three to the same state (`lib/main.dart`); the timer
    // adoption is what makes the wrist's timer the phone's interval.
    graph.timerAdoption.bindWorkoutState(phoneState);
    graph.timerPush.bindWorkoutState(phoneState);

    final started = await engine.startTimer(
      WatchTimerKind.elapsed,
      sessionExerciseId: _slotId,
    );
    await radio.fromWrist(wristFrames.last);
    await _settle();

    final adopted = interval(0);
    expect(
      adopted.state,
      TimedState.active,
      reason: 'the fixture: the phone adopted the wrist timer (43b2)',
    );
    expect(
      adopted.startedAtMs,
      started.startedAt.millisecondsSinceEpoch,
      reason: "the fixture: the phone runs the wrist's own start",
    );

    await graph.timerPush.flush();
    expect(
      timerFrames(),
      isEmpty,
      reason: 'the fixture: the adopted timer is not echoed to the wrist',
    );
    return started;
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
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: wristFrames.add,
    );
  });

  group('S-6211 a started interval travels as one timer_state frame', () {
    test(
      'S-6211 the interval is sent once, with its slot, running state and '
      'startedAt, it validates, and the wrist starts its timer from it',
      () async {
        await wristStartsTimedSession();
        graph.timerPush.bindWorkoutState(phoneState);
        final instance = await startInterval();
        await graph.timerPush.flush();

        final frames = timerFrames();
        expect(
          frames,
          hasLength(1),
          reason: 'S-6211 exactly one timer frame is sent',
        );
        final timers = timersOf(frames.single);
        expect(timers.keys, [
          'elapsed',
        ], reason: 'S-6211 a timed effort is the wire elapsed timer');
        final timer = _asObject(timers['elapsed']);
        expect(timer['kind'], 'elapsed');
        expect(timer['state'], 'running');
        expect(
          timer['sessionExerciseId'],
          _slotId,
          reason: "S-6211 the timer names the slot the work is in",
        );
        expect(timer['accumulatedPauseMs'], 0);
        expect(
          parseUtcIso(timer['startedAt']),
          DateTime.fromMillisecondsSinceEpoch(
            instance.startedAtMs,
            isUtc: true,
          ),
          reason: 'S-6211 the frame carries the instance it came from',
        );
        expect(
          loadProtocolValidator().validateEnvelope(frames.single),
          isEmpty,
          reason: 'S-6211 the envelope passes the Dart validator',
        );

        expect(
          await engine.applyMessage(frames.single),
          isTrue,
          reason: 'S-6211 the wrist applies the frame the way the app does',
        );
        final wristTimer = engine.timerFor(WatchTimerKind.elapsed)!;
        expect(wristTimer.sessionExerciseId, _slotId);
        expect(wristTimer.state, WatchTimerState.running);
        expect(
          wristTimer.startedAt.millisecondsSinceEpoch,
          instance.startedAtMs,
          reason: 'S-6211 the wrist starts from the phone instant',
        );

        await graph.timerPush.flush();
        expect(
          timerFrames(),
          hasLength(1),
          reason: 'S-6211 a second pass with no change sends no frame',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      'S-6211 a hold and a round carry their kind and length',
      () async {
        await seedExercise(
          repository,
          id: 'ex-plank',
          name: 'Plank',
          capabilities: ['hold', 'time'],
        );
        await seedExercise(
          repository,
          id: 'ex-bag',
          name: 'Punch bag',
          capabilities: ['time', 'rounds'],
        );

        await phoneState.createNewSession(modality: 'sports');
        final holdSlot = await phoneState.addExerciseToSession(
          (await repository.getExerciseById('ex-plank'))!,
          effortKindOverride: 'drill',
        );
        await phoneState.startTimedEntry(holdSlot, 0);

        graph.timerPush.bindWorkoutState(phoneState);
        await graph.timerPush.flush();

        final holdFrame = timerFrames().single;
        final hold = _asObject(timersOf(holdFrame)['hold']);
        expect(hold['kind'], 'hold');
        expect(
          hold['sessionExerciseId'],
          holdSlot,
          reason: 'S-6211 a hold names the drill slot it came from',
        );
        expect(hold['state'], 'running');
        expect(
          loadProtocolValidator().validateEnvelope(holdFrame),
          isEmpty,
          reason: 'S-6211 the hold frame passes the Dart validator',
        );

        final roundSlot = await phoneState.addExerciseToSession(
          (await repository.getExerciseById('ex-bag'))!,
        );
        // 75 s is unlike every default, so a hard-coded plan fails.
        await phoneState.updateRoundPlannedDuration(roundSlot, 0, 75);
        await phoneState.startRound(roundSlot, 0);
        await graph.timerPush.flush();

        expect(timerFrames(), hasLength(2));
        final roundFrame = timerFrames().last;
        final round = _asObject(timersOf(roundFrame)['round']);
        expect(round['kind'], 'round');
        expect(
          round['sessionExerciseId'],
          roundSlot,
          reason: 'S-6211 a round names the round slot it came from',
        );
        expect(
          round['plannedDurationMs'],
          75000,
          reason: 'S-6211 the round carries its planned length',
        );
        expect(
          loadProtocolValidator().validateEnvelope(roundFrame),
          isEmpty,
          reason: 'S-6211 the round frame passes the Dart validator',
        );
        expect(failures, isEmpty);
      },
    );
  });
  group('S-6212 a pause and a resume travel with their bookkeeping', () {
    test('S-6212 pausing sends the paused stamp and resuming sends the pause '
        'accumulated so far, which the wrist reads back', () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);
      await startInterval();
      await graph.timerPush.flush();
      expect(timerFrames(), hasLength(1), reason: 'the fixture: one frame');
      await applyPhoneTimers();

      await phoneState.pauseTimedEntry(_slotId, 0);
      final paused = phoneState.getTimedInstancesForEffort(_slotId).single;
      await graph.timerPush.flush();
      expect(timerFrames(), hasLength(2));
      final pausedTimer = _asObject(timersOf(timerFrames().last)['elapsed']);
      expect(pausedTimer['state'], 'paused');
      expect(
        parseUtcIso(pausedTimer['pausedAt']),
        DateTime.fromMillisecondsSinceEpoch(paused.pausedAtMs!, isUtc: true),
        reason: 'S-6212 the frame carries the instance it came from',
      );
      await applyPhoneTimers();
      expect(
        engine.timerFor(WatchTimerKind.elapsed)!.state,
        WatchTimerState.paused,
        reason: 'S-6212 the wrist holds the paused timer',
      );

      // The pause must have a length to accumulate; the phone's timer clock
      // is real time, so the smallest measurable pause is a few milliseconds.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await phoneState.resumeTimedEntry(_slotId, 0);
      final resumed = phoneState.getTimedInstancesForEffort(_slotId).single;
      expect(
        resumed.totalPausedDurationMs,
        greaterThan(0),
        reason: 'the fixture: the instance measured a pause',
      );
      await graph.timerPush.flush();
      expect(timerFrames(), hasLength(3));
      final resumedTimer = _asObject(timersOf(timerFrames().last)['elapsed']);
      expect(resumedTimer['state'], 'running');
      expect(
        resumedTimer['accumulatedPauseMs'],
        resumed.totalPausedDurationMs,
        reason: 'S-6212 the resume carries the pause the phone accumulated',
      );
      expect(
        resumedTimer.containsKey('pausedAt'),
        isFalse,
        reason: 'S-6212 a running timer carries no paused stamp',
      );

      await applyPhoneTimers();
      final wristTimer = engine.timerFor(WatchTimerKind.elapsed)!;
      expect(wristTimer.state, WatchTimerState.running);
      expect(
        wristTimer.accumulatedPauseMs,
        resumed.totalPausedDurationMs,
        reason: 'S-6212 the wrist excludes the pause it was told about',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6213 finishing the interval clears it on the wrist', () {
    test('S-6213 the finished interval is sent as a cleared elapsed timer, and '
        'the wrist stops the timer it had', () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);
      await startInterval();
      await graph.timerPush.flush();
      expect(timerFrames(), hasLength(1), reason: 'the fixture: one frame');
      await applyPhoneTimers();
      expect(
        engine.timerFor(WatchTimerKind.elapsed)!.state,
        WatchTimerState.running,
        reason: 'the fixture: the wrist is counting',
      );

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      expect(
        timerFrames(),
        hasLength(2),
        reason: 'S-6213 exactly one frame is sent for the finish',
      );
      final cleared = timersOf(timerFrames().last);
      expect(
        cleared.containsKey('elapsed'),
        isTrue,
        reason: 'S-6213 the frame names the timer it clears',
      );
      expect(
        cleared['elapsed'],
        isNull,
        reason: 'S-6213 a key present with null clears that timer',
      );

      await applyPhoneTimers();
      expect(
        engine.timerFor(WatchTimerKind.elapsed)!.state,
        WatchTimerState.stopped,
        reason: 'S-6213 the wrist stops the timer the phone finished',
      );

      // A later notification offers the pass the same empty wanted set again:
      // the delivered clear is spent, so it is not sent a second time.
      phoneState.notifyListeners();
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(2),
        reason: 'S-6213 a delivered clear is not sent twice',
      );
      expect(failures, isEmpty);
    });
  });

  group("S-6214 the wrist's earlier timer is not overwritten or echoed", () {
    test(
      'S-6214 a phone start later than the timer the wrist holds for the same '
      'slot sends nothing',
      () async {
        await wristStartsTimedSession();

        // The wrist started this interval itself, at the pinned instant.
        await engine.startTimer(
          WatchTimerKind.elapsed,
          sessionExerciseId: _slotId,
        );
        expect(wristFrames, isNotEmpty);
        await radio.fromWrist(wristFrames.last);
        await _settle();
        final held = _asObject(
          _asObject(graph.mirror.state['timers'])['elapsed'],
        );
        expect(
          held['sessionExerciseId'],
          _slotId,
          reason: "the fixture: the mirror holds the wrist's timer",
        );

        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();
        await graph.timerPush.flush();

        expect(
          timerFrames(),
          isEmpty,
          reason:
              "S-6214 the wrist's earlier start wins, so the phone does not "
              'overwrite it',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      'S-6214 a timer the mirror already holds equal to the phone\'s own sends '
      'nothing',
      () async {
        await wristStartsTimedSession();
        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();
        await graph.timerPush.flush();
        final delivered = timerFrames().single;
        await applyPhoneTimers();

        // The wrist echoes the timer it stored, exactly as the phone sent it.
        await radio.fromWrist(
          _wristTimerFrame({
            'elapsed': _asObject(timersOf(delivered)['elapsed']),
          }),
        );
        await _settle();
        expect(
          _asObject(graph.mirror.state['timers'])['elapsed'],
          isNotNull,
          reason: 'the fixture: the mirror holds the echoed timer',
        );

        await graph.timerPush.flush();
        expect(
          timerFrames(),
          hasLength(1),
          reason: 'S-6214 a timer the wrist already holds is not echoed back',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      'S-6214 a timer the wrist already holds exactly as the phone has it is '
      'not sent',
      () async {
        await wristStartsTimedSession();

        // The wrist started this interval itself, at the pinned instant.
        await engine.startTimer(
          WatchTimerKind.elapsed,
          sessionExerciseId: _slotId,
        );
        await radio.fromWrist(wristFrames.last);
        await _settle();
        final wristStartMs = engine
            .timerFor(WatchTimerKind.elapsed)!
            .startedAt
            .millisecondsSinceEpoch;

        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();

        // Give the phone's instance the wrist's own start instant: the two
        // devices then hold the same timer field for field.
        final started = phoneState.getTimedInstancesForEffort(_slotId).single;
        await repository.updateTimedInstance(
          started.copyWith(startedAtMs: wristStartMs),
        );
        await phoneState.refreshEfforts([_slotId]);
        expect(
          phoneState.getTimedInstancesForEffort(_slotId).single.startedAtMs,
          wristStartMs,
          reason: 'the fixture: the phone counts from the wrist instant',
        );

        await graph.timerPush.flush();
        expect(
          timerFrames(),
          isEmpty,
          reason: 'S-6214 a timer both sides hold identically is not sent',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      'S-6214 the same instant with the phone paused is sent',
      () async {
        await wristStartsTimedSession();

        await engine.startTimer(
          WatchTimerKind.elapsed,
          sessionExerciseId: _slotId,
        );
        await radio.fromWrist(wristFrames.last);
        await _settle();
        final wristStart = engine.timerFor(WatchTimerKind.elapsed)!.startedAt;

        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();
        await phoneState.pauseTimedEntry(_slotId, 0);

        final paused = phoneState.getTimedInstancesForEffort(_slotId).single;
        expect(paused.pausedAtMs, isNotNull, reason: 'the fixture: paused');
        await repository.updateTimedInstance(
          paused.copyWith(startedAtMs: wristStart.millisecondsSinceEpoch),
        );
        await phoneState.refreshEfforts([_slotId]);

        await graph.timerPush.flush();
        final frames = timerFrames();
        expect(
          frames,
          hasLength(1),
          reason:
              'S-6214 the same start instant with a paused phone is a '
              'different timer, so it is sent',
        );
        final timer = _asObject(timersOf(frames.single)['elapsed']);
        expect(timer['state'], 'paused');
        expect(timer['sessionExerciseId'], _slotId);
        expect(
          parseUtcIso(timer['startedAt']),
          wristStart,
          reason: 'S-6214 the frame still carries the shared start instant',
        );
        expect(
          timer.containsKey('pausedAt'),
          isTrue,
          reason: 'S-6214 the pause is what makes the encodings differ',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      "S-6214 an earlier wrist timer for ANOTHER exercise does not stop the "
      "phone's start from being sent",
      () async {
        await wristStartsTimedSession();
        graph.timerPush.bindWorkoutState(phoneState);
        final instance = await startInterval();

        // The wrist holds an earlier timer of the same kind, for a different
        // slot: its start is earlier, but it is not the phone's timer.
        await radio.fromWrist(
          _wristTimerFrame({
            'elapsed': {
              'kind': 'elapsed',
              'state': 'running',
              'startedAt': utcIso(
                DateTime.fromMillisecondsSinceEpoch(
                  instance.startedAtMs - 60000,
                  isUtc: true,
                ),
              ),
              'accumulatedPauseMs': 0,
              'sessionExerciseId': 'sx-other',
            },
          }),
        );
        await _settle();
        final held = _asObject(
          _asObject(graph.mirror.state['timers'])['elapsed'],
        );
        expect(
          held['sessionExerciseId'],
          'sx-other',
          reason: "the fixture: the mirror holds another slot's earlier timer",
        );

        await graph.timerPush.flush();
        final frames = timerFrames();
        expect(
          frames,
          hasLength(1),
          reason:
              'S-6214 an earlier timer for another slot does not hold the '
              "phone's timer",
        );
        final timer = _asObject(timersOf(frames.single)['elapsed']);
        expect(
          timer['sessionExerciseId'],
          _slotId,
          reason: "S-6214 the frame names the phone's own slot",
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-6215 an undelivered frame is re-offered', () {
    test('S-6215 the first send answers not-delivered, the next pass offers it '
        'again, and once delivered it stops', () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);
      await startInterval();

      radio.unreachable = true;
      await graph.timerPush.flush();
      expect(
        [
          for (final envelope in radio.attempted)
            if (envelope['type'] == 'timer_state') envelope,
        ],
        hasLength(1),
        reason: 'S-6215 the first attempt was made and carried nothing',
      );
      expect(timerFrames(), isEmpty);

      radio.unreachable = false;
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6215 the next pass offers the owed timer again',
      );

      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6215 once delivered, it stops',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6216 the negative guards', () {
    test(
      'S-6216 an inactive session sends nothing and clears the ledger',
      () async {
        await wristStartsTimedSession();
        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();
        await graph.timerPush.flush();
        expect(timerFrames(), hasLength(1), reason: 'the fixture: one frame');

        await phoneState.endSession();
        expect(phoneState.hasActiveSession, isFalse);
        await graph.timerPush.flush();

        expect(
          timerFrames(),
          hasLength(1),
          reason: 'S-6216 a session that is not active has no timers to send',
        );
        expect(failures, isEmpty);
      },
    );

    test('S-6216 a set effort contributes no timer frame', () async {
      await phoneState.createNewSession();
      final exercise = (await repository.getExerciseById('ex-run'))!;
      await phoneState.addExerciseToSession(exercise);
      graph.timerPush.bindWorkoutState(phoneState);

      final effort = phoneState
          .getEffortsForSegment(phoneState.segments.single.id)
          .single;
      expect(
        effort.effortKind,
        'set',
        reason: 'the fixture: a session with no modality logs sets',
      );
      await phoneState.addEntry(effort.id);
      expect(phoneState.hasActiveSession, isTrue);
      await graph.timerPush.flush();

      expect(
        timerFrames(),
        isEmpty,
        reason: 'S-6216 a set effort has no work timer to send',
      );
      expect(failures, isEmpty);
    });

    test('S-6216 an unbound push sends nothing', () async {
      await wristStartsTimedSession();
      await startInterval();
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        isEmpty,
        reason: 'S-6216 no bound session state, nothing to compose timers from',
      );

      graph.timerPush.bindWorkoutState(phoneState);
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6216 once bound, the running timer is sent',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6217 a new interval replacing a delivered one', () {
    test('S-6217 the replaced interval is cleared in its own frame before the '
        'new one, and the wrist ends on the new timer', () async {
      await wristStartsTimedSession();
      graph.timerPush.bindWorkoutState(phoneState);
      await startInterval();
      await graph.timerPush.flush();
      expect(timerFrames(), hasLength(1), reason: 'the fixture: one frame');
      final oldStartedAt = parseUtcIso(
        _asObject(timersOf(timerFrames().single)['elapsed'])['startedAt'],
      );
      await applyPhoneTimers();
      expect(timerFrames(), hasLength(1), reason: 'the fixture: applied');

      // Finish the first interval and start a second, with no window closing
      // between the two notifications.
      await phoneState.finishTimedEntry(_slotId, 0);
      await phoneState.addEntry(_slotId);
      // The second start must land on a later millisecond than the first, or
      // the two instants tie; the mock repository resolves in microtasks, so
      // without this the whole fixture can run inside one millisecond.
      while (DateTime.now().millisecondsSinceEpoch <=
          oldStartedAt.millisecondsSinceEpoch) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await phoneState.startTimedEntry(_slotId, 1);
      final current = phoneState.inProgressWorkTimers().single;
      expect(
        current.startedAtMs,
        greaterThan(oldStartedAt.millisecondsSinceEpoch),
      );
      await graph.timerPush.flush();

      final frames = timerFrames();
      expect(
        frames,
        hasLength(3),
        reason: 'S-6217 the clear and the new timer are two frames',
      );
      final cleared = timersOf(frames[1]);
      expect(
        cleared['elapsed'],
        isNull,
        reason: 'S-6217 the first frame clears the replaced interval',
      );
      final next = _asObject(timersOf(frames[2])['elapsed']);
      expect(next['state'], 'running');
      expect(
        parseUtcIso(next['startedAt']),
        DateTime.fromMillisecondsSinceEpoch(current.startedAtMs, isUtc: true),
        reason: 'S-6217 the second frame names the new interval',
      );

      await applyPhoneTimers();
      final wristTimer = engine.timerFor(WatchTimerKind.elapsed)!;
      expect(
        wristTimer.state,
        WatchTimerState.running,
        reason: 'S-6217 the wrist ends on the new interval',
      );
      expect(
        wristTimer.startedAt.millisecondsSinceEpoch,
        current.startedAtMs,
        reason: 'S-6217 the wrist counts the new interval, not the old one',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6321 finishing an adopted interval clears the wrist clock', () {
    test('S-6321 the phone finishing the interval the wrist started sends one '
        'cleared elapsed timer, and the wrist stops counting', () async {
      await adoptedInterval();

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      final frames = timerFrames();
      expect(
        frames,
        hasLength(1),
        reason: 'S-6321 exactly one frame is sent for the finish',
      );
      final timers = timersOf(frames.single);
      expect(
        timers.containsKey('elapsed'),
        isTrue,
        reason: 'S-6321 the frame names the timer it clears',
      );
      expect(
        timers['elapsed'],
        isNull,
        reason: 'S-6321 a key present with null clears that timer',
      );

      expect(
        await engine.applyMessage(frames.single),
        isTrue,
        reason: 'S-6321 the wrist applies the frame the way the app does',
      );
      expect(
        engine.timerFor(WatchTimerKind.elapsed)!.state,
        WatchTimerState.stopped,
        reason: "S-6321 the wrist stops the timer the phone logged",
      );

      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6321 the delivered clear is not sent twice',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6322 the wrist stopped first', () {
    test('S-6322 when the wrist has already logged the interval the phone '
        'finishes, nothing is sent', () async {
      await adoptedInterval();

      await engine.stopTimer(kind: WatchTimerKind.elapsed);
      final stoppedFrame = wristFrames.last;
      expect(
        stoppedFrame['type'],
        'timer_state',
        reason: 'the fixture: the wrist reports its own stop',
      );
      final stopped = _asObject(
        _asObject(_payload(stoppedFrame)['timers'])['elapsed'],
      );
      expect(
        stopped['state'],
        'stopped',
        reason: 'the fixture: the wrist holds a stopped row',
      );
      await radio.fromWrist(stoppedFrame);
      await _settle();

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      expect(
        timerFrames(),
        isEmpty,
        reason: 'S-6322 the wrist logged first, so there is no clock to clear',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6323 the mirror holds a different start', () {
    test("S-6323 when the wrist has begun the slot's next interval, the "
        'phone finishing the old one does not stop the new clock', () async {
      await adoptedInterval();
      final first = mirrorTimer('elapsed');
      final nextStart = DateTime.fromMillisecondsSinceEpoch(
        parseUtcIso(first['startedAt']).millisecondsSinceEpoch + 60000,
        isUtc: true,
      );

      await radio.fromWrist(
        _wristTimerFrame({
          'elapsed': {
            'kind': 'elapsed',
            'state': 'running',
            'startedAt': utcIso(nextStart),
            'accumulatedPauseMs': 0,
            'sessionExerciseId': _slotId,
          },
        }),
      );
      await _settle();
      expect(
        parseUtcIso(mirrorTimer('elapsed')['startedAt']),
        nextStart,
        reason: "the fixture: the mirror holds the wrist's next interval",
      );

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      expect(
        timerFrames(),
        isEmpty,
        reason:
            "S-6323 a clear would stop the wrist's newer interval, so none is "
            'sent',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6324 the mirror holds the same start for another slot', () {
    test(
      'S-6324 when the mirror holds another slot at the same instant, the '
      "phone finishing its interval does not clear the wrist's clock",
      () async {
        await adoptedInterval();
        final first = mirrorTimer('elapsed');

        await radio.fromWrist(
          _wristTimerFrame({
            'elapsed': {
              'kind': 'elapsed',
              'state': 'running',
              'startedAt': first['startedAt'],
              'accumulatedPauseMs': 0,
              'sessionExerciseId': 'sx-other',
            },
          }),
        );
        await _settle();
        expect(
          mirrorTimer('elapsed')['sessionExerciseId'],
          'sx-other',
          reason: "the fixture: the mirror holds another slot's timer",
        );

        await phoneState.finishTimedEntry(_slotId, 0);
        await graph.timerPush.flush();

        expect(
          timerFrames(),
          isEmpty,
          reason:
              'S-6324 the same start for another slot is not the interval '
              'the phone finished',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-6325 an undelivered clear is re-offered', () {
    test('S-6325 the clear the radio could not carry is offered again at the '
        'next pass and then stops', () async {
      await adoptedInterval();

      radio.unreachable = true;
      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();

      expect(
        timerFrames(),
        isEmpty,
        reason: 'S-6325 the radio carried nothing',
      );
      final attempted = [
        for (final envelope in radio.attempted)
          if (envelope['type'] == 'timer_state') envelope,
      ];
      expect(
        attempted,
        hasLength(1),
        reason: 'S-6325 the clear was offered once',
      );
      final offered = timersOf(attempted.single);
      expect(offered.containsKey('elapsed'), isTrue);
      expect(
        offered['elapsed'],
        isNull,
        reason: 'S-6325 the owed frame is the clear',
      );

      radio.unreachable = false;
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6325 the next pass offers the owed clear again',
      );
      expect(
        timersOf(timerFrames().single)['elapsed'],
        isNull,
        reason: 'S-6325 the offered timer is still the clear',
      );

      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'S-6325 once delivered, the clear stops',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6326 the cleared mirror copy does not block the next interval', () {
    test('S-6326 after the clear the mirror still holds the old timer, and the '
        "phone's next interval is sent and run on the wrist", () async {
      await adoptedInterval();

      await phoneState.finishTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      expect(
        timerFrames(),
        hasLength(1),
        reason: 'the fixture: the clear is delivered',
      );
      final oldStartMs = parseUtcIso(
        mirrorTimer('elapsed')['startedAt'],
      ).millisecondsSinceEpoch;

      await phoneState.addEntry(_slotId);
      while (DateTime.now().millisecondsSinceEpoch <= oldStartMs) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await phoneState.startTimedEntry(_slotId, 1);
      final current = phoneState.inProgressWorkTimers().single;
      expect(
        current.startedAtMs,
        greaterThan(oldStartMs),
        reason: 'the fixture: the new interval starts after the old one',
      );
      await graph.timerPush.flush();

      final frames = timerFrames();
      expect(
        frames,
        hasLength(2),
        reason:
            'S-6326 a stale mirror copy does not block the newer phone timer',
      );
      final timer = _asObject(timersOf(frames.last)['elapsed']);
      expect(
        timer['sessionExerciseId'],
        _slotId,
        reason: "S-6326 the frame names the phone's own slot",
      );
      expect(
        parseUtcIso(timer['startedAt']),
        DateTime.fromMillisecondsSinceEpoch(current.startedAtMs, isUtc: true),
        reason: 'S-6326 the frame carries the new interval',
      );

      await applyPhoneTimers();
      final wristTimer = engine.timerFor(WatchTimerKind.elapsed)!;
      expect(
        wristTimer.state,
        WatchTimerState.running,
        reason: 'S-6326 the wrist ends up counting',
      );
      expect(
        wristTimer.startedAt.millisecondsSinceEpoch,
        current.startedAtMs,
        reason: 'S-6326 the wrist runs the new interval, not the old one',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6327 a replacement in one window', () {
    test('S-6327 finishing the adopted interval and starting another before a '
        'pass sends the clear first and then the new timer', () async {
      final started = await adoptedInterval();

      await phoneState.finishTimedEntry(_slotId, 0);
      await phoneState.addEntry(_slotId);
      while (DateTime.now().millisecondsSinceEpoch <=
          started.startedAt.millisecondsSinceEpoch) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await phoneState.startTimedEntry(_slotId, 1);
      final current = phoneState.inProgressWorkTimers().single;
      await graph.timerPush.flush();

      final frames = timerFrames();
      expect(
        frames,
        hasLength(2),
        reason: 'S-6327 the clear and the new timer are two frames',
      );
      expect(
        timersOf(frames.first)['elapsed'],
        isNull,
        reason: 'S-6327 the first frame clears the finished interval',
      );
      final next = _asObject(timersOf(frames.last)['elapsed']);
      expect(
        parseUtcIso(next['startedAt']),
        DateTime.fromMillisecondsSinceEpoch(current.startedAtMs, isUtc: true),
        reason: 'S-6327 the second frame names the new interval',
      );

      await applyPhoneTimers();
      final wristTimer = engine.timerFor(WatchTimerKind.elapsed)!;
      expect(
        wristTimer.state,
        WatchTimerState.running,
        reason: 'S-6327 the wrist ends on the new interval',
      );
      expect(
        wristTimer.startedAt.millisecondsSinceEpoch,
        current.startedAtMs,
        reason: 'S-6327 the wrist counts the new interval, not the old one',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-6328 a second pass while the adopted interval still runs', () {
    test(
      'S-6328 further passes send nothing until the phone pauses the interval, '
      "and the pause travels with the wrist's own start",
      () async {
        final started = await adoptedInterval();

        await graph.timerPush.flush();
        await graph.timerPush.flush();
        expect(
          timerFrames(),
          isEmpty,
          reason: 'S-6328 a pass with nothing new sends nothing, and no clear',
        );

        await phoneState.pauseTimedEntry(_slotId, 0);
        await graph.timerPush.flush();

        final frames = timerFrames();
        expect(
          frames,
          hasLength(1),
          reason: 'S-6328 a pause is news, so it still travels',
        );
        final paused = _asObject(timersOf(frames.single)['elapsed']);
        expect(paused['state'], 'paused');
        expect(
          parseUtcIso(paused['startedAt']),
          started.startedAt,
          reason: "S-6328 the pause carries the wrist's own start",
        );
        expect(
          timersOf(frames.single)['elapsed'],
          isNotNull,
          reason: 'S-6328 nothing clears the clock the wrist started',
        );

        await graph.timerPush.flush();
        expect(
          timerFrames(),
          hasLength(1),
          reason: 'S-6328 a delivered pause is not sent twice',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group("S-6329 after a clear, the wrist's next interval still wins", () {
    test(
      'S-6329 the wrist\'s next start is not mistaken for the copy this push '
      "cleared, so the phone's later interval is not sent",
      () async {
        final first = await adoptedInterval();

        await phoneState.finishTimedEntry(_slotId, 0);
        await graph.timerPush.flush();
        expect(
          timerFrames(),
          hasLength(1),
          reason: 'the fixture: the clear is delivered',
        );
        expect(timersOf(timerFrames().single)['elapsed'], isNull);

        // The wrist's next interval starts after the one it just cleared. The
        // engine's clock is pinned, so its report is handed over directly, the
        // way the radio would.
        final nextStart = first.startedAt.add(const Duration(milliseconds: 2));
        await radio.fromWrist(
          _wristTimerFrame({
            'elapsed': {
              'kind': 'elapsed',
              'state': 'running',
              'startedAt': utcIso(nextStart),
              'accumulatedPauseMs': 0,
              'sessionExerciseId': _slotId,
            },
          }),
        );
        await _settle();
        expect(
          parseUtcIso(mirrorTimer('elapsed')['startedAt']),
          nextStart,
          reason: "the fixture: the mirror holds the wrist's next interval",
        );

        await phoneState.addEntry(_slotId);
        while (DateTime.now().millisecondsSinceEpoch <=
            nextStart.millisecondsSinceEpoch) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await phoneState.startTimedEntry(_slotId, 1);
        expect(
          phoneState.inProgressWorkTimers().single.startedAtMs,
          greaterThan(nextStart.millisecondsSinceEpoch),
          reason: "the fixture: the phone's own start is later",
        );

        await graph.timerPush.flush();
        expect(
          timerFrames(),
          hasLength(1),
          reason:
              "S-6329 the wrist's newer timer starts earlier than the phone's "
              'and wins; it is not the copy this push cleared',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-6330 a stopped wrist timer does not block the phone', () {
    test(
      "S-6330 the wrist stopped its own timer, so the phone's later start is "
      'sent',
      () async {
        await wristStartsTimedSession();

        await engine.startTimer(
          WatchTimerKind.elapsed,
          sessionExerciseId: _slotId,
        );
        await radio.fromWrist(wristFrames.last);
        await _settle();
        await engine.stopTimer(kind: WatchTimerKind.elapsed);
        await radio.fromWrist(wristFrames.last);
        await _settle();
        expect(
          mirrorTimer('elapsed')['state'],
          'stopped',
          reason: "the fixture: the mirror holds the wrist's stopped timer",
        );

        graph.timerPush.bindWorkoutState(phoneState);
        final instance = await startInterval();
        await graph.timerPush.flush();

        final frames = timerFrames();
        expect(
          frames,
          hasLength(1),
          reason: 'S-6330 a stopped timer holds nothing, so the start travels',
        );
        final timer = _asObject(timersOf(frames.single)['elapsed']);
        expect(timer['state'], 'running');
        expect(
          parseUtcIso(timer['startedAt']),
          DateTime.fromMillisecondsSinceEpoch(
            instance.startedAtMs,
            isUtc: true,
          ),
          reason: "S-6330 the frame carries the phone's own start",
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-6341 the wrist logs after the phone logged', () {
    test(
      'S-6341 one interval, no duplicate: the wrist entry lands on the '
      'interval the phone already finished',
      () async {
        final started = await adoptedInterval();

        // The phone logs the interval while the radio cannot carry the clear.
        radio.unreachable = true;
        await phoneState.finishTimedEntry(_slotId, 0);
        await graph.timerPush.flush();
        final logged = interval(0);
        expect(
          logged.state,
          TimedState.finished,
          reason: 'the fixture: the phone logged the interval',
        );
        expect(
          timerFrames(),
          isEmpty,
          reason: 'the fixture: the radio carried nothing',
        );

        // The wrist logs the interval it timed — the same one the phone logged.
        radio.unreachable = false;
        final entryId = 'sx-run-logged';
        final endedAt = started.startedAt.add(const Duration(minutes: 5));
        await engine.appendObservation(<String, Object?>{
          'entryId': entryId,
          'eventId': entryId,
          'kind': 'timed',
          'loggedAt': utcIso(endedAt),
          'sessionExerciseId': _slotId,
          'exerciseId': 'ex-run',
          'startedAt': utcIso(started.startedAt),
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

        final held = phoneState.getTimedInstancesForEffort(_slotId);
        expect(
          held,
          hasLength(1),
          reason: 'S-6341 the wrist entry does not become a second interval',
        );
        expect(held.single.state, TimedState.finished);
        expect(
          held.single.finishedAtMs,
          logged.finishedAtMs,
          reason: 'S-6341 the phone logged it, and its stamps stand',
        );
        expect(
          await repository.getTimedInstances(_slotId),
          hasLength(1),
          reason: 'S-6341 nothing was written beside the phone\'s interval',
        );
        expect(failures, isEmpty);
      },
    );
  });
}
