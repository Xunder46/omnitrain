library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/session_summary.dart';

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
        total += _computeVolumeFromObservations(observations);
      }
    }

    return total;
  }

  double _computeVolumeFromObservations(List<EffortObservation> observations) {
    final entries = <int, Map<String, double>>{};

    for (final observation in observations) {
      final entryIndex = _parseEntryIndex(observation.id) ?? 0;
      final value = observation.valueReal ?? observation.valueInt?.toDouble();
      if (value == null) continue;

      final entry = entries.putIfAbsent(entryIndex, () => {});
      entry[observation.metricId] = value;
    }

    double total = 0;
    for (final entry in entries.values) {
      final reps = entry[MetricIds.reps];
      final weight = entry[MetricIds.weight];
      if (reps == null || weight == null) continue;
      total += reps * weight;
    }

    return total;
  }

  int? _parseEntryIndex(String observationId) {
    final parts = observationId.split('-');
    if (parts.length < 3) return null;
    return int.tryParse(parts[parts.length - 2]);
  }
}
