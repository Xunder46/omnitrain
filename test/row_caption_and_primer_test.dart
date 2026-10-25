// Plan 77d — row caption and primer tests (S-13010..S-13014).
//
// The caption under a Foods I Eat amount box is the unit alone
// (`foodUnitCaption`), an unlogged thumbnail's corner ring carries
// `Icons.add`, and the nutrition primer rises over `NutritionScreen`
// (not over Home) on first open.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/log_food_row.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

Food _food(
  String id,
  String name,
  FoodUnitType unitType,
  double referenceAmount,
  String referenceLabel,
) => Food(
  id: id,
  name: name,
  unitType: unitType,
  referenceAmount: referenceAmount,
  referenceLabel: referenceLabel,
  protein: 0,
  carbs: 0,
  fat: 0,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

/// Pump a single [LogFoodRow] the way `test/nutrition_test.dart`'s
/// "LogFoodRow — log from library" group does.
Future<void> _pumpLogFoodRow(
  WidgetTester tester,
  MockWorkoutRepository repo,
  Food food,
) async {
  final nutrition = NutritionState(repo);
  final foodLib = FoodLibraryState(repo);
  await nutrition.loadConsumedToday();
  await foodLib.loadFoodGroups();
  await foodLib.loadFoods();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            LogFoodRow(
              food: food,
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Build a `HomeScreen` the way `test/home_nutrition_summary_card_test.dart`
/// does, with the primer state built by the shared helper so the test
/// controls whether the primer was already seen.
Future<HomeScreen> _buildHomeScreen(
  MockWorkoutRepository repo, {
  required bool primerSeen,
}) async {
  final workoutState = WorkoutState(repo);
  final homeState = HomeState(repo);
  await homeState.init();
  final routineState = RoutineState(repo);
  final routineSessionService = RoutineSessionService(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  final periodState = PeriodState(repo);
  final profileState = ProfileState(repo);
  await profileState.loadProfile();
  final prefs = FakePreferencesService();
  await prefs.init();
  final settingsState = SettingsState(repo, prefs);
  await settingsState.initialize();
  final nutritionState = NutritionState(repo);
  final foodLibraryState = FoodLibraryState(repo);
  final primerState = await buildNutritionPrimerState(repo, seen: primerSeen);

  return HomeScreen(
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    timerAlertService: FakeTimerAlertService(),
    nutritionState: nutritionState,
    foodLibraryState: foodLibraryState,
    nutritionPrimerState: primerState,
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );
}

void main() {
  group('S-13010: foodUnitCaption table', () {
    test('the caption is the unit alone', () {
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, 'g')),
        'g',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, 'ml')),
        'ml',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.count, 1, 'medium')),
        'medium',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, '100 g')),
        'g',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, 'per 100g')),
        'g',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, 'per 100 ml')),
        'ml',
      );
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.count, 1, 'egg white')),
        'egg white',
      );
      expect(foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, '')), '');
      // A label that is only a number has nothing left after stripping it:
      // the caption falls back to the label as stored.
      expect(
        foodUnitCaption(_food('f', 'f', FoodUnitType.grams, 100, '100')),
        '100',
      );
    });
  });

  group('S-13011: LogFoodRow caption is the unit alone', () {
    testWidgets('a 100 ml food shows caption "ml", box 100; typing keeps it', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-drinks-13011',
          name: 'Drinks 13011',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-oat-drink-13011',
          name: 'Oat Drink (13011)',
          unitType: FoodUnitType.grams,
          groupId: 'g-drinks-13011',
          referenceAmount: 100.0,
          referenceLabel: 'ml',
          protein: 1,
          carbs: 7,
          fat: 2,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final food = (await repo.getFoodById('f-oat-drink-13011'))!;

      await _pumpLogFoodRow(tester, repo, food);

      expect(find.text('ml'), findsOneWidget);
      expect(find.text('100 ml'), findsNothing);
      expect(find.text('100'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('log_food_amount_f-oat-drink-13011')),
        '250',
      );
      await tester.pumpAndSettle();

      expect(find.text('ml'), findsOneWidget);
      expect(find.text('100 ml'), findsNothing);
    });

    testWidgets('a count food shows caption "medium" and box 1', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-count-13011',
          name: 'Count 13011',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-kiwi-13011',
          name: 'Kiwi (13011)',
          unitType: FoodUnitType.count,
          groupId: 'g-count-13011',
          referenceAmount: 1.0,
          referenceLabel: 'medium',
          protein: 1,
          carbs: 14,
          fat: 1,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final food = (await repo.getFoodById('f-kiwi-13011'))!;

      await _pumpLogFoodRow(tester, repo, food);

      expect(find.text('medium'), findsOneWidget);
      expect(find.text('1 medium'), findsNothing);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('S-13012: thumbnail badge glyph follows the logged state', () {
    testWidgets('unlogged ring shows +; tapping logs and shows check', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-thumb-13012',
          name: 'Thumb 13012',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-plum-13012',
          name: 'Plum (13012)',
          unitType: FoodUnitType.count,
          groupId: 'g-thumb-13012',
          referenceAmount: 1.0,
          referenceLabel: 'medium',
          protein: 1,
          carbs: 11,
          fat: 0,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final food = (await repo.getFoodById('f-plum-13012'))!;

      await _pumpLogFoodRow(tester, repo, food);

      final thumb = find.byKey(const Key('log_food_thumb_f-plum-13012'));
      expect(thumb, findsOneWidget);
      expect(
        find.descendant(of: thumb, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: thumb, matching: find.byIcon(Icons.check)),
        findsNothing,
      );

      await tester.tap(thumb);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: thumb, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: thumb, matching: find.byIcon(Icons.add)),
        findsNothing,
      );
    });
  });

  group('S-13013: the primer rises over NutritionScreen, not Home', () {
    testWidgets(
      'unseen primer: home card opens the screen AND the sheet; dismiss '
      'marks seen; a second visit shows no sheet',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final repo = await _freshRepo();
        final homeScreen = await _buildHomeScreen(repo, primerSeen: false);
        final primerState = homeScreen.nutritionPrimerState;

        await tester.pumpWidget(MaterialApp(home: homeScreen));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nutrition_card')));
        await tester.pumpAndSettle();

        expect(find.text('Daily Nutrition'), findsOneWidget);
        expect(
          find.byKey(const Key('nutrition_primer_dismiss')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('nutrition_primer_dismiss')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('nutrition_primer_dismiss')), findsNothing);
        expect(primerState.shouldShowPrimer, isFalse);

        // Go back and tap the card again: no primer this time.
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nutrition_card')));
        await tester.pumpAndSettle();

        expect(find.text('Daily Nutrition'), findsOneWidget);
        expect(find.byKey(const Key('nutrition_primer_dismiss')), findsNothing);
      },
    );

    testWidgets('seen primer: tapping the card shows the screen, no sheet', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final repo = await _freshRepo();
      final homeScreen = await _buildHomeScreen(repo, primerSeen: true);

      await tester.pumpWidget(MaterialApp(home: homeScreen));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nutrition_card')));
      await tester.pumpAndSettle();

      expect(find.text('Daily Nutrition'), findsOneWidget);
      expect(find.byKey(const Key('nutrition_primer_dismiss')), findsNothing);
    });
  });

  group('S-13014: source guard — primer lives on NutritionScreen', () {
    test('home_screen.dart no longer shows the primer; nutrition_screen.dart '
        'does, with both markSeen modes', () {
      final homeSource = File(
        'lib/features/home/home_screen.dart',
      ).readAsStringSync();
      final nutritionSource = File(
        'lib/features/nutrition/nutrition_screen.dart',
      ).readAsStringSync();

      expect(homeSource, isNot(contains('_showNutritionPrimer')));
      expect(nutritionSource, contains('_showPrimer(markSeen: true)'));
      expect(nutritionSource, contains('_showPrimer(markSeen: false)'));
    });
  });
}
