import '../models/models.dart';

/// Abstract interface for workout data operations
abstract class WorkoutRepository {
  // Exercises
  Future<List<Exercise>> getExercises();
  Future<Exercise?> getExerciseById(String id);
  Future<String> createExercise(Exercise exercise);
  Future<void> updateExercise(Exercise exercise);
  Future<void> deleteExercise(String id);
  Future<List<Exercise>> searchExercises({
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  });

  // Sessions
  Future<TrainingSession?> getSession(String id);
  Future<String> createSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);

  // Segments
  Future<List<SessionSegment>> getSessionSegments(String sessionId);
  Future<String> createSegment(SessionSegment segment);

  // Efforts
  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId);
  Future<String> createEffort(SegmentEffort effort);

  // Observations
  Future<List<EffortObservation>> getEffortObservations(String effortId);
  Future<String> createObservation(EffortObservation observation);
  Future<void> updateObservation(EffortObservation observation);

  // Sport Categories
  Future<List<SportCategory>> getSportCategories();
  Future<SportCategory?> getSportCategoryById(String id);
  Future<SportCategory?> getSportCategoryByKey(String key);

  // Disciplines
  Future<List<Discipline>> getDisciplines();
  Future<Discipline?> getDisciplineById(String id);
  Future<List<Discipline>> getDisciplinesByCategory(String categoryId);

  // Muscle Groups
  Future<List<MuscleGroup>> getMuscleGroups();
  Future<List<MuscleGroup>> getExerciseMuscleGroups(String exerciseId);

  // Equipment
  Future<List<Equipment>> getEquipment();
  Future<List<Equipment>> getExerciseEquipment(String exerciseId);

  // Tags
  Future<List<Tag>> getTags();
  Future<List<Tag>> getExerciseTags(String exerciseId);

  // Units
  Future<List<UnitModel>> getUnits();
  Future<UnitModel?> getUnitById(String id);

  // Metrics
  Future<List<MetricDefinition>> getMetricDefinitions();
  Future<List<MetricDefinition>> getMetricsForEffortKind(String effortKind);
  Future<MetricDefinition?> getMetricById(String id);

  // Templates
  Future<List<WorkoutTemplate>> getTemplates();
  Future<WorkoutTemplate?> getTemplateById(String id);
  Future<List<TemplateSegment>> getTemplateSegments(String templateId);
  Future<List<TemplateEffort>> getTemplateEfforts(String templateSegmentId);
  Future<List<TemplateTarget>> getTemplateTargets(String templateEffortId);
}

