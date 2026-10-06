import '../../core/constants/effort_defaults.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/constants/workout_constants.dart';
import '../../core/models/session_summary.dart';
import '../../core/services/stats_progress_service.dart';
import '../../core/utils/entry_rows.dart';
import '../../core/utils/observation_grouper.dart';
import '../../data/models/models.dart';
import 'timer_manager.dart';

class SessionSummaryBuilder {
  final TimerManager _timerManager;

  /// Map of {effortId: [observations]}
  final Map<String, List<EffortObservation>> _observations;

  /// Map of {segmentId: [efforts]}
  final Map<String, List<SegmentEffort>> _efforts;

  /// List of session segments
  final List<SessionSegment> _segments;

  /// Map of {exerciseId: Exercise} for quick lookups
  final Map<String, Exercise> _exerciseCache;

  SessionSummaryBuilder({
    required TimerManager timerManager,
    required Map<String, List<EffortObservation>> observations,
    required Map<String, List<SegmentEffort>> efforts,
    required List<SessionSegment> segments,
    required Map<String, Exercise> exerciseCache,
  }) : _timerManager = timerManager,
       _observations = observations,
       _efforts = efforts,
       _segments = segments,
       _exerciseCache = exerciseCache;

  SessionSummary buildSessionSummary(TrainingSession session) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final endedAt = session.endedAtMs ?? now;
    final durationMs = endedAt - session.startedAtMs;

    double totalVolume = 0;
    int totalSets = 0;
    int totalRounds = 0;
    int totalRoundDurationMs = 0;
    int totalCardioDurationMs = 0;
    int totalDrillDurationMs = 0;
    int executionOrder = 0;
    final exerciseSummaries = <ExerciseSummary>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseId = effort.exerciseId ?? 'unknown';
        final exerciseName =
            _exerciseCache[exerciseId]?.name ?? 'Unknown Exercise';
        final observations = _observations[effort.id] ?? [];
        final entries = _buildEntriesForEffort(effort.effortKind, observations);

        int setsCompleted = 0;
        double? bestWeight;
        double? bestE1RM;
        int? bestReps;
        int? effortDurationMs;
        int effortRounds = 0;

        if (effort.effortKind == 'set') {
          for (final entry in entries) {
            final reps = entry['reps'] as int?;
            final weight = entry['weight'] as double?;

            if (reps != null && weight != null) {
              totalVolume += reps * weight;
            }

            if (weight != null) {
              if (bestWeight == null || weight > bestWeight) {
                bestWeight = weight;
              }
            }

            // Also track the highest Epley e1RM in this session's
            // sets, computed with the same formula the in-workout
            // toast and the Stats screen use. A rep-driven
            // improvement (more reps at a non-top weight) can be the
            // new PR even when its raw weight is below `bestWeight`.
            // See docs/plans/summary-pr-parity-plan.md
            // (D-1, D-2).
            final e1rm = StatsProgressService.epley1RM(
              weight ?? 0.0,
              reps ?? 0,
            );
            if (e1rm != null && (bestE1RM == null || e1rm > bestE1RM)) {
              bestE1RM = e1rm;
            }

            // Bodyweight-axis PR: max reps in a single set for
            // sets performed without added external weight
            // (`weight == 0`). Mirrors the axis decision in
            // `StatsProgressService._processSetEffort` so the
            // session summary, the in-session toast, and the Stats
            // screen agree on the same verdict for the same set
            // (`docs/plans/stats-summary-fix-pack-plan.md`,
            // Item 2 — rep-based record parity).
            if ((weight ?? 0.0) == 0.0 && reps != null && reps > 0) {
              if (bestReps == null || reps > bestReps) bestReps = reps;
            }
          }

          setsCompleted = entries
              .where(
                (entry) =>
                    ((entry['reps'] as int?) ?? 0) > 0 ||
                    ((entry['weight'] as double?) ?? 0.0) > 0,
              )
              .length;
          totalSets += setsCompleted;
        } else if (effort.effortKind == 'round') {
          final rounds = _timerManager.getRoundsForEffort(effort.id);
          final finishedRounds = rounds
              .where(
                (round) =>
                    round.state == RoundState.finished &&
                    round.startedAtMs > 0 &&
                    round.finishedAtMs != null,
              )
              .toList();
          effortRounds = finishedRounds.length;
          setsCompleted = effortRounds;
          totalRounds += effortRounds;
          effortDurationMs = finishedRounds.fold<int>(
            0,
            (sum, round) => sum + round.elapsedMs,
          );
          totalRoundDurationMs += effortDurationMs;
        } else if (effort.effortKind == 'timed') {
          final timedInstances = _timerManager.getTimedInstancesForEffort(
            effort.id,
          );
          setsCompleted = timedInstances
              .where((inst) => inst.state == TimedState.finished)
              .length;
          totalCardioDurationMs += timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
          effortDurationMs = timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
        } else if (effort.effortKind == 'drill') {
          final timedInstances = _timerManager.getTimedInstancesForEffort(
            effort.id,
          );
          setsCompleted = timedInstances
              .where((inst) => inst.state == TimedState.finished)
              .length;
          totalDrillDurationMs += timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
          effortDurationMs = timedInstances.fold<int>(
            0,
            (sum, inst) => sum + inst.elapsedMs,
          );
        } else {
          setsCompleted = entries.length;
        }

