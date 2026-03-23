class SessionSummary {
  final String sessionId;
  final String title;
  final int startedAtMs;
  final int? endedAtMs;
  final int totalDurationMs;
  final double totalVolume;
  final int totalSets;
  final List<ExerciseSummary> exercises;

  /// Total rounds across all round-based exercises.
  final int totalRounds;

  /// Total duration in ms for all cardio/timed exercises.
  final int totalCardioDurationMs;

  /// Total duration in ms for all drill/isometric exercises.
  final int totalDrillDurationMs;

  SessionSummary({
    required this.sessionId,
    required this.title,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.totalDurationMs,
    required this.totalVolume,
    required this.totalSets,
    required this.exercises,
    this.totalRounds = 0,
    this.totalCardioDurationMs = 0,
    this.totalDrillDurationMs = 0,
  });
}

class ExerciseSummary {
  final String exerciseId;
  final String name;
  final String effortKind;
  final int setsCompleted;
  final double? bestWeight;

  /// Positional index preserving original execution order (0-based).
  final int executionOrder;

  /// Total duration in milliseconds for timed/drill efforts; null for set/round.
  final int? totalDurationMs;

  /// Number of rounds completed for round-based efforts; 0 otherwise.
  final int totalRounds;

  ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.effortKind,
    required this.setsCompleted,
    required this.bestWeight,
    required this.executionOrder,
    this.totalDurationMs,
    this.totalRounds = 0,
  });
}

class PRAchievement {
  final String exerciseName;
  final String metricLabel;
  final double previousBest;
  final double newBest;

  PRAchievement({
    required this.exerciseName,
    required this.metricLabel,
    required this.previousBest,
    required this.newBest,
  });
}

class VolumeComparison {
  final double currentVolume;
  final double? previousVolume;
  final double? delta;

  VolumeComparison({
    required this.currentVolume,
    required this.previousVolume,
    required this.delta,
  });

  bool get hasPrevious => previousVolume != null && delta != null;
}

/// Per-modality-group progress delta vs the most recent previous session.
class GroupDelta {
  /// Raw numeric delta (current − previous). Null when no comparison is available.
  final double? delta;

  /// Unit of the delta: 'kg' (strength volume), 'ms' (duration), 'rounds' (round count).
  final String unit;

  /// Whether a previous session existed to compare against.
  final bool hasPrevious;

  const GroupDelta({
    this.delta,
    required this.unit,
    required this.hasPrevious,
  });
}

class SessionTemplateDraft {
  final String name;
  final String? focusModality;
  final List<SessionTemplateExercise> exercises;

  SessionTemplateDraft({
    required this.name,
    required this.focusModality,
    required this.exercises,
  });
}

class SessionTemplateExercise {
  final String exerciseId;
  final String name;
  final String effortKind;
  final List<TemplateTargetDraft> targets;

  SessionTemplateExercise({
    required this.exerciseId,
    required this.name,
    required this.effortKind,
    required this.targets,
  });

  SessionTemplateExercise copyWith({
    String? exerciseId,
    String? name,
    String? effortKind,
    List<TemplateTargetDraft>? targets,
  }) {
    return SessionTemplateExercise(
      exerciseId: exerciseId ?? this.exerciseId,
      name: name ?? this.name,
      effortKind: effortKind ?? this.effortKind,
      targets: targets ?? this.targets,
    );
  }
}

class TemplateTargetDraft {
  final String metricId;
  final int setIndex;
  final String? unitId;
  final double? valueReal;
  final int? valueInt;
  final String? valueText;

  TemplateTargetDraft({
    required this.metricId,
    required this.setIndex,
    required this.unitId,
    required this.valueReal,
    required this.valueInt,
    required this.valueText,
  });
}
