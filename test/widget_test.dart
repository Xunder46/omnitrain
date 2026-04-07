import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';

Future<
  ({
    MockWorkoutRepository repository,
    WorkoutState workoutState,
    RoutineState routineState,
    SessionSummaryService sessionSummaryService,
  })
>
_setupSession({String modality = 'resistance_lifting'}) async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  final workoutState = WorkoutState(repository);
  final routineState = RoutineState(repository);
  final sessionSummaryService = SessionSummaryService(repository);
  await workoutState.createNewSession(modality: modality);
  return (
    repository: repository,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
  );
}

Future<void> _pumpSession(
  WidgetTester tester, {
  required WorkoutState workoutState,
  required RoutineState routineState,
  required SessionSummaryService sessionSummaryService,
  bool editMode = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        editMode: editMode,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Open exercise list -> tap detail -> shows exercise name in header',
    (WidgetTester tester) async {
      final deps = await _setupSession();

      final exercises = await deps.repository.getExercises();
      final squat = exercises.firstWhere((e) => e.name.contains('Squat'));
      final press = exercises.firstWhere((e) => e.name == 'Bench Press');
      await deps.workoutState.addExerciseToSession(squat, chosenMetric: 'reps');
      await deps.workoutState.addExerciseToSession(press, chosenMetric: 'reps');

      await _pumpSession(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      // List view should show exercise names
      expect(find.text(squat.name), findsOneWidget);
      expect(find.text(press.name), findsOneWidget);

      // Tap to open detail view
      await tester.tap(find.text(press.name));
      await tester.pumpAndSettle();

      // Header should show the exercise name
      expect(find.text(press.name), findsWidgets);
    },
  );

  testWidgets('Add exercise via picker adds to session list', (
    WidgetTester tester,
  ) async {
    final deps = await _setupSession();

    await _pumpSession(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    // Empty session auto-opens the exercise picker; close it so we can test
    // the manual add-button flow below.
    if (find.byIcon(Icons.close).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
    }

    // List view should show add button (FilledButton with Icons.add)
    expect(find.byIcon(Icons.add), findsWidgets);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    // Exercise picker dialog should open with search field
    expect(find.widgetWithText(TextField, 'Search exercises...'), findsOneWidget);

    // Search for an exercise
    await tester.enterText(
      find.widgetWithText(TextField, 'Search exercises...'),
      'Barbell Squat',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Tap the exercise in search results
    await tester.tap(find.text('Barbell Squat').last);
    await tester.pumpAndSettle();

    // Exercise should now be in the session
    expect(find.text('Barbell Squat'), findsWidgets);
  });

  testWidgets('Resistance logs create deterministic rest transitions', (
    WidgetTester tester,
  ) async {
    final deps = await _setupSession();

    final exercise = (await deps.repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    final effortId = await deps.workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );

    // Prepare 3 entries: first real, second skipped, third real.
    await deps.workoutState.addEntry(effortId);
    await deps.workoutState.addEntry(effortId);
    await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 8);
    await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 0);
    await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 6);

    await _pumpSession(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    // Log set 1 (real): should start rest for entry 1.
    await tester.tap(find.byTooltip('Log Set'));
    await tester.pumpAndSettle();

    var rests = deps.workoutState.getEntryRests(effortId);
    expect(rests.length, 1);
    expect(rests.first.entryIndex, 1);
    expect(rests.first.restEndMs, isNull);

    // Log set 2 (skipped): should not create/reset rest windows.
    await tester.tap(find.byTooltip('Log Set'));
    await tester.pumpAndSettle();

    rests = deps.workoutState.getEntryRests(effortId);
    expect(rests.length, 1);
    expect(rests.first.entryIndex, 1);
    expect(rests.first.restEndMs, isNull);

    // Log set 3 (real): previous rest closes before next rest starts.
    await tester.tap(find.byTooltip('Log Set'));
    await tester.pumpAndSettle();

    rests = List.of(deps.workoutState.getEntryRests(effortId))
      ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
    expect(rests.length, 2);

    final closedRest = rests.firstWhere((r) => r.entryIndex == 1);
    final openRest = rests.firstWhere((r) => r.entryIndex == 3);
    expect(closedRest.restEndMs, isNotNull);
    expect(openRest.restEndMs, isNull);

    final entries =
        deps.workoutState.getExercisesWithEntries().first['entries'] as List;
    expect((entries[0] as Map<String, dynamic>)['reps'], 8);
    expect((entries[1] as Map<String, dynamic>)['reps'], 0);
    expect((entries[2] as Map<String, dynamic>)['reps'], 6);

    // Sanity check: only one open rest at a time.
    final openCount = deps.workoutState
        .getEntryRests(effortId)
        .where((r) => r.restEndMs == null)
        .length;
    expect(openCount, 1);
    expect(
      deps.workoutState
          .getEntryRests(effortId)
          .every((EntryRest r) => r.effortId == effortId),
      isTrue,
    );
  });

  testWidgets('Resistance shows Rest overlay after logging set', (
    WidgetTester tester,
  ) async {
    final deps = await _setupSession();

    final exercise = (await deps.repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains('reps'),
    );
    final effortId = await deps.workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );
    await deps.workoutState.addEntry(effortId);
    await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);

    await _pumpSession(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Log Set'));
    await tester.pumpAndSettle();

    // Rest overlay should show the self_improvement icon
    expect(find.byIcon(Icons.self_improvement), findsOneWidget);
    final rests = deps.workoutState.getEntryRests(effortId);
    expect(rests.isNotEmpty, isTrue);
    expect(rests.where((r) => r.restEndMs == null).length, 1);
  });

  testWidgets(
    'Resistance rest only appears after Log Set, not just from entering reps',
    (WidgetTester tester) async {
      final deps = await _setupSession();

      final exercise = (await deps.repository.getExercises()).firstWhere(
        (e) => e.capabilities.contains('reps'),
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);

      await _pumpSession(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      await tester.tap(find.text(exercise.name));
      await tester.pumpAndSettle();

      // Verify no rest yet
      var rests = deps.workoutState.getEntryRests(effortId);
      expect(rests.isEmpty, isTrue,
          reason: 'No rest should exist before Log Set is pressed');

      // Click Log Set button
      await tester.tap(find.byTooltip('Log Set'));
      await tester.pumpAndSettle();

      // NOW rest should be created for the next entry
      rests = deps.workoutState.getEntryRests(effortId);
      expect(rests.isNotEmpty, isTrue,
          reason: 'Rest should be created after Log Set press');
      expect(rests.first.entryIndex, 1,
          reason: 'Rest should be for next entry (set 2)');
      expect(rests.first.restEndMs, isNull,
          reason: 'Rest should be open and running');

      // Verify rest overlay is visible (shows self_improvement icon, not "Rest" text)
      expect(find.byIcon(Icons.self_improvement), findsOneWidget,
          reason: 'Rest overlay should be visible on set 2');
    },
  );
}
