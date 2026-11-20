// Plan 277 P3a — day-list series wiring (S-27722, S-27723, S-27728).
//
// The day list routes a series row through the shared three-choice dialog
// and a non-series row through today's two-choice dialog / a plain save.
// Mock repository only; series rows are seeded through
// `CalendarState.createRecurringPlannedSessions` (never hand-built), before
// the pump. Dates come from the real clock (`DateTime.now()`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/recurrence_rule.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime get _tomorrow {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

const _seriesRule = RecurrenceRule(
  series: 'series-a',
  unit: RecurrenceUnit.day,
  every: 1,
  end: RecurrenceEnd.count,
  count: 4,
);

/// A fresh fixture: a series of four `Upper` rows (tomorrow .. tomorrow+3)
/// created through the state's series factory, seeded before any pump.
Future<(MockWorkoutRepository, WorkoutState, CalendarState)>
_seededSeries() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  await calendarState.createRecurringPlannedSessions(
    first: _tomorrow,
    rule: _seriesRule,
    title: 'Upper',
  );
  final rows = await repo.getPlannedSessions();
  expect(rows.length, 4, reason: 'fixture: the series seeded 4 rows');
  return (repo, workoutState, calendarState);
}

/// A fresh fixture with ONE ordinary planned row titled `Plan A` on [day].
Future<(MockWorkoutRepository, WorkoutState, CalendarState)> _seededSingle(
  DateTime day,
) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final now = DateTime.now().millisecondsSinceEpoch;
  await repo.createPlannedSession(
    PlannedSession(
      id: 'p-single',
      ownerUserId: 'user-1',
      scheduledDateMs: day.millisecondsSinceEpoch,
      modality: null,
      routineTemplateId: null,
      title: 'Plan A',
      isCompleted: false,
      createdAtMs: now,
      updatedAtMs: now,
    ),
  );
  final workoutState = WorkoutState(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  return (repo, workoutState, calendarState);
}

