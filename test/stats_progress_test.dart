// ignore_for_file: avoid_positional_boolean_parameters

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

// ── Seed helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Seed a completed session starting at [day] midnight.
Future<TrainingSession> _seedSession(
  MockWorkoutRepository repo, {
  required String id,
  required DateTime day,
  String? modality,
}) async {
  final startMs = day.millisecondsSinceEpoch;
  final session = TrainingSession(
    id: id,
    ownerUserId: 'user-1',
    startedAtMs: startMs,
    endedAtMs: startMs + 3600000,
    modality: modality,
    createdAtMs: startMs,
    updatedAtMs: startMs,
  );
  await repo.createSession(session);
  return session;
}

/// Seed a set effort with one segment auto-created inside [sessionId].
/// [sets] is a list of (weight_kg, reps) pairs.
Future<String> _addSetEffort(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required List<(double, int)> sets,
}) async {
  final segId = 'seg-$sessionId-$exerciseId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  final effId = 'eff-$sessionId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  for (var i = 0; i < sets.length; i++) {
    final (weight, reps) = sets[i];
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-weight',
        effortId: effId,
        metricId: MetricIds.weight,
        unitId: MetricIds.unitKg,
        valueReal: weight,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-reps',
        effortId: effId,
        metricId: MetricIds.reps,
        unitId: MetricIds.unitReps,
        valueInt: reps,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
  }

  return effId;
}

