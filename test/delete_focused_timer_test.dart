// `−` on a timed, hold or round effort (plan 41, phase P2b): the focused set's
// delete rule for the timer kinds, where "the focused set" is a position in the
// timer UI state as well as in the entry list.
//
// Covers S-4904, S-4905, S-4906 and S-4908 of
// `docs/plans/2026-10-18-41-delete-focused-set-plan/2026-10-18-41-delete-focused-set-plan.md`.
//
// The elapsed digits are wall clock (`TimedInstance.elapsedMs`) and
// `tester.pump` moves only the fake clock, so a pump can never make a live
// readout grow (`test/count_up_screen_test.dart` documents this). S-4905
// therefore reads an elapsed time seeded into the repository, which is what
// shows whether the running interval's own time sits on the set it belongs to
// after a middle delete.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers (copied from test/session_toolbar_rework_test.dart) ───────

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
  MockWorkoutRepository repo,
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
    repo: repo,
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

/// Navigate from list view to the detail view by tapping the first exercise
/// name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

// ── Readers ─────────────────────────────────────────────────────────────────

/// The digits the elapsed readout draws (`MM:SS`).
String _elapsedDigits(WidgetTester tester) {
  final text = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(const Key('count-up-digits')),
          matching: find.byType(Text),
        )
        .first,
  );
  return text.data!;
}

/// Puts [elapsedMs] of wall-clock time behind the running timed entry at
/// [entryIndex], then re-reads it into the state the way a restored session
/// does.
///
/// The readout is wall clock, so a `pump` cannot make it grow; seeding is the
/// readable way to prove which set a running interval's own time follows.
Future<void> _seedRunningElapsed(
  _Deps deps,
  String effortId, {
  required int entryIndex,
  required int elapsedMs,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final existing = (await deps.repo.getTimedInstances(
    effortId,
  )).firstWhere((instance) => instance.entryIndex == entryIndex);
  await deps.repo.updateTimedInstance(
    TimedInstance(
      id: existing.id,
      effortId: effortId,
      entryIndex: entryIndex,
      targetDurationSecs: existing.targetDurationSecs,
      startedAtMs: now - elapsedMs,
      state: TimedState.active,
      pausedAtMs: null,
      actualDurationSecs: 0,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

void main() {
  group('Delete the focused set — timers (plan 41)', () {
    testWidgets(
      'S-4904: deleting a running interval asks first; cancel keeps it '
      'running; delete drops it and its timer; the next set is idle',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Easy Run');

        await tester.tap(find.byKey(const Key('set-segment-1')));
        await tester.pumpAndSettle();
        expect(find.text('Interval 2 of 3'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // A running interval's centre control is its log button.
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete running Interval?'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('workout-delete-running-entry-cancel')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Interval 2 of 3'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('workout-delete-running-entry-confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Interval 2 of 2'), findsOneWidget);

        // The interval that was running is gone, so no ticker is live and the
        // fake clock can be advanced with pumps alone.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 200));

        // Position 2 is the old interval 3, which was never started.
        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Log Interval'), findsNothing);

        final instances = deps.workoutState.getTimedInstancesForEffort(
          effortId,
        );
        expect(instances.length, 2);
        expect(instances.where((i) => i.state == TimedState.active), isEmpty);

        // Position 2 was never started, so `−` deletes it at once instead of
        // asking about a running set.
        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Interval 1 of 1'), findsOneWidget);
      },
    );

    testWidgets(
      'S-4905: a running later interval keeps running and keeps its own '
      'time after a middle delete',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');
        final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(
          _buildSessionScreen(deps, initialFocusId: effortId),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('set-segment-2')));
        await tester.pumpAndSettle();
        expect(find.text('Interval 3 of 3'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );

        await _seedRunningElapsed(
          deps,
          effortId,
          entryIndex: 2,
          elapsedMs: 45000,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(_elapsedDigits(tester), '00:45');

        // Interval 1 was never started, so it holds no timer to lose.
        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Interval 1 of 3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Interval 1 of 2'), findsOneWidget);

        // The interval that was running is position 2 now, still running, and
        // it shows its own 00:45 — the time seeded for it — rather than the
        // fresh 00:00 of a set that never started.
        await tester.tap(find.byKey(const Key('set-segment-1')));
        await tester.pumpAndSettle();
        expect(find.text('Interval 2 of 2'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(_elapsedDigits(tester), '00:45');
      },
    );

    testWidgets('S-4906: deleting a running round asks first', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-heavy-bag-rounds',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Heavy Bag Rounds');
      expect(find.text('Round 1 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete running Round?'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('workout-delete-running-entry-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Round 1 of 2'), findsOneWidget);

      final rounds = deps.workoutState.getRoundsForEffort(effortId);
      expect(rounds.length, 2);
      expect(rounds.where((r) => r.state == RoundState.active), isEmpty);
    });

    testWidgets('S-4908: the only interval, started, asks to remove the '
        'exercise', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');
      expect(find.text('Interval 1 of 1'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();

      // The last interval takes the exercise with it, so the whole-exercise
      // question is the one that shows, not the running-set one.
      expect(find.textContaining('Remove Exercise?'), findsOneWidget);
      expect(find.textContaining('Delete running'), findsNothing);

      await tester.tap(find.byKey(const Key('workout-remove-exercise-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Interval 1 of 1'), findsOneWidget);
      // Cancelling kept the interval, so the exercise is still there with it.
      final exercises = deps.workoutState.getExercisesWithEntries();
      expect(exercises.length, 1);
      expect((exercises.first['entries'] as List).length, 1);
    });
  });
}
