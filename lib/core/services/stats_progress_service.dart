/// Service that computes progress-focused stats data from the workout history.
///
/// Works against the [WorkoutRepository] interface — runs identically on
/// [MockWorkoutRepository] (web/test) and any native SQLite implementation.
library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/stats_progress.dart';
import '../utils/observation_grouper.dart';

class StatsProgressService {
  final WorkoutRepository _repository;

  StatsProgressService(this._repository);

  /// Maximum number of top lifts to include in [StatsProgressData.topLifts].
  static const int kTopLiftCount = 3;

  /// Maximum number of top cardio activities to include in
  /// [StatsProgressData.topCardio].
  static const int kTopCardioCount = 2;

  /// Maximum number of recent PRs to return in [StatsProgressData.recentPRs].
  static const int kRecentPRCount = 5;

  /// Compute all progress data for the Stats screen.
  ///
  /// Complexity: O(sessions × segments × efforts). Acceptable for any
  /// foreseeable on-device history without caching in v1.
  Future<StatsProgressData> computeProgressData() async {
    final allSessions = await _repository.getAllSessions();
    final completed = allSessions.where((s) => s.endedAtMs != null).toList();

    // exerciseId → { training-day → list of SetTuple }
    final setsByExercise = <String, Map<DateTime, List<_SetTuple>>>{};

    // exerciseId → { training-day → accumulated _CardioDay }
    final cardioByExercise = <String, Map<DateTime, _CardioDay>>{};

    for (final session in completed) {
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
      final sessionDay = DateTime(sessionDt.year, sessionDt.month, sessionDt.day);

      final segments = await _repository.getSessionSegments(session.id);
      for (final segment in segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          switch (effort.effortKind) {
            case 'set':
              await _processSetEffort(effort, sessionDay, setsByExercise);
            case 'timed':
              await _processTimedEffort(effort, sessionDay, cardioByExercise);
            default:
              // drill, round → not tracked in progress views
              break;
          }
        }
      }
    }

    // Resolve exercise names for all referenced exercise IDs.
    final nameCache = <String, String>{};
    for (final id in {...setsByExercise.keys, ...cardioByExercise.keys}) {
      if (!nameCache.containsKey(id)) {
        final exercise = await _repository.getExerciseById(id);
        nameCache[id] = exercise?.name ?? id;
      }
    }

    // Select top-N exercises by distinct training-day count.
    final topLiftIds = _selectTopN(setsByExercise, kTopLiftCount, nameCache);
    final topCardioIds = _selectTopN(cardioByExercise, kTopCardioCount, nameCache);

    // Build LiftProgress + collect PRs.
    final topLifts = <LiftProgress>[];
    final allPRs = <StatsPR>[];

    for (final exerciseId in topLiftIds) {
      final name = nameCache[exerciseId] ?? exerciseId;
      final dayMap = setsByExercise[exerciseId]!;
      final days = dayMap.keys.toList()..sort();

      final e1RmTrend = <TrendPoint>[];
      final volumeTrend = <TrendPoint>[];

      for (final day in days) {
        final sets = dayMap[day]!;
        double maxE1Rm = 0;
        double totalVolume = 0;

        for (final set in sets) {
          final e1rm = _epley(set.weight, set.reps);
          if (e1rm != null) {
            if (e1rm > maxE1Rm) maxE1Rm = e1rm;
            totalVolume += set.weight * set.reps;
          }
        }

        if (maxE1Rm > 0) {
          e1RmTrend.add(TrendPoint(date: day, value: maxE1Rm));
        }
        if (totalVolume > 0) {
          volumeTrend.add(TrendPoint(date: day, value: totalVolume));
        }
      }

      topLifts.add(LiftProgress(
        exerciseName: name,
        e1RmTrend: e1RmTrend,
        volumeTrend: volumeTrend,
      ));

      // PR detection: walk the e1RM trend chronologically.
      double bestSoFar = 0;
      for (final point in e1RmTrend) {
        if (point.value > bestSoFar) {
          bestSoFar = point.value;
          allPRs.add(StatsPR(
            exerciseName: name,
            e1Rm: point.value,
            date: point.date,
          ));
        }
      }
    }

    // Sort PRs newest-first, then deduplicate: one entry per exercise at its
    // current best (highest e1RM). Tiebreaker: most recent date, then alpha.
    final dedupedPRs = <String, StatsPR>{};
    for (final pr in allPRs) {
      final existing = dedupedPRs[pr.exerciseName];
      if (existing == null ||
          pr.e1Rm > existing.e1Rm ||
          (pr.e1Rm == existing.e1Rm && pr.date.isAfter(existing.date))) {
        dedupedPRs[pr.exerciseName] = pr;
      }
    }

