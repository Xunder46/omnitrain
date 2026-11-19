// Plan 120 Phase 2: the session screen attaches the keep-awake controller in
// `initState` when it is not in edit mode and detaches it as the first
// statement of `dispose` (S-19520, S-19521, S-19522).
//
// Widget tests, Mock-only: a plain `MockWorkoutRepository`, no Hive, and the
// `FakeScreenAwakePort` records every `setKeepAwake` value synchronously.

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
import 'helpers/fake_screen_awake_port.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers (copied from test/delete_focused_timer_test.dart) ───────

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
  FakeScreenAwakePort port,
});

Future<_Deps> _buildDeps({String? modality}) async {
  final repo = await _freshRepo();
  final port = FakeScreenAwakePort();
  final workoutState = WorkoutState(repo, screenAwake: port);
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
    port: port,
  );
}

WorkoutSessionScreen _sessionScreen(_Deps deps, {bool editMode = false}) {
  return WorkoutSessionScreen(
    workoutState: deps.workoutState,
    routineState: deps.routineState,
    sessionSummaryService: deps.sessionSummaryService,
    timerAlertService: FakeTimerAlertService(),
    settingsState: deps.settingsState,
    editMode: editMode,
  );
}

/// The app under test for the pop scenarios: a home screen with a button that
/// pushes the session screen, so the screen's route can be popped.
Widget _buildOpenButtonApp(_Deps deps, {bool editMode = false}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _sessionScreen(deps, editMode: editMode),
                ),
              );
            },
            child: const Text('Open session'),
          ),
        ),
      ),
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

void main() {
  testWidgets(
    'S-19520: a live session screen attaches on push and releases on pop, '
    'and the running timer survives the pop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.startTimedEntry(effortId, 0);

      await tester.pumpWidget(_buildOpenButtonApp(deps));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(deps.port.calls.last, isTrue);
      expect(deps.workoutState.screenAwake.attachedCount, 1);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(deps.port.calls.last, isFalse);
      expect(deps.workoutState.screenAwake.attachedCount, 0);
      expect(deps.workoutState.inProgressWorkTimers().length, 1);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S-19521: an edit-mode session screen never attaches and never detaches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.startTimedEntry(effortId, 0);

      await tester.pumpWidget(_buildOpenButtonApp(deps, editMode: true));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(deps.port.calls, [false]);
      expect(deps.workoutState.screenAwake.attachedCount, 0);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(deps.port.calls, [false]);
      expect(deps.workoutState.screenAwake.attachedCount, 0);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S-19522: tapping Start on the session screen acquires the keep-awake',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(
        MaterialApp(home: _sessionScreen(deps)),
      );
      await _openDetailView(tester, 'Easy Run');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(deps.port.calls.last, isTrue);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
