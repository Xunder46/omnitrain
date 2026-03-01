library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/session_summary.dart';
import '../utils/observation_grouper.dart';

class SessionSummaryService {
  final WorkoutRepository _repository;

  SessionSummaryService(this._repository);

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
    List<ExerciseSummary> exercises,
  ) async {
    final results = <PRAchievement>[];

    for (final summary in exercises) {
      if (summary.effortKind != 'set') continue;
      final bestWeight = summary.bestWeight;
      if (bestWeight == null || bestWeight <= 0) continue;

      final previousBest = await _repository.getPersonalRecordCandidates(
        summary.exerciseId,
        metricId: MetricIds.weight,
      );

      if (previousBest == null || bestWeight > previousBest) {
        results.add(
          PRAchievement(
            exerciseName: summary.name,
            metricLabel: 'Weight',
            previousBest: previousBest ?? 0,
            newBest: bestWeight,
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
