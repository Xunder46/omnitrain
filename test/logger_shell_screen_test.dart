import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/constants/workout_constants.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/set_segment_bar.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';
import 'helpers/set_captions.dart';

// ── Shared helpers (copied from test/session_toolbar_rework_test.dart) ───────

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

// ── Shell readers ───────────────────────────────────────────────────────────

Finder _segment(int index) => find.byKey(Key('set-segment-$index'));

Finder _segmentBar(int index) =>
    find.descendant(of: _segment(index), matching: find.byType(Container));

Color _segmentFill(WidgetTester tester, int index) {
  final container = tester.widget<Container>(_segmentBar(index));
  return (container.decoration! as BoxDecoration).color!;
}

/// The painted bar's height: 6 dp unlogged, 10 dp focused or logged.
double _segmentBarHeight(WidgetTester tester, int index) {
  final container = tester.widget<Container>(_segmentBar(index));
  return container.constraints!.maxHeight;
}

List<int> _segmentIndices(WidgetTester tester) {
  final indices = <int>[];
  for (var i = 0; i < WorkoutConstants.maxEntriesPerEffort; i++) {
    if (_segment(i).evaluate().isEmpty) break;
    indices.add(i);
  }
  return indices;
}

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

/// The entry indexes of the effort's rests, as the state holds them.
List<int> _restIndexes(_Deps deps, String effortId) => [
  for (final rest in deps.workoutState.getEntryRests(effortId)) rest.entryIndex,
];

/// The entry indexes of the effort's rests that are still open.
List<int> _openRestIndexes(_Deps deps, String effortId) => [
  for (final rest in deps.workoutState.getEntryRests(effortId))
    if (rest.restEndMs == null) rest.entryIndex,
];

/// The entry indexes of the effort's rests as the repository holds them.
Future<List<int>> _repoRestIndexes(_Deps deps, String effortId) async => [
  for (final rest in await deps.workoutState.repository.getEntryRests(effortId))
    rest.entryIndex,
];

