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

Future<
  ({
    WorkoutState workoutState,
    RoutineState routineState,
    SessionSummaryService summaryService,
    MockWorkoutRepository repository,
  })
>
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

    // Source the exercise via the SAME path the picker uses, so a regression
    // anywhere in picker → session cache chain is caught (this is the real
    // hydration path).
    final exercise = (await ctx.workoutState.getExercisesRankedForModality(
      modality: 'resistance_lifting',
    )).firstWhere((e) => e.capabilities.contains(ExerciseCapability.bilateral));
    await ctx.workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

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
    expect(find.textContaining('20 kg × 10 reps'), findsOneWidget);
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
    await ctx.workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

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

  // ── S-006: addExerciseToSession hydrates capabilities from the repo ──────
  //
  // Verifies that an Exercise whose capabilities list is empty when passed
  // into addExerciseToSession still ends up with the canonical (repository)
  // capabilities once cached — i.e. the session path doesn't trust the
  // caller's payload blindly. Without the fix, the cached exercise keeps the
  // empty list and the bilateral note never shows in the info sheet.
  test(
    'S-006: addExerciseToSession hydrates capabilities from repository',
    () async {
      final ctx = await _setUpSession();

      // Build an Exercise whose id matches a seeded bilateral exercise but
      // whose capabilities are deliberately empty (as if the caller had a
      // stale or otherwise incomplete Exercise object).
      final now = DateTime.now().millisecondsSinceEpoch;
      final exerciseWithoutCaps = Exercise(
        id: 'exercise-dumbbell-curl',
        name: 'Dumbbell Curl',
        createdAtMs: now,
        updatedAtMs: now,
        capabilities: const [],
      );
      await ctx.workoutState.addExerciseToSession(
        exerciseWithoutCaps,
        chosenMetric: 'reps',
      );

      final cached = ctx.workoutState.getExercise('exercise-dumbbell-curl');
      expect(
        cached,
        isNotNull,
        reason: 'session should have cached the exercise after adding it',
      );
      expect(
        cached!.capabilities,
        isNotEmpty,
        reason:
            'cached exercise should carry the seeded capabilities, '
            'not the empty list passed in by the caller',
      );
      expect(
        cached.capabilities,
        contains(ExerciseCapability.bilateral),
        reason:
            'the cached exercise must carry its real bilateral flag '
            'so the info sheet can show the bilateral note',
      );
    },
  );

  // ── S-007: real-session-path info sheet (no caps injected by test) ──────
  //
  // Companion to S-001: S-001 sources the exercise from
  // getExercisesRankedForModality (which already merges caps), so it does
  // not catch a regression where addExerciseToSession trusts the caller.
  // S-007 explicitly constructs an Exercise WITHOUT caps and relies on the
  // session hydration to populate them before the info sheet renders.
  testWidgets('S-007: info sheet renders bilateral note when exercise is added '
      'without capabilities and hydrated via session path', (
    WidgetTester tester,
  ) async {
    final ctx = await _setUpSession();

    // Build an Exercise whose id matches a seeded bilateral exercise but
    // whose capabilities are empty — no capabilities injected by the test.
    final now = DateTime.now().millisecondsSinceEpoch;
    final exercise = Exercise(
      id: 'exercise-dumbbell-curl',
      name: 'Dumbbell Curl',
      createdAtMs: now,
      updatedAtMs: now,
      capabilities: const [],
    );
    await ctx.workoutState.addExerciseToSession(exercise, chosenMetric: 'reps');

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

    expect(
      find.text('LOGGING NOTE'),
      findsOneWidget,
      reason:
          'session must hydrate capabilities so the bilateral note '
          'renders for a bilateral-flagged exercise',
    );
    expect(
      find.textContaining('Log both sides as a single combined set'),
      findsOneWidget,
    );
  });
}
