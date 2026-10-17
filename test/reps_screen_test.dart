import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

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
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_Deps> _buildDeps({
  String? modality,
  MockWorkoutRepository? repo,
}) async {
  final resolvedRepo = repo ?? await _freshRepo();
  final workoutState = WorkoutState(resolvedRepo);
  final routineState = RoutineState(resolvedRepo);
  final sessionSummaryService = SessionSummaryService(resolvedRepo);
  final settingsState = SettingsState(resolvedRepo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(modality: modality);
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
  );
}

Widget _buildSessionScreen(
  _Deps deps, {
  bool editMode = false,
  String? initialFocusId,
}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
      editMode: editMode,
      initialFocusId: initialFocusId,
    ),
  );
}

/// Navigate from list view to the detail view by tapping the first exercise name.
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

Finder _segment(int index) => find.byKey(Key('set-segment-$index'));

Finder _plusRow(String metricType) =>
    find.byKey(Key('value-stepper-plus-$metricType'));

Finder _minusRow(String metricType) =>
    find.byKey(Key('value-stepper-minus-$metricType'));

Finder _editorOf(String metricType) => find.byWidgetPredicate(
  (widget) => widget is InlineMetricEditor && widget.metricType == metricType,
);

InlineMetricEditor _editor(WidgetTester tester, String metricType) =>
    tester.widget<InlineMetricEditor>(_editorOf(metricType));

Finder _editorNumber(String metricType, String text) =>
    find.descendant(of: _editorOf(metricType), matching: find.text(text));

List<Map<String, dynamic>> _entriesOf(_Deps deps, String effortId) {
  final exercise = deps.workoutState.getExercisesWithEntries().firstWhere(
    (e) => e['id'] == effortId,
  );
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

// ── Layout guard (S-4255) ───────────────────────────────────────────────────

/// The short-phone surface the layout guard measures on.
const Size _guardSurface = Size(390, 844);

/// S-4255: every control of the reps screen is reachable and stacked in one
/// column.
///
/// Only relations are asserted: the test font is wider than the device font,
/// so the literal positions the fixture was probed at are not pinned.
void _expectRepsControlsReachable(WidgetTester tester) {
  const minusReps = Key('value-stepper-minus-reps');
  const plusReps = Key('value-stepper-plus-reps');
  const minusWeight = Key('value-stepper-minus-weight');
  const plusWeight = Key('value-stepper-plus-weight');
  const removeSet = Key('set-count-remove');
  const addSet = Key('set-count-add');
  const stepButtons = [minusReps, plusReps, minusWeight, plusWeight];

  // 1. Every control answers a tap: nothing is clipped or covered.
  for (final key in [...stepButtons, removeSet, addSet]) {
    expect(
      find.byKey(key).hitTestable(),
      findsOneWidget,
      reason: 'S-4255 $key must be on screen and reachable',
    );
  }
  expect(
    find.widgetWithText(FilledButton, 'Log Set').hitTestable(),
    findsOneWidget,
    reason: 'S-4255 the primary action must be on screen',
  );

  // 2. The rows stack in order: reps, then weight, then the sets stepper.
  final repsPlus = tester.getRect(find.byKey(plusReps));
  final weightPlus = tester.getRect(find.byKey(plusWeight));
  expect(repsPlus.bottom, lessThanOrEqualTo(weightPlus.top));
  expect(
    weightPlus.bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(addSet)).top),
  );

  // 4. The step buttons flank their row: plus at the right edge, minus at the
  // left edge, each at least 48 x 48.
  expect(repsPlus.right, lessThanOrEqualTo(_guardSurface.width - 16 + 0.5));
  expect(
    tester.getRect(find.byKey(minusReps)).left,
    greaterThanOrEqualTo(16 - 0.5),
  );
  for (final key in stepButtons) {
    final size = tester.getSize(find.byKey(key));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }
}

