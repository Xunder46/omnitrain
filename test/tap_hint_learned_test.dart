// Plan 44 / T3a — the tap-to-type hint is learned per control (S-5120..S-5125).
//
// A hint goes when its own control's number is tapped, never when a stepper
// button is used, and the learned flag survives a restart identically on the
// Mock and Hive stores. Locked rows and the routine editor keep the hint.
//
// The helpers below are copied from test/delete_focused_set_test.dart, with
// only the imports they need and a `repo` field on the dependency record.
//
// Plan: `docs/plans/2026-10-19-44-logger-feedback-round-plan/2026-10-19-44-logger-feedback-round-plan.md`
// (D-6, D-12, D-13).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

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
    repo: resolvedRepo,
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

Finder _editorOf(String metricType) => find.byWidgetPredicate(
  (widget) => widget is InlineMetricEditor && widget.metricType == metricType,
);

Finder _editorNumber(String metricType, String text) =>
    find.descendant(of: _editorOf(metricType), matching: find.text(text));

List<Map<String, dynamic>> _entriesOf(_Deps deps, String effortId) {
  final exercise = deps.workoutState.getExercisesWithEntries().firstWhere(
    (e) => e['id'] == effortId,
  );
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

// ── Shared readers ──────────────────────────────────────────────────────────

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Finder _hintIn(Finder row) =>
    find.descendant(of: row, matching: find.byKey(const Key('tap-hint')));

Finder _hint() => find.byKey(const Key('tap-hint'));

Future<void> _dismissDialog(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

/// Seeds the timed/drill instance of entry 0 as finished, the way
/// `test/count_up_screen_test.dart` seeds an editor fixture.
Future<void> _seedFinishedInstance(
  _Deps deps,
  String effortId,
  int seconds,
) async {
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
      startedAtMs: now - seconds * 1000,
      state: TimedState.finished,
      actualDurationSecs: seconds,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    ),
  );
  await deps.workoutState.refreshEfforts([effortId]);
}

