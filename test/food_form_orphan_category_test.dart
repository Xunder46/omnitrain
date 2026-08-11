// filepath: test/food_form_orphan_category_test.dart
//
// Regression tests for the **Edit Food must not crash when its
// category is gone** bug.
//
// Symptom (reported by the user): opening a food for editing
// crashes the app when that food's `groupId` is no longer in the
// active category list. The crash is a full-page error that
// requires a force-quit. It currently reproduces on any dairy
// food because the **Dairy** category can be deleted (or never
// created at first launch) and bundled catalog foods in
// **Dairy** (Milk, Cheese, Yogurt, etc.) all carry
// `groupId: 'food-group-dairy'`.
//
// Root cause: the form's
// `DropdownButtonFormField<String?>(initialValue: _groupId)`
// for the category field throws a `FlutterError` ("There should
// be exactly one item with [DropdownButton]'s value: ...") when
// the items list (active groups + the Ungrouped null entry) does
// not contain an item with `value == _groupId`. The form has
// always assumed every food's `groupId` is present in the active
// list, so the assumption breaks when:
//   * the user deleted the category, OR
//   * the user pre-created their own category with the same
//     name and the default-seeding pass skipped creating ours.
//
// Fix: the form's items list now synthesises a selectable item
// for the food's stored `groupId` when that id is not in the
// active list. The item is labelled with a "(no longer
// available)" suffix for ids missing from the *full* group cache
// (deletion) or "(archived)" for ids whose `FoodGroup.isArchived`
// is true. Both render with `OmniTheme.colors.textMuted`. The
// dropdown's `initialValue` stays `_groupId`, so the
// synthesised item is the selected value on open.
//
// Saving the form without touching the dropdown must persist the
// stored `groupId` byte-identical (no silent defaulting to
// "Ungrouped"). Saving after picking an active category must
// persist the new `groupId` (the existing
// `FoodLibraryState.updateCatalogFood` path).
//
// The crash only affects the editor path because the **+ New
// Item** form starts with `_groupId = null` (always present in
// the items list as the "Ungrouped" entry). All existing tests
// construct foods with `groupId: null` or `groupId` equal to an
// active id, so they pass regardless of this defect — they were
// not evidence that the form handles orphan categories
// correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';

/// Standard tall surface for the food form (image tile + 9 fields).
const _formSurface = Size(420, 1800);

