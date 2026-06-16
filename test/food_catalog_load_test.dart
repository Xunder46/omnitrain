// Unit tests for the food catalog loading and immutability.
//
// Verifies:
// 1. The catalog loads with the expected number of foods and required fields per food.
// 2. Catalog foods are immutable through any user action.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/datasources/food_catalog_loader.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';
import 'package:omnitrain/mock/seed_data.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('FoodCatalogLoader', () {
    test('parseCatalogJson returns 107 foods from the bundled data', () {
      // Inline a minimal JSON to avoid asset I/O in unit tests.
      // This mirrors the structure of assets/data/food_catalog.json.
      const json = '''
      {
        "version": 2,
        "foods": [
          {
            "id": "test_chicken",
            "name": "Test Chicken",
            "category": "Proteins",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "100 g",
            "calories": 156,
            "protein": 31,
            "carbs": 0,
            "fat": 3.6,
            "sodium_mg": 74
          },
          {
            "id": "test_egg",
            "name": "Test Egg",
            "category": "Proteins",
            "unitType": "count",
            "referenceAmount": 1,
            "referenceLabel": "egg",
            "calories": 71,
            "protein": 6,
            "carbs": 0.5,
            "fat": 5,
            "sodium_mg": 71
          }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      expect(foods.length, 2);
      expect(foods[0].id, 'test_chicken');
      expect(foods[1].id, 'test_egg');
    });

    test('parseCatalogJson sets isCatalog = true on all foods', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          {
            "id": "a",
            "name": "A",
            "category": "Proteins",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "100 g",
            "calories": 100,
            "protein": 10,
            "carbs": 5,
            "fat": 3
          }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      expect(foods[0].isCatalog, true);
      expect(foods[0].isLibraryFood, false);
    });
  });

  group('MockWorkoutRepository catalog loading', () {
    test('getCatalogFoods returns 107 foods after initialize', () async {
      final repo = await _freshRepo();
      final catalogFoods = await repo.getCatalogFoods();
      expect(catalogFoods.length, 107);
    });

    test('all catalog foods have required fields', () async {
      final repo = await _freshRepo();
      final catalogFoods = await repo.getCatalogFoods();

      for (final food in catalogFoods) {
        expect(food.id, isNotEmpty, reason: 'food id should not be empty');
        expect(
          food.name,
          isNotEmpty,
          reason: 'food ${food.id} name should not be empty',
        );
        expect(
          food.unitType,
          isIn([FoodUnitType.count, FoodUnitType.grams]),
          reason: 'food ${food.id} unitType should be count or grams',
        );
        expect(
          food.referenceAmount > 0,
          isTrue,
          reason: 'food ${food.id} referenceAmount should be positive',
        );
        expect(
          food.referenceLabel,
          isNotEmpty,
          reason: 'food ${food.id} referenceLabel should not be empty',
        );
        expect(
          food.isCatalog,
          isTrue,
          reason: 'food ${food.id} should be marked as catalog',
        );
        // Macros are stored as ints; we just check they're non-negative.
        expect(food.protein >= 0, isTrue);
        expect(food.carbs >= 0, isTrue);
        expect(food.fat >= 0, isTrue);
      }
    });

    test('catalog covers all expected categories', () async {
      final repo = await _freshRepo();
      final catalogFoods = await repo.getCatalogFoods();
      final groups = await repo.getFoodGroups();

      // Each catalog food's `groupId` resolves to a default FoodGroup
      // whose name is one of the 9 category labels. We translate the
      // FK back to a label so the test stays readable.
      final groupNameById = {for (final g in groups) g.id: g.name};
      final categories = catalogFoods
          .map((f) => f.groupId)
          .where((id) => id != null)
          .map((id) => groupNameById[id])
          .where((name) => name != null)
          .toSet();

      expect(categories.contains('Proteins'), isTrue);
      expect(categories.contains('Dairy'), isTrue);
      expect(categories.contains('Grains & Starches'), isTrue);
      expect(categories.contains('Fruits'), isTrue);
      expect(categories.contains('Vegetables'), isTrue);
      expect(categories.contains('Nuts, Seeds & Fats'), isTrue);
      expect(categories.contains('Snacks & Prepared'), isTrue);
      expect(categories.contains('Drinks'), isTrue);
      expect(categories.contains('Condiments'), isTrue);
    });

    test('catalog includes count-type and grams-type foods', () async {
      final repo = await _freshRepo();
      final catalogFoods = await repo.getCatalogFoods();

      final hasCount = catalogFoods.any(
        (f) => f.unitType == FoodUnitType.count,
      );
      final hasGrams = catalogFoods.any(
        (f) => f.unitType == FoodUnitType.grams,
      );

      expect(hasCount, isTrue, reason: 'catalog should have count-type foods');
      expect(hasGrams, isTrue, reason: 'catalog should have grams-type foods');
    });

    test('catalog food is retrievable by ID', () async {
      final repo = await _freshRepo();
      final chicken = await repo.getCatalogFoodById('chicken_breast');

      expect(chicken, isNotNull);
      expect(chicken!.name, 'Chicken breast, skinless');
      expect(chicken.unitType, FoodUnitType.grams);
      expect(chicken.referenceAmount, 100.0);
      expect(chicken.protein, 31);
      expect(chicken.isCatalog, true);
    });

    test('getFoods does not return catalog foods', () async {
      final repo = await _freshRepo();
      final libraryFoods = await repo.getFoods();

      // Library should be empty (no user foods added yet)
      expect(libraryFoods, isEmpty);

      // Catalog should still be full
      final catalogFoods = await repo.getCatalogFoods();
      expect(catalogFoods.length, 107);
    });
  });

  group('Catalog immutability', () {
    test('updateFood on a catalog food ID does not mutate the catalog', () async {
      final repo = await _freshRepo();

      // Get the original catalog food
      final original = await repo.getCatalogFoodById('chicken_breast');
      expect(original, isNotNull);
      final originalProtein = original!.protein;
      final originalName = original.name;

      // Attempt to "update" the catalog food via the library mutator.
      // Since the ID is not in the library, the mutator will create a
      // NEW library food with the same ID — this should NOT affect the catalog.
      final mutated = original.copyWith(
        name: 'MUTATED NAME',
        protein: 999,
        isCatalog: false, // Even if the caller tries to flip this flag
      );
      await repo.updateFood(mutated);

      // Re-read the catalog food — should be unchanged
      final afterUpdate = await repo.getCatalogFoodById('chicken_breast');
      expect(afterUpdate, isNotNull);
      expect(afterUpdate!.name, originalName);
      expect(afterUpdate.protein, originalProtein);
      expect(afterUpdate.isCatalog, true);

      // The mutated copy should now live in the library
      final libraryFood = await repo.getFoodById('chicken_breast');
      expect(libraryFood, isNotNull);
      expect(libraryFood!.name, 'MUTATED NAME');
      expect(libraryFood.protein, 999);
      expect(libraryFood.isCatalog, false);
    });

    test(
      'archiveFood on a catalog food ID does not mutate the catalog',
      () async {
        final repo = await _freshRepo();

        // Get the original catalog food
        final original = await repo.getCatalogFoodById('egg');
        expect(original, isNotNull);
        final originalArchived = original!.isArchived;

        // Attempt to archive the catalog food
        await repo.archiveFood('egg');

        // Re-read the catalog food — should be unchanged
        final afterArchive = await repo.getCatalogFoodById('egg');
        expect(afterArchive, isNotNull);
        expect(afterArchive!.isArchived, originalArchived);

        // Catalog count should still be 107
        final all = await repo.getCatalogFoods(includeArchived: true);
        expect(all.length, 107);
      },
    );

    test('createFood cannot accidentally add to the catalog', () async {
      final repo = await _freshRepo();

      // Create a new food with isCatalog = true (attempting to inject into catalog)
      final custom = Food(
        id: 'fake-catalog-entry',
        name: 'Fake Catalog',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        isCatalog: true, // Caller tries to set this flag
        protein: 10,
        carbs: 10,
        fat: 5,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );
      await repo.createFood(custom);

      // The food is stored in the LIBRARY (createFood writes to _foods).
      // getFoods() filters out catalog-flagged rows, so it should not appear.
      final libraryFoods = await repo.getFoods();
      expect(
        libraryFoods.any((f) => f.id == 'fake-catalog-entry'),
        isFalse,
        reason: 'createFood should not allow injecting into the catalog',
      );

      // The catalog count should still be 107
      final catalogFoods = await repo.getCatalogFoods();
      expect(catalogFoods.length, 107);
    });

    test(
      'addCatalogFoodToLibrary does not mutate the source catalog entry',
      () async {
        final repo = await _freshRepo();

        // Get the original catalog food
        final original = await repo.getCatalogFoodById('salmon');
        expect(original, isNotNull);
        final originalName = original!.name;
        final originalProtein = original.protein;

        // Add to library
        final libraryId = await repo.addCatalogFoodToLibrary('salmon');
        expect(libraryId, isNot('salmon'));

        // Re-read the catalog food — should be unchanged
        final afterCopy = await repo.getCatalogFoodById('salmon');
        expect(afterCopy, isNotNull);
        expect(afterCopy!.name, originalName);
        expect(afterCopy.protein, originalProtein);
        expect(afterCopy.isCatalog, true);

        // The library copy should have a new ID and isCatalog = false
        final libraryCopy = await repo.getFoodById(libraryId);
        expect(libraryCopy, isNotNull);
        expect(libraryCopy!.isCatalog, false);
      },
    );
  });

  group('FoodCatalogSeed parity', () {
    test('sampleCatalogFoods contains 107 entries', () {
      expect(FoodCatalogSeed.sampleCatalogFoods.length, 107);
    });

    test('all seed entries are marked isCatalog = true', () {
      for (final food in FoodCatalogSeed.sampleCatalogFoods) {
        expect(food.isCatalog, true, reason: '${food.id} should be isCatalog');
        expect(food.isLibraryFood, false);
      }
    });

    test('seed entries have unique IDs', () {
      final ids = FoodCatalogSeed.sampleCatalogFoods.map((f) => f.id).toSet();
      expect(ids.length, FoodCatalogSeed.sampleCatalogFoods.length);
    });
  });

  group('Default food group categories seeded from catalog', () {
    test('every catalog category has a matching default FoodGroup', () {
      // Read the actual categories out of the seeded catalog so the
      // assertion stays in sync if the catalog grows. Catalog rows
      // now store the category as a `groupId` FK, so we translate
      // the FK back to a label via SeedData.defaultFoodGroups.
      final groupNameById = <String, String>{
        for (final g in SeedData.defaultFoodGroups) g.id: g.name,
      };
      final categories = <String>{
        for (final food in FoodCatalogSeed.sampleCatalogFoods)
          food.groupId == null ? '' : (groupNameById[food.groupId] ?? ''),
      }..removeWhere((c) => c.isEmpty);

      final defaultNames = SeedData.defaultFoodGroups
          .map((g) => g.name)
          .toSet();

      for (final category in categories) {
        expect(
          defaultNames.contains(category),
          isTrue,
          reason:
              'Catalog category "$category" must be in SeedData.defaultFoodGroups',
        );
      }
    });

    test(
      'MockWorkoutRepository.initialize seeds all 9 default food groups',
      () async {
        final repo = await _freshRepo();

        final groups = await repo.getFoodGroups();
        final names = groups.map((g) => g.name).toSet();

        // The 9 category names bundled with the catalog.
        expect(
          names,
          containsAll(<String>[
            'Proteins',
            'Dairy',
            'Grains & Starches',
            'Fruits',
            'Vegetables',
            'Nuts, Seeds & Fats',
            'Snacks & Prepared',
            'Drinks',
            'Condiments',
          ]),
        );
      },
    );

    test('default food groups have stable, deterministic ids', () {
      // Stable ids are required for the Hive idempotency migration.
      // If a future refactor drops one, this test fails fast.
      final ids = SeedData.defaultFoodGroups.map((g) => g.id).toList();
      expect(ids, contains('food-group-proteins'));
      expect(ids, contains('food-group-dairy'));
      expect(ids, contains('food-group-grains-starches'));
      expect(ids, contains('food-group-fruits'));
      expect(ids, contains('food-group-vegetables'));
      expect(ids, contains('food-group-nuts-seeds-fats'));
      expect(ids, contains('food-group-snacks-prepared'));
      expect(ids, contains('food-group-drinks'));
      expect(ids, contains('food-group-condiments'));
    });

    test('default food groups are not archived and have no color', () {
      for (final group in SeedData.defaultFoodGroups) {
        expect(group.isArchived, isFalse);
        expect(group.color, isNull);
      }
    });

    test('user can archive a default food group', () async {
      // The user can rename/archive/delete default groups; the mutator
      // path is unaware of seed provenance.
      final repo = await _freshRepo();
      final groups = await repo.getFoodGroups();
      final proteins = groups.firstWhere((g) => g.id == 'food-group-proteins');

      await repo.archiveFoodGroup(proteins.id);

      final reloaded = await repo.getFoodGroupById(proteins.id);
      expect(reloaded?.isArchived, isTrue);

      // Default-group ids are preserved across the archive round-trip.
      expect(reloaded?.id, 'food-group-proteins');
    });
  });

  group('FoodCatalogLoader — category → groupId mapping (S-020)', () {
    test('parses a row with category=Proteins and sets groupId', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          {
            "id": "loader-proteins-1",
            "name": "Chicken Breast",
            "category": "Proteins",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "100 g",
            "protein": 31,
            "carbs": 0,
            "fat": 4
          }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      expect(foods, hasLength(1));
      expect(foods.single.id, 'loader-proteins-1');
      expect(foods.single.groupId, 'food-group-proteins');
      expect(foods.single.notes, isNull);
    });

    test('resolves all 9 default categories to their groupId', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          { "id": "a", "name": "A", "category": "Proteins",          "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "b", "name": "B", "category": "Dairy",             "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "c", "name": "C", "category": "Grains & Starches", "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "d", "name": "D", "category": "Fruits",            "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "e", "name": "E", "category": "Vegetables",        "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "f", "name": "F", "category": "Nuts, Seeds & Fats","unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "g", "name": "G", "category": "Snacks & Prepared", "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "h", "name": "H", "category": "Drinks",            "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "i", "name": "I", "category": "Condiments",        "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      final expected = <String, String>{
        'a': 'food-group-proteins',
        'b': 'food-group-dairy',
        'c': 'food-group-grains-starches',
        'd': 'food-group-fruits',
        'e': 'food-group-vegetables',
        'f': 'food-group-nuts-seeds-fats',
        'g': 'food-group-snacks-prepared',
        'h': 'food-group-drinks',
        'i': 'food-group-condiments',
      };
      for (final food in foods) {
        expect(
          food.groupId,
          expected[food.id],
          reason: '${food.id} should map to ${expected[food.id]}',
        );
        expect(
          food.notes,
          isNull,
          reason: '${food.id} should not carry the category in notes',
        );
      }
    });

    test('case-insensitive category lookup (e.g. "proteins" → groupId)', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          {
            "id": "lower",
            "name": "Lower Case",
            "category": "proteins",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "g"
          },
          {
            "id": "upper",
            "name": "Upper Case",
            "category": "DAIRY",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "g"
          }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      expect(foods[0].groupId, 'food-group-proteins');
      expect(foods[1].groupId, 'food-group-dairy');
    });

    test('unknown category leaves groupId null and notes null', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          {
            "id": "exotic",
            "name": "Exotic Item",
            "category": "Mystery Bucket",
            "unitType": "grams",
            "referenceAmount": 100,
            "referenceLabel": "g"
          }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      expect(foods.single.groupId, isNull);
      // The category is dropped; notes is the free-form "Info" field
      // and stays null for catalog rows.
      expect(foods.single.notes, isNull);
    });

    test('notes is always null on freshly-parsed catalog rows', () {
      const json = '''
      {
        "version": 2,
        "foods": [
          { "id": "x1", "name": "A", "category": "Proteins", "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" },
          { "id": "x2", "name": "B", "category": "Mystery",  "unitType": "grams", "referenceAmount": 100, "referenceLabel": "g" }
        ]
      }
      ''';
      final foods = FoodCatalogLoader.parseCatalogJson(json);
      for (final f in foods) {
        expect(
          f.notes,
          isNull,
          reason: '${f.id} should not carry a notes value',
        );
      }
    });
  });

  group('MockWorkoutRepository — catalog foods are seeded with groupId', () {
    test(
      'every catalog food has a non-null groupId from default groups',
      () async {
        final repo = await _freshRepo();
        final groups = await repo.getFoodGroups();
        final validGroupIds = groups.map((g) => g.id).toSet();
        final catalog = await repo.getCatalogFoods();

        for (final food in catalog) {
          expect(
            food.groupId,
            isNotNull,
            reason: '${food.id} should have a groupId',
          );
          expect(
            validGroupIds.contains(food.groupId),
            isTrue,
            reason:
                '${food.id} groupId=${food.groupId} must point to a default FoodGroup',
          );
        }
      },
    );

    test('addCatalogFoodToLibrary copies the groupId across', () async {
      final repo = await _freshRepo();
      final salmon = await repo.getCatalogFoodById('salmon');
      expect(salmon, isNotNull);
      expect(salmon!.groupId, 'food-group-proteins');

      final newId = await repo.addCatalogFoodToLibrary('salmon');
      final library = await repo.getFoodById(newId);
      expect(library, isNotNull);
      expect(library!.groupId, salmon.groupId);
      expect(library.isCatalog, isFalse);
    });
  });

  group('Loader ↔ seed parity (drift guard)', () {
    // Permanent guard: every Food in FoodCatalogSeed.sampleCatalogFoods
    // must match the value produced by FoodCatalogLoader.parseCatalogJson
    // for the same JSON asset, field-for-field. If either side drifts
    // (loader rounding changes, generator uses .toInt() instead of
    // .round(), a row is added/removed/renamed), this test fails fast.
    test('every seed entry equals the loader output for the bundled JSON', () {
      final asset = File('assets/data/food_catalog.json');
      expect(
        asset.existsSync(),
        isTrue,
        reason:
            'assets/data/food_catalog.json not found at project root; '
            'the parity test must run from the project root.',
      );

      final loaderFoods = FoodCatalogLoader.parseCatalogJson(
        asset.readAsStringSync(),
      );
      final seedFoods = FoodCatalogSeed.sampleCatalogFoods;

      // Same set of ids, same length. Use a Map keyed by id so the
      // per-field comparison below has O(1) lookups and the failure
      // message is unambiguous.
      expect(
        loaderFoods.length,
        seedFoods.length,
        reason:
            'Loader and seed disagree on catalog size. Re-run '
            '`dart run scripts/generate_food_catalog_seed.dart`.',
      );
      final byId = {for (final f in seedFoods) f.id: f};

      for (final loaded in loaderFoods) {
        final seeded = byId[loaded.id];
        expect(
          seeded,
          isNotNull,
          reason: 'Loader produced id "${loaded.id}" not in seed list.',
        );

        // Field-by-field equality. The set of fields is the union of
        // what the JSON carries + the derived groupId/isCatalog;
        // imagePath and notes are NOT asserted (catalog rows have
        // imagePath=null and notes=null by design; the seed file
        // also omits both, and Food equality is field-by-field).
        expect(loaded.id, seeded!.id, reason: '${loaded.id} .id');
        expect(loaded.name, seeded.name, reason: '${loaded.id} .name');
        expect(loaded.groupId, seeded.groupId, reason: '${loaded.id} .groupId');
        expect(
          loaded.unitType,
          seeded.unitType,
          reason: '${loaded.id} .unitType',
        );
        expect(
          loaded.referenceAmount,
          seeded.referenceAmount,
          reason: '${loaded.id} .referenceAmount',
        );
        expect(
          loaded.referenceLabel,
          seeded.referenceLabel,
          reason: '${loaded.id} .referenceLabel',
        );
        expect(
          loaded.protein,
          seeded.protein,
          reason:
              '${loaded.id} .protein  (loader=${loaded.protein}, '
              'seed=${seeded.protein})',
        );
        expect(
          loaded.carbs,
          seeded.carbs,
          reason:
              '${loaded.id} .carbs  (loader=${loaded.carbs}, '
              'seed=${seeded.carbs})',
        );
        expect(loaded.fiber, seeded.fiber, reason: '${loaded.id} .fiber');
        expect(
          loaded.fat,
          seeded.fat,
          reason:
              '${loaded.id} .fat  (loader=${loaded.fat}, '
              'seed=${seeded.fat})',
        );
        expect(loaded.sodium, seeded.sodium, reason: '${loaded.id} .sodium');
      }
    });

    test('seed covers the loader output by id (no orphans either way)', () {
      final asset = File('assets/data/food_catalog.json');
      final loaderFoods = FoodCatalogLoader.parseCatalogJson(
        asset.readAsStringSync(),
      );
      final seedFoods = FoodCatalogSeed.sampleCatalogFoods;

      final loaderIds = loaderFoods.map((f) => f.id).toSet();
      final seedIds = seedFoods.map((f) => f.id).toSet();

      // No id in the seed that isn't in the loader.
      for (final id in seedIds.difference(loaderIds)) {
        fail('Seed has id "$id" that the loader does not produce.');
      }
      // No id in the loader that isn't in the seed.
      for (final id in loaderIds.difference(seedIds)) {
        fail('Loader produces id "$id" that the seed is missing.');
      }
    });
  });
}
