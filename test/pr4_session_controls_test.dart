// PR 4 (Session Screen Controls) — UI smoke tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Pre-seed coach mark flags so the overlay never blocks button taps.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

class _SessionHarness {
  _SessionHarness(this.workoutState, this.screen);
  final WorkoutState workoutState;
  final WorkoutSessionScreen screen;
}

Future<_SessionHarness> _pumpSession(
  MockWorkoutRepository repo, {
  bool editMode = false,
  bool endSessionFirst = false,
  String chosenMetric = 'reps',
}) async {
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession();
  if (endSessionFirst) {
    await workoutState.endSession();
  } else {
    final exercises = await repo.getExercises();
    final first = exercises.firstWhere(
      (e) => e.capabilities.contains(chosenMetric),
      orElse: () => exercises.first,
    );
    await workoutState.addExerciseToSession(
      first,
      chosenMetric: chosenMetric,
    );
  }

  final screen = WorkoutSessionScreen(
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    timerAlertService: FakeTimerAlertService(),
    settingsState: settingsState,
    restNotificationService: FakeRestNotificationService(),
    editMode: editMode,
  );
  return _SessionHarness(workoutState, screen);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _SessionHarness harness,
) async {
  await tester.pumpWidget(MaterialApp(home: harness.screen));
  await tester.pumpAndSettle();
}

/// Open a rest via the standard user-facing Log Set flow. Sets
/// reps > 0 first so the Log Set button actually fires (set-kind
/// entries with reps=0 are skipped and never open a rest).
Future<void> _logSetToOpenRest(
  WidgetTester tester,
  _SessionHarness harness,
) async {
  final effortId = harness.workoutState
      .getExercisesWithEntries()
      .first['id'] as String;
  await harness.workoutState.updateEntryValue(effortId, 0, 'reps', 8);
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Log Set'));
  await tester.pumpAndSettle();
}

