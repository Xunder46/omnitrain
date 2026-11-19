// Plan 254 P3 — state tests for "the calories override travels through every
// path" (S-25401..S-25405).
//
// Every site that turns a `FoodDraft` (or the named fields of
// `createCustomFood`) into a `Food` carries `caloriesOverride` through:
// catalog create, custom create (both deprecated library-only paths),
// custom update (a field-by-field rebuild: null clears), catalog update
// (a `copyWith`: null clears) and its propagation to linked library
// copies, and the own-copy-of-default path.
//
// Every scenario runs under Mock AND Hive (plain `test()`, the harness
// from `test/calories_override_test.dart` / `test/last_time_prefill_test.dart`).
//
// Plan: `docs/plans/2026-11-19-254-calories-field-in-food-form-plan/
// 2026-11-19-254-calories-field-in-food-form-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture ────────────────────────────────────────────────────────────────

/// Beer: 100 ml, 0.5 P / 3.6 C / 0 F (macro sum 16.4 kcal), with the
/// brewery's own 43 kcal per 100 ml when [override] is given.
FoodDraft draft({double? override}) => FoodDraft(
  name: 'Beer',
  groupId: null,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'ml',
  protein: 0.5,
  carbs: 3.6,
  fiber: null,
  fat: 0,
  sodium: null,
  notes: null,
  imagePath: null,
  caloriesOverride: override,
);

/// The catalog row [state] holds for [id].
Food catalogFood(FoodLibraryState state, String id) =>
    state.catalogFoods.firstWhere((f) => f.id == id);

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: the calories override travels through every state path', () {
      late RepositoryHarness harness;
      late WorkoutRepository repo;
      late FoodLibraryState state;

      setUp(() async {
        harness = make();
        repo = await harness.open();
        state = FoodLibraryState(repo);
        await state.loadCatalogFoods();
      });
      tearDown(() => harness.close());

      test('S-25401 createCatalogFood carries the draft\'s override, and '
          'null without one', () async {
        final id = await state.createCatalogFood(draft(override: 43));
        expect(catalogFood(state, id).caloriesOverride, 43);

        final plainId = await state.createCatalogFood(draft());
        expect(catalogFood(state, plainId).caloriesOverride, isNull);
      });

      test('S-25402 createCustomFood and createCustomFoodFromDraft store '
          'the override', () async {
        // ignore: deprecated_member_use_from_same_package
        final id = await state.createCustomFood(
          name: 'Beer',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0.5,
          carbs: 3.6,
          fat: 0,
          caloriesOverride: 43,
        );
        expect((await repo.getFoodById(id))!.caloriesOverride, 43);

        // ignore: deprecated_member_use_from_same_package
        final draftId = await state.createCustomFoodFromDraft(
          draft(override: 43),
        );
        expect((await repo.getFoodById(draftId))!.caloriesOverride, 43);
      });

      test('S-25403 updateCustomFood sets the override and clears it '
          'again with null', () async {
        // ignore: deprecated_member_use_from_same_package
        final id = await state.createCustomFood(
          name: 'Beer',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0.5,
          carbs: 3.6,
          fat: 0,
        );
        expect((await repo.getFoodById(id))!.caloriesOverride, isNull);

        await state.updateCustomFood(
          id: id,
          name: 'Beer',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0.5,
          carbs: 3.6,
          fat: 0,
          sodium: null,
          notes: null,
          imagePath: null,
          caloriesOverride: 43,
        );
        expect((await repo.getFoodById(id))!.caloriesOverride, 43);

        await state.updateCustomFood(
          id: id,
          name: 'Beer',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0.5,
          carbs: 3.6,
          fat: 0,
          sodium: null,
          notes: null,
          imagePath: null,
          caloriesOverride: null,
        );
        expect((await repo.getFoodById(id))!.caloriesOverride, isNull);
      });

      test(
        'S-25404 updateCatalogFood holds the override in the catalog '
        'food and the linked library copy, and clears both with null',
        () async {
          final id = await state.createCatalogFood(draft());
          final libId = await state.addCatalogFoodToLibrary(id);
          expect(state.libraryFoodFor(id)!.id, libId);
          expect(catalogFood(state, id).caloriesOverride, isNull);
          expect(state.libraryFoodFor(id)!.caloriesOverride, isNull);

          final existing = catalogFood(state, id);
          await state.updateCatalogFood(existing, draft(override: 43));
          final updated = catalogFood(state, id);
          expect(updated.caloriesOverride, 43);
          expect(state.libraryFoodFor(id)!.caloriesOverride, 43);

          await state.updateCatalogFood(updated, draft());
          expect(catalogFood(state, id).caloriesOverride, isNull);
          expect(state.libraryFoodFor(id)!.caloriesOverride, isNull);
        },
      );

      test('S-25405 createOwnCopyOfDefault applies the draft\'s override '
          'to the new library row', () async {
        final source = state.catalogFoods.firstWhere(
          (f) => f.id == 'chicken_breast',
        );
        expect(state.isDefaultFood(source), isTrue);

        final libId = await state.createOwnCopyOfDefault(
          source,
          draft(override: 43),
          addToList: true,
        );

        final libraryRow = state.foods.firstWhere((f) => f.id == libId);
        expect(libraryRow.caloriesOverride, 43);
        // The catalog row behind the copy holds the same number.
        expect(catalogFood(state, libraryRow.catalogId!).caloriesOverride, 43);
      });

      test('S-25414 createFood keeps the food\'s caloriesOverride', () async {
        const beer = Food(
          id: 's25414-beer',
          name: 'Beer',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0.5,
          carbs: 3.6,
          fat: 0,
          caloriesOverride: 43,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        await state.createFood(beer);

        expect((await repo.getFoodById(beer.id))!.caloriesOverride, 43);
      });
    });
  }
}
