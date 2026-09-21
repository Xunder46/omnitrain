// filepath: test/food_library_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Variant of [_freshRepo] that wipes the seeded consumed-foods map
/// after initialization. The `SeedData.sampleConsumedFoods()` seed
/// preloads rows for days 0/1/3/4/5/7/8/10/12/14/.../43 — so any test
/// that creates a `ConsumedFood` for one of those dates and then
/// asserts the count via `getConsumedFoodsForDate(dateMs)` will see
/// the seed row on top of its own row. Use this helper for tests
/// that need a clean day-log.
Future<MockWorkoutRepository> _freshRepoCleanConsumed() async {
  final repo = await _freshRepo();
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Helper to create a library food for testing. Macros are `double`
/// to match the [Food] model (S-001 / S-002 — see
/// `.github/agents/plans/food-form-decimals-and-autofocus-plan.md`).
Food _testFood({
  String id = 'food-test-1',
  String name = 'Test Food',
  double protein = 10,
  double carbs = 20,
  double fat = 5,
}) {
  return Food(
    id: id,
    name: name,
    unitType: FoodUnitType.grams,
    referenceAmount: 100.0,
    referenceLabel: 'g',
    isCatalog: false,
    protein: protein,
    carbs: carbs,
    fat: fat,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

/// Helper to create a ConsumedFood snapshot for testing. Macros
/// are `double` to match the [ConsumedFood] model.
ConsumedFood _testConsumedFood({
  String id = 'consumed-1',
  required String sourceFoodId,
  required int dateMs,
  String name = 'Snapshot Food',
  double protein = 10,
  double carbs = 20,
  double fat = 5,
}) {
  return ConsumedFood(
    id: id,
    loggedAtMs: dateMs + 3600000, // 1 hour into the day
    dateMs: dateMs,
    sourceFoodId: sourceFoodId,
    name: name,
    unitType: FoodUnitType.grams,
    referenceAmount: 100.0,
    referenceLabel: 'g',
    protein: protein,
    carbs: carbs,
    fat: fat,
    amountConsumed: 100.0, // 100 g of a per-100 g food → 1× scaling
    groupIdSnapshot: 'group-1',
    groupNameSnapshot: 'Proteins',
    targetCalories: 2000.0,
    targetProtein: 150.0,
    targetCarbs: 200.0,
    targetFat: 65.0,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
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

    // ... existing tests omitted for brevity, full file would include all CRUD tests ...

    // ─── Food CRUD ────────────────────────────────────────────────────────

    test('createFood creates food and updates cache', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = _testFood(id: 'food-1', name: 'Chicken Breast', protein: 31);
      final id = await state.createFood(food);

      expect(id, isNotEmpty);
      expect(state.foods, hasLength(1));
      expect(state.foods[0].name, 'Chicken Breast');
      expect(state.foods[0].protein, 31);
      expect(state.foods[0].isArchived, isFalse);
    });

    // ... existing tests omitted for brevity ...

    // ─── Archive ───────────────────────────────────────────────────────────

    test('archiveFood marks food as archived', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      final food = _testFood(id: 'food-archive', name: 'Archive Me');
      await state.createFood(food);
      expect(state.foods[0].isArchived, isFalse);

      await state.archiveFood('food-archive');

      expect(state.foods[0].isArchived, isTrue);
    });

    // ─── Library Removal ─────────────────────────────────────────────────

    group('Library removal', () {
      test('removeFood removes food from library', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        final food = _testFood(id: 'food-remove-1', name: 'Remove Me');
        await state.createFood(food);

        expect(state.foods, hasLength(1));

        await state.removeFood('food-remove-1');

        expect(state.foods, isEmpty);
      });

      test('removeFood is a no-op for unknown id', () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        // Should not throw
        await state.removeFood('nonexistent-id');

        // State should still be empty
        expect(state.foods, isEmpty);
      });

      test('removeFood leaves past day-log snapshots intact', () async {
        final repo = await _freshRepoCleanConsumed();

        // Seed a library food
        final food = _testFood(
          id: 'food-snap-1',
          name: 'Snapshot Chicken',
          protein: 30,
          carbs: 0,
          fat: 4,
        );
        await repo.createFood(food);

        // Seed a consumed food (snapshot) that references the library food
        // Use a past date: June 1, 2026 (midnight local time).
        // June 1 is day-14 in the seed (100 g oats), so the
        // clean-consumed fixture is required to isolate this test's row.
        final pastDateMs = DateTime(2026, 6, 1).millisecondsSinceEpoch;

        final consumed = _testConsumedFood(
          id: 'consumed-past-1',
          sourceFoodId: 'food-snap-1',
          dateMs: pastDateMs,
          name: 'Snapshot Chicken',
          protein: 30,
          carbs: 0,
          fat: 4,
        );
        await repo.createConsumedFood(consumed);

        // Build state and load
        final state = FoodLibraryState(repo);
        await state.loadFoods();

        // Verify initial state
        expect(state.foods, hasLength(1));
        expect(state.foods[0].id, 'food-snap-1');

        // Capture the ConsumedFood before removal (serialize to compare)
        final consumedBefore = await repo.getConsumedFoodsForDate(pastDateMs);
        expect(consumedBefore, hasLength(1));

        final beforeJson = jsonEncode(consumedBefore[0].toMap());

        // Remove the library food
        await state.removeFood('food-snap-1');

        // Verify library food is gone
        expect(state.foods, isEmpty);
        expect(await repo.getFoodById('food-snap-1'), isNull);

        // Verify ConsumedFood is unchanged (snapshot preserved)
        final consumedAfter = await repo.getConsumedFoodsForDate(pastDateMs);
        expect(consumedAfter, hasLength(1));

        final afterJson = jsonEncode(consumedAfter[0].toMap());
        expect(afterJson, equals(beforeJson));

        // Verify specific fields are unchanged
        expect(consumedAfter[0].sourceFoodId, equals('food-snap-1'));
        expect(consumedAfter[0].name, equals('Snapshot Chicken'));
        expect(consumedAfter[0].protein, equals(30));
        expect(consumedAfter[0].carbs, equals(0));
        expect(consumedAfter[0].fat, equals(4));
        expect(consumedAfter[0].groupNameSnapshot, equals('Proteins'));
        expect(consumedAfter[0].targetCalories, equals(2000.0));

        // Verify calories consumed is unchanged (frozen calculation)
        // (30*4 + 0*4 + 4*9) * 1.0 = 156
        expect(consumedAfter[0].caloriesConsumed, equals(156));
      });

      test('removeFood does not affect other days\' snapshots', () async {
        final repo = await _freshRepoCleanConsumed();

        // Seed a library food
        final food = _testFood(id: 'food-multi-day', name: 'Multi Day Food');
        await repo.createFood(food);

        // Seed consumed foods for multiple days.
        // June 1 (day-14) and June 3 (day-12) both have seed rows
        // (oats, chicken+rice), so the clean-consumed fixture is
        // required to isolate this test's rows.
        final date1 = DateTime(2026, 6, 1).millisecondsSinceEpoch;
        final date2 = DateTime(2026, 6, 2).millisecondsSinceEpoch;
        final date3 = DateTime(2026, 6, 3).millisecondsSinceEpoch;

        await repo.createConsumedFood(
          _testConsumedFood(
            id: 'consumed-1',
            sourceFoodId: 'food-multi-day',
            dateMs: date1,
          ),
        );
        await repo.createConsumedFood(
          _testConsumedFood(
            id: 'consumed-2',
            sourceFoodId: 'food-multi-day',
            dateMs: date2,
          ),
        );
        await repo.createConsumedFood(
          _testConsumedFood(
            id: 'consumed-3',
            sourceFoodId: 'food-multi-day',
            dateMs: date3,
          ),
        );

        // Build state and remove
        final state = FoodLibraryState(repo);
        await state.loadFoods();
        await state.removeFood('food-multi-day');

        // Verify all three days' snapshots are intact
        final day1 = await repo.getConsumedFoodsForDate(date1);
        final day2 = await repo.getConsumedFoodsForDate(date2);
        final day3 = await repo.getConsumedFoodsForDate(date3);

        expect(day1, hasLength(1));
        expect(day2, hasLength(1));
        expect(day3, hasLength(1));

        // Verify sourceFoodId is still the original (dangling reference)
        expect(day1[0].sourceFoodId, equals('food-multi-day'));
        expect(day2[0].sourceFoodId, equals('food-multi-day'));
        expect(day3[0].sourceFoodId, equals('food-multi-day'));
      });

      test(
        'removeFood does not affect catalog foods (no-op for isCatalog=true)',
        () async {
          final repo = await _freshRepo();

          // Seed a true catalog food directly into the catalog box
          // (bypasses the library write path so isCatalog stays true).
          final catalogFood = _testFood(
            id: 'catalog-frozen-1',
            name: 'Frozen Catalog Item',
            protein: 10,
            carbs: 20,
            fat: 5,
          );
          await repo.seedCatalogFood(catalogFood);

          // Confirm it is in the catalog and NOT in the library
          final fromCatalog = await repo.getCatalogFoodById('catalog-frozen-1');
          expect(fromCatalog, isNotNull);
          expect(fromCatalog!.isCatalog, isTrue);
          expect(
            await repo.getFoodById('catalog-frozen-1'),
            isNull,
            reason: 'catalog foods must not be visible via the library API',
          );

          // Build state and load (library is empty, catalog is loaded internally)
          final state = FoodLibraryState(repo);
          await state.loadFoods();

          // Attempt to remove the catalog food via the state layer
          await state.removeFood('catalog-frozen-1');

          // The catalog food must still be present and unchanged
          final afterCatalog = await repo.getCatalogFoodById(
            'catalog-frozen-1',
          );
          expect(
            afterCatalog,
            isNotNull,
            reason: 'removeFood must be a no-op for catalog foods',
          );
          expect(afterCatalog!.isCatalog, isTrue);
          expect(afterCatalog.name, 'Frozen Catalog Item');
          expect(afterCatalog.protein, 10);

          // The full catalog must still be intact (150 bundled + 1 seeded test entry)
          final allCatalog = await repo.getCatalogFoods(includeArchived: true);
          expect(allCatalog, isNotEmpty);
          expect(
            allCatalog.any((f) => f.id == 'catalog-frozen-1'),
            isTrue,
            reason: 'catalog row must survive a removeFood call',
          );
        },
      );
    });

    // ─── Search ───────────────────────────────────────────────────────────

    test('searchFoods returns matching results', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);

      await state.createFood(_testFood(id: 'f1', name: 'Chicken Breast'));
      await state.createFood(_testFood(id: 'f2', name: 'Broccoli'));

      final results = await state.searchFoods('chicken');

      expect(results, hasLength(1));
      expect(results[0].name, 'Chicken Breast');
    });
  });

  // ─── Food Library — Catalog Edit (Iteration 3) ─────────────────────
  // The catalog is the **global managed library**: mutable at
  // runtime, browsable in the **Library** tab of `AddFoodScreen`,
  // editable via row tap, and growable via **+ New Item**.

  group('Food catalog: create + update (S-001, S-002)', () {
    test(
      'createCatalogFood writes to the catalog box, not the library',
      () async {
        final repo = await _freshRepo();
        final baselineCatalog = (await repo.getCatalogFoods()).length;

        final newId = await repo.createCatalogFood(
          _testFood(id: 'catalog-new-1', name: 'New Catalog Food', protein: 11),
        );

        // The new row is in the catalog.
        final fromCatalog = await repo.getCatalogFoodById(newId);
        expect(fromCatalog, isNotNull);
        expect(fromCatalog!.name, 'New Catalog Food');
        expect(fromCatalog.isCatalog, isTrue);

        // The catalog grew by one.
        final allCatalog = await repo.getCatalogFoods();
        expect(allCatalog, hasLength(baselineCatalog + 1));

        // The new row is NOT visible via the library read path
        // (getFoods filters out isCatalog = true).
        final fromLibrary = await repo.getFoodById(newId);
        expect(fromLibrary, isNull);
      },
    );

    test('updateCatalogFood overwrites the catalog row in place', () async {
      final repo = await _freshRepo();
      // Seed a catalog row.
      await repo.seedCatalogFood(
        _testFood(id: 'catalog-update-1', protein: 10),
      );

      // Read → mutate → write.
      final original = (await repo.getCatalogFoodById('catalog-update-1'))!;
      final updated = original.copyWith(
        name: 'Updated Catalog Food',
        protein: 50,
      );
      await repo.updateCatalogFood(updated);

      // Catalog reflects the change.
      final reread = await repo.getCatalogFoodById('catalog-update-1');
      expect(reread!.name, 'Updated Catalog Food');
      expect(reread.protein, 50);
    });

    test('updateCatalogFood throws on a non-catalog food', () async {
      final repo = await _freshRepo();
      // _testFood produces a row with isCatalog = false (the
      // default for user-owned foods).
      final libRow = _testFood(id: 'not-catalog-1');
      expect(() => repo.updateCatalogFood(libRow), throwsStateError);
    });

    test('updateCatalogFood throws on an unknown catalog id', () async {
      final repo = await _freshRepo();
      final phantom = _testFood(
        id: 'phantom-1',
        name: 'Phantom',
      ).copyWith(isCatalog: true);
      expect(() => repo.updateCatalogFood(phantom), throwsStateError);
    });
  });

  // ─── Food groups (Groups tab) (R-2) ──────────────────────────────
  // The Groups tab lets the user rename groups inline, delete
  // groups (with food reassignment, never silent data loss), and
  // create new groups. These tests cover the state + repo surface
  // the tab uses.

  group('Food groups (Groups tab)', () {
    test(
      'renameFoodGroup persists the rename and notifies listeners',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        final groupId = await state.createFoodGroup('Proteins');

        var notifications = 0;
        state.addListener(() => notifications++);

        await state.renameFoodGroup(groupId, 'Lean Proteins');

        // Repo persists.
        final reloaded = await repo.getFoodGroupById(groupId);
        expect(reloaded?.name, 'Lean Proteins');
        // Cache reflects.
        expect(
          state.foodGroups.firstWhere((g) => g.id == groupId).name,
          'Lean Proteins',
        );
        // Listener fired at least once (create + rename).
        expect(notifications, greaterThanOrEqualTo(1));
      },
    );

    test('renameFoodGroup no-ops on empty or unchanged names', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      final groupId = await state.createFoodGroup('Proteins');

      var notifications = 0;
      state.addListener(() => notifications++);

      await state.renameFoodGroup(groupId, '   ');
      expect(notifications, 0);
      await state.renameFoodGroup(groupId, 'Proteins');
      expect(notifications, 0);
    });

    test('renameFoodGroup throws on unknown id', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      expect(() => state.renameFoodGroup('nonexistent', 'X'), throwsException);
    });

    test('deleteFoodGroupReassigningFoods moves foods to null (Ungrouped) '
        'and archives the group', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      final proteinsId = await state.createFoodGroup('Proteins');
      final snacksId = await state.createFoodGroup('Snacks');

      // Seed 3 foods in Proteins and 1 in Snacks.
      for (final id in ['f-p1', 'f-p2', 'f-p3']) {
        await state.createFood(
          _testFood(id: id, name: 'Protein $id').copyWith(groupId: proteinsId),
        );
      }
      await state.createFood(
        _testFood(id: 'f-s1', name: 'Snack 1').copyWith(groupId: snacksId),
      );

      expect(state.foods, hasLength(4));
      expect(state.foods.where((f) => f.groupId == proteinsId), hasLength(3));

      // Delete Proteins, reassigning to null (Ungrouped).
      await state.deleteFoodGroupReassigningFoods(proteinsId, null);

      // The group is archived (no longer in the active list).
      final groupAfter = await repo.getFoodGroupById(proteinsId);
      expect(groupAfter?.isArchived, isTrue);
      expect(
        state.activeFoodGroups.any((g) => g.id == proteinsId),
        isFalse,
        reason: 'archived groups are filtered out of the active list',
      );

      // The 3 proteins foods are now ungrouped.
      final foodsAfter = state.foods;
      expect(foodsAfter, hasLength(4));
      for (final f in foodsAfter) {
        if (f.id == 'f-s1') {
          expect(f.groupId, snacksId);
        } else {
          expect(f.groupId, isNull);
        }
      }

      // The repo agrees (storage shape is byte-equivalent to cache).
      final allFoods = await repo.getFoods(includeArchived: true);
      expect(allFoods, hasLength(4));
      for (final f in allFoods) {
        if (f.id == 'f-s1') {
          expect(f.groupId, snacksId);
        } else {
          expect(f.groupId, isNull);
        }
      }
    });

    test(
      'deleteFoodGroupReassigningFoods moves foods to a chosen group',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        final proteinsId = await state.createFoodGroup('Proteins');
        final snacksId = await state.createFoodGroup('Snacks');

        for (final id in ['f-p1', 'f-p2']) {
          await state.createFood(
            _testFood(id: id).copyWith(groupId: proteinsId),
          );
        }

        // Delete Proteins, reassigning to Snacks.
        await state.deleteFoodGroupReassigningFoods(proteinsId, snacksId);

        // Both proteins foods are now in Snacks.
        final foodsAfter = state.foods;
        expect(foodsAfter.where((f) => f.groupId == snacksId), hasLength(2));
        expect(foodsAfter.where((f) => f.groupId == proteinsId), isEmpty);
      },
    );

    test('reassignFoodsToGroup leaves total food count unchanged', () async {
      final repo = await _freshRepo();
      final proteinsId = await repo.createFoodGroup(
        FoodGroup(
          id: 'g-proteins',
          name: 'Proteins',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      final snacksId = await repo.createFoodGroup(
        FoodGroup(
          id: 'g-snacks',
          name: 'Snacks',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      for (final id in ['f1', 'f2', 'f3']) {
        await repo.createFood(_testFood(id: id).copyWith(groupId: proteinsId));
      }
      expect(await repo.getFoods(includeArchived: true), hasLength(3));

      await repo.reassignFoodsToGroup(['f1', 'f2'], snacksId);

      // Total count is unchanged — no food is deleted.
      final all = await repo.getFoods(includeArchived: true);
      expect(all, hasLength(3));
      expect(all.where((f) => f.groupId == snacksId), hasLength(2));
      expect(all.where((f) => f.groupId == proteinsId), hasLength(1));
    });

    test('reassignFoodsToGroup is a no-op for an empty id list', () async {
      final repo = await _freshRepo();
      // No throw; no writes.
      await repo.reassignFoodsToGroup([], null);
      expect(await repo.getFoods(includeArchived: true), isEmpty);
    });

    test('reassignFoodsToGroup silently skips unknown ids', () async {
      final repo = await _freshRepo();
      final proteinsId = await repo.createFoodGroup(
        FoodGroup(
          id: 'g-proteins',
          name: 'Proteins',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createFood(
        _testFood(id: 'f-known').copyWith(groupId: proteinsId),
      );
      // Should not throw on the unknown id.
      await repo.reassignFoodsToGroup(['f-known', 'f-bogus'], null);
      final all = await repo.getFoods(includeArchived: true);
      expect(all, hasLength(1));
      expect(all[0].groupId, isNull);
    });
  });

  // ─── Catalog search (R-3) ────────────────────────────────────────────
  // The catalog is loaded into FoodLibraryState's cache by
  // `loadCatalogFoods`. The search field on the AddFoodScreen's
  // Library tab calls `searchCatalogFoods(query)` on every keystroke;
  // the implementation is a pure local filter on `_catalogFoods`.

  group('Catalog search', () {
    test(
      'searchCatalogFoods filters by case-insensitive name substring',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();
        // Catalog is seeded with 150 bundled foods; we use the real
        // catalog so the assertion is realistic.
        final all = state.catalogFoods;
        expect(all, isNotEmpty);

        // 'chick' must match 'Chicken breast, skinless' and
        // 'Chicken thigh, skinless' (and possibly others).
        final chick = await state.searchCatalogFoods('chick');
        expect(chick, isNotEmpty);
        for (final f in chick) {
          expect(
            f.name.toLowerCase().contains('chick'),
            isTrue,
            reason: 'every match must contain the query (got: ${f.name})',
          );
        }
        // No false positives: 'chick' must not match unrelated foods.
        expect(
          chick.any((f) => f.name.toLowerCase().contains('salmon')),
          isFalse,
        );

        // Case-insensitive: same set of results for 'CHICK'.
        final upper = await state.searchCatalogFoods('CHICK');
        expect(upper.map((f) => f.id), chick.map((f) => f.id));
      },
    );

    test('searchCatalogFoods returns the full list for empty query', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final all = state.catalogFoods;
      final empty = await state.searchCatalogFoods('');
      expect(empty, hasLength(all.length));
      final whitespace = await state.searchCatalogFoods('   ');
      expect(whitespace, hasLength(all.length));
    });

    test('searchCatalogFoods returns results in alphabetical order', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();

      final all = await state.searchCatalogFoods('');
      // Sorted case-insensitive by name.
      for (var i = 0; i < all.length - 1; i++) {
        expect(
          all[i].name.toLowerCase().compareTo(all[i + 1].name.toLowerCase()),
          lessThanOrEqualTo(0),
        );
      }
    });

    // S-005: searchCatalogFoods filters out hidden catalog rows.
    // The two retired rows (beer_regular, red_wine) are bundled
    // with `hidden: true`; the search must return zero matches
    // for any query that resolves to those rows (or to any
    // hidden row added later). The empty-query full-list result
    // also excludes them — only 166 visible rows surface.
    test('S-005: searchCatalogFoods filters out hidden catalog rows', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();

      // The two retired terms return nothing — they were hidden
      // at the bundled catalog layer because the app's calorie
      // model cannot represent their alcohol-derived energy.
      final beer = await state.searchCatalogFoods('beer');
      expect(
        beer,
        isEmpty,
        reason:
            'beer_regular must not appear in catalog search; the row '
            'is hidden by the bundled catalog',
      );

      final wine = await state.searchCatalogFoods('wine');
      expect(
        wine,
        isEmpty,
        reason:
            'red_wine must not appear in catalog search; the row is '
            'hidden by the bundled catalog',
      );

      // The empty-query full list drops the hidden rows too.
      final all = await state.searchCatalogFoods('');
      expect(
        all.length,
        166,
        reason: 'empty-query search returns the 166 visible rows only',
      );
      expect(all.any((f) => f.id == 'beer_regular'), isFalse);
      expect(all.any((f) => f.id == 'red_wine'), isFalse);

      // A close-but-not-equal query still matches unrelated rows.
      // Sanity check that the search predicate is not degenerate.
      final beerish = await state.searchCatalogFoods('beef');
      expect(
        beerish,
        isNotEmpty,
        reason: 'non-hidden rows must still match normally',
      );
      for (final f in beerish) {
        expect(f.id, isNot('beer_regular'));
      }
    });
  });
}
