// Plan 239 P2 — the summary's rest-day count stops at today (scenarios
// S-23901..S-23903 of
// docs/plans/2026-11-18-239-rest-days-count-only-elapsed-days-plan/
// 2026-11-18-239-rest-days-count-only-elapsed-days-plan.md).
//
// The card under the month grid prints "N workout days / M rest days"; M used
// to cover the whole month, including days that have not started. The
// production fix (`OmniDateUtils.daysElapsedInMonth` in
// `lib/core/utils/date_utils.dart`, used by `_buildCalendarCard` in
// `session_summary_screen.dart`) was applied by the lead; these tests prove
// it. Mock repository only, no `Future.delayed` — every value is seeded
// before the first pump. Harness copied from
// `test/summary_note_survives_quick_done_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const Size _surface = Size(600, 1600);

/// A rolling session seeded the way `test/screen_widget_test.dart`
/// 'rolling session still shows group card, note, and calendar sections'
/// seeds it: feeling 3, so the automatic rating sheet does not open, and
/// one exercise added. Captures the session id before any pumping.
Future<
  ({MockWorkoutRepository repo, WorkoutState workoutState, String sessionId})
>
_seedRollingSession() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(isRolling: true);
  final sessionId = workoutState.currentSession!.id;
  await workoutState.updateSessionFeeling(sessionId, 3);
  final exercises = await repo.getExercises();
  await workoutState.addExerciseToSession(
    exercises.first,
    chosenMetric: 'reps',
  );
  return (repo: repo, workoutState: workoutState, sessionId: sessionId);
}

/// Like `_seedFinishedSession` in
/// `test/summary_note_survives_quick_done_test.dart`, but the session is
/// created at the real clock shifted to the 10th of the PREVIOUS month (the
/// Dart constructor normalises month 0 to December of the previous year), so
/// the calendar card shows a fully elapsed past month.
Future<
  ({MockWorkoutRepository repo, WorkoutState workoutState, String sessionId})
>
_seedFinishedSessionLastMonth() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final now = DateTime.now();
  final lastMonth10 = DateTime(now.year, now.month - 1, 10, 12);
  final workoutState = WorkoutState(repo, clock: () => lastMonth10);
  await workoutState.createNewSession();
  final sessionId = workoutState.currentSession!.id;
  final exercises = await repo.getExercises();
  final effortId = await workoutState.addExerciseToSession(
    exercises.first,
    chosenMetric: 'reps',
  );
  await workoutState.updateEntryValue(effortId, 0, 'reps', 5);
  await workoutState.endSession(writeToHealth: false);
  await workoutState.viewHistoricalSession(sessionId);
  return (repo: repo, workoutState: workoutState, sessionId: sessionId);
}

Widget _summaryScreen(
  WorkoutState workoutState,
  MockWorkoutRepository repo, {
  bool openedFromCalendar = false,
}) {
  return SessionSummaryScreen(
    workoutState: workoutState,
    routineState: RoutineState(repo),
    sessionSummaryService: SessionSummaryService(repo),
    settingsState: SettingsState(repo, fakePreferencesService()),
    timerAlertService: FakeTimerAlertService(),
    openedFromCalendar: openedFromCalendar,
  );
}

void main() {
  test('S-23901 daysElapsedInMonth counts only days that have started', () {
    // A past month returns its full length, even though "today" is the 18th.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 10, 1),
        DateTime(2026, 11, 18),
      ),
      31,
    );
    // The same month returns today's day number (today counts).
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 18),
      ),
      18,
    );
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 1),
      ),
      1,
    );
    // A leap February, seen from the next month.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2028, 2, 1),
        DateTime(2028, 3, 5),
      ),
      29,
    );
    // A December seen from January of the next year.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 12, 1),
        DateTime(2027, 1, 5),
      ),
      31,
    );
    // A later month returns 0.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2027, 1, 1),
        DateTime(2026, 12, 31),
      ),
      0,
    );
    // The last day of the same month.
    expect(
      OmniDateUtils.daysElapsedInMonth(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      ),
      30,
    );
  });

  testWidgets('S-23902 the post-workout summary counts rest days up to today',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedRollingSession();

    await tester.pumpWidget(
      MaterialApp(home: _summaryScreen(workoutState, repo)),
    );
    await tester.pumpAndSettle();

    // Read AFTER the pump: the seeded workout day is today, so the card
    // shows 1 workout day and the rest days elapsed before today. If today
    // is the 1st the expected rest count is 0; the formula covers it.
    final now = DateTime.now();
    expect(
      find.text('1 workout days / ${now.day - 1} rest days'),
      findsOneWidget,
    );
  });

  testWidgets('S-23903 a past-month summary counts that whole month', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) =
        await _seedFinishedSessionLastMonth();

    await tester.pumpWidget(
      MaterialApp(
        home: _summaryScreen(
          workoutState,
          repo,
          openedFromCalendar: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A past month is fully elapsed, so only its one workout day (the 10th)
    // is subtracted from its full length.
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final daysInThatMonth =
        DateTime(lastMonth.year, lastMonth.month + 1, 0).day;
    expect(
      find.text('1 workout days / ${daysInThatMonth - 1} rest days'),
      findsOneWidget,
    );
  });
}
