// Live Calories chip on the active session screen — plan 134d, phase P2.
//
// Scenarios S-13445 .. S-13449 of
// `docs/plans/2026-11-09-134d-live-session-calories-plan/2026-11-09-134d-live-session-calories-plan.md`,
// driven against the built session screen
// (`lib/features/session/workout_session_screen.dart`).
//
// Mock-first: every screen here is pumped over `MockWorkoutRepository` and
// every elapsed count is seeded through the repository — a backdated start
// row, never a real wait — so no `testWidgets` body ever awaits real time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
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

/// plan 135 (S-13508..S-13510): the optional holder the wrist's `energy_live`
/// frame fills; a dep built without it behaves exactly as before.
typedef _WristEnergy =
    ValueNotifier<({String sessionId, double kcal, DateTime at})?>;

Future<_Deps> _buildDeps({String? modality, _WristEnergy? wristEnergy}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(
    repo,
    activeEnergy: ActiveEnergyService(repo, () => StatsProgressService(repo)),
    wristEnergy: wristEnergy,
  );
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(isRolling: false, modality: modality);
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

/// Logs a bodyweight measurement of [kg] — the live figure's weight input.
Future<void> _seedBodyWeight(_Deps deps, double kg) async {
  await deps.repo.saveMeasurementEntry(
    BodyMeasurementEntry(
      id: 'bw1',
      measurementType: 'bodyweight',
      value: kg,
      unitId: 'unit-kg',
      recordedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}

/// The live chip's value text.
String _chipValue(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('omni_session_live_calories_value')))
      .data!;
}

void main() {
  testWidgets('S-13445: resistance session, 80 kg, 1800 s reads ~100 kcal', (
    tester,
  ) async {
    final deps = await _buildDeps(modality: Modality.resistanceLifting);
    await _addTimedExercise(deps);
    await _seedBodyWeight(deps, 80.0);
    await _backdateSessionStart(deps, 1800);
    await _pumpSession(tester, deps);

    expect(find.text('Calories'), findsOneWidget);
    expect(_chipValue(tester), '~100 kcal');
    expect(find.text('Session Time'), findsOneWidget);
  });

  testWidgets(
    'S-13445b a weight logged while the screen is open is read again '
    'on the 60th tick', (tester) async {
      final deps = await _buildDeps(modality: Modality.resistanceLifting);
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);
      expect(_chipValue(tester), '~100 kcal');

      // A newer entry: 90 kg, recorded after the 80 kg seed above.
      await deps.repo.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'bw2',
          measurementType: 'bodyweight',
          value: 90.0,
          unitId: 'unit-kg',
          recordedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // 58 s: 59 ticks in total including the one _pumpSession pumped — the
      // 60th tick, the only re-read, has not run yet. A re-read on every
      // tick shows the 90 kg figure here already.
      await tester.pump(const Duration(seconds: 58));
      expect(_chipValue(tester), '~100 kcal');

      // One more second is the 60th tick: the weight is re-read and the
      // label recomputes (2.5 x 90 x ~1802 s / 3600 = ~113). A % 61 mutant
      // re-reads on the 61st tick only, so it stays ~100 here and fails.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(_chipValue(tester), '~113 kcal');
    },
  );

  testWidgets('S-13446: no body weight on file reads —', (tester) async {
    final deps = await _buildDeps(modality: Modality.resistanceLifting);
    await _addTimedExercise(deps);
    await _backdateSessionStart(deps, 1800);
    await _pumpSession(tester, deps);

    expect(_chipValue(tester), '—');
  });

  group('S-13447: geometry at 390x844', () {
    testWidgets('the chip sits right of the time chip, flush to the padding', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: Modality.resistanceLifting);
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);

      final calories = tester.getRect(
        find.byKey(const Key('omni_session_live_calories')),
      );
      final timeLabel = tester.getRect(find.text('Session Time'));
      expect(calories.left, greaterThan(timeLabel.right));
      expect(calories.right, closeTo(370.0, 1.0));
      // Tops: the two chips' label texts start at the same height.
      final caloriesTop = tester.getTopLeft(find.text('Calories'));
      expect(caloriesTop.dy, closeTo(timeLabel.top, 1.0));
    });
  });

  testWidgets(
    'S-13448: Free Training session (null modality) reads ~100 kcal',
    (tester) async {
      final deps = await _buildDeps();
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);

      expect(_chipValue(tester), '~100 kcal');
    },
  );

  group('S-13449: no exercise yet and the edit-mode screen', () {
    testWidgets('no exercise yet: ~0 kcal with the clock at 00:00', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: Modality.resistanceLifting);
      await _seedBodyWeight(deps, 80.0);
      await _pumpSession(tester, deps);

      expect(find.text('00:00'), findsOneWidget);
      expect(_chipValue(tester), '~0 kcal');
    });

    testWidgets('edit mode: no Calories chip, Session Time present', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: Modality.resistanceLifting);
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps, editMode: true);

      expect(find.text('Calories'), findsNothing);
      expect(find.text('Session Time'), findsOneWidget);
    });

    testWidgets('S-13449c edit mode on a session with no exercise shows no '
        'Calories chip', (tester) async {
      // No exercise: the empty-state bar of the standard list view is the
      // branch under test, so nothing is added here.
      final deps = await _buildDeps(modality: Modality.resistanceLifting);
      await _pumpSession(tester, deps, editMode: true);

      // The bar under test is the empty-state row of the standard list view:
      // 'Add Exercise' is only built there.
      expect(find.text('Add Exercise'), findsOneWidget);
      expect(find.text('Session Time'), findsOneWidget);
      expect(find.text('Calories'), findsNothing);
      expect(find.byKey(const Key('omni_session_live_calories')), findsNothing);
    });
  });

  group('plan 135: the wrist kcal on the chip (S-13508..S-13510)', () {
    /// The fixed instant the fake wrist frames carry.
    final at = DateTime.utc(2026, 11, 9, 12);

    testWidgets('S-13508 a wrist frame for the open session replaces the '
        'estimate', (tester) async {
      final wrist = _WristEnergy(null);
      final deps = await _buildDeps(
        modality: Modality.resistanceLifting,
        wristEnergy: wrist,
      );
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      final sessionId = deps.workoutState.currentSession!.id;
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);

      expect(_chipValue(tester), '~100 kcal', reason: 'the old estimate');

      wrist.value = (sessionId: sessionId, kcal: 42.6, at: at);
      await tester.pump();
      expect(_chipValue(tester), '43 kcal');
    });

    testWidgets('S-13509 the chip stays at the wrist kcal while the clock '
        'ticks', (tester) async {
      final wrist = _WristEnergy(null);
      final deps = await _buildDeps(
        modality: Modality.resistanceLifting,
        wristEnergy: wrist,
      );
      await _addTimedExercise(deps);
      await _seedBodyWeight(deps, 80.0);
      final sessionId = deps.workoutState.currentSession!.id;
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);

      wrist.value = (sessionId: sessionId, kcal: 42.6, at: at);
      await tester.pump();
      // A rest: three more ticks, the estimate would have climbed.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(_chipValue(tester), '43 kcal');
    });

    testWidgets('S-13510 a wrist kcal shows with no body weight, and only '
        'for the open session', (tester) async {
      final wrist = _WristEnergy(null);
      final deps = await _buildDeps(
        modality: Modality.resistanceLifting,
        wristEnergy: wrist,
      );
      await _addTimedExercise(deps);
      final sessionId = deps.workoutState.currentSession!.id;
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);
      expect(_chipValue(tester), '—');

      wrist.value = (sessionId: sessionId, kcal: 42.6, at: at);
      await tester.pump();
      expect(_chipValue(tester), '43 kcal');

      // A frame naming another session id does not light this screen's chip.
      wrist.value = (sessionId: 's-13502', kcal: 99, at: at);
      await tester.pump();
      expect(_chipValue(tester), '—');
    });

    testWidgets('S-13510b a total the phone already holds when the screen '
        'opens shows only if it names this session', (tester) async {
      final other = _WristEnergy((sessionId: 's-13502', kcal: 99, at: at));
      final deps = await _buildDeps(
        modality: Modality.resistanceLifting,
        wristEnergy: other,
      );
      await _addTimedExercise(deps);
      await _backdateSessionStart(deps, 1800);
      await _pumpSession(tester, deps);
      expect(_chipValue(tester), '—', reason: 'a held total of another session');
    });

    testWidgets('S-13510c a total the phone already holds for this session '
        'shows when the screen opens', (tester) async {
      final mine = _WristEnergy(null);
      final deps2 = await _buildDeps(
        modality: Modality.resistanceLifting,
        wristEnergy: mine,
      );
      await _addTimedExercise(deps2);
      mine.value = (
        sessionId: deps2.workoutState.currentSession!.id,
        kcal: 42.6,
        at: at,
      );
      await _backdateSessionStart(deps2, 1800);
      await _pumpSession(tester, deps2);
      expect(_chipValue(tester), '43 kcal', reason: 'held before the screen opened');
    });
  });
}
