import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
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

  testWidgets('Resistance logs create deterministic rest transitions', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    await workoutState.createNewSession(modality: 'resistance_lifting');

    final exercise = (await repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    final effortId = await workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );

    // Prepare 3 entries: first real, second skipped, third real.
    await workoutState.addEntry(effortId);
    await workoutState.addEntry(effortId);
    await workoutState.updateEntryValue(effortId, 0, 'reps', 8);
    await workoutState.updateEntryValue(effortId, 1, 'reps', 0);
    await workoutState.updateEntryValue(effortId, 2, 'reps', 6);

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

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    // Log set 1 (real): should start rest for entry 1.
    await tester.tap(find.text('Log Set'));
    await tester.pumpAndSettle();

    var rests = workoutState.getEntryRests(effortId);
    expect(rests.length, 1);
    expect(rests.first.entryIndex, 1);
    expect(rests.first.restEndMs, isNull);

    // Log set 2 (skipped): should not create/reset rest windows.
    await tester.tap(find.text('Log Set'));
    await tester.pumpAndSettle();

    rests = workoutState.getEntryRests(effortId);
    expect(rests.length, 1);
    expect(rests.first.entryIndex, 1);
    expect(rests.first.restEndMs, isNull);

    // Log set 3 (real): previous rest closes before next rest starts.
    await tester.tap(find.text('Log Set'));
    await tester.pumpAndSettle();

    rests = workoutState.getEntryRests(effortId)
      ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
    expect(rests.length, 2);

    final closedRest = rests.firstWhere((r) => r.entryIndex == 1);
    final openRest = rests.firstWhere((r) => r.entryIndex == 3);
    expect(closedRest.restEndMs, isNotNull);
    expect(openRest.restEndMs, isNull);

    final entries =
        workoutState.getExercisesWithEntries().first['entries'] as List;
    expect((entries[0] as Map<String, dynamic>)['reps'], 8);
    expect((entries[1] as Map<String, dynamic>)['reps'], 0);
    expect((entries[2] as Map<String, dynamic>)['reps'], 6);

    // Sanity check persisted model state reflects no duplicate open rests.
    final openCount = workoutState
        .getEntryRests(effortId)
        .where((r) => r.restEndMs == null)
        .length;
    expect(openCount, 1);
    expect(
      workoutState
          .getEntryRests(effortId)
          .every((EntryRest r) => r.effortId == effortId),
      isTrue,
    );
  });

  testWidgets('Resistance shows Rest overlay after logging set', (
    WidgetTester tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    await workoutState.createNewSession(modality: 'resistance_lifting');

    final exercise = (await repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    final effortId = await workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );
    await workoutState.addEntry(effortId);
    await workoutState.updateEntryValue(effortId, 0, 'reps', 10);

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

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log Set'));
    await tester.pumpAndSettle();

    expect(find.text('Rest'), findsOneWidget);
    final rests = workoutState.getEntryRests(effortId);
    expect(rests.isNotEmpty, isTrue);
    expect(rests.where((r) => r.restEndMs == null).length, 1);
  });

  testWidgets(
    'Resistance rest only appears after Log Set, not just from entering reps',
    (WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);

      await workoutState.createNewSession(modality: 'resistance_lifting');

      final exercise = (await repository.getExercises()).firstWhere(
        (e) => e.capabilities.contains('reps'),
      );
      final effortId = await workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      // Add second set so we can verify rest for next entry
      await workoutState.addEntry(effortId);

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
      await tester.tap(find.text(exercise.name));
      await tester.pumpAndSettle();

      // Before fix: entering reps caused _isSetLogged to return true,
      // which prevented rest creation on Log Set.
      // After fix: entering reps does NOT prevent rest creation.

      // Verify no rest yet
      var rests = workoutState.getEntryRests(effortId);
      expect(rests.isEmpty, isTrue,
          reason: 'No rest should exist before Log Set is pressed');

      // Click Log Set button to actually log the set
      await tester.tap(find.text('Log Set'));
      await tester.pumpAndSettle();

      // NOW rest should be created for the next entry (entryIndex=1)
      rests = workoutState.getEntryRests(effortId);
      expect(rests.isNotEmpty, isTrue,
          reason: 'Rest should be created after Log Set press');
      expect(rests.first.entryIndex, 1,
          reason: 'Rest should be for next entry (set 2)');
      expect(rests.first.restEndMs, isNull,
          reason: 'Rest should be open and running');

      // Verify we're on set 2 and rest overlay is visible
      expect(find.text('Rest'), findsOneWidget,
          reason: 'Rest overlay should be visible on set 2');
    },
  );

}
