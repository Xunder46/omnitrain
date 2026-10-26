// Plan 41 / P2a — `−` deletes the focused set (S-4901, S-4902, S-4907,
// S-4909).
//
// The helpers below are copied verbatim from test/logger_shell_screen_test.dart,
// with only the imports they need.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
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

/// The entry indexes of the effort's rests, as the state holds them.
List<int> _restIndexes(_Deps deps, String effortId) => [
  for (final rest in deps.workoutState.getEntryRests(effortId)) rest.entryIndex,
];

/// The entry indexes of the effort's rests that are still open.
List<int> _openRestIndexes(_Deps deps, String effortId) => [
  for (final rest in deps.workoutState.getEntryRests(effortId))
    if (rest.restEndMs == null) rest.entryIndex,
];

void main() {
  group('Delete the focused set (plan 41)', () {
    testWidgets(
      'S-4901: − deletes the focused unlogged set, not the last one',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        // addExerciseToSession already creates set 1 (reps 5).
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 5);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 6);
        await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 8);
        // A rest at entry 1 marks set 1 logged; sets 2 and 3 stay unlogged.
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // The screen opens on the first unlogged set: set 2, reps 6.
        expect(find.text('Set 2 of 3'), findsOneWidget);
        expect(_editorNumber('reps', '6'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(
          _editorNumber('reps', '8'),
          findsOneWidget,
          reason: 'the focused set (6) went; the old set 3 (8) slid up',
        );
        expect(_editorNumber('reps', '6'), findsNothing);
      },
    );

    testWidgets(
      'S-4902: − on a logged focused set asks, cancel keeps it, delete '
      'removes it and re-keys the rests',
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
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
        await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 6);
        // Rests at 1 and 2 mark sets 1 and 2 logged; set 3 stays unlogged.
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 3 of 3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete logged Set?'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-cancel')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);
        expect(_restIndexes(deps, effortId), [1, 2]);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_editorNumber('reps', '8'), findsOneWidget);
        expect(
          _restIndexes(deps, effortId),
          [1],
          reason: 'set 1 keeps no rest; the rest at 2 moves down to 1',
        );
      },
    );

    testWidgets(
      'S-4907: an open rest of a later set keeps its own set after a middle '
      'delete',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final restService = FakeRestNotificationService();
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
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 9);
        await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 8);
        // Sets 1 and 2 are logged; set 3's rest is the one still open.
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);
        await deps.workoutState.recordRestStart(effortId, 3);
        expect(_openRestIndexes(deps, effortId), [3]);

        await tester.pumpWidget(
          _buildSessionScreen(deps, restNotificationService: restService),
        );
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 3 of 3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);
        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_restIndexes(deps, effortId), [1, 2]);
        expect(
          _openRestIndexes(deps, effortId),
          [2],
          reason: 'set 3 keeps its own rest, now at entry 2',
        );
        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      },
    );

    testWidgets(
      'S-4909: an edit-mode delete moves the buffered edits with their sets',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        // addExerciseToSession already creates set 1.
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);
        const reps = [10, 6, 8];
        for (var i = 0; i < 3; i++) {
          await deps.workoutState.updateEntryValue(
            effortId,
            i,
            'reps',
            reps[i],
          );
          await deps.workoutState.recordRestStart(effortId, i + 1);
          await deps.workoutState.recordRestEnd(effortId, i + 1);
        }

        await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.text('Set 3 of 3'), findsOneWidget);

        // Step set 3's reps 8 → 9; the edit is buffered until Save.
        await tester.tap(find.byKey(const Key('value-stepper-plus-reps')));
        await tester.pumpAndSettle();
        expect(_editorNumber('reps', '9'), findsOneWidget);
        expect(
          _entriesOf(deps, effortId)[2]['reps'],
          8,
          reason: 'the edit is buffered, not written yet',
        );

        // Delete the focused first set; every later set moves down one place.
        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete logged Set?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 2'), findsOneWidget);

        // Back to the list view, then Save.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes').last);
        await tester.pumpAndSettle();

        final entries = _entriesOf(deps, effortId);
        expect(entries.length, 2);
        expect(entries[0]['reps'], 6);
        expect(
          entries[1]['reps'],
          9,
          reason: 'the buffered edit moved down with its set',
        );
      },
    );
  });
}
