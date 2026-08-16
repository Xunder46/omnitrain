// Tests for the exercise-detail emphasis-tier rebalance.
//
// Plan: .github/agents/plans/exercise-detail-emphasis-tier-rebalance-plan.md
//
// Phase 1 verifies the visual hierarchy rebalance (Decision Ledger
// D-1, D-2, D-3, D-4, D-5, D-6) by pumping the two affected screens
// and asserting on the rendered widget tree:
//
//   - The big "ROUND 1" / "PERIOD 1" header renders in
//     `OmniTheme.colors.textSecondary` on every surface and every mode
//     where it appears (S-101, S-103, S-108).
//   - Weight and extra-weight `InlineMetricEditor` widgets are built
//     with `emphasisTier: MetricEmphasisTier.dominant` on every
//     call site (S-105, S-106, S-110).
//
// Out of scope (per the plan): reps, duration, RPE, status text, the
// "Weight adjustment" button label, the small "Round X of Y"
// progress label, and the theme contract itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

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

InlineMetricEditor _editorFor(WidgetTester tester, String metricType) {
  return tester
      .widgetList<InlineMetricEditor>(find.byType(InlineMetricEditor))
      .firstWhere((e) => e.metricType == metricType);
}

void _expectRoundHeaderColor(WidgetTester tester, String expectedLabel) {
  final textWidget = tester.widget<Text>(find.text(expectedLabel));
  expect(textWidget.style?.color, OmniTheme.colors.textSecondary);
}

void _expectEmphasisTierDominant(WidgetTester tester, String metricType) {
  final editor = _editorFor(tester, metricType);
  expect(
    editor.emphasisTier,
    MetricEmphasisTier.dominant,
    reason: '$metricType InlineMetricEditor must render at dominant tier',
  );
}

// ── Session-detail builders ──────────────────────────────────────────────

typedef _SessionDeps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  String exerciseName,
});

Future<_SessionDeps> _buildSessionDeps({
  required AppTheme theme,
  required String effortKind,
  String? modality,
  String? intent,
  bool forceFree = false,
  bool seedSetValues = true,
  bool seedExtraWeight = false,
  double extraWeightKg = 5.0,
}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  // `forceFree` lets a test pin the session modality to `null` even
  // when the effort kind's default mapping would set a non-null
  // modality.  We can't pass `null` directly through the
  // `modality:` parameter because the `?? _modalityForEffortKind(...)`
  // default would replace it — `forceFree` is the explicit override.
  final resolvedModality = forceFree
      ? null
      : (modality ?? _modalityForEffortKind(effortKind));
  await workoutState.createNewSession(
    modality: resolvedModality,
    intent: intent,
  );

  final exercises = await repo.getExercises();
  final exercise = switch (effortKind) {
    'set' => exercises.firstWhere(
      (e) =>
          e.capabilities.contains('sets') &&
          e.capabilities.contains('load') &&
          e.capabilities.contains('reps'),
      orElse: () => exercises.first,
    ),
    'timed' => exercises.firstWhere(
      (e) => e.capabilities.contains('time'),
      orElse: () => exercises.first,
    ),
    'round' => exercises.firstWhere(
      (e) => e.capabilities.contains('rounds'),
      orElse: () => exercises.first,
    ),
    'drill' => exercises.firstWhere(
      (e) => e.capabilities.contains('hold'),
      orElse: () => exercises.first,
    ),
    _ => exercises.first,
  };

  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );

  // Second entry so previous-set / count flow has something to render
  // and the test is consistent with the rest of the session-detail
  // test suite.
  await workoutState.addEntry(effortId);

  if (effortKind == 'set' && seedSetValues) {
    await workoutState.updateEntryValue(effortId, 0, 'reps', 10);
    await workoutState.updateEntryValue(effortId, 0, 'weight', 80.0);
  }
  if (effortKind == 'timed' && seedExtraWeight) {
    await workoutState.updateEntryValue(
      effortId,
      0,
      'extra-weight',
      extraWeightKg,
    );
  }

  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exerciseName: exercise.name,
  );
}

// ── Routine-setup builders ──────────────────────────────────────────────

