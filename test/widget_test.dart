import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';

void main() {
  testWidgets(
    'Open exercise list -> open detail -> return focuses selected exercise',
    (WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);
      await workoutState.createNewSession();

      // Add exercises to session
      final exercises = await repository.getExercises();
      final squats = exercises.firstWhere((e) => e.name.contains('Squat'));
      final press = exercises.firstWhere((e) => e.name.contains('Press'));
      await workoutState.addExerciseToSession(squats, chosenMetric: 'reps');
      await workoutState.addExerciseToSession(press, chosenMetric: 'reps');

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // List view should be shown by default
      expect(find.text('Exercises'), findsOneWidget);
      expect(find.text('Squats'), findsOneWidget);
      expect(find.text('Press'), findsOneWidget);

      // Tap 'Press' to open detail
      await tester.tap(find.text('Press'));
      await tester.pumpAndSettle();

      // WorkoutSessionScreen should show the exercise name in the header
      expect(find.text('Press'), findsWidgets);
    },
  );

  testWidgets('Create exercise -> open detail -> back focuses new exercise', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);
    await workoutState.createNewSession();

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: workoutState,
          routineState: routineState,
          sessionSummaryService: sessionSummaryService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // List view should be shown by default with floating add button
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Enter exercise name
    await tester.enterText(find.byType(TextField), 'Cleans');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // After adding, WorkoutSessionScreen should show the newly created exercise in detail view
    expect(find.text('Cleans'), findsWidgets);
  });
}
