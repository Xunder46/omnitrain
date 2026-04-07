import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

/// Fake repository that adds configurable latency to note reads/writes.
/// Useful for testing async sequencing of note load/save flows.
class DelayedNoteRepository extends MockWorkoutRepository {
  final Duration loadLatency;
  final Duration saveLatency;
  final Map<String, int> _getExerciseNoteReadCounts = {};

  DelayedNoteRepository({
    this.loadLatency = Duration.zero,
    this.saveLatency = const Duration(milliseconds: 100),
  });

  @override
  Future<ExerciseNote?> getExerciseNote(String exerciseId) async {
    _getExerciseNoteReadCounts[exerciseId] =
        (_getExerciseNoteReadCounts[exerciseId] ?? 0) + 1;
    if (loadLatency > Duration.zero) {
      await Future.delayed(loadLatency);
    }
    return super.getExerciseNote(exerciseId);
  }

  int getReadCountForExercise(String exerciseId) {
    return _getExerciseNoteReadCounts[exerciseId] ?? 0;
  }

  @override
  Future<void> saveExerciseNote(ExerciseNote note) async {
    await Future.delayed(saveLatency);
    await super.saveExerciseNote(note);
  }

  @override
  Future<void> deleteExerciseNote(String exerciseId) async {
    await Future.delayed(saveLatency);
    await super.deleteExerciseNote(exerciseId);
  }
}
