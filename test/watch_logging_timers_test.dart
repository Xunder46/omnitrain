// Watch logging surfaces — timestamp-derived timers and their haptics.
//
// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
// Scenario mapping:
//   S-003 the round countdown fires at the right wall-clock moment → `S-003 ...`
//   S-160 the wrist's rest has no length                            → `S-160 ...`
//   S-161 a rest survives the screen turning off                    → `S-161 ...`
//   S-164 no alert is ever owed for a rest                          → `S-164 ...`
//
// A haptic is owed when a countdown reaches zero, and the instant it is owed at
// comes from the timer's own timestamps. Nothing here counts down: every case
// below moves a clock, never a ticker, which is what makes the screen-off case
// the same case as the on-screen one.
//
// A rest is the exception: it is a count-up with no length, so it has no
// remaining time and is never owed a haptic (D-160).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_timer_haptics.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_timer_math.dart';

/// Deterministic clock: the engine and the surfaces read time only through an
/// injected clock, so a "backgrounded" minute is a value, not a wait.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
};

/// A countdown as a phone frame carries it: the shape, not the row.
Map<String, Object?> _timerJson(
  String kind, {
  required String startedAt,
  int? plannedDurationMs,
}) => {
  'kind': kind,
  'state': WatchTimerState.running,
  'startedAt': startedAt,
  'plannedDurationMs': plannedDurationMs,
};

Map<String, Object?> _frame(
  String type,
  String sessionId,
  String messageId,
  Map<String, Object?> payload,
) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': type,
  'origin': 'phone',
  'sentAt': '2026-07-13T17:00:00Z',
  'payload': payload,
};

/// The phone's whole account of the session, timers included.
Map<String, Object?> _snapshotFrame(
  String sessionId,
  String messageId, {
  required Map<String, Object?> timers,
  List<Map<String, Object?>> exercises = const [],
}) => _frame('session_snapshot', sessionId, messageId, {
  'sessionId': sessionId,
  'revision': 1,
  'status': WatchSessionStatus.active,
  'currentExerciseIndex': 0,
  'exercises': exercises,
  'entries': const [],
  'timers': timers,
});

