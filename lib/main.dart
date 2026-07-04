import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';
import 'core/services/image_storage_service.dart';
import 'core/services/preferences_service.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'data/repositories/hive_workout_repository.dart';
import 'data/repositories/workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';
import 'state/profile/profile_state.dart';
import 'state/settings/settings_state.dart';
import 'state/nutrition_state.dart';
import 'state/food_library_state.dart';
import 'state/nutrition/nutrition_primer_state.dart';
import 'core/utils/timer_alert_service.dart';
import 'core/utils/rest_notification_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Create the appropriate repository based on platform
///
/// Web: Always uses MockWorkoutRepository (in-memory, no persistence)
/// Native (iOS/Android): Would use SqliteWorkoutRepository when implemented
///
/// This pattern allows easy switching between environments without platform checks
/// scattered throughout the codebase
Future<WorkoutRepository> _createRepository() async {
  // Use Hive for local persistence across web and native.
  // SqliteWorkoutRepository can replace this on native later.
  return HiveWorkoutRepository();
}

Future<void> _initializeLocalTimezone() async {
  tzdata.initializeTimeZones();
  if (kIsWeb) {
    return;
  }

  try {
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));
  } catch (_) {
    // Keep tz.local as the default fallback when platform timezone lookup fails.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeLocalTimezone();
  try {
    // Initialize services
    final preferencesService = PreferencesServiceImpl();
    await preferencesService.init();

    // Initialize repository (injectable, can be swapped per environment)
    final repository = await _createRepository();
    await repository.initialize();

    // Check first-launch onboarding flag
    final onboardingComplete = await repository.getPreferenceBool(
      'onboarding_complete',
    );
    final showOnboarding = !onboardingComplete;

    // Native-only image storage helper (Phase 2 of the
    // image-persistence fix plan). Owns the managed directory
    // `<applicationDocumentsDirectory>/omni_images/` and is the
    // sole gate for the pick-and-store flow on profile avatars and
    // food photos. Construction resolves the documents directory
    // once at app start; the same instance is shared by every
    // state and screen that needs it (D-8).
    // On web, skip initialization as it's not supported there.
    final imageStorageService = kIsWeb ? null : await ImageStorageService.create();

    // Create state with repository
    final workoutState = WorkoutState(repository);
    final homeState = HomeState(repository);
    await homeState.init();
    final routineState = RoutineState(repository);
    final calendarState = CalendarState(repository);
    final periodState = PeriodState(repository);
    final profileState = ProfileState(
      repository,
      imageStorage: imageStorageService,
    );
    final settingsState = SettingsState(repository, preferencesService);
    await settingsState.initialize();
    final nutritionState = NutritionState(repository);
    await nutritionState.loadNutritionTarget();
    final foodLibraryState = FoodLibraryState(
      repository,
      imageStorage: imageStorageService,
    );
    // One-shot Daily Nutrition primer state. Hydrated eagerly
    // so the first home-strip tap consults the persisted
    // seen-flag from frame 1 (no flicker of the auto-show).
    final nutritionPrimerState = NutritionPrimerState(repository);
    await nutritionPrimerState.init();
    final timerAlertService = TimerAlertService();
    await timerAlertService.initialize();
    final restNotificationService = RestNotificationService();
    await restNotificationService.initialize();

    // Create service with repository
    final routineSessionService = RoutineSessionService(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    runApp(
      MyApp(
        repository: repository,
        showOnboarding: showOnboarding,
        workoutState: workoutState,
        homeState: homeState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
        calendarState: calendarState,
        periodState: periodState,
        profileState: profileState,
        settingsState: settingsState,
        nutritionState: nutritionState,
        foodLibraryState: foodLibraryState,
        nutritionPrimerState: nutritionPrimerState,
        timerAlertService: timerAlertService,
        restNotificationService: restNotificationService,
      ),
    );
  } catch (e) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error initializing app. Check console for details.'),
          ),
        ),
      ),
    );
  }
}
