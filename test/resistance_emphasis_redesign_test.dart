import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Widget _themeWrappedApp({required Widget home, required AppTheme theme}) {
  final colors = OmniTheme.colorsForTheme(theme);
  return MaterialApp(
    theme: buildTheme(
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
    ),
    home: home,
  );
}

typedef _SessionDeps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  Exercise exercise,
});

String _modalityForEffortKind(String effortKind) {
  switch (effortKind) {
    case 'timed':
      return 'cardio_endurance';
    case 'round':
      return 'sports';
    case 'drill':
      return 'isometric_stretching';
    case 'set':
    default:
      return 'resistance_lifting';
  }
}

Exercise _pickExercise(List<Exercise> exercises, String effortKind) {
  switch (effortKind) {
    case 'set':
      return exercises.firstWhere(
        (e) =>
            e.capabilities.contains('sets') &&
            e.capabilities.contains('load') &&
            e.capabilities.contains('reps'),
        orElse: () => exercises.first,
      );
    case 'timed':
      return exercises.firstWhere(
        (e) => e.capabilities.contains('time'),
        orElse: () => exercises.first,
      );
    case 'round':
      return exercises.firstWhere(
        (e) => e.capabilities.contains('rounds'),
        orElse: () => exercises.first,
      );
    case 'drill':
      return exercises.firstWhere(
        (e) => e.capabilities.contains('hold'),
        orElse: () => exercises.first,
      );
    default:
      return exercises.first;
  }
}

Future<_SessionDeps> _buildSessionDeps({
  required AppTheme theme,
  required String effortKind,
  String? intent,
  bool seedSetValues = true,
}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  await workoutState.createNewSession(
    modality: _modalityForEffortKind(effortKind),
    intent: intent,
  );

  final exercises = await repo.getExercises();
  final exercise = _pickExercise(exercises, effortKind);

  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );

  // Ensure there is a second entry to navigate into for previous-set absence tests.
  await workoutState.addEntry(effortId);

  if (effortKind == 'set' && seedSetValues) {
    await workoutState.updateEntryValue(effortId, 0, 'reps', 10);
    await workoutState.updateEntryValue(effortId, 0, 'weight', 80.0);
  }

  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercise: exercise,
  );
}

Future<void> _openSessionDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelFinder = find.text(exerciseName).first;
  await tester.ensureVisible(labelFinder);
  final rowTapTarget = find.ancestor(
    of: labelFinder,
    matching: find.byType(InkWell),
  );
  if (rowTapTarget.evaluate().isNotEmpty) {
    final rowInkWell = tester.widget<InkWell>(rowTapTarget.first);
    expect(rowInkWell.onTap, isNotNull);
    rowInkWell.onTap!.call();
  } else {
    await tester.tap(labelFinder);
  }
  await tester.pumpAndSettle();
}

List<Color> _progressDotColors(WidgetTester tester) {
  final dotContainers = tester.widgetList<Container>(
    find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final width = widget.constraints?.minWidth;
      final height = widget.constraints?.minHeight;
      if ((width != 10 && width != 14) || (height != 10 && height != 14)) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.shape == BoxShape.circle &&
          decoration.color != null;
    }),
  );

  return dotContainers
      .map((container) => (container.decoration as BoxDecoration).color!)
      .toList();
}

typedef _RoutineDeps = ({
  RoutineState routineState,
  WorkoutState workoutState,
  SettingsState settingsState,
  String templateId,
  Exercise exercise,
  String effortKind,
});

Future<_RoutineDeps> _buildRoutineSetupDeps({
  required AppTheme theme,
  required String effortKind,
}) async {
  final repo = await _freshRepo();
  final routineState = RoutineState(repo);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Emphasis Routine');
  await workoutState.loadAllExercises();

  final exercises = await repo.getExercises();
  final exercise = _pickExercise(exercises, effortKind);

  final effortId = await routineState.addExerciseToRoutine(
    exercise,
    effortKind,
  );
  if (effortKind == 'set') {
    await routineState.setTargetValue(
      effortId,
      MetricIds.reps,
      MetricIds.unitReps,
      setIndex: 0,
      targetInt: 10,
    );
    await routineState.setTargetValue(
      effortId,
      MetricIds.weight,
      MetricIds.unitKg,
      setIndex: 0,
      targetMin: 80.0,
    );
  }
  await routineState.saveRoutine();

  return (
    routineState: routineState,
    workoutState: workoutState,
    settingsState: settingsState,
    templateId: routineState.currentTemplate!.id,
    exercise: exercise,
    effortKind: effortKind,
  );
}

Future<void> _openRoutineDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelFinder = find.text(exerciseName).first;
  await tester.ensureVisible(labelFinder);
  final rowTapTarget = find.ancestor(
    of: labelFinder,
    matching: find.byType(InkWell),
  );
  final rowInkWell = tester.widget<InkWell>(rowTapTarget.first);
  expect(rowInkWell.onTap, isNotNull);
  rowInkWell.onTap!.call();
  await tester.pumpAndSettle();
}

