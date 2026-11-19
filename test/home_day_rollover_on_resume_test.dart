// filepath: test/home_day_rollover_on_resume_test.dart
//
// Plan 237, S-23706: resuming Home after midnight shows the new
// day, not yesterday's food.
//
// Screen-level copy of the harness of
// `test/home_nutrition_summary_card_test.dart` with a
// `NutritionState` built with a fake clock. Mock store only:
// no `Future.delayed`; pump with `tester.pump()` /
// `tester.pumpAndSettle()` exactly as the source file's
// "live update" test does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/preferences_service.dart'
    show PreferencesService;
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Variant of [_freshRepo] that wipes the seeded consumed-foods
/// after initialization.
Future<MockWorkoutRepository> _freshRepoCleanConsumed() async {
  final repo = await _freshRepo();
  repo.clearConsumedFoodsForTest();
  return repo;
}

class _FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

/// Per-100g chicken breast: 31P / 0C / 3F = 151 kcal, 0 fiber, 0 sodium.
Food _chicken() => Food(
  id: 'card-chicken',
  name: 'Chicken Breast',
  unitType: FoodUnitType.grams,
  referenceAmount: 100.0,
  referenceLabel: 'g',
  protein: 31,
  carbs: 0,
  fat: 3,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

Future<HomeScreen> _buildHomeScreen(
  MockWorkoutRepository repo,
  DateTime Function() clock,
) async {
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
  final prefs = _FakePreferencesService();
  await prefs.init();
  final settingsState = SettingsState(repo, prefs);
  await settingsState.initialize();
  final nutritionState = NutritionState(repo, clock: clock);
  final foodLibraryState = FoodLibraryState(repo);
  final nutritionPrimerState = await buildNutritionPrimerState(repo);

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
    nutritionPrimerState: nutritionPrimerState,
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );
}

/// Seed a per-100g chicken into the food library so
/// `nutritionState.logConsumedFoodAt(food, 200.0)` works.
Future<Food> _seedChicken(
  MockWorkoutRepository repo,
  NutritionState nutrition,
) async {
  final food = _chicken();
  final library = FoodLibraryState(repo);
  await library.createFood(food);
  await nutrition.loadConsumedToday();
  return food;
}

void main() {
  testWidgets('S-23706 resuming Home after midnight shows the new day, '
      'not yesterday\'s food', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await _freshRepoCleanConsumed();
    var now = DateTime(2026, 6, 15, 21);
    final homeScreen = await _buildHomeScreen(repo, () => now);

    await tester.pumpWidget(MaterialApp(home: homeScreen));
    await tester.pump();
    await tester.pumpAndSettle();

    final nutrition = homeScreen.nutritionState;
    await nutrition.saveNutritionTarget(NutritionTarget(calories: 2000));
    await tester.pumpAndSettle();

    final food = await _seedChicken(repo, nutrition);
    await nutrition.logConsumedFoodAt(food, 200.0);
    await tester.pumpAndSettle();

    // Yesterday's food, still "today" (15 June 21:00).
    expect(find.text('302 / 2,000 Cal'), findsOneWidget);

    // The app slept past midnight.
    now = DateTime(2026, 6, 16, 7);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // The new day: empty, same inherited target.
    expect(find.text('0 / 2,000 Cal'), findsOneWidget);
    expect(nutrition.consumedToday, isEmpty);
  });

  testWidgets(
    'S-27204 Home left open past midnight shows the new day without a '
    'resume (plan 272)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = await _freshRepoCleanConsumed();
      var now = DateTime(2026, 6, 15, 21);
      final homeScreen = await _buildHomeScreen(repo, () => now);

      await tester.pumpWidget(MaterialApp(home: homeScreen));
      await tester.pump();
      await tester.pumpAndSettle();

      final nutrition = homeScreen.nutritionState;
      await nutrition.saveNutritionTarget(NutritionTarget(calories: 2000));
      await tester.pumpAndSettle();
      final food = await _seedChicken(repo, nutrition);
      await nutrition.logConsumedFoodAt(food, 200.0);
      await tester.pumpAndSettle();
      expect(find.text('302 / 2,000 Cal'), findsOneWidget);

      // An hour later, same day: nothing happens.
      await tester.pump(const Duration(hours: 1));
      expect(find.text('302 / 2,000 Cal'), findsOneWidget);

      // Midnight passes while the app stays open on Home.
      now = DateTime(2026, 6, 16, 0, 0, 30);
      await tester.pump(const Duration(hours: 2, minutes: 1));
      await tester.pumpAndSettle();

      expect(find.text('0 / 2,000 Cal'), findsOneWidget);
      expect(nutrition.consumedToday, isEmpty);
    },
  );

  testWidgets('S-23706b resuming on the same day changes nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await _freshRepoCleanConsumed();
    var now = DateTime(2026, 6, 15, 21);
    final homeScreen = await _buildHomeScreen(repo, () => now);

    await tester.pumpWidget(MaterialApp(home: homeScreen));
    await tester.pump();
    await tester.pumpAndSettle();

    final nutrition = homeScreen.nutritionState;
    await nutrition.saveNutritionTarget(NutritionTarget(calories: 2000));
    await tester.pumpAndSettle();

    final food = await _seedChicken(repo, nutrition);
    await nutrition.logConsumedFoodAt(food, 200.0);
    await tester.pumpAndSettle();

    expect(find.text('302 / 2,000 Cal'), findsOneWidget);

    // Resume with the clock unchanged: a no-op rollover.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('302 / 2,000 Cal'), findsOneWidget);
    expect(nutrition.consumedToday, hasLength(1));
  });
}
