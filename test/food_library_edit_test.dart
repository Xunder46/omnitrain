// filepath: test/food_library_edit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Food _libraryFood({
  String id = 'food-edit-1',
  String name = 'Edit Me',
  String? groupId,
  int protein = 10,
  int carbs = 20,
  int? fiber = 0,
  int fat = 5,
  String? imagePath,
  FoodUnitType unitType = FoodUnitType.grams,
  double referenceAmount = 100,
  String referenceLabel = 'g',
}) {
  return Food(
    id: id,
    name: name,
    groupId: groupId,
    unitType: unitType,
    referenceAmount: referenceAmount,
    referenceLabel: referenceLabel,
    isCatalog: false,
    protein: protein,
    carbs: carbs,
    fiber: fiber,
    fat: fat,
    imagePath: imagePath,
    createdAtMs: 1700000000000,
    updatedAtMs: 1700000000000,
  );
}

void main() {
  group('FoodLibraryState updateCustomFood', () {
    test(
      'updates the cached food and notifies listeners (S-001)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.createFood(_libraryFood(id: 'food-edit-1', protein: 31));
        await state.loadFoods();

        var notifications = 0;
        state.addListener(() => notifications++);

        await state.updateCustomFood(
          id: 'food-edit-1',
          name: 'Edit Me',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 35, // <-- changed
          carbs: 0,
          fiber: 0,
          fat: 4,
          imagePath: null,
        );

        // Cache reflects the new protein.
        final updated = state.foods.firstWhere((f) => f.id == 'food-edit-1');
        expect(updated.protein, 35);
        expect(updated.fat, 4);
        expect(updated.updatedAtMs, greaterThanOrEqualTo(updated.createdAtMs));
        // Listener was notified.
        expect(notifications, greaterThanOrEqualTo(1));
      },
    );

    test(
      'persists the update through the repository (round-trip)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.createFood(_libraryFood(id: 'food-rt-1', name: 'Before'));
        await state.loadFoods();

        await state.updateCustomFood(
          id: 'food-rt-1',
          name: 'After',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 11,
          carbs: 22,
          fiber: 3,
          fat: 4,
          imagePath: '/tmp/x.jpg',
        );

        // Re-read from the repository (cache-miss path).
        final reloaded = await repo.getFoodById('food-rt-1');
        expect(reloaded, isNotNull);
        expect(reloaded!.name, 'After');
        expect(reloaded.protein, 11);
        expect(reloaded.carbs, 22);
        expect(reloaded.fiber, 3);
        expect(reloaded.fat, 4);
        expect(reloaded.imagePath, '/tmp/x.jpg');
      },
    );

    test(
      'editing a catalog-copy in the library leaves the source catalog row untouched (S-002)',
      () async {
        final repo = await _freshRepo();

        // Seed a catalog row directly.
        final catalogFood = _libraryFood(
          id: 'catalog-source-1',
          name: 'Frozen Catalog',
        );
        await repo.seedCatalogFood(catalogFood.copyWith(isCatalog: true));

        // Copy to library.
        final newId = await repo.addCatalogFoodToLibrary('catalog-source-1');
        final state = FoodLibraryState(repo);
        await state.loadFoods();

        // Rename the library copy.
        await state.updateCustomFood(
          id: newId,
          name: 'Renamed Library Copy',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 10,
          carbs: 20,
          fiber: 0,
          fat: 5,
          imagePath: null,
        );

        // Catalog row is unchanged.
        final fromCatalog = await repo.getCatalogFoodById('catalog-source-1');
        expect(fromCatalog, isNotNull);
        expect(fromCatalog!.name, 'Frozen Catalog');
        expect(fromCatalog.isCatalog, isTrue);

        // Library row reflects the rename.
        final libRow = await repo.getFoodById(newId);
        expect(libRow, isNotNull);
        expect(libRow!.name, 'Renamed Library Copy');
        expect(libRow.isCatalog, isFalse);
      },
    );

    test(
      'imagePath null clears the cached image (S-004)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.createFood(
          _libraryFood(id: 'food-img-1', imagePath: '/tmp/a.jpg'),
        );
        await state.loadFoods();

        expect(
          state.foods.firstWhere((f) => f.id == 'food-img-1').imagePath,
          '/tmp/a.jpg',
        );

        await state.updateCustomFood(
          id: 'food-img-1',
          name: 'Edit Me',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 10,
          carbs: 20,
          fiber: 0,
          fat: 5,
          imagePath: null, // <-- cleared
        );

        final cleared = state.foods.firstWhere((f) => f.id == 'food-img-1');
        expect(cleared.imagePath, isNull);
      },
    );

    test(
      'fiber is stored separately from carbs and round-trips (S-005)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.createFood(
          _libraryFood(id: 'food-fiber-1', carbs: 20, fiber: 0),
        );
        await state.loadFoods();

        await state.updateCustomFood(
          id: 'food-fiber-1',
          name: 'Edit Me',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 10,
          carbs: 20,
          fiber: 5, // <-- fiber set separately
          fat: 5,
          imagePath: null,
        );

        final reloaded = await repo.getFoodById('food-fiber-1');
        expect(reloaded!.carbs, 20);
        expect(reloaded.fiber, 5);
        expect(reloaded.netCarbs, 15); // 20 - 5
      },
    );

    test(
      'editing does not modify any ConsumedFood snapshots (image is food-scoped, not snapshot-scoped)',
      () async {
        final repo = await _freshRepo();

        // Seed a library food with an image and a past-day consumed row.
        await repo.createFood(
          _libraryFood(id: 'food-snap-edit', imagePath: '/tmp/old.jpg'),
        );

        const pastDateMs = 1748736000000; // 2025-06-01 UTC
        await repo.createConsumedFood(
          ConsumedFood(
            id: 'consumed-1',
            loggedAtMs: pastDateMs + 3600000,
            dateMs: pastDateMs,
            sourceFoodId: 'food-snap-edit',
            name: 'Edit Me',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 10,
            carbs: 20,
            fat: 5,
            amountConsumed: 100,
            groupNameSnapshot: 'Proteins',
            targetCalories: 2000,
            targetProtein: 100,
            targetCarbs: 200,
            targetFat: 60,
            createdAtMs: 1700000000000,
            updatedAtMs: 1700000000000,
          ),
        );

        final state = FoodLibraryState(repo);
        await state.loadFoods();
        await state.updateCustomFood(
          id: 'food-snap-edit',
          name: 'Edit Me (renamed)',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 11,
          carbs: 21,
          fiber: 6,
          fat: 6,
          imagePath: '/tmp/new.jpg',
        );

        // Past day log is frozen — its name, macros, and image are not in
        // the snapshot model, so they cannot change.
        final dayLog = await repo.getConsumedFoodsForDate(pastDateMs);
        expect(dayLog, hasLength(1));
        expect(dayLog.first.name, 'Edit Me'); // NOT renamed
        expect(dayLog.first.protein, 10); // NOT updated
        expect(dayLog.first.carbs, 20);
        expect(dayLog.first.fat, 5);
      },
    );
  });

  // ── Iteration 3: Global managed library (catalog) ─────────────────

  /// Catalog food used for the catalog-scope tests below. The
  /// `isCatalog: true` flag is what distinguishes these rows from
  /// the user's personal library.
  Food catalogFood({
    String id = 'catalog-edit-1',
    String name = 'Catalog Food',
    int protein = 10,
    int carbs = 20,
    int? fiber = 0,
    int fat = 5,
    String? imagePath,
  }) {
    return Food(
      id: id,
      name: name,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      isCatalog: true,
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      imagePath: imagePath,
      createdAtMs: 1700000000000,
      updatedAtMs: 1700000000000,
    );
  }

  FoodDraft catalogDraft({
    String name = 'Catalog Food',
    int protein = 10,
    int carbs = 20,
    int? fiber = 0,
    int fat = 5,
    String? imagePath,
  }) {
    return FoodDraft(
      name: name,
      groupId: null,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      sodium: null,
      notes: null,
      imagePath: imagePath,
    );
  }

  group('FoodLibraryState updateCatalogFood', () {
    test('updates a bundled catalog food and notifies listeners (S-001)', () async {
      final repo = await _freshRepo();
      // Seed a bundled catalog row directly.
      await repo.seedCatalogFood(
        catalogFood(id: 'catalog-bundled-1', protein: 31),
      );

      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final original = state.catalogFoods.firstWhere(
        (f) => f.id == 'catalog-bundled-1',
      );

      var notifications = 0;
      state.addListener(() => notifications++);

      await state.updateCatalogFood(
        original,
        catalogDraft(name: 'Renamed Bundled', protein: 50),
      );

      // Cache reflects the new value.
      final updated = state.catalogFoods.firstWhere(
        (f) => f.id == 'catalog-bundled-1',
      );
      expect(updated.name, 'Renamed Bundled');
      expect(updated.protein, 50);
      expect(updated.isCatalog, isTrue);
      expect(updated.updatedAtMs, greaterThanOrEqualTo(updated.createdAtMs));
      // Listener was notified.
      expect(notifications, greaterThanOrEqualTo(1));
      // Repository persists the change.
      final fromRepo = await repo.getCatalogFoodById('catalog-bundled-1');
      expect(fromRepo!.protein, 50);
    });

    test('throws on a non-catalog food (library row is not editable here)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.createFood(_libraryFood(id: 'lib-row-1'));
      final libRow = state.foods.first;

      expect(
        () => state.updateCatalogFood(
          libRow,
          catalogDraft(name: 'Should Not Work'),
        ),
        throwsStateError,
      );
    });

    test('throws when the catalog food is not in the cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      final phantom = catalogFood(id: 'phantom-id');

      expect(
        () => state.updateCatalogFood(
          phantom,
          catalogDraft(name: 'Phantom'),
        ),
        throwsException,
      );
    });

    test('syncs user library copies when catalog food is updated', () async {
      final repo = await _freshRepo();
      // Seed a catalog food
      await repo.seedCatalogFood(
        catalogFood(id: 'catalog-sync-1', name: 'Original Name', protein: 10),
      );

      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      await state.loadFoods();

      // Add catalog food to user library
      await state.addCatalogFoodToLibrary('catalog-sync-1');

      // Verify user library has the original values
      final userFoodBefore = state.foods.firstWhere(
        (f) => f.name == 'Original Name' && !f.isCatalog,
      );
      expect(userFoodBefore.protein, 10);

      // Now update the catalog food
      final catalogFoodBefore = state.catalogFoods.firstWhere(
        (f) => f.id == 'catalog-sync-1',
      );
      await state.updateCatalogFood(
        catalogFoodBefore,
        catalogDraft(name: 'Updated Name', protein: 25),
      );

      // Verify user library copy was also updated
      final userFoodAfter = state.foods.firstWhere(
        (f) => f.name == 'Updated Name' && !f.isCatalog,
      );
      expect(userFoodAfter.protein, 25);
      // Verify repository also has the updated value
      final fromRepo = await repo.getFoodById(userFoodAfter.id);
      expect(fromRepo!.protein, 25);
    });
  });

  group('FoodLibraryState createCatalogFood', () {
    test(
      'inserts the food into the catalog (S-002: + New Item writes to catalog)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();

        final baselineCatalogCount = state.catalogFoods.length;

        final newId = await state.createCatalogFood(
          catalogDraft(name: 'My Trail Mix', protein: 10),
        );

        expect(newId, isNotEmpty);

        // Catalog has grown by one.
        expect(
          state.catalogFoods,
          hasLength(baselineCatalogCount + 1),
        );
        // The new food is in the catalog with isCatalog = true.
        final newFood = state.catalogFoods
            .firstWhere((f) => f.id == newId);
        expect(newFood.name, 'My Trail Mix');
        expect(newFood.protein, 10);
        expect(newFood.isCatalog, isTrue);

        // The food does NOT appear in the personal library.
        await state.loadFoods();
        expect(
          state.foods.where((f) => f.name == 'My Trail Mix'),
          isEmpty,
        );

        // The repository also sees the new row.
        final fromRepo = await repo.getCatalogFoodById(newId);
        expect(fromRepo, isNotNull);
        expect(fromRepo!.name, 'My Trail Mix');
      },
    );
  });
}
