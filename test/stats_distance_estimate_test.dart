// Stats PR 3a, Phase 3 — estimates are marked, and the pace counts only the
// entries that have a distance.
//
// The cardio card's pace used to divide every finished second by every stored
// metre, which reads a session's walk-breaks and its untimed entries as if
// they were part of the run. A day's pace now counts only the finished entries
// that carry a distance (D-309). Separately, a distance the watch platform
// *estimated* is marked, in text and by a hollow dot, wherever it appears
// (D-303, D-308, D-317).
//
// Scenarios: S-831–S-837 of
// `.github/agents/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.md`.

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

// ─── Fixture ────────────────────────────────────────────────────────────────

/// Midnight local, [daysAgo] days back — the day separator the service buckets
/// a point by.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: daysAgo));
}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// One exercise, created once per id.
Future<void> _exercise(MockWorkoutRepository repo, String id, String name) =>
    repo.createExercise(
      Exercise(id: id, name: name, createdAtMs: 1000, updatedAtMs: 1000),
    );

/// A completed session holding one segment, [seconds] long, dated [daysAgo].
Future<String> _session(
  MockWorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final start = _day(daysAgo).add(const Duration(hours: 9));
  final end = start.add(const Duration(hours: 1));
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: start.millisecondsSinceEpoch,
      endedAtMs: end.millisecondsSinceEpoch,
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: end.millisecondsSinceEpoch,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    ),
  );
  return id;
}

