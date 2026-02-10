import 'package:flutter/material.dart';
import 'state/workout/workout_state.dart';
import 'features/home/home_screen.dart';

class MyApp extends StatelessWidget {
  final WorkoutState workoutState;

  const MyApp({super.key, required this.workoutState});

  @override
  Widget build(BuildContext context) {
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
        textTheme: textTheme,
      ),
      home: HomeScreen(workoutState: workoutState),
    );
  }
}
