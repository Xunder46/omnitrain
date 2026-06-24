// filepath: test/nutrition_log_from_library_test.dart
//
// Scenario tests for the "log a food as consumed from the library"
// feature. These tests pin the behavior described in
// `.github/agents/plans/nutrition-log-from-library-plan.md`:
//
//   S-001: Mark grams-type food consumed at 150 g (1.5x scaling).
//   S-002: Mark count-type food consumed at 3     (3x scaling).
//   S-003: Totals equal sum of scaled snapshots across multiple foods.
//   S-004: Logged entry is frozen — editing the source food does not
//          change it.
//   S-005: Logged entry is frozen — removing the source food does not
//          change it.
//   S-006: Logged entry is frozen — changing today's target does not
//          change it.
//   S-007: Amount edit on a logged row updates the existing snapshot.
//   S-008: Uncheck removes the log; re-check creates a new one.
//   S-009: Amount input rejects 0 and negative values.

import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/log_food_row.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log. The `SeedData.sampleConsumedFoods()` seed preloads three
  // today-dated rows for the Stats Nutrition Trend card; tests that
  // read `consumedToday` / `todayConsumedCalories` need a clean slate
  // to keep their totals and frozen-snapshot assertions deterministic.
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Grams-type library food: 100 g, 31P / 0C / 3F = 151 kcal.
/// Macros are `double` to match the [Food] model.
Food _chicken({
  String id = 'food-chicken',
  double protein = 31,
  double carbs = 0,
  double fat = 3,
  String? groupId,
}) {
  return Food(
    id: id,
    name: 'Chicken Breast',
    groupId: groupId,
    unitType: FoodUnitType.grams,
    referenceAmount: 100.0,
    referenceLabel: '100 g',
    protein: protein,
    carbs: carbs,
    fat: fat,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

/// Count-type library food: 1 egg, 6P / 1C / 5F = 69 kcal.
Food _egg({String id = 'food-egg'}) {
  return Food(
    id: id,
    name: 'Egg',
    unitType: FoodUnitType.count,
    referenceAmount: 1.0,
    referenceLabel: '1 egg',
    protein: 6,
    carbs: 1,
    fat: 5,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

Future<NutritionState> _buildState(MockWorkoutRepository repo) async {
  final state = NutritionState(repo);
  // Pre-warm the day's target cache so logConsumedFoodAt has a snapshot
  // to freeze (matches the live wiring in NutritionScreen.initState).
  await state.loadNutritionTarget();
  return state;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // S-001 — grams-type food at 150 g contributes 1.5x
  // ═══════════════════════════════════════════════════════════════════════
  group('S-001: log grams food at 150', () {
    test('1.5x scaling for grams-type food', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);

      final id = await state.logConsumedFoodAt(food, 150.0);
      expect(id, isNotNull);

      expect(state.consumedToday.length, 1);
      // (31*4 + 0*4 + 3*9) * (150 / 100) = 151 * 1.5 = 226.5; rounding
      // can land on 226 or 227 (Dart's double.round() rounds .5 toward
      // +∞). We accept either — the spec defines the formula, not the
      // rounding mode.
      expect(state.todayConsumedCalories, anyOf(226, 227));
      // protein: 31 * 1.5 = 46.5 → 46 or 47
      expect(state.todayConsumedProtein, anyOf(46, 47));
      // carbs: 0
      expect(state.todayConsumedCarbs, 0);
      // fat: 3 * 1.5 = 4.5 → 4 or 5
      expect(state.todayConsumedFat, anyOf(4, 5));

      // The snapshot itself carries the frozen per-reference macros
      // and the scaled amount.
      final entry = state.consumedToday.first;
      expect(entry.sourceFoodId, 'food-chicken');
      expect(entry.amountConsumed, 150.0);
      expect(entry.protein, 31);
      expect(entry.unitType, FoodUnitType.grams);
      expect(entry.referenceAmount, 100.0);
    });

    test('persists the snapshot to the repository', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, 150.0);

      final fromRepo = await repo.getConsumedFoodById(id!);
      expect(fromRepo, isNotNull);
      expect(fromRepo!.sourceFoodId, 'food-chicken');
      expect(fromRepo.amountConsumed, 150.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-002 — count-type food at 3 contributes 3x
  // ═══════════════════════════════════════════════════════════════════════
  group('S-002: log count food at 3', () {
    test('3x scaling for count-type food', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _egg();
      await foodLib.createFood(food);

      final state = await _buildState(repo);

      await state.logConsumedFoodAt(food, 3.0);

      expect(state.consumedToday.length, 1);
      // (6*4 + 1*4 + 5*9) * (3 / 1) = 73 * 3 = 219
      expect(state.todayConsumedCalories, 219);
      expect(state.todayConsumedProtein, 18); // 6 * 3
      expect(state.todayConsumedCarbs, 3); // 1 * 3
      expect(state.todayConsumedFat, 15); // 5 * 3

      final entry = state.consumedToday.first;
      expect(entry.unitType, FoodUnitType.count);
      expect(entry.referenceAmount, 1.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-003 — totals = sum of scaled snapshots
  // ═══════════════════════════════════════════════════════════════════════
  group('S-003: multiple foods sum correctly', () {
    test('two foods log additively', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      await foodLib.createFood(_chicken());
      await foodLib.createFood(_egg());

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(_chicken(), 150.0);
      await state.logConsumedFoodAt(_egg(), 3.0);

      expect(state.consumedToday.length, 2);
      // chicken: 151 * 1.5 = 226.5 (226 or 227); egg: 73 * 3 = 219;
      // total 445 or 446.
      expect(
        state.todayConsumedCalories,
        anyOf(226 + 219, 227 + 219),
      );
      // chicken: 31 * 1.5 = 46.5 (46 or 47); egg: 6 * 3 = 18; total 64-65.
      expect(state.todayConsumedProtein, anyOf(64, 65));
      // chicken: 3 * 1.5 = 4.5 (4 or 5); egg: 5 * 3 = 15; total 19-20.
      expect(state.todayConsumedFat, anyOf(19, 20));
    });

    test('consumedTodaySorted is sorted by loggedAtMs ascending', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      await foodLib.createFood(_chicken());
      await foodLib.createFood(_egg());

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(_chicken(), 100.0);
      // Force a later loggedAtMs on the second insert.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await state.logConsumedFoodAt(_egg(), 1.0);

      final sorted = state.consumedTodaySorted;
      expect(sorted.length, 2);
      expect(sorted.first.sourceFoodId, 'food-chicken');
      expect(sorted.last.sourceFoodId, 'food-egg');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-004 — snapshot is frozen when source food is edited
  // ═══════════════════════════════════════════════════════════════════════
  group('S-004: snapshot frozen against food edits', () {
    test('editing source food protein does not change the log', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(food, 150.0);

      // Edit the source food's protein in the library.
      await foodLib.updateFood(food.copyWith(protein: 50));

      // Reload the day's log and confirm the snapshot is intact.
      await state.refreshConsumedToday();
      final entry = state.consumedToday.first;
      expect(entry.protein, 31, reason: 'snapshot is frozen');
      expect(entry.caloriesConsumed, anyOf(226, 227),
          reason: 'calories computed from frozen macros');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-005 — snapshot is frozen when source food is removed
  // ═══════════════════════════════════════════════════════════════════════
  group('S-005: snapshot frozen against food removal', () {
    test('removing source food leaves the log intact', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(food, 150.0);

      // Hard-delete the source food from the library.
      await foodLib.removeFood('food-chicken');

      // Reload the day's log; the snapshot survives.
      await state.refreshConsumedToday();
      expect(state.consumedToday.length, 1);
      final entry = state.consumedToday.first;
      expect(entry.sourceFoodId, 'food-chicken',
          reason: 'dangling reference is expected');
      expect(entry.name, 'Chicken Breast');
      expect(entry.protein, 31);
      expect(entry.amountConsumed, 150.0);
      expect(entry.unitType, FoodUnitType.grams);
      expect(entry.referenceAmount, 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-006 — snapshot is frozen when target is changed
  // ═══════════════════════════════════════════════════════════════════════
  group('S-006: snapshot frozen against target changes', () {
    test('changing target after log does not rewrite snapshot', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      // Seed a target of 2000 kcal so the snapshot has a target to freeze.
      await state.saveNutritionTarget(NutritionTarget(calories: 2000));
      await state.loadNutritionTarget();

      await state.logConsumedFoodAt(food, 150.0);
      final entryAtLog = state.consumedToday.first;
      expect(entryAtLog.targetCalories, 2000.0);

      // Change today's target to 3000.
      await state.saveNutritionTarget(NutritionTarget(calories: 3000));
      await state.refreshConsumedToday();

      final entryAfter = state.consumedToday.first;
      expect(entryAfter.targetCalories, 2000.0,
          reason: 'frozen at log time');
      expect(entryAfter.caloriesConsumed, anyOf(226, 227),
          reason: 'calories from frozen macros + frozen amount');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-007 — amount edit updates the existing snapshot
  // ═══════════════════════════════════════════════════════════════════════
  group('S-007: amount edit updates existing row', () {
    test('second log of same food updates, not appends', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id1 = await state.logConsumedFoodAt(food, 150.0);
      final id2 = await state.logConsumedFoodAt(food, 200.0);

      expect(id1, equals(id2),
          reason: 'day-uniqueness: same row id, not a new row');
      expect(state.consumedToday.length, 1);
      // 151 * 2 = 302
      expect(state.todayConsumedCalories, 302);
      expect(state.consumedToday.first.amountConsumed, 200.0);
    });

    test('snapshot fields (macros, unit, name) are preserved on amount edit',
        () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, 150.0);
      final before = (await repo.getConsumedFoodById(id!))!;
      final beforeMacros = (before.protein, before.carbs, before.fat);

      // Re-log with a different amount.
      await state.logConsumedFoodAt(food, 200.0);

      final after = (await repo.getConsumedFoodById(id))!;
      expect((after.protein, after.carbs, after.fat), beforeMacros);
      expect(after.amountConsumed, 200.0);
      expect(after.sourceFoodId, 'food-chicken');
      expect(after.unitType, FoodUnitType.grams);
      expect(after.referenceAmount, 100.0);
      // updatedAtMs should be ≥ the previous value (monotonic).
      expect(after.updatedAtMs >= before.updatedAtMs, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-008 — uncheck removes; re-check creates a fresh row
  // ═══════════════════════════════════════════════════════════════════════
  group('S-008: unlog + re-log cycle', () {
    test('unlogFoodToday removes the row and notifies', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, 150.0);
      expect(state.consumedToday.length, 1);

      final removed = await state.unlogFoodToday('food-chicken');
      expect(removed, isTrue);
      expect(state.consumedToday, isEmpty);
      expect(await repo.getConsumedFoodById(id!), isNull);
    });

    test('unlogFoodToday is a no-op for an unknown food', () async {
      final repo = await _freshRepo();
      final state = await _buildState(repo);
      final removed = await state.unlogFoodToday('does-not-exist');
      expect(removed, isFalse);
    });

    test('re-log creates a new row id (not resurrection)', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id1 = await state.logConsumedFoodAt(food, 150.0);
      await state.unlogFoodToday('food-chicken');
      // Force a different `now` for the new id (the id uses
      // `consumed-<ms>-<sec>`; back-to-back calls inside the same
      // millisecond would produce identical ids).
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final id2 = await state.logConsumedFoodAt(food, 150.0);

      expect(id1, isNot(equals(id2)),
          reason: 'a deleted-then-recreated log has a new id');
      expect(state.consumedToday.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-009 — validation: 0 / negative blocked
  // ═══════════════════════════════════════════════════════════════════════
  group('S-009: amount validation', () {
    test('amount = 0 does not log', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, 0.0);
      expect(id, isNull, reason: 'zero amount is invalid');
      expect(state.consumedToday, isEmpty);
    });

    test('negative amount does not log', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, -5.0);
      expect(id, isNull);
      expect(state.consumedToday, isEmpty);
    });

    test('decimal amount logs for grams-type food', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      final id = await state.logConsumedFoodAt(food, 0.5);
      expect(id, isNotNull);
      expect(state.consumedToday.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════
  // S-044 — Sodium is frozen onto the ConsumedFood snapshot at log time
  // ═══════════════════════════════════════════════════════════════════════
  group('S-044: sodium frozen onto snapshot (D-7)', () {
    test('logged snapshot carries the source food\'s sodium value', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      // 74 mg / 100 g — a realistic chicken breast value.
      final food = _chicken().copyWith(sodium: 74);
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(food, 200.0);
      // 200 g × 74 mg / 100 g = 148 mg.
      expect(state.consumedToday.single.sodium, 74,
          reason: 'sodium is frozen on the snapshot at log time');
      expect(state.todayConsumedSodium, 148);
    });

    test(
      'editing the source food\'s sodium after logging does NOT change '
      'the snapshot',
      () async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final food = _chicken().copyWith(sodium: 74);
        await foodLib.createFood(food);

        final state = await _buildState(repo);
        await state.logConsumedFoodAt(food, 200.0);
        expect(state.consumedToday.single.sodium, 74);

        // Edit the source food's sodium in the library.
        await foodLib.updateFood(food.copyWith(sodium: 999));
        await state.refreshConsumedToday();

        // The snapshot is unchanged.
        expect(state.consumedToday.single.sodium, 74,
            reason: 'sodium freeze is a one-way copy at log time');
        expect(state.todayConsumedSodium, 148,
            reason: 'todayConsumedSodium is derived from the snapshot, '
                'not the live food');
      },
    );

    test('null sodium on the source food is frozen as null', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      // No sodium field (null).
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      await state.logConsumedFoodAt(food, 100.0);
      expect(state.consumedToday.single.sodium, isNull);
      // Null source sodium is treated as 0 in the daily total.
      expect(state.todayConsumedSodium, 0);
    });

    test('todayConsumedSodium rounds once across multiple rows', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final state = await _buildState(repo);

      // Two foods, each contributing a fraction of a milligram.
      // sodium = 33 mg/100g, amount = 50g → 16.5 mg (would round to 17
      // if rounded per row, but the getter accumulates as double and
      // rounds once at the end).
      final a = _chicken(id: 'food-a').copyWith(sodium: 33);
      final b = _chicken(id: 'food-b').copyWith(sodium: 33);
      await foodLib.createFood(a);
      await foodLib.createFood(b);
      await state.logConsumedFoodAt(a, 50.0);
      await state.logConsumedFoodAt(b, 50.0);

      // 16.5 + 16.5 = 33 mg (no per-row rounding drift).
      expect(state.todayConsumedSodium, 33);
    });
  });

  // Formatter regression — the dot character must be allowed in the
  // grams amount input. Previously the input was gated by an
  // anchored regex that rejected intermediate states, so the dot
  // did not appear when the user typed a decimal value.
  // ═══════════════════════════════════════════════════════════════════════
  group('amount input formatter (grams)', () {
    // We test the formatter behavior by driving a real TextField in
    // a widget pump. Importing the private `_GramsAmountFormatter`
    // would require exposing it; pumping a `LogFoodRow` exercises the
    // formatter end-to-end and is the contract that matters to users.
    testWidgets('typing "0.5" in the grams amount field keeps the dot',
        (tester) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);
      final nutritionState = await _buildState(repo);
      await foodLib.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: food,
              foodLibraryState: foodLib,
              nutritionState: nutritionState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountKey = Key('log_food_amount_${food.id}');
      // Clear the prefilled "100" and type "0.5".
      await tester.enterText(find.byKey(amountKey), '');
      await tester.enterText(find.byKey(amountKey), '0.5');
      await tester.pump();

      // The field must show "0.5" verbatim — the dot is preserved.
      final widget = tester.widget<TextField>(find.byKey(amountKey));
      expect(widget.controller!.text, '0.5',
          reason: 'dot must be allowed in the grams amount input');
    });

    testWidgets('typing more than one dot is rejected', (tester) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);
      final nutritionState = await _buildState(repo);
      await foodLib.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: food,
              foodLibraryState: foodLib,
              nutritionState: nutritionState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountKey = Key('log_food_amount_${food.id}');
      await tester.enterText(find.byKey(amountKey), '');
      await tester.enterText(find.byKey(amountKey), '1.5.5');
      await tester.pump();

      final widget = tester.widget<TextField>(find.byKey(amountKey));
      expect(widget.controller!.text, isNot('1.5.5'),
          reason: 'a second dot must be rejected by the formatter');
    });

    testWidgets('count-type amount field also allows the dot (regression)',
        (tester) async {
      // The count-type field used to be gated by `digitsOnly`, which
      // stripped the dot character even though the user could see
      // (and want to type) it. The dot must now be visible in both
      // unit types; the unit-type-specific validator decides whether
      // the resulting value is acceptable.
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _egg();
      await foodLib.createFood(food);
      final nutritionState = await _buildState(repo);
      await foodLib.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: food,
              foodLibraryState: foodLib,
              nutritionState: nutritionState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountKey = Key('log_food_amount_${food.id}');
      await tester.enterText(find.byKey(amountKey), '');
      await tester.enterText(find.byKey(amountKey), '3.5');
      await tester.pump();

      // The dot is preserved in the field. The validator will reject
      // the value when the user tries to commit, but the dot must be
      // visible to the user.
      final widget = tester.widget<TextField>(find.byKey(amountKey));
      expect(widget.controller!.text, '3.5',
          reason: 'dot must be allowed in the count amount input too');
    });

    testWidgets('fractional count is accepted as a multiplier', (tester) async {
      // Per the "amount is a multiplier" contract, 0.5 of a per-1-egg
      // food means "half an egg" — perfectly valid. The earlier
      // "Count foods require a whole number" check was over-restrictive
      // and has been removed; this test pins the new contract.
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _egg();
      await foodLib.createFood(food);
      final nutritionState = await _buildState(repo);
      await foodLib.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: food,
              foodLibraryState: foodLib,
              nutritionState: nutritionState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountKey = Key('log_food_amount_${food.id}');
      final thumbKey = Key('log_food_thumb_${food.id}');
      await tester.enterText(find.byKey(amountKey), '');
      await tester.enterText(find.byKey(amountKey), '0.5');
      await tester.pump();
      await tester.tap(find.byKey(thumbKey));
      await tester.pumpAndSettle();

      // The food is logged at amount = 0.5; the thumb's
      // checked semantics are now `isTrue` (S-005).
      expect(nutritionState.consumedToday.length, 1);
      expect(nutritionState.consumedToday.first.amountConsumed, 0.5);
      final semHandle = tester.ensureSemantics();
      try {
        final node = tester.getSemantics(find.byKey(thumbKey));
        expect(
          node.getSemanticsData().flagsCollection.isChecked,
          CheckedState.isTrue,
        );
      } finally {
        semHandle.dispose();
      }
    });

    testWidgets('zero count is still rejected', (tester) async {
      // 0 must remain invalid even for count foods (no-op log
      // protection).
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _egg();
      await foodLib.createFood(food);
      final nutritionState = await _buildState(repo);
      await foodLib.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: food,
              foodLibraryState: foodLib,
              nutritionState: nutritionState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountKey = Key('log_food_amount_${food.id}');
      final thumbKey = Key('log_food_thumb_${food.id}');
      await tester.enterText(find.byKey(amountKey), '');
      await tester.enterText(find.byKey(amountKey), '0');
      await tester.pump();
      await tester.tap(find.byKey(thumbKey));
      await tester.pumpAndSettle();

      expect(nutritionState.consumedToday, isEmpty,
          reason: 'zero is rejected for both unit types');
      expect(
        find.text('Amount must be greater than 0'),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Cache-only helpers used by the row widget
  // ═══════════════════════════════════════════════════════════════════════
  group('cache helpers', () {
    test('isFoodLoggedToday reflects the cache', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      expect(state.isFoodLoggedToday('food-chicken'), isFalse);

      await state.logConsumedFoodAt(food, 100.0);
      expect(state.isFoodLoggedToday('food-chicken'), isTrue);

      await state.unlogFoodToday('food-chicken');
      expect(state.isFoodLoggedToday('food-chicken'), isFalse);
    });

    test('findLoggedTodayForFood returns the row or null', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final state = await _buildState(repo);
      expect(state.findLoggedTodayForFood('food-chicken'), isNull);

      await state.logConsumedFoodAt(food, 100.0);
      final found = state.findLoggedTodayForFood('food-chicken');
      expect(found, isNotNull);
      expect(found!.amountConsumed, 100.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Repository additions (B-7, B-8)
  // ═══════════════════════════════════════════════════════════════════════
  group('repository: updateConsumedFood + getConsumedFoodById', () {
    test('updateConsumedFood persists changes to an existing row', () async {
      final repo = await _freshRepo();
      final state = await _buildState(repo);
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);
      final id = await state.logConsumedFoodAt(food, 150.0);

      final before = (await repo.getConsumedFoodById(id!))!;
      final updated = before.copyWith(amountConsumed: 250.0);
      await repo.updateConsumedFood(updated);

      final after = await repo.getConsumedFoodById(id);
      expect(after!.amountConsumed, 250.0);
    });

    test('updateConsumedFood throws for unknown id', () async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final food = _chicken();
      await foodLib.createFood(food);

      final ghost = ConsumedFood(
        id: 'does-not-exist',
        loggedAtMs: DateTime.now().millisecondsSinceEpoch,
        dateMs: OmniDateUtils.todayMidnightMs(),
        sourceFoodId: 'food-chicken',
        name: food.name,
        unitType: food.unitType,
        referenceAmount: food.referenceAmount,
        referenceLabel: food.referenceLabel,
        protein: food.protein,
        carbs: food.carbs,
        fat: food.fat,
        amountConsumed: 1.0,
        targetCalories: 0.0,
        targetProtein: 0.0,
        targetCarbs: 0.0,
        targetFat: 0.0,
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      expect(
        () => repo.updateConsumedFood(ghost),
        throwsA(isA<StateError>()),
      );
    });

    test('getConsumedFoodById returns null for unknown id', () async {
      final repo = await _freshRepo();
      final result = await repo.getConsumedFoodById('does-not-exist');
      expect(result, isNull);
    });
  });
}
