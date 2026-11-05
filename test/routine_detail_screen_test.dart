// `RoutineSetupScreen` exercise detail — the shared bar, rows and sets control.
//
// Plan: `docs/plans/2026-10-16-38e-routine-editor-plan/2026-10-16-38e-routine-editor-plan.md`.
// Scenario mapping:
//   S-4501 the live session editor still uses the shared bar, rows and stepper
//   S-4502 A1 header subtitle; the in-body name and block lines are gone
//   S-4503 A2 set bar: focused fill, neutral siblings, tap to jump, one set
//   S-4504 A3 resistance reps/weight rows write the targets of the shown unit
//   S-4505 A3 the weight row steps in the user's unit (lbs → 5 lb, stored kg)
//   S-4505b A4 a hold's weight row converts too (lbs → 5 lb, stored kg)
//   S-4506 A4 hold: one weight row, no reps row, writes `extraWeight`
//   S-4507 A5 interval: no editable value; a stored target of an old routine
//          stays in the repository
//   S-4508 A6 round length row: caption, no `ROUND 1` heading, `+` writes both
//          `roundDuration` and `rounds`
//   S-4509 A6 15 s is the floor; the number opens the duration dialog
//   S-4510 A7 add set focuses the new set; disabled with its tooltip at the cap
//   S-4511 A7 remove set applies only to the focused last set; disabled else
//   S-4512 A8 the Previous Set / Next Set arrows still navigate
//   S-4513 a long block name does not overflow the header subtitle
//
// Mock repository only, no timers and no real delays (FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/workout_constants.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/set_count_stepper.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Phone surface (iPhone 15 class), the size the brief pins.
const Size _phone = Size(402, 874);

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

/// A routine under construction plus the states the screen needs.
typedef _Routine = ({
  MockWorkoutRepository repo,
  RoutineState routineState,
  WorkoutState workoutState,
});

Future<_Routine> _newRoutine(String name) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine(name);
  return (repo: repo, routineState: routineState, workoutState: workoutState);
}

/// A library exercise that carries both a load and reps.
Future<Exercise> _resistanceExercise(MockWorkoutRepository repo) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere(
    (e) => e.capabilities.contains('load') && e.capabilities.contains('reps'),
    orElse: () => exercises.first,
  );
}

/// A library exercise other than [notId], so the list shows two names.
Future<Exercise> _otherExercise(
  MockWorkoutRepository repo,
  String notId,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id != notId);
}

/// Saves the routine, pumps the screen and opens [exerciseName]'s detail view.
Future<void> _openDetail(
  WidgetTester tester,
  _Routine routine, {
  required String exerciseName,
  SettingsState? settingsState,
}) async {
  // The routine editor body (name field, description, modality dropdown)
  // only lays out at the editor's own height in the test font; the detail
  // view is what runs at phone size, so the surface shrinks after the tap.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await routine.routineState.saveRoutine();
  final templateId = routine.routineState.currentTemplate!.id;
  await tester.pumpWidget(
    MaterialApp(
      home: RoutineSetupScreen(
        routineState: routine.routineState,
        workoutState: routine.workoutState,
        templateId: templateId,
        settingsState: settingsState,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName).first);
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(_phone);
  await tester.pumpAndSettle();
}

/// The stored target row for one metric and set, as the screen reads it.
TemplateTarget? _target(
  _Routine routine,
  String effortId,
  String metricId,
  int setIndex,
) {
  for (final target in routine.routineState.getEffortTargets(effortId)) {
    if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
      return target;
    }
  }
  return null;
}

/// The stored target rows the repository holds for one metric and set.
Future<TemplateTarget?> _storedTarget(
  MockWorkoutRepository repo,
  String effortId,
  String metricId,
  int setIndex,
) async {
  final targets = await repo.getTemplateTargets(effortId);
  for (final target in targets) {
    if (target.metricId == metricId && (target.setIndex ?? 0) == setIndex) {
      return target;
    }
  }
  return null;
}

/// Seeds `count` sets of 10 reps on a resistance effort.
Future<void> _seedSets(_Routine routine, String effortId, int count) async {
  for (var i = 0; i < count; i++) {
    await routine.routineState.setTargetValue(
      effortId,
      MetricIds.reps,
      MetricIds.unitReps,
      setIndex: i,
      targetInt: 10,
    );
  }
}

Finder _segment(int index) => find.byKey(Key('set-segment-$index'));

Color _segmentFill(WidgetTester tester, int index) {
  final container = tester.widget<Container>(
    find.descendant(of: _segment(index), matching: find.byType(Container)),
  );
  return (container.decoration! as BoxDecoration).color!;
}