Future<void> pumpDay(
  WidgetTester tester,
  DateTime day,
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  CalendarState calendarState,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: DaySessionListScreen(
        date: day,
        calendarState: calendarState,
        routineState: RoutineState(repo),
        workoutState: workoutState,
        routineSessionService: RoutineSessionService(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<int> storedRowCount(MockWorkoutRepository repo) async =>
    (await repo.getPlannedSessions()).length;

void main() {
  group('S-27722: delete on a series row; a non-series row', () {
    testWidgets(
      'S-27722: "Just this one" removes only the tapped day\'s row; three '
      'rows of the series remain',
      (tester) async {
        final (repo, workoutState, calendarState) = await _seededSeries();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await tester.tap(find.byTooltip('Delete session'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('day-session-series-delete-one')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('day-session-series-delete-after')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('day-session-delete-cancel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('day-session-delete-confirm')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const Key('day-session-series-delete-one')),
        );
        await tester.pumpAndSettle();

        final left = await repo.getPlannedSessions();
        expect(left, hasLength(3));
        expect(left.map((row) => row.title), everyElement('Upper'));
        expect(
          left.any(
            (row) => row.scheduledDateMs == _tomorrow.millisecondsSinceEpoch,
          ),
          isFalse,
        );
      },
    );

    testWidgets('S-27722: "This and all after it" removes the whole series', (
      tester,
    ) async {
      final (repo, workoutState, calendarState) = await _seededSeries();
      await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

      await tester.tap(find.byTooltip('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('day-session-series-delete-after')),
      );
      await tester.pumpAndSettle();

      expect(await storedRowCount(repo), 0);
    });

    testWidgets('S-27722: Cancel removes nothing', (tester) async {
      final (repo, workoutState, calendarState) = await _seededSeries();
      await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

      await tester.tap(find.byTooltip('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('day-session-delete-cancel')));
      await tester.pumpAndSettle();

      expect(await storedRowCount(repo), 4);
    });

    testWidgets('S-27722: a NON-series row still shows the two-choice dialog', (
      tester,
    ) async {
      final (repo, workoutState, calendarState) = await _seededSingle(
        _tomorrow,
      );
      await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

      await tester.tap(find.byTooltip('Delete session'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('day-session-delete-confirm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('day-session-series-delete-one')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('day-session-delete-confirm')));
      await tester.pumpAndSettle();

      expect(await storedRowCount(repo), 0);
    });
  });

  group(
    'S-27723: edit then Save Changes on a series row; a non-series row',
    () {
      /// Opens the edit sheet for the pumped day's `Upper` row and submits a
      /// new title through `Save Changes`.
      Future<void> editRowTitle(WidgetTester tester, String newTitle) async {
        await tester.tap(find.text('Upper'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Session'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, newTitle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
      }

      testWidgets(
        'S-27723: "Just this one" changes only the edited row\'s title',
        (tester) async {
          final (repo, workoutState, calendarState) = await _seededSeries();
          await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

          await editRowTitle(tester, 'Upper New');

          expect(
            find.byKey(const Key('day-session-series-edit-one')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('day-session-series-edit-after')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('day-session-series-edit-cancel')),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const Key('day-session-series-edit-one')),
          );
          await tester.pumpAndSettle();

          final rows = await repo.getPlannedSessions();
          expect(rows, hasLength(4));
          final titled = rows.map((row) => row.title).toList();
          expect(
            titled.where((title) => title == 'Upper New'),
            hasLength(1),
            reason: 'only the edited day takes the new title',
          );
          expect(titled.where((title) => title == 'Upper'), hasLength(3));
        },
      );

      testWidgets('S-27723: "This and all after it" changes the whole series', (
        tester,
      ) async {
        final (repo, workoutState, calendarState) = await _seededSeries();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await editRowTitle(tester, 'Upper New');
        await tester.tap(
          find.byKey(const Key('day-session-series-edit-after')),
        );
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(rows, hasLength(4));
        expect(rows.map((row) => row.title), everyElement('Upper New'));
      });

      testWidgets('S-27723: Cancel writes nothing', (tester) async {
        final (repo, workoutState, calendarState) = await _seededSeries();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await editRowTitle(tester, 'Upper New');
        await tester.tap(
          find.byKey(const Key('day-session-series-edit-cancel')),
        );
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(rows, hasLength(4));
        expect(rows.map((row) => row.title), everyElement('Upper'));
      });

      testWidgets('S-27723: a non-series row saves with NO dialog', (
        tester,
      ) async {
        final (repo, workoutState, calendarState) = await _seededSingle(_today);
        await pumpDay(tester, _today, repo, workoutState, calendarState);

        await tester.tap(find.text('Plan A'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Session'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Plan B');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('day-session-series-edit-one')),
          findsNothing,
        );
        expect(find.text('Edit Session'), findsNothing);

        final rows = await repo.getPlannedSessions();
        expect(rows, hasLength(1));
        expect(rows.single.title, 'Plan B');
      });
    },
  );

  group('S-27728: one day holding an ordinary plan and a series row', () {
    testWidgets('S-27728: both rows render and the day counts two entries', (
      tester,
    ) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createPlannedSession(
        PlannedSession(
          id: 'p-ordinary',
          ownerUserId: 'user-1',
          scheduledDateMs: _tomorrow.millisecondsSinceEpoch,
          modality: null,
          routineTemplateId: null,
          title: 'Solo Plan',
          isCompleted: false,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final workoutState = WorkoutState(repo);
      final calendarState = CalendarState(repo);
      await calendarState.init();
      await calendarState.createRecurringPlannedSessions(
        first: _tomorrow,
        rule: _seriesRule,
        title: 'Upper',
      );

      await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

      expect(find.text('Solo Plan'), findsOneWidget);
      expect(find.text('Upper'), findsOneWidget);
      expect(calendarState.entriesForDay(_tomorrow).length, 2);
    });
  });
}
