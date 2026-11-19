// Plan 238 P1 — a note typed on the summary screen survives a quick Done or
// Back (scenarios S-23801..S-23805 of
// docs/plans/2026-11-18-238-summary-note-survives-a-quick-done-plan/
// 2026-11-18-238-summary-note-survives-a-quick-done-plan.md).
//
// The note saves on a 600 ms debounce (`_handleNoteChanged`); a Done or Back
// inside that pause used to drop it. The production fix (`_flushNote` in
// `session_summary_screen.dart`) was applied by the lead; these tests prove
// it. Mock repository only, `testWidgets` only, no `Future.delayed` — every
// value is seeded before the first pump, and the pending debounce timer is
// kept alive by not pumping any wall time between `enterText` and the tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const Size _surface = Size(600, 1600);

/// The only `TextField` on the summary screen (the note field).
Finder get _noteField => find.byType(TextField);

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

/// A finished session (ended with `endSession()`, plan 229's way), then
/// loaded into the shared slot with `viewHistoricalSession(id)`, so the
/// summary screen opens on a historical view.
Future<
  ({MockWorkoutRepository repo, WorkoutState workoutState, String sessionId})
>
_seedFinishedSession() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
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

/// A plain home whose `open` button pushes [route] over it, so the summary
/// can be closed with a route pop (Back).
Widget _pusherHome(Widget route) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              // No transition: a real Back runs a ~0.5 s slide, and the
              // 600 ms note timer would fire inside it. Back pressed a
              // moment after the last key is what loses the note, so the
              // route closes at once here.
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  pageBuilder: (_, _, _) => route,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('S-23801 a note typed under 0.6 s before Done is saved', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedRollingSession();

    await tester.pumpWidget(
      MaterialApp(home: _summaryScreen(workoutState, repo)),
    );
    await tester.pumpAndSettle();

    // The trailing space exercises the trim the debounce timer applies.
    await tester.enterText(_noteField, 'Felt strong ');
    // No time pumped: the 600 ms debounce timer is still pending.
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect((await repo.getSession(sessionId))!.note, 'Felt strong');
  });

  testWidgets('S-23802 a note cleared just before Done stays cleared', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedRollingSession();
    await workoutState.updateSessionNote('old');

    await tester.pumpWidget(
      MaterialApp(home: _summaryScreen(workoutState, repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsOneWidget);

    await tester.enterText(_noteField, '');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect((await repo.getSession(sessionId))!.note, '');
  });

  testWidgets('S-23803 a note typed just before Back is saved', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedRollingSession();

    await tester.pumpWidget(_pusherHome(_summaryScreen(workoutState, repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(_noteField, 'Back note');
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect((await repo.getSession(sessionId))!.note, 'Back note');
  });

  testWidgets('S-23804 a note already saved by the timer survives Done', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedRollingSession();

    await tester.pumpWidget(
      MaterialApp(home: _summaryScreen(workoutState, repo)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_noteField, 'Later note');
    // The 600 ms debounce timer fires and writes the note itself.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect((await repo.getSession(sessionId))!.note, 'Later note');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(workoutState.currentSession, isNull);
    expect((await repo.getSession(sessionId))!.note, 'Later note');
  });

  testWidgets('S-23805 a note typed on a calendar-opened summary survives '
      'Back', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (:repo, :workoutState, :sessionId) = await _seedFinishedSession();

    await tester.pumpWidget(
      _pusherHome(_summaryScreen(workoutState, repo, openedFromCalendar: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(_noteField, 'Hist note');
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect((await repo.getSession(sessionId))!.note, 'Hist note');
  });
}
