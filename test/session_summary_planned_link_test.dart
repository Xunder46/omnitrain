// A finished workout started from a planned session is linked to that plan
// when the summary opens — not only when "Done" is tapped — so leaving the
// summary with Back cannot leave the plan uncompleted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const _sessionId = 's-planned';

Future<MockWorkoutRepository> _repoWithEndedSession() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.createSession(
    TrainingSession(
      id: _sessionId,
      ownerUserId: 'user-1',
      startedAtMs: 1000000,
      endedAtMs: 1600000,
      title: 'Planned Session',
      createdAtMs: 1000000,
      updatedAtMs: 1600000,
    ),
  );
  return repo;
}

Future<void> _pumpSummary(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  required List<String> saved,
  required bool openedFromCalendar,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final workoutState = WorkoutState(repo);
  await workoutState.loadHistoricalSession(_sessionId);
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);

  await tester.pumpWidget(
    MaterialApp(
      home: SessionSummaryScreen(
        workoutState: workoutState,
        routineState: RoutineState(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: settings,
        timerAlertService: FakeTimerAlertService(),
        openedFromCalendar: openedFromCalendar,
        onSessionSaved: (id) async => saved.add(id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'opening the summary of a just-finished session links it without Done',
    (tester) async {
      final repo = await _repoWithEndedSession();
      final saved = <String>[];

      await _pumpSummary(
        tester,
        repo,
        saved: saved,
        openedFromCalendar: false,
      );

      expect(saved, [_sessionId]);
    },
  );

  testWidgets('tapping Done after the summary opened does not link twice', (
    tester,
  ) async {
    final repo = await _repoWithEndedSession();
    final saved = <String>[];

    await _pumpSummary(tester, repo, saved: saved, openedFromCalendar: false);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved, [_sessionId]);
  });

  testWidgets('a historical summary never links anything', (tester) async {
    final repo = await _repoWithEndedSession();
    final saved = <String>[];

    await _pumpSummary(tester, repo, saved: saved, openedFromCalendar: true);

    expect(saved, isEmpty);
  });
}
