// filepath: test/unified_rest_overlay_test.dart
//
// Tests for the unified rest-overlay visibility rule.
//
// The previous behavior had the list view (session-detail) and the detail view
// (per-exercise) disagreeing about whether a rest chip should be displayed
// while an effort timer was running anywhere in the session. After the fix,
// both surfaces route through a single helper that returns
// `openRest && no-effort-running-anywhere`, so the chip is always shown
// identically on every screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Shared helpers ──────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Suppress first-run coach-mark sheets that interfere with finder assertions.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
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

Widget _buildSessionScreen(_Deps deps) {
  return MaterialApp(
    home: WorkoutSessionScreen(
      workoutState: deps.workoutState,
      routineState: deps.routineState,
      sessionSummaryService: deps.sessionSummaryService,
      timerAlertService: FakeTimerAlertService(),
      settingsState: deps.settingsState,
    ),
  );
}

Future<void> _openDetailView(WidgetTester tester, String exerciseName) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(exerciseName));
  await tester.pumpAndSettle();
}

Future<void> _returnToListView(WidgetTester tester) async {
  // The header back button switches _showListView from false → true. The
  // test pumps a MaterialApp(home: WorkoutSessionScreen) so a stray
  // Navigator.maybePop() is a harmless no-op.
  final back = find.byIcon(Icons.arrow_back).first;
  await tester.tap(back);
  await tester.pumpAndSettle();
}

/// Locate the rest-overlay chip's elapsed text (the only `Text` inside the
/// rest chip's `Row`). Returns null if the chip is not on screen.
String? _restChipElapsed(WidgetTester tester) {
  final chipFinder = find.byKey(const Key('rest-overlay-chip'));
  if (chipFinder.evaluate().isEmpty) return null;
  final textFinder = find.descendant(
    of: chipFinder,
    matching: find.byType(Text),
  );
  if (textFinder.evaluate().isEmpty) return null;
  return (tester.widget<Text>(textFinder).data);
}

