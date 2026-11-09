// filepath: test/edit_food_save_test.dart
//
// S-92a.1..4 — Edit Food gets a bottom **Save** and the same unsaved-work
// guard New Food has (plan `2026-10-29-92a-edit-food-save-plan`).
//
// The rule these tests pin: nothing is written until Save is tapped, and a
// back path (header arrow) with edits asks "Unsaved changes" first. The
// form's text fields used to save on blur, so typing a name and leaving the
// field wrote the food without any confirmation.
//
// Plan 133 (133b2b): a default food's Save asks and then makes a food of
// the user's own (S-92a.7 built on the copy flow); S-92a.15 (Reset) is
// deleted with the Reset feature.
//
// Mock-only: the screen writes through `FoodLibraryState` on a
// `MockWorkoutRepository`; no Hive, no real file I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

const String _trailMixId = 'edit-food-trail-mix';
const String _orphanSnackId = 'edit-food-orphan';

/// The shipped catalog food the library-copy scenarios copy from.
const String _bundledId = 'chicken_breast';

/// A user-created catalog food (`isCatalog: true`) — the one kind of row
/// `EditFoodScreen` edits in place, with no shipped original behind it.
const Food _trailMix = Food(
  id: _trailMixId,
  name: 'Trail Mix',
  groupId: null,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: 12,
  carbs: 40,
  fiber: 4,
  fat: 18,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

typedef _Fixture = ({
  MockWorkoutRepository repo,
  FoodLibraryState foodLib,
  Food loaded,
});

/// Fixture for the library-copy scenarios: a bundled catalog food plus the
/// user's copy of it, edited so it differs from the shipped row (so Reset is
/// offered, S-92a.15).
typedef _CopyFixture = ({
  MockWorkoutRepository repo,
  FoodLibraryState foodLib,
  Food copy,
  Food shipped,
});

/// A user-created catalog food whose category no longer exists (S-92a.13).
const Food _orphanSnack = Food(
  id: _orphanSnackId,
  name: 'Orphan Snack',
  groupId: 'g-gone',
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: 3,
  carbs: 12,
  fiber: 1,
  fat: 2,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

Future<_Fixture> _seedCatalog(Food seed) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.seedCatalogFood(seed);
  final foodLib = FoodLibraryState(repo);
  await foodLib.loadCatalogFoods();
  final loaded = foodLib.catalogFoods.firstWhere((f) => f.id == seed.id);
  return (repo: repo, foodLib: foodLib, loaded: loaded);
}

Future<_Fixture> _seedTrailMix() => _seedCatalog(_trailMix);

/// Sets the stored library copy's values directly (the copy the user
/// edited before plan 133). The old `FoodLibraryState.editLibraryFood`
/// write path is deleted; plan 133 made a default food's Save create a
/// food of the user's own instead.
Future<void> seedEditedCopy(
  MockWorkoutRepository repo,
  FoodLibraryState foodLib,
  String catalogId, {
  required String name,
  double? protein,
}) async {
  final copy = foodLib.libraryFoodFor(catalogId)!;
  await repo.updateFood(
    copy.copyWith(name: name, protein: protein ?? copy.protein),
  );
  await foodLib.loadFoods();
}

Future<_CopyFixture> _seedEditedLibraryCopy() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final foodLib = FoodLibraryState(repo);
  await foodLib.loadCatalogFoods();
  final shipped = (await repo.getCatalogFoodById(_bundledId))!;
  await foodLib.addCatalogFoodToLibrary(_bundledId);
  await seedEditedCopy(
    repo,
    foodLib,
    _bundledId,
    name: 'My ${shipped.name}',
  );
  return (
    repo: repo,
    foodLib: foodLib,
    copy: foodLib.libraryFoodFor(_bundledId)!,
    shipped: shipped,
  );
}

/// Pushes [EditFoodScreen] from a host route, so a pop lands back on a real
/// screen and `find.byType(EditFoodScreen)` tells us whether it is open.
class _Host extends StatelessWidget {
  const _Host({
    required this.food,
    required this.foodLibraryState,
    this.nutritionState,
  });

  final Food food;
  final FoodLibraryState foodLibraryState;
  final NutritionState? nutritionState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditFoodScreen(
                food: food,
                foodLibraryState: foodLibraryState,
                nutritionState: nutritionState,
              ),
            ),
          ),
          child: const Text('open editor'),
        ),
      ),
    );
  }
}

