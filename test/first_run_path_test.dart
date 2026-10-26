// First-run path tests (plan 77c, S-12910..S-12914).
//
// The home nutrition card says what it is ("Nutrition"), the empty
// Foods I Eat list leads to the picker, and the sodium chip is hidden
// on a day with nothing logged.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/widgets/nutrition_summary_card.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/calorie_ring_card.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/test_nutrition_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required int consumed,
  required int? target,
  Size surface = const Size(360, 600),
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: surface,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Center(
            child: NutritionSummaryCard(
              consumedCalories: consumed,
              targetCalories: target,
              proteinKcal: 0,
              carbsKcal: 0,
              fatKcal: 0,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpNutritionScreen(
  WidgetTester tester,
  MockWorkoutRepository repo,
) async {
  final primer = await buildNutritionPrimerState(repo, seen: true);
  final nutritionState = NutritionState(repo);
  final foodLibraryState = FoodLibraryState(repo);
  await foodLibraryState.loadFoodGroups();
  await foodLibraryState.loadFoods();

  await tester.pumpWidget(
    MaterialApp(
      home: NutritionScreen(
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
        nutritionPrimerState: primer,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('S-12910 — home card title and headline', () {
    testWidgets('shows the Nutrition label and the unchanged headline', (
      tester,
    ) async {
      await _pumpCard(tester, consumed: 0, target: 2000);

      expect(find.byKey(const Key('nutrition_card_title')), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(
        find.byKey(const Key('nutrition_card_headline_text')),
        findsOneWidget,
      );
      expect(find.text('0 / 2,000 Cal'), findsOneWidget);
    });

    group('no overflow at 320 wide and 2.0x text scale', () {
      testWidgets('scenario body', (tester) async {
        await _pumpCard(
          tester,
          consumed: 0,
          target: 2000,
          surface: const Size(320, 568),
          textScale: 2.0,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Nutrition'), findsOneWidget);
        expect(find.text('0 / 2,000 Cal'), findsOneWidget);
        // The figure is scaled to fit, not clipped: its painted box stays
        // inside the card and clear of the label.
        final card = tester.getRect(find.byType(NutritionSummaryCard));
        final figure = tester.getRect(
          find.byKey(const Key('nutrition_card_headline_text')),
        );
        final label = tester.getRect(
          find.byKey(const Key('nutrition_card_title')),
        );
        expect(figure.right, lessThanOrEqualTo(card.right));
        expect(figure.left, greaterThanOrEqualTo(label.right));
      });
    });
  });

  group('S-12911 — empty library leads to the picker', () {
    testWidgets('empty state with Choose foods button opens the library', (
      tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpNutritionScreen(tester, repo);

      expect(find.text('Pick the foods you eat'), findsOneWidget);
      expect(find.text('Your Foods I Eat list is empty.'), findsNothing);
      expect(find.text('Tap the pencil to add foods.'), findsNothing);

      // The button sits below the fold on the default test surface.
      await tester.ensureVisible(
        find.byKey(const Key('foods_i_eat_choose_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('foods_i_eat_choose_button')));
      await tester.pumpAndSettle();

      expect(find.text('Manage Food Library'), findsOneWidget);
    });
  });

  group('S-12912 — populated library has no empty state', () {
    testWidgets('empty state and choose button absent with a food', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-test',
          name: 'Test Group',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-test',
          name: 'Test Food',
          unitType: FoodUnitType.grams,
          groupId: 'g-test',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      await _pumpNutritionScreen(tester, repo);

      expect(find.text('Pick the foods you eat'), findsNothing);
      expect(find.byKey(const Key('foods_i_eat_choose_button')), findsNothing);
      expect(find.text('Test Food'), findsOneWidget);
    });
  });

  group('S-12913 — sodium chip hidden on an empty day', () {
    testWidgets('chip absent when nothing logged, present after logging', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutrition = NutritionState(repo);
      await nutrition.loadConsumedToday();
      await nutrition.loadNutritionTarget();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(nutritionState: nutrition, onEditTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nutrition_sodium_total')), findsNothing);
      final water = find.byKey(const Key('water_tracker_label'));
      expect(water, findsOneWidget);
      final cardCenter = tester.getCenter(find.byType(CalorieRingCard));
      expect(
        tester.getCenter(water).dx,
        greaterThan(cardCenter.dx),
        reason: 'Water control stays right of the card centre on an empty day',
      );

      // Log a food with an unusual sodium value: 731 mg per 100 g,
      // 100 g logged → "Na 731 mg".
      final food = Food(
        id: 'food-sodium-731',
        name: 'Salty Snack',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        protein: 5,
        carbs: 20,
        fat: 10,
        sodium: 731,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );
      await nutrition.logConsumedFoodAt(food, 100.0);
      await tester.pumpAndSettle();

      expect(find.text('Na 731 mg'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('water_tracker_label'))).dx,
        greaterThan(tester.getCenter(find.byType(CalorieRingCard)).dx),
        reason: 'Water control stays right of the card centre with the chip',
      );
    });
  });

  group('S-12914 — source guard', () {
    test('lib files carry the 77c changes', () {
      final summaryCard = File(
        'lib/features/home/widgets/nutrition_summary_card.dart',
      ).readAsStringSync();
      expect(summaryCard, contains('nutrition_card_title'));
      expect(summaryCard, contains("'Nutrition',"));

      final nutritionScreen = File(
        'lib/features/nutrition/nutrition_screen.dart',
      ).readAsStringSync();
      expect(nutritionScreen, contains('foods_i_eat_choose_button'));
      expect(nutritionScreen, isNot(contains('Tap the pencil')));

      final calorieRing = File(
        'lib/features/nutrition/widgets/calorie_ring_card.dart',
      ).readAsStringSync();
      expect(calorieRing, contains('todayConsumedSodium > 0'));
    });
  });
}
