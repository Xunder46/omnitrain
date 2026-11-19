// Two Stats reads that step by days must step by calendar day, not by 24 h:
// across a DST change a 24 h step drifts off local midnight.
//
// - The NUTRITION adherence line walks the logged days one at a time and keys
//   each target change by the day it starts on. Drift keyed the change at
//   01:00 or 23:00 instead of midnight.
// - The top-lift recency cutoff is the midnight 30 calendar days back. Drift
//   put it an hour late, so a lift last trained exactly 30 days ago dropped out.
//
// The boundary is the first day of 2026 whose local length is not 24 h, so the
// test never depends on today's date. Needs a time zone with DST; skipped in
// one without (UTC). To force one:
// `TZ=America/New_York flutter test test/stats_dst_day_arithmetic_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// Local midnight of the day after the first DST change in 2026, or null when
/// the zone has none.
DateTime? _dayAfterFirstDstChange() {
  for (
    var d = DateTime(2026, 1, 1);
    d.year == 2026;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) return next;
  }
  return null;
}

NutritionTarget _target(double calories) =>
    NutritionTarget(calories: calories, protein: 100, carbs: 250, fat: 70);

Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required DateTime day,
}) async {
  final dateMs = day.millisecondsSinceEpoch;
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
      protein: 50,
      carbs: 200,
      fiber: 0,
      fat: 50,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 2000,
      targetProtein: 100,
      targetCarbs: 250,
      targetFat: 70,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

void main() {
  final after = _dayAfterFirstDstChange();
  const skip = 'time zone without DST';

  for (final factory in harnessFactories) {
    final harness = factory();

    test(
      '${harness.name} — adherence line keys a target change at local midnight '
      'after a DST change',
      () async {
        final repo = await harness.open();
        addTearDown(harness.close);
        for (final f in await repo.getConsumedFoodsInRange(0, 9999999999999)) {
          await repo.deleteConsumedFood(f.id);
        }
        final first = DateTime(after!.year, after.month, after.day - 5);
        final change = DateTime(after.year, after.month, after.day + 1);
        final last = DateTime(after.year, after.month, after.day + 3);
        await repo.saveNutritionTargetForDate(
          first.millisecondsSinceEpoch,
          _target(2000),
        );
        await repo.saveNutritionTargetForDate(
          change.millisecondsSinceEpoch,
          _target(2400),
        );
        await _seedFood(repo, id: 'f-first', day: first);
        await _seedFood(repo, id: 'f-last', day: last);

        final adherence = await StatsProgressService(
          repo,
        ).computeNutritionAdherence();

        expect(adherence.targetLine.map((p) => p.date).toList(), [
          first,
          change,
        ]);
        expect(adherence.targetLine.map((p) => p.calories).toList(), [
          2000,
          2400,
        ]);
      },
      skip: after == null ? skip : null,
    );
  }

  test(
    'the top-lift recency cutoff is a local midnight 30 calendar days back',
    () {
      // Reading on the day after the change puts the change inside the window.
      final now = DateTime(after!.year, after.month, after.day, 15, 30);
      final cutoff = StatsProgressService.topExerciseRecencyCutoff(now);
      expect(
        cutoff,
        DateTime(
          after.year,
          after.month,
          after.day - StatsProgressService.kTopExerciseRecencyDays,
        ),
      );
      expect(cutoff.hour, 0);
      expect(cutoff.minute, 0);
    },
    skip: after == null ? skip : null,
  );
}
