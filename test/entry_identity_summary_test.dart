// Stats PR 3a2, Phase 2 — the Session Summary's DISTANCE rows read the same
// entries the writes address. Stats PR 4c removed the Stats screen's distance
// card, so S-858's Stats half asserts the readout is gone.
//
// The rows the section lists and the rows a distance write reaches are one list
// (D-328), so a row that reads "· 4" is the fourth entry the write numbers 4. A
// leftover row appears in no row and no total.
//
// Scenarios S-855, S-856 and S-858 of
// `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`.
// The state half of S-858 is `test/entry_identity_test.dart`'s.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/session_distance_card.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

// ─── Fixture ────────────────────────────────────────────────────────────────

const _easyRun = 'Easy Run';

/// 09:00 on the day [daysAgo] days ago, so the Summary opens as a historical
/// one and Stats buckets the session by the same day.
int _dayStart(int daysAgo) {
  final now = DateTime.now();
  final day = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: daysAgo));
  return DateTime(day.year, day.month, day.day, 9).millisecondsSinceEpoch;
}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A `SettingsState` with the feeling prompt off, so the Summary never opens a
/// sheet over the rows under test.
Future<SettingsState> _settings(
  MockWorkoutRepository repo, {
  String unit = 'km',
}) async {
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);
  await settings.setPreferredDistanceUnit(unit);
  return settings;
}

/// A completed session dated [daysAgo], with the exercise its effort names.
Future<String> _seedSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  String? modality,
}) async {
  final start = _dayStart(daysAgo);
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + 3600000,
      modality: modality,
      createdAtMs: start,
      updatedAtMs: start + 3600000,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  return sessionId;
}

/// A timed effort on [sessionId], one finished instance and one distance row
/// per entry.
Future<void> _seedTimedEffort(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required String exerciseId,
  required List<(int, int, double)> entries,
}) async {
  final start = _dayStart(1);
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      topLevelOrderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );

  for (final (number, durationSecs, metres) in entries) {
    await repo.createTimedInstance(
      TimedInstance(
        id: 'ti-$effortId-$number',
        effortId: effortId,
        entryIndex: number,
        targetDurationSecs: durationSecs,
        actualDurationSecs: durationSecs,
        startedAtMs: start,
        finishedAtMs: start + durationSecs * 1000,
        state: TimedState.finished,
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    await repo.createObservation(
      distanceRow(effortId, number, metres, atMs: start + number),
    );
  }
}

// ─── Widget harness ─────────────────────────────────────────────────────────

Future<void> _pumpSummary(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  required SettingsState settings,
  String? sessionId,
  WorkoutState? workoutState,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  final state = workoutState ?? WorkoutState(repo);
  if (workoutState == null) {
    await state.loadHistoricalSession(sessionId!);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: SessionSummaryScreen(
        workoutState: state,
        routineState: RoutineState(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: settings,
        timerAlertService: FakeTimerAlertService(),
        openedFromCalendar: workoutState == null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpStats(
  WidgetTester tester,
  MockWorkoutRepository repo,
  SettingsState settings,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 1600));
  await tester.pumpWidget(
    MaterialApp(
      home: StatsScreen(
        workoutState: WorkoutState(repo),
        settingsState: settings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The full text of the Distance section, in render order.
List<String> _sectionTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(SessionDistanceCard),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? '')
    .toList();

void main() {
  // ─── S-855: deleting two timed entries keeps each distance with its entry ──

  testWidgets('S-855 the Summary names the two entries that are left', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await seedExercise(repo, id: 'ex-run4', name: _easyRun);
    await _seedSession(
      repo,
      sessionId: 's-855',
      daysAgo: 1,
      modality: 'cardio_endurance',
    );
    await _seedTimedEffort(
      repo,
      sessionId: 's-855',
      effortId: 'e-run4',
      exerciseId: 'ex-run4',
      entries: [
        (0, 600, 1000.0),
        (1, 600, 2000.0),
        (2, 600, 3000.0),
        (3, 600, 4000.0),
      ],
    );

    final state = WorkoutState(repo);
    await state.loadHistoricalSession('s-855');
    await state.deleteEntry('e-run4', 0);
    await state.deleteEntry('e-run4', 0);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-855',
      settings: await _settings(repo),
      workoutState: state,
    );

    expect(_sectionTexts(tester), [
      '$_easyRun · 1',
      '3.00',
      'KM',
      '$_easyRun · 2',
      '4.00',
      'KM',
    ]);
  });

  // ─── S-856: the F-5 sequence, as the Summary reads it ─────────────────────

  testWidgets('S-856 the Summary names the entry that holds the 2000 m', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await seedExercise(repo, id: 'ex-run', name: _easyRun);

    final state = WorkoutState(repo);
    await state.createNewSession(modality: Modality.cardioEndurance);
    final effortId = await state.addExerciseToSession(
      Exercise(
        id: 'ex-run',
        name: _easyRun,
        createdAtMs: fixtureStart,
        updatedAtMs: fixtureStart,
      ),
      effortKindOverride: 'timed',
    );
    for (var i = 0; i < 3; i++) {
      await state.addEntry(effortId);
    }

    await state.deleteEntry(effortId, 0);
    await state.addEntry(effortId);
    await state.setEntryDistance(effortId, 3, 2000.0);
    await state.addEntry(effortId);

    await _pumpSummary(
      tester,
      repo,
      settings: await _settings(repo),
      workoutState: state,
    );

    expect(_sectionTexts(tester), [
      '$_easyRun · 1',
      SessionDistanceCard.absentValue,
      'KM',
      '$_easyRun · 2',
      SessionDistanceCard.absentValue,
      'KM',
      '$_easyRun · 3',
      SessionDistanceCard.absentValue,
      'KM',
      '$_easyRun · 4',
      '2.00',
      'KM',
      '$_easyRun · 5',
      SessionDistanceCard.absentValue,
      'KM',
    ]);
  });

  // ─── S-858: a leftover never shows and never counts ──────────────────────

  testWidgets('S-858 the Summary shows one row and Stats no distance', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await seedExercise(repo, id: 'ex-lo', name: _easyRun);
    await _seedSession(
      repo,
      sessionId: 's-858',
      daysAgo: 1,
      modality: 'cardio_endurance',
    );
    await _seedTimedEffort(
      repo,
      sessionId: 's-858',
      effortId: 'e-lo',
      exerciseId: 'ex-lo',
      entries: [(0, 1800, 5000.0)],
    );
    // A row past the last entry: an old writer's leftover.
    await repo.createObservation(
      distanceRow('e-lo', 7, 1000.0, atMs: _dayStart(1) + 7),
    );

    final state = WorkoutState(repo);
    await state.loadHistoricalSession('s-858');
    await state.setEntryDistance('e-lo', 0, 5500.0);

    final settings = await _settings(repo);
    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-858',
      settings: settings,
      workoutState: state,
    );

    expect(_sectionTexts(tester), [
      _easyRun,
      '5.50',
      'KM',
    ], reason: 'D-328: a lone entry carries no "· n"');

    await _pumpStats(tester, repo, settings);
    // 4c: the cardio card that read these entries is gone from the screen.
    expect(find.textContaining('Distance: 5.50 km'), findsNothing);
    expect(find.textContaining('Pace: 327 s/km'), findsNothing);

    final leftover = (await repo.getEffortObservations(
      'e-lo',
    )).firstWhere((row) => row.id == 'obs-e-lo-7-distance');
    expect(leftover.valueReal, 1000.0);
  });
}
