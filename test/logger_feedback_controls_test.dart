// Plan 44 / T2a — the forward arrow's end rule and the rest chip
// (S-5109..S-5115).
//
// The helpers below are copied verbatim from test/delete_focused_set_test.dart,
// with only the imports they need.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
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

/// A nav arrow's state: whether it answers taps, its disc fill and icon colour.
({bool enabled, Color? fill, Color? iconColor}) _arrow(
  WidgetTester tester,
  String tooltip,
) {
  final tip = find.byTooltip(tooltip);
  final ink = tester.widget<InkWell>(
    find.descendant(of: tip, matching: find.byType(InkWell)),
  );
  final material = tester.widget<Material>(
    find.descendant(of: tip, matching: find.byType(Material)).first,
  );
  final icon = tester.widget<Icon>(
    find.descendant(of: tip, matching: find.byType(Icon)),
  );
  return (
    enabled: ink.onTap != null,
    fill: material.color,
    iconColor: icon.color,
  );
}

/// Adds one squat with [sets] sets at [reps] reps each.
Future<String> _seedSquatSets(
  _Deps deps,
  Exercise squat, {
  int sets = 1,
  int reps = 10,
}) async {
  final effortId = await deps.workoutState.addExerciseToSession(
    squat,
    chosenMetric: 'reps',
  );
  for (var i = 1; i < sets; i++) {
    await deps.workoutState.addEntry(effortId);
  }
  for (var i = 0; i < sets; i++) {
    await deps.workoutState.updateEntryValue(effortId, i, 'reps', reps);
  }
  return effortId;
}

Finder _restChip() => find.byKey(const Key('rest-overlay-chip'));

Finder _restChipSemantics(String label) => find.ancestor(
  of: _restChip(),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.label == label &&
        w.properties.button == true,
  ),
);

Color? _restChipFill(WidgetTester tester) {
  final ink = tester.widget<Ink>(
    find.descendant(of: _restChip(), matching: find.byType(Ink)),
  );
  return (ink.decoration as BoxDecoration).color;
}