    final sortedPRs = dedupedPRs.values.toList()
      ..sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return a.exerciseName.compareTo(b.exerciseName);
      });

    final recentPRs = sortedPRs.take(kRecentPRCount).toList();

    // Build CardioProgress.
    final topCardio = <CardioProgress>[];
    for (final exerciseId in topCardioIds) {
      final name = nameCache[exerciseId] ?? exerciseId;
      final dayMap = cardioByExercise[exerciseId]!;
      final days = dayMap.keys.toList()..sort();

      final trend = <CardioTrendPoint>[];
      for (final day in days) {
        final cd = dayMap[day]!;
        double? pace;
        if (cd.distanceM != null && cd.distanceM! > 0) {
          pace = cd.durationSecs / (cd.distanceM! / 1000.0);
        }
        trend.add(CardioTrendPoint(
          date: day,
          durationSecs: cd.durationSecs,
          distanceM: cd.distanceM,
          paceSecPerKm: pace,
        ));
      }

      topCardio.add(CardioProgress(exerciseName: name, trend: trend));
    }

    return StatsProgressData(
      topLifts: topLifts,
      topCardio: topCardio,
      recentPRs: recentPRs,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _processSetEffort(
    SegmentEffort effort,
    DateTime sessionDay,
    Map<String, Map<DateTime, List<_SetTuple>>> setsByExercise,
  ) async {
    final exerciseId = effort.exerciseId;
    if (exerciseId == null) return;

    final observations = await _repository.getEffortObservations(effort.id);
    final entries = ObservationGrouper.groupByEffortKind('set', observations);

    for (final entry in entries) {
      final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
      final reps = entry['reps'] as int? ?? 0;
      if (weight <= 0 || reps <= 0) continue;

      setsByExercise
          .putIfAbsent(exerciseId, () => {})
          .putIfAbsent(sessionDay, () => [])
          .add(_SetTuple(weight: weight, reps: reps));
    }
  }

  Future<void> _processTimedEffort(
    SegmentEffort effort,
    DateTime sessionDay,
    Map<String, Map<DateTime, _CardioDay>> cardioByExercise,
  ) async {
    final exerciseId = effort.exerciseId;
    if (exerciseId == null) return;

    final timedInstances = await _repository.getTimedInstances(effort.id);
    final totalDuration = timedInstances
        .where((t) => t.state == TimedState.finished)
        .fold<int>(0, (sum, t) => sum + t.actualDurationSecs);

    if (totalDuration <= 0) return;

    final observations = await _repository.getEffortObservations(effort.id);
    final distanceObs = observations
        .where((o) => o.metricId == MetricIds.distance)
        .toList();

    double? newDistanceM;
    if (distanceObs.isNotEmpty) {
      final sum = distanceObs.fold<double>(
        0.0,
        (s, o) => s + (o.valueReal ?? 0.0),
      );
      if (sum > 0) newDistanceM = sum;
    }

    final dayMap = cardioByExercise.putIfAbsent(exerciseId, () => {});
    final existing = dayMap[sessionDay];

    if (existing == null) {
      dayMap[sessionDay] = _CardioDay(
        durationSecs: totalDuration,
        distanceM: newDistanceM,
      );
    } else {
      dayMap[sessionDay] = _CardioDay(
        durationSecs: existing.durationSecs + totalDuration,
        distanceM: (existing.distanceM != null || newDistanceM != null)
            ? (existing.distanceM ?? 0.0) + (newDistanceM ?? 0.0)
            : null,
      );
    }
  }

  /// Returns the top-[n] exercise IDs ordered by distinct training-day count
  /// (descending), with alphabetical name as a tiebreaker.
  List<String> _selectTopN(
    Map<String, Map<DateTime, dynamic>> data,
    int n,
    Map<String, String> nameCache,
  ) {
    final ranked = data.entries.map((e) {
      return (id: e.key, count: e.value.length, name: nameCache[e.key] ?? e.key);
    }).toList()
      ..sort((a, b) {
        final countCmp = b.count.compareTo(a.count);
        if (countCmp != 0) return countCmp;
        return a.name.compareTo(b.name);
      });

    return ranked.take(n).map((e) => e.id).toList();
  }

  /// Epley 1-rep-max estimate: weight × (1 + reps / 30).
  /// Returns null when weight or reps is zero/negative.
  static double? _epley(double weight, int reps) {
    if (weight <= 0 || reps <= 0) return null;
    return weight * (1 + reps / 30.0);
  }
}

// ── Internal accumulator types ────────────────────────────────────────────────

class _SetTuple {
  final double weight;
  final int reps;

  const _SetTuple({required this.weight, required this.reps});
}

class _CardioDay {
  final int durationSecs;
  final double? distanceM;

  const _CardioDay({required this.durationSecs, required this.distanceM});
}
