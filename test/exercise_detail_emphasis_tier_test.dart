// Tests for the exercise-detail emphasis-tier rebalance.
//
// Plan: docs/plans/exercise-detail-emphasis-tier-rebalance-plan.md
//
// Phase 1 verifies the visual hierarchy rebalance (Decision Ledger
// D-1, D-2, D-3, D-4, D-5, D-6) by pumping the two affected screens
// and asserting on the rendered widget tree:
//
//   - The round effort's live screen shows the countdown ring: the digits
//     centred in it render in `OmniTheme.colors.textDominant` with the
//     `REMAINING` caption, and the old "ROUND 1" / "PERIOD 1" heading is
//     gone (38d; S-101, S-103; S-108 keeps the routine surface).
//   - Weight `InlineMetricEditor` widgets are built with
//     `emphasisTier: MetricEmphasisTier.dominant` on every call site
//     that still shows one: resistance sets (S-105, S-110) and the
//     hold's weight row (S-106). The interval screen has no weight
//     control at all (S-106b, O-11).
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
import 'package:omnitrain/widgets/session/timer_ring.dart';

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

/// The live round screen after 38d: the ring centres the `mm:ss` digits at the
/// dominant colour, captioned `REMAINING` — the import of the round's time.
///
/// Scoped to the ring, because the round-length row below repeats the number.
void _expectRoundRing(WidgetTester tester) {
  final ring = find.byType(TimerRing);
  expect(ring, findsOneWidget);

  final digits = find.descendant(
    of: ring,
    matching: find.textContaining(':'),
  );
  expect(digits, findsOneWidget);
  expect(
    tester.widget<Text>(digits).style?.color,
    OmniTheme.colors.textDominant,
  );

  final caption = find.descendant(of: ring, matching: find.text('REMAINING'));
  expect(caption, findsOneWidget);
}

/// The round heading the ring replaced (38d, A1): gone from the live screen.
void _expectNoRoundHeading(WidgetTester tester) {
  expect(find.text('ROUND 1'), findsNothing);
  expect(find.text('PERIOD 1'), findsNothing);
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
  if ((effortKind == 'timed' || effortKind == 'drill') && seedExtraWeight) {
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
    // ── S-101: Free session round-effort ring at dominant tier (live) ─────
    //
    // Non-sports modality (free training): the old "ROUND" heading is gone,
    // so the live screen's round time is asserted through the ring.
    testWidgets(
      'S-101 free session round shows the ring with a dominant caption (live, non-sports)',
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

        _expectRoundRing(tester);
        _expectNoRoundHeading(tester);
      },
    );

    // ── S-103: Free session sports modality → same ring, caption unchanged ─
    //
    // sports modality: the same call site, no "PERIOD 1" heading any more.
    testWidgets(
      'S-103 free session sports round shows the ring with a dominant caption',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final deps = await _buildSessionDeps(
          theme: AppTheme.abyssalNeon,
          effortKind: 'round',
          modality: 'sports', // → "PERIOD" label in the sets control
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

        _expectRoundRing(tester);
        _expectNoRoundHeading(tester);
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

    // ── S-106: Hold effort — weight row at dominant tier ──────────────────
    //
    // The hold (drill) screen's only input is a full-width weight
    // `ValueStepperRow`, whose inner `InlineMetricEditor` carries
    // `metricType: 'weight'`. The row is always rendered, whether or not
    // a weight was logged (the fixture seeds one at 5.0 kg).
    testWidgets('S-106 hold effort weight row renders dominant tier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final deps = await _buildSessionDeps(
        theme: AppTheme.abyssalNeon,
        effortKind: 'drill',
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

      _expectEmphasisTierDominant(tester, 'weight');
    });

    // ── S-106b: Interval effort — the weight row is back (plan 39, A1) ────
    //
    // Interval (`timed`) work carries a weight row again, like the hold: an
    // `InlineMetricEditor` with a weight metric is built, from the value
    // seeded on the entry.
    testWidgets('S-106b interval effort renders a weight editor', (
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

      final weightEditors = tester
          .widgetList<InlineMetricEditor>(find.byType(InlineMetricEditor))
          .where(
            (e) => e.metricType == 'weight' || e.metricType == 'extra-weight',
          );
      expect(
        weightEditors,
        isNotEmpty,
        reason: 'the interval screen has a weight row again (plan 39)',
      );
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
