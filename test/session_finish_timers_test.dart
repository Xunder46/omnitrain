import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

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
  });

  testWidgets('Back after finish does not return to active workout screen', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

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

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Open Workout'), findsOneWidget);
    expect(find.byType(WorkoutSessionScreen), findsNothing);
  });

  testWidgets('Session summary Open Calendar button navigates to calendar', (
    WidgetTester tester,
  ) async {
    final deps = await setupStates();

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutSessionScreen(
          workoutState: deps.workoutState,
          routineState: deps.routineState,
          sessionSummaryService: deps.sessionSummaryService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await tester.pumpAndSettle();

    expect(find.byType(SessionSummaryScreen), findsOneWidget);
    expect(find.text('Open Calendar'), findsOneWidget);

    await tester.tap(find.text('Open Calendar'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarScreen), findsOneWidget);
  });
}
