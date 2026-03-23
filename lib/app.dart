import 'package:flutter/material.dart';
import 'core/constants/omni_theme.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';
import 'state/profile/profile_state.dart';
import 'state/settings/settings_state.dart';

import 'features/home/home_screen.dart';

class MyApp extends StatelessWidget {
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final CalendarState calendarState;
  final PeriodState periodState;
  final ProfileState profileState;
  final SettingsState settingsState;

  const MyApp({
    super.key,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.calendarState,
    required this.periodState,
    required this.profileState,
    required this.settingsState,
  });

  @override
  Widget build(BuildContext context) {
    // Custom text theme with explicit font sizes (accessibility-compliant)
    final textTheme = ThemeData.dark().textTheme.copyWith(
      labelSmall: const TextStyle(
        fontSize: 18,
        letterSpacing: 2,
        color: Colors.white,
      ),
      labelLarge: const TextStyle(
        fontSize: 18,
        letterSpacing: 2,
        color: Colors.white,
        decorationColor: Colors.white,
      ),
    );

    return ListenableBuilder(
      listenable: settingsState,
      builder: (context, child) {
        final activeTheme = settingsState.appTheme;
        OmniTheme.activeTheme = activeTheme;
        final tokens = OmniTheme.colorsForTheme(activeTheme);

        final ThemeData appTheme = buildTheme(
          theme: activeTheme,
          brightness: Brightness.dark,
          background: tokens.backgroundBottom,
          surface: tokens.surface,
          secondary: tokens.secondary,
          textPrimary: const Color(0xFFE6EDF3),
          textSecondary: tokens.textMuted,
          divider: tokens.divider,
        );

        return MaterialApp(
          title: 'Omnitrain',
          debugShowCheckedModeBanner: false,
          theme: appTheme.copyWith(textTheme: textTheme),
          // Splash screen temporarily disabled - showing home screen directly
          // home: OmniSplashScreen(workoutState: workoutState, homeState: homeState),
          home: HomeScreen(
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
      },
    );
  }
}

ThemeData buildTheme({
  AppTheme theme = AppTheme.abyssalNeon,
  required Brightness brightness,
  required Color secondary,
  required Color background,
  required Color surface,
  required Color textPrimary,
  required Color textSecondary,
  required Color divider,
}) {
  final primary = OmniTheme.colorsForTheme(theme).primary;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    error: Colors.red,
    onError: Colors.white,
    surface: surface,
    onSurface: textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    dividerColor: divider,
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: textPrimary),
      bodyMedium: TextStyle(color: textSecondary),
      labelLarge: TextStyle(color: textPrimary),
    ),
  );
}
