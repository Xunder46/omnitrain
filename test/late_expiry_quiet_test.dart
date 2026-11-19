// Plan 273: an interval that ended while the phone was locked was already
// announced by the scheduled notification, so noticing it late must not play
// the in-app alert a second time. An interval that ends on time still does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A cardio session holding one timed interval of 1 s. The state's clock runs
/// [startedAgo] behind the real one, so an interval started from the screen is
/// stamped in the past: its first tick finds it long over, as the first tick
/// after a locked phone does.
Future<
  ({
    WorkoutState workoutState,
    MockWorkoutRepository repo,
    SettingsState settings,
    String effortId,
    String name,
  })
>
_deps({required Duration startedAgo}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // First-run coach-mark sheets would sit in front of the Start button.
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  final workoutState = WorkoutState(
    repo,
    clock: () => DateTime.now().subtract(startedAgo),
  );
  final settings = SettingsState(repo, FakePreferencesService());
  await settings.initialize();
  await workoutState.createNewSession(modality: 'cardio_endurance');
  final exercise = (await repo.getExercises()).firstWhere(
    (e) => e.capabilities.contains('time'),
  );
  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: 'timed',
  );
  await workoutState.updateEntryValue(effortId, 0, 'duration', 1);
  return (
    workoutState: workoutState,
    repo: repo,
    settings: settings,
    effortId: effortId,
    name: exercise.name,
  );
}

Future<FakeTimerAlertService> _openAndWait(
  WidgetTester tester,
  ({
    WorkoutState workoutState,
    MockWorkoutRepository repo,
    SettingsState settings,
    String effortId,
    String name,
  })
  d,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final alerts = FakeTimerAlertService();
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: d.workoutState,
        routineState: RoutineState(d.repo),
        sessionSummaryService: SessionSummaryService(d.repo),
        timerAlertService: alerts,
        settingsState: d.settings,
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump();
    if (find.text(d.name).evaluate().isNotEmpty) break;
  }
  await tester.tap(find.text(d.name));
  await tester.pumpAndSettle();
  // Start the interval from the screen: its first tick comes one second later.
  await tester.tap(find.widgetWithText(FilledButton, 'Start').first);
  await tester.pump();
  // Let the one-second tick notice the interval is over.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return alerts;
}

bool _finished(WorkoutState s, String effortId) => s
    .getTimedInstancesForEffort(effortId)
    .any((i) => i.state == TimedState.finished);

void main() {
  testWidgets('S-27301 an interval that ended 60 s ago plays no second alert', (
    tester,
  ) async {
    final d = await _deps(startedAgo: const Duration(seconds: 60));
    final alerts = await _openAndWait(tester, d);

    expect(_finished(d.workoutState, d.effortId), isTrue);
    expect(alerts.effortAlertSoundIds, isEmpty);
  });

  testWidgets('S-27302 an interval that ends on time still plays its alert (control)', (
    tester,
  ) async {
    final d = await _deps(startedAgo: Duration.zero);
    final alerts = await _openAndWait(tester, d);

    expect(_finished(d.workoutState, d.effortId), isTrue);
    expect(alerts.effortAlertSoundIds, hasLength(1));
  });
}
