// Plan 253 P2 — the tests for "a food can carry its own calories number"
// (data and math, S-25301..S-25309).
//
// A food (and, frozen with the rest of the log-time snapshot, a logged row)
// can hold `caloriesOverride`: kcal per the food's reference amount that
// REPLACES the macro sum wherever calories are shown or added up. Macros,
// sodium and the macro donut never change because of it; a row logged before
// the change (no `calories_override` key) reads back as no override.
//
// Plan: `docs/plans/2026-11-19-253-calories-override-data-plan/
// 2026-11-19-253-calories-override-data-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition/nutrition_day_totals.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixtures ───────────────────────────────────────────────────────────────

/// Beer: 100 ml, 0.5 P / 3.6 C / 0 F (macro sum 16.4 kcal → 16), with the
/// brewery's own 43 kcal per 100 ml when [caloriesOverride] is given.
Food _beer({double? caloriesOverride}) => Food(
  id: 'f-beer',
  name: 'Beer',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'ml',
  protein: 0.5,
  carbs: 3.6,
  fat: 0,
  caloriesOverride: caloriesOverride,
  createdAtMs: 1,
  updatedAtMs: 1,
);

/// Rice: 100 g, 10 P / 10 C / 10 F (170 kcal), no override — the control
/// food whose calories stay macro-computed.
Food _rice() => Food(
  id: 'f-rice',
  name: 'Rice',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 10,
  carbs: 10,
  fat: 10,
  createdAtMs: 1,
  updatedAtMs: 1,
);

/// A logged row of the beer: 250 ml, frozen the way `NutritionState` freezes
/// a snapshot at log time. [caloriesOverride] is the frozen value.
ConsumedFood _beerRow({
  required int dateMs,
  double? caloriesOverride,
  double amountConsumed = 250,
  String id = 'c-beer',
}) => ConsumedFood(
  id: id,
  loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
  dateMs: dateMs,
  sourceFoodId: 'f-beer',
  name: 'Beer',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'ml',
  protein: 0.5,
  carbs: 3.6,
  fat: 0,
  amountConsumed: amountConsumed,
  targetCalories: 2000,
  targetProtein: 0,
  targetCarbs: 0,
  targetFat: 0,
  caloriesOverride: caloriesOverride,
  createdAtMs: dateMs,
  updatedAtMs: dateMs,
);

/// A logged row of the rice: 200 g, macro-only calories (340).
ConsumedFood _riceRow({required int dateMs, String id = 'c-rice'}) =>
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: 'f-rice',
      name: 'Rice',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 10,
      carbs: 10,
      fat: 10,
      amountConsumed: 200,
      targetCalories: 2000,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    );

// ─── Model scenarios (pure) ────────────────────────────────────────────────

