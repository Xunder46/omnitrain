import '../../core/constants/catalog_version.dart';
import '../../core/utils/exercise_helpers.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

// TEMPORARY DEBUG FLAG — remove before shipping.
// When true, the exercise info/notes coach marks are treated as never-seen
// every time the workout session screen loads, so both hints replay on each
// visit instead of only the very first time.
const bool kDebugAlwaysShowExerciseHints = true;

class ExerciseLibrary {
  final WorkoutRepository _repository;
  final void Function() _notify;
  final void Function(String) _setErrorCallback;
  final void Function() _clearErrorCallback;
  final String? Function() _getCurrentSessionModality;

  final Map<String, ExerciseNote?> _exerciseNotes = {};
  final Map<String, Future<void>> _exerciseNoteLoadInFlight = {};
  final Map<String, Future<void>> _exerciseNoteSaveInFlight = {};

  List<Exercise> _allExercises = [];
  List<MuscleGroup> _muscleGroups = [];
  List<Discipline> _disciplines = [];

  bool _exerciseNotesHintSeen = false;
  bool _exerciseInfoHintSeen = false;

  ExerciseLibrary(
    this._repository, {
    required void Function() notify,
    required void Function(String) setError,
    required void Function() clearError,
    required String? Function() getCurrentSessionModality,
  }) : _notify = notify,
       _setErrorCallback = setError,
       _clearErrorCallback = clearError,
       _getCurrentSessionModality = getCurrentSessionModality;

  bool get shouldShowExerciseNotesHint => !_exerciseNotesHintSeen;
  bool get shouldShowExerciseInfoHint => !_exerciseInfoHintSeen;
  List<Exercise> get allExercises => List.unmodifiable(_allExercises);
  List<MuscleGroup> get muscleGroups => List.unmodifiable(_muscleGroups);
  List<Discipline> get disciplines => List.unmodifiable(_disciplines);

  Future<void> loadExerciseNote(String exerciseId) async {
    if (_exerciseNotes.containsKey(exerciseId)) {
      return;
    }

    final inFlight = _exerciseNoteLoadInFlight[exerciseId];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final loadFuture = (() async {
      try {
        final note = await _repository.getExerciseNote(exerciseId);
        _exerciseNotes[exerciseId] = note;
        _notify();
      } catch (e) {
        _setError('Failed to load exercise note: $e');
      } finally {
        _exerciseNoteLoadInFlight.remove(exerciseId);
      }
    })();

    _exerciseNoteLoadInFlight[exerciseId] = loadFuture;
    await loadFuture;
  }

  Future<void> saveExerciseNote(
    String exerciseId,
    String text, {
    String? sessionId,
  }) async {
    final trimmed = text.trim();

    _exerciseNoteSaveInFlight[exerciseId] =
        (_exerciseNoteSaveInFlight[exerciseId] ?? Future.value()).then((
          _,
        ) async {
          try {
            if (trimmed.isEmpty) {
              await _repository.deleteExerciseNote(exerciseId);
              _exerciseNotes[exerciseId] = null;
            } else {
              final now = DateTime.now().millisecondsSinceEpoch;
              final existing = _exerciseNotes[exerciseId];
              final updated = existing != null
                  ? existing.copyWith(
                      note: trimmed,
                      lastSessionId: sessionId ?? existing.lastSessionId,
                      updatedAtMs: now,
                    )
                  : ExerciseNote(
                      id: 'note-$exerciseId',
                      exerciseId: exerciseId,
                      note: trimmed,
                      lastSessionId: sessionId,
                      createdAtMs: now,
                      updatedAtMs: now,
                    );
              await _repository.saveExerciseNote(updated);
              _exerciseNotes[exerciseId] = updated;
            }
            _notify();
          } catch (e) {
            _setError('Failed to save exercise note: $e');
          }
        });
  }

  ExerciseNote? getExerciseNote(String exerciseId) {
    return _exerciseNotes[exerciseId];
  }

  bool hasExerciseNote(String exerciseId) {
    return _exerciseNotes.containsKey(exerciseId) &&
        _exerciseNotes[exerciseId] != null;
  }

  Future<void> initExerciseHints() async {
    if (kDebugAlwaysShowExerciseHints) {
      _exerciseNotesHintSeen = false;
      _exerciseInfoHintSeen = false;
      _notify();
      return;
    }
    _exerciseNotesHintSeen = await _repository.getPreferenceBool(
      'hint_seen_exercise_notes',
    );
    _exerciseInfoHintSeen = await _repository.getPreferenceBool(
      'hint_seen_exercise_info',
    );
    _notify();
  }

  Future<void> markExerciseNotesHintSeen() async {
    if (_exerciseNotesHintSeen) return;
    _exerciseNotesHintSeen = true;
    _notify();
    await _repository.setPreferenceBool('hint_seen_exercise_notes', true);
  }

