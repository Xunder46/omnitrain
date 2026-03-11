import 'package:flutter/material.dart';
import 'app.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'data/repositories/hive_workout_repository.dart';
import 'data/repositories/workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';

/// Create the appropriate repository based on platform
///
/// Web: Always uses MockWorkoutRepository (in-memory, no persistence)
/// Native (iOS/Android): Would use SqliteWorkoutRepository when implemented
///
/// This pattern allows easy switching between environments without platform checks
/// scattered throughout the codebase
Future<WorkoutRepository> _createRepository() async {
  // Use Hive for local persistence across web and native.
  // SqliteWorkoutRepository can replace this on native later.
  return HiveWorkoutRepository();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize repository (injectable, can be swapped per environment)
    final repository = await _createRepository();
    await repository.initialize();

    // Create state with repository
    final workoutState = WorkoutState(repository);
    final homeState = HomeState();
    final routineState = RoutineState(repository);
    final calendarState = CalendarState(repository);
    final periodState = PeriodState(repository);

    // Create service with repository
    final routineSessionService = RoutineSessionService(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    runApp(
      MyApp(
        workoutState: workoutState,
        homeState: homeState,
        routineState: routineState,
        routineSessionService: routineSessionService,
        sessionSummaryService: sessionSummaryService,
        calendarState: calendarState,
        periodState: periodState,
      ),
    );
  } catch (e) {
    print('Error initializing app: $e');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error initializing app. Check console for details.'),
          ),
        ),
      ),
    );
  }
}
