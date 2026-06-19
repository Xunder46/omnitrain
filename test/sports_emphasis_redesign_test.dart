import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
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
    ),
    home: home,
  );
}

Exercise _testSportsExercise() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Exercise(
    id: 'test-sports-$now',
    modality: 'sports',
    name: 'Test Sports Exercise',
    createdAtMs: now,
    updatedAtMs: now,
    capabilities: const ['time'],
  );
}

typedef _SessionDeps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  Exercise exercise,
  String effortId,
});

typedef _RoutineSetupDeps = ({
  RoutineState routineState,
  WorkoutState workoutState,
  SettingsState settingsState,
  Exercise exercise,
  String templateId,
});

Future<_SessionDeps> _buildFreeSessionDeps({required AppTheme theme}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testSportsExercise();
  await repo.createExercise(exercise);

  await workoutState.createNewSession(modality: 'sports');
  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'round',
  );

  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercise: exercise,
    effortId: effortId,
  );
}

Future<_SessionDeps> _buildRoutineSessionDeps({required AppTheme theme}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testSportsExercise();
  await repo.createExercise(exercise);

  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Sports emphasis template');
  await routineState.addExerciseToRoutine(exercise, 'round');
  await routineState.saveRoutine();
  final templateId = routineState.currentTemplate!.id;

  final manifest = await RoutineSessionService(repo).buildSessionFromTemplate(
    templateId,
  );
  await workoutState.createNewSession(
    modality: 'sports',
    routineTemplateId: templateId,
  );
  await workoutState.populateSessionFromManifest(manifest);

  final effortId = workoutState.getExercisesWithEntries().first['id'] as String;

  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercise: exercise,
    effortId: effortId,
  );
}

Future<_RoutineSetupDeps> _buildRoutineSetupDeps({required AppTheme theme}) async {
  final repo = await _freshRepo();
  final routineState = RoutineState(repo);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testSportsExercise();
  await repo.createExercise(exercise);

  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Sports setup template');
  await routineState.updateRoutineFocusModality('sports');
  await routineState.addExerciseToRoutine(exercise, 'round');
  await routineState.saveRoutine();

  return (
    routineState: routineState,
    workoutState: workoutState,
    settingsState: settingsState,
    exercise: exercise,
    templateId: routineState.currentTemplate!.id,
  );
}

Future<void> _openSessionDetail(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  final labelMatches = find.text(exerciseName);
  expect(labelMatches, findsAtLeastNWidgets(1));
  final labelFinder = labelMatches.first;
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

Future<void> _openRoutineDetail(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  final labelMatches = find.text(exerciseName);
  if (labelMatches.evaluate().isNotEmpty) {
    final labelFinder = labelMatches.first;
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
  } else {
    final cards = find.byType(ExerciseCard);
    expect(cards, findsAtLeastNWidgets(1));
    final firstCard = cards.first;
    await tester.ensureVisible(firstCard);
    await tester.tap(firstCard);
  }
  await tester.pumpAndSettle();
}

Text _statusLineText(
  WidgetTester tester, {
  required IconData icon,
  required String label,
}) {
  final iconFinder = find.byIcon(icon);
  expect(iconFinder, findsOneWidget);
  final statusRow = find.ancestor(of: iconFinder, matching: find.byType(Row));
  final labelFinder = find.descendant(of: statusRow.first, matching: find.text(label));
  expect(labelFinder, findsOneWidget);
  return tester.widget<Text>(labelFinder);
}

Finder _sessionProgressDots() {
  return find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration || decoration.shape != BoxShape.circle) {
      return false;
    }
    final margin = widget.margin;
    if (margin is! EdgeInsets) return false;
    return margin.horizontal == 12;
  });
}

