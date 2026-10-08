// Watch rest surface — the count-up, one Next, and the twin of the watchOS
// `WatchRestSurfaceTests.swift`.
//
// Plan: `docs/plans/2026-10-08-18b-watch-rest-count-up-plan.md`.
// Scenario mapping:
//   S-161 a rest counts up and survives the screen turning off → `S-161 ...`
//   S-162 Next ends the rest and returns to logging            → `S-162 ...`
//   S-163 logging ends a running rest first                    → `S-163 ...`
//
// A rest is a count-up with no length, and its elapsed is derived from the
// persisted row at the instant it is read: every case below moves a clock,
// never a ticker, which is what makes the screen-off case the same case as the
// on-screen one. The surface is built and pumped with `tester.pump`, never a
// real delay — FakeAsync never advances real time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_rest_screen.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_timer_math.dart';

/// Deterministic clock: the engine and the surface read time only through an
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
    clock = _Clock(DateTime.utc(2026, 10, 8, 10));
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

  group("S-161 / S-162 / S-163 the wrist's rest surface", () {
    test('S-161 the rest elapsed counts up and survives the screen turning off',
        () async {
      await surface.log();
      expect(surface.isResting, isTrue, reason: 'logging a set starts a rest');
      expect(surface.restElapsedSeconds(), 0, reason: 'the rest starts at 0:00');

      clock.advance(const Duration(seconds: 7));
      expect(
        surface.restElapsedSeconds(),
        7,
        reason: 'a count-up, not a countdown',
      );

      // Four minutes with the screen off, then a relaunch over the same store.
      clock.advance(const Duration(minutes: 3, seconds: 53));
      final relaunched = WatchSessionEngine(store, clock: clock.call);
      await relaunched.restore();
      final restored = WatchLoggingState(engine: relaunched, clock: clock.call);

      expect(restored.isResting, isTrue, reason: 'the restore keeps the rest');
      expect(
        restored.restElapsedSeconds(),
        240,
        reason: 'the elapsed is derived from the row, not from a ticker',
      );
    });

    test('S-162 Next ends the rest at the tap instant', () async {
      await surface.log();
      clock.advance(const Duration(seconds: 30));
      expect(surface.restElapsedSeconds(), 30);

      await surface.endRest();

      expect(surface.isResting, isFalse, reason: 'Next returns to logging');
      expect(surface.restElapsedSeconds(), isNull);
      final rest = engine.timerFor(WatchTimerKind.rest)!;
      expect(rest.stoppedAt, clock.now, reason: 'the tap instant ends the rest');
      expect(
        activeElapsedMs(rest, clock.now.add(const Duration(seconds: 40))),
        30000,
        reason: 'a stopped timer keeps the time it had reached',
      );
    });

    test('S-163 logging ends a running rest first', () async {
      await surface.log(); // set #1, rest #1 starts
      clock.advance(const Duration(seconds: 30));
      await surface.endRest(); // Next ends rest #1

      clock.advance(const Duration(seconds: 40)); // 10:01:10
      await surface.log(); // set #2, rest #2 starts
      final rest2StartedAt = engine.timerFor(WatchTimerKind.rest)!.startedAt;

      clock.advance(const Duration(seconds: 50)); // 10:02:00
      await surface.log(); // set #3, ends rest #2 first, starts rest #3

      final restRows = (await store.readAll()).timers
          .where((row) => row.kind == WatchTimerKind.rest)
          .toList();
      final stoppedRest2 = restRows.firstWhere(
        (row) => row.startedAt == rest2StartedAt && row.stoppedAt != null,
      );
      expect(
        stoppedRest2.stoppedAt,
        clock.now,
        reason: "logging the next set ends the running rest at that log's "
            'instant',
      );
      final newest = engine.timerFor(WatchTimerKind.rest)!;
      expect(newest.stoppedAt, isNull, reason: 'the follow-on rest is running');
      expect(newest.startedAt, isNot(rest2StartedAt));
      expect(
        restRows.map((row) => row.startedAt).toSet().length,
        3,
        reason: 'one rest per logged set',
      );
      expect(engine.entries.length, 3);
    });

    test('a rest left over from a finished session shows nothing', () async {
      await surface.log();
      expect(surface.isResting, isTrue);

      await engine.finishSession();

      expect(surface.isResting, isFalse);
      expect(surface.restElapsedSeconds(), isNull);
    });
  });

  group('the rest surface renders', () {
    testWidgets('the elapsed and exactly one control, Next', (tester) async {
      await surface.log();
      var nextTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WatchRestScreen(state: surface, onNext: () => nextTapped = true),
        ),
      );
      await tester.pump();

      expect(find.text('sx-bench'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);

      clock.advance(const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:07'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      expect(surface.isResting, isFalse);
      expect(nextTapped, isTrue);

      // Dispose the screen so its ticker does not outlive the test.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
