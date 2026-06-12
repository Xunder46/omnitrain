import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

// ── Shared helpers ─────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Suppress first-run coach-mark sheets that interfere with finder assertions.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps({String? modality}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
  );
}

Widget _buildSessionScreen(_Deps deps) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      // restNotificationService defaults to RestNotificationService.noop()
    ),
  );
}

Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('Round Auto-Expiry Active-Round Lock Fix', () {
    // S-BUG-001: The core regression test.
    //
    // Repro: start round 0 → wait for timer to expire → round auto-completes
    // via _handleEffortTimerExpired → navigate to round 1 → tap Start.
    //
    // Bug: _inProgressKeys still contained round-0's key, so _toggleEffortTimer
    // showed a "Another set is still in progress" SnackBar instead of starting.
    //
    // Fix: _handleEffortTimerExpired now calls _inProgressKeys.remove(timerKey)
    // for rounds before firing the alert and calling completeRound.
    testWidgets(
      'S-BUG-001: auto-expired round clears active-round lock so next round can start',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        // Get a round-capable exercise from a fresh repo (same seed data).
        final helperRepo = await _freshRepo();
        final exercises = await helperRepo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        // Add round 1 so there is a "next round" to start after round 0 expires.
        await deps.workoutState.addEntry(effortId);

        // Use a 2-second duration so the test only needs ~3 seconds of real time.
        await deps.workoutState.updateRoundPlannedDuration(effortId, 0, 2);
        await deps.workoutState.updateRoundPlannedDuration(effortId, 1, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);

        // Round 0 is notStarted — "Start" button is the center control.
        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

        // Tap Start: _toggleEffortTimer → _inProgressKeys.add('$effortId-0'),
        // startRound() fires. Settle so _pendingRoundTransitions is cleared.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // Wait in real time so that DateTime.now() - startedAtMs >= 2 s.
        // The Timer.periodic inside the widget lives in fake-async; it will
        // fire on the next tester.pump() call below, at which point
        // round.elapsedMs ≥ targetSeconds → _handleEffortTimerExpired fires.
        await tester.runAsync(() async {
          await Future.delayed(const Duration(seconds: 3));
        });

        // Advance the fake clock by 1 s to fire the Timer.periodic callback.
        await tester.pump(const Duration(seconds: 1));
        // Allow completeRound() and any setState calls to settle.
        await tester.pumpAndSettle();

        // Round 0 is now auto-completed ("LOGGED" center label).
        // Tap the forward arrow to navigate to round 1.
        final forwardArrow = find.byIcon(Icons.arrow_forward);
        expect(forwardArrow, findsOneWidget);
        await tester.tap(forwardArrow);
        await tester.pumpAndSettle();

        // Round 1 is notStarted — "Start" should be the center control.
        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

        // Tap Start for round 1. Before the fix this showed a SnackBar error.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Another set is still in progress'),
          findsNothing,
          reason:
              'auto-expiry of round 0 must clear _inProgressKeys so round 1 can start',
        );
      },
    );

    // S-BUG-001b: The same regression as S-BUG-001 but the user navigates
    // forward BEFORE the periodic tick fires (faster than tick interval).
    //
    // Repro: start round 0 → wall clock reaches target → user taps forward
    // arrow immediately (tick has not yet pumped) → taps Start for round 1.
    //
    // Bug: the previous fix only cleared _inProgressKeys inside
    // _handleEffortTimerExpired, which fires on the next tick. If the user
    // navigates before that tick, the stale key still blocks Start.
    //
    // Fix: _drainStaleInProgressKeys() in _toggleEffortTimer checks the
    // wall-clock elapsed and fires _handleEffortTimerExpired eagerly.
    testWidgets(
      'S-BUG-001b: round lock cleared by drain when user navigates before tick fires',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final helperRepo = await _freshRepo();
        final exercises = await helperRepo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateRoundPlannedDuration(effortId, 0, 2);
        await deps.workoutState.updateRoundPlannedDuration(effortId, 1, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // Let the wall clock advance past the 2 s target, but do NOT pump
        // the fake clock — the Timer.periodic tick does not fire yet.
        await tester.runAsync(() async {
          await Future.delayed(const Duration(seconds: 3));
        });

        // Navigate to round 1 WITHOUT pumping a tick first.
        final forwardArrow = find.byIcon(Icons.arrow_forward);
        expect(forwardArrow, findsOneWidget);
        await tester.tap(forwardArrow);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

        // Tap Start — _drainStaleInProgressKeys fires _handleEffortTimerExpired
        // eagerly and clears the stale key before the lock check.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Another set is still in progress'),
          findsNothing,
          reason:
              '_drainStaleInProgressKeys must clear wall-clock-expired round key before tick fires',
        );
      },
    );

    // S-BUG-002: Parity — manual "Log Round" path also clears the lock.
    //
    // The manual path calls _logSet() → _resetTimerState() → removes key.
    // This test guards that the manual path continues to work after the fix.
    testWidgets(
      'S-BUG-002: manual Log Round clears active-round lock (parity with auto-expiry)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final helperRepo = await _freshRepo();
        final exercises = await helperRepo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);

        // Tap Start for round 0.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // Tap "Log Round" (or "Log Period" for sports modality) while running.
        final logRoundFinder = find.byWidgetPredicate(
          (w) =>
              w is FilledButton &&
              w.child is Text &&
              ((w.child as Text).data ?? '').startsWith('Log'),
        );
        expect(logRoundFinder, findsOneWidget);
        await tester.tap(logRoundFinder);
        await tester.pumpAndSettle();

        // Round 1 is now visible — Start must be available.
        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Another set is still in progress'),
          findsNothing,
          reason: 'manual Log Round must clear the active-round lock',
        );
      },
    );

    // S-BUG-003: Guard — count-up timed efforts are not auto-logged.
    //
    // A timed effort with duration == 0 has no target, so _handleEffortTimerExpired
    // never fires. The user must tap "Log Interval" manually.
    testWidgets(
      'S-BUG-003: count-up timed effort (no target duration) is never auto-logged',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');

        final helperRepo = await _freshRepo();
        final exercises = await helperRepo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
        );

        await deps.workoutState.addExerciseToSession(
          timedExercise,
          effortKindOverride: 'timed',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, timedExercise.name);

        // Tap Start.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pump();

        // Let real time pass — no target means no auto-expiry.
        await tester.runAsync(() async {
          await Future.delayed(const Duration(seconds: 2));
        });
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // "LOGGED" must not appear — the effort is still in progress.
        expect(find.text('LOGGED'), findsNothing,
            reason: 'count-up timed effort must not auto-log');

        // "Log Interval" must still be available for manual logging.
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );
      },
    );
  });
}
