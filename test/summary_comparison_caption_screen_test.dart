// Plan 246, P3 — the Summary's comparison basis line as the screen shows it.
//
// When the session has a like session before it (same routine, else same type)
// and some group figure is shown, the Summary shows one line above the group
// cards: `Compared with your last <label> (<date>)` for a routine session and
// `Compared with your last <label> session (<date>)` for a free one.
//
// Scenarios: S-24611..S-24614 of
// `docs/plans/2026-11-18-246-summary-compares-like-with-like-plan/2026-11-18-246-summary-compares-like-with-like-plan.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
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

/// The short date the screen puts in the caption, built in the test from the
/// seeded start time with the same rule as the screen's `_formatDate`:
/// month abbreviation and day (`Nov 12`).
String _shortDate(int daysAgo) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = _seededDay(daysAgo);
  return '${months[day.month - 1]} ${day.day}';
}

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A `SettingsState` with the feeling prompt off, so the summary screen never
/// opens a sheet over the caption under test.
Future<SettingsState> _settings(
  MockWorkoutRepository repo, {
  String weightUnit = 'kg',
}) async {
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);
  await settings.setPreferredWeightUnit(weightUnit);
  return settings;
}

/// One completed session whose whole work is a single set of [reps] reps at
/// [weightKg] kg, so the session's strength volume is reps × weight. A session
/// started from a routine sets [routineTemplateId] (and [intent]); a free one
/// leaves both null and carries its type in [modality].
Future<void> _seedSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required int reps,
  required double weightKg,
  String? routineTemplateId,
  String? title,
  String? modality,
  String? intent,
}) async {
  final start = _dayStartMs(daysAgo);
  final end = start + 3600000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      routineTemplateId: routineTemplateId,
      startedAtMs: start,
      endedAtMs: end,
      title: title,
      modality: modality,
      intent: intent,
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
  final effortId = 'e-$sessionId-0';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      topLevelOrderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-$sessionId',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createExercise(
    Exercise(
      id: 'ex-$sessionId',
      name: 'Bench Press',
      capabilities: const ['load'],
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createObservation(_repsRow(effortId, 0, reps, start));
  await repo.createObservation(_weightRow(effortId, 0, weightKg, start));
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

/// Pumps the Summary over the seeded session, opened historically from the
/// calendar.
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
  // S-24611 — a routine summary names the last run of that routine
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24611 a routine summary says it compares with the last run of '
      'that routine', (tester) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-t1-old',
      daysAgo: 5,
      reps: 8,
      weightKg: 50,
      routineTemplateId: 't1',
      title: 'Push Day',
      modality: Modality.resistanceLifting,
      intent: 'routine',
    );
    await _seedSession(
      repo,
      sessionId: 's-t1-new',
      daysAgo: 2,
      reps: 10,
      weightKg: 50,
      routineTemplateId: 't1',
      title: 'Push Day',
      modality: Modality.resistanceLifting,
      intent: 'routine',
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-t1-new',
      settings: settings,
      openedFromCalendar: true,
    );

    expect(
      find.text('Compared with your last Push Day (${_shortDate(5)})'),
      findsOneWidget,
    );
    expect(
      find.textContaining('↑'),
      findsWidgets,
      reason: 'the volume rose 400 → 500, so a comparison chip points up',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24612 — no like session, no caption
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24612 no like session means no line', (tester) async {
    final repo = await _freshRepo();
    // An older FREE session of the same modality: unlike the routine session
    // below, so the caption must not be shown against it.
    await _seedSession(
      repo,
      sessionId: 's-free-old',
      daysAgo: 5,
      reps: 8,
      weightKg: 50,
      modality: Modality.resistanceLifting,
    );
    await _seedSession(
      repo,
      sessionId: 's-t1',
      daysAgo: 2,
      reps: 10,
      weightKg: 50,
      routineTemplateId: 't1',
      title: 'Push Day',
      modality: Modality.resistanceLifting,
      intent: 'routine',
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-t1',
      settings: settings,
      openedFromCalendar: true,
    );

    expect(find.byKey(const Key('summary_comparison_basis')), findsNothing);
    expect(find.textContaining('Compared with'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24613 — a free summary names the last session of its type
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24613 a free session says it compares with the last session '
      'of its type', (tester) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-free-old',
      daysAgo: 5,
      reps: 8,
      weightKg: 50,
      modality: Modality.resistanceLifting,
    );
    await _seedSession(
      repo,
      sessionId: 's-free-new',
      daysAgo: 2,
      reps: 10,
      weightKg: 50,
      modality: Modality.resistanceLifting,
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-free-new',
      settings: settings,
      openedFromCalendar: true,
    );

    expect(
      find.text(
        'Compared with your last Resistance / Lifting session '
        '(${_shortDate(5)})',
      ),
      findsOneWidget,
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-24614 — a like session with no group shows no line
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-24614 a like session with no group shows no line',
      (tester) async {
    final repo = await _freshRepo();
    // An older run of the same routine that recorded nothing at all: no
    // segments, no efforts — only the finished session row.
    final start = _dayStartMs(5);
    await repo.createSession(
      TrainingSession(
        id: 's-t1-old-empty',
        ownerUserId: 'user-1',
        routineTemplateId: 't1',
        startedAtMs: start,
        endedAtMs: start + 3600000,
        title: 'Push Day',
        modality: Modality.resistanceLifting,
        createdAtMs: start,
        updatedAtMs: start + 3600000,
      ),
    );
    await _seedSession(
      repo,
      sessionId: 's-t1-new',
      daysAgo: 2,
      reps: 10,
      weightKg: 50,
      routineTemplateId: 't1',
      title: 'Push Day',
      modality: Modality.resistanceLifting,
      intent: 'routine',
    );
    final settings = await _settings(repo);

    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-t1-new',
      settings: settings,
      openedFromCalendar: true,
    );

    // A like session exists, so the service returns a basis, but the like
    // session has no strength, so the strength figure is hidden: no line.
    expect(find.byKey(const Key('summary_comparison_basis')), findsNothing);
    expect(find.textContaining('Compared with'), findsNothing);
  });
}
