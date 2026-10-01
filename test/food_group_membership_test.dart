// Regression tests for **what a food category actually contains**.
//
// Symptom (2026-08-18): the Groups tab reported "Drinks — 1 food"
// on a device whose Library tab listed a dozen drinks, and the
// food editor showed a raw internal id ("food-group-dairy (no
// longer available)") as a food's category.
//
// Both come from the same root: bundled catalog foods are filed
// into categories, but the category-management UI counted only
// the user's personal library. The tally excluded
//
//   * every bundled catalog food, and
//   * every food the user created via **+ New Item** (those rows
//     live in the catalog box, not the library box),
//
// which also made the delete-confirmation dialog dishonest: a
// category holding nothing but + New Item foods reported zero and
// took the silent-delete path.
//
// Product decision (2026-08-18): the count is the bundled catalog
// plus user-created foods; personal-library COPIES of a catalog
// food do not add a second entry to the category.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Reads the suffix the Groups tab renders inside a category's
/// name field (the "N foods" / "empty" tally).
String? _suffixFor(WidgetTester tester, String groupId) {
  final field = tester.widget<TextField>(
    find.byKey(Key('group_name_$groupId')),
  );
  return field.decoration?.suffixText;
}

Future<void> _openGroupsTab(WidgetTester tester) async {
  await tester.tap(find.text('Categories'));
  await tester.pumpAndSettle();
}

void main() {
  group('Groups tab — category tally', () {
    testWidgets('counts the bundled catalog foods filed in the category', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadFoodGroups();
      await foodLib.loadCatalogFoods();
      await foodLib.loadFoods();

      // How many bundled drinks the catalog actually ships.
      final bundledDrinks = foodLib.catalogFoods
          .where((f) => !f.isArchived && f.groupId == 'food-group-drinks')
          .length;
      expect(
        bundledDrinks,
        greaterThan(1),
        reason:
            'the bundled catalog must ship several drinks for this '
            'test to be meaningful',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openGroupsTab(tester);

      expect(
        _suffixFor(tester, 'food-group-drinks'),
        '$bundledDrinks',
        reason:
            'the Drinks tally must reflect the drinks the category '
            'holds, not just the personal library',
      );
    });

    testWidgets('counts a food created via + New Item', (tester) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadFoodGroups();
      await foodLib.loadCatalogFoods();
      await foodLib.loadFoods();

      final before = foodLib.catalogFoods
          .where((f) => !f.isArchived && f.groupId == 'food-group-drinks')
          .length;

      // The + New Item path writes a catalog row, not a library row.
      await foodLib.createCatalogFood(
        const FoodDraft(
          name: 'Homemade Kombucha',
          groupId: 'food-group-drinks',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          protein: 0,
          carbs: 3,
          fiber: null,
          fat: 0,
          sodium: null,
          notes: null,
          imagePath: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openGroupsTab(tester);

      expect(_suffixFor(tester, 'food-group-drinks'), '${before + 1}');
    });

    testWidgets('adding a catalog food to the library does not double-count', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadFoodGroups();
      await foodLib.loadCatalogFoods();
      await foodLib.loadFoods();

      final drinks = foodLib.catalogFoods
          .where((f) => !f.isArchived && f.groupId == 'food-group-drinks')
          .toList();
      final expected = drinks.length;

      // "Add to Foods I Eat" makes a personal-library copy. The
      // category still holds the same set of foods.
      await foodLib.addCatalogFoodToLibrary(drinks.first.id);

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openGroupsTab(tester);

      expect(_suffixFor(tester, 'food-group-drinks'), '$expected');
    });
  });

  group('Delete guard — cold catalog cache', () {
    test(
      'refuses to delete a category the bundled catalog still uses',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.loadFoodGroups();
        // Deliberately NOT loading the catalog: the guard reads the
        // in-memory catalog cache, and a cold cache used to make it
        // wave the deletion through and strand every bundled drink.

        await expectLater(
          state.deleteFoodGroupReassigningFoods('food-group-drinks', null),
          throwsA(isA<FoodGroupHasBundledFoodsError>()),
        );

        final groups = await repo.getFoodGroups(includeArchived: true);
        final drinks = groups.firstWhere((g) => g.id == 'food-group-drinks');
        expect(
          drinks.isArchived,
          isFalse,
          reason: 'a refused deletion must be a true no-op',
        );
      },
    );
  });

  group('Foods I Eat — food filed under a missing category', () {
    testWidgets('renders under Ungrouped instead of vanishing', (tester) async {
      final repo = await _freshRepo();
      final primer = await buildNutritionPrimerState(repo);

      // A library food pointing at a category that does not exist
      // on this device — the state a user lands in when a default
      // category was never seeded (name collision) or was removed.
      await repo.createFood(
        const Food(
          id: 'f-orphan',
          name: 'Stranded Yoghurt',
          groupId: 'food-group-does-not-exist',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 5,
          carbs: 4,
          fat: 3,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );

      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutrition,
            foodLibraryState: foodLib,
            nutritionPrimerState: primer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Stranded Yoghurt'),
        findsOneWidget,
        reason: 'a food whose category is gone must still be listed',
      );
      expect(find.text('Uncategorized'), findsOneWidget);
    });
  });
}