void main() {
  group('Reps screen — stepper rows — resistance (S-4250..S-4256)', () {
    testWidgets('S-4250: the two rows step reps and weight and store both', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(_plusRow('reps'), findsOneWidget);
      expect(_plusRow('weight'), findsOneWidget);
      expect(_editorNumber('reps', '10'), findsOneWidget);

      await tester.tap(_plusRow('reps'));
      await tester.pumpAndSettle();

      expect(_editorNumber('reps', '11'), findsOneWidget);
      expect(_entriesOf(deps, effortId)[0]['reps'], 11);

      await tester.tap(_plusRow('weight'));
      await tester.pumpAndSettle();

      expect(_editorNumber('weight', '62.5'), findsOneWidget);
      expect(_entriesOf(deps, effortId)[0]['weight'], 62.5);
    });

    testWidgets('S-4251: with pounds saved the weight row steps 5 lb', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      await deps.settingsState.setPreferredWeightUnit('lbs');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 5);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 100.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(_editorNumber('weight', '220.5'), findsOneWidget);

      await tester.tap(_plusRow('weight'));
      await tester.pumpAndSettle();

      expect(_editorNumber('weight', '225.5'), findsOneWidget);
      expect(
        _entriesOf(deps, effortId)[0]['weight'],
        UnitFormatter.toCanonicalWeight(225.5, deps.settingsState),
        reason: 'the row hands pounds to the screen, which stores kilograms',
      );
    });

    testWidgets(
      'S-4252: live, a logged set is locked and an unlogged one steps',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // Set 1 is logged, so the screen focuses set 2: go back to it.
        await tester.tap(_segment(0));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_editor(tester, 'reps').isReadOnly, isTrue);
        expect(_editor(tester, 'weight').isReadOnly, isTrue);

        await tester.tap(_plusRow('reps'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(_minusRow('reps'), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(_plusRow('weight'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(_editorNumber('reps', '10'), findsOneWidget);
        expect(_editorNumber('weight', '60.0'), findsOneWidget);
        final locked = _entriesOf(deps, effortId);
        expect(locked[0]['reps'], 10);
        expect(locked[0]['weight'], 60.0);

        // The same rows on the unlogged set 2 still step and store.
        await tester.tap(_segment(1));
        await tester.pumpAndSettle();
        expect(_editor(tester, 'reps').isReadOnly, isFalse);

        await tester.tap(_plusRow('reps'));
        await tester.pumpAndSettle();

        expect(_entriesOf(deps, effortId)[1]['reps'], 9);
      },
    );

    testWidgets('S-4252: edit mode steps a logged set without storing it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(_segment(0));
      await tester.pumpAndSettle();
      expect(_editor(tester, 'reps').isReadOnly, isFalse);

      await tester.tap(_plusRow('reps'));
      await tester.pumpAndSettle();

      expect(_editorNumber('reps', '11'), findsOneWidget);
      expect(
        _entriesOf(deps, effortId)[0]['reps'],
        10,
        reason: 'edit mode buffers the change until Save',
      );
    });

    testWidgets('S-4253: holding plus stores the stepped value once, on lift', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final counted = _CountingRepository();
      await counted.initialize();
      await counted.setPreferenceBool('hint_seen_exercise_info', true);
      await counted.setPreferenceBool('hint_seen_exercise_notes', true);
      final deps = await _buildDeps(
        modality: 'resistance_lifting',
        repo: counted,
      );
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      counted.updates = 0;

      final hold = await tester.startGesture(
        tester.getCenter(_plusRow('reps')),
      );
      // Flutter's long-press deadline is 500 ms: tick 1 lands there, then one
      // tick every 200 ms, so 5 more pumps read 16 (10 + 6 ticks).
      await tester.pump(const Duration(milliseconds: 500));
      for (var tick = 0; tick < 5; tick++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        _editorNumber('reps', '16'),
        findsOneWidget,
        reason: 'the number follows the hold',
      );
      expect(
        counted.updates,
        0,
        reason: 'nothing is stored while the finger is down',
      );

      await hold.up();
      await tester.pumpAndSettle();

      expect(counted.updates, 1, reason: 'the lift stores the value once');
      expect(_entriesOf(deps, effortId)[0]['reps'], 16);
    });

    testWidgets('S-4254: tapping the weight number still opens Edit Weight', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(_editorNumber('weight', '60.0'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Weight'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '70');
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Weight'), findsNothing);
      expect(_editorNumber('weight', '70.0'), findsOneWidget);
      expect(_entriesOf(deps, effortId)[0]['weight'], 70.0);
    });

    testWidgets('S-4256: Log Set logs the stepped value and starts rest', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(_plusRow('reps'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(setCaptionText(tester, 0), '11×60');
      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      expect(deps.workoutState.getEntryRests(effortId), isNotEmpty);
    });

    testWidgets('S-4257: a hold dies with its set when the arrows move focus', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.text('Set 1 of 2'), findsOneWidget);

      final hold = await tester.startGesture(
        tester.getCenter(_plusRow('reps')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _editorNumber('reps', '12'),
        findsOneWidget,
        reason: 'the hold is stepping set 1',
      );

      // A second pointer moves focus to set 2 while the first one is held.
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 2'), findsOneWidget);

      await hold.up();
      await tester.pumpAndSettle();

      final stored = _entriesOf(deps, effortId);
      expect(
        stored[0]['reps'],
        10,
        reason: 'the hold dies with the row that owned it',
      );
      expect(
        stored[1]['reps'],
        8,
        reason: 'the set under the finger is untouched',
      );
      expect(_editorNumber('reps', '8'), findsOneWidget);
    });

    testWidgets(
      'S-4257b: a weight hold dies with its set when the arrows move focus',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 40.0);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.text('Set 1 of 2'), findsOneWidget);

        final hold = await tester.startGesture(
          tester.getCenter(_plusRow('weight')),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          _editorNumber('weight', '65.0'),
          findsOneWidget,
          reason: 'the hold is stepping set 1: 62.5 then 65.0',
        );

        // A second pointer moves focus to set 2 while the first one is held.
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 2'), findsOneWidget);

        await hold.up();
        await tester.pumpAndSettle();

        final stored = _entriesOf(deps, effortId);
        expect(
          stored[0]['weight'],
          60.0,
          reason: 'the hold dies with the row that owned it',
        );
        expect(
          stored[1]['weight'],
          40.0,
          reason: 'the set under the finger is untouched',
        );
        expect(_editorNumber('weight', '40.0'), findsOneWidget);
      },
    );

    testWidgets(
      'S-4255: with the rest strip up every control of the reps screen is '
      'on screen',
      (tester) async {
        await tester.binding.setSurfaceSize(_guardSurface);
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 100.0);
        // The common state between sets: the rest strip is up while the next
        // set waits.
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        _expectRepsControlsReachable(tester);

        // 3. Nothing hides behind the strip.
        expect(
          tester.getRect(find.byKey(const Key('set-count-add'))).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const Key('rest-overlay-chip'))).top,
          ),
          reason: 'S-4255 the sets stepper must sit clear of the rest strip',
        );
      },
    );

    testWidgets(
      'S-4255b: without the rest strip every control of the reps screen is '
      'on screen',
      (tester) async {
        await tester.binding.setSurfaceSize(_guardSurface);
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 100.0);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);

        _expectRepsControlsReachable(tester);
      },
    );
  });
}