Future<void> _openEditorFor(
  WidgetTester tester, {
  required Food food,
  required FoodLibraryState foodLib,
  NutritionState? nutritionState,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      // A fresh key each call so a second editor in the same test gets a new
      // Navigator instead of reusing the previous route stack.
      key: UniqueKey(),
      home: _Host(
        food: food,
        foodLibraryState: foodLib,
        nutritionState: nutritionState,
      ),
    ),
  );
  await tester.tap(find.text('open editor'));
  await tester.pumpAndSettle();
  expect(find.byType(EditFoodScreen), findsOneWidget);
}

Future<void> _openEditor(WidgetTester tester, _Fixture setup) =>
    _openEditorFor(tester, food: setup.loaded, foodLib: setup.foodLib);

/// Taps the bottom Save and waits (real time, bounded) for the Mock's async
/// write to land and the screen to pop, then settles the frames.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('food_form_save')));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (find.byType(EditFoodScreen).evaluate().isEmpty) break;
    }
  });
  await tester.pumpAndSettle();
}

/// Changes the form's name field.
Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('food_form_name')), name);
  await tester.pump();
}

/// The stored name after a short real-time settle window, so an instant
/// write (blur save) has room to land before a "nothing was written"
/// assertion. No fixed sleep: the window ends as soon as the value shows up.
Future<String?> _storedNameAfterSettle(
  MockWorkoutRepository repo, [
  Duration window = const Duration(seconds: 1),
]) async {
  final deadline = DateTime.now().add(window);
  var name = (await repo.getCatalogFoodById(_trailMixId))?.name;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    name = (await repo.getCatalogFoodById(_trailMixId))?.name;
  }
  return name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S-92a.1: Save writes the edited food and closes the screen', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    expect(
      find.byKey(const Key('food_form_save')),
      findsOneWidget,
      reason: 'Edit Food must offer the bottom Save (D-92a.1)',
    );

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Trail Mix 2',
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('food_form_save')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        if ((await setup.repo.getCatalogFoodById(_trailMixId))?.name ==
            'Trail Mix 2') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix 2',
      reason: 'Save must write the edited name through updateCatalogFood',
    );
    expect(
      find.byType(EditFoodScreen),
      findsNothing,
      reason: 'Save closes the screen after a successful write',
    );
  });

  testWidgets('S-92a.2: focus leaving the form writes nothing', (tester) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Trail Mix 2',
    );
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final stored = await tester.runAsync(
      () => _storedNameAfterSettle(setup.repo),
    );
    expect(
      stored,
      'Trail Mix',
      reason: 'blur must not save; only the Save button writes (D-92a.3)',
    );
    expect(
      find.byType(EditFoodScreen),
      findsOneWidget,
      reason: 'a blur is not an exit; the editor stays open',
    );
  });

  testWidgets(
    'S-92a.3: back with edits asks; Discard drops them and Keep editing stays',
    (tester) async {
      final setup = await _seedTrailMix();
      await _openEditor(tester, setup);

      // Discard leg.
      await tester.enterText(
        find.byKey(const Key('food_form_name')),
        'Trail Mix 2',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('Unsaved changes'),
        findsOneWidget,
        reason: 'an edited form must ask before it closes',
      );
      await tester.tap(find.byKey(const Key('edit-food-unsaved-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(EditFoodScreen), findsNothing);
      expect(
        (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
        'Trail Mix',
        reason: 'Discard must leave the stored food alone',
      );

      // Keep-editing leg.
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('food_form_name')),
        'Trail Mix 3',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-food-unsaved-keep')));
      await tester.pumpAndSettle();
      expect(
        find.byType(EditFoodScreen),
        findsOneWidget,
        reason: 'Keep editing must leave the editor open',
      );
      expect(
        find.text('Trail Mix 3'),
        findsOneWidget,
        reason: 'Keep editing must preserve the typed name',
      );
      expect(
        (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
        'Trail Mix',
        reason: 'Keep editing must not write either',
      );
    },
  );

  testWidgets('S-92a.4: back on an untouched form closes with no dialog', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason: 'an untouched form has nothing to discard',
    );
    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix',
    );
  });

  testWidgets(
    'S-92a.7: a default food\'s Save asks and makes a food of your own',
    (tester) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final nutritionState = NutritionState(repo);
      final foodLib = FoodLibraryState(repo);
      await foodLib.loadCatalogFoods();
      await foodLib.addCatalogFoodToLibrary(_bundledId);
      final copy = foodLib.libraryFoodFor(_bundledId)!;
      final shipped = (await repo.getCatalogFoodById(_bundledId))!;

      await _openEditorFor(
        tester,
        food: copy,
        foodLib: foodLib,
        nutritionState: nutritionState,
      );
      await _typeName(tester, 'Chicken breast, mine');
      await tester.tap(find.byKey(const Key('food_form_save')));
      await tester.pumpAndSettle();
      expect(find.byType(EditFoodScreen), findsOneWidget);

      // Save on a default food asks first; Confirm makes a food of
      // the user's own (the library flow, plan 133).
      expect(find.text('Save as your own food?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('food-copy-confirm')));
      await tester.pumpAndSettle();

      expect(
        foodLib.libraryFoodFor(_bundledId),
        isNull,
        reason: 'the Confirm swap removes the replaced library copy',
      );
      final ownRow = foodLib.catalogFoods.firstWhere(
        (f) => f.name == 'Chicken breast, mine',
      );
      expect(ownRow.isCatalog, isTrue);
      expect(
        foodLib.foods.where((f) => f.name == 'Chicken breast, mine'),
        isNotEmpty,
        reason: 'the old copy was in the list, so the new food replaces it',
      );

      final shippedAfter = (await repo.getCatalogFoodById(_bundledId))!;
      expect(
        shippedAfter.name,
        shipped.name,
        reason:
            'the shipped catalog row must never be altered by the copy flow',
      );
      expect(shippedAfter.protein, shipped.protein);
      expect(
        await repo.isSeedEntryTouched(SeedEntryType.foodCatalog, _bundledId),
        isFalse,
        reason: 'the copy flow must not mark the shipped entry user-touched',
      );
      expect(find.byType(EditFoodScreen), findsNothing);
    },
  );

  testWidgets(
    'S-92a.9: a default food\'s editor has no secondary button, Delete '
    'stays above Save',
    (tester) async {
      // A library copy of a bundled food is a default food: no Reset
      // (plan 133 D-13317) and no Delete (not the user's own).
      final copyFixture = await _seedEditedLibraryCopy();
      await _openEditorFor(
        tester,
        food: copyFixture.copy,
        foodLib: copyFixture.foodLib,
      );
      expect(
        find.byKey(const Key('food_reset_original')),
        findsNothing,
        reason: 'plan 133 removed Reset to original',
      );
      expect(
        find.byKey(const Key('food_delete_created')),
        findsNothing,
        reason: 'a default food is not the user\'s own',
      );

    final createdFixture = await _seedTrailMix();
    await _openEditorFor(
      tester,
      food: createdFixture.loaded,
      foodLib: createdFixture.foodLib,
      nutritionState: NutritionState(createdFixture.repo),
    );
    expect(
      find.byKey(const Key('food_delete_created')),
      findsOneWidget,
      reason: 'a user-created catalog food offers Delete',
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('food_delete_created'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('food_form_save'))).dy,
      ),
      reason: 'Delete sits in the footer, directly above Save',
    );
    expect(
      tester.getSize(find.byKey(const Key('food_delete_created'))),
      tester.getSize(find.byKey(const Key('food_form_save'))),
      reason: 'Delete food has the same height and width as Save',
    );
  });

  testWidgets('S-92a.11: Save with an empty name writes nothing and stays '
      'open', (tester) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await _typeName(tester, '');
    await tester.tap(find.byKey(const Key('food_form_save')));
    await tester.pump();

    expect(
      find.text('Name is required'),
      findsOneWidget,
      reason: 'validation must surface the inline name error',
    );
    expect(
      find.byType(EditFoodScreen),
      findsOneWidget,
      reason: 'a validation failure must not close the editor',
    );
    final stored = await tester.runAsync(
      () => _storedNameAfterSettle(setup.repo),
    );
    expect(
      stored,
      'Trail Mix',
      reason: 'validation failure must not write (D-92a.11)',
    );
  });

  testWidgets('S-92a.12: a second Save while saving writes once', (
    tester,
  ) async {
    final repo = _CountingCatalogRepo();
    await repo.initialize();
    await repo.seedCatalogFood(_trailMix);
    final foodLib = FoodLibraryState(repo);
    await foodLib.loadCatalogFoods();
    final loaded = foodLib.catalogFoods.firstWhere(
      (f) => f.id == _trailMixId,
    );

    await _openEditorFor(tester, food: loaded, foodLib: foodLib);
    await _typeName(tester, 'Trail Mix 2');

    final controller = tester
        .widget<FoodForm>(find.byType(FoodForm))
        .controller!;
    await tester.runAsync(() async {
      // No frame between the two submits: the first sets `_saving`
      // synchronously, so the second must be a no-op.
      controller.submit();
      controller.submit();
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (repo.catalogUpdates > 0) break;
      }
    });
    await tester.pumpAndSettle();

    expect(
      repo.catalogUpdates,
      1,
      reason: 'the _saving re-entry guard makes the second submit a no-op',
    );
    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      find.text('open editor'),
      findsOneWidget,
      reason: 'exactly one route popped (a double pop would remove the host)',
    );
  });

  testWidgets('S-92a.13: an orphan category survives Save', (tester) async {
    final setup = await _seedCatalog(_orphanSnack);
    await _openEditor(tester, setup);

    expect(
      find.text('g-gone (no longer available)'),
      findsOneWidget,
      reason: 'the dropdown must surface the orphaned category',
    );

    await _typeName(tester, 'Orphan Snack 2');
    await _tapSave(tester);

    final stored = (await setup.repo.getCatalogFoodById(_orphanSnackId))!;
    expect(stored.name, 'Orphan Snack 2');
    expect(
      stored.groupId,
      'g-gone',
      reason: 'Save must keep the stored groupId, not silently regroup',
    );
    expect(find.byType(EditFoodScreen), findsNothing);
  });

  testWidgets('S-92a.14: system back routes through the guard', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);
    await _typeName(tester, 'Trail Mix 2');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.text('Unsaved changes'),
      findsOneWidget,
      reason: 'system back on an edited form must ask first',
    );
    expect(find.byKey(const Key('edit-food-unsaved-keep')), findsOneWidget);
    expect(find.byKey(const Key('edit-food-unsaved-discard')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-food-unsaved-discard')));
    await tester.pumpAndSettle();

    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix',
      reason: 'Discard from system back must not write',
    );
  });

  // S-92a.15 (Reset pops through unsaved edits) is deleted with the
  // Reset feature in plan 133 (D-13317).

  testWidgets('S-92a.16: Delete pops through unsaved edits with no dialog', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    final nutrition = NutritionState(setup.repo);
    await _openEditorFor(
      tester,
      food: setup.loaded,
      foodLib: setup.foodLib,
      nutritionState: nutrition,
    );

    await _typeName(tester, 'Trail Mix 2');
    await tester.tap(find.byKey(const Key('food_delete_created')));
    await tester.pumpAndSettle();

    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason: 'Delete confirms its own destructive action (D-92a.14)',
    );
    expect(find.text('Delete Trail Mix?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('food-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason: 'Delete must pop directly, not through the exit guard',
    );
    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      await setup.repo.getCatalogFoodById(_trailMixId),
      isNull,
      reason: 'the confirmed delete removes the food',
    );
  });

  testWidgets('S-92a.17: a failed save keeps the form and the guard', (
    tester,
  ) async {
    final repo = _FailingCatalogRepo();
    await repo.initialize();
    await repo.seedCatalogFood(_trailMix);
    final foodLib = FoodLibraryState(repo);
    await foodLib.loadCatalogFoods();
    final loaded = foodLib.catalogFoods.firstWhere(
      (f) => f.id == _trailMixId,
    );

    await _openEditorFor(tester, food: loaded, foodLib: foodLib);
    await _typeName(tester, 'Trail Mix 2');

    await tester.tap(find.byKey(const Key('food_form_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Could not save food'),
      findsOneWidget,
      reason: 'a failed write surfaces the shared error message (D-92a.10)',
    );
    expect(
      find.byType(EditFoodScreen),
      findsOneWidget,
      reason: 'a failed save must not close the editor',
    );
    final stored = await tester.runAsync(
      () => _storedNameAfterSettle(repo),
    );
    expect(stored, 'Trail Mix');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('Unsaved changes'),
      findsOneWidget,
      reason: 'the edits are still dirty after a failed save',
    );
  });

  testWidgets('S-92a.18: Save pops without the guard', (tester) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await _typeName(tester, 'Trail Mix 2');
    await tester.tap(find.byKey(const Key('food_form_save')));
    await tester.pump();

    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason: 'Save is not routed through the exit guard (D-92a.15)',
    );

    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix 2',
    );
  });
}

/// Counts catalog writes so the double-tap guard is observable (S-92a.12).
class _CountingCatalogRepo extends MockWorkoutRepository {
  int catalogUpdates = 0;

  @override
  Future<void> updateCatalogFood(Food food) async {
    catalogUpdates++;
    await super.updateCatalogFood(food);
  }
}

/// Fails every catalog write (S-92a.17).
class _FailingCatalogRepo extends MockWorkoutRepository {
  @override
  Future<void> updateCatalogFood(Food food) async {
    throw StateError('catalog write failed');
  }
}
