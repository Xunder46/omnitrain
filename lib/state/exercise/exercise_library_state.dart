// PR 8 — Exercise Library State
//
// ChangeNotifier that powers the Exercise Library screen. Talks only to
// `ExerciseLibraryService` and (for rename / edit body work) to
// `WorkoutState.updateCustomExercise`. Never touches the repository
// directly.

import 'package:flutter/foundation.dart';

import '../../core/services/exercise_library_service.dart';
import '../../data/models/models.dart';
import '../workout/workout_state.dart';

class ExerciseLibraryState extends ChangeNotifier {
  final ExerciseLibraryService _service;
  final WorkoutState _workoutState;

  List<Exercise> _exercises = const [];
  String? _searchText;
  String? _disciplineId;
  bool _customOnly = false;
  bool _isLoading = false;
  String? _error;

  ExerciseLibraryState({
    required ExerciseLibraryService service,
    required WorkoutState workoutState,
  }) : _service = service,
       _workoutState = workoutState;

  // ── Public reads ──────────────────────────────────────────────────────

  List<Exercise> get exercises => List.unmodifiable(_exercises);
  String? get searchText => _searchText;
  String? get disciplineId => _disciplineId;
  bool get customOnly => _customOnly;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ExerciseLibraryService get service => _service;
  WorkoutState get workoutState => _workoutState;

  // ── Filter mutations ─────────────────────────────────────────────────

  Future<void> setSearchText(String? value) async {
    _searchText = (value == null || value.trim().isEmpty) ? null : value;
    await _reload();
  }

  Future<void> setDisciplineId(String? value) async {
    _disciplineId = value;
    await _reload();
  }

  Future<void> setCustomOnly(bool value) async {
    _customOnly = value;
    await _reload();
  }

  Future<void> reload() => _reload();

  // ── Library actions ──────────────────────────────────────────────────

  /// Copy a bundled exercise into a new user-created exercise. Returns
  /// the newly-created exercise.
  ///
  /// Calling this on an already-custom exercise is a no-op copy that
  /// duplicates the row — supported because the user might want to
  /// fork a custom exercise they created earlier. The UI surface
  /// (ExerciseLibraryDetailScreen) does not expose copy on custom rows.
  Future<Exercise> copyAsCustom(Exercise source) async {
    _clearError();
    try {
      final created = await _service.copyAsCustom(source);
      await _reload();
      return created;
    } catch (e) {
      _setError('Failed to copy exercise: $e');
      rethrow;
    }
  }

  /// Reference-aware removal. Throws `BuiltInExerciseImmutableError`
  /// when called on a bundled row — the UI prevents that path, but
  /// the guard is here too.
  Future<ExerciseRemovalKind> removeExercise(Exercise exercise) async {
    _clearError();
    try {
      final kind = await _service.removeExercise(exercise);
      await _reload();
      return kind;
    } catch (e) {
      _setError('Failed to remove exercise: $e');
      rethrow;
    }
  }

  /// Rename a custom exercise in place. Bundled rows throw.
  Future<Exercise> renameCustom({
    required Exercise exercise,
    required String newName,
  }) async {
    _clearError();
    try {
      final updated = await _service.renameCustom(
        exercise: exercise,
        newName: newName,
      );
      await _reload();
      return updated;
    } catch (e) {
      _setError('Failed to rename exercise: $e');
      rethrow;
    }
  }

  /// Edit a custom exercise's body (delegates to the service, which
  /// persists capabilities + muscle groups).
  Future<Exercise> editCustom({
    required Exercise exercise,
    required String name,
    String? description,
    String? disciplineId,
    List<String> capabilities = const [],
    List<String> muscleGroupIds = const [],
  }) async {
    _clearError();
    try {
      final updated = await _service.editCustom(
        exercise: exercise,
        name: name,
        description: description,
        disciplineId: disciplineId,
        capabilities: capabilities,
        muscleGroupIds: muscleGroupIds,
      );
      await _reload();
      return updated;
    } catch (e) {
      _setError('Failed to edit exercise: $e');
      rethrow;
    }
  }

  // ── Internals ────────────────────────────────────────────────────────

  Future<void> _reload() async {
    _isLoading = true;
    notifyListeners();
    try {
      final results = await _service.searchExercises(
        searchText: _searchText,
        disciplineId: _disciplineId,
        customOnly: _customOnly,
      );
      _exercises = results;
    } catch (e) {
      _setError('Failed to load exercises: $e');
      _exercises = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }
}
