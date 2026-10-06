// Stats PR 8b Phase 2 — the four reads the Protein Consistency adapter asks
// `StatsProgressService` for: the window's nutrition series (8a's
// `nutritionSeries`), the per-day stored protein targets (`proteinTargetsByDay`),
// the range's completed resistance-session count (`resistanceSessionCount`) and
// the latest bodyweight in kilograms (`latestBodyWeightKg`), over both
// repository harnesses.
//
// Plan: `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.md`
// (D-1510, D-1511, D-1519; S-2214).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Calendar anchors ───────────────────────────────────────────────────────
//
// `day(n)` is local midnight n days before today, the same key the pure rule
// uses, so the reads' keys line up with the rule's.

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

/// `hour` local on `day(daysAgo)`.
DateTime _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour);
}

int _dayMs(DateTime day) =>
    DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;

// ─── Rows ───────────────────────────────────────────────────────────────────

/// A stored target from [day] on, carrying [protein] grams.
Future<void> _seedTarget(
  WorkoutRepository repo, {
  required DateTime day,
  required double protein,
}) => repo.saveNutritionTargetForDate(
  _dayMs(day),
  NutritionTarget(calories: 2000, protein: protein, carbs: 250, fat: 70),
);

/// One consumed-food snapshot on [day], scaled to [protein] grams.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required DateTime day,
  required double protein,
}) async {
  final dateMs = _dayMs(day);
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + 12 * 60 * 60 * 1000,
      dateMs: dateMs,
      sourceFoodId: id,
      name: 'Food $id',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: protein,
      carbs: 0,
      fiber: 0,
      fat: 0,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 2000,
      targetProtein: 150,
      targetCarbs: 250,
      targetFat: 70,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// Wipe the seeds `initialize()` writes so a fixture's own rows are the only
/// ones the series read sees.
Future<void> _clearSeededFoods(WorkoutRepository repo) async {
  for (final entry in await repo.getConsumedFoodsInRange(0, 9999999999999)) {
    if (entry.id.startsWith('seed-consumed-')) {
      await repo.deleteConsumedFood(entry.id);
    }
  }
}

/// A session starting at [start] with one segment and one effort of
/// [effortKind] — `set` for Resistance, `timed` for cardio. An in-progress
/// session leaves `endedAtMs` null.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required String effortKind,
  bool inProgress = false,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: inProgress ? null : startMs + 3600000,
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
  await seedExercise(repo, id: 'ex-$id', name: 'Work');
  await repo.createEffort(
    SegmentEffort(
      id: 'ef-$id',
      segmentId: 'seg-$id',
      orderIndex: 0,
      effortKind: effortKind,
      exerciseId: 'ex-$id',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

/// A `bodyweight` measurement recorded at [recordedAtMs] in [unitId].
Future<void> _seedMeasurement(
  WorkoutRepository repo, {
  required String id,
  required double value,
  required String unitId,
  required int recordedAtMs,
}) => repo.saveMeasurementEntry(
  BodyMeasurementEntry(
    id: id,
    measurementType: 'bodyweight',
    value: value,
    unitId: unitId,
    recordedAtMs: recordedAtMs,
  ),
);

List<String> _describeSeries(List<NutritionTrendPoint> points) => [
  for (final p in points) '${p.date.millisecondsSinceEpoch}|${p.protein}',
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the Protein Consistency reads', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSeededFoods(repo);
        // Targets: 150 g stored on day(13) rolls forward through day(7); a
        // 160 g target stored on day(6) rolls forward from there.
        await _seedTarget(repo, day: _day(13), protein: 150);
        await _seedTarget(repo, day: _day(6), protein: 160);
        // Logged days inside the window.
        await _seedFood(repo, id: 'cf-13', day: _day(13), protein: 120);
        await _seedFood(repo, id: 'cf-6', day: _day(6), protein: 120);
        await _seedFood(repo, id: 'cf-0', day: _day(0), protein: 120);
        // Two completed Resistance sessions, one cardio-only, one still in
        // progress, one starting before the window.
        await _seedSession(
          repo,
          id: 's-res-12',
          start: _at(12, 9),
          effortKind: 'set',
        );
        await _seedSession(
          repo,
          id: 's-res-2',
          start: _at(2, 9),
          effortKind: 'set',
        );
        await _seedSession(
          repo,
          id: 's-cardio-10',
          start: _at(10, 9),
          effortKind: 'timed',
        );
        await _seedSession(
          repo,
          id: 's-open-1',
          start: _at(1, 9),
          effortKind: 'set',
          inProgress: true,
        );
        await _seedSession(
          repo,
          id: 's-old-20',
          start: _at(20, 9),
          effortKind: 'set',
        );
        // Bodyweight: an older 82.0 kg and a newer 78.5 kg.
        await _seedMeasurement(
          repo,
          id: 'm-old',
          value: 82.0,
          unitId: MetricIds.unitKg,
          recordedAtMs: _at(30, 8).millisecondsSinceEpoch,
        );
        await _seedMeasurement(
          repo,
          id: 'm-new',
          value: 78.5,
          unitId: MetricIds.unitKg,
          recordedAtMs: _at(5, 8).millisecondsSinceEpoch,
        );
      });

      tearDown(() async {
        await harness.close();
      });

      test('proteinTargetsByDay inherits the last stored target forward', () async {
        final targets = await StatsProgressService(repo).proteinTargetsByDay(
          fromMs: _day(13),
          toMs: _day(0),
        );

        expect(targets, hasLength(14));
        // The day(13) target is inherited by every day through day(7).
        for (var daysAgo = 7; daysAgo <= 13; daysAgo++) {
          expect(targets[_day(daysAgo)], 150);
        }
        // The day(6) target is inherited from day(6) through day(0).
        for (var daysAgo = 0; daysAgo <= 6; daysAgo++) {
          expect(targets[_day(daysAgo)], 160);
        }
        // Keyed by local midnight, the key the pure rule uses.
        expect(targets.keys, contains(_day(0)));
        expect(targets.keys, contains(_day(13)));
      });

      test('a day before any stored target is absent', () async {
        final targets = await StatsProgressService(repo).proteinTargetsByDay(
          fromMs: _day(15),
          toMs: _day(14),
        );

        expect(targets, isEmpty);
      });

      test('only completed resistance sessions in the range are counted', () async {
        final count = await StatsProgressService(repo).resistanceSessionCount(
          fromMs: _day(13),
          toMs: _todayEnd(),
        );

        // s-res-12 and s-res-2 count; s-cardio-10 has no Resistance effort,
        // s-open-1 is in progress and s-old-20 starts before the range.
        expect(count, 2);
      });

      test('a session with only timed efforts is not counted', () async {
        final count = await StatsProgressService(repo).resistanceSessionCount(
          fromMs: _day(10),
          toMs: _at(10, 23),
        );

        expect(count, 0);
      });

      test('an in-progress session is not counted', () async {
        final count = await StatsProgressService(repo).resistanceSessionCount(
          fromMs: _day(1),
          toMs: _at(1, 23),
        );

        expect(count, 0);
      });

      test('a session starting before the range is not counted', () async {
        final service = StatsProgressService(repo);

        // The day(20) session sits outside the 14-day window…
        expect(
          await service.resistanceSessionCount(
            fromMs: _day(13),
            toMs: _todayEnd(),
          ),
          2,
        );
        // …and inside a range widened to reach it.
        expect(
          await service.resistanceSessionCount(
            fromMs: _day(20),
            toMs: _todayEnd(),
          ),
          3,
        );
      });

      test('the latest bodyweight is the newest by recordedAtMs', () async {
        expect(await StatsProgressService(repo).latestBodyWeightKg(), 78.5);
      });

      test('the window\'s nutrition series holds the logged days', () async {
        final points = await StatsProgressService(repo).nutritionSeries(
          fromMs: _day(13),
          toMs: _todayEnd(),
        );

        expect([
          for (final p in points) p.date,
        ], [_day(13), _day(6), _day(0)]);
      });
    });

    final edgeHarness = factory();

    group('${edgeHarness.name} — the latest bodyweight edges', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await edgeHarness.open();
      });

      tearDown(() async {
        await edgeHarness.close();
      });

      test('no measurement on file yields null', () async {
        expect(await StatsProgressService(repo).latestBodyWeightKg(), isNull);
      });

      test('a non-kg measurement yields null', () async {
        await _seedMeasurement(
          repo,
          id: 'm-lb',
          value: 175.0,
          unitId: 'unit-lb',
          recordedAtMs: _at(5, 8).millisecondsSinceEpoch,
        );

        expect(await StatsProgressService(repo).latestBodyWeightKg(), isNull);
      });
    });
  }

  test('S-2214 Mock and Hive give the same figures for all four reads', () async {
    Future<List<String>> read(RepositoryHarness harness) async {
      final repo = await harness.open();
      await _clearSeededFoods(repo);
      await _seedTarget(repo, day: _day(13), protein: 150);
      await _seedTarget(repo, day: _day(6), protein: 160);
      await _seedFood(repo, id: 'cf-13', day: _day(13), protein: 120);
      await _seedFood(repo, id: 'cf-0', day: _day(0), protein: 130);
      await _seedSession(
        repo,
        id: 's-res-12',
        start: _at(12, 9),
        effortKind: 'set',
      );
      await _seedSession(
        repo,
        id: 's-cardio-10',
        start: _at(10, 9),
        effortKind: 'timed',
      );
      await _seedMeasurement(
        repo,
        id: 'm-new',
        value: 78.5,
        unitId: MetricIds.unitKg,
        recordedAtMs: _at(5, 8).millisecondsSinceEpoch,
      );

      final service = StatsProgressService(repo);
      final series = await service.nutritionSeries(
        fromMs: _day(13),
        toMs: _todayEnd(),
      );
      final targets = await service.proteinTargetsByDay(
        fromMs: _day(13),
        toMs: _day(0),
      );
      final count = await service.resistanceSessionCount(
        fromMs: _day(13),
        toMs: _todayEnd(),
      );
      final weight = await service.latestBodyWeightKg();
      await harness.close();

      return <String>[
        ..._describeSeries(series),
        ...targets.entries.map((e) => '${e.key.millisecondsSinceEpoch}|${e.value}'),
        'count=$count',
        'kg=$weight',
      ];
    }

    final mock = await read(MockRepositoryHarness());
    final hive = await read(HiveRepositoryHarness());

    expect(mock, hive);
    // 2 logged days + 14 target days + the count + the bodyweight.
    expect(mock, hasLength(2 + 14 + 2));
  });
}
