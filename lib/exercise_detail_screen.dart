import 'package:flutter/material.dart';
import 'workout_session_service.dart';
import 'screens/workout_session_screen.dart';

// Thin compatibility wrapper: forward to WorkoutSessionScreen so
// existing imports that referenced ExerciseDetailScreen continue to work.
class ExerciseDetailScreen extends StatelessWidget {
  final WorkoutSessionService sessionService;
  final String effortId;

  const ExerciseDetailScreen({super.key, required this.sessionService, required this.effortId});

  @override
  Widget build(BuildContext context) {
    return WorkoutSessionScreen(sessionService: sessionService, initialFocusId: effortId);
  }
}
