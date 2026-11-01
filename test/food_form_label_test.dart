// filepath: test/food_form_label_test.dart
//
// 92c Phase 2A — the food form's macro boxes read like a nutrition label.
// Scenario register: `docs/plans/2026-10-31-92c-food-form-like-a-label-plan/`.
//
// Covered here: S-92c.2 (package order), S-92c.3 (blank boxes + faint 0),
// S-92c.4 (blank save), S-92c.5 (formatGrams prefill), S-92c.6 (a lone dot
// blocks Save), S-92c.14 (stored 0.0 vs null for fiber/sodium), S-92c.15
// (select-all on the label-like text), S-92c.16 (the always-on label is
// macro-only).
//
// Mock-only: the form is presentation-only and the save callback captures
// the draft, so every test runs on `MockWorkoutRepository` and no Hive box
// is opened inside `testWidgets` (FakeAsync would never settle the write).
// The surface is tall and wide so the whole form is laid out at once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';

const _formSurface = Size(800, 3000);

/// The five macro keys in the order a package prints them (D-92c.2).
const _macroKeys = <String>[
  'food_form_fat',
  'food_form_carbs',
  'food_form_fiber',
  'food_form_protein',
  'food_form_sodium',
];

const _macroLabels = <String>[
  'Fat (g)',
  'Carbs (g)',
  'Fiber (g)',
  'Protein (g)',
  'Sodium (mg)',
];

