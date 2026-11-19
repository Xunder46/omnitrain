// Plan 262: on the calendar's New Planned Session form, Add Session stays off
// in Routine mode until a routine is chosen, so it can never save as Free
// Training by accident.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/calendar/day_session_list_screen.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _openForm(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-262',
      name: 'Push day',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
  );
  final calendarState = CalendarState(repo);
  await calendarState.init();
  final routineState = RoutineState(repo);
  await routineState.loadRoutines();
  await tester.pumpWidget(
    MaterialApp(
      home: DaySessionListScreen(
        date: DateTime(2099, 12, 31),
        calendarState: calendarState,
        routineState: routineState,
        workoutState: WorkoutState(repo),
        routineSessionService: RoutineSessionService(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: SettingsState(repo, fakePreferencesService()),
        timerAlertService: FakeTimerAlertService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '+ New Planned Session'));
  await tester.pumpAndSettle();
  return repo;
}

FilledButton _addButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(
    of: find.text('Add Session'),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  testWidgets('S-26201 Free Training mode can add straight away', (
    tester,
  ) async {
    await _openForm(tester);
    expect(_addButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'S-26202 Routine mode with no routine chosen has Add Session off',
    (tester) async {
      await _openForm(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Routine'));
      await tester.pumpAndSettle();
      expect(_addButton(tester).onPressed, isNull);
    },
  );

  testWidgets('S-26203 choosing a routine turns Add Session on', (
    tester,
  ) async {
    await _openForm(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Routine'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push day').last);
    await tester.pumpAndSettle();
    expect(_addButton(tester).onPressed, isNotNull);
  });
}
