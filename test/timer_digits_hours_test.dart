// Timer digits past an hour — plan 39, phase P1.
//
// Scenarios S-4702 (the session header), S-4703 (the rest chip) and S-4706
// (the list's `total` line) of
// `docs/plans/2026-10-17-39-logger-polish-2-plan/2026-10-17-39-logger-polish-2-plan.md`,
// driven against the built session screen
// (`lib/features/session/workout_session_screen.dart`).
//
// Mock-first: every screen here is pumped over `MockWorkoutRepository` and
// every elapsed count is seeded through the repository — a backdated start
// row, never a real wait — so no `testWidgets` body ever awaits real time.

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

/// The phone every scenario is measured at.
const Size _phone = Size(390, 844);

/// The timed exercise the scenarios put on the session.
const String _timedExerciseId = 'exercise-easy-run';

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

Future<_Deps> _buildDeps() async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(isRolling: false);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    repo: repo,
  );
}

/// Adds the timed exercise the header, chip and total scenarios count on, and
/// returns its effort id.
Future<String> _addTimedExercise(_Deps deps) async {
  final exercises = await deps.repo.getExercises();
  final exercise = exercises.firstWhere((e) => e.id == _timedExerciseId);
  return deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'timed',
  );
}

Widget _buildSessionScreen(_Deps deps, {bool editMode = false}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
    ),
  );
}

/// Mounts the session screen and lets its own 1 s ticker run once, so the
/// header and the rest chip have counted.
Future<void> _pumpSession(
  WidgetTester tester,
  _Deps deps, {
  bool editMode = false,
}) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(_buildSessionScreen(deps, editMode: editMode));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Moves the live session's start back [seconds] and re-reads the session the
/// way a resumed one is read, so the header's own clock computes its elapsed
/// time from the backdated start.
Future<void> _backdateSessionStart(_Deps deps, int seconds) async {
  final session = deps.workoutState.currentSession!;
  final now = DateTime.now().millisecondsSinceEpoch;
  await deps.repo.updateSession(
    TrainingSession(
      id: session.id,
      ownerUserId: session.ownerUserId,
      routineTemplateId: session.routineTemplateId,
      startedAtMs: now - seconds * 1000,
      title: session.title,
      note: session.note,
      locationText: session.locationText,
      modality: session.modality,
      intent: session.intent,
      perceivedSessionRpe: session.perceivedSessionRpe,
      sessionFeeling: session.sessionFeeling,
      qualityRating: session.qualityRating,
      isRolling: session.isRolling,
      createdAtMs: session.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.loadHistoricalSession(session.id);
}

/// Opens a rest for the first set of [effortId] with its start [seconds] in
/// the past, and re-reads the effort so the chip counts from that age.
Future<void> _openBackdatedRest(
  _Deps deps,
  String effortId,
  int seconds,
) async {
  await deps.workoutState.recordRestStart(effortId, 0);
  final rest = deps.workoutState.getEntryRests(effortId).last;
  final now = DateTime.now().millisecondsSinceEpoch;
  await deps.repo.updateEntryRest(
    rest.copyWith(restStartMs: now - seconds * 1000),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

/// Puts [elapsedMs] on the first timed instance of [effortId] by moving its
/// `startedAtMs` back from its pause instant, so the list reads that elapsed
/// percent back exactly. A paused instance adds no wall-clock time of its own.
Future<void> _seedTimedElapsed(
  _Deps deps,
  String effortId,
  int elapsedMs,
) async {
  final existing = (await deps.repo.getTimedInstances(
    effortId,
  )).firstWhere((instance) => instance.entryIndex == 0);
  final now = DateTime.now().millisecondsSinceEpoch;
  await deps.repo.updateTimedInstance(
    TimedInstance(
      id: existing.id,
      effortId: effortId,
      entryIndex: 0,
      targetDurationSecs: existing.targetDurationSecs,
      startedAtMs: now - elapsedMs,
      state: TimedState.paused,
      pausedAtMs: now,
      actualDurationSecs: 0,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

/// The digits the rest chip draws — the chip carries one `Text`.
String _restChipElapsed(WidgetTester tester) {
  final text = tester.widget<Text>(
    find
        .descendant(
          of: find.byKey(const Key('rest-overlay-chip')),
          matching: find.byType(Text),
        )
        .first,
  );
  return text.data!;
}

void main() {
  // ── Session header (S-4702) ───────────────────────────────────────────────

  group('Timer digits past an hour — session header (S-4702)', () {
    testWidgets('S-4702: a live session 4535 s old reads 1:15:35', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _addTimedExercise(deps);
      await _backdateSessionStart(deps, 4535);

      await _pumpSession(tester, deps);

      expect(find.text('Session Time'), findsOneWidget);
      expect(find.text('1:15:35'), findsOneWidget);
    });

    testWidgets('S-4702: a live session 59 s old keeps the mm:ss shape', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _addTimedExercise(deps);
      await _backdateSessionStart(deps, 59);

      await _pumpSession(tester, deps);

      expect(find.text('00:59'), findsOneWidget);
    });

    testWidgets('S-4702: edit mode reads the stored window as h:mm:ss', (
      tester,
    ) async {
      final deps = await _buildDeps();
      await _addTimedExercise(deps);
      await deps.workoutState.endSession();
      // A stored window of 4535 s, the way the duration dialog writes one.
      await deps.workoutState.updateSessionEndTime(4535);

      await _pumpSession(tester, deps, editMode: true);

      expect(find.text('1:15:35'), findsOneWidget);
    });
  });

  // ── Rest chip (S-4703) ────────────────────────────────────────────────────

  group('Timer digits past an hour — rest chip (S-4703)', () {
    testWidgets('S-4703: a rest open 4535 s reads 1:15:35', (tester) async {
      final deps = await _buildDeps();
      final effortId = await _addTimedExercise(deps);
      await _openBackdatedRest(deps, effortId, 4535);

      await _pumpSession(tester, deps);

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      expect(_restChipElapsed(tester), '1:15:35');
    });

    testWidgets('S-4703: a rest open 75 s reads 01:15', (tester) async {
      final deps = await _buildDeps();
      final effortId = await _addTimedExercise(deps);
      await _openBackdatedRest(deps, effortId, 75);

      await _pumpSession(tester, deps);

      expect(_restChipElapsed(tester), '01:15');
    });
  });

  // ── List `total` line (S-4706) ────────────────────────────────────────────

  group('Timer digits past an hour — list total (S-4706)', () {
    testWidgets('S-4706: a 4535 s timed total reads 1:15:35 total', (
      tester,
    ) async {
      final deps = await _buildDeps();
      final effortId = await _addTimedExercise(deps);
      await _seedTimedElapsed(deps, effortId, 4535000);

      await _pumpSession(tester, deps);

      expect(find.text('1:15:35 total'), findsOneWidget);
    });

    testWidgets('S-4706: a 125 s timed total reads 02:05 total', (
      tester,
    ) async {
      final deps = await _buildDeps();
      final effortId = await _addTimedExercise(deps);
      await _seedTimedElapsed(deps, effortId, 125000);

      await _pumpSession(tester, deps);

      expect(find.text('02:05 total'), findsOneWidget);
    });
  });
}
