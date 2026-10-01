// Watch logging surfaces — timestamp-derived timers and their haptics.
//
// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
// Scenario mapping:
//   S-003 the round countdown fires at the right wall-clock moment → `S-003 ...`
//   S-005 rest timer with screen-off haptic                        → `S-005 ...`
//
// A haptic is owed when a countdown reaches zero, and the instant it is owed at
// comes from the timer's own timestamps. Nothing here counts down: every case
// below moves a clock, never a ticker, which is what makes the screen-off case
// the same case as the on-screen one.

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

  group('S-005 rest timer with screen-off haptic', () {
    test(
      'S-005 logging a set starts a rest countdown of the surface length',
      () async {
        await surface.log();

        final rest = engine.timerFor(WatchTimerKind.rest);
        expect(rest, isNotNull);
        expect(rest!.startedAt, clock.now);
        expect(rest.plannedDurationMs, 90000);
      },
    );

    test(
      'S-005 the haptic is owed exactly at the instant the countdown ends',
      () async {
        await surface.log();
        final haptics = WatchTimerHaptics(engine);

        final deadline = clock.now.add(const Duration(seconds: 90));
        expect(
          haptics.poll(deadline.subtract(const Duration(seconds: 1))),
          isEmpty,
          reason: 'a second early is early',
        );
        expect(haptics.poll(deadline), [
          WatchTimerMilestone(kind: WatchTimerKind.rest, at: deadline),
        ]);
        expect(
          haptics.poll(deadline.add(const Duration(minutes: 10))),
          isEmpty,
          reason: 'a countdown the user has been told about is told once',
        );
      },
    );

    test(
      'S-005 a screen-off gap fires the haptic, at the moment it was due',
      () async {
        await surface.log();
        final haptics = WatchTimerHaptics(engine);

        // Ten minutes pass with the screen off: no poll happened in between.
        clock.advance(const Duration(minutes: 10));

        expect(haptics.poll(clock.now), [
          WatchTimerMilestone(
            kind: WatchTimerKind.rest,
            at: DateTime.utc(2026, 7, 13, 17, 1, 30),
          ),
        ]);
      },
    );

    test(
      'S-005 a pause moves the deadline by the pause, not the tick count',
      () async {
        await surface.log();
        final haptics = WatchTimerHaptics(engine);
        final startedAt = clock.now;

        clock.advance(const Duration(seconds: 30));
        await engine.pauseTimer(kind: WatchTimerKind.rest);
        clock.advance(const Duration(seconds: 30));
        await engine.resumeTimer(kind: WatchTimerKind.rest);

        expect(
          haptics.poll(startedAt.add(const Duration(seconds: 90))),
          isEmpty,
          reason: 'the paused half-minute has not been counted yet',
        );
        expect(haptics.poll(startedAt.add(const Duration(seconds: 120))), [
          WatchTimerMilestone(
            kind: WatchTimerKind.rest,
            at: startedAt.add(const Duration(seconds: 120)),
          ),
        ]);
      },
    );

    test(
      'S-005 a rest timer is a wall clock after a kill, not a counter',
      () async {
        await surface.log();
        final deadline = clock.now.add(const Duration(seconds: 90));

        // A relaunch: a brand-new engine over the same storage, nothing handed
        // across in memory, and the same clock the watch would be holding.
        final relaunched = WatchSessionEngine(store, clock: clock.call);
        await relaunched.restore();

        expect(
          WatchTimerHaptics(relaunched).poll(deadline),
          [WatchTimerMilestone(kind: WatchTimerKind.rest, at: deadline)],
          reason: 'the countdown reads its own timestamp, not a counter',
        );
      },
    );
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
      await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90000);
      final haptics = WatchTimerHaptics(engine);

      clock.advance(const Duration(seconds: 60));
      await engine.stopTimer(kind: WatchTimerKind.rest);

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
}
