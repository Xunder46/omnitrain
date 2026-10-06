library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/session_summary.dart';
import '../utils/observation_grouper.dart';
import 'stats_progress_service.dart';

class SessionSummaryService {
  final WorkoutRepository _repository;

  SessionSummaryService(this._repository);

  Future<int> computeSessionRestTimeMs(String sessionId) async {
    // Step 1 — fetch session window for clipping
    final session = await _repository.getSession(sessionId);
    if (session == null) return 0;
    final windowStart = session.startedAtMs;
    final windowEnd =
        session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch;

    // Step 2 — collect closed intervals from all efforts, clipped to session window
    final intervals = <(int, int)>[];
    final segments = await _repository.getSessionSegments(sessionId);
    for (final segment in segments) {
      final efforts = await _repository.getSegmentEfforts(segment.id);
      for (final effort in efforts) {
        final rests = await _repository.getEntryRests(effort.id);
        for (final rest in rests) {
          final endMs = rest.restEndMs;
          if (endMs == null) continue;
          final start = rest.restStartMs.clamp(windowStart, windowEnd);
          final end = endMs.clamp(windowStart, windowEnd);
          if (end > start) intervals.add((start, end));
        }
      }
    }

    if (intervals.isEmpty) return 0;

    // Step 3 — merge overlapping intervals, then sum
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var mergedStart = intervals.first.$1;
    var mergedEnd = intervals.first.$2;
    var totalMs = 0;
    for (final iv in intervals.skip(1)) {
      if (iv.$1 <= mergedEnd) {
        if (iv.$2 > mergedEnd) mergedEnd = iv.$2;
      } else {
        totalMs += mergedEnd - mergedStart;
        mergedStart = iv.$1;
        mergedEnd = iv.$2;
      }
    }
    totalMs += mergedEnd - mergedStart;
    return totalMs;
  }

  Future<Map<String, SessionGroupMetrics>> buildGroupMetrics(
    SessionSummary summary,
  ) async {
    final cardioRounds = summary.exercises
        .where((e) => e.effortKind == 'timed')
        .fold<int>(0, (sum, e) => sum + e.setsCompleted);
    final isometricHolds = summary.exercises
        .where((e) => e.effortKind == 'drill')
        .fold<int>(0, (sum, e) => sum + e.setsCompleted);

    final groups = <String, SessionGroupMetrics>{};

    if (summary.totalSets > 0 || summary.totalVolume > 0) {
      groups['strength'] = SessionGroupMetrics(
        groupKey: 'strength',
        primaryLabel: 'Sets',
        primaryCount: summary.totalSets,
        totalVolumeKg: summary.totalVolume,
      );
    }

    if (cardioRounds > 0 || summary.totalCardioDurationMs > 0) {
      groups['cardio'] = SessionGroupMetrics(
        groupKey: 'cardio',
        primaryLabel: 'Rounds',
        primaryCount: cardioRounds,
        effortDurationMs: summary.totalCardioDurationMs,
      );
    }

    if (summary.totalRounds > 0 || summary.totalRoundDurationMs > 0) {
      groups['rounds'] = SessionGroupMetrics(
        groupKey: 'rounds',
        primaryLabel: 'Rounds',
        primaryCount: summary.totalRounds,
        effortDurationMs: summary.totalRoundDurationMs,
      );
    }

    if (isometricHolds > 0 || summary.totalDrillDurationMs > 0) {
      groups['isometric'] = SessionGroupMetrics(
        groupKey: 'isometric',
        primaryLabel: 'Holds',
        primaryCount: isometricHolds,
        effortDurationMs: summary.totalDrillDurationMs,
      );
    }

    return groups;
  }

  Map<String, List<PRAchievement>> groupPrsByEffortKind(
    List<PRAchievement> prs,
    List<ExerciseSummary> exercises,
  ) {
    final groupByExercise = <String, String>{};
    for (final exercise in exercises) {
      groupByExercise[exercise.name] = _groupForEffort(exercise.effortKind);
    }

    final grouped = <String, List<PRAchievement>>{};
    for (final pr in prs) {
      final groupKey = groupByExercise[pr.exerciseName] ?? 'strength';
      grouped.putIfAbsent(groupKey, () => []).add(pr);
    }
    return grouped;
  }

