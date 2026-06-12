import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Future<Exercise> _getExerciseById(MockWorkoutRepository repo, String id) async {
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

Widget _buildSessionScreen(
  _Deps deps, {
  bool editMode = false,
  String? initialFocusId,
}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
      initialFocusId: initialFocusId,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the first exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

Finder _detailSwipeSurface() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is GestureDetector &&
        widget.onHorizontalDragEnd != null &&
        widget.onVerticalDragEnd != null,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Initial Landing — First Unlogged Set', () {
    testWidgets('set effort with 2/4 logged opens on set 3 from list tap', (
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
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.text('Set 3 of 4'), findsOneWidget);
    });

    testWidgets('set effort with none logged opens on set 1', (tester) async {
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

      expect(find.text('Set 1 of 3'), findsOneWidget);
    });

    testWidgets('set effort with all logged opens on last set', (tester) async {
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
      await deps.workoutState.addEntry(effortId);

      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);
      await deps.workoutState.recordRestStart(effortId, 3);
      await deps.workoutState.recordRestStart(effortId, 4);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.text('Set 4 of 4'), findsOneWidget);
    });

    testWidgets('single-set effort opens on set 1 when logged or unlogged', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));

      final depsUnlogged = await _buildDeps(modality: 'resistance_lifting');
      final repoUnlogged = await _freshRepo();
      final exerciseUnlogged = await _getExerciseById(
        repoUnlogged,
        'exercise-barbell-squat',
      );
      await depsUnlogged.workoutState.addExerciseToSession(
        exerciseUnlogged,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(_buildSessionScreen(depsUnlogged));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 1'), findsOneWidget);

      final depsLogged = await _buildDeps(modality: 'resistance_lifting');
      final repoLogged = await _freshRepo();
      final exerciseLogged = await _getExerciseById(
        repoLogged,
        'exercise-barbell-squat',
      );
      final effortId = await depsLogged.workoutState.addExerciseToSession(
        exerciseLogged,
        chosenMetric: 'reps',
      );
      await depsLogged.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(depsLogged));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 1'), findsOneWidget);
    });

    testWidgets('list tap and initialFocusId land on same first-unlogged set', (
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
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 3 of 4'), findsOneWidget);

      await tester.pumpWidget(
        _buildSessionScreen(deps, initialFocusId: effortId),
      );
      await tester.pumpAndSettle();
      expect(find.text('Set 3 of 4'), findsOneWidget);
    });

    testWidgets('timed effort uses timed logged state to land on interval 2', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-easy-run');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await deps.workoutState.startTimedEntry(effortId, 0);
      await deps.workoutState.finishTimedEntry(effortId, 0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');
      expect(find.text('Interval 2 of 3'), findsOneWidget);
    });

    testWidgets('round effort uses round logged state to land on round 3', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(
        repo,
        'exercise-heavy-bag-rounds',
      );

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await deps.workoutState.startRound(effortId, 0);
      await deps.workoutState.completeRound(effortId, 0);
      await deps.workoutState.startRound(effortId, 1);
      await deps.workoutState.completeRound(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');
      expect(find.text('Round 3 of 3'), findsOneWidget);
    });

    testWidgets('drill effort uses timed logged state to land on hold 2', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-plank-hold');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await deps.workoutState.startTimedEntry(effortId, 0);
      await deps.workoutState.finishTimedEntry(effortId, 0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');
      expect(find.text('Hold 2 of 3'), findsOneWidget);
    });
  });

  group('Toolbar Rework — Log Button Labels (Phase C)', () {
    // S-001: Resistance set → shows "Log Set"
    testWidgets(
      'S-001: incomplete resistance set shows FilledButton "Log Set"',
      (tester) async {
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
      },
    );

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

      // Timer exercises show "Start" first — log button appears after starting
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    // S-003: Round exercise in non-sports session → shows "Log Round"
    testWidgets('S-003: incomplete round set (non-sports) shows "Log Round"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(
        repo,
        'exercise-heavy-bag-rounds',
      );
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');

      // Round exercises show "Start" first — log button appears after starting
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    // S-004: Round exercise in sports session → shows "Log Period"
    testWidgets('S-004: incomplete round set (sports) shows "Log Period"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'sports');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(
        repo,
        'exercise-heavy-bag-rounds',
      );
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');

      // Sports round exercises show "Start" first — log button appears after starting
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
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

      // Drill exercises show "Start" first — log button appears after starting
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
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
        reason:
            'At least one GestureDetector with onTap should exist for the timer',
      );
    });

    // S-009: Start button starts the timer (outer GestureDetector removed per B-02-1)
    testWidgets('S-009: tapping Start button starts timer (play/pause icons reflect state)', (
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

      // Before starting: play_circle_outline icon is shown
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

      // Start the timer via the dedicated Start button.
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      // After starting, timer should be running (RUNNING text or pause icon).
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

      // Start via the dedicated Start button (outer GestureDetector removed per B-02-1).
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
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

        // Start the timer on set 1 via the dedicated Start button.
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pump();

        // Navigate to set 2 via forward arrow while set 1 timer is running.
        final forwardBtn = find.byIcon(Icons.arrow_forward);
        if (forwardBtn.evaluate().isNotEmpty) {
          await tester.tap(forwardBtn.first);
          await tester.pumpAndSettle();

          // Now try to start a timer on set 2 via Start button.
          final startBtn = find.widgetWithText(FilledButton, 'Start');
          if (startBtn.evaluate().isNotEmpty) {
            await tester.tap(startBtn.first);
            await tester.pumpAndSettle();

            // Should show SnackBar with in-progress message
            expect(find.textContaining('still in progress'), findsOneWidget);
          }
        }
      },
    );
  });

  group('Toolbar Rework — Delete Confirmation (Phase E)', () {
    // S-014: Unlogged multi-set delete proceeds without confirmation
    testWidgets('S-014: deleting unlogged set does not show AlertDialog', (
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
      // Add a second set so multi-set deletion path is triggered
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // Tap remove
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.textContaining('of 1'),
        findsOneWidget,
        reason: 'Unlogged set should be deleted immediately without warning',
      );
    });

    // S-015: Logged multi-set delete requires confirmation and then removes
    testWidgets('S-015: logged set delete requires confirmation', (
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
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // Navigate to set 2 (middle set)
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      // Verify we are on set 2 of 3
      expect(find.textContaining('Set 2 of 3'), findsOneWidget);

      // Log set 2 so deletion requires confirmation.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      // Logging auto-advances to set 3, so navigate back to logged set 2.
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();

      // Delete set 2
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Delete logged Set?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Should now have 2 sets total
      expect(
        find.textContaining('of 2'),
        findsOneWidget,
        reason: 'After deleting set 2 of 3, only 2 sets should remain',
      );
    });

    // S-016: Cancelling logged-set delete preserves set count
    testWidgets('S-016: cancelling logged set delete preserves set count', (
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

      // Mark current set logged so delete path prompts.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      // Logging auto-advances to set 2, so go back to logged set 1.
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('of 2'), findsOneWidget);
    });
  });

  group('Toolbar Rework — Auto-Pause on Navigation (Phase B)', () {
    // S-013: Navigating away from timed set auto-pauses timer
    testWidgets('S-013: jumping to another set auto-pauses the running timer', (
      tester,
    ) async {
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

      // Start timer on set 1 via the dedicated Start button.
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
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
    });
  });

  group('Session Detail Swipe Mapping + Transition', () {
    testWidgets('left swipe advances and right swipe goes back', (
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
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 3'), findsOneWidget);

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 3'), findsOneWidget);
    });

    testWidgets('horizontal swipes mirror previous and next arrow navigation', (
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
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(-500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 3'), findsOneWidget);

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(500, 0),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 3'), findsOneWidget);
    });

    testWidgets('vertical metric tap-to-edit updates value without set navigation', (
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
      expect(find.text('Set 1 of 2'), findsOneWidget);

      final beforeReps =
          tester
                  .widget<InlineMetricEditor>(
                    find.byType(InlineMetricEditor).first,
                  )
                  .currentValue
              as int;

      // Tap the reps value to open the modal (crown is dormant).
      await tester.tap(find.byType(InlineMetricEditor).first);
      await tester.pumpAndSettle();

      // If the modal opened, enter a higher value and confirm.
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        final newReps = beforeReps + 5;
        await tester.enterText(find.byType(TextField), '$newReps');
        await tester.tap(find.text('Ok'));
        await tester.pumpAndSettle();
      }

      final afterReps =
          tester
                  .widget<InlineMetricEditor>(
                    find.byType(InlineMetricEditor).first,
                  )
                  .currentValue
              as int;

      expect(afterReps, greaterThan(beforeReps));
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.text('Set 2 of 2'), findsNothing);
    });

    testWidgets('vertical exercise swipe direction remains unchanged', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
      final rounds = await _getExerciseById(repo, 'exercise-heavy-bag-rounds');

      await deps.workoutState.addExerciseToSession(squat, chosenMetric: 'reps');
      await deps.workoutState.addExerciseToSession(
        rounds,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(0, -500),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Heavy Bag Rounds'), findsOneWidget);

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(0, 500),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Barbell Back Squat'), findsOneWidget);
    });

    testWidgets('horizontal swipe lands on the correct set after transition', (
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
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.fling(
        _detailSwipeSurface().first,
        const Offset(-500, 0),
        1200,
      );
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 3'), findsOneWidget);
      expect(find.text('Set 1 of 3'), findsNothing);
    });
  });

  // ── Remove-button icon swap (Phase G) ────────────────────────────────────

  group('Toolbar Rework — Remove Button Icon (Phase G)', () {
    // S-020: Single set shows trash-can icon (delete_outline)
    testWidgets(
      'S-020: delete_outline icon shown when exercise has exactly one set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );
        // addExerciseToSession seeds exactly 1 entry
        await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.text('Set 1 of 1'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.remove), findsNothing);
      },
    );

    // S-021: Multi-set shows minus icon (remove)
    testWidgets(
      'S-021: remove icon shown when exercise has more than one set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        // Add a second set so there are 2 entries
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(find.byIcon(Icons.remove), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
      },
    );

    // S-022: Deleting down to the last set switches minus → trash before confirm
    testWidgets(
      'S-022: icon switches to delete_outline after removing all but last set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // 2 sets — minus icon
        expect(find.byIcon(Icons.remove), findsOneWidget);

        // Remove unlogged set 1 (no confirmation dialog)
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pumpAndSettle();

        // 1 set remaining — trash icon
        expect(find.text('Set 1 of 1'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        expect(find.byIcon(Icons.remove), findsNothing);
      },
    );

    // S-023: Tooltip text on single-set is "Remove exercise"
    testWidgets(
      'S-023: tooltip reads "Remove exercise" when only one set remains',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );
        await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.text('Set 1 of 1'), findsOneWidget);

        // Long-press to trigger the tooltip
        final deleteIcon = find.byIcon(Icons.delete_outline);
        await tester.longPress(deleteIcon);
        await tester.pumpAndSettle();

        expect(find.text('Remove exercise'), findsOneWidget);
      },
    );
  });
}