/// Standard catalog food builder used by every test below.
Food _catalogFood({
  required String id,
  String name = 'Test Food',
  String? groupId,
}) {
  return Food(
    id: id,
    name: name,
    groupId: groupId,
    unitType: FoodUnitType.grams,
    referenceAmount: 100,
    referenceLabel: 'g',
    isCatalog: true,
    protein: 10,
    carbs: 5,
    fiber: 0,
    fat: 1,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

Future<(MockWorkoutRepository, FoodLibraryState)> _setupState() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = FoodLibraryState(repo);
  await state.loadCatalogFoods();
  await state.loadFoodGroups();
  return (repo, state);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── S-001: missing category ──────────────────────────────────────────

  group('FoodForm: orphan category (S-001 / S-002)', () {
    testWidgets(
      'builds successfully when the food\'s groupId is not in '
      'the active list (S-001)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        // Seed a catalog food whose groupId is the seeded
        // `food-group-dairy`, then archive that group so the
        // active list no longer contains it. The food's
        // `groupId` remains `food-group-dairy`, so the
        // dropdown's `initialValue` is a stale id.
        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-orphan-dairy',
            name: 'Milk, whole',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-orphan-dairy');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: state,
                onSave: (_) async => true,
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No `FlutterError` from the dropdown — the form is on
        // screen. We assert this by ensuring the form's name
        // field rendered.
        expect(find.byKey(const Key('food_form_name')), findsOneWidget);
        expect(find.byKey(const Key('food_form_group')), findsOneWidget);

        // The food's stored groupId is still 'food-group-dairy'
        // — the form's selected value must reflect that even
        // though the active list does not contain it.
        // The dropdown button text is the synthesised item
        // label; the test asserts the label includes the
        // "(no longer available)" hint OR an "(archived)"
        // hint, depending on whether the group is still in
        // the full cache. The selected value's label is
        // rendered inside the inner DropdownButton, so we
        // locate it by walking the widget tree from the
        // outer DropdownButtonFormField.
        final dropdown = tester.widget<DropdownButtonFormField<String?>>(
          find.byKey(const Key('food_form_group')),
        );
        expect(dropdown.initialValue, 'food-group-dairy');
        // The selected Text appears inside the inner
        // DropdownButton; locate it under the form key.
        final innerButtonFinder = find.descendant(
          of: find.byKey(const Key('food_form_group')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains('Dairy'),
          ),
        );
        expect(innerButtonFinder, findsOneWidget,
            reason: 'synthesised item must still surface the group name');
        // Distinguish-from-active check: the label must
        // contain either "(no longer available)" or
        // "(archived)".
        final labelWidget =
            tester.widget<Text>(innerButtonFinder);
        final label = labelWidget.data!;
        expect(
          label.contains('no longer available') ||
              label.contains('archived'),
          isTrue,
          reason: 'synthesised item must distinguish itself from active '
              'categories so the user sees the category is not in '
              'their active list',
        );
      },
    );

    testWidgets(
      'builds successfully when the food\'s groupId corresponds to '
      'an archived group (S-002)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-archived-cat',
            name: 'Yogurt',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-archived-cat');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: state,
                onSave: (_) async => true,
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No crash; the archived group's row is surfaced as the
        // selected value (still resolvable from the full cache).
        expect(find.byKey(const Key('food_form_name')), findsOneWidget);
        final dropdown = tester.widget<DropdownButtonFormField<String?>>(
          find.byKey(const Key('food_form_group')),
        );
        expect(dropdown.initialValue, 'food-group-dairy');
        final labelFinder = find.descendant(
          of: find.byKey(const Key('food_form_group')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains('archived'),
          ),
        );
        expect(labelFinder, findsOneWidget,
            reason: 'archived item must surface an "(archived)" hint');
      },
    );

    testWidgets(
      'the food\'s stored groupId is the selected value on open '
      'in both S-001 and S-002 cases — not silently replaced with '
      '"Ungrouped" (S-001 / S-002)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-keeps-cat',
            name: 'Cheese',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-keeps-cat');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: state,
                onSave: (_) async => true,
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dropdown = tester.widget<DropdownButtonFormField<String?>>(
          find.byKey(const Key('food_form_group')),
        );
        expect(
          dropdown.initialValue,
          'food-group-dairy',
          reason: 'initialValue must match the food\'s stored groupId',
        );
        // No "Ungrouped" defaulting: there is no item with
        // value null at the top of the items list whose label
        // is "Ungrouped" being pre-selected.
        expect(dropdown.initialValue, isNotNull);
      },
    );

    testWidgets(
      'saving without touching the category leaves the food\'s '
      'stored groupId byte-identical (S-003)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-save-untouched',
            name: 'Butter',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-save-untouched');

        FoodDraft? capturedDraft;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: state,
                controller: controller,
                onSave: (draft) async {
                  capturedDraft = draft;
                  // Route through the real state path so the
                  // persisted row matches the cached row.
                  await state.updateCatalogFood(initial, draft);
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Submit without touching the dropdown.
        controller.submit();
        await tester.pumpAndSettle();

        // The draft's groupId is the food's stored groupId
        // (byte-identical).
        expect(capturedDraft, isNotNull);
        expect(capturedDraft!.groupId, 'food-group-dairy');
        // The persisted row is also byte-identical on groupId.
        final reloaded = await repo.getCatalogFoodById('food-save-untouched');
        expect(reloaded, isNotNull);
        expect(reloaded!.groupId, 'food-group-dairy');
      },
    );

    testWidgets(
      'selecting a valid category and saving persists the new '
      'groupId (S-004)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-pick-new-cat',
            name: 'Yogurt, plain',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-pick-new-cat');

        // The Proteins group is still active.
        final proteins = state.activeFoodGroups
            .firstWhere((g) => g.id == 'food-group-proteins');

        FoodDraft? capturedDraft;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: state,
                controller: controller,
                onSave: (draft) async {
                  capturedDraft = draft;
                  await state.updateCatalogFood(initial, draft);
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the dropdown and pick Proteins. The dropdown
        // selection is the only state change; macros / name
        // are untouched.
        await tester.tap(find.byKey(const Key('food_form_group')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(proteins.name).last);
        await tester.pumpAndSettle();

        controller.submit();
        await tester.pumpAndSettle();

        expect(capturedDraft, isNotNull);
        expect(capturedDraft!.groupId, 'food-group-proteins');

        final reloaded = await repo.getCatalogFoodById('food-pick-new-cat');
        expect(reloaded, isNotNull);
        expect(reloaded!.groupId, 'food-group-proteins');
      },
    );

    testWidgets(
      'opening and immediately backing out produces no change to '
      'the food\'s stored data (S-005)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final (repo, state) = await _setupState();

        await repo.seedCatalogFood(
          _catalogFood(
            id: 'food-backout',
            name: 'Almond milk',
            groupId: 'food-group-dairy',
          ),
        );
        await repo.archiveFoodGroup('food-group-dairy');
        await state.loadCatalogFoods();
        await state.loadFoodGroups(includeArchived: true);

        final initial = state.catalogFoods
            .firstWhere((f) => f.id == 'food-backout');

        final navigatorKey = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(body: Container()),
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: FoodForm(
                  initial: initial,
                  foodLibraryState: state,
                  onSave: (_) async => true,
                  skipPopOnSave: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Push the editor route.
        navigatorKey.currentState!.pushNamed('/');
        await tester.pumpAndSettle();
        // Wait for the dropdown crash to be resolved (RED
        // before the fix); we still pop either way.
        try {
          // Pop without touching the form, mirroring a back
          // gesture. The form was opened and never had its
          // onSave invoked.
          navigatorKey.currentState!.pop();
        } catch (_) {
          // best-effort — the assertion below is the contract.
        }
        await tester.pumpAndSettle();

        // The persisted row is byte-identical.
        final reloaded = await repo.getCatalogFoodById('food-backout');
        expect(reloaded, isNotNull);
        expect(reloaded!.name, initial.name);
        expect(reloaded.groupId, initial.groupId);
        expect(reloaded.protein, initial.protein);
        expect(reloaded.fat, initial.fat);
        expect(reloaded.updatedAtMs, initial.updatedAtMs,
            reason: 'no save happened; updatedAtMs must not advance');
      },
    );
  });
}
