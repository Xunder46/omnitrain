// Plan 137, S-13705 — the Categories tab shows no trash control on the nine
// categories the app ships with, keeps it on a category the user made, and
// still lets a shipped category be renamed. Plain widget tests on the Mock
// repository only: a Hive write inside testWidgets' FakeAsync never settles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/shipped_food_groups.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

Future<void> _openCategories(
  WidgetTester tester,
  FoodLibraryState foodLib,
  NutritionState nutrition,
) async {
  await foodLib.loadFoodGroups();
  await tester.pumpWidget(
    MaterialApp(
      home: AddFoodScreen(foodLibraryState: foodLib, nutritionState: nutrition),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Categories'));
  await tester.pumpAndSettle();
}

void main() {
  group('Categories tab — shipped categories (plan 137)', () {
    testWidgets(
      'S-13705: no trash on any shipped category, trash on a custom one',
      (tester) async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final nutrition = NutritionState(repo);
        final customId = await foodLib.createFoodGroup('Snacks 2');

        await _openCategories(tester, foodLib, nutrition);

        expect(shippedFoodGroupIds.length, 9);
        for (final id in shippedFoodGroupIds) {
          expect(
            find.byKey(Key('group_name_$id'), skipOffstage: false),
            findsOneWidget,
            reason: 'shipped row $id is listed',
          );
          expect(
            find.byKey(Key('group_delete_$id'), skipOffstage: false),
            findsNothing,
            reason: 'shipped row $id has no trash control',
          );
        }
        expect(
          find.byKey(Key('group_name_$customId'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('group_delete_$customId'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('S-13705: a shipped category can still be renamed', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);

      await _openCategories(tester, foodLib, nutrition);

      final field = find.byKey(const Key('group_name_food-group-dairy'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Milk and Cheese');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final dairy = foodLib.foodGroups.firstWhere(
        (g) => g.id == 'food-group-dairy',
      );
      expect(dairy.name, 'Milk and Cheese');
      expect(dairy.isArchived, isFalse);
    });
  });
}
