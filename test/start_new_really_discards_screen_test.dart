// Plan 230 P1 — a confirmed "Start New Session?" really discards the running
// workout (screen side).
//
// Scenarios S-23004..S-23009 of
// `docs/plans/2026-11-17-230-start-new-really-discards-plan/`. Mock
// repository only, seeded before the first pump. The running session is
// created with a `WorkoutState(repo, clock: ...)` at an earlier fixed time so
// its ms-based id cannot collide with the new session the start creates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/home/home_screen.dart';
import 'package:omnitrain/features/routine/my_routines_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/test_nutrition_primer_state.dart';

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

/// The day-list fixture of `test/planned_routine_calendar_modality_test.dart`
/// (S-12409): a routine planned for today, with the segment and effort the
/// manifest builder needs.
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

Future<HomeScreen> _home(
  MockWorkoutRepository repo,
  WorkoutState workoutState,
) async {
  final routineState = RoutineState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  return HomeScreen(
    workoutState: workoutState,
    homeState: HomeState(repo),
    routineState: routineState,
    routineSessionService: RoutineSessionService(repo),
    sessionSummaryService: SessionSummaryService(repo),
    calendarState: CalendarState(repo),
    periodState: PeriodState(repo),
    profileState: ProfileState(repo),
    settingsState: settingsState,
    timerAlertService: FakeTimerAlertService(),
    nutritionState: NutritionState(repo),
    foodLibraryState: FoodLibraryState(repo),
    nutritionPrimerState: await buildNutritionPrimerState(repo),
    exerciseLibraryState: ExerciseLibraryState(
      service: ExerciseLibraryService(repo),
      workoutState: workoutState,
    ),
  );
}

void main() {
  group('Plan 230 — the day list really discards on a confirmed Start New', () {
    Future<(MockWorkoutRepository, WorkoutState, CalendarState)>
    seeded() async {
      final repo = await freshRepo();
      await seedPlannedSessionToday(repo);
      final workoutState = WorkoutState(repo, clock: () => _clockNow);
      await startRunningWorkout(repo, workoutState);
      final calendarState = CalendarState(repo);
      await calendarState.init();
      return (repo, workoutState, calendarState);
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

    testWidgets(
      'S-23004 the prompt Cancel keeps the running workout current and stored',
      (tester) async {
        final (repo, workoutState, calendarState) = await seeded();
        final runningId = workoutState.currentSession!.id;
        await pumpDay(tester, repo, workoutState, calendarState);

        await tester.tap(find.byTooltip('Start session'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('day-session-new-start-cancel')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('day-session-new-start-cancel')));
        await tester.pumpAndSettle();

        expect(workoutState.currentSession!.id, runningId);
        expect(workoutState.currentSession!.endedAtMs, isNull);
        expect(workoutState.hasActiveSession, isTrue);
        final stored = await repo.getSession(runningId);
        expect(stored, isNotNull);
        expect(stored!.endedAtMs, isNull);
      },
    );

    testWidgets(
      'S-23005 the prompt Confirm deletes the old row and starts a new session',
      (tester) async {
        final (repo, workoutState, calendarState) = await seeded();
        final runningId = workoutState.currentSession!.id;
        await pumpDay(tester, repo, workoutState, calendarState);

        // The new session is created with a later clock, so the ms-based ids
        // never collide.
        _clockNow = DateTime(2026, 6, 10, 10);

        await tester.tap(find.byTooltip('Start session'));
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

  group('Plan 230 — the Home modality tile really discards on Confirm', () {
    testWidgets(
      'S-23006 confirming a modality-tile Start New deletes the old row',
      (tester) async {
        final repo = await freshRepo();
        // Seed at 9:00 no matter what an earlier test left behind, so the
        // confirm's later clock never collides with the seeded id.
        _clockNow = DateTime(2026, 6, 10, 9);
        final workoutState = WorkoutState(repo, clock: () => _clockNow);
        final runningId = await startRunningWorkout(repo, workoutState);

        await tester.binding.setSurfaceSize(const Size(400, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(home: await _home(repo, workoutState)),
        );
        // The running session's elapsed ticker keeps scheduling frames, so the
        // screen never settles: settle what is settleable, then move on.
        try {
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
        } catch (_) {}

        // The running session has no modality, so the Free tile is the active
        // one; a non-rolling session and another modality tile mean the
        // conflict prompt.
        _clockNow = DateTime(2026, 6, 10, 10);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is EnergyTile && widget.title == 'Cardio',
          ),
        );
        try {
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
        } catch (_) {}

        await tester.tap(find.byKey(const Key('home-modality-change-confirm')));
        try {
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
        } catch (_) {}

        expect(await repo.getSession(runningId), isNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, isNot(runningId));
      },
    );
  });

  group('Plan 230 — the other three start paths really discard on Confirm', () {
    Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
      // The running session's elapsed ticker keeps scheduling frames on Home,
      // so it never settles: settle what is settleable, then move on.
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          Duration(seconds: seconds),
        );
      } catch (_) {}
    }

    Future<(MockWorkoutRepository, WorkoutState, String)> homeSeeded(
      WidgetTester tester, {
      String? modality,
    }) async {
      final repo = await freshRepo();
      _clockNow = DateTime(2026, 6, 10, 9);
      final workoutState = WorkoutState(repo, clock: () => _clockNow);
      final runningId = await startRunningWorkout(
        repo,
        workoutState,
        modality: modality,
      );
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: await _home(repo, workoutState)),
      );
      await settle(tester);
      _clockNow = DateTime(2026, 6, 10, 10);
      return (repo, workoutState, runningId);
    }

    testWidgets(
      'S-23007 confirming the Home Routines tile prompt deletes the old row',
      (tester) async {
        final (repo, workoutState, runningId) = await homeSeeded(tester);

        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is EnergyTile && widget.title == 'Routines',
          ),
        );
        await settle(tester);
        await tester.tap(find.byKey(const Key('home-routine-open-confirm')));
        await settle(tester, seconds: 5);

        expect(await repo.getSession(runningId), isNull);
        expect(workoutState.currentSession, isNull);
      },
    );

    testWidgets(
      'S-23008 confirming a Free tile start over a running workout deletes '
      'the old row',
      (tester) async {
        // A cardio workout is running, so the Free tile is not the active one
        // and tapping it asks first.
        final (repo, workoutState, runningId) = await homeSeeded(
          tester,
          modality: 'cardio_endurance',
        );

        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is EnergyTile && widget.title == 'Free',
          ),
        );
        await settle(tester);
        await tester.tap(find.byKey(const Key('home-modality-change-confirm')));
        await settle(tester);
        await tester.tap(find.text('Start Session'));
        await settle(tester, seconds: 5);

        expect(await repo.getSession(runningId), isNull);
        expect(workoutState.currentSession, isNotNull);
        expect(workoutState.currentSession!.id, isNot(runningId));
      },
    );

    testWidgets(
      'S-23009 confirming a My Routines Start New deletes the old row',
      (tester) async {
        final repo = await freshRepo();
        await seedPlannedSessionToday(repo);
        _clockNow = DateTime(2026, 6, 10, 9);
        final workoutState = WorkoutState(repo, clock: () => _clockNow);
        final runningId = await startRunningWorkout(repo, workoutState);
        _clockNow = DateTime(2026, 6, 10, 10);

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
}
