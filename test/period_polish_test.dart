// Plan 260: the calendar names the current training period under the month
// title, the period screens share one name, and the period form shows dates
// the way the rest of the app does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/calendar_screen.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/period/period_list_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

TrainingPeriod _period(String name, DateTime start, DateTime end) =>
    TrainingPeriod(
      id: 'p-$name',
      name: name,
      startDateMs: OmniDateUtils.startOfDayMs(start),
      endDateMs: OmniDateUtils.startOfDayMs(end),
      focusModalities: const [],
      createdAtMs: 1,
      updatedAtMs: 1,
    );

Future<CalendarState> _pumpCalendar(
  WidgetTester tester,
  List<TrainingPeriod> periods,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = MockWorkoutRepository();
  await repo.initialize();
  for (final p in periods) {
    await repo.createPeriod(p);
  }
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

void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);

  group('Calendar names the current period (plan 260)', () {
    testWidgets('S-26001 the period you are in shows under the month title', (
      tester,
    ) async {
      await _pumpCalendar(tester, [
        _period('Cut block', day.subtract(const Duration(days: 1)), day),
      ]);
      expect(find.byKey(const Key('calendar_period_name')), findsOneWidget);
      expect(find.text('Cut block'), findsOneWidget);
    });

    testWidgets(
      'S-26002 no line without a period, or for one not covering today',
      (tester) async {
        await _pumpCalendar(tester, [
          _period(
            'Old block',
            day.subtract(const Duration(days: 40)),
            day.subtract(const Duration(days: 20)),
          ),
        ]);
        expect(find.byKey(const Key('calendar_period_name')), findsNothing);
      },
    );

    testWidgets('S-26003 a month the period does not reach shows no line', (
      tester,
    ) async {
      final state = await _pumpCalendar(tester, [
        _period('Cut block', day, day.add(const Duration(days: 1))),
      ]);
      state.goToNextMonth();
      await tester.pumpAndSettle();
      state.goToNextMonth();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_period_name')), findsNothing);
    });
  });

  group('Period screens (plan 260)', () {
    testWidgets('S-26004 the button and the screen use one name', (
      tester,
    ) async {
      await _pumpCalendar(tester, const []);
      final button = tester.widget<IconButton>(
        find.byKey(const Key('calendar_training_periods_button')),
      );
      expect(button.tooltip, 'Training periods');

      final repo = MockWorkoutRepository();
      await repo.initialize();
      await tester.pumpWidget(
        MaterialApp(home: PeriodListScreen(periodState: PeriodState(repo))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Training periods'), findsOneWidget);
      expect(find.text('Periodization'), findsNothing);
    });

    test('S-26005 formatDay drops the year only in the current year', () {
      final now = DateTime(2026, 11, 19);
      expect(OmniDateUtils.formatDay(DateTime(2026, 11, 6), now), 'Nov 6');
      expect(
        OmniDateUtils.formatDay(DateTime(2025, 11, 16), now),
        'Nov 16, 2025',
      );
    });

    testWidgets(
      'S-26006 the period form shows dates like Nov 16, not dd/mm/yyyy',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final period = _period(
          'Block',
          DateTime(2020, 3, 8),
          DateTime(2020, 4, 5),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CreatePeriodScreen(
              periodState: PeriodState(repo),
              existingPeriod: period,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mar 8, 2020'), findsOneWidget);
        expect(find.text('Apr 5, 2020'), findsOneWidget);
        expect(find.textContaining(RegExp(r'\d{2}/\d{2}/\d{4}')), findsNothing);
      },
    );
  });
}