typedef _RoutineDeps = ({
  RoutineState routineState,
  WorkoutState workoutState,
  SettingsState settingsState,
  String templateId,
  String exerciseName,
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
  final exercise = switch (effortKind) {
    'set' => exercises.firstWhere(
      (e) =>
          e.capabilities.contains('sets') &&
          e.capabilities.contains('load') &&
          e.capabilities.contains('reps'),
      orElse: () => exercises.first,
    ),
    'timed' => exercises.firstWhere(
      (e) => e.capabilities.contains('time'),
      orElse: () => exercises.first,
    ),
    'round' => exercises.firstWhere(
      (e) => e.capabilities.contains('rounds'),
      orElse: () => exercises.first,
    ),
    'drill' => exercises.firstWhere(
      (e) => e.capabilities.contains('hold'),
      orElse: () => exercises.first,
    ),
    _ => exercises.first,
  };

  final effortId = await routineState.addExerciseToRoutine(
    exercise,
    effortKind,
  );
  if (effortKind == 'set') {
    // Weight is in canonical kg.
    await routineState.setTargetValue(
      effortId,
      'metric-reps',
      'unit-reps',
      setIndex: 0,
      targetInt: 10,
    );
    await routineState.setTargetValue(
      effortId,
      'metric-weight',
      'unit-kg',
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
    exerciseName: exercise.name,
  );
}

// ── Tests ────────────────────────────────────────────────────────────────

void main() {
  group('Exercise-detail emphasis-tier rebalance', () {
    // ── S-101: Free session round-effort header at textSecondary (live) ───
    //
    // Non-sports modality (free training) so the label reads "ROUND",
    // not "PERIOD". Verifies the live-mode round header.
    testWidgets(
      'S-101 free session round header renders textSecondary (live, non-sports)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final deps = await _buildSessionDeps(
          theme: AppTheme.abyssalNeon,
          effortKind: 'round',
          forceFree: true, // modality=null → "ROUND" label
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

        await _openSessionDetail(tester, deps.exerciseName);

        _expectRoundHeaderColor(tester, 'ROUND 1');
      },
    );

    // ── S-103: Free session sports modality → "PERIOD 1" at textSecondary ─
    //
    // sports modality → "PERIOD" label. Verifies the same call site
    // is correct under the discriminator branch.
    testWidgets(
      'S-103 free session sports round header reads PERIOD at textSecondary',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final deps = await _buildSessionDeps(
          theme: AppTheme.abyssalNeon,
          effortKind: 'round',
          modality: 'sports', // → "PERIOD" label
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

        await _openSessionDetail(tester, deps.exerciseName);

        _expectRoundHeaderColor(tester, 'PERIOD 1');
      },
    );

    // ── S-105: Resistance effort — weight value at dominant tier (live) ───
    testWidgets(
      'S-105 resistance set effort weight renders dominant tier (live)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
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

        await _openSessionDetail(tester, deps.exerciseName);

        _expectEmphasisTierDominant(tester, 'weight');
        // Reps is also dominant (unchanged); assert it explicitly so a
        // future regression that drops it cannot sneak through this
        // scenario.
        _expectEmphasisTierDominant(tester, 'reps');
      },
    );

    // ── S-106: Cardio effort — extra-weight at dominant tier ──────────────
    //
    // The "Weight adjustment" chip is expanded by default because
    // `currentValue > 0` (seeded at 5.0 kg), so the extra-weight
    // InlineMetricEditor is present in the widget tree.
    testWidgets('S-106 cardio effort extra-weight renders dominant tier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final deps = await _buildSessionDeps(
        theme: AppTheme.abyssalNeon,
        effortKind: 'timed',
        seedExtraWeight: true,
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

      await _openSessionDetail(tester, deps.exerciseName);

      _expectEmphasisTierDominant(tester, 'extra-weight');
    });

    // ── S-108: Routine creation — resistance weight at dominant tier ──────
    //
    // Uses the default surface size (800×600) because the routine
    // setup screen's set-control row needs more horizontal room than
    // the narrower 400×1000 surface the session tests use.
    testWidgets('S-108 routine setup resistance weight renders dominant tier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      final deps = await _buildRoutineSetupDeps(
        theme: AppTheme.abyssalNeon,
        effortKind: 'set',
      );

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

      await _openRoutineDetail(tester, deps.exerciseName);

      _expectEmphasisTierDominant(tester, 'weight');
      _expectEmphasisTierDominant(tester, 'reps');
    });

    // ── S-110: Edit mode — weight value at dominant tier ──────────────────
    testWidgets('S-110 edit mode resistance set weight renders dominant tier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
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
            editMode: true,
          ),
        ),
      );

      await _openSessionDetail(tester, deps.exerciseName);

      _expectEmphasisTierDominant(tester, 'weight');
    });
  });
}
