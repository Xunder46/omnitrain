import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/core/models/food_draft.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('FoodLibraryState', () {
    // ─── Initialization & Caching ─────────────────────────────────────────

    test('initial state has empty caches and not loading', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // The cache is empty until loadFoodGroups()/loadFoods() is called.
      // The repo has 9 default groups, but the cache is demand-loaded.
      expect(state.foodGroups, isEmpty);
      expect(state.foods, isEmpty);
      expect(state.isLoadingGroups, isFalse);
      expect(state.isLoadingFoods, isFalse);
    });

    // ─── Food Group CRUD ──────────────────────────────────────────────────

    test('createFoodGroup creates group and updates cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Load the default groups from the repo into the cache.
      await state.loadFoodGroups();
      final baseline = state.foodGroups.length;

      final id = await state.createFoodGroup('My Proteins', color: '#FF5722');

      expect(id, isNotEmpty);
      expect(state.foodGroups, hasLength(baseline + 1));
      final created = state.foodGroups.firstWhere((g) => g.id == id);
      expect(created.name, 'My Proteins');
      expect(created.color, '#FF5722');
      expect(created.isArchived, isFalse);
    });

    test(
      'createFoodGroup without color creates group with null color',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        // Load the default groups from the repo into the cache.
        await state.loadFoodGroups();
        final baseline = state.foodGroups.length;

        await state.createFoodGroup('My Vegetables');

        expect(state.foodGroups, hasLength(baseline + 1));
        final created = state.foodGroups.firstWhere(
          (g) => g.name == 'My Vegetables',
        );
        expect(created.color, isNull);
      },
    );

    test('getFoodGroupById returns from cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final id = await state.createFoodGroup('My Proteins');
      final retrieved = await state.getFoodGroupById(id);

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'My Proteins');
    });

    test('getFoodGroupById returns null when not found', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final result = await state.getFoodGroupById('nonexistent-id');

      expect(result, isNull);
    });

    test('updateFoodGroup updates cache and repository', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final id = await state.createFoodGroup('My Proteins', color: '#FF5722');
      final group = state.foodGroups.firstWhere((g) => g.id == id);

      final updated = FoodGroup(
        id: group.id,
        name: 'Protein Sources',
        color: '#4CAF50',
        isArchived: group.isArchived,
        createdAtMs: group.createdAtMs,
        updatedAtMs: group.updatedAtMs,
      );

      await state.updateFoodGroup(updated);

      final after = state.foodGroups.firstWhere((g) => g.id == id);
      expect(after.name, 'Protein Sources');
      expect(after.color, '#4CAF50');
    });

    test('archiveFoodGroup marks group as archived', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final id = await state.createFoodGroup('My Proteins');
      final before = state.foodGroups.firstWhere((g) => g.id == id);
      expect(before.isArchived, isFalse);

      await state.archiveFoodGroup(id);

      final after = state.foodGroups.firstWhere((g) => g.id == id);
      expect(after.isArchived, isTrue);
    });

    test('archiveFoodGroup throws when group not found', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      expect(() => state.archiveFoodGroup('nonexistent-id'), throwsException);
    });

    test('loadFoodGroups loads all groups from repository', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final defaultCount = SeedData.defaultFoodGroups.length;

      // Seed groups directly
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-1',
          name: 'My Proteins',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-2',
          name: 'My Vegetables',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoodGroups();

      expect(state.foodGroups, hasLength(defaultCount + 2));
      expect(
        state.foodGroups.map((g) => g.name).toList(),
        containsAll(['My Proteins', 'My Vegetables']),
      );
    });

    test('loadFoodGroups excludes archived groups by default', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final defaultCount = SeedData.defaultFoodGroups.length;

      // Seed: one active, one archived
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-1',
          name: 'Active Group',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-2',
          name: 'Archived Group',
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoodGroups(includeArchived: false);

      // Default groups + the new active group, but not the archived one.
      expect(state.foodGroups, hasLength(defaultCount + 1));
      expect(state.foodGroups.any((g) => g.name == 'Active Group'), isTrue);
      expect(state.foodGroups.any((g) => g.name == 'Archived Group'), isFalse);
    });

    test('loadFoodGroups includes archived groups when requested', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final defaultCount = SeedData.defaultFoodGroups.length;

      // Seed: one active, one archived
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-1',
          name: 'Active Group',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-2',
          name: 'Archived Group',
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoodGroups(includeArchived: true);

      // All default groups + the new active + the new archived.
      expect(state.foodGroups, hasLength(defaultCount + 2));
    });

    // ─── Food CRUD ────────────────────────────────────────────────────────

    test('createFood creates food and updates cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final id = await state.createFood(food);

      expect(id, isNotEmpty);
      expect(state.foods, hasLength(1));
      expect(state.foods[0].name, 'Chicken Breast');
      expect(state.foods[0].protein, 31);
      expect(state.foods[0].isArchived, isFalse);
    });

    test('createFood with provided id uses that id', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: 'custom-id',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final id = await state.createFood(food);

      expect(id, 'custom-id');
    });

    test('getFoodById returns from cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final id = await state.createFood(food);
      final retrieved = await state.getFoodById(id);

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Chicken Breast');
    });

    test('getFoodById returns null when not found', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final result = await state.getFoodById('nonexistent-id');

      expect(result, isNull);
    });

    test('updateFood updates cache and repository', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      await state.createFood(food);
      final original = state.foods[0];

      final updated = Food(
        id: original.id,
        name: 'Chicken Breast (cooked)',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 35,
        carbs: 0,
        fat: 4,
        createdAtMs: original.createdAtMs,
        updatedAtMs: original.updatedAtMs,
      );

      await state.updateFood(updated);

      expect(state.foods[0].name, 'Chicken Breast (cooked)');
      expect(state.foods[0].protein, 35);
    });

    test('archiveFood marks food as archived', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final id = await state.createFood(food);
      expect(state.foods[0].isArchived, isFalse);

      await state.archiveFood(id);

      expect(state.foods[0].isArchived, isTrue);
    });

    test('archiveFood throws when food not found', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      expect(() => state.archiveFood('nonexistent-id'), throwsException);
    });

    test('loadFoods loads all foods from repository', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed foods directly
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Rice',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 3,
          carbs: 28,
          fat: 0,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoods();

      expect(state.foods, hasLength(2));
      expect(
        state.foods.map((f) => f.name).toList(),
        containsAll(['Chicken Breast', 'Rice']),
      );
    });

    test('loadFoods excludes archived foods by default', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed: one active, one archived
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Active Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Archived Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoods(includeArchived: false);

      expect(state.foods, hasLength(1));
      expect(state.foods[0].name, 'Active Food');
    });

    test('loadFoods includes archived foods when requested', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed: one active, one archived
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Active Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Archived Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await state.loadFoods(includeArchived: true);

      expect(state.foods, hasLength(2));
    });

    // ─── Search ───────────────────────────────────────────────────────────

    test('searchFoods returns matching results', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed foods
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Broccoli',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 3,
          carbs: 7,
          fat: 0,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final results = await state.searchFoods('chicken');

      expect(results, hasLength(1));
      expect(results[0].name, 'Chicken Breast');
    });

    test('searchFoods is case-insensitive', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed food
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final results = await state.searchFoods('CHICKEN');

      expect(results, hasLength(1));
      expect(results[0].name, 'Chicken Breast');
    });

    test('searchFoods excludes archived foods by default', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed: one active, one archived
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Active Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Archived Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final results = await state.searchFoods(
        'chicken',
        includeArchived: false,
      );

      expect(results, hasLength(1));
      expect(results[0].name, 'Active Chicken');
    });

    test('searchFoods includes archived foods when requested', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Seed: one active, one archived
      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Active Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createFood(
        Food(
          id: 'food-2',
          name: 'Archived Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          isArchived: true,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final results = await state.searchFoods('chicken', includeArchived: true);

      expect(results, hasLength(2));
    });

    // ─── Catalog → Library (S-003) ─────────────────────────────────────────

    test(
      'addCatalogFoodToLibrary inserts a library copy with catalog values',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        // Pin a deterministic catalog seed so the test is not coupled to
        // the bundled catalog content. We seed directly into the catalog
        // box and read it back to confirm the values we will assert on
        // are the ones the user will see in the Add-from-Catalog tab.
        final catalogSource = const Food(
          id: 'test-catalog-apple',
          name: 'Apple (test)',
          groupId: 'g-fruit',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 0,
          carbs: 14,
          fat: 0,
          createdAtMs: 100,
          updatedAtMs: 100,
        );
        await repo.seedCatalogFood(catalogSource);

        // Library starts empty.
        await state.loadFoods();
        expect(
          state.foods,
          isEmpty,
          reason: 'sanity: fresh library should be empty',
        );

        // Add it via the state helper.
        final newId = await state.addCatalogFoodToLibrary('test-catalog-apple');
        expect(newId, isNotEmpty);
        expect(
          newId,
          isNot(equals('test-catalog-apple')),
          reason: 'library copy must have a fresh id, not the catalog id',
        );

        // Refresh the cache so the assertion is independent of whether
        // the helper inserts the food in-memory or only via the repo.
        await state.loadFoods();
        expect(state.foods, hasLength(1));
        final libFood = state.foods.single;
        expect(libFood.id, newId);
        expect(libFood.name, 'Apple (test)');
        expect(libFood.unitType, FoodUnitType.grams);
        expect(libFood.referenceAmount, 100.0);
        expect(libFood.referenceLabel, 'g');
        expect(libFood.protein, 0);
        expect(libFood.carbs, 14);
        expect(libFood.fat, 0);
        expect(
          libFood.isCatalog,
          isFalse,
          reason: 'library copy must have isCatalog = false',
        );
      },
    );

    test('addCatalogFoodToLibrary leaves the catalog unchanged', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      await repo.seedCatalogFood(
        const Food(
          id: 'test-catalog-pear',
          name: 'Pear (test)',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 0,
          carbs: 15,
          fat: 0,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      final catalogBefore = await repo.getCatalogFoodById('test-catalog-pear');
      expect(catalogBefore, isNotNull);
      final beforeName = catalogBefore!.name;
      final beforeCarbs = catalogBefore.carbs;

      await state.addCatalogFoodToLibrary('test-catalog-pear');

      // Catalog row is unchanged.
      final catalogAfter = await repo.getCatalogFoodById('test-catalog-pear');
      expect(catalogAfter, isNotNull);
      expect(catalogAfter!.name, beforeName);
      expect(catalogAfter.carbs, beforeCarbs);
      expect(catalogAfter.isCatalog, isTrue);
    });

    // ─── + New Item Food (S-004) ────────────────────────────────────────

    test('createCustomFood persists in the library', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      // Create a real group first so the custom food can be linked to it.
      final groupId = await state.createFoodGroup('Snacks');
      await state.loadFoodGroups();

      final id = await state.createCustomFood(
        name: 'My Trail Mix',
        groupId: groupId,
        unitType: FoodUnitType.grams,
        referenceAmount: 50.0,
        referenceLabel: 'g',
        protein: 10,
        carbs: 18,
        fat: 12,
      );
      expect(id, isNotEmpty);

      await state.loadFoods();
      final libFood = state.foods.firstWhere(
        (f) => f.id == id,
        orElse: () => state.foods.first,
      );
      expect(libFood.name, 'My Trail Mix');
      expect(libFood.groupId, groupId);
      expect(libFood.unitType, FoodUnitType.grams);
      expect(libFood.referenceAmount, 50.0);
      expect(libFood.referenceLabel, 'g');
      expect(libFood.protein, 10);
      expect(libFood.carbs, 18);
      expect(libFood.fat, 12);
      expect(
        libFood.isCatalog,
        isFalse,
        reason: 'custom foods must have isCatalog = false',
      );
    });

    test('createCustomFood is absent from the catalog', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final id = await state.createCustomFood(
        name: 'My Custom Protein Bar',
        groupId: null,
        unitType: FoodUnitType.count,
        referenceAmount: 1.0,
        referenceLabel: 'bar',
        protein: 20,
        carbs: 25,
        fat: 8,
      );

      // The custom food is in the library…
      await state.loadFoods();
      final inLibrary = state.foods.any((f) => f.id == id);
      expect(inLibrary, isTrue);

      // …but it is NOT in the catalog (no row with the same id).
      final allCatalog = await repo.getCatalogFoods(includeArchived: true);
      final leaked = allCatalog.where((f) => f.id == id).toList();
      expect(
        leaked,
        isEmpty,
        reason: 'createCustomFood must not insert into the catalog box',
      );
    });

    test('createCustomFood notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      var notified = false;
      state.addListener(() => notified = true);

      await state.createCustomFood(
        name: 'Listener Probe',
        groupId: null,
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 5,
        carbs: 5,
        fat: 5,
      );

      expect(notified, isTrue);
    });

    // ─── Listener Notification ────────────────────────────────────────────

    test('createFoodGroup notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      var notified = false;
      state.addListener(() => notified = true);

      await state.createFoodGroup('Proteins');

      expect(notified, isTrue);
    });

    test('updateFoodGroup notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      await state.createFoodGroup('Proteins');
      final group = state.foodGroups[0];

      var notified = false;
      state.addListener(() => notified = true);

      final updated = FoodGroup(
        id: group.id,
        name: 'Updated',
        color: group.color,
        isArchived: group.isArchived,
        createdAtMs: group.createdAtMs,
        updatedAtMs: group.updatedAtMs,
      );

      await state.updateFoodGroup(updated);

      expect(notified, isTrue);
    });

    test('archiveFoodGroup notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final id = await state.createFoodGroup('Proteins');

      var notified = false;
      state.addListener(() => notified = true);

      await state.archiveFoodGroup(id);

      expect(notified, isTrue);
    });

    test('createFood notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      var notified = false;
      state.addListener(() => notified = true);

      final food = Food(
        id: '',
        name: 'Chicken',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      await state.createFood(food);

      expect(notified, isTrue);
    });

    test('updateFood notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      await state.createFood(food);
      final original = state.foods[0];

      var notified = false;
      state.addListener(() => notified = true);

      final updated = Food(
        id: original.id,
        name: 'Updated Chicken',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 35,
        carbs: 0,
        fat: 4,
        createdAtMs: original.createdAtMs,
        updatedAtMs: original.updatedAtMs,
      );

      await state.updateFood(updated);

      expect(notified, isTrue);
    });

    test('archiveFood notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = Food(
        id: '',
        name: 'Chicken',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final id = await state.createFood(food);

      var notified = false;
      state.addListener(() => notified = true);

      await state.archiveFood(id);

      expect(notified, isTrue);
    });

    test('loadFoodGroups notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      await repo.createFoodGroup(
        FoodGroup(
          id: 'group-1',
          name: 'Proteins',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      var notified = false;
      state.addListener(() => notified = true);

      await state.loadFoodGroups();

      expect(notified, isTrue);
    });

    test('loadFoods notifies listeners', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      await repo.createFood(
        Food(
          id: 'food-1',
          name: 'Chicken',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      var notified = false;
      state.addListener(() => notified = true);

      await state.loadFoods();

      expect(notified, isTrue);
    });

    // ─── isInLibrary (Manage Food Library – add/remove toggle) ───────────
    //
    // `isInLibrary(catalogId)` answers "is a library row present whose
    // identity matches this catalog food?" Identity is name + reference
    // + macros (catalog copies get a fresh id on add, so we cannot
    // match by id). The method must:
    //   - return false for an unknown catalog id
    //   - return false when no library row matches
    //   - return true after `addCatalogFoodToLibrary`
    //   - return false after `removeFood` on that same row
    //   - ignore archived library rows
    //   - tolerate case differences in `name` (matches the user
    //     perception: "I already added this Chicken Breast")
    group('isInLibrary', () {
      const catalogSource = Food(
        id: 'test-catalog-chicken',
        name: 'Chicken Breast',
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

      test('returns false for an unknown catalog id', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        // Catalog cache is cold → unknown-id path is the active branch.
        expect(state.isInLibrary('does-not-exist'), isFalse);
      });

      test('returns false when no library row matches', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await repo.seedCatalogFood(catalogSource);
        await state.loadCatalogFoods();
        // Library is empty, catalog has the source — still not in library.
        expect(state.isInLibrary('test-catalog-chicken'), isFalse);
      });

      test('returns true after addCatalogFoodToLibrary', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await repo.seedCatalogFood(catalogSource);
        // `isInLibrary` reads from the catalog cache. The production
        // path always calls `loadCatalogFoods()` before rendering the
        // catalog tab; we mirror that here.
        await state.loadCatalogFoods();
        await state.addCatalogFoodToLibrary('test-catalog-chicken');
        expect(state.isInLibrary('test-catalog-chicken'), isTrue);
      });

      test(
        'returns false after removeFood on the matching library row',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();
          final libId = await state.addCatalogFoodToLibrary(
            'test-catalog-chicken',
          );
          expect(state.isInLibrary('test-catalog-chicken'), isTrue);
          await state.removeFood(libId);
          expect(state.isInLibrary('test-catalog-chicken'), isFalse);
        },
      );

      test('ignores archived library rows when matching identity', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await repo.seedCatalogFood(catalogSource);
        await state.loadCatalogFoods();
        // Add a library row, then archive it.
        final libId = await state.addCatalogFoodToLibrary(
          'test-catalog-chicken',
        );
        await state.archiveFood(libId);
        // Archive should hide it from the in-library scan.
        expect(
          state.isInLibrary('test-catalog-chicken'),
          isFalse,
          reason:
              'archived library rows must not count as "in library" '
              'for the toggle UI',
        );
      });

      test(
        'matches by name + reference + macros, case-insensitive on name',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          // Catalog source uses 'Chicken Breast'; library row uses
          // 'chicken breast' (different case). Identity must still match.
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();
          await state.createFood(
            const Food(
              id: 'lib-chicken-1',
              name: 'chicken breast',
              unitType: FoodUnitType.grams,
              referenceAmount: 100.0,
              referenceLabel: 'g',
              isCatalog: false,
              protein: 31,
              carbs: 0,
              fat: 3,
              createdAtMs: 200,
              updatedAtMs: 200,
            ),
          );
          await state.loadFoods();
          expect(
            state.isInLibrary('test-catalog-chicken'),
            isTrue,
            reason: 'name match must be case-insensitive',
          );
        },
      );

      test('does not match a library row with different macros', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await repo.seedCatalogFood(catalogSource);
        await state.loadCatalogFoods();
        // Library row has the same name + reference but different
        // protein. Identity must NOT match.
        await state.createFood(
          const Food(
            id: 'lib-chicken-different',
            name: 'Chicken Breast',
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            isCatalog: false,
            protein: 50, // different
            carbs: 0,
            fat: 3,
            createdAtMs: 200,
            updatedAtMs: 200,
          ),
        );
        await state.loadFoods();
        expect(
          state.isInLibrary('test-catalog-chicken'),
          isFalse,
          reason: 'macro mismatch must disqualify the identity match',
        );
      });
    });

    // ─── libraryIdFor (companion of isInLibrary) ───────────────────────
    //
    // `libraryIdFor(catalogId)` is the underlying lookup that
    // `isInLibrary` delegates to; it returns the matching library
    // row's id (or `null`) so the Manage Food Library toggle can
    // call `removeFood` / `unlogFoodToday` against the right row
    // without re-deriving the identity rule in the UI.
    group('libraryIdFor', () {
      const catalogSource = Food(
        id: 'test-catalog-chicken-id',
        name: 'Chicken Breast',
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

      test('returns null for an unknown catalog id', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        expect(state.libraryIdFor('does-not-exist'), isNull);
      });

      test(
        'returns the matching library row id after addCatalogFoodToLibrary',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();
          final libId = await state.addCatalogFoodToLibrary(
            'test-catalog-chicken-id',
          );
          expect(
            state.libraryIdFor('test-catalog-chicken-id'),
            libId,
            reason:
                'libraryIdFor should return the same id that '
                'addCatalogFoodToLibrary produced (not the catalog id)',
          );
        },
      );

      test('returns null after removeFood on the matching row', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await repo.seedCatalogFood(catalogSource);
        await state.loadCatalogFoods();
        final libId = await state.addCatalogFoodToLibrary(
          'test-catalog-chicken-id',
        );
        expect(state.libraryIdFor('test-catalog-chicken-id'), libId);
        await state.removeFood(libId);
        expect(state.libraryIdFor('test-catalog-chicken-id'), isNull);
      });
    });

    // ─── Catalog Edit Propagation (D-3) ─────────────────────────────────
    //
    // When a user edits a catalog food, the linked library food should
    // automatically reflect the updated values (calories, name, image,
    // etc.). This is the core durable-identity behavior: edits to the
    // catalog source propagate to the user's "Foods I Eat" entry.
    group('catalog edit propagation', () {
      const catalogSource = Food(
        id: 'catalog-edit-test-id',
        name: 'Test Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 20,
        carbs: 30,
        fat: 5,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      test(
        'editing catalog food propagates to library food with catalogId',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();

          // Add to library - this creates a library food with catalogId set
          final libId = await state.addCatalogFoodToLibrary(
            'catalog-edit-test-id',
          );
          final originalLibFood = state.foods.firstWhere((f) => f.id == libId);
          expect(originalLibFood.catalogId, 'catalog-edit-test-id');

          // Edit the catalog food
          final draft = FoodDraft(
            name: 'Renamed Food',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            protein: 25,
            carbs: 35,
            fiber: null,
            fat: 8,
            sodium: null,
            notes: null,
            imagePath: null,
          );
          await state.updateCatalogFood(catalogSource, draft);

          // Verify library food was updated with new values
          final updatedLibFood = state.foods.firstWhere((f) => f.id == libId);
          expect(updatedLibFood.name, 'Renamed Food');
          expect(updatedLibFood.protein, 25);
          expect(updatedLibFood.carbs, 35);
          expect(updatedLibFood.fat, 8);
          // catalogId should still be set (durable linkage preserved)
          expect(updatedLibFood.catalogId, 'catalog-edit-test-id');
        },
      );

      test(
        'editing catalog food propagates to legacy library food via identity match',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();

          // Simulate legacy data: create a library food WITHOUT catalogId
          // but with values matching the catalog
          final legacyFood = Food(
            id: 'legacy-lib-id',
            name: 'Test Food',
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            isCatalog: false,
            // No catalogId - simulating legacy data
            protein: 20,
            carbs: 30,
            fat: 5,
            createdAtMs: 100,
            updatedAtMs: 100,
          );
          await repo.createFood(legacyFood);
          await state.loadFoods();

          // Edit the catalog food
          final draft = FoodDraft(
            name: 'Updated Food Name',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            protein: 22,
            carbs: 33,
            fiber: null,
            fat: 6,
            sodium: null,
            notes: null,
            imagePath: null,
          );
          await state.updateCatalogFood(catalogSource, draft);

          // Verify legacy library food was updated with new values
          final updatedLegacyFood = state.foods.firstWhere(
            (f) => f.id == 'legacy-lib-id',
          );
          expect(updatedLegacyFood.name, 'Updated Food Name');
          expect(updatedLegacyFood.protein, 22);
          expect(updatedLegacyFood.carbs, 33);
          expect(updatedLegacyFood.fat, 6);
          // catalogId should now be set (upgraded from legacy)
          expect(updatedLegacyFood.catalogId, 'catalog-edit-test-id');
        },
      );

      test(
        'addCatalogFoodToLibrary does not create duplicate for already-linked food',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();

          // Add to library first time
          final libId1 = await state.addCatalogFoodToLibrary(
            'catalog-edit-test-id',
          );
          expect(state.foods.length, 1);

          // Try to add again - should not create duplicate
          final libId2 = await state.addCatalogFoodToLibrary(
            'catalog-edit-test-id',
          );
          expect(libId2, libId1);
          expect(state.foods.length, 1);
        },
      );

      test(
        'addCatalogFoodToLibrary upgrades legacy library food with catalogId',
        () async {
          final repo = await _freshRepo();
          final state = FoodLibraryState(repo);
          await repo.seedCatalogFood(catalogSource);
          await state.loadCatalogFoods();

          // Create legacy library food without catalogId
          final legacyFood = Food(
            id: 'legacy-food-1',
            name: 'Test Food',
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            isCatalog: false,
            protein: 20,
            carbs: 30,
            fat: 5,
            createdAtMs: 100,
            updatedAtMs: 100,
          );
          await repo.createFood(legacyFood);
          await state.loadFoods();

          // Add catalog to library - should upgrade legacy food
          final libId = await state.addCatalogFoodToLibrary(
            'catalog-edit-test-id',
          );
          expect(libId, 'legacy-food-1');

          // Verify the legacy food now has catalogId
          final upgradedFood = state.foods.firstWhere(
            (f) => f.id == 'legacy-food-1',
          );
          expect(upgradedFood.catalogId, 'catalog-edit-test-id');
          // Should not create new food
          expect(state.foods.length, 1);
        },
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Food Helper Functions
  // ══════════════════════════════════════════════════════════════════════════

  group('Food Helper Functions', () {
    test('calculateCalories computes correct total', () {
      final food = Food(
        id: 'food-1',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final calories = calculateCalories(food);

      // 31 * 4 + 0 * 4 + 3 * 9 = 124 + 0 + 27 = 151
      expect(calories, 151);
    });

    test('calculateCalories with macronutrients', () {
      final food = Food(
        id: 'food-1',
        name: 'Mixed Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 20,
        carbs: 50,
        fat: 10,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final calories = calculateCalories(food);

      // 20 * 4 + 50 * 4 + 10 * 9 = 80 + 200 + 90 = 370
      expect(calories, 370);
    });

    test('calculateNetCarbs with no fiber', () {
      final food = Food(
        id: 'food-1',
        name: 'Rice',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 3,
        carbs: 28,
        fat: 0,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final netCarbs = calculateNetCarbs(food);

      // 28 - 0 = 28
      expect(netCarbs, 28);
    });

    test('calculateNetCarbs with fiber', () {
      final food = Food(
        id: 'food-1',
        name: 'Broccoli',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 3,
        carbs: 7,
        fiber: 2,
        fat: 0,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final netCarbs = calculateNetCarbs(food);

      // 7 - 2 = 5
      expect(netCarbs, 5);
    });

    test('calculateNetCarbs with null fiber defaults to 0', () {
      final food = Food(
        id: 'food-1',
        name: 'Rice',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 3,
        carbs: 28,
        fiber: null,
        fat: 0,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final netCarbs = calculateNetCarbs(food);

      // 28 - 0 = 28
      expect(netCarbs, 28);
    });

    test('Food.calories getter matches calculateCalories', () {
      final food = Food(
        id: 'food-1',
        name: 'Chicken',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      expect(food.calories, calculateCalories(food));
    });

    test('Food.netCarbs getter matches calculateNetCarbs', () {
      final food = Food(
        id: 'food-1',
        name: 'Broccoli',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 3,
        carbs: 7,
        fiber: 2,
        fat: 0,
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      expect(food.netCarbs, calculateNetCarbs(food));
    });
  });
}
