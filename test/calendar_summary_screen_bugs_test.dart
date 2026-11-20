import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:uuid/uuid.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const _uuid = Uuid();

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Builds a `SettingsState` whose feeling-survey preference is disabled,
/// so the post-workout feeling sheet never opens in tests. This keeps
/// the calendar / Discard buttons directly tappable.
Future<SettingsState> _settingsWithoutFeelingSheet(
  MockWorkoutRepository repo,
) async {
  final s = SettingsState(repo, fakePreferencesService());
  await s.setShowFeelingSurvey(false);
  return s;
}

/// Seeds a minimal completed `TrainingSession` whose start time lands on
/// [startDate] at 09:00 local time. Returns the session id.
Future<String> _seedCompletedSession(
  MockWorkoutRepository repo, {
  required DateTime startDate,
  String modality = Modality.resistanceLifting,
  String title = 'Historical Lift',
}) async {
  final start = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
  final end = start.add(const Duration(hours: 1));
  final id = 'hist-${_uuid.v4()}';
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'u-test',
      startedAtMs: start.millisecondsSinceEpoch,
      endedAtMs: end.millisecondsSinceEpoch,
      title: title,
      modality: modality,
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: end.millisecondsSinceEpoch,
    ),
  );
  return id;
}

// ════════════════════════════════════════════════════════════════════════════════
// S-001 (deleted, plan 245): the summary month grid and month label no longer
// exist; the new exercise card is covered by S-24511..S-24514 in
// test/summary_exercise_list_screen_test.dart.
// ════════════════════════════════════════════════════════════════════════════════

void main() {
  // ════════════════════════════════════════════════════════════════════════════
  // S-002 / S-003 (deleted): the summary no longer has an Open Calendar button.
  // The screen shows none, whichever way it was reached.
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // S-004: Discard on historical summary returns to the originating screen
  // ════════════════════════════════════════════════════════════════════════════

  group('S-004 — discard on historical summary returns to day list', () {
    testWidgets(
      'discarding a historical session pops back to the originating screen '
      'and removes the session from the calendar',
      (WidgetTester tester) async {
        final today = DateTime.now();
        final historical = DateTime(today.year - 3, 3, 15);

        final repo = await _freshRepo();
        final sessionId = await _seedCompletedSession(
          repo,
          startDate: historical,
          title: 'Discard Me',
        );

        final workoutState = WorkoutState(repo);
        await workoutState.loadHistoricalSession(sessionId);

        final calendarState = CalendarState(repo);
        await calendarState.init();
        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = await _settingsWithoutFeelingSheet(repo);

        await tester.binding.setSurfaceSize(const Size(400, 1100));

        // Stack: _ParentScreen (root) → SessionSummaryScreen (pushed).
        // Use `MaterialPageRoute` + fixed `pump(Duration)` to avoid the
        // `pumpAndSettle` hang the summary's background async work
        // introduces (see S-002 for the same rationale).
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SessionSummaryScreen(
                              workoutState: workoutState,
                              routineState: routineState,
                              sessionSummaryService: sessionSummaryService,
                              settingsState: settingsState,
                              timerAlertService: FakeTimerAlertService(),
                              openedFromCalendar: true,
                              originatingCalendarState: calendarState,
                            ),
                          ),
                        );
                      },
                      child: const Text('OPEN_SUMMARY'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Push the summary.
        await tester.tap(find.text('OPEN_SUMMARY'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        // Pre-condition: summary is on top of the parent.
        expect(find.byType(SessionSummaryScreen), findsOneWidget);
        expect(find.text('OPEN_SUMMARY'), findsNothing);
        // Session is still in the repo.
        expect(await repo.getSession(sessionId), isNotNull);

        // Open the overflow menu and tap Discard.
        await tester.tap(find.byType(PopupMenuButton<String>));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.tap(find.text('Discard').last);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Confirm in the dialog. The discard confirm button is a
        // `FilledButton` (not `TextButton`) in the consolidated dialog.
        await tester.tap(find.widgetWithText(FilledButton, 'Discard').last);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Summary is gone; parent is the topmost screen.
        expect(find.byType(SessionSummaryScreen), findsNothing);
        expect(find.text('OPEN_SUMMARY'), findsOneWidget);
        // Session was deleted from the repo.
        expect(await repo.getSession(sessionId), isNull);
      },
    );

    // ════════════════════════════════════════════════════════════════════════
    // S-005: post-workout discard still pops to home (first route)
    // ════════════════════════════════════════════════════════════════════════

    testWidgets(
      'discarding from a post-workout summary (openedFromCalendar=false) '
      'still pops to the first route',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(
          modality: Modality.resistanceLifting,
        );

        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = await _settingsWithoutFeelingSheet(repo);

        await tester.binding.setSurfaceSize(const Size(400, 1100));

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SessionSummaryScreen(
                              workoutState: workoutState,
                              routineState: routineState,
                              sessionSummaryService: sessionSummaryService,
                              settingsState: settingsState,
                              timerAlertService: FakeTimerAlertService(),
                            ),
                          ),
                        );
                      },
                      child: const Text('OPEN_SUMMARY'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OPEN_SUMMARY'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Pre-condition: summary is on top of parent.
        expect(find.byType(SessionSummaryScreen), findsOneWidget);
        expect(find.text('OPEN_SUMMARY'), findsNothing);

        // Open overflow → Discard.
        await tester.tap(find.byType(PopupMenuButton<String>));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.tap(find.text('Discard').last);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Confirm in the dialog.
        await tester.tap(find.widgetWithText(FilledButton, 'Discard').last);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Summary is gone; parent is the topmost route.
        expect(find.byType(SessionSummaryScreen), findsNothing);
        expect(find.text('OPEN_SUMMARY'), findsOneWidget);
      },
    );
  });
}
