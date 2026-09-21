import 'package:flutter/material.dart';
import 'core/constants/omni_theme.dart';
import 'core/models/app_version_info.dart';
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
import 'state/watch/live_session_mirror_state.dart';
import 'core/utils/timer_alert_service.dart';
import 'core/utils/rest_notification_service.dart';
import 'state/nutrition_state.dart';
import 'state/food_library_state.dart';
import 'state/nutrition/nutrition_primer_state.dart';
import 'state/exercise/exercise_library_state.dart';

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
  final NutritionPrimerState nutritionPrimerState;
  final ExerciseLibraryState exerciseLibraryState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;
  final AppVersionInfo? appVersionInfo;

  /// The session running on the wrist, when this build has watch sync wired up.
  /// Null otherwise, and the home panel reserves nothing for it.
  final LiveSessionMirrorState? liveSession;

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
    required this.nutritionPrimerState,
    required this.exerciseLibraryState,
    required this.timerAlertService,
    this.appVersionInfo,
    this.liveSession,
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
          onPrimary: getOnPrimaryForTheme(activeTheme),
          onSecondary: getOnSecondaryForTheme(activeTheme),
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
                  nutritionPrimerState: nutritionPrimerState,
                  exerciseLibraryState: exerciseLibraryState,
                  restNotificationService: restNotificationService,
                  appVersionInfo: appVersionInfo,
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
                  exerciseLibraryState: exerciseLibraryState,
                  timerAlertService: timerAlertService,
                  nutritionState: nutritionState,
                  foodLibraryState: foodLibraryState,
                  nutritionPrimerState: nutritionPrimerState,
                  restNotificationService: restNotificationService,
                  appVersionInfo: appVersionInfo,
                  liveSession: liveSession,
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
  required Color onPrimary,
  required Color onSecondary,
}) {
  final primary = OmniTheme.colorsForTheme(theme).primary;

  // Per-theme container and outline roles (Iteration 2: D-8 through D-12)
  // D-8: outline = white at 0x66 (40%) — uniform across all themes
  // D-9: outlineVariant = white at 0x30 (19%) — matches surfaceBorder
  // D-10: surfaceContainerHighest ≥ 2 L* lighter than surface per theme
  // D-11: onSurfaceVariant clears 4.5:1 against surface
  // D-12: Complete role set for all six themes, no framework fallbacks

  const Color outlineGround = Color(0x66FFFFFF); // white at 0x66 (D-8)
  const Color outlineVariantGround = Color(0x30FFFFFF); // white at 0x30 (D-9)
  const Color onSurfaceVariantGround = Color(0x99FFFFFF); // white at 60% (D-11 constraint)

  late Color primaryContainer;
  late Color onPrimaryContainer;
  late Color secondaryContainer;
  late Color onSecondaryContainer;
  late Color tertiary;
  late Color onTertiary;
  late Color tertiaryContainer;
  late Color onTertiaryContainer;
  late Color surfaceContainerLowest;
  late Color surfaceContainerLow;
  late Color surfaceContainer;
  late Color surfaceContainerHigh;
  late Color surfaceContainerHighest;
  late Color onSurfaceVariant;
  late Color surfaceTint;
  late Color inverseSurface;
  late Color inverseOnSurface;
  late Color errorContainer;
  late Color onErrorContainer;
  late Color shadow;

  switch (theme) {
    case AppTheme.abyssalNeon:
      primaryContainer = const Color(0xFF1A3A42);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF1A3A42);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFF2DB8BF);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF1A2A35);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF0A1420);
      surfaceContainerLow = const Color(0xFF0F1F33);
      surfaceContainer = const Color(0xFF152A42);
      surfaceContainerHigh = const Color(0xFF1A3450);
      surfaceContainerHighest = const Color(0xFF1F3E5E); // ≥2 L* above surface #102842
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFE0E7F1);
      inverseOnSurface = const Color(0xFF0B1424);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);

    case AppTheme.forgeEmber:
      primaryContainer = const Color(0xFF3D2B1A);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF3D2B1A);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFFFF9B6A);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF2E2215);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF1A0D04);
      surfaceContainerLow = const Color(0xFF28160B);
      surfaceContainer = const Color(0xFF341D10);
      surfaceContainerHigh = const Color(0xFF402415);
      surfaceContainerHighest = const Color(0xFF4C2B1A); // ≥2 L* above surface #3A2712
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFEEDFD6);
      inverseOnSurface = const Color(0xFF1A0B05);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);

    case AppTheme.obsidianVolt:
      primaryContainer = const Color(0xFF2A2A1A);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF2A2A1A);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFFC49A00);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF1F1F15);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF0A0A0A);
      surfaceContainerLow = const Color(0xFF141414);
      surfaceContainer = const Color(0xFF1E1E1E);
      surfaceContainerHigh = const Color(0xFF282828);
      surfaceContainerHighest = const Color(0xFF323232); // ≥2 L* above surface #262626
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFE0E0E0);
      inverseOnSurface = const Color(0xFF0B0B0B);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);

    case AppTheme.voidPulse:
      primaryContainer = const Color(0xFF2A1F3D);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF2A1F3D);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFFC1A3FF);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF1F1730);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF0A0714);
      surfaceContainerLow = const Color(0xFF151028);
      surfaceContainer = const Color(0xFF1F1A3A);
      surfaceContainerHigh = const Color(0xFF292448);
      surfaceContainerHighest = const Color(0xFF332E56); // ≥2 L* above surface #2A2350
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFDDD1E7);
      inverseOnSurface = const Color(0xFF0A071A);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);

    case AppTheme.crimsonDojo:
      primaryContainer = const Color(0xFF4D2A25);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF4D2A25);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFFFF7B6D);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF3D2015);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF0D0402);
      surfaceContainerLow = const Color(0xFF1B0D08);
      surfaceContainer = const Color(0xFF27140F);
      surfaceContainerHigh = const Color(0xFF331B16);
      surfaceContainerHighest = const Color(0xFF3F221B); // ≥2 L* above surface #3A1A16
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFEED7D3);
      inverseOnSurface = const Color(0xFF1A0606);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);

    case AppTheme.malachiteCore:
      primaryContainer = const Color(0xFF2A3A2F);
      onPrimaryContainer = const Color(0xFFFFFFFF);
      secondaryContainer = const Color(0xFF2A3A2F);
      onSecondaryContainer = const Color(0xFFFFFFFF);
      tertiary = const Color(0xFF24B85A);
      onTertiary = const Color(0xFF000000);
      tertiaryContainer = const Color(0xFF1F2F22);
      onTertiaryContainer = const Color(0xFFFFFFFF);
      surfaceContainerLowest = const Color(0xFF050906);
      surfaceContainerLow = const Color(0xFF0D1610);
      surfaceContainer = const Color(0xFF161F18);
      surfaceContainerHigh = const Color(0xFF1F281F);
      surfaceContainerHighest = const Color(0xFF283227); // ≥2 L* above surface #182E1B
      onSurfaceVariant = onSurfaceVariantGround;
      surfaceTint = primary;
      inverseSurface = const Color(0xFFDFE5DC);
      inverseOnSurface = const Color(0xFF0C0F0A);
      errorContainer = const Color(0xFF7D0B0B);
      onErrorContainer = const Color(0xFFFFFFFF);
      shadow = const Color(0xFF000000);
  }

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: secondary,
    onSecondary: onSecondary,
    tertiary: tertiary,
    onTertiary: onTertiary,
    error: Colors.red,
    onError: Colors.white,
    surface: surface,
    onSurface: textPrimary,
    onSurfaceVariant: onSurfaceVariant,
    surfaceTint: surfaceTint,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    outline: outlineGround,
    outlineVariant: outlineVariantGround,
    scrim: shadow,
    inverseSurface: inverseSurface,
    onInverseSurface: inverseOnSurface,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    shadow: shadow,
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
