import '../models/models.dart';

/// Abstract interface for workout data operations
abstract class WorkoutRepository {
  Future<List<Exercise>> getExercises();
  Future<Exercise?> getExerciseById(String id);
  Future<String> createExercise(Exercise exercise);
  Future<void> updateExercise(Exercise exercise);
  Future<void> deleteExercise(String id);

  Future<TrainingSession?> getSession(String id);
  Future<String> createSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);

  Future<List<SessionSegment>> getSessionSegments(String sessionId);
  Future<String> createSegment(SessionSegment segment);

  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId);
  Future<String> createEffort(SegmentEffort effort);

  Future<List<EffortObservation>> getEffortObservations(String effortId);
  Future<String> createObservation(EffortObservation observation);
  Future<void> updateObservation(EffortObservation observation);

  // Muscle groups
  Future<List<MuscleGroup>> getMuscleGroups();
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId);

  // Disciplines
  Future<List<Discipline>> getDisciplines();

  // Exercise search with filters
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  });
}
