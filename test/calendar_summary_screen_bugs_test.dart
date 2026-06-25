import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
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
/// the calendar / Open Calendar / Discard buttons directly tappable.
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

/// Pumps `SessionSummaryScreen` with the historical session already loaded
/// into [workoutState]. Returns the widget tree's `BuildContext` for the
/// summary screen so callers can drive navigation.
Future<NavigatorState> _pumpHistoricalSummary(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  required WorkoutState workoutState,
  required bool openedFromCalendar,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1100));
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = await _settingsWithoutFeelingSheet(repo);

  await tester.pumpWidget(
    MaterialApp(
      home: SessionSummaryScreen(
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        settingsState: settingsState,
        timerAlertService: FakeTimerAlertService(),
        openedFromCalendar: openedFromCalendar,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<NavigatorState>(find.byType(Navigator).first);
}

// ════════════════════════════════════════════════════════════════════════════════
// S-001: Historical session summary calendar shows the session's month
// ════════════════════════════════════════════════════════════════════════════════

void main() {
  group('S-001 — historical summary calendar shows the session month', () {
    testWidgets(
      'calendar header label uses the historical session month + year',
      (WidgetTester tester) async {
        // Pick a historical date that is GUARANTEED to be in a different
        // month and year from "today" (test runs at any wall-clock time).
        final today = DateTime.now();
        final historical = DateTime(today.year - 3, 3, 15); // March, 3 yrs ago

        final repo = await _freshRepo();
        final sessionId = await _seedCompletedSession(
          repo,
          startDate: historical,
        );

        final workoutState = WorkoutState(repo);
        await workoutState.loadHistoricalSession(sessionId);

        await _pumpHistoricalSummary(
          tester,
          repo: repo,
          workoutState: workoutState,
          openedFromCalendar: true,
        );

        // The calendar header label is built from the session's start month
        // (long-form: "March 2022"). The CURRENT month is today.month and
        // today.year; they must NOT appear in the header.
        final sessionDate = OmniDateUtils.fromMs(
          workoutState.currentSession!.startedAtMs,
        );
        final expectedLabel =
            '${OmniDateUtils.fullMonthName(sessionDate.month)} ${sessionDate.year}';

        // Scroll until the calendar card is visible.
        await tester.scrollUntilVisible(
          find.text(expectedLabel),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text(expectedLabel), findsOneWidget);
        // The current month label must not appear in the calendar header.
        final currentLabel =
            '${OmniDateUtils.fullMonthName(today.month)} ${today.year}';
        expect(find.text(currentLabel), findsNothing);
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════════
  // S-002: Open Calendar on historical summary pops back
  // ════════════════════════════════════════════════════════════════════════════

  group('S-002 — Open Calendar pops back on historical summary', () {
    testWidgets(
      'tapping "Open Calendar" with openedFromCalendar=true pops one route '
      'instead of pushing a new CalendarScreen',
      (WidgetTester tester) async {
        final today = DateTime.now();
        final historical = DateTime(today.year - 3, 3, 15);

        final repo = await _freshRepo();
        final sessionId = await _seedCompletedSession(
          repo,
          startDate: historical,
        );

        final workoutState = WorkoutState(repo);
        await workoutState.loadHistoricalSession(sessionId);

        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = await _settingsWithoutFeelingSheet(repo);

        await tester.binding.setSurfaceSize(const Size(400, 1100));

        // Stack: parent Scaffold (root) → SessionSummaryScreen (pushed).
        // The parent is a small Scaffold whose body holds a single
        // marker text. We push the summary, then verify the tap on
        // "Open Calendar" pops it back to the parent without stacking
        // a fresh CalendarScreen on top.
        final navKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
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
                              sessionSummaryService:
                                  sessionSummaryService,
                              settingsState: settingsState,
                              timerAlertService: FakeTimerAlertService(),
                              openedFromCalendar: true,
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

        // Push the summary by tapping the trigger. Pump repeatedly
        // to let the route transition + the summary's background
        // async work settle enough for the calendar card to be built
        // and the Open Calendar button to be present in the tree.
        await tester.tap(find.text('OPEN_SUMMARY'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(find.byType(SessionSummaryScreen), findsOneWidget);
        expect(find.text('OPEN_SUMMARY'), findsNothing);

        // Scroll until Open Calendar is visible, then tap it.
        await tester.scrollUntilVisible(
          find.text('Open Calendar'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        await tester.tap(find.text('Open Calendar'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Summary should be gone; parent is on top.
        // Critically: NO new CalendarScreen should have been pushed on top.
        expect(find.byType(SessionSummaryScreen), findsNothing);
        expect(find.byType(CalendarScreen), findsNothing);
        expect(find.text('OPEN_SUMMARY'), findsOneWidget);
      },
    );

    // ════════════════════════════════════════════════════════════════════════
    // S-003: post-workout Open Calendar still pushes a fresh calendar
    // ════════════════════════════════════════════════════════════════════════

    testWidgets(
      'tapping "Open Calendar" with openedFromCalendar=false (default) '
      'pushes a new CalendarScreen on top',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(modality: Modality.resistanceLifting);

        final routineState = RoutineState(repo);
        final sessionSummaryService = SessionSummaryService(repo);
        final settingsState = await _settingsWithoutFeelingSheet(repo);

        await tester.binding.setSurfaceSize(const Size(400, 1100));
        await tester.pumpWidget(
          MaterialApp(
            home: SessionSummaryScreen(
              workoutState: workoutState,
              routineState: routineState,
              sessionSummaryService: sessionSummaryService,
              settingsState: settingsState,
              timerAlertService: FakeTimerAlertService(),
              // openedFromCalendar omitted → default false (post-workout)
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Open Calendar'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Calendar'));
        await tester.pumpAndSettle();

        expect(find.byType(CalendarScreen), findsOneWidget);
      },
    );
  });

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
                              sessionSummaryService:
                                  sessionSummaryService,
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
        // `TextButton` (not `FilledButton`) in the existing dialog.
        await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
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
        await workoutState.createNewSession(modality: Modality.resistanceLifting);

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
                              sessionSummaryService:
                                  sessionSummaryService,
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
        await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
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

