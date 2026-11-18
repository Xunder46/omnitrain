// Plan 233: a workout screen opened while an interval is running counts it.
//
// The screen restores a session from storage with
// `_restoreTimerStateFromPersisted` (`workout_session_screen.dart`, in
// `_loadExercises`), which seeds a persisted running interval's elapsed digits
// and in-progress key but starts no ticker. `_adoptRunningTimerState()` — the
// step the watch-driven resync already runs — starts the ticker, the running
// flag and the expiry notification. `_loadExercises` now calls it right after
// the restore, so Back-to-Home-and-return (or an app relaunch) mid-interval
// keeps the interval counting instead of freezing it.
//
// Mock-first: every future below is a microtask of the mock repository, so no
// real clock, Hive write or `Future.delayed` runs inside FakeAsync. The
// instances compute elapsed from the real wall clock (`DateTime.now()`), which
// `pump(Duration)` does not advance, so the digits are asserted as ranges.
//
//   S-23301 a timed interval stored running counts on the reopened screen
//   S-23302 a round stored running sweeps its countdown ring
//   S-23303 a paused interval opens paused with no running control
//   S-23304 an interval that ran out while the screen was away is finished

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// The phone every scenario is measured at: a tall 390 x 844.
const Size _phoneSurface = Size(390, 844);

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Suppress first-run coach-mark sheets that interfere with finder assertions.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  MockWorkoutRepository repo,
});

Future<_Deps> _buildDeps({String modality = 'cardio_endurance'}) async {
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
    repo: repo,
  );
}

Widget _screen(_Deps deps, {String? initialFocusId}) => MaterialApp(
  home: WorkoutSessionScreen(
    workoutState: deps.workoutState,
    routineState: deps.routineState,
    sessionSummaryService: deps.sessionSummaryService,
    settingsState: deps.settingsState,
    timerAlertService: FakeTimerAlertService(),
    initialFocusId: initialFocusId,
  ),
);

/// The frame that mounts the screen, then the frames that run its deferred
/// first load (D-150). No `pumpAndSettle`: an adopted ticker never settles.
Future<void> _mount(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(_phoneSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(screen);
  await tester.pump();
  await tester.pump();
}

Future<Exercise> _exerciseWith(
  MockWorkoutRepository repo,
  String capability,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.capabilities.contains(capability));
}

/// Moves a started instance's start stamp [elapsed] into the past and reloads
/// the session, so the screen restores from the repository the way a reopen
/// does. The instance reads elapsed from the real wall clock, so the restored
/// digits are [elapsed] plus the milliseconds the test body spends.
Future<void> _backdateTimedStart(
  _Deps deps, {
  required String effortId,
  int entryIndex = 0,
  required Duration elapsed,
}) async {
  final instance = deps.workoutState.getTimedInstancesForEffort(
    effortId,
  )[entryIndex];
  await deps.repo.updateTimedInstance(
    instance.copyWith(
      startedAtMs:
          DateTime.now().millisecondsSinceEpoch - elapsed.inMilliseconds,
    ),
  );
  await deps.workoutState.loadSessionData();
}

/// Freezes a paused interval at exactly [elapsed]: a paused instance derives
/// its elapsed from `pausedAtMs - startedAtMs`, so the start stamp is moved
/// back from the pause instant and the value stops moving.
Future<void> _freezePausedTimed(
  _Deps deps, {
  required String effortId,
  required Duration elapsed,
}) async {
  final instance = deps.workoutState
      .getTimedInstancesForEffort(effortId)
      .single;
  await deps.repo.updateTimedInstance(
    instance.copyWith(
      startedAtMs: instance.pausedAtMs! - elapsed.inMilliseconds,
    ),
  );
  await deps.workoutState.loadSessionData();
}

/// Moves a started round's start stamp [elapsed] into the past and reloads the
/// session, the way the round countdown tests backdate a restored round.
Future<void> _backdateRoundStart(
  _Deps deps, {
  required String effortId,
  required Duration elapsed,
}) async {
  final round = deps.workoutState.getRoundsForEffort(effortId).single;
  await deps.repo.updateRoundInstance(
    round.copyWith(
      startedAtMs:
          DateTime.now().millisecondsSinceEpoch - elapsed.inMilliseconds,
    ),
  );
  await deps.workoutState.loadSessionData();
}

