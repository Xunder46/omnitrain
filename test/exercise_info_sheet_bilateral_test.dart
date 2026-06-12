import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

Future<void> _pumpSessionScreen(
  WidgetTester tester, {
  required WorkoutState workoutState,
  required RoutineState routineState,
  required SessionSummaryService sessionSummaryService,
  required MockWorkoutRepository repository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        timerAlertService: FakeTimerAlertService(),
        settingsState: SettingsState(repository, fakePreferencesService()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<({WorkoutState workoutState, RoutineState routineState, SessionSummaryService summaryService, MockWorkoutRepository repository})>
    _setUpSession() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  // Skip coach-mark overlays so they don't block button taps.
  await repository.setPreferenceBool('hint_seen_exercise_info', true);
  await repository.setPreferenceBool('hint_seen_exercise_notes', true);
  final workoutState = WorkoutState(repository);
  final routineState = RoutineState(repository);
  final summaryService = SessionSummaryService(repository);
  await workoutState.createNewSession(modality: 'resistance_lifting');
  return (
    workoutState: workoutState,
    routineState: routineState,
    summaryService: summaryService,
    repository: repository,
  );
}

void main() {
  // ── S-001: bilateral exercise shows LOGGING NOTE ─────────────────────────

  testWidgets('S-001: bilateral exercise shows LOGGING NOTE section', (
    WidgetTester tester,
  ) async {
    final ctx = await _setUpSession();

    // Find a bilateral exercise in the mock repo.
    final exercise = (await ctx.repository.getExercises()).firstWhere(
      (e) => e.capabilities.contains(ExerciseCapability.bilateral),
    );
    await ctx.workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );

    await _pumpSessionScreen(
      tester,
      workoutState: ctx.workoutState,
      routineState: ctx.routineState,
      sessionSummaryService: ctx.summaryService,
      repository: ctx.repository,
    );

    // Navigate to detail view.
    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    // Open the exercise info sheet.
    await tester.tap(find.byKey(const Key('exercise-info-button')));
    await tester.pumpAndSettle();

    expect(find.text('LOGGING NOTE'), findsOneWidget);
    expect(
      find.textContaining('Log both sides as a single combined set'),
      findsOneWidget,
    );
    expect(
      find.textContaining('30 lb × 10 reps'),
      findsOneWidget,
    );
  });

  // ── S-002: non-bilateral exercise does NOT show LOGGING NOTE ─────────────

  testWidgets('S-002: non-bilateral exercise does not show LOGGING NOTE', (
    WidgetTester tester,
  ) async {
    final ctx = await _setUpSession();

    // Find an exercise that is NOT bilateral.
    final exercise = (await ctx.repository.getExercises()).firstWhere(
      (e) =>
          e.capabilities.contains('reps') &&
          !e.capabilities.contains(ExerciseCapability.bilateral),
    );
    await ctx.workoutState.addExerciseToSession(
      exercise,
      chosenMetric: 'reps',
    );

    await _pumpSessionScreen(
      tester,
      workoutState: ctx.workoutState,
      routineState: ctx.routineState,
      sessionSummaryService: ctx.summaryService,
      repository: ctx.repository,
    );

    await tester.tap(find.text(exercise.name));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exercise-info-button')));
    await tester.pumpAndSettle();

    expect(find.text('LOGGING NOTE'), findsNothing);
  });

  // ── S-003: bilateral + no steps hides empty-state, shows note ────────────

  testWidgets(
    'S-003: bilateral exercise with no steps/image shows note and hides empty-state',
    (WidgetTester tester) async {
      final ctx = await _setUpSession();

      // Build a minimal bilateral exercise with no image or steps.
      final now = DateTime.now().millisecondsSinceEpoch;
      final exercise = Exercise(
        id: 'ex-bilateral-bare',
        name: 'Bare Bilateral',
        createdAtMs: now,
        updatedAtMs: now,
        capabilities: const [ExerciseCapability.bilateral],
      );
      await ctx.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );

      await _pumpSessionScreen(
        tester,
        workoutState: ctx.workoutState,
        routineState: ctx.routineState,
        sessionSummaryService: ctx.summaryService,
        repository: ctx.repository,
      );

      await tester.tap(find.text(exercise.name));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise-info-button')));
      await tester.pumpAndSettle();

      expect(find.text('LOGGING NOTE'), findsOneWidget);
      expect(find.text('No information available yet'), findsNothing);
    },
  );

  // ── S-004: non-bilateral with no image/steps shows empty state ────────────

  testWidgets(
    'S-004: non-bilateral exercise with no steps/image shows empty-state',
    (WidgetTester tester) async {
      final ctx = await _setUpSession();

      final now = DateTime.now().millisecondsSinceEpoch;
      final exercise = Exercise(
        id: 'ex-bare',
        name: 'Bare Exercise',
        createdAtMs: now,
        updatedAtMs: now,
      );
      await ctx.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );

      await _pumpSessionScreen(
        tester,
        workoutState: ctx.workoutState,
        routineState: ctx.routineState,
        sessionSummaryService: ctx.summaryService,
        repository: ctx.repository,
      );

      await tester.tap(find.text(exercise.name));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise-info-button')));
      await tester.pumpAndSettle();

      expect(find.text('LOGGING NOTE'), findsNothing);
      expect(find.text('No information available yet'), findsOneWidget);
    },
  );
}
