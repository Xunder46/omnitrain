// PR 3 / S-002 — Labelled nutrition target control.
//
// Item 5 of the 2026-07-27 feedback pack replaces the icon-only
// `Icons.tune` gear on the Today card header with a labelled control
// whose text reflects the saved-target state:
//   - No target saved            → "Set target"
//   - Target already saved        → "Change target"
//
// The tap target still opens the same `NutritionTargetScreen`; the
// rest of the Nutrition screen is unchanged. The old key
// `edit_targets_icon` is gone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_target_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seed consumed-foods so the day-log is empty.
  repo.clearConsumedFoodsForTest();
  return repo;
}

Future<void> _pumpNutritionScreen(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  required NutritionState nutritionState,
  required FoodLibraryState foodLibraryState,
}) async {
  final primer = await buildNutritionPrimerState(repo);
  await tester.pumpWidget(
    MaterialApp(
      home: NutritionScreen(
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
        nutritionPrimerState: primer,
      ),
    ),
  );
  // Allow initState's loads (target + consumed + library) to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('S-002: nutrition target control is a labelled button', () {
    testWidgets(
      'S-002a: shows "Set target" when no target is saved',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        // The old icon-only `edit_targets_icon` key is gone.
        expect(find.byKey(const Key('edit_targets_icon')), findsNothing);

        // The new labelled control is present with the absent-target label.
        expect(
          find.byKey(const Key('nutrition_target_button')),
          findsOneWidget,
        );
        expect(find.text('Set target'), findsOneWidget);
      },
    );

    testWidgets(
      'S-002b: shows "Change target" when a target is already saved',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await nutritionState.saveNutritionTarget(
          NutritionTarget(calories: 2200),
        );
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        expect(
          find.byKey(const Key('nutrition_target_button')),
          findsOneWidget,
        );
        expect(find.text('Change target'), findsOneWidget);
        // The "Set target" label must not appear once a target is saved.
        expect(find.text('Set target'), findsNothing);
      },
    );

    testWidgets(
      'S-002c: tap opens the same NutritionTargetScreen',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        await tester.tap(find.byKey(const Key('nutrition_target_button')));
        await tester.pumpAndSettle();

        // The target-setting surface is unchanged.
        expect(find.byType(NutritionTargetScreen), findsOneWidget);
        expect(find.text('Daily Calorie Target'), findsOneWidget);
      },
    );

    testWidgets(
      'S-002d: tap opens the same screen when a target is already saved',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await nutritionState.saveNutritionTarget(
          NutritionTarget(calories: 1800),
        );
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        await tester.tap(find.byKey(const Key('nutrition_target_button')));
        await tester.pumpAndSettle();

        expect(find.byType(NutritionTargetScreen), findsOneWidget);
      },
    );

    testWidgets(
      'S-002e: the gear icon is no longer used as the only affordance',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await nutritionState.loadNutritionTarget();

        await _pumpNutritionScreen(
          tester,
          repo: repo,
          nutritionState: nutritionState,
          foodLibraryState: foodLibraryState,
        );

        // The icon-only tooltip button is gone.
        expect(
          find.byTooltip('Edit targets'),
          findsNothing,
          reason:
              'The icon-only tune gear has been replaced by a labelled '
              'control; no icon-only tooltip should remain on the Today '
              'card header.',
        );
      },
    );
  });
}
