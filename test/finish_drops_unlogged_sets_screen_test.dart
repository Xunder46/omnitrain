import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
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
    'S-15709 Finishing a workout with planned sets nobody logged shows a summary of the logged work only',
    (WidgetTester tester) async {
      final deps = await setupStates();

      final exercises = await deps.repository.getExercises();
      final exercise = exercises.firstWhere(
        (e) =>
            e.capabilities.contains('load') && e.capabilities.contains('sets'),
        orElse: () => exercises.firstWhere(
          (e) => e.capabilities.contains('load'),
        ),
      );

      final effortId = await deps.workoutState.addExerciseToSession(exercise);

      // Set 0 is real: values, then logged the way the screen logs it.
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 3);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 100.0);
      await deps.workoutState.recordRestStart(effortId, 1);

      // Set 1 is a planned set nobody did.
      await deps.workoutState.addEntry(
        effortId,
        previousValues: {'reps': 10, 'weight': 100.0},
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

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
      await tester.pumpAndSettle();

      expect(find.byType(SessionSummaryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      final groups = EntryRows.setGroups(
        await deps.repository.getEffortObservations(effortId),
      );
      expect(groups, hasLength(1));
      expect((groups.single.entry['reps'] as int?) ?? 0, 3);
      expect((groups.single.entry['weight'] as double?) ?? 0.0, 100.0);

      final summary = deps.workoutState.computeSessionSummary();
      expect(summary.totalSets, 1);
      expect(summary.totalVolume, closeTo(300.0, 1e-9));

      // The screen's SETS pill shows the logged-set count, not the planned one.
      final setsLabel = find.text('SETS');
      expect(setsLabel, findsOneWidget);
      final pillColumn = find
          .ancestor(of: setsLabel, matching: find.byType(Column))
          .last;
      expect(find.descendant(of: pillColumn, matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: pillColumn, matching: find.text('2')), findsNothing);
    },
  );
}
