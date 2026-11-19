// Plan 248 P2 — the planned-row Start button on the day list.
//
// Scenarios S-24801..S-24806 of
// `docs/plans/2026-11-19-248-planned-session-start-button-plan/`. Mock
// repository only; every write happens before the pump. Today is decided by
// the real clock (`OmniDateUtils.isToday`), so the fixture dates are built
// from `DateTime.now()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// The running session's clock in the `running` fixture: an earlier fixed
// time, so its ms-based id cannot collide with a session a start would
// create at the real clock.
DateTime _clockRunning = DateTime(2026, 6, 10, 9);

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime get _tomorrow {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

DateTime get _yesterday {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 1);
}

/// Starts a running non-rolling workout with one logged set on [state]
/// (as `test/start_new_really_discards_screen_test.dart` does). Returns
/// its id.
Future<String> _startRunningWorkout(
  MockWorkoutRepository repo,
  WorkoutState state,
) async {
  final exercise = (await repo.getExercises()).first;
  await state.createNewSession(modality: null);
  final effortId = await state.addExerciseToSession(exercise);
  await state.addEntry(effortId);
  await state.updateEntryValue(effortId, 0, 'reps', 3);
  await state.updateEntryValue(effortId, 0, 'weight', 100.0);
  return state.currentSession!.id;
}

/// One free planned session titled `Plan A` on [day], written before any
/// pump; returns the two states built over the seeded repository. With
/// `running: true`, a running workout exists before the pump too.
Future<(MockWorkoutRepository, WorkoutState, CalendarState)> seeded(
  DateTime day, {
  bool running = false,
}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final now = DateTime.now();
  final rowAt = now.millisecondsSinceEpoch;
  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-248',
      ownerUserId: 'user-1',
      scheduledDateMs: day.millisecondsSinceEpoch,
      modality: null,
      routineTemplateId: null,
      title: 'Plan A',
      isCompleted: false,
      createdAtMs: rowAt,
      updatedAtMs: rowAt,
    ),
  );

  final workoutState = WorkoutState(repo, clock: () => _clockRunning);
  if (running) {
    await _startRunningWorkout(repo, workoutState);
  }
  final calendarState = CalendarState(repo);
  await calendarState.init();
  return (repo, workoutState, calendarState);
}

Future<void> pumpDay(
  WidgetTester tester,
  DateTime day,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  CalendarState calendarState,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: DaySessionListScreen(
        date: day,
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

void main() {
  testWidgets(
    'S-24801: today, the Start button starts the workout; the row has no '
    'edit tooltip and the play sits left of the bin',
    (tester) async {
      final today = _today;
      final (repo, workoutState, calendarState) = await seeded(today);
      expect(workoutState.currentSession, isNull);
      await pumpDay(tester, today, repo, workoutState, calendarState);

      expect(find.byTooltip('Start session'), findsOneWidget);
      expect(find.byTooltip('Delete session'), findsOneWidget);
      expect(find.byTooltip('Edit session'), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('Start session')).dx,
        lessThan(tester.getCenter(find.byTooltip('Delete session')).dx),
      );

      await tester.tap(find.byTooltip('Start session'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      // The plan table expects hasActiveSession true, but that getter also
      // requires a logged effort (session_core.dart) and a freshly started
      // free session has none; the started session itself is open.
      expect(workoutState.currentSession, isNotNull);
      expect(workoutState.currentSession!.endedAtMs, isNull);
    },
  );

  testWidgets(
    'S-24802: today, tapping the planned row opens the edit sheet and '
    'starts nothing',
    (tester) async {
      final today = _today;
      final (repo, workoutState, calendarState) = await seeded(today);
      await pumpDay(tester, today, repo, workoutState, calendarState);

      await tester.tap(find.text('Plan A'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(workoutState.currentSession, isNull);
      expect(find.byType(WorkoutSessionScreen), findsNothing);
    },
  );

  testWidgets(
    'S-24803: tomorrow, the row shows only the bin and the tap opens edit',
    (tester) async {
      final tomorrow = _tomorrow;
      final (repo, workoutState, calendarState) = await seeded(tomorrow);
      await pumpDay(tester, tomorrow, repo, workoutState, calendarState);

      expect(find.byTooltip('Start session'), findsNothing);
      expect(find.byTooltip('Delete session'), findsOneWidget);
      expect(find.byTooltip('Edit session'), findsNothing);

      await tester.tap(find.text('Plan A'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(workoutState.currentSession, isNull);
    },
  );

  testWidgets(
    'S-24804: yesterday, the row is read-only and the tap does nothing',
    (tester) async {
      final yesterday = _yesterday;
      final (repo, workoutState, calendarState) = await seeded(yesterday);
      await pumpDay(tester, yesterday, repo, workoutState, calendarState);

      expect(find.byTooltip('Start session'), findsNothing);
      expect(find.byTooltip('Delete session'), findsNothing);

      await tester.tap(find.text('Plan A'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsNothing);
      expect(workoutState.currentSession, isNull);
    },
  );

  testWidgets(
    'S-24805: today with a running workout, Start asks first, Cancel keeps '
    'it, and the row tap opens edit with no prompt',
    (tester) async {
      final today = _today;
      final (repo, workoutState, calendarState) = await seeded(
        today,
        running: true,
      );
      final runningId = workoutState.currentSession!.id;
      await pumpDay(tester, today, repo, workoutState, calendarState);

      await tester.tap(find.byTooltip('Start session'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('day-session-new-start-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('day-session-new-start-cancel')));
      await tester.pumpAndSettle();

      expect(workoutState.currentSession!.id, runningId);
      expect(workoutState.hasActiveSession, isTrue);

      await tester.tap(find.text('Plan A'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(
        find.byKey(const Key('day-session-new-start-confirm')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'S-24806: today, the bin asks for confirmation and cancelling leaves '
    'the row, the play button and no workout',
    (tester) async {
      final today = _today;
      final (repo, workoutState, calendarState) = await seeded(today);
      await pumpDay(tester, today, repo, workoutState, calendarState);

      await tester.tap(find.byTooltip('Delete session'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('day-session-delete-confirm')),
        findsOneWidget,
      );
      expect(find.text('Edit Session'), findsNothing);
      expect(workoutState.currentSession, isNull);

      await tester.tap(find.byKey(const Key('day-session-delete-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Plan A'), findsOneWidget);
      expect(find.byTooltip('Start session'), findsOneWidget);
      expect(workoutState.currentSession, isNull);
    },
  );
}
