// Plan 261: the calendar keeps the old month on screen while the next one
// loads, swipes between months, has a Today button, and reads each day with
// its session count.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A repository whose month read waits on [gate] once it is set.
class _GatedRepo extends MockWorkoutRepository {
  Completer<void>? gate;

  @override
  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    final g = gate;
    if (g != null) await g.future;
    return super.getSessionsByDateRange(fromMs, toMs);
  }
}

Future<void> _session(
  MockWorkoutRepository repo,
  String id,
  DateTime at,
) async {
  final ms = at.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'u-1',
      startedAtMs: ms,
      endedAtMs: ms + 3600000,
      createdAtMs: ms,
      updatedAtMs: ms,
    ),
  );
}

Future<CalendarState> _pump(
  WidgetTester tester,
  MockWorkoutRepository repo,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final calendarState = CalendarState(repo);
  await calendarState.init();
  await tester.pumpWidget(
    MaterialApp(
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
    ),
  );
  await tester.pumpAndSettle();
  return calendarState;
}

String _title(DateTime d) =>
    '${OmniDateUtils.fullMonthName(d.month)} ${d.year}';

void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 1);
  final nextMonth = DateTime(now.year, now.month + 1, 1);

  group('Calendar navigation polish (plan 261)', () {
    testWidgets('S-26101 swiping left shows the next month, right goes back', (
      tester,
    ) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await _pump(tester, repo);
      expect(find.text(_title(thisMonth)), findsOneWidget);

      await tester.fling(find.byType(GridView), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text(_title(nextMonth)), findsOneWidget);

      await tester.fling(find.byType(GridView), const Offset(300, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text(_title(thisMonth)), findsOneWidget);
    });

    testWidgets('S-26102 the Today button shows only away from this month', (
      tester,
    ) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = await _pump(tester, repo);
      expect(find.byKey(const Key('calendar_today_button')), findsNothing);

      await state.goToNextMonth();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_today_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_today_button')));
      await tester.pumpAndSettle();
      expect(find.text(_title(thisMonth)), findsOneWidget);
      expect(find.byKey(const Key('calendar_today_button')), findsNothing);
    });

    testWidgets('S-26103 no spinner while the next month loads', (
      tester,
    ) async {
      final repo = _GatedRepo();
      await repo.initialize();
      final state = await _pump(tester, repo);

      repo.gate = Completer<void>();
      final loading = state.goToNextMonth();
      await tester.pump();
      expect(state.isLoading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(GridView), findsOneWidget);

      repo.gate!.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(find.text(_title(nextMonth)), findsOneWidget);
    });

    testWidgets('S-26104 each day is read with its session count', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final d = DateTime(now.year, now.month, 1, 9);
      await _session(repo, 's-a', d);
      await _session(repo, 's-b', d.add(const Duration(hours: 3)));
      await _session(repo, 's-c', d.add(const Duration(days: 1)));
      await _pump(tester, repo);

      expect(find.bySemanticsLabel('1, 2 sessions'), findsOneWidget);
      expect(find.bySemanticsLabel('2, 1 session'), findsOneWidget);
      semantics.dispose();
    });
  });
}
