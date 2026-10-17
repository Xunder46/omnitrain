// Count-up screens (plan 38c): plain elapsed digits on timed and drill
// entries, and the weight stepper row on holds only.
//
// Covers the core scenarios S-4260..S-4270, the architect's edge scenarios
// S-4273..S-4275 and the interaction-containment scenarios S-4276..S-4279 of
// `docs/plans/2026-10-15-38c-count-up-plan/2026-10-15-38c-count-up-plan.md`.
//
// The elapsed digits are wall clock (`TimedInstance.elapsedMs`), and
// `tester.pump` moves only the fake clock, so a pump can never make them grow.
// The flow assertions here therefore read the centre-button label and the
// absence of the removed chrome, and every non-zero digit assertion reads an
// elapsed time seeded into the repository (S-4273/S-4275), which the restore
// path renders unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/core/utils/metric_stepping.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/set_count_stepper.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/set_captions.dart';

// ── Shared helpers (copied from test/logger_shell_screen_test.dart) ──────────

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

Future<_Deps> _buildDeps({
  String? modality,
  String? weightUnit,
  MockWorkoutRepository? repo,
}) async {
  final resolvedRepo = repo ?? await _freshRepo();
  final workoutState = WorkoutState(resolvedRepo);
  final routineState = RoutineState(resolvedRepo);
  final sessionSummaryService = SessionSummaryService(resolvedRepo);
  final settingsState = SettingsState(resolvedRepo, fakePreferencesService());
  await settingsState.initialize();
  if (weightUnit != null) {
    await settingsState.setPreferredWeightUnit(weightUnit);
  }
  await workoutState.createNewSession(modality: modality);
  return (
    repo: resolvedRepo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
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

/// Navigate from list view to the detail view by tapping the exercise name.
Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

/// A repository that counts the observation writes the screen makes, so a hold
/// can be shown to store its value once.
class _CountingRepository extends MockWorkoutRepository {
  int updates = 0;

  @override
  Future<void> updateObservation(EffortObservation observation) async {
    updates += 1;
    await super.updateObservation(observation);
  }
}

// ── Readers ─────────────────────────────────────────────────────────────────

Finder _editorOf(String metricType) => find.byWidgetPredicate(
  (widget) => widget is InlineMetricEditor && widget.metricType == metricType,
);

InlineMetricEditor _editor(WidgetTester tester, String metricType) =>
    tester.widget<InlineMetricEditor>(_editorOf(metricType));

/// The digits the duration editor draws (`MM:SS`).
String _digits(WidgetTester tester) {
  final text = tester.widget<Text>(
    find
        .descendant(of: _editorOf('duration'), matching: find.byType(Text))
        .first,
  );
  return text.data!;
}

/// The number the weight row draws.
String _weightNumber(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(of: _editorOf('weight'), matching: find.byType(Text)).first,
  );
  return text.data!;
}

Finder get _plusWeight => find.byKey(const Key('value-stepper-plus-weight'));

Finder get _minusWeight => find.byKey(const Key('value-stepper-minus-weight'));

Finder _weightRow() => find.byType(ValueStepperRow);

/// The `extra-weight` observation the repository holds for one entry, in
/// canonical kg, or null when the entry carries no such row.
Future<double?> _storedExtraWeight(
  MockWorkoutRepository repo,
  String effortId, {
  int entryIndex = 0,
}) async {
  final wanted = LoggedEntryRows.observationId(
    effortId,
    entryIndex,
    'extra-weight',
  );
  final observations = await repo.getEffortObservations(effortId);
  for (final observation in observations) {
    if (observation.id == wanted) return observation.valueReal;
  }
  return null;
}

/// Seeds the timed/drill instance of one entry with an elapsed time behind it,
/// then re-reads it into the state the way a restored session does, so the
/// screen renders the seeded elapsed.
Future<void> _seedInstance(
  _Deps deps,
  String effortId, {
  required TimedState state,
  int elapsedMs = 0,
  int entryIndex = 0,
  int actualDurationSecs = 0,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final existing = (await deps.repo.getTimedInstances(
    effortId,
  )).firstWhere((instance) => instance.entryIndex == entryIndex);
  await deps.repo.updateTimedInstance(
    TimedInstance(
      id: existing.id,
      effortId: effortId,
      entryIndex: entryIndex,
      targetDurationSecs: existing.targetDurationSecs,
      startedAtMs: now - elapsedMs,
      state: state,
      pausedAtMs: state == TimedState.paused ? now : null,
      actualDurationSecs: actualDurationSecs,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

/// Ticks a press-and-hold fires [elapsedMs] after the pointer went down,
/// derived from the row's own schedule so the count cannot drift from it.
int _ticksBy(int elapsedMs) {
  var ticks = 1;
  var at = 500; // Flutter's long-press deadline.
  while (at + ValueStepperRow.repeatInterval(ticks).inMilliseconds <=
      elapsedMs) {
    at += ValueStepperRow.repeatInterval(ticks).inMilliseconds;
    ticks += 1;
  }
  return ticks;
}

// ── Timed intervals (S-4260..S-4263) ────────────────────────────────────────

/// Sets up a live (or editor) timed screen on `exercise-easy-run`.
Future<({_Deps deps, String effortId})> _timedScreenSetup({
  MockWorkoutRepository? repo,
  bool editMode = false,
  double? extraWeightKg,
  int entries = 1,
  String exerciseId = 'exercise-easy-run',
}) async {
  final deps = await _buildDeps(modality: 'cardio_endurance', repo: repo);
  final exercise = await _getExerciseById(deps.repo, exerciseId);
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'timed',
  );
  for (var i = 1; i < entries; i++) {
    await deps.workoutState.addEntry(effortId);
  }
  if (extraWeightKg != null) {
    await deps.workoutState.updateEntryValue(
      effortId,
      0,
      'extra-weight',
      extraWeightKg,
    );
  }
  return (deps: deps, effortId: effortId);
}

/// Every trace of the removed status row and weight section, plus the
/// restored caption: an unfinished live screen carries `ELAPSED`, never
/// `COMPLETED` (Q-1, owner O-13).
void _expectNoTimedChrome(WidgetTester tester) {
  expect(find.text('STOPPED'), findsNothing);
  expect(find.text('ELAPSED'), findsOneWidget);
  expect(find.text('COMPLETED'), findsNothing);
  expect(find.text('RUNNING'), findsNothing);
  expect(find.text('PAUSED'), findsNothing);
  expect(find.byIcon(Icons.play_circle_outline), findsNothing);
  expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
  expect(find.text('Weight adjustment'), findsNothing);
  expect(_editorOf('extra-weight'), findsNothing);
  expect(_weightRow(), findsNothing);
}

// ── Layout guard (S-4271) ───────────────────────────────────────────────────

/// The short-phone surface the layout guard measures on.
const Size _guardSurface = Size(390, 844);

/// A hold with two holds, the first one logged, so the sets stepper is up on
/// the same column as the digits and the weight row.
Future<({_Deps deps, String effortId})> _holdGuardSetup({
  bool restOpen = true,
}) async {
  final deps = await _buildDeps(modality: 'isometric_stretching');
  final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
  final effortId = await deps.workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'drill',
  );
  await deps.workoutState.addEntry(effortId);
  await deps.workoutState.addEntry(effortId);
  await deps.workoutState.setTimedEntryDuration(effortId, 0, 30);
  if (restOpen) {
    await deps.workoutState.recordRestStart(effortId, 0);
  }
  return (deps: deps, effortId: effortId);
}

/// S-4271: every control of a hold is reachable and stacked in one column.
///
/// Only relations are asserted: the test font is wider than the device font,
/// so the literal positions the fixture was probed at are not pinned.
void _expectHoldControlsReachable(WidgetTester tester) {
  const minusWeight = Key('value-stepper-minus-weight');
  const plusWeight = Key('value-stepper-plus-weight');
  const removeSet = Key('set-count-remove');
  const addSet = Key('set-count-add');

  // 1. Every control answers a tap: nothing is clipped or covered.
  for (final key in [minusWeight, plusWeight, removeSet, addSet]) {
    expect(
      find.byKey(key).hitTestable(),
      findsOneWidget,
      reason: 'S-4271 $key must be on screen and reachable',
    );
  }

  // 2. The weight buttons are full 48 x 48 targets.
  for (final key in [minusWeight, plusWeight]) {
    final size = tester.getSize(find.byKey(key));
    expect(size.width, 48, reason: 'S-4271 $key must be 48 wide');
    expect(size.height, 48, reason: 'S-4271 $key must be 48 tall');
  }

  // 3. The column stacks digits, then the weight row, then the sets stepper.
  final digits = tester.getRect(_editorOf('duration'));
  final weightRow = tester.getRect(_weightRow());
  final setsStepper = tester.getRect(find.byType(SetCountStepper));
  expect(digits.bottom, lessThanOrEqualTo(weightRow.top));
  expect(weightRow.bottom, lessThanOrEqualTo(setsStepper.top));
}

/// The sets stepper sits clear of the docked rest strip.
void _expectStepperAboveRestChip(WidgetTester tester) {
  expect(
    tester.getRect(find.byKey(const Key('set-count-add'))).bottom,
    lessThanOrEqualTo(
      tester.getRect(find.byKey(const Key('rest-overlay-chip'))).top,
    ),
    reason: 'S-4271 the sets stepper must sit clear of the rest strip',
  );
}

void main() {
  group('Count-up — timed intervals (S-4260..S-4263)', () {
    testWidgets('S-4260: an interval with no load shows digits and no chrome', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup();

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      expect(_digits(tester), '00:00');
      _expectNoTimedChrome(tester);
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    testWidgets('S-4260: a stored extra weight changes nothing on an '
        'interval', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup(extraWeightKg: 5.0);

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      expect(_digits(tester), '00:00');
      _expectNoTimedChrome(tester);
      expect(find.text('5.0'), findsNothing);
    });

    testWidgets('S-4260: an exercise that carries load still shows no weight '
        'on an interval (O-11)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup(
        exerciseId: 'exercise-barbell-squat',
        extraWeightKg: 5.0,
      );

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(_digits(tester), '00:00');
      _expectNoTimedChrome(tester);
      expect(find.text('5.0'), findsNothing);
    });

    testWidgets('S-4261: Start leaves the digits plain and the button logs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup(entries: 2);

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(_digits(tester), '00:00');
      expect(find.text('RUNNING'), findsNothing);
      expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Log Interval'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Interval'));
      await tester.pumpAndSettle();

      // The log moves focus to the next unlogged interval (38a, unchanged).
      expect(find.text('Interval 2 of 2'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous Set'));
      await tester.pumpAndSettle();

      expect(find.text('Interval 1 of 2'), findsOneWidget);
      expect(find.text('LOGGED'), findsOneWidget);
      expect(setCaptionText(tester, 0), '0:00');
    });

    testWidgets('S-4262: the interval editor keeps its duration dialog only', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup(editMode: true, extraWeightKg: 5.0);

      await tester.pumpWidget(_buildSessionScreen(setup.deps, editMode: true));
      await _openDetailView(tester, 'Easy Run');

      expect(_editor(tester, 'duration').isReadOnly, isFalse);
      expect(find.text('Weight adjustment'), findsNothing);
      expect(_editorOf('extra-weight'), findsNothing);
      expect(_weightRow(), findsNothing);

      await tester.tap(find.byType(InlineMetricEditor).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Interval Duration'), findsOneWidget);
    });

    testWidgets('S-4263: logging an interval leaves its data untouched', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup(extraWeightKg: 5.0);

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.widgetWithText(FilledButton, 'Log Interval'));
      await tester.pumpAndSettle();

      expect(find.text('LOGGED'), findsOneWidget);
      expect(
        await _storedExtraWeight(setup.deps.repo, setup.effortId),
        5.0,
        reason: 'D-6: logging never rewrites the entry data',
      );
    });

    testWidgets('S-4277: a live interval\'s digits open nothing on a tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final setup = await _timedScreenSetup();

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      expect(
        _editor(tester, 'duration').isReadOnly,
        isTrue,
        reason: 'the live digits are read-only, so they carry no tap target',
      );

      await tester.tap(_editorOf('duration'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  // ── Holds (S-4264..S-4270) ────────────────────────────────────────────────

  group('Count-up — holds (S-4264..S-4270)', () {
    testWidgets('S-4264: a hold shows digits plus one weight row', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_digits(tester), '00:00');
      expect(find.text('STOPPED'), findsNothing);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('COMPLETED'), findsNothing);
      expect(find.text('Weight adjustment'), findsNothing);
      expect(_editorOf('extra-weight'), findsNothing);
      expect(_weightRow(), findsOneWidget);
      expect(_plusWeight, findsOneWidget);
      expect(_minusWeight, findsOneWidget);
      expect(_weightNumber(tester), '0.0');
      expect(find.text('KG'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    testWidgets('S-4265: the hold weight steps 2.5 kg at a time', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();
      expect(_weightNumber(tester), '2.5');
      expect(await _storedExtraWeight(deps.repo, effortId), 2.5);

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();
      expect(_weightNumber(tester), '5.0');
      expect(await _storedExtraWeight(deps.repo, effortId), 5.0);

      await tester.tap(_minusWeight);
      await tester.pumpAndSettle();
      expect(_weightNumber(tester), '2.5');
      expect(await _storedExtraWeight(deps.repo, effortId), 2.5);
    });

    testWidgets('S-4265: a pounds preference steps 5 lb and stores kg', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(
        modality: 'isometric_stretching',
        weightUnit: 'lbs',
      );
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.text('LBS'), findsOneWidget);

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();

      expect(_weightNumber(tester), '5.0');
      expect(
        await _storedExtraWeight(deps.repo, effortId),
        closeTo(UnitFormatter.toCanonicalWeight(5.0, deps.settingsState), 1e-9),
      );
    });

    testWidgets('S-4266: a weight step does not stop a running hold', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget);

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();

      expect(
        deps.workoutState.getTimedInstancesForEffort(effortId)[0].state,
        TimedState.active,
        reason: 'the reload must not pause the instance',
      );
      expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsNothing);
      expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);
      expect(await _storedExtraWeight(deps.repo, effortId), 2.5);
    });

    testWidgets('S-4267: a logged hold locks both weight buttons', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(FilledButton, 'Log Hold'));
      await tester.pumpAndSettle();

      expect(find.text('LOGGED'), findsOneWidget);
      expect(_editor(tester, 'weight').isReadOnly, isTrue);

      await tester.tap(_plusWeight, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_weightNumber(tester), '0.0');
      expect(await _storedExtraWeight(deps.repo, effortId), 0.0);

      await tester.tap(_editorOf('weight'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('S-4267: a logged hold stays editable in the editor', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.setTimedEntryDuration(effortId, 0, 30);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();
      expect(_weightNumber(tester), '2.5');
      expect(
        await _storedExtraWeight(deps.repo, effortId),
        0.0,
        reason: 'edit mode buffers the change until Save',
      );

      await tester.tap(_editorOf('weight'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Weight'), findsOneWidget);
    });

    testWidgets('S-4268: the hold weight number opens Edit Weight', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(_editorOf('weight'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Weight'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12.5');
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Weight'), findsNothing);
      expect(_weightNumber(tester), '12.5');
      expect(await _storedExtraWeight(deps.repo, effortId), 12.5);
    });

    testWidgets('S-4269: a stored 10.0 reads as 10.0, with no sign', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.updateEntryValue(
        effortId,
        0,
        'extra-weight',
        10.0,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_weightNumber(tester), '10.0');
      expect(find.text('+10.0'), findsNothing);
      expect(find.text('Weight adjustment'), findsNothing);
      expect(_editorOf('extra-weight'), findsNothing);
    });

    testWidgets('S-4269: a stored -10.0 reads as -10.0 and plus gives -7.5', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.updateEntryValue(
        effortId,
        0,
        'extra-weight',
        -10.0,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_weightNumber(tester), '-10.0');

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();

      expect(_weightNumber(tester), '-7.5');
      expect(await _storedExtraWeight(deps.repo, effortId), -7.5);
    });

    testWidgets('S-4270: a long press survives the one-second rebuilds', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final counted = _CountingRepository();
      await counted.initialize();
      await counted.setPreferenceBool('hint_seen_exercise_info', true);
      await counted.setPreferenceBool('hint_seen_exercise_notes', true);
      final deps = await _buildDeps(
        modality: 'isometric_stretching',
        repo: counted,
      );
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();
      counted.updates = 0;

      const holdMs = 2000;
      final expected = _ticksBy(holdMs) * MetricStepping.kilogramsPerStep;

      final hold = await tester.startGesture(tester.getCenter(_plusWeight));
      for (var slice = 0; slice < holdMs ~/ 100; slice++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        _weightNumber(tester),
        expected.toStringAsFixed(1),
        reason: 'the stepped number is not dropped by the rebuilds',
      );
      expect(
        counted.updates,
        0,
        reason: 'nothing is stored while the finger is down',
      );

      await hold.up();
      await tester.pumpAndSettle();

      expect(counted.updates, 1, reason: 'the lift stores the value once');
      expect(await _storedExtraWeight(deps.repo, effortId), expected);
    });

    testWidgets('S-4276: a hold dies with its set when the arrows move focus', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.text('Hold 1 of 2'), findsOneWidget);
      expect(_weightNumber(tester), '0.0');

      final hold = await tester.startGesture(tester.getCenter(_plusWeight));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // A second pointer moves focus to hold 2 while the first one is held.
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Hold 2 of 2'), findsOneWidget);

      await hold.up();
      await tester.pumpAndSettle();

      // The row key carries the set, so hold 1's row and its hold are gone:
      // the lift cannot commit the stepped number (up to the 999 kg clamp)
      // into the set under the finger.
      expect(_weightNumber(tester), '0.0');
      expect(await _storedExtraWeight(deps.repo, effortId), 0.0);
      expect(await _storedExtraWeight(deps.repo, effortId, entryIndex: 1), 0.0);
    });

    testWidgets('S-4278: a live hold\'s digits open nothing on a tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(
        _editor(tester, 'duration').isReadOnly,
        isTrue,
        reason: 'the live digits are read-only, so they carry no tap target',
      );

      await tester.tap(_editorOf('duration'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('S-4279: the hold editor keeps its duration dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.setTimedEntryDuration(effortId, 0, 30);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, 'Plank Hold');

      expect(_editor(tester, 'duration').isReadOnly, isFalse);

      await tester.tap(
        find
            .descendant(of: _editorOf('duration'), matching: find.byType(Text))
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Hold Duration'), findsOneWidget);
    });
  });

  // ── Restored paused entries (S-4273/S-4274) ───────────────────────────────

  group('Count-up — restored paused entries (S-4273, S-4274)', () {
    testWidgets('S-4273: a paused interval shows its elapsed and Resume', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await _seedInstance(
        deps,
        effortId,
        state: TimedState.paused,
        elapsedMs: 75000,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      expect(_digits(tester), '01:15');
      expect(find.text('STOPPED'), findsNothing);
      expect(find.text('PAUSED'), findsNothing);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('COMPLETED'), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Log Interval'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.widgetWithText(FilledButton, 'Log Interval'), findsOneWidget);
      expect(
        deps.workoutState.getTimedInstancesForEffort(effortId)[0].state,
        TimedState.active,
      );
      expect(_digits(tester), '01:15');
    });

    testWidgets('S-4274: a paused hold keeps its elapsed, weight and Resume', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await deps.workoutState.updateEntryValue(
        effortId,
        0,
        'extra-weight',
        10.0,
      );
      await _seedInstance(
        deps,
        effortId,
        state: TimedState.paused,
        elapsedMs: 75000,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_digits(tester), '01:15');
      expect(find.text('PAUSED'), findsNothing);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('COMPLETED'), findsNothing);
      expect(_weightNumber(tester), '10.0');
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();

      expect(_weightNumber(tester), '12.5');
      expect(await _storedExtraWeight(deps.repo, effortId), 12.5);
      expect(
        deps.workoutState.getTimedInstancesForEffort(effortId)[0].state,
        TimedState.paused,
        reason: 'a paused hold is not logged, so the step must not resume it',
      );
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    });
  });

  // ── Finished captions (S-4402, Q-1/D-8) ───────────────────────────────────

  group('Count-up — a finished entry reads COMPLETED (S-4402)', () {
    testWidgets('S-4402: a finished interval swaps ELAPSED for COMPLETED', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'cardio_endurance');
      final exercise = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'timed',
      );
      await _seedInstance(
        deps,
        effortId,
        state: TimedState.finished,
        elapsedMs: 75000,
        actualDurationSecs: 75,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Easy Run');

      expect(_digits(tester), '01:15');
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('ELAPSED'), findsNothing);
    });

    testWidgets('S-4402: a finished hold swaps ELAPSED for COMPLETED', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      await _seedInstance(
        deps,
        effortId,
        state: TimedState.finished,
        elapsedMs: 75000,
        actualDurationSecs: 75,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_digits(tester), '01:15');
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('ELAPSED'), findsNothing);
    });
  });

  // ── A running hold survives a weight step (S-4275) ────────────────────────

  group('Count-up — a running hold survives a weight step (S-4275)', () {
    testWidgets('S-4275: the reload keeps the elapsed time and the timer', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final exercise = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        effortKindOverride: 'drill',
      );
      // A hold the user paused mid-session carries a non-zero elapsed time,
      // which makes a reset-by-reload visible as `00:00`.
      await _seedInstance(
        deps,
        effortId,
        state: TimedState.paused,
        elapsedMs: 5000,
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(_digits(tester), '00:05');
      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget);

      await tester.tap(_plusWeight);
      await tester.pumpAndSettle();

      expect(
        _digits(tester),
        '00:05',
        reason: 'the reload must not reset the digits to 00:00',
      );
      expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsNothing);
      expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);
      expect(await _storedExtraWeight(deps.repo, effortId), 2.5);
    });
  });

  // ── Layout guard (S-4271) ─────────────────────────────────────────────────

  group('Count-up — layout guard (S-4271)', () {
    testWidgets('S-4271: with the rest strip up the hold\'s controls are '
        'reachable', (tester) async {
      await tester.binding.setSurfaceSize(_guardSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final setup = await _holdGuardSetup();

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

      _expectHoldControlsReachable(tester);
      _expectStepperAboveRestChip(tester);
    });

    testWidgets('S-4271b: without the rest strip the hold\'s controls are '
        'reachable', (tester) async {
      await tester.binding.setSurfaceSize(_guardSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final setup = await _holdGuardSetup(restOpen: false);

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);

      _expectHoldControlsReachable(tester);
    });

    testWidgets('S-4271c: with the rest strip up an interval keeps its '
        'stepper reachable and clear of the strip', (tester) async {
      await tester.binding.setSurfaceSize(_guardSurface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final setup = await _timedScreenSetup(entries: 2);
      await setup.deps.workoutState.setTimedEntryDuration(
        setup.effortId,
        0,
        30,
      );
      await setup.deps.workoutState.recordRestStart(setup.effortId, 0);

      await tester.pumpWidget(_buildSessionScreen(setup.deps));
      await _openDetailView(tester, 'Easy Run');

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      expect(_weightRow(), findsNothing);
      expect(_plusWeight, findsNothing);

      expect(
        find.byKey(const Key('set-count-add')).hitTestable(),
        findsOneWidget,
        reason: 'S-4271c the interval stepper must be on screen and reachable',
      );
      _expectStepperAboveRestChip(tester);
    });
  });
}
