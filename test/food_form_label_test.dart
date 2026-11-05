// filepath: test/food_form_label_test.dart
//
// 92c — the food form reads like a nutrition label.
// Scenario register: `docs/plans/2026-10-31-92c-food-form-like-a-label-plan/`.
//
// Phase 2A: S-92c.2 (package order), S-92c.3 (blank boxes + faint 0),
// S-92c.4 (blank save), S-92c.5 (formatGrams prefill), S-92c.6 (a lone dot
// blocks Save), S-92c.14 (stored 0.0 vs null for fiber/sodium), S-92c.15
// (select-all on the label-like text), S-92c.16 (the always-on label is
// macro-only).
//
// Phase 2B: S-92c.1 (the live calories line and its place between Sodium and
// Notes), S-92c.7 (the photo tile below the name), S-92c.8 (the duplicate
// note), S-92c.10 (padded / different-case names), S-92c.11 (clearing the
// name hides the note), S-92c.12 (one note for two rows), S-92c.13 (the
// fractional line and the Library row agree).
//
// Mock-only: the form is presentation-only and the save callback captures
// the draft, so every test runs on `MockWorkoutRepository` and no Hive box
// is opened inside `testWidgets` (FakeAsync would never settle the write).
// The surface is tall and wide so the whole form is laid out at once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/utils/food_helpers.dart';
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
  bool isCatalog = true,
}) => Food(
  id: id,
  name: name,
  groupId: null,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: isCatalog,
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
///
/// [seed] runs before the form is pumped and may return the food to edit —
/// a library row only exists after seeding.
Future<(FoodFormController, List<FoodDraft>)> _pumpForm(
  WidgetTester tester, {
  Food? initial,
  bool showNotesField = false,
  Future<Food?> Function(FoodLibraryState state)? seed,
}) async {
  await tester.binding.setSurfaceSize(_formSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = FoodLibraryState(repo);
  if (seed != null) {
    initial = await seed(state) ?? initial;
  }

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
          showNotesField: showNotesField,
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

/// The text of the single-line `Text` under [key].
String _line(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data ?? '';

const _duplicateNoteKey = Key('food_form_duplicate_note');

/// Loads the shipped catalog into the form's state (the duplicate-note
/// fixtures read it).
Future<Food?> _loadShippedCatalog(FoodLibraryState state) async {
  await state.loadCatalogFoods();
  return null;
}

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

  // ─── Phase 2B ─────────────────────────────────────────────────────────

  testWidgets('S-92c.1: the calories line follows the macros', (
    tester,
  ) async {
    await _pumpForm(tester, showNotesField: true);

    await tester.enterText(find.byKey(const Key('food_form_protein')), '10');
    await tester.enterText(find.byKey(const Key('food_form_carbs')), '18');
    await tester.enterText(find.byKey(const Key('food_form_fat')), '12');
    await tester.pump();

    expect(_line(tester, 'food_form_calories'), '= 220 cal');

    // Clearing fat drops the 9 kcal/g term.
    await tester.enterText(find.byKey(const Key('food_form_fat')), '');
    await tester.pump();
    expect(_line(tester, 'food_form_calories'), '= 112 cal');

    // A lone `.` in carbs does not parse and counts 0.
    await tester.enterText(find.byKey(const Key('food_form_fat')), '12');
    await tester.enterText(find.byKey(const Key('food_form_carbs')), '.');
    await tester.pump();
    expect(_line(tester, 'food_form_calories'), '= 148 cal');

    // Fiber and sodium never enter the formula.
    await tester.enterText(find.byKey(const Key('food_form_carbs')), '18');
    await tester.enterText(find.byKey(const Key('food_form_fiber')), '5');
    await tester.enterText(find.byKey(const Key('food_form_sodium')), '300');
    await tester.pump();
    expect(_line(tester, 'food_form_calories'), '= 220 cal');

    // The same values through the one formula give the same number.
    final same = _food(
      id: 's1-label',
      name: 'Label',
      protein: 10,
      carbs: 18,
      fat: 12,
    );
    expect(calculateCalories(same), 220);

    // D-92c.1: directly under the last macro field, above Notes.
    final caloriesDy = tester
        .getTopLeft(find.byKey(const Key('food_form_calories')))
        .dy;
    final sodiumDy = tester
        .getTopLeft(find.byKey(const Key('food_form_sodium')))
        .dy;
    final notesDy = tester.getTopLeft(find.byKey(const Key('food_form_notes'))).dy;
    expect(
      caloriesDy,
      greaterThan(sodiumDy),
      reason: 'the line sits below the last macro field (Sodium)',
    );
    expect(
      caloriesDy,
      lessThan(notesDy),
      reason: 'the line sits above the Notes field',
    );
  });

  testWidgets('S-92c.7: the photo tile sits below the name, above Category', (
    tester,
  ) async {
    await _pumpForm(tester);

    final nameDy = tester.getTopLeft(find.byKey(const Key('food_form_name'))).dy;
    final tileDy = tester
        .getTopLeft(find.byKey(const Key('food_form_image_tile')))
        .dy;
    final groupDy = tester.getTopLeft(find.byKey(const Key('food_form_group'))).dy;

    expect(
      nameDy,
      lessThan(tileDy),
      reason: 'the photo is asked for after the name (D-92c.6)',
    );
    expect(
      tileDy,
      lessThan(groupDy),
      reason: 'the photo sits above the category dropdown (AC-6)',
    );
  });

  testWidgets('S-92c.8: an existing catalog name shows the note, Save works', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(
      tester,
      seed: _loadShippedCatalog,
    );
    final nameField = find.byKey(const Key('food_form_name'));

    await tester.enterText(nameField, ' chicken breast, skinless ');
    await tester.pump();
    expect(find.byKey(_duplicateNoteKey), findsOneWidget);
    expect(
      find.text(
        'There\'s already a food called "chicken breast, skinless" '
        'in the Library',
      ),
      findsOneWidget,
    );

    await tester.enterText(nameField, 'Chicken');
    await tester.pump();
    expect(
      find.byKey(_duplicateNoteKey),
      findsNothing,
      reason: 'a partial name is not a duplicate',
    );

    await tester.enterText(nameField, 'chicken breast, skinless');
    await tester.pump();
    await _submit(tester, controller);
    expect(
      saved,
      hasLength(1),
      reason: 'the note never blocks Save',
    );
    expect(saved.single.name, 'chicken breast, skinless');
  });

  testWidgets('S-92c.8: editing a user-created food notes only a rename', (
    tester,
  ) async {
    final myBar = _food(id: 'my-bar', name: 'My Bar', isCatalog: false);
    await _pumpForm(
      tester,
      seed: (state) async {
        await state.loadCatalogFoods();
        await state.createFood(myBar);
        return myBar;
      },
    );

    expect(
      find.byKey(_duplicateNoteKey),
      findsNothing,
      reason: "a food's own name is not a duplicate of itself",
    );

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Oats, dry',
    );
    await tester.pump();

    expect(
      find.byKey(_duplicateNoteKey),
      findsOneWidget,
      reason: 'renaming onto an existing food shows the note (Oats, dry)',
    );
  });

  testWidgets('S-92c.8: editing a library copy of a bundled food shows none', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      seed: (state) async {
        await state.loadCatalogFoods();
        final id = await state.addCatalogFoodToLibrary('chicken_breast');
        return state.foods.firstWhere((f) => f.id == id);
      },
    );

    expect(
      find.byKey(_duplicateNoteKey),
      findsNothing,
      reason: 'the copy and the catalog row it came from are one food',
    );

    // The same fixture must be able to show the note, or the leg above
    // would pass on a form that never looks for duplicates at all.
    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Oats, dry',
    );
    await tester.pump();
    expect(
      find.byKey(_duplicateNoteKey),
      findsOneWidget,
      reason: 'another bundled food is still a duplicate',
    );
  });

  testWidgets('S-92c.10: padded and differently-cased names still match', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(
      tester,
      seed: _loadShippedCatalog,
    );
    final nameField = find.byKey(const Key('food_form_name'));

    await tester.enterText(nameField, ' chicken breast, skinless ');
    await tester.pump();
    expect(
      find.text(
        'There\'s already a food called "chicken breast, skinless" '
        'in the Library',
      ),
      findsOneWidget,
      reason: 'the note shows the trimmed text as typed',
    );

    await tester.enterText(nameField, 'CHICKEN BREAST, SKINLESS');
    await tester.pump();
    expect(
      find.text(
        'There\'s already a food called "CHICKEN BREAST, SKINLESS" '
        'in the Library',
      ),
      findsOneWidget,
      reason: 'the match ignores case; the note keeps what the user typed',
    );

    await _submit(tester, controller);
    expect(saved, hasLength(1));
    expect(saved.single.name, 'CHICKEN BREAST, SKINLESS');
  });

  testWidgets('S-92c.11: clearing the name hides the note', (tester) async {
    await _pumpForm(tester, seed: _loadShippedCatalog);
    final nameField = find.byKey(const Key('food_form_name'));

    await tester.enterText(nameField, ' chicken breast, skinless ');
    await tester.pump();
    expect(find.byKey(_duplicateNoteKey), findsOneWidget);

    await tester.enterText(nameField, '');
    await tester.pump();
    expect(
      find.byKey(_duplicateNoteKey),
      findsNothing,
      reason: 'a blank name is never a duplicate',
    );

    await tester.enterText(nameField, 'Chicken breast, skinless');
    await tester.pump();
    expect(
      find.byKey(_duplicateNoteKey),
      findsOneWidget,
      reason: 'typing the name again brings the note back',
    );
  });

  testWidgets('S-92c.12: two rows with the same name show one note', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(
      tester,
      seed: (state) async {
        await state.loadCatalogFoods();
        await state.createFood(
          _food(id: 'my-bar-1', name: 'My Bar', isCatalog: false),
        );
        await state.createFood(
          _food(id: 'my-bar-2', name: 'My Bar', isCatalog: false),
        );
        return null;
      },
    );

    await tester.enterText(find.byKey(const Key('food_form_name')), 'My Bar');
    await tester.pump();

    expect(
      find.byKey(_duplicateNoteKey),
      findsOneWidget,
      reason: 'the predicate is true once, whatever the number of matches',
    );

    await _submit(tester, controller);
    expect(
      saved,
      hasLength(1),
      reason: 'a third My Bar is still allowed',
    );
    expect(saved.single.name, 'My Bar');
  });

  testWidgets('S-92c.13: fractional macros agree on the line and the row', (
    tester,
  ) async {
    final (controller, saved) = await _pumpForm(tester);

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Half-fat spread',
    );
    await tester.enterText(find.byKey(const Key('food_form_fat')), '0.5');
    await tester.pump();

    expect(
      _line(tester, 'food_form_calories'),
      '= 5 cal',
      reason: '0.5 g of fat alone is 4.5 kcal, rounded half away from zero',
    );

    await _submit(tester, controller);
    final draft = saved.single;
    final stored = _food(
      id: 's13-half-fat',
      name: draft.name,
      protein: draft.protein,
      carbs: draft.carbs,
      fat: draft.fat,
      fiber: draft.fiber,
      sodium: draft.sodium,
    );

    expect(
      calculateCalories(stored),
      5,
      reason: 'the Library row reads the same stored food through the one '
          'formula (`<cal> cal per ...`, add_food_screen.dart)',
    );
    expect(
      _line(tester, 'food_form_calories'),
      '= ${calculateCalories(stored)} cal',
      reason: 'the form line and the Library row show the same number',
    );
  });
}
