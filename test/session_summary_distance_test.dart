// Stats PR 3a, Phase 2 — the Session Summary's DISTANCE section.
//
// The Summary lists one row per entry a distance belongs to: every entry
// tracked through Cardio (the stored record of it is the effort kind `timed`),
// plus any stored distance a non-Cardio entry still carries. A row's tap opens
// the shared numeric dialog, and the answer goes through the state write.
//
// Format: km/mi through `UnitFormatter`, two decimals, `—` for absence, and
// `est.` after the unit for an estimate — never a pace, total or delta.
//
// Scenarios: S-811–S-820, S-821 (state layer), S-822, S-823 of
// `docs/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/models/session_edit_snapshot.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/session_distance_card.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ─── Fixture ────────────────────────────────────────────────────────────────

const _treadmill = 'Treadmill Run';
const _easyRun = 'Easy Run';
const _briskWalk = 'Brisk Walk';
const _plank = 'Plank';

/// 09:00 on the day [daysAgo] days ago — a past day, so the Summary opens as a
/// historical one.
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

/// A `SettingsState` with the feeling prompt off, so the summary screen never
/// opens a sheet over the rows under test.
Future<SettingsState> _settings(
  MockWorkoutRepository repo, {
  String unit = 'km',
}) async {
  final settings = SettingsState(repo, fakePreferencesService());
  await settings.setShowFeelingSurvey(false);
  await settings.setPreferredDistanceUnit(unit);
  return settings;
}

