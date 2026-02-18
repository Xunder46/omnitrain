/// Service for converting workout templates (routines) into session manifests
/// Orchestrates template → session data transformation without state dependencies
library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../models/routine_session_manifest.dart';

/// Service for building session manifests from workout templates
/// Pure business logic - no dependencies on state classes or UI
class RoutineSessionService {
  final WorkoutRepository _repository;

  RoutineSessionService(this._repository);

  /// Build a complete session manifest from a template
  /// 
  /// Loads the template, all segments, efforts, targets, and exercises,
  /// then returns a structured manifest ready for WorkoutState to consume.
  /// 
  /// Throws if template not found or has no exercises.
  Future<RoutineSessionManifest> buildSessionFromTemplate(String templateId) async {
    // Load template
    final template = await _repository.getTemplateById(templateId);
    if (template == null) {
      throw Exception('Template not found: $templateId');
    }

    // Load all segments for this template
    final segments = await _repository.getTemplateSegments(templateId);
    if (segments.isEmpty) {
      throw Exception('Template has no segments: $templateId');
    }

    // Build exercise cache
    final Map<String, Exercise> exerciseCache = {};
    final allExercises = await _repository.getExercises();
    for (final exercise in allExercises) {
      exerciseCache[exercise.id] = exercise;
    }

    // Process each segment and build exercise entries
    final List<SessionSegmentEntry> segmentEntries = [];
    final orderedSegments = [...segments]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    for (final segment in orderedSegments) {
      // Load efforts for this segment
      final efforts = await _repository.getTemplateEfforts(segment.id);
      final List<SessionExerciseEntry> exerciseEntries = [];

      for (final effort in efforts) {
        // Skip efforts without exercise reference
        if (effort.exerciseId == null) continue;

        // Get exercise from cache
        final exercise = exerciseCache[effort.exerciseId];
        if (exercise == null) continue; // Skip if exercise not found

        // Load targets for this effort
        final targets = await _repository.getTemplateTargets(effort.id);

        // Calculate set count from targets
        final setCount = _calculateSetCount(targets);

        // Create session exercise entry
        exerciseEntries.add(SessionExerciseEntry(
          exercise: exercise,
          effortKind: effort.effortKind,
          setCount: setCount,
          targets: targets,
          restSeconds: effort.restSeconds,
          restType: effort.restType,
        ));
      }

      if (exerciseEntries.isNotEmpty) {
        segmentEntries.add(SessionSegmentEntry(
          segment: segment,
          exercises: exerciseEntries,
        ));
      }
    }

    if (segmentEntries.isEmpty) {
      throw Exception('Template has no exercises: $templateId');
    }

    return RoutineSessionManifest(
      template: template,
      segments: segmentEntries,
    );
  }

  /// Calculate the number of sets from targets
  /// Assumes set indices are 0-based (0 = first set, 1 = second set, etc.)
  int _calculateSetCount(List<TemplateTarget> targets) {
    if (targets.isEmpty) return 1; // Default to 1 set if no targets

    int maxSetIndex = 0;
    for (final target in targets) {
      final index = target.setIndex ?? 0;
      if (index > maxSetIndex) maxSetIndex = index;
    }

    // Set count = max index + 1 (since 0-indexed)
    return maxSetIndex + 1;
  }
}
