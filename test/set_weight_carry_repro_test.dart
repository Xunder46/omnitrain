// Plan 44 / P4a + P5a — the set-2-at-0.0 repro matrix (S-5126, D-10), now the
// guards for the D-14 carry rule (S-5127): H-6 and H-5 are green with the fix,
// H-4 stays a guard, and S-5127-a..f prove the rule's boundaries.
//
// The helpers below are copied verbatim from test/delete_focused_set_test.dart,
// with only the imports they need.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/routine_session_manifest.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
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
  RestNotificationService? restNotificationService,
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
      restNotificationService: restNotificationService,
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

/// Steps the focused set's weight with the screen's `+` button until the stored
/// value reaches [target] kg or more, and returns the stored value. The step
/// follows the saved unit, so a test reads what it reached instead of assuming
/// 2.5.
Future<double> _stepWeightUntilAtLeast(
  WidgetTester tester,
  _Deps deps,
  String effortId,
  int entryIndex,
  double target,
) async {
  double stored() =>
      ((_entriesOf(deps, effortId)[entryIndex]['weight'] as num?) ?? 0.0)
          .toDouble();
  var taps = 0;
  while (stored() < target && taps < 20) {
    await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
    await tester.pumpAndSettle();
    taps++;
  }
  return stored();
}

