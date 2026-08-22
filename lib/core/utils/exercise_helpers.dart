/// Exercise utility functions and extensions
/// Keeps models pure data while providing convenience methods for business logic
library;

import '../../data/models/models.dart';

const Object _exerciseCopyWithUnset = Object();

/// Extension methods for Exercise - encapsulates capability checking logic
extension ExerciseCapabilities on Exercise {
  /// Identity contract for user-created (custom) exercises.
  ///
  /// PR 7 establishes this as the single canonical marker used by every
  /// surface that needs to highlight user-owned exercises (picker, details
  /// screen, future PR 8 library). The contract is intentionally narrow:
  ///
  /// - `ownerUserId != null` ⇒ user-created / custom
  /// - `ownerUserId == null` ⇒ bundled / catalog
  ///
  /// Today every code path that creates a custom exercise stamps the
  /// hard-coded value `'user-1'` (see
  /// `lib/state/workout/exercise_library.dart` -> `createExercise` and the
  /// corresponding seed-time callers), and every bundled row in
  /// `lib/mock/seed_data.dart` leaves the field null. PR 8 may revisit the
  /// value to a real per-user id, but the *nullability* distinction is the
  /// contract and must not change without a data migration.
  bool get isCustomExercise => ownerUserId != null;

  /// Check if exercise supports a specific capability
  bool supports(String capability) => capabilities.contains(capability);

  /// Check if exercise supports any of the given capabilities
  bool supportsAny(List<String> caps) => caps.any((c) => capabilities.contains(c));

  /// Create a copy with updated fields
  /// Preserves immutability pattern and allows for transient field updates (e.g. relevanceScore)
  Exercise copyWith({
    String? id,
    String? ownerUserId,
    Object? modality = _exerciseCopyWithUnset,
    String? disciplineId,
    String? name,
    String? description,
    String? movementPattern,
    bool? isArchived,
    int? createdAtMs,
    int? updatedAtMs,
    List<String>? capabilities,
    double? relevanceScore,
    int? defaultRoundDurationSecs,
    Object? howToSteps = _exerciseCopyWithUnset,
    Object? imageAssetPath = _exerciseCopyWithUnset,
  }) {
    return Exercise(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      modality: modality == _exerciseCopyWithUnset
          ? this.modality
          : modality as String?,
      disciplineId: disciplineId ?? this.disciplineId,
      name: name ?? this.name,
      description: description ?? this.description,
      movementPattern: movementPattern ?? this.movementPattern,
      isArchived: isArchived ?? this.isArchived,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      capabilities: capabilities ?? this.capabilities,
      relevanceScore: relevanceScore ?? this.relevanceScore,
      defaultRoundDurationSecs:
          defaultRoundDurationSecs ?? this.defaultRoundDurationSecs,
        howToSteps: howToSteps == _exerciseCopyWithUnset
          ? this.howToSteps
          : howToSteps as List<String>?,
        imageAssetPath: imageAssetPath == _exerciseCopyWithUnset
          ? this.imageAssetPath
          : imageAssetPath as String?,
    );
  }
}

