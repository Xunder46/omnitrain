// filepath: test/calories_field_form_test.dart
//
// Plan 254 — the food form's Calories (kcal) box follows the macros until
// the user types a number of their own (S-25406..S-25412).
// Plan: `docs/plans/2026-11-19-254-calories-field-in-food-form-plan/`.
//
// Mock-only: the form is presentation-only and the save callback captures
// the draft, so every test runs on `MockWorkoutRepository` and no Hive box
// is opened inside `testWidgets` (FakeAsync would never settle the write).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form_unsaved_probe.dart';
import 'package:omnitrain/state/food_library_state.dart';

const _formSurface = Size(600, 1200);

const _caloriesNoteKey = Key('food_form_calories');
const _caloriesResetKey = Key('food_form_calories_reset');

Food _food({
  required String id,
  required String name,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
  double? caloriesOverride,
}) => Food(
  id: id,
  name: name,
  groupId: null,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: protein,
  carbs: carbs,
  fat: fat,
  caloriesOverride: caloriesOverride,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// Pumps a New Food form (or an edit of [initial]) and returns the host
/// controller plus the drafts the form handed to `onSave`.
Future<(FoodFormController, List<FoodDraft>)> _pumpForm(
  WidgetTester tester, {
  Food? initial,
}) async {
  await tester.binding.setSurfaceSize(_formSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Clear the tree first: pumping a second form of the same shape onto an
  // existing one reuses the previous form's element (same type and position,
  // no key), so its State survives and `initState` never attaches the new
  // controller.
  await tester.pumpWidget(const SizedBox.shrink());

  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = FoodLibraryState(repo);

  final controller = FoodFormController();
  addTearDown(controller.detach);
  final saved = <FoodDraft>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FoodForm(
          initial: initial,
          foodLibraryState: state,
          controller: controller,
          onSave: (draft) async {
            saved.add(draft);
            return true;
          },
          skipPopOnSave: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, saved);
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller?.text ?? '';

/// The Calories box's current text (plan 254: the number sits in the
/// field's controller, not in a separate `Text` line).
String _box(WidgetTester tester) =>
    _fieldText(tester, 'food_form_calories_field');

Future<void> _submit(WidgetTester tester, FoodFormController controller) async {
  controller.submit();
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S-25406: the box follows the macros until the user types', (
    tester,
  ) async {
    await _pumpForm(tester);

    await _type(tester, 'food_form_fat', '10');
    expect(_box(tester), '90');

    await _type(tester, 'food_form_carbs', '10');
    expect(_box(tester), '130');

    // Auto mode: the reset button only exists while the user's own number
    // differs from the macro sum.
    expect(find.byKey(_caloriesResetKey), findsNothing);
  });

  testWidgets('S-25407: a typed number stays put while the macros move', (
    tester,
  ) async {
    await _pumpForm(tester);

    await _type(tester, 'food_form_fat', '10');
    expect(_box(tester), '90');

    await _type(tester, 'food_form_calories_field', '43');
    expect(_box(tester), '43');

    await _type(tester, 'food_form_carbs', '10');
    expect(_box(tester), '43', reason: 'the macros must not overwrite 43');
    expect(
      tester.widget<Text>(find.byKey(_caloriesNoteKey)).data,
      'Macros give 130 cal',
    );
    expect(find.byKey(_caloriesResetKey), findsOneWidget);
  });

  testWidgets('S-25408: Use macros restores the macro sum and auto mode', (
    tester,
  ) async {
    await _pumpForm(tester);

    await _type(tester, 'food_form_fat', '10');
    await _type(tester, 'food_form_calories_field', '43');
    await _type(tester, 'food_form_carbs', '10');
    expect(_box(tester), '43');

    await tester.tap(find.byKey(_caloriesResetKey));
    await tester.pumpAndSettle();

    expect(_box(tester), '130');
    expect(find.byKey(_caloriesNoteKey), findsNothing);
    expect(find.byKey(_caloriesResetKey), findsNothing);

    // Auto mode again: a macro change moves the box.
    await _type(tester, 'food_form_protein', '5');
    expect(_box(tester), '150');
  });

  testWidgets('S-25409: a typed number saves as caloriesOverride', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(tester);

    await _type(tester, 'food_form_name', 'Beer');
    await _type(tester, 'food_form_fat', '0');
    await _type(tester, 'food_form_carbs', '3.6');
    await _type(tester, 'food_form_protein', '0.5');
    // The serving control stays on its default 100 g, the serving the
    // neighbouring form tests submit with.
    await _type(tester, 'food_form_calories_field', '43');

    await _submit(tester, controller);

    expect(saved, hasLength(1));
    final draft = saved.single;
    expect(draft.name, 'Beer');
    expect(draft.caloriesOverride, 43);
    expect(draft.protein, 0.5);
    expect(draft.carbs, 3.6);
    expect(draft.fat, 0.0);
  });

  testWidgets('S-25410: untouched, equal and cleared boxes store no override', (
    tester,
  ) async {
    // (a) macros summing to 90, box untouched.
    var (controller, saved) = await _pumpForm(tester);
    await _type(tester, 'food_form_name', 'A');
    await _type(tester, 'food_form_fat', '10');
    expect(_box(tester), '90');
    await _submit(tester, controller);
    expect(saved.single.caloriesOverride, isNull);

    // (b) the user types the macro sum itself.
    (controller, saved) = await _pumpForm(tester);
    await _type(tester, 'food_form_name', 'B');
    await _type(tester, 'food_form_fat', '10');
    // The box already reads 90, and entering identical text sends no change
    // event: pass through another number first so the box counts as typed in.
    await _type(tester, 'food_form_calories_field', '43');
    await _type(tester, 'food_form_calories_field', '90');
    await _submit(tester, controller);
    expect(saved.single.caloriesOverride, isNull);

    // (c) the user types 43, then clears the box.
    (controller, saved) = await _pumpForm(tester);
    await _type(tester, 'food_form_name', 'C');
    await _type(tester, 'food_form_fat', '10');
    await _type(tester, 'food_form_calories_field', '43');
    await _type(tester, 'food_form_calories_field', '');
    await _submit(tester, controller);
    expect(saved.single.caloriesOverride, isNull);
  });

  testWidgets('S-25411: an edit opens on the stored override and keeps it', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(
      tester,
      initial: _food(
        id: 's25411-beer',
        name: 'Beer',
        protein: 0.5,
        carbs: 3.6,
        fat: 0,
        caloriesOverride: 43,
      ),
    );

    expect(_box(tester), '43');
    expect(
      tester.widget<Text>(find.byKey(_caloriesNoteKey)).data,
      'Macros give 16 cal',
      reason: '0.5*4 + 3.6*4 = 16.4 kcal, rounded to 16',
    );
    expect(find.byKey(_caloriesResetKey), findsOneWidget);

    await _submit(tester, controller);
    expect(saved, hasLength(1));
    expect(saved.single.caloriesOverride, 43);
  });

  testWidgets('S-25412: a lone dot is rejected and nothing saves', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(tester);

    await _type(tester, 'food_form_name', 'D');
    await _type(tester, 'food_form_calories_field', '.');

    await _submit(tester, controller);

    expect(find.text('Must be a number'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('S-25413: a typed zero is a real override', (tester) async {
    final (controller, saved) = await _pumpForm(tester);

    await _type(tester, 'food_form_name', 'Beer');
    await _type(tester, 'food_form_fat', '0');
    await _type(tester, 'food_form_carbs', '3.6');
    await _type(tester, 'food_form_protein', '0.5');
    expect(_box(tester), '16');

    await _type(tester, 'food_form_calories_field', '0');
    expect(
      tester.widget<Text>(find.byKey(_caloriesNoteKey)).data,
      'Macros give 16 cal',
    );

    await _submit(tester, controller);

    expect(saved, hasLength(1));
    expect(saved.single.caloriesOverride, 0.0);
  });

  testWidgets(
    'S-25415: focusing the untouched calories box does not make a new food '
    'form look dirty',
    (tester) async {
      await tester.binding.setSurfaceSize(_formSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SizedBox.shrink());

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);

      final controller = FoodFormController();
      addTearDown(controller.detach);

      final formKey = GlobalKey();
      final probe = FoodFormUnsavedProbe(formKey);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FoodForm(
              key: formKey,
              initial: null,
              foodLibraryState: state,
              controller: controller,
              onSave: (draft) async => true,
              skipPopOnSave: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      probe.record();

      expect(probe.isDirty, isFalse);

      // Tapping into the box selects all its text (the auto-mode macro sum),
      // which notifies the controller — but only a change of TEXT counts.
      await tester.tap(find.byKey(const Key('food_form_calories_field')));
      await tester.pump();
      await tester.pump();

      expect(probe.isDirty, isFalse);

      await tester.enterText(find.byKey(const Key('food_form_fat')), '5');
      await tester.pump();

      expect(probe.isDirty, isTrue);

      probe.dispose();
    },
  );
}
