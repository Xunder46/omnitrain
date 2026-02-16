/// Data structures for template-to-session conversion
/// These models represent a materialized routine ready to be instantiated as a workout session
library;

import '../../data/models/models.dart';

/// Complete manifest for starting a routine as a workout session
/// Contains all data needed to populate a new session without further queries
class RoutineSessionManifest {
  final WorkoutTemplate template;
  final List<SessionExerciseEntry> exercises;

  RoutineSessionManifest({
    required this.template,
    required this.exercises,
  });

  /// Total number of exercises across all blocks
  int get totalExercises => exercises.length;

  /// Check if manifest has any exercises
  bool get isEmpty => exercises.isEmpty;
}

/// A single exercise entry in the session manifest
/// Represents one exercise to be added, with all metadata and targets pre-resolved
class SessionExerciseEntry {
  final Exercise exercise;
  final String effortKind;
  final int setCount;
  final List<TemplateTarget> targets;
  final int? restSeconds;
  final String? restType;

  SessionExerciseEntry({
    required this.exercise,
    required this.effortKind,
    required this.setCount,
    required this.targets,
    this.restSeconds,
    this.restType,
  });

  /// Get targets for a specific set index
  List<TemplateTarget> getTargetsForSet(int setIndex) {
    return targets.where((t) => (t.setIndex ?? 0) == setIndex).toList();
  }
}
