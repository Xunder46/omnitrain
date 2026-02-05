import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../session/workout_session_screen.dart';

// Thin compatibility wrapper: forward to WorkoutSessionScreen so
// existing imports that referenced ExerciseDetailScreen continue to work.
class ExerciseDetailScreen extends StatelessWidget {
  final WorkoutState workoutState;
  final String effortId;

  const ExerciseDetailScreen({super.key, required this.workoutState, required this.effortId});

  @override
  Widget build(BuildContext context) {
    return WorkoutSessionScreen(workoutState: workoutState, initialFocusId: effortId);
  }
}
