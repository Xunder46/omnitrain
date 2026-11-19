// Plan 240 — an empty routine cannot be saved, and a routine that cannot
// start never costs the running workout.
//
// Scenarios S-24001..S-24005 of
// `docs/plans/2026-11-18-240-empty-routine-cannot-cost-the-running-workout-plan/2026-11-18-240-empty-routine-cannot-cost-the-running-workout-plan.md`.
// Mock repository only, seeded before the first pump; no `Future.delayed`.
// The running session is created with a `WorkoutState(repo, clock: ...)`
// at an earlier fixed time so its ms-based id cannot collide with any new
// session a start creates. Harness copied from
// `test/start_new_really_discards_screen_test.dart` (plan 230) and the
// guard harness from `test/routine_unsaved_changes_guard_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// The running session's clock: an earlier fixed time, so its id (the create
// time in ms) differs from the new session the confirmed start creates.
DateTime _clockNow = DateTime(2026, 6, 10, 9);

/// Starts a running non-rolling workout with one logged set on [state].
/// Returns its id.
Future<String> startRunningWorkout(
  MockWorkoutRepository repo,
  WorkoutState state, {
  String? modality,
}) async {
  final exercise = (await repo.getExercises()).first;
  await state.createNewSession(modality: modality);
  final effortId = await state.addExerciseToSession(exercise);
  await state.addEntry(effortId);
  await state.updateEntryValue(effortId, 0, 'reps', 3);
  await state.updateEntryValue(effortId, 0, 'weight', 100.0);
  return state.currentSession!.id;
}

Future<MockWorkoutRepository> freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// The valid control of plan 230 (S-23005's fixture): a routine planned for
/// today, with the segment and effort the manifest builder needs.
Future<void> seedPlannedSessionToday(MockWorkoutRepository repo) async {
  final exercise = (await repo.getExercises()).first;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final rowAt = today.millisecondsSinceEpoch;
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-230-iso',
      name: 'Iso Rework 230',
      focusModality: null,
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );
  await repo.createTemplateSegment(
    TemplateSegment(
      id: 'seg-230-iso',
      templateId: 'tpl-230-iso',
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main',
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );
  await repo.createTemplateEffort(
    TemplateEffort(
      id: 'eff-230-iso',
      templateSegmentId: 'seg-230-iso',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exercise.id,
      createdAtMs: rowAt,
    ),
  );
  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-230-today',
      ownerUserId: 'user-1',
      scheduledDateMs: today.millisecondsSinceEpoch,
      modality: null,
      routineTemplateId: 'tpl-230-iso',
      title: 'Plan Today 230',
      isCompleted: false,
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );
}

/// The plan 240 fixture: a routine template with NO segments, plus (for the
/// day list) a planned session for today pointing at it.
Future<void> seedEmptyRoutineAndPlan(MockWorkoutRepository repo) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final rowAt = today.millisecondsSinceEpoch;
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-240-empty',
      name: 'Empty Rework 240',
      focusModality: null,
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );
  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-240-today',
      ownerUserId: 'user-1',
      scheduledDateMs: today.millisecondsSinceEpoch,
      modality: null,
      routineTemplateId: 'tpl-240-empty',
      title: 'Plan Empty 240',
      isCompleted: false,
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );
}

Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
  // The running session's elapsed ticker keeps scheduling frames, so the
  // screen never settles: settle what is settleable, then move on.
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      Duration(seconds: seconds),
    );
  } catch (_) {}
}