/// One completed session with the exercises it names, dated [daysAgo].
///
/// Each exercise is a `(name, effortKind, entries)` triple: `entries` is one
/// `(actualDurationSecs, distanceMetres, distanceSource)` record per entry, and
/// a `null` distance stores no row at all. An effort listed in
/// [legacyMapEfforts] has its rows stored as raw maps with no source key, as a
/// pre-`value_source` writer left them.
Future<String> _seedSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required List<(String, String, List<(int, double?, String?)>)> exercises,
  String? modality,
  String? title,
  String? intent,
  Set<int> legacyMapEfforts = const {},
}) async {
  final start = _dayStart(daysAgo);
  final end = start + 3600000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: end,
      modality: modality,
      title: title,
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

  for (var e = 0; e < exercises.length; e++) {
    final (name, effortKind, entries) = exercises[e];
    final effortId = 'e-$sessionId-$e';
    await repo.createEffort(
      SegmentEffort(
        id: effortId,
        segmentId: segmentId,
        orderIndex: e,
        topLevelOrderIndex: e,
        effortKind: effortKind,
        exerciseId: 'ex-$e',
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    final exercise = Exercise(
      id: 'ex-$e',
      name: name,
      createdAtMs: start,
      updatedAtMs: start,
    );
    await repo.createExercise(exercise);

    for (var i = 0; i < entries.length; i++) {
      final (durationSecs, metres, source) = entries[i];
      if (effortKind == 'timed' || effortKind == 'drill') {
        await repo.createTimedInstance(
          TimedInstance(
            id: 'ti-$effortId-$i',
            effortId: effortId,
            entryIndex: i,
            targetDurationSecs: durationSecs,
            actualDurationSecs: durationSecs,
            startedAtMs: start + i * 1000,
            finishedAtMs: start + i * 1000 + durationSecs * 1000,
            state: TimedState.finished,
            createdAtMs: start,
            updatedAtMs: start,
          ),
        );
      }
      if (metres == null) {
        // A drill still carries its extra-weight companion row.
        if (effortKind == 'drill') {
          await repo.createObservation(_extraWeight(effortId, i, 0.0, start));
        }
        continue;
      }
      // A raw map with no source key for an effort that stored one before the
      // field existed; otherwise a row built by the model.
      await repo.createObservation(
        legacyMapEfforts.contains(e)
            ? _legacyDistanceRow(effortId, i, metres, start)
            : _distanceRow(effortId, i, metres, source, start),
      );
      if (effortKind == 'drill') {
        await repo.createObservation(_extraWeight(effortId, i, 0.0, start));
      }
    }
  }
  return sessionId;
}

EffortObservation _distanceRow(
  String effortId,
  int entryIndex,
  double metres,
  String? source,
  int atMs,
) => EffortObservation(
  id: 'obs-$effortId-$entryIndex-distance',
  effortId: effortId,
  metricId: MetricIds.distance,
  unitId: MetricIds.unitMeters,
  valueReal: metres,
  valueSource: source,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

/// A distance row as this app stored one before the source existed — a map
/// with no `value_source` key (S-801, S-811's `Easy Run`).
EffortObservation _legacyDistanceRow(
  String effortId,
  int entryIndex,
  double metres,
  int atMs,
) => EffortObservation.fromMap({
  'id': 'obs-$effortId-$entryIndex-distance',
  'effort_id': effortId,
  'metric_id': MetricIds.distance,
  'unit_id': MetricIds.unitMeters,
  'value_real': metres,
  'created_at_ms': atMs,
  'updated_at_ms': atMs,
});

EffortObservation _extraWeight(
  String effortId,
  int entryIndex,
  double kg,
  int atMs,
) => EffortObservation(
  id: 'obs-$effortId-$entryIndex-extra-weight',
  effortId: effortId,
  metricId: MetricIds.extraWeight,
  unitId: MetricIds.unitKg,
  valueReal: kg,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

/// FX-CARDIO: a Cardio session with two efforts, one estimate, one row with no
/// source and one empty entry. `Easy Run`'s row is stored as a raw map with no
/// source key, as a pre-`value_source` writer left it (S-801).
Future<void> _seedCardio(MockWorkoutRepository repo, {int daysAgo = 3}) =>
    _seedSession(
      repo,
      sessionId: 's-cardio',
      daysAgo: daysAgo,
      modality: Modality.cardioEndurance,
      title: 'Cardio',
      exercises: [
        (
          _treadmill,
          'timed',
          [(1200, 4873.6, EffortObservation.sourceEstimated), (600, 0.0, null)],
        ),
        (_easyRun, 'timed', [(1800, 5000.0, null)]),
      ],
      legacyMapEfforts: {1},
    );

// ─── Widget harness ─────────────────────────────────────────────────────────

/// Pumps the Summary and returns the state behind it, so a test can read what
/// a write stored. A [workoutState] that already holds a session is used as it
/// is; otherwise [sessionId] is loaded into a fresh one.
Future<WorkoutState> _pumpSummary(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  SettingsState? settings,
  String? sessionId,
  WorkoutState? workoutState,
  bool openedFromCalendar = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2400));
  final resolvedSettings = settings ?? await _settings(repo);
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
        settingsState: resolvedSettings,
        timerAlertService: FakeTimerAlertService(),
        openedFromCalendar: openedFromCalendar,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

/// The DISTANCE card, or null when the section is hidden.
Finder get _distanceCard => find.byKey(const Key('omni_session_distance_card'));

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

Future<void> _tapRow(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The dialog's own field. The Summary also carries a session-note field, so
/// the finder has to be scoped to the dialog.
Finder get _dialogField => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

Future<void> _enterInDialog(WidgetTester tester, String text) async {
  await tester.enterText(_dialogField, text);
  await tester.tap(find.text('Ok'));
  await tester.pumpAndSettle();
}

Future<void> _confirmInDialog(WidgetTester tester) async {
  await tester.tap(find.text('Ok'));
  await tester.pumpAndSettle();
}

List<EffortObservation> _distanceRows(WorkoutState state, String effortId) =>
    state
        .getObservationsForEffort(effortId)
        .where((row) => row.metricId == MetricIds.distance)
        .toList();

List<EffortObservation> _rowsFor(
  WorkoutState state,
  String sessionId,
  int effortIndex,
) => _distanceRows(state, 'e-$sessionId-$effortIndex');

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-811 / S-812 — the section and its rows
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-811 a Cardio session lists every entry, since all are tracked '
      'through Cardio', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);

    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    expect(find.text('DISTANCE'), findsOneWidget);
    expect(
      _sectionTexts(tester),
      [
        'Treadmill Run · 1',
        '4.87',
        'KM EST.',
        'Treadmill Run · 2',
        SessionDistanceCard.absentValue,
        'KM',
        'Easy Run',
        '5.00',
        'KM',
      ],
      reason: 'D-315/D-319: one row per Cardio-tracked entry, in entry order',
    );

    // The section sits above SESSION NOTE.
    final distanceY = tester.getTopLeft(find.text('DISTANCE')).dy;
    final noteY = tester.getTopLeft(find.text('SESSION NOTE')).dy;
    expect(distanceY, lessThan(noteY));

    // No pace, total or delta anywhere on the Summary (D-306).
    for (final forbidden in ['/km', '/mi', 'Pace']) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: 'D-306: the Summary carries no $forbidden readout',
      );
    }
  });

  testWidgets('S-812 miles', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo, unit: 'mi');

    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    expect(_sectionTexts(tester), [
      'Treadmill Run · 1',
      '3.03',
      'MI EST.',
      'Treadmill Run · 2',
      SessionDistanceCard.absentValue,
      'MI',
      'Easy Run',
      '3.11',
      'MI',
    ]);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-813 – S-817 — editing through the dialog
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-813 correcting an estimate', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);
    final state = await _pumpSummary(
      tester,
      repo,
      sessionId: 's-cardio',
      settings: settings,
    );

    await _tapRow(tester, 'Treadmill Run · 1');
    expect(find.text('Edit Distance'), findsOneWidget);
    expect(tester.widget<TextField>(_dialogField).controller?.text, '4.87');

    await _enterInDialog(tester, '5.2');

    expect(find.text('5.20'), findsOneWidget);
    expect(find.text('KM EST.'), findsNothing);

    final rows = await repo.getEffortObservations('e-s-cardio-0');
    final stored = rows.firstWhere(
      (row) => row.id == 'obs-e-s-cardio-0-0-distance',
    );
    expect(stored.valueReal, 5200.0);
    expect(stored.valueSource, EffortObservation.sourceEntered);
    expect(state.error, isNull);
  });

  testWidgets('S-814 confirming unchanged removes the marker', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    await _tapRow(tester, 'Treadmill Run · 1');
    await _confirmInDialog(tester);

    expect(_sectionTexts(tester).take(3), ['Treadmill Run · 1', '4.87', 'KM']);

    final stored = (await repo.getEffortObservations(
      'e-s-cardio-0',
    )).firstWhere((row) => row.id == 'obs-e-s-cardio-0-0-distance');
    expect(
      stored.valueReal,
      4873.6,
      reason: 'D-307: a confirm keeps the metres',
    );
    expect(stored.valueSource, EffortObservation.sourceEntered);
  });

  testWidgets('S-815 entering 0 in a Cardio session keeps the row as absence', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    await _tapRow(tester, 'Easy Run');
    await _enterInDialog(tester, '0');

    expect(_sectionTexts(tester), [
      'Treadmill Run · 1',
      '4.87',
      'KM EST.',
      'Treadmill Run · 2',
      SessionDistanceCard.absentValue,
      'KM',
      'Easy Run',
      SessionDistanceCard.absentValue,
      'KM',
    ]);

    final stored = (await repo.getEffortObservations('e-s-cardio-1')).single;
    expect(stored.valueReal, 0.0);
    expect(stored.valueSource, isNull);
  });

  testWidgets('S-816 cancelling changes nothing', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    // (a) an outside tap closes without a change.
    await _tapRow(tester, 'Treadmill Run · 1');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('4.87'), findsOneWidget);

    // (b) clearing the text and pressing Ok changes nothing either.
    await _tapRow(tester, 'Treadmill Run · 1');
    await _enterInDialog(tester, '');

    expect(_sectionTexts(tester).take(3), [
      'Treadmill Run · 1',
      '4.87',
      'KM EST.',
    ]);
    final stored = (await repo.getEffortObservations(
      'e-s-cardio-0',
    )).firstWhere((row) => row.id == 'obs-e-s-cardio-0-0-distance');
    expect(stored.valueReal, 4873.6);
    expect(stored.valueSource, EffortObservation.sourceEstimated);
  });

  testWidgets('S-817 adding a distance to an empty entry', (tester) async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-cardio', settings: settings);

    await _tapRow(tester, 'Treadmill Run · 2');
    expect(tester.widget<TextField>(_dialogField).controller?.text, '0.00');

    await _enterInDialog(tester, '1.5');

    expect(_sectionTexts(tester), [
      'Treadmill Run · 1',
      '4.87',
      'KM EST.',
      'Treadmill Run · 2',
      '1.50',
      'KM',
      'Easy Run',
      '5.00',
      'KM',
    ]);

    final stored = (await repo.getEffortObservations(
      'e-s-cardio-0',
    )).firstWhere((row) => row.id == 'obs-e-s-cardio-0-1-distance');
    expect(stored.valueReal, 1500.0);
    expect(stored.valueSource, EffortObservation.sourceEntered);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-818 / S-819 — Cardio tracking decides, in every kind of session
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'S-818a a Free Training session lists the entries added as Cardio',
    (tester) async {
      final repo = await _freshRepo();
      await _seedSession(
        repo,
        sessionId: 's-free',
        daysAgo: 2,
        title: 'Free Training',
        exercises: [
          (_easyRun, 'timed', [(1800, 0.0, null), (900, 3000.0, null)]),
          (_briskWalk, 'timed', [(600, 0.0, null)]),
        ],
      );
      final settings = await _settings(repo);
      await _pumpSummary(tester, repo, sessionId: 's-free', settings: settings);

      expect(_sectionTexts(tester), [
        'Easy Run · 1',
        SessionDistanceCard.absentValue,
        'KM',
        'Easy Run · 2',
        '3.00',
        'KM',
        'Brisk Walk',
        SessionDistanceCard.absentValue,
        'KM',
      ]);
    },
  );

  testWidgets('S-818b a resistance session shows no DISTANCE section', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-lift',
      daysAgo: 2,
      modality: Modality.resistanceLifting,
      exercises: [
        ('Bench Press', 'set', [(0, null, null), (0, null, null)]),
      ],
    );
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-lift', settings: settings);

    expect(_distanceCard, findsNothing);
    expect(find.text('DISTANCE'), findsNothing);
  });

  testWidgets('S-818c a watch-imported session lists its timed entries', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-watch',
      daysAgo: 1,
      exercises: [
        (_easyRun, 'timed', [(2400, 2400.0, null), (600, 0.0, null)]),
      ],
    );
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-watch', settings: settings);

    expect(_sectionTexts(tester), [
      'Easy Run · 1',
      '2.40',
      'KM',
      'Easy Run · 2',
      SessionDistanceCard.absentValue,
      'KM',
    ]);
  });

  testWidgets('S-818d a non-Cardio entry with a stored distance gets one row', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-plank',
      daysAgo: 1,
      modality: Modality.isometricStretching,
      exercises: [
        (_plank, 'drill', [(60, 400.0, null), (60, null, null)]),
      ],
    );
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-plank', settings: settings);

    expect(_sectionTexts(tester), [_plank, '0.40', 'KM']);
  });

  testWidgets('S-819 removing a legacy distance hides its row', (tester) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-plank',
      daysAgo: 1,
      modality: Modality.isometricStretching,
      exercises: [
        (_plank, 'drill', [(60, 400.0, null), (60, null, null)]),
      ],
    );
    final settings = await _settings(repo);
    await _pumpSummary(tester, repo, sessionId: 's-plank', settings: settings);

    await _tapRow(tester, _plank);
    await _enterInDialog(tester, '0');

    expect(_distanceCard, findsNothing, reason: 'D-319: the row disappears');
    expect(find.text('DISTANCE'), findsNothing);

    final stored = (await repo.getEffortObservations(
      'e-s-plank-0',
    )).firstWhere((row) => row.metricId == MetricIds.distance);
    expect(stored.valueReal, 0.0);
    expect(stored.valueSource, isNull);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-820 — the post-workout Summary
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'S-820 the post-workout Summary writes to the repository on Done',
    (tester) async {
      final repo = await _freshRepo();
      final settings = await _settings(repo);
      final state = WorkoutState(repo);
      await state.createNewSession(modality: Modality.cardioEndurance);

      final exercise = Exercise(
        id: 'ex-easy-live',
        name: _easyRun,
        capabilities: const ['time'],
        createdAtMs: 1,
        updatedAtMs: 1,
      );
      await repo.createExercise(exercise);
      final effortId = await state.addExerciseToSession(
        exercise,
        effortKindOverride: ModalityConfig.forModality(
          Modality.cardioEndurance,
        )!.effortKind,
      );
      expect(effortId, isNotEmpty);
      // `addExerciseToSession` logs the effort's first entry itself.
      expect(state.getTimedInstancesForEffort(effortId), hasLength(1));

      await _pumpSummary(
        tester,
        repo,
        settings: settings,
        workoutState: state,
        openedFromCalendar: false,
      );

      expect(_sectionTexts(tester), [
        _easyRun,
        SessionDistanceCard.absentValue,
        'KM',
      ]);

      await _tapRow(tester, _easyRun);
      await _enterInDialog(tester, '4.2');
      expect(_sectionTexts(tester), [_easyRun, '4.20', 'KM']);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final stored = (await repo.getEffortObservations(
        effortId,
      )).firstWhere((row) => row.metricId == MetricIds.distance);
      expect(stored.valueReal, 4200.0);
      expect(stored.valueSource, EffortObservation.sourceEntered);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // S-821 — an Edit Session discard keeps the Summary's value
  // ══════════════════════════════════════════════════════════════════════════

  test('S-821 an Edit Session discard keeps the Summary value', () async {
    final repo = await _freshRepo();
    await _seedCardio(repo);
    final state = WorkoutState(repo);
    await state.loadHistoricalSession('s-cardio');

    await state.setEntryDistance('e-s-cardio-0', 0, 5200.0);
    final snapshot = state.snapshotSessionState();
    expect(snapshot, isNotNull);

    await state.addEntry('e-s-cardio-0');
    await state.restoreSessionSnapshot(snapshot as SessionEditSnapshot);

    final reloaded = WorkoutState(repo);
    await reloaded.loadHistoricalSession('s-cardio');

    final rows = _rowsFor(reloaded, 's-cardio', 0);
    expect(rows, hasLength(2));
    final first = rows.firstWhere(
      (row) => row.id == 'obs-e-s-cardio-0-0-distance',
    );
    expect(first.valueReal, 5200.0);
    expect(first.valueSource, EffortObservation.sourceEntered);
    expect(
      rows.where((row) => (row.valueReal ?? 0) > 0).map((row) => row.valueReal),
      [5200.0],
      reason: 'the second entry still has no distance',
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-822 / S-823 — a routine, and a plank tracked through Cardio
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets('S-822 a routine lists only the exercise assigned Cardio', (
    tester,
  ) async {
    final repo = await _freshRepo();
    await _seedSession(
      repo,
      sessionId: 's-routine',
      daysAgo: 2,
      intent: 'routine',
      title: 'Morning Routine',
      exercises: [
        (_easyRun, 'timed', [(1800, 0.0, null)]),
        (_plank, 'drill', [(60, null, null), (60, null, null)]),
      ],
    );
    final settings = await _settings(repo);
    await _pumpSummary(
      tester,
      repo,
      sessionId: 's-routine',
      settings: settings,
    );

    expect(_sectionTexts(tester), [
      _easyRun,
      SessionDistanceCard.absentValue,
      'KM',
    ]);
    expect(find.textContaining(_plank), findsNothing);
  });

  testWidgets('S-823 a plank tracked through Cardio gets the field', (
    tester,
  ) async {
    final repo = await _freshRepo();
    final settings = await _settings(repo);
    final state = WorkoutState(repo);
    await state.createNewSession();

    final plank = Exercise(
      id: 'ex-plank',
      name: _plank,
      capabilities: const ['hold'],
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    await repo.createExercise(plank);

    // The modality picker's own mapping: Cardio yields `timed`, Isometric
    // yields `drill` (F17).
    final cardioKind = ModalityConfig.forModality(
      Modality.cardioEndurance,
    )!.effortKind;
    final isometricKind = ModalityConfig.forModality(
      Modality.isometricStretching,
    )!.effortKind;
    expect(cardioKind, 'timed');
    expect(isometricKind, 'drill');

    final cardioEffortId = await state.addExerciseToSession(
      plank,
      effortKindOverride: cardioKind,
    );
    final isometricEffortId = await state.addExerciseToSession(
      plank,
      effortKindOverride: isometricKind,
    );

    await _pumpSummary(
      tester,
      repo,
      settings: settings,
      workoutState: state,
      openedFromCalendar: false,
    );

    expect(
      _sectionTexts(tester),
      [_plank, SessionDistanceCard.absentValue, 'KM'],
      reason: 'D-319: only the Cardio-tracked effort gets a row',
    );

    await _tapRow(tester, _plank);
    await _enterInDialog(tester, '0.4');

    expect(_sectionTexts(tester), [_plank, '0.40', 'KM']);

    final stored = (await repo.getEffortObservations(
      cardioEffortId,
    )).firstWhere((row) => row.metricId == MetricIds.distance);
    expect(stored.valueReal, 400.0);
    expect(stored.valueSource, EffortObservation.sourceEntered);
    expect(
      (await repo.getEffortObservations(
        isometricEffortId,
      )).where((row) => row.metricId == MetricIds.distance),
      isEmpty,
      reason: 'the Isometric-tracked effort gains no distance row',
    );
  });
}
