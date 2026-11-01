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
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';

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

String _heading(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('food_form_per_heading')))
    .data!;

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

const _servingWords = ['slice', 'scoop', 'bar', 'piece', 'cup'];

void _expectNoServingControls() {
  expect(find.byKey(const Key('food_form_serving_label')), findsNothing);
  for (final word in _servingWords) {
    expect(find.byKey(Key('food_form_serving_chip_$word')), findsNothing);
  }
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
        // … the heading states it …
        expect(find.text('Nutrition facts are per'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('food_form_per_heading')))
              .data,
          'Nutrition per 100 g',
        );
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
        expect(_heading(tester), 'Nutrition per 100 ml');

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
        expect(_heading(tester), 'Nutrition per 100 g');

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
  });
}