void main() {
  group('Sports effort emphasis redesign', () {
    testWidgets('S-001 free session stopped hierarchy is correct', (tester) async {
      final deps = await _buildFreeSessionDeps(theme: AppTheme.abyssalNeon);
      final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);

      final periodText = tester.widget<Text>(find.text('PERIOD 1'));
      expect(periodText.style?.color, colors.textSecondary);

      final durationEditor = tester.widget<InlineMetricEditor>(
        find.byWidgetPredicate(
          (widget) =>
              widget is InlineMetricEditor && widget.metricType == 'duration',
        ),
      );
      expect(durationEditor.emphasisTier, MetricEmphasisTier.dominant);

      final stoppedText = _statusLineText(
        tester,
        icon: Icons.play_circle_outline,
        label: 'STOPPED',
      );
      expect(stoppedText.style?.color, colors.textMuted);

      final playIcon = tester.widget<Icon>(find.byIcon(Icons.play_circle_outline));
      expect(playIcon.color, colors.textMuted);

      final periodCount = tester.widget<Text>(find.text('Period 1 of 1'));
      expect(periodCount.style?.color, colors.textSecondary);

      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    testWidgets('S-002 free session running hierarchy is correct', (tester) async {
      final deps = await _buildFreeSessionDeps(theme: AppTheme.abyssalNeon);
      final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      final durationEditor = tester.widget<InlineMetricEditor>(
        find.byWidgetPredicate(
          (widget) =>
              widget is InlineMetricEditor && widget.metricType == 'duration',
        ),
      );
      expect(durationEditor.emphasisTier, MetricEmphasisTier.dominant);

      final runningText = _statusLineText(
        tester,
        icon: Icons.pause_circle_outline,
        label: 'RUNNING',
      );
      expect(runningText.style?.color, colors.textMuted);

      final pauseIcon = tester.widget<Icon>(find.byIcon(Icons.pause_circle_outline));
      expect(pauseIcon.color, colors.textMuted);
    });

    testWidgets('S-003 routine-backed session matches stopped and running hierarchy', (
      tester,
    ) async {
      final deps = await _buildRoutineSessionDeps(theme: AppTheme.abyssalNeon);
      final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);

      final periodText = tester.widget<Text>(find.text('PERIOD 1'));
      expect(periodText.style?.color, colors.textSecondary);

      final stoppedText = _statusLineText(
        tester,
        icon: Icons.play_circle_outline,
        label: 'STOPPED',
      );
      expect(stoppedText.style?.color, colors.textMuted);

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pump();

      final runningText = _statusLineText(
        tester,
        icon: Icons.pause_circle_outline,
        label: 'RUNNING',
      );
      expect(runningText.style?.color, colors.textMuted);
    });

    testWidgets('S-004 routine setup sports hierarchy is dominant+neutral', (
      tester,
    ) async {
      final deps = await _buildRoutineSetupDeps(theme: AppTheme.abyssalNeon);
      final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: RoutineSetupScreen(
            routineState: deps.routineState,
            workoutState: deps.workoutState,
              templateId: deps.templateId,
            settingsState: deps.settingsState,
          ),
        ),
      );

      await _openRoutineDetail(tester, deps.exercise.name);

      final periodText = tester.widget<Text>(find.text('PERIOD 1'));
      expect(periodText.style?.color, colors.textSecondary);

      final durationEditor = tester.widget<InlineMetricEditor>(
        find.byWidgetPredicate(
          (widget) =>
              widget is InlineMetricEditor && widget.metricType == 'duration',
        ),
      );
      expect(durationEditor.emphasisTier, MetricEmphasisTier.dominant);

      final periodCount = tester.widget<Text>(find.text('Period 1 of 1'));
      expect(periodCount.style?.color, colors.textSecondary);
    });

    testWidgets('accent appears only on current dot and primary action', (tester) async {
      final deps = await _buildFreeSessionDeps(theme: AppTheme.abyssalNeon);

      await tester.pumpWidget(
        _themeWrappedApp(
          theme: AppTheme.abyssalNeon,
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            settingsState: deps.settingsState,
            timerAlertService: FakeTimerAlertService(),
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exercise.name);
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);

      final theme = Theme.of(tester.element(find.byType(WorkoutSessionScreen)));
      final dots = _sessionProgressDots();
      expect(dots, findsAtLeastNWidgets(1));

      var accentedDots = 0;
      for (final element in dots.evaluate()) {
        final dot = element.widget as Container;
        final decoration = dot.decoration as BoxDecoration;
        if (decoration.color == theme.colorScheme.primary) {
          accentedDots += 1;
        }
      }
      expect(accentedDots, 1);
    });

    testWidgets('S-005 theme parity across free, routine-backed, and routine-setup', (
      tester,
    ) async {
      for (final themeValue in AppTheme.values) {
        final colors = OmniTheme.colorsForTheme(themeValue);

        final freeDeps = await _buildFreeSessionDeps(theme: themeValue);
        await tester.pumpWidget(
          _themeWrappedApp(
            theme: themeValue,
            home: WorkoutSessionScreen(
              workoutState: freeDeps.workoutState,
              routineState: freeDeps.routineState,
              sessionSummaryService: freeDeps.sessionSummaryService,
              settingsState: freeDeps.settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _openSessionDetail(tester, freeDeps.exercise.name);
        expect(tester.widget<Text>(find.text('PERIOD 1')).style?.color, colors.textSecondary);
        expect(
          tester
              .widget<InlineMetricEditor>(
                find.byWidgetPredicate(
                  (widget) => widget is InlineMetricEditor && widget.metricType == 'duration',
                ),
              )
              .emphasisTier,
          MetricEmphasisTier.dominant,
        );
        expect(
          _statusLineText(
            tester,
            icon: Icons.play_circle_outline,
            label: 'STOPPED',
          ).style?.color,
          colors.textMuted,
        );

        final routineSessionDeps = await _buildRoutineSessionDeps(theme: themeValue);
        await tester.pumpWidget(
          _themeWrappedApp(
            theme: themeValue,
            home: WorkoutSessionScreen(
              workoutState: routineSessionDeps.workoutState,
              routineState: routineSessionDeps.routineState,
              sessionSummaryService: routineSessionDeps.sessionSummaryService,
              settingsState: routineSessionDeps.settingsState,
              timerAlertService: FakeTimerAlertService(),
            ),
          ),
        );
        await _openSessionDetail(tester, routineSessionDeps.exercise.name);
        expect(tester.widget<Text>(find.text('PERIOD 1')).style?.color, colors.textSecondary);
        expect(
          _statusLineText(
            tester,
            icon: Icons.play_circle_outline,
            label: 'STOPPED',
          ).style?.color,
          colors.textMuted,
        );

        final setupDeps = await _buildRoutineSetupDeps(theme: themeValue);
        await tester.pumpWidget(
          _themeWrappedApp(
            theme: themeValue,
            home: RoutineSetupScreen(
              routineState: setupDeps.routineState,
              workoutState: setupDeps.workoutState,
                templateId: setupDeps.templateId,
              settingsState: setupDeps.settingsState,
            ),
          ),
        );
        await _openRoutineDetail(tester, setupDeps.exercise.name);
        expect(tester.widget<Text>(find.text('PERIOD 1')).style?.color, colors.textSecondary);
        expect(
          tester
              .widget<InlineMetricEditor>(
                find.byWidgetPredicate(
                  (widget) => widget is InlineMetricEditor && widget.metricType == 'duration',
                ),
              )
              .emphasisTier,
          MetricEmphasisTier.dominant,
        );
      }
    });
  });
}