void main() {
  group('Forward arrow and rest chip (plan 44 T2a)', () {
    testWidgets(
      'S-5109: the forward arrow dims and stops answering at the last set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
        final bench = await _getExerciseById(repo, 'exercise-bench-press');

        await _seedSquatSets(deps, squat, sets: 2);
        await _seedSquatSets(deps, bench, sets: 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, squat.name);

        // The subtitle carries the block name after ' · '; match the counter.
        expect(find.textContaining('Exercise 1 / 2'), findsOneWidget);
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isTrue);

        // The disabled look is the back arrow's own at the very start.
        final disabledBack = _arrow(tester, 'Previous Set');
        expect(disabledBack.enabled, isFalse);

        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isTrue);

        // The last set of exercise A still has a way forward: exercise B.
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Exercise 2 / 2'), findsOneWidget);
        expect(find.text('Set 1 of 1'), findsOneWidget);

        final endArrow = _arrow(tester, 'Next');
        expect(endArrow.enabled, isFalse);
        expect(endArrow.fill, disabledBack.fill);
        expect(endArrow.iconColor, disabledBack.iconColor);

        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Exercise 2 / 2'), findsOneWidget);
        expect(find.text('Set 1 of 1'), findsOneWidget);
      },
    );

    testWidgets(
      'S-5110: a single unlogged set keeps both arrows dead, logging included',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
        await _seedSquatSets(deps, squat);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, squat.name);

        expect(find.text('Set 1 of 1'), findsOneWidget);
        expect(_editorOf('reps'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isFalse);
        expect(_arrow(tester, 'Previous Set').enabled, isFalse);

        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        expect(find.text('LOGGED'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isFalse);
        expect(_arrow(tester, 'Previous Set').enabled, isFalse);
      },
    );

    testWidgets('S-5111: adding a set wakes the forward arrow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final deps = await _buildDeps(modality: null);
      final repo = await _freshRepo();
      final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
      await _seedSquatSets(deps, squat);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, squat.name);
      expect(_arrow(tester, 'Next').enabled, isFalse);

      await tester.tap(find.byKey(const Key('set-count-add')));
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(_arrow(tester, 'Next').enabled, isTrue);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(_arrow(tester, 'Next').enabled, isFalse);
    });

    testWidgets(
      'S-5112: the session editor dims its forward arrow at the end',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');

        final effortId = await _seedSquatSets(deps, squat, sets: 2);
        // A rest after each set is what marks it logged.
        await deps.workoutState.recordRestStart(effortId, 1);
        await deps.workoutState.recordRestStart(effortId, 2);
        expect(_entriesOf(deps, effortId).length, 2);
        expect(_restIndexes(deps, effortId), [1, 2]);

        await tester.pumpWidget(_buildSessionScreen(deps, editMode: true));
        await _openDetailView(tester, squat.name);

        await tester.tap(find.byKey(const Key('set-segment-0')));
        await tester.pumpAndSettle();
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_editorNumber('reps', '10'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isTrue);

        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Set 2 of 2'), findsOneWidget);
        expect(_arrow(tester, 'Next').enabled, isFalse);
        expect(_arrow(tester, 'Previous Set').enabled, isTrue);
      },
    );

    testWidgets(
      'S-5113: a not-started interval keeps the forward arrow dead and Start live',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: 'cardio_endurance');
        final repo = await _freshRepo();
        final easyRun = await _getExerciseById(repo, 'exercise-easy-run');
        await deps.workoutState.addExerciseToSession(
          easyRun,
          effortKindOverride: 'timed',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, easyRun.name);

        expect(_arrow(tester, 'Next').enabled, isFalse);
        expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        // A started timer keeps scheduling frames, so step time by hand.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(_arrow(tester, 'Next').enabled, isFalse);
        expect(
          find.widgetWithText(FilledButton, 'Log Interval'),
          findsOneWidget,
        );
      },
    );

    testWidgets('S-5113: a not-started round keeps the forward arrow dead', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final deps = await _buildDeps(modality: 'cardio_endurance');
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final roundExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      await deps.workoutState.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );

      await tester.pumpWidget(_buildSessionScreen(deps));
      await _openDetailView(tester, roundExercise.name);

      expect(_arrow(tester, 'Next').enabled, isFalse);
    });

    testWidgets(
      'S-5114: the rest chip shows pause while running and play while paused',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
        final effortId = await _seedSquatSets(deps, squat, sets: 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, squat.name);
        expect(find.text('Set 1 of 2'), findsOneWidget);
        expect(_editorNumber('reps', '10'), findsOneWidget);

        // Logging set 1 is what opens the rest and shows the chip.
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        final chip = _restChip();
        expect(chip, findsOneWidget);

        final scheme = Theme.of(tester.element(chip)).colorScheme;

        // Running: pause icon, tonal container, primary icon and digits.
        expect(_openRestIndexes(deps, effortId), [1]);
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.self_improvement), findsNothing);
        expect(_restChipFill(tester), scheme.primaryContainer);

        Icon chipIcon() => tester.widget<Icon>(
          find.descendant(of: chip, matching: find.byType(Icon)),
        );
        Text chipDigits() => tester.widget<Text>(
          find.descendant(of: chip, matching: find.byType(Text)),
        );

        expect(chipIcon().color, scheme.primary);
        expect(chipDigits().style?.color, scheme.primary);
        expect(_restChipSemantics('Pause rest'), findsOneWidget);

        final runningRect = tester.getRect(chip);

        await tester.tap(chip);
        await tester.pumpAndSettle();

        // Paused: play icon, unchanged geometry, same primary foreground.
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.play_arrow)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.pause)),
          findsNothing,
        );
        expect(_restChipSemantics('Resume rest'), findsOneWidget);
        expect(chipIcon().color, scheme.primary);
        expect(chipDigits().style?.color, scheme.primary);
        expect(tester.getRect(chip), runningRect);
      },
    );

    test(
      'S-5114: the chip foreground clears 3:1 on both fills on every theme',
      () {
        for (final theme in AppTheme.values) {
          final colors = OmniTheme.colorsForTheme(theme);
          final scheme = buildTheme(
            theme: theme,
            brightness: Brightness.dark,
            secondary: colors.secondary,
            background: colors.backgroundTop,
            surface: colors.surface,
            textPrimary: colors.textDominant,
            textSecondary: colors.textSecondary,
            divider: colors.divider,
            onPrimary: getOnPrimaryForTheme(theme),
            onSecondary: getOnSecondaryForTheme(theme),
          ).colorScheme;

          final onRunning = OmniTheme.contrastRatio(
            scheme.primary,
            scheme.primaryContainer,
          );
          final onPaused = OmniTheme.contrastRatio(
            scheme.primary,
            colors.surface,
          );
          expect(
            onRunning,
            greaterThanOrEqualTo(3.0),
            reason: '${theme.name} running fill measured $onRunning:1',
          );
          expect(
            onPaused,
            greaterThanOrEqualTo(3.0),
            reason: '${theme.name} paused fill measured $onPaused:1',
          );
        }
      },
    );

    testWidgets(
      'S-5115: the rest chip keeps its running look on the standard list view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');
        await _seedSquatSets(deps, squat, sets: 2);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, squat.name);
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        final chip = _restChip();
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        final scheme = Theme.of(tester.element(chip)).colorScheme;
        expect(_restChipFill(tester), scheme.primaryContainer);
      },
    );

    testWidgets(
      'S-5115: the rest chip keeps its running look on the rolling list view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final deps = await _buildDeps(modality: null);
        await deps.workoutState.createNewSession(isRolling: true);
        final repo = await _freshRepo();
        final squat = await _getExerciseById(repo, 'exercise-barbell-squat');

        final blockId = await deps.workoutState.addSessionBlock();
        final effortId = await _seedSquatSets(deps, squat);
        await deps.workoutState.assignEffortToBlock(effortId, blockId);
        // A rest after set 1 marks it logged and opens the chip.
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await tester.pumpAndSettle();

        final chip = _restChip();
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        final scheme = Theme.of(tester.element(chip)).colorScheme;
        expect(_restChipFill(tester), scheme.primaryContainer);
      },
    );
  });
}
