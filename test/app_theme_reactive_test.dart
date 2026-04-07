import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

void main() {
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
    final settingsState = SettingsState(repository);
    await settingsState.initialize();
    final routineSessionService = RoutineSessionService(repository);
    final sessionSummaryService = SessionSummaryService(repository);

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
      ),
    );

    ThemeData themeData() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

    expect(themeData().colorScheme.primary.value, 0xFF2DE2E6);

    await settingsState.setAppTheme(AppTheme.obsidianVolt);
    await tester.pump();

    expect(themeData().colorScheme.primary.value, 0xFFEAE000);
  });
}