void main() {
  testWidgets('S-23301 a timed interval stored running counts on the reopened '
      'screen and holds the in-progress lock', (WidgetTester tester) async {
    final deps = await _buildDeps();
    final effortId = await deps.workoutState.addExerciseToSession(
      await _exerciseWith(deps.repo, 'time'),
    );

    // The phone started interval 1 itself; the stamp is pushed 40 s into the
    // past, then the session is reloaded, so the mount reads a persisted
    // running interval the way a reopen does. Interval 2 never started.
    await deps.workoutState.startTimedEntry(effortId, 0);
    await deps.workoutState.addEntry(effortId);
    await _backdateTimedStart(
      deps,
      effortId: effortId,
      elapsed: const Duration(seconds: 40),
    );

    await _mount(tester, _screen(deps, initialFocusId: effortId));

    expect(
      find.text('Interval 1 of 2'),
      findsOneWidget,
      reason: 'S-23301 the screen opens on the first of the two intervals',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Interval'),
      findsOneWidget,
      reason:
          'S-23301 the stored running interval offers the log control: the '
          'reopen adopted it as its own running timer',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('count-up-digits')),
        matching: find.textContaining(RegExp(r'00:4\d')),
      ),
      findsOneWidget,
      reason:
          'S-23301 the digits count the stored forty seconds, not the phone\'s '
          'zero',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-23301 nothing escapes the frame',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.takeException(),
      isNull,
      reason:
          'S-23301 nothing escapes the frame from the adopted ticker either',
    );

    // The ticker is live: the stored start moves back to 100 s ago, and the
    // next ticks (the clock is the instance's, not the test's) show it. A
    // screen that only restored the numbers has no ticker and stays at 00:4x.
    await _backdateTimedStart(
      deps,
      effortId: effortId,
      elapsed: const Duration(seconds: 100),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.descendant(
        of: find.byKey(const Key('count-up-digits')),
        matching: find.textContaining(RegExp(r'01:4\d')),
      ),
      findsOneWidget,
      reason: 'S-23301 the adopted ticker re-reads the interval every second',
    );

    // The adopted interval holds the in-progress lock: interval 2 refuses.
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();
    expect(
      find.text('Interval 2 of 2'),
      findsOneWidget,
      reason: 'S-23301 the user moved to interval 2, which never started',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsOneWidget,
      reason: 'S-23301 interval 2 offers Start',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Another set is still in progress'),
      findsOneWidget,
      reason:
          'S-23301 the adopted interval holds the in-progress lock, so the '
          'screen refuses to start a second timer beside it',
    );
    expect(
      deps.workoutState.getTimedInstancesForEffort(effortId)[1].state,
      TimedState.notStarted,
      reason: 'S-23301 and interval 2 was not started',
    );
    expect(
      deps.workoutState.getTimedInstancesForEffort(effortId)[0].state,
      TimedState.active,
      reason: 'S-23301 interval 1 keeps running',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-23301 nothing escapes the frame',
    );
  });

  testWidgets('S-23302 a round stored running sweeps its countdown ring on the '
      'reopened screen', (WidgetTester tester) async {
    final deps = await _buildDeps();
    final effortId = await deps.workoutState.addExerciseToSession(
      await _exerciseWith(deps.repo, 'rounds'),
      effortKindOverride: 'round',
    );

    // A 120 s round started 30 s ago, persisted through the repository and
    // reloaded, so the mount reads a stored running round.
    await deps.workoutState.updateRoundPlannedDuration(effortId, 0, 120);
    await deps.workoutState.startRound(effortId, 0);
    await _backdateRoundStart(
      deps,
      effortId: effortId,
      elapsed: const Duration(seconds: 30),
    );

    await _mount(tester, _screen(deps, initialFocusId: effortId));

    expect(
      find.text('Round 1 of 1'),
      findsOneWidget,
      reason: 'S-23302 the screen opens on the round',
    );
    expect(
      tester.widget<TimerRing>(find.byType(TimerRing)).running,
      isTrue,
      reason:
          'S-23302 the ring sweeps: the stored round is running on the '
          'reopened screen, not frozen at the time of the reopen',
    );
    expect(
      find.descendant(
        of: find.byType(TimerRing),
        matching: find.textContaining(RegExp(r'01:[23]\d')),
      ),
      findsOneWidget,
      reason:
          'S-23302 the ring counts the remaining ~90 s of the stored 120 s '
          'round, not the full length of a stopped one',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Round'),
      findsOneWidget,
      reason: 'S-23302 a running round offers its log control, not Start',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsNothing,
      reason: 'S-23302 and Start is gone while the round runs',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-23302 nothing escapes the frame',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.takeException(),
      isNull,
      reason:
          'S-23302 nothing escapes the frame from the adopted ticker either',
    );
  });

  testWidgets(
    'S-23303 a paused interval opens paused with no running control',
    (WidgetTester tester) async {
      final deps = await _buildDeps();
      final effortId = await deps.workoutState.addExerciseToSession(
        await _exerciseWith(deps.repo, 'time'),
      );

      // Started and paused on the phone, then frozen at exactly 20 s of elapsed
      // by moving the start stamp back from the pause instant.
      await deps.workoutState.startTimedEntry(effortId, 0);
      await deps.workoutState.pauseTimedEntry(effortId, 0);
      await _freezePausedTimed(
        deps,
        effortId: effortId,
        elapsed: const Duration(seconds: 20),
      );

      await _mount(tester, _screen(deps, initialFocusId: effortId));

      expect(
        deps.workoutState.getTimedInstancesForEffort(effortId).single.state,
        TimedState.paused,
        reason: 'S-23303 the interval is stored paused',
      );
      expect(
        find.widgetWithText(FilledButton, 'Resume'),
        findsOneWidget,
        reason: 'S-23303 a paused interval offers Resume, not the running look',
      );
      expect(
        find.widgetWithText(FilledButton, 'Log Interval'),
        findsNothing,
        reason: 'S-23303 and no running log control is offered',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('count-up-digits')),
          matching: find.textContaining(RegExp(r'00:2\d')),
        ),
        findsOneWidget,
        reason: 'S-23303 the digits read the stored twenty seconds',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-23303 nothing escapes the frame',
      );
    },
  );

  testWidgets('S-23304 an interval that ran out while the screen was away is '
      'finished', (WidgetTester tester) async {
    final deps = await _buildDeps();
    final effortId = await deps.workoutState.addExerciseToSession(
      await _exerciseWith(deps.repo, 'time'),
    );

    // Stored active with a 30 s target whose start stamp is 60 s in the past:
    // the interval ran out before the screen was opened again.
    final instance = deps.workoutState
        .getTimedInstancesForEffort(effortId)
        .single;
    await deps.repo.updateTimedInstance(
      instance.copyWith(
        state: TimedState.active,
        targetDurationSecs: 30,
        startedAtMs:
            DateTime.now().millisecondsSinceEpoch -
            const Duration(seconds: 60).inMilliseconds,
      ),
    );
    await deps.workoutState.loadSessionData();

    await _mount(tester, _screen(deps, initialFocusId: effortId));

    expect(
      deps.workoutState.getTimedInstancesForEffort(effortId).single.state,
      TimedState.finished,
      reason: 'S-23304 the restore finished the interval that ran out',
    );
    expect(
      find.text('LOGGED'),
      findsOneWidget,
      reason: 'S-23304 the finished interval reads as logged, not running',
    );
    expect(
      find.widgetWithText(FilledButton, 'Log Interval'),
      findsNothing,
      reason: 'S-23304 no running log control is offered',
    );
    expect(
      find.widgetWithText(FilledButton, 'Start'),
      findsNothing,
      reason: 'S-23304 and nothing offers a start either',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-23304 nothing escapes the frame',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.takeException(),
      isNull,
      reason: 'S-23304 nothing escapes the frame either',
    );
  });
}
