// Plan 267: a workout's date and start time can be changed from the summary's
// menu; its length is kept and a time in the future is refused.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A finished session that started 3 days ago and lasted 40 minutes.
Future<({MockWorkoutRepository repo, WorkoutState state, DateTime start})>
_finishedSession() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = WorkoutState(repo);
  await state.createNewSession();
  final real = DateTime.now().subtract(const Duration(days: 3));
  final start = DateTime(real.year, real.month, real.day, 9, 30);
  expect(await state.updateSessionStart(start.millisecondsSinceEpoch), isTrue);
  await state.updateSessionEndTime(40 * 60);
  await state.updateSessionFeeling(state.currentSession!.id, 3);
  return (repo: repo, state: state, start: start);
}

void main() {
  test(
    'S-26701 the start moves and a finished session keeps its length',
    () async {
      final s = await _finishedSession();
      final id = s.state.currentSession!.id;
      final before = (await s.repo.getSession(id))!;
      final length = before.endedAtMs! - before.startedAtMs;

      final next = s.start.subtract(const Duration(days: 2, hours: 1));
      expect(
        await s.state.updateSessionStart(next.millisecondsSinceEpoch),
        isTrue,
      );

      final after = (await s.repo.getSession(id))!;
      expect(after.startedAtMs, next.millisecondsSinceEpoch);
      expect(after.endedAtMs! - after.startedAtMs, length);
      expect(s.state.currentSession!.startedAtMs, next.millisecondsSinceEpoch);
    },
  );

  test(
    'S-26702 a start in the future is refused and nothing changes',
    () async {
      final s = await _finishedSession();
      final id = s.state.currentSession!.id;
      final before = (await s.repo.getSession(id))!;

      final future = DateTime.now().add(const Duration(days: 1));
      expect(
        await s.state.updateSessionStart(future.millisecondsSinceEpoch),
        isFalse,
      );

      final after = (await s.repo.getSession(id))!;
      expect(after.startedAtMs, before.startedAtMs);
      expect(after.endedAtMs, before.endedAtMs);
    },
  );

  testWidgets('S-26703 the summary menu changes the date and keeps the time', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await _finishedSession();
    final id = s.state.currentSession!.id;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionSummaryScreen(
          workoutState: s.state,
          routineState: RoutineState(s.repo),
          sessionSummaryService: SessionSummaryService(s.repo),
          settingsState: SettingsState(s.repo, fakePreferencesService()),
          timerAlertService: FakeTimerAlertService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change date & time'));
    await tester.pumpAndSettle();

    // Another day of the month the picker opens on (never crossing months).
    final day = s.start.day >= 2 ? s.start.day - 1 : s.start.day + 1;
    await tester.tap(find.text('$day').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The time picker opens on the current time; confirm it unchanged.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final stored = DateTime.fromMillisecondsSinceEpoch(
      (await s.repo.getSession(id))!.startedAtMs,
    );
    expect(stored.day, day);
    expect(stored.month, s.start.month);
    expect(stored.hour, 9);
    expect(stored.minute, 30);
    expect(find.text('Date and time changed'), findsOneWidget);
  });
}
