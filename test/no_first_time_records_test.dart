// Tests for plan 252 — no record for a first-ever exercise.
//
// Plan: docs/plans/2026-11-19-252-no-first-time-records-plan/
//
// S-25206 covers the summary's record-line text (`prLineText`):
// a strength record is labelled "est. 1RM", the reps line is
// unchanged. S-25207 covers the screen itself: the summary of a
// workout whose exercise has NO earlier finished workout renders no
// "New best" line at all (the first time is not a record).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart' show buildTheme;
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// The app's real ThemeData for the active theme, so the screen reads
/// production colour tokens (same helper as
/// `test/session_summary_effort_row_test.dart`).
ThemeData _appTheme() {
  final theme = OmniTheme.activeTheme;
  final colors = OmniTheme.colorsForTheme(theme);
  return buildTheme(
    theme: theme,
    brightness: Brightness.dark,
    secondary: colors.secondary,
    background: colors.backgroundBottom,
    surface: colors.surface,
    textPrimary: colors.textDominant,
    textSecondary: colors.textSecondary,
    divider: colors.divider,
    onPrimary: getOnPrimaryForTheme(theme),
    onSecondary: getOnSecondaryForTheme(theme),
  );
}

void main() {
  group('Plan 252 — no record for a first-ever exercise', () {
    // S-25206: the summary's record line says what the strength
    // number is (an estimated one-rep max, formatted by the injected
    // weight formatter); the reps-axis line is unchanged.
    test(
      'S-25206 prLineText labels a strength record est. 1RM and leaves reps unchanged',
      () {
        String formatWeight(double kg) => '$kg kg';

        final strengthLine = prLineText(
          PRAchievement(
            exerciseName: 'Bench',
            metricLabel: 'e1RM',
            previousBest: 100.0,
            newBest: 105.0,
          ),
          formatWeight,
        );
        expect(
          strengthLine,
          'Bench: New best est. 1RM 105.0 kg (was est. 1RM 100.0 kg)',
        );

        final repsLine = prLineText(
          PRAchievement(
            exerciseName: 'Push-Up',
            metricLabel: 'reps',
            previousBest: 18.0,
            newBest: 20.0,
          ),
          formatWeight,
        );
        expect(repsLine, 'Push-Up: New best 20 reps (was 18 reps)');
      },
    );

    // S-25207: the summary screen of a first-ever workout (no earlier
    // finished workout holds the exercise) shows no "New best" line —
    // the first time is not a record. Mock repository only; every
    // write happens before pumpWidget.
    testWidgets(
      'S-25207 the summary of a first-ever workout shows no New best line',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // A finished session holding one loaded set (100 kg × 5) for
        // an exercise with NO earlier finished workout.
        final startedAtMs = DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        final endedAtMs = startedAtMs + 45 * 60000;
        await repo.createSession(
          TrainingSession(
            id: 's-first',
            ownerUserId: 'u-1',
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            modality: Modality.resistanceLifting,
            createdAtMs: startedAtMs,
            updatedAtMs: endedAtMs,
          ),
        );
        await repo.createSegment(
          SessionSegment(
            id: 'seg-s-first',
            sessionId: 's-first',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createEffort(
          SegmentEffort(
            id: 'eff-s-first',
            segmentId: 'seg-s-first',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: ex.id,
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-first-0-reps',
            effortId: 'eff-s-first',
            metricId: 'metric-reps',
            valueInt: 5,
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-first-0-weight',
            effortId: 'eff-s-first',
            metricId: 'metric-weight',
            valueReal: 100.0,
            createdAtMs: startedAtMs + 1,
            updatedAtMs: startedAtMs + 1,
          ),
        );

        final workoutState = WorkoutState(repo);
        await workoutState.loadHistoricalSession('s-first');

        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await settingsState.setShowFeelingSurvey(false);

        await tester.pumpWidget(
          MaterialApp(
            theme: _appTheme(),
            home: SessionSummaryScreen(
              workoutState: workoutState,
              routineState: RoutineState(repo),
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
              openedFromCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('New best'), findsNothing);
      },
    );

    // S-25207b: the summary screen of a workout whose exercise HAS an
    // earlier finished workout with a LOWER best renders exactly one
    // record line labelled "est. 1RM" with the previous best. This
    // guards the wiring: a screen that reverted to unlabelled inline
    // text (or stopped reading PR achievements) fails here even
    // though S-25207 stays green.
    testWidgets(
      'S-25207b the summary of a beaten earlier best shows exactly one New best est. 1RM line',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // An earlier finished session (7 days before today's) holding
        // one loaded set (100 kg × 5, e1RM ≈ 116.7 kg).
        final earlierStartMs = DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch;
        final earlierEndMs = earlierStartMs + 45 * 60000;
        await repo.createSession(
          TrainingSession(
            id: 's-earlier',
            ownerUserId: 'u-1',
            startedAtMs: earlierStartMs,
            endedAtMs: earlierEndMs,
            modality: Modality.resistanceLifting,
            createdAtMs: earlierStartMs,
            updatedAtMs: earlierEndMs,
          ),
        );
        await repo.createSegment(
          SessionSegment(
            id: 'seg-s-earlier',
            sessionId: 's-earlier',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: earlierStartMs,
            updatedAtMs: earlierStartMs,
          ),
        );
        await repo.createEffort(
          SegmentEffort(
            id: 'eff-s-earlier',
            segmentId: 'seg-s-earlier',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: ex.id,
            createdAtMs: earlierStartMs,
            updatedAtMs: earlierStartMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-earlier-0-reps',
            effortId: 'eff-s-earlier',
            metricId: 'metric-reps',
            valueInt: 5,
            createdAtMs: earlierStartMs,
            updatedAtMs: earlierStartMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-earlier-0-weight',
            effortId: 'eff-s-earlier',
            metricId: 'metric-weight',
            valueReal: 100.0,
            createdAtMs: earlierStartMs + 1,
            updatedAtMs: earlierStartMs + 1,
          ),
        );

        // Today's finished session holding one loaded set (105 kg × 5,
        // e1RM ≈ 122.5 kg) — above the earlier best.
        final startedAtMs = DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch;
        final endedAtMs = startedAtMs + 45 * 60000;
        await repo.createSession(
          TrainingSession(
            id: 's-latest',
            ownerUserId: 'u-1',
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            modality: Modality.resistanceLifting,
            createdAtMs: startedAtMs,
            updatedAtMs: endedAtMs,
          ),
        );
        await repo.createSegment(
          SessionSegment(
            id: 'seg-s-latest',
            sessionId: 's-latest',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createEffort(
          SegmentEffort(
            id: 'eff-s-latest',
            segmentId: 'seg-s-latest',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: ex.id,
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-latest-0-reps',
            effortId: 'eff-s-latest',
            metricId: 'metric-reps',
            valueInt: 5,
            createdAtMs: startedAtMs,
            updatedAtMs: startedAtMs,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-eff-s-latest-0-weight',
            effortId: 'eff-s-latest',
            metricId: 'metric-weight',
            valueReal: 105.0,
            createdAtMs: startedAtMs + 1,
            updatedAtMs: startedAtMs + 1,
          ),
        );

        final workoutState = WorkoutState(repo);
        await workoutState.loadHistoricalSession('s-latest');

        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
        await settingsState.setShowFeelingSurvey(false);

        await tester.pumpWidget(
          MaterialApp(
            theme: _appTheme(),
            home: SessionSummaryScreen(
              workoutState: workoutState,
              routineState: RoutineState(repo),
              sessionSummaryService: SessionSummaryService(repo),
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
              openedFromCalendar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('New best est. 1RM'), findsOneWidget);
        expect(find.textContaining('(was est. 1RM'), findsOneWidget);
      },
    );
  });
}
