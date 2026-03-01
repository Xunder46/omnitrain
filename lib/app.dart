import 'package:flutter/material.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';

import 'features/home/home_screen.dart';

class MyApp extends StatelessWidget {
  final WorkoutState workoutState;
  final HomeState homeState;
  final RoutineState routineState;
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;

  const MyApp({
    super.key,
    required this.workoutState,
    required this.homeState,
    required this.routineState,
    required this.routineSessionService,
    required this.sessionSummaryService,
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

    // Active theme: abyssalNeonDark
    final ThemeData abyssalNeonDark = buildTheme(
      brightness: Brightness.dark,
      background: Color(0xFF0B0F14),
      surface: Color(0xFF121826),
      primary: Color.fromARGB(207, 45, 227, 230),
      secondary: Color(0xFF1B9AAA),
      textPrimary: Color(0xFFE6EDF3),
      textSecondary: Color(0xFF9BA4B5),
      divider: Color(0xFF1F2937),
    );

    return MaterialApp(
      title: 'Omnitrain',
      debugShowCheckedModeBanner: false,
      theme: abyssalNeonDark.copyWith(textTheme: textTheme),
      // Splash screen temporarily disabled - showing home screen directly
      // home: OmniSplashScreen(workoutState: workoutState, homeState: homeState),
      home: HomeScreen(
        workoutState: workoutState,
        homeState: homeState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
      ),
    );
  }
}

ThemeData buildTheme({
  required Brightness brightness,
  required Color primary,
  required Color secondary,
  required Color background,
  required Color surface,
  required Color textPrimary,
  required Color textSecondary,
  required Color divider,
}) {
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
