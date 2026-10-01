// filepath: test/food_form_decimals_and_autofocus_test.dart
//
// Tests for the **decimal macros** and **auto-select on focus**
// polish on `FoodForm`. See
// `docs/plans/food-form-decimals-and-autofocus-plan.md`
// for the full scenario register (S-001..S-008).
//
// The food form lives in
// `lib/features/nutrition/widgets/food_form.dart` and is shared
// by the **+ New Item** and **Edit Food** flows. Two things
// changed:
//
// 1. Macros are now stored as `double` end-to-end (Food,
//    ConsumedFood, FoodDraft) so the form can persist fractional
//    grams like `0.5` g of fat. The form's macro field
//    previously used `digitsOnly` + `int.parse`, which rejected
//    `0.5`. The new contract uses the same `^\d*\.?\d*$` regex
//    the reference-amount field already used.
//
// 2. Every `TextFormField` on the form has a per-field
//    `FocusNode` that selects all text on focus, so tapping a
//    pre-filled field (e.g. `4` g of fat in **Edit Food** mode)
//    highlights the entire value for fast overwrite.
//
// `MockWorkoutRepository` is used (the project is web-compatible
// via the Hive-backed mock, per the global conventions in
// `docs/global_conventions.md`).
//
// Note: the form renders inside a `ListView` so on a phone-sized
// surface the macro fields are below the fold. The widget tests
// below set a tall surface so the field keys are discoverable
// without scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';

