// Widget-level tests for the Library row toggle (plan 77a,
// scenarios S-12710..S-12717): the row tap adds/removes, the check
// indicator replaces the trash button, the pencil opens the editor
// with the library copy, and the in-list row carries the primary
// outline.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log. The `SeedData.sampleConsumedFoods()` seed preloads three
  // today-dated rows (chicken, rice, olive oil) for the Stats Nutrition
  // Trend card; tests that read `consumedToday` / `todayConsumedCalories`
  // need a clean slate to keep their totals deterministic.
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// The vertically-scrolling list on a screen.
///
/// Screens that carry a horizontal tab strip or chip row above their content
/// contain several [Scrollable]s, and the horizontal ones come first in the
/// tree — so `find.byType(Scrollable).first` grabs the wrong one and dragging
/// it reveals nothing. Match on axis instead of position.
final Finder _verticalScrollable = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

void main() {
  group('Library row toggle (plan 77a S-12710..S-12717)', () {
    /// Pin a single catalog food and return the seeded id.
    Future<String> seedSingleCatalog(MockWorkoutRepository repo) async {
      const catalogSource = Food(
        id: 'toggle-catalog-chicken',
        name: 'Chicken (toggle test)',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );
      await repo.seedCatalogFood(catalogSource);
      return catalogSource.id;
    }

    /// Pump the AddFoodScreen for the Library tab.
    ///
    /// [searchFor] types the seeded food's name into the catalog
    /// search field after the first settle, switching the list to the
    /// flat filtered view so the lazily-built list actually renders
    /// the seeded row (with category headings the seeded null-group
    /// food sits under the last heading, far below the viewport).
    Future<({NutritionState nutrition, FoodLibraryState foodLib})>
    pumpCatalogTab(
      WidgetTester tester, {
      MockWorkoutRepository? repo,
      String? searchFor,
    }) async {
      final r = repo ?? await _freshRepo();
      final nutrition = NutritionState(r);
      final foodLib = FoodLibraryState(r);
      await tester.binding.setSurfaceSize(const Size(800, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await foodLib.loadFoodGroups();
      await foodLib.loadFoods();
      // The screen's initState schedules a loadCatalogFoods via
      // addPostFrameCallback; pumpAndSettle drains that microtask
      // chain so the list is populated before the first assertion.
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
      if (searchFor != null) {
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          searchFor,
        );
        await tester.pumpAndSettle();
      }
      return (nutrition: nutrition, foodLib: foodLib);
    }

    testWidgets('S-12710: row tap adds a not-in-list food to the library', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final catalogId = await seedSingleCatalog(repo);
      final states = await pumpCatalogTab(
        tester,
        repo: repo,
        searchFor: 'Chicken (toggle',
      );

      // Before: the Add button is there, no pencil, no check icon.
      expect(find.byKey(Key('add_catalog_food_$catalogId')), findsOneWidget);
      expect(find.byKey(Key('edit_catalog_food_$catalogId')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Row tap (on the name text) adds the food.
      await tester.tap(find.text('Chicken (toggle test)'));
      await tester.pumpAndSettle();

      // After: the library holds the copy, the row flipped to the
      // in-list state, and the screen is still on top.
      await states.foodLib.loadFoods();
      expect(states.foodLib.foods, hasLength(1));
      expect(find.byKey(Key('add_catalog_food_$catalogId')), findsNothing);
      expect(
        find.byKey(Key('remove_catalog_food_$catalogId')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(Key('remove_catalog_food_$catalogId')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(find.byKey(Key('edit_catalog_food_$catalogId')), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Manage Food Library'), findsOneWidget);
    });

    testWidgets(
      'S-12711: in-list row tap asks before removing; Cancel keeps, '
      'Confirm removes and unlogs today',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await seedSingleCatalog(repo);
        final states = await pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken (toggle',
        );

        // Add it by row tap, and log it for today so the confirm path
        // has to unlog it.
        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();
        await states.foodLib.loadFoods();
        final libId = states.foodLib.libraryIdFor(catalogId);
        expect(libId, isNotNull, reason: 'precondition: the food is added');
        await states.nutrition.loadNutritionTarget();
        await states.nutrition.logConsumedFoodAt(
          states.foodLib.foods.firstWhere((f) => f.id == libId),
          100.0,
        );
        expect(states.nutrition.isFoodLoggedToday(libId!), isTrue);

        // Tap the name again: the remove dialog names the food.
        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();
        expect(
          find.text('Remove Chicken (toggle test) from your library?'),
          findsOneWidget,
        );

        // Cancel keeps the food in the library and today's log.
        await tester.tap(find.byKey(const Key('food-remove-cancel')));
        await tester.pumpAndSettle();
        await states.foodLib.loadFoods();
        expect(states.foodLib.foods, hasLength(1));
        expect(states.nutrition.isFoodLoggedToday(libId), isTrue);

        // Tap again and confirm: the food is removed and unlogged.
        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-remove-confirm')));
        await tester.pumpAndSettle();
        await states.foodLib.loadFoods();
        expect(states.foodLib.foods, isEmpty);
        expect(states.nutrition.isFoodLoggedToday(libId), isFalse);
        expect(find.byKey(Key('add_catalog_food_$catalogId')), findsOneWidget);
      },
    );

    testWidgets(
      'S-12712: the in-list row carries the primary outline; the '
      'not-in-list row has none',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await seedSingleCatalog(repo);
        await pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken (toggle',
        );

        // Before the add: no outline.
        expect(find.byKey(Key('library_row_outline_$catalogId')), findsNothing);

        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();

        // After the add: a DecoratedBox outline in the primary colour.
        final box = tester.widget<DecoratedBox>(
          find.byKey(Key('library_row_outline_$catalogId')),
        );
        final border = (box.decoration as BoxDecoration).border! as Border;
        final primary =
            Theme.of(
              tester.element(find.byType(AddFoodScreen)),
            ).colorScheme.primary;
        expect(border.top.color, equals(primary));
        expect(border.top.width, equals(2));

        // Removing the food (confirm dialog) removes the outline.
        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-remove-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('library_row_outline_$catalogId')), findsNothing);
      },
    );

    testWidgets(
      'S-12713: pencil on an in-list bundled food edits the copy; reset '
      'restores the shipped values',
      (tester) async {
        final repo = await _freshRepo();
        final states = await pumpCatalogTab(tester, repo: repo);
        final foodLib = states.foodLib;

        await foodLib.loadCatalogFoods();
        final shipped = (await repo.getCatalogFoodById('chicken_breast'))!;
        await foodLib.addCatalogFoodToLibrary('chicken_breast');
        await tester.pumpAndSettle();

        // The list is lazily built; scroll the pencil into view.
        await tester.scrollUntilVisible(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
          200,
          scrollable: _verticalScrollable,
        );
        await tester.pumpAndSettle();

        // (1) The pencil opens the editor; no Reset before an edit.
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
        // The editor was opened with the library copy, not the
        // bundled catalog row.
        final edit = tester.widget<EditFoodScreen>(
          find.byType(EditFoodScreen),
        );
        expect(edit.food.isCatalog, isFalse);
        expect(edit.food.id, foodLib.libraryFoodFor('chicken_breast')!.id);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // (2) Edit the copy through state: only the copy changes.
        final copy = foodLib.libraryFoodFor('chicken_breast')!;
        final draft = FoodDraft(
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
        );
        await foodLib.editLibraryFood(copy, draft);
        await tester.pumpAndSettle();
        expect(find.text('My chicken 77'), findsOneWidget);
        final catalogAfterEdit = await repo.getCatalogFoodById(
          'chicken_breast',
        );
        expect(catalogAfterEdit!.name, shipped.name);

        // (3) The Reset button appears after the edit and restores the
        // shipped values.
        await tester.scrollUntilVisible(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
          200,
          scrollable: _verticalScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_chicken_breast')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);
        expect(find.byKey(const Key('food_reset_original')), findsOneWidget);

        await tester.tap(find.byKey(const Key('food_reset_original')));
        await tester.pumpAndSettle();
        expect(find.text('Reset to original?'), findsOneWidget);

        // Cancel keeps the copy as edited.
        await tester.tap(find.byKey(const Key('food-reset-cancel')));
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);
        expect(foodLib.libraryFoodFor('chicken_breast')!.name, 'My chicken 77');

        // Confirm restores the shipped values.
        await tester.tap(find.byKey(const Key('food_reset_original')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-reset-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsNothing);
        final restored = foodLib.libraryFoodFor('chicken_breast')!;
        expect(restored.name, shipped.name);
        expect(restored.protein, shipped.protein);
        expect(find.text(shipped.name), findsOneWidget);
      },
    );

    testWidgets('S-12714: the pencil does not toggle the row', (tester) async {
      final repo = await _freshRepo();
      final catalogId = await seedSingleCatalog(repo);
      final states = await pumpCatalogTab(
        tester,
        repo: repo,
        searchFor: 'Chicken (toggle',
      );

      await tester.tap(find.text('Chicken (toggle test)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('edit_catalog_food_$catalogId')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The food is still in the library; the row is still in-list.
      await states.foodLib.loadFoods();
      expect(states.foodLib.foods, hasLength(1));
      expect(find.byKey(Key('remove_catalog_food_$catalogId')), findsOneWidget);
    });

    testWidgets(
      'S-12715: the row macro line reads the copy after an edit',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await seedSingleCatalog(repo);
        final states = await pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken (toggle',
        );

        // Before the add the row shows the catalog food's macros,
        // computed with the same helper the row uses.
        final catalog = (await repo.getCatalogFoodById(catalogId))!;
        final cal = calculateCalories(catalog);
        expect(find.text('$cal cal per 100 g'), findsOneWidget);
        expect(find.text('31P · 0C · 3F'), findsOneWidget);

        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();

        // Edit the copy: the in-list row shows the copy's values.
        final copy = states.foodLib.libraryFoodFor(catalogId)!;
        final draft = FoodDraft(
          name: 'Edited chicken',
          groupId: copy.groupId,
          unitType: copy.unitType,
          referenceAmount: copy.referenceAmount,
          referenceLabel: copy.referenceLabel,
          protein: 7,
          carbs: copy.carbs,
          fiber: copy.fiber,
          fat: copy.fat,
          sodium: copy.sodium,
          notes: copy.notes,
          imagePath: copy.imagePath,
        );
        await states.foodLib.editLibraryFood(copy, draft);
        await tester.pumpAndSettle();

        final edited = states.foodLib.libraryFoodFor(catalogId)!;
        final cal2 = calculateCalories(edited);
        expect(find.text('Edited chicken'), findsOneWidget);
        expect(find.text('$cal2 cal per 100 g'), findsOneWidget);
        expect(find.text('7P · 0C · 3F'), findsOneWidget);
      },
    );

    testWidgets(
      'S-12717: a user-created (non-bundled) in-list food has no Reset '
      'button',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await seedSingleCatalog(repo);
        await pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken (toggle',
        );

        await tester.tap(find.text('Chicken (toggle test)'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('edit_catalog_food_$catalogId')));
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
        // The editor was opened with the catalog row itself: a
        // user-created food has no shipped original, so its catalog
        // row is the thing edited, not the library copy.
        final edit = tester.widget<EditFoodScreen>(
          find.byType(EditFoodScreen),
        );
        expect(edit.food.isCatalog, isTrue);
        expect(edit.food.id, catalogId);
      },
    );

    testWidgets(
      'S-12719: the Edit screen routes a bundled copy\'s save through '
      'editLibraryFood (onSave and onImageSave)',
      (tester) async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await foodLib.loadCatalogFoods();
        final shipped = (await repo.getCatalogFoodById('chicken_breast'))!;
        await foodLib.addCatalogFoodToLibrary('chicken_breast');
        final copy = foodLib.libraryFoodFor('chicken_breast')!;

        await tester.pumpWidget(
          MaterialApp(
            home: EditFoodScreen(food: copy, foodLibraryState: foodLib),
          ),
        );
        await tester.pumpAndSettle();

        // Drive the form's own save callback directly: deterministic,
        // no typing, no blur.
        final form = tester.widget<FoodForm>(find.byType(FoodForm));
        final draft = FoodDraft(
          name: 'Screen edit 77',
          groupId: copy.groupId,
          unitType: copy.unitType,
          referenceAmount: copy.referenceAmount,
          referenceLabel: copy.referenceLabel,
          protein: 88,
          carbs: copy.carbs,
          fiber: copy.fiber,
          fat: copy.fat,
          sodium: copy.sodium,
          notes: copy.notes,
          imagePath: copy.imagePath,
        );
        final ok = await form.onSave(draft);
        expect(ok, isTrue);

        // The library copy has the draft's values...
        final edited = foodLib.libraryFoodFor('chicken_breast')!;
        expect(edited.name, 'Screen edit 77');
        expect(edited.protein, 88);
        // ...and the shipped catalog row is untouched.
        final catalogAfterEdit = await repo.getCatalogFoodById(
          'chicken_breast',
        );
        expect(catalogAfterEdit!.name, shipped.name);
        expect(catalogAfterEdit.protein, shipped.protein);
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.foodCatalog,
            'chicken_breast',
          ),
          isFalse,
        );

        // onImageSave is wired to the same routing.
        final draft2 = FoodDraft(
          name: 'Image path edit 77',
          groupId: copy.groupId,
          unitType: copy.unitType,
          referenceAmount: copy.referenceAmount,
          referenceLabel: copy.referenceLabel,
          protein: 66,
          carbs: copy.carbs,
          fiber: copy.fiber,
          fat: copy.fat,
          sodium: copy.sodium,
          notes: copy.notes,
          imagePath: copy.imagePath,
        );
        final ok2 = await form.onImageSave!(draft2);
        expect(ok2, isTrue);
        final afterImage = foodLib.libraryFoodFor('chicken_breast')!;
        expect(afterImage.name, 'Image path edit 77');
        expect(afterImage.protein, 66);
      },
    );

    testWidgets(
      'S-12720: the Edit screen routes a user-created catalog food\'s '
      'save through updateCatalogFood (propagates to the library copy)',
      (tester) async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await foodLib.loadCatalogFoods();
        final id = await foodLib.createCatalogFood(
          const FoodDraft(
            name: 'Mine 77',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            protein: 10,
            carbs: 5,
            fiber: 0,
            fat: 2,
            sodium: null,
            notes: null,
            imagePath: null,
          ),
        );
        await foodLib.addCatalogFoodToLibrary(id);
        final catalogRow = foodLib.catalogFoods.firstWhere((f) => f.id == id);
        expect(catalogRow.isCatalog, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: EditFoodScreen(food: catalogRow, foodLibraryState: foodLib),
          ),
        );
        await tester.pumpAndSettle();

        // A user-created catalog food has no shipped original: no Reset.
        expect(find.byKey(const Key('food_reset_original')), findsNothing);

        final form = tester.widget<FoodForm>(find.byType(FoodForm));
        final draft = FoodDraft(
          name: 'Mine 77 edited',
          groupId: catalogRow.groupId,
          unitType: catalogRow.unitType,
          referenceAmount: catalogRow.referenceAmount,
          referenceLabel: catalogRow.referenceLabel,
          protein: 44,
          carbs: catalogRow.carbs,
          fiber: catalogRow.fiber,
          fat: catalogRow.fat,
          sodium: catalogRow.sodium,
          notes: catalogRow.notes,
          imagePath: catalogRow.imagePath,
        );
        final ok = await form.onSave(draft);
        expect(ok, isTrue);

        // The CATALOG row has the draft's values...
        final catalogAfter = await repo.getCatalogFoodById(id);
        expect(catalogAfter!.name, 'Mine 77 edited');
        expect(catalogAfter.protein, 44);
        // ...and the library copy was propagated (L-3).
        final libCopy = foodLib.libraryFoodFor(id)!;
        expect(libCopy.name, 'Mine 77 edited');
        expect(libCopy.protein, 44);
      },
    );
  });

  test('S-12716: source guard on _CatalogRowState', () async {
    final source = File('lib/features/nutrition/add_food_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('class _CatalogRowState');
    expect(start, isNot(-1), reason: '_CatalogRowState exists in the source');
    final nextClass = source.indexOf('\nclass ', start + 1);
    final slice = source.substring(
      start,
      nextClass == -1 ? source.length : nextClass,
    );
    expect(
      slice,
      contains('onTap: () => _onToggle(context),'),
      reason: 'S-12716: the row tap is the add/remove toggle',
    );
    expect(
      slice,
      contains('Icons.edit_outlined'),
      reason: 'S-12716: the pencil edit affordance is rendered',
    );
    expect(
      slice,
      contains('Icons.check_circle'),
      reason: 'S-12716: the in-list indicator is the check icon',
    );
    expect(
      slice,
      isNot(contains('Icons.delete_outline')),
      reason: 'S-12716: the trash button is gone from the catalog row',
    );
    expect(
      slice,
      isNot(contains('colorScheme.error')),
      reason: 'S-12716: the remove affordance is not red',
    );
  });
}
