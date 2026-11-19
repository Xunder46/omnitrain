// Plan 265: Daily Nutrition keeps its scroll position and typed amounts when
// the screen reloads after Daily Targets, and the amount error shows under the
// row at full width.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

final DateTime _now = DateTime(2026, 11, 18, 10);

/// A repository whose target read can be held, to look at the screen mid-load.
class _GatedRepo extends MockWorkoutRepository {
  Completer<void>? gate;

  @override
  Future<NutritionTarget?> getNutritionTargetForDate(int dateMs) async {
    final g = gate;
    if (g != null) await g.future;
    return super.getNutritionTargetForDate(dateMs);
  }
}

Food _food(String id, String name) => Food(
  id: id,
  name: name,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 10,
  carbs: 10,
  fat: 10,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

Future<({_GatedRepo repo, NutritionState state})> _pump(
  WidgetTester tester, {
  int foodCount = 14,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = _GatedRepo();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  final foods = FoodLibraryState(repo);
  for (var i = 0; i < foodCount; i++) {
    await foods.createFood(_food('f$i', 'Food $i'));
  }
  final state = NutritionState(repo, clock: () => _now);
  await state.loadConsumedToday();
  await state.loadWaterForToday();
  await state.loadNutritionTarget();
  final primer = await buildNutritionPrimerState(repo, seen: true);
  await tester.pumpWidget(
    MaterialApp(
      home: NutritionScreen(
        nutritionState: state,
        foodLibraryState: foods,
        nutritionPrimerState: primer,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (repo: repo, state: state);
}

double _scrollPixels(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

void main() {
  testWidgets('S-26501 a reload keeps the scroll position and typed amount', (
    tester,
  ) async {
    final d = await _pump(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump();

    // An amount typed into a food that is not logged yet (the field scrolls
    // itself into view, so read the position after typing).
    await tester.enterText(find.byKey(const Key('log_food_amount_f2')), '7');
    await tester.pump();
    // Opening Daily Targets takes the focus (and the keyboard) away.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final before = _scrollPixels(tester);
    expect(before, greaterThan(100));

    // What coming back from Daily Targets does: reload the target, slowly.
    d.repo.gate = Completer<void>();
    final loading = d.state.loadNutritionTarget();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_scrollPixels(tester), before);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('log_food_amount_f2')))
          .controller!
          .text,
      '7',
    );

    d.repo.gate!.complete();
    await loading;
    await tester.pump();
    expect(_scrollPixels(tester), before);
  });

  testWidgets('S-26502 the amount error sits under the row at full width', (
    tester,
  ) async {
    await _pump(tester, foodCount: 2);

    await tester.enterText(find.byKey(const Key('log_food_amount_f0')), '0');
    await tester.pump();

    final error = find.byKey(const Key('log_food_amount_error_f0'));
    expect(error, findsOneWidget);
    expect(find.text('Amount must be greater than 0'), findsOneWidget);
    final field = tester.getRect(find.byKey(const Key('log_food_amount_f0')));
    final message = tester.getRect(error);
    // Below the amount box, and far wider than the 73 dp box.
    expect(message.top, greaterThanOrEqualTo(field.bottom));
    expect(message.width, greaterThan(250));
    // The box itself no longer carries the message.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('log_food_amount_f0')))
          .decoration!
          .errorText,
      isNull,
    );
  });
}
