// Screen tests for the streak figures — plan
// `docs/plans/2026-11-03-101-streak-accuracy-plan/`, scenarios S-17406,
// S-17407 and S-17408.
//
// The calendar strip must read a live streak even before the month's first
// session (S-17406), must label a lapsed figure BEST RUN (S-17407a) and a live
// one STREAK (S-17407b); the Records & Trends Streak pill reads the live
// streak and falls to 0 d once it has lapsed (S-17408).
//
// Mock repository only, fixed 2026 dates and sessions at noon — never the
// device clock. Sessions are built here, not with the harness `seedSession`,
// whose 24 h steps drift after a clock change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart'
    show MockRepositoryHarness, repsRow, weightRow;

// ─── Calendar strip (S-17406, S-17407) ──────────────────────────────────────

Future<MockWorkoutRepository> freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Widget buildScreen(MockWorkoutRepository repo, CalendarState calendarState) {
  return MaterialApp(
    home: CalendarScreen(
      calendarState: calendarState,
      periodState: PeriodState(repo),
      workoutState: WorkoutState(repo),
      routineState: RoutineState(repo),
      routineSessionService: RoutineSessionService(repo),
      sessionSummaryService: SessionSummaryService(repo),
      settingsState: SettingsState(repo, fakePreferencesService()),
      timerAlertService: FakeTimerAlertService(),
    ),
  );
}

/// One completed session starting at [start], finished an hour later.
Future<void> seedSessionOn(
  MockWorkoutRepository repo,
  DateTime start, {
  required String id,
}) async {
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'u-test',
      startedAtMs: start.millisecondsSinceEpoch,
      endedAtMs: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    ),
  );
}

Future<void> pumpCalendar(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  required CalendarState calendarState,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(buildScreen(repo, calendarState));
  await tester.pumpAndSettle();
}

// ─── Records & Trends (S-17408) ─────────────────────────────────────────────

/// Tall enough that the aggregate card and everything under it are laid out,
/// so an assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// One completed session on [start] holding one set effort, so the screen
/// leaves its empty state and renders the aggregate card. Built here with
/// fixed dates for the same reason as the calendar sessions above.
Future<void> seedSetSessionOn(
  WorkoutRepository repo, {
  required String sessionId,
  required DateTime start,
}) async {
  final at = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: at,
      endedAtMs: at + 3600000,
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createEffort(
    SegmentEffort(
      id: 'eff-$sessionId',
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-bench',
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  await repo.createObservation(repsRow('eff-$sessionId', 0, 5, atMs: at));
  await repo.createObservation(weightRow('eff-$sessionId', 0, 80, atMs: at));
}

void main() {
  group('S-17406 and S-17407 the Calendar strip', () {
    testWidgets('S-17406 a live streak shows before the month first session',
        (tester) async {
      final repo = await freshRepo();
      await seedSessionOn(repo, DateTime(2026, 5, 30, 12), id: 's-may-30');
      await seedSessionOn(repo, DateTime(2026, 5, 31, 12), id: 's-may-31');
      final calendarState = CalendarState(
        repo,
        now: () => DateTime(2026, 6, 1, 9),
      );
      await calendarState.init();
      await pumpCalendar(tester, repo: repo, calendarState: calendarState);

      expect(find.text('STREAK'), findsOneWidget);
      expect(find.text('2d'), findsOneWidget);
      expect(find.text('BEST RUN'), findsNothing);
      // The SESSIONS slot itself reads the dash: June has no session yet.
      final sessionsSlot = find
          .ancestor(of: find.text('SESSIONS'), matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: sessionsSlot, matching: find.text('—')),
        findsOneWidget,
      );
    });

    testWidgets('S-17407 a lapsed streak reads BEST RUN', (tester) async {
      final repo = await freshRepo();
      await seedSessionOn(repo, DateTime(2026, 6, 1, 12), id: 's-jun-1');
      await seedSessionOn(repo, DateTime(2026, 6, 2, 12), id: 's-jun-2');
      final calendarState = CalendarState(
        repo,
        now: () => DateTime(2026, 6, 5, 9),
      );
      await calendarState.init();
      await pumpCalendar(tester, repo: repo, calendarState: calendarState);

      expect(find.text('BEST RUN'), findsOneWidget);
      expect(find.text('2d'), findsOneWidget);
      expect(find.text('STREAK'), findsNothing);
    });

    testWidgets('S-17407 a live streak reads STREAK', (tester) async {
      final repo = await freshRepo();
      await seedSessionOn(repo, DateTime(2026, 6, 4, 12), id: 's-jun-4');
      await seedSessionOn(repo, DateTime(2026, 6, 5, 12), id: 's-jun-5');
      final calendarState = CalendarState(
        repo,
        now: () => DateTime(2026, 6, 5, 18),
      );
      await calendarState.init();
      await pumpCalendar(tester, repo: repo, calendarState: calendarState);

      expect(find.text('STREAK'), findsOneWidget);
      expect(find.text('2d'), findsOneWidget);
      expect(find.text('BEST RUN'), findsNothing);
    });
  });

  group('S-17408 the Records and Trends Streak figure', () {
    late WorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      final harness = MockRepositoryHarness();
      repo = await harness.open();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      addTearDown(harness.close);
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(_kTallViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
    }

    Widget recordsScreen() => RecordsAndTrendsScreen(
      workoutState: workoutState,
      settingsState: settingsState,
      clock: () => DateTime(2026, 6, 5, 9),
    );

    testWidgets('S-17408 a live streak reads 2 d', (tester) async {
      await seedSetSessionOn(
        repo,
        sessionId: 's-jun-3',
        start: DateTime(2026, 6, 3, 12),
      );
      await seedSetSessionOn(
        repo,
        sessionId: 's-jun-4',
        start: DateTime(2026, 6, 4, 12),
      );
      await pump(tester, recordsScreen());

      final pills = _textsUnder(find.byType(OmniSurface).first);
      expect(pills, contains('STREAK'));
      expect(pills, contains('2 d'));
    });

    testWidgets('S-17408 a lapsed streak reads 0 d, not the month best run',
        (tester) async {
      await seedSetSessionOn(
        repo,
        sessionId: 's-jun-1',
        start: DateTime(2026, 6, 1, 12),
      );
      await seedSetSessionOn(
        repo,
        sessionId: 's-jun-2',
        start: DateTime(2026, 6, 2, 12),
      );
      await pump(tester, recordsScreen());

      final pills = _textsUnder(find.byType(OmniSurface).first);
      expect(pills, contains('STREAK'));
      expect(pills, contains('0 d'));
      expect(pills, isNot(contains('2 d')));
    });
  });
}