  Future<String> getPreferredWeightUnit() async {
    final pref = (await _repository.getPreferenceString(
      'preferred_weight_unit',
      defaultValue: 'kg',
    ))?.toLowerCase().trim();
    if (pref == 'lb' || pref == 'lbs') {
      return 'lbs';
    }
    return 'kg';
  }

  static String _groupForEffort(String effortKind) {
    switch (effortKind) {
      case 'set':
        return 'strength';
      case 'timed':
        return 'cardio';
      case 'round':
        return 'rounds';
      case 'drill':
        return 'isometric';
      default:
        return 'strength';
    }
  }

  Future<VolumeComparison> compareToPreviousSession(
    TrainingSession currentSession,
    double currentVolume,
  ) async {
    final sessions = await _repository.getAllSessions();
    final previous =
        sessions
            .where(
              (s) =>
                  s.endedAtMs != null &&
                  s.id != currentSession.id &&
                  s.startedAtMs < currentSession.startedAtMs,
            )
            .toList()
          ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

    if (previous.isEmpty) {
      return VolumeComparison(
        currentVolume: currentVolume,
        previousVolume: null,
        delta: null,
      );
    }

    final previousVolume = await _computeSessionVolume(previous.first.id);
    return VolumeComparison(
      currentVolume: currentVolume,
      previousVolume: previousVolume,
      delta: currentVolume - previousVolume,
    );
  }

  Future<List<PRAchievement>> computePRs(
    List<ExerciseSummary> exercises, {
    String? currentSessionId,
  }) async {
    final results = <PRAchievement>[];

    // A session can produce at most one new record per exercise:
    // its single best effort. When the same exercise appears in
    // more than one block (most commonly when a user clones a
    // block several times), the input list carries one
    // `ExerciseSummary` per block — group by `exerciseId` and
    // take the maximum e1RM across the group so the summary
    // emits at most one PR entry per exercise at its true session
    // maximum. The verdict (is this a PR) is unchanged; only the
    // entry count collapses. Set count, total volume, and the
    // per-exercise breakdown are byte-equal before and after this
    // step.
    //
    // Axis rule (mirrors `StatsProgressService.topLifts`: the reps
    // axis comes from the bodyweight sets `_processSetEffort`
    // accumulates):
    // an exercise that has ANY bodyweight set in this session
    // (`bestReps > 0`) is reps-axis — its PR is a max-reps
    // verdict and the e1RM path is skipped. A loaded-only
    // exercise keeps its e1RM verdict. This stops Push-Up from
    // emitting a "New best e1RM" line just because one session
    // was logged with added weight — see the Push-Up mixed-axis
    // bug fix in `docs/plans/stats-summary-fix-pack-plan.md`.
    //
    // Plan: docs/plans/stats-summary-fix-pack-plan.md (PR 1 + PR 2).
    final byExerciseId = <String, ExerciseSummary>{};
    for (final summary in exercises) {
      if (summary.effortKind != 'set') continue;
      final bestE1RM = summary.bestE1RM;
      if (bestE1RM == null || bestE1RM <= 0) continue;
      // Reps-axis exercises (any bodyweight set this session)
      // never get an e1RM PR — see the axis rule above.
      if ((summary.bestReps ?? 0) > 0) continue;
      final existing = byExerciseId[summary.exerciseId];
      if (existing == null || (existing.bestE1RM ?? 0) < bestE1RM) {
        byExerciseId[summary.exerciseId] = summary;
      }
    }

    for (final summary in byExerciseId.values) {
      final bestE1RM = summary.bestE1RM!;
      final previousBest = await StatsProgressService(_repository)
          .getAllTimeBestE1RM(
            summary.exerciseId,
            excludeSessionId: currentSessionId,
          );

      if (bestE1RM > previousBest) {
        results.add(
          PRAchievement(
            exerciseName: summary.name,
            metricLabel: 'e1RM',
            previousBest: previousBest,
            newBest: bestE1RM,
          ),
        );
      }
    }

    // Reps-axis pass: exercises with at least one bodyweight set
    // (`bestReps > 0`) produce a max-reps PR, not an e1RM PR.
    // Mirrors the e1RM-axis logic above — group by exerciseId,
    // take the session maximum, compare against the standing
    // best via `StatsProgressService.getAllTimeBestReps`. The
    // same one-entry-per-exercise collapse applies.
    //
    // Plan: docs/plans/stats-summary-fix-pack-plan.md,
    // Item 2 (rep-based record parity).
    final repsByExerciseId = <String, ExerciseSummary>{};
    for (final summary in exercises) {
      if (summary.effortKind != 'set') continue;
      final bestReps = summary.bestReps;
      if (bestReps == null || bestReps <= 0) continue;
      final existing = repsByExerciseId[summary.exerciseId];
      if (existing == null || (existing.bestReps ?? 0) < bestReps) {
        repsByExerciseId[summary.exerciseId] = summary;
      }
    }

    for (final summary in repsByExerciseId.values) {
      final bestReps = summary.bestReps!;
      final previousBest = await StatsProgressService(_repository)
          .getAllTimeBestReps(
            summary.exerciseId,
            excludeSessionId: currentSessionId,
          );

      if (bestReps > previousBest) {
        results.add(
          PRAchievement(
            exerciseName: summary.name,
            metricLabel: 'reps',
            previousBest: previousBest.toDouble(),
            newBest: bestReps.toDouble(),
          ),
        );
      }
    }

    return results;
  }

