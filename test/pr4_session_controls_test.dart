// PR 4 (Session Screen Controls) — UI smoke tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/effort_rating_sheet.dart';
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
    await workoutState.addExerciseToSession(first, chosenMetric: chosenMetric);
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

Future<void> _pumpScreen(WidgetTester tester, _SessionHarness harness) async {
  await tester.pumpWidget(MaterialApp(home: harness.screen));
  await tester.pumpAndSettle();
}

/// The route beneath the session screen (D-179's S-184 asks which route the
/// stack holds after the screen leaves).
class _HomeStub extends StatelessWidget {
  const _HomeStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home-stub')));
}

/// Counts the routes the navigator *adds* — `didPush` and `didReplace`. An
/// exit animation's `didPop` / `didRemove` is not an addition, so the count is
/// what "left once" is read from.
class _RouteAdder extends NavigatorObserver {
  int added = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => added++;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      added++;
}

/// Pushes the session screen above [_HomeStub] and pumps until the seeded set
/// is on screen — the point at which the screen has armed the session id it
/// was mounted for. `pumpAndSettle` is never used: the session screen runs a
/// one-second ticker.
Future<void> _pushSessionRoute(
  WidgetTester tester,
  _SessionHarness harness, {
  NavigatorObserver? observer,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [?observer],
      home: const _HomeStub(),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => harness.screen),
    ),
  );
  await _pumpUntil(tester, find.byType(ListTile));
  expect(
    find.byType(ListTile),
    findsWidgets,
    reason:
        'the session screen must have loaded its session (and armed the id '
        'it was mounted for) before the watch delivers anything',
  );
}

/// Pumps up to [frames] frames of [step] until [finder] matches. Never
/// `pumpAndSettle` on a tree that holds the session screen.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int frames = 40,
  Duration step = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < frames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
}

/// Open a rest via the standard user-facing Log Set flow. Sets
/// reps > 0 first so the Log Set button actually fires (set-kind
/// entries with reps=0 are skipped and never open a rest).
Future<void> _logSetToOpenRest(
  WidgetTester tester,
  _SessionHarness harness,
) async {
  final effortId =
      harness.workoutState.getExercisesWithEntries().first['id'] as String;
  await harness.workoutState.updateEntryValue(effortId, 0, 'reps', 8);
  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Log Set'));
  await tester.pumpAndSettle();
}

