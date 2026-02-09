import 'package:flutter/material.dart';
import 'state/workout/workout_state.dart';
import 'features/home/home_screen.dart';

class MyApp extends StatelessWidget {
  final WorkoutState workoutState;

  const MyApp({super.key, required this.workoutState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omnitrain',
      theme: ThemeData.dark(useMaterial3: true),
      home: HomeScreen(workoutState: workoutState),
    );
  }
}
