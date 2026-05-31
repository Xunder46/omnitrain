import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

void main() {
  Future<
    ({
      MockWorkoutRepository repository,
      WorkoutState workoutState,
      RoutineState routineState,
      SessionSummaryService sessionSummaryService,
    })
  >
  setupStates({String? modality}) async {
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

  testWidgets('Finish workout finalizes active timed entries and session', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates(modality: 'cardio_endurance');
    final restService = FakeRestNotificationService();

    final exercises = await deps.repository.getExercises();
    final timedExercise = exercises.firstWhere(
      (e) => e.capabilities.contains('time'),
    );

    final effortId = await deps.workoutState.addExerciseToSession(
      timedExercise,
    );
    await deps.workoutState.startTimedEntry(effortId, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: SettingsState(deps.repository),
          restNotificationService: restService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(find.byType(SessionSummaryScreen), findsOneWidget);

    final session = deps.workoutState.currentSession;
    expect(session, isNotNull);
    expect(session!.endedAtMs, isNotNull);

    final timedEntries = deps.workoutState.getTimedInstancesForEffort(effortId);
    expect(timedEntries, isNotEmpty);
    expect(timedEntries.first.state, TimedState.finished);
    expect(restService.cancelCallCount, greaterThan(0));
  });

  testWidgets('empty free-training session exits immediately without dialog', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

    expect(deps.workoutState.currentSession?.modality, isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: SettingsState(deps.repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    // No dialog should appear — the screen just exits.
    expect(find.text('End empty session?'), findsNothing);
    expect(find.text('Finish Workout?'), findsNothing);
    // The WorkoutSessionScreen is no longer in the tree.
    expect(find.text('Finish Workout'), findsNothing);
  });

  testWidgets('Back after finish does not return to active workout screen', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

    // Add an exercise so the session is non-empty and goes through the
    // normal finish dialog → summary flow.
    final exercises = await deps.repository.getExercises();
    await deps.workoutState.addExerciseToSession(exercises.first);

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
                        workoutState: deps.workoutState,
                        routineState: deps.routineState,
                        sessionSummaryService: deps.sessionSummaryService,
                        timerAlertService: FakeTimerAlertService(),
                        settingsState: SettingsState(deps.repository),
                      ),
                    ),
                  );
                },
                child: const Text('Open Workout'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(find.byType(SessionSummaryScreen), findsOneWidget);

    // The summary screen shows a non-dismissible "How did it feel?" sheet.
    // Select a feeling to dismiss it before navigating back.
    if (find.text('How did it feel?').evaluate().isNotEmpty) {
      // Tap the "3" tile in the feeling sheet (last occurrence to avoid ambiguity)
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
    }

    // Navigate back from the summary screen to verify we don't return to the workout.
    final navState = tester.state<NavigatorState>(find.byType(Navigator).first);
    navState.pop();
    await tester.pumpAndSettle();

    expect(find.text('Open Workout'), findsOneWidget);
    expect(find.byType(WorkoutSessionScreen), findsNothing);
  });

  testWidgets('Finish workout finalizes active round and sets endedAtMs', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

    final exercises = await deps.repository.getExercises();
    final roundExercise = exercises.firstWhere(
      (e) => e.capabilities.contains('rounds'),
      orElse: () => exercises.first,
    );

    final effortId = await deps.workoutState.addExerciseToSession(
      roundExercise,
      effortKindOverride: 'round',
    );
    await deps.workoutState.startRound(effortId, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: SettingsState(deps.repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(find.byType(SessionSummaryScreen), findsOneWidget);

    final session = deps.workoutState.currentSession;
    expect(session, isNotNull);
    expect(session!.endedAtMs, isNotNull);

    final rounds = deps.workoutState.getRoundsForEffort(effortId);
    expect(rounds, isNotEmpty);
    expect(rounds.first.state, RoundState.finished);
  });

  testWidgets('Session summary shows Open Calendar button', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

    // Add an exercise so the session is non-empty and reaches the summary screen.
    final exercises = await deps.repository.getExercises();
    await deps.workoutState.addExerciseToSession(exercises.first);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
          timerAlertService: FakeTimerAlertService(),
          settingsState: SettingsState(deps.repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(find.byType(SessionSummaryScreen), findsOneWidget);

    // Dismiss the "How did it feel?" rating sheet if present.
    if (find.text('How did it feel?').evaluate().isNotEmpty) {
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
    }

    // Scroll down to ensure the calendar card (and Open Calendar button) is built.
    await tester.scrollUntilVisible(
      find.text('Open Calendar'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Open Calendar'), findsOneWidget);
  });

  test('finishing session closes the active open rest record', () async {
    final deps = await setupStates();
    final exercises = await deps.repository.getExercises();
    final exercise = exercises.firstWhere(
      (e) => e.capabilities.contains('set'),
      orElse: () => exercises.first,
    );

    final effortId = await deps.workoutState.addExerciseToSession(exercise);

    // Simulate a rest that started (as the timer mixin does after a set).
    await deps.workoutState.recordRestStart(effortId, 0);

    // End the session — persistOpenRests should close the open rest.
    await deps.workoutState.endSession();

    final rests = await deps.repository.getEntryRests(effortId);
    expect(rests, isNotEmpty);
    // The open rest must now be closed (restEndMs is non-null).
    expect(rests.first.restEndMs, isNotNull);
    // It must be closed at or before the session's endedAtMs.
    final endedAtMs = deps.workoutState.currentSession?.endedAtMs;
    expect(endedAtMs, isNotNull);
    expect(rests.first.restEndMs, lessThanOrEqualTo(endedAtMs!));
  });

  test('rest time shown on summary is non-zero after a single set with rest',
      () async {
    final deps = await setupStates();
    final exercises = await deps.repository.getExercises();
    final exercise = exercises.firstWhere(
      (e) => e.capabilities.contains('set'),
      orElse: () => exercises.first,
    );

    final effortId = await deps.workoutState.addExerciseToSession(exercise);

    // Simulate a rest that started at least 1 ms ago.
    await deps.workoutState.recordRestStart(effortId, 0);

    // Ensure endSession closes the open rest at a later timestamp.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await deps.workoutState.endSession();

    final restMs = await deps.sessionSummaryService.computeSessionRestTimeMs(
      deps.workoutState.currentSession!.id,
    );

    // Rest time should be at least 1 ms (a non-zero rest was recorded).
    expect(restMs, greaterThan(0));
    // And must not exceed the session duration.
    final session = deps.workoutState.currentSession!;
    final duration = session.endedAtMs! - session.startedAtMs;
    expect(restMs, lessThanOrEqualTo(duration));
  });
}
