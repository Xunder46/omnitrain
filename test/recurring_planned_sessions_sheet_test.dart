// Plan 277 P3b-3 — widget tests of the Repeat sheet (S-27717..S-27721,
// S-27724..S-27726) plus the series-row read-only line (S-27725).
//
// The sheet is driven exactly as the app does: the bottom button
// "+ New Planned Session" opens a NEW plan, tapping a planned row opens
// EDIT. Mock repository only; writes happen through the screen and are
// read back with `repo.getPlannedSessions()` (no Hive — a Hive write never
// settles in a widget test). Dates come from the real clock
// (`DateTime.now()`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/recurrence_rule.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/inputs/numeric_field_with_done_bar.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A mock repository whose planned-session writes can be switched to fail,
/// so the screen's handling of a failed later-dates write can be observed.
class _FailingCreateRepo extends MockWorkoutRepository {
  bool failCreates = false;

  @override
  Future<String> createPlannedSession(PlannedSession session) async {
    if (failCreates) {
      throw StateError('boom');
    }
    return super.createPlannedSession(session);
  }
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

/// A fresh empty fixture: a mock repository with no planned rows.
Future<(MockWorkoutRepository, WorkoutState, CalendarState)>
_emptyFixture() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workoutState = WorkoutState(repo);
  final calendarState = CalendarState(repo);
  await calendarState.init();
  return (repo, workoutState, calendarState);
}

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

/// Opens the New Planned Session sheet the way the app does: the bottom
/// button.
Future<void> _openNewPlanSheet(WidgetTester tester) async {
  await tester.tap(find.text('+ New Planned Session'));
  await tester.pumpAndSettle();
  expect(find.text('New Planned Session'), findsOneWidget);
}

