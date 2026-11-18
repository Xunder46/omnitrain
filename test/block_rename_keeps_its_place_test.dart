// Plan 234 — renaming a session block keeps it where it is.
// Scenarios S-23401..S-23403
// (docs/plans/2026-11-17-234-block-rename-keeps-its-place-plan).
// Mock repository only: blocks are seeded before the first pump, no Hive
// harness, and no real Future.delayed inside testWidgets (FakeAsync never
// advances real time).
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

const _seedCreatedAtMs = 1700000000000;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<void> _renameFirstBlock(WidgetTester tester, String newName) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();

  expect(find.text('Rename Block'), findsOneWidget);
  await tester.enterText(find.byType(TextField), newName);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('Plan 234 — block rename keeps its top-level position', () {
    // S-23401: the block is stored with orderIndex 0 and topLevelOrderIndex 3;
    // after the rename the stored row must still read 3.
    testWidgets('rename keeps the seeded topLevelOrderIndex (S-23401)', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      final blockId = await workoutState.addSessionBlock();
      final sessionId = workoutState.currentSession!.id;
      await workoutState.updateSessionBlock(
        SessionBlock(
          id: blockId,
          sessionId: sessionId,
          name: 'Main',
          orderIndex: 0,
          topLevelOrderIndex: 3,
          createdAtMs: _seedCreatedAtMs,
          updatedAtMs: _seedCreatedAtMs,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pump();

      await _renameFirstBlock(tester, 'Warm-Up');

      expect(workoutState.getSessionBlocks().single.topLevelOrderIndex, 3);
      final stored = await repo.getSessionBlocks(sessionId);
      expect(stored.single.topLevelOrderIndex, 3);
    });

    // S-23402: nothing else changes — new name, same orderIndex, same
    // createdAtMs.
    testWidgets('rename writes the new name and keeps order/created (S-23402)', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      final blockId = await workoutState.addSessionBlock();
      final sessionId = workoutState.currentSession!.id;
      await workoutState.updateSessionBlock(
        SessionBlock(
          id: blockId,
          sessionId: sessionId,
          name: 'Main',
          orderIndex: 0,
          topLevelOrderIndex: 3,
          createdAtMs: _seedCreatedAtMs,
          updatedAtMs: _seedCreatedAtMs,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pump();

      await _renameFirstBlock(tester, 'Warm-Up');

      final stored = await repo.getSessionBlocks(sessionId);
      expect(stored.single.name, 'Warm-Up');
      expect(stored.single.orderIndex, 0);
      expect(stored.single.createdAtMs, _seedCreatedAtMs);
    });

    // S-23403: a block never reordered (topLevelOrderIndex null, orderIndex 0)
    // stays at 0 — the effective stored value is orderIndex, unchanged.
    testWidgets('rename keeps a never-reordered block at its orderIndex (S-23403)', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final routineState = RoutineState(repo);
      await workoutState.createNewSession(isRolling: true);
      final blockId = await workoutState.addSessionBlock();
      final sessionId = workoutState.currentSession!.id;
      await workoutState.updateSessionBlock(
        SessionBlock(
          id: blockId,
          sessionId: sessionId,
          name: 'Main',
          orderIndex: 0,
          createdAtMs: _seedCreatedAtMs,
          updatedAtMs: _seedCreatedAtMs,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: SessionSummaryService(repo),
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repo, fakePreferencesService()),
          ),
        ),
      );
      await tester.pump();

      await _renameFirstBlock(tester, 'Warm-Up');

      final stored = await repo.getSessionBlocks(sessionId);
      // Mock keeps a null index as null; the stored value is effective as
      // orderIndex (the repository's own _effectiveBlockTopLevelOrder).
      expect(stored.single.topLevelOrderIndex ?? stored.single.orderIndex, 0);
    });
  });
}