/// The number as drawn inside [row] — the first [Text] of the row is the value.
String _shownNumber(WidgetTester tester, Finder row) {
  return tester
      .widget<Text>(find.descendant(of: row, matching: find.byType(Text)).first)
      .data!;
}

/// A session-screen dependency bundle (pattern: `logger_shell_screen_test.dart`).
typedef _SessionDeps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
});

Future<_SessionDeps> _buildSessionDeps({String? modality}) async {
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

Widget _buildSessionScreen(_SessionDeps deps, {bool editMode = false}) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      settingsState: deps.settingsState,
      timerAlertService: FakeTimerAlertService(),
      editMode: editMode,
    ),
  );
}

Future<Exercise> _exerciseById(MockWorkoutRepository repo, String id) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere((e) => e.id == id);
}

void main() {
  group('S-4501 session editor guard', () {
    testWidgets('the live session editor still uses the shared pieces', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(_phone);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final deps = await _buildSessionDeps(modality: 'resistance_lifting');
      final exercise = await _exerciseById(deps.repo, 'exercise-barbell-squat');
      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text(exercise.name).first);
      await tester.pumpAndSettle();

      expect(find.byType(SetSegmentBar), findsOneWidget);
      final bar = tester.widget<SetSegmentBar>(find.byType(SetSegmentBar));
      expect(bar.count, greaterThan(1));
      expect(bar.focusedIndex, 0);

      final rows = tester
          .widgetList<ValueStepperRow>(find.byType(ValueStepperRow))
          .toList();
      expect(
        rows.map((r) => r.metricType),
        containsAll(<String>['reps', 'weight']),
        reason: 'the session editor keeps its reps and weight rows',
      );
      expect(
        find.byKey(const Key('tap-hint')),
        findsNWidgets(2),
        reason: 'S-4712: both editable rows carry the hint',
      );

      expect(find.byType(SetCountStepper), findsOneWidget);
      final stepper = tester.widget<SetCountStepper>(
        find.byType(SetCountStepper),
      );
      expect(stepper.text, 'Set 1 of ${bar.count}');
      expect(stepper.canAdd, isTrue);
      expect(_segment(0), findsOneWidget);
      expect(_segment(bar.count - 1), findsOneWidget);
      expect(_segment(bar.count), findsNothing);
    });
  });

  group('S-4502 header (A1)', () {
    testWidgets('the subtitle carries the exercise index and the block name', (
      tester,
    ) async {
      final routine = await _newRoutine('Header Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final other = await _otherExercise(routine.repo, exercise.id);
      await routine.routineState.addExerciseToRoutine(exercise, 'set');
      await routine.routineState.addExerciseToRoutine(other, 'set');

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(find.text('Exercise 1 / 2 · Main Block'), findsOneWidget);
      expect(
        find.text('Main Block'),
        findsNothing,
        reason: 'the block line is gone from the body',
      );
      expect(
        find.text(exercise.name),
        findsOneWidget,
        reason: 'the exercise name only lives in the header title',
      );
      expect(find.text(other.name), findsNothing);
      expect(find.byType(SetSegmentBar), findsOneWidget);
    });
  });

  group('S-4503 set bar (A2)', () {
    testWidgets('the focused segment is the faint accent, the others neutral', (
      tester,
    ) async {
      final routine = await _newRoutine('Set Bar Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await _seedSets(routine, effortId, 3);

      await _openDetail(tester, routine, exerciseName: exercise.name);

      final scheme = Theme.of(
        tester.element(find.byType(RoutineSetupScreen)),
      ).colorScheme;
      expect(_segmentFill(tester, 0), scheme.primary.withAlpha(115));
      expect(_segmentFill(tester, 1), scheme.onSurface.withAlpha(51));
      expect(_segmentFill(tester, 2), scheme.onSurface.withAlpha(51));
      expect(_segment(3), findsNothing);
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.tap(_segment(2));
      await tester.pumpAndSettle();

      expect(find.text('Set 3 of 3'), findsOneWidget);
      expect(_segmentFill(tester, 2), scheme.primary.withAlpha(115));
      expect(_segmentFill(tester, 0), scheme.onSurface.withAlpha(51));
    });

    testWidgets('a one-set effort still shows one segment', (tester) async {
      final routine = await _newRoutine('One Set Routine');
      final exercise = await _resistanceExercise(routine.repo);
      await routine.routineState.addExerciseToRoutine(exercise, 'set');

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(_segment(0), findsOneWidget);
      expect(_segment(1), findsNothing);
      expect(find.text('Set 1 of 1'), findsOneWidget);
    });
  });

  group('S-4504 resistance rows (A3)', () {
    testWidgets('the reps and weight rows read and write the shown set', (
      tester,
    ) async {
      final routine = await _newRoutine('Resistance Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.reps,
        MetricIds.unitReps,
        setIndex: 0,
        targetInt: 10,
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.weight,
        MetricIds.unitKg,
        setIndex: 0,
        targetMin: 50.0,
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      final repsRow = find.byKey(ValueKey('$effortId-0-reps'));
      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(repsRow, findsOneWidget);
      expect(weightRow, findsOneWidget);
      expect(find.byType(ValueStepperRow), findsNWidgets(2));
      expect(_shownNumber(tester, repsRow), '10');
      expect(_shownNumber(tester, weightRow), '50.0');
      expect(find.text('REPS'), findsOneWidget);
      expect(find.text('KG'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-plus-reps')));
      await tester.pumpAndSettle();

      final reps = _target(routine, effortId, MetricIds.reps, 0);
      expect(reps, isNotNull);
      expect(reps!.targetInt, 11);
      expect(reps.unitId, MetricIds.unitReps);

      await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
      await tester.pumpAndSettle();

      final weight = _target(routine, effortId, MetricIds.weight, 0);
      expect(weight, isNotNull);
      expect(weight!.targetMin, 52.5, reason: 'kg steps by 2.5');
      expect(weight.unitId, MetricIds.unitKg);
    });
  });

  group('S-4505 user unit (A3)', () {
    testWidgets('a lbs lifter steps 5 lb and the kg target follows', (
      tester,
    ) async {
      final routine = await _newRoutine('Lbs Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.weight,
        MetricIds.unitKg,
        setIndex: 0,
        targetMin: 0.0,
      );
      final settingsState = SettingsState(
        routine.repo,
        fakePreferencesService(),
      );
      await settingsState.initialize();
      await settingsState.setPreferredWeightUnit('lbs');

      await _openDetail(
        tester,
        routine,
        exerciseName: exercise.name,
        settingsState: settingsState,
      );

      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(find.text('LBS'), findsOneWidget);
      expect(find.text('KG'), findsNothing);
      expect(_shownNumber(tester, weightRow), '0.0');

      await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
      await tester.pumpAndSettle();

      expect(_shownNumber(tester, weightRow), '5.0');
      final stored = _target(routine, effortId, MetricIds.weight, 0);
      expect(stored, isNotNull);
      expect(stored!.targetMin, closeTo(5 / 2.20462, 0.0001));
    });
  });

  group('S-4506 hold rows (A4)', () {
    testWidgets('a hold has a weight row and no reps row', (tester) async {
      final routine = await _newRoutine('Hold Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'drill',
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(find.byType(ValueStepperRow), findsOneWidget);
      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(weightRow, findsOneWidget);
      expect(find.byKey(ValueKey('$effortId-0-reps')), findsNothing);
      expect(find.text('KG'), findsOneWidget);
      expect(find.text('Hold 1 of 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
      await tester.pumpAndSettle();

      final extraWeight = _target(routine, effortId, MetricIds.extraWeight, 0);
      expect(extraWeight, isNotNull);
      expect(extraWeight!.targetMin, 2.5);
      expect(extraWeight.unitId, MetricIds.unitKg);
      expect(_target(routine, effortId, MetricIds.reps, 0), isNull);
    });

    testWidgets('S-4505b hold in pounds stores the kg target', (tester) async {
      final routine = await _newRoutine('Lbs Hold Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'drill',
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.extraWeight,
        MetricIds.unitKg,
        setIndex: 0,
        targetMin: 0.0,
      );
      final settingsState = SettingsState(
        routine.repo,
        fakePreferencesService(),
      );
      await settingsState.initialize();
      await settingsState.setPreferredWeightUnit('lbs');

      await _openDetail(
        tester,
        routine,
        exerciseName: exercise.name,
        settingsState: settingsState,
      );

      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(find.text('LBS'), findsOneWidget);
      expect(find.text('KG'), findsNothing);
      expect(_shownNumber(tester, weightRow), '0.0');

      await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
      await tester.pumpAndSettle();

      expect(_shownNumber(tester, weightRow), '5.0');
      final stored = _target(routine, effortId, MetricIds.extraWeight, 0);
      expect(stored, isNotNull);
      expect(stored!.targetMin, closeTo(5 / 2.20462, 0.001));
      expect(stored.unitId, MetricIds.unitKg);
    });
  });

  group('S-4507 interval (A5, restored by plan 39 D-5)', () {
    testWidgets('the interval row reads the stored target and steps it', (
      tester,
    ) async {
      final routine = await _newRoutine('Interval Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'timed',
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.extraWeight,
        MetricIds.unitKg,
        setIndex: 0,
        targetMin: 10.0,
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      final weightRow = find.byKey(ValueKey('$effortId-0-weight'));
      expect(find.byType(ValueStepperRow), findsOneWidget);
      expect(weightRow, findsOneWidget);
      expect(find.text('Interval 1 of 1'), findsOneWidget);
      expect(
        _shownNumber(tester, weightRow),
        '10.0',
        reason: 'an old routine\'s stored extraWeight target comes back',
      );

      await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
      await tester.pumpAndSettle();

      expect(_shownNumber(tester, weightRow), '12.5');
      final inState = _target(routine, effortId, MetricIds.extraWeight, 0);
      expect(inState, isNotNull);
      expect(inState!.targetMin, 12.5);

      await tester.tap(find.byKey(const Key('routine-add-set')));
      await tester.pumpAndSettle();

      expect(find.text('Interval 2 of 2'), findsOneWidget);

      await routine.routineState.saveRoutine();
      final stored = await _storedTarget(
        routine.repo,
        effortId,
        MetricIds.extraWeight,
        0,
      );
      expect(stored, isNotNull);
      expect(stored!.targetMin, 12.5);
    });
  });

  group('S-4508 round length (A6)', () {
    testWidgets(
      'the round row reads 03:00 and writes duration plus one round',
      (tester) async {
        final routine = await _newRoutine('Round Routine');
        final exercise = await _resistanceExercise(routine.repo);
        final effortId = await routine.routineState.addExerciseToRoutine(
          exercise,
          'round',
        );

        await _openDetail(tester, routine, exerciseName: exercise.name);

        final row = find.byKey(ValueKey('$effortId-0-round-length'));
        expect(row, findsOneWidget);
        expect(find.byType(ValueStepperRow), findsOneWidget);
        expect(find.text('ROUND LENGTH'), findsOneWidget);
        expect(_shownNumber(tester, row), '03:00');
        expect(find.text('Round 1 of 1'), findsOneWidget);
        expect(
          find.text('ROUND 1'),
          findsNothing,
          reason: 'the round count is a heading of the past, not a body line',
        );

        await tester.tap(find.byKey(const Key('value-stepper-plus-duration')));
        await tester.pumpAndSettle();

        final duration = _target(routine, effortId, MetricIds.roundDuration, 0);
        expect(duration, isNotNull);
        expect(duration!.targetInt, 195, reason: 'the default 180 plus 15 s');
        expect(duration.unitId, MetricIds.unitSeconds);

        final rounds = _target(routine, effortId, MetricIds.rounds, 0);
        expect(rounds, isNotNull);
        expect(rounds!.targetInt, 1);
        expect(rounds.unitId, MetricIds.unitRounds);
        expect(_shownNumber(tester, row), '03:15');
      },
    );
  });

  group('S-4509 round floor and the duration dialog (A6)', () {
    testWidgets('15 s is the floor and the number opens the h/m/s dialog', (
      tester,
    ) async {
      final routine = await _newRoutine('Floor Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'round',
      );
      await routine.routineState.setTargetValue(
        effortId,
        MetricIds.roundDuration,
        MetricIds.unitSeconds,
        setIndex: 0,
        targetInt: 15,
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      final row = find.byKey(ValueKey('$effortId-0-round-length'));
      expect(_shownNumber(tester, row), '00:15');

      await tester.tap(find.byKey(const Key('value-stepper-minus-duration')));
      await tester.pumpAndSettle();

      expect(_shownNumber(tester, row), '00:15');
      expect(
        _target(routine, effortId, MetricIds.roundDuration, 0)!.targetInt,
        15,
        reason: 'a step below the floor changes nothing',
      );

      await tester.tap(
        find.descendant(of: row, matching: find.byType(InlineMetricEditor)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Round Duration'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), '0');
      await tester.enterText(fields.at(1), '2');
      await tester.enterText(fields.at(2), '0');
      await tester.tap(find.text('Ok'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      final duration = _target(routine, effortId, MetricIds.roundDuration, 0);
      expect(duration, isNotNull);
      expect(duration!.targetInt, 120);
      expect(
        _target(routine, effortId, MetricIds.rounds, 0)!.targetInt,
        1,
        reason: 'the dialog writes the same duration plus rounds pair',
      );
      expect(_shownNumber(tester, row), '02:00');
    });
  });

  group('S-4510 add set (A7)', () {
    testWidgets('a new set takes the focus and is the only focused segment', (
      tester,
    ) async {
      final routine = await _newRoutine('Add Set Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(find.text('Set 1 of 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine-add-set')));
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(_segment(1), findsOneWidget);
      expect(_segment(2), findsNothing);
      final scheme = Theme.of(
        tester.element(find.byType(RoutineSetupScreen)),
      ).colorScheme;
      expect(_segmentFill(tester, 1), scheme.primary.withAlpha(115));
      expect(_segmentFill(tester, 0), scheme.onSurface.withAlpha(51));
      expect(_target(routine, effortId, MetricIds.reps, 1)!.targetInt, 10);
    });

    testWidgets('at the cap the add button is disabled with its tooltip', (
      tester,
    ) async {
      final routine = await _newRoutine('Cap Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await _seedSets(routine, effortId, WorkoutConstants.maxEntriesPerEffort);

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(
        _segment(WorkoutConstants.maxEntriesPerEffort - 1),
        findsOneWidget,
      );
      expect(_segment(WorkoutConstants.maxEntriesPerEffort), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('routine-add-set')))
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('Max 12 entries'), findsOneWidget);
    });
  });

  group('S-4511 remove set (A7)', () {
    testWidgets('only the focused last set can be removed', (tester) async {
      final routine = await _newRoutine('Remove Set Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await _seedSets(routine, effortId, 3);

      await _openDetail(tester, routine, exerciseName: exercise.name);

      final remove = find.byKey(const Key('routine-remove-set'));
      expect(
        tester.widget<IconButton>(remove).onPressed,
        isNull,
        reason: 'set 1 of 3 is not the last set',
      );

      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(find.text('Set 1 of 3'), findsOneWidget);
      expect(_target(routine, effortId, MetricIds.reps, 2), isNotNull);

      await tester.tap(_segment(2));
      await tester.pumpAndSettle();

      expect(find.text('Set 3 of 3'), findsOneWidget);
      expect(tester.widget<IconButton>(remove).onPressed, isNotNull);

      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(_segment(2), findsNothing);
      expect(_target(routine, effortId, MetricIds.reps, 2), isNull);
      expect(_target(routine, effortId, MetricIds.reps, 1), isNotNull);
    });

    testWidgets('a one-set effort cannot lose its set', (tester) async {
      final routine = await _newRoutine('Last Set Routine');
      final exercise = await _resistanceExercise(routine.repo);
      await routine.routineState.addExerciseToRoutine(exercise, 'set');

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('routine-remove-set')))
            .onPressed,
        isNull,
      );
    });
  });

  group('S-4512 set arrows (A8)', () {
    testWidgets('Previous and Next Set walk the sets and stop at the ends', (
      tester,
    ) async {
      final routine = await _newRoutine('Arrows Routine');
      final exercise = await _resistanceExercise(routine.repo);
      final effortId = await routine.routineState.addExerciseToRoutine(
        exercise,
        'set',
      );
      await _seedSets(routine, effortId, 2);

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(find.byTooltip('Previous Set'), findsOneWidget);
      expect(find.byTooltip('Next Set'), findsOneWidget);
      expect(find.text('Set 1 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Next Set'));
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(find.byKey(ValueKey('$effortId-1-reps')), findsOneWidget);

      await tester.tap(find.byTooltip('Next Set'));
      await tester.pumpAndSettle();

      expect(
        find.text('Set 2 of 2'),
        findsOneWidget,
        reason: 'the last set is the end of the excursion',
      );

      await tester.tap(find.byTooltip('Previous Set'));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.byKey(ValueKey('$effortId-0-reps')), findsOneWidget);
    });
  });

  group('S-4513 long block name (header)', () {
    testWidgets('an 80-character block name does not overflow the header', (
      tester,
    ) async {
      final routine = await _newRoutine('Long Block Routine');
      final exercise = await _resistanceExercise(routine.repo);
      await routine.routineState.addExerciseToRoutine(exercise, 'set');
      final longName =
          ('Heavy compound lifts and accessory work for the whole week ' * 2)
              .substring(0, 80);
      await routine.routineState.updateSegment(
        routine.routineState.currentSegments.first.id,
        name: longName,
      );

      await _openDetail(tester, routine, exerciseName: exercise.name);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the long block name must not overflow the header row',
      );
      final subtitle = tester.widget<Text>(
        find.text('Exercise 1 / 1 · $longName'),
      );
      expect(
        subtitle.maxLines,
        1,
        reason: 'the subtitle stays on one line',
      );
      expect(
        subtitle.overflow,
        TextOverflow.ellipsis,
        reason: 'a block name longer than the header is clipped, not wrapped',
      );
    });
  });
}
