// Stats PR 8a Phase 2 — the period-scoped per-day nutrition read
// (`StatsProgressService.nutritionSeries`) and the 21-day period call into
// `StatsProgressService.computeMixPeriod`, over both repository harnesses.
//
// Plan: `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`
// (D-1402, D-1403, D-1405, D-1419; S-2112).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Calendar anchors ───────────────────────────────────────────────────────
//
// `day(n)` is local midnight n days before today, exactly as the plan defines
// it, so the real-clock anchor `computeNutritionTrend` uses and the explicit
// bounds this file hands to `nutritionSeries` line up.

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _day(int daysAgo) {
  final today = _today();
  return DateTime(today.year, today.month, today.day - daysAgo);
}

DateTime _todayEnd() {
  final today = _today();
  return DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
}

/// The plan's `now` for the S-2112 fixture: 10:00 local today, so no fixture
/// session starts after it and the period and window calls see the same
/// sessions.
DateTime _now() {
  final today = _today();
  return DateTime(today.year, today.month, today.day, 10);
}

/// `hour`:[minute] local on `day(daysAgo)`.
DateTime _at(int daysAgo, int hour, [int minute = 0]) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour, minute);
}

// ─── Rows ───────────────────────────────────────────────────────────────────

/// One consumed-food snapshot on [day]'s local midnight. [loggedAt] defaults
/// to noon of that day; the repository filters by `dateMs`, so only the day
/// matters to every read here.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required DateTime day,
  DateTime? loggedAt,
}) async {
  final dateMs = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs:
          loggedAt?.millisecondsSinceEpoch ?? dateMs + 12 * 60 * 60 * 1000,
      dateMs: dateMs,
      sourceFoodId: id,
      name: 'Food $id',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 200,
      fiber: 0,
      fat: 60,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 2400,
      targetProtein: 160,
      targetCarbs: 280,
      targetFat: 80,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// Wipe the seeds `initialize()` writes so a fixture's own rows are the only
/// ones any read sees.
Future<void> _clearSeededFoods(WorkoutRepository repo) async {
  for (final entry in await repo.getConsumedFoodsInRange(0, 9999999999999)) {
    if (entry.id.startsWith('seed-consumed-')) {
      await repo.deleteConsumedFood(entry.id);
    }
  }
}

// ─── Sessions and efforts ───────────────────────────────────────────────────

/// A rated hour session starting at [start], carrying one effort of [kind]
/// lasting [seconds] — `timed` (cardio), `drill` (isometric) or `round`
/// (sports).
Future<void> _seedWork(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required String kind,
  required int seconds,
  int rating = 4,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: startMs + 3600000,
      sessionFeeling: rating,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  final exerciseId = 'ex-$id';
  await seedExercise(repo, id: exerciseId, name: 'Work');
  switch (kind) {
    case 'timed':
    case 'drill':
      await seedHoldEffort(
        repo,
        segmentId: 'seg-$id',
        effortId: 'ef-$id',
        exerciseId: exerciseId,
        entryCount: 1,
        secondsPerEntry: seconds,
        effortKind: kind,
      );
    case 'round':
      await seedRoundEffort(
        repo,
        segmentId: 'seg-$id',
        effortId: 'ef-$id',
        exerciseId: exerciseId,
        rounds: [roundInstance('ef-$id', 0, durationSecs: seconds)],
      );
  }
}

/// F-MIX42: four rated baseline sessions in four distinct 7-day blocks before
/// `day(41)`, plus work in the recent period `[day(20), now]` and the prior
/// period `[day(41), day(20) 00:00 − 1 ms]`.
///
/// The recent period's first instant carries Sports work and the prior
/// period's last instant carries Isometric work, so the two periods' segments
/// prove which period each boundary session landed in. Every session is rated,
/// so both periods report the load measure.
Future<void> _seedFMix42(WorkoutRepository repo) async {
  for (final days in [104, 97, 90, 83]) {
    await _seedWork(
      repo,
      id: 'fmix42-b$days',
      start: _at(days, 9),
      kind: 'timed',
      seconds: 600,
    );
  }

  // Recent period.
  await _seedWork(
    repo,
    id: 'fmix42-recent-sports',
    start: _day(20),
    kind: 'round',
    seconds: 600,
  );
  await _seedWork(
    repo,
    id: 'fmix42-recent-cardio',
    start: _at(10, 9),
    kind: 'timed',
    seconds: 1200,
  );

  // Prior period.
  await _seedWork(
    repo,
    id: 'fmix42-prior-iso',
    start: _at(21, 23, 59),
    kind: 'drill',
    seconds: 1200,
  );
  await _seedWork(
    repo,
    id: 'fmix42-prior-cardio',
    start: _at(30, 9),
    kind: 'timed',
    seconds: 600,
  );
}

// ─── Read helpers ───────────────────────────────────────────────────────────

List<String> _describe(List<NutritionTrendPoint> points) => [
  for (final p in points)
    '${p.date.millisecondsSinceEpoch}|${p.calories}|${p.protein}|${p.carbs}|${p.fat}',
];

List<DateTime> _days(List<NutritionTrendPoint> points) => [
  for (final p in points) p.date,
];

List<String> _shape(List<MixSegment> segments) => [
  for (final s in segments) '${s.section.name}|${s.measure}|${s.percent}',
];

double _measureOf(List<MixSegment> segments, ExerciseSection section) =>
    segments
        .where((s) => s.section == section)
        .fold<double>(0, (sum, s) => sum + s.measure);

StatsWindow _window(DateTime from, DateTime to) => StatsWindow(
  fromMs: from,
  toMs: to,
  label: 'Test window',
  isPeriodScoped: false,
);

void main() {
  for (final factory in harnessFactories) {
    final seriesHarness = factory();

    group('${seriesHarness.name} — nutritionSeries', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await seriesHarness.open();
        await _clearSeededFoods(repo);
        // Logged days: today, day(2), day(5) and day(9). Days 1, 3, 4, 6, 7
        // and 8 carry no row.
        await _seedFood(repo, id: 'cf-0', day: _day(0));
        await _seedFood(repo, id: 'cf-2', day: _day(2));
        await _seedFood(repo, id: 'cf-5', day: _day(5));
        await _seedFood(repo, id: 'cf-9', day: _day(9));
      });

      tearDown(() async {
        await seriesHarness.close();
      });

      test(
        'the new read equals computeNutritionTrend for the equivalent span',
        () async {
          final service = StatsProgressService(repo);

          // `computeNutritionTrend(days: 7)` spans [day(6) 00:00, endOfDay(today)].
          final trend = await service.computeNutritionTrend(days: 7);
          final series = await service.nutritionSeries(
            fromMs: _day(6),
            toMs: _todayEnd(),
          );

          expect(_describe(series), _describe(trend));
          // The day(9) row is outside the 7-day span and inside full history.
          expect(_days(series), [_day(5), _day(2), _day(0)]);
          expect(_days(await service.computeNutritionTrend(days: null)), [
            _day(9),
            _day(5),
            _day(2),
            _day(0),
          ]);
        },
      );

      test('the logged days are the rows\' own days', () async {
        final series = await StatsProgressService(
          repo,
        ).nutritionSeries(fromMs: _day(9), toMs: _todayEnd());

        expect(_days(series), [_day(9), _day(5), _day(2), _day(0)]);
        // One row per day: protein 100 × 100/100, carbs 200, fat 60, and
        // calories (100×4 + 200×4 + 60×9) × 100/100.
        for (final point in series) {
          expect(point.calories, 1740);
          expect(point.protein, 100);
          expect(point.carbs, 200);
          expect(point.fat, 60);
        }
      });

      test('a day without a row is absent', () async {
        final series = await StatsProgressService(
          repo,
        ).nutritionSeries(fromMs: _day(6), toMs: _todayEnd());

        expect(series, hasLength(3));
        expect(_days(series), isNot(contains(_day(1))));
        expect(_days(series), isNot(contains(_day(3))));
        expect(_days(series), isNot(contains(_day(4))));
      });
    });

    final mixHarness = factory();

    group('${mixHarness.name} — S-2112', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await mixHarness.open();
        await _clearSeededFoods(repo);
        await _seedFMix42(repo);
        // A logged day at day(21) 23:59 and one at day(20) 00:00, one day
        // either side of the recent period's first instant.
        await _seedFood(
          repo,
          id: 'cf-day21',
          day: _day(21),
          loggedAt: _at(21, 23, 59),
        );
        await _seedFood(
          repo,
          id: 'cf-day20',
          day: _day(20),
          loggedAt: _day(20),
        );
      });

      tearDown(() async {
        await mixHarness.close();
      });

      test(
        'S-2112 the 21-day period equals the equivalent window call',
        () async {
          final service = StatsProgressService(repo);

          final period = (await service.computeMixPeriod(
            fromMs: _day(20),
            toMs: _now(),
          ))!;
          final layer = (await service.computeMixLayer(
            window: _window(_day(20), _todayEnd()),
            now: _now(),
            startOfWeek: 'monday',
          ))!;

          expect(period.measure, layer.measure);
          expect(_shape(period.segments), _shape(layer.segments));
          expect(
            _shape(period.baselineSegments),
            _shape(layer.baselineSegments),
          );
          expect(period.unratedSessionCount, layer.unratedSessionCount);
          expect(period.ratedBaselineWeeks, layer.ratedBaselineWeeks);
          expect(period.weeks, isEmpty);

          // Both periods report load, so the boundary assertions below read
          // segments rather than time.
          expect(period.measure, MixMeasure.load);
        },
      );

      test(
        'S-2112 the two periods abut and the boundary rows land in the right period',
        () async {
          final service = StatsProgressService(repo);

          final recentFrom = _day(20);
          final priorTo = _day(20).subtract(const Duration(milliseconds: 1));

          final recent = (await service.computeMixPeriod(
            fromMs: recentFrom,
            toMs: _now(),
          ))!;
          final prior = (await service.computeMixPeriod(
            fromMs: _day(41),
            toMs: priorTo,
          ))!;

          // A session at day(20) 00:00 is in the recent period, not the prior.
          expect(
            _measureOf(recent.segments, ExerciseSection.sports),
            greaterThan(0),
          );
          expect(_measureOf(prior.segments, ExerciseSection.sports), 0);

          // A session at day(21) 23:59 is in the prior period, not the recent.
          expect(
            _measureOf(prior.segments, ExerciseSection.isometric),
            greaterThan(0),
          );
          expect(_measureOf(recent.segments, ExerciseSection.isometric), 0);

          // A logged day at day(21) 23:59 is in the prior period, not dropped.
          expect(
            _days(
              await service.nutritionSeries(fromMs: _day(41), toMs: priorTo),
            ),
            [_day(21)],
          );
          // A logged day at day(20) 00:00 is in the recent period.
          expect(
            _days(
              await service.nutritionSeries(
                fromMs: recentFrom,
                toMs: _todayEnd(),
              ),
            ),
            [_day(20)],
          );
        },
      );
    });
  }

  test('Mock and Hive give the same points', () async {
    Future<List<String>> read(RepositoryHarness harness) async {
      final repo = await harness.open();
      await _clearSeededFoods(repo);
      for (final daysAgo in [0, 3, 8]) {
        await _seedFood(repo, id: 'cf-parity-$daysAgo', day: _day(daysAgo));
      }
      final points = await StatsProgressService(
        repo,
      ).nutritionSeries(fromMs: _day(20), toMs: _todayEnd());
      await harness.close();
      return _describe(points);
    }

    final mock = await read(MockRepositoryHarness());
    final hive = await read(HiveRepositoryHarness());
    expect(mock, hive);
    expect(mock, hasLength(3));
  });
}
