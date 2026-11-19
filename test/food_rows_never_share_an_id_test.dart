// Plan 231 — foods logged back to back never overwrite each other.
//
// A logged row's id is built from a stamp that only ever goes up
// (`NutritionState._nextIdStamp`), because both stores replace a row with an
// equal id and two foods logged in the same millisecond would otherwise
// overwrite each other.
//
// Plan: `docs/plans/2026-11-17-231-food-rows-never-share-an-id-plan/2026-11-17-231-food-rows-never-share-an-id-plan.md`.
// Scenario mapping:
//   S-23101 six foods logged one after another with no delay → `S-23101 ...`
//   S-23102 the same six foods through `Future.wait`        → `S-23102 ...`
//   S-23103 the same food logged twice: one row, second amt → `S-23103 ...`
//   S-23104 two foods on a past day back to back            → `S-23104 ...`
//   S-23105 six past-day foods logged together              → `S-23105 ...`
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

List<Food> _sixFoods() =>
    List.generate(6, (i) => _food('food-231-$i', 'Plan 231 food $i'));

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();
    group('plan 231 row ids on ${harness.name}', () {
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

      tearDown(() async => await harness.close());

      Future<void> seedFoods(List<Food> foods) async {
        for (final food in foods) {
          await repository.createFood(food);
        }
      }

      test(
        'S-23101 six foods logged back to back keep six rows and six ids',
        () async {
          final foods = _sixFoods();
          await seedFoods(foods);

          for (var i = 0; i < foods.length; i++) {
            await nutrition.logConsumedFoodAt(foods[i], (i + 1) * 10.0);
          }

          final rows = await repository.getConsumedFoodsForDate(
            OmniDateUtils.todayMidnightMs(),
          );
          expect(rows, hasLength(6));
          expect(rows.map((r) => r.id).toSet(), hasLength(6));
          for (var i = 0; i < foods.length; i++) {
            final row = rows.firstWhere((r) => r.sourceFoodId == 'food-231-$i');
            expect(row.amountConsumed, (i + 1) * 10.0);
          }
        },
      );

      test(
        'S-23102 six foods logged through Future.wait keep six rows',
        () async {
          final foods = _sixFoods();
          await seedFoods(foods);

          await Future.wait([
            for (var i = 0; i < foods.length; i++)
              nutrition.logConsumedFoodAt(foods[i], (i + 1) * 10.0),
          ]);

          final rows = await repository.getConsumedFoodsForDate(
            OmniDateUtils.todayMidnightMs(),
          );
          expect(rows, hasLength(6));
          expect(rows.map((r) => r.id).toSet(), hasLength(6));
          for (var i = 0; i < foods.length; i++) {
            final row = rows.firstWhere((r) => r.sourceFoodId == 'food-231-$i');
            expect(row.amountConsumed, (i + 1) * 10.0);
          }
        },
      );

      test(
        'S-23103 the same food logged twice is one row with the second amount',
        () async {
          final food = _food('food-231-solo', 'Plan 231 solo food');
          await seedFoods([food]);

          final first = await nutrition.logConsumedFoodAt(food, 50.0);
          final second = await nutrition.logConsumedFoodAt(food, 175.0);

          expect(first, isNotNull);
          expect(
            second,
            first,
            reason: 'one row per food per day is updated, not duplicated',
          );
          final rows = await repository.getConsumedFoodsForDate(
            OmniDateUtils.todayMidnightMs(),
          );
          expect(rows, hasLength(1));
          expect(rows.single.amountConsumed, 175.0);
        },
      );

      test(
        'S-23105 six foods on a past day logged together keep six rows',
        () async {
          final now = DateTime.now();
          final threeDaysAgo = DateTime(now.year, now.month, now.day - 3, 12);
          final dayMs = DateTime(
            threeDaysAgo.year,
            threeDaysAgo.month,
            threeDaysAgo.day,
          ).millisecondsSinceEpoch;
          final foods = _sixFoods();
          await seedFoods(foods);

          // All six calls take their clock reading before any await, so they
          // share a millisecond: the wrist bridge's several-foods message.
          await Future.wait([
            for (var i = 0; i < foods.length; i++)
              nutrition.logConsumedFoodOnDay(
                foods[i],
                (i + 1) * 10.0,
                loggedAt: threeDaysAgo,
              ),
          ]);

          final rows = await repository.getConsumedFoodsInRange(dayMs, dayMs);
          expect(rows, hasLength(6));
          expect(rows.map((r) => r.id).toSet(), hasLength(6));
        },
      );

      test(
        'S-23104 two foods on a past day back to back keep two rows',
        () async {
          final now = DateTime.now();
          final threeDaysAgo = DateTime(now.year, now.month, now.day - 3, 12);
          final dayMs = DateTime(
            threeDaysAgo.year,
            threeDaysAgo.month,
            threeDaysAgo.day,
          ).millisecondsSinceEpoch;
          final rice = _food('food-231-rice', 'Rice');
          final beans = _food('food-231-beans', 'Beans');
          await seedFoods([rice, beans]);

          final first = await nutrition.logConsumedFoodOnDay(
            rice,
            120.0,
            loggedAt: threeDaysAgo,
          );
          final second = await nutrition.logConsumedFoodOnDay(
            beans,
            240.0,
            loggedAt: threeDaysAgo,
          );
          expect(first, isNotNull);
          expect(second, isNotNull);

          final rows = await repository.getConsumedFoodsInRange(dayMs, dayMs);
          expect(rows, hasLength(2));
          expect(rows.map((r) => r.id).toSet(), hasLength(2));
          expect(
            rows
                .firstWhere((r) => r.sourceFoodId == 'food-231-rice')
                .amountConsumed,
            120.0,
          );
          expect(
            rows
                .firstWhere((r) => r.sourceFoodId == 'food-231-beans')
                .amountConsumed,
            240.0,
          );
          expect(
            nutrition.consumedToday,
            isEmpty,
            reason: 'a past meal never reaches the today ring',
          );
        },
      );
    });
  }
}