void main() {
  group('Unified rest overlay rule', () {
    testWidgets(
      'S-001: list view hides the rest chip when any effort is running',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);
        // Open a rest for round 1 (the next entry after round 0).
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await tester.pumpAndSettle();

        // On the LIST view with no timer running, the chip must be visible.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should appear on list view with an open rest',
        );

        // Switch to DETAIL view, start round 1's timer.
        await _openDetailView(tester, roundExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // Switch back to the LIST view. Chip must be hidden.
        await _returnToListView(tester);
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'list view must hide the rest chip whenever any effort is '
              'actively running in the session',
        );
      },
    );

    testWidgets(
      'S-002: detail view hides the rest chip when any effort is running',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();

        // Sanity: chip is currently visible (no timer running yet).
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should be visible before the timer is started',
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'detail view must hide the rest chip when any effort is '
              'actively running in the session',
        );
      },
    );

    testWidgets(
      'S-002b: cross-effort — list view hides the chip for A\'s open rest while B\'s timer is running',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        // Exercise A: set-kind. Record an open rest for entry 1.
        final effortA = await deps.workoutState.addExerciseToSession(
          setExercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortA);
        await deps.workoutState.recordRestStart(effortA, 1);

        // Exercise B: round-kind. No rest.
        final effortB = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );

        await tester.pumpWidget(_buildSessionScreen(deps));
        await tester.pumpAndSettle();

        // Sanity: list view shows the chip (A's rest is open, no timer).
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should appear on list view with A\'s open rest',
        );

        // Open B's detail view. Default landing is B's first round
        // (entryIndex 0). Start B's round timer.
        await tester.tap(find.text(roundExercise.name));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(FilledButton, 'Start'),
          findsOneWidget,
          reason:
              'sanity: detail view must show a Start button for B\'s '
              'first round',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // The detail view must not show the chip while B's timer is
        // running.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'detail view must hide the chip while B\'s round timer is '
              'running (session-wide rule)',
        );

        // Navigate back to the LIST view. A's rest is still open in the
        // data layer (closeAllOpenRests only closes B's). Under the unified
        // session-wide rule the chip must also be hidden here. Under the
        // old per-entry list-view rule the chip would still be visible.
        await _returnToListView(tester);
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'list view must hide the chip for A\'s open rest while B\'s '
              'timer is running (unified session-wide rule)',
        );

        // Sanity: A's rest is still in the data layer — confirms that the
        // chip is hidden by the UI rule, not because the data was cleared.
        final openA = deps.workoutState
            .getEntryRests(effortA)
            .where((r) => r.restEndMs == null);
        expect(
          openA,
          isNotEmpty,
          reason:
              'A\'s open rest must remain in the data so the chip can '
              'reappear when B\'s timer ends — only the UI hide changes',
        );

        // End B's round directly via the state so the test environment is
        // tidy (not required for the assertions above, which are now
        // satisfied).
        await deps.workoutState.endRoundEarly(effortB, 0);
      },
    );

    testWidgets(
      'S-003: both surfaces show the chip with the same elapsed text when no effort is running',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final setExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('reps'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          setExercise,
          chosenMetric: 'reps',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await tester.pumpAndSettle();

        // Capture list-view chip text.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should appear on list view',
        );
        final listText = _restChipElapsed(tester)!;

        // Switch to detail view; capture chip text.
        await _openDetailView(tester, setExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should appear on detail view too',
        );
        final detailText = _restChipElapsed(tester)!;

        expect(
          listText,
          detailText,
          reason:
              'both surfaces must render the same elapsed text for the '
              'same session state',
        );
      },
    );

    testWidgets(
      'S-004: both surfaces hide the chip identically when the entry\'s effort is running',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // Detail view: chip hidden because the entry's effort is running.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason: 'detail view must hide the chip when effort is running',
        );

        // Switch to list view: chip must also be hidden (parity).
        await _returnToListView(tester);
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'list view must hide the chip with the same rule as the '
              'detail view (unified rule)',
        );
      },
    );

    testWidgets('S-005: logging a set closes the open rest for that entry', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      final deps = await _buildDeps(modality: 'resistance_lifting');

      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final setExercise = exercises.firstWhere(
        (e) => e.capabilities.contains('reps'),
      );

      final effortId = await deps.workoutState.addExerciseToSession(
        setExercise,
        chosenMetric: 'reps',
      );
      await deps.workoutState.addEntry(effortId);

      await tester.pumpWidget(_buildSessionScreen(deps));
      await tester.pumpAndSettle();
      await _openDetailView(tester, setExercise.name);

      // First Log Set on entry 0 opens a rest for entry 1.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      final restAfterFirstLog = deps.workoutState
          .getEntryRests(effortId)
          .firstWhere((r) => r.entryIndex == 1);
      expect(
        restAfterFirstLog.restEndMs,
        isNull,
        reason: 'sanity: after logging entry 0, rest for entry 1 must be open',
      );

      // Second Log Set (now on entry 1) must close the rest for entry 1.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pumpAndSettle();

      final rests = deps.workoutState.getEntryRests(effortId);
      final openForEntry1 = rests.where(
        (r) => r.entryIndex == 1 && r.restEndMs == null,
      );
      expect(
        openForEntry1,
        isEmpty,
        reason:
            'the second Log Set must close the rest for entry 1 (the '
            'just-logged entry)',
      );
    });

    testWidgets(
      'S-006: starting a round closes the open rest for that effort',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'resistance_lifting');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final roundExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('rounds'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          roundExercise,
          effortKindOverride: 'round',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, roundExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();

        // Sanity: chip is present, rest is open.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'sanity: chip should appear before Start is tapped',
        );
        final openBefore = deps.workoutState
            .getEntryRests(effortId)
            .where((r) => r.restEndMs == null);
        expect(openBefore, isNotEmpty);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // The rest should now be closed.
        final rests = deps.workoutState.getEntryRests(effortId);
        final openAfter = rests.where((r) => r.restEndMs == null);
        expect(
          openAfter,
          isEmpty,
          reason: 'starting a round must close any open rest for that effort',
        );

        // Chip must be hidden because the timer for that entry is running.
        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'detail view must hide the chip once the round\'s effort is '
              'actively running',
        );
      },
    );

    testWidgets(
      'S-007: starting a timed effort closes the open rest for that effort',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        final deps = await _buildDeps(modality: 'cardio_endurance');

        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final timedExercise = exercises.firstWhere(
          (e) => e.capabilities.contains('time'),
        );

        final effortId = await deps.workoutState.addExerciseToSession(
          timedExercise,
          effortKindOverride: 'timed',
        );
        await deps.workoutState.addEntry(effortId);
        await deps.workoutState.recordRestStart(effortId, 1);

        await tester.pumpWidget(_buildSessionScreen(deps));
        await _openDetailView(tester, timedExercise.name);
        await tester.tap(find.byIcon(Icons.arrow_forward).first);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('rest-overlay-chip')), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Start'));
        await tester.pumpAndSettle();

        // The rest should be closed.
        final rests = deps.workoutState.getEntryRests(effortId);
        final openAfter = rests.where((r) => r.restEndMs == null);
        expect(
          openAfter,
          isEmpty,
          reason:
              'starting a timed effort must close any open rest for that '
              'effort',
        );

        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsNothing,
          reason:
              'detail view must hide the chip once the timed entry\'s '
              'effort is actively running',
        );
      },
    );
  });
}
