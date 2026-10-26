// Widget-level tests for the Library merge (plan 77b, scenarios
// S-12810..S-12818): the two-tab Manage Food Library screen, the
// merged Library list (catalog rows + legacy customs), the Yours
// tag, the tab-aware bottom CTA, and deleting a created food from
// its editor.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/delete_created_food.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log (same rationale as library_row_toggle_test.dart).
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Creates a user-created catalog food (values unlike every default)
/// and adds it to the library. Returns the catalog id.
Future<String> _seedCreatedFood(FoodLibraryState foodLib) async {
  final id = await foodLib.createCatalogFood(
    const FoodDraft(
      name: 'Mine 77 food',
      groupId: null,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 17,
      carbs: 9,
      fiber: 0,
      fat: 4,
      sodium: null,
      notes: null,
      imagePath: null,
    ),
  );
  await foodLib.addCatalogFoodToLibrary(id);
  return id;
}

/// Creates a legacy library-only custom (pre-D-2 path, no catalog
/// twin). Returns the new id.
Future<String> _seedLegacyFood(FoodLibraryState foodLib) async {
  // ignore: deprecated_member_use_from_same_package
  return foodLib.createCustomFood(
    name: 'Legacy 77 stew',
    groupId: null,
    unitType: FoodUnitType.grams,
    referenceAmount: 250,
    referenceLabel: 'g',
    protein: 18,
    carbs: 22,
    fat: 12,
  );
}

/// Types [query] into the Library search field, which also brings the
/// matching row into view on the lazily-built list.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('catalog_search_field')), query);
  await tester.pumpAndSettle();
}

