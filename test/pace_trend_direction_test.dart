// Plan 226 — a faster pace rises on the trend line (S-22601..S-22604).
//
// Pace is seconds per kilometre, so a faster pace is a smaller number; the
// trend is drawn flipped so getting faster rises on both the Instruments
// sparkline and the Exercise Progress chart, while the axis labels keep
// reading true clock values. The widget scenarios run on the Mock repository
// only, seeded in `setUp`, never inside a `testWidgets` body.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/chart_axis_helper.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_sparkline.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

const Size _kTallViewport = Size(400, 2400);

Future<void> _seedPaceSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required int seconds,
}) async {
  await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'ex-run',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  // 1000 m over [seconds] reads as [seconds] per kilometre.
  await repo.createTimedInstance(
    timedInstance(effortId, 0, durationSecs: seconds, entryIndex: 0),
  );
  await repo.createObservation(
    distanceRow(effortId, 0, 1000, atMs: fixtureRowAt(0)),
  );
}

Future<void> _seedSetSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required double weightKg,
  required int reps,
}) async {
  await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId',
    exerciseId: 'ex-press',
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: weightKg,
    repsBase: reps,
  );
}

void main() {
  // ─── S-22601 / S-22602: the sparkline's plotted values ─────────────────────

  test('S-22601 plottedValues negates a pace series, so a faster pace rises', () {
    final points = [
      for (final pace in const [330.0, 320.0, 310.0])
        ExerciseMetricPoint(
          dayMs: 0,
          value: NativeValue(metric: NativeMetric.pace, value: pace),
        ),
    ];

    expect(InstrumentSparkline.plottedValues(points), [-330, -320, -310]);
  });

  test('S-22602 plottedValues leaves a non-pace series as it is', () {
    final points = [
      for (final e1rm in const [100.0, 110.0, 120.0])
        ExerciseMetricPoint(
          dayMs: 0,
          value: NativeValue(metric: NativeMetric.estimatedOneRepMax, value: e1rm),
        ),
    ];

    expect(InstrumentSparkline.plottedValues(points), [100, 110, 120]);
  });

  // ─── S-22603 / S-22604: the Exercise Progress chart ────────────────────────

  final harness = MockRepositoryHarness();
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

    testWidgets('S-22603 an improving pace draws a rising line and reads the '
        'axis in true clocks', (tester) async {
      await seedExercise(repo, id: 'ex-run', name: 'Easy Run');
      // Three kilometres a day at a pace that improves: 330, 320, 310 s/km.
      await _seedPaceSession(
        repo,
        sessionId: 's-run-3',
        daysAgo: 3,
        seconds: 330,
      );
      await _seedPaceSession(
        repo,
        sessionId: 's-run-2',
        daysAgo: 2,
        seconds: 320,
      );
      await _seedPaceSession(
        repo,
        sessionId: 's-run-1',
        daysAgo: 1,
        seconds: 310,
      );

      await tester.binding.setSurfaceSize(_kTallViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseProgressScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            exerciseId: 'ex-run',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final spots = data.lineBarsData.single.spots;
      expect(spots, hasLength(3));
      // Getting faster rises: strictly increasing left to right.
      expect(spots[0].y, lessThan(spots[1].y));
      expect(spots[1].y, lessThan(spots[2].y));

      // The labels stay true clocks: the top of the axis (plotted bounds.max)
      // reflects back to the smallest pace value the axis shows and the
      // bottom to the largest.
      final chart = tester.widget<ScrollableTrendChart>(
        find.byType(ScrollableTrendChart),
      );
      expect(
        chart.yLabelFormatter!(data.maxY),
        ChartAxisHelper.formatClockAxisValue(data.minY),
      );
      expect(
        chart.yLabelFormatter!(data.minY),
        ChartAxisHelper.formatClockAxisValue(data.maxY),
      );
    });

    testWidgets('S-22604 a rising e1RM draws the values as they are', (
      tester,
    ) async {
      await seedExercise(
        repo,
        id: 'ex-press',
        name: 'Bench Press',
        capabilities: const ['load', 'reps'],
      );
      await _seedSetSession(
        repo,
        sessionId: 's-press-3',
        daysAgo: 3,
        weightKg: 100,
        reps: 5,
      );
      await _seedSetSession(
        repo,
        sessionId: 's-press-2',
        daysAgo: 2,
        weightKg: 110,
        reps: 5,
      );
      await _seedSetSession(
        repo,
        sessionId: 's-press-1',
        daysAgo: 1,
        weightKg: 120,
        reps: 5,
      );

      await tester.binding.setSurfaceSize(_kTallViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseProgressScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            exerciseId: 'ex-press',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final spots = data.lineBarsData.single.spots;
      final expected = [
        StatsProgressService.epley1RM(100, 5)!,
        StatsProgressService.epley1RM(110, 5)!,
        StatsProgressService.epley1RM(120, 5)!,
      ];
      expect(spots, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(spots[i].y, closeTo(expected[i], 1e-9));
        if (i > 0) expect(spots[i].y, greaterThan(spots[i - 1].y));
      }
      // A non-clock metric keeps the bare-number formatter.
      final chart = tester.widget<ScrollableTrendChart>(
        find.byType(ScrollableTrendChart),
      );
      expect(chart.yLabelFormatter, isNull);
    });
}