void main() {
  group(
    'S-5126 H-6: sets added before set 1 has a weight take its weight',
    () {
      testWidgets('set 2 weight follows set 1 after Log Set', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        // addExerciseToSession already creates set 1 (10 reps, 0.0 kg).
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 1 of 1'), findsOneWidget);
        expect(_editorNumber('reps', '10'), findsOneWidget);

        // Sets 2 and 3 are added while set 1 still has no weight: each copies
        // the last entry of that moment (10 × 0.0).
        await tester.tap(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();
        expect(
          _entriesOf(deps, effortId).length,
          3,
          reason: 'S-5126 H-6 fixture needs sets 1..3',
        );

        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);

        double storedSetOneWeight() =>
            (_entriesOf(deps, effortId)[0]['weight'] as num?)?.toDouble() ??
            0.0;

        // Step set 1's weight until the stored value reaches 15.0 kg or more.
        // The step follows the saved unit, so the test reads what it reached
        // instead of assuming 2.5.
        var taps = 0;
        while (storedSetOneWeight() < 15.0 && taps < 20) {
          await tester.tap(find.byKey(const Key('value-stepper-plus-weight')));
          await tester.pumpAndSettle();
          taps++;
        }
        expect(
          storedSetOneWeight(),
          greaterThanOrEqualTo(15.0),
          reason:
              'S-5126 H-6 fixture: set 1 weight is ${storedSetOneWeight()} '
              'after $taps plus taps, expected at least 15.0',
        );
        final expected = storedSetOneWeight();

        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        final entries = _entriesOf(deps, effortId);
        expect(
          entries[1]['weight'],
          expected,
          reason:
              'S-5126 H-6: set 2 weight is ${entries[1]['weight']}, '
              'expected $expected',
        );
      });
    },
  );

  group('S-5126 H-5: a delete then an add keeps the weight of the sets that '
      'had one', () {
    testWidgets('the newly added set carries the logged weight', (
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
      // All three sets carry the same values, so the delete is the only
      // variable: a red here would be the delete's, not H-6's cache.
      for (var i = 0; i < 3; i++) {
        await deps.workoutState.updateEntryValue(effortId, i, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, i, 'weight', 15.0);
      }

      await tester.pumpWidget(
        _buildSessionScreen(
          deps,
          restNotificationService: FakeRestNotificationService(),
        ),
      );
      await _openDetailView(tester, 'Barbell Back Squat');

      // Log set 1 through the screen so a rest exists at entry 1.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();
      expect(
        deps.workoutState.getEntryRests(effortId).map((r) => r.entryIndex),
        contains(1),
        reason: 'S-5126 H-5 fixture needs set 1 logged',
      );

      // Focus set 2, delete it, then add a set back.
      await tester.tap(find.byKey(const Key('set-segment-1')));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();

      final entries = _entriesOf(deps, effortId);
      final rested = {
        for (final rest in deps.workoutState.getEntryRests(effortId))
          rest.entryIndex,
      };
      // A set is logged exactly when a rest sits at its index + 1 (D-1).
      for (var i = entries.length - 1; i >= 1; i--) {
        if (rested.contains(i + 1)) continue;
        expect(
          entries[i]['weight'],
          15.0,
          reason:
              'S-5126 H-5: unlogged set ${i + 1} weight is '
              '${entries[i]['weight']}, expected 15.0',
        );
      }
    });
  });

  group('S-5126 H-4: the stored weight is a double in both repositories', () {
    test('Mock and Hive both read the weight back as a double', () async {
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 15.0);

      final mockWeight = _entriesOf(deps, effortId).first['weight'];
      expect(
        mockWeight,
        isA<double>(),
        reason:
            'S-5126 H-4: Mock entry weight is $mockWeight '
            '(${mockWeight.runtimeType}), not a double',
      );

      final harness = HiveRepositoryHarness();
      final hiveRepo = await harness.open();
      try {
        final hiveState = WorkoutState(hiveRepo);
        await hiveState.createNewSession(modality: 'resistance_lifting');
        final hiveExercise = (await hiveRepo.getExercises()).firstWhere(
          (e) => e.id == 'exercise-barbell-squat',
        );
        final hiveEffortId = await hiveState.addExerciseToSession(
          hiveExercise,
          chosenMetric: 'reps',
        );
        await hiveState.updateEntryValue(hiveEffortId, 0, 'weight', 15.0);
        final hiveEntry = hiveState.getExercisesWithEntries().firstWhere(
          (e) => e['id'] == hiveEffortId,
        );
        final hiveEntries = (hiveEntry['entries'] as List)
            .cast<Map<String, dynamic>>();
        final hiveWeight = hiveEntries.first['weight'];
        expect(
          hiveWeight,
          isA<double>(),
          reason:
              'S-5126 H-4: Hive entry weight is $hiveWeight '
              '(${hiveWeight.runtimeType}), not a double',
        );
      } finally {
        await harness.close();
      }
    });
  });

  group('S-5127 the D-14 carry rule (fixed)', () {
    testWidgets(
      'S-5127-a set 2 shows the carried weight on screen after Log Set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // The H-6 flow: sets 2 and 3 appear while set 1 has no weight yet.
        await tester.tap(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();

        final stepped = await _stepWeightUntilAtLeast(
          tester,
          deps,
          effortId,
          0,
          15.0,
        );
        expect(
          stepped,
          greaterThanOrEqualTo(15.0),
          reason: 'S-5127-a fixture: set 1 weight is $stepped',
        );

        final setOneValue = tester
            .widget<InlineMetricEditor>(_editorOf('weight'))
            .currentValue;

        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(find.text('Set 2 of 3'), findsOneWidget);
        final setTwoValue = tester
            .widget<InlineMetricEditor>(_editorOf('weight'))
            .currentValue;
        expect(
          setTwoValue,
          setOneValue,
          reason:
              'S-5127-a set 2 shows $setTwoValue, expected the weight set 1 '
              'showed before logging ($setOneValue)',
        );
        expect(
          _editorNumber('weight', setOneValue.toStringAsFixed(1)),
          findsOneWidget,
          reason:
              'S-5127-a the number on screen is the carried weight, as the '
              'weight editor formats it',
        );
      },
    );

    testWidgets(
      'S-5127-b a non-zero weight on the next set is never overwritten',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 15.0);
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 20.0);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(
          _entriesOf(deps, effortId)[1]['weight'],
          20.0,
          reason:
              'S-5127-b set 2 keeps its own weight; observed '
              '${_entriesOf(deps, effortId)[1]['weight']}',
        );
      },
    );

    testWidgets('S-5127-c reps on the next set never change', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
      await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 15.0);
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 7);
      await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 0.0);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      final next = _entriesOf(deps, effortId)[1];
      expect(
        next['reps'],
        7,
        reason:
            'S-5127-c set 2 reps stay 7; observed ${next['reps']}',
      );
      expect(
        next['weight'],
        15.0,
        reason:
            'S-5127-c set 2 weight is ${next['weight']}, expected the carried '
            '15.0',
      );
    });

    testWidgets('S-5127-d a logged next set is untouched', (tester) async {
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
      for (var i = 0; i < 3; i++) {
        await deps.workoutState.updateEntryValue(effortId, i, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, i, 'weight', 0.0);
      }

      await tester.pumpWidget(
        _buildSessionScreen(
          deps,
          restNotificationService: FakeRestNotificationService(),
        ),
      );
      await _openDetailView(tester, 'Barbell Back Squat');

      // Log set 2 first; it has no weight, so nothing carries to set 3.
      await tester.tap(find.byKey(const Key('set-segment-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();
      expect(
        deps.workoutState.getEntryRests(effortId).map((r) => r.entryIndex),
        contains(2),
        reason: 'S-5127-d fixture needs set 2 logged',
      );

      // Give set 1 a weight through the screen, then log it: set 2 is already
      // logged and must not take the weight.
      await tester.tap(find.byKey(const Key('set-segment-0')));
      await tester.pumpAndSettle();
      final stepped = await _stepWeightUntilAtLeast(
        tester,
        deps,
        effortId,
        0,
        15.0,
      );
      expect(
        stepped,
        greaterThanOrEqualTo(15.0),
        reason: 'S-5127-d fixture: set 1 weight is $stepped',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(
        _entriesOf(deps, effortId)[1]['weight'],
        0.0,
        reason:
            'S-5127-d set 2 is already logged and keeps 0.0; observed '
            '${_entriesOf(deps, effortId)[1]['weight']}',
      );
    });

    testWidgets(
      'S-5127-e a skipped set (reps 0) carries nothing to the next set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 0);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 15.0);
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 0.0);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(
          _entriesOf(deps, effortId)[1]['weight'],
          0.0,
          reason:
              'S-5127-e a skipped set carries nothing; set 2 weight is '
              '${_entriesOf(deps, effortId)[1]['weight']}',
        );
      },
    );

    testWidgets(
      'S-5127-f a routine whose weight target sits on set 1 only (H-1)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(
          repo,
          'exercise-barbell-squat',
        );

        final template = WorkoutTemplate(
          id: 'tmpl-carry',
          name: 'Carry Routine',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        final manifest = RoutineSessionManifest(
          template: template,
          segments: [
            SessionSegmentEntry(
              segment: TemplateSegment(
                id: 'tseg-carry',
                templateId: 'tmpl-carry',
                orderIndex: 0,
                segmentType: 'mixed',
                name: 'Main Work',
                createdAtMs: 1000,
                updatedAtMs: 1000,
              ),
              exercises: [
                SessionExerciseEntry(
                  exercise: exercise,
                  effortKind: 'set',
                  setCount: 3,
                  targets: [
                    TemplateTarget(
                      id: 'tt-carry-reps',
                      templateEffortId: 'eff-carry',
                      metricId: MetricIds.reps,
                      setIndex: 0,
                      targetInt: 10,
                      createdAtMs: 1000,
                      updatedAtMs: 1000,
                    ),
                    TemplateTarget(
                      id: 'tt-carry-weight',
                      templateEffortId: 'eff-carry',
                      metricId: MetricIds.weight,
                      setIndex: 0,
                      targetMin: 15.0,
                      createdAtMs: 1000,
                      updatedAtMs: 1000,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await deps.workoutState.populateSessionFromManifest(manifest);

        final effortId = deps.workoutState
            .getExercisesWithEntries()
            .firstWhere(
              (e) => e['exerciseId'] == 'exercise-barbell-squat',
            )['id'] as String;
        expect(
          _entriesOf(deps, effortId).length,
          3,
          reason: 'S-5127-f fixture needs the routine\'s three sets',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(
          _entriesOf(deps, effortId)[1]['weight'],
          15.0,
          reason:
              'S-5127-f the routine\'s set 2 weight is '
              '${_entriesOf(deps, effortId)[1]['weight']}, expected the '
              'logged set 1\'s 15.0',
        );
      },
    );
  });
}
