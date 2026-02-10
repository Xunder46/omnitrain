import 'package:flutter/material.dart';
import 'state/workout/workout_state.dart';
import 'features/home/home_screen.dart';

class MyApp extends StatelessWidget {
  final WorkoutState workoutState;

  const MyApp({super.key, required this.workoutState});

  @override
  Widget build(BuildContext context) {
    // Custom dark color scheme with your preferred purple
    final colorScheme = ColorScheme.dark(
      primary: const Color(0xFFbc441c),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF21022d),
      onPrimaryContainer: Colors.white,
      secondary: const Color(0xFFbfbf31),
      onSecondary: Colors.black,
      surface: const Color(0xFF0c071e), // Dark background
      onSurface: Colors.white,
      error: const Color(0xFFd68473),
      onError: Color.fromARGB(255, 156, 0, 0),
    );

    // Custom text theme with explicit font sizes (accessibility-compliant)
    final textTheme = ThemeData.dark().textTheme.copyWith(
      labelSmall: const TextStyle(
        fontSize: 18,
        letterSpacing: 2,
        color: Colors.white
      ),
      labelLarge: const TextStyle(
        fontSize: 18,
        letterSpacing: 2,
        color: Colors.white,
        decorationColor: Colors.white
      ),
    );

    return MaterialApp(
      title: 'Omnitrain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: colorScheme,
        textTheme: textTheme,
      ),
      home: HomeScreen(workoutState: workoutState),
    );
  }
}
