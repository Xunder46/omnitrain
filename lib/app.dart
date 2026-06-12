import 'package:flutter/material.dart';
import 'core/constants/omni_theme.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'data/repositories/workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';
import 'state/profile/profile_state.dart';
import 'state/settings/settings_state.dart';
import 'core/utils/timer_alert_service.dart';
import 'core/utils/rest_notification_service.dart';
import 'state/nutrition_state.dart';
import 'state/food_library_state.dart';

import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'widgets/layout/omni_gradient_background.dart';

class MyApp extends StatelessWidget {
  final WorkoutRepository repository;
  final bool showOnboarding;
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final CalendarState calendarState;
  final PeriodState periodState;
  final ProfileState profileState;
  final SettingsState settingsState;
  final NutritionState nutritionState;
  final FoodLibraryState foodLibraryState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  MyApp({
    super.key,
    required this.repository,
    required this.showOnboarding,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.calendarState,
    required this.periodState,
    required this.profileState,
    required this.settingsState,
    required this.nutritionState,
    required this.foodLibraryState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  Widget build(BuildContext context) {
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
          textPrimary: tokens.textDominant,
          textSecondary: tokens.textSecondary,
          divider: tokens.divider,
        );

        return MaterialApp(
          title: 'Omnitrain',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          // Global text scale clamp: honours accessibility scaling within a
          // sensible range. Below 0.9 text shrinks to unreadable; above 1.3
          // dense screens (session logger, calendar) feel tight but remain
          // functional. Configured here only — never re-implemented per screen.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final rawScale = mq.textScaler.scale(1.0);
            final clamped = rawScale.clamp(
              OmniTheme.kTextScaleMin,
              OmniTheme.kTextScaleMax,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(clamped)),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: OmniGradientBackground(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          // Splash screen temporarily disabled - showing home screen directly
          // home: OmniSplashScreen(workoutState: workoutState, homeState: homeState),
          home: showOnboarding
              ? OnboardingScreen(
                  repository: repository,
                  workoutState: workoutState,
                  homeState: homeState,
                  routineState: routineState,
                  routineSessionService: routineSessionService,
                  sessionSummaryService: sessionSummaryService,
                  calendarState: calendarState,
                  periodState: periodState,
                  profileState: profileState,
                  settingsState: settingsState,
                  timerAlertService: timerAlertService,
                  nutritionState: nutritionState,
                  foodLibraryState: foodLibraryState,
                  restNotificationService: restNotificationService,
                )
              : HomeScreen(
                  workoutState: workoutState,
                  homeState: homeState,
                  routineState: routineState,
                  routineSessionService: routineSessionService,
                  sessionSummaryService: sessionSummaryService,
                  calendarState: calendarState,
                  periodState: periodState,
                  profileState: profileState,
                  settingsState: settingsState,
                  timerAlertService: timerAlertService,
                  nutritionState: nutritionState,
                  foodLibraryState: foodLibraryState,
                  restNotificationService: restNotificationService,
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
    onPrimary: Colors.white,
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
    scaffoldBackgroundColor: Colors.transparent,
    dividerColor: divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      elevation: 0,
      backgroundColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.transparent,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      elevation: 0,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    textTheme: OmniTheme.buildTextTheme(
      textPrimary: textPrimary,
      textSecondary: textSecondary,
    ),
  );
}
