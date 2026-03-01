import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../core/services/session_summary_service.dart';
import '../session/workout_session_screen.dart';

// Thin compatibility wrapper: forward to WorkoutSessionScreen so
// existing imports that referenced ExerciseDetailScreen continue to work.
class ExerciseDetailScreen extends StatelessWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final String effortId;

  const ExerciseDetailScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    required this.effortId,
  });

  @override
  Widget build(BuildContext context) {
    return WorkoutSessionScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      initialFocusId: effortId,
    );
  }
}