void main() {
  group('Logger shell — set bar and logged line (S-4210..S-4214)', () {
    testWidgets('S-4210: logging through the button fills the bar and line', (
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
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 62.5);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      final theme = Theme.of(tester.element(find.byType(WorkoutSessionScreen)));
      expect(_segmentIndices(tester), [0, 1, 2]);

      // Log set 1, then set 2 (the screen advances to set 3).
      await tester.tap(find.text('Log Set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Set'));
      await tester.pumpAndSettle();

      expect(_segmentFill(tester, 0), theme.colorScheme.primary);
      expect(_segmentFill(tester, 1), theme.colorScheme.primary);
      expect(
        _segmentFill(tester, 2),
        theme.colorScheme.primary.withAlpha(115),
        reason: 'the focused, unlogged segment is the faint accent',
      );
      expect(_segmentBarHeight(tester, 0), 6);
      expect(_segmentBarHeight(tester, 2), 6);
      expect(setCaptionText(tester, 0), '10×60');
      expect(setCaptionText(tester, 1), '8×62.5');
      expect(find.text('Set 3 of 3'), findsOneWidget);
    });

    testWidgets('S-4211: the line converts the weight to the user unit', (
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
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      final formatted = UnitFormatter.formatWeightValue(
        100.0,
        deps.settingsState,
      );
      expect(formatted, '220.5');
      expect(setCaptionText(tester, 0), '5×$formatted');
      expect(setCaptionText(tester, 0), '5×220.5');
    });

    testWidgets('S-4212: a set without weight reads reps and a zero weight', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 12);
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(setCaptionText(tester, 0), '12×0');
    });

    testWidgets('S-4213: logged intervals read as m:ss', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final timed = await _buildDeps(modality: 'cardio_endurance');
      final timedRepo = await _freshRepo();
      final run = await _getExerciseById(timedRepo, 'exercise-easy-run');

      final runId = await timed.workoutState.addExerciseToSession(
        run,
        effortKindOverride: 'timed',
      );
      await timed.workoutState.addEntry(runId);
      await timed.workoutState.setTimedEntryDuration(runId, 0, 42);
      await timed.workoutState.setTimedEntryDuration(runId, 1, 38);

      await tester.pumpWidget(_buildSessionScreen(timed));
      await _openDetailView(tester, 'Easy Run');
      expect(setCaptionText(tester, 0), '0:42');
      expect(setCaptionText(tester, 1), '0:38');
    });

    testWidgets('S-4213: a logged round reads as m:ss', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final round = await _buildDeps(modality: 'resistance_lifting');
      final roundRepo = await _freshRepo();
      final bag = await _getExerciseById(
        roundRepo,
        'exercise-heavy-bag-rounds',
      );

      final bagId = await round.workoutState.addExerciseToSession(
        bag,
        effortKindOverride: 'round',
      );
      await round.workoutState.setRoundDuration(bagId, 0, 95);

      await tester.pumpWidget(_buildSessionScreen(round));
      await _openDetailView(tester, 'Heavy Bag Rounds');
      expect(setCaptionText(tester, 0), '1:35');
    });

    testWidgets('S-4214: nothing logged keeps the line empty at its height', (
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(captionsPresent(), isTrue, reason: 'the caption row is reserved');
      for (final index in _segmentIndices(tester)) {
        expect(setCaptionText(tester, index), '');
      }
      expect(_segmentIndices(tester), [0, 1, 2]);
      final scheme = Theme.of(
        tester.element(find.byType(WorkoutSessionScreen)),
      ).colorScheme;
      expect(_segmentFill(tester, 0), scheme.primary.withAlpha(115));
      for (final index in _segmentIndices(tester)) {
        if (index == 0) continue;
        expect(_segmentFill(tester, index), scheme.onSurface.withAlpha(51));
        expect(_segmentBarHeight(tester, index), 6);
      }
      expect(_segmentBarHeight(tester, 0), 6);
    });
  });

  group('Logger shell — logged sets are locked live (S-4216/S-4217)', () {
    testWidgets('S-4216: a logged set is read-only and shows LOGGED', (
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
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 62.5);
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // Set 1 is logged, so the screen lands on set 2: navigate back to it.
      expect(find.text('Set 2 of 3'), findsOneWidget);
      await tester.tap(_segment(0));
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 3'), findsOneWidget);

      expect(find.text('LOGGED'), findsOneWidget);
      expect(_editor(tester, 'reps').isReadOnly, isTrue);
      expect(_editor(tester, 'weight').isReadOnly, isTrue);

      await tester.tap(_editorNumber('reps', '10'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // The same tap on an unlogged set still opens the editor.
      await tester.tap(_segment(1));
      await tester.pumpAndSettle();
      expect(_editor(tester, 'reps').isReadOnly, isFalse);
      await tester.tap(_editorNumber('reps', '8'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('LOGGED'), findsNothing);
    });

    testWidgets('S-4216: edit mode leaves a logged set editable', (
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
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(_segment(0));
      await tester.pumpAndSettle();

      expect(_editor(tester, 'reps').isReadOnly, isFalse);
      expect(_editor(tester, 'weight').isReadOnly, isFalse);
      await tester.tap(_editorNumber('reps', '10'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('S-4217: a logged hold\'s weight is read-only live', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-plank-hold');

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
      await deps.workoutState.setTimedEntryDuration(effortId, 0, 30);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Plank Hold');

      expect(find.text('LOGGED'), findsOneWidget);
      expect(_editor(tester, 'weight').isReadOnly, isTrue);
      expect(_editorNumber('weight', '10.0'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('value-stepper-plus-weight')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('value-stepper-minus-weight')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(_editorNumber('weight', '10.0'), findsOneWidget);
      expect(
        _entriesOf(deps, effortId)[0]['extra-weight'],
        10.0,
        reason: 'a logged hold is locked, so the buttons store nothing',
      );

      await tester.tap(_editorNumber('weight', '10.0'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('S-4217: edit mode keeps a logged hold\'s weight editable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'isometric_stretching');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-plank-hold');

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
      await deps.workoutState.setTimedEntryDuration(effortId, 0, 30);

      await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
      await _openDetailView(tester, 'Plank Hold');

      expect(_editor(tester, 'weight').isReadOnly, isFalse);
      await tester.tap(_editorNumber('weight', '10.0'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Edit Weight'), findsOneWidget);
    });
  });

  group('Logger shell — layout (S-4221/S-4223)', () {
    testWidgets('S-4221: the bar sits above the controls, the stepper below', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      // The controls row keeps its position: measured on the base build.
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Log Set')),
        const Rect.fromLTRB(96, 752, 294, 808),
      );
      expect(
        tester.getRect(find.byTooltip('Next')),
        const Rect.fromLTRB(306, 748, 370, 812),
      );
      expect(
        tester.getRect(find.byTooltip('Previous Set')),
        const Rect.fromLTRB(20, 748, 84, 812),
      );

      // D-8: the bar block is pinned under the header — the body starts below
      // it.
      final barBottom = tester.getRect(find.byType(SetSegmentBar)).bottom;
      final repsRect = tester.getRect(_editorOf('reps'));
      expect(repsRect.top, greaterThanOrEqualTo(barBottom));
      expect(repsRect.top - barBottom, lessThanOrEqualTo(40));

      expect(
        tester.getRect(find.byKey(const Key('set-count-add'))).top,
        greaterThan(repsRect.bottom),
        reason: 'the stepper sits below the exercise controls',
      );
      expect(find.text('SETS'), findsNothing);
      expect(_segmentIndices(tester), [0, 1, 2]);
    });

    testWidgets('S-4224: the sets stepper stays reachable while resting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      // The rest strip is up: the common state between sets.
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);
      expect(
        find.byKey(const Key('set-count-add')).hitTestable(),
        findsOneWidget,
        reason:
            'S-4224 the sets stepper must stay reachable while the rest chip shows',
      );
    });

    test('S-4223: the dot builders are gone from the session detail view', () {
      final source = File(
        'lib/features/session/workout_session_detail_view.dart',
      ).readAsStringSync();
      expect(source.contains('_buildSetProgress'), isFalse);
      expect(source.contains('_buildSetIndicator'), isFalse);

      final screen = File(
        'lib/features/session/workout_session_screen.dart',
      ).readAsStringSync();
      expect(screen.contains('_skippedSets'), isFalse);
    });
  });

  group('Logger shell — auto-advance (S-4215)', () {
    testWidgets('S-4215: logging set 1 moves focus to set 2', (tester) async {
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 3'), findsOneWidget);
    });

    testWidgets('S-4215: focus never goes back to an earlier unlogged set', (
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.tap(_segment(1));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(
        find.text('Set 3 of 3'),
        findsOneWidget,
        reason: 'set 1 is still unlogged, but focus only moves forwards, so '
            'the advance takes the first unlogged set after the focused one',
      );
    });

    testWidgets('S-4215: a logged set ahead is skipped', (tester) async {
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
      // The rest that follows set 1 belongs to set 2: set 2 reads logged.
      await deps.workoutState.recordRestStart(effortId, 2);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(
        find.text('Set 3 of 3'),
        findsOneWidget,
        reason: 'the logged set 2 is skipped; focus lands on the first '
            'unlogged set after set 1',
      );
    });

    testWidgets('S-4215: the last set moves to the next exercise', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final repExercises = (await repo.getExercises())
          .where((e) => e.capabilities.contains('reps'))
          .toList();
      final first = repExercises[0];
      final second = repExercises[1];

      final firstId = await deps.workoutState.addExerciseToSession(
        first,
        chosenMetric: 'reps',
      );
      await deps.workoutState.updateEntryValue(firstId, 0, 'reps', 10);
      await deps.workoutState.addExerciseToSession(second, chosenMetric: 'reps');

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, first.name);
      expect(find.text('Exercise 1 / 2 · Main Workout'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(find.text('Exercise 2 / 2 · Main Workout'), findsOneWidget);
      expect(find.text('Set 1 of 1'), findsOneWidget);
    });
  });

  group('Logger shell — sets stepper (S-4220/S-4230/S-4231)', () {
    testWidgets('S-4220: + adds a set', (tester) async {
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 3'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 of 4'), findsOneWidget);
      expect(_segmentIndices(tester), [0, 1, 2, 3]);
      expect(find.byTooltip('Remove set'), findsOneWidget);
      expect(find.byTooltip('Remove exercise'), findsNothing);
    });

    testWidgets('S-4220: − deletes the focused unlogged set, no dialog', (
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
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 3 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Set 2 of 2'),
        findsOneWidget,
        reason: 'the unlogged set 3 goes and the focus clamps to set 2',
      );
    });

    testWidgets('S-4220: − on an all-logged effort asks to delete a logged set', (
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
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 6);
      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);
      await deps.workoutState.recordRestStart(effortId, 3);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 3 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delete logged Set?'), findsOneWidget);
      expect(
        find.byKey(const Key('workout-delete-logged-entry-confirm')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('workout-delete-logged-entry-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 2'), findsOneWidget);
    });

    testWidgets('S-4220: − on an all-logged effort drops the last set', (
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
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 62.5);
      await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 6);
      await deps.workoutState.updateEntryValue(effortId, 2, 'weight', 65.0);
      await deps.workoutState.recordRestStart(effortId, 1);
      await deps.workoutState.recordRestStart(effortId, 2);
      await deps.workoutState.recordRestStart(effortId, 3);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 3 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('workout-delete-logged-entry-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        setCaptionText(tester, 0),
        '10×60',
        reason: 'the last set went; sets 1 and 2 keep their own values',
      );
      expect(setCaptionText(tester, 1), '8×62.5');
    });

    testWidgets('S-4231: one logged set left asks to remove the exercise', (
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
      await deps.workoutState.recordRestStart(effortId, 1);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');
      expect(find.text('Set 1 of 1'), findsOneWidget);
      expect(find.byTooltip('Remove exercise'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('set-count-remove')),
          matching: find.byIcon(Icons.delete_outline),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('set-count-remove')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Remove Exercise?'), findsOneWidget);
      expect(
        find.byKey(const Key('workout-remove-exercise-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('S-4230: at the 12-set cap + is disabled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      for (var i = 1; i < WorkoutConstants.maxEntriesPerEffort; i++) {
        await deps.workoutState.addEntry(effortId);
      }

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      expect(find.text('Set 1 of 12'), findsOneWidget);
      expect(_segmentIndices(tester).length, 12);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('set-count-add')))
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('Max 12 entries'), findsOneWidget);
    });
  });

  group('Logger shell — bar and chip (S-4232/S-4222)', () {
    testWidgets('S-4232: tapping a segment jumps to that set', (tester) async {
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();
      expect(find.text('Set 3 of 3'), findsOneWidget);

      await tester.tap(_segment(0));
      await tester.pumpAndSettle();

      expect(find.text('Set 1 of 3'), findsOneWidget);
    });

    testWidgets('S-4222: the rest chip appears after a log and pauses on tap', (
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

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('rest-overlay-chip')));
      await tester.pumpAndSettle();

      expect(deps.workoutState.isRestPaused(effortId, 1), isTrue);
    });
  });

  group('Logger shell — skipped log (S-4233)', () {
    testWidgets('S-4233: a zero-rep log leaves the segment unlogged', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final handle = tester.ensureSemantics();
      final deps = await _buildDeps(modality: 'resistance_lifting');
      final repo = await _freshRepo();
      final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

      final effortId = await deps.workoutState.addExerciseToSession(
        exercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.addEntry(effortId);
      await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 0);
      await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
      await deps.workoutState.updateEntryValue(effortId, 2, 'reps', 6);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, 'Barbell Back Squat');

      final entries =
          deps.workoutState.getExercisesWithEntries().firstWhere(
                (e) => e['id'] == effortId,
              )['entries']
              as List;
      expect((entries[0] as Map<String, dynamic>)['reps'], 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      expect(find.text('Set 2 of 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Set 1 of 3, not logged'), findsOneWidget);
      expect(setCaptionText(tester, 0), '');
      expect(deps.workoutState.getEntryRests(effortId), isEmpty);

      handle.dispose();
    });
  });

  // ── 38f P1 — a deleted logged set must not come back as logged ────────────
  group('Logger polish — deleting a logged set (S-4310, S-4319..S-4321)', () {
    testWidgets(
      'S-4310: the set added after a delete reads unlogged and logs cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final handle = tester.ensureSemantics();
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

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        final theme = Theme.of(
          tester.element(find.byType(WorkoutSessionScreen)),
        );

        // Log all three sets through the button: three real rests.
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Log Set'));
          await tester.pumpAndSettle();
        }
        expect(_restIndexes(deps, effortId), [1, 2, 3]);
        expect(
          find.bySemanticsLabel('Set 3 of 3, logged, current'),
          findsOneWidget,
        );

        // − on an all-logged effort deletes the last logged set.
        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete logged Set?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();
        expect(_restIndexes(deps, effortId), [1, 2]);

        await tester.ensureVisible(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('set-count-add')));
        await tester.pumpAndSettle();

        // The delete clamped the focus to set 2, so the fresh third set is
        // reached by tapping its segment.
        await tester.tap(_segment(2));
        await tester.pumpAndSettle();

        expect(find.text('Set 3 of 3'), findsOneWidget);
        expect(
          find.text('LOGGED'),
          findsNothing,
          reason: 'the new set 3 has never been logged',
        );
        expect(find.text('Log Set'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Set 3 of 3, current'),
          findsOneWidget,
          reason: 'the new segment is focused and not logged',
        );
        expect(
          _segmentFill(tester, 2),
          theme.colorScheme.primary.withAlpha(115),
          reason: 'a focused, unlogged segment keeps the faint accent',
        );

        await tester.tap(find.text('Log Set'));
        await tester.pumpAndSettle();

        expect(
          _restIndexes(deps, effortId),
          [1, 2, 3],
          reason: 'the tap logs the new set instead of being swallowed',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'S-4319: an edit-mode delete that is Saved keeps the new rest indexes',
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
        for (var i = 0; i < 3; i++) {
          await deps.workoutState.updateEntryValue(effortId, i, 'reps', 10 - i);
          await deps.workoutState.recordRestStart(effortId, i + 1);
          await deps.workoutState.recordRestEnd(effortId, i + 1);
        }
        expect(_restIndexes(deps, effortId), [1, 2, 3]);

        await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(
          find.text('Set 3 of 3'),
          findsOneWidget,
          reason: 'every set is logged, so the focus lands on the last one',
        );

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete logged Set?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(
          _restIndexes(deps, effortId),
          [1, 2],
          reason: 'the deleted set 3 takes rest 3 with it',
        );

        // Back to the list view, then Save.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes').last);
        await tester.pumpAndSettle();

        expect(_restIndexes(deps, effortId), [1, 2]);
        expect(
          await _repoRestIndexes(deps, effortId),
          [1, 2],
          reason: 'Save keeps the re-key that was just persisted',
        );
      },
    );

    testWidgets(
      'S-4320: deleting the set whose rest is open hides the chip and '
      'cancels the pings',
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
        // addExerciseToSession already creates set 1.
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);
        for (var i = 0; i < 3; i++) {
          await deps.workoutState.updateEntryValue(effortId, i, 'reps', 10 - i);
          // Set 3 is logged and its rest is never closed.
          await deps.workoutState.recordRestStart(effortId, i + 1);
        }
        expect(_openRestIndexes(deps, effortId), [3]);

        await tester.pumpWidget(
          _buildSessionScreen(deps, restNotificationService: restService),
        );
        await _openDetailView(tester, 'Barbell Back Squat');
        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        final cancelsBefore = restService.cancelCallCount;

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Delete logged Set?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-delete-logged-entry-confirm')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rest-overlay-chip')), findsNothing);
        expect(_restIndexes(deps, effortId), [1, 2]);
        expect(_openRestIndexes(deps, effortId), isEmpty);
        expect(
          restService.cancelCallCount,
          greaterThan(cancelsBefore),
          reason: 'the deleted set takes the rest pings it scheduled with it',
        );
      },
    );

    testWidgets(
      'S-4321: removing the exercise cascades its logged set and rest away',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        // addExerciseToSession already creates the single set of this effort.
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
        await deps.workoutState.recordRestStart(effortId, 1);
        expect(_entriesOf(deps, effortId), hasLength(1));
        expect(_restIndexes(deps, effortId), [1]);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        // The single set is the whole exercise: − asks to remove the exercise.
        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Remove Exercise?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-remove-exercise-confirm')),
        );
        await tester.pumpAndSettle();

        expect(
          deps.workoutState.getExercisesWithEntries().map((e) => e['id']),
          isNot(contains(effortId)),
        );
        expect(deps.workoutState.getEntryRests(effortId), isEmpty);
        expect(
          await _repoRestIndexes(deps, effortId),
          isEmpty,
          reason: 'the repository cascades the rests of a removed exercise',
        );
      },
    );

    testWidgets(
      'S-4330: removing the exercise cancels the pings of its open rest',
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
        // addExerciseToSession already creates the single set of this effort.
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);

        await tester.pumpWidget(
          _buildSessionScreen(deps, restNotificationService: restService),
        );
        await _openDetailView(tester, 'Barbell Back Squat');

        // Log the only set through the button: its rest stays open.
        await tester.tap(find.text('Log Set'));
        await tester.pumpAndSettle();
        expect(_openRestIndexes(deps, effortId), [1]);
        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        final cancelsBefore = restService.cancelCallCount;

        await tester.tap(find.byKey(const Key('set-count-remove')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Remove Exercise?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('workout-remove-exercise-confirm')),
        );
        await tester.pumpAndSettle();

        expect(
          restService.cancelCallCount,
          greaterThan(cancelsBefore),
          reason: 'the removed exercise takes its open rest pings with it',
        );
      },
    );
  });

  // ── 38f P3a — wiring: captions, pinned bar, one-line header, sets control ──
  group(
    'Logger polish — header, captions, boxes, layout '
    '(S-4311..S-4317, S-4322..S-4324)',
    () {
      testWidgets('S-4311: the counter and the section name are one text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(find.text('Exercise 1 / 1 · Main Workout'), findsOneWidget);
        expect(
          find.text('Exercise 1 / 1'),
          findsNothing,
          reason: 'the counter and the section name are one text now',
        );
      });

      testWidgets('S-4312: every logged set carries its own caption', (
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
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 62.5);
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(setCaptionText(tester, 0), '10×60');
        expect(setCaptionText(tester, 1), '8×62.5');
        expect(
          setCaptionText(tester, 2),
          '',
          reason: 'the third set is not logged',
        );
        expect(captionTexts(tester), ['10×60', '8×62.5']);

        for (final index in const [0, 1]) {
          final cell = tester.getRect(_segment(index));
          final caption = tester.getRect(setCaption(index));
          expect(caption.left, greaterThanOrEqualTo(cell.left));
          expect(caption.right, lessThanOrEqualTo(cell.right));
          expect(
            caption.top,
            greaterThanOrEqualTo(tester.getRect(_segmentBar(index)).bottom),
            reason: 'the caption sits below its own segment',
          );
        }
      });

      testWidgets('S-4312: six sets drop the captions and their space', (
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
        for (var i = 0; i < 5; i++) {
          await deps.workoutState.addEntry(effortId);
        }
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(_segmentIndices(tester), [0, 1, 2, 3, 4, 5]);
        expect(find.byKey(const Key('set-caption-0')), findsNothing);
        expect(captionsPresent(), isFalse);
      });

      testWidgets('S-4313: a zero and a negative weight still read', (
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
        await deps.workoutState.updateEntryValue(effortId, 0, 'reps', 12);
        await deps.workoutState.updateEntryValue(effortId, 0, 'weight', 0.0);
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 10);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', -5.0);
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(setCaptionText(tester, 0), '12×0');
        expect(setCaptionText(tester, 1), '10×-5');
      });

      testWidgets('S-4314: no segment has a border and all are 6 dp', (
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

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(_segmentIndices(tester), [0, 1, 2]);
        for (final index in _segmentIndices(tester)) {
          final decoration =
              tester.widget<Container>(_segmentBar(index)).decoration!
                  as BoxDecoration;
          expect(decoration.border, isNull, reason: 'segment $index');
          expect(_segmentBarHeight(tester, index), 6, reason: 'segment $index');
        }
      });

      testWidgets('S-4315: the sets control boxes the count text', (
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

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        await tester.tap(_segment(1));
        await tester.pumpAndSettle();

        expect(find.text('Set 2 of 3'), findsOneWidget);
        final box = find.ancestor(
          of: find.text('Set 2 of 3'),
          matching: find.byType(OmniSurface),
        );
        expect(box, findsOneWidget);
        expect(
          find.descendant(
            of: box,
            matching: find.byKey(const Key('set-count-remove')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: box,
            matching: find.byKey(const Key('set-count-add')),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Remove set'), findsOneWidget);
        expect(find.byTooltip('Add set'), findsOneWidget);
        expect(find.byTooltip('Max 12 entries'), findsNothing);
        expect(
          find.text('SETS'),
          findsNothing,
          reason: 'the separate count and its label are gone',
        );
      });

      testWidgets('S-4316: the reps and weight rows sit in an OmniSurface', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        final rows = find.byType(ValueStepperRow);
        expect(rows, findsNWidgets(2));
        expect(tester.widget<ValueStepperRow>(rows.first).metricType, 'reps');
        expect(tester.widget<ValueStepperRow>(rows.last).metricType, 'weight');
        for (final row in [rows.first, rows.last]) {
          expect(
            find.descendant(of: row, matching: find.byType(OmniSurface)),
            findsOneWidget,
          );
        }
      });

      testWidgets(
        'S-4317: at 390 x 844 the bar hugs the header and the sets control '
        'stays reachable',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
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
          await deps.workoutState.addEntry(effortId);
          await deps.workoutState.addEntry(effortId);
          // The rest strip is up: the common state between sets.
          await deps.workoutState.recordRestStart(effortId, 1);

          await tester.pumpWidget(_buildSessionScreen(deps));
          await _openDetailView(tester, 'Barbell Back Squat');
          await tester.tap(_segment(1));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

          final headerBottom = tester
              .getRect(find.byKey(const Key('session-detail-header')))
              .bottom;
          final barTop = tester.getRect(_segmentBar(0)).top;
          expect(
            barTop - headerBottom,
            inInclusiveRange(0, 8),
            reason: 'the bar sits directly under the header, not in the scroll',
          );

          expect(
            find.byKey(const Key('set-count-add')).hitTestable(),
            findsOneWidget,
            reason: 'the sets control must stay reachable while resting',
          );

          final setsBox = find.ancestor(
            of: find.text('Set 2 of 3'),
            matching: find.byType(OmniSurface),
          );
          final repsBox = find.descendant(
            of: find.byType(ValueStepperRow).first,
            matching: find.byType(OmniSurface),
          );
          expect(
            tester.getSize(setsBox).height,
            lessThan(tester.getSize(repsBox).height),
            reason: 'the sets control is shorter than a reps row',
          );
        },
      );

      testWidgets('S-4322: an empty section name leaves the counter alone', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = deps.workoutState.repository;
        final sessionId = deps.workoutState.currentSession!.id;
        final at = DateTime.now().millisecondsSinceEpoch;
        const effortId = 'eff-nameless';
        const segmentId = 'seg-nameless';

        // A NULL name falls back to `Block N`, so the empty string is the only
        // way to reach a header with no section name (plan 38f, S-4322).
        await repo.createSegment(
          SessionSegment(
            id: segmentId,
            sessionId: sessionId,
            orderIndex: 1,
            segmentType: 'workout',
            name: '',
            createdAtMs: at,
            updatedAtMs: at,
          ),
        );
        await seedSetEffort(
          repo,
          segmentId: segmentId,
          effortId: effortId,
          exerciseId: 'exercise-barbell-squat',
          entryCount: 1,
          hasExtraWeight: false,
        );
        await deps.workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(
          _buildSessionScreen(deps, initialFocusId: effortId),
        );
        await tester.pumpAndSettle();

        expect(find.text('Exercise 1 / 1'), findsOneWidget);
        expect(find.textContaining('·'), findsNothing);
      });

      testWidgets('S-4323: the captions row is there, blank, before a log', (
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

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(setCaption(0), findsOneWidget);
        expect(setCaptionText(tester, 0), '');
        expect(captionTexts(tester), isEmpty);

        final emptyBar = tester.getRect(find.byType(SetSegmentBar));
        final emptyReps = tester.getRect(find.byType(ValueStepperRow).first);

        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(captionTexts(tester), ['10×0']);
        expect(
          tester.getRect(find.byType(SetSegmentBar)),
          emptyBar,
          reason: 'the captions row must not change the bar block',
        );
        expect(
          tester.getRect(find.byType(ValueStepperRow).first),
          emptyReps,
          reason: 'the first log must not push the body down',
        );
      });

      testWidgets('S-4324: a logged, focused set reads dominant', (tester) async {
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
        await deps.workoutState.updateEntryValue(effortId, 1, 'reps', 8);
        await deps.workoutState.updateEntryValue(effortId, 1, 'weight', 62.5);
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');
        await tester.tap(_segment(0));
        await tester.pumpAndSettle();

        final theme = Theme.of(tester.element(find.byType(WorkoutSessionScreen)));
        expect(_segmentFill(tester, 0), theme.colorScheme.primary);
        expect(
          tester.widget<Text>(setCaption(0)).style!.color,
          OmniTheme.colors.textDominant,
          reason: 'the focused set carries the dominant caption',
        );
        expect(
          tester.widget<Text>(setCaption(1)).style!.color,
          OmniTheme.colors.textSecondary,
        );
      });

      testWidgets('S-4331: the bar block is inset 20 dp on both sides', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final deps = await _buildDeps(modality: 'resistance_lifting');
        final repo = await _freshRepo();
        final exercise = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await deps.workoutState.addExerciseToSession(
          exercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.addEntry(effortId);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, 'Barbell Back Squat');

        expect(_segmentIndices(tester), [0, 1, 2]);
        expect(
          tester.getRect(_segment(0)).left,
          closeTo(23.0, 0.01),
          reason: 'the 20 dp inset plus the 3 dp cell padding',
        );
        expect(
          tester.getRect(_segment(2)).right,
          closeTo(367.0, 0.01),
          reason: '390 dp minus the 20 dp inset and the 3 dp cell padding',
        );
      });
    },
  );
}
