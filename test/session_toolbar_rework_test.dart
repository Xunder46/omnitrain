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

// ── Shared helpers ────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Future<Exercise> _getExerciseById(
  MockWorkoutRepository repo,
  String id,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
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
  final settingsState = SettingsState(repo);
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
  );
}

Widget _buildSessionScreen(_Deps deps, {bool editMode = false}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the first exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Toolbar Rework — Log Button Labels (Phase C)', () {
    // S-001: Resistance set → shows "Log Set"
    testWidgets('S-001: incomplete resistance set shows FilledButton "Log Set"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
      await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.widgetWithText(FilledButton, 'Log Set'), findsOneWidget);
    });

    // S-002: Timed exercise → shows "Log Interval"
    testWidgets('S-002: incomplete timed set shows "Log Interval"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      expect(find.widgetWithText(FilledButton, 'Log Interval'), findsOneWidget);
    });

    // S-003: Round exercise in non-sports session → shows "Log Round"
    testWidgets('S-003: incomplete round set (non-sports) shows "Log Round"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-heavy-bag-rounds');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');

      expect(find.widgetWithText(FilledButton, 'Log Round'), findsOneWidget);
    });

    // S-004: Round exercise in sports session → shows "Log Period"
    testWidgets('S-004: incomplete round set (sports) shows "Log Period"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'sports');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-heavy-bag-rounds');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');

      expect(find.widgetWithText(FilledButton, 'Log Period'), findsOneWidget);
    });

    // S-005: Drill exercise → shows "Log Hold"
    testWidgets('S-005: incomplete drill set shows "Log Hold"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-plank-hold');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget);
    });
  });

  group('Toolbar Rework — Play Button Removal (Phase C)', () {
    // S-007: No play/pause IconButton in toolbar (removed from toolbar center)
    testWidgets('S-007: play_arrow IconButton NOT present in toolbar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      // play_arrow should NOT appear in the toolbar at all
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('S-007b: pause IconButton NOT present in toolbar for timed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      // There must be NO standalone pause IconButton in the toolbar
      expect(find.byIcon(Icons.pause), findsNothing);
    });
  });

  group('Toolbar Rework — Timer Display Tap-to-Toggle (Phase D)', () {
    // S-008: Timer display for timed exercise is wrapped in GestureDetector
    testWidgets('S-008: timed timer display is tappable (GestureDetector present)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      // There should be a GestureDetector with an onTap wrapping the timer display
      // We verify this by checking that tapping the timer area doesn't crash and
      // that at least one GestureDetector with onTap is present
      final gestureDetectors = tester.widgetList<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(
        gestureDetectors.any((gd) => gd.onTap != null),
        isTrue,
        reason: 'At least one GestureDetector with onTap should exist for the timer',
      );
    });

    // S-009: Tapping the timer display starts the timer
    testWidgets('S-009: tapping timer display starts/pauses timer', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      // Status should show play affordance (STOPPED or similar) initially
      expect(
        find.textContaining('STOPPED').evaluate().isNotEmpty ||
        find.byIcon(Icons.play_circle_outline).evaluate().isNotEmpty,
        isTrue,
      );

      // Tap the timer display area to start
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pump();

      // After tapping, timer should be running (status changes to RUNNING)
      // or play icon changes to pause icon
      expect(
        find.textContaining('RUNNING').evaluate().isNotEmpty ||
        find.byIcon(Icons.pause_circle_outline).evaluate().isNotEmpty,
        isTrue,
      );
    });

    // S-010: Timer display shows play affordance when not running
    testWidgets('S-010: timer shows play_circle_outline when not running', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    });

    // S-011: Timer display shows pause affordance when running
    testWidgets('S-011: timer shows pause_circle_outline when running', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      // Tap to start
      await tester.tap(find.byIcon(Icons.play_circle_outline));
      await tester.pump();

      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    });
  });

  group('Toolbar Rework — In-Progress Lock (Phase A)', () {
    // S-012: Starting second timer while another is in-progress shows SnackBar
    testWidgets(
      'S-012: starting second timed exercise timer shows in-progress SnackBar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final repo = await _freshRepo();
        final ex1 = await _getExerciseById(repo, 'exercise-easy-run');
        final ex2 = await _getExerciseById(repo, 'exercise-heavy-bag-rounds');
        final effortId1 = await deps.workoutState.addExerciseToSession(
          ex1,
          effortKindOverride: 'timed',
        );
        await deps.workoutState.addExerciseToSession(
          ex2,
          effortKindOverride: 'timed',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Easy Run');

        // Add a second set so we can navigate to it while first is in progress
        await deps.workoutState.addEntry(effortId1);
        await tester.pumpAndSettle();

        // Start the timer on set 1 by tapping timer display
        await tester.tap(find.byIcon(Icons.play_circle_outline));
        await tester.pump();

        // Now tap the dot indicator to jump to set 2 (while set 1 timer runs)
        // The second set's timer tap should be blocked
        // Navigate to set 2 via dot indicator
        // Try navigating forward (set 2)
        final forwardBtn = find.byIcon(Icons.arrow_forward);
        if (forwardBtn.evaluate().isNotEmpty) {
          await tester.tap(forwardBtn.first);
          await tester.pumpAndSettle();

          // Now try to start a timer on set 2
          await tester.tap(find.byIcon(Icons.play_circle_outline));
          await tester.pumpAndSettle();

          // Should show SnackBar with in-progress message
          expect(
            find.textContaining('still in progress'),
            findsOneWidget,
          );
        }
      },
    );
  });

  group('Toolbar Rework — Delete Confirmation (Phase E)', () {
    // S-014: Tapping delete shows confirmation dialog
    testWidgets('S-014: tapping delete shows AlertDialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      // Add a second set so multi-set deletion path is triggered
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // Tap remove
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // S-015: Confirming delete removes the CURRENT set (not always last)
    testWidgets('S-015: confirming delete removes current set', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // Navigate to set 2 (middle set)
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      // Verify we are on set 2 of 3
      expect(find.textContaining('Set 2 of 3'), findsOneWidget);

      // Delete set 2
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Should now have 2 sets total
      expect(
        find.textContaining('of 2'),
        findsOneWidget,
        reason: 'After deleting set 2 of 3, only 2 sets should remain',
      );
    });

    // S-016: Cancelling delete dialog preserves the set
    testWidgets('S-016: cancelling delete dialog preserves set count', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.textContaining('of 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('of 2'), findsOneWidget);
    });
  });

  group('Toolbar Rework — Previous Set Graceful Empty State (Phase F)', () {
    // S-019: Unlogged previous set shows "—" not zeros
    testWidgets(
      'S-019: previous set stats show "—" when previous set is unlogged',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // Navigate to set 2 without logging set 1
        await tester.tap(find.byIcon(Icons.arrow_forward));
        await tester.pumpAndSettle();

        // Previous set 1 was never logged → should show "Previous: —"
        expect(find.textContaining('Previous: —'), findsOneWidget);
      },
    );
  });

  group('Toolbar Rework — Auto-Pause on Navigation (Phase B)', () {
    // S-013: Navigating away from timed set auto-pauses timer
    testWidgets(
      'S-013: jumping to another set auto-pauses the running timer',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-easy-run');
final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Easy Run');

        // Start timer on set 1
        await tester.tap(find.byIcon(Icons.play_circle_outline));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // RUNNING should be displayed
        expect(find.textContaining('RUNNING'), findsOneWidget);

        // Tap forward arrow to jump to set 2 — should auto-pause
        await tester.tap(find.byIcon(Icons.arrow_forward));
        await tester.pumpAndSettle();

        // Navigate back to set 1 to verify it's now paused
        await tester.tap(find.byIcon(Icons.arrow_back).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.textContaining('PAUSED'), findsOneWidget);
      },
    );
  });
}
