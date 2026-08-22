// PR 8 — Exercise Library Service
//
// Owns the reference-aware removal contract, copy-as-custom path, and
// built-in immutability guards for the Exercise Library feature.
//
// Layering:
//   - State layer (ExerciseLibraryState) talks to this service.
//   - UI layer (ExerciseLibraryScreen, ExerciseLibraryDetailScreen) talks
//     to the state layer, never to this service directly.
//   - This service talks only to WorkoutRepository.
//
// Built-in immutability is enforced HERE, not just in the UI:
//   - Every mutation path branches on `Exercise.isCustomExercise` first.
//   - Built-in attempts throw `BuiltInExerciseImmutableError`.
//
// References check covers:
//   - app_segment_effort.exercise_id (live + historical sessions)
//   - app_template_effort.exercise_id (routine templates)
//
// PR 8 does not add a new repository method for `getAllSessions` or
// `getTemplateEfforts` callers — those already exist on the interface.

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../utils/exercise_helpers.dart';

/// Thrown when a caller attempts to mutate a built-in (non-custom)
/// exercise. Built-ins are owned by the catalog and may only be read.
class BuiltInExerciseImmutableError extends Error {
  final String exerciseId;
  BuiltInExerciseImmutableError(this.exerciseId);

  @override
  String toString() =>
      'BuiltInExerciseImmutableError: exercise "$exerciseId" is a '
      'bundled catalog entry and cannot be modified';
}

/// Plan returned by `planRemoval(exerciseId)`. Tells the UI which path
/// the eventual `removeExercise` call will take so the confirmation
/// dialog can show the correct copy.
enum ExerciseRemovalKind {
  /// No references anywhere — the row will be hard-deleted.
  hardDelete,

  /// Referenced by at least one session or routine template — the row
  /// will be retired (isArchived = true) to keep history resolvable.
  retire,
}

/// Result of a `planRemoval` check. Includes a non-binding count of
/// the referencing rows so the UI can surface how widely the exercise
/// is used.
class ExerciseRemovalPlan {
  final ExerciseRemovalKind kind;
  final int referencingSessionEfforts;
  final int referencingTemplateEfforts;

  const ExerciseRemovalPlan({
    required this.kind,
    required this.referencingSessionEfforts,
    required this.referencingTemplateEfforts,
  });

  int get totalReferences =>
      referencingSessionEfforts + referencingTemplateEfforts;
}

class ExerciseLibraryService {
  final WorkoutRepository _repository;

  ExerciseLibraryService(this._repository);

  WorkoutRepository get repository => _repository;

  // ── Listing ───────────────────────────────────────────────────────────

  /// List every exercise, including archived rows. The picker /
  /// library screens should call `searchExercises` (which already
  /// filters out archived) for user-facing flows; this method is for
  /// management contexts that need the full picture.
  Future<List<Exercise>> listAllIncludingArchived() async {
    return _repository.getExercises();
  }

