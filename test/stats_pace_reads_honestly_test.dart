// Plan 209 — Stats pace reads honestly: a faster run reads as an improvement,
// and a trend line plots one measure.
//
// `docs/plans/2026-11-15-209-stats-pace-reads-honestly-plan/
// 2026-11-15-209-stats-pace-reads-honestly-plan.md`.
//
// S-21004 and S-21005 pin the pace change chip's text and colour on a
// pre-built `InstrumentRow` — no repository, no Hive, no real timers, so they
// are plain `testWidgets` bodies. S-21006 and S-21007 pin the per-day series
// (`points` keeps one point per training day, each in the metric that day
// reads; `trendPoints` keeps only the best metric's days) on both repository
// implementations. S-21008 and S-21009 pin the two drawings reading
// `trendPoints` while RECENT SESSIONS keeps `points`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_row.dart';
import 'package:omnitrain/features/stats/widgets/instrument_sparkline.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

// ─── widget fixtures ────────────────────────────────────────────────────────

/// The app's real dark ThemeData, built the way
/// `test/instrument_list_screen_test.dart`'s pump builds it.
ThemeData _theme() {
  final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);
  return buildTheme(
    theme: AppTheme.abyssalNeon,
    brightness: Brightness.dark,
    secondary: colors.secondary,
    background: colors.backgroundBottom,
    surface: colors.surface,
    textPrimary: colors.textDominant,
    textSecondary: colors.textSecondary,
    divider: colors.divider,
    onPrimary: getOnPrimaryForTheme(AppTheme.abyssalNeon),
    onSecondary: getOnSecondaryForTheme(AppTheme.abyssalNeon),
  );
}

Future<SettingsState> _settings() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setPreferredWeightUnit('kg');
  await settings.setPreferredDistanceUnit('km');
  return settings;
}

Future<void> _pumpRow(WidgetTester tester, InstrumentRow row) async {
  final settings = await _settings();
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: Scaffold(
        body: InstrumentRowTile(
          row: row,
          settingsState: settings,
          themeColors: OmniTheme.colorsForTheme(settings.appTheme),
          onTap: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A pace row whose window reads [bestValue] and whose previous range read
/// [previousValue], in seconds per kilometre.
InstrumentRow _paceRow({required double bestValue, required double previousValue}) =>
    InstrumentRow(
      summary: ExerciseMetricSummary(
        exerciseId: 'ex-run',
        name: 'Easy Run',
        section: ExerciseSection.cardio,
        best: NativeValue(metric: NativeMetric.pace, value: bestValue),
        points: const [],
        lastTrainedMs: fixtureStart,
        sessionCount: 1,
      ),
      previousValue: NativeValue(
        metric: NativeMetric.pace,
        value: previousValue,
      ),
    );

// ─── service fixtures (copied from instrument_list_service_test.dart) ───────

/// A `timed` effort on [segmentId] with no entries yet.
Future<void> addTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
}) => repo.createEffort(
  SegmentEffort(
    id: effortId,
    segmentId: segmentId,
    orderIndex: 0,
    effortKind: 'timed',
    exerciseId: exerciseId,
    createdAtMs: fixtureStart,
    updatedAtMs: fixtureStart,
  ),
);

/// One finished timed entry of [effortId], [durationSecs] long, with a distance
/// row of [metres] when it is given.
Future<void> seedTimedEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required int durationSecs,
  double? metres,
}) async {
  await repo.createTimedInstance(
    timedInstance(
      effortId,
      entryIndex,
      durationSecs: durationSecs,
      entryIndex: entryIndex,
    ),
  );
  if (metres != null) {
    await repo.createObservation(
      distanceRow(effortId, entryIndex, metres, atMs: fixtureRowAt(entryIndex)),
    );
  }
}

