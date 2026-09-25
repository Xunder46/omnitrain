import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// Helper to create a fresh mock repo
Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

// Helper to build SessionSummaryScreen with all required dependencies
Future<Widget> _buildSessionSummaryScreen({
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
  bool showFeelingSurvey = true,
  bool openedFromCalendar = false,
}) async {
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final prefs = fakePreferencesService();
  final settingsState = SettingsState(repo, prefs);

  if (!showFeelingSurvey) {
    await settingsState.setShowFeelingSurvey(false);
  }

  return MaterialApp(
    home: SessionSummaryScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      settingsState: settingsState,
      timerAlertService: FakeTimerAlertService(),
      openedFromCalendar: openedFromCalendar,
    ),
  );
}

void main() {
  group('SessionSummaryScreen EFFORT row (Phase 3)', () {
    testWidgets(
      'Task 1a: Automatic prompt with survey ON — EFFORT row refreshes after prompt closes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: true,
        ));
        await tester.pumpAndSettle();

        // Verify automatic prompt is open
        expect(find.text('How hard was this session?'), findsOneWidget);

        // Tap tile 4 on the automatic prompt (scoped to BottomSheet)
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        // Sheet closes
        expect(find.text('How hard was this session?'), findsNothing);

        // CRITICAL: After automatic prompt closes, EFFORT row MUST show the value
        // This test FAILS without setState in _showFeelingSheet
        expect(find.text('4 / 5'), findsOneWidget, reason: 'EFFORT row must refresh after automatic prompt');
        expect(find.text('Change'), findsOneWidget);

        // Verify repository has the value
        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'Task 1b: User-opened sheet with survey OFF — setState needed for refresh',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false, // No automatic prompt
        ));
        await tester.pumpAndSettle();

        // No automatic prompt, unrated state
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('Add rating'), findsOneWidget);

        // Tap "Add rating"
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        expect(find.text('How hard was this session?'), findsOneWidget);

        // Tap tile 4 on user-opened sheet
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        expect(find.text('How hard was this session?'), findsNothing);

        // CRITICAL: User-opened sheet needs setState to refresh
        // This test FAILS without setState in _openEffortRatingSheet
        expect(find.text('4 / 5'), findsOneWidget, reason: 'EFFORT row must refresh after user-opened sheet');
        expect(find.text('Change'), findsOneWidget);

        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'S-3: Fresh session — user adds rating from Summary (button path)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a fresh session (no rating)
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;

        // TURN OFF automatic prompt so we test the button path
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // Verify no automatic prompt, EFFORT row shows unrated state
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('—'), findsWidgets);
        expect(find.text('Add rating'), findsOneWidget);

        // Tap "Add rating" button
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        // Verify sheet is open
        expect(find.text('How hard was this session?'), findsOneWidget);

        // Find the tile with "4" on the user-opened sheet
        final tile4 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('4'),
        );
        await tester.ensureVisible(tile4);
        await tester.tap(tile4.first);
        await tester.pumpAndSettle();

        // Sheet should close, verify value is displayed
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('4 / 5'), findsOneWidget);
        expect(find.text('Change'), findsOneWidget);

        // Verify repository has the value
        final updated = await repo.getSession(session.id);
        expect(updated?.sessionFeeling, 4);
      },
    );

    testWidgets(
      'S-4/S-5: Historical session — add and change rating (opened from calendar)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a past session with no rating
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final sessionId = 'historical-session';
        final session = TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: yesterday.millisecondsSinceEpoch,
          endedAtMs: yesterday.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
          title: 'Yesterday Session',
          modality: 'cardioEndurance',
          sessionFeeling: null,
          createdAtMs: yesterday.millisecondsSinceEpoch,
          updatedAtMs: yesterday.millisecondsSinceEpoch,
        );
        await repo.createSession(session);

        // Load historical session
        await workoutState.loadHistoricalSession(sessionId);

        // OPENED FROM CALENDAR so no automatic prompt appears even with survey ON
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          openedFromCalendar: true,
        ));
        await tester.pumpAndSettle();

        // No automatic prompt
        expect(find.text('How hard was this session?'), findsNothing, reason: 'Historical summary must not show automatic prompt');

        // Add rating: tap "Add rating"
        expect(find.text('Add rating'), findsOneWidget);
        await tester.tap(find.text('Add rating'));
        await tester.pumpAndSettle();

        // Select rating 2
        final tile2 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('2'),
        );
        await tester.ensureVisible(tile2);
        await tester.tap(tile2.first);
        await tester.pumpAndSettle();

        // Verify added
        expect(find.text('2 / 5'), findsOneWidget);
        var stored = await repo.getSession(sessionId);
        expect(stored?.sessionFeeling, 2);

        // Change rating: tap "Change"
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();

        // Select rating 5
        final tile5 = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('5'),
        );
        await tester.ensureVisible(tile5);
        await tester.tap(tile5.first);
        await tester.pumpAndSettle();

        // Verify changed
        expect(find.text('5 / 5'), findsOneWidget);
        stored = await repo.getSession(sessionId);
        expect(stored?.sessionFeeling, 5);
      },
    );

    testWidgets(
      'S-5.5: User-opened sheet dismissed — value unchanged (button path)',
      (WidgetTester tester) async {
        // Large surface to fit Summary + Sheet
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create session with rating 3
        await workoutState.createNewSession();
        final session = workoutState.currentSession!;
        await workoutState.updateSessionFeeling(session.id, 3);

        // TURN OFF automatic prompt for button path test
        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // Verify current value is 3
        expect(find.text('3 / 5'), findsOneWidget);

        // Tap "Change"
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();

        // Dismiss by tapping barrier (outside the sheet, in the dim area)
        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();

        // Verify sheet is closed and value is unchanged
        expect(find.text('How hard was this session?'), findsNothing);
        expect(find.text('3 / 5'), findsOneWidget);

        // Verify repository was not updated
        final stored = await repo.getSession(session.id);
        expect(stored?.sessionFeeling, 3);
      },
    );

    testWidgets(
      'Task 3: Rolling session — EFFORT row visible, Duration/Rest hidden',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);

        // Create a new session, then make it rolling
        await workoutState.createNewSession();
        final sessionId = workoutState.currentSession!.id;

        // Update the session to be rolling with a rating
        final now = DateTime.now();
        final session = TrainingSession(
          id: sessionId,
          ownerUserId: 'u-1',
          startedAtMs: now.millisecondsSinceEpoch,
          endedAtMs: null, // No end = rolling
          title: 'Rolling Session',
          modality: null, // Free training
          sessionFeeling: 2, // Already has a rating
          createdAtMs: now.millisecondsSinceEpoch,
          updatedAtMs: now.millisecondsSinceEpoch,
          isRolling: true,
        );
        await repo.updateSession(session);

        // Reload to get the updated rolling session
        await workoutState.loadHistoricalSession(sessionId);

        await tester.pumpWidget(await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
          showFeelingSurvey: false,
        ));
        await tester.pumpAndSettle();

        // EFFORT row MUST be visible for rolling sessions
        expect(find.text('EFFORT'), findsOneWidget, reason: 'EFFORT label must be visible');
        expect(find.text('2 / 5'), findsOneWidget, reason: 'EFFORT value must be visible');
        expect(find.text('Change'), findsOneWidget, reason: 'Change button must be visible');

        // Duration and Rest Time must be HIDDEN for rolling sessions
        expect(find.text('DURATION'), findsNothing, reason: 'Duration must be hidden in rolling session');
        expect(find.text('REST TIME'), findsNothing, reason: 'Rest Time must be hidden in rolling session');
      },
    );
  });
}
