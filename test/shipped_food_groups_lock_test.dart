// Plan 137 phase P1a — the shipped food categories are locked (S-13701..S-13704
// of `docs/plans/2026-11-09-137-shipped-food-categories-locked-plan/...`).
//
// `shippedFoodGroupIds` mirrors the nine `SeedData.defaultFoodGroups` ids; the
// state refuses `deleteFoodGroupReassigningFoods` and `archiveFoodGroup` for
// any of them with a typed `ShippedFoodGroupError`, before anything is read or
// written. A custom group still deletes (reassigning its foods) and archives
// normally.
//
// The shared cases run over `harnessFactories` with plain `test()`: a Hive
// write inside a widget test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/shipped_food_groups.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'helpers/repository_harness.dart';

Food _bundledLookingDairy({
  String id = 'whole_milk',
  String name = 'Whole milk',
}) => Food(
  id: id,
  name: name,
  groupId: 'food-group-dairy',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: 3,
  carbs: 5,
  fat: 3,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

Food _libraryCopy(String groupId) => Food(
  id: 'copy-milk',
  name: 'Milk copy',
  groupId: groupId,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: false,
  catalogId: 'whole_milk',
  protein: 3,
  carbs: 5,
  fat: 3,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — shipped food categories locked (plan 137)', () {
      late WorkoutRepository repo;
      late FoodLibraryState state;

      setUp(() async {
        repo = await harness.open();
        state = FoodLibraryState(repo);
      });
      tearDown(() => harness.close());

      test('S-13701 ships nine categories, equal to the seed list', () async {
        expect(shippedFoodGroupIds.length, 9);
        expect(
          shippedFoodGroupIds,
          SeedData.defaultFoodGroups.map((g) => g.id).toSet(),
        );
        expect(isShippedFoodGroupId('food-group-dairy'), isTrue);

        final id = await state.createFoodGroup('My Dairy');
        expect(isShippedFoodGroupId(id), isFalse);
      });

      test(
        'S-13702 delete of a shipped category is refused, no food moves',
        () async {
          // Delete every catalog food still pointing at Dairy so the
          // fixture exercises the new lock, not the removed bundled
          // guard. Add one bundled-looking row first if the repo starts
          // with none, so the removal is not vacuous.
          final before = await repo.getCatalogFoods();
          final dairyIds = before
              .where((f) => !f.isArchived && f.groupId == 'food-group-dairy')
              .map((f) => f.id)
              .toList();
          if (dairyIds.isEmpty) {
            await repo.createCatalogFood(_bundledLookingDairy());
            dairyIds.add('whole_milk');
          }
          for (final id in dairyIds) {
            await repo.deleteCatalogFood(id);
          }

          // The stranded library twin the lock must protect.
          await repo.createFood(_libraryCopy('food-group-dairy'));

          await state.loadFoodGroups();
          await state.loadFoods();

          await expectLater(
            state.deleteFoodGroupReassigningFoods('food-group-dairy', null),
            throwsA(isA<ShippedFoodGroupError>()),
          );

          final groups = await repo.getFoodGroups(includeArchived: true);
          final dairy = groups.firstWhere((g) => g.id == 'food-group-dairy');
          expect(dairy.isArchived, isFalse);
          final copy = await repo.getFoodById('copy-milk');
          expect(copy, isNotNull);
          expect(copy!.groupId, 'food-group-dairy');
        },
      );

      test('S-13703 archive of a shipped category is refused; a custom one '
          'archives', () async {
        await state.loadFoodGroups();

        await expectLater(
          state.archiveFoodGroup('food-group-dairy'),
          throwsA(isA<ShippedFoodGroupError>()),
        );
        final groups = await repo.getFoodGroups(includeArchived: true);
        final dairy = groups.firstWhere((g) => g.id == 'food-group-dairy');
        expect(dairy.isArchived, isFalse);

        final id = await state.createFoodGroup('My Proteins');
        await state.archiveFoodGroup(id);
        final after = await repo.getFoodGroups(includeArchived: true);
        final custom = after.firstWhere((g) => g.id == id);
        expect(custom.isArchived, isTrue);
      });

      test(
        'S-13711 updateFoodGroup cannot archive a shipped category; '
        'a rename still works',
        () async {
          await state.loadFoodGroups();
          final dairy = state.foodGroups.firstWhere(
            (g) => g.id == 'food-group-dairy',
          );

          await expectLater(
            state.updateFoodGroup(
              FoodGroup(
                id: dairy.id,
                name: dairy.name,
                color: dairy.color,
                isArchived: true,
                createdAtMs: dairy.createdAtMs,
                updatedAtMs: dairy.updatedAtMs,
              ),
            ),
            throwsA(isA<ShippedFoodGroupError>()),
          );

          final groups = await repo.getFoodGroups(includeArchived: true);
          var stored = groups.firstWhere((g) => g.id == 'food-group-dairy');
          expect(stored.isArchived, isFalse);

          await state.renameFoodGroup('food-group-dairy', 'Milk and Cheese');
          final after = await repo.getFoodGroups(includeArchived: true);
          stored = after.firstWhere((g) => g.id == 'food-group-dairy');
          expect(stored.name, 'Milk and Cheese');
          expect(stored.isArchived, isFalse);
        },
      );

      test(
        'S-13704 a custom group still reassigns its foods and archives',
        () async {
          final tempId = await state.createFoodGroup('Temp');
          final destId = await state.createFoodGroup('Dest');

          final libId = await repo.createFood(
            Food(
              id: 'lib-temp-1',
              name: 'Temp library food',
              groupId: tempId,
              unitType: FoodUnitType.grams,
              referenceAmount: 100,
              referenceLabel: 'g',
              protein: 10,
              carbs: 5,
              fat: 1,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          final catalogId = await repo.createCatalogFood(
            Food(
              id: 'catalog-temp-1',
              name: 'Temp catalog food',
              groupId: tempId,
              unitType: FoodUnitType.grams,
              referenceAmount: 100,
              referenceLabel: 'g',
              isCatalog: true,
              protein: 11,
              carbs: 6,
              fat: 2,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          await state.loadFoodGroups();
          await state.loadFoods();
          await state.loadCatalogFoods();

          await state.deleteFoodGroupReassigningFoods(tempId, destId);

          final movedLib = await repo.getFoodById(libId);
          expect(movedLib, isNotNull);
          expect(movedLib!.groupId, destId);
          final movedCatalog = await repo.getCatalogFoodById(catalogId);
          expect(movedCatalog, isNotNull);
          expect(movedCatalog!.groupId, destId);

          final groups = await repo.getFoodGroups(includeArchived: true);
          final temp = groups.firstWhere((g) => g.id == tempId);
          expect(temp.isArchived, isTrue);
        },
      );

      test(
        'S-13710 a custom group deletes with a cold catalog cache and still '
        'moves its catalog foods',
        () async {
          final tempId = await state.createFoodGroup('Temp');
          final destId = await state.createFoodGroup('Dest');

          final catalogId = await repo.createCatalogFood(
            Food(
              id: 'catalog-cold-1',
              name: 'Cold catalog food',
              groupId: tempId,
              unitType: FoodUnitType.grams,
              referenceAmount: 100,
              referenceLabel: 'g',
              isCatalog: true,
              protein: 7,
              carbs: 2,
              fat: 1,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          // The catalog cache must stay cold: no loadCatalogFoods() here —
          // deleteFoodGroupReassigningFoods has to load it itself.
          await state.loadFoodGroups();
          await state.loadFoods();

          await state.deleteFoodGroupReassigningFoods(tempId, destId);

          final movedCatalog = await repo.getCatalogFoodById(catalogId);
          expect(movedCatalog, isNotNull);
          expect(movedCatalog!.groupId, destId);

          final groups = await repo.getFoodGroups(includeArchived: true);
          final temp = groups.firstWhere((g) => g.id == tempId);
          expect(temp.isArchived, isTrue);
        },
      );
    });
  }
}