  Future<String> saveRoutineFromDraft(
    SessionTemplateDraft draft, {
    String? focusModality,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final templateId = 'template-$now';

    final template = WorkoutTemplate(
      id: templateId,
      name: draft.name,
      focusModality: focusModality ?? draft.focusModality,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _repository.createTemplate(template);

    final segmentId = 'tseg-$now';
    final segment = TemplateSegment(
      id: segmentId,
      templateId: templateId,
      orderIndex: 0,
      segmentType: 'main',
      name: 'Main Block',
      createdAtMs: now,
      updatedAtMs: now,
    );
    await _repository.createTemplateSegment(segment);

    for (var i = 0; i < draft.exercises.length; i++) {
      final exercise = draft.exercises[i];
      final effortId = 'teff-$now-$i';
      final effort = TemplateEffort(
        id: effortId,
        templateSegmentId: segmentId,
        orderIndex: i,
        effortKind: exercise.effortKind,
        modality: focusModality ?? draft.focusModality,
        exerciseId: exercise.exerciseId,
        createdAtMs: now,
      );

      await _repository.createTemplateEffort(effort);

      for (final target in exercise.targets) {
        final targetId = 'ttgt-$now-$i-${target.setIndex}-${target.metricId}';
        final targetModel = TemplateTarget(
          id: targetId,
          templateEffortId: effortId,
          metricId: target.metricId,
          setIndex: target.setIndex,
          unitId: target.unitId,
          targetMin: target.valueReal,
          targetMax: null,
          targetInt: target.valueInt,
          targetText: target.valueText,
          createdAtMs: now,
          updatedAtMs: now,
        );

        await _repository.createTemplateTarget(targetModel);
      }
    }

    return templateId;
  }

  /// Computes per-group stats for [sessionId] by iterating its segments/efforts
  /// via the repository interface (works on both Hive and SQLite).
  Future<Map<String, double>> _computeGroupStats(String sessionId) async {
    final stats = <String, double>{};
    final segments = await _repository.getSessionSegments(sessionId);

    for (final segment in segments) {
      final efforts = await _repository.getSegmentEfforts(segment.id);
      for (final effort in efforts) {
        switch (effort.effortKind) {
          case 'set':
            final observations = await _repository.getEffortObservations(
              effort.id,
            );
            final vol = _computeVolumeFromObservations(
              effort.effortKind,
              observations,
            );
            stats['strength'] = (stats['strength'] ?? 0) + vol;
            break;
          case 'timed':
            final instances = await _repository.getTimedInstances(effort.id);
            final ms = instances.fold<int>(
              0,
              (sum, inst) => sum + inst.elapsedMs,
            );
            stats['cardio'] = (stats['cardio'] ?? 0) + ms;
            break;
          case 'round':
            final instances = await _repository.getRoundInstances(effort.id);
            final finishedRounds = instances
                .where(
                  (i) =>
                      i.state == RoundState.finished &&
                      i.startedAtMs > 0 &&
                      i.finishedAtMs != null,
                )
                .toList();
            final durationMs = finishedRounds.fold<int>(
              0,
              (sum, round) => sum + round.elapsedMs,
            );
            stats['rounds'] = (stats['rounds'] ?? 0) + durationMs;
            break;
          case 'drill':
            final instances = await _repository.getTimedInstances(effort.id);
            final ms = instances.fold<int>(
              0,
              (sum, inst) => sum + inst.elapsedMs,
            );
            stats['isometric'] = (stats['isometric'] ?? 0) + ms;
            break;
        }
      }
    }

    return stats;
  }

  /// Returns a [GroupDelta] for every modality group that has data in [currentSummary].
  /// Uses [currentSession] only to identify and exclude it from the previous-session search.
  Future<Map<String, GroupDelta>> compareGroupsToPreviousSession(
    TrainingSession currentSession,
    SessionSummary currentSummary,
  ) async {
    const units = <String, String>{
      'strength': 'kg',
      'cardio': 'ms',
      'rounds': 'ms',
      'isometric': 'ms',
    };

    // Build current values from summary fields — no extra DB reads needed.
    final currentValues = <String, double>{};
    if (currentSummary.totalVolume > 0) {
      currentValues['strength'] = currentSummary.totalVolume;
    }
    if (currentSummary.totalCardioDurationMs > 0) {
      currentValues['cardio'] = currentSummary.totalCardioDurationMs.toDouble();
    }
    if (currentSummary.totalRounds > 0 ||
        currentSummary.totalRoundDurationMs > 0) {
      currentValues['rounds'] = currentSummary.totalRoundDurationMs.toDouble();
    }
    if (currentSummary.totalDrillDurationMs > 0) {
      currentValues['isometric'] = currentSummary.totalDrillDurationMs
          .toDouble();
    }

    // Find the most recent completed session before this one.
    final sessions = await _repository.getAllSessions();
    final previous =
        sessions
            .where(
              (s) =>
                  s.endedAtMs != null &&
                  s.id != currentSession.id &&
                  s.startedAtMs < currentSession.startedAtMs,
            )
            .toList()
          ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

    final result = <String, GroupDelta>{};

    if (previous.isEmpty) {
      for (final entry in currentValues.entries) {
        result[entry.key] = GroupDelta(
          delta: null,
          unit: units[entry.key]!,
          hasPrevious: false,
        );
      }
      return result;
    }

    final prevStats = await _computeGroupStats(previous.first.id);

    for (final entry in currentValues.entries) {
      final key = entry.key;
      final currentVal = entry.value;
      final prevVal = prevStats[key] ?? 0.0;
      result[key] = GroupDelta(
        delta: currentVal - prevVal,
        unit: units[key]!,
        hasPrevious: true,
      );
    }

    return result;
  }

  Future<double> _computeSessionVolume(String sessionId) async {
    double total = 0;
    final segments = await _repository.getSessionSegments(sessionId);

    for (final segment in segments) {
      final efforts = await _repository.getSegmentEfforts(segment.id);
      for (final effort in efforts) {
        if (effort.effortKind != 'set') continue;
        final observations = await _repository.getEffortObservations(effort.id);
        total += _computeVolumeFromObservations(
          effort.effortKind,
          observations,
        );
      }
    }

    return total;
  }

  double _computeVolumeFromObservations(
    String effortKind,
    List<EffortObservation> observations,
  ) {
    final sorted = List<EffortObservation>.from(observations)
      ..sort((a, b) {
        final createdCompare = a.createdAtMs.compareTo(b.createdAtMs);
        if (createdCompare != 0) return createdCompare;
        return _metricOrderForEffort(
          effortKind,
          a.metricId,
        ).compareTo(_metricOrderForEffort(effortKind, b.metricId));
      });

    final entries = ObservationGrouper.groupByEffortKind(effortKind, sorted);

    double total = 0;
    for (final entry in entries) {
      final reps = entry['reps'] as int?;
      final weight = entry['weight'] as double?;
      if (reps == null || weight == null) continue;
      total += reps * weight;
    }

    return total;
  }

  int _metricOrderForEffort(String effortKind, String metricId) {
    switch (effortKind) {
      case 'set':
        return metricId == MetricIds.reps ? 0 : 1;
      case 'timed':
        return metricId == MetricIds.duration ? 0 : 1;
      case 'round':
        return metricId == MetricIds.rounds ? 0 : 1;
      case 'drill':
        return metricId == MetricIds.duration ? 0 : 1;
      default:
        return 0;
    }
  }
}