void main() {
  group('Rest tile — UI state mirroring', () {
    testWidgets('rest chip is visible after Log Set opens a rest window', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final harness = await _pumpSession(repo);
      await _pumpScreen(tester, harness);

      await _logSetToOpenRest(tester, harness);

      expect(
        find.byKey(const Key('rest-overlay-chip')),
        findsOneWidget,
        reason: 'rest chip must appear when a rest window is open',
      );
      final effortId =
          harness.workoutState.getExercisesWithEntries().first['id'] as String;
      expect(
        harness.workoutState.isRestPaused(effortId, 1),
        isFalse,
        reason: 'rest is running right after Log Set',
      );
    });

    testWidgets('rest chip meets 48-dp touch-target minimum', (
      WidgetTester tester,
    ) async {
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
    });

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
        final effortId =
            harness.workoutState.getExercisesWithEntries().first['id']
                as String;
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
    Finder discardFinder() => find.widgetWithText(OutlinedButton, 'Discard');

    // The confirmation dialog also contains a "Discard" action —
    // scope its finder to the AlertDialog so the screen-level button
    // does not collide with the dialog action.
    Finder dialogDiscardFinder() => find.descendant(
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
          discardFinder(),
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
          discardFinder(),
          findsNothing,
          reason: 'Detail view must NOT show the Discard button',
        );
      },
    );

    testWidgets('cancel preserves all session-owned data and timers', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final harness = await _pumpSession(repo);
      await _pumpScreen(tester, harness);

      final effortId =
          harness.workoutState.getExercisesWithEntries().first['id'] as String;
      await harness.workoutState.recordRestStart(effortId, 1);
      await tester.pumpAndSettle();

      final sessionId = harness.workoutState.currentSession!.id;

      // Open the discard dialog → tap Cancel.
      await tester.tap(discardFinder());
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
    });

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
        await tester.tap(discardFinder());
        await tester.pumpAndSettle();
        expect(find.text('Discard session?'), findsOneWidget);
        await tester.tap(dialogDiscardFinder());
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

    testWidgets('discard button is hidden in edit mode', (
      WidgetTester tester,
    ) async {
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
      final discard = tester.widget<OutlinedButton>(discardFinder());
      expect(discard.onPressed, isNull);
    });

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
        final discardRect = tester.getRect(discardFinder());
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
        expect(notesRect.height, OmniTheme.headerSecondaryActionSize);
        expect(infoRect.height, OmniTheme.headerSecondaryActionSize);

        // And the three secondary actions are exactly the same height
        // in absolute terms — the consolidated token guarantees it.
        expect(discardRect.height, notesRect.height);
        expect(discardRect.height, infoRect.height);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 19a Phase 3 (D-179) — the phone's session screen follows an end delivered
  // by the other device: it leaves for its own session's end, once, and never
  // in edit mode.
  // -------------------------------------------------------------------------
  group('Watch authority — the session screen leaves on its own', () {
    testWidgets(
      'S-174 the screen leaves for the summary when the watch completes its session, rating shown, no prompt',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        final sessionId = harness.workoutState.currentSession!.id;
        final nav = _RouteAdder();
        await _pushSessionRoute(tester, harness, observer: nav);
        final routesAtMount = nav.added;

        // The wrist's lifecycle naming the live session: the adoption bridge
        // catches the row up with the watch's rating (`_catchUpSessionRow`)
        // and then ends it. `updateSessionFeeling` clamps to 1..5, so the
        // plan's rating 7 is delivered as the top of the real scale.
        await harness.workoutState.updateSessionFeeling(sessionId, 4);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          nav.added,
          routesAtMount,
          reason:
              'S-174 a live session\'s own lifecycle does not move the screen — '
              'red under the mutation that drops the `endedAtMs` clause',
        );

        await harness.workoutState.endSession();

        // One frame runs the listener's post-frame replacement; the session
        // route is still mounted here, on its way out.
        await tester.pump();
        expect(
          nav.added,
          routesAtMount + 1,
          reason: 'S-174 the end opens exactly one route — the summary',
        );

        // A second lifecycle naming the same session arrives while the screen
        // is leaving: D-179 leaves once.
        await harness.workoutState.updateSessionFeeling(sessionId, 4);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          nav.added,
          routesAtMount + 1,
          reason:
              'S-174 the screen leaves once — a later notification for its own '
              'session must not navigate again (red under the mutation that '
              'drops the `_leaving` guard)',
        );

        await _pumpUntil(
          tester,
          find.byType(SessionSummaryScreen, skipOffstage: false),
        );
        // Let the replacement finish: the session route is disposed when its
        // exit transition ends, not when the summary is pushed.
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpUntil(tester, find.text('4 / 5'));

        expect(
          find.byType(SessionSummaryScreen, skipOffstage: false),
          findsOneWidget,
          reason:
              'S-174 the screen leaves for the summary on its own — red before '
              'the change, when the screen stays on the ended session',
        );
        expect(
          find.byType(WorkoutSessionScreen),
          findsNothing,
          reason: 'S-174 the session route is replaced, not left beneath',
        );
        expect(
          find.text('4 / 5'),
          findsWidgets,
          reason:
              'S-174 the summary reads the row as it stands — the rating the '
              'watch wrote is on screen',
        );
        expect(
          find.byType(EffortRatingSheet),
          findsNothing,
          reason:
              'S-174 the phone must not prompt for a rating the watch already '
              'gave (D-180, one end = one prompt)',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-184 a discard from the watch pops the screen and pushes no summary',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        final sessionId = harness.workoutState.currentSession!.id;
        await _pushSessionRoute(tester, harness);

        // What the wrist's `abandoned` lifecycle leaves behind: the row is
        // deleted and `currentSession` becomes null.
        await harness.workoutState.discardCurrentSession();

        await tester.pump();
        // One frame runs the listener's post-frame pop, the rest let the exit
        // transition finish (the session route is disposed when it ends).
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          find.byType(WorkoutSessionScreen),
          findsNothing,
          reason:
              'S-184 the session route is popped — red before the change, when '
              'the deleted session leaves the screen mounted',
        );
        expect(
          find.text('home-stub'),
          findsOneWidget,
          reason: 'S-184 the stack\'s top is the route beneath the session',
        );
        expect(
          find.byType(SessionSummaryScreen, skipOffstage: false),
          findsNothing,
          reason: 'S-184 a discarded session has nothing to summarize',
        );
        expect(await repo.getSession(sessionId), isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-185a an edit-mode screen over an ended session stays put',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        // Edit mode is a review mount: an ended session whose row carries a
        // feeling (the shape the summary's historical view hands it, D-179).
        final harness = await _pumpSession(repo, editMode: true);
        final sessionId = harness.workoutState.currentSession!.id;
        await harness.workoutState.updateSessionFeeling(sessionId, 4);
        await harness.workoutState.endSession();
        await _pushSessionRoute(tester, harness);

        // The lifecycle arrives while the review screen is up.
        await harness.workoutState.updateSessionFeeling(sessionId, 4);
        await harness.workoutState.endSession();

        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          find.byType(WorkoutSessionScreen),
          findsOneWidget,
          reason:
              'S-185a a review mount must not replace itself with a summary — '
              'red under the mutation that drops the `!editMode` clause',
        );
        expect(
          find.byType(SessionSummaryScreen, skipOffstage: false),
          findsNothing,
          reason: 'S-185a no summary is pushed for an edit-mode mount',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-185b the screen\'s own finish leaves exactly once while a same-session lifecycle arrives',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final harness = await _pumpSession(repo);
        final sessionId = harness.workoutState.currentSession!.id;
        await _pushSessionRoute(tester, harness);

        await tester.tap(find.text('Finish Workout'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
        await tester.pump();

        // The lifecycle naming the same session arrives while the screen's own
        // finish flow is running.
        await harness.workoutState.updateSessionFeeling(sessionId, 4);
        await harness.workoutState.endSession();

        // The route stack after each pump: never two summaries, exactly one
        // by the end.
        final summary = find.byType(SessionSummaryScreen, skipOffstage: false);
        for (var i = 0; i < 40; i++) {
          expect(
            summary.evaluate().length,
            lessThanOrEqualTo(1),
            reason:
                'S-185b exactly one replacement — red under the mutation that '
                'drops the `_isFinishingSession` guard',
          );
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          summary,
          findsOneWidget,
          reason: 'S-185b the phone\'s own finish opened one summary',
        );
        expect(
          find.byType(WorkoutSessionScreen),
          findsNothing,
          reason: 'S-185b the session route was replaced, not left beneath',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-185c an ended session the screen was not mounted for is ignored',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        // A different session, already ended — what a foreign row looks like
        // when the state loads it (the summary's historical view).
        final other = WorkoutState(repo);
        await other.createNewSession();
        final otherId = other.currentSession!.id;
        await other.endSession();

        final harness = await _pumpSession(repo);
        await _pushSessionRoute(tester, harness);

        await harness.workoutState.loadHistoricalSession(otherId);

        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          find.byType(WorkoutSessionScreen),
          findsOneWidget,
          reason:
              'S-185c another session\'s end must not move the screen — the id '
              'it was mounted for is what decides',
        );
        expect(
          find.byType(SessionSummaryScreen, skipOffstage: false),
          findsNothing,
          reason: 'S-185c no summary is pushed for a foreign session id',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