        exerciseSummaries.add(
          ExerciseSummary(
            exerciseId: exerciseId,
            name: exerciseName,
            effortKind: effort.effortKind,
            setsCompleted: setsCompleted,
            bestWeight: bestWeight,
            executionOrder: executionOrder,
            totalDurationMs: effortDurationMs,
            totalRounds: effortRounds,
            bestE1RM: bestE1RM,
            bestReps: bestReps,
            blockId: effort.blockId,
          ),
        );
        executionOrder++;
      }
    }

    final title =
        session.title ??
        (session.modality == null ? 'Free Training' : session.modality!);

    return SessionSummary(
      sessionId: session.id,
      title: title,
      startedAtMs: session.startedAtMs,
      endedAtMs: session.endedAtMs,
      totalDurationMs: session.isRolling ? 0 : durationMs,
      totalVolume: totalVolume,
      totalSets: totalSets,
      exercises: exerciseSummaries,
      totalRounds: totalRounds,
      totalRoundDurationMs: totalRoundDurationMs,
      totalCardioDurationMs: totalCardioDurationMs,
      totalDrillDurationMs: totalDrillDurationMs,
    );
  }

  List<SessionTemplateExercise> buildTemplateDraftExercises() {
    final drafts = <SessionTemplateExercise>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exerciseId = effort.exerciseId ?? 'unknown';
        final exerciseName =
            _exerciseCache[exerciseId]?.name ?? 'Unknown Exercise';

        List<TemplateTargetDraft> targets;
        if (effort.effortKind == 'round') {
          final rounds = _timerManager.getRoundsForEffort(effort.id);
          final plannedDuration = rounds.isNotEmpty
              ? rounds.first.plannedDurationSecs
              : WorkoutConstants.defaultRoundDurationSecs;
          targets = [
            TemplateTargetDraft(
              metricId: MetricIds.rounds,
              setIndex: 0,
              unitId: MetricIds.unitRounds,
              valueInt: rounds.isNotEmpty ? rounds.length : 1,
              valueReal: null,
              valueText: null,
            ),
            TemplateTargetDraft(
              metricId: MetricIds.roundDuration,
              setIndex: 0,
              unitId: MetricIds.unitSeconds,
              valueInt: plannedDuration,
              valueReal: null,
              valueText: null,
            ),
          ];
        } else if (effort.effortKind == 'timed' ||
            effort.effortKind == 'drill') {
          final timedInstances = _timerManager.getTimedInstancesForEffort(
            effort.id,
          );
          final targetDuration = timedInstances.isNotEmpty
              ? timedInstances.first.targetDurationSecs
              : 300;
          targets = [
            TemplateTargetDraft(
              metricId: MetricIds.duration,
              setIndex: 0,
              unitId: MetricIds.unitSeconds,
              valueInt: targetDuration,
              valueReal: null,
              valueText: null,
            ),
          ];

          if (effort.effortKind == 'drill') {
            final extraWeight = _entryExtraWeight(effort.id, timedInstances);
            targets.add(
              TemplateTargetDraft(
                metricId: MetricIds.extraWeight,
                setIndex: 0,
                unitId: MetricIds.unitKg,
                valueReal: extraWeight,
                valueInt: null,
                valueText: null,
              ),
            );
          }
          if (effort.effortKind == 'timed') {
            final rows = _observations[effort.id] ?? const <EffortObservation>[];
            final hasExtraWeightRow = rows.any(
              (o) => o.metricId == MetricIds.extraWeight,
            );
            if (hasExtraWeightRow) {
              targets.add(
                TemplateTargetDraft(
                  metricId: MetricIds.extraWeight,
                  setIndex: 0,
                  unitId: MetricIds.unitKg,
                  valueReal: _entryExtraWeight(effort.id, timedInstances),
                  valueInt: null,
                  valueText: null,
                ),
              );
            }
          }
        } else {
          final observations = _observations[effort.id] ?? [];
          targets = _buildTemplateTargetsFromObservations(
            observations,
            effort.effortKind,
          );
        }

        drafts.add(
          SessionTemplateExercise(
            exerciseId: exerciseId,
            name: exerciseName,
            effortKind: effort.effortKind,
            targets: targets,
          ),
        );
      }
    }

    return drafts;
  }

  List<Map<String, dynamic>> buildExercisesWithEntries() {
    final result = <Map<String, dynamic>>[];

    for (final segment in _segments) {
      final segmentEfforts = _efforts[segment.id] ?? [];

      for (final effort in segmentEfforts) {
        final exercise = _exerciseCache[effort.exerciseId];
        final exerciseName = exercise?.name ?? 'Unknown Exercise';

        final List<Map<String, dynamic>> entries;
        if (effort.effortKind == 'round') {
          final rounds = _timerManager.getRoundsForEffort(effort.id);
          entries = rounds
              .map(
                (r) => <String, dynamic>{
                  'rounds': r.roundIndex + 1,
                  'round-duration': r.plannedDurationSecs,
                  'actualDuration': r.actualDurationSecs,
                  'startedAt': r.startedAtMs,
                  'finishedAt': r.finishedAtMs,
                  'completed': r.completed,
                },
              )
              .toList();
        } else if (effort.effortKind == 'timed' ||
            effort.effortKind == 'drill') {
          final timedList = _timerManager.getTimedInstancesForEffort(effort.id);
          final companionObs = _observations[effort.id] ?? [];
          // Entry k's companions are the k-th row of each metric (D-324), not
          // whichever row the store returned k-th.
          final distances = effort.effortKind == 'timed'
              ? EntryRows.companions(
                  rows: companionObs,
                  metricId: MetricIds.distance,
                  entryCount: timedList.length,
                )
              : const <EffortObservation?>[];
          final extraWeights = EntryRows.companions(
            rows: companionObs,
            metricId: MetricIds.extraWeight,
            entryCount: timedList.length,
          );

          entries = <Map<String, dynamic>>[];
          for (int i = 0; i < timedList.length; i++) {
            final t = timedList[i];
            final elapsedSecs = t.state == TimedState.finished
                ? t.actualDurationSecs
                : (t.elapsedMs / 1000).round();
            final entryMap = <String, dynamic>{
              'duration': t.targetDurationSecs,
              'elapsedSecs': elapsedSecs,
              'timedState': t.state.name,
            };
            if (effort.effortKind == 'timed') {
              entryMap['distance'] = distances[i]?.valueReal ?? 0.0;
              if (extraWeights[i] != null) {
                entryMap['extra-weight'] = extraWeights[i]!.valueReal ?? 0.0;
              }
            } else {
              entryMap['extra-weight'] = extraWeights[i]?.valueReal ?? 0.0;
            }
            entries.add(entryMap);
          }
        } else {
          final effortObservations = _observations[effort.id] ?? [];
          entries = ObservationGrouper.groupByEffortKind(
            effort.effortKind,
            effortObservations,
          );

          final hasLoad = exercise?.capabilities.contains('load') ?? false;
          if (effort.effortKind == 'set' && !hasLoad) {
            // Each set reads the added weight its own number holds (D-324) — not
            // whichever row the store returned its position in. A row with no
            // number is in no group, so a group's own row is its numbered row
            // (D-705).
            final groups = EntryRows.setGroups(effortObservations);
            for (int i = 0; i < entries.length; i++) {
              final own = i < groups.length
                  ? groups[i].rowFor(MetricIds.extraWeight)
                  : null;
              entries[i]['extra-weight'] =
                  own?.valueReal ??
                  (entries[i]['extra-weight'] as double? ?? 0.0);
            }
          }
        }

        result.add({
          'id': effort.id,
          'exerciseId': effort.exerciseId,
          'name': exerciseName,
          'effortKind': effort.effortKind,
          'capabilities': exercise?.capabilities ?? const <String>[],
          'executionOrder': effort.orderIndex,
          'topLevelOrderIndex': effort.topLevelOrderIndex ?? effort.orderIndex,
          'blockOrderIndex': effort.blockOrderIndex,
          'entries': entries,
          'segmentId': segment.id,
          'segmentName': segment.name ?? 'Block ${segment.orderIndex + 1}',
          'segmentType': segment.segmentType,
          'segmentOrder': segment.orderIndex,
          'blockId': effort.blockId,
          'createdAtMs': effort.createdAtMs,
        });
      }
    }

    return result;
  }

  /// The added weight a `timed` or `drill` draft carries: the first entry's own
  /// row (D-324), not whichever row the store returned first. An effort whose
  /// first entry holds none reads 0.0.
  double _entryExtraWeight(String effortId, List<TimedInstance> instances) {
    final paired = EntryRows.companions(
      rows: _observations[effortId] ?? const <EffortObservation>[],
      metricId: MetricIds.extraWeight,
      entryCount: instances.length,
    );
    return paired.isEmpty ? 0.0 : (paired.first?.valueReal ?? 0.0);
  }

  List<Map<String, dynamic>> _buildEntriesForEffort(
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

    return ObservationGrouper.groupByEffortKind(effortKind, sorted);
  }

  List<TemplateTargetDraft> _buildTemplateTargetsFromObservations(
    List<EffortObservation> observations,
    String effortKind,
  ) {
    if (observations.isEmpty) {
      final defaults = EffortDefaults.getDefaultTargets(effortKind);
      return defaults.entries
          .map(
            (entry) => TemplateTargetDraft(
              metricId: entry.key,
              setIndex: 0,
              unitId: null,
              valueReal: entry.value is double ? entry.value as double : null,
              valueInt: entry.value is int ? entry.value as int : null,
              valueText: entry.value is String ? entry.value as String : null,
            ),
          )
          .toList();
    }

    final entries = _buildEntriesForEffort(effortKind, observations);
    final targets = <TemplateTargetDraft>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      for (final metricEntry in entry.entries) {
        final metricId = MetricIds.keyToMetricId[metricEntry.key];
        if (metricId == null) continue;

        final value = metricEntry.value;
        targets.add(
          TemplateTargetDraft(
            metricId: metricId,
            setIndex: i,
            unitId: MetricIds.metricKeyToUnitId[metricEntry.key],
            valueReal: value is double ? value : null,
            valueInt: value is int ? value : null,
            valueText: value is String ? value : null,
          ),
        );
      }
    }

    return targets;
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
