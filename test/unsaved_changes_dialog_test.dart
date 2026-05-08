import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_timer_alert_service.dart';

void main() {
  Future<
    ({
      MockWorkoutRepository repository,
      WorkoutState workoutState,
      RoutineState routineState,
      SessionSummaryService sessionSummaryService,
      Exercise exercise,
    })
  >
  setupEditSession() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    // Pre-seed coach mark flags so the overlay never blocks button taps.
    await repository.setPreferenceBool('hint_seen_exercise_info', true);
    await repository.setPreferenceBool('hint_seen_exercise_notes', true);

    final workoutState = WorkoutState(repository);
    final routineState = RoutineState(repository);
    final sessionSummaryService = SessionSummaryService(repository);

    await workoutState.createNewSession();
    final exercises = await repository.getExercises();
    final exercise = exercises.first;
    await workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

    return (
      repository: repository,
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      exercise: exercise,
    );
  }

  int entryCount(WorkoutState workoutState) {
    final exercises = workoutState.getExercisesWithEntries();
    final entries = exercises.first['entries'] as List<dynamic>? ?? [];
    return entries.length;
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
                        timerAlertService: FakeTimerAlertService(),
                        settingsState: SettingsState(MockWorkoutRepository()),
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

  Future<void> createUnsavedStructuralChange(
    WidgetTester tester, {
    required String exerciseName,
  }) async {
    // Go to exercise detail
    await tester.tap(find.text(exerciseName).first);
    await tester.pumpAndSettle();

    // Add a set
    final addSetButton = find.byIcon(Icons.add);
    await tester.ensureVisible(addSetButton);
    await tester.tap(addSetButton);
    await tester.pumpAndSettle();

    // Back from detail to list view via custom back button
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();

    // Back from list to trigger unsaved dialog via custom back button
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);
  }

  testWidgets('Unsaved dialog close icon dismisses and keeps editing', (
    WidgetTester tester,
  ) async {
    final deps = await setupEditSession();

    await openEditScreen(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    await createUnsavedStructuralChange(
      tester,
      exerciseName: deps.exercise.name,
    );

    expect(find.text('Keep editing'), findsNothing);
    expect(find.byTooltip('Keep editing'), findsOneWidget);

    await tester.tap(find.byTooltip('Keep editing'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byType(WorkoutSessionScreen), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('Unsaved dialog discard rolls back structural changes', (
    WidgetTester tester,
  ) async {
    final deps = await setupEditSession();

    await openEditScreen(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    expect(entryCount(deps.workoutState), 1);

    await createUnsavedStructuralChange(
      tester,
      exerciseName: deps.exercise.name,
    );

    expect(entryCount(deps.workoutState), 2);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutSessionScreen), findsNothing);
    expect(find.text('Open Edit Session'), findsOneWidget);
    expect(entryCount(deps.workoutState), 1);
  });

  testWidgets('Unsaved dialog save keeps structural changes', (
    WidgetTester tester,
  ) async {
    final deps = await setupEditSession();

    await openEditScreen(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    expect(entryCount(deps.workoutState), 1);

    await createUnsavedStructuralChange(
      tester,
      exerciseName: deps.exercise.name,
    );

    expect(entryCount(deps.workoutState), 2);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutSessionScreen), findsNothing);
    expect(find.text('Open Edit Session'), findsOneWidget);
    expect(entryCount(deps.workoutState), 2);
  });

  testWidgets('Unsaved dialog renders without overflow in constrained width', (
    WidgetTester tester,
  ) async {
    final deps = await setupEditSession();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    binding.window.physicalSizeTestValue = const Size(280, 700);
    binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() {
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    await openEditScreen(
      tester,
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
    );

    await createUnsavedStructuralChange(
      tester,
      exerciseName: deps.exercise.name,
    );

    expect(find.widgetWithText(OutlinedButton, 'Discard'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