Future<void> _triggerRoutineAddSet(WidgetTester tester) async {
  final addSetInkWell = tester.widget<InkWell>(
    find.byKey(const Key('routine-add-set')),
  );
  expect(addSetInkWell.onTap, isNotNull);
  addSetInkWell.onTap!.call();
  await tester.pumpAndSettle();
}

Future<void> _triggerLogSet(WidgetTester tester) async {
  final logSetButton = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Log Set'),
  );
  expect(logSetButton.onPressed, isNotNull);
  logSetButton.onPressed!.call();
  await tester.pumpAndSettle();
}

void _expectDotColors(
  WidgetTester tester,
  ThemeData theme, {
  required int primaryCount,
  int minNeutralCount = 1,
}) {
  final dotColors = _progressDotColors(tester);
  expect(
    dotColors.where((c) => c == theme.colorScheme.primary).length,
    primaryCount,
  );
  expect(
    dotColors
        .where(
          (c) =>
              c == theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
        )
        .length,
    greaterThanOrEqualTo(minNeutralCount),
  );
}

int _primaryDotCount(WidgetTester tester, ThemeData theme) {
  final dotColors = _progressDotColors(tester);
  return dotColors.where((c) => c == theme.colorScheme.primary).length;
}

void main() {
  group('Resistance emphasis redesign', () {
    testWidgets(
      'session detail uses neutral add-set icon, first tap adds set, and logged dots are primary',
      (tester) async {
        final deps = await _buildSessionDeps(
          theme: AppTheme.abyssalNeon,
          effortKind: 'set',
        );

        await tester.pumpWidget(
          _themeWrappedApp(
            theme: AppTheme.abyssalNeon,
            home: WorkoutSessionScreen(
              workoutState: deps.workoutState,
              routineState: deps.routineState,
              sessionSummaryService: deps.sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: deps.settingsState,
            ),
          ),
        );

        await _openSessionDetail(tester, deps.exercise.name);

        final theme = Theme.of(
          tester.element(find.byType(WorkoutSessionScreen)),
        );

        final addSetIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byTooltip('Add set'),
            matching: find.byIcon(Icons.add),
          ),
        );
        expect(
          addSetIcon.color,
          theme.colorScheme.onSurface.withAlpha((0.35 * 255).round()),
        );

        expect(find.widgetWithText(FilledButton, 'Log Set'), findsOneWidget);
        _expectDotColors(tester, theme, primaryCount: 0, minNeutralCount: 2);

        await tester.tap(find.byTooltip('Add set'));
        await tester.pumpAndSettle();
        expect(find.textContaining('of 3'), findsOneWidget);

        // Log the first set; logged dots should switch to primary while
        // unlogged dots remain neutral.
        await _triggerLogSet(tester);
        _expectDotColors(tester, theme, primaryCount: 1);
      },
    );

    testWidgets('skipped set dot is treated as completed and rendered primary', (
      tester,
    ) async {
      final deps = await _buildSessionDeps(
        theme: AppTheme.abyssalNeon,
        effortKind: 'set',
        seedSetValues: false,
      );

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: deps.settingsState,
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);
      final theme = Theme.of(tester.element(find.byType(WorkoutSessionScreen)));

      // Skip first set by logging with zero reps; dot 1 should become primary.
      await _triggerLogSet(tester);
      _expectDotColors(tester, theme, primaryCount: 1);
    });

    testWidgets('reps and weight both render dominant in session detail', (
      tester,
    ) async {
      // Plan: .github/agents/plans/exercise-detail-emphasis-tier-rebalance-plan.md
      // Weight is now a primary data input (D-2), equal in tier and
      // color to reps.  The old "weight is subordinate to reps"
      // assumption from the original resistance-emphasis redesign
      // no longer holds.
      final deps = await _buildSessionDeps(
        theme: AppTheme.abyssalNeon,
        effortKind: 'set',
      );

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: deps.settingsState,
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);

      final repsTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(InlineMetricEditor).at(0),
          matching: find.byType(Text),
        ),
      );
      final weightTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(InlineMetricEditor).at(1),
          matching: find.byType(Text),
        ),
      );

      final repsValueText = repsTexts.first;
      final weightValueText = weightTexts.first;

      // Both figures share the same emphasis tier (D-2/D-3): the
      // same display font, the same size, and the same color.
      expect(repsValueText.style?.fontSize, weightValueText.style?.fontSize);
      expect(repsValueText.style?.color, OmniTheme.colors.textDominant);
      expect(weightValueText.style?.color, OmniTheme.colors.textDominant);
    });

    testWidgets(
      'previous set line is absent for set timed round drill on session and routine setup surfaces',
      (tester) async {
        for (final effortKind in const ['set', 'timed', 'round', 'drill']) {
          final sessionDeps = await _buildSessionDeps(
            theme: AppTheme.abyssalNeon,
            effortKind: effortKind,
          );

          await tester.pumpWidget(
            _themeWrappedApp(
              theme: AppTheme.abyssalNeon,
              home: WorkoutSessionScreen(
                workoutState: sessionDeps.workoutState,
                routineState: sessionDeps.routineState,
                sessionSummaryService: sessionDeps.sessionSummaryService,
                timerAlertService: FakeTimerAlertService(),
                settingsState: sessionDeps.settingsState,
              ),
            ),
          );

          await _openSessionDetail(tester, sessionDeps.exercise.name);
          await tester.tap(find.byIcon(Icons.arrow_forward).last);
          await tester.pumpAndSettle();
          expect(find.textContaining('Previous:'), findsNothing);

          final routineDeps = await _buildRoutineSetupDeps(
            theme: AppTheme.abyssalNeon,
            effortKind: effortKind,
          );
          await tester.pumpWidget(
            _themeWrappedApp(
              theme: AppTheme.abyssalNeon,
              home: RoutineSetupScreen(
                routineState: routineDeps.routineState,
                workoutState: routineDeps.workoutState,
                templateId: routineDeps.templateId,
                settingsState: routineDeps.settingsState,
              ),
            ),
          );

          await _openRoutineDetail(tester, routineDeps.exercise.name);
          await _triggerRoutineAddSet(tester);
          expect(find.textContaining('Previous:'), findsNothing);
        }
      },
    );

    testWidgets(
      'all six themes keep neutral controls, remove tracking chip, and apply logged-dot semantics',
      (tester) async {
        for (final themeValue in AppTheme.values) {
          final freeDeps = await _buildSessionDeps(
            theme: themeValue,
            effortKind: 'set',
          );
          await tester.pumpWidget(
            _themeWrappedApp(
              theme: themeValue,
              home: WorkoutSessionScreen(
                workoutState: freeDeps.workoutState,
                routineState: freeDeps.routineState,
                sessionSummaryService: freeDeps.sessionSummaryService,
                timerAlertService: FakeTimerAlertService(),
                settingsState: freeDeps.settingsState,
              ),
            ),
          );
          await _openSessionDetail(tester, freeDeps.exercise.name);
          final freeTheme = Theme.of(
            tester.element(find.byType(WorkoutSessionScreen)),
          );
          final freeAddSet = tester.widget<Icon>(
            find.descendant(
              of: find.byTooltip('Add set'),
              matching: find.byIcon(Icons.add),
            ),
          );
          expect(
            freeAddSet.color,
            freeTheme.colorScheme.onSurface.withAlpha((0.35 * 255).round()),
          );
          _expectDotColors(
            tester,
            freeTheme,
            primaryCount: 0,
            minNeutralCount: 2,
          );
          await _triggerLogSet(tester);
          _expectDotColors(tester, freeTheme, primaryCount: 1);

          final routineSessionDeps = await _buildSessionDeps(
            theme: themeValue,
            effortKind: 'set',
            intent: 'routine',
          );
          await tester.pumpWidget(
            _themeWrappedApp(
              theme: themeValue,
              home: WorkoutSessionScreen(
                workoutState: routineSessionDeps.workoutState,
                routineState: routineSessionDeps.routineState,
                sessionSummaryService: routineSessionDeps.sessionSummaryService,
                timerAlertService: FakeTimerAlertService(),
                settingsState: routineSessionDeps.settingsState,
              ),
            ),
          );
          await _openSessionDetail(tester, routineSessionDeps.exercise.name);
          final routineTheme = Theme.of(
            tester.element(find.byType(WorkoutSessionScreen)),
          );
          final routinePrimaryBeforeLog = _primaryDotCount(
            tester,
            routineTheme,
          );
          _expectDotColors(
            tester,
            routineTheme,
            primaryCount: routinePrimaryBeforeLog,
            minNeutralCount: 1,
          );
          await _triggerLogSet(tester);
          _expectDotColors(
            tester,
            routineTheme,
            primaryCount: routinePrimaryBeforeLog + 1,
            minNeutralCount: 0,
          );

          final routineSetupDeps = await _buildRoutineSetupDeps(
            theme: themeValue,
            effortKind: 'set',
          );
          await tester.pumpWidget(
            _themeWrappedApp(
              theme: themeValue,
              home: RoutineSetupScreen(
                routineState: routineSetupDeps.routineState,
                workoutState: routineSetupDeps.workoutState,
                templateId: routineSetupDeps.templateId,
                settingsState: routineSetupDeps.settingsState,
              ),
            ),
          );
          await _openRoutineDetail(tester, routineSetupDeps.exercise.name);
          await _triggerRoutineAddSet(tester);
          expect(find.textContaining('of 2'), findsOneWidget);

          final setupTheme = Theme.of(
            tester.element(find.byType(RoutineSetupScreen)),
          );
          final setupAddSet = tester.widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('routine-add-set')),
              matching: find.byIcon(Icons.add),
            ),
          );
          expect(
            setupAddSet.color,
            setupTheme.colorScheme.onSurface.withAlpha((0.35 * 255).round()),
          );
          _expectDotColors(
            tester,
            setupTheme,
            primaryCount: 0,
            minNeutralCount: 2,
          );

          // Tracking chip was removed from routine detail view.
          expect(find.text('Track by Reps & Sets'), findsNothing);
        }
      },
    );
  });
}
