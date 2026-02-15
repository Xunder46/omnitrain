/// Exercise utility functions and extensions
/// Keeps models pure data while providing convenience methods for business logic

import '../../data/models/models.dart';

/// Extension methods for Exercise - encapsulates capability checking logic
extension ExerciseCapabilities on Exercise {
  /// Check if exercise supports a specific capability
  bool supports(String capability) => capabilities.contains(capability);

  /// Check if exercise supports any of the given capabilities
  bool supportsAny(List<String> caps) => caps.any((c) => capabilities.contains(c));

  /// Create a copy with updated fields
  /// Preserves immutability pattern and allows for transient field updates
  Exercise copyWith({
    String? id,
    String? ownerUserId,
    String? disciplineId,
    String? name,
    String? description,
    String? movementPattern,
    bool? isArchived,
    int? createdAtMs,
    int? updatedAtMs,
    List<String>? capabilities,
  }) {
    return Exercise(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      disciplineId: disciplineId ?? this.disciplineId,
      name: name ?? this.name,
      description: description ?? this.description,
      movementPattern: movementPattern ?? this.movementPattern,
      isArchived: isArchived ?? this.isArchived,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}

/// Lightweight set data structure for UI-level tracking
/// Used by WorkoutSessionScreen and RoutineSetupScreen for human-friendly set management
/// Not a persistence model - observations are persisted via EffortObservation entities
class UiSetData {
  final String id;
  final String exerciseId;
  int reps;
  double weight;
  int duration; // seconds
  final int timestamp;

  UiSetData({
    required this.id,
    required this.exerciseId,
    required this.reps,
    required this.weight,
    required this.duration,
    required this.timestamp,
  });
}
