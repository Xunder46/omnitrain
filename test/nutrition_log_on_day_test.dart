// `NutritionState.logConsumedFoodOnDay` — a wrist food is filed on the day it
// was tapped (plan 112, D-18602), on both repository implementations.
//
// Plan: `docs/plans/2026-11-04-112-stats-sweep-fixes-plan/2026-11-04-112-stats-sweep-fixes-plan.md`.
// Scenario mapping:
//   S-18608 a past-day log is stored on that day and updated in place → `S-18608 ...`
//   S-18609 a loggedAt today delegates to the today log               → `S-18609 ...`
//
// Plain `test()` throughout: the Hive taps must never run inside
// `testWidgets` (FakeAsync never advances a real Hive write).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

Food _food(String id, String name) => Food(
  id: id,
  name: name,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 20,
  carbs: 30,
  fat: 10,
  createdAtMs: 0,
  updatedAtMs: 0,
);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();
    group('logConsumedFoodOnDay on ${harness.name}', () {
      late WorkoutRepository repository;
      late NutritionState nutrition;

      setUp(() async {
        final repo = await harness.open();
        repository = repo;
        if (repo is MockWorkoutRepository) {
          // The Mock seeds now-relative consumed-food rows for the Stats
          // trend card; the day-log counts below need a clean slate, which
          // is what the Hive group already starts with.
          repo.clearConsumedFoodsForTest();
        }
        nutrition = NutritionState(repo);
        await nutrition.loadConsumedToday();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-18608 a past-day log is stored on that day and updated in place', () async {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
        final yDayMs = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
        ).millisecondsSinceEpoch;

        final id = await nutrition.logConsumedFoodOnDay(
          _food('food-lentils', 'Lentils'),
          150,
          loggedAt: yesterday,
        );
        expect(id, isNotNull);

        final rows = await repository.getConsumedFoodsInRange(yDayMs, yDayMs);
        expect(rows, hasLength(1));
        expect(rows.single.sourceFoodId, 'food-lentils');
        expect(rows.single.amountConsumed, 150);
        expect(rows.single.dateMs, yDayMs);
        expect(rows.single.loggedAtMs, yesterday.millisecondsSinceEpoch);

        final second = await nutrition.logConsumedFoodOnDay(
          _food('food-lentils', 'Lentils'),
          275,
          loggedAt: yesterday,
        );
        expect(second, id, reason: 'one row per food per day is updated, not duplicated');
        final after = await repository.getConsumedFoodsInRange(yDayMs, yDayMs);
        expect(after, hasLength(1));
        expect(after.single.amountConsumed, 275);

        await nutrition.logConsumedFoodOnDay(
          _food('food-pearl-couscous', 'Pearl couscous'),
          120,
          loggedAt: yesterday,
        );
        final both = await repository.getConsumedFoodsInRange(yDayMs, yDayMs);
        expect(both, hasLength(2));

        expect(
          nutrition.consumedToday,
          isEmpty,
          reason: 'a past meal never reaches the today ring',
        );
      });

      test('S-18609 a loggedAt today delegates; invalid amounts store nothing', () async {
        final id = await nutrition.logConsumedFoodOnDay(
          _food('food-lentils', 'Lentils'),
          150,
          loggedAt: DateTime.now(),
        );
        expect(id, isNotNull);

        final today = nutrition.consumedToday;
        expect(today, hasLength(1));
        expect(today.single.sourceFoodId, 'food-lentils');
        expect(today.single.dateMs, OmniDateUtils.todayMidnightMs());

        final zero = await nutrition.logConsumedFoodOnDay(
          _food('food-pearl-couscous', 'Pearl couscous'),
          0,
          loggedAt: DateTime.now(),
        );
        expect(zero, isNull);
        final nan = await nutrition.logConsumedFoodOnDay(
          _food('food-pearl-couscous', 'Pearl couscous'),
          double.nan,
          loggedAt: DateTime.now(),
        );
        expect(nan, isNull);

        final stored = await repository.getConsumedFoodsForDate(
          OmniDateUtils.todayMidnightMs(),
        );
        expect(stored, hasLength(1), reason: 'an invalid amount stores nothing');
      });
    });
  }
}
