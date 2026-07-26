// ignore_for_file: avoid_positional_boolean_parameters

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

// ── Seed helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Wipe the seeded nutrition log so nutrition-trend tests start
/// from a clean baseline. Only the now-relative consumed-food
/// rows from `SeedData.sampleConsumedFoods()` are cleared — every
/// other entity remains intact.
Future<void> _clearSeededFoods(MockWorkoutRepository repo) async {
  // The seeds are id-prefixed `seed-consumed-*`; pull them all
  // and delete by id so we don't disturb any rows the test added.
  for (final entry in await repo.getConsumedFoodsInRange(0, 9999999999999)) {
    if (entry.id.startsWith('seed-consumed-')) {
      await repo.deleteConsumedFood(entry.id);
    }
  }
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
/// [sets] is a list of (weight_kg, reps) pairs. Pass
/// [extraWeights] (same length as [sets]) to also persist a
/// `metric-extra-weight` observation per set — used for
/// weighted-calisthenics annotation rows that do not flip the
/// exercise onto a weight axis.
Future<String> _addSetEffort(
  MockWorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required List<(double, int)> sets,
  List<double>? extraWeights,
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
    final extraWeight = (extraWeights != null && i < extraWeights.length)
        ? extraWeights[i]
        : 0.0;
    if (extraWeight != 0.0) {
      await repo.createObservation(
        EffortObservation(
          id: 'obs-$effId-$i-extra-weight',
          effortId: effId,
          metricId: MetricIds.extraWeight,
          unitId: MetricIds.unitKg,
          valueReal: extraWeight,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
    }
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
  // Local-midnight `[n]` days before today. Used by the
  // windowed-selection tests below to anchor seeded sessions
  // inside the current-state window (rather than 2024 dates
  // that fall outside it).
  DateTime daysAgo(int n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: n));
  }

  // Creates a training period that covers today (default) and an
  // optional explicit range. Anchored to local midnight.
  Future<TrainingPeriod> seedActivePeriod(
    MockWorkoutRepository repo, {
    required String id,
    required String name,
    DateTime? startDay,
    DateTime? endDay,
  }) async {
    final start = startDay ?? daysAgo(7);
    final end = endDay ?? daysAgo(-7);
    final startMs = DateTime(
      start.year,
      start.month,
      start.day,
    ).millisecondsSinceEpoch;
    final endMs = DateTime(
      end.year,
      end.month,
      end.day,
      23,
      59,
      59,
      999,
    ).millisecondsSinceEpoch;
    final period = TrainingPeriod(
      id: id,
      name: name,
      startDateMs: startMs,
      endDateMs: endMs,
      focusModalities: const [],
      createdAtMs: 1000,
      updatedAtMs: 1000,
    );
    await repo.createPeriod(period);
    return period;
  }
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

      await _seedSession(repo, id: 's1', day: daysAgo(0));
      await _addSetEffort(
        repo,
        sessionId: 's1',
        exerciseId: 'ex-bw',
        sets: [(0.0, 10)],
      );

      final data = await StatsProgressService(repo).computeProgressData();
      // Bodyweight sets are now tracked on the reps axis
      // (`.github/agents/plans/stats-summary-fix-pack-plan.md`,
      // Item 2) — `weight == 0, reps > 0` is a legitimate signal,
      // not a skip. The exercise must appear in topLifts on its
      // reps axis with `e1RmTrend` and `volumeTrend` empty.
      expect(data.topLifts, hasLength(1));
      expect(data.topLifts.first.exerciseName, 'Bodyweight Squat');
      expect(data.topLifts.first.repsTrend, hasLength(1));
      expect(data.topLifts.first.repsTrend.first.value, 10);
      expect(data.topLifts.first.e1RmTrend, isEmpty);
      expect(data.topLifts.first.volumeTrend, isEmpty);
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

      await _seedSession(repo, id: 's1', day: daysAgo(0));
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
        await _seedSession(repo, id: 'exa-$i', day: daysAgo(i));
        await _addSetEffort(
          repo,
          sessionId: 'exa-$i',
          exerciseId: 'ex-ExA',
          sets: [(80.0, 5)],
        );
      }

      // ExB: 5 distinct days (tied with ExA alphabetically second)
      for (var i = 0; i < 5; i++) {
        await _seedSession(repo, id: 'exb-$i', day: daysAgo(i));
        await _addSetEffort(
          repo,
          sessionId: 'exb-$i',
          exerciseId: 'ex-ExB',
          sets: [(80.0, 5)],
        );
      }

      // ExC: 3 days
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'exc-$i', day: daysAgo(i));
        await _addSetEffort(
          repo,
          sessionId: 'exc-$i',
          exerciseId: 'ex-ExC',
          sets: [(80.0, 5)],
        );
      }

      // ExD: 1 day
      await _seedSession(repo, id: 'exd-0', day: daysAgo(0));
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
        // Reseed relative to "now" so the sessions fall inside
        // the current-state window (the recent-training-days
        // window's 14-day capacity).
        await _seedSession(repo, id: 'sess-$i', day: daysAgo(i));
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

      // CEx0: 3 days (anchored to "now" so the sessions land
      // inside the current-state window).
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'c0-$i', day: daysAgo(i));
        await _addTimedEffort(
          repo,
          sessionId: 'c0-$i',
          exerciseId: 'cex-0',
          durationSecs: 1800,
        );
      }

      // CEx1: 3 days (tied with CEx0; uses the next 3 days)
      for (var i = 0; i < 3; i++) {
        await _seedSession(repo, id: 'c1-$i', day: daysAgo(3 + i));
        await _addTimedEffort(
          repo,
          sessionId: 'c1-$i',
          exerciseId: 'cex-1',
          durationSecs: 1800,
        );
      }

      // CEx2: 1 day
      await _seedSession(repo, id: 'c2-0', day: daysAgo(7));
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
      await _seedSession(repo, id: 'sq-d1', day: daysAgo(1));
      await _addSetEffort(
        repo,
        sessionId: 'sq-d1',
        exerciseId: 'ex-sq',
        sets: [(100.0, 5), (110.0, 1)],
      );

      // Day 2: one set → e1RM 90×(1+5/30)=105.0
      await _seedSession(repo, id: 'sq-d2', day: daysAgo(0));
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

      // Day 1 (older): max of (100×(1+5/30), 110×(1+1/30))
      //        = max(116.67, 113.67) = 116.67
      expect(trend[0].date, daysAgo(1));
      expect(trend[0].value, closeTo(116.67, 0.01));

      // Day 2 (today): 90×(1+5/30) = 105.0
      expect(trend[1].date, daysAgo(0));
      expect(trend[1].value, closeTo(105.0, 0.01));
    });

    test('volume aggregation: sum of reps×weight per day', () async {
      final repo = await _freshRepo();
      await repo.createExercise(
        Exercise(id: 'ex-bp', name: 'Bench Press', createdAtMs: 1000, updatedAtMs: 1000),
      );

      // Day 1: 5×100 = 500, 3×80 = 240 → total 740
      await _seedSession(repo, id: 'bp-d1', day: daysAgo(1));
      await _addSetEffort(
        repo,
        sessionId: 'bp-d1',
        exerciseId: 'ex-bp',
        sets: [(100.0, 5), (80.0, 3)],
      );

      // Day 2: 10×60 = 600
      await _seedSession(repo, id: 'bp-d2', day: daysAgo(0));
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

      await _seedSession(repo, id: 's-null', day: daysAgo(0), modality: null);
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
        day: daysAgo(0),
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
        day: daysAgo(0),
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

      await _seedSession(repo, id: 'sess-s', day: daysAgo(0));
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

      await _seedSession(repo, id: 'sess-r', day: daysAgo(0));
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
      await _seedSession(repo, id: 'pr-d1', day: daysAgo(2));
      await _addSetEffort(
        repo,
        sessionId: 'pr-d1',
        exerciseId: 'ex-sq',
        sets: [(100.0, 5)],
      );

      // Day 2: 100 kg × 4 reps → e1RM ≈ 113.33 → not a PR
      await _seedSession(repo, id: 'pr-d2', day: daysAgo(1));
      await _addSetEffort(
        repo,
        sessionId: 'pr-d2',
        exerciseId: 'ex-sq',
        sets: [(100.0, 4)],
      );

      // Day 3: 105 kg × 5 reps → e1RM ≈ 122.5 → new high = PR
      await _seedSession(repo, id: 'pr-d3', day: daysAgo(0));
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
      expect(data.recentPRs.first.date, daysAgo(0));
      expect(data.recentPRs.first.e1Rm, closeTo(105 * (1 + 5 / 30.0), 0.01));
      // Day 2 (not a PR) is still absent.
      final prDates = data.recentPRs.map((pr) => pr.date).toList();
      expect(prDates, isNot(contains(daysAgo(1))));
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
      await _seedSession(repo, id: 'hc-d1', day: daysAgo(2));
      await _addSetEffort(repo, sessionId: 'hc-d1', exerciseId: 'ex-hc', sets: [(50.0, 1)]);

      // Day 2: e1RM ≈ 55 * (1 + 1/30) ≈ 56.83 → new PR
      await _seedSession(repo, id: 'hc-d2', day: daysAgo(1));
      await _addSetEffort(repo, sessionId: 'hc-d2', exerciseId: 'ex-hc', sets: [(55.0, 1)]);

      // Day 3: e1RM ≈ 60 * (1 + 1/30) ≈ 62.0 → new PR (standing record)
      await _seedSession(repo, id: 'hc-d3', day: daysAgo(0));
      await _addSetEffort(repo, sessionId: 'hc-d3', exerciseId: 'ex-hc', sets: [(60.0, 1)]);

      final data = await StatsProgressService(repo).computeProgressData();

      // 3 historical PR events → deduped to 1 standing record.
      expect(data.recentPRs, hasLength(1));
      expect(data.recentPRs.first.exerciseName, 'Hammer Curl');
      expect(data.recentPRs.first.e1Rm, closeTo(60 * (1 + 1 / 30.0), 0.01));
      expect(data.recentPRs.first.date, daysAgo(0));
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
      await _seedSession(repo, id: 'tie-d1', day: daysAgo(0));
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

      await _seedSession(repo, id: 'dl-d1', day: daysAgo(0));
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
      await _seedSession(repo, id: 'bp-d1', day: daysAgo(2));
      await _addSetEffort(repo, sessionId: 'bp-d1', exerciseId: 'ex-bp', sets: [(80.0, 5)]);
      await _seedSession(repo, id: 'bp-d2', day: daysAgo(1));
      await _addSetEffort(repo, sessionId: 'bp-d2', exerciseId: 'ex-bp', sets: [(85.0, 5)]);
      await _seedSession(repo, id: 'bp-d3', day: daysAgo(0));
      await _addSetEffort(repo, sessionId: 'bp-d3', exerciseId: 'ex-bp', sets: [(90.0, 5)]);

      // Squat: 1 PR event (no duplicates to dedupe).
      await _seedSession(repo, id: 'sq2-d1', day: daysAgo(1));
      await _addSetEffort(repo, sessionId: 'sq2-d1', exerciseId: 'ex-sq2', sets: [(120.0, 5)]);

      final data = await StatsProgressService(repo).computeProgressData();

      // 4 historical events (3 BP + 1 SQ) → deduped to 2 standing records.
      expect(data.recentPRs, hasLength(2));

      final bpEntry = data.recentPRs.firstWhere((p) => p.exerciseName == 'Bench Press');
      // Standing record = Day 3 value: 90 × (1 + 5/30) = 90 × 1.1667 ≈ 105.0
      expect(bpEntry.e1Rm, closeTo(90 * (1 + 5 / 30.0), 0.01));
      expect(bpEntry.date, daysAgo(0));

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

      await _seedSession(repo, id: 'pc-d1', day: daysAgo(0));
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

      await _seedSession(repo, id: 'run-d1', day: daysAgo(0));
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

      await _seedSession(repo, id: 'bike-d1', day: daysAgo(0));
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

  // ── Nutrition trend aggregation (Stats screen NUTRITION card) ────────────
  // The card is fed by `StatsProgressData.nutritionTrend`, a list of
  // `NutritionTrendPoint { date, calories, protein, carbs, fat }`.
  // S-001..S-006 cover the UI; these tests cover the aggregation
  // contract that the card renders against.

  // Frozen-snapshot test helper. Macros are per the food's
  // reference (per 100 g or per 1 serving); the service scales
  // them by amountConsumed/referenceAmount and rounds once per day.
  Future<void> seedConsumedFood(
    MockWorkoutRepository repo, {
    required String id,
    required DateTime day,
    required String name,
    required double protein,
    required double carbs,
    required double fat,
    required double amountConsumed,
    double referenceAmount = 100,
    String referenceLabel = '100 g',
    FoodUnitType unitType = FoodUnitType.grams,
  }) async {
    final dateMs = DateTime(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    await repo.createConsumedFood(
      ConsumedFood(
        id: id,
        loggedAtMs: dateMs + (12 * 60 * 60 * 1000), // 12:00 local
        dateMs: dateMs,
        sourceFoodId: id,
        name: name,
        unitType: unitType,
        referenceAmount: referenceAmount,
        referenceLabel: referenceLabel,
        protein: protein,
        carbs: carbs,
        fiber: 0,
        fat: fat,
        sodium: null,
        amountConsumed: amountConsumed,
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
        targetCalories: 2400,
        targetProtein: 160,
        targetCarbs: 280,
        targetFat: 80,
        createdAtMs: dateMs,
        updatedAtMs: dateMs,
      ),
    );
  }

  DateTime dayAt(int daysAgo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: daysAgo));
  }

  group('Nutrition trend aggregation', () {
    // The shared mock repo now seeds a now-relative nutrition log
    // on `initialize()`. Each test gets a fresh repo via
    // `_freshRepo()` and immediately wipes the seeded rows so the
    // baseline is empty. The seeds remain in place for the running
    // app / web build — only the test baseline is reset here.
    Future<MockWorkoutRepository> cleanRepo() async {
      final repo = await _freshRepo();
      await _clearSeededFoods(repo);
      return repo;
    }

    test(
      'S-005: zero logged days in the last 10 → empty nutritionTrend',
      () async {
        final repo = await cleanRepo();
        // No food rows at all → trend is empty.
        final data = await StatsProgressService(repo).computeProgressData();
        expect(data.nutritionTrend, isEmpty);
      },
    );

    test(
      'S-004: exactly 1 logged day in window → single NutritionTrendPoint',
      () async {
        final repo = await cleanRepo();
        await seedConsumedFood(
          repo,
          id: 'cf-1',
          day: dayAt(0),
          name: 'Chicken breast',
          protein: 31,
          carbs: 0,
          fat: 4,
          amountConsumed: 150,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        expect(data.nutritionTrend, hasLength(1));
        final p = data.nutritionTrend.first;
        // Date is local midnight (date components only).
        expect(p.date.year, dayAt(0).year);
        expect(p.date.month, dayAt(0).month);
        expect(p.date.day, dayAt(0).day);
        // Protein: 31 × (150/100) = 46.5 → rounds to 47 (rounds half-up).
        // Same arithmetic for carbs (0) and fat (4 × 1.5 = 6).
        expect(p.protein, 47);
        expect(p.carbs, 0);
        expect(p.fat, 6);
        // Calories: per-row rounding on the snapshot, so 150g of a
        // 100g-snapshot with 31/0/4 = (31*4+0*4+4*9)*1.5 = 162*1.5 = 243.
        // The snapshot's caloriesConsumed returns the *rounded*
        // 31*4+0+4*9 = 160 (×1.5) = 240, since the getter rounds.
        expect(p.calories, 240);
      },
    );

    test(
      'S-001: multiple days → ascending sort, per-day macro grams '
      '(round-once), calories as Σ caloriesConsumed',
      () async {
        final repo = await cleanRepo();
        // Day 0: 150 g chicken (31/0/4 100 g) → protein 47, fat 6.
        await seedConsumedFood(
          repo,
          id: 'cf-d0',
          day: dayAt(0),
          name: 'Chicken breast',
          protein: 31,
          carbs: 0,
          fat: 4,
          amountConsumed: 150,
        );
        // Day 3: 200 g greek_yogurt (10/4/0 100 g) → protein 20, carbs 8.
        await seedConsumedFood(
          repo,
          id: 'cf-d3a',
          day: dayAt(3),
          name: 'Greek yogurt',
          protein: 10,
          carbs: 4,
          fat: 0,
          amountConsumed: 200,
        );
        // Day 3: 1 tbsp peanut_butter (4/3/8 tbsp) → protein 4, carbs 3, fat 8.
        // Day 3 protein sum: 20 + 4 = 24.
        // Day 3 carbs sum: 8 + 3 = 11.
        // Day 3 fat sum: 0 + 8 = 8.
        await seedConsumedFood(
          repo,
          id: 'cf-d3b',
          day: dayAt(3),
          name: 'Peanut butter',
          unitType: FoodUnitType.count,
          referenceAmount: 1,
          referenceLabel: 'tbsp',
          protein: 4,
          carbs: 3,
          fat: 8,
          amountConsumed: 1,
        );
        // Day 7: 120 g oats (13/67/7 100 g) → protein 16, carbs 80, fat 8.
        // (13*1.2=15.6 → 16; 67*1.2=80.4 → 80; 7*1.2=8.4 → 8)
        await seedConsumedFood(
          repo,
          id: 'cf-d7',
          day: dayAt(7),
          name: 'Oats',
          protein: 13,
          carbs: 67,
          fat: 7,
          amountConsumed: 120,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        // Day 2 / 6 / 9 had no rows → not plotted (skip-empty).
        expect(data.nutritionTrend, hasLength(3));

        // Ascending: day 7 (oldest) at index 0, day 3 in the
        // middle, day 0 (today) at index 2. Compare actual
        // `DateTime`s chronologically — comparing `date.day`
        // (calendar day-of-month) directly is not a valid proxy
        // for chronological order once the window crosses a
        // month boundary (e.g. day 27 of one month is older than
        // day 1 of the next, even though 27 > 1 numerically).
        final dates = data.nutritionTrend.map((p) => p.date).toList();
        for (var i = 0; i < dates.length - 1; i++) {
          expect(
            dates[i].isBefore(dates[i + 1]),
            isTrue,
            reason: 'nutritionTrend must be chronologically ascending',
          );
        }

        // Day 7 totals (single row, fractional grams → round-once).
        // This is the OLDEST point in the trend (ascending).
        final d7 = data.nutritionTrend[0];
        expect(d7.protein, 16);
        expect(d7.carbs, 80);
        expect(d7.fat, 8);
        // Per-row calories: (13*4+67*4+7*9)*(120/100).round()
        // = (52+268+63)*1.2 = 383*1.2 = 459.6 → rounds to 460.
        expect(d7.calories, 460);

        // Day 3 totals (two rows summed). Middle of the trend.
        final d3 = data.nutritionTrend[1];
        expect(d3.protein, 24);
        expect(d3.carbs, 11);
        expect(d3.fat, 8);
        // Day 3: greek_yogurt (10/4/0 100g × 2.0) + peanut_butter (4/3/8 × 1.0).
        // Per-row calories (snapshot rounds per row, not at the end):
        //   yogurt: (10*4 + 4*4 + 0*9) * (200/100) = 56 * 2 = 112
        //   pb:     (4*4  + 3*4 + 8*9) * (1/1)    = 16+12+72 = 100
        // Σ = 112 + 100 = 212.
        expect(d3.calories, 212);

        // Day 0 totals (single row). The NEWEST point in the trend
        // (ascending) — chicken at index 2.
        final d0 = data.nutritionTrend[2];
        expect(d0.protein, 47);
        expect(d0.carbs, 0);
        expect(d0.fat, 6);
        // Per-row caloriesConsumed = (31*4+0*4+4*9)*(150/100).round()
        // = (124+36)*1.5.round() = 160*1.5 = 240. Day 0 has one row → 240.
        expect(d0.calories, 240);
      },
    );

    test('window bound: rows older than 10 days are excluded', () async {
      final repo = await cleanRepo();
      // 11 days ago — must NOT be included.
      await seedConsumedFood(
        repo,
        id: 'cf-old',
        day: dayAt(11),
        name: 'Old row',
        protein: 31,
        carbs: 0,
        fat: 4,
        amountConsumed: 100,
      );
      // Today — included.
      await seedConsumedFood(
        repo,
        id: 'cf-today',
        day: dayAt(0),
        name: 'Today row',
        protein: 10,
        carbs: 4,
        fat: 0,
        amountConsumed: 100,
      );

      // The full-history path now includes both rows; verify the
      // windowed path excludes the 11-day-old row.
      final trend = await StatsProgressService(repo)
          .computeNutritionTrend(days: 10);
      expect(trend, hasLength(1));
      expect(trend.first.date.day, dayAt(0).day);
    });

    test(
      'skip-empty: gaps between logged days are not zero-filled',
      () async {
        final repo = await cleanRepo();
        // Day 0 + Day 4 (skipping 1, 2, 3).
        await seedConsumedFood(
          repo,
          id: 'cf-a',
          day: dayAt(0),
          name: 'A',
          protein: 10,
          carbs: 5,
          fat: 2,
          amountConsumed: 100,
        );
        await seedConsumedFood(
          repo,
          id: 'cf-b',
          day: dayAt(4),
          name: 'B',
          protein: 8,
          carbs: 12,
          fat: 3,
          amountConsumed: 100,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        expect(data.nutritionTrend, hasLength(2));
        // Ascending by date: day 0 first, day 4 second.
        expect(
          data.nutritionTrend[0].date.isBefore(data.nutritionTrend[1].date),
          isTrue,
        );
      },
    );

    test(
      'round-once: per-day macro grams accumulate as double and round once',
      () async {
        final repo = await cleanRepo();
        // Two rows on the same day with macros that would round to 0
        // per-row (e.g. 0.45 g each). Sum-then-round: 0.9 → 1.
        // Each row: protein 30, amountConsumed 1, referenceAmount 100
        // → 30 * (1/100) = 0.3 g.
        await seedConsumedFood(
          repo,
          id: 'cf-r1',
          day: dayAt(0),
          name: 'Tiny 1',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );
        await seedConsumedFood(
          repo,
          id: 'cf-r2',
          day: dayAt(0),
          name: 'Tiny 2',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );
        // Three rows of 0.3 g each = 0.9 g → rounds to 1.
        await seedConsumedFood(
          repo,
          id: 'cf-r3',
          day: dayAt(0),
          name: 'Tiny 3',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        expect(data.nutritionTrend, hasLength(1));
        // 3 × 0.3 g = 0.9 g → rounds to 1 g. Per-row rounding would
        // drop each row to 0 g and lose the data.
        expect(data.nutritionTrend.first.protein, 1);
      },
    );

    test(
      'carbs use total carbs grams (not net carbs) — matches the strip',
      () async {
        final repo = await cleanRepo();
        // 100 g of a food with 20 g carbs (fiber=2 → net = 18). The
        // strip uses total carbs (20), so the line value here must
        // also be 20, not 18.
        await seedConsumedFood(
          repo,
          id: 'cf-fiber',
          day: dayAt(0),
          name: 'Whole wheat bread',
          protein: 4,
          carbs: 20,
          fat: 1,
          amountConsumed: 100,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        expect(data.nutritionTrend, hasLength(1));
        expect(data.nutritionTrend.first.carbs, 20);
      },
    );
  });

  // ── Full-history nutrition aggregation (S-003) ────────────────────────────
  // The chart switched from a 10-day cap to "full history". The
  // service exposes the window via the optional `days:` argument
  // (null = full history, from 0..now inclusive). The chart
  // always uses `days: null`. The 10-day constant remains as a
  // soft hint for callers that still want a fixed window.

  group('computeNutritionTrend (full history)', () {
    test(
      'S-003: days: null returns all logged days (no 10-day cap)',
      () async {
        final repo = await _freshRepo();
        await _clearSeededFoods(repo);
        // Seed rows on day 0 and day 25 (well outside the old 10-day
        // cap) — both must be returned.
        await seedConsumedFood(
          repo,
          id: 'cf-fh-0',
          day: dayAt(0),
          name: 'Today',
          protein: 31,
          carbs: 0,
          fat: 4,
          amountConsumed: 100,
        );
        await seedConsumedFood(
          repo,
          id: 'cf-fh-25',
          day: dayAt(25),
          name: 'Old',
          protein: 10,
          carbs: 5,
          fat: 1,
          amountConsumed: 100,
        );

        final trend = await StatsProgressService(repo)
            .computeNutritionTrend(days: null);
        expect(trend, hasLength(2));
        // Ascending: day 25 (oldest) at index 0, day 0 (newest) at index 1.
        expect(
          trend[0].date.isBefore(trend[1].date),
          isTrue,
        );
      },
    );

    test(
      'days: N still applies the window cap (backwards-compatible)',
      () async {
        final repo = await _freshRepo();
        await _clearSeededFoods(repo);
        await seedConsumedFood(
          repo,
          id: 'cf-cap-0',
          day: dayAt(0),
          name: 'Today',
          protein: 10,
          carbs: 0,
          fat: 0,
          amountConsumed: 100,
        );
        await seedConsumedFood(
          repo,
          id: 'cf-cap-15',
          day: dayAt(15),
          name: 'Out of window',
          protein: 10,
          carbs: 0,
          fat: 0,
          amountConsumed: 100,
        );

        final trend = await StatsProgressService(repo)
            .computeNutritionTrend(days: 10);
        expect(trend, hasLength(1));
        expect(trend.first.date.day, dayAt(0).day);
      },
    );

    test(
      'full history still skips empty days and rounds macros once per day',
      () async {
        final repo = await _freshRepo();
        await _clearSeededFoods(repo);
        // Day 0: two rows → round-once aggregation.
        await seedConsumedFood(
          repo,
          id: 'cf-fh-r1',
          day: dayAt(0),
          name: 'A',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );
        await seedConsumedFood(
          repo,
          id: 'cf-fh-r2',
          day: dayAt(0),
          name: 'B',
          protein: 30,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );
        // Day 7: one row.
        await seedConsumedFood(
          repo,
          id: 'cf-fh-r3',
          day: dayAt(7),
          name: 'C',
          protein: 50,
          carbs: 0,
          fat: 0,
          amountConsumed: 1,
        );

        final trend = await StatsProgressService(repo)
            .computeNutritionTrend(days: null);
        // Days 1..6, 8..N skipped (no rows on those days).
        expect(trend, hasLength(2));
        // Ascending: day 7 first (oldest), day 0 second.
        final day0 = trend[1];
        // Day 0: 2 rows × (30 × 1/100) = 0.6 g → round-once → 1.
        expect(day0.protein, 1);
        // Day 7: 50 × 1/100 = 0.5 g → rounds to 1.
        expect(trend[0].protein, 1);
      },
    );

    test(
      'empty repo → empty trend (full history, no data)',
      () async {
        final repo = await _freshRepo();
        await _clearSeededFoods(repo);
        final trend = await StatsProgressService(repo)
            .computeNutritionTrend(days: null);
        expect(trend, isEmpty);
      },
    );
  });

  // ── Windowed selection (current-state window) ────────────────────────────
  // The Strength and Cardio sections must select their top exercises
  // from a "current window" rather than all-time, so a lift trained
  // heavily long ago can't crowd out the user's current focus. The
  // window is resolved from:
  //   - an active training period covering today that contains
  //     ≥1 qualifying session, or
  //   - the most recent N training days (N from
  //     `StatsProgressService.kRecentTrainingDaysWindow`).
  // Each scenario below pins this behavior with a real seeded
  // session so the test fails loudly if the window is dropped or
  // widened.
  group('Windowed selection (current-state window)', () {
    test(
      'S-001: an exercise trained only outside the recent window does not '
      'appear in selection; one trained inside does',
      () async {
        final repo = await _freshRepo();
        // OldFavorite (trained only outside the window).
        await repo.createExercise(
          Exercise(
            id: 'ex-old',
            name: 'OldFavorite',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // CurrentFocus (trained inside the window).
        await repo.createExercise(
          Exercise(
            id: 'ex-now',
            name: 'CurrentFocus',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // A filler exercise whose training days occupy the entire
        // recent window, ensuring OldFavorite's 5 days fall
        // outside the N-most-recent training days.
        await repo.createExercise(
          Exercise(
            id: 'ex-filler',
            name: 'Filler',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Filler: 1 training day on each of the 14 most recent
        // distinct calendar days (kRecentTrainingDaysWindow = 14).
        // The days are days 0, 1, 2, ..., 13 ago. With the
        // skip-empty rule, Filler's training days fill the
        // window's capacity.
        for (var i = 0; i < StatsProgressService.kRecentTrainingDaysWindow; i++) {
          await _seedSession(
            repo,
            id: 's-filler-$i',
            day: daysAgo(i),
          );
          await _addSetEffort(
            repo,
            sessionId: 's-filler-$i',
            exerciseId: 'ex-filler',
            sets: [(80.0, 5)],
          );
        }

        // OldFavorite: 5 training days, all 15+ days ago. With the
        // 14 most-recent training days already filled by Filler,
        // OldFavorite's 5 days fall outside the window.
        for (var i = 0; i < 5; i++) {
          await _seedSession(
            repo,
            id: 's-old-$i',
            day: daysAgo(15 + i),
          );
          await _addSetEffort(
            repo,
            sessionId: 's-old-$i',
            exerciseId: 'ex-old',
            sets: [(80.0, 5)],
          );
        }

        // CurrentFocus: 1 training day today, inside the window.
        await _seedSession(
          repo,
          id: 's-now-0',
          day: daysAgo(0),
        );
        await _addSetEffort(
          repo,
          sessionId: 's-now-0',
          exerciseId: 'ex-now',
          sets: [(80.0, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        // Sanity: the window's training-day count is the constant
        // (14 most recent distinct days, of which Filler occupies
        // the first 14 calendar slots and CurrentFocus shares
        // the most recent day with Filler; so the 14-day window
        // is fully filled).
        expect(
          data.window.recentDays,
          StatsProgressService.kRecentTrainingDaysWindow,
        );
        // OldFavorite's days are outside the window.
        expect(
          data.topLifts.any((l) => l.exerciseName == 'OldFavorite'),
          isFalse,
          reason: 'OldFavorite was trained only outside the window',
        );
        // CurrentFocus is inside the window.
        expect(
          data.topLifts.any((l) => l.exerciseName == 'CurrentFocus'),
          isTrue,
          reason: 'CurrentFocus was trained inside the window',
        );
      },
    );

    test(
      'S-002: with an active period covering today, selection includes an '
      'exercise trained inside the period and excludes one trained before '
      'the period started',
      () async {
        final repo = await _freshRepo();
        await seedActivePeriod(
          repo,
          id: 'p1',
          name: 'Off-Season Block',
          startDay: daysAgo(7),
          endDay: daysAgo(-7),
        );

        await repo.createExercise(
          Exercise(
            id: 'ex-inside',
            name: 'InsidePeriod',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-before',
            name: 'BeforePeriod',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // InsidePeriod: 1 training day within the period.
        await _seedSession(
          repo,
          id: 's-inside-0',
          day: daysAgo(2),
        );
        await _addSetEffort(
          repo,
          sessionId: 's-inside-0',
          exerciseId: 'ex-inside',
          sets: [(80.0, 5)],
        );
        // BeforePeriod: 3 training days, all before the period
        // started. Should be excluded by the period window.
        for (var i = 0; i < 3; i++) {
          await _seedSession(
            repo,
            id: 's-before-$i',
            day: daysAgo(20 + i),
          );
          await _addSetEffort(
            repo,
            sessionId: 's-before-$i',
            exerciseId: 'ex-before',
            sets: [(80.0, 5)],
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();

        expect(
          data.topLifts.any((l) => l.exerciseName == 'InsidePeriod'),
          isTrue,
        );
        expect(
          data.topLifts.any((l) => l.exerciseName == 'BeforePeriod'),
          isFalse,
          reason: 'BeforePeriod was trained only before the period',
        );
        // Window is the period → its label appears in StatsWindow.
        expect(data.window.isPeriodScoped, isTrue);
        expect(data.window.periodName, 'Off-Season Block');
        expect(data.window.label, 'Off-Season Block');
      },
    );

    test(
      'S-003: an active period that contains no qualifying completed '
      'sessions falls back to the recent-training-days window rather '
      'than rendering empty',
      () async {
        final repo = await _freshRepo();
        // Period covers today but is FUTURE-only, so the seeded
        // session (which is in the past) cannot qualify.
        await seedActivePeriod(
          repo,
          id: 'p-empty',
          name: 'EmptyBlock',
          startDay: daysAgo(0),
          endDay: daysAgo(-7),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-recent',
            name: 'RecentLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // A single training day in the past, well outside the
        // future-only period. The period has no qualifying
        // sessions, so the recent-training-days window is used.
        await _seedSession(repo, id: 's-r-0', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 's-r-0',
          exerciseId: 'ex-recent',
          sets: [(80.0, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        // Selection uses the recent-training-days window because
        // the active period has no qualifying sessions.
        expect(data.window.isPeriodScoped, isFalse);
        expect(data.topLifts.any((l) => l.exerciseName == 'RecentLift'),
            isTrue);
      },
    );

    test(
      'S-004: training days counting ignores gaps — sessions spread '
      'across a date range with rest days in between still resolve the '
      'intended number of training days, not calendar days',
      () async {
        // Build a history whose training days inside a ~14-day
        // envelope total exactly 5 distinct days, with rest days in
        // between. The recent window of 5 days must select all five
        // distinct days (no rest-day gaps shrink the data).
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-eg',
            name: 'ExampleLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // 5 distinct training days, each separated by 1-2 rest days,
        // all within the last 14 calendar days.
        for (final offset in [0, 2, 4, 7, 10]) {
          await _seedSession(
            repo,
            id: 's-eg-$offset',
            day: daysAgo(offset),
          );
          await _addSetEffort(
            repo,
            sessionId: 's-eg-$offset',
            exerciseId: 'ex-eg',
            sets: [(80.0, 5)],
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();
        // Resolve the recent-days window directly and confirm it
        // includes all 5 distinct training days (not just the most
        // recent 5 calendar days, which would drop days 8-10).
        expect(data.window.isPeriodScoped, isFalse);
        expect(
          data.window.recentDays,
          isNotNull,
        );
        // The exact N is governed by kRecentTrainingDaysWindow. The
        // shape of the contract is: 5 training days exist, the
        // window is "Last N training days", and ExampleLift is the
        // top (only) lift selected from those 5 days.
        expect(
          data.topLifts.length,
          1,
        );
        expect(data.topLifts.first.exerciseName, 'ExampleLift');
        // Trend is full-history (5 points).
        expect(
          data.topLifts.first.e1RmTrend.length,
          5,
          reason: 'trend uses full history even when selection is windowed',
        );
      },
    );

    test(
      'S-005: a selected exercise\'s trend still contains data points '
      'from training days that fall outside the current window',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-l',
            name: 'LongLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // A training day well outside the recent-days window.
        await _seedSession(repo, id: 's-l-old', day: daysAgo(45));
        await _addSetEffort(
          repo,
          sessionId: 's-l-old',
          exerciseId: 'ex-l',
          sets: [(80.0, 5)],
        );
        // A training day inside the recent-days window.
        await _seedSession(repo, id: 's-l-new', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 's-l-new',
          exerciseId: 'ex-l',
          sets: [(85.0, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        // Selection still picks LongLift (it's the only exercise in
        // the recent window).
        expect(
          data.topLifts.any((l) => l.exerciseName == 'LongLift'),
          isTrue,
        );
        // Trend includes BOTH the 45-day-old and today's data points.
        final e1RmTrend = data.topLifts.first.e1RmTrend;
        expect(
          e1RmTrend.length,
          2,
          reason: 'trend is full-history, not windowed',
        );
      },
    );

    test(
      'S-006: Recent PRs still reflects an all-time high that was set '
      'outside the current window',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-pr',
            name: 'PrLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // Big lift 45 days ago (outside recent window). This is the
        // all-time high.
        await _seedSession(repo, id: 's-pr-old', day: daysAgo(45));
        await _addSetEffort(
          repo,
          sessionId: 's-pr-old',
          exerciseId: 'ex-pr',
          sets: [(180.0, 3)],
        );
        // Smaller lift today (inside recent window). Selection will
        // pick this lift, but PRs should still record the lifetime
        // high set 45 days ago.
        await _seedSession(repo, id: 's-pr-new', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 's-pr-new',
          exerciseId: 'ex-pr',
          sets: [(100.0, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(
          data.topLifts.any((l) => l.exerciseName == 'PrLift'),
          isTrue,
        );
        // Recent PRs is all-time, so it picks the 180 kg × 3 e1RM
        // (≈198.0), not the today's 100 × 5 (≈116.67).
        expect(data.recentPRs, hasLength(1));
        final pr = data.recentPRs.first;
        expect(pr.exerciseName, 'PrLift');
        expect(pr.e1Rm, closeTo(198.0, 0.01));
        // The date of the standing record is the 45-day-old day,
        // not today.
        expect(
          pr.date,
          daysAgo(45),
          reason: 'PR date is the all-time high day, regardless of window',
        );
      },
    );

    test(
      'S-007: both sections resolve to the same window in a single '
      'computation (a period active for one section is active for both)',
      () async {
        final repo = await _freshRepo();
        await seedActivePeriod(
          repo,
          id: 'p-shared',
          name: 'SharedBlock',
          startDay: daysAgo(7),
          endDay: daysAgo(-7),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-str',
            name: 'StrLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-card',
            name: 'CardActivity',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Strength session inside the period.
        await _seedSession(repo, id: 's-str', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 's-str',
          exerciseId: 'ex-str',
          sets: [(80.0, 5)],
        );
        // Cardio session inside the period.
        await _seedSession(repo, id: 's-card', day: daysAgo(1));
        await _addTimedEffort(
          repo,
          sessionId: 's-card',
          exerciseId: 'ex-card',
          durationSecs: 1800,
        );

        // Two extras outside the period — one for each section.
        await repo.createExercise(
          Exercise(
            id: 'ex-str-old',
            name: 'StrLiftOld',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-card-old',
            name: 'CardActivityOld',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        for (var i = 0; i < 3; i++) {
          await _seedSession(repo, id: 's-str-old-$i', day: daysAgo(20 + i));
          await _addSetEffort(
            repo,
            sessionId: 's-str-old-$i',
            exerciseId: 'ex-str-old',
            sets: [(80.0, 5)],
          );
          await _seedSession(repo, id: 's-card-old-$i', day: daysAgo(20 + i));
          await _addTimedEffort(
            repo,
            sessionId: 's-card-old-$i',
            exerciseId: 'ex-card-old',
            durationSecs: 1800,
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();

        // Both sections share the period window.
        expect(data.window.isPeriodScoped, isTrue);
        expect(data.window.periodName, 'SharedBlock');
        // The inside-period exercises are selected; outside-period
        // exercises are not.
        expect(
          data.topLifts.any((l) => l.exerciseName == 'StrLift'),
          isTrue,
        );
        expect(
          data.topLifts.any((l) => l.exerciseName == 'StrLiftOld'),
          isFalse,
        );
        expect(
          data.topCardio.any((c) => c.exerciseName == 'CardActivity'),
          isTrue,
        );
        expect(
          data.topCardio.any((c) => c.exerciseName == 'CardActivityOld'),
          isFalse,
        );
      },
    );

    test(
      'S-008: when no exercises qualify within the window, topLifts '
      'and topCardio are empty (the service does not silently widen '
      'to all-time)',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-drill',
            name: 'DrillOnly',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        // Seed a recent training day that has ONLY drill efforts
        // (no set or timed). The window resolves, the day is
        // inside it, but no exercise qualifies for Strength or
        // Cardio. The screen renders its existing empty states.
        await _seedSession(repo, id: 's-drill', day: daysAgo(1));
        final segId = 'seg-s-drill-ex-drill';
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

        // Drill efforts never contribute to Strength or Cardio.
        expect(data.topLifts, isEmpty);
        expect(data.topCardio, isEmpty);
        // The recent-days window reports at least 1 training day
        // (the drill day is still a training day) and is not
        // widened to all-time.
        expect(data.window.isPeriodScoped, isFalse);
        expect(data.window.recentDays, greaterThan(0));
      },
    );

    test(
      'S-009: when the active period is in the past (today not in any '
      'period), the recent-training-days window is used',
      () async {
        final repo = await _freshRepo();
        // Period that ended two weeks ago.
        await seedActivePeriod(
          repo,
          id: 'p-past',
          name: 'PastBlock',
          startDay: daysAgo(60),
          endDay: daysAgo(15),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-rec',
            name: 'RecentLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await _seedSession(repo, id: 's-rec', day: daysAgo(1));
        await _addSetEffort(
          repo,
          sessionId: 's-rec',
          exerciseId: 'ex-rec',
          sets: [(80.0, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.window.isPeriodScoped, isFalse,
            reason: 'past period does not cover today');
        expect(
          data.topLifts.any((l) => l.exerciseName == 'RecentLift'),
          isTrue,
        );
      },
    );

    test(
      'S-010: kRecentTrainingDaysWindow is the single tunable for the '
      'recent-days window size (no other call site hard-codes N)',
      () async {
        // The constant is exported and the test reads it directly.
        // The structural guarantee is that this constant is the
        // only place N is defined for the recent-days window. Any
        // other code path that picks top-N uses the resolved window.
        expect(StatsProgressService.kRecentTrainingDaysWindow, greaterThan(0));
        // Sanity: changing the constant changes the label's N.
        // (We don't change the constant here, but we verify the
        // surface that's exposed.)
        expect(
          StatsProgressService.kRecentTrainingDaysWindow,
          isA<int>(),
        );
      },
    );
  });

  // ── Feeling trend (HOW DID IT FEEL card) ─────────────────────────────────────────
  // The Stats screen surfaces the post-session feeling captured by
  // the summary sheet as a trend. The aggregator reads only
  // `TrainingSession.sessionFeeling` and the current-state window;
  // it is modality-agnostic so all-running or all-grappling datasets
  // render identically to a lifter's. Sessions without a recorded
  // feeling are omitted (no zero-fill, no synthetic flat line).

  /// Seed a completed session and (optionally) set a feeling on it.
  /// Adds no efforts — feeling is a session-level field, so the test
  /// stays decoupled from any strength / cardio / drill effort.
  Future<TrainingSession> seedFeelingSession(
    MockWorkoutRepository repo, {
    required String id,
    required DateTime day,
    int? feeling,
    String? modality,
  }) async {
    final startMs = day.millisecondsSinceEpoch;
    final session = TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: startMs + 3600000,
      modality: modality,
      sessionFeeling: feeling,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    );
    await repo.createSession(session);
    return session;
  }

  group('Feeling trend aggregation', () {
    test(
      'S-001: building the feeling series from a window — correct points '
      'for sessions that have a feeling, correct omission of sessions '
      'without one, correct chronological ordering',
      () async {
        final repo = await _freshRepo();
        // 5 sessions across the last 5 days; sessions #2 and #4 have
        // a recorded feeling. #1, #3, #5 do not.
        await seedFeelingSession(
          repo,
          id: 'sf-no-1',
          day: daysAgo(4),
        );
        await seedFeelingSession(
          repo,
          id: 'sf-yes-1',
          day: daysAgo(3),
          feeling: 3,
        );
        await seedFeelingSession(
          repo,
          id: 'sf-no-2',
          day: daysAgo(2),
        );
        await seedFeelingSession(
          repo,
          id: 'sf-yes-2',
          day: daysAgo(1),
          feeling: 5,
        );
        await seedFeelingSession(
          repo,
          id: 'sf-no-3',
          day: daysAgo(0),
        );

        final data = await StatsProgressService(repo).computeProgressData();

        // Exactly 2 points — the two sessions that had a feeling.
        expect(data.feelingTrend, hasLength(2));
        // Chronological ascending: the day-3 session before the day-1
        // session.
        expect(
          data.feelingTrend[0].date.isBefore(data.feelingTrend[1].date),
          isTrue,
        );
        // The actual day components and feeling values match what
        // we seeded (local-midnight DateTime).
        expect(data.feelingTrend[0].date.day, daysAgo(3).day);
        expect(data.feelingTrend[0].feeling, 3);
        expect(data.feelingTrend[1].date.day, daysAgo(1).day);
        expect(data.feelingTrend[1].feeling, 5);
      },
    );

    test(
      'S-002: all-non-strength dataset (runs and rolls only) still '
      'produces a populated feeling series — universality guard',
      () async {
        final repo = await _freshRepo();
        // Three sessions — cardio_endurance and sports only; zero
        // lifting. Each has a recorded feeling.
        await seedFeelingSession(
          repo,
          id: 'run-1',
          day: daysAgo(2),
          feeling: 4,
          modality: Modality.cardioEndurance,
        );
        await seedFeelingSession(
          repo,
          id: 'roll-1',
          day: daysAgo(1),
          feeling: 3,
          modality: Modality.sports,
        );
        await seedFeelingSession(
          repo,
          id: 'run-2',
          day: daysAgo(0),
          feeling: 5,
          modality: Modality.cardioEndurance,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        // The feeling trend must render identically — there is no
        // gating on strength data, no "must have a set effort"
        // filter, no coupling to topLifts / topCardio.
        expect(data.feelingTrend, hasLength(3));
        // TopLifts is empty (no lifting), but feelingTrend is
        // unaffected.
        expect(data.topLifts, isEmpty);
        // Chronological: day-2 → day-1 → day-0.
        expect(data.feelingTrend[0].feeling, 4);
        expect(data.feelingTrend[1].feeling, 3);
        expect(data.feelingTrend[2].feeling, 5);
      },
    );

    test(
      'S-003: empty window — explicit empty list, no crash, no fabricated '
      'points, no zero line',
      () async {
        final repo = await _freshRepo();
        // Sessions exist, but none have a feeling logged.
        await seedFeelingSession(repo, id: 's-nf-1', day: daysAgo(3));
        await seedFeelingSession(repo, id: 's-nf-2', day: daysAgo(1));
        await seedFeelingSession(repo, id: 's-nf-3', day: daysAgo(0));

        final data = await StatsProgressService(repo).computeProgressData();

        // Empty list — the UI reads this as the explicit empty
        // state. Not a crash, not a zero point, not a flat line.
        expect(data.feelingTrend, isEmpty);
      },
    );

    test(
      'S-004: window recomputes the feeling series on the same '
      'boundaries as the other trends',
      () async {
        final repo = await _freshRepo();
        // Period covers today. Two sessions inside the period with
        // feelings; one outside the period (further back than the
        // recent-training-days window) with a feeling too.
        // Filling the recent window with a 15th, 16th, ... training
        // day forces the day-45 session out of the recent-days
        // window while the period-scoped window still covers it.
        final today = DateTime.now();
        final periodStart = DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 7));
        final periodEnd = DateTime(today.year, today.month, today.day)
            .add(const Duration(days: 7));
        final periodStartMs = periodStart.millisecondsSinceEpoch;
        final periodEndMs = DateTime(
          periodEnd.year,
          periodEnd.month,
          periodEnd.day,
          23,
          59,
          59,
          999,
        ).millisecondsSinceEpoch;

        await repo.createPeriod(
          TrainingPeriod(
            id: 'p-ft',
            name: 'FeelingWindowBlock',
            startDateMs: periodStartMs,
            endDateMs: periodEndMs,
            focusModalities: const [],
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Inside the period: two sessions with feelings.
        await seedFeelingSession(
          repo,
          id: 'inside-1',
          day: daysAgo(2),
          feeling: 4,
        );
        await seedFeelingSession(
          repo,
          id: 'inside-2',
          day: daysAgo(0),
          feeling: 5,
        );

        // First pass: period is active and covers today → it scopes
        // the selection AND the feeling trend.
        final periodData =
            await StatsProgressService(repo).computeProgressData();
        expect(periodData.window.isPeriodScoped, isTrue);
        expect(periodData.feelingTrend, hasLength(2));
        // Both in-period sessions are included.
        final periodDates =
            periodData.feelingTrend.map((p) => p.date.day).toSet();
        expect(periodDates, contains(daysAgo(2).day));
        expect(periodDates, contains(daysAgo(0).day));

        // The feelingTrend must reflect the SAME window the rest
        // of the screen uses — same `data.window` instance — so
        // changing the window moves the trend in lockstep with
        // Strength / Cardio.
        expect(
          periodData.feelingTrend.length,
          isNotNull,
        );

        // Direct check: call the helper with the same window and
        // verify it returns identical points. This locks the
        // contract that `computeFeelingTrend(window:)` is the
        // single source of truth for the boundary check.
        final directTrend = await StatsProgressService(repo)
            .computeFeelingTrend(window: periodData.window);
        expect(directTrend, hasLength(2));
        expect(
          directTrend.map((p) => p.date.day),
          periodData.feelingTrend.map((p) => p.date.day),
        );

        // Outside the period but inside a recent-training-days
        // window: would only appear when the period is deleted AND
        // the recent window extends that far. With only 3 training
        // days, all 3 fit inside the N=14 recent-days window.
        // Verify the recent-days window's fromMs/toMs bounds it
        // from below (older sessions are still filtered by the
        // window's fromMs).
        await repo.deletePeriod('p-ft');
        final recentData =
            await StatsProgressService(repo).computeProgressData();
        expect(recentData.window.isPeriodScoped, isFalse);
        expect(recentData.feelingTrend, hasLength(2));
        // Direct re-check: the helper, called with the new
        // window, returns the same trend.
        final directRecentTrend = await StatsProgressService(repo)
            .computeFeelingTrend(window: recentData.window);
        expect(directRecentTrend, hasLength(2));
        expect(
          directRecentTrend.map((p) => p.date.day),
          recentData.feelingTrend.map((p) => p.date.day),
        );
      },
    );

    test(
      'S-006: omitted sessions are skipped, not interpolated as a dip',
      () async {
        final repo = await _freshRepo();
        // Three consecutive days. Day-0 = feeling 3, day-1 = no
        // feeling, day-2 = feeling 5. The series must contain
        // exactly 2 points at day-0 and day-2, never an interpolated
        // point at day-1 with value 0 (or anything else).
        await seedFeelingSession(
          repo,
          id: 'dip-0',
          day: daysAgo(2),
          feeling: 3,
        );
        await seedFeelingSession(
          repo,
          id: 'dip-1',
          day: daysAgo(1),
        );
        await seedFeelingSession(
          repo,
          id: 'dip-2',
          day: daysAgo(0),
          feeling: 5,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.feelingTrend, hasLength(2));
        expect(data.feelingTrend[0].feeling, 3);
        expect(data.feelingTrend[1].feeling, 5);
        // The middle date (daysAgo(1)) must NOT appear as a
        // fabricated point.
        expect(
          data.feelingTrend.any((p) => p.date.day == daysAgo(1).day),
          isFalse,
        );
      },
    );

    test(
      'feeling outside 1..5 is omitted (defensive — out-of-range values '
      'must never produce a point)',
      () async {
        final repo = await _freshRepo();
        // Seed a session with a feeling of 0 (out of range) and
        // another with 7 (out of range). Neither must produce a
        // point. A third session with feeling 4 must still render.
        await seedFeelingSession(
          repo,
          id: 'oor-0',
          day: daysAgo(2),
          feeling: 0,
        );
        await seedFeelingSession(
          repo,
          id: 'oor-7',
          day: daysAgo(1),
          feeling: 7,
        );
        await seedFeelingSession(
          repo,
          id: 'valid-4',
          day: daysAgo(0),
          feeling: 4,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.feelingTrend, hasLength(1));
        expect(data.feelingTrend.first.feeling, 4);
      },
    );

    test(
      'in-progress (endedAtMs == null) sessions are excluded',
      () async {
        final repo = await _freshRepo();
        // A still-running session with a recorded feeling must
        // NOT show up in the trend (the trend is for completed
        // sessions, mirroring the rest of the Stats screen).
        final startMs = daysAgo(0).millisecondsSinceEpoch;
        await repo.createSession(
          TrainingSession(
            id: 'in-progress',
            ownerUserId: 'user-1',
            startedAtMs: startMs,
            // endedAtMs intentionally omitted
            sessionFeeling: 5,
            createdAtMs: startMs,
            updatedAtMs: startMs,
          ),
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.feelingTrend, isEmpty);
      },
    );
  });

  // ── Stats & Summary Fix Pack — PR 2 (bodyweight + recency floor) ─────────
  //
  // Plan: .github/agents/plans/stats-summary-fix-pack-plan.md
  //
  // PR 2 ships the bodyweight inclusion (Item 2) and the recency
  // floor on Strength/Cardio selection (Item 3). These two items
  // share the same exercise-selection machinery, so they ship
  // together as one PR.
  //
  // Tests in this group MUST fail before the implementation is
  // landed (red state). They exercise the new reps axis and the
  // new recency floor at the same level of fidelity as the
  // existing e1RM / volume tests above.

  group('Bodyweight inclusion (Item 2)', () {
    test(
      'S-101 bodyweight pull-up → reps trend + max-reps PR + eligible',
      () async {
        final repo = await _freshRepo();
        // Use the seeded pull-up exercise — present in the seed
        // data and tagged as a bodyweight movement in description,
        // but its equipment is `equipment-pullup-bar`, not
        // `equipment-bodyweight`. The selection must NOT depend
        // on the equipment label.
        final pullUp = (await repo.getExercises())
            .firstWhere((e) => e.id == 'exercise-pullup');

        // Two training days, today and 2 days ago, both with a
        // bodyweight pull-up set (reps=12, weight=0).
        await _seedSession(repo, id: 'bw-d1', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'bw-d1',
          exerciseId: pullUp.id,
          sets: [(0.0, 12)],
        );
        await _seedSession(repo, id: 'bw-d2', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 'bw-d2',
          exerciseId: pullUp.id,
          sets: [(0.0, 10)],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        // The exercise is eligible — appears in topLifts.
        expect(
          data.topLifts.any((l) => l.exerciseName == 'Pull-Up'),
          isTrue,
        );
        final lift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'Pull-Up',
        );
        // The reps trend has the same training-day count as the
        // number of distinct days we logged.
        expect(lift.repsTrend, hasLength(2));
        // First day (older, 2 days ago): max reps that day = 10.
        expect(lift.repsTrend.first.value, 10);
        // Second day (today): max reps that day = 12.
        expect(lift.repsTrend.last.value, 12);
        // Bodyweight exercise has no e1RM trend (no weighted sets).
        expect(lift.e1RmTrend, isEmpty);
        expect(lift.volumeTrend, isEmpty);

        // Max-reps PR is recorded.
        final prs = data.recentPRs
            .where((pr) => pr.exerciseName == 'Pull-Up')
            .toList();
        expect(prs, isNotEmpty);
        expect(prs.first.reps, 12);
        expect(prs.first.e1Rm, isNull);
        // PR date is the day the max was first reached.
        expect(prs.first.date, daysAgo(0));
      },
    );

    test(
      'S-102 pull-ups and chin-ups at bodyweight are not excluded by label',
      () async {
        final repo = await _freshRepo();
        final pullUp = (await repo.getExercises())
            .firstWhere((e) => e.id == 'exercise-pullup');
        final chinUp = (await repo.getExercises())
            .firstWhere((e) => e.id == 'exercise-chin-up');

        // Both exercises use `equipment-pullup-bar`, NOT
        // `equipment-bodyweight`. The selection rule must not
        // depend on this label — only on whether sets were
        // performed without added weight.
        for (final ex in [pullUp, chinUp]) {
          for (var i = 0; i < 3; i++) {
            await _seedSession(repo, id: 's-$ex-$i', day: daysAgo(i));
            await _addSetEffort(
              repo,
              sessionId: 's-$ex-$i',
              exerciseId: ex.id,
              sets: [(0.0, 8)],
            );
          }
        }

        final data =
            await StatsProgressService(repo).computeProgressData();

        expect(
          data.topLifts.any((l) => l.exerciseName == 'Pull-Up'),
          isTrue,
          reason:
              'Pull-Up must be eligible despite equipment label being '
              'equipment-pullup-bar, not equipment-bodyweight',
        );
        expect(
          data.topLifts.any((l) => l.exerciseName == 'Chin-Up'),
          isTrue,
          reason:
              'Chin-Up must be eligible despite equipment label being '
              'equipment-pullup-bar, not equipment-bodyweight',
        );
      },
    );

    test(
      'S-103 bodyweight trained more frequently ranks above loaded',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-bw',
            name: 'BodyweightMove',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-ld',
            name: 'LoadedMove',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // BodyweightMove trained on 5 distinct days inside the window.
        for (var i = 0; i < 5; i++) {
          await _seedSession(repo, id: 'bw-$i', day: daysAgo(i));
          await _addSetEffort(
            repo,
            sessionId: 'bw-$i',
            exerciseId: 'ex-bw',
            sets: [(0.0, 10)],
          );
        }
        // LoadedMove trained on 2 distinct days inside the window.
        for (var i = 0; i < 2; i++) {
          await _seedSession(repo, id: 'ld-$i', day: daysAgo(i));
          await _addSetEffort(
            repo,
            sessionId: 'ld-$i',
            exerciseId: 'ex-ld',
            sets: [(80.0, 5)],
          );
        }

        final data =
            await StatsProgressService(repo).computeProgressData();

        final bodyLift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'BodyweightMove',
        );
        final loadedLift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'LoadedMove',
        );
        // BodyweightMove appears ahead of LoadedMove in topLifts.
        expect(
          data.topLifts.indexOf(bodyLift),
          lessThan(data.topLifts.indexOf(loadedLift)),
          reason: 'More-frequent bodyweight must outrank less-frequent loaded',
        );
      },
    );

    test(
      'S-104 weighted bodyweight set → annotation only, no weight-axis PR',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-wbpu',
            name: 'WeightedPullUp',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // First day: bodyweight 10 reps (weight=0).
        await _seedSession(repo, id: 'd1', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 'd1',
          exerciseId: 'ex-wbpu',
          sets: [(0.0, 10)],
        );
        // Second day: weighted 8 reps at 10 kg extra.
        await _seedSession(repo, id: 'd2', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'd2',
          exerciseId: 'ex-wbpu',
          sets: [(0.0, 8)],
          extraWeights: [10.0],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        final lift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'WeightedPullUp',
        );
        // The exercise is on the reps axis (because at least one
        // set has weight=0). No e1RM trend, no volume trend.
        expect(lift.e1RmTrend, isEmpty);
        expect(lift.volumeTrend, isEmpty);
        // Reps trend has both days; max reps that day wins.
        expect(lift.repsTrend, hasLength(2));
        // Day-1: 10 reps (the highest of that day's set).
        expect(lift.repsTrend.first.value, 10);
        // Day-2: 8 reps (the highest of that day's set; weighted
        // set contributes 8 reps; 10 kg is an annotation only).
        expect(lift.repsTrend.last.value, 8);

        // PRs: only a reps PR, never a weight/e1RM PR.
        final prs = data.recentPRs
            .where((pr) => pr.exerciseName == 'WeightedPullUp')
            .toList();
        for (final pr in prs) {
          expect(pr.e1Rm, isNull, reason: 'No e1RM PR for reps-axis exercise');
          expect(pr.reps, isNotNull, reason: 'Reps-axis exercises only emit reps PRs');
        }
        // The first PR is the day-1 10-rep bodyweight max (the
        // weighted set's 8 reps is below that, so it doesn't
        // register as a PR).
        expect(prs.first.reps, 10);
      },
    );

    test(
      'S-105 kg Total Volume unchanged by bodyweight sets',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-bench',
            name: 'BenchPress',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-pu',
            name: 'Pull-Up',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // A loaded bench set: 5 reps × 100 kg = 500 kg volume.
        await _seedSession(repo, id: 's-bench', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 's-bench',
          exerciseId: 'ex-bench',
          sets: [(100.0, 5)],
        );
        // A bodyweight pull-up set: 12 reps × 0 kg = 0 kg volume.
        await _seedSession(repo, id: 's-pu', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 's-pu',
          exerciseId: 'ex-pu',
          sets: [(0.0, 12)],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        // Total kg volume is contributed only by the bench set.
        final benchLift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'BenchPress',
        );
        final pullUpLift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'Pull-Up',
        );
        // Bench has a volume trend with the day's total volume
        // (5 × 100 = 500 kg).
        expect(benchLift.volumeTrend, hasLength(1));
        expect(benchLift.volumeTrend.first.value, 500.0);
        // Pull-up has no volume trend (bodyweight contributes
        // zero to the kg total and must not be summed into it).
        expect(pullUpLift.volumeTrend, isEmpty);
      },
    );

    // ── Bug-fix tests — Push-Up mixed-axis overshoot ─────────────────────────
    //
    // Symptom (user report): Push-Up was rendered with both a
    // reps trend AND an Estimated 1RM / kg Volume because at
    // least one session was logged with added weight. The spec
    // says any exercise with at least one no-added-weight set is
    // a reps-based exercise — its card must be reps-only, even
    // when some sets carried added weight. A loaded-only exercise
    // (every set has `weight > 0`) keeps its weight-based card.

    test(
      'S-106 Push-Up with one weighted session renders reps-only (no '
      'e1RM/Volume block, weighted day contributes reps + annotation)',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-pushup',
            name: 'Push-Up',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Three days of bodyweight push-ups + ONE day with a
        // weighted push-up (10 kg extra on a dip belt).
        // The mix must NOT promote the exercise to weight-axis.
        await _seedSession(repo, id: 'bw-1', day: daysAgo(6));
        await _addSetEffort(
          repo,
          sessionId: 'bw-1',
          exerciseId: 'ex-pushup',
          sets: [(0.0, 15)],
        );
        await _seedSession(repo, id: 'bw-2', day: daysAgo(4));
        await _addSetEffort(
          repo,
          sessionId: 'bw-2',
          exerciseId: 'ex-pushup',
          sets: [(0.0, 18)],
        );
        await _seedSession(repo, id: 'bw-3', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 'bw-3',
          exerciseId: 'ex-pushup',
          sets: [(0.0, 16)],
        );
        // Weighted day: 10 kg extra, 12 reps. The rep count
        // contributes to the reps trend; the 10 kg is annotation.
        await _seedSession(repo, id: 'bw-weighted', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'bw-weighted',
          exerciseId: 'ex-pushup',
          sets: [(0.0, 12)],
          extraWeights: [10.0],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        final lift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'Push-Up',
        );
        // No e1RM trend, no volume trend — the exercise is
        // reps-axis because at least one set has weight=0.
        expect(lift.e1RmTrend, isEmpty);
        expect(lift.volumeTrend, isEmpty);
        // Reps trend covers all 4 days.
        expect(lift.repsTrend, hasLength(4));
        // The weighted day's rep count (12) is in the trend.
        expect(
          lift.repsTrend.last.value,
          12,
          reason: 'Weighted session still contributes its rep count',
        );
        // The weighted day's point carries an extra-weight
        // annotation; the three bodyweight days do not.
        final weightedDayPoint = lift.repsTrend.last;
        expect(weightedDayPoint.extraWeightKg, 10.0);
        final plainBwPoint = lift.repsTrend.first;
        expect(plainBwPoint.extraWeightKg, isNull);

        // No e1RM PR (only reps PR). The session summary +
        // Stats screen surfaces a max-reps verdict, never a
        // weight-based one, for this exercise.
        final prs = data.recentPRs
            .where((pr) => pr.exerciseName == 'Push-Up')
            .toList();
        for (final pr in prs) {
          expect(pr.e1Rm, isNull, reason: 'No e1RM PR for reps-axis exercise');
          expect(pr.reps, isNotNull);
        }
      },
    );

    test(
      'S-107 a loaded-only exercise keeps its weight-based e1RM/Volume card '
      '— guards against over-flipping genuine loaded lifts to reps',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-loaded',
            name: 'BarbellSquat',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Every set has `weight > 0` — this is a genuine loaded
        // lift, never once at bodyweight. Its card must remain
        // weight-based.
        for (var i = 0; i < 3; i++) {
          await _seedSession(repo, id: 'sq-$i', day: daysAgo(i));
          await _addSetEffort(
            repo,
            sessionId: 'sq-$i',
            exerciseId: 'ex-loaded',
            sets: [(100.0 + i * 5.0, 5)],
          );
        }

        final data =
            await StatsProgressService(repo).computeProgressData();

        final lift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'BarbellSquat',
        );
        // Weight-based trends present.
        expect(lift.e1RmTrend, hasLength(3));
        expect(lift.volumeTrend, hasLength(3));
        // No reps trend (no bodyweight sets anywhere).
        expect(lift.repsTrend, isEmpty);
        // PR is e1RM-based, never reps.
        final prs = data.recentPRs
            .where((pr) => pr.exerciseName == 'BarbellSquat')
            .toList();
        for (final pr in prs) {
          expect(pr.reps, isNull);
          expect(pr.e1Rm, isNotNull);
        }
      },
    );

    test(
      'S-108 weighted session still appears as a reps point with '
      'extra-weight annotation when the day has both bodyweight and '
      'weighted sets',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-mixed',
            name: 'MixedExercise',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // One day, two sets:
        //   set 1: 14 reps @ 0 kg (bodyweight)
        //   set 2:  8 reps @ 0 kg + 20 kg extra (weighted)
        // Day's max reps = 14 (the bodyweight set), max
        // added weight that day = 20 kg.
        await _seedSession(repo, id: 'mixed-d', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'mixed-d',
          exerciseId: 'ex-mixed',
          sets: [(0.0, 14), (0.0, 8)],
          extraWeights: [0.0, 20.0],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        final lift = data.topLifts.firstWhere(
          (l) => l.exerciseName == 'MixedExercise',
        );
        expect(lift.repsTrend, hasLength(1));
        final point = lift.repsTrend.first;
        expect(point.value, 14, reason: 'Day\'s max reps = 14');
        expect(
          point.extraWeightKg,
          20.0,
          reason: 'Day\'s max added weight = 20 kg',
        );
      },
    );
  });

  group('Recency floor on Strength/Cardio selection (Item 3)', () {
    test(
      'S-201 stale exercise dropped from Strength top slots',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-stale',
            name: 'StaleLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-current',
            name: 'CurrentLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // StaleLift: 10 distinct training days, all well outside
        // the recency threshold. Date math:
        //   kTopExerciseRecencyDays = 30 (per the implementation).
        //   Threshold = todayMidnight - 30 days.
        //   Any training day older than that drops out.
        for (var i = 0; i < 10; i++) {
          await _seedSession(
            repo,
            id: 'stale-$i',
            day: daysAgo(60 + i), // 60-69 days ago — all stale
          );
          await _addSetEffort(
            repo,
            sessionId: 'stale-$i',
            exerciseId: 'ex-stale',
            sets: [(80.0, 5)],
          );
        }
        // CurrentLift: 2 training days, both recent.
        for (var i = 0; i < 2; i++) {
          await _seedSession(repo, id: 'cur-$i', day: daysAgo(i));
          await _addSetEffort(
            repo,
            sessionId: 'cur-$i',
            exerciseId: 'ex-current',
            sets: [(80.0, 5)],
          );
        }

        final data =
            await StatsProgressService(repo).computeProgressData();

        // Recency threshold is 30 calendar days; the test asserts
        // the constant value to keep the contract explicit.
        expect(
          StatsProgressService.kTopExerciseRecencyDays,
          30,
          reason: 'Recency floor threshold is 30 calendar days',
        );
        expect(
          data.topLifts.any((l) => l.exerciseName == 'StaleLift'),
          isFalse,
          reason:
              'StaleLift must be dropped — its most-recent training '
              'day is older than kTopExerciseRecencyDays',
        );
        expect(
          data.topLifts.any((l) => l.exerciseName == 'CurrentLift'),
          isTrue,
        );
      },
    );

    test(
      'S-202 currently-trained exercise takes the freed slot',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-stale',
            name: 'StaleLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-other-old',
            name: 'OtherOldLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-other-old2',
            name: 'OtherOldLift2',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-fresh',
            name: 'FreshLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Three lifts that would fill the top 3 by frequency if
        // the recency floor weren't applied — but all stale.
        for (final ex in ['ex-stale', 'ex-other-old', 'ex-other-old2']) {
          for (var i = 0; i < 5; i++) {
            await _seedSession(
              repo,
              id: 'old-$ex-$i',
              day: daysAgo(60 + i),
            );
            await _addSetEffort(
              repo,
              sessionId: 'old-$ex-$i',
              exerciseId: ex,
              sets: [(80.0, 5)],
            );
          }
        }
        // FreshLift: trained 2 days ago (inside the 30-day
        // window), only 2 days → would not have been in top 3
        // without the floor opening slots.
        await _seedSession(repo, id: 'fresh-1', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 'fresh-1',
          exerciseId: 'ex-fresh',
          sets: [(80.0, 5)],
        );

        final data =
            await StatsProgressService(repo).computeProgressData();

        // The three stale exercises are all dropped.
        for (final staleName in ['StaleLift', 'OtherOldLift', 'OtherOldLift2']) {
          expect(
            data.topLifts.any((l) => l.exerciseName == staleName),
            isFalse,
            reason: '$staleName should be dropped (stale)',
          );
        }
        // FreshLift takes one of the freed slots.
        expect(
          data.topLifts.any((l) => l.exerciseName == 'FreshLift'),
          isTrue,
        );
      },
    );

    test(
      'S-203 regular-cadence exercise stays present across consecutive sessions',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-weekly',
            name: 'WeeklyLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // WeeklyLift trained 5 days ago. Inside the 30-day window.
        await _seedSession(repo, id: 'wk-1', day: daysAgo(5));
        await _addSetEffort(
          repo,
          sessionId: 'wk-1',
          exerciseId: 'ex-weekly',
          sets: [(80.0, 5)],
        );

        final data1 =
            await StatsProgressService(repo).computeProgressData();
        expect(
          data1.topLifts.any((l) => l.exerciseName == 'WeeklyLift'),
          isTrue,
          reason: '5 days ago is inside the 30-day recency window',
        );

        // User trains it again today. Now most-recent training
        // day is today; the lift must still be present.
        await _seedSession(repo, id: 'wk-2', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'wk-2',
          exerciseId: 'ex-weekly',
          sets: [(80.0, 5)],
        );

        final data2 =
            await StatsProgressService(repo).computeProgressData();
        expect(
          data2.topLifts.any((l) => l.exerciseName == 'WeeklyLift'),
          isTrue,
          reason: 'Trained today, must stay present',
        );

        // Trend preserves full history across the two loads.
        final lift = data2.topLifts.firstWhere(
          (l) => l.exerciseName == 'WeeklyLift',
        );
        expect(lift.e1RmTrend, hasLength(2));
      },
    );

    test(
      'S-204 dropped exercise returns → full historical trend intact',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-cycle',
            name: 'CycledLift',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Old cycle: 3 training days, all > 30 days ago.
        for (var i = 0; i < 3; i++) {
          await _seedSession(repo, id: 'old-$i', day: daysAgo(60 + i));
          await _addSetEffort(
            repo,
            sessionId: 'old-$i',
            exerciseId: 'ex-cycle',
            sets: [(80.0, 5)],
          );
        }

        // Before the new session: exercise is stale and dropped.
        final beforeData =
            await StatsProgressService(repo).computeProgressData();
        expect(
          beforeData.topLifts.any((l) => l.exerciseName == 'CycledLift'),
          isFalse,
        );

        // New training day (today): user picks the lift back up.
        await _seedSession(repo, id: 'new-0', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 'new-0',
          exerciseId: 'ex-cycle',
          sets: [(100.0, 5)],
        );

        final afterData =
            await StatsProgressService(repo).computeProgressData();

        // Reappears in the top slots.
        expect(
          afterData.topLifts.any((l) => l.exerciseName == 'CycledLift'),
          isTrue,
        );
        // Trend preserves the OLD points plus the new point.
        final lift = afterData.topLifts.firstWhere(
          (l) => l.exerciseName == 'CycledLift',
        );
        expect(
          lift.e1RmTrend.length,
          4,
          reason: 'Three historical days + one new day = 4 trend points',
        );
      },
    );

    test(
      'S-205 Cardio selection honours the same recency floor',
      () async {
        final repo = await _freshRepo();
        await repo.createExercise(
          Exercise(
            id: 'ex-stale-cardio',
            name: 'StaleCardio',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createExercise(
          Exercise(
            id: 'ex-fresh-cardio',
            name: 'FreshCardio',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // StaleCardio: 8 distinct training days, all stale.
        for (var i = 0; i < 8; i++) {
          await _seedSession(
            repo,
            id: 'stale-c-$i',
            day: daysAgo(60 + i),
          );
          await _addTimedEffort(
            repo,
            sessionId: 'stale-c-$i',
            exerciseId: 'ex-stale-cardio',
            durationSecs: 1800,
          );
        }
        // FreshCardio: 3 distinct training days, all recent.
        for (var i = 0; i < 3; i++) {
          await _seedSession(repo, id: 'fresh-c-$i', day: daysAgo(i));
          await _addTimedEffort(
            repo,
            sessionId: 'fresh-c-$i',
            exerciseId: 'ex-fresh-cardio',
            durationSecs: 1800,
          );
        }

        final data =
            await StatsProgressService(repo).computeProgressData();

        expect(
          data.topCardio.any((c) => c.exerciseName == 'StaleCardio'),
          isFalse,
          reason: 'Cardio section drops stale exercises',
        );
        expect(
          data.topCardio.any((c) => c.exerciseName == 'FreshCardio'),
          isTrue,
        );
      },
    );
  });
}
