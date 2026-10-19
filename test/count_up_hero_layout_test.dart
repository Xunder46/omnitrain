// Count-up hero digits and the tightened sports body (plan 39, P4).
//
// Covers:
//   S-4710 the live interval and hold digits render at the `hero` tier —
//          112 sp ([kCountUpDigitsFontSize]) inside a `FittedBox(scaleDown)` —
//          the `ELAPSED` caption stays, a value past an hour reads `1:15:35`,
//          and the sports ring digits are 48 sp ([kRingDigitsFontSize]) inside
//          the ring's usable chord.
//   S-4711 the set bar cell is 34 dp with captions and 18 dp without, and the
//          ring starts within 12 dp of the bar (no 8 dp spacer above it).
//
// Mock-first: every case runs on `MockWorkoutRepository` with no Hive write and
// no real clock. Elapsed time is seeded through the repository and read back by
// the restore path, so `tester.pump` never has to advance a wall clock.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';
import 'package:omnitrain/widgets/session/timer_ring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers (copied from test/count_up_screen_test.dart) ──────────────

/// The phone the scenarios are measured at.
const Size _phone = Size(390, 844);

/// The ring's own side on [_phone]: `TimerRing.size` (232) is narrower than the
/// screen minus the ring's 64 dp horizontal inset, so 232 wins.
const double _ringSide = 232;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Future<Exercise> _getExerciseById(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

typedef _Deps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps({String? modality}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
  );
}

Widget _buildSessionScreen(_Deps deps) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

/// Mounts the session screen at [_phone] and lands on [exerciseName]'s detail.
Future<void> _pumpDetail(
  WidgetTester tester,
  _Deps deps,
  String exerciseName,
) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_buildSessionScreen(deps));
  await _openDetailView(tester, exerciseName);
}

