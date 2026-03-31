import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

void main() {
  // ── Shared setup ──────────────────────────────────────────────────────────

  Future<
    ({
      MockWorkoutRepository repository,
      WorkoutState workoutState,
      RoutineState routineState,
      SessionSummaryService sessionSummaryService,
    })
  >
  setupEndedSession() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    await workoutState.createNewSession();
    final exercises = await repository.getExercises();
    await workoutState.addExerciseToSession(
      exercises.first,
      chosenMetric: 'reps',
    );
    await workoutState.endSession();

    return (
      repository: repository,
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
    );
  }

  Future<void> openEditScreen(
    WidgetTester tester, {
    required WorkoutState workoutState,
    required RoutineState routineState,
    required SessionSummaryService sessionSummaryService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutSessionScreen(
                        workoutState: workoutState,
                        routineState: routineState,
                        sessionSummaryService: sessionSummaryService,
                        editMode: true,
                      ),
                    ),
                  );
                },
                child: const Text('Open Edit Session'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Edit Session'));
    await tester.pumpAndSettle();
  }

  // ── WorkoutState.updateSessionEndTime unit tests ──────────────────────────

  group('WorkoutState.updateSessionEndTime', () {
    test('updates endedAtMs to startedAtMs + durationSecs * 1000', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = WorkoutState(repository);

      await state.createNewSession();
      await state.endSession(); // set endedAtMs

      final start = state.currentSession!.startedAtMs;
      const durationSecs = 3600; // 1 hour

      await state.updateSessionEndTime(durationSecs);

      expect(state.currentSession!.endedAtMs, start + durationSecs * 1000);
    });

    test('is a no-op when durationSecs is zero', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = WorkoutState(repository);

      await state.createNewSession();
      await state.endSession();

      final originalEnd = state.currentSession!.endedAtMs;

      await state.updateSessionEndTime(0);

      expect(state.currentSession!.endedAtMs, originalEnd);
    });

    test('is a no-op when durationSecs is negative', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = WorkoutState(repository);

      await state.createNewSession();
      await state.endSession();

      final originalEnd = state.currentSession!.endedAtMs;

      await state.updateSessionEndTime(-300);

      expect(state.currentSession!.endedAtMs, originalEnd);
    });

    test('persists to repository', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = WorkoutState(repository);

      await state.createNewSession();
      await state.endSession();

      final sessionId = state.currentSession!.id;
      const durationSecs = 1800; // 30 min

      await state.updateSessionEndTime(durationSecs);

      final persisted = await repository.getSession(sessionId);
      expect(
        persisted!.endedAtMs,
        state.currentSession!.startedAtMs + durationSecs * 1000,
      );
    });
  });

  // ── Screen widget tests ───────────────────────────────────────────────────

  group('Edit session duration — screen', () {
    testWidgets('Session Time chip is visible in list view during edit mode', (
      WidgetTester tester,
    ) async {
      final deps = await setupEndedSession();

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      // The chip label and edit icon should both be visible.
      expect(find.text('Session Time'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets(
        'Tapping Session Time chip opens Edit Session Duration dialog', (
      WidgetTester tester,
    ) async {
      final deps = await setupEndedSession();

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      await tester.tap(find.text('Session Time'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session Duration'), findsOneWidget);
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Sec'), findsOneWidget);
    });

    testWidgets('Cancelling the dialog leaves duration unchanged', (
      WidgetTester tester,
    ) async {
      final deps = await setupEndedSession();
      final originalEnd = deps.workoutState.currentSession!.endedAtMs;

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      await tester.tap(find.text('Session Time'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed, no change.
      expect(find.text('Edit Session Duration'), findsNothing);
      expect(deps.workoutState.currentSession!.endedAtMs, originalEnd);
    });

    testWidgets('Duration change triggers unsaved-changes dialog on back', (
      WidgetTester tester,
    ) async {
      final deps = await setupEndedSession();

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      // Open the duration dialog and apply a new value.
      await tester.tap(find.text('Session Time'));
      await tester.pumpAndSettle();

      // Set 1 hour 30 min 0 sec.
      final hField = find.widgetWithText(TextField, '0');
      await tester.enterText(hField.first, '1');
      final mField = find.widgetWithText(TextField, '00').first;
      await tester.tap(mField);
      await tester.enterText(mField, '30');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // We should be in list view. Tap back to trigger unsaved-changes dialog.
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();

      // The unsaved-changes dialog must appear.
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    testWidgets('Discarding reverts endedAtMs to original value', (
      WidgetTester tester,
    ) async {
      final deps = await setupEndedSession();
      final originalEnd = deps.workoutState.currentSession!.endedAtMs;

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      // Apply a new duration via the dialog.
      await tester.tap(find.text('Session Time'));
      await tester.pumpAndSettle();

      final hField = find.widgetWithText(TextField, '0');
      await tester.enterText(hField.first, '2');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Navigate back to trigger the unsaved-changes dialog.
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);

      // Choose Discard.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // endedAtMs should be unchanged (discard did not write to repo).
      expect(deps.workoutState.currentSession!.endedAtMs, originalEnd);
    });

    testWidgets('Saving persists corrected endedAtMs via updateSessionEndTime',
        (WidgetTester tester) async {
      final deps = await setupEndedSession();
      final startedAtMs = deps.workoutState.currentSession!.startedAtMs;

      await openEditScreen(
        tester,
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
      );

      // Apply exactly 1 hour (3600 s).
      await tester.tap(find.text('Session Time'));
      await tester.pumpAndSettle();

      final hField = find.widgetWithText(TextField, '0');
      await tester.enterText(hField.first, '1');
      // Leave min/sec as 00.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Tap "Save Changes" in the bottom bar.
      await tester.tap(find.text('Save Changes').last);
      await tester.pumpAndSettle();

      // endedAtMs must equal startedAtMs + 1 h.
      final expectedEnd = startedAtMs + 3600 * 1000;
      expect(deps.workoutState.currentSession!.endedAtMs, expectedEnd);
    });
  });
}