/// One timed effort on [sessionId]: `entries` is one
/// `(entryIndex, durationSecs, distanceMetres, distanceSource, finished)`
/// record each. A null distance stores no row.
Future<void> _timedEffort(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required String effortId,
  required List<(int, int, double?, String?, bool)> entries,
  int orderIndex = 0,
}) async {
  final atMs = _day(1).millisecondsSinceEpoch;
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: orderIndex,
      topLevelOrderIndex: orderIndex,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );

  for (final (index, durationSecs, metres, source, finished) in entries) {
    await repo.createTimedInstance(
      TimedInstance(
        id: 'ti-$effortId-$index',
        effortId: effortId,
        entryIndex: index,
        targetDurationSecs: durationSecs,
        actualDurationSecs: durationSecs,
        startedAtMs: atMs,
        finishedAtMs: finished ? atMs + durationSecs * 1000 : null,
        state: finished ? TimedState.finished : TimedState.notStarted,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
    if (metres == null) continue;
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effortId-$index-distance',
        effortId: effortId,
        metricId: MetricIds.distance,
        unitId: MetricIds.unitMeters,
        valueReal: metres,
        valueSource: source,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
  }
}

Future<void> _pumpStats(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  String unit = 'km',
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1600));
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.initialize();
  await settings.setPreferredDistanceUnit(unit);

  await tester.pumpWidget(
    MaterialApp(
      home: StatsScreen(
        workoutState: WorkoutState(repo),
        settingsState: settings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every `FlDotPainter` the chart draws, grouped by the bar that draws it, so
/// a caller can name a series by its position (the cardio chart draws pace
/// first, distance second).
List<List<(FlSpot, FlDotPainter)>> _dotsByBar(LineChart chart) {
  final bars = <List<(FlSpot, FlDotPainter)>>[];
  for (final bar in chart.data.lineBarsData) {
    final painter = bar.dotData.getDotPainter;
    bars.add([
      for (var i = 0; i < bar.spots.length; i++)
        (bar.spots[i], painter(bar.spots[i], i.toDouble(), bar, i)),
    ]);
  }
  return bars;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-831 — the pace counts only the entries that have a distance
  // ══════════════════════════════════════════════════════════════════════════

  group('S-831 the pace counts only entries with a distance', () {
    test(
      '(a) an entry with no distance contributes no time and no pace',
      () async {
        final repo = await _freshRepo();
        await _exercise(repo, 'ex-run', 'Treadmill Run');
        await _session(repo, id: 's-a', daysAgo: 1);
        await _timedEffort(
          repo,
          sessionId: 's-a',
          exerciseId: 'ex-run',
          effortId: 'e-a',
          entries: [(0, 600, 2000.0, null, true), (1, 600, 0.0, null, true)],
        );

        final data = await StatsProgressService(repo).computeProgressData();
        final point = data.topCardio.first.trend.first;

        expect(point.durationSecs, 1200);
        expect(point.distanceM, closeTo(2000.0, 0.1));
        expect(point.paceSecPerKm, closeTo(300.0, 0.01));
      },
    );

    test(
      '(b) an unfinished entry counts its distance but no pace time',
      () async {
        final repo = await _freshRepo();
        await _exercise(repo, 'ex-run', 'Treadmill Run');
        await _session(repo, id: 's-b', daysAgo: 1);
        await _timedEffort(
          repo,
          sessionId: 's-b',
          exerciseId: 'ex-run',
          effortId: 'e-b',
          entries: [(0, 600, 2000.0, null, true), (1, 0, 1000.0, null, false)],
        );

        final data = await StatsProgressService(repo).computeProgressData();
        final point = data.topCardio.first.trend.first;

        expect(point.durationSecs, 600);
        expect(point.distanceM, closeTo(3000.0, 0.1));
        expect(point.paceSecPerKm, closeTo(300.0, 0.01));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-832 — the estimated flag, per day
  // ══════════════════════════════════════════════════════════════════════════

  test('S-832 the estimated flag is per day and per exercise', () async {
    final repo = await _freshRepo();
    await _exercise(repo, 'ex-run', 'Run');

    await _session(repo, id: 's-d3', daysAgo: 3);
    await _timedEffort(
      repo,
      sessionId: 's-d3',
      exerciseId: 'ex-run',
      effortId: 'e-d3',
      entries: [(0, 1800, 4873.6, EffortObservation.sourceEstimated, true)],
    );

    await _session(repo, id: 's-d2', daysAgo: 2);
    await _timedEffort(
      repo,
      sessionId: 's-d2',
      exerciseId: 'ex-run',
      effortId: 'e-d2',
      entries: [(0, 1800, 5000.0, null, true)],
    );

    await _session(repo, id: 's-d1', daysAgo: 1);
    await _timedEffort(
      repo,
      sessionId: 's-d1',
      exerciseId: 'ex-run',
      effortId: 'e-d1-a',
      entries: [(0, 600, 5000.0, EffortObservation.sourceGps, true)],
      orderIndex: 0,
    );
    await _timedEffort(
      repo,
      sessionId: 's-d1',
      exerciseId: 'ex-run',
      effortId: 'e-d1-b',
      entries: [(0, 600, 1000.0, EffortObservation.sourceEstimated, true)],
      orderIndex: 1,
    );

    final data = await StatsProgressService(repo).computeProgressData();
    final trend = data.topCardio.first.trend;
    expect(trend, hasLength(3));
    expect(
      trend.map((point) => point.distanceEstimated).toList(),
      [true, false, true],
      reason: 'D-317: any estimated distance in the day marks the day',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-833 / S-834 — the single-point card's marker
  // ══════════════════════════════════════════════════════════════════════════

  group('the single-point cardio card', () {
    Future<void> seedOneDay(
      MockWorkoutRepository repo, {
      String? source,
    }) async {
      await _exercise(repo, 'ex-run', 'Run');
      await _session(repo, id: 's-card', daysAgo: 1);
      await _timedEffort(
        repo,
        sessionId: 's-card',
        exerciseId: 'ex-run',
        effortId: 'e-card',
        entries: [(0, 1800, 4873.6, source, true)],
      );
    }

    testWidgets('S-833 marks an estimated single day, in km', (tester) async {
      final repo = await _freshRepo();
      await seedOneDay(repo, source: EffortObservation.sourceEstimated);

      await _pumpStats(tester, repo, unit: 'km');

      expect(find.textContaining('Distance: 4.87 km est.'), findsOneWidget);
      expect(find.textContaining('Pace: 369 s/km est.'), findsOneWidget);
    });

    testWidgets('S-833 marks an estimated single day, in miles', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await seedOneDay(repo, source: EffortObservation.sourceEstimated);

      await _pumpStats(tester, repo, unit: 'mi');

      expect(find.textContaining('Distance: 3.03 mi est.'), findsOneWidget);
      expect(find.textContaining('Pace: 594 s/mi est.'), findsOneWidget);
    });

    testWidgets('S-834 a measured day carries no marker', (tester) async {
      final repo = await _freshRepo();
      await seedOneDay(repo, source: null);

      await _pumpStats(tester, repo, unit: 'km');

      expect(find.textContaining('Distance: 4.87 km'), findsOneWidget);
      expect(find.textContaining('Pace: 369 s/km'), findsOneWidget);
      expect(find.textContaining('est.'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-835 — chart dots and the legend
  // ══════════════════════════════════════════════════════════════════════════

  group('S-835 chart dots and the legend', () {
    Future<void> seedThreeDays(
      MockWorkoutRepository repo, {
      required bool withEstimate,
    }) async {
      await _exercise(repo, 'ex-row', 'Row');
      for (final (sessionId, daysAgo, secs, metres, source) in [
        ('s-p1', 3, 1200, 4000.0, null),
        (
          's-p2',
          2,
          1080,
          4200.0,
          withEstimate ? EffortObservation.sourceEstimated : null,
        ),
        ('s-p3', 1, 1150, 4100.0, null),
      ]) {
        await _session(repo, id: sessionId, daysAgo: daysAgo);
        await _timedEffort(
          repo,
          sessionId: sessionId,
          exerciseId: 'ex-row',
          effortId: 'e-$sessionId',
          entries: [(0, secs, metres, source, true)],
        );
      }
    }

    testWidgets('an estimated day is hollow, and the legend gains est.', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await seedThreeDays(repo, withEstimate: true);
      await _pumpStats(tester, repo);

      expect(find.text('Distance (km)'), findsOneWidget);
      expect(find.text('est.'), findsOneWidget);

      final chart = tester.widget<LineChart>(find.byType(LineChart).first);
      final colors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
      final bars = _dotsByBar(chart);
      expect(bars, hasLength(2), reason: 'pace first, distance second');

      for (final (barIndex, seriesColor) in [
        (0, colors.secondary),
        (1, colors.primary),
      ]) {
        final dots = bars[barIndex];
        expect(dots, hasLength(3), reason: 'bar $barIndex has three days');
        for (final (spot, painter) in dots) {
          final circle = painter as FlDotCirclePainter;
          final estimated = spot.x == 1.0;
          expect(
            circle.color,
            estimated ? colors.surface : seriesColor,
            reason:
                'bar $barIndex, day ${spot.x}: ${estimated ? 'hollow' : 'filled'} fill',
          );
          expect(
            circle.strokeColor,
            estimated ? seriesColor : colors.surface,
            reason:
                'bar $barIndex, day ${spot.x}: ${estimated ? 'hollow' : 'filled'} stroke',
          );
        }
      }
    });

    testWidgets('a run without an estimate keeps every dot filled and shows '
        'no est. item', (tester) async {
      final repo = await _freshRepo();
      await seedThreeDays(repo, withEstimate: false);
      await _pumpStats(tester, repo);

      expect(find.text('est.'), findsNothing);

      final chart = tester.widget<LineChart>(find.byType(LineChart).first);
      final colors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
      for (final dots in _dotsByBar(chart)) {
        for (final (spot, painter) in dots) {
          final circle = painter as FlDotCirclePainter;
          expect(circle.strokeColor, colors.surface, reason: 'x=${spot.x}');
          expect(circle.color, isNot(colors.surface), reason: 'x=${spot.x}');
        }
      }
    });

    testWidgets('a day with no distance does not shift the estimated dot', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _exercise(repo, 'ex-row', 'Row');
      // Day one holds a duration but no distance, so it gets a trend point and
      // no spot in either series. The estimated day is therefore the trend's
      // *second* day but each bar's *first* dot, which a lookup by the
      // painter's list position would read as the day with no distance.
      final days = <(String, int, int, double?, String?)>[
        ('s-n1', 3, 600, null, null),
        ('s-n2', 2, 1080, 4200.0, EffortObservation.sourceEstimated),
        ('s-n3', 1, 1150, 4100.0, null),
      ];
      for (final (sessionId, daysAgo, secs, metres, source) in days) {
        await _session(repo, id: sessionId, daysAgo: daysAgo);
        await _timedEffort(
          repo,
          sessionId: sessionId,
          exerciseId: 'ex-row',
          effortId: 'e-$sessionId',
          entries: [(0, secs, metres, source, true)],
        );
      }
      await _pumpStats(tester, repo);

      expect(find.text('est.'), findsOneWidget);

      final chart = tester.widget<LineChart>(find.byType(LineChart).first);
      final colors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
      final bars = _dotsByBar(chart);
      expect(bars, hasLength(2), reason: 'pace first, distance second');

      for (final (barIndex, seriesColor) in [
        (0, colors.secondary),
        (1, colors.primary),
      ]) {
        final dots = bars[barIndex];
        final xs = [for (final (spot, _) in dots) spot.x];
        expect(xs, [
          1.0,
          2.0,
        ], reason: 'bar $barIndex skips the day with no distance');
        for (final (spot, painter) in dots) {
          final circle = painter as FlDotCirclePainter;
          final estimated = spot.x == 1.0;
          expect(
            circle.color,
            estimated ? colors.surface : seriesColor,
            reason:
                'bar $barIndex, day ${spot.x}: ${estimated ? 'hollow' : 'filled'} fill',
          );
          expect(
            circle.strokeColor,
            estimated ? seriesColor : colors.surface,
            reason:
                'bar $barIndex, day ${spot.x}: ${estimated ? 'hollow' : 'filled'} stroke',
          );
        }
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-836 — conversions go through UnitFormatter
  // ══════════════════════════════════════════════════════════════════════════

  test('S-836 the Stats screen holds no km↔mi constant', () {
    final source = File(
      'lib/features/stats/stats_screen.dart',
    ).readAsStringSync();
    for (final literal in ['0.621371', '1.609344', '1609.3']) {
      expect(
        source.contains(literal),
        isFalse,
        reason:
            'D-314: the conversion belongs to UnitFormatter.metresPerUnit, '
            'never to a literal in this file ($literal)',
      );
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-837 — a Summary correction reaches Stats
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-837 a Summary correction reaches the Stats card', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _exercise(repo, 'ex-treadmill', 'Treadmill Run');
    await _exercise(repo, 'ex-easy', 'Easy Run');
    await _session(repo, id: 's-cardio', daysAgo: 1);
    await _timedEffort(
      repo,
      sessionId: 's-cardio',
      exerciseId: 'ex-treadmill',
      effortId: 'e-tread',
      entries: [
        (0, 1200, 4873.6, EffortObservation.sourceEstimated, true),
        (1, 600, 0.0, null, true),
      ],
    );
    await _timedEffort(
      repo,
      sessionId: 's-cardio',
      exerciseId: 'ex-easy',
      effortId: 'e-easy',
      entries: [(0, 1800, 5000.0, null, true)],
      orderIndex: 1,
    );

    // The Summary's own write, at the state layer.
    final workoutState = WorkoutState(repo);
    await workoutState.loadHistoricalSession('s-cardio');
    await workoutState.setEntryDistance('e-tread', 0, 5200.0);

    await _pumpStats(tester, repo, unit: 'km');

    expect(find.textContaining('Distance: 5.20 km'), findsOneWidget);
    expect(find.textContaining('Pace: 231 s/km'), findsOneWidget);
    expect(find.textContaining('est.'), findsNothing);
  });
}
