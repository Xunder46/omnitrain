// The rated-weeks count (Stats 99b, Phase 3) — the screen half of P1's
// service change, on both repository implementations. Scenarios S-17107 and
// S-17108 of `docs/plans/2026-11-02-99b-stats-rated-weeks-plan/`.
//
// The count is the number of the last 12 seven-day weeks ending today (current
// ones included) that hold a rated completed session. That one number drives
// the Mix note, the locked Signals line and the load measure.
//
// The harness is opened and seeded in `setUp` and never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

// ─── readers ────────────────────────────────────────────────────────────────

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Text), matchRoot: true)
          .evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

// ─── fixtures ───────────────────────────────────────────────────────────────

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// [daysAgo]'s day at [hour] o'clock, in epoch ms.
int _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
}

/// One completed session with one segment. Written directly because the shared
/// `seedSession` cannot express a rating and marks a rolling session
/// unfinished.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  int? rating,
  bool isRolling = false,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      sessionFeeling: rating,
      isRolling: isRolling,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

/// A rated 60-minute lifting-only session [daysAgo] days back: every second of
/// it is the session's resistance remainder, so it needs no effort to be
/// measured (D-905), and the rating is what the rated-weeks count reads.
Future<void> _seedLifting(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  int minutes = 60,
  int? rating,
  int hour = 9,
}) async {
  final start = _at(daysAgo, hour);
  await _seedSession(
    repo,
    sessionId: sessionId,
    startedAtMs: start,
    endedAtMs: start + minutes * 60000,
    rating: rating,
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Rated weeks — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      Future<void> pumpStats(
        WidgetTester tester, {
        Size size = _kTallViewport,
        double textScale = 1.0,
      }) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MaterialApp(
              home: StatsScreen(
                workoutState: workoutState,
                settingsState: settingsState,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // ─── S-17107 ─────────────────────────────────────────────────────────

      group('S-17107 current weeks count', () {
        setUp(() async {
          await _seedLifting(
            repo,
            sessionId: 's-rated-today',
            daysAgo: 0,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-8',
            daysAgo: 8,
            rating: 4,
          );
        });

        testWidgets('two rated weeks drive the locked line and the Mix note', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('signals_locked_line'))), [
            'Unlocks after 4 weeks of rating your workouts — 2 of 4 so far.',
          ]);
          expect(
            _textsUnder(find.byKey(const Key('mix_baseline_note'))),
            everyElement(contains('(2 of 4 so far)')),
          );
          expect(find.byKey(const Key('signals_layer')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-17107 twin — two rated sessions in one week', () {
        setUp(() async {
          await _seedLifting(
            repo,
            sessionId: 's-rated-today',
            daysAgo: 0,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-3',
            daysAgo: 3,
            rating: 4,
          );
        });

        testWidgets('the same week counts once', (tester) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('signals_locked_line'))), [
            'Unlocks after 4 weeks of rating your workouts — 1 of 4 so far.',
          ]);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17108 ─────────────────────────────────────────────────────────

      group('S-17108 four current weeks unlock Signals', () {
        setUp(() async {
          await _seedLifting(
            repo,
            sessionId: 's-rated-0',
            daysAgo: 0,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-8',
            daysAgo: 8,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-15',
            daysAgo: 15,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-22',
            daysAgo: 22,
            rating: 4,
          );
        });

        testWidgets('the load measure shows and the Signals layer renders', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('signals_locked')), findsNothing);
          expect(find.byKey(const Key('mix_baseline_note')), findsNothing);
          expect(find.byKey(const Key('mix_usual_bar')), findsNothing);
          expect(_textsUnder(find.byKey(const Key('mix_explainer'))), [
            'Your training split by how hard each session felt.',
          ]);
          expect(find.byKey(const Key('signals_layer')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-17108 twin — three current weeks stay locked', () {
        setUp(() async {
          await _seedLifting(
            repo,
            sessionId: 's-rated-0',
            daysAgo: 0,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-8',
            daysAgo: 8,
            rating: 4,
          );
          await _seedLifting(
            repo,
            sessionId: 's-rated-15',
            daysAgo: 15,
            rating: 4,
          );
        });

        testWidgets('the locked line and the Mix note remain', (tester) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('signals_locked_line'))), [
            'Unlocks after 4 weeks of rating your workouts — 3 of 4 so far.',
          ]);
          expect(find.byKey(const Key('mix_baseline_note')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    });
  }
}
