import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

void main() {
  test('Abyssal Neon uses neon cyan primary with white CTA text', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

    expect(colors.primary, const Color(0xFF2DE2E6));

    final theme = buildTheme(
      theme: AppTheme.abyssalNeon,
      brightness: Brightness.dark,
      background: colors.backgroundBottom,
      surface: colors.surface,
      secondary: colors.secondary,
      textPrimary: const Color(0xFFE6EDF3),
      textSecondary: colors.textMuted,
      divider: colors.divider,
    );

    expect(theme.colorScheme.onPrimary, Colors.white);
  });

  testWidgets('MyApp reacts to theme changes through SettingsState', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final workoutState = WorkoutState(repository);
    final homeState = HomeState(repository);
    await homeState.init();
    final routineState = RoutineState(repository);
    final calendarState = CalendarState(repository);
    final periodState = PeriodState(repository);
    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    final routineSessionService = RoutineSessionService(repository);
    final sessionSummaryService = SessionSummaryService(repository);
    final nutritionState = NutritionState(repository);
    final foodLibraryState = FoodLibraryState(repository);

    await tester.pumpWidget(
      MyApp(
        repository: repository,
        showOnboarding: false,
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
      ),
    );

    ThemeData themeData() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

    expect(
      themeData().colorScheme.primary.value,
      OmniTheme.colorsForTheme(AppTheme.abyssalNeon).primary.value,
    );
    expect(themeData().colorScheme.onPrimary, Colors.white);

    await settingsState.setAppTheme(AppTheme.obsidianVolt);
    await tester.pump();

    expect(
      themeData().colorScheme.primary.value,
      OmniTheme.colorsForTheme(AppTheme.obsidianVolt).primary.value,
    );
    expect(themeData().colorScheme.onPrimary, Colors.white);
  });
}
