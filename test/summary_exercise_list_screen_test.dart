// Plan 245, P3b — the Session Summary's EXERCISES card as the screen shows it.
//
// One row per exercise with logged work, between the group cards and
// SESSION NOTE: the exercise name, then one short text per logged item
// (`10×60 kg`, `01:00`). The month grid, the month label and the
// `N workout days / M rest days` line are gone; `Open Calendar` stays.
//
// Scenarios: S-24511..S-24516 of
// `docs/plans/2026-11-18-245-summary-exercise-list-plan/2026-11-18-245-summary-exercise-list-plan.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/core/utils/unit_formatter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ─── Fixture ────────────────────────────────────────────────────────────────

const _benchPress = 'Bench Press';
const _plank = 'Plank';

/// 09:00 on the day [daysAgo] days ago — a past day, so the Summary opens as a
/// historical one.
DateTime _seededDay(int daysAgo) {
  final now = DateTime.now();
  final day = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: daysAgo));
  return DateTime(day.year, day.month, day.day, 9);
}

int _dayStartMs(int daysAgo) => _seededDay(daysAgo).millisecondsSinceEpoch;

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A `SettingsState` with the feeling prompt off, so the summary screen never
/// opens a sheet over the rows under test.
Future<SettingsState> _settings(
  MockWorkoutRepository repo, {
  String weightUnit = 'kg',
}) async {
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);
  await settings.setPreferredWeightUnit(weightUnit);
  return settings;
}