Food _food({
  required String id,
  required String name,
  double protein = 0,
  double carbs = 0,
  double? fiber,
  double fat = 0,
  double? sodium,
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
  fiber: fiber,
  fat: fat,
  sodium: sodium,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// Pumps a New Food form (or an edit of [initial]) on the tall surface and
/// returns the host controller plus the drafts the form handed to `onSave`.
Future<(FoodFormController, List<FoodDraft>)> _pumpForm(
  WidgetTester tester, {
  Food? initial,
}) async {
  await tester.binding.setSurfaceSize(_formSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

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

/// The field's rendered decoration (the form's own `InputDecoration`).
InputDecoration _decorationOf(WidgetTester tester, String key) {
  final decorator = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(InputDecorator),
  );
  return tester.widget<InputDecorator>(decorator.first).decoration;
}

Future<void> _submit(WidgetTester tester, FoodFormController controller) async {
  controller.submit();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S-92c.2: the macros run top to bottom in package order', (
    tester,
  ) async {
    await _pumpForm(tester);

    final tops = [
      for (final key in _macroKeys) tester.getTopLeft(find.byKey(Key(key))).dy,
    ];
    for (var i = 0; i < tops.length - 1; i++) {
      expect(
        tops[i],
        lessThan(tops[i + 1]),
        reason:
            '${_macroKeys[i]} must sit above ${_macroKeys[i + 1]} '
            '(fat, carbs, fiber, protein, sodium)',
      );
    }
  });

  testWidgets(
    'S-92c.3: a new food starts with five blank boxes and a faint 0',
    (tester) async {
      await _pumpForm(tester);

      for (final key in _macroKeys) {
        expect(_fieldText(tester, key), isEmpty, reason: '$key starts blank');
      }
      expect(
        find.text('0.0'),
        findsNothing,
        reason: 'a new food must not prefill 0.0',
      );
      expect(
        find.text('0'),
        findsNWidgets(5),
        reason: 'each empty macro box shows the faint 0 hint without focus',
      );
    },
  );

  testWidgets('S-92c.4: a name-only food saves blanks as 0.0 and null', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(tester);

    await tester.enterText(find.byKey(const Key('food_form_name')), 'Plain');
    await tester.pump();
    await _submit(tester, controller);

    expect(saved, hasLength(1));
    final draft = saved.single;
    expect(draft.protein, 0.0);
    expect(draft.carbs, 0.0);
    expect(draft.fat, 0.0);
    expect(draft.fiber, isNull, reason: 'blank fiber is "not recorded"');
    expect(draft.sodium, isNull, reason: 'blank sodium is "not recorded"');
  });

  testWidgets(
    'S-92c.5: edit prefills with formatGrams and keeps a null fiber empty',
    (tester) async {
      final initial = _food(
        id: 's5-chicken',
        name: 'Chicken',
        protein: 31,
        carbs: 0,
        fat: 3.6,
        sodium: 74,
      );
      final (controller, saved) = await _pumpForm(tester, initial: initial);

      expect(_fieldText(tester, 'food_form_protein'), '31');
      expect(_fieldText(tester, 'food_form_carbs'), '0');
      expect(_fieldText(tester, 'food_form_fat'), '3.6');
      expect(_fieldText(tester, 'food_form_fiber'), isEmpty);
      expect(_fieldText(tester, 'food_form_sodium'), '74');

      await _submit(tester, controller);

      expect(saved, hasLength(1));
      final draft = saved.single;
      expect(draft.protein, 31.0);
      expect(draft.carbs, 0.0);
      expect(draft.fat, 3.6);
      expect(draft.fiber, isNull);
      expect(draft.sodium, 74.0);
    },
  );

  testWidgets('S-92c.6: a lone dot blocks Save with "Must be a number"', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(tester);

    await tester.enterText(find.byKey(const Key('food_form_name')), 'Dot');
    await tester.enterText(find.byKey(const Key('food_form_fat')), '.');
    await tester.pump();
    await _submit(tester, controller);

    expect(saved, isEmpty, reason: 'a lone dot must block Save');
    expect(find.text('Must be a number'), findsOneWidget);
  });

  testWidgets('S-92c.14: a stored 0.0 fiber opens as 0 and stays 0.0', (
    tester,
  ) async {
    final initial = _food(
      id: 's14-a',
      name: 'Food A',
      protein: 10,
      fiber: 0,
      sodium: 74,
    );
    final (controller, saved) = await _pumpForm(tester, initial: initial);

    expect(_fieldText(tester, 'food_form_fiber'), '0');
    expect(_fieldText(tester, 'food_form_sodium'), '74');

    await _submit(tester, controller);

    final draft = saved.single;
    expect(draft.fiber, 0.0);
    expect(draft.sodium, 74.0);
  });

  testWidgets(
    'S-92c.14: an unrecorded fiber and sodium open empty and save null',
    (tester) async {
      final initial = _food(id: 's14-b', name: 'Food B', protein: 10);
      final (controller, saved) = await _pumpForm(tester, initial: initial);

      expect(_fieldText(tester, 'food_form_fiber'), isEmpty);
      expect(_fieldText(tester, 'food_form_sodium'), isEmpty);

      await _submit(tester, controller);

      final draft = saved.single;
      expect(draft.fiber, isNull);
      expect(draft.sodium, isNull);
    },
  );

  testWidgets('S-92c.14: typing then clearing sodium saves null', (
    tester,
  ) async {
    final initial = _food(id: 's14-c', name: 'Food C', protein: 10);
    final (controller, saved) = await _pumpForm(tester, initial: initial);

    await tester.enterText(find.byKey(const Key('food_form_sodium')), '74');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('food_form_sodium')), '');
    await tester.pump();
    await _submit(tester, controller);

    final draft = saved.single;
    expect(
      draft.sodium,
      isNull,
      reason: 'an emptied box is "not recorded", not 0',
    );
  });

  testWidgets('S-92c.15: tapping the prefilled fat selects the whole value', (
    tester,
  ) async {
    final initial = _food(
      id: 's15-oats',
      name: 'Oats',
      protein: 31,
      carbs: 0,
      fat: 4,
    );
    await _pumpForm(tester, initial: initial);

    expect(_fieldText(tester, 'food_form_fat'), '4');

    await tester.tap(find.byKey(const Key('food_form_fat')));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextFormField>(find.byKey(const Key('food_form_fat')))
        .controller!;
    expect(controller.text, '4');
    expect(
      controller.selection,
      TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      reason: 'the pre-filled fat is fully selected on focus',
    );
  });

  testWidgets('S-92c.16: the always-on label and faint 0 are macro-only', (
    tester,
  ) async {
    await _pumpForm(tester);

    for (final label in _macroLabels) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '$label is visible without focusing anything',
      );
    }
    expect(find.text('0'), findsNWidgets(5));

    for (final key in ['food_form_name', 'food_form_group']) {
      final decoration = _decorationOf(tester, key);
      expect(decoration.hintText, isNull, reason: "$key keeps today's hint");
      expect(
        decoration.floatingLabelBehavior,
        isNot(FloatingLabelBehavior.always),
        reason: "$key keeps today's label behaviour",
      );
    }

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });
}
