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
  Future<List<TrainingSession>> getInProgressSessions();
  Future<List<TrainingSession>> getSessionsByDateRange(int fromMs, int toMs);
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

  /// Every segment on the device, grouped by `sessionId`.
  ///
  /// Semantically identical to calling [getSessionSegments] once per
  /// session, but costs a single pass instead of one full scan per
  /// session. Each group carries the same ordering [getSessionSegments]
  /// guarantees.
  ///
  /// Intended for whole-history analytics (see `StatsProgressService`).
  /// Screens that need one session's segments should keep using
  /// [getSessionSegments].
  Future<Map<String, List<SessionSegment>>> getSegmentsBySession();

  // Efforts
  /// Returns efforts in deterministic active-session display order.
  ///
  /// Ordering contract:
  /// - top-level order for standalone efforts
  /// - block-local order for efforts inside the same block
  /// - stable tie-breakers for legacy rows
  Future<List<SegmentEffort>> getSegmentEfforts(String segmentId);

  /// Every effort on the device, grouped by `segmentId`.
  ///
  /// The bulk counterpart to [getSegmentEfforts]; each group is sorted
  /// by the same ordering contract documented there. One pass over the
  /// effort store instead of one full scan per segment.
  Future<Map<String, List<SegmentEffort>>> getEffortsBySegment();

  /// Persist a new effort.
  ///
  /// Implementations must assign deterministic ordering metadata for:
  /// - top-level session order (standalone efforts)
  /// - block-local order (efforts assigned to blocks)
  Future<String> createEffort(SegmentEffort effort);

  // Observations
  Future<List<EffortObservation>> getEffortObservations(String effortId);

  /// Every observation on the device, grouped by `effortId`.
  ///
  /// The bulk counterpart to [getEffortObservations]. Like that method
  /// the groups carry no ordering guarantee — callers that need a
  /// stable order must sort.
  Future<Map<String, List<EffortObservation>>> getObservationsByEffort();

  /// Every timed instance on the device, grouped by `effortId`.
  ///
  /// The bulk counterpart to [getTimedInstances]; each group carries the
  /// same `entryIndex` ordering.
  Future<Map<String, List<TimedInstance>>> getTimedInstancesByEffort();
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

  /// Insert [group] if absent, or update it in place when the bundled
  /// definition differs. Used by the catalog refresh so groups added after
  /// a device's first launch still reach it; without this, an exercise can
  /// reference a group the device has never heard of.
  Future<void> upsertMuscleGroup(MuscleGroup group);

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
  /// - `searchText`: Optional exercise-name search filter (case-insensitive, typo-tolerant)
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

  // ─── Periodization ─────────────────────────────────────────────────────

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

  /// Get all blocks for a session in deterministic top-level session order.
  Future<List<SessionBlock>> getSessionBlocks(String sessionId);

  /// Persist a new session block.
  ///
  /// Implementations must assign deterministic top-level order metadata so
  /// mixed block + standalone sessions reload in identical sequence.
  Future<String> createSessionBlock(SessionBlock block);

  /// Update an existing session block.
  Future<void> updateSessionBlock(SessionBlock block);

  /// Delete a session block by ID.
  /// Cascade-deletes linked efforts and their sub-records.
  Future<void> deleteSessionBlock(String blockId);

  /// Reorder blocks within a session by providing the desired ID order.
  Future<void> reorderSessionBlocks(String sessionId, List<String> orderedIds);

  /// Deep-clone a block and all its linked efforts/observations/rounds/rests.
  ///
  /// Ordering contract:
  /// - cloned block is appended to end of top-level session order
  /// - cloned efforts preserve source block-local order exactly
  Future<String> cloneSessionBlock(String blockId);

  /// Assign or unassign an effort to a block.
  /// Pass [blockId] as null to unassign (effort becomes unblocked).
  ///
  /// Implementations must update ordering metadata so assigning to a block
  /// appends at block tail without perturbing unrelated top-level items.
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

  // Nutrition Targets
  /// Get the nutrition target for a specific date (ms since epoch).
  /// If target exists for that date, returns it.
  /// If not, walks backward to find the most recent ancestor target and returns a copy.
  /// Returns null if no ancestor target exists.
  Future<NutritionTarget?> getNutritionTargetForDate(int dateMs);

  /// Save a nutrition target for a specific date and propagate forward.
  /// When saving, updates all future dates that had the old target values to the new values.
  /// Only updates future targets that are identical to the one being replaced (forward-propagation rule).
  /// Past targets are never modified.
  Future<void> saveNutritionTargetForDate(int dateMs, NutritionTarget target);

  /// Get today's nutrition target (convenience method; delegates to getNutritionTargetForDate with today).
  /// Backwards compatibility: existing code using this method continues to work.
  Future<NutritionTarget?> getNutritionTarget();

  /// Save today's nutrition target and propagate forward (convenience method; delegates to saveNutritionTargetForDate with today).
  /// Backwards compatibility: existing code using this method continues to work.
  Future<void> saveNutritionTarget(NutritionTarget target);

  // ─── Food Library ─────────────────────────────────────────────────────────

  /// Get all non-archived food groups.
  /// Pass [includeArchived] = true to include archived groups.
  Future<List<FoodGroup>> getFoodGroups({bool includeArchived = false});

  /// Get a single food group by ID, or null if not found.
  Future<FoodGroup?> getFoodGroupById(String id);

  /// Create a new food group; returns its ID.
  Future<String> createFoodGroup(FoodGroup group);

  /// Update an existing food group.
  Future<void> updateFoodGroup(FoodGroup group);

  /// Archive a food group (soft-delete: sets isArchived = true).
  Future<void> archiveFoodGroup(String id);

  /// Reassign a list of foods to a new group in a single transaction.
  ///
  /// Used by the Groups tab when deleting a non-empty group:
  /// the caller passes the source group's food ids and a destination
  /// group id (or `null` for "Ungrouped"). The repository updates
  /// each food's `groupId` in place; foods are never deleted by
  /// this method.
  ///
  /// Unknown food ids are silently skipped (idempotent). An empty
  /// list is a no-op.
  Future<void> reassignFoodsToGroup(
    List<String> foodIds,
    String? targetGroupId,
  );

  /// Reassign a list of **catalog** foods to a new group in a single
  /// transaction.
  ///
  /// Parallel to [reassignFoodsToGroup] but targets the catalog box
  /// (`_foodCatalogBox`) instead of the library box. Used by
  /// `FoodLibraryState.deleteFoodGroupReassigningFoods` so that
  /// user-owned catalog foods (those created via the **+ New Item**
  /// flow) are moved off a deleted category just like library foods
  /// are. Bundled catalog foods are never passed here — the
  /// bundled-food guard runs before this method is called and refuses
  /// the entire deletion if any bundled food points at the source
  /// group (the catalog refresh would otherwise undo the rewrite).
  ///
  /// Unknown food ids are silently skipped (idempotent). An empty
  /// list is a no-op.
  Future<void> reassignCatalogFoodsToGroup(
    List<String> catalogFoodIds,
    String? targetGroupId,
  );

  /// Get all non-archived foods.
  /// Pass [includeArchived] = true to include archived foods.
  Future<List<Food>> getFoods({bool includeArchived = false});

  /// Get all non-archived foods belonging to a specific group.
  /// Pass [includeArchived] = true to include archived foods.
  Future<List<Food>> getFoodsByGroup(String groupId, {bool includeArchived = false});

  /// Get a single food by ID, or null if not found.
  Future<Food?> getFoodById(String id);

  /// Search foods by name (case-insensitive substring match).
  /// Pass [includeArchived] = true to include archived foods in results.
  Future<List<Food>> searchFoods(String query, {bool includeArchived = false});

  /// Create a new food; returns its ID.
  Future<String> createFood(Food food);

  /// Update an existing food.
  Future<void> updateFood(Food food);

  /// Archive a food (soft-delete: sets isArchived = true).
  /// Does NOT remove from storage — archived foods remain in the database
  /// but are excluded from active queries (getFoods, searchFoods, etc.)
  /// unless [includeArchived] = true is passed.
  Future<void> archiveFood(String id);

  /// Hard-delete a library food from the user's library.
  ///
  /// This operation is safe because [ConsumedFood] (the day-log snapshot model)
  /// freezes all food attributes at log time: name, unitType, referenceAmount,
  /// referenceLabel, protein, carbs, fiber, fat, sodium, groupIdSnapshot,
  /// groupNameSnapshot, and the daily targets. A [ConsumedFood] row stores its
  /// own copy of every value — it does NOT reference the live [Food] row.
  ///
  /// The [sourceFoodId] field on [ConsumedFood] may become a dangling reference
  /// after removal — this is expected and supported. The snapshot remains valid
  /// because all needed values are frozen on the [ConsumedFood] itself.
  ///
  /// This method only touches user-owned library foods (isCatalog = false).
  /// Catalog foods (isCatalog = true) are read-only and cannot be removed
  /// through this method; passing a catalog ID is a no-op.
  ///
  /// Does nothing if [id] is not present in the library.
  Future<void> removeFood(String id);

  // ─── Food Catalog ─────────────────────────────────────────────────────────
  // The catalog is the **global managed library**: a bundled set of
  // foods that ships with the app and is mutable at runtime. Users
  // can browse it on the **Library** tab of `AddFoodScreen`, edit any
  // catalog food, and create new catalog foods via the **+ New Item**
  // tab. Catalog foods can be added to the user's personal library
  // for logging via the **Add** button on the row.

  /// Get all catalog foods.
  /// Pass [includeArchived] = true to include archived foods.
  Future<List<Food>> getCatalogFoods({bool includeArchived = false});

  /// Get a single catalog food by ID, or null if not found.
  Future<Food?> getCatalogFoodById(String id);

  /// Create a new catalog food. The new row has `isCatalog = true`
  /// and a fresh id assigned by the state. Returns the new id.
  Future<String> createCatalogFood(Food food);

  /// Update an existing catalog food. Preserves the original `id`
  /// and `isCatalog = true`; advances `updatedAtMs`. Implementations
  /// should throw a clear exception when the id is not present.
  Future<void> updateCatalogFood(Food food);

  /// Delete a catalog food by ID (hard delete). This permanently
  /// removes the food from the catalog. Does NOT affect user's
  /// historical nutrition logs (ConsumedFood entries) since they
  /// store frozen snapshots.
  ///
  /// Implementations should throw if the id is not present.
  Future<void> deleteCatalogFood(String id);

  /// Copy a catalog food into the user's library.
  /// Returns the new library food's ID.
  /// The new library food will have:
  /// - A new generated ID (not the catalog ID)
  /// - isCatalog = false
  /// - All other fields copied from the catalog source
  /// The original catalog food remains unchanged.
  Future<String> addCatalogFoodToLibrary(String catalogFoodId);

  // ─── Day Nutrition Log ────────────────────────────────────────────────────
  // Foods consumed on a given day. Each entry is a frozen snapshot.

  /// Get all consumed foods for a specific day.
  /// Returns entries where dateMs matches the given day (local midnight).
  Future<List<ConsumedFood>> getConsumedFoodsForDate(int dateMs);

  /// Create a new consumed food entry (log a food).
  /// Returns the new entry's ID.
  Future<String> createConsumedFood(ConsumedFood entry);

  /// Delete a consumed food entry by ID.
  Future<void> deleteConsumedFood(String id);

  /// Get consumed foods within a date range (inclusive).
  /// Useful for reports or bulk operations.
  Future<List<ConsumedFood>> getConsumedFoodsInRange(int fromMs, int toMs);

  /// Update an existing consumed food entry by id.
  ///
  /// The entry's [ConsumedFood.id] is used as the storage key. The frozen
  /// snapshot contract is preserved by the caller — this method writes
  /// whatever fields the caller sets, but the UI/state layer is responsible
  /// for keeping name, unit, reference, macros, and target fields stable
  /// when only the amount has changed.
  ///
  /// Implementations should throw a clear exception (e.g. `StateError`)
  /// when the id is not present, so the caller can detect the bug.
  Future<void> updateConsumedFood(ConsumedFood entry);

  /// Get a single consumed food entry by id, or `null` if not found.
  ///
  /// Used by the state layer as a cache-miss fallback when looking up a
  /// row by [ConsumedFood.sourceFoodId] + [ConsumedFood.dateMs].
  Future<ConsumedFood?> getConsumedFoodById(String id);

  // ─── Daily Water Log ──────────────────────────────────────────────────────
  // One row per calendar day; the day's volume is stored as a real milliliter
  // value so the historical record stays unit-clean. The on-screen glass
  // count is derived at the display boundary, never stored.

  /// Returns the stored water volume in milliliters for [dateMs]
  /// (local midnight). Returns `0` when no row exists — the absence of a
  /// row is the same as a 0 ml day, callers never see `null`.
  ///
  /// Past dates are never modified implicitly; the per-day row only changes
  /// when the user explicitly logs a glass on that date.
  Future<int> getWaterVolumeForDate(int dateMs);

  /// Persist [volumeMl] (clamped to `>= 0`) for [dateMs]. Creates the row
  /// on first write; overwrites the existing row on subsequent writes.
  /// Past dates other than [dateMs] are never touched.
  ///
  /// The row id is derived from [dateMs] via [WaterLogEntry.idForDate] so
  /// the same day always maps to the same storage key in both
  /// implementations.
  Future<void> saveWaterVolumeForDate(int dateMs, int volumeMl);

  // ─── Catalog Version + Seed-Entry Tombstones ─────────────────────────────
  //
  // These methods back [CatalogRefreshService]. They are intentionally
  // separate from the per-entity read/write methods so the refresh can:
  //   - read the device's stored catalog version,
  //   - skip seed entries the user has touched (tombstone),
  //   - write the new version atomically only after a successful refresh.
  //
  // The tombstone design lets the refresh distinguish "seed entry the user
  // has edited" from "seed entry that hasn't been touched yet". A tombstone
  // is set by the state layer when the user mutates a seed entry; the
  // refresh reads it but never writes it.

  /// Read the device's stored catalog version. Returns [defaultValue] when
  /// no value has been written yet (typically `0` for legacy installs).
  Future<int> getCatalogVersion({int defaultValue = 0});

  /// Persist the device's catalog version. Called by [CatalogRefreshService]
  /// after a successful refresh so subsequent launches skip the work.
  Future<void> setCatalogVersion(int version);

  /// Returns `true` if the user has ever mutated the seed entry identified
  /// by ([entityType], [id]). The refresh consults this before overwriting
  /// an existing device row with the bundled value.
  Future<bool> isSeedEntryTouched(String entityType, String id);

  /// Mark a seed entry as user-touched. The state layer calls this when the
  /// user edits, archives, or deletes a seed entry; the refresh then skips
  /// the entry on subsequent upgrades.
  ///
  /// Idempotent. Safe to call from any code path that mutates a seed entry.
  Future<void> markSeedEntryTouched(String entityType, String id);

  // ─── Data-Migration Version Sequence ─────────────────────────────────────
  //
  // The repository persists a single `data_version` integer that tracks
  // which consolidated migration step the device has reached. On startup,
  // `DataMigrationService` reads it, runs any pending steps in order, and
  // advances the version after each step succeeds. The catalog refresh
  // (`catalog_version`) is a separate always-on mechanism and is not
  // affected by this version.

  /// Read the device's stored data-migration version. Returns
  /// [defaultValue] (typically `1`) when no value has been written yet —
  /// either a brand-new install or a legacy install that has not yet been
  /// mapped by the back-compat shim.
  Future<int> getDataVersion({int defaultValue = 1});

  /// Persist the device's data-migration version. Called by
  /// `DataMigrationService` after each step completes so subsequent
  /// launches skip the work.
  Future<void> setDataVersion(int version);

  /// Back-compat shim: returns the highest data-version implied by any
  /// legacy one-shot marker still present on the device. `1` when none
  /// of the legacy markers are set. Called once on the first launch under
  /// the new system to map legacy installs to the correct starting
  /// version without re-running already-applied steps.
  Future<int> getLegacyAppliedDataVersion();

  /// Returns the most recent `(from, to)` transition the device recorded
  /// after a data-migration run, or `null` if no transition has been
  /// recorded yet. Diagnostic — used by support / debugging tools.
  Future<({int from, int to})?> getLastDataVersionTransition();

  /// Record the most recent `(from, to)` data-migration transition.
  /// Called by `DataMigrationService` after a successful migration run.
  Future<void> setLastDataVersionTransition(int from, int to);
}