void main() {
  group('the pace change chip', () {
    testWidgets('S-21004 a faster pace reads up in the primary colour', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        _paceRow(bestValue: 350, previousValue: 360),
      );

      final chip = find.byKey(const Key('instrument_change_ex-run'));
      final text = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)),
      );
      expect(text.data, '↑ 0:10 /km');
      expect(
        text.style?.color,
        Theme.of(tester.element(chip)).colorScheme.primary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('S-21005 a slower pace reads down in the error colour', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        _paceRow(bestValue: 370, previousValue: 360),
      );

      final chip = find.byKey(const Key('instrument_change_ex-run'));
      final text = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)),
      );
      expect(text.data, '↓ 0:10 /km');
      expect(
        text.style?.color,
        Theme.of(tester.element(chip)).colorScheme.error.withValues(
          alpha: 0.8,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the per-day series', () {
    for (final factory in harnessFactories) {
      final harness = factory();

      group('on ${harness.name}', () {
        late WorkoutRepository repo;

        setUp(() async => repo = await harness.open());
        tearDown(() async => await harness.close());

        test('S-21006 a pace row plots only its pace days', () async {
          await seedExercise(
            repo,
            id: 'ex-run',
            name: 'Easy Run',
            capabilities: ['time', 'distance'],
          );
          await seedSession(repo, sessionId: 's-run-a', daysAgo: 3);
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-run-a',
            effortId: 'eff-run-a',
            exerciseId: 'ex-run',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-run-a',
            entryIndex: 0,
            durationSecs: 1800,
            metres: 5000,
          );

          await seedSession(repo, sessionId: 's-run-b', daysAgo: 2);
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-run-b',
            effortId: 'eff-run-b',
            exerciseId: 'ex-run',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-run-b',
            entryIndex: 0,
            durationSecs: 1200,
          );

          await seedSession(repo, sessionId: 's-run-c', daysAgo: 1);
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-run-c',
            effortId: 'eff-run-c',
            exerciseId: 'ex-run',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-run-c',
            entryIndex: 0,
            durationSecs: 1750,
            metres: 5000,
          );

          final summaries = await StatsProgressService(repo)
              .computeExerciseMetrics(fromMs: null, toMs: null);

          final run = summaries
              .where((s) => s.exerciseId == 'ex-run')
              .toList();
          expect(run, hasLength(1));
          expect(run.single.best.metric, NativeMetric.pace);
          expect(
            run.single.best.value,
            closeTo(350.0, 0.01),
            reason: 'the best pace of 1800/5 and 1750/5',
          );
          // One point per training day, each in the metric that day reads.
          expect(run.single.points, hasLength(3));
          expect(run.single.points[0].value.metric, NativeMetric.pace);
          expect(run.single.points[0].value.value, closeTo(360.0, 0.01));
          expect(run.single.points[1].value.metric, NativeMetric.duration);
          expect(run.single.points[1].value.value, closeTo(1200.0, 0.01));
          expect(run.single.points[2].value.metric, NativeMetric.pace);
          expect(run.single.points[2].value.value, closeTo(350.0, 0.01));
          // Only the days that read in the best metric draw.
          expect(run.single.trendPoints, hasLength(2));
          expect(run.single.trendPoints[0].value.metric, NativeMetric.pace);
          expect(run.single.trendPoints[0].value.value, closeTo(360.0, 0.01));
          expect(run.single.trendPoints[1].value.metric, NativeMetric.pace);
          expect(run.single.trendPoints[1].value.value, closeTo(350.0, 0.01));
        });

        test('S-21007 one-metric exercises keep every day', () async {
          await seedExercise(
            repo,
            id: 'ex-lift',
            name: 'Squat',
            capabilities: ['load'],
          );
          await seedExercise(
            repo,
            id: 'ex-easy',
            name: 'Easy Bike',
            capabilities: ['time'],
          );
          for (final day in const [('a', 3), ('b', 2), ('c', 1)]) {
            final (suffix, daysAgo) = day;
            await seedSession(
              repo,
              sessionId: 's-lift-$suffix',
              daysAgo: daysAgo,
            );
            await seedSetEffort(
              repo,
              segmentId: 'seg-s-lift-$suffix',
              effortId: 'eff-lift-$suffix',
              exerciseId: 'ex-lift',
              entryCount: 1,
              hasExtraWeight: false,
              weightFactor: 100.0,
              repsBase: 5,
            );
            await seedSession(
              repo,
              sessionId: 's-easy-$suffix',
              daysAgo: daysAgo,
            );
            await addTimedEffort(
              repo,
              segmentId: 'seg-s-easy-$suffix',
              effortId: 'eff-easy-$suffix',
              exerciseId: 'ex-easy',
            );
            await seedTimedEntry(
              repo,
              effortId: 'eff-easy-$suffix',
              entryIndex: 0,
              durationSecs: 600,
            );
          }

          final summaries = await StatsProgressService(repo)
              .computeExerciseMetrics(fromMs: null, toMs: null);

          for (final id in const ['ex-lift', 'ex-easy']) {
            final summary = summaries
                .where((s) => s.exerciseId == id)
                .single;
            expect(summary.points, hasLength(3), reason: id);
            for (final point in summary.points) {
              expect(
                point.value.metric,
                summary.best.metric,
                reason: '$id plots only ${summary.best.metric} days',
              );
            }
            // One metric per exercise: the trend keeps every day too.
            expect(summary.trendPoints, hasLength(3), reason: id);
            expect(
              [for (final point in summary.trendPoints) point.value.metric],
              [for (final point in summary.points) point.value.metric],
              reason: id,
            );
            expect(
              [for (final point in summary.trendPoints) point.value.value],
              [for (final point in summary.points) point.value.value],
              reason: id,
            );
          }
        });
      });
    }
  });

  group('the drawings behind a summary', () {
    testWidgets('S-21008 the Instruments sparkline plots only the days that '
        'read in the best metric', (tester) async {
      const dayA = 1700000000000;
      const dayB = 1700086400000;
      const dayC = 1700172800000;
      const summary = ExerciseMetricSummary(
        exerciseId: 'ex-run',
        name: 'Easy Run',
        section: ExerciseSection.cardio,
        best: NativeValue(metric: NativeMetric.pace, value: 350),
        points: [
          ExerciseMetricPoint(
            dayMs: dayA,
            value: NativeValue(metric: NativeMetric.pace, value: 360),
          ),
          ExerciseMetricPoint(
            dayMs: dayB,
            value: NativeValue(metric: NativeMetric.duration, value: 1200),
          ),
          ExerciseMetricPoint(
            dayMs: dayC,
            value: NativeValue(metric: NativeMetric.pace, value: 350),
          ),
        ],
        lastTrainedMs: dayC,
        sessionCount: 3,
      );

      await _pumpRow(tester, InstrumentRow(summary: summary));

      final sparkline = tester.widget<InstrumentSparkline>(
        find.byKey(const Key('instrument_sparkline_ex-run')),
      );
      expect(sparkline.points, hasLength(2));
      for (final point in sparkline.points) {
        expect(point.value.metric, NativeMetric.pace);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('S-21009 Exercise Progress charts trendPoints and lists every '
        'training day', (tester) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await seedExercise(
        repo,
        id: 'ex-run',
        name: 'Easy Run',
        capabilities: ['time', 'distance'],
      );
      await seedSession(repo, sessionId: 's-run-a', daysAgo: 3);
      await addTimedEffort(
        repo,
        segmentId: 'seg-s-run-a',
        effortId: 'eff-run-a',
        exerciseId: 'ex-run',
      );
      await seedTimedEntry(
        repo,
        effortId: 'eff-run-a',
        entryIndex: 0,
        durationSecs: 1800,
        metres: 5000,
      );
      await seedSession(repo, sessionId: 's-run-b', daysAgo: 2);
      await addTimedEffort(
        repo,
        segmentId: 'seg-s-run-b',
        effortId: 'eff-run-b',
        exerciseId: 'ex-run',
      );
      await seedTimedEntry(
        repo,
        effortId: 'eff-run-b',
        entryIndex: 0,
        durationSecs: 1200,
      );
      await seedSession(repo, sessionId: 's-run-c', daysAgo: 1);
      await addTimedEffort(
        repo,
        segmentId: 'seg-s-run-c',
        effortId: 'eff-run-c',
        exerciseId: 'ex-run',
      );
      await seedTimedEntry(
        repo,
        effortId: 'eff-run-c',
        entryIndex: 0,
        durationSecs: 1750,
        metres: 5000,
      );
      final settings = SettingsState(repo, fakePreferencesService());
      await settings.initialize();

      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseProgressScreen(
            workoutState: WorkoutState(repo),
            settingsState: settings,
            exerciseId: 'ex-run',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // RECENT SESSIONS lists every training day, the duration day included.
      expect(find.text('RECENT SESSIONS'), findsOneWidget);
      final history = find.widgetWithText(OmniSurface, '20:00');
      expect(history, findsOneWidget, reason: 'the duration day is listed');
      // Three entries, a date and a figure each.
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: history, matching: find.byType(Text)),
            )
            .where((text) => text.data != null),
        hasLength(6),
      );
      // The chart plots only the two pace days.
      final chart = tester.widget<ScrollableTrendChart>(
        find.byType(ScrollableTrendChart),
      );
      expect(chart.pointCount, 2);
    });
  });
}
