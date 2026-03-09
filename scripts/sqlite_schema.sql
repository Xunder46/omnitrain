PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

-- Note: IDs are TEXT (UUID hex), timestamps in INTEGER (ms), booleans as INTEGER (0/1).
--
-- UNIFIED SPORTS MODALITY (Feb 2026 Refactor):
-- ============================================== 
-- The 'sports' modality now encompasses both martial arts and sports exercises.
-- Home screen shows a unified "Sports" tile combining martial arts icon with sports modality.
-- Exercise ranking for sports modality pulls exercises from BOTH:
--   - category-martial-arts (Boxing, BJJ, Muay Thai, wrestling)
--   - category-sports (Soccer, basketball, tennis, team sports)
-- Feature constraints supported by sports modality:
--   - Primary metric: time (round duration)
--   - Secondary metrics: rounds (periods/halves/rounds)
--   - Optional metrics: distance, rpe
-- See Modality.modalityToCategoryIds in lib/core/constants/modality.dart
-- Migration: SqliteWorkoutRepository.getExercisesRankedForModality() must filter by
--   categoryIds IN ('category-martial-arts', 'category-sports') when modality='sports'
--
-- DELETE OPERATIONS (Phase 1 Implementation - Feb 2026):
-- =========================================================
-- The repository interface now supports deletion operations for session management:
--
-- 1. DELETE INDIVIDUAL OBSERVATIONS (remove sets/entries):
--    - WorkoutRepository.deleteObservation(String id)
--    - Use case: Remove a single set from an exercise
--    - SQLite: DELETE FROM app_effort_observation WHERE id = ?;
--
-- 2. DELETE ALL OBSERVATIONS FOR AN EFFORT (batch delete):
--    - WorkoutRepository.deleteObservationsForEffort(String effortId)
--    - Use case: Clear all entries when removing an exercise
--    - SQLite: DELETE FROM app_effort_observation WHERE effort_id = ?;
--
-- 3. DELETE EFFORT (remove exercise from session):
--    - WorkoutRepository.deleteEffort(String id)
--    - Must delete observations first (or use CASCADE)
--    - SQLite: DELETE FROM app_segment_effort WHERE id = ?;
--    - Note: Foreign keys configured with ON DELETE CASCADE for automatic cleanup
--
-- 4. UPDATE SESSION (end workout):
--    - WorkoutRepository.updateSession(TrainingSession session)
--    - Use case: Set ended_at_ms when finishing a workout
--    - SQLite: UPDATE app_training_session SET ended_at_ms = ?, updated_at_ms = ? WHERE id = ?;
--
-- CASCADE BEHAVIOR:
-- - app_effort_observation.effort_id → ON DELETE CASCADE
--   Deleting an effort automatically removes all its observations
-- - app_segment_effort.segment_id → ON DELETE CASCADE
--   Deleting a segment automatically removes all its efforts (and their observations)
--
-- SOFT DELETE ALTERNATIVE:
-- - For production sync/history preservation, consider using deleted_at_ms field
-- - Current implementation uses hard deletes (removes from Maps in MockWorkoutRepository)
-- - Future SqliteWorkoutRepository can implement soft deletes for sync conflict resolution
--
-- SESSION SUMMARY COMPUTATION (Feb 2026):
-- =========================================
-- SessionSummary and ExerciseSummary are computed in-memory models (not persisted tables).
-- Future SqliteWorkoutRepository.computeSessionSummary() should derive these aggregates via:
--
-- Per-exercise (ExerciseSummary):
--   executionOrder  → ROW_NUMBER() OVER (ORDER BY ss.order_index, se.order_index)
--   totalDurationMs → SUM(eo.value_int) * 1000 WHERE eo.metric_id = 'metric-duration'
--                      (for effortKind IN ('timed', 'drill') only)
--   totalRounds     → COUNT(*) FROM app_round_instance WHERE effort_id = se.id
--                      (for effortKind = 'round' only)
--
-- Session-level aggregates (SessionSummary):
--   totalRounds          → SUM of per-effort round counts
--   totalCardioDurationMs → SUM of totalDurationMs for effortKind = 'timed'
--   totalDrillDurationMs  → SUM of totalDurationMs for effortKind = 'drill'
--
-- These aggregates power modality-grouped exercise display on the summary screen.
-- Grouping logic maps effortKind → modality group:
--   'set'   → Strength
--   'timed' → Cardio
--   'round' → Rounds
--   'drill' → Intervals (Isometric)
--
-- EDIT-MODE SNAPSHOT / ROLLBACK (Mar 2026):
-- ==========================================
-- When the user enters edit mode from the summary screen (SessionSummaryScreen →
-- Edit Session → WorkoutSessionScreen(editMode: true)), structural mutations
-- (add/remove exercise via addExerciseToSession/removeExerciseFromSession, and
-- add/remove sets via addEntry/deleteEntry) are persisted to the repository
-- immediately — they bypass the metric _editBuffer.
--
-- If the user presses Back without saving, WorkoutState.restoreSessionSnapshot()
-- rolls back these changes using the following repository primitives (all already
-- implemented in both HiveWorkoutRepository and future SqliteWorkoutRepository):
--
--   deleteEffort(effortId)           → DELETE FROM app_segment_effort WHERE id = ?
--   createEffort(effort)             → INSERT INTO app_segment_effort ...
--   deleteObservationsForEffort(id)  → DELETE FROM app_effort_observation WHERE effort_id = ?
--   createObservation(obs)           → INSERT INTO app_effort_observation ...
--   deleteRoundInstancesForEffort(id)→ DELETE FROM app_round_instance WHERE effort_id = ?
--   createRoundInstance(ri)          → INSERT INTO app_round_instance ...
--   deleteTimedInstancesForEffort(id)→ DELETE FROM app_timed_instance WHERE effort_id = ?
--   createTimedInstance(ti)          → INSERT INTO app_timed_instance ...
--
-- No new repository methods are required. WorkoutState.restoreSessionSnapshot()
-- orchestrates the restore entirely through the above existing abstract interface
-- methods. SqliteWorkoutRepository only needs correct ON DELETE CASCADE foreign
-- keys (already present in schema below) for deleteEffort cascade to work.
--
-- Snapshot is stored in-memory in WorkoutSessionScreen as a SessionEditSnapshot
-- (lib/core/models/session_edit_snapshot.dart). It is discarded on Save;
-- used for rollback on Back without Save.
--
CREATE TABLE app_sport_category (
  id TEXT NOT NULL PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  icon_name TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE app_discipline (
  id TEXT NOT NULL PRIMARY KEY,
  category_id TEXT NOT NULL,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(category_id) REFERENCES app_sport_category(id)
);
CREATE INDEX IF NOT EXISTS IX_discipline_category ON app_discipline(category_id);

CREATE TABLE app_exercise (
  id TEXT NOT NULL PRIMARY KEY,
  owner_user_id TEXT,
  discipline_id TEXT,
  name TEXT NOT NULL,
  description TEXT,
  movement_pattern TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  -- Default duration (seconds) for a single round/period when effortKind == 'round'.
  -- NULL = use app-wide default (WorkoutConstants.defaultRoundDurationSecs = 180).
  -- Set per-sport: e.g. Soccer Match = 2700 (45-min half), Ice Hockey = 1200 (20-min period).
  -- Migration note: ALTER TABLE app_exercise ADD COLUMN default_round_duration_secs INTEGER;
  default_round_duration_secs INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(discipline_id) REFERENCES app_discipline(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS UX_exercise_owner_name ON app_exercise(owner_user_id, name);

CREATE TABLE app_exercise_alias (
  id TEXT NOT NULL PRIMARY KEY,
  exercise_id TEXT NOT NULL,
  alias TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id)
);

CREATE TABLE app_equipment (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE app_exercise_equipment (
  exercise_id TEXT NOT NULL,
  equipment_id TEXT NOT NULL,
  PRIMARY KEY (exercise_id, equipment_id),
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id),
  FOREIGN KEY(equipment_id) REFERENCES app_equipment(id)
);

CREATE TABLE app_training_session (
  id TEXT NOT NULL PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  routine_template_id TEXT,
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  title TEXT,
  note TEXT,
  location_text TEXT,
  modality TEXT, -- Functional training type: 'cardio_endurance', 'resistance_lifting', 'martial_arts', 'isometric_stretching', 'sports', or NULL for 'Free Training'
  intent TEXT,
  perceived_session_rpe REAL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS IX_session_started_at ON app_training_session(started_at_ms);
CREATE INDEX IF NOT EXISTS IX_session_owner_dirty ON app_training_session(owner_user_id, is_dirty);

-- SESSION HISTORY QUERY NOTES (Feb 2026):
-- - WorkoutRepository.getAllSessions():
--   SELECT * FROM app_training_session ORDER BY started_at_ms DESC;
-- - WorkoutRepository.getSessionsByDateRange(fromMs, toMs):
--   SELECT * FROM app_training_session WHERE started_at_ms BETWEEN ? AND ? ORDER BY started_at_ms ASC;
-- - WorkoutRepository.getPersonalRecordCandidates(exerciseId, metricId?):
--   SELECT MAX(COALESCE(o.value_real, o.value_int))
--   FROM app_effort_observation o
--   JOIN app_segment_effort e ON e.id = o.effort_id
--   JOIN app_session_segment s ON s.id = e.segment_id
--   JOIN app_training_session t ON t.id = s.session_id
--   WHERE e.exercise_id = ?
--     AND t.ended_at_ms IS NOT NULL
--     AND (? IS NULL OR o.metric_id = ?);

CREATE TABLE app_session_discipline (
  session_id TEXT NOT NULL,
  discipline_id TEXT NOT NULL,
  is_primary INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (session_id, discipline_id),
  FOREIGN KEY(session_id) REFERENCES app_training_session(id),
  FOREIGN KEY(discipline_id) REFERENCES app_discipline(id)
);

CREATE TABLE app_session_segment (
  id TEXT NOT NULL PRIMARY KEY,
  session_id TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  segment_type TEXT NOT NULL,
  discipline_id TEXT,
  name TEXT,
  note TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(session_id) REFERENCES app_training_session(id),
  FOREIGN KEY(discipline_id) REFERENCES app_discipline(id)
);
CREATE INDEX IF NOT EXISTS IX_segment_session_order ON app_session_segment(session_id, order_index);

CREATE TABLE app_segment_effort (
  id TEXT NOT NULL PRIMARY KEY,
  segment_id TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  effort_kind TEXT NOT NULL,
  exercise_id TEXT,
  note TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(segment_id) REFERENCES app_session_segment(id) ON DELETE CASCADE,
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id)
);
CREATE INDEX IF NOT EXISTS IX_effort_segment_order ON app_segment_effort(segment_id, order_index);
CREATE INDEX IF NOT EXISTS IX_effort_exercise ON app_segment_effort(exercise_id);

-- DELETE NOTES for app_segment_effort:
-- When deleting an effort:
--   1. Set deleted_at_ms for soft delete (preserves history)
--   2. For hard delete, must first delete all app_effort_observation rows for this effort
--   3. OR use ON DELETE CASCADE foreign key on app_effort_observation.effort_id

CREATE TABLE app_unit (
  id TEXT NOT NULL PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  unit_type TEXT,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE app_metric_definition (
  id TEXT NOT NULL PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  data_type TEXT NOT NULL,
  default_unit_id TEXT,
  is_core INTEGER NOT NULL DEFAULT 0,
  applies_to_effort_kind TEXT,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(default_unit_id) REFERENCES app_unit(id)
);

CREATE TABLE app_metric_applicability (
  metric_id TEXT NOT NULL,
  effort_kind TEXT NOT NULL,
  PRIMARY KEY (metric_id, effort_kind),
  FOREIGN KEY(metric_id) REFERENCES app_metric_definition(id)
);

CREATE TABLE app_effort_observation (
  id TEXT NOT NULL PRIMARY KEY,
  effort_id TEXT NOT NULL,
  metric_id TEXT NOT NULL,
  unit_id TEXT,
  value_int INTEGER,
  value_real REAL,
  value_text TEXT,
  value_bool INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  deleted_at_ms INTEGER,
  row_version INTEGER NOT NULL DEFAULT 0,
  is_dirty INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE,
  FOREIGN KEY(metric_id) REFERENCES app_metric_definition(id),
  FOREIGN KEY(unit_id) REFERENCES app_unit(id),
  CHECK (
    (CASE WHEN value_int IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN value_real IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN value_text IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN value_bool IS NOT NULL THEN 1 ELSE 0 END) = 1
  )
);
CREATE INDEX IF NOT EXISTS IX_obs_effort ON app_effort_observation(effort_id);
CREATE INDEX IF NOT EXISTS IX_obs_metric ON app_effort_observation(metric_id);

-- DELETE NOTES for app_effort_observation:
-- Individual observations can be deleted to remove sets/entries from an effort
-- When deleting by effort_id (removing entire exercise from session):
--   DELETE FROM app_effort_observation WHERE effort_id = ?;
--   Then: DELETE FROM app_segment_effort WHERE id = ?;
-- With ON DELETE CASCADE, deleting an effort automatically deletes its observations

CREATE TABLE app_exercise_pr (
  id TEXT NOT NULL PRIMARY KEY,
  exercise_id TEXT NOT NULL,
  metric_id TEXT NOT NULL,
  best_value_real REAL,
  best_value_int INTEGER,
  best_session_id TEXT,
  best_effort_id TEXT,
  computed_at_ms INTEGER NOT NULL,
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id),
  FOREIGN KEY(metric_id) REFERENCES app_metric_definition(id),
  FOREIGN KEY(best_session_id) REFERENCES app_training_session(id),
  FOREIGN KEY(best_effort_id) REFERENCES app_segment_effort(id)
);
CREATE INDEX IF NOT EXISTS IX_exercise_pr_ex_metric ON app_exercise_pr(exercise_id, metric_id);

CREATE TABLE app_training_plan (
  id TEXT NOT NULL PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE app_focus_block (
  id TEXT NOT NULL PRIMARY KEY,
  plan_id TEXT NOT NULL,
  name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  note TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(plan_id) REFERENCES app_training_plan(id)
);

CREATE TABLE app_plan_day (
  id TEXT NOT NULL PRIMARY KEY,
  plan_id TEXT NOT NULL,
  block_id TEXT,
  date TEXT NOT NULL,
  name TEXT,
  note TEXT,
  status TEXT NOT NULL DEFAULT 'planned',
  linked_session_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(plan_id) REFERENCES app_training_plan(id),
  FOREIGN KEY(block_id) REFERENCES app_focus_block(id),
  FOREIGN KEY(linked_session_id) REFERENCES app_training_session(id)
);
CREATE INDEX IF NOT EXISTS IX_plan_day_plan_date ON app_plan_day(plan_id, date);

CREATE TABLE app_workout_template (
  id TEXT NOT NULL PRIMARY KEY,
  owner_user_id TEXT,
  name TEXT NOT NULL,
  description TEXT,
  focus_modality TEXT,
  primary_discipline_id TEXT,
  note TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(primary_discipline_id) REFERENCES app_discipline(id)
);

CREATE TABLE app_template_segment (
  id TEXT NOT NULL PRIMARY KEY,
  template_id TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  segment_type TEXT NOT NULL,
  discipline_id TEXT,
  name TEXT,
  note TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(template_id) REFERENCES app_workout_template(id),
  FOREIGN KEY(discipline_id) REFERENCES app_discipline(id)
);

CREATE TABLE app_template_effort (
  id TEXT NOT NULL PRIMARY KEY,
  template_segment_id TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  effort_kind TEXT NOT NULL,
  modality TEXT, -- Optional per-exercise modality for routine tracking
  exercise_id TEXT,
  note TEXT,
  rest_seconds INTEGER,
  rest_type TEXT,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(template_segment_id) REFERENCES app_template_segment(id) ON DELETE CASCADE,
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id)
);

CREATE TABLE app_template_target (
  id TEXT NOT NULL PRIMARY KEY,
  template_effort_id TEXT NOT NULL,
  metric_id TEXT NOT NULL,
  set_index INTEGER, -- 0-based set index for per-set targets
  unit_id TEXT,
  target_min REAL,
  target_max REAL,
  target_int INTEGER,
  target_text TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(template_effort_id) REFERENCES app_template_effort(id) ON DELETE CASCADE,
  FOREIGN KEY(metric_id) REFERENCES app_metric_definition(id),
  FOREIGN KEY(unit_id) REFERENCES app_unit(id)
);

CREATE TABLE app_plan_day_template (
  plan_day_id TEXT NOT NULL,
  template_id TEXT NOT NULL,
  PRIMARY KEY (plan_day_id, template_id),
  FOREIGN KEY(plan_day_id) REFERENCES app_plan_day(id),
  FOREIGN KEY(template_id) REFERENCES app_workout_template(id)
);

CREATE TABLE app_tag (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE app_session_tag (
  session_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (session_id, tag_id),
  FOREIGN KEY(session_id) REFERENCES app_training_session(id),
  FOREIGN KEY(tag_id) REFERENCES app_tag(id)
);

CREATE TABLE app_exercise_tag (
  exercise_id TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  PRIMARY KEY (exercise_id, tag_id),
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id),
  FOREIGN KEY(tag_id) REFERENCES app_tag(id)
);

-- Exercise capabilities for modality-aware ranking
-- Maps each exercise to a set of capability flags indicating what tracking methods it supports.
-- Used for intelligent exercise recommendation in the exercise picker.
--
-- Capability flags:
--   'time'     - Continuous duration tracking (e.g., running, holding)
--   'distance' - Distance covered (e.g., running, cycling)
--   'reps'     - Repetition counting (e.g., strength exercises)
--   'sets'     - Set grouping (e.g., strength exercises)
--   'load'     - External weight/resistance (e.g., barbell exercises)
--   'hold'     - Isometric hold duration (e.g., planks, wall sits)
--   'rounds'   - Round/period segmentation (e.g., boxing, sports)
--
-- Exercise Ranking Algorithm (in workoutRepository.getExercisesRankedForModality):
-- When a user creates a session with a specific modality (e.g., cardio_endurance), exercises
-- are ranked by their relevance to that modality using a multi-factor scoring system:
--
-- Scoring breakdown (total: 0-100):
--   1. Discipline affinity (0-40): Does the exercise's discipline belong to the modality's category?
--      - E.g., Running discipline (category-cardio) gets 40 points in cardio_endurance modality
--   2. Primary capability match (0-30): What fraction of modality's core capabilities does the exercise support?
--      - E.g., cardio_endurance has primary ['time', 'distance']; exercise with ['time'] gets 15 points
--   3. Secondary capability bonus (0-10): What fraction of modality's bonus capabilities matched?
--   4. Isometric nature bonus (0-15): Special recognition for isometric exercises (hold + time capabilities)
--      - Allows cross-category isometric exercises (e.g., calisthenics planks) to score well in isometric_stretching
--   5. Anti-capability penalty (0 to -20): Does the exercise have capabilities from conflicting modalities?
--      - E.g., 'load' capability in cardio context suggests strength focus, reduces score
--   6. No-overlap penalty (0 or -10): No primary capabilities matched AND different category
--
-- Recommendation threshold: RECOMMENDED_SCORE_THRESHOLD = 50.0 (lib/core/constants/modality_config.dart)
-- Feature: Exercise relevance score is now attached to Exercise objects returned by getExercisesRankedForModality()
-- The score is transient (computed at query time, never persisted) and used for UI partitioning:
--   - "Recommended" section: score >= 50.0
--   - "Other" section: score < 50.0
--
-- Modality configurations (lib/core/constants/modality_config.dart):
--   cardio_endurance:
--     categoryId: category-cardio
--     primaryCapabilities: ['time', 'distance']
--     secondaryCapabilities: ['rounds']
--     antiCapabilities: ['load', 'hold']
--   resistance_lifting:
--     categoryId: category-resistance
--     primaryCapabilities: ['reps', 'sets', 'load']
--     secondaryCapabilities: ['time']
--     antiCapabilities: ['distance', 'rounds', 'hold']
--   martial_arts:
--     categoryId: category-martial-arts
--     primaryCapabilities: ['time', 'rounds']
--     secondaryCapabilities: []
--     antiCapabilities: ['load', 'hold', 'distance']
--   isometric_stretching:
--     categoryId: category-isometric
--     primaryCapabilities: ['hold', 'time']
--     secondaryCapabilities: ['sets']
--     antiCapabilities: ['load', 'distance', 'rounds']
--   sports:
--     categoryId: category-sports
--     primaryCapabilities: ['time', 'rounds']
--     secondaryCapabilities: ['distance']
--     antiCapabilities: ['load', 'hold']
--
-- Example: Barbell Squat with capabilities ['reps', 'sets', 'load', 'time']
--   In resistance_lifting:  Score = 40 (discipline) + 30 (all 3 primary) + 0 (secondary) + 0 (no anti) = 70 → Recommended
--   In cardio_endurance:    Score = 0 (different category) + 0 (no primary) + 0 (no secondary) + -20 (load anti) = -20 → clamp to 0 → Others
--
-- Example: Plank Hold (calisthenics discipline) with capabilities ['hold', 'time', 'sets']
--   In isometric_stretching: Score = 0 (category-resistance ≠ category-isometric) + 30 (primary 'hold', 'time')
--                                     + 10 (secondary 'sets') + 15 (isometric nature bonus) + 0 (no anti) = 55 → Recommended
--   In resistance_lifting:   Score = 0 (different category) + 0 (no primary reps/load) + 0 (no secondary)
--                                     + 0 (no isometric bonus - no 'load' primary) + 0 (no anti) + -10 (no-overlap) = -10 → clamp to 0 → Others
--
-- Isometric Nature Bonus Rationale:
-- Isometric exercises (plank, dead hang, wall sit, etc.) are bodyweight/calisthenics movements, not
-- stretching exercises. However, they share the isometric nature (hold + time capabilities) with the
-- isometric_stretching modality. The +15 point bonus recognizes this cross-category affinity, allowing
-- calisthenics isometric holds to appear in "Recommended" when creating a workout in isometric_stretching mode.
--
-- Note: The 'time' capability is present on almost all exercises because virtually anything can be
-- done for duration. This is why the isometric nature bonus specifically checks for BOTH 'hold' AND 'time'
-- and only applies in modalities that list 'hold' as a primary capability (currently: isometric_stretching).
CREATE TABLE app_exercise_capability (
  exercise_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  PRIMARY KEY (exercise_id, capability),
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id)
);
CREATE INDEX IF NOT EXISTS IX_exercise_capability_cap ON app_exercise_capability(capability);

-- ROUND INSTANCES (Feb 2026 Refactor — updated with explicit state model):
-- ==========================================
-- Replaces the metric-rounds + metric-round-duration observation pair pattern for round
-- (effortKind == 'round') exercises. Each row is a single timed round of one effort.
--
-- Lifecycle / state transitions:
--   1. Created on addRound():
--        state = 'notStarted', started_at_ms = 0, total_paused_duration_ms = 0
--   2. Started on startRound():
--        state = 'active', started_at_ms = wall-clock epoch ms
--   3. Paused on pauseRound():
--        state = 'paused', paused_at_ms = wall-clock epoch ms
--   4. Resumed on resumeRound():
--        state = 'active', total_paused_duration_ms += (now - paused_at_ms), paused_at_ms = NULL
--   5. Completed naturally (countdown → 0):
--        state = 'finished', completed = 1,
--        actual_duration_secs = planned_duration_secs,
--        finished_at_ms = started_at_ms + (planned_duration_secs * 1000) + total_paused_duration_ms
--   6. Ended early (manual log) or session close:
--        state = 'finished', completed = 0,
--        actual_duration_secs = elapsed (now - started_at_ms - total_paused_duration_ms) / 1000,
--        finished_at_ms = now
--
-- Allowed state transitions:
--   notStarted → active
--   active     → paused | finished
--   paused     → active | finished
--   finished   → (none — terminal)
--
-- Rules:
--   - completed = 1 ONLY when countdown naturally reaches zero (never inferred from duration)
--   - elapsed = now - started_at_ms - total_paused_duration_ms  (always derived from timestamps)
--   - actual_duration_secs stores final elapsed; countdown is UI-only presentation
--   - Partial rounds are never discarded
--   - finished is terminal — no further mutations allowed
--   - ON DELETE CASCADE ensures automatic cleanup when the parent effort is deleted
--
-- Backward compatibility:
--   Existing rows without state/paused_at_ms/total_paused_duration_ms columns use
--   SQLite column defaults ('notStarted' / NULL / 0). The Dart fromMap() infers
--   state from finished_at_ms and started_at_ms when the state column is missing.
--
-- SqliteWorkoutRepository implementation notes:
--   getRoundInstances(effortId):
--     SELECT * FROM app_round_instance WHERE effort_id = ? ORDER BY round_index ASC;
--   createRoundInstance(instance):
--     INSERT INTO app_round_instance VALUES (...);
--   updateRoundInstance(instance):
--     UPDATE app_round_instance SET
--       planned_duration_secs=?, actual_duration_secs=?, started_at_ms=?,
--       finished_at_ms=?, completed=?, state=?, paused_at_ms=?,
--       total_paused_duration_ms=?, updated_at_ms=?
--     WHERE id = ?;
--   deleteRoundInstance(id):
--     DELETE FROM app_round_instance WHERE id = ?;
--   deleteRoundInstancesForEffort(effortId):
--     DELETE FROM app_round_instance WHERE effort_id = ?;
--
-- Migration (for existing production databases — add new columns with safe defaults):
--   ALTER TABLE app_round_instance ADD COLUMN state TEXT NOT NULL DEFAULT 'notStarted';
--   ALTER TABLE app_round_instance ADD COLUMN paused_at_ms INTEGER;
--   ALTER TABLE app_round_instance ADD COLUMN total_paused_duration_ms INTEGER NOT NULL DEFAULT 0;
--   -- Back-fill state from existing fields:
--   UPDATE app_round_instance SET state = 'finished' WHERE finished_at_ms IS NOT NULL;
--   UPDATE app_round_instance SET state = 'active'
--     WHERE finished_at_ms IS NULL AND started_at_ms > 0;
CREATE TABLE app_round_instance (
  id TEXT NOT NULL PRIMARY KEY,
  effort_id TEXT NOT NULL,
  round_index INTEGER NOT NULL,                        -- 0-based round number within the effort
  planned_duration_secs INTEGER NOT NULL DEFAULT 180,  -- User-configurable countdown target
  actual_duration_secs INTEGER NOT NULL DEFAULT 0,     -- Final elapsed secs; 0 while in-progress
  started_at_ms INTEGER NOT NULL DEFAULT 0,            -- 0 = not yet started
  finished_at_ms INTEGER,                              -- NULL = not finished
  completed INTEGER NOT NULL DEFAULT 0,                -- 1 = countdown reached zero naturally
  state TEXT NOT NULL DEFAULT 'notStarted',            -- RoundState: notStarted|active|paused|finished
  paused_at_ms INTEGER,                                -- Wall-clock ms when paused; NULL if not paused
  total_paused_duration_ms INTEGER NOT NULL DEFAULT 0, -- Accumulated pause time in ms
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS IX_round_instance_effort ON app_round_instance(effort_id, round_index);

-- TIMED INSTANCES (Feb 2026)
-- ==========================
-- Stores the full lifecycle of each timed entry for effortKind == 'timed' or 'drill' efforts.
-- Replaces the old duration EffortObservation for these effort kinds.
-- Companion metrics (distance for timed, extra weight for drill) remain as EffortObservation records.
--
-- Design mirrors app_round_instance but with key differences:
--   - entry_index instead of round_index (same semantics, different naming)
--   - target_duration_secs instead of planned_duration_secs (0 = open-ended, no alert)
--   - No completed flag (timed/drill count UP; no natural completion concept)
--   - elapsed counts up without upper clamp (rounds count down)
--
-- Lifecycle:
--   1. Created:   state = 'notStarted', started_at_ms = 0
--   2. Started:   state = 'active', started_at_ms = now
--   3. Paused:    state = 'paused', paused_at_ms = now
--   4. Resumed:   state = 'active', total_paused_duration_ms += (now - paused_at_ms), paused_at_ms = NULL
--   5. Finished:  state = 'finished', actual_duration_secs = derived from timestamps, finished_at_ms = now
--   6. Session close: same as finish (via _persistActiveTimedEntries safety net)
--
-- Rules:
--   - finished is terminal — no further mutations allowed
--   - ON DELETE CASCADE ensures automatic cleanup when the parent effort is deleted
--
-- SqliteWorkoutRepository implementation notes:
--   getTimedInstances(effortId):
--     SELECT * FROM app_timed_instance WHERE effort_id = ? ORDER BY entry_index ASC;
--   createTimedInstance(instance):
--     INSERT INTO app_timed_instance VALUES (...);
--   updateTimedInstance(instance):
--     UPDATE app_timed_instance SET
--       target_duration_secs=?, actual_duration_secs=?, started_at_ms=?,
--       finished_at_ms=?, state=?, paused_at_ms=?,
--       total_paused_duration_ms=?, updated_at_ms=?
--     WHERE id = ?;
--   deleteTimedInstance(id):
--     DELETE FROM app_timed_instance WHERE id = ?;
--   deleteTimedInstancesForEffort(effortId):
--     DELETE FROM app_timed_instance WHERE effort_id = ?;
CREATE TABLE app_timed_instance (
  id TEXT NOT NULL PRIMARY KEY,
  effort_id TEXT NOT NULL,
  entry_index INTEGER NOT NULL,                        -- 0-based entry number within the effort
  target_duration_secs INTEGER NOT NULL DEFAULT 0,     -- User-set target; 0 = open-ended (no alert)
  actual_duration_secs INTEGER NOT NULL DEFAULT 0,     -- Final elapsed secs; 0 while in-progress
  started_at_ms INTEGER NOT NULL DEFAULT 0,            -- 0 = not yet started
  finished_at_ms INTEGER,                              -- NULL = not finished
  state TEXT NOT NULL DEFAULT 'notStarted',            -- TimedState: notStarted|active|paused|finished
  paused_at_ms INTEGER,                                -- Wall-clock ms when paused; NULL if not paused
  total_paused_duration_ms INTEGER NOT NULL DEFAULT 0, -- Accumulated pause time in ms
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS IX_timed_instance_effort ON app_timed_instance(effort_id, entry_index);

CREATE TABLE app_muscle_group (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE app_exercise_muscle_group (
  exercise_id TEXT NOT NULL,
  muscle_group_id TEXT NOT NULL,
  is_primary INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (exercise_id, muscle_group_id),
  FOREIGN KEY(exercise_id) REFERENCES app_exercise(id),
  FOREIGN KEY(muscle_group_id) REFERENCES app_muscle_group(id)
);
-- SqliteWorkoutRepository.setExerciseMuscleGroups(exerciseId, ids)
-- should replace existing rows for exercise_id and insert the new set.

CREATE TABLE app_sync_event (
  event_id TEXT NOT NULL PRIMARY KEY,
  device_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  op TEXT NOT NULL,
  payload TEXT NOT NULL,
  server_sequence INTEGER,
  pushed_at_ms INTEGER,
  applied_at_ms INTEGER
);
CREATE INDEX IF NOT EXISTS IX_sync_event_user_seq ON app_sync_event(user_id, server_sequence);
CREATE INDEX IF NOT EXISTS IX_sync_event_user_device ON app_sync_event(user_id, device_id);

CREATE TABLE app_sync_op_local_example (
  id TEXT NOT NULL PRIMARY KEY,
  device_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  op_time_ms INTEGER NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  op TEXT NOT NULL,
  payload TEXT NOT NULL,
  pushed INTEGER NOT NULL DEFAULT 0
);

COMMIT;
