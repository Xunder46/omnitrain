// Widget-level tests for editing a default food (plan 133, scenarios
// S-13310..S-13316, S-13318..S-13320, S-13327, S-13328): the pencil on
// every Library row, the copy flow (Save asks `Save as your own food?`
// and, on Confirm, makes a food of the user's own) and the carried
// today-log.
//
// Mock only, plain widget tests; all state operations run on a
// `MockWorkoutRepository` like `test/library_row_toggle_test.dart`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

const String _bundledId = 'chicken_breast';
const String _shippedName = 'Chicken breast, skinless';
const String _newName = 'Zed 133 bird';
const String _newProteinText = '31.5';

/// The exact dialog body the helper shows for the untouched bundled name.
String _copyDialogBody(String defaultName) =>
    '$defaultName is a default food and stays as it is. Saving creates '
    'a new food of your own, with its photo copied.';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log (same rationale as library_row_toggle_test.dart).
  repo.clearConsumedFoodsForTest();
  return repo;
}

typedef _TestStates = ({NutritionState nutrition, FoodLibraryState foodLib});

Future<_TestStates> _pumpCatalogTab(
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

/// The S-13312 flow on the seeded bundled default: open its pencil from
/// the Library, edit name + protein, Save, Confirm. Returns the states
/// and the new catalog row id.
class _OwnCopyResult {
  _OwnCopyResult(this.nutrition, this.foodLib, this.newCatalogId);

  final NutritionState nutrition;
  final FoodLibraryState foodLib;
  final String newCatalogId;
}

Future<_OwnCopyResult> _createOwnCopyNotInList(WidgetTester tester) async {
  final repo = await _freshRepo();
  // Seed the bundled row's catalog cache before the screen pumps so the
  // state ops below see it.
  await repo.getCatalogFoodById(_bundledId);
  final states = await _pumpCatalogTab(tester, repo: repo);
  final foodLib = states.foodLib;
  await foodLib.loadCatalogFoods();
  final before = foodLib.catalogFoods.length;

  await tester.tap(find.byKey(const Key('edit_catalog_food_$_bundledId')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('food_form_name')),
    _newName,
  );
  await tester.enterText(
    find.byKey(const Key('food_form_protein')),
    _newProteinText,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('food_form_save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('food-copy-confirm')));
  await tester.pumpAndSettle();

  final newRow = foodLib.catalogFoods.firstWhere(
    (f) => f.name == _newName,
  );
  expect(foodLib.catalogFoods.length, before + 1);
  return _OwnCopyResult(states.nutrition, foodLib, newRow.id);
}

void main() {
  group('Edit a default food (plan 133)', () {
    testWidgets(
      'S-13310 the pencil shows on a not-in-list default row and opens '
      'the editor on it',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        await states.foodLib.loadCatalogFoods();
        // Precondition: the bundled default is NOT in Foods I Eat.
        expect(
          states.foodLib.libraryFoodFor(_bundledId),
          isNull,
          reason: 'precondition: the default is not in the list',
        );

        expect(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);
        final edit = tester.widget<EditFoodScreen>(
          find.byType(EditFoodScreen),
        );
        expect(edit.food.id, _bundledId);

        // The pencil must not have toggled the row.
        expect(
          states.foodLib.libraryFoodFor(_bundledId),
          isNull,
        );
      },
    );

    testWidgets(
      'S-13311 Save on an edited default asks first; Cancel writes '
      'nothing; an untouched form pops with no dialog',
      (tester) async {
        // Cancel leg.
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();
        final rowsBefore = foodLib.catalogFoods.length;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        expect(find.text('Save as your own food?'), findsOneWidget);
        expect(
          find.text(_copyDialogBody(_shippedName)),
          findsOneWidget,
          reason: 'the body names the default\'s own shipped name',
        );

        await tester.tap(find.byKey(const Key('food-copy-cancel')));
        await tester.pumpAndSettle();

        // The editor is still open and nothing was written.
        expect(find.text('Edit Food'), findsOneWidget);
        expect(foodLib.catalogFoods.length, rowsBefore);
        expect(foodLib.libraryFoodFor(_bundledId), isNull);
      },
    );

    testWidgets(
      'S-13335 switching only the serving type, in either direction, makes '
      'Save ask and a Confirm creates a food of the user\'s own with that '
      'serving',
      (tester) async {
        final repo = await _freshRepo();
        await repo.getCatalogFoodById(_bundledId);
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();
        final before = foodLib.catalogFoods.length;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        // Nothing is typed: only the "Nutrition facts are per" toggle moves.
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'slice',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        expect(find.text('Save as your own food?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(foodLib.catalogFoods.length, before + 1);
      },
    );

    testWidgets(
      'S-13335 (toggle only, no other edit) a switch between the 100 g and '
      '100 ml segments alone makes Save ask',
      (tester) async {
        final repo = await _freshRepo();
        await repo.getCatalogFoodById(_bundledId);
        await _pumpCatalogTab(tester, repo: repo, searchFor: 'Chicken breast');

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        expect(find.text('Save as your own food?'), findsOneWidget);
      },
    );

    testWidgets(
      'S-13311 (untouched form) Save pops with no dialog',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();
        final rowsBefore = foodLib.catalogFoods.length;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        expect(find.byType(EditFoodScreen), findsNothing);
        expect(find.text('Save as your own food?'), findsNothing);
        // Nothing was created: an untouched default makes no copy.
        expect(foodLib.catalogFoods.length, rowsBefore);
        expect(foodLib.libraryFoodFor(_bundledId), isNull);
      },
    );

    testWidgets('S-13328 Cancel shows no error snackbar', (tester) async {
      final repo = await _freshRepo();
      final states = await _pumpCatalogTab(
        tester,
        repo: repo,
        searchFor: 'Chicken breast',
      );
      await states.foodLib.loadCatalogFoods();

      await tester.tap(
        find.byKey(const Key('edit_catalog_food_$_bundledId')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('food_form_name')),
        _newName,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('food_form_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('food-copy-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Could not save food'), findsNothing);
      expect(find.byType(EditFoodScreen), findsOneWidget);
    });

    testWidgets(
      'S-13312 Confirm makes a food of your own, not added to the list',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();
        final shipped = (await repo.getCatalogFoodById(_bundledId))!;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          _newProteinText,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();

        // The editor popped.
        expect(find.byType(EditFoodScreen), findsNothing);

        // A catalog row of the user's own.
        final row = foodLib.catalogFoods.firstWhere(
          (f) => f.name == _newName,
        );
        expect(row.isCatalog, isTrue);
        expect(row.protein, 31.5);
        expect(foodLib.isDefaultFood(row), isFalse);
        // Not in Foods I Eat.
        expect(foodLib.libraryFoodFor(row.id), isNull);

        // The bundled default is untouched.
        final after = (await repo.getCatalogFoodById(_bundledId))!;
        expect(after.name, shipped.name);
        expect(after.protein, shipped.protein);
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.foodCatalog,
            _bundledId,
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'S-13313 Confirm on an in-list logged default replaces it and '
      'carries today\'s amount',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;
        await states.nutrition.loadNutritionTarget();
        await states.nutrition.logConsumedFoodAt(oldCopy, 150);
        expect(
          states.nutrition.isFoodLoggedToday(oldCopy.id),
          isTrue,
          reason: 'precondition: today is logged at 150',
        );

        // Open the editor from the Library pencil: it opens on the copy.
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          _newProteinText,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);

        // The old copy is gone from Foods I Eat; a library row with the
        // new name exists.
        expect(
          foodLib.foods.where((f) => f.id == oldCopy.id),
          isEmpty,
        );
        final newRow = foodLib.foods.firstWhere((f) => f.name == _newName);
        expect(newRow.id, isNot(oldCopy.id));

        // Today's amount carried over to the new row.
        expect(states.nutrition.isFoodLoggedToday(oldCopy.id), isFalse);
        expect(states.nutrition.isFoodLoggedToday(newRow.id), isTrue);
        expect(
          states.nutrition.findLoggedTodayForFood(newRow.id)!.amountConsumed,
          150,
        );
        // The shipped reference is 100 g (see the seed fixture), new
        // protein 31.5 at 150 g; `todayConsumedProtein` is an int.
        expect(
          states.nutrition.todayConsumedProtein,
          (31.5 * 150 / 100).round(),
        );

        // The bundled default row offers Add again.
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Chicken breast',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('add_catalog_food_$_bundledId')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'S-13319 Cancel on the dialog leaves the log alone',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;
        await states.nutrition.loadNutritionTarget();
        await states.nutrition.logConsumedFoodAt(oldCopy, 150);

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-cancel')));
        await tester.pumpAndSettle();

        // Nothing changed: the copy is still in the list, the log is
        // still today at 150.
        expect(foodLib.libraryFoodFor(_bundledId), isNotNull);
        expect(
          states.nutrition.findLoggedTodayForFood(oldCopy.id)!.amountConsumed,
          150,
        );
      },
    );

    testWidgets(
      'S-13327 a failed swap keeps today\'s log',
      (tester) async {
        final repo = _FailingCreateRepo();
        await repo.initialize();
        repo.clearConsumedFoodsForTest();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;
        await states.nutrition.loadNutritionTarget();
        await states.nutrition.logConsumedFoodAt(oldCopy, 150);

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();

        // The form's own error, once, and the editor stays open.
        expect(find.text('Could not save food'), findsOneWidget);
        expect(find.byType(EditFoodScreen), findsOneWidget);

        // The old copy row is still in the list, still logged at 150.
        expect(foodLib.libraryFoodFor(_bundledId), isNotNull);
        expect(states.nutrition.isFoodLoggedToday(oldCopy.id), isTrue);
        expect(
          states.nutrition.findLoggedTodayForFood(oldCopy.id)!.amountConsumed,
          150,
        );
      },
    );

    testWidgets(
      'S-13315 a food of your own saves with no dialog',
      (tester) async {
        final created = await _createOwnCopyNotInList(tester);
        final foodLib = created.foodLib;
        final newId = created.newCatalogId;

        // Open the new food's pencil.
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Zed 133',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit_catalog_food_$newId')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'Zed 133 bird two',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        // No rename dialog: the editor pops straight away.
        expect(find.text('Save as your own food?'), findsNothing);
        expect(find.byType(EditFoodScreen), findsNothing);
        final row = foodLib.catalogFoods.firstWhere(
          (f) => f.id == newId,
        );
        expect(row.name, 'Zed 133 bird two');
      },
    );

    testWidgets(
      'S-13316 no Reset button; Delete food only for a food of your own',
      (tester) async {
        // An already-edited library copy (a copy the user edited before
        // plan 133) is an ordinary row: its editor has no Reset and no
        // Delete.
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();
        await foodLib.addCatalogFoodToLibrary(_bundledId);
        final copy = foodLib.libraryFoodFor(_bundledId)!;
        await repo.updateFood(copy.copyWith(name: 'Old edit'));
        await foodLib.loadFoods();
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsOneWidget);
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
        expect(find.text('Reset to original'), findsNothing);
        expect(
          find.byKey(const Key('food_delete_created')),
          findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Then do the S-13312 flow: Confirm makes a food of the user's
        // own, and its editor shows Delete food.
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);

        final own = states.foodLib.catalogFoods.firstWhere(
          (f) => f.name == _newName,
        );
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Zed 133',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit_catalog_food_${own.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsOneWidget);
        expect(
          find.byKey(const Key('food_delete_created')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('food_reset_original')), findsNothing);
      },
    );

    testWidgets(
      'S-13320 after the swap the default and the new food are both '
      'listed',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);
        final newCatalogId = foodLib
            .catalogFoods
            .firstWhere((f) => f.name == _newName)
            .id;
        expect(foodLib.libraryFoodFor(_bundledId), isNull);
        expect(oldCopy, isNotNull);

        // The bundled default is listed again, with its Add button.
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Chicken breast',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('add_catalog_food_$_bundledId')),
          findsOneWidget,
        );
        expect(find.text(_shippedName), findsOneWidget);

        // The new food is listed too, Yours and in the list.
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Zed 133',
        );
        await tester.pumpAndSettle();
        expect(find.text(_newName), findsOneWidget);
        expect(
          find.byKey(Key('yours_tag_$newCatalogId')),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('remove_catalog_food_$newCatalogId')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'S-13321 an in-list default that is not logged swaps without '
      'touching the log',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;
        await states.nutrition.loadNutritionTarget();
        expect(
          states.nutrition.isFoodLoggedToday(oldCopy.id),
          isFalse,
          reason: 'precondition: the copy is in the list but not logged',
        );

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          _newProteinText,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);

        // The old copy is gone; a library row with the new name exists.
        expect(foodLib.foods.where((f) => f.id == oldCopy.id), isEmpty);
        final newRow = foodLib.foods.firstWhere(
          (f) => f.name == _newName,
        );
        expect(newRow.id, isNot(oldCopy.id));

        // Nothing is logged, so the log was not touched.
        await states.nutrition.loadNutritionTarget();
        expect(states.nutrition.isFoodLoggedToday(newRow.id), isFalse);
        expect(states.nutrition.todayConsumedProtein, 0);
      },
    );

    testWidgets(
      'S-13326 an archived copy is treated as not in the list',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        final oldCopyId = await foodLib.addCatalogFoodToLibrary(_bundledId);
        await repo.updateFood(
          (await repo.getFoodById(oldCopyId))!.copyWith(isArchived: true),
        );
        await foodLib.loadFoods();
        await tester.pumpAndSettle();
        // The archived copy no longer counts as in the list.
        expect(foodLib.libraryFoodFor(_bundledId), isNull);

        // The bundled row's pencil therefore opens on the bundled row
        // and the save writes a new food of the user's own, not added.
        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);

        // A catalog row of the user's own exists; no library row.
        final newCatalogId = foodLib.catalogFoods
            .firstWhere((f) => f.name == _newName)
            .id;
        expect(foodLib.libraryFoodFor(newCatalogId), isNull);

        // The archived copy is untouched in the repository.
        final archived = (await repo.getFoodById(oldCopyId))!;
        expect(archived.isArchived, isTrue);
        expect(archived.name, _shippedName);
      },
    );

    testWidgets(
      'S-13331 an older value-matched copy opens the editor on the '
      'bundled row and still asks',
      (tester) async {
        final repo = await _freshRepo();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        // A legacy value-matched copy: the bundled row's own values,
        // but no durable `catalogId`.
        // ignore: deprecated_member_use_from_same_package
        final legacyId = await foodLib.createCustomFood(
          name: _shippedName,
          groupId: 'food-group-proteins',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fiber: 0,
          fat: 3.6,
          sodium: 74,
        );
        await tester.pumpAndSettle();
        expect(
          foodLib.libraryIdFor(_bundledId),
          legacyId,
          reason: 'precondition: the value-matched row is found',
        );

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        // The editor opens on the BUNDLED row, not on the legacy row.
        final edit = tester.widget<EditFoodScreen>(
          find.byType(EditFoodScreen),
        );
        expect(edit.food.id, _bundledId);
        expect(edit.food.catalogId, isNull);

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        // The copy flow still asks.
        expect(find.text('Save as your own food?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditFoodScreen), findsNothing);

        // The legacy row was replaced, not edited in place.
        expect(foodLib.foods.any((f) => f.id == legacyId), isFalse);
        expect(
          foodLib.foods.where((f) => f.name == _newName).length,
          1,
        );
      },
    );

    testWidgets(
      'S-13334 a failed add keeps today\'s log and the old copy',
      (tester) async {
        final repo = _FailingAddRepo();
        await repo.initialize();
        repo.clearConsumedFoodsForTest();
        final states = await _pumpCatalogTab(
          tester,
          repo: repo,
          searchFor: 'Chicken breast',
        );
        final foodLib = states.foodLib;
        await foodLib.loadCatalogFoods();

        await foodLib.addCatalogFoodToLibrary(_bundledId);
        await tester.pumpAndSettle();
        final oldCopy = foodLib.libraryFoodFor(_bundledId)!;
        await states.nutrition.loadNutritionTarget();
        await states.nutrition.logConsumedFoodAt(oldCopy, 150);

        // Failures start only here: the setup add ran on the passing
        // implementation.
        repo.failAdd = true;

        await tester.tap(
          find.byKey(const Key('edit_catalog_food_$_bundledId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          _newName,
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food-copy-confirm')));
        await tester.pumpAndSettle();

        // The form's own error, once, and the editor stays open.
        expect(find.text('Could not save food'), findsOneWidget);
        expect(find.byType(EditFoodScreen), findsOneWidget);

        // The old copy row is still in the list, still logged at 150.
        expect(foodLib.foods.any((f) => f.id == oldCopy.id), isTrue);
        expect(states.nutrition.isFoodLoggedToday(oldCopy.id), isTrue);
        expect(
          states.nutrition.findLoggedTodayForFood(oldCopy.id)!.amountConsumed,
          150,
        );
      },
    );
  });

  test('S-13318 source guards pin the copy flow', () {
    final editSource = File(
      'lib/features/nutrition/edit_food_screen.dart',
    ).readAsStringSync();
    expect(editSource, contains('isDefaultFood'));
    expect(editSource, contains('confirmSaveAsOwnFood'));
    expect(editSource, isNot(contains('editLibraryFood')));
    expect(editSource, isNot(contains('food_reset_original')));

    final addSource = File(
      'lib/features/nutrition/add_food_screen.dart',
    ).readAsStringSync();
    expect(addSource, isNot(contains('if (inList || isYours)')));
    expect(
      addSource,
      isNot(contains('if (bundled && copy == null) return;')),
    );

    final helperSource = File(
      'lib/features/nutrition/widgets/save_default_as_own_food.dart',
    ).readAsStringSync();
    expect(helperSource, contains('food-copy-confirm'));
  });
}

/// S-13327: every `createCatalogFood` write fails (Mock subclass built
/// like `_freshRepo` builds one, plus the cleared day-log).
class _FailingCreateRepo extends MockWorkoutRepository {
  @override
  Future<String> createCatalogFood(Food food) async {
    throw StateError('catalog create failed');
  }
}

/// S-13334: fails ONLY once [failAdd] is set, so the fixture's own
/// setup `addCatalogFoodToLibrary` still succeeds.
class _FailingAddRepo extends MockWorkoutRepository {
  bool failAdd = false;

  @override
  Future<String> addCatalogFoodToLibrary(String catalogFoodId) async {
    if (failAdd) {
      throw StateError('library add failed (S-13334)');
    }
    return super.addCatalogFoodToLibrary(catalogFoodId);
  }
}
