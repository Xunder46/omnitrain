// Plan 241: an interval that ran out while the app was not ticking records
// its real end, not the instant the app noticed.
//
// `TimerManager.finishTimedEntry(.., {int? expiredAfterSecs})` ends a timed
// entry at start + pauses + the target (never later than now), and
// `TimerManager.recordRestStart(.., {int? atMs})` opens the rest at the
// instant the interval or round really ended (never in the future).
//
// Plan: `docs/plans/2026-11-18-241-expired-interval-records-its-real-end-plan/
// 2026-11-18-241-expired-interval-records-its-real-end-plan.md`.
//
//   S-24101 an expired interval is finished at its target length
//   S-24102 a manual finish still records the whole elapsed time (control)
//   S-24103 an expired interval with a pause is finished at target + pauses
//   S-24104 an expiry whose cap lies after now falls back to now
//   S-24105 the rest after a late-noticed end starts at the real end instant
//   S-24106 a screen opened on an interval that ran out finishes it at 30 s
//   S-24107 a still-running interval is left active on reopen (control)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A mutable clock the manager reads: a test moves [_now] forward instead of
/// waiting for wall time.
DateTime _now = DateTime.utc(2026, 6, 15, 12);

/// A timer manager whose every read of the clock answers [_now].
Future<(MockWorkoutRepository, TimerManager)> _manager() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final timer = TimerManager(
    repo,
    notify: () {},
    setError: (_) {},
    clearError: () {},
    clock: () => _now,
  );
  return (repo, timer);
}

void main() {
  test(
    'S-24101 an interval that ran out is finished at its target, not at now',
    () async {
      final (repo, timer) = await _manager();
      final t0 = _now.millisecondsSinceEpoch;
      await timer.addTimedEntry('e-t');
      await timer.startTimedEntry('e-t', 0);

      // The phone slept five minutes past the 60 s target.
      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 300000, isUtc: true);
      await timer.finishTimedEntry('e-t', 0, expiredAfterSecs: 60);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.actualDurationSecs, 60);
      expect(instance.finishedAtMs, t0 + 60000);
    },
  );

  test(
    'S-24102 a manual finish without the parameter records the whole elapsed '
    'time (control)',
    () async {
      final (repo, timer) = await _manager();
      final t0 = _now.millisecondsSinceEpoch;
      await timer.addTimedEntry('e-t');
      await timer.startTimedEntry('e-t', 0);

      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 300000, isUtc: true);
      await timer.finishTimedEntry('e-t', 0);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.actualDurationSecs, 300);
      expect(instance.finishedAtMs, t0 + 300000);
    },
  );

  test(
    'S-24103 an expired interval that was paused counts its pauses in the cap',
    () async {
      final (repo, timer) = await _manager();
      final t0 = _now.millisecondsSinceEpoch;
      await timer.addTimedEntry('e-t');
      await timer.startTimedEntry('e-t', 0);

      // Ten seconds run, twenty seconds paused, resumed, then the phone slept
      // past the 60 s target.
      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 10000, isUtc: true);
      await timer.pauseTimedEntry('e-t', 0);
      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 30000, isUtc: true);
      await timer.resumeTimedEntry('e-t', 0);
      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 400000, isUtc: true);
      await timer.finishTimedEntry('e-t', 0, expiredAfterSecs: 60);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.actualDurationSecs, 60);
      // start + 20 s paused + 60 s target, not the 400 s until the notice.
      expect(instance.finishedAtMs, t0 + 80000);
    },
  );

  test(
    'S-24104 an expiry whose cap lies after now falls back to now',
    () async {
      final (repo, timer) = await _manager();
      final t0 = _now.millisecondsSinceEpoch;
      await timer.addTimedEntry('e-t');
      await timer.startTimedEntry('e-t', 0);

      // The clock reads 30 s but the cap says 60 s: never an end in the
      // future.
      _now = DateTime.fromMillisecondsSinceEpoch(t0 + 30000, isUtc: true);
      await timer.finishTimedEntry('e-t', 0, expiredAfterSecs: 60);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.finishedAtMs, t0 + 30000);
      expect(instance.actualDurationSecs, 30);
    },
  );

  test(
    'S-24105 the rest after a late-noticed end starts at the real end instant',
    () async {
      final (repo, timer) = await _manager();
      final t0 = _now.millisecondsSinceEpoch;
      final t = DateTime.fromMillisecondsSinceEpoch(t0 + 600000, isUtc: true);
      _now = t;
      final tMs = t.millisecondsSinceEpoch;

      // A past instant is honoured; a future one is not; nothing means now.
      await timer.recordRestStart('e-t', 1, atMs: t0 + 100000);
      await timer.recordRestStart('e-t', 2, atMs: tMs + 600000);
      await timer.recordRestStart('e-t', 3);

      final rests = await repo.getEntryRests('e-t');
      int startOf(int entryIndex) =>
          rests.firstWhere((r) => r.entryIndex == entryIndex).restStartMs;
      expect(startOf(1), t0 + 100000);
      expect(startOf(2), tMs);
      expect(startOf(3), tMs);
    },
  );

  testWidgets(
    'S-24106 a screen opened on an interval that ran out finishes it at its '
    'target length',
    (WidgetTester tester) async {
      final deps = await _buildDeps();
      final effortId = await deps.workoutState.addExerciseToSession(
        await _exerciseWith(deps.repo, 'time'),
      );

      // Stored active with a 30 s target whose start stamp is 60 s in the
      // past: the interval ran out before the screen was opened again.
      final instance = deps.workoutState
          .getTimedInstancesForEffort(effortId)
          .single;
      final startedAtMs =
          DateTime.now().millisecondsSinceEpoch -
          const Duration(seconds: 60).inMilliseconds;
      await deps.repo.updateTimedInstance(
        instance.copyWith(
          state: TimedState.active,
          targetDurationSecs: 30,
          startedAtMs: startedAtMs,
        ),
      );
      await deps.workoutState.loadSessionData();

      await _mount(tester, _screen(deps, initialFocusId: effortId));

      var stored = (await deps.repo.getTimedInstances(effortId)).single;
      // The restore finishes the expired interval with an un-awaited call.
      if (stored.state != TimedState.finished) {
        await tester.pump();
        stored = (await deps.repo.getTimedInstances(effortId)).single;
      }
      expect(stored.state, TimedState.finished);
      expect(stored.actualDurationSecs, 30);
      expect(stored.finishedAtMs, startedAtMs + 30000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-24107 a still-running interval is left active on reopen (control)',
    (WidgetTester tester) async {
      final deps = await _buildDeps();
      final effortId = await deps.workoutState.addExerciseToSession(
        await _exerciseWith(deps.repo, 'time'),
      );

      // A 120 s target started 40 s ago: still running.
      final instance = deps.workoutState
          .getTimedInstancesForEffort(effortId)
          .single;
      await deps.repo.updateTimedInstance(
        instance.copyWith(
          state: TimedState.active,
          targetDurationSecs: 120,
          startedAtMs:
              DateTime.now().millisecondsSinceEpoch -
              const Duration(seconds: 40).inMilliseconds,
        ),
      );
      await deps.workoutState.loadSessionData();

      await _mount(tester, _screen(deps, initialFocusId: effortId));
      await tester.pump();

      final stored = (await deps.repo.getTimedInstances(effortId)).single;
      expect(stored.state, TimedState.active);
      expect(stored.finishedAtMs, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

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
