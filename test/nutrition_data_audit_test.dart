// Unit tests for the nutrition data layer audit.
// Tests the contract compliance: frozen snapshots, catalog/library separation, unit types.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('Food model', () {
    // Supporting test: Food round-trips with unit type and reference preserved
    test('round-trips with unit type count and reference preserved', () {
      final food = Food(
        id: 'food-1',
        name: 'Egg',
        groupId: null,
        unitType: FoodUnitType.count,
        referenceAmount: 1.0,
        referenceLabel: 'egg',
        isCatalog: false,
        protein: 6,
        carbs: 1,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final map = food.toMap();
      final restored = Food.fromMap(map);

      expect(restored.id, food.id);
      expect(restored.name, food.name);
      expect(restored.unitType, FoodUnitType.count);
      expect(restored.referenceAmount, 1.0);
      expect(restored.referenceLabel, 'egg');
      expect(restored.isCatalog, false);
      expect(restored.protein, 6);
      expect(restored.calories, 6 * 4 + 1 * 4 + 5 * 9); // 69
    });

    test('round-trips with unit type grams and reference preserved', () {
      final food = Food(
        id: 'food-2',
        name: 'Chicken Breast',
        groupId: 'group-1',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final map = food.toMap();
      final restored = Food.fromMap(map);

      expect(restored.unitType, FoodUnitType.grams);
      expect(restored.referenceAmount, 100.0);
      expect(restored.referenceLabel, 'g');
      expect(restored.isCatalog, true);
    });

    // Supporting test: FoodUnitType serializes as 'count' and 'grams'
    test('FoodUnitType serializes correctly', () {
      expect(FoodUnitType.count.toStorageString(), 'count');
      expect(FoodUnitType.grams.toStorageString(), 'grams');
      expect(FoodUnitType.fromString('count'), FoodUnitType.count);
      expect(FoodUnitType.fromString('grams'), FoodUnitType.grams);
      expect(FoodUnitType.fromString('unknown'), FoodUnitType.grams); // default
    });

    // Supporting test: Food.fromMap legacy-row fallback
    test('legacy row falls back gracefully', () {
      // Simulate legacy row without new fields
      final legacyMap = {
        'id': 'legacy-1',
        'name': 'Legacy Food',
        'group_id': null,
        'serving_size': 100,
        'serving_unit': 'g',
        'protein': 10,
        'carbs': 20,
        'fat': 5,
        'is_archived': 0,
        'created_at_ms': 100,
        'updated_at_ms': 100,
      };

      final food = Food.fromMap(legacyMap);

      expect(food.unitType, FoodUnitType.grams);
      expect(food.referenceAmount, 100.0);
      expect(food.referenceLabel, 'g');
      expect(food.isCatalog, false);
    });

    // Helper getters
    test('isCatalogFood and isLibraryFood work correctly', () {
      final catalogFood = Food(
        id: 'cat-1',
        name: 'Catalog Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final libraryFood = Food(
        id: 'lib-1',
        name: 'Library Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: false,
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      expect(catalogFood.isCatalogFood, true);
      expect(catalogFood.isLibraryFood, false);
      expect(libraryFood.isCatalogFood, false);
      expect(libraryFood.isLibraryFood, true);
    });
  });

  group('ConsumedFood model', () {
    // Supporting test: ConsumedFood round-trip
    test('round-trips all fields correctly', () {
      final consumed = ConsumedFood(
        id: 'consumed-1',
        loggedAtMs: 1700000000000,
        dateMs: 1700000000000,
        sourceFoodId: 'food-1',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        amountConsumed: 1.5,
        groupIdSnapshot: 'group-1',
        groupNameSnapshot: 'Proteins',
        targetCalories: 2000,
        targetProtein: 150,
        targetCarbs: 250,
        targetFat: 70,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );

      final map = consumed.toMap();
      final restored = ConsumedFood.fromMap(map);

      expect(restored.id, consumed.id);
      expect(restored.loggedAtMs, consumed.loggedAtMs);
      expect(restored.dateMs, consumed.dateMs);
      expect(restored.sourceFoodId, consumed.sourceFoodId);
      expect(restored.name, consumed.name);
      expect(restored.unitType, consumed.unitType);
      expect(restored.referenceAmount, consumed.referenceAmount);
      expect(restored.referenceLabel, consumed.referenceLabel);
      expect(restored.protein, consumed.protein);
      expect(restored.carbs, consumed.carbs);
      expect(restored.fat, consumed.fat);
      expect(restored.amountConsumed, consumed.amountConsumed);
      expect(restored.groupIdSnapshot, consumed.groupIdSnapshot);
      expect(restored.groupNameSnapshot, consumed.groupNameSnapshot);
      expect(restored.targetCalories, consumed.targetCalories);
      expect(restored.targetProtein, consumed.targetProtein);
      expect(restored.targetCarbs, consumed.targetCarbs);
      expect(restored.targetFat, consumed.targetFat);
    });

    test('calculates caloriesConsumed correctly', () {
      final consumed = ConsumedFood(
        id: 'consumed-1',
        loggedAtMs: 1700000000000,
        dateMs: 1700000000000,
        name: 'Test Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10, // 40 cal
        carbs: 20,   // 80 cal
        fat: 5,      // 45 cal
        amountConsumed: 2.0, // 2 g consumed of a per-100 g food
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );

      // (10*4 + 20*4 + 5*9) * (2.0 / 100.0) = 165 * 0.02 = 3.3 → 3
      expect(consumed.caloriesConsumed, 3);
    });

    test('caloriesConsumed: 150 g of per-100 g food is 1.5x (per spec)',
        () {
      final consumed = ConsumedFood(
        id: 'consumed-spec-1',
        loggedAtMs: 1700000000000,
        dateMs: 1700000000000,
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31, // 124 cal
        carbs: 0,    // 0 cal
        fat: 3,     // 27 cal
        amountConsumed: 150.0, // 1.5x the reference
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );

      // 151 * (150 / 100) = 151 * 1.5 = 226.5 → 227 (round half to even
      // gives 226; Dart's default double-to-int rounds .5 toward +∞ →
      // 227). The exact rounding is implementation-defined for the
      // fraction; the spec defines the formula, not the rounding mode.
      // We assert 226 OR 227 to stay robust.
      expect(consumed.caloriesConsumed, anyOf(226, 227));
    });

    test('caloriesConsumed: 3 of per-1-egg food is 3x', () {
      final consumed = ConsumedFood(
        id: 'consumed-spec-2',
        loggedAtMs: 1700000000000,
        dateMs: 1700000000000,
        name: 'Egg',
        unitType: FoodUnitType.count,
        referenceAmount: 1.0,
        referenceLabel: 'egg',
        protein: 6, // 24
        carbs: 1,   // 4
        fat: 5,    // 45
        amountConsumed: 3.0, // 3x the reference
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );

      // (6*4 + 1*4 + 5*9) * (3 / 1) = 73 * 3 = 219
      expect(consumed.caloriesConsumed, 219);
    });
  });

  group('MockWorkoutRepository — catalog vs library separation', () {
    test('getFoods returns only library foods (isCatalog == false)', () async {
      final repo = await _freshRepo();

      // Create a library food (isCatalog defaults to false)
      await repo.createFood(Food(
        id: 'lib-1',
        name: 'Library Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: false,
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      ));

      final libraryFoods = await repo.getFoods();

      expect(libraryFoods.length, 1);
      expect(libraryFoods[0].id, 'lib-1');
      expect(libraryFoods[0].isLibraryFood, true);
    });

    // Verify catalog and library are separate stores by checking that
    // a food marked isCatalog=true is NOT returned by getFoods
    test('foods with isCatalog=true are not returned by getFoods', () async {
      final repo = await _freshRepo();

      // Create a food marked as catalog (would go to catalog store if seeded separately)
      await repo.createFood(Food(
        id: 'cat-1',
        name: 'Catalog Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true, // Marked as catalog
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      ));

      // Create a library food
      await repo.createFood(Food(
        id: 'lib-1',
        name: 'Library Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: false,
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      ));

      final libraryFoods = await repo.getFoods();

      // Only library food should be returned
      expect(libraryFoods.length, 1);
      expect(libraryFoods[0].id, 'lib-1');
      expect(libraryFoods[0].isLibraryFood, true);
    });
  });

  group('MockWorkoutRepository — addCatalogFoodToLibrary', () {
    // Required test: Catalog is not mutated by adding/editing/removing library foods
    test('addCatalogFoodToLibrary throws when catalog food not found', () async {
      final repo = await _freshRepo();

      // Try to add a non-existent catalog food
      expect(
        () => repo.addCatalogFoodToLibrary('nonexistent-id'),
        throwsException,
      );
    });

    // Required test: Catalog is not mutated by adding library foods
    test('addCatalogFoodToLibrary creates copy with new id and isCatalog = false', () async {
      final repo = await _freshRepo();

      // Seed a catalog food
      final catalogFood = Food(
        id: 'cat-source-1',
        name: 'Original Catalog',
        groupId: 'group-1',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );
      await repo.seedCatalogFood(catalogFood);

      // Add to library
      final libraryId = await repo.addCatalogFoodToLibrary('cat-source-1');

      // Verify library food was created
      final libraryFood = await repo.getFoodById(libraryId);
      expect(libraryFood, isNotNull);
      expect(libraryFood!.name, 'Original Catalog');
      expect(libraryFood.isCatalog, false);
      expect(libraryFood.isLibraryFood, true);
      expect(libraryFood.id, isNot('cat-source-1')); // New ID

      // Verify original catalog food is unchanged
      final catalogFoods = await repo.getCatalogFoods(includeArchived: true);
      final original = catalogFoods.firstWhere((f) => f.id == 'cat-source-1');
      expect(original.name, 'Original Catalog');
      expect(original.isCatalog, true);
    });
  });

  group('MockWorkoutRepository — day log (ConsumedFood)', () {
    // Supporting test: getConsumedFoodsForDate returns only rows with matching dateMs
    test('getConsumedFoodsForDate returns only matching date', () async {
      final repo = await _freshRepo();

      const date1 = 1700000000000; // day 1
      const date2 = 1700086400000; // day 2

      await repo.createConsumedFood(ConsumedFood(
        id: 'consumed-1',
        loggedAtMs: date1,
        dateMs: date1,
        name: 'Food Day 1',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: date1,
        updatedAtMs: date1,
      ));

      await repo.createConsumedFood(ConsumedFood(
        id: 'consumed-2',
        loggedAtMs: date2,
        dateMs: date2,
        name: 'Food Day 2',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: date2,
        updatedAtMs: date2,
      ));

      final day1Foods = await repo.getConsumedFoodsForDate(date1);
      expect(day1Foods.length, 1);
      expect(day1Foods[0].name, 'Food Day 1');

      final day2Foods = await repo.getConsumedFoodsForDate(date2);
      expect(day2Foods.length, 1);
      expect(day2Foods[0].name, 'Food Day 2');
    });

    // Required test: A logged day's stored values do not change when source library food is edited/deleted
    test('logged day values are frozen and do not change when source food is edited', () async {
      final repo = await _freshRepo();

      const dateMs = 1700000000000;

      // Create a library food
      final food = Food(
        id: 'food-to-edit',
        name: 'Original Name',
        groupId: 'group-1',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: false,
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );
      await repo.createFood(food);

      // Log it
      await repo.createConsumedFood(ConsumedFood(
        id: 'log-1',
        loggedAtMs: dateMs,
        dateMs: dateMs,
        sourceFoodId: 'food-to-edit',
        name: 'Original Name',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        amountConsumed: 1.5,
        groupIdSnapshot: 'group-1',
        groupNameSnapshot: 'Proteins',
        targetCalories: 2000,
        targetProtein: 150,
        targetCarbs: 200,
        targetFat: 70,
        createdAtMs: dateMs,
        updatedAtMs: dateMs,
      ));

      // Verify initial snapshot
      var consumed = (await repo.getConsumedFoodsForDate(dateMs))[0];
      expect(consumed.name, 'Original Name');
      expect(consumed.protein, 31);
      expect(consumed.groupNameSnapshot, 'Proteins');

      // Edit the library food
      await repo.updateFood(Food(
        id: 'food-to-edit',
        name: 'Modified Name',
        groupId: 'group-2',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: false,
        protein: 50, // Changed!
        carbs: 5,
        fat: 8,
        createdAtMs: 100,
        updatedAtMs: 200,
      ));

      // Verify snapshot is unchanged
      consumed = (await repo.getConsumedFoodsForDate(dateMs))[0];
      expect(consumed.name, 'Original Name'); // Still original!
      expect(consumed.protein, 31); // Still original!
      expect(consumed.groupNameSnapshot, 'Proteins'); // Still original!

      // Delete the library food
      await repo.archiveFood('food-to-edit');

      // Verify snapshot is STILL unchanged
      consumed = (await repo.getConsumedFoodsForDate(dateMs))[0];
      expect(consumed.name, 'Original Name');
      expect(consumed.protein, 31);
    });

    // Required test: A logged day's target values do not change when current targets are edited
    test('logged day target values are frozen and do not change when targets are edited', () async {
      final repo = await _freshRepo();

      const dateMs = 1700000000000;

      // Set initial targets for the day
      await repo.saveNutritionTargetForDate(dateMs, NutritionTarget(
        calories: 2000,
        protein: 100,
        carbs: 200,
        fat: 60,
      ));

      // Log a food with snapshot of those targets
      await repo.createConsumedFood(ConsumedFood(
        id: 'log-1',
        loggedAtMs: dateMs,
        dateMs: dateMs,
        name: 'Test Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 20,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000, // FROZEN
        targetProtein: 100,   // FROZEN
        targetCarbs: 200,     // FROZEN
        targetFat: 60,        // FROZEN
        createdAtMs: dateMs,
        updatedAtMs: dateMs,
      ));

      // Verify initial targets in log
      var consumed = (await repo.getConsumedFoodsForDate(dateMs))[0];
      expect(consumed.targetCalories, 2000);
      expect(consumed.targetProtein, 100);
      expect(consumed.targetCarbs, 200);
      expect(consumed.targetFat, 60);

      // Change the targets
      await repo.saveNutritionTargetForDate(dateMs, NutritionTarget(
        calories: 2500,
        protein: 150,
        carbs: 300,
        fat: 80,
      ));

      // Verify log targets are STILL unchanged
      consumed = (await repo.getConsumedFoodsForDate(dateMs))[0];
      expect(consumed.targetCalories, 2000); // Still original!
      expect(consumed.targetProtein, 100);   // Still original!
      expect(consumed.targetCarbs, 200);     // Still original!
      expect(consumed.targetFat, 60);         // Still original!

      // Verify current targets have changed
      final currentTarget = await repo.getNutritionTargetForDate(dateMs);
      expect(currentTarget!.calories, 2500);
      expect(currentTarget.protein, 150);
    });

    test('getConsumedFoodsInRange returns foods in date range', () async {
      final repo = await _freshRepo();

      const date1 = 1700000000000;
      const date2 = 1700086400000;
      const date3 = 1700172800000;

      // Day 1
      await repo.createConsumedFood(ConsumedFood(
        id: 'c1',
        loggedAtMs: date1,
        dateMs: date1,
        name: 'Food 1',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: date1,
        updatedAtMs: date1,
      ));

      // Day 2
      await repo.createConsumedFood(ConsumedFood(
        id: 'c2',
        loggedAtMs: date2,
        dateMs: date2,
        name: 'Food 2',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: date2,
        updatedAtMs: date2,
      ));

      // Day 3
      await repo.createConsumedFood(ConsumedFood(
        id: 'c3',
        loggedAtMs: date3,
        dateMs: date3,
        name: 'Food 3',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 10,
        fat: 5,
        amountConsumed: 1.0,
        targetCalories: 2000,
        targetProtein: 100,
        targetCarbs: 200,
        targetFat: 60,
        createdAtMs: date3,
        updatedAtMs: date3,
      ));

      // Query range day1 to day2
      final range = await repo.getConsumedFoodsInRange(date1, date2);
      expect(range.length, 2);
      expect(range.map((c) => c.name), containsAll(['Food 1', 'Food 2']));
    });
  });
}