  Future<void> markExerciseInfoHintSeen() async {
    if (_exerciseInfoHintSeen) return;
    _exerciseInfoHintSeen = true;
    _notify();
    await _repository.setPreferenceBool('hint_seen_exercise_info', true);
  }

  Future<void> resetExerciseHintsForTesting() async {
    _exerciseNotesHintSeen = false;
    _exerciseInfoHintSeen = false;
    _notify();
    await _repository.setPreferenceBool('hint_seen_exercise_notes', false);
    await _repository.setPreferenceBool('hint_seen_exercise_info', false);
  }

  void clearNoteCache() {
    _exerciseNotes.clear();
    _exerciseNoteLoadInFlight.clear();
    _exerciseNoteSaveInFlight.clear();
  }

  Future<Exercise?> createCustomExercise({
    required String name,
    String? modality,
    String? description,
    String? disciplineId,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    _clearError();

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _setError('Exercise name is required');
      return null;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final exerciseId = 'exercise-$now';
      final exercise = Exercise(
        id: exerciseId,
        ownerUserId: 'user-1',
        modality: modality,
        disciplineId: disciplineId,
        name: trimmedName,
        description: description?.trim().isEmpty == true ? null : description,
        createdAtMs: now,
        updatedAtMs: now,
      );

      await _repository.createExercise(exercise);
      await _repository.setExerciseCapabilities(exerciseId, capabilities);
      await _repository.setExerciseMuscleGroups(exerciseId, muscleGroupIds);

      final exerciseWithCaps = exercise.copyWith(capabilities: capabilities);
      _allExercises = [
        ..._allExercises.where((e) => e.id != exerciseId),
        exerciseWithCaps,
      ];

      _notify();
      return exerciseWithCaps;
    } catch (e) {
      _setError('Failed to create exercise: $e');
      return null;
    }
  }

  Future<Exercise?> updateCustomExercise({
    required Exercise exercise,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    _clearError();

    final trimmedName = exercise.name.trim();
    if (trimmedName.isEmpty) {
      _setError('Exercise name is required');
      return null;
    }

    try {
      final updated = exercise.copyWith(
        name: trimmedName,
        description: exercise.description?.trim().isEmpty == true
            ? null
            : exercise.description,
      );

      await _repository.updateExercise(updated);
      await _repository.setExerciseCapabilities(updated.id, capabilities);
      await _repository.setExerciseMuscleGroups(updated.id, muscleGroupIds);

      // Mark the entry as user-touched so the next catalog refresh
      // doesn't overwrite the user's edit (or capability / muscle-group
      // choices). For seed exercises this protects the user's
      // customization; for custom exercises (whose ids are never in
      // the seed list) it's a harmless no-op.
      await _repository.markSeedEntryTouched(
        SeedEntryType.exercise,
        updated.id,
      );

      final updatedWithCaps = updated.copyWith(capabilities: capabilities);
      _allExercises = [
        ..._allExercises.where((e) => e.id != updated.id),
        updatedWithCaps,
      ];

      _notify();
      return updatedWithCaps;
    } catch (e) {
      _setError('Failed to update exercise: $e');
      return null;
    }
  }

  Future<void> loadAllExercises() async {
    try {
      _allExercises = await _repository.getExercises();
      _notify();
    } catch (e) {
      _setError('Failed to load exercises: $e');
    }
  }

  Future<void> loadMuscleGroups() async {
    try {
      _muscleGroups = await _repository.getMuscleGroups();
      _notify();
    } catch (e) {
      _setError('Failed to load muscle groups: $e');
    }
  }

  Future<void> loadDisciplines() async {
    try {
      _disciplines = await _repository.getDisciplines();
      _notify();
    } catch (e) {
      _setError('Failed to load disciplines: $e');
    }
  }

  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    try {
      return await _repository.searchExercises(
        searchText: searchText,
        disciplineId: disciplineId,
        muscleGroupIds: muscleGroupIds,
      );
    } catch (e) {
      _setError('Failed to search exercises: $e');
      return [];
    }
  }

  Future<List<Exercise>> getExercisesRankedForModality({
    String? modality,
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  }) async {
    try {
      final modalityToUse = modality ?? _getCurrentSessionModality();
      return await _repository.getExercisesRankedForModality(
        modalityToUse,
        searchText: searchText,
        disciplineId: disciplineId,
        muscleGroupIds: muscleGroupIds,
      );
    } catch (e) {
      _setError('Failed to get ranked exercises: $e');
      return [];
    }
  }

  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId) async {
    try {
      return await _repository.getExerciseMuscleGroups(exerciseId);
    } catch (e) {
      _setError('Failed to load exercise muscle groups: $e');
      return [];
    }
  }

  void _setError(String message) => _setErrorCallback(message);

  void _clearError() => _clearErrorCallback();
}
