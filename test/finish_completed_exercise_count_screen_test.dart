// Plan 217, Scenario S-21704:
// The Finish dialog counts only the exercises the user did.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
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
    'S-21704 the Finish dialog counts only the exercises the user did',
    (WidgetTester tester) async {
      final deps = await setupStates();

      final exercises = await deps.repository.getExercises();
      final loadExercises = exercises
          .where((e) => e.capabilities.contains('load'))
          .toList();
      final x = loadExercises.first;
      final y = loadExercises.firstWhere((e) => e.id != x.id);
      expect(x.id, isNot(y.id));

      final xEffortId = await deps.workoutState.addExerciseToSession(x);
      final yEffortId = await deps.workoutState.addExerciseToSession(y);

      // X: set 0 is logged (values + rest at position + 1), set 1 stays planned.
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'reps', 3);
      await deps.workoutState.updateEntryValue(xEffortId, 0, 'weight', 100.0);
      await deps.workoutState.recordRestStart(xEffortId, 1);
      await deps.workoutState.addEntry(
        xEffortId,
        previousValues: {'reps': 10, 'weight': 100.0},
      );

      // Y: its single seed entry stays planned only.

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

      expect(find.text('• 1 exercise'), findsOneWidget);
      expect(find.text('• 2 exercises'), findsNothing);

      await tester.tap(find.byKey(const Key('session-finish-cancel')));
      await tester.pumpAndSettle();

      // Log a set of Y the way X's was logged, through the state.
      await tester.runAsync(() async {
        await deps.workoutState.updateEntryValue(yEffortId, 0, 'reps', 5);
        await deps.workoutState.updateEntryValue(yEffortId, 0, 'weight', 50.0);
        await deps.workoutState.recordRestStart(yEffortId, 1);
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Workout'));
      await tester.pumpAndSettle();

      expect(find.text('• 2 exercises'), findsOneWidget);
      expect(find.text('• 1 exercise'), findsNothing);
    },
  );
}