  /// Reference-aware search used by the library screen.
  ///
  /// `customOnly` filters to user-created exercises only. Archived
  /// rows are excluded in both modes — the management screen has its
  /// own way to surface them (e.g., an "Archived" section) if needed.
  ///
  /// Returns the same shape as `getExercisesRankedForModality(null)`
  /// for the no-modality case (alphabetical) so the library rows are
  /// stable and predictable.
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    bool customOnly = false,
  }) async {
    final all = await _repository.searchExercises(
      searchText: searchText,
      disciplineId: disciplineId,
    );
    return _filterAndRank(all, searchText: searchText, customOnly: customOnly);
  }

  /// Centralised selection eligibility. The picker / routine editor
  /// both call this before showing an exercise as addable.
  ///
  /// Bundled exercises are always eligible. Custom exercises are
  /// eligible unless they've been archived (retired via a referenced
  /// removal).
  bool isSelectableForWorkout(Exercise exercise) {
    if (exercise.isArchived) return false;
    return true;
  }

  List<Exercise> _filterAndRank(
    List<Exercise> rows, {
    String? searchText,
    required bool customOnly,
  }) {
    var filtered = rows.where((e) => !e.isArchived);
    if (customOnly) {
      filtered = filtered.where((e) => e.isCustomExercise);
    }
    final list = filtered.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ── Reference check ──────────────────────────────────────────────────

  /// True iff `exerciseId` is referenced by at least one
  /// `SegmentEffort.exerciseId` or one `TemplateEffort.exerciseId`.
  ///
  /// This is the single source of truth used by both the service's
  /// removal planner and any UI that needs to surface reference
  /// counts (e.g., a destructive-action confirmation dialog).
  Future<bool> isExerciseReferenced(String exerciseId) async {
    final plan = await planRemoval(exerciseId);
    return plan.totalReferences > 0;
  }

  /// Detailed reference check — same scan as `isExerciseReferenced`
  /// but returns the breakdown so the UI can render "Used in N sets
  /// and M routines".
  Future<ExerciseRemovalPlan> planRemoval(String exerciseId) async {
    var sessionRefs = 0;
    var templateRefs = 0;

    // Two bulk reads instead of one scan per session and one per segment.
    //
    // The per-parent getters each scan and deserialize their whole box, so
    // the old nested walk cost sessions×segments + segments×efforts — it
    // measured 130 ms at 50 sessions, 509 ms at 100, and 2.1 s at 200 on a
    // desktop CPU, i.e. quadratic in history. This runs when the user
    // deletes a custom exercise, so a user with a year of logs got a hung
    // dialog (and a phone is several times slower again).
    //
    // The traversal shape is preserved deliberately: counting every effort
    // whose exerciseId matches would also count efforts orphaned from any
    // session, which is not what "used in N sets" means.
    final sessions = await _repository.getAllSessions();
    final segmentsBySession = await _repository.getSegmentsBySession();
    final effortsBySegment = await _repository.getEffortsBySegment();
    for (final session in sessions) {
      final segments = segmentsBySession[session.id] ?? const [];
      for (final segment in segments) {
        final efforts = effortsBySegment[segment.id] ?? const [];
        for (final effort in efforts) {
          if (effort.exerciseId == exerciseId) sessionRefs += 1;
        }
      }
    }

    final templates = await _repository.getTemplates();
    for (final template in templates) {
      final segments = await _repository.getTemplateSegments(template.id);
      for (final segment in segments) {
        final efforts = await _repository.getTemplateEfforts(segment.id);
        for (final effort in efforts) {
          if (effort.exerciseId == exerciseId) templateRefs += 1;
        }
      }
    }

    final kind = (sessionRefs + templateRefs) == 0
        ? ExerciseRemovalKind.hardDelete
        : ExerciseRemovalKind.retire;

    return ExerciseRemovalPlan(
      kind: kind,
      referencingSessionEfforts: sessionRefs,
      referencingTemplateEfforts: templateRefs,
    );
  }

  // ── Mutation ──────────────────────────────────────────────────────────

  /// Reference-aware removal. Branches on the result of `planRemoval`:
  ///
  /// - zero references → `deleteExercise` (no residue anywhere).
  /// - any reference → flips `isArchived = true`. History keeps
  ///   resolving by id; selectors exclude it.
  ///
  /// Built-in exercises throw `BuiltInExerciseImmutableError` BEFORE
  /// any reference scan runs — we never even consider mutating a
  /// bundled row.
  Future<ExerciseRemovalKind> removeExercise(Exercise exercise) async {
    if (!exercise.isCustomExercise) {
      throw BuiltInExerciseImmutableError(exercise.id);
    }

    final plan = await planRemoval(exercise.id);
    switch (plan.kind) {
      case ExerciseRemovalKind.hardDelete:
        await _repository.deleteExercise(exercise.id);
        return plan.kind;
      case ExerciseRemovalKind.retire:
        final retired = exercise.copyWith(
          isArchived: true,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _repository.updateExercise(retired);
        return plan.kind;
    }
  }

  /// Copy a bundled exercise into a brand-new user-created exercise.
  /// The original is never mutated.
  Future<Exercise> copyAsCustom(Exercise source) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = Exercise(
      id: 'exercise-${now}-${source.id.hashCode.abs()}',
      ownerUserId: 'user-1',
      modality: source.modality,
      disciplineId: source.disciplineId,
      name: '$source.name (copy)',
      description: source.description,
      movementPattern: source.movementPattern,
      isArchived: false,
      createdAtMs: now,
      updatedAtMs: now,
      capabilities: source.capabilities,
      relevanceScore: source.relevanceScore,
      defaultRoundDurationSecs: source.defaultRoundDurationSecs,
      howToSteps: source.howToSteps,
      imageAssetPath: source.imageAssetPath,
    );
    await _repository.createExercise(copy);
    // Carry capability + muscle-group links forward so the copy is
    // immediately selectable in the same contexts as the source.
    await _repository.setExerciseCapabilities(copy.id, source.capabilities);
    final sourceMuscles = await _repository.getExerciseMuscleGroups(source.id);
    await _repository.setExerciseMuscleGroups(
      copy.id,
      sourceMuscles.map((m) => m.id).toList(),
    );
    return copy.copyWith(capabilities: source.capabilities);
  }

  /// Rename a custom exercise. Built-in attempts throw.
  Future<Exercise> renameCustom({
    required Exercise exercise,
    required String newName,
  }) async {
    if (!exercise.isCustomExercise) {
      throw BuiltInExerciseImmutableError(exercise.id);
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(newName, 'newName', 'must not be empty');
    }
    final updated = exercise.copyWith(
      name: trimmed,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.updateExercise(updated);
    return updated;
  }

  /// Edit a custom exercise's full body (used by the library when the
  /// user taps Edit on a custom row). Built-in attempts throw.
  Future<Exercise> editCustom({
    required Exercise exercise,
    required String name,
    String? description,
    String? disciplineId,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    if (!exercise.isCustomExercise) {
      throw BuiltInExerciseImmutableError(exercise.id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = exercise.copyWith(
      name: name.trim(),
      description: description?.trim().isEmpty == true ? null : description,
      disciplineId: disciplineId,
      updatedAtMs: now,
    );
    await _repository.updateExercise(updated);
    await _repository.setExerciseCapabilities(updated.id, capabilities);
    await _repository.setExerciseMuscleGroups(updated.id, muscleGroupIds);
    return updated.copyWith(capabilities: capabilities);
  }
}
