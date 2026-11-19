// Plan 220 P1 — Finish with nothing logged discards the workout (screen side).
//
// S-22002: a workout where sets were typed but never logged gets a
// `Discard Workout?` dialog; Cancel keeps the session, Discard deletes it and
// leaves the screen.
// S-22003: a workout with something done keeps the normal `Finish Workout?`
// dialog and is never discarded.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
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

  testWidgets(
    'S-22002 Finish on a typed-but-unlogged workout asks to discard, then '
    'discards on confirm',
    (WidgetTester tester) async {
      final deps = await setupStates();

      final exercises = await deps.repository.getExercises();
      final x = exercises
          .where((e) => e.capabilities.contains('load'))
          .first;

      final xEffortId = await deps.workoutState.addExerciseToSession(x);

      // The user typed values but never tapped Log Set: no rest marks the set.
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'reps', 3);
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'weight', 100.0);

      final restService = FakeRestNotificationService();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(
              deps.repository,
              fakePreferencesService(),
            ),
            restNotificationService: restService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Workout'));
      await tester.pumpAndSettle();

      expect(find.text('Discard Workout?'), findsOneWidget);
      expect(
        find.text("Nothing was logged, so this workout won't be saved."),
        findsOneWidget,
      );
      expect(find.text('Finish Workout?'), findsNothing);

      await tester.tap(find.byKey(const Key('session-finish-nothing-cancel')));
      await tester.pumpAndSettle();

      expect(
        await deps.repository.getAllSessions(),
        hasLength(1),
        reason: 'Cancel keeps the workout open',
      );

      await tester.tap(find.text('Finish Workout'));
      await tester.pumpAndSettle();

      expect(find.text('Discard Workout?'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('session-finish-nothing-confirm')),
      );
      await tester.pumpAndSettle();

      expect(await deps.repository.getAllSessions(), isEmpty);
      expect(find.byType(SessionSummaryScreen), findsNothing);
    },
  );

  testWidgets(
    'S-22003 a workout with something done keeps the normal Finish dialog',
    (WidgetTester tester) async {
      final deps = await setupStates();

      final exercises = await deps.repository.getExercises();
      final x = exercises
          .where((e) => e.capabilities.contains('load'))
          .first;

      final xEffortId = await deps.workoutState.addExerciseToSession(x);

      // Set 0 is logged (values + rest at position + 1); set 1 is typed but
      // never logged.
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'reps', 3);
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'weight', 100.0);
      await deps.workoutState.recordRestStart(xEffortId, 1);
      await deps.workoutState.addEntry(
        xEffortId,
        previousValues: {'reps': 8, 'weight': 60.0},
      );

      final restService = FakeRestNotificationService();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(
              deps.repository,
              fakePreferencesService(),
            ),
            restNotificationService: restService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Workout'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Workout?'), findsOneWidget);
      expect(find.text('• 1 exercise'), findsOneWidget);
      expect(find.text('Discard Workout?'), findsNothing);

      await tester.tap(find.byKey(const Key('session-finish-cancel')));
      await tester.pumpAndSettle();
    },
  );
}