/// Selects one of the sheet's unit dropdown items by tapping the dropdown
/// by key, then the item text (the last match is the menu item).
Future<void> _changeUnit(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('repeat-unit')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Selects an `Every` interval the same way.
Future<void> _changeEvery(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('repeat-every')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

String _dayText(DateTime day) => '${day.year}-${day.month}-${day.day}';

void main() {
  group('S-27717: sheet, Repeat off', () {
    testWidgets(
      'S-27717: Repeat off hides the settings and stores one plain row',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        expect(
          find.byKey(const Key('repeat-switch')),
          findsOneWidget,
          reason: 'S-27717: the Repeat switch is in the new-plan sheet',
        );
        expect(
          find.byKey(const Key('repeat-every')),
          findsNothing,
          reason:
              'S-27717: the Every row is not in the tree while Repeat is off',
        );
        expect(
          find.byKey(const Key('repeat-unit')),
          findsNothing,
          reason:
              'S-27717: the unit row is not in the tree while Repeat is off',
        );
        expect(
          find.byKey(const Key('repeat-end-count')),
          findsNothing,
          reason:
              'S-27717: the Ends row is not in the tree while Repeat is off',
        );
        expect(
          find.byKey(const Key('repeat-summary')),
          findsNothing,
          reason:
              'S-27717: the summary line is not in the tree while Repeat is off',
        );

        await tester.tap(find.text('Add Session'));
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(
          rows,
          hasLength(1),
          reason: 'S-27717: Add Session with Repeat off stores exactly one row',
        );
        expect(
          rows.single.recurrenceRule,
          isNull,
          reason: 'S-27717: the stored row carries no recurrence rule',
        );
        expect(
          rows.single.scheduledDateMs,
          _tomorrow.millisecondsSinceEpoch,
          reason: 'S-27717: the row is on the planned day, no later rows',
        );
      },
    );
  });

  group('S-27718: sheet, Repeat on', () {
    testWidgets(
      'S-27718: the settings rows appear, chips follow the unit, the Ends '
      'toggle is one-of',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('repeat-every')),
          findsOneWidget,
          reason: 'S-27718: the Every row appears with Repeat on',
        );
        expect(
          find.byKey(const Key('repeat-unit')),
          findsOneWidget,
          reason: 'S-27718: the unit row appears with Repeat on',
        );
        for (var day = 1; day <= 7; day++) {
          expect(
            find.byKey(Key('repeat-weekday-$day')),
            findsOneWidget,
            reason:
                'S-27718: weekday chip $day exists with the default Weeks unit',
          );
        }
        final plannedWeekday = _tomorrow.weekday;
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(Key('repeat-weekday-$plannedWeekday')),
              )
              .selected,
          isTrue,
          reason: "S-27718: the planned day's own chip is ticked",
        );
        await tester.tap(find.byKey(Key('repeat-weekday-$plannedWeekday')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilterChip>(
                find.byKey(Key('repeat-weekday-$plannedWeekday')),
              )
              .selected,
          isTrue,
          reason: "S-27718: tapping the planned day's chip does not un-tick it",
        );

        final other = plannedWeekday % 7 + 1;
        await tester.tap(find.byKey(Key('repeat-weekday-$other')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilterChip>(find.byKey(Key('repeat-weekday-$other')))
              .selected,
          isTrue,
          reason: 'S-27718: tapping another weekday chip selects it',
        );

        await _changeUnit(tester, 'Days');
        for (var day = 1; day <= 7; day++) {
          expect(
            find.byKey(Key('repeat-weekday-$day')),
            findsNothing,
            reason: 'S-27718: chip $day is gone with the Days unit',
          );
        }

        await _changeUnit(tester, 'Months');
        for (var day = 1; day <= 7; day++) {
          expect(
            find.byKey(Key('repeat-weekday-$day')),
            findsNothing,
            reason: 'S-27718: chip $day is gone with the Months unit',
          );
        }

        await _changeUnit(tester, 'Weeks');
        for (var day = 1; day <= 7; day++) {
          expect(
            find.byKey(Key('repeat-weekday-$day')),
            findsOneWidget,
            reason: 'S-27718: chip $day is back with the Weeks unit',
          );
        }

        expect(
          tester.widget(find.byKey(const Key('repeat-end-count'))),
          isA<FilledButton>(),
          reason: 'S-27718: After is the selected end mode by default',
        );
        expect(
          tester.widget(find.byKey(const Key('repeat-end-date'))),
          isA<OutlinedButton>(),
          reason: 'S-27718: On date is not the selected end mode by default',
        );
        expect(
          find.byKey(const Key('repeat-count')),
          findsOneWidget,
          reason: 'S-27718: After shows the count field',
        );
        expect(
          find.byKey(const Key('repeat-until')),
          findsNothing,
          reason: 'S-27718: After hides the date row',
        );

        await tester.tap(find.byKey(const Key('repeat-end-date')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('repeat-until')),
          findsOneWidget,
          reason: 'S-27718: On date shows the date row',
        );
        expect(
          find.byKey(const Key('repeat-count')),
          findsNothing,
          reason: 'S-27718: On date hides the count field — never both',
        );
      },
    );
  });

  group('S-27719: the summary line follows the settings', () {
    testWidgets(
      'S-27719: the summary text changes with the interval, the count and '
      'the end mode',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();

        final day = _tomorrow;
        final defaultExpected = RecurrenceRule(
          series: 'x',
          unit: RecurrenceUnit.week,
          every: 1,
          weekdays: [day.weekday],
          end: RecurrenceEnd.count,
          count: 8,
        ).summary(day, 8);
        expect(
          tester.widget<Text>(find.byKey(const Key('repeat-summary'))).data,
          defaultExpected,
          reason: 'S-27719: the default Weeks/1/After-8 summary line',
        );

        await _changeEvery(tester, '2');
        await tester.enterText(find.byKey(const Key('repeat-count')), '5');
        await tester.pumpAndSettle();

        final every2Count5 = RecurrenceRule(
          series: 'x',
          unit: RecurrenceUnit.week,
          every: 2,
          weekdays: [day.weekday],
          end: RecurrenceEnd.count,
          count: 5,
        ).summary(day, 5);
        expect(
          tester.widget<Text>(find.byKey(const Key('repeat-summary'))).data,
          every2Count5,
          reason:
              'S-27719: the summary follows every 2 and After 5 (5 sessions)',
        );

        await tester.tap(find.byKey(const Key('repeat-end-date')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('repeat-summary'))).data,
          'Choose an end date',
          reason:
              'S-27719: with On date and no date chosen the line asks for a date',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add Session'),
              )
              .onPressed,
          isNull,
          reason:
              'S-27719: Add Session is disabled while no end date is chosen',
        );
      },
    );
  });

  group('S-27721: the On date picker bounds', () {
    testWidgets(
      'S-27721: the picker runs from the planned day + 1 to one year on, '
      'and a picked day enables Add Session',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repeat-end-date')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repeat-until')));
        await tester.pumpAndSettle();

        final picker = tester.widget<CalendarDatePicker>(
          find.byType(CalendarDatePicker),
        );
        final firstExpected = DateTime(
          _tomorrow.year,
          _tomorrow.month,
          _tomorrow.day + 1,
        );
        final lastExpected = DateTime(
          _tomorrow.year + 1,
          _tomorrow.month,
          _tomorrow.day,
        );
        expect(
          _dayText(picker.firstDate),
          _dayText(firstExpected),
          reason: 'S-27721: the picker starts at the planned day + 1',
        );
        expect(
          _dayText(picker.lastDate),
          _dayText(lastExpected),
          reason:
              'S-27721: the picker ends at the same calendar date one year later',
        );

        // The picker opens on the month of the initial candidate (day + 7).
        // The first selectable day can sit one page earlier.
        final displayed = DateTime(
          _tomorrow.year,
          _tomorrow.month,
          _tomorrow.day + 7,
        );
        if (displayed.month != firstExpected.month) {
          await tester.tap(find.byTooltip('Previous month'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('${firstExpected.day}').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        final picked = firstExpected;
        expect(
          find.text(
            '${picked.day} '
            '${OmniDateUtils.shortMonthName(picked.month)} '
            '${picked.year}',
          ),
          findsOneWidget,
          reason: 'S-27721: the repeat-until label shows the picked day',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add Session'),
              )
              .onPressed,
          isNotNull,
          reason: 'S-27721: a chosen end date enables Add Session',
        );
      },
    );
  });

  group('S-27726: Repeat on then off drops the settings', () {
    testWidgets(
      'S-27726: Every-3-days then off stores one plain row; ON again shows '
      'the defaults',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await _changeEvery(tester, '3');
        await _changeUnit(tester, 'Days');

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('repeat-every')),
          findsNothing,
          reason: 'S-27726: turning Repeat off hides the settings again',
        );

        await tester.tap(find.text('Add Session'));
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(
          rows,
          hasLength(1),
          reason: 'S-27726: the stale Every-3-days settings are dropped',
        );
        expect(
          rows.single.recurrenceRule,
          isNull,
          reason: 'S-27726: the stored row carries no recurrence rule',
        );
        expect(
          rows.single.scheduledDateMs,
          _tomorrow.millisecondsSinceEpoch,
          reason: 'S-27726: one row on the planned day, no later rows',
        );

        await _openNewPlanSheet(tester);
        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(const Key('repeat-every')),
              )
              .initialValue,
          1,
          reason: 'S-27726: a fresh ON starts at every 1',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<RecurrenceUnit>>(
                find.byKey(const Key('repeat-unit')),
              )
              .initialValue,
          RecurrenceUnit.week,
          reason: 'S-27726: a fresh ON starts at Weeks',
        );
        expect(
          tester.widget(find.byKey(const Key('repeat-end-count'))),
          isA<FilledButton>(),
          reason: 'S-27726: a fresh ON starts with After',
        );
        expect(
          tester
              .widget<NumericFieldWithDoneBar>(
                find.byKey(const Key('repeat-count')),
              )
              .controller!
              .text,
          '8',
          reason: 'S-27726: a fresh ON starts with 8 times',
        );
      },
    );
  });

  group(
    'S-27726b: the same sheet starts clean when Repeat is turned on again',
    () {
      testWidgets(
        'S-27726b: stale Every-3-Months/extra-weekday/On-date settings are '
        'dropped in the SAME sheet when the switch goes OFF then ON',
        (tester) async {
          final (repo, workoutState, calendarState) = await _emptyFixture();
          await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
          await _openNewPlanSheet(tester);

          await tester.tap(find.byKey(const Key('repeat-switch')));
          await tester.pumpAndSettle();
          await _changeEvery(tester, '3');
          await _changeUnit(tester, 'Months');
          await _changeUnit(tester, 'Weeks');
          final plannedWeekday = _tomorrow.weekday;
          final other = plannedWeekday % 7 + 1;
          await tester.tap(find.byKey(Key('repeat-weekday-$other')));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('repeat-end-date')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('repeat-until')));
          await tester.pumpAndSettle();
          final firstExpected = DateTime(
            _tomorrow.year,
            _tomorrow.month,
            _tomorrow.day + 1,
          );
          // The picker opens on the month of the initial candidate (day + 7).
          // The first selectable day can sit one page earlier.
          final displayed = DateTime(
            _tomorrow.year,
            _tomorrow.month,
            _tomorrow.day + 7,
          );
          if (displayed.month != firstExpected.month) {
            await tester.tap(find.byTooltip('Previous month'));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('${firstExpected.day}').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('repeat-switch')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('repeat-switch')));
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<DropdownButtonFormField<int>>(
                  find.byKey(const Key('repeat-every')),
                )
                .initialValue,
            1,
            reason: 'S-27726b: the same sheet ON again starts at every 1',
          );
          expect(
            tester
                .widget<DropdownButtonFormField<RecurrenceUnit>>(
                  find.byKey(const Key('repeat-unit')),
                )
                .initialValue,
            RecurrenceUnit.week,
            reason: 'S-27726b: the same sheet ON again starts at Weeks',
          );
          for (var day = 1; day <= 7; day++) {
            expect(
              find.byKey(Key('repeat-weekday-$day')),
              findsOneWidget,
              reason: 'S-27726b: weekday chip $day exists after the reset',
            );
            expect(
              tester
                  .widget<FilterChip>(find.byKey(Key('repeat-weekday-$day')))
                  .selected,
              day == plannedWeekday,
              reason:
                  'S-27726b: after the reset only the planned day '
                  '($plannedWeekday) is ticked, chip $day is not stale',
            );
          }
          expect(
            tester.widget(find.byKey(const Key('repeat-end-count'))),
            isA<FilledButton>(),
            reason: 'S-27726b: the same sheet ON again starts with After',
          );
          expect(
            find.byKey(const Key('repeat-count')),
            findsOneWidget,
            reason: 'S-27726b: After shows the count field after the reset',
          );
          expect(
            find.byKey(const Key('repeat-until')),
            findsNothing,
            reason:
                'S-27726b: no On-date leftover after the reset in the same sheet',
          );
          expect(
            tester
                .widget<NumericFieldWithDoneBar>(
                  find.byKey(const Key('repeat-count')),
                )
                .controller!
                .text,
            '8',
            reason: 'S-27726b: the same sheet ON again starts with 8 times',
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Add Session'),
                )
                .onPressed,
            isNotNull,
            reason:
                'S-27726b: Add Session is enabled with the clean default '
                'settings',
          );
        },
      );
    },
  );

  group('S-27718b: Add Session with Repeat on creates the series', () {
    testWidgets(
      'S-27718b: daily After 3 titled Tmp creates three rows sharing one rule',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);
        await _openNewPlanSheet(tester);

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await _changeUnit(tester, 'Days');
        await tester.enterText(find.byKey(const Key('repeat-count')), '3');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Tmp');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add Session'));
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(
          rows,
          hasLength(3),
          reason: 'S-27718b: the daily After-3 rule creates three rows',
        );
        final sorted = [...rows]
          ..sort((a, b) => a.scheduledDateMs.compareTo(b.scheduledDateMs));
        final seriesIds = <String>{};
        for (var i = 0; i < 3; i++) {
          final expectedDate = DateTime(
            _tomorrow.year,
            _tomorrow.month,
            _tomorrow.day + i,
          );
          expect(
            sorted[i].scheduledDateMs,
            expectedDate.millisecondsSinceEpoch,
            reason: 'S-27718b: row $i is on the pumped day +$i',
          );
          expect(
            sorted[i].recurrenceRule,
            isNotNull,
            reason: 'S-27718b: row $i carries a recurrence rule',
          );
          final parsed = RecurrenceRule.tryParse(sorted[i].recurrenceRule!);
          expect(
            parsed,
            isNotNull,
            reason: 'S-27718b: row $i rule text parses',
          );
          seriesIds.add(parsed!.series);
          expect(
            parsed.count,
            3,
            reason: 'S-27718b: row $i rule states After 3',
          );
          expect(
            sorted[i].title,
            'Tmp',
            reason: 'S-27718b: row $i carries the title on all rows',
          );
        }
        expect(
          seriesIds,
          hasLength(1),
          reason: 'S-27718b: all three rows share one series id',
        );
      },
    );
  });

  group('S-27720b: the sheet stays below the status bar', () {
    testWidgets(
      'S-27720b: with a 47 px status-bar inset the sheet header starts below it',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 47);
        tester.view.viewPadding = const FakeViewPadding(top: 47);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: _tomorrow,
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

        await tester.tap(find.text('+ New Planned Session'));
        await tester.pumpAndSettle();
        // Open the Repeat section so the sheet is as tall as it gets.
        await tester.ensureVisible(find.byKey(const Key('repeat-switch')));
        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();

        // Scroll back to the top of the sheet.
        final scrollable = find.byType(SingleChildScrollView).last;
        await tester.drag(scrollable, const Offset(0, 2000));
        await tester.pumpAndSettle();

        final headerTop = tester.getRect(find.text('New Planned Session')).top;
        expect(
          headerTop,
          greaterThanOrEqualTo(47),
          reason:
              'S-27720b: the header must not sit under the status bar (47 px)',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'S-27720b: no exception',
        );
      },
    );
  });

  group('S-27720: layout at 390x844 with the keyboard up', () {
    testWidgets(
      'S-27720: no overflow with the keyboard up and a scroll reaches '
      'Add Session',
      (tester) async {
        final (repo, workoutState, calendarState) = await _emptyFixture();

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 291);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: DaySessionListScreen(
              date: _tomorrow,
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

        await tester.tap(find.text('+ New Planned Session'));
        await tester.pumpAndSettle();
        final sheetTop = tester.getRect(find.text('New Planned Session')).top;

        // The sheet's own scroll view is the last one in the overlay.
        final scrollable = find.byType(SingleChildScrollView).last;
        Future<void> scrollToKey(Key key) async {
          for (var guard = 0; guard < 40; guard++) {
            final rect = tester.getRect(find.byKey(key));
            if (rect.top >= 0 && rect.bottom <= 844 - 291) return;
            await tester.drag(scrollable, const Offset(0, -120));
            await tester.pumpAndSettle();
          }
        }

        await scrollToKey(const Key('repeat-switch'));
        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await scrollToKey(const Key('repeat-count'));
        final countRect = tester.getRect(find.byKey(const Key('repeat-count')));
        await tester.tap(find.byKey(const Key('repeat-count')));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'S-27720: no overflow exception at 390x844 with the keyboard up',
        );

        const visibleBottom = 844.0 - 291.0;
        final buttonFinder = find.widgetWithText(FilledButton, 'Add Session');
        for (var guard = 0; guard < 40; guard++) {
          final rect = tester.getRect(buttonFinder);
          if (rect.top >= 0 && rect.bottom <= visibleBottom) break;
          await tester.drag(scrollable, const Offset(0, -150));
          await tester.pumpAndSettle();
        }
        final buttonRect = tester.getRect(buttonFinder);
        // ignore: avoid_print
        print(
          'S-27720 rects: sheetTop=$sheetTop repeatCount=$countRect '
          'addButton=$buttonRect visibleBottom=$visibleBottom',
        );
        expect(
          buttonRect.bottom,
          lessThanOrEqualTo(visibleBottom),
          reason:
              'S-27720: a scroll of the sheet reaches Add Session above the '
              'keyboard inset',
        );
        expect(
          buttonRect.top,
          greaterThanOrEqualTo(0),
          reason: 'S-27720: the button is on the 844-tall surface',
        );
      },
    );
  });

  group('S-27724: edit a plain row with Repeat on', () {
    testWidgets(
      'S-27724: the kept row is the first of the series and only the later '
      'dates are created',
      (tester) async {
        final (repo, workoutState, calendarState) = await _seededSingle(
          _tomorrow,
        );
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await tester.tap(find.text('Plan A'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await _changeUnit(tester, 'Days');
        await tester.enterText(find.byKey(const Key('repeat-count')), '3');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        final rows = await repo.getPlannedSessions();
        expect(
          rows,
          hasLength(3),
          reason:
              'S-27724: the kept row plus two later rows, never a doubled '
              'planned day',
        );
        final kept = rows.singleWhere((row) => row.id == 'p-single');
        expect(
          kept.scheduledDateMs,
          _tomorrow.millisecondsSinceEpoch,
          reason: 'S-27724: the seeded row stays on tomorrow',
        );
        expect(
          kept.recurrenceRule,
          isNotNull,
          reason: 'S-27724: the kept row gets the rule text stamped',
        );
        final parsed = RecurrenceRule.tryParse(kept.recurrenceRule!);
        expect(
          parsed,
          isNotNull,
          reason: 'S-27724: the kept row rule text parses',
        );
        expect(
          parsed!.count,
          3,
          reason: 'S-27724: the kept row rule states After 3',
        );

        final later = rows.where((row) => row.id != 'p-single').toList();
        expect(
          later,
          hasLength(2),
          reason: 'S-27724: only the two LATER dates are created',
        );
        final expectedDates = {
          DateTime(
            _tomorrow.year,
            _tomorrow.month,
            _tomorrow.day + 1,
          ).millisecondsSinceEpoch,
          DateTime(
            _tomorrow.year,
            _tomorrow.month,
            _tomorrow.day + 2,
          ).millisecondsSinceEpoch,
        };
        expect(
          later.map((row) => row.scheduledDateMs).toSet(),
          expectedDates,
          reason: 'S-27724: the later rows are tomorrow+1 and tomorrow+2',
        );
        for (final row in later) {
          expect(
            row.recurrenceRule,
            kept.recurrenceRule,
            reason: 'S-27724: a later row carries the same rule text',
          );
        }
      },
    );
  });

  group('S-27724b: a failed later-dates write says so', () {
    testWidgets(
      'S-27724b: a failed later-dates write shows the message and keeps '
      'only the stamped kept row',
      (tester) async {
        final repo = _FailingCreateRepo();
        await repo.initialize();
        final now = DateTime.now().millisecondsSinceEpoch;
        await repo.createPlannedSession(
          PlannedSession(
            id: 'p-single',
            ownerUserId: 'user-1',
            scheduledDateMs: _tomorrow.millisecondsSinceEpoch,
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
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await tester.tap(find.text('Plan A'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('repeat-switch')));
        await tester.pumpAndSettle();
        await _changeUnit(tester, 'Days');
        await tester.enterText(find.byKey(const Key('repeat-count')), '3');
        await tester.pumpAndSettle();

        repo.failCreates = true;
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not save. Try again.'),
          findsOneWidget,
          reason:
              'S-27724b: the failed later-dates write shows the error message',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'S-27724b: the failure is handled, nothing unhandled escapes',
        );

        final rows = await repo.getPlannedSessions();
        expect(
          rows,
          hasLength(1),
          reason: 'S-27724b: only the kept plan is stored, no later rows',
        );
        expect(
          rows.single.id,
          'p-single',
          reason: 'S-27724b: the stored row is the seeded kept plan',
        );
        expect(
          rows.single.recurrenceRule,
          isNotNull,
          reason:
              'S-27724b: the kept row got the rule text stamped before '
              'the failing write',
        );
      },
    );
  });

  group('S-27725: edit sheet of a series row', () {
    testWidgets(
      'S-27725: a series row shows the read-only line and no switch',
      (tester) async {
        final (repo, workoutState, calendarState) = await _seededSeries();
        await pumpDay(tester, _tomorrow, repo, workoutState, calendarState);

        await tester.tap(find.text('Upper'));
        await tester.pumpAndSettle();

        final described = _seriesRule.describe(_tomorrow);
        final expected =
            'Repeats ${described[0].toLowerCase()}${described.substring(1)}';
        expect(
          find.byKey(const Key('repeat-series-summary')),
          findsOneWidget,
          reason: 'S-27725: the read-only series line is in the sheet',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('repeat-series-summary')))
              .data,
          expected,
          reason: 'S-27725: the line equals the lowered describe of the series',
        );
        expect(
          find.byKey(const Key('repeat-switch')),
          findsNothing,
          reason: 'S-27725: a series row has no Repeat switch',
        );
        const otherKeys = [
          'repeat-every',
          'repeat-unit',
          'repeat-weekday-1',
          'repeat-weekday-4',
          'repeat-end-count',
          'repeat-end-date',
          'repeat-count',
          'repeat-until',
          'repeat-summary',
        ];
        for (final key in otherKeys) {
          expect(
            find.byKey(Key(key)),
            findsNothing,
            reason: "S-27725: '$key' is not in a series row's sheet",
          );
        }
      },
    );
  });
}