void main() {
  group('S-25301: Food.calories honours the override', () {
    test('S-25301 the override replaces the macro sum; without it the sum '
        'stands', () {
      expect(_beer(caloriesOverride: 43).calories, 43);
      expect(_beer().calories, 16); // 0.5×4 + 3.6×4 = 16.4 → 16
      expect(_rice().calories, 170); // 10×4 + 10×4 + 10×9
    });
  });

  group('S-25302: Food.toMap / fromMap carry the override', () {
    test('S-25302 a stored override survives the roundtrip', () {
      final restored = Food.fromMap(_beer(caloriesOverride: 43).toMap());
      expect(restored.caloriesOverride, 43.0);
      expect(restored.calories, 43);
    });

    test('S-25302 a map with no calories_override key reads as no override '
        '(old rows)', () {
      final legacy = _beer(caloriesOverride: 43).toMap()
        ..remove('calories_override');
      final restored = Food.fromMap(legacy);
      expect(restored.caloriesOverride, isNull);
      expect(restored.calories, 16);
    });
  });

  group('S-25303: Food.copyWith can set, keep and clear the override', () {
    test('S-25303 an explicit null clears it; no argument keeps it; a new '
        'number replaces it', () {
      final beer = _beer(caloriesOverride: 43);
      expect(beer.copyWith(caloriesOverride: null).caloriesOverride, isNull);
      expect(beer.copyWith().caloriesOverride, 43.0);
      expect(beer.copyWith(caloriesOverride: 50.0).caloriesOverride, 50.0);
    });
  });

  group('S-25304: ConsumedFood.caloriesConsumed scales the override once', () {
    test('S-25304 250 ml of the 43-kcal beer is 108 (107.5 rounds once); '
        'without the override 41', () {
      expect(_beerRow(dateMs: 1, caloriesOverride: 43).caloriesConsumed, 108);
      expect(_beerRow(dateMs: 1).caloriesConsumed, 41); // 16.4 × 2.5
    });
  });

  group('S-25305: ConsumedFood.toMap / fromMap carry the frozen override', () {
    test('S-25305 a frozen override survives the roundtrip', () {
      final restored = ConsumedFood.fromMap(
        _beerRow(dateMs: 1, caloriesOverride: 43).toMap(),
      );
      expect(restored.caloriesOverride, 43.0);
      expect(restored.caloriesConsumed, 108);
    });

    test(
      'S-25305 a map with no calories_override key reads as no override',
      () {
        final legacy = _beerRow(dateMs: 1, caloriesOverride: 43).toMap()
          ..remove('calories_override');
        final restored = ConsumedFood.fromMap(legacy);
        expect(restored.caloriesOverride, isNull);
        expect(restored.caloriesConsumed, 41);
      },
    );
  });

  group('S-25307: NutritionDayTotals adds the overridden calories only', () {
    test('S-25307 the day totals add 108 + 340 = 448, and every macro total '
        'equals the macro-only math', () {
      final dayMs = OmniDateUtils.todayMidnightMs();
      final withOverride = NutritionDayTotals.of([
        _beerRow(dateMs: dayMs, caloriesOverride: 43),
        _riceRow(dateMs: dayMs),
      ]);
      final withoutOverride = NutritionDayTotals.of([
        _beerRow(dateMs: dayMs),
        _riceRow(dateMs: dayMs, id: 'c-rice-no-override'),
      ]);

      expect(withOverride.calories, 448);
      // The override changes calories only: protein 1.25 + 20 → 21,
      // carbs 9 + 20 → 29, fat 0 + 20 → 20, on both row sets.
      expect(withOverride.protein, withoutOverride.protein);
      expect(withOverride.carbs, withoutOverride.carbs);
      expect(withOverride.fat, withoutOverride.fat);
      expect(withOverride.fiber, withoutOverride.fiber);
      expect(withOverride.sodium, withoutOverride.sodium);
      expect(withoutOverride.calories, 381); // 41 + 340
    });
  });

  group(
    'S-25308: calculateCalories and the watch payload read the override',
    () {
      test(
        'S-25308 calculateCalories returns the override, not the macro sum',
        () {
          expect(calculateCalories(_beer(caloriesOverride: 43)), 43);
          expect(calculateCalories(_beer()), 16);
        },
      );

      test('S-25308 the foods_down payload carries the override as '
          'caloriesPerServing', () {
        final frame = WatchReferenceSync.buildFoodsDown(
          foods: [_beer(caloriesOverride: 43)],
          groups: const [],
          generatedAt: DateTime(2026, 11, 19, 10),
        );
        final payload = frame['payload'] as Map<String, Object?>;
        final rows = payload['foods'] as List<Object?>;
        expect(rows, hasLength(1));
        final beer = rows.single as Map<String, Object?>;
        expect(beer['foodId'], 'f-beer');
        expect(beer['caloriesPerServing'], 43);
      });
    },
  );

  // A food missing from the library is shown from its logged row's own frozen
  // numbers (plan 247): the display food must carry the frozen override too, or
  // the row's calories would revert to the macro sum.
  test(
    'S-25310 the display food of a logged row keeps its frozen override',
    () {
      final day = DateTime(2026, 11, 18).millisecondsSinceEpoch;
      final withOverride = foodFromConsumedSnapshot(
        _beerRow(dateMs: day, caloriesOverride: 43),
      );
      final without = foodFromConsumedSnapshot(_beerRow(dateMs: day));
      expect(withOverride.caloriesOverride, 43);
      expect(calculateCalories(withOverride), 43);
      expect(without.caloriesOverride, isNull);
      expect(calculateCalories(without), 16);
    },
  );

  // ─── Stored scenarios (Mock AND Hive) ────────────────────────────────────

  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: the log-time freeze (S-25306)', () {
      late RepositoryHarness harness;
      late WorkoutRepository repo;

      setUp(() async {
        harness = make();
        repo = await harness.open();
        // The Mock seed pre-loads today rows; tests that read
        // `todayConsumedCalories` need a clean day-log. Hive seeds no
        // consumed foods.
        if (repo is MockWorkoutRepository) {
          (repo as MockWorkoutRepository).clearConsumedFoodsForTest();
        }
      });
      tearDown(() => harness.close());

      test('S-25306 logging the beer freezes the override into the row, and '
          'editing the library food later never changes the day', () async {
        await repo.createFood(_beer(caloriesOverride: 43));
        final state = NutritionState(repo);
        await state.loadNutritionTarget();

        await state.logConsumedFood(_beer(caloriesOverride: 43), 250);
        await state.loadConsumedToday();
        expect(state.todayConsumedCalories, 108); // 43 × 2.5 = 107.5 → 108

        final rows = await repo.getConsumedFoodsForDate(
          OmniDateUtils.todayMidnightMs(),
        );
        expect(rows, hasLength(1));
        expect(rows.single.caloriesOverride, 43);

        await repo.updateFood(_beer(caloriesOverride: 100.0));
        await state.loadConsumedToday();
        expect(state.todayConsumedCalories, 108); // frozen with the row
      });

      test(
        'S-25306b changing the logged amount keeps the frozen override',
        () async {
          await repo.createFood(_beer(caloriesOverride: 43));
          final state = NutritionState(repo);
          await state.loadNutritionTarget();
          await state.logConsumedFood(_beer(caloriesOverride: 43), 250);

          // The food changed since: the row still carries what was frozen.
          await repo.updateFood(_beer(caloriesOverride: 100.0));
          await state.logConsumedFoodAt(_beer(caloriesOverride: 100.0), 500);
          await state.loadConsumedToday();

          final rows = await repo.getConsumedFoodsForDate(
            OmniDateUtils.todayMidnightMs(),
          );
          expect(rows, hasLength(1));
          expect(rows.single.caloriesOverride, 43);
          expect(rows.single.caloriesConsumed, 215); // 43 x 5.0
          expect(state.todayConsumedCalories, 215);
        },
      );
    });

    group('$name: the Stats nutrition series (S-25309)', () {
      late RepositoryHarness harness;
      late WorkoutRepository repo;

      setUp(() async {
        harness = make();
        repo = await harness.open();
        if (repo is MockWorkoutRepository) {
          (repo as MockWorkoutRepository).clearConsumedFoodsForTest();
        }
      });
      tearDown(() => harness.close());

      test('S-25309 the day whose row holds the override totals 108', () async {
        final dayMs = OmniDateUtils.todayMidnightMs();
        await repo.createConsumedFood(
          _beerRow(dateMs: dayMs, caloriesOverride: 43),
        );

        final trend = await StatsProgressService(
          repo,
        ).computeNutritionTrend(days: null);
        expect(trend, hasLength(1));
        expect(trend.single.calories, 108);
      });
    });
  }
}