Future<void> pumpDay(
  WidgetTester tester,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  CalendarState calendarState,
) async {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final now = DateTime.now();
  await tester.pumpWidget(
    MaterialApp(
      home: DaySessionListScreen(
        date: DateTime(now.year, now.month, now.day),
        calendarState: calendarState,
        routineState: RoutineState(repo),
        workoutState: workoutState,
        routineSessionService: RoutineSessionService(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpMyRoutines(
  WidgetTester tester,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
) async {
  final routineState = RoutineState(repo);
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MyRoutinesScreen(
        routineState: routineState,
        workoutState: workoutState,
        routineSessionService: RoutineSessionService(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await settle(tester);
}

// ── Guard harness, copied from test/routine_unsaved_changes_guard_test.dart ──

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<Exercise> _getExerciseById(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

typedef _RoutineDeps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SettingsState settingsState,
});

Future<_RoutineDeps> _buildDeps() async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  routineState.setAutosaveEnabled(false);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    settingsState: settingsState,
  );
}

Widget _buildScreen(_RoutineDeps deps, {String? templateId}) {
  return MaterialApp(
    home: RoutineSetupScreen(
      routineState: deps.routineState,
      workoutState: deps.workoutState,
      settingsState: deps.settingsState,
      templateId: templateId,
    ),
  );
}

Future<void> _pumpAndSettle(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Future<void> _tapSaveButton(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('Plan 240 — a My Routines start that cannot start keeps the workout', () {
    testWidgets(
      'S-24001 starting an empty routine over a running workout keeps the '
      'running workout and shows the error',
      (tester) async {
        final repo = await freshRepo();
        await seedEmptyRoutineAndPlan(repo);
        _clockNow = DateTime(2026, 6, 10, 9);
        final workoutState = WorkoutState(repo, clock: () => _clockNow);
        final runningId = await startRunningWorkout(repo, workoutState);
        _clockNow = DateTime(2026, 6, 10, 10);

        await pumpMyRoutines(tester, repo, workoutState);

        await tester.tap(find.byKey(const Key('routine-card-start')).first);
        await settle(tester);
        await tester.tap(find.byKey(const Key('routine-start-new-confirm')));
        await settle(tester, seconds: 5);
        // The OmniMessage snackbar may need one more frame to appear.
        await tester.pump();

        expect(await repo.getSession(runningId), isNotNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, runningId);
        expect(
          find.text('Could not start the routine. Try again.'),
          findsOneWidget,
        );
      },
    );
  });

  group('Plan 240 — a day-list planned start that cannot start keeps the workout', () {
    Future<(MockWorkoutRepository, WorkoutState, CalendarState)> seeded(
      Future<void> Function(MockWorkoutRepository repo) seed,
    ) async {
      final repo = await freshRepo();
      await seed(repo);
      // Seed the running workout at 9:00 no matter what an earlier test left
      // behind, so the confirm's later clock never collides with the id.
      _clockNow = DateTime(2026, 6, 10, 9);
      final workoutState = WorkoutState(repo, clock: () => _clockNow);
      await startRunningWorkout(repo, workoutState);
      final calendarState = CalendarState(repo);
      await calendarState.init();
      return (repo, workoutState, calendarState);
    }

    testWidgets(
      'S-24002 starting an empty routine plan over a running workout keeps '
      'the running workout and shows the error',
      (tester) async {
        final (repo, workoutState, calendarState) = await seeded(
          seedEmptyRoutineAndPlan,
        );
        final runningId = workoutState.currentSession!.id;
        await pumpDay(tester, repo, workoutState, calendarState);

        _clockNow = DateTime(2026, 6, 10, 10);

        await tester.tap(find.text('Plan Empty 240'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('day-session-new-start-confirm')),
        );
        await tester.pumpAndSettle();

        expect(await repo.getSession(runningId), isNotNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, runningId);
        expect(
          find.text('Could not start the session. Try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'S-24004 control the day-list twin: a valid routine plan starts a new '
      'session and the old row is gone',
      (tester) async {
        final (repo, workoutState, calendarState) = await seeded(
          seedPlannedSessionToday,
        );
        final runningId = workoutState.currentSession!.id;
        await pumpDay(tester, repo, workoutState, calendarState);

        _clockNow = DateTime(2026, 6, 10, 10);

        await tester.tap(find.text('Plan Today 230'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('day-session-new-start-confirm')),
        );
        await tester.pumpAndSettle();

        expect(await repo.getSession(runningId), isNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, isNot(runningId));
        expect(workoutState.currentSession!.endedAtMs, isNull);
      },
    );
  });

  group('Plan 240 — controls on the valid My Routines start', () {
    testWidgets(
      'S-24004 control a valid routine start discards the old row and starts '
      'a new session',
      (tester) async {
        final repo = await freshRepo();
        await seedPlannedSessionToday(repo);
        _clockNow = DateTime(2026, 6, 10, 9);
        final workoutState = WorkoutState(repo, clock: () => _clockNow);
        final runningId = await startRunningWorkout(repo, workoutState);
        _clockNow = DateTime(2026, 6, 10, 10);

        await pumpMyRoutines(tester, repo, workoutState);

        await tester.tap(find.byKey(const Key('routine-card-start')).first);
        await settle(tester);
        await tester.tap(find.byKey(const Key('routine-start-new-confirm')));
        await settle(tester, seconds: 5);

        expect(await repo.getSession(runningId), isNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, isNot(runningId));
      },
    );
  });

  group('Plan 240 — the editor refuses to save a routine with no exercise', () {
    testWidgets(
      'S-24003 saving a named routine with no exercise shows the message and '
      'saves nothing',
      (tester) async {
        final deps = await _buildDeps();

        await tester.pumpWidget(_buildScreen(deps));
        await _pumpAndSettle(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'Routine Name'),
          'Empty',
        );
        await _pumpAndSettle(tester);

        await _tapSaveButton(tester);
        await _pumpAndSettle(tester);

        expect(
          find.text('Add at least one exercise before saving'),
          findsOneWidget,
        );
        expect(find.byType(RoutineSetupScreen), findsOneWidget);
        final templates = await deps.repo.getTemplates();
        expect(templates.where((t) => t.name == 'Empty'), isEmpty);
      },
    );

    testWidgets(
      'S-24005 control saving a named routine with one exercise saves and '
      'pops',
      (tester) async {
        final deps = await _buildDeps();

        await tester.pumpWidget(_buildScreen(deps));
        await _pumpAndSettle(tester);

        await tester.enterText(
          find.widgetWithText(TextField, 'Routine Name'),
          'One',
        );
        await _pumpAndSettle(tester);

        final ex = await _getExerciseById(deps.repo, 'exercise-barbell-squat');
        await deps.routineState.addExerciseToRoutine(ex, 'set');
        await _pumpAndSettle(tester);

        await _tapSaveButton(tester);
        await _pumpAndSettle(tester);

        expect(find.byType(RoutineSetupScreen), findsNothing);
        final templates = await deps.repo.getTemplates();
        expect(templates.where((t) => t.name == 'One'), isNotEmpty);
      },
    );
  });
}
