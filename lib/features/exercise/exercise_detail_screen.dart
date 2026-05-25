import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../state/routine/routine_state.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../state/settings/settings_state.dart';
import '../session/workout_session_screen.dart';

// Thin compatibility wrapper: forward to WorkoutSessionScreen so
// existing imports that referenced ExerciseDetailScreen continue to work.
class ExerciseDetailScreen extends StatelessWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final String effortId;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  ExerciseDetailScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    required this.effortId,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  Widget build(BuildContext context) {
    return WorkoutSessionScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      initialFocusId: effortId,
      settingsState: settingsState,
      timerAlertService: timerAlertService,
      restNotificationService: restNotificationService,
    );
  }
}
