// Phone hardening Phase 2 — the Session Summary never throws on an inverted
// session window (a stored `endedAtMs` before `startedAtMs`).
//
// Scenarios: S-153, S-154 of
// `docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.md`.

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

// ─── Fixture ────────────────────────────────────────────────────────────────

/// The owner's stored pair: the start is the value from the crash log
/// (`Invalid argument(s): 1791419191803`), the end sits one hour before it.
const int _invertedStartMs = 1791419191803;
const int _invertedEndMs = _invertedStartMs - 3600000;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A `SettingsState` with the feeling prompt off, so the summary screen never
/// opens a sheet over the render under test.
Future<SettingsState> _settings(MockWorkoutRepository repo) async {
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);
  return settings;
}

/// One session with one segment, one effort on it, and the given closed rests
/// — each a `(restStartMs, restEndMs)` pair — on that effort.
Future<void> _seedSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String title,
  required List<(int, int)> rests,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      title: title,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final segmentId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segmentId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final effortId = 'e-$sessionId-0';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      topLevelOrderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-$sessionId-0',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createExercise(
    Exercise(
      id: 'ex-$sessionId-0',
      name: 'Bench Press',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  for (var i = 0; i < rests.length; i++) {
    final (restStartMs, restEndMs) = rests[i];
    await repo.createEntryRest(
      EntryRest(
        id: 'rest-$effortId-$i',
        effortId: effortId,
        entryIndex: i,
        restStartMs: restStartMs,
        restEndMs: restEndMs,
        createdAtMs: restStartMs,
        updatedAtMs: restEndMs,
      ),
    );
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-153 — the inverted window from the owner's log
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'S-153: an inverted session window contributes no rest and the summary still renders',
    (tester) async {
      final repo = await _freshRepo();
      await _seedSession(
        repo,
        sessionId: 's-inverted',
        startedAtMs: _invertedStartMs,
        endedAtMs: _invertedEndMs,
        title: 'Inverted Window Session',
        rests: [(_invertedStartMs + 1000, _invertedStartMs + 61000)],
      );

      // The trigger from the owner's log: `computeSessionRestTimeMs` on the
      // stored pair, then the summary screen on the same session. At the base
      // the clamp sees `lowerLimit > upperLimit` and throws
      // `ArgumentError(1791419191803)` here.
      final restTimeMs = await SessionSummaryService(
        repo,
      ).computeSessionRestTimeMs('s-inverted');
      expect(
        restTimeMs,
        0,
        reason: 'the empty window clips the one closed rest to zero length',
      );

      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final workoutState = WorkoutState(repo);
      await workoutState.loadHistoricalSession('s-inverted');

      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            workoutState: workoutState,
            routineState: RoutineState(repo),
            sessionSummaryService: SessionSummaryService(repo),
            settingsState: await _settings(repo),
            timerAlertService: FakeTimerAlertService(),
            openedFromCalendar: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Inverted Window Session'), findsOneWidget);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // S-154 — the negative guard: an ordinary session's total is unchanged
  // ══════════════════════════════════════════════════════════════════════════

  test(
    'S-154: an ordinary session merges overlapping rests once and keeps its total',
    () async {
      final repo = await _freshRepo();
      await _seedSession(
        repo,
        sessionId: 's-ordinary',
        startedAtMs: 1000000,
        endedAtMs: 1600000,
        title: 'Ordinary Session',
        rests: [
          (1030000, 1090000),
          (1080000, 1120000),
          (1100000, 1130000),
          (900000, 950000),
        ],
      );

      final restTimeMs = await SessionSummaryService(
        repo,
      ).computeSessionRestTimeMs('s-ordinary');
      expect(
        restTimeMs,
        100000,
        reason: 'the merged union is 1_030_000…1_130_000; the rest before '
            'the window contributes nothing',
      );
    },
  );
}
