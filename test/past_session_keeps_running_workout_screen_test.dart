// Plan 229 P1 — the calendar puts the running workout back when the summary
// closes: a tap on a finished past session (S-22906) and a tap on the
// completed row of the day list (S-22907).
//
// Mock repository only. The calendar's clock is fixed like
// `test/calendar_streak_screen_test.dart`, so the past day is the fixed June
// 8 2026 — at least two days before the calendar's now, and in the real past
// too (the real date the suite runs on is later). The running workout uses
// the state's own clock; only its identity is asserted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart' show repsRow, weightRow;

/// The calendar's now: the past day is two days before it and never today.
DateTime _now() => DateTime(2026, 6, 10, 9);
DateTime get _pastDay => DateTime(2026, 6, 8, 12);

Future<MockWorkoutRepository> freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A finished session on the past day, titled so the day list row has a
/// deterministic label. Built with fixed dates, not the harness `seedSession`,
/// whose 24 h steps drift after a clock change.
Future<void> seedPastSession(
  MockWorkoutRepository repo, {
  required String sessionId,
}) async {
  final at = _pastDay.millisecondsSinceEpoch;
  await repo.createExercise(
    Exercise(
      id: 'ex-bench',
      name: 'Bench Press',
      capabilities: ['load'],
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: at,
      endedAtMs: at + 3600000,
      title: 'Past Strength',
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createEffort(
    SegmentEffort(
      id: 'eff-$sessionId',
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-bench',
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createObservation(repsRow('eff-$sessionId', 0, 5, atMs: at));
  await repo.createObservation(weightRow('eff-$sessionId', 0, 80, atMs: at));
}

/// Starts the running workout on [state] over the seeded repo: an exercise
/// and a logged set, so the resumed session is active again. Returns its id.
Future<String> startRunningWorkout(
  MockWorkoutRepository repo,
  WorkoutState state,
) async {
  final exercise = (await repo.getExercises()).firstWhere(
    (e) => e.id == 'ex-bench',
  );
  await state.createNewSession();
  final effortId = await state.addExerciseToSession(exercise);
  await state.updateEntryValue(effortId, 0, 'reps', 3);
  await state.updateEntryValue(effortId, 0, 'weight', 100.0);
  return state.currentSession!.id;
}

Widget _screen({
  required MockWorkoutRepository repo,
  required CalendarState calendarState,
  required WorkoutState workoutState,
  required SettingsState settingsState,
  required Widget child,
}) => MaterialApp(
  home: child,
);

DaySessionListScreen _dayList({
  required DateTime date,
  required CalendarState calendarState,
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
  required SettingsState settingsState,
}) => DaySessionListScreen(
  date: date,
  calendarState: calendarState,
  routineState: RoutineState(repo),
  workoutState: workoutState,
  routineSessionService: RoutineSessionService(repo),
  sessionSummaryService: SessionSummaryService(repo),
  settingsState: settingsState,
  timerAlertService: FakeTimerAlertService(),
);

CalendarScreen _calendar({
  required CalendarState calendarState,
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
  required SettingsState settingsState,
}) => CalendarScreen(
  calendarState: calendarState,
  periodState: PeriodState(repo),
  workoutState: workoutState,
  routineState: RoutineState(repo),
  routineSessionService: RoutineSessionService(repo),
  sessionSummaryService: SessionSummaryService(repo),
  settingsState: settingsState,
  timerAlertService: FakeTimerAlertService(),
);

void main() {
  group('Plan 229 the running workout survives a past session view', () {
    testWidgets('S-22906 the calendar puts the running workout back after the summary closes',
        (tester) async {
      final repo = await freshRepo();
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await seedPastSession(repo, sessionId: 's-past');
      final runningId = await startRunningWorkout(repo, workoutState);

      // Seed before init: the calendar loads the month's entries at init.
      final calendarState = CalendarState(repo, now: _now);
      await calendarState.init();

      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _screen(
          repo: repo,
          calendarState: calendarState,
          workoutState: workoutState,
          settingsState: settingsState,
          child: _calendar(
            calendarState: calendarState,
            workoutState: workoutState,
            repo: repo,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The past day's cell: the day number 8 in the month grid.
      await tester.tap(find.text('8').first);
      await tester.pumpAndSettle();
      expect(find.byType(SessionSummaryScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(SessionSummaryScreen), findsNothing);

      expect(workoutState.currentSession!.id, runningId);
      expect(workoutState.currentSession!.endedAtMs, isNull);
      expect(workoutState.hasActiveSession, isTrue);
    });

    testWidgets('S-22907 the day list puts the running workout back after the summary closes',
        (tester) async {
      final repo = await freshRepo();
      final workoutState = WorkoutState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await seedPastSession(repo, sessionId: 's-past');
      final runningId = await startRunningWorkout(repo, workoutState);

      // Seed before init: the calendar loads the month's entries at init.
      final calendarState = CalendarState(repo, now: _now);
      await calendarState.init();

      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _screen(
          repo: repo,
          calendarState: calendarState,
          workoutState: workoutState,
          settingsState: settingsState,
          child: _dayList(
            date: DateTime(2026, 6, 8),
            calendarState: calendarState,
            workoutState: workoutState,
            repo: repo,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Past Strength'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionSummaryScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(SessionSummaryScreen), findsNothing);

      expect(workoutState.currentSession!.id, runningId);
      expect(workoutState.currentSession!.endedAtMs, isNull);
      expect(workoutState.hasActiveSession, isTrue);
    });
  });
}