void main() {
  group('S-5120: a hint goes when its own control is tapped', () {
    testWidgets('the weight hint goes, the reps hint stays, and the flag '
        'persists', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-barbell-squat',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);

      expect(_entriesOf(deps, effortId).length, 2);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      expect(_editorNumber('reps', '10'), findsOneWidget);
      expect(_hint(), findsNWidgets(2), reason: 'reps and weight rows');

      await tester.tap(_editorNumber('weight', '0.0'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Weight'), findsOneWidget);
      await _dismissDialog(tester);

      final repsRow = find.byKey(ValueKey('$effortId-0-reps'));
      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(_hintIn(repsRow), findsOneWidget);
      expect(_hintIn(weightRow), findsNothing);
      expect(_hint(), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();

      final repsRow2 = find.byKey(ValueKey('$effortId-1-reps'));
      final weightRow2 = find.byKey(ValueKey('$effortId-1-weight'));
      expect(_hintIn(repsRow2), findsOneWidget);
      expect(_hintIn(weightRow2), findsNothing);
      expect(_hint(), findsOneWidget);

      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.weight),
        isTrue,
      );
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
      expect(
        await deps.repo.getPreferenceBool('hint_seen_tap_to_type_weight'),
        isTrue,
      );
    });

    testWidgets('S-5120b the reps number teaches reps only, and a learned '
        'reps flag hides the reps hint at open', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-barbell-squat',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      expect(_hint(), findsNWidgets(2), reason: 'reps and weight rows');

      await tester.tap(_editorNumber('reps', '10'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Reps'), findsOneWidget);
      await _dismissDialog(tester);

      final repsRow = find.byKey(ValueKey('$effortId-0-reps'));
      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(_hintIn(repsRow), findsNothing);
      expect(_hintIn(weightRow), findsOneWidget);
      expect(_hint(), findsOneWidget);
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isTrue);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.weight),
        isFalse,
      );

      await deps.settingsState.markTapHintLearned(TapHintControl.reps);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      expect(
        _hintIn(find.byKey(ValueKey('$effortId-0-reps'))),
        findsNothing,
      );
      expect(
        _hintIn(find.byKey(ValueKey('$effortId-0-weight'))),
        findsOneWidget,
      );
    });
  });

  group('S-5121: steppers do not teach', () {
    testWidgets('three plus taps and a one-second hold leave the reps hint', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-barbell-squat',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      final plusReps = find.byKey(const Key('value-stepper-plus-reps'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(plusReps);
        await tester.pumpAndSettle();
      }
      final gesture = await tester.startGesture(tester.getCenter(plusReps));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();

      final repsRow = find.byKey(ValueKey('$effortId-0-reps'));
      expect(_hintIn(repsRow), findsOneWidget);
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
    });
  });

  group('S-5122: remembered after a restart, identical on both stores', () {
    final results = <String, List<bool>>{};

    for (final factory in harnessFactories) {
      final harness = factory();

      test('${harness.name}: weight and round length stay learned', () async {
        addTearDown(harness.close);
        final repo = await harness.open();
        final state = SettingsState(repo, fakePreferencesService());
        await state.initialize();
        await state.markTapHintLearned(TapHintControl.weight);
        await state.markTapHintLearned(TapHintControl.roundLength);

        final restarted = await harness.restart();
        final fresh = SettingsState(restarted, fakePreferencesService());
        await fresh.initialize();

        final flags = [
          fresh.isTapHintLearned(TapHintControl.weight),
          fresh.isTapHintLearned(TapHintControl.roundLength),
          fresh.isTapHintLearned(TapHintControl.reps),
          fresh.isTapHintLearned(TapHintControl.elapsed),
        ];
        results[harness.name] = flags;

        expect(flags, [true, true, false, false]);
        expect(
          await restarted.getPreferenceBool('hint_seen_tap_to_type_weight'),
          isTrue,
        );
        expect(
          await restarted.getPreferenceBool(
            'hint_seen_tap_to_type_round_length',
          ),
          isTrue,
        );
      });
    }

    test('Mock and Hive agree', () {
      expect(results['Mock'], isNotNull);
      expect(results['Hive'], results['Mock']);
    });

    testWidgets('a restarted Mock repo hides the weight hint and keeps reps', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final harness = MockRepositoryHarness();
      addTearDown(harness.close);
      final repo = await harness.open();
      final state = SettingsState(repo, fakePreferencesService());
      await state.initialize();
      await state.markTapHintLearned(TapHintControl.weight);
      await state.markTapHintLearned(TapHintControl.roundLength);

      final restarted = await harness.restart();
      final deps = await _buildDeps(repo: restarted as MockWorkoutRepository);
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-barbell-squat',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      final repsRow = find.byKey(ValueKey('$effortId-0-reps'));
      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(_hintIn(repsRow), findsOneWidget);
      expect(_hintIn(weightRow), findsNothing);
    });
  });

  group('S-5123: one weight control, one round-length control', () {
    testWidgets('weight learned hides every weight hint; the round length '
        'teaches on its own tap', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      await deps.settingsState.markTapHintLearned(TapHintControl.weight);

      final plank = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final plankId = await deps.workoutState.addExerciseToSession(
        plank,
        effortKindOverride: 'drill',
      );
      final run = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final runId = await deps.workoutState.addExerciseToSession(
        run,
        effortKindOverride: 'timed',
      );
      final exercises = await deps.repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      final roundId = await deps.workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );
      expect(plankId, isNotEmpty);
      expect(runId, isNotEmpty);
      expect(roundId, isNotEmpty);

      await tester.pumpWidget(_buildSessionScreen(deps));

      await _openDetailView(tester, plank.name);
      expect(_hintIn(find.byKey(ValueKey('$plankId-0-weight'))), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await _openDetailView(tester, run.name);
      expect(_hintIn(find.byKey(ValueKey('$runId-0-weight'))), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await _openDetailView(tester, roundExercise.name);
      final roundRow = find.byKey(ValueKey('$roundId-0-round-length'));
      expect(_hintIn(roundRow), findsOneWidget);

      final row = tester.widget<ValueStepperRow>(roundRow);
      final lengthText = OmniDateUtils.formatTimerDigits(
        (row.currentValue as int),
      );
      await tester.tap(
        find.descendant(of: roundRow, matching: find.text(lengthText)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Round Duration'), findsOneWidget);
      await _dismissDialog(tester);

      expect(_hintIn(roundRow), findsNothing);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.roundLength),
        isTrue,
      );
    });

    testWidgets('the session editor round-length row shows no hint once '
        'learned', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      await deps.settingsState.markTapHintLearned(TapHintControl.roundLength);
      final exercises = await deps.repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      final roundId = await deps.workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, roundExercise.name);

      expect(
        _hintIn(find.byKey(ValueKey('$roundId-0-round-length'))),
        findsNothing,
      );
    });

    testWidgets('S-5123b tapping the hold load row teaches weight', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final plank = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final plankId = await deps.workoutState.addExerciseToSession(
        plank,
        effortKindOverride: 'drill',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, plank.name);

      final weightRow = find.byKey(ValueKey('$plankId-0-weight'));
      expect(_hintIn(weightRow), findsOneWidget);

      await tester.tap(_editorNumber('weight', '0.0'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Weight'), findsOneWidget);
      await _dismissDialog(tester);

      expect(_hintIn(weightRow), findsNothing);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.weight),
        isTrue,
      );
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.roundLength),
        isFalse,
      );
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.elapsed),
        isFalse,
      );
    });

    testWidgets('S-5123b tapping the interval load row teaches weight', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final run = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final runId = await deps.workoutState.addExerciseToSession(
        run,
        effortKindOverride: 'timed',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, run.name);

      final weightRow = find.byKey(ValueKey('$runId-0-weight'));
      expect(_hintIn(weightRow), findsOneWidget);

      await tester.tap(_editorNumber('weight', '0.0'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Weight'), findsOneWidget);
      await _dismissDialog(tester);

      expect(_hintIn(weightRow), findsNothing);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.weight),
        isTrue,
      );
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.roundLength),
        isFalse,
      );
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.elapsed),
        isFalse,
      );
    });

    testWidgets('S-5123c the session editor round-length number teaches '
        'roundLength', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final exercises = await deps.repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      final roundId = await deps.workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, roundExercise.name);

      final roundRow = find.byKey(ValueKey('$roundId-0-round-length'));
      expect(_hintIn(roundRow), findsOneWidget);

      final row = tester.widget<ValueStepperRow>(roundRow);
      final lengthText = OmniDateUtils.formatTimerDigits(
        (row.currentValue as int),
      );
      await tester.tap(
        find.descendant(of: roundRow, matching: find.text(lengthText)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Round Duration'), findsOneWidget);
      await _dismissDialog(tester);

      expect(_hintIn(roundRow), findsNothing);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.roundLength),
        isTrue,
      );
      expect(deps.settingsState.isTapHintLearned(TapHintControl.weight), isFalse);
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.elapsed),
        isFalse,
      );
    });
  });

  group('S-5124: the session editor elapsed editor', () {
    testWidgets('tapping the interval elapsed hides both elapsed hints', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final run = await _getExerciseById(deps.repo, 'exercise-easy-run');
      final runId = await deps.workoutState.addExerciseToSession(
        run,
        effortKindOverride: 'timed',
      );
      await _seedFinishedInstance(deps, runId, 95);

      final plank = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final plankId = await deps.workoutState.addExerciseToSession(
        plank,
        effortKindOverride: 'drill',
      );
      await _seedFinishedInstance(deps, plankId, 30);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));

      await _openDetailView(tester, run.name);
      expect(
        find.descendant(of: _editorOf('duration'), matching: _hint()),
        findsOneWidget,
      );
      expect(_editorNumber('duration', '01:35'), findsOneWidget);

      await tester.tap(_editorNumber('duration', '01:35'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Interval Duration'), findsOneWidget);
      await _dismissDialog(tester);

      expect(
        find.descendant(of: _editorOf('duration'), matching: _hint()),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await _openDetailView(tester, plank.name);

      expect(
        find.descendant(of: _editorOf('duration'), matching: _hint()),
        findsNothing,
      );
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.elapsed),
        isTrue,
      );
    });

    testWidgets('S-5124b the hold elapsed editor teaches elapsed', (
      tester,
    ) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final plank = await _getExerciseById(deps.repo, 'exercise-plank-hold');
      final plankId = await deps.workoutState.addExerciseToSession(
        plank,
        effortKindOverride: 'drill',
      );
      await _seedFinishedInstance(deps, plankId, 30);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, plank.name);

      expect(
        find.descendant(of: _editorOf('duration'), matching: _hint()),
        findsOneWidget,
      );
      expect(_editorNumber('duration', '00:30'), findsOneWidget);

      await tester.tap(_editorNumber('duration', '00:30'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Hold Duration'), findsOneWidget);
      await _dismissDialog(tester);

      expect(
        find.descendant(of: _editorOf('duration'), matching: _hint()),
        findsNothing,
      );
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.elapsed),
        isTrue,
      );
      expect(deps.settingsState.isTapHintLearned(TapHintControl.weight), isFalse);
      expect(deps.settingsState.isTapHintLearned(TapHintControl.reps), isFalse);
      expect(
        deps.settingsState.isTapHintLearned(TapHintControl.roundLength),
        isFalse,
      );
    });
  });

  group('S-5125: locked rows and the routine editor', () {
    testWidgets('a logged set shows no hint', (tester) async {
      await _usePhoneSurface(tester);
      final deps = await _buildDeps();
      final exercise = await _getExerciseById(
        deps.repo,
        'exercise-barbell-squat',
      );
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, exercise.name);

      expect(find.text('Set 2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous Set'));
      await tester.pumpAndSettle();

      expect(_hint(), findsNothing);
      expect(
        tester.widget<InlineMetricEditor>(_editorOf('reps')).isReadOnly,
        isTrue,
      );
      expect(
        tester.widget<InlineMetricEditor>(_editorOf('weight')).isReadOnly,
        isTrue,
      );
    });

    testWidgets('the routine editor shows the hints even with every flag '
        'learned', (tester) async {
      await _usePhoneSurface(tester);
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      routineState.setAutosaveEnabled(false);
      await routineState.createNewRoutine('Tap Hint Routine');
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');
      final effortId = await routineState.addExerciseToRoutine(exercise, 'set');
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      for (final control in TapHintControl.values) {
        await settingsState.markTapHintLearned(control);
      }
      await routineState.saveRoutine();
      final templateId = routineState.currentTemplate!.id;

      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            workoutState: workoutState,
            templateId: templateId,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(exercise.name).first);
      await tester.pumpAndSettle();

      expect(_hintIn(find.byKey(ValueKey('$effortId-0-reps'))), findsOneWidget);
      expect(
        _hintIn(find.byKey(ValueKey('$effortId-0-weight'))),
        findsOneWidget,
      );
    });
  });
}