/// One completed session with the strength fixture of plan 245: `Bench Press`
/// (`set`) with two logged sets — 10 reps at 60 kg, then 8 reps at 60 kg — and
/// `Plank` (`timed`) with one hold finished at 60 s. [isRolling] marks the
/// session a rolling one, stored on `TrainingSession` itself.
Future<String> _seedStrength(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  String? modality,
  bool isRolling = false,
}) async {
  final start = _dayStartMs(daysAgo);
  final end = start + 3600000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: end,
      modality: modality,
      isRolling: isRolling,
      title: 'Strength',
      createdAtMs: start,
      updatedAtMs: end,
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
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );

  final setEffortId = 'e-$sessionId-0';
  await repo.createEffort(
    SegmentEffort(
      id: setEffortId,
      segmentId: segmentId,
      orderIndex: 0,
      topLevelOrderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-0',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createExercise(
    Exercise(
      id: 'ex-0',
      name: _benchPress,
      capabilities: const ['load'],
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  // A set is the rows of one entry number (D-324): the id carries it as
  // `obs-<effortId>-<n>-<metricKey>`, so the reps and the weight rows of one
  // set share the number and land in the same group.
  await repo.createObservation(_repsRow(setEffortId, 0, 10, start));
  await repo.createObservation(_weightRow(setEffortId, 0, 60.0, start));
  await repo.createObservation(_repsRow(setEffortId, 1, 8, start));
  await repo.createObservation(_weightRow(setEffortId, 1, 60.0, start));

  final timedEffortId = 'e-$sessionId-1';
  await repo.createEffort(
    SegmentEffort(
      id: timedEffortId,
      segmentId: segmentId,
      orderIndex: 1,
      topLevelOrderIndex: 1,
      effortKind: 'timed',
      exerciseId: 'ex-1',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createExercise(
    Exercise(id: 'ex-1', name: _plank, createdAtMs: start, updatedAtMs: start),
  );
  await repo.createTimedInstance(
    TimedInstance(
      id: 'ti-$timedEffortId-0',
      effortId: timedEffortId,
      entryIndex: 0,
      targetDurationSecs: 60,
      actualDurationSecs: 60,
      startedAtMs: start,
      finishedAtMs: start + 60000,
      state: TimedState.finished,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  return sessionId;
}

EffortObservation _repsRow(String effortId, int number, int reps, int atMs) =>
    EffortObservation(
      id: 'obs-$effortId-$number-reps',
      effortId: effortId,
      metricId: MetricIds.reps,
      unitId: MetricIds.unitReps,
      valueInt: reps,
      valueBool: false,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    );

EffortObservation _weightRow(
  String effortId,
  int number,
  double kg,
  int atMs,
) => EffortObservation(
  id: 'obs-$effortId-$number-weight',
  effortId: effortId,
  metricId: MetricIds.weight,
  unitId: MetricIds.unitKg,
  valueReal: kg,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

// ─── Widget harness ─────────────────────────────────────────────────────────

/// Pumps the Summary over the seeded session.
Future<void> _pumpSummary(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  required String sessionId,
  SettingsState? settings,
  bool openedFromCalendar = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  final resolvedSettings = settings ?? await _settings(repo);
  final state = WorkoutState(repo);
  await state.loadHistoricalSession(sessionId);

  await tester.pumpWidget(
    MaterialApp(
      home: SessionSummaryScreen(
        workoutState: state,
        routineState: RoutineState(repo),
        sessionSummaryService: SessionSummaryService(repo),
        settingsState: resolvedSettings,
        timerAlertService: FakeTimerAlertService(),
        openedFromCalendar: openedFromCalendar,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-24511 / S-24512 — the card and its rows
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24511 a post-workout style summary lists each exercise with '
      'its logged work', (tester) async {
    final repo = await _freshRepo();
    await _seedStrength(
      repo,
      sessionId: 's-strength',
      daysAgo: 3,
      modality: Modality.resistanceLifting,
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-strength',
      settings: settings,
      openedFromCalendar: false,
    );

    expect(find.text('EXERCISES'), findsOneWidget);
    expect(find.text(_benchPress), findsOneWidget);
    expect(find.text('10×60 kg'), findsOneWidget);
    expect(find.text('8×60 kg'), findsOneWidget);
    expect(
      find.text(_plank),
      findsWidgets,
      reason: 'the card row and another card both name it',
    );
    expect(find.text('01:00'), findsOneWidget);

    // The header sits below the first card and above SESSION NOTE.
    final firstCardTop = tester.getTopLeft(find.byType(OmniSurface).first).dy;
    final headerY = tester.getTopLeft(find.text('EXERCISES')).dy;
    final noteY = tester.getTopLeft(find.text('SESSION NOTE')).dy;
    expect(headerY, greaterThan(firstCardTop));
    expect(headerY, lessThan(noteY));
  });

  testWidgets('S-24512 a calendar-opened summary lists the same rows in the '
      'same order', (tester) async {
    final repo = await _freshRepo();
    await _seedStrength(
      repo,
      sessionId: 's-strength',
      daysAgo: 3,
      modality: Modality.resistanceLifting,
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-strength',
      settings: settings,
      openedFromCalendar: true,
    );

    final row0 = find.descendant(
      of: find.byKey(const Key('summary_exercise_row_0')),
      matching: find.byType(Text),
    );
    final row1 = find.descendant(
      of: find.byKey(const Key('summary_exercise_row_1')),
      matching: find.byType(Text),
    );
    expect(
      tester.widgetList<Text>(row0).map((text) => text.data),
      containsAllInOrder([_benchPress, '10×60 kg', '8×60 kg']),
    );
    expect(
      tester.widgetList<Text>(row1).map((text) => text.data),
      containsAllInOrder([_plank, '01:00']),
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24513 — nothing logged, no card
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24513 a session with no logged work shows no EXERCISES card', (
    tester,
  ) async {
    final repo = await _freshRepo();
    final start = _dayStartMs(2);
    await repo.createSession(
      TrainingSession(
        id: 's-empty',
        ownerUserId: 'user-1',
        startedAtMs: start,
        endedAtMs: start + 3600000,
        createdAtMs: start,
        updatedAtMs: start + 3600000,
      ),
    );
    await repo.createSegment(
      SessionSegment(
        id: 'seg-s-empty',
        sessionId: 's-empty',
        orderIndex: 0,
        segmentType: 'workout',
        name: 'Main Workout',
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    // An effort with no observation and no timed instance: nothing was logged.
    await repo.createEffort(
      SegmentEffort(
        id: 'e-s-empty-0',
        segmentId: 'seg-s-empty',
        orderIndex: 0,
        topLevelOrderIndex: 0,
        effortKind: 'set',
        exerciseId: 'ex-0',
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    await repo.createExercise(
      Exercise(
        id: 'ex-0',
        name: _benchPress,
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );

    await _pumpSummary(tester, repo, sessionId: 's-empty');

    expect(find.text('EXERCISES'), findsNothing);
    expect(find.byKey(const Key('omni_session_exercise_card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24514 — the grid and the rest-day line are gone, Open Calendar stays
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24514 the month grid and the rest-day line are gone, Open '
      'Calendar stays', (tester) async {
    final repo = await _freshRepo();
    const daysAgo = 3;
    await _seedStrength(
      repo,
      sessionId: 's-strength',
      daysAgo: daysAgo,
      modality: Modality.resistanceLifting,
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-strength',
      settings: settings,
      openedFromCalendar: false,
    );

    // The totals line the old grid carried.
    expect(find.textContaining('workout days'), findsNothing);

    // The label the old calendar header built for the session's month.
    final seededDay = _seededDay(daysAgo);
    final monthLabel =
        '${OmniDateUtils.fullMonthName(seededDay.month)} ${seededDay.year}';
    expect(find.text(monthLabel), findsNothing);

    // One Open Calendar button, under the SESSION NOTE card.
    final calendarButton = find.text('Open Calendar');
    expect(calendarButton, findsOneWidget);
    final buttonY = tester.getTopLeft(calendarButton).dy;
    final noteY = tester.getTopLeft(find.text('SESSION NOTE')).dy;
    expect(buttonY, greaterThan(noteY));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24515 — a rolling session lists its logged exercise
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24515 a rolling session lists its logged exercise', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedStrength(
      repo,
      sessionId: 's-rolling',
      daysAgo: 3,
      modality: Modality.resistanceLifting,
      isRolling: true,
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-rolling',
      settings: settings,
    );

    expect(find.text('EXERCISES'), findsOneWidget);
    expect(find.text(_benchPress), findsOneWidget);
    expect(find.text('10×60 kg'), findsOneWidget);
    expect(find.text('8×60 kg'), findsOneWidget);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24516 — the Weight unit setting
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24516 weights follow the Weight unit setting', (tester) async {
    final repo = await _freshRepo();
    await _seedStrength(
      repo,
      sessionId: 's-strength',
      daysAgo: 3,
      modality: Modality.resistanceLifting,
    );
    final settings = await _settings(repo, weightUnit: 'lbs');

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-strength',
      settings: settings,
    );

    final expected = '10×${UnitFormatter.formatWeightValue(60, settings)} lbs';
    expect(find.text(expected), findsOneWidget);
    expect(find.textContaining(' kg'), findsNothing);
  });
}