/// Standard tall surface for the food form (image tile + 9 fields).
const _formSurface = Size(420, 1800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── S-007 / S-008: map round-trip with REAL and INTEGER macros ──────
  // These are model-level tests: the `Food` / `ConsumedFood`
  // `fromMap` must accept both a legacy `INTEGER` row (no
  // migration) and the new `REAL` row, casting via
  // `((m['k'] as num?) ?? 0.0).toDouble()`.

  group(
    'Food macros: fromMap accepts INTEGER and REAL values (S-007/S-008)',
    () {
      test('REAL value (1.5) round-trips as 1.5 (S-007)', () {
        final food = Food.fromMap(<String, dynamic>{
          'id': 'food-real-1',
          'name': 'Olive oil',
          'unit_type': 'grams',
          'reference_amount': 100.0,
          'reference_label': 'g',
          'is_catalog': 0,
          'protein': 0.0,
          'carbs': 0.0,
          'fiber': null,
          'fat': 1.5,
          'sodium': null,
          'is_archived': 0,
          'created_at_ms': 1000,
          'updated_at_ms': 1000,
        });
        expect(food.fat, 1.5);
        expect(food.protein, 0.0);
        expect(food.fiber, isNull);
        expect(food.sodium, isNull);
      });

      test('INTEGER value (31) round-trips as 31.0 (S-008 back-compat)', () {
        final food = Food.fromMap(<String, dynamic>{
          'id': 'food-int-1',
          'name': 'Chicken',
          'unit_type': 'grams',
          'reference_amount': 100.0,
          'reference_label': 'g',
          'is_catalog': 0,
          'protein': 31,
          'carbs': 0,
          'fiber': 0,
          'fat': 4,
          'sodium': 50,
          'is_archived': 0,
          'created_at_ms': 1000,
          'updated_at_ms': 1000,
        });
        expect(food.protein, 31.0);
        expect(food.carbs, 0.0);
        expect(food.fiber, 0.0);
        expect(food.fat, 4.0);
        expect(food.sodium, 50.0);
      });

      test('ConsumedFood fromMap accepts REAL and INTEGER macros', () {
        final realRow = ConsumedFood.fromMap(<String, dynamic>{
          'id': 'c-real-1',
          'logged_at_ms': 1000,
          'date_ms': 0,
          'source_food_id': 'f-1',
          'name': 'Snack',
          'unit_type': 'grams',
          'reference_amount': 100.0,
          'reference_label': 'g',
          'protein': 0.0,
          'carbs': 0.0,
          'fiber': 0.0,
          'fat': 1.5,
          'sodium': null,
          'amount_consumed': 100.0,
          'target_calories': 2000.0,
          'target_protein': 0.0,
          'target_carbs': 0.0,
          'target_fat': 0.0,
          'created_at_ms': 1000,
          'updated_at_ms': 1000,
        });
        expect(realRow.fat, 1.5);

        final intRow = ConsumedFood.fromMap(<String, dynamic>{
          'id': 'c-int-1',
          'logged_at_ms': 1000,
          'date_ms': 0,
          'source_food_id': 'f-1',
          'name': 'Snack',
          'unit_type': 'grams',
          'reference_amount': 100.0,
          'reference_label': 'g',
          'protein': 31,
          'carbs': 0,
          'fiber': 0,
          'fat': 4,
          'sodium': 50,
          'amount_consumed': 100.0,
          'target_calories': 2000.0,
          'target_protein': 0.0,
          'target_carbs': 0.0,
          'target_fat': 0.0,
          'created_at_ms': 1000,
          'updated_at_ms': 1000,
        });
        expect(intRow.protein, 31.0);
        expect(intRow.sodium, 50.0);
      });
    },
  );

  // ─── S-001 / S-002 / S-003: decimal input & validation ──────────────

  group('FoodForm: decimal macros (S-001/S-002/S-003)', () {
    testWidgets(
      'accepts "0.5" in the Fat field and persists it as 0.5 (S-001)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        FoodDraft? capturedDraft;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: state,
                controller: controller,
                onSave: (draft) async {
                  capturedDraft = draft;
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'Half-fat snack',
        );
        await tester.enterText(find.byKey(const Key('food_form_fat')), '0.5');
        await tester.pump();
        controller.submit();
        await tester.pumpAndSettle();

        expect(capturedDraft, isNotNull);
        expect(capturedDraft!.fat, 0.5);
        expect(capturedDraft!.name, 'Half-fat snack');
        // Required macros default to "0" and parse to 0.0.
        expect(capturedDraft!.protein, 0.0);
        expect(capturedDraft!.carbs, 0.0);
      },
    );

    testWidgets(
      'saves a decimal edit end-to-end into the FoodLibraryState cache '
      '(S-002)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        // Seed a catalog food with an integer protein.
        const existing = Food(
          id: 'food-decimal-edit-1',
          name: 'Greek Yogurt',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 10,
          carbs: 4,
          fiber: 0,
          fat: 0.5,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.seedCatalogFood(existing);
        await state.loadCatalogFoods();
        final initial = state.catalogFoods.firstWhere(
          (f) => f.id == 'food-decimal-edit-1',
        );

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
                  // Route through the real `updateCatalogFood` so
                  // we exercise the full state → repository →
                  // cache path.
                  await state.updateCatalogFood(initial, draft);
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Change protein to 10.5 (a fractional value).
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          '10.5',
        );
        await tester.pump();
        controller.submit();
        await tester.pumpAndSettle();

        // Cached food in the state must reflect the decimal.
        final updated = state.catalogFoods.firstWhere(
          (f) => f.id == 'food-decimal-edit-1',
        );
        expect(updated.protein, 10.5);
      },
    );

    testWidgets(
      'the decimal input formatter strips letters, so a required macro '
      'field shows the "Required" validator error (S-003)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        var saveCalled = false;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: state,
                controller: controller,
                onSave: (_) async {
                  saveCalled = true;
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'Bad input',
        );
        // The decimal formatter strips every non-digit, non-dot
        // character. The validator's "Required" branch is the
        // first one triggered when the field is empty after
        // stripping. This is the user-facing behaviour we
        // exercise here.
        await tester.enterText(find.byKey(const Key('food_form_carbs')), 'abc');
        await tester.pump();
        controller.submit();
        await tester.pumpAndSettle();

        expect(
          saveCalled,
          isFalse,
          reason: 'save must be blocked by validator',
        );
        // "Required" surfaces for required macros whose input
        // was filtered down to empty. This is the visible
        // behaviour of the `^\d*\.?\d*$` formatter + the
        // `required ? "Required" : null` branch in the
        // validator.
        expect(find.text('Required'), findsOneWidget);
      },
    );
  });

  // ─── S-004 / S-005 / S-006: focus selection ──────────────────────────

  group('FoodForm: auto-select on focus (S-004/S-005/S-006)', () {
    testWidgets('focusing a pre-filled macro field selects all text (S-004)', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(_formSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);

      const initial = Food(
        id: 'food-focus-1',
        name: 'Pre-filled Food',
        groupId: null,
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 31,
        carbs: 0,
        fiber: 0,
        fat: 4,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

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

      // Tap into the pre-filled Fat field. The select-all
      // listener runs on focus gain, so after the tap, the
      // controller's selection should span the entire text.
      await tester.tap(find.byKey(const Key('food_form_fat')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('food_form_fat')),
      );
      final controller = field.controller!;
      expect(controller.text, '4.0');
      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
        reason: 'pre-filled fat should be fully selected on focus',
      );
    });

    testWidgets(
      'focusing an empty Notes field is a no-op (no exception) (S-005)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        // Notes is the only field the form may render with an
        // empty starting value (gated by `showNotesField`). The
        // _selectAllOnFocus handler short-circuits on empty
        // text to avoid setting a selection that crosses an
        // empty range, so this test asserts the no-throw + no-
        // select-all path.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: state,
                showNotesField: true,
                onSave: (_) async => true,
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('food_form_notes')));
        await tester.pumpAndSettle();

        final field = tester.widget<TextFormField>(
          find.byKey(const Key('food_form_notes')),
        );
        final controller = field.controller!;
        expect(controller.text, isEmpty);
        // Empty field: no select-all is performed, so the
        // selection is collapsed (whatever the field default is).
        expect(controller.selection.isCollapsed, isTrue);
      },
    );

    testWidgets(
      'focusing a pre-filled name field does NOT select all text (S-006)',
      (WidgetTester tester) async {
        // The food form's name field is a free-text label field,
        // not a value-entry field. Per the value-entry
        // select-on-focus contract, free-text fields (names,
        // descriptions, multi-line notes) keep the default
        // cursor-placement behavior so the user can position the
        // cursor freely to edit in place. The select-all behavior
        // applies to numeric value fields and short value labels
        // (reference amount, reference label, macros) — not to
        // the food name.
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        const initial = Food(
          id: 'food-focus-2',
          name: 'Eggs',
          groupId: null,
          unitType: FoodUnitType.count,
          referenceAmount: 1,
          referenceLabel: 'egg',
          isCatalog: true,
          protein: 6,
          carbs: 1,
          fiber: 0,
          fat: 5,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

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

        await tester.tap(find.byKey(const Key('food_form_name')));
        await tester.pumpAndSettle();

        final field = tester.widget<TextFormField>(
          find.byKey(const Key('food_form_name')),
        );
        final controller = field.controller!;
        expect(controller.text, 'Eggs');
        // Free-text name field: selection stays collapsed, the
        // user can position the cursor freely inside the name.
        expect(
          controller.selection.isCollapsed,
          isTrue,
          reason: 'free-text name field should NOT auto-select on focus',
        );
      },
    );
  });
}
