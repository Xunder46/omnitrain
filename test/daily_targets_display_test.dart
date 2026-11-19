// filepath: test/daily_targets_display_test.dart
//
// Plan 80 — daily targets on the donut focus text.
//
//   S-14035 — with a macro target the ring card's focused center
//             reads "<grams> of <target> g"; the Net Carbs slice
//             names "Carbs" and counts TOTAL carbs; fibre and
//             target-less macros keep the old form.
//   S-14036 — `MacroFocusContent` target forms in isolation.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/calorie_ring_card.dart';
import 'package:omnitrain/features/nutrition/widgets/macro_donut_chart.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log (same contract as `test/nutrition_test.dart`).
  repo.clearConsumedFoodsForTest();
  return repo;
}

/// Per-100g fixture: 80P / 180C (30 of it fibre) / 50F.
/// Net carbs = 150. Eaten 100 g.
Food _fixtureFood() => Food(
  id: 'target-fixture',
  name: 'Fixture',
  unitType: FoodUnitType.grams,
  referenceAmount: 100.0,
  referenceLabel: 'g',
  protein: 80,
  carbs: 180,
  fiber: 30,
  fat: 50,
  createdAtMs: 1,
  updatedAtMs: 1,
);

/// Build a state, optionally save a target BEFORE logging foods,
/// log the given foods, and pump the ring card.
Future<NutritionState> pumpRing(
  WidgetTester tester, {
  required List<({Food food, double amount})> entries,
  NutritionTarget? target,
}) async {
  final repo = await _freshRepo();
  final foodLib = FoodLibraryState(repo);
  final nutrition = NutritionState(repo);
  await nutrition.loadConsumedToday();
  await nutrition.loadNutritionTarget();
  if (target != null) {
    await nutrition.saveNutritionTarget(target);
  }
  for (final e in entries) {
    await foodLib.createFood(e.food);
    await nutrition.logConsumedFoodAt(e.food, e.amount);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CalorieRingCard(nutritionState: nutrition, onEditTap: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return nutrition;
}

/// Focus a donut slice by name by invoking the chart's focus
/// callback with the index the card derives (tapping by pixel is
/// not reliable in tests).
void focusSlice(WidgetTester tester, NutritionState nutrition, String name) {
  final sections = computeMacroSections(
    protein: nutrition.todayConsumedProtein,
    netCarbs: math.max(
      0,
      nutrition.todayConsumedCarbs - nutrition.todayConsumedFiber,
    ),
    fiber: nutrition.todayConsumedFiber,
    fat: nutrition.todayConsumedFat,
    gapDegrees: 1.5,
  );
  final index = sections.indexWhere((s) => s.name == name);
  expect(index, greaterThanOrEqualTo(0), reason: 'section $name must exist');
  tester
      .widget<MacroDonutChart>(find.byType(MacroDonutChart))
      .onSectionFocusChange!(index);
}

void main() {
  group('CalorieRingCard — focus text with macro targets (S-14035)', () {
    testWidgets('with targets 150/250/67 the focus reads "of target"; '
        'Net Carbs names "Carbs" and counts total carbs', (tester) async {
      final nutrition = await pumpRing(
        tester,
        entries: [(food: _fixtureFood(), amount: 100.0)],
        target: NutritionTarget(calories: 2000, protein: 150, carbs: 250, fat: 67),
      );

      // Protein: 80 g of the 150 g target.
      focusSlice(tester, nutrition, 'Protein');
      await tester.pump();
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('80 of 150 g'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Net Carbs slice: names "Carbs", shows TOTAL carbs (180 g,
      // fibre included) — not the net 150 g.
      focusSlice(tester, nutrition, 'Net Carbs');
      await tester.pump();
      expect(find.text('Carbs'), findsOneWidget);
      expect(find.text('180 of 250 g'), findsOneWidget);
      expect(find.text('150 of 250 g'), findsNothing);
      expect(find.textContaining('%'), findsNothing);

      // Fat: 50 g of the 67 g target.
      focusSlice(tester, nutrition, 'Fat');
      await tester.pump();
      expect(find.text('Fat'), findsOneWidget);
      expect(find.text('50 of 67 g'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      // Fiber: informational, unchanged.
      focusSlice(tester, nutrition, 'Fiber');
      await tester.pump();
      expect(find.text('Fiber'), findsOneWidget);
      expect(find.text('30 g'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('calories-only target keeps the old grams + percent form', (
      tester,
    ) async {
      final nutrition = await pumpRing(
        tester,
        entries: [(food: _fixtureFood(), amount: 100.0)],
        target: NutritionTarget(calories: 2000),
      );

      // Protein share: 320 / (320 + 600 + 450) = 23%.
      focusSlice(tester, nutrition, 'Protein');
      await tester.pump();
      expect(find.text('Protein'), findsOneWidget);
      expect(find.textContaining('80 g · '), findsOneWidget);

      // No carbs target → the slice keeps its "Net Carbs" name.
      focusSlice(tester, nutrition, 'Net Carbs');
      await tester.pump();
      expect(find.text('Net Carbs'), findsOneWidget);
    });
  });

  group('MacroFocusContent — target forms (S-14036)', () {
    Future<void> pumpFocus(
      WidgetTester tester, {
      required int grams,
      int? targetGrams,
      bool informational = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MacroFocusContent(
              name: 'Protein',
              grams: grams,
              percentOfCalories: 25,
              color: Colors.red,
              informational: informational,
              targetGrams: targetGrams,
            ),
          ),
        ),
      );
    }

    testWidgets('no target → grams + percent', (tester) async {
      await pumpFocus(tester, grams: 80);
      expect(find.text('80 g · 25%'), findsOneWidget);
    });

    testWidgets('target 150 → "80 of 150 g", no percent', (tester) async {
      await pumpFocus(tester, grams: 80, targetGrams: 150);
      expect(find.text('80 of 150 g'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('target 0 → old grams + percent form', (tester) async {
      await pumpFocus(tester, grams: 80, targetGrams: 0);
      expect(find.text('80 g · 25%'), findsOneWidget);
    });

    testWidgets('informational ignores the target', (tester) async {
      await pumpFocus(
        tester,
        grams: 30,
        targetGrams: 150,
        informational: true,
      );
      expect(find.text('30 g'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('of'), findsNothing);
    });
  });
}