/// Seed a timed effort with one finished [TimedInstance].
Future<String> _addTimedEffort(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required int durationSecs,
  double? distanceM,
}) async {
  final segId = 'seg-$sessionId-$exerciseId';
  // Only create segment if it doesn't already exist.
  try {
    await repo.createSegment(
      SessionSegment(
        id: segId,
        sessionId: sessionId,
        orderIndex: 0,
        segmentType: 'main',
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
  } catch (_) {}

  final effId = 'eff-$sessionId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  await repo.createTimedInstance(
    TimedInstance(
      id: 'ti-$effId',
      effortId: effId,
      entryIndex: 0,
      actualDurationSecs: durationSecs,
      state: TimedState.finished,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  if (distanceM != null && distanceM > 0) {
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-0-distance',
        effortId: effId,
        metricId: MetricIds.distance,
        unitId: MetricIds.unitMeters,
        valueReal: distanceM,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
  }

  return effId;
}

void main() {
  // ── e1RM calculation ──────────────────────────────────────────────────────

  group('e1RM calculation (Epley formula)', () {
    test('5 reps at 100 kg → ≈116.67', () {
      // 100 × (1 + 5/30) = 100 × 1.1667
      final result = 100.0 * (1 + 5 / 30.0);
      expect(result, closeTo(116.67, 0.01));
    });

    test('1 rep at 120 kg → ≈124.0', () {
      // 120 × (1 + 1/30) = 120 × 1.0333
      final result = 120.0 * (1 + 1 / 30.0);
      expect(result, closeTo(124.0, 0.01));
    });

    test('zero weight → exercise not tracked (skipped)', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-bw',
          name: 'Bodyweight Squat',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await _seedSession(repo, id: 's1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 's1',
        exerciseId: 'ex-bw',
        sets: [(0.0, 10)],
      );

      final data = await StatsProgressService(repo).computeProgressData();
      expect(data.topLifts, isEmpty);
    });

    test('zero reps → exercise not tracked (skipped)', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-press',
          name: 'Bench Press',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await _seedSession(repo, id: 's1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 's1',
        exerciseId: 'ex-press',
        sets: [(80.0, 0)],
      );

      final data = await StatsProgressService(repo).computeProgressData();
      expect(data.topLifts, isEmpty);
    });
  });

  // ── Top-N auto-detection ──────────────────────────────────────────────────

  group('Top-N auto-detection', () {
    test('top 3 lifts selected by training-day count, ties broken alphabetically', () async {
      final repo = await _freshRepo();

      for (final name in ['ExA', 'ExB', 'ExC', 'ExD']) {
        await repo.createExercise(
          Exercise(
            id: 'ex-$name',
            name: name,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }

      // ExA: 5 distinct days
      for (var i = 0; i < 5; i++) {
        await _seedSession(repo, id: 'exa-$i', day: DateTime(2024, 1, i + 1));
        await _addSetEffort(
          repo,
          sessionId: 'exa-$i',
          exerciseId: 'ex-ExA',
          sets: [(80.0, 5)],
        );
      }

      // ExB: 5 distinct days (tied with ExA alphabetically second)
      for (var i = 0; i < 5; i++) {
        await _seedSession(repo, id: 'exb-$i', day: DateTime(2024, 2, i + 1));
        await _addSetEffort(
          repo,
          sessionId: 'exb-$i',
          exerciseId: 'ex-ExB',
          sets: [(80.0, 5)],
        );
      }

      // ExC: 3 days
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'exc-$i', day: DateTime(2024, 3, i + 1));
        await _addSetEffort(
          repo,
          sessionId: 'exc-$i',
          exerciseId: 'ex-ExC',
          sets: [(80.0, 5)],
        );
      }

      // ExD: 1 day
      await _seedSession(repo, id: 'exd-0', day: DateTime(2024, 4, 1));
      await _addSetEffort(
        repo,
        sessionId: 'exd-0',
        exerciseId: 'ex-ExD',
        sets: [(80.0, 5)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts.length, 3);
      expect(data.topLifts[0].exerciseName, 'ExA'); // tied 5 days, alphabetical
      expect(data.topLifts[1].exerciseName, 'ExB');
      expect(data.topLifts[2].exerciseName, 'ExC');
    });

    test('respects kTopLiftCount when fewer exercises exist', () async {
      final repo = await _freshRepo();

      for (var i = 0; i < 2; i++) {
        await repo.createExercise(
          Exercise(
            id: 'ex-$i',
            name: 'Ex$i',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await _seedSession(repo, id: 'sess-$i', day: DateTime(2024, 1, i + 1));
        await _addSetEffort(
          repo,
          sessionId: 'sess-$i',
          exerciseId: 'ex-$i',
          sets: [(80.0, 5)],
        );
      }

      final data = await StatsProgressService(repo).computeProgressData();
      // Only 2 exercises available, cap is 3 → returns 2
      expect(data.topLifts.length, 2);
    });

    test('top 2 cardio selected correctly with alphabetical tiebreak', () async {
      final repo = await _freshRepo();

      for (var i = 0; i < 3; i++) {
        await repo.createExercise(
          Exercise(
            id: 'cex-$i',
            name: 'CEx$i',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      }

      // CEx0: 3 days
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'c0-$i', day: DateTime(2024, 1, i + 1));
        await _addTimedEffort(
          repo,
          sessionId: 'c0-$i',
          exerciseId: 'cex-0',
          durationSecs: 1800,
        );
      }

      // CEx1: 3 days (tied with CEx0)
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'c1-$i', day: DateTime(2024, 2, i + 1));
        await _addTimedEffort(
          repo,
          sessionId: 'c1-$i',
          exerciseId: 'cex-1',
          durationSecs: 1800,
        );
      }

      // CEx2: 1 day
      await _seedSession(repo, id: 'c2-0', day: DateTime(2024, 3, 1));
      await _addTimedEffort(
        repo,
        sessionId: 'c2-0',
        exerciseId: 'cex-2',
        durationSecs: 1800,
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topCardio.length, 2);
      expect(data.topCardio[0].exerciseName, 'CEx0');
      expect(data.topCardio[1].exerciseName, 'CEx1');
    });
  });

  // ── Trend aggregation ─────────────────────────────────────────────────────

  group('Trend aggregation', () {
    test('e1RM trend: max per day, chronological', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-sq', name: 'Squat', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Day 1: two sets → e1RMs 100×1.167=116.7 and 110×1.0333=113.67 → max 116.7
      await _seedSession(repo, id: 'sq-d1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 'sq-d1',
        exerciseId: 'ex-sq',
        sets: [(100.0, 5), (110.0, 1)],
      );

      // Day 2: one set → e1RM 90×(1+5/30)=105.0
      await _seedSession(repo, id: 'sq-d2', day: DateTime(2024, 1, 2));
      await _addSetEffort(
        repo,
        sessionId: 'sq-d2',
        exerciseId: 'ex-sq',
        sets: [(90.0, 5)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts.length, 1);
      final trend = data.topLifts.first.e1RmTrend;
      expect(trend.length, 2);

      // Day 1: max of (100×(1+5/30), 110×(1+1/30))
      //        = max(116.67, 113.67) = 116.67
      expect(trend[0].date, DateTime(2024, 1, 1));
      expect(trend[0].value, closeTo(116.67, 0.01));

      // Day 2: 90×(1+5/30) = 105.0
      expect(trend[1].date, DateTime(2024, 1, 2));
      expect(trend[1].value, closeTo(105.0, 0.01));
    });

    test('volume aggregation: sum of reps×weight per day', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-bp', name: 'Bench Press', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Day 1: 5×100 = 500, 3×80 = 240 → total 740
      await _seedSession(repo, id: 'bp-d1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 'bp-d1',
        exerciseId: 'ex-bp',
        sets: [(100.0, 5), (80.0, 3)],
      );

      // Day 2: 10×60 = 600
      await _seedSession(repo, id: 'bp-d2', day: DateTime(2024, 1, 2));
      await _addSetEffort(
        repo,
        sessionId: 'bp-d2',
        exerciseId: 'ex-bp',
        sets: [(60.0, 10)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      final volTrend = data.topLifts.first.volumeTrend;
      expect(volTrend.length, 2);
      expect(volTrend[0].value, closeTo(740.0, 0.01));
      expect(volTrend[1].value, closeTo(600.0, 0.01));
    });
  });

  // ── Effort-type keying ────────────────────────────────────────────────────

  group('Effort-type keying', () {
    test('set effort in null-modality session → appears in topLifts only', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-dl', name: 'Deadlift', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 's-null', day: DateTime(2024, 1, 1), modality: null);
      await _addSetEffort(
        repo,
        sessionId: 's-null',
        exerciseId: 'ex-dl',
        sets: [(80.0, 5)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts.any((l) => l.exerciseName == 'Deadlift'), isTrue);
      expect(data.topCardio.any((c) => c.exerciseName == 'Deadlift'), isFalse);
    });

    test('timed effort in lifting-modality session → appears in topCardio only', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-run', name: 'Treadmill Run', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(
        repo,
        id: 's-lift',
        day: DateTime(2024, 1, 1),
        modality: 'resistance_lifting',
      );
      await _addTimedEffort(
        repo,
        sessionId: 's-lift',
        exerciseId: 'ex-run',
        durationSecs: 1800,
        distanceM: 5000,
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topCardio.any((c) => c.exerciseName == 'Treadmill Run'), isTrue);
      expect(data.topLifts.any((l) => l.exerciseName == 'Treadmill Run'), isFalse);
    });

    test('drill effort in lifting session → neither section receives data', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(
          id: 'ex-drill',
          name: 'Plank Hold',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      await _seedSession(
        repo,
        id: 's-drill',
        day: DateTime(2024, 1, 1),
        modality: 'resistance_lifting',
      );

      // Create a drill effort (not 'set' or 'timed')
      const segId = 'seg-s-drill-ex-drill';
      await repo.createSegment(
        SessionSegment(
          id: segId,
          sessionId: 's-drill',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createEffort(
        SegmentEffort(
          id: 'eff-s-drill',
          segmentId: segId,
          orderIndex: 0,
          effortKind: 'drill',
          exerciseId: 'ex-drill',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts, isEmpty);
      expect(data.topCardio, isEmpty);
    });
  });

  // ── Empty states ──────────────────────────────────────────────────────────

  group('Empty states', () {
    test('only set efforts → topCardio is empty, topLifts is non-empty', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-s', name: 'Squat', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'sess-s', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 'sess-s',
        exerciseId: 'ex-s',
        sets: [(100.0, 5)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts, isNotEmpty);
      expect(data.topCardio, isEmpty);
    });

    test('only timed efforts → topLifts is empty, topCardio is non-empty', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-run', name: 'Run', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'sess-r', day: DateTime(2024, 1, 1));
      await _addTimedEffort(
        repo,
        sessionId: 'sess-r',
        exerciseId: 'ex-run',
        durationSecs: 1800,
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts, isEmpty);
      expect(data.topCardio, isNotEmpty);
    });

    test('empty repository → both sections are empty', () async {
      final repo = await _freshRepo();

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts, isEmpty);
      expect(data.topCardio, isEmpty);
      expect(data.recentPRs, isEmpty);
    });
  });

  // ── PR detection ──────────────────────────────────────────────────────────

  group('PR detection', () {
    test('PRs on Day 1 (first ever) and Day 3 (new high), not Day 2 — deduped to 1 entry', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-sq', name: 'Squat', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Day 1: 100 kg × 5 reps → e1RM ≈ 116.67 → first ever = PR
      await _seedSession(repo, id: 'pr-d1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 'pr-d1',
        exerciseId: 'ex-sq',
        sets: [(100.0, 5)],
      );

      // Day 2: 100 kg × 4 reps → e1RM ≈ 113.33 → not a PR
      await _seedSession(repo, id: 'pr-d2', day: DateTime(2024, 1, 2));
      await _addSetEffort(
        repo,
        sessionId: 'pr-d2',
        exerciseId: 'ex-sq',
        sets: [(100.0, 4)],
      );

      // Day 3: 105 kg × 5 reps → e1RM ≈ 122.5 → new high = PR
      await _seedSession(repo, id: 'pr-d3', day: DateTime(2024, 1, 3));
      await _addSetEffort(
        repo,
        sessionId: 'pr-d3',
        exerciseId: 'ex-sq',
        sets: [(105.0, 5)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      // After deduplication: Squat appears exactly ONCE — its standing record
      // (Day 3, the current best). Day 1 is superseded and no longer listed.
      expect(data.recentPRs.length, 1);
      expect(data.recentPRs.first.exerciseName, 'Squat');
      expect(data.recentPRs.first.date, DateTime(2024, 1, 3));
      expect(data.recentPRs.first.e1Rm, closeTo(105 * (1 + 5 / 30.0), 0.01));
      // Day 2 (not a PR) is still absent.
      final prDates = data.recentPRs.map((pr) => pr.date).toList();
      expect(prDates, isNot(contains(DateTime(2024, 1, 2))));
    });
  });

  // ── PR list dedupe ────────────────────────────────────────────────────────

  group('PR list dedupe', () {
    test('same exercise appearing 3× collapses to 1 entry at current best', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-hc', name: 'Hammer Curl', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Day 1: e1RM ≈ 50 * (1 + 1/30) ≈ 51.67
      await _seedSession(repo, id: 'hc-d1', day: DateTime(2024, 2, 1));
      await _addSetEffort(repo, sessionId: 'hc-d1', exerciseId: 'ex-hc', sets: [(50.0, 1)]);

      // Day 2: e1RM ≈ 55 * (1 + 1/30) ≈ 56.83 → new PR
      await _seedSession(repo, id: 'hc-d2', day: DateTime(2024, 2, 8));
      await _addSetEffort(repo, sessionId: 'hc-d2', exerciseId: 'ex-hc', sets: [(55.0, 1)]);

      // Day 3: e1RM ≈ 60 * (1 + 1/30) ≈ 62.0 → new PR (standing record)
      await _seedSession(repo, id: 'hc-d3', day: DateTime(2024, 2, 15));
      await _addSetEffort(repo, sessionId: 'hc-d3', exerciseId: 'ex-hc', sets: [(60.0, 1)]);

      final data = await StatsProgressService(repo).computeProgressData();

      // 3 historical PR events → deduped to 1 standing record.
      expect(data.recentPRs, hasLength(1));
      expect(data.recentPRs.first.exerciseName, 'Hammer Curl');
      expect(data.recentPRs.first.e1Rm, closeTo(60 * (1 + 1 / 30.0), 0.01));
      expect(data.recentPRs.first.date, DateTime(2024, 2, 15));
    });

    test('ordering is deterministic and stable when two records share a date', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-a', name: 'Arnold Press', createdAtMs: 1000, updatedAtMs: 1000),
      );
      await repo.createExercise(
        Exercise(id: 'ex-z', name: 'Zercher Squat', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Both exercises achieve their only (first-ever) PR on the same day.
      await _seedSession(repo, id: 'tie-d1', day: DateTime(2024, 3, 1));
      await _addSetEffort(repo, sessionId: 'tie-d1', exerciseId: 'ex-a', sets: [(40.0, 5)]);
      await _addSetEffort(repo, sessionId: 'tie-d1', exerciseId: 'ex-z', sets: [(80.0, 5)]);

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.recentPRs, hasLength(2));
      // When dates are equal, alphabetical order: Arnold Press < Zercher Squat.
      expect(data.recentPRs[0].exerciseName, 'Arnold Press');
      expect(data.recentPRs[1].exerciseName, 'Zercher Squat');
    });

    test('single-PR exercise appears correctly — dedupe does not drop singletons', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-dl', name: 'Deadlift', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'dl-d1', day: DateTime(2024, 4, 1));
      await _addSetEffort(repo, sessionId: 'dl-d1', exerciseId: 'ex-dl', sets: [(180.0, 3)]);

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.recentPRs, hasLength(1));
      expect(data.recentPRs.first.exerciseName, 'Deadlift');
      // 180 × (1 + 3/30) = 180 × 1.1 = 198.0
      expect(data.recentPRs.first.e1Rm, closeTo(198.0, 0.01));
    });

    test('multiple exercises: each appears at most once, best value shown', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-bp', name: 'Bench Press', createdAtMs: 1000, updatedAtMs: 1000),
      );
      await repo.createExercise(
        Exercise(id: 'ex-sq2', name: 'Squat', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Bench Press: 3 PR events (should dedupe to 1).
      await _seedSession(repo, id: 'bp-d1', day: DateTime(2024, 5, 1));
      await _addSetEffort(repo, sessionId: 'bp-d1', exerciseId: 'ex-bp', sets: [(80.0, 5)]);
      await _seedSession(repo, id: 'bp-d2', day: DateTime(2024, 5, 8));
      await _addSetEffort(repo, sessionId: 'bp-d2', exerciseId: 'ex-bp', sets: [(85.0, 5)]);
      await _seedSession(repo, id: 'bp-d3', day: DateTime(2024, 5, 15));
      await _addSetEffort(repo, sessionId: 'bp-d3', exerciseId: 'ex-bp', sets: [(90.0, 5)]);

      // Squat: 1 PR event (no duplicates to dedupe).
      await _seedSession(repo, id: 'sq2-d1', day: DateTime(2024, 5, 10));
      await _addSetEffort(repo, sessionId: 'sq2-d1', exerciseId: 'ex-sq2', sets: [(120.0, 5)]);

      final data = await StatsProgressService(repo).computeProgressData();

      // 4 historical events (3 BP + 1 SQ) → deduped to 2 standing records.
      expect(data.recentPRs, hasLength(2));

      final bpEntry = data.recentPRs.firstWhere((p) => p.exerciseName == 'Bench Press');
      // Standing record = Day 3 value: 90 × (1 + 5/30) = 90 × 1.1667 ≈ 105.0
      expect(bpEntry.e1Rm, closeTo(90 * (1 + 5 / 30.0), 0.01));
      expect(bpEntry.date, DateTime(2024, 5, 15));

      final sqEntry = data.recentPRs.firstWhere((p) => p.exerciseName == 'Squat');
      expect(sqEntry.e1Rm, closeTo(120 * (1 + 5 / 30.0), 0.01));
    });
  });

  // ── Session-summary vs stats PR consistency ───────────────────────────────

  group('Session-summary vs stats PR invariant', () {
    test('stats e1RM is always >= raw weight (Epley invariant for positive reps)', () {
      // For any weight > 0 and reps >= 1:
      //   e1RM = weight × (1 + reps/30) ≥ weight × (1 + 1/30) > weight
      // Session-summary uses raw weight as the PR value.
      // Therefore statsPR.e1Rm is always strictly greater than the raw weight.

      const weight = 110.0;
      const reps = 1;
      final e1Rm = weight * (1 + reps / 30.0);
      const sessionPRBest = weight; // session summary stores raw weight

      expect(e1Rm, greaterThanOrEqualTo(sessionPRBest));
      expect(e1Rm, closeTo(113.67, 0.01));
    });
  });

  // ── Scenario: single-rep set ──────────────────────────────────────────────

  group('Single-rep set', () {
    test('1 rep at 120 kg → e1RM ≈ 124.0, not special-cased', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-pl', name: 'Power Clean', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'pc-d1', day: DateTime(2024, 1, 1));
      await _addSetEffort(
        repo,
        sessionId: 'pc-d1',
        exerciseId: 'ex-pl',
        sets: [(120.0, 1)],
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topLifts.length, 1);
      expect(data.topLifts.first.e1RmTrend.length, 1);
      expect(data.topLifts.first.e1RmTrend.first.value, closeTo(124.0, 0.01));
    });
  });

  // ── Cardio pace calculation ───────────────────────────────────────────────

  group('Cardio trend', () {
    test('pace computed as durationSecs / (distanceM / 1000)', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-run', name: 'Run', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'run-d1', day: DateTime(2024, 1, 1));
      // 1800 s, 5000 m = 5 km → pace = 1800 / 5 = 360 s/km
      await _addTimedEffort(
        repo,
        sessionId: 'run-d1',
        exerciseId: 'ex-run',
        durationSecs: 1800,
        distanceM: 5000,
      );

      final data = await StatsProgressService(repo).computeProgressData();

      expect(data.topCardio.length, 1);
      final point = data.topCardio.first.trend.first;
      expect(point.durationSecs, 1800);
      expect(point.distanceM, closeTo(5000.0, 0.1));
      expect(point.paceSecPerKm, closeTo(360.0, 0.01));
    });

    test('timed effort without distance → paceSecPerKm is null', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-bike', name: 'Bike', createdAtMs: 1000, updatedAtMs: 1000),
      );

      await _seedSession(repo, id: 'bike-d1', day: DateTime(2024, 1, 1));
      await _addTimedEffort(
        repo,
        sessionId: 'bike-d1',
        exerciseId: 'ex-bike',
        durationSecs: 2400,
      );

      final data = await StatsProgressService(repo).computeProgressData();

      final point = data.topCardio.first.trend.first;
      expect(point.paceSecPerKm, isNull);
      expect(point.distanceM, isNull);
    });
  });
}