/// Seeds the timed/drill instance of one entry with an elapsed time behind it,
/// then re-reads it into the state the way a restored session does, so the
/// screen renders the seeded elapsed.
Future<void> _seedInstance(
  _Deps deps,
  String effortId, {
  required TimedState state,
  int elapsedMs = 0,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final existing = (await deps.repo.getTimedInstances(
    effortId,
  )).firstWhere((instance) => instance.entryIndex == 0);
  await deps.repo.updateTimedInstance(
    TimedInstance(
      id: existing.id,
      effortId: effortId,
      entryIndex: 0,
      targetDurationSecs: existing.targetDurationSecs,
      startedAtMs: now - elapsedMs,
      state: state,
      pausedAtMs: state == TimedState.paused ? now : null,
      actualDurationSecs: 0,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

/// A live cardio interval on `exercise-easy-run`.
Future<({_Deps deps, String effortId})> _timedSetup({int entries = 1}) async {
  final deps = await _buildDeps(modality: 'cardio_endurance');
  final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'timed',
  );
  for (var i = 1; i < entries; i++) {
    await deps.workoutState.addEntry(effortId);
  }
  return (deps: deps, effortId: effortId);
}

/// A live isometric hold on `exercise-plank-hold`.
Future<({_Deps deps, String effortId})> _drillSetup() async {
  final deps = await _buildDeps(modality: 'isometric_stretching');
  final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'drill',
  );
  return (deps: deps, effortId: effortId);
}

/// Adds the catalog's round-capable exercise with [periods] periods of
/// [durationSecs] each and returns the name to tap.
Future<({String effortId, String name})> _sportsSetup(
  _Deps deps, {
  int periods = 1,
  int durationSecs = 180,
}) async {
  final exercises = await deps.repo.getExercises();
  final exercise = exercises.firstWhere(
    (e) => e.capabilities.contains('rounds'),
  );
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'round',
  );
  for (var i = 1; i < periods; i++) {
    await deps.workoutState.addEntry(effortId);
  }
  for (var i = 0; i < periods; i++) {
    await deps.workoutState.updateRoundPlannedDuration(
      effortId,
      i,
      durationSecs,
    );
  }
  return (effortId: effortId, name: exercise.name);
}

// ── Finders ─────────────────────────────────────────────────────────────────

const Key _countUpKey = Key('count-up-digits');
const Key _ringDigitsKey = Key('ring-digits');

/// The digits `Text` inside one editor (the first descendant `Text`).
Text _valueText(WidgetTester tester, Key editorKey) => tester.widget<Text>(
  find.descendant(of: find.byKey(editorKey), matching: find.byType(Text)).first,
);

InlineMetricEditor _editor(WidgetTester tester, Key editorKey) =>
    tester.widget<InlineMetricEditor>(find.byKey(editorKey));

/// The `FittedBox` directly above one editor.
FittedBox _fittedBoxAbove(WidgetTester tester, Key editorKey) =>
    tester.widget<FittedBox>(
      find
          .ancestor(of: find.byKey(editorKey), matching: find.byType(FittedBox))
          .first,
    );

/// The `SizedBox` the ring wraps its child in — the ring's usable chord.
SizedBox _ringChildBox(WidgetTester tester) => tester.widget<SizedBox>(
  find
      .ancestor(of: find.byKey(_ringDigitsKey), matching: find.byType(SizedBox))
      .first,
);

void main() {
  group('S-4710 hero count-up digits', () {
    testWidgets('the live interval digits are 112 sp inside a scaleDown '
        'FittedBox, captioned ELAPSED', (tester) async {
      final setup = await _timedSetup();
      await _pumpDetail(tester, setup.deps, 'Easy Run');

      expect(
        _editor(tester, _countUpKey).emphasisTier,
        MetricEmphasisTier.hero,
      );
      expect(
        _valueText(tester, _countUpKey).style?.fontSize,
        112.0,
      );
      expect(_valueText(tester, _countUpKey).data, '00:00');
      expect(_fittedBoxAbove(tester, _countUpKey).fit, BoxFit.scaleDown);
      expect(find.text('ELAPSED'), findsOneWidget);
    });

    testWidgets('the live hold digits are 112 sp inside a scaleDown FittedBox, '
        'captioned ELAPSED', (tester) async {
      final setup = await _drillSetup();
      await _pumpDetail(tester, setup.deps, 'Plank Hold');

      expect(
        _editor(tester, _countUpKey).emphasisTier,
        MetricEmphasisTier.hero,
      );
      expect(
        _valueText(tester, _countUpKey).style?.fontSize,
        112.0,
      );
      expect(_valueText(tester, _countUpKey).data, '00:00');
      expect(_fittedBoxAbove(tester, _countUpKey).fit, BoxFit.scaleDown);
      expect(find.text('ELAPSED'), findsOneWidget);
    });

    testWidgets('an interval past an hour reads 1:15:35', (tester) async {
      final setup = await _timedSetup();
      await _seedInstance(
        setup.deps,
        setup.effortId,
        state: TimedState.paused,
        elapsedMs: 4535000,
      );
      await _pumpDetail(tester, setup.deps, 'Easy Run');

      expect(_valueText(tester, _countUpKey).data, '1:15:35');
      expect(_valueText(tester, _countUpKey).style?.fontSize, 112.0);
    });

    testWidgets('the sports ring digits are 48 sp inside the ring chord', (
      tester,
    ) async {
      final deps = await _buildDeps(modality: 'sports');
      final seeded = await _sportsSetup(deps, durationSecs: 8130);
      await _pumpDetail(tester, deps, seeded.name);

      expect(find.byKey(_ringDigitsKey), findsOneWidget);
      expect(
        _valueText(tester, _ringDigitsKey).style?.fontSize,
        48.0,
      );
      expect(_valueText(tester, _ringDigitsKey).data, '2:15:30');
      expect(
        tester.getSize(find.byType(TimerRing)).width,
        _ringSide,
        reason: 'the ring is 232 dp on a 390 dp phone',
      );
      expect(_ringChildBox(tester).width, _ringSide - 40);
    });
  });

  group('S-4711 tightened body', () {
    testWidgets('the set bar cell is 34 dp with captions on a 3-period '
        'sports screen', (tester) async {
      final deps = await _buildDeps(modality: 'sports');
      final seeded = await _sportsSetup(deps, periods: 3);
      await _pumpDetail(tester, deps, seeded.name);

      expect(
        tester.getSize(find.byKey(const Key('set-segment-0'))).height,
        34.0,
      );
    });

    testWidgets('the set bar cell is 18 dp without captions on a 6-period '
        'sports screen', (tester) async {
      final deps = await _buildDeps(modality: 'sports');
      final seeded = await _sportsSetup(deps, periods: 6);
      await _pumpDetail(tester, deps, seeded.name);

      expect(
        tester.getSize(find.byKey(const Key('set-segment-0'))).height,
        18.0,
      );
    });

    testWidgets('the ring starts within 12 dp of the set bar', (tester) async {
      final deps = await _buildDeps(modality: 'sports');
      final seeded = await _sportsSetup(deps, periods: 3);
      await _pumpDetail(tester, deps, seeded.name);

      final barBottom = tester
          .getRect(find.byKey(const Key('set-segment-0')))
          .bottom;
      final ringTop = tester.getRect(find.byType(TimerRing)).top;

      expect(ringTop - barBottom, lessThanOrEqualTo(12));
    });
  });

  group('plan 39 constants', () {
    test('the digit and set bar sizes are pinned at the plan 39 values', () {
      expect(kCountUpDigitsFontSize, 112);
      expect(kRingDigitsFontSize, 48);
      expect(kSetBarCaptionedHeight, 34);
      expect(kSetBarPlainHeight, 18);
    });
  });
}
