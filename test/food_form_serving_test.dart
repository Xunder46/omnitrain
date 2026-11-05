// filepath: test/food_form_serving_test.dart
//
// Plan 92b — the food form's one serving question ("Nutrition facts are per").
// Scenario register: `docs/plans/2026-10-31-92b-serving-question-plan/`.
// Phase 2A covers S-92b.2 (Part 2A-i) and S-92b.3-5, 12, 13, 15 (Part
// 2A-ii); the edit-mode scenarios land in Phase 2B.
//
// `MockWorkoutRepository` only (the form is presentation-only; the save
// callback captures the draft), Mock-first per `docs/global_conventions.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

/// Tall, wide surface so the whole form and every segment fit.
const _formSurface = Size(800, 1800);

/// Labels of the segments currently selected on `food_form_basis`.
///
/// `SegmentedButton`'s type argument is the form's private basis enum, so the
/// widget is read dynamically and matched through its own `segments` list.
List<String> _selectedBasisLabels(WidgetTester tester) {
  final Widget widget = tester.widget(find.byKey(const Key('food_form_basis')));
  final dynamic basis = widget;
  final List<dynamic> segments = basis.segments as List<dynamic>;
  final Set<dynamic> selected = basis.selected as Set<dynamic>;
  return [
    for (final segment in segments)
      if (selected.contains(segment.value)) (segment.label as Text).data ?? '',
  ];
}

/// Pumps a New Food form on a surface tall enough for the whole form (the
/// serving row and the package row push it past the 1800 used by S-92b.2),
/// and returns the host controller plus the drafts the form handed to
/// `onSave`.
Future<(FoodFormController, List<FoodDraft>)> _pumpNewFoodForm(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
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
          initial: null,
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

/// Fills the required fields that are not under test, so a save attempt
/// only surfaces the serving control's own validation.
Future<void> _fillRequiredMacros(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('food_form_name')),
    'My Trail Mix',
  );
  await tester.enterText(find.byKey(const Key('food_form_protein')), '10');
  await tester.enterText(find.byKey(const Key('food_form_carbs')), '18');
  await tester.enterText(find.byKey(const Key('food_form_fat')), '12');
  await tester.pump();
}

/// The form's own validation + save path (the host CTA's entry point).
Future<void> _save(WidgetTester tester, FoodFormController controller) async {
  controller.submit();
  await tester.pumpAndSettle();
}

/// The line above the macros, or null when it is hidden (a plain 100 g /
/// 100 ml, which the selected toggle segment already says).
String? _heading(WidgetTester tester) {
  final finder = find.byKey(const Key('food_form_per_heading'));
  return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller?.text ?? '';

void _expectServing(
  FoodDraft draft,
  FoodUnitType unitType,
  double amount,
  String label,
) {
  expect(draft.unitType, unitType);
  expect(draft.referenceAmount, amount);
  expect(draft.referenceLabel, label);
}

const _servingWords = [
  'slice',
  'scoop',
  'bar',
  'piece',
  'cup',
  'tbsp',
  'tsp',
];

void _expectNoServingControls() {
  expect(find.byKey(const Key('food_form_serving_label')), findsNothing);
  for (final word in _servingWords) {
    expect(find.byKey(Key('food_form_serving_chip_$word')), findsNothing);
  }
}

/// The edit-mode note, when present.
String? _note(WidgetTester tester) {
  final finder = find.byKey(const Key('food_form_per_note'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

/// A catalog food for the edit-mode scenarios.
Food _catalogFood({
  required String id,
  required String name,
  FoodUnitType unitType = FoodUnitType.grams,
  double referenceAmount = 100,
  String referenceLabel = 'g',
  double protein = 10,
  double carbs = 20,
  double fiber = 2,
  double fat = 5,
  double? sodium = 100,
}) => Food(
  id: id,
  name: name,
  groupId: null,
  unitType: unitType,
  referenceAmount: referenceAmount,
  referenceLabel: referenceLabel,
  isCatalog: true,
  protein: protein,
  carbs: carbs,
  fiber: fiber,
  fat: fat,
  sodium: sodium,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

typedef _EditFixture = ({
  MockWorkoutRepository repo,
  FoodLibraryState state,
  Food loaded,
});

/// Seeds [seed] into the catalog and returns the loaded copy.
Future<_EditFixture> _seedEditFood(Food seed) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.seedCatalogFood(seed);
  final state = FoodLibraryState(repo);
  await state.loadCatalogFoods();
  final loaded = state.catalogFoods.firstWhere((f) => f.id == seed.id);
  return (repo: repo, state: state, loaded: loaded);
}

/// Pushes [EditFoodScreen] from a host route so a save can pop back to a
/// real screen and the test can see it close.
class _EditHost extends StatelessWidget {
  const _EditHost({required this.food, required this.foodLibraryState});

  final Food food;
  final FoodLibraryState foodLibraryState;

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
              ),
            ),
          ),
          child: const Text('open editor'),
        ),
      ),
    );
  }
}

