import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

Future<void> _pumpWorkoutSessionScreen(
  WidgetTester tester, {
  required WorkoutState workoutState,
  required RoutineState routineState,
  required SessionSummaryService sessionSummaryService,
}) async {
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
}

void main() {
  testWidgets('Exercise notes indicator updates after save and clear', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    // Pre-seed coach mark flags so the overlay never blocks button taps.
    await repository.setPreferenceBool('hint_seen_exercise_info', true);
    await repository.setPreferenceBool('hint_seen_exercise_notes', true);
    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    await workoutState.createNewSession(modality: 'resistance_lifting');
    final exercise = (await repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    await workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

    await _pumpWorkoutSessionScreen(
      tester,
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
    );

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-note-indicator')), findsNothing);

    await tester.tap(find.byKey(const Key('exercise-note-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Stay upright through the drive.',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-note-indicator')), findsOneWidget);

    await tester.tap(find.byKey(const Key('exercise-note-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-note-indicator')), findsNothing);
  });

  testWidgets('Adding an exercise loads an existing note into detail header', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    // Pre-seed coach mark flags so the overlay never blocks widget interaction.
    await repository.setPreferenceBool('hint_seen_exercise_info', true);
    await repository.setPreferenceBool('hint_seen_exercise_notes', true);
    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    final exercise = (await repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await repository.saveExerciseNote(
      ExerciseNote(
        id: 'note-${exercise.id}',
        exerciseId: exercise.id,
        note: 'Keep elbows high.',
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    await workoutState.createNewSession(modality: 'resistance_lifting');

    await _pumpWorkoutSessionScreen(
      tester,
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
    );

    // Empty session auto-opens the exercise picker. If the picker is not yet
    // visible (i.e. another code path), tap Icons.add to open it manually.
    if (find
        .widgetWithText(TextField, 'Search exercises...')
        .evaluate()
        .isEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Add Exercise'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises...'),
      exercise.name,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.text(exercise.name).last);
    await tester.pumpAndSettle();

    expect(find.text(exercise.name), findsWidgets);
    expect(find.byKey(const Key('exercise-note-indicator')), findsOneWidget);
  });
}