void main() {
  late _Clock clock;
  late WatchSessionStore store;
  late WatchSessionEngine engine;
  late WatchLoggingState surface;

  setUp(() async {
    clock = _Clock(DateTime.utc(2026, 7, 13, 17));
    store = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(store, clock: clock.call);
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        _slot('sx-bench', ['reps', 'sets', 'load']),
      ],
    );
    surface = WatchLoggingState(engine: engine, clock: clock.call);
  });

  group('S-160 / S-161 / S-164 the wrist\'s rest is a count-up', () {
    test('S-160 a logged set starts a rest with no planned length', () async {
      await surface.log();

      final rest = engine.timerFor(WatchTimerKind.rest);
      expect(rest, isNotNull);
      expect(rest!.startedAt, clock.now);
      expect(rest.plannedDurationMs, isNull, reason: 'a rest has no preset length');
      expect(activeElapsedMs(rest, clock.now), 0);
      expect(
        activeElapsedMs(rest, clock.now.add(const Duration(seconds: 7))),
        7000,
        reason: 'the rest counts up from the instant the set was logged',
      );
      expect(
        remainingMs(rest, clock.now.add(const Duration(seconds: 90))),
        isNull,
        reason: 'nothing is left of a rest to show, at any instant',
      );
    });

    test('S-161 a rest survives the screen turning off', () async {
      await surface.log();
      final startedAt = clock.now;

      // Four minutes with the screen off: nothing ticked and nothing was
      // handed across in memory — the stored row is the whole account of it.
      clock.advance(const Duration(minutes: 4));
      final relaunched = WatchSessionEngine(store, clock: clock.call);
      await relaunched.restore();

      final rest = relaunched.timerFor(WatchTimerKind.rest)!;
      expect(rest.startedAt, startedAt, reason: 'the restore left the row alone');
      expect(rest.state, WatchTimerState.running);
      expect(rest.stoppedAt, isNull);
      expect(
        activeElapsedMs(rest, clock.now),
        240000,
        reason: 'the elapsed comes from the row, not from a ticker that stopped',
      );
    });

    test('S-164 no alert is ever owed for a rest', () async {
      await surface.log();
      await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60000);

      // Five minutes, polled every second: the round is owed its one milestone,
      // and the rest is owed nothing at any instant.
      final haptics = WatchTimerHaptics(engine);
      final startedAt = clock.now;
      final milestones = <WatchTimerMilestone>[];
      for (var second = 0; second <= 300; second++) {
        milestones.addAll(haptics.poll(startedAt.add(Duration(seconds: second))));
      }

      expect(
        milestones,
        [
          WatchTimerMilestone(
            kind: WatchTimerKind.round,
            at: startedAt.add(const Duration(seconds: 60)),
          ),
        ],
        reason: 'a rest has no length, so no alert is ever owed for one',
      );
    });

    test('S-164 a paused rest is still owed no alert', () async {
      await surface.log();
      final haptics = WatchTimerHaptics(engine);
      final startedAt = clock.now;

      clock.advance(const Duration(seconds: 30));
      await engine.pauseTimer(kind: WatchTimerKind.rest);
      clock.advance(const Duration(seconds: 30));
      await engine.resumeTimer(kind: WatchTimerKind.rest);

      for (var second = 0; second <= 600; second++) {
        expect(
          haptics.poll(startedAt.add(Duration(seconds: second))),
          isEmpty,
          reason: 'a rest owes no alert, running or paused',
        );
      }
    });

    test('S-164 a stored rest row with a stale plan owes no alert', () async {
      // A row an older build wrote: a rest that still carries its 90-second
      // plan. Nothing in this build writes one, but an upgrade restores one
      // from the store, and its clamped-to-zero remaining time must not read
      // as a countdown to alarm (F1, R-13).
      await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90000);
      await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60000);

      final haptics = WatchTimerHaptics(engine);
      final startedAt = clock.now;
      final milestones = <WatchTimerMilestone>[];
      for (var second = 0; second <= 300; second++) {
        milestones.addAll(haptics.poll(startedAt.add(Duration(seconds: second))));
      }

      expect(
        milestones,
        [
          WatchTimerMilestone(
            kind: WatchTimerKind.round,
            at: startedAt.add(const Duration(seconds: 60)),
          ),
        ],
        reason: 'the stale plan on a rest row is not a countdown to alarm',
      );
    });
  });

  group('S-003 round countdown', () {
    // A round lives in a round-based modality, which is the language S-008 is
    // about; the timer derivation underneath is the same one sets use.
    setUp(() async {
      clock = _Clock(DateTime.utc(2026, 7, 13, 17));
      store = InMemoryWatchSessionStore();
      engine = WatchSessionEngine(store, clock: clock.call);
      await engine.createSession(
        modality: 'sports',
        exercises: [
          _slot('sx-round', ['time', 'rounds']),
        ],
      );
      surface = WatchLoggingState(engine: engine, clock: clock.call);
    });

    test('S-003 logging a round starts the next round countdown', () async {
      await surface.log();

      final round = engine.timerFor(WatchTimerKind.round);
      expect(round, isNotNull);
      expect(round!.plannedDurationMs, 180000);
    });

    test(
      'S-003 the round haptic fires at the instant the round ends',
      () async {
        await surface.log();
        final haptics = WatchTimerHaptics(engine);

        final roundEnd = clock.now.add(const Duration(seconds: 180));
        expect(
          haptics.poll(roundEnd.subtract(const Duration(seconds: 1))),
          isEmpty,
        );
        expect(haptics.poll(roundEnd), [
          WatchTimerMilestone(kind: WatchTimerKind.round, at: roundEnd),
        ]);
      },
    );

    test('S-003 a new round is a new countdown, so it fires again', () async {
      await surface.log();
      final haptics = WatchTimerHaptics(engine);

      clock.advance(const Duration(seconds: 180));
      expect(haptics.poll(clock.now), hasLength(1));

      await surface.log();
      clock.advance(const Duration(seconds: 180));
      expect(
        haptics.poll(clock.now),
        hasLength(1),
        reason: 'round two is owed its own haptic',
      );
    });
  });

  group('WatchTimerHaptics derivation', () {
    test('a timer with no planned length has no completion instant', () async {
      final running = await engine.startTimer(WatchTimerKind.rest);

      expect(
        completionInstant(running),
        isNull,
        reason: 'nothing was promised, so nothing is owed',
      );
    });

    test('a timer with no planned duration never counts down', () async {
      await engine.startTimer(WatchTimerKind.elapsed);
      final haptics = WatchTimerHaptics(engine);

      clock.advance(const Duration(hours: 3));
      expect(haptics.poll(clock.now), isEmpty);
    });

    test('a countdown the user ended early never fires', () async {
      await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60000);
      final haptics = WatchTimerHaptics(engine);

      clock.advance(const Duration(seconds: 30));
      await engine.stopTimer(kind: WatchTimerKind.round);

      clock.advance(const Duration(minutes: 5));
      expect(haptics.poll(clock.now), isEmpty);
    });

    test(
      'a countdown the user ended late did complete, and fires once',
      () async {
        await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60000);
        final haptics = WatchTimerHaptics(engine);

        clock.advance(const Duration(seconds: 90));
        await engine.stopTimer(kind: WatchTimerKind.round);

        expect(haptics.poll(clock.now), [
          WatchTimerMilestone(
            kind: WatchTimerKind.round,
            at: clock.now.subtract(const Duration(seconds: 30)),
          ),
        ]);
        expect(
          haptics.poll(clock.now.add(const Duration(minutes: 1))),
          isEmpty,
        );
      },
    );
  });

  group('S-79 each device owns only the countdown it started', () {
    late String sessionId;

    setUp(() async {
      sessionId = engine.session!.sessionId;
      // The phone's countdown: the row id is derived from the message that
      // named it, which is what marks it as the sender's own (D-80).
      await engine.applyMessage(
        _frame('timer_state', sessionId, 'm-7', {
          'timers': {
            'round': _timerJson(
              WatchTimerKind.round,
              startedAt: '2026-07-13T16:59:50Z',
              plannedDurationMs: 60000,
            ),
          },
        }),
      );
      // The wrist's own countdown, started on the watch. A rest has no length
      // (D-160); its ownership is what this case is about.
      await engine.startTimer(WatchTimerKind.rest);
    });

    test(
      "S-79 a snapshot leaves the wrist's countdown running and stops the "
      "phone's own",
      () async {
        final wristTimer = engine.timerFor(WatchTimerKind.rest)!;
        expect(wristTimer.state, WatchTimerState.running);

        await engine.applyMessage(
          _snapshotFrame(
            sessionId,
            'snap-msg-1',
            timers: const {},
            exercises: [_slot('sx-bench', ['reps', 'sets', 'load'])],
          ),
        );

        final rest = engine.timerFor(WatchTimerKind.rest)!;
        expect(
          rest.recordId,
          wristTimer.recordId,
          reason: 'the wrist started it, so the phone is not speaking about it',
        );
        expect(rest.state, WatchTimerState.running);
        expect(rest.stoppedAt, isNull);

        final round = engine.timerFor(WatchTimerKind.round)!;
        expect(round.state, WatchTimerState.stopped);
        expect(round.stoppedAt, clock.now);

        expect(
          [for (final row in (await store.readAll()).timers)
            if (row.kind == WatchTimerKind.round) row.recordId],
          ['tms-m-7-round', 'tms-snap-msg-1-round'],
          reason: "the phone's own row is never rewritten: the stop is a row",
        );
      },
    );

    test('S-79 a kind named null is still cleared', () async {
      await engine.applyMessage(
        _snapshotFrame(
          sessionId,
          'snap-msg-2',
          timers: const {'rest': null},
          exercises: [_slot('sx-bench', ['reps', 'sets', 'load'])],
        ),
      );

      expect(
        engine.timerFor(WatchTimerKind.rest)!.state,
        WatchTimerState.stopped,
        reason: 'a kind the phone names is a kind the phone is speaking about',
      );
    });
  });
}