void main() {
  group('Library merge (plan 77b S-12810..S-12818)', () {
    /// Pump the AddFoodScreen on the Library tab, seeding the library
    /// through [seed] before the first frame so the screen's own
    /// post-frame loads pick the fixtures up.
    Future<({NutritionState nutrition, FoodLibraryState foodLib})>
    pumpLibraryTab(
      WidgetTester tester, {
      MockWorkoutRepository? repo,
      Future<void> Function(FoodLibraryState foodLib)? seed,
    }) async {
      final r = repo ?? await _freshRepo();
      final nutrition = NutritionState(r);
      final foodLib = FoodLibraryState(r);
      await foodLib.loadFoodGroups();
      await seed?.call(foodLib);
      await tester.binding.setSurfaceSize(const Size(800, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddFoodScreen(
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (nutrition: nutrition, foodLib: foodLib);
    }

    testWidgets('S-12810: tabs are Library and Categories, no My Foods', (
      tester,
    ) async {
      await pumpLibraryTab(tester);

      expect(find.byType(TabBar), findsOneWidget);
      expect(
        find.descendant(of: find.byType(TabBar), matching: find.byType(Tab)),
        findsNWidgets(2),
      );
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('My Foods'), findsNothing);
    });

    testWidgets(
      'S-12811: a created food carries the Yours tag; a bundled food '
      'does not',
      (tester) async {
        String createdId = '';
        await pumpLibraryTab(
          tester,
          seed: (lib) async {
            createdId = await _seedCreatedFood(lib);
          },
        );

        await _search(tester, 'Mine 77');
        expect(find.text('Mine 77 food'), findsOneWidget);
        expect(find.byKey(Key('yours_tag_$createdId')), findsOneWidget);

        await _search(tester, 'Chicken breast');
        expect(find.text('Chicken breast, skinless'), findsOneWidget);
        expect(
          find.byKey(const Key('yours_tag_chicken_breast')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'S-12812: a legacy custom renders as a row with delete and Yours '
      'tag; a library copy of a bundled food is not listed twice',
      (tester) async {
        String legacyId = '';
        final states = await pumpLibraryTab(
          tester,
          seed: (lib) async {
            legacyId = await _seedLegacyFood(lib);
            await lib.addCatalogFoodToLibrary('chicken_breast');
          },
        );

        await _search(tester, 'Legacy 77');
        expect(find.text('Legacy 77 stew'), findsOneWidget);
        expect(find.byKey(Key('delete_user_food_$legacyId')), findsOneWidget);
        expect(find.byKey(Key('yours_tag_$legacyId')), findsOneWidget);
        // The old one-line macro text.
        final legacy = states.foodLib.foods.firstWhere(
          (f) => f.id == legacyId,
        );
        final cal = calculateCalories(legacy);
        expect(
          find.text(
            '$cal cal · ${formatGrams(legacy.protein)}P · '
            '${formatGrams(legacy.carbs)}C · ${formatGrams(legacy.fat)}F',
          ),
          findsOneWidget,
        );

        // The library copy of the bundled food is not a second row.
        await _search(tester, 'Chicken breast');
        expect(find.text('Chicken breast, skinless'), findsOneWidget);
      },
    );

    testWidgets(
      'S-12812b an edited copy of a bundled food is not listed as a '
      'legacy row',
      (tester) async {
        Food? copy;
        await pumpLibraryTab(
          tester,
          seed: (lib) async {
            await lib.addCatalogFoodToLibrary('chicken_breast');
            copy = lib.libraryFoodFor('chicken_breast');
            await lib.editLibraryFood(
              copy!,
              FoodDraft(
                name: 'Edited chicken 77',
                groupId: copy!.groupId,
                unitType: copy!.unitType,
                referenceAmount: copy!.referenceAmount,
                referenceLabel: copy!.referenceLabel,
                protein: 71,
                carbs: copy!.carbs,
                fiber: copy!.fiber,
                fat: copy!.fat,
                sodium: copy!.sodium,
                notes: copy!.notes,
                imagePath: copy!.imagePath,
              ),
            );
          },
        );
        // Precondition: the row we edited really is the library copy
        // of the bundled food.
        expect(copy, isNotNull);
        expect(copy!.catalogId, 'chicken_breast');

        // The catalog row is matched by its shipped name only; the
        // in-list row shows the COPY's name.
        await _search(tester, 'Chicken breast');
        expect(find.text('Edited chicken 77'), findsOneWidget);
        expect(find.byKey(Key('delete_user_food_${copy!.id}')), findsNothing);
        expect(
          find.byKey(const Key('remove_catalog_food_chicken_breast')),
          findsOneWidget,
        );

        // The edited copy must not surface as a legacy row either:
        // searching by its own name matches no catalog row, so the
        // list is empty (a mutant that lists the copy as a legacy row
        // would show it here with a red delete button).
        await _search(tester, 'Edited');
        expect(find.text('No matches for "Edited"'), findsOneWidget);
        expect(find.byKey(Key('delete_user_food_${copy!.id}')), findsNothing);
      },
    );

    testWidgets(
      'S-12813: search is case-insensitive and filters; the clear '
      'button restores the full list',
      (tester) async {
        await pumpLibraryTab(
          tester,
          seed: (lib) async {
            await _seedCreatedFood(lib);
            await _seedLegacyFood(lib);
          },
        );

        await _search(tester, 'mine 77');
        expect(find.text('Mine 77 food'), findsOneWidget);
        expect(find.text('Legacy 77 stew'), findsNothing);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        // The clear button is gone once the query is empty; the full
        // list is back (lazily built, so rows assert via a fresh
        // search below).
        expect(find.byIcon(Icons.close), findsNothing);

        await _search(tester, 'Legacy 77');
        expect(find.text('Legacy 77 stew'), findsOneWidget);
      },
    );

    testWidgets(
      'S-12814: the Library CTA opens the New Food form; the '
      'Categories tab shows its own CTA',
      (tester) async {
        await pumpLibraryTab(tester);

        expect(find.byKey(const Key('new_food_button')), findsOneWidget);
        expect(find.text('+ New Food'), findsOneWidget);
        expect(find.text('+ Create new food'), findsNothing);

        await tester.tap(find.byKey(const Key('new_food_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_form_name')), findsOneWidget);

        // The untouched form pops straight back (no discard prompt).
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('new_group_button')), findsOneWidget);
        expect(find.text('+ New Food'), findsNothing);
      },
    );

    testWidgets(
      'S-12815: deleting a created food from its editor removes the '
      'catalog row, the library copy and today\'s log',
      (tester) async {
        String createdId = '';
        final states = await pumpLibraryTab(
          tester,
          seed: (lib) async {
            createdId = await _seedCreatedFood(lib);
          },
        );
        final foodLib = states.foodLib;
        final nutrition = states.nutrition;
        final libId = foodLib.libraryIdFor(createdId)!;

        // Log it today so the delete has to unlog it.
        await nutrition.loadNutritionTarget();
        await nutrition.logConsumedFoodAt(
          foodLib.libraryFoodFor(createdId)!,
          100,
        );
        expect(nutrition.isFoodLoggedToday(libId), isTrue);

        await _search(tester, 'Mine 77');
        await tester.tap(find.byKey(Key('edit_catalog_food_$createdId')));
        await tester.pumpAndSettle();
        final edit = tester.widget<EditFoodScreen>(find.byType(EditFoodScreen));
        expect(edit.nutritionState, isNotNull);
        expect(find.byKey(const Key('food_delete_created')), findsOneWidget);

        // Cancel keeps everything.
        await tester.tap(find.byKey(const Key('food_delete_created')));
        await tester.pumpAndSettle();
        expect(find.text('Delete Mine 77 food?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('food-delete-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsOneWidget);
        expect(foodLib.catalogFoods.any((f) => f.id == createdId), isTrue);

        // Confirm removes the row, the copy and today's log.
        await tester.tap(find.byKey(const Key('food_delete_created')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);
        expect(foodLib.catalogFoods.any((f) => f.id == createdId), isFalse);
        expect(foodLib.libraryFoodFor(createdId), isNull);
        expect(nutrition.isFoodLoggedToday(libId), isFalse);
      },
    );

    testWidgets(
      'S-12816: Delete food is absent for a bundled food; Reset and '
      'Delete are never both shown',
      (tester) async {
        String createdId = '';
        final states = await pumpLibraryTab(
          tester,
          seed: (lib) async {
            createdId = await _seedCreatedFood(lib);
            await lib.addCatalogFoodToLibrary('chicken_breast');
          },
        );
        final foodLib = states.foodLib;

        // Bundled editor before any edit: no footer at all.
        await _search(tester, 'Chicken breast');
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_delete_created')), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Edit the copy so Reset shows; still no Delete.
        final copy = foodLib.libraryFoodFor('chicken_breast')!;
        await foodLib.editLibraryFood(
          copy,
          FoodDraft(
            name: 'My chicken 77',
            groupId: copy.groupId,
            unitType: copy.unitType,
            referenceAmount: copy.referenceAmount,
            referenceLabel: copy.referenceLabel,
            protein: 99,
            carbs: copy.carbs,
            fiber: copy.fiber,
            fat: copy.fat,
            sodium: copy.sodium,
            notes: copy.notes,
            imagePath: copy.imagePath,
          ),
        );
        await tester.pumpAndSettle();
        await _search(tester, 'Chicken breast');
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_reset_original')), findsOneWidget);
        expect(find.byKey(const Key('food_delete_created')), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // A created food's editor: Delete food, never Reset.
        await _search(tester, 'Mine 77');
        await tester.tap(find.byKey(Key('edit_catalog_food_$createdId')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_delete_created')), findsOneWidget);
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
      },
    );

    testWidgets(
      'S-12816b no Delete food on a bundled catalog row',
      (tester) async {
        final repo = await _freshRepo();
        final nutrition = NutritionState(repo);
        final foodLib = FoodLibraryState(repo);
        await foodLib.loadFoodGroups();
        await foodLib.loadCatalogFoods();
        final createdId = await _seedCreatedFood(foodLib);
        final createdRow = foodLib.catalogFoods.firstWhere(
          (f) => f.id == createdId,
        );
        final bundledRow = foodLib.catalogFoods.firstWhere(
          (f) => f.id == 'chicken_breast',
        );

        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Precondition: the created food's catalog row DOES offer
        // Delete food, so the assertions below cannot pass because
        // the button is never built at all.
        await tester.pumpWidget(
          MaterialApp(
            home: EditFoodScreen(
              food: createdRow,
              foodLibraryState: foodLib,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_delete_created')), findsOneWidget);

        // The bundled catalog row's editor: no Delete food and no
        // Reset (nothing was edited).
        await tester.pumpWidget(
          MaterialApp(
            home: EditFoodScreen(
              food: bundledRow,
              foodLibraryState: foodLib,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('food_delete_created')), findsNothing);
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
      },
    );

    testWidgets(
      'S-12817: confirmAndDeleteCreatedFood returns false on Cancel '
      'and true on Confirm',
      (tester) async {
        final repo = await _freshRepo();
        final nutrition = NutritionState(repo);
        final foodLib = FoodLibraryState(repo);
        await foodLib.loadFoodGroups();
        final id = await _seedCreatedFood(foodLib);
        final createdRow = foodLib.catalogFoods.firstWhere((f) => f.id == id);

        Future<bool>? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  key: const Key('go'),
                  onPressed: () => result = confirmAndDeleteCreatedFood(
                    ctx,
                    food: createdRow,
                    foodLibraryState: foodLib,
                    nutritionState: nutrition,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Cancel: false, nothing deleted.
        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();
        expect(find.text('Delete Mine 77 food?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('food-delete-cancel')));
        await tester.pumpAndSettle();
        expect(await result!, isFalse);
        expect(foodLib.catalogFoods.any((f) => f.id == id), isTrue);
        expect(foodLib.libraryFoodFor(id), isNotNull);

        // Confirm: true, catalog row and library copy gone.
        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-delete-confirm')));
        await tester.pumpAndSettle();
        expect(await result!, isTrue);
        expect(foodLib.catalogFoods.any((f) => f.id == id), isFalse);
        expect(foodLib.libraryFoodFor(id), isNull);
      },
    );
  });

  test('S-12818: source guard on add_food_screen.dart', () async {
    final source = File(
      'lib/features/nutrition/add_food_screen.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains('class _MyFoodsTab')),
      reason: 'S-12818: the My Foods tab widget is deleted',
    );
    expect(
      source,
      isNot(contains('_myFoodsTabIndex')),
      reason: 'S-12818: the My Foods tab index constant is deleted',
    );
    expect(
      source,
      isNot(contains("Tab(text: 'My Foods')")),
      reason: 'S-12818: the My Foods tab is gone from the TabBar',
    );
    expect(
      source,
      contains("label: '+ New Food',"),
      reason: 'S-12818: the Library CTA label is + New Food',
    );
    expect(
      source,
      isNot(contains("'+ Create new food'")),
      reason: 'S-12818: the old CTA label is replaced by + New Food',
    );
    expect(
      source,
      isNot(contains('No custom foods yet')),
      reason: 'S-12818: the My Foods empty state is deleted',
    );
    expect(
      source,
      contains('TabController(length: 2, vsync: this)'),
      reason: 'S-12818: the screen has exactly two tabs',
    );
  });
}