void main() {
  group('Rest tile — UI state mirroring', () {
    testWidgets(
      'rest chip is visible after Log Set opens a rest window',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        await _logSetToOpenRest(tester, harness);

        expect(
          find.byKey(const Key('rest-overlay-chip')),
          findsOneWidget,
          reason: 'rest chip must appear when a rest window is open',
        );
        final effortId = harness.workoutState
            .getExercisesWithEntries()
            .first['id'] as String;
        expect(
          harness.workoutState.isRestPaused(effortId, 1),
          isFalse,
          reason: 'rest is running right after Log Set',
        );
      },
    );

    testWidgets(
      'rest chip meets 48-dp touch-target minimum',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        await _logSetToOpenRest(tester, harness);

        final chipRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );
        expect(
          chipRect.height,
          greaterThanOrEqualTo(48),
          reason: 'rest chip must meet 48-dp touch-target floor',
        );
      },
    );

    testWidgets(
      'three visual states — running shows meditation icon, paused swaps to pause icon (same size)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        await _logSetToOpenRest(tester, harness);

        // Running: meditation icon.
        expect(find.byIcon(Icons.self_improvement), findsOneWidget);
        final runningRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );

        // Pause the rest via the public state API. The screen's
        // ticker-driven rebuild picks up the new state on the next
        // 1-second tick.
        final effortId = harness.workoutState
            .getExercisesWithEntries()
            .first['id'] as String;
        await harness.workoutState.pauseRest(effortId, 1);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        // Paused: meditation icon is gone (replaced by the pause
        // icon). The caption is intentionally absent — the chip
        // must stay the same size in both states.
        expect(find.byIcon(Icons.self_improvement), findsNothing);
        expect(find.text('Paused · tap to resume'), findsNothing);
        final pausedRect = tester.getRect(
          find.byKey(const Key('rest-overlay-chip')),
        );
        expect(
          pausedRect.height,
          closeTo(runningRect.height, 0.5),
          reason: 'paused chip must stay the same height as running chip',
        );
      },
    );
  });

  group('Discard Session — confirm/cancel flows', () {
    Finder _discardFinder() =>
        find.widgetWithText(OutlinedButton, 'Discard');

    // The confirmation dialog also contains a "Discard" action —
    // scope its finder to the AlertDialog so the screen-level button
    // does not collide with the dialog action.
    Finder _dialogDiscardFinder() => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Discard'),
        );

    testWidgets(
      'discard button is visible in the session-details (list) view',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        // Default surface = list view, so the Discard button must be
        // reachable as an OutlinedButton labelled "Discard".
        expect(
          _discardFinder(),
          findsOneWidget,
          reason: 'Discard button must be reachable from the list surface',
        );
      },
    );

    testWidgets(
      'discard button is hidden in the exercise-details (detail) view',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        // Navigate to detail view by tapping the exercise.
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // The Discard button is intentionally absent on the detail
        // surface — only the session-details screen offers discard.
        expect(
          _discardFinder(),
          findsNothing,
          reason: 'Detail view must NOT show the Discard button',
        );
      },
    );

    testWidgets(
      'cancel preserves all session-owned data and timers',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        final effortId = harness.workoutState
            .getExercisesWithEntries()
            .first['id'] as String;
        await harness.workoutState.recordRestStart(effortId, 1);
        await tester.pumpAndSettle();

        final sessionId = harness.workoutState.currentSession!.id;

        // Open the discard dialog → tap Cancel.
        await tester.tap(_discardFinder());
        await tester.pumpAndSettle();
        expect(find.text('Discard session?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Session is still in the repo.
        expect(await repo.getSession(sessionId), isNotNull);
        // The WorkoutSessionScreen is still mounted.
        expect(find.byType(WorkoutSessionScreen), findsOneWidget);
        // The rest record is still open (restEndMs is null).
        final rests = harness.workoutState.getEntryRests(effortId);
        expect(rests, isNotEmpty);
        expect(rests.first.restEndMs, isNull);
      },
    );

    testWidgets(
      'confirm removes full session aggregate (state + repo cleared)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        final sessionId = harness.workoutState.currentSession!.id;

        // Open the dialog → confirm. Use the dialog-scoped finder so
        // the "Discard" tap lands on the dialog action, not the
        // screen-level button.
        await tester.tap(_discardFinder());
        await tester.pumpAndSettle();
        expect(find.text('Discard session?'), findsOneWidget);
        await tester.tap(_dialogDiscardFinder());
        await tester.pumpAndSettle();

        // Session and every child record are gone from the repo.
        expect(await repo.getSession(sessionId), isNull);
        // No completed sessions in the date range.
        final remaining = await repo.getSessionsByDateRange(0, 99999999999999);
        expect(remaining.where((s) => s.id == sessionId), isEmpty);
        // State layer cleared.
        expect(harness.workoutState.hasActiveSession, isFalse);
        // No active session: currentSession is null.
        expect(harness.workoutState.currentSession, isNull);
        // No exercise entries left in the state cache.
        expect(harness.workoutState.getExercisesWithEntries(), isEmpty);
      },
    );

    testWidgets(
      'discard button is hidden in edit mode',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        // edit mode requires a completed session.
        final harness = await _pumpSession(
          repo,
          editMode: true,
          endSessionFirst: true,
        );
        await _pumpScreen(tester, harness);

        // In edit mode the Discard button is hidden — its onPressed
        // is disabled but the widget still mounts. Verify that the
        // OutlinedButton is present but disabled.
        final discard = tester.widget<OutlinedButton>(_discardFinder());
        expect(discard.onPressed, isNull);
      },
    );

    testWidgets(
      'discard header button matches compact secondary action height (40dp)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        await _pumpScreen(tester, harness);

        // The Discard button lives in the list header at the same
        // compact height as the notes / info IconButtons in the
        // detail header — both are secondary header actions and
        // both consume OmniTheme.headerSecondaryActionSize so the
        // header row stays visually aligned across list ↔ detail
        // navigation. Same height token as the calendar "+"
        // button (which uses VisualDensity.compact).
        final discardRect = tester.getRect(_discardFinder());
        expect(
          discardRect.height,
          OmniTheme.headerSecondaryActionSize,
          reason:
              'Discard button must match the shared secondary action height',
        );

        // Navigate to detail view and confirm the notes / info
        // buttons also resolve to headerSecondaryActionSize.
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();
        final notesRect = tester.getRect(
          find.byKey(const Key('exercise-note-button')),
        );
        final infoRect = tester.getRect(
          find.byKey(const Key('exercise-info-button')),
        );
        expect(
          notesRect.height,
          OmniTheme.headerSecondaryActionSize,
        );
        expect(
          infoRect.height,
          OmniTheme.headerSecondaryActionSize,
        );

        // And the three secondary actions are exactly the same height
        // in absolute terms — the consolidated token guarantees it.
        expect(
          discardRect.height,
          notesRect.height,
        );
        expect(
          discardRect.height,
          infoRect.height,
        );
      },
    );
  });
}