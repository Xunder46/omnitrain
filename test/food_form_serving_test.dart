// filepath: test/food_form_serving_test.dart
//
// Plan 92b — the food form's one serving question ("Nutrition facts are per").
// Scenario register: `docs/plans/2026-10-31-92b-serving-question-plan/`.
// Phase 2A covers S-92b.2; the remaining scenarios land in Phase 2B.
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
  });
}
