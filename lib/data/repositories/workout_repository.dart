import '../models/models.dart';

/// Abstract interface for workout data operations
abstract class WorkoutRepository {
  /// Initialize the repository (load seed data, open database, etc.)
  /// Must be called before any other operations
  Future<void> initialize();
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
  Future<List<TrainingSession>> getAllSessions();
  Future<List<TrainingSession>> getSessionsByDateRange(int fromMs, int toMs);

  /// Returns sessions that have not yet been finished (endedAtMs == null),
  /// sorted by startedAtMs descending (most recent first).
  /// Malformed records are skipped gracefully — never throws.
  Future<List<TrainingSession>> getInProgressSessions();
  Future<double?> getPersonalRecordCandidates(
    String exerciseId, {
    String? metricId,
  });
  Future<String> createSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);
  Future<void> updateSessionFeeling(String sessionId, int feeling);
  Future<void> deleteSession(String id);

  // Profile
  Future<UserProfile?> getProfile();
  Future<void> saveProfile(UserProfile profile);
  Future<List<BodyMeasurementEntry>> getMeasurementHistory(
    String measurementType,
  );
  Future<BodyMeasurementEntry?> getLatestMeasurement(String measurementType);
  Future<void> saveMeasurementEntry(BodyMeasurementEntry entry);
  Future<void> deleteMeasurementEntry(String entryId);

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
  Future<void> setExerciseMuscleGroups(
    String exerciseId,
    List<String> muscleGroupIds,
  );

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
  Future<void> setExerciseCapabilities(
    String exerciseId,
    List<String> capabilities,
  );

  // Round Instances
  //
  // Stores the full lifecycle of each timed round for effortKind == 'round' efforts.
  // Each RoundInstance captures: planned duration, wall-clock timestamps, actual
  // elapsed time, and whether the round completed naturally vs was cut short.
  // This replaces the old metric-rounds + metric-round-duration observation-pair pattern.

  /// Get all round instances for a round-based effort, ordered by roundIndex ascending.
  Future<List<RoundInstance>> getRoundInstances(String effortId);

  /// Persist a newly created round instance (startedAtMs = 0, not yet begun).
  Future<String> createRoundInstance(RoundInstance instance);

  /// Update an existing round instance.
  /// Used to set startedAtMs, finishedAtMs, actualDurationSecs, and completed flag.
  Future<void> updateRoundInstance(RoundInstance instance);

  /// Delete a single round instance by ID.
  Future<void> deleteRoundInstance(String id);

  /// Delete all round instances belonging to an effort.
  /// Call this before deleting the effort to maintain referential integrity
  /// (or rely on ON DELETE CASCADE in the SQLite schema).
  Future<void> deleteRoundInstancesForEffort(String effortId);

  // Timed Instances
  //
  // Stores the full lifecycle of each timed entry for effortKind == 'timed' or 'drill' efforts.
  // Each TimedInstance captures: target duration (0 = open-ended), wall-clock timestamps,
  // actual elapsed time, and explicit lifecycle state.
  // The companion metric (distance for timed, extra weight for drill) remains as an EffortObservation.
  // This replaces the old duration EffortObservation for these effort kinds.

  /// Get all timed instances for a timed/drill effort, ordered by entryIndex ascending.
  Future<List<TimedInstance>> getTimedInstances(String effortId);

  /// Persist a newly created timed instance (startedAtMs = 0, not yet begun).
  Future<String> createTimedInstance(TimedInstance instance);

  /// Update an existing timed instance.
  /// Used to set startedAtMs, finishedAtMs, actualDurationSecs, state, and pause fields.
  Future<void> updateTimedInstance(TimedInstance instance);

  /// Delete a single timed instance by ID.
  Future<void> deleteTimedInstance(String id);

  /// Delete all timed instances belonging to an effort.
  /// Call this before deleting the effort to maintain referential integrity
  /// (or rely on ON DELETE CASCADE in the SQLite schema).
  Future<void> deleteTimedInstancesForEffort(String effortId);

  // Entry Rests
  //
  // Tracks the actual recovery time between consecutive sets/rounds/entries for
  // ANY effort kind (set, round, timed, drill, and any future kinds).
  // Created with restEndMs == null at the moment a set is logged; closed
  // (restEndMs set) when the athlete actively starts the next set/round/timer.
  // All times are wall-clock epoch milliseconds — rest survives backgrounding.

  /// Get all rest records for an effort, ordered by entryIndex ascending.
  Future<List<EntryRest>> getEntryRests(String effortId);

  /// Persist a newly created rest record (restEndMs = null, athlete is resting).
  Future<String> createEntryRest(EntryRest rest);

  /// Update an existing rest record (typically to set restEndMs when rest ends).
  Future<void> updateEntryRest(EntryRest rest);

  /// Delete all rest records belonging to an effort.
  /// Called by deleteEffort() and during edit-mode rollback.
  Future<void> deleteEntryRestsForEffort(String effortId);

  /// Returns all closed EntryRest records (restEndMs != null) whose restStartMs
  /// falls within [fromMs, toMs], grouped by normalised modality key.
  /// - null key = Free Training (session had no modality set).
  Future<Map<String?, List<EntryRest>>> getEntryRestsByModalityInDateRange(
    int fromMs,
    int toMs,
  );

  // Exercise Notes
  //
  // Per-exercise user notes that persist across sessions.
  // Notes are keyed by exerciseId (deterministic id = 'note-{exerciseId}').
  // These are NOT session-scoped: one note per exercise, updated in-place.

  /// Get the note for an exercise, or null if none exists.
  Future<ExerciseNote?> getExerciseNote(String exerciseId);

  /// Upsert a note for an exercise.
  Future<void> saveExerciseNote(ExerciseNote note);

  /// Delete the note for an exercise (called when note text is empty).
  Future<void> deleteExerciseNote(String exerciseId);

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

  // ─── Planned Sessions ─────────────────────────────────────────────────────

  /// Get all planned sessions, ordered by scheduled_date_ms ascending.
  Future<List<PlannedSession>> getPlannedSessions();

  /// Get planned sessions within [fromMs]..[toMs] inclusive.
  /// Matches sessions where scheduled_date_ms falls within the range.
  Future<List<PlannedSession>> getPlannedSessionsForDateRange(
    int fromMs,
    int toMs,
  );

  /// Persist a new planned session; returns its ID.
  Future<String> createPlannedSession(PlannedSession session);

  /// Update an existing planned session (e.g. mark completed, change modality).
  Future<void> updatePlannedSession(PlannedSession session);

  /// Delete a planned session by ID.
  Future<void> deletePlannedSession(String id);

  /// Get all planned sessions linked to a specific routine template.
  Future<List<PlannedSession>> getPlannedSessionsByTemplateId(
    String templateId,
  );

  /// Delete all planned sessions linked to a specific routine template.
  /// Used during routine deletion cascade.
  Future<void> deletePlannedSessionsByTemplateId(String templateId);

  // ─── Training Periods ─────────────────────────────────────────────────────

  /// Get all training periods, ordered by start_date_ms ascending.
  Future<List<TrainingPeriod>> getPeriods();

  /// Get a single training period by ID; null if not found.
  Future<TrainingPeriod?> getPeriodById(String id);

  /// Persist a new training period; returns its ID.
  Future<String> createPeriod(TrainingPeriod period);

  /// Update an existing training period.
  Future<void> updatePeriod(TrainingPeriod period);

  /// Delete a training period by ID.
  Future<void> deletePeriod(String id);

  /// Returns true if [startMs]..[endMs] overlaps any existing period.
  ///
  /// Overlap rule: startMs <= existing.endDateMs AND endMs >= existing.startDateMs
  ///
  /// [excludeId]: when editing an existing period, pass its ID to skip it.
  Future<bool> hasPeriodOverlap(int startMs, int endMs, {String? excludeId});

  // ─── Session Blocks ───────────────────────────────────────────────────────

  /// Get all blocks for a session, ordered by orderIndex ascending.
  Future<List<SessionBlock>> getSessionBlocks(String sessionId);

  /// Persist a new session block; returns its ID.
  Future<String> createSessionBlock(SessionBlock block);

  /// Update an existing session block.
  Future<void> updateSessionBlock(SessionBlock block);

  /// Delete a session block by ID.
  /// Nulls out blockId on any linked SegmentEffort — does NOT delete the efforts.
  Future<void> deleteSessionBlock(String blockId);

  /// Reorder blocks within a session by providing the desired ID order.
  Future<void> reorderSessionBlocks(String sessionId, List<String> orderedIds);

  /// Deep-clone a block and all its linked efforts/observations/rounds/rests.
  /// Returns the new block's ID.
  Future<String> cloneSessionBlock(String blockId);

  /// Assign or unassign an effort to a block.
  /// Pass [blockId] as null to unassign (effort becomes unblocked).
  Future<void> assignEffortToBlock(String effortId, String? blockId);

  // ─── Preferences ─────────────────────────────────────────────────────────

  /// Read a named boolean preference; returns [defaultValue] when not yet set.
  Future<bool> getPreferenceBool(String key, {bool defaultValue = false});

  /// Write a named boolean preference.
  Future<void> setPreferenceBool(String key, bool value);

  /// Read a named string preference; returns [defaultValue] when not yet set.
  Future<String?> getPreferenceString(String key, {String? defaultValue});

  /// Write a named string preference.
  Future<void> setPreferenceString(String key, String value);
}
