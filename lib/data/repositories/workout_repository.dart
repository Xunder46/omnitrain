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
  Future<void> deleteObservation(String id);
  Future<void> deleteObservationsForEffort(String effortId);

  // Efforts (additional methods)
  Future<void> deleteEffort(String id);

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
  Future<String> createTemplate(WorkoutTemplate template);
  Future<void> updateTemplate(WorkoutTemplate template);
  Future<void> deleteTemplate(String id);
  Future<List<TemplateSegment>> getTemplateSegments(String templateId);
  Future<String> createTemplateSegment(TemplateSegment segment);
  Future<void> updateTemplateSegment(TemplateSegment segment);
  Future<void> deleteTemplateSegment(String id);
  Future<List<TemplateEffort>> getTemplateEfforts(String templateSegmentId);
  Future<String> createTemplateEffort(TemplateEffort effort);
  Future<void> updateTemplateEffort(TemplateEffort effort);
  Future<void> deleteTemplateEffort(String id);
  Future<List<TemplateTarget>> getTemplateTargets(String templateEffortId);
  Future<String> createTemplateTarget(TemplateTarget target);
  Future<void> updateTemplateTarget(TemplateTarget target);
  Future<void> deleteTemplateTarget(String id);
  Future<void> deleteTemplateTargetsForEffort(String templateEffortId);

  // Exercise Capabilities
  Future<List<String>> getExerciseCapabilities(String exerciseId);
  Future<void> setExerciseCapabilities(String exerciseId, List<String> capabilities);

  // Modality-ranked exercise retrieval
  /// Retrieve exercises ranked by relevance to a given modality.
  ///
  /// This method implements intelligent exercise recommendation for the exercise picker.
  /// Exercises are scored based on how well they fit the specified modality, using a
  /// multi-factor ranking algorithm that considers:
  ///
  /// 1. **Discipline Affinity (0-40 points)**: Does the exercise's discipline belong
  ///    to the modality's category? E.g., Running discipline → category-cardio → cardio_endurance.
  ///    This is the strongest signal because it directly maps to the modality.
  ///
  /// 2. **Primary Capability Match (0-30 points)**: What fraction of the modality's core
  ///    capabilities does the exercise support? E.g., cardio_endurance has primary capabilities
  ///    ['time', 'distance']. An exercise with ['time', 'distance'] gets 30 points.
  ///
  /// 3. **Secondary Capability Bonus (0-10 points)**: Bonus for supporting secondary
  ///    capabilities. E.g., cardio accepts ['rounds'] as secondary.
  ///
  /// 4. **Anti-Capability Penalty (0 to -20 points)**: Penalty for having capabilities
  ///    from conflicting modalities. E.g., 'load' and 'hold' capabilities are bad for cardio.
  ///
  /// 5. **No-Overlap Penalty (0 or -10 points)**: Additional penalty if no primary
  ///    capabilities match AND the exercise's category differs from the modality's category.
  ///
  /// **Scoring Example**:
  /// - Barbell Squat (discipline: bodybuilding, capabilities: ['reps', 'sets', 'load', 'time'])
  ///   - In resistance_lifting: 40 (discipline) + 30 (all 3 primary) + 0 (no secondary) + 0 (no anti) = **70 → Recommended**
  ///   - In cardio_endurance: 0 (different category) + 0 (no primary time/distance) + 0 (no secondary) + -20 ('load' anti) = **-20 → 0 (clamped) → Others**
  ///
  /// **Return Order**:
  /// - Exercises are sorted descending by relevance score
  /// - Ties are broken alphabetically by name
  /// - The UI partitions at score >= 50.0 to create "Recommended" vs "Others" sections
  /// - For Free Training (modality=null), exercises return alphabetically sorted without ranking
  ///
  /// **Parameters**:
  /// - `modality`: The session's modality (e.g., 'cardio_endurance') or null for Free Training
  /// - `searchText`: Optional search filter (matches exercise name/description, case-insensitive)
  /// - `disciplineId`: Optional discipline filter
  /// - `muscleGroupIds`: Optional muscle group filter (exercise must have at least one)
  ///
  /// **Implementation Notes**:
  /// - Web (MockWorkoutRepository): Uses in-memory lookups with ModalityConfig from lib/core/constants/modality_config.dart
  /// - Production (SqliteWorkoutRepository): Queries app_exercise_capability table and calculates scores
  /// - Both implementations share the same scoring logic from ModalityConfig.calculateRelevanceScore()
  /// - The 'capabilities' list is populated on each Exercise returned (transient field)
  /// - See scripts/sqlite_schema.sql for app_exercise_capability table documentation
  /// - See lib/core/constants/modality_config.dart for modality configuration definitions
  Future<List<Exercise>> getExercisesRankedForModality(
    String? modality, {
    String? searchText,
    String? disciplineId,
    List<String>? muscleGroupIds,
  });
}