Future<void> _openEditHost(
  WidgetTester tester, {
  required Food food,
  required FoodLibraryState state,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: _EditHost(food: food, foodLibraryState: state),
    ),
  );
  await tester.tap(find.text('open editor'));
  await tester.pumpAndSettle();
  expect(find.byType(EditFoodScreen), findsOneWidget);
}

/// Taps the edit host's bottom Save and waits for the screen to close.
Future<void> _tapEditSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('food_form_save')));
  await tester.pumpAndSettle();
  expect(find.byType(EditFoodScreen), findsNothing);
}

void _expectStoredTriple(
  Food? stored,
  FoodUnitType unitType,
  double amount,
  String label,
) {
  expect(stored, isNotNull);
  expect(stored!.unitType, unitType);
  expect(stored.referenceAmount, amount);
  expect(stored.referenceLabel, label);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FoodForm serving (S-92b)', () {
    testWidgets(
      'S-92b.2 New Food defaults to 100 g and saves grams / 100 / g',
      (tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        FoodDraft? captured;
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
                  captured = draft;
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The one serving control is there, on its 100 g segment …
        expect(find.byKey(const Key('food_form_basis')), findsOneWidget);
        expect(_selectedBasisLabels(tester), ['100 g']);
        // … the label above it asks the question, and no second line
        // repeats the answer …
        expect(find.text('Nutrition facts are per'), findsOneWidget);
        expect(_heading(tester), isNull);
        // … and the three old boxes are gone.
        expect(find.byKey(const Key('food_form_unit_type')), findsNothing);
        expect(
          find.byKey(const Key('food_form_reference_amount')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('food_form_reference_label')),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'My Trail Mix',
        );
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          '10',
        );
        await tester.enterText(find.byKey(const Key('food_form_carbs')), '18');
        await tester.enterText(find.byKey(const Key('food_form_fat')), '12');
        await tester.pump();
        controller.submit();
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.name, 'My Trail Mix');
        expect(captured!.unitType, FoodUnitType.grams);
        expect(captured!.referenceAmount, 100);
        expect(captured!.referenceLabel, 'g');
      },
    );

    testWidgets(
      'S-92b.3 100 ml saves grams / 100 / ml',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();

        expect(_selectedBasisLabels(tester), ['100 ml']);
        expect(_heading(tester), isNull);

        await _save(tester, controller);

        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.grams, 100, 'ml');
      },
    );

    testWidgets(
      'S-92b.4 1 serving requires a label and the chips fill it',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();

        // An empty label blocks the save and says why.
        await _save(tester, controller);
        expect(saved, isEmpty);
        expect(find.text('Name the serving, e.g. slice'), findsOneWidget);

        // The chip fills the field and the heading follows it.
        await tester.tap(find.byKey(const Key('food_form_serving_chip_slice')));
        await tester.pumpAndSettle();
        expect(_fieldText(tester, 'food_form_serving_label'), 'slice');
        expect(_heading(tester), 'Nutrition per 1 slice');

        await _save(tester, controller);
        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.count, 1, 'slice');

        // Typing a label instead of tapping a chip saves that label.
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'bar',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 1 bar');

        await _save(tester, controller);
        expect(saved, hasLength(2));
        _expectServing(saved.last, FoodUnitType.count, 1, 'bar');
      },
    );

    testWidgets(
      'S-92b.5 package serving sets the amount, and Back restores 100 g',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('food_form_package_amount')),
          findsOneWidget,
        );
        expect(_fieldText(tester, 'food_form_package_amount'), isEmpty);

        // An empty amount blocks the save.
        await _save(tester, controller);
        expect(saved, isEmpty);
        expect(find.text('Required'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '30',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 30 g');

        await _save(tester, controller);
        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.grams, 30, 'g');

        // Back to per 100 g closes the row and restores the base serving.
        expect(find.text('Back to per 100 g'), findsOneWidget);
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('food_form_package_amount')),
          findsNothing,
        );
        expect(_heading(tester), isNull);

        await _save(tester, controller);
        expect(saved, hasLength(2));
        _expectServing(saved.last, FoodUnitType.grams, 100, 'g');

        // The same row under 100 ml stores millilitres.
        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '250',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 250 ml');

        await _save(tester, controller);
        expect(saved, hasLength(3));
        _expectServing(saved.last, FoodUnitType.grams, 250, 'ml');
      },
    );

    testWidgets(
      'S-92b.12 a padded serving label saves trimmed',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          ' slice ',
        );
        await tester.pumpAndSettle();

        expect(_heading(tester), 'Nutrition per 1 slice');

        await _save(tester, controller);

        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.count, 1, 'slice');
      },
    );

    testWidgets(
      'S-92b.13 package amount 0 and . are rejected',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '0',
        );
        await _save(tester, controller);
        expect(saved, isEmpty);
        expect(find.text('Must be greater than 0'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '.',
        );
        await _save(tester, controller);
        expect(saved, isEmpty);
        expect(find.text('Must be a number'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '30',
        );
        await _save(tester, controller);

        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.grams, 30, 'g');
      },
    );

    testWidgets(
      'S-92b.15 chips are hidden off the serving segment',
      (tester) async {
        await _pumpNewFoodForm(tester);

        // The default 100 g segment shows neither the label nor the chips.
        _expectNoServingControls();

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        _expectNoServingControls();

        // Type a label on 1 serving, then leave and come back.
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('food_form_serving_label')),
          findsOneWidget,
        );
        for (final word in _servingWords) {
          expect(
            find.byKey(Key('food_form_serving_chip_$word')),
            findsOneWidget,
          );
        }
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'scoop',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        _expectNoServingControls();

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        _expectNoServingControls();

        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('food_form_serving_label')),
          findsOneWidget,
        );
        expect(_fieldText(tester, 'food_form_serving_label'), 'scoop');
        for (final word in _servingWords) {
          expect(
            find.byKey(Key('food_form_serving_chip_$word')),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'S-92b.18 switching segments keeps the typed label and amount',
      (tester) async {
        await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        // 1 serving: type a label.
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'bar',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 1 bar');

        // 100 g: open the package row and type an amount.
        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '30',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 30 g');

        // Back on 1 serving the label is still there.
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        expect(_fieldText(tester, 'food_form_serving_label'), 'bar');

        // Back on 100 g the package row is still open with 30.
        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        expect(find.text('Back to per 100 g'), findsOneWidget);
        expect(_fieldText(tester, 'food_form_package_amount'), '30');
        expect(_heading(tester), 'Nutrition per 30 g');
      },
    );

    testWidgets(
      'S-92b.6 an edited food opens on its stored serving and saves both ways',
      (tester) async {
        final egg = await _seedEditFood(
          _catalogFood(
            id: 'egg',
            name: 'Egg',
            unitType: FoodUnitType.count,
            referenceAmount: 1.0,
            referenceLabel: 'egg',
          ),
        );
        await _openEditHost(tester, food: egg.loaded, state: egg.state);

        expect(_selectedBasisLabels(tester), ['1 serving']);
        expect(_fieldText(tester, 'food_form_serving_label'), 'egg');
        expect(_heading(tester), 'Nutrition per 1 egg');

        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        await _tapEditSave(tester);
        _expectStoredTriple(
          await egg.repo.getCatalogFoodById('egg'),
          FoodUnitType.grams,
          100,
          'g',
        );

        final rice = await _seedEditFood(
          _catalogFood(id: 'rice', name: 'Rice'),
        );
        await _openEditHost(tester, food: rice.loaded, state: rice.state);
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'cup',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 1 cup');

        await _tapEditSave(tester);
        _expectStoredTriple(
          await rice.repo.getCatalogFoodById('rice'),
          FoodUnitType.count,
          1,
          'cup',
        );
      },
    );

    testWidgets(
      'S-92b.7 a package-stored food opens with its amount and keeps it on save',
      (tester) async {
        final fixture = await _seedEditFood(
          _catalogFood(
            id: 'beef_jerky',
            name: 'Beef jerky',
            referenceAmount: 28,
          ),
        );
        await _openEditHost(tester, food: fixture.loaded, state: fixture.state);

        expect(_fieldText(tester, 'food_form_package_amount'), '28');
        expect(_heading(tester), 'Nutrition per 28 g');

        await _tapEditSave(tester);
        _expectStoredTriple(
          await fixture.repo.getCatalogFoodById('beef_jerky'),
          FoodUnitType.grams,
          28,
          'g',
        );
      },
    );

    testWidgets(
      'S-92b.8 As saved round trips and restores the opened triple',
      (tester) async {
        final fixture = await _seedEditFood(
          _catalogFood(
            id: 'as_saved_food',
            name: 'Mayo',
            unitType: FoodUnitType.count,
            referenceAmount: 3,
            referenceLabel: 'tbsp',
          ),
        );
        await _openEditHost(tester, food: fixture.loaded, state: fixture.state);

        expect(_selectedBasisLabels(tester), ['As saved: 3 tbsp']);
        expect(_heading(tester), 'Nutrition per 3 tbsp');

        await _tapEditSave(tester);
        _expectStoredTriple(
          await fixture.repo.getCatalogFoodById('as_saved_food'),
          FoodUnitType.count,
          3,
          'tbsp',
        );

        // Reopen and walk away to 100 g and back.
        final second = await _seedEditFood(
          _catalogFood(
            id: 'as_saved_food',
            name: 'Mayo',
            unitType: FoodUnitType.count,
            referenceAmount: 3,
            referenceLabel: 'tbsp',
          ),
        );
        await _openEditHost(tester, food: second.loaded, state: second.state);

        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        expect(_heading(tester), isNull);
        expect(
          find.text('As saved: 3 tbsp'),
          findsOneWidget,
          reason: 'the segment stays visible once the loaded choice was '
              'as-saved',
        );

        // The fourth segment sits past the 800 px edge of the
        // horizontally scrolling segments row.
        await tester.ensureVisible(find.text('As saved: 3 tbsp'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('As saved: 3 tbsp'));
        await tester.pumpAndSettle();
        expect(_selectedBasisLabels(tester), ['As saved: 3 tbsp']);
        expect(_heading(tester), 'Nutrition per 3 tbsp');

        await _tapEditSave(tester);
        _expectStoredTriple(
          await second.repo.getCatalogFoodById('as_saved_food'),
          FoodUnitType.count,
          3,
          'tbsp',
        );
      },
    );

    testWidgets(
      'S-92b.9 the check line appears off the opened serving and hides again',
      (tester) async {
        final fixture = await _seedEditFood(
          _catalogFood(id: 'note_food', name: 'Oats'),
        );
        await _openEditHost(tester, food: fixture.loaded, state: fixture.state);

        expect(_note(tester), isNull);

        final proteinBefore = _fieldText(tester, 'food_form_protein');
        final carbsBefore = _fieldText(tester, 'food_form_carbs');
        final fatBefore = _fieldText(tester, 'food_form_fat');

        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'slice',
        );
        await tester.pumpAndSettle();

        expect(_note(tester), 'Check these numbers are per 1 slice');
        expect(_fieldText(tester, 'food_form_protein'), proteinBefore);
        expect(_fieldText(tester, 'food_form_carbs'), carbsBefore);
        expect(_fieldText(tester, 'food_form_fat'), fatBefore);

        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        expect(_note(tester), isNull);

        await _tapEditSave(tester);
        final stored = await fixture.repo.getCatalogFoodById('note_food');
        expect(stored, isNotNull);
        expect(stored!.protein, 10);
        expect(stored.carbs, 20);
        expect(stored.fat, 5);

        // A New Food never shows the note.
        await _pumpNewFoodForm(tester);
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'slice',
        );
        await tester.pumpAndSettle();
        expect(_note(tester), isNull);
      },
    );

    testWidgets(
      'S-92b.11 a millilitre food opens on 100 ml and saves it unchanged',
      (tester) async {
        final fixture = await _seedEditFood(
          _catalogFood(
            id: 'milk',
            name: 'Milk',
            referenceAmount: 100,
            referenceLabel: 'ml',
          ),
        );
        await _openEditHost(tester, food: fixture.loaded, state: fixture.state);

        expect(_selectedBasisLabels(tester), ['100 ml']);
        expect(_heading(tester), isNull);

        await _tapEditSave(tester);
        _expectStoredTriple(
          await fixture.repo.getCatalogFoodById('milk'),
          FoodUnitType.grams,
          100,
          'ml',
        );
      },
    );

    testWidgets(
      'S-92b.14 the package row survives a parent rebuild',
      (tester) async {
        await _pumpNewFoodForm(tester);

        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '30',
        );
        await tester.pumpAndSettle();

        // Change another field so the form rebuilds.
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'My Trail Mix',
        );
        await tester.pumpAndSettle();

        expect(find.text('Back to per 100 g'), findsOneWidget);
        expect(_fieldText(tester, 'food_form_package_amount'), '30');
        expect(_heading(tester), 'Nutrition per 30 g');
      },
    );

    testWidgets(
      'S-92b.16 both edit hosts render the same serving control',
      (tester) async {
        // EditFoodScreen host: a library copy of a bundled catalog food.
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();
        await state.addCatalogFoodToLibrary('chicken_breast');
        final copy = state.libraryFoodFor('chicken_breast')!;
        await _openEditHost(tester, food: copy, state: state);

        expect(find.byKey(const Key('food_form_basis')), findsOneWidget);
        expect(_selectedBasisLabels(tester), ['100 g']);
        expect(find.byKey(const Key('food_form_unit_type')), findsNothing);
        expect(
          find.byKey(const Key('food_form_reference_amount')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('food_form_reference_label')),
          findsNothing,
        );

        // The legacy edit shim, reached by tapping an isCatalog: false row.
        final legacyRepo = MockWorkoutRepository();
        await legacyRepo.initialize();
        final legacyState = FoodLibraryState(legacyRepo);
        await legacyState.loadFoodGroups();
        await legacyState.loadFoods();
        await legacyState.loadCatalogFoods();
        final nutrition = NutritionState(legacyRepo);
        await nutrition.loadConsumedToday();
        await nutrition.loadNutritionTarget();
        await legacyState.createFood(
          const Food(
            id: '',
            name: 'Legacy Oats',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            isCatalog: false,
            protein: 10,
            carbs: 20,
            fiber: 2,
            fat: 5,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await legacyState.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: AddFoodScreen(
              foodLibraryState: legacyState,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('catalog_search_field')),
          'Legacy Oats',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Legacy Oats'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Edit Food'), findsOneWidget);

        expect(find.byKey(const Key('food_form_basis')), findsOneWidget);
        expect(_selectedBasisLabels(tester), ['100 g']);
        expect(find.byKey(const Key('food_form_unit_type')), findsNothing);
        expect(
          find.byKey(const Key('food_form_reference_amount')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('food_form_reference_label')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'S-92b.19 the note is hidden while the package row reproduces the opened serving',
      (tester) async {
        final fixture = await _seedEditFood(
          _catalogFood(
            id: 'package_food',
            name: 'Yoghurt pot',
            referenceAmount: 30,
          ),
        );
        await _openEditHost(tester, food: fixture.loaded, state: fixture.state);

        expect(_fieldText(tester, 'food_form_package_amount'), '30');
        expect(_heading(tester), 'Nutrition per 30 g');
        expect(_note(tester), isNull);

        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '45',
        );
        await tester.pumpAndSettle();

        expect(_heading(tester), 'Nutrition per 45 g');
        expect(_note(tester), 'Check these numbers are per 45 g');
      },
    );

    testWidgets(
      'S-95.1 what the toggle opens sits clear of it, and the package '
      'button reads on one line',
      (tester) async {
        await _pumpNewFoodForm(tester);
        final toggleBottom = tester
            .getBottomLeft(find.byKey(const Key('food_form_basis')))
            .dy;

        // Package button: below the toggle with a gap, one line tall.
        final link = find.byKey(const Key('food_form_package_link'));
        expect(tester.getTopLeft(link).dy - toggleBottom, greaterThan(8));
        expect(tester.getSize(link).height, lessThan(56));

        // Its size field: below the button with a gap.
        await tester.tap(link);
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('food_form_package_amount'));
        expect(
          tester.getTopLeft(field).dy - tester.getBottomLeft(link).dy,
          greaterThan(8),
        );

        // "Called a…": below the toggle with a gap, so its label is not
        // drawn over the toggle.
        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        final called = find.byKey(const Key('food_form_serving_label'));
        expect(tester.getTopLeft(called).dy - toggleBottom, greaterThan(8));
      },
    );

    testWidgets(
      'S-95.2 the line above the macros shows only when it adds to the toggle',
      (tester) async {
        await _pumpNewFoodForm(tester);
        expect(_heading(tester), isNull, reason: '100 g repeats the toggle');

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        expect(_heading(tester), isNull, reason: '100 ml repeats the toggle');

        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '250',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 250 ml');

        await tester.tap(find.text('1 serving'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_serving_label')),
          'slice',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 1 slice');
      },
    );

    testWidgets(
      'switching g to ml and back with a package amount typed keeps the '
      'amount and follows the unit',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '250',
        );
        await tester.pumpAndSettle();
        expect(_heading(tester), 'Nutrition per 250 g');

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        expect(_fieldText(tester, 'food_form_package_amount'), '250');
        expect(_heading(tester), 'Nutrition per 250 ml');
        await _save(tester, controller);
        _expectServing(saved.last, FoodUnitType.grams, 250, 'ml');

        await tester.tap(find.text('100 g'));
        await tester.pumpAndSettle();
        expect(_fieldText(tester, 'food_form_package_amount'), '250');
        expect(_heading(tester), 'Nutrition per 250 g');
        await _save(tester, controller);
        _expectServing(saved.last, FoodUnitType.grams, 250, 'g');
      },
    );

    testWidgets(
      'an unusable package amount hides the heading and blocks Save',
      (tester) async {
        final (controller, saved) = await _pumpNewFoodForm(tester);
        await _fillRequiredMacros(tester);

        await tester.tap(find.text('100 ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();

        for (final (typed, error) in [
          ('', 'Required'),
          ('0', 'Must be greater than 0'),
          ('.', 'Must be a number'),
        ]) {
          await tester.enterText(
            find.byKey(const Key('food_form_package_amount')),
            typed,
          );
          await tester.pumpAndSettle();
          expect(_heading(tester), isNull, reason: 'typed "$typed"');

          await _save(tester, controller);
          expect(saved, isEmpty, reason: 'typed "$typed" must not save');
          expect(find.text(error), findsOneWidget, reason: 'typed "$typed"');
        }

        // Going back to the plain 100 ml saves the base serving.
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await _save(tester, controller);
        expect(saved, hasLength(1));
        _expectServing(saved.last, FoodUnitType.grams, 100, 'ml');
      },
    );
  });
}
