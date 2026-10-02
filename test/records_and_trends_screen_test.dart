// Records & Trends and Exercise Progress — the two screens Phase 3 adds, and
// the Stats header entry point that opens the first of them.
//
// Plan: `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/`.
//
// Every scenario runs on both repository implementations. The harness is opened
// and seeded in `setUp` and never inside a `testWidgets` body: a widget test
// body runs under `FakeAsync`, where Hive's real file I/O never settles and the
// test hangs.
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/recent_pr_list.dart';
import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// The height every scenario pumps at: tall enough that a section header, an
/// entry and a chart below it are all laid out, so an assertion on a widget's
/// absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// A completed session holding one set effort of [reps] reps at [weightKg].
Future<void> _seedSetSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required String exerciseId,
  required double weightKg,
  required int reps,
}) async {
  await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-$exerciseId',
    exerciseId: exerciseId,
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: weightKg,
    repsBase: reps,
  );
}

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// The label a training day [daysAgo] days back reads as in a history list.
String _dayLabel(int daysAgo) =>
    OmniDateUtils.formatShort(DateTime.now().subtract(Duration(days: daysAgo)));

/// The all-time best [weightKg] × [reps] reads as, on the weight axis.
String _e1RmLabel(double weightKg, int reps, SettingsState settings) {
  final value = StatsProgressService.epley1RM(weightKg, reps)!;
  return '${UnitFormatter.formatWeightValue(value, settings)} '
      '${UnitFormatter.weightLabel(settings)}';
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Records & Trends / Exercise Progress — ${harness.name}', () {
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

      Future<void> pump(WidgetTester tester, Widget screen) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
      }

      Widget recordsScreen() => RecordsAndTrendsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
      );

      // ─── S-910: nothing logged yet ─────────────────────────────────────────

      testWidgets('S-910 an empty history shows the Records & Trends empty '
          'state', (tester) async {
        await pump(tester, recordsScreen());

        expect(find.text('Records & Trends'), findsOneWidget);
        expect(find.text('No sessions yet'), findsOneWidget);
        expect(
          find.text('Complete your first session to see stats here.'),
          findsOneWidget,
        );
        expect(find.text('Resistance'), findsNothing);
        expect(find.text('Sports'), findsNothing);
        expect(find.byType(RecentPRList), findsNothing);
      });

      // The entry list can never offer an id with no history, so this guard is
      // only reachable by a direct push — it exists so a stale id cannot throw.
      testWidgets('S-910 an id with no history shows the guard empty state '
          'instead of throwing', (tester) async {
        await pump(
          tester,
          ExerciseProgressScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            exerciseId: 'ex-never-logged',
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Exercise Progress'), findsOneWidget);
        expect(find.text('No history for this exercise'), findsOneWidget);
        expect(
          find.text('Log it in a completed session to see its progress here.'),
          findsOneWidget,
        );
        expect(find.byType(ScrollableTrendChart), findsNothing);
      });

      // ─── S-912: the search field filters the exercise list ────────────────

      group('S-912', () {
        setUp(() async {
          await seedExercise(
            repo,
            id: 'ex-bench',
            name: 'Bench Press',
            capabilities: const ['load', 'reps'],
          );
          await seedExercise(
            repo,
            id: 'ex-incline',
            name: 'Incline Bench Press',
            capabilities: const ['load', 'reps'],
          );
          await seedExercise(
            repo,
            id: 'ex-squat',
            name: 'Back Squat',
            capabilities: const ['rounds'],
          );
          // One training day for Bench Press, three for Incline Bench Press, so
          // training-day share and name order disagree: share puts the longer
          // name first.
          await _seedSetSession(
            repo,
            sessionId: 's-bench',
            daysAgo: 2,
            exerciseId: 'ex-bench',
            weightKg: 100,
            reps: 5,
          );
          for (final daysAgo in const [5, 3, 1]) {
            await _seedSetSession(
              repo,
              sessionId: 's-incline-$daysAgo',
              daysAgo: daysAgo,
              exerciseId: 'ex-incline',
              weightKg: 80,
              reps: 5,
            );
          }
          await seedSession(repo, sessionId: 's-squat', daysAgo: 1);
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-squat',
            effortId: 'eff-squat',
            exerciseId: 'ex-squat',
            rounds: [roundInstance('eff-squat', 0, durationSecs: 120)],
          );
        });

        testWidgets('the search field narrows the list by exercise name', (
          tester,
        ) async {
          await pump(tester, recordsScreen());

          // Entries are addressed by id: the PR list above the sections can
          // carry the same exercise names, so a name alone is ambiguous.
          Finder entry(String exerciseId) =>
              find.byKey(Key('records_entry_$exerciseId'));

          final field = find.byKey(
            const Key('records_and_trends_search_field'),
          );
          expect(field, findsOneWidget);

          // Unfiltered: one header per section that has an exercise, and one
          // entry per exercise.
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.text('Sports'), findsOneWidget);
          expect(entry('ex-bench'), findsOneWidget);
          expect(entry('ex-incline'), findsOneWidget);
          expect(entry('ex-squat'), findsOneWidget);
          expect(
            find.descendant(
              of: entry('ex-bench'),
              matching: find.text('Bench Press'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: entry('ex-squat'),
              matching: find.text('Back Squat'),
            ),
            findsOneWidget,
          );
          // Incline Bench Press has three training days to Bench Press's one,
          // so it leads even though its name sorts later.
          expect(
            tester.getTopLeft(entry('ex-incline')).dy,
            lessThan(tester.getTopLeft(entry('ex-bench')).dy),
          );

          // A query both presses share keeps their section and drops the
          // section that has no match.
          await tester.enterText(field, 'bench');
          await tester.pumpAndSettle();
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.text('Sports'), findsNothing);
          expect(entry('ex-bench'), findsOneWidget);
          expect(entry('ex-incline'), findsOneWidget);
          expect(entry('ex-squat'), findsNothing);
          expect(
            tester.getTopLeft(entry('ex-incline')).dy,
            lessThan(tester.getTopLeft(entry('ex-bench')).dy),
          );

          // A query only the round exercise matches hides the other section.
          await tester.enterText(field, 'squat');
          await tester.pumpAndSettle();
          expect(find.text('Resistance'), findsNothing);
          expect(find.text('Sports'), findsOneWidget);
          expect(entry('ex-squat'), findsOneWidget);
          expect(entry('ex-bench'), findsNothing);
          expect(entry('ex-incline'), findsNothing);

          // A query nothing matches leaves no section at all, and the field is
          // still there to clear.
          await tester.enterText(field, 'zzzz');
          await tester.pumpAndSettle();
          expect(find.text('Resistance'), findsNothing);
          expect(find.text('Sports'), findsNothing);
          expect(entry('ex-bench'), findsNothing);
          expect(entry('ex-incline'), findsNothing);
          expect(entry('ex-squat'), findsNothing);
          expect(field, findsOneWidget);

          // Clearing restores the unfiltered list.
          await tester.enterText(field, '');
          await tester.pumpAndSettle();
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.text('Sports'), findsOneWidget);
          expect(entry('ex-bench'), findsOneWidget);
          expect(entry('ex-incline'), findsOneWidget);
          expect(entry('ex-squat'), findsOneWidget);
        });
      });

      // ─── S-913: the Stats header icon opens Records & Trends ──────────────

      group('S-913', () {
        setUp(() async {
          await seedExercise(
            repo,
            id: 'ex-bench',
            name: 'Bench Press',
            capabilities: const ['load', 'reps'],
          );
          await seedExercise(
            repo,
            id: 'ex-squat',
            name: 'Back Squat',
            capabilities: const ['load', 'reps'],
          );
          // Two completed sessions, each with a PR on both lifts: the best
          // e1RM lands on the same day for both, so the PR list order is the
          // name tiebreak — Back Squat before Bench Press.
          await _seedSetSession(
            repo,
            sessionId: 's-a-bench',
            daysAgo: 3,
            exerciseId: 'ex-bench',
            weightKg: 100,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-a-squat',
            daysAgo: 3,
            exerciseId: 'ex-squat',
            weightKg: 100,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-b-bench',
            daysAgo: 2,
            exerciseId: 'ex-bench',
            weightKg: 120,
            reps: 3,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-b-squat',
            daysAgo: 2,
            exerciseId: 'ex-squat',
            weightKg: 140,
            reps: 5,
          );
          // A completed rolling session: it counts as a session without
          // contributing to the time total.
          final start = fixtureStart - 86400000;
          await repo.createSession(
            TrainingSession(
              id: 's-rolling',
              ownerUserId: 'user-1',
              startedAtMs: start,
              endedAtMs: start + 3600000,
              isRolling: true,
              createdAtMs: start,
              updatedAtMs: start,
            ),
          );
          await repo.createSegment(
            SessionSegment(
              id: 'seg-s-rolling',
              sessionId: 's-rolling',
              orderIndex: 0,
              segmentType: 'workout',
              name: 'Main Workout',
              createdAtMs: start,
              updatedAtMs: start,
            ),
          );
          await seedSetEffort(
            repo,
            segmentId: 'seg-s-rolling',
            effortId: 'eff-s-rolling',
            exerciseId: 'ex-bench',
            entryCount: 1,
            hasExtraWeight: false,
            weightFactor: 90,
            repsBase: 5,
          );
        });

        testWidgets('the header icon opens Records & Trends with the same '
            'figures', (tester) async {
          await pump(
            tester,
            StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          );

          // The entry point exists and carries a label.
          expect(find.byTooltip('Records & Trends'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Records & Trends',
            ),
            findsWidgets,
          );

          // The all-time figures the Stats screen already shows.
          final statsPills = _textsUnder(find.byType(OmniSurface).first);
          expect(statsPills, contains('SESSIONS'));
          expect(statsPills, contains('TIME'));
          expect(statsPills, contains('STREAK'));

          // The PR list is not on this screen: it lives in Records & Trends.
          expect(find.byType(RecentPRList), findsNothing);

          // Tapping through lands on Records & Trends with the same figures.
          await tester.tap(find.byTooltip('Records & Trends'));
          await tester.pumpAndSettle();

          expect(find.text('Records & Trends'), findsOneWidget);
          expect(_textsUnder(find.byType(OmniSurface).first), statsPills);

          // The PR list Records & Trends renders, in the same order.
          final trendPrs = _textsUnder(find.byType(RecentPRList));
          expect(trendPrs, contains('Recent PRs'));
          expect(trendPrs, contains('Back Squat'));
          expect(trendPrs, contains('Bench Press'));
          expect(
            tester
                .getTopLeft(
                  find.descendant(
                    of: find.byType(RecentPRList),
                    matching: find.text('Back Squat'),
                  ),
                )
                .dy,
            lessThan(
              tester
                  .getTopLeft(
                    find.descendant(
                      of: find.byType(RecentPRList),
                      matching: find.text('Bench Press'),
                    ),
                  )
                  .dy,
            ),
          );
        });
      });

      // ─── the Recent PRs weight unit ───────────────────────────────────────
      //
      // Records & Trends is the PR list's only host since Stats PR 4c removed
      // the legacy sections, so the unit conversion the retired Stats-screen
      // test guarded is asserted here.

      group('Recent PRs weight unit', () {
        setUp(() async {
          await seedExercise(
            repo,
            id: 'ex-bench',
            name: 'Bench Press',
            capabilities: const ['load', 'reps'],
          );
          await _seedSetSession(
            repo,
            sessionId: 's-lbs',
            daysAgo: 2,
            exerciseId: 'ex-bench',
            weightKg: 100,
            reps: 5,
          );
          await settingsState.setPreferredWeightUnit('lbs');
        });

        testWidgets('a PR row reads the record in pounds when the weight unit '
            'preference is pounds', (tester) async {
          await pump(tester, recordsScreen());

          final expected = _e1RmLabel(100, 5, settingsState);
          expect(
            expected,
            endsWith('lbs'),
            reason: 'the fixture must exercise the pounds preference',
          );

          final prTexts = _textsUnder(find.byType(RecentPRList));
          expect(prTexts, contains('Recent PRs'));
          expect(prTexts, contains('Bench Press'));
          expect(prTexts, contains(expected));
          expect(
            prTexts.where((text) => text.endsWith('kg')),
            isEmpty,
            reason: 'the row must not read the stored kilograms',
          );
        });
      });

      // ─── S-914: an entry opens that exercise's history ────────────────────

      group('S-914', () {
        setUp(() async {
          await seedExercise(
            repo,
            id: 'ex-row',
            name: 'Barbell Row',
            capabilities: const ['load', 'reps'],
          );
          await seedExercise(
            repo,
            id: 'ex-pull',
            name: 'Pull-up',
            capabilities: const ['reps'],
          );
          await _seedSetSession(
            repo,
            sessionId: 's-row-old',
            daysAgo: 3,
            exerciseId: 'ex-row',
            weightKg: 100,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-row-new',
            daysAgo: 1,
            exerciseId: 'ex-row',
            weightKg: 120,
            reps: 3,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-pull',
            daysAgo: 2,
            exerciseId: 'ex-pull',
            weightKg: 0,
            reps: 8,
          );
        });

        testWidgets('an entry opens the exercise history and back returns to '
            'the list', (tester) async {
          await pump(tester, recordsScreen());

          final entry = find.byKey(const Key('records_entry_ex-row'));
          await tester.scrollUntilVisible(
            entry,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(entry);
          await tester.pumpAndSettle();

          expect(find.text('Exercise Progress'), findsOneWidget);
          expect(find.text('Barbell Row'), findsOneWidget);
          expect(find.byType(ScrollableTrendChart), findsOneWidget);
          expect(find.text(_e1RmLabel(120, 3, settingsState)), findsWidgets);

          final progressHeader = find.ancestor(
            of: find.text('Exercise Progress'),
            matching: find.byType(OmniBackHeader),
          );
          await tester.tap(
            find.descendant(
              of: progressHeader,
              matching: find.byIcon(Icons.arrow_back),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Exercise Progress'), findsNothing);
          expect(find.text('Records & Trends'), findsOneWidget);
          expect(find.byKey(const Key('records_entry_ex-row')), findsOneWidget);
        });
      });

      // ─── S-915: one exercise's best, trend and recent days ────────────────

      group('S-915', () {
        setUp(() async {
          await seedExercise(
            repo,
            id: 'ex-row',
            name: 'Barbell Row',
            capabilities: const ['load', 'reps'],
          );
          await _seedSetSession(
            repo,
            sessionId: 's-row-3',
            daysAgo: 3,
            exerciseId: 'ex-row',
            weightKg: 100,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-row-2',
            daysAgo: 2,
            exerciseId: 'ex-row',
            weightKg: 110,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-row-1',
            daysAgo: 1,
            exerciseId: 'ex-row',
            weightKg: 120,
            reps: 5,
          );
          // A session that never ended, five days back, carrying a far heavier
          // set. It is not history, so it must not appear anywhere.
          final cancelledStart = fixtureStart - 4 * 86400000;
          await repo.createSession(
            TrainingSession(
              id: 's-cancelled',
              ownerUserId: 'user-1',
              startedAtMs: cancelledStart,
              endedAtMs: null,
              createdAtMs: cancelledStart,
              updatedAtMs: cancelledStart,
            ),
          );
          await repo.createSegment(
            SessionSegment(
              id: 'seg-s-cancelled',
              sessionId: 's-cancelled',
              orderIndex: 0,
              segmentType: 'workout',
              name: 'Main Workout',
              createdAtMs: cancelledStart,
              updatedAtMs: cancelledStart,
            ),
          );
          await seedSetEffort(
            repo,
            segmentId: 'seg-s-cancelled',
            effortId: 'eff-s-cancelled',
            exerciseId: 'ex-row',
            entryCount: 1,
            hasExtraWeight: false,
            weightFactor: 999,
            repsBase: 1,
          );
        });

        testWidgets('the history reads one best, one point per training day '
            'and the recent days newest first', (tester) async {
          await pump(
            tester,
            ExerciseProgressScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              exerciseId: 'ex-row',
            ),
          );

          expect(find.text('Exercise Progress'), findsOneWidget);
          expect(find.text('Barbell Row'), findsOneWidget);

          // The best is the newest completed day's e1RM, not the cancelled
          // session's — which would read far higher.
          expect(find.text(_e1RmLabel(120, 5, settingsState)), findsWidgets);
          expect(find.textContaining('1032'), findsNothing);
          expect(find.text('3'), findsOneWidget);

          // One point per training day, oldest first.
          final chart = tester.widget<ScrollableTrendChart>(
            find.byType(ScrollableTrendChart),
          );
          expect(chart.pointCount, 3);
          final spots = tester
              .widget<LineChart>(find.byType(LineChart))
              .data
              .lineBarsData
              .single
              .spots;
          expect(spots, hasLength(3));
          expect(spots[0].y, lessThan(spots[1].y));
          expect(spots[1].y, lessThan(spots[2].y));

          // The recent days run newest first, one row per day, and stop at the
          // three days that ended.
          final history = _textsUnder(find.byType(OmniSurface).at(2));
          expect(history, hasLength(6));
          expect(history[0], _dayLabel(1));
          expect(history[2], _dayLabel(2));
          expect(history[4], _dayLabel(3));
          expect(find.text(_dayLabel(5)), findsNothing);
        });
      });
    });
  }

  // The header chart icon is the only entry point into Records & Trends. A
  // static source scan, so it runs once rather than once per repository harness.
  test('StatsScreen is the only file in lib/ that constructs '
      'RecordsAndTrendsScreen', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('records_and_trends_screen.dart')) continue;
      if (entity.readAsStringSync().contains('RecordsAndTrendsScreen(')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, ['lib/features/stats/stats_screen.dart']);
  });

  // Exercise Progress is reached from Records & Trends and from an Instruments
  // row, and from nowhere else. A static source scan, so it runs once rather
  // than once per repository harness.
  test('only Records & Trends and the Instruments list construct '
      'ExerciseProgressScreen', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The screen's own declaration is not a construction site.
      if (entity.path.endsWith('exercise_progress_screen.dart')) continue;
      if (entity.readAsStringSync().contains('ExerciseProgressScreen(')) {
        offenders.add(entity.path);
      }
    }
    offenders.sort();
    expect(offenders, [
      'lib/features/stats/records_and_trends_screen.dart',
      'lib/features/stats/widgets/instrument_list.dart',
    ]);
  });
}
