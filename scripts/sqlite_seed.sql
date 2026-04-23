PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

-- Calendar placeholder policy (Mar 2026 cleanup):
--   Do not seed demo rows into app_planned_session or app_training_period.
--   These tables must start empty and be populated only by user actions.

-- ============================================================================
-- UNIFIED SPORTS MODALITY (Feb 2026 Refactor)
-- ============================================================================
-- The 'sports' modality covers all sports disciplines under a single category-sports.
-- Home screen shows a unified "Sports" tile (Sports category).
-- 
-- MODALITY FEATURE SUPPORT:
-- - Primary metric: time (round/period duration)
-- - Secondary metrics: rounds (periods, halves, quarters, or rounds)
-- - Optional metrics: distance, rpe
-- - Default input type: segment_timer (for period/round-based tracking)
-- - Structure: segmented
-- - Effort kind: round
--
-- EXERCISE RANKING FOR SPORTS:
-- When SqliteWorkoutRepository.getExercisesRankedForModality('sports',...) is called:
-- 1. Filter: exercises whose discipline.category_id = 'category-sports'
-- 2. Score: by capability matchagains ModalityConfig(sports).primaryCapabilities = ['time', 'rounds']
-- 3. Return: sorted by relevance score (capabilities-based affinity)
--
-- CATEGORIES INVOLVED:
--   category-sports: Boxing, BJJ, Muay Thai, soccer, basketball, tennis, team sports
--
-- See lib/core/constants/modality.dart Modality.modalityToCategoryIds mapping:
--   sports: ['category-sports']
--
-- ============================================================================
-- EXERCISE CAPABILITY SEEDING NOTES
-- ============================================================================
-- When implementing SqliteWorkoutRepository.getExercisesRankedForModality(),
-- ensure exercise capabilities are properly seeded into app_exercise_capability table.
--
-- The capability flags define what tracking methods each exercise supports:
--   'time'     - Continuous duration (e.g., running, holding)
--   'distance' - Distance covered (e.g., running, cycling)
--   'reps'     - Repetition counting (e.g., barbell exercises)
--   'sets'     - Set grouping (e.g., bodybuilding)
--   'load'     - External weight/resistance (e.g., barbell exercises)
--   'hold'     - Isometric hold duration (e.g., planks, yoga)
--   'rounds'   - Round/period segmentation (e.g., boxing, sports)
--
-- Running exercises (category-cardio):
--   - 'exercise-easy-run', 'exercise-long-run', etc.: ['time', 'distance']
--   - 'exercise-interval-run', 'exercise-hill-repeats': ['time', 'distance', 'rounds']
--   (See lib/mock/seed_data.dart exerciseCapabilityRelationships for complete list)
--
-- Bodybuilding exercises (category-resistance):
--   - 'exercise-barbell-squat', 'exercise-bench-press', etc.: ['reps', 'sets', 'load', 'time']
--   (Can be done for time in cardio context, but primarily reps/sets/load)
--
-- Boxing exercises (category-sports):
--   - 'exercise-heavy-bag-rounds', 'exercise-sparring', etc.: ['time', 'rounds']
--
-- Calisthenics/Isometric (category-calisthenics → category-isometric):
--   - 'exercise-plank-hold', 'exercise-wall-sit', etc.: ['hold', 'time', 'sets']
--
-- These seed values are in lib/mock/seed_data.dart as exerciseCapabilityRelationships Map.
-- When migrating to SQLite, insert these into app_exercise_capability via DELETE+INSERT
-- or idempotent ON CONFLICT DO UPDATE patterns.

-- Units (idempotent)
INSERT OR IGNORE INTO app_unit (id, key, name, unit_type, created_at_ms)
VALUES
  ('unit-kg', 'kg', 'Kilograms', 'weight', (strftime('%s','now') * 1000)),
  ('unit-lbs', 'lbs', 'Pounds', 'weight', (strftime('%s','now') * 1000)),
  ('unit-cm', 'cm', 'Centimeters', 'length', (strftime('%s','now') * 1000)),
  ('unit-pct', 'pct', 'Percent', 'ratio', (strftime('%s','now') * 1000)),
  ('unit-sec', 'sec', 'Seconds', 'time', (strftime('%s','now') * 1000)),
  ('unit-min', 'min', 'Minutes', 'time', (strftime('%s','now') * 1000)),
  ('unit-m', 'm', 'Meters', 'distance', (strftime('%s','now') * 1000)),
  ('unit-km', 'km', 'Kilometers', 'distance', (strftime('%s','now') * 1000)),
  ('unit-mi', 'mi', 'Miles', 'distance', (strftime('%s','now') * 1000)),
  ('unit-cal', 'cal', 'Calories', 'energy', (strftime('%s','now') * 1000)),
  ('unit-bpm', 'bpm', 'Beats per Minute', 'heart_rate', (strftime('%s','now') * 1000)),
  ('unit-reps', 'reps', 'Repetitions', 'count', (strftime('%s','now') * 1000)),
  ('unit-rounds', 'rounds', 'Rounds', 'count', (strftime('%s','now') * 1000));

-- Metric definitions (idempotent)
INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-reps', 'reps', 'Repetitions', 'int', 'unit-reps', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-reps');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-weight', 'weight', 'Weight', 'real', 'unit-kg', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-weight');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-rpe', 'rpe', 'RPE (Rate of Perceived Exertion)', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-rpe');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-duration', 'duration', 'Duration', 'int', 'unit-sec', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-duration');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-rest', 'rest', 'Rest Time', 'int', 'unit-sec', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-rest');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-distance', 'distance', 'Distance', 'real', 'unit-m', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-distance');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-pace', 'pace', 'Pace (min/km)', 'real', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-pace');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-rounds', 'rounds', 'Rounds', 'int', 'unit-rounds', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-rounds');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-round-duration', 'round_duration', 'Round Duration', 'int', 'unit-sec', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-round-duration');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-score', 'score', 'Score', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-score');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-quality', 'quality', 'Quality Rating', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-quality');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-heart-rate', 'heart_rate', 'Heart Rate', 'int', 'unit-bpm', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-heart-rate');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT 'metric-extra-weight', 'extra-weight', 'Extra Weight', 'real', 'unit-kg', 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE id='metric-extra-weight');

-- Metric applicability (maps metrics to effort kinds)
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'set' FROM app_metric_definition m WHERE m.key = 'reps';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'set' FROM app_metric_definition m WHERE m.key = 'weight';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'set' FROM app_metric_definition m WHERE m.key = 'rpe';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'set' FROM app_metric_definition m WHERE m.key = 'rest';

INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'timed' FROM app_metric_definition m WHERE m.key = 'duration';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'timed' FROM app_metric_definition m WHERE m.key = 'distance';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'timed' FROM app_metric_definition m WHERE m.key = 'heart_rate';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'timed' FROM app_metric_definition m WHERE m.key = 'rpe';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'timed' FROM app_metric_definition m WHERE m.key = 'extra-weight';

INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'interval' FROM app_metric_definition m WHERE m.key = 'distance';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'interval' FROM app_metric_definition m WHERE m.key = 'duration';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'interval' FROM app_metric_definition m WHERE m.key = 'pace';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'interval' FROM app_metric_definition m WHERE m.key = 'rest';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'interval' FROM app_metric_definition m WHERE m.key = 'heart_rate';

INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'round' FROM app_metric_definition m WHERE m.key = 'rounds';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'round' FROM app_metric_definition m WHERE m.key = 'round_duration';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'round' FROM app_metric_definition m WHERE m.key = 'rpe';

INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'amrap' FROM app_metric_definition m WHERE m.key = 'score';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'amrap' FROM app_metric_definition m WHERE m.key = 'duration';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'amrap' FROM app_metric_definition m WHERE m.key = 'rpe';

INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'drill' FROM app_metric_definition m WHERE m.key = 'duration';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'drill' FROM app_metric_definition m WHERE m.key = 'reps';
INSERT OR IGNORE INTO app_metric_applicability (metric_id, effort_kind)
SELECT m.id, 'drill' FROM app_metric_definition m WHERE m.key = 'quality';

-- Categories (aligned with 5 home screen modality tiles after Feb 2026 restructure)
-- Note: Keys match Modality constants in lib/core/constants/modality.dart
-- NOTE: sports modality now uses a single 'sports' category for all sports disciplines
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'cardio_endurance', 'Cardio / Endurance', 'Running, cycling, swimming, rowing', 'directions_run', 1, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'resistance_lifting', 'Resistance / Lifting', 'Weightlifting, bodybuilding, powerlifting, strength training', 'fitness_center', 2, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'isometric_stretching', 'Isometric / Stretching', 'Yoga, static holds, stretching, flexibility work', 'self_improvement', 4, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
-- Sports category (includes martial arts disciplines and field/court sports)
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'sports', 'Sports', 'Boxing, BJJ, Muay Thai, wrestling, soccer, basketball, tennis, team sports', 'sports_soccer', 5, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
-- Legacy category (kept for backward compatibility)
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'recovery_rehab', 'Recovery / Rehab', 'Active recovery, physical therapy, rehab', 'spa', 10, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));

-- Disciplines (using category lookup)
INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'running', 'Running', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='running');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'cycling', 'Cycling', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='cycling');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'swimming', 'Swimming', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='swimming');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'rowing', 'Rowing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='rowing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'walking', 'Walking & Hiking', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='walking');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'machine_cardio', 'Machine Cardio', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio_endurance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='machine_cardio');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'boxing', 'Boxing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='boxing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bjj', 'Brazilian Jiu-Jitsu', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bjj');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'muay_thai', 'Muay Thai', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='muay_thai');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'powerlifting', 'Powerlifting', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='resistance_lifting' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='powerlifting');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bodybuilding', 'Bodybuilding', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='resistance_lifting' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bodybuilding');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'weightlifting', 'Olympic Weightlifting', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='resistance_lifting' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='weightlifting');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'calisthenics', 'Calisthenics', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='resistance_lifting' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='calisthenics');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'soccer', 'Soccer', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='soccer');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'basketball', 'Basketball', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='basketball');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'yoga', 'Yoga', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='isometric_stretching' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='yoga');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'stretching', 'Stretching', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='isometric_stretching' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='stretching');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'active_recovery', 'Active Recovery', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='recovery_rehab' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='active_recovery');

-- Equipment
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Barbell', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Dumbbell', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Kettlebell', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Resistance Band', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Pull-up Bar', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Treadmill', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Heavy Bag', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Body Weight', (strftime('%s','now') * 1000));

-- Tags
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Legs', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Push', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Pull', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Core', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Isometric', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Stretching', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_tag (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Full Body', (strftime('%s','now') * 1000));

-- Muscle Groups
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Chest', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Back', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Shoulders', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Biceps', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Triceps', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Quadriceps', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Hamstrings', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Glutes', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_muscle_group (id, name, created_at_ms) VALUES (lower(hex(randomblob(16))), 'Core', (strftime('%s','now') * 1000));

-- Default shared exercises (owner_user_id IS NULL)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Easy Run' AS name, 'A low-intensity, conversational-pace run that forms the backbone of any endurance program. Most of your weekly running volume should live here.' AS description UNION ALL
  SELECT 'Long Run', 'The weekly endurance-builder. A sustained easy-to-moderate effort longer than your other runs, designed to develop aerobic capacity and fatigue resistance.' UNION ALL
  SELECT 'Tempo Run', 'A sustained effort at lactate threshold pace — "comfortably hard." Trains the body to clear lactate efficiently and raises the speed you can hold without blowing up.' UNION ALL
  SELECT 'Interval Run', 'Repeated hard efforts with recovery between, performed above threshold pace. Builds VO2 max and raw speed.' UNION ALL
  SELECT 'Hill Repeats', 'Repeated uphill efforts with recovery on the way back down. Builds leg strength, running economy, and VO2 max with reduced impact compared to flat intervals.' UNION ALL
  SELECT 'Fartlek', 'Swedish for "speed play" — an unstructured run mixing surges of fast running with easy sections, played by feel rather than a stopwatch.' UNION ALL
  SELECT 'Recovery Run', 'A very slow, short run performed the day after a hard session. Promotes blood flow and aids recovery without adding meaningful training stress.' UNION ALL
  SELECT 'Track Repeats', 'Measured interval efforts on a running track, typically 400m to 1600m repeats. Precise pace control makes this a favorite for serious training.' UNION ALL
  SELECT 'Progression Run', 'A run that starts easy and gradually increases pace, finishing at or near tempo effort. Teaches pacing discipline and builds late-run strength.' UNION ALL
  SELECT 'Time Trial', 'An all-out effort over a fixed distance or duration. A benchmark for current fitness and a useful hard day when you need to measure yourself.'
) e
WHERE d.key='running'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Update how_to_steps (cues) for existing running exercises
UPDATE app_exercise SET
  how_to_steps = json_array(
    'Run at a pace where you could hold a full conversation — if you can only speak in short phrases, you''re going too hard.',
    'Heart rate should sit in Zone 2, roughly 65–75% of max.',
    'Effort should feel like a 4 out of 10.',
    'Don''t chase pace — let it come to you. If you feel fast on an easy day, you''re doing it wrong.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Easy Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Start at a conversational pace and hold it — don''t progress into tempo territory.',
    'Fuel and hydrate during anything over 90 minutes.',
    'The goal is time on your feet, not pace. Going too hard here costs you the rest of the week.',
    'Expect to feel fatigued by the end — that''s the point.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Long Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Effort is 7–8 out of 10: you can speak in short phrases but not hold a conversation.',
    'Pace is roughly what you could hold for a 1-hour race.',
    'Include a proper 10–15 minute warm-up and cool-down — tempo efforts start cold at your peril.',
    'Don''t start too fast. Tempo is about sustained discomfort, not early-rep hero pace.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Tempo Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Work intervals are hard — 8–9 out of 10 effort, too hard to speak more than a word or two.',
    'Recovery should be easy jogging or walking, not standing still.',
    'Every rep should be roughly the same pace — if the last rep is way slower, you started too hot.',
    'Always warm up thoroughly before the first hard rep.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Interval Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Pick a hill with a 4–8% grade — steep enough to feel it, not so steep you can''t run.',
    'Push hard on the way up, at 85–90% effort.',
    'Recover fully on the walk or jog back down.',
    'Focus on form: short strides, driving knees, arms pumping.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Hill Repeats' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Pick landmarks on the fly: "hard to that lamppost, easy to the next tree."',
    'Vary the surges — some short and fast, some longer and moderate.',
    'Recovery between surges is easy running, not walking.',
    'The point is play and variation, not hitting target paces.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Fartlek' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Slower than your easy pace — embarrassingly slow if it needs to be.',
    'Keep it short: 20–40 minutes.',
    'If you finish feeling tired, you went too hard. This is for feeling better, not worse.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Recovery Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Know your target pace before you step on the track — winging it defeats the purpose.',
    'Run the first rep slightly conservative, negative-split the set if you can.',
    'Recovery is usually a standing rest or easy lap depending on the session.',
    'Stay in lane 1 unless other runners are working — and check before stepping on.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Track Repeats' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Start truly easy — Zone 2, conversational.',
    'Build pace in thirds or halves, not in one sudden shift.',
    'The final segment should feel like a tempo effort, not a sprint.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Progression Run' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  how_to_steps = json_array(
    'Warm up thoroughly — 15–20 minutes including a few strides at target pace.',
    'Pace evenly. Most time trials are lost in the first mile.',
    'Don''t do these too often — once every 4–6 weeks is plenty.'
  ),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Time Trial' AND owner_user_id IS NULL;

-- ============================================================================
-- CARDIO / ENDURANCE EXERCISE LIBRARY (Phase 4 — 38 exercises)
-- ============================================================================

-- Running (3 new)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Sprint Intervals' AS name,
         'Short, all-out efforts of 10–30 seconds with long recovery between. Develops raw top-end speed and anaerobic power.' AS description,
         json_array('Every rep is maximum effort — if rep 4 is as fast as rep 1, recovery is long enough.','Recovery between reps is 2–4 minutes of walking or very easy jogging.','Always warm up thoroughly — cold sprints injure hamstrings.','Quality over quantity. When pace drops, end the session.') AS cues
  UNION ALL
  SELECT 'Strides',
         'Short accelerations of 80–100 meters at roughly 5K race pace, performed after easy runs. Maintains neuromuscular sharpness without adding training stress.',
         json_array('Build pace smoothly over the first 20 meters, hold it, then decelerate.','Focus on relaxed form — shoulders down, tall posture, quick feet.','Full recovery between each stride — walk back, don''t rush.','4–8 strides is plenty. This is sharpening, not a workout.')
  UNION ALL
  SELECT 'Trail Run',
         'An easy-to-moderate effort run on dirt, gravel, or technical singletrack. Lower impact than road running, with added demand on ankle stability and footing awareness.',
         json_array('Pace by effort, not by watch — hills and technical sections will mess with your numbers.','Shorten your stride on descents and technical ground.','Look ahead, not at your feet, on uneven terrain.')
  UNION ALL
  SELECT 'Treadmill Run',
         'Any run performed on a treadmill. Useful when weather or time doesn''t cooperate, and lets you control pace and incline precisely.',
         json_array('Set a 1% incline to approximate outdoor effort.','Pick the session type first — easy, tempo, intervals — and set the pace accordingly.','Don''t grip the rails. If the pace is too hard, slow it down.')
) e
WHERE d.key='running'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- Cycling (9: 8 + Stationary Bike cross-training)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Zone 2 Ride' AS name,
         'A long, easy-to-moderate ride at aerobic endurance pace. The cycling equivalent of the easy run — the foundation of cycling fitness.' AS description,
         json_array('Ride at a conversational pace — you should be able to speak in full sentences.','Target roughly 65–75% of max heart rate or 55–75% of FTP if you ride with a power meter.','Duration is the point, not intensity. 60–180 minutes is typical.','Resist the urge to chase riders or Strava segments. Keep it easy.') AS cues
  UNION ALL
  SELECT 'Tempo Ride',
         'A sustained ride at moderately hard intensity, above endurance but below threshold. Builds aerobic capacity and muscular endurance.',
         json_array('Effort is 7 out of 10 — comfortably uncomfortable.','Target roughly 76–90% of FTP or 80–90% of threshold heart rate.','Typical duration is 20–60 minutes of continuous tempo work, or broken into blocks.','You should be breathing heavily but not gasping.')
  UNION ALL
  SELECT 'Sweet Spot Intervals',
         'Intervals at 88–94% of FTP — the maximum intensity you can sustain for long durations. High training stimulus with manageable recovery cost.',
         json_array('Work intervals are typically 10–20 minutes long.','Focus on smooth, steady power — not surging and fading.','Rest intervals are short: 3–5 minutes of easy pedaling.','Common session: 3 x 15 minutes at 90% FTP with 5-minute recovery.')
  UNION ALL
  SELECT 'Threshold Intervals',
         'Intervals held at or near FTP — the hardest intensity sustainable for about an hour. Raises your ceiling for sustained effort.',
         json_array('Work intervals are typically 8–20 minutes at 95–105% of FTP.','These hurt. Rate of perceived exertion is 8–9 out of 10.','Rest intervals are 4–8 minutes of easy pedaling.','Don''t start too hard — negative-split the intervals if anything.')
  UNION ALL
  SELECT 'VO2 Max Intervals',
         'Short, very hard efforts above threshold — 3 to 5 minutes of suffering per rep. Develops maximum aerobic capacity and raises ceiling for hard efforts.',
         json_array('Work intervals are typically 3–5 minutes at 110–120% FTP.','Effort is 9 out of 10 — you can count reps, not sentences.','Recovery is equal to or slightly shorter than the work interval.','These sessions are brutal. Limit to once per week in-season.')
  UNION ALL
  SELECT 'Cycling Sprint Intervals',
         'All-out sprints of 10–30 seconds with long recovery. Builds peak power and anaerobic capacity.',
         json_array('Each sprint is maximum effort — 100% gas.','Get out of the saddle and attack the start of the sprint.','Recovery is 3–5 minutes of easy spinning.','Stop the session when peak power drops significantly.')
  UNION ALL
  SELECT 'Long Ride',
         'The cyclist''s long run — an extended ride at mostly easy intensity, occasionally spicier. Builds aerobic durability and tests fueling and pacing.',
         json_array('Keep the bulk of the ride in Zone 2.','Fuel every 30–45 minutes — 60–90g of carbs per hour for rides over 2 hours.','Don''t try to "make it a workout." Consistency of easy riding is what builds durability.','Plan your route — bonking 40km from home is a long walk.')
  UNION ALL
  SELECT 'Recovery Ride',
         'A very easy spin after a hard session or race. Promotes blood flow and active recovery without adding training stress.',
         json_array('Effort is 3 out of 10 or lower.','Keep it short: 30–60 minutes is plenty.','Stay in the small ring and let the legs turn over.','If it feels like a workout, ease off further.')
  UNION ALL
  SELECT 'Stationary Bike',
         'Any indoor cycling effort on a stationary, spin, or smart bike. Zero traffic, zero weather, full pace control.',
         json_array('Set up position first — saddle height, reach, handlebar — before starting.','Pick the session type (Zone 2, tempo, intervals) and hold to it.','Indoor cycling runs hot. Fans and hydration matter more than outdoors.')
) e
WHERE d.key='cycling'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- Rowing (5)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Steady State Row' AS name,
         'A sustained, moderate-intensity erg session at aerobic pace. The foundation of rowing training and an efficient full-body aerobic workout.' AS description,
         json_array('Target a stroke rate of 20–24 strokes per minute.','Effort is conversational — 5 or 6 out of 10.','Focus on a long, smooth stroke rather than a fast, choppy one.','Typical duration is 30–60 minutes.') AS cues
  UNION ALL
  SELECT 'Rowing Intervals',
         'Repeated hard erg efforts with rest between. Builds power and anaerobic capacity for rowing and general conditioning.',
         json_array('Common intervals: 500m, 750m, 1000m repeats.','Work intervals should be paced to match — don''t blow up on rep 1.','Stroke rate climbs with intensity: typically 28–34 for intervals.','Rest is typically equal to or slightly longer than work time.')
  UNION ALL
  SELECT '2K Test',
         'The rowing benchmark — an all-out 2000-meter effort. The gold-standard test of rowing fitness and a brutal measure of anaerobic capacity.',
         json_array('Warm up thoroughly — 15–20 minutes including pace work.','Have a plan: target split, stroke rate per segment, and when you''ll push.','The third 500 is always the hardest. Hold form through it.','Don''t do these often — once every 8–12 weeks is plenty.')
  UNION ALL
  SELECT 'Long Row',
         'An extended low-intensity erg session, typically 60–90 minutes. Builds aerobic base with minimal impact.',
         json_array('Stroke rate stays low: 18–22.','Focus on relaxed, efficient form — fatigue will expose technique breakdowns.','Break up the monotony with podcasts, audiobooks, or film.')
  UNION ALL
  SELECT 'Power Strokes',
         'Short bursts of maximum-power rowing within a longer steady piece. Trains peak force production without full interval structure.',
         json_array('Typical structure: 10 hard strokes every minute during a 10–20 minute piece.','Hard strokes are full-power, same stroke rate — not faster, harder.','Return to steady-state pace immediately after each set of power strokes.')
) e
WHERE d.key='rowing'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- Swimming (6: 5 + Swim Kick Set cross-training)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Easy Swim' AS name,
         'A low-intensity continuous swim focused on technique and aerobic base. The swimming equivalent of an easy run.' AS description,
         json_array('Focus on feel and stroke mechanics, not pace.','Breathing should be relaxed and controlled.','Typical duration is 20–45 minutes, continuous or with short rest.') AS cues
  UNION ALL
  SELECT 'Swim Intervals',
         'Repeated pool lengths or sets at hard pace with structured rest. The bread and butter of swim training.',
         json_array('Common sets: 10 x 100m on a fixed send-off time.','Pace is aggressive but sustainable across the whole set.','Rest is determined by the send-off — faster swims buy more rest.','Technique should hold even as fatigue builds.')
  UNION ALL
  SELECT 'Swim Sprints',
         'All-out short efforts, typically 25m to 100m, with long recovery. Builds raw speed and anaerobic capacity.',
         json_array('Each sprint is maximum effort from push-off.','Rest 1–3 minutes between sprints — full recovery is the point.','Quality over quantity. 6–10 sprints is plenty.')
  UNION ALL
  SELECT 'Long Swim',
         'An extended continuous swim, typically 1500m or longer. Builds aerobic capacity and mental toughness in the water.',
         json_array('Pace easier than you think — the back half is the test.','Sight-breathing if you''re training for open water.','Break the distance into chunks mentally: halves, quarters, or lap counts.')
  UNION ALL
  SELECT 'Drill Set',
         'A technique-focused set using single-arm, catch-up, fist drill, or kickboard work. Improves stroke mechanics without high aerobic demand.',
         json_array('Slow down and focus — drill work is about quality, not effort.','Mix drills: single-arm, catch-up, fist, fingertip drag, 6-3-6.','Use a kickboard or pull buoy to isolate the upper or lower body.')
  UNION ALL
  SELECT 'Swim Kick Set',
         'Kickboard-based swimming focused entirely on leg work. Builds leg endurance and kick power without upper-body recovery issues.',
         json_array('Kick from the hips, not the knees.','Keep the kick narrow and steady — big splashing kicks waste energy.','Typical set: 4–8 x 50m or 100m kick with short rest.')
) e
WHERE d.key='swimming'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- Walking & Hiking (4)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Brisk Walk' AS name,
         'A fast-paced walk that elevates heart rate without the impact of running. An underrated foundation for any fitness program.' AS description,
         json_array('Pace is one where holding a conversation is possible but not effortless.','Swing your arms naturally and stay tall.','Aim for 30–60 minutes.') AS cues
  UNION ALL
  SELECT 'Incline Walk',
         'A sustained walk on a treadmill incline or uphill outdoors. Builds aerobic fitness and leg strength with minimal impact — great cross-training for runners.',
         json_array('Incline is 8–15% on a treadmill, or a meaningful uphill gradient outdoors.','Don''t hold the rails on a treadmill — it defeats the purpose.','Heart rate should climb into low Zone 2 or 3.','Typical duration is 30–60 minutes.')
  UNION ALL
  SELECT 'Rucking',
         'Walking with a weighted pack on the back. A low-impact strength-and-cardio combination used by military, hikers, and anyone who wants to build work capacity without running.',
         json_array('Start with 10–15% of your bodyweight in the pack.','Wear shoes with good support — rucking exposes weak footwear fast.','Stay tall and don''t hunch under the load.','Build duration before adding weight.')
  UNION ALL
  SELECT 'Hike',
         'An extended outdoor walk over trails, often with elevation gain. Mix of aerobic work, leg strength, and time in nature.',
         json_array('Pace by terrain, not by time — hills dictate the effort.','Fuel and hydrate on anything over 2 hours.','Pack for conditions: layers, water, navigation.')
) e
WHERE d.key='walking'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- Machine Cardio (10)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.cues,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Elliptical Steady' AS name,
         'A sustained effort on an elliptical machine at moderate intensity. Low-impact alternative to running for aerobic work or injury recovery.' AS description,
         json_array('Target Zone 2 — conversational pace.','Use the arms actively, not just the legs.','Resistance should be meaningful — spinning the handle on low resistance isn''t a workout.') AS cues
  UNION ALL
  SELECT 'Elliptical Intervals',
         'Hard efforts on the elliptical alternated with easy recovery. Low-impact interval training that spares the joints.',
         json_array('Work intervals of 1–3 minutes at hard effort.','Increase resistance, stride rate, or both to raise intensity.','Recovery at easy resistance, matching the work interval in length.')
  UNION ALL
  SELECT 'Stair Climber',
         'Sustained effort on a stair climbing machine. Brutal on the legs, great for glutes and lungs, low impact.',
         json_array('Don''t hold the rails — lean in and let your legs do the work.','Stand tall, don''t slouch over the console.','Target Zone 2–3 for steady sessions.','20–40 minutes is a full session for most.')
  UNION ALL
  SELECT 'Stair Intervals',
         'Hard efforts on a stair climber alternated with recovery. Builds leg-specific aerobic capacity and work tolerance.',
         json_array('Work intervals of 1–3 minutes at a high step rate.','Recovery at slow climbing pace, not standing rest.','Hands off the rails on work intervals.')
  UNION ALL
  SELECT 'Ski Erg',
         'A standing upper-body-dominant machine mimicking cross-country ski poling. Full-body aerobic work with heavy emphasis on back, core, and shoulders.',
         json_array('Drive through the hips and core, not just the arms.','Stroke rate varies by session: lower for steady, higher for intervals.','Stand close enough to the machine to pull straight down and through.')
  UNION ALL
  SELECT 'Assault Bike',
         'A fan bike with moving handles that becomes harder the harder you work. A staple of CrossFit and conditioning work — punishing and efficient.',
         json_array('Resistance scales with effort — there''s no easy gear.','Use arms and legs together for maximum power output.','Common workouts: 30 seconds on, 30 seconds off, repeated.')
  UNION ALL
  SELECT 'Assault Bike Sprints',
         'All-out short efforts on the fan bike, typically 10–30 seconds, with long recovery. Peak power and conditioning in a low-impact format.',
         json_array('Every sprint is maximum effort.','Rest 2–4 minutes of easy spinning between sprints.','These are miserable. Keep the session short — 6 to 10 sprints is enough.')
  UNION ALL
  SELECT 'Jump Rope Steady',
         'Sustained skipping at a steady pace. Deceptively hard aerobic work that doubles as coordination and foot-speed training.',
         json_array('Stay on the balls of the feet, barely leaving the ground.','Turn the rope with the wrists, not the whole arm.','Break up rounds if unbroken is unrealistic — 60 seconds on, 30 off works well.')
  UNION ALL
  SELECT 'Jump Rope Intervals',
         'Hard skipping efforts alternated with rest. Used by boxers and athletes for conditioning and footwork.',
         json_array('Work intervals at high pace — double-unders if you have them.','Rest as long as needed to keep the quality high.','Protect the wrists with good rope technique and don''t let it become a shoulder workout.')
  UNION ALL
  SELECT 'Rowing Erg Sprints',
         'All-out short erg efforts, typically 100m to 500m. Builds peak power and anaerobic capacity.',
         json_array('Drive hard with the legs — rowing power comes from below the waist.','Stroke rate climbs to 32–38 on sprints.','Rest fully between reps to maintain intensity.')
) e
WHERE d.key='machine_cardio'
AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL);

-- ============================================================================
-- CARDIO EXERCISE CAPABILITIES
-- ============================================================================

-- Running (10 existing + 4 new): time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Easy Run', 'Long Run', 'Tempo Run', 'Fartlek', 'Recovery Run',
  'Progression Run', 'Time Trial', 'Strides', 'Trail Run', 'Treadmill Run'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Easy Run', 'Long Run', 'Tempo Run', 'Fartlek', 'Recovery Run',
  'Progression Run', 'Time Trial', 'Strides', 'Trail Run', 'Treadmill Run'
) AND e.owner_user_id IS NULL;

-- Running interval exercises: time + distance + rounds
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Interval Run', 'Hill Repeats', 'Track Repeats', 'Sprint Intervals'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Interval Run', 'Hill Repeats', 'Track Repeats', 'Sprint Intervals'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Interval Run', 'Hill Repeats', 'Track Repeats', 'Sprint Intervals'
) AND e.owner_user_id IS NULL;

-- Cycling (steady): time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Zone 2 Ride', 'Tempo Ride', 'Long Ride', 'Recovery Ride', 'Stationary Bike'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Zone 2 Ride', 'Tempo Ride', 'Long Ride', 'Recovery Ride', 'Stationary Bike'
) AND e.owner_user_id IS NULL;

-- Cycling (interval): time + distance + rounds
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Sweet Spot Intervals', 'Threshold Intervals', 'VO2 Max Intervals', 'Cycling Sprint Intervals'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Sweet Spot Intervals', 'Threshold Intervals', 'VO2 Max Intervals', 'Cycling Sprint Intervals'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Sweet Spot Intervals', 'Threshold Intervals', 'VO2 Max Intervals', 'Cycling Sprint Intervals'
) AND e.owner_user_id IS NULL;

-- Rowing (steady): time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Steady State Row', '2K Test', 'Long Row', 'Power Strokes'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Steady State Row', '2K Test', 'Long Row', 'Power Strokes'
) AND e.owner_user_id IS NULL;

-- Rowing intervals: time + distance + rounds
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name = 'Rowing Intervals' AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name = 'Rowing Intervals' AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name = 'Rowing Intervals' AND e.owner_user_id IS NULL;

-- Swimming: time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Easy Swim', 'Long Swim', 'Drill Set', 'Swim Kick Set'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Easy Swim', 'Long Swim', 'Drill Set', 'Swim Kick Set'
) AND e.owner_user_id IS NULL;

-- Swimming intervals/sprints: time + distance + rounds
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN ('Swim Intervals', 'Swim Sprints') AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN ('Swim Intervals', 'Swim Sprints') AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN ('Swim Intervals', 'Swim Sprints') AND e.owner_user_id IS NULL;

-- Walking & Hiking: time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Brisk Walk', 'Incline Walk', 'Rucking', 'Hike'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Brisk Walk', 'Incline Walk', 'Rucking', 'Hike'
) AND e.owner_user_id IS NULL;

-- Machine Cardio (time only — distance where applicable)
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Elliptical Steady', 'Elliptical Intervals', 'Stair Climber', 'Stair Intervals',
  'Ski Erg', 'Assault Bike', 'Assault Bike Sprints',
  'Jump Rope Steady', 'Jump Rope Intervals', 'Rowing Erg Sprints'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Elliptical Steady', 'Ski Erg', 'Assault Bike', 'Rowing Erg Sprints'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Elliptical Intervals', 'Stair Intervals',
  'Assault Bike Sprints', 'Jump Rope Intervals'
) AND e.owner_user_id IS NULL;

-- ============================================================================
-- RESISTANCE / LIFTING EXERCISE LIBRARY (Phase 4 — 59 additional exercises)
-- ============================================================================

-- New resistance exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, movement_pattern, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.mp,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Barbell Front Squat' AS name, 'A squat variation with the bar racked across the front delts, emphasizing the quads and demanding an upright torso.' AS description, 'squat' AS mp UNION ALL
  SELECT 'Goblet Squat', 'A dumbbell or kettlebell squat held at chest height, excellent for learning depth, posture, and bracing.', 'squat' UNION ALL
  SELECT 'Dumbbell Split Squat', 'A split-stance single-leg squat with dumbbells held at the sides, building unilateral leg strength and stability.', 'squat' UNION ALL
  SELECT 'Bulgarian Split Squat', 'A rear-foot elevated split squat that loads the front leg heavily and punishes hip and ankle mobility limitations.', 'squat' UNION ALL
  SELECT 'Hack Squat', 'A machine-based squat with the back supported against an angled pad, isolating the quads with minimal spinal load.', 'squat' UNION ALL
  SELECT 'Pistol Squat', 'A bodyweight single-leg squat to a full depth, the benchmark for unilateral lower-body strength and mobility.', 'squat' UNION ALL
  SELECT 'Sumo Deadlift', 'A deadlift with a wide stance and hands inside the knees, shortening the range of motion and emphasizing the hips and inner thighs.', 'hinge' UNION ALL
  SELECT 'Romanian Deadlift (Barbell)', 'A hip-hinge pull from the top down, stopping just below the knees. Loads the hamstrings and glutes under a long stretch.', 'hinge' UNION ALL
  SELECT 'Romanian Deadlift (Dumbbell)', 'A hip hinge performed with dumbbells at the sides, offering a friendlier entry point to the movement pattern and more freedom of motion.', 'hinge' UNION ALL
  SELECT 'Good Morning', 'A hip-hinge with the barbell on the upper back, isolating the posterior chain without grip or arm involvement.', 'hinge' UNION ALL
  SELECT 'Barbell Hip Thrust', 'A glute-dominant hip extension performed with the upper back on a bench and a loaded bar across the hips.', 'hinge' UNION ALL
  SELECT 'Kettlebell Swing', 'A dynamic two-handed hip hinge that uses the kettlebell''s momentum to train explosive hip extension.', 'hinge' UNION ALL
  SELECT 'Back Extension', 'A posterior-chain exercise performed on a 45-degree bench or GHD, extending the hips against gravity with optional load.', 'hinge' UNION ALL
  SELECT 'Incline Barbell Bench Press', 'A bench press performed on a 30-45 degree incline, shifting emphasis to the upper chest and front delts.', 'horizontal_push' UNION ALL
  SELECT 'Decline Barbell Bench Press', 'A bench press on a decline bench, emphasizing the lower chest with a shorter range of motion than flat bench.', 'horizontal_push' UNION ALL
  SELECT 'Flat Dumbbell Bench Press', 'A horizontal press with dumbbells, allowing a deeper stretch and independent arm paths. Great for pec development and shoulder-friendly pressing.', 'horizontal_push' UNION ALL
  SELECT 'Incline Dumbbell Bench Press', 'An incline press with dumbbells, combining upper-chest emphasis with a fuller range of motion than the barbell version.', 'horizontal_push' UNION ALL
  SELECT 'Push-Up', 'The foundational bodyweight horizontal press. Trains the chest, shoulders, triceps, and core under a plank position.', 'horizontal_push' UNION ALL
  SELECT 'Dip', 'A bodyweight press between parallel bars, heavily loading the chest and triceps. Can be weighted with a belt for progression.', 'horizontal_push' UNION ALL
  SELECT 'Machine Chest Press', 'A seated chest press on a plate-loaded or selectorized machine, offering a controlled press path with lower stability demands.', 'horizontal_push' UNION ALL
  SELECT 'Barbell Bent-Over Row', 'A compound horizontal pull with the torso hinged forward, loading the entire back. Demands strict posture to avoid the lower back.', 'horizontal_pull' UNION ALL
  SELECT 'Pendlay Row', 'A strict barbell row performed with the torso parallel to the floor, resetting the bar on the ground between each rep.', 'horizontal_pull' UNION ALL
  SELECT 'Seated Cable Row', 'A seated row with a cable and handle attachment, providing constant tension across the full range of the pull.', 'horizontal_pull' UNION ALL
  SELECT 'Chest-Supported Row', 'A row performed face-down on an incline bench, removing the lower back from the equation so the back muscles do all the work.', 'horizontal_pull' UNION ALL
  SELECT 'T-Bar Row', 'A heavy-loadable row using a landmine or dedicated T-bar station, pulled from a hinged position with a neutral grip.', 'horizontal_pull' UNION ALL
  SELECT 'Inverted Row', 'A bodyweight horizontal pull performed under a fixed bar, the rowing equivalent of a push-up. Scales easily by adjusting foot position.', 'horizontal_pull' UNION ALL
  SELECT 'Face Pull', 'A high-cable row with a rope, pulled toward the forehead. Trains the rear delts and upper back — a staple for shoulder health.', 'horizontal_pull' UNION ALL
  SELECT 'Standing Dumbbell Shoulder Press', 'An overhead press with dumbbells, performed standing. Demands more stability than the seated or barbell version.', 'vertical_push' UNION ALL
  SELECT 'Seated Dumbbell Shoulder Press', 'A supported overhead press with dumbbells and a vertical bench, reducing lower-back demand for cleaner shoulder isolation.', 'vertical_push' UNION ALL
  SELECT 'Landmine Press', 'A single-arm press using a barbell anchored at one end, pressed at an upward angle. Shoulder-friendly alternative to a vertical overhead press.', 'vertical_push' UNION ALL
  SELECT 'Arnold Press', 'A dumbbell overhead press that rotates through the lift, starting with palms toward you and finishing with palms forward. Hits all three deltoid heads.', 'vertical_push' UNION ALL
  SELECT 'Chin-Up', 'A vertical pull-up performed with a supinated grip, shifting emphasis to the biceps while still heavily training the back.', 'vertical_pull' UNION ALL
  SELECT 'Neutral-Grip Pulldown', 'A lat pulldown with a parallel-grip handle, placing the shoulders in a stronger, more comfortable position than overhand.', 'vertical_pull' UNION ALL
  SELECT 'Straight-Arm Pulldown', 'A cable isolation for the lats performed with straight arms, driving the bar from overhead down to the thighs.', 'vertical_pull' UNION ALL
  SELECT 'Walking Lunge', 'A forward-stepping lunge performed continuously, challenging balance, coordination, and single-leg strength with every step.', 'lunge' UNION ALL
  SELECT 'Reverse Lunge', 'A backward-stepping lunge that is easier on the knees than a forward lunge, emphasizing the glutes and front-leg quad.', 'lunge' UNION ALL
  SELECT 'Dumbbell Step-Up', 'A single-leg exercise stepping onto a raised surface, emphasizing the glute and quad of the working leg.', 'lunge' UNION ALL
  SELECT 'Single-Leg Romanian Deadlift', 'A unilateral hip hinge balanced on one leg, training the hamstrings, glutes, and hip stabilizers.', 'lunge' UNION ALL
  SELECT 'Cable Lateral Raise', 'A lateral raise performed from a low cable, offering constant tension through the full range of the lift.', 'shoulder_isolation' UNION ALL
  SELECT 'Rear Delt Fly', 'A reverse fly performed with dumbbells or a reverse pec-deck, isolating the rear delts and upper back.', 'shoulder_isolation' UNION ALL
  SELECT 'Front Raise', 'A frontal-plane shoulder raise with a dumbbell or plate, isolating the front delt.', 'shoulder_isolation' UNION ALL
  SELECT 'Upright Row', 'A vertical pull to the chest with a barbell or dumbbells, hitting the side delts and traps.', 'shoulder_isolation' UNION ALL
  SELECT 'Barbell Curl', 'The benchmark bicep exercise — a standing curl of a barbell with a shoulder-width grip.', 'arm_isolation' UNION ALL
  SELECT 'Dumbbell Curl', 'A bicep curl with dumbbells, allowing each arm to work independently and the wrists to rotate through the movement.', 'arm_isolation' UNION ALL
  SELECT 'Hammer Curl', 'A curl with a neutral grip, emphasizing the brachialis and forearm alongside the biceps.', 'arm_isolation' UNION ALL
  SELECT 'Preacher Curl', 'A curl performed on a preacher bench, locking the upper arm in place to isolate the biceps with no momentum.', 'arm_isolation' UNION ALL
  SELECT 'Overhead Triceps Extension', 'A triceps extension performed with the arm overhead, emphasizing the long head of the triceps under stretch.', 'arm_isolation' UNION ALL
  SELECT 'Skullcrusher', 'A lying triceps extension with a barbell or EZ-bar, lowered toward the forehead and pressed back up. A classic triceps mass-builder.', 'arm_isolation' UNION ALL
  SELECT 'Cable Pull-Through', 'A cable-loaded hip hinge, pulled between the legs from behind. Teaches the hinge pattern with less technical demand than a deadlift.', 'posterior_chain' UNION ALL
  SELECT 'Glute Kickback', 'A single-leg hip extension against cable or machine resistance, isolating the glute on the working side.', 'posterior_chain' UNION ALL
  SELECT 'Nordic Curl', 'A bodyweight hamstring curl performed from a kneeling position with anchored feet, lowering under eccentric control.', 'posterior_chain' UNION ALL
  SELECT 'Standing Calf Raise', 'A loaded calf raise performed standing, emphasizing the gastrocnemius with the knee straight.', 'calves' UNION ALL
  SELECT 'Seated Calf Raise', 'A calf raise performed seated with the knees bent, shifting emphasis to the soleus beneath the gastrocnemius.', 'calves' UNION ALL
  SELECT 'Farmer''s Carry', 'A loaded walk with heavy dumbbells or trap bar, training grip, core, and whole-body stability. Time- or distance-based.', 'loaded_core' UNION ALL
  SELECT 'Pallof Press', 'An anti-rotation core exercise performed at a cable, pressing a handle straight out while resisting the cable''s pull to one side.', 'loaded_core' UNION ALL
  SELECT 'Cable Woodchop', 'A rotational core exercise on a cable, pulling a handle diagonally across the body. Trains rotation and anti-rotation together.', 'loaded_core' UNION ALL
  SELECT 'Hanging Leg Raise', 'A hanging abdominal exercise lifting the legs from vertical to horizontal or higher. Trains the entire anterior core.', 'abs' UNION ALL
  SELECT 'Cable Crunch', 'A loaded crunch performed kneeling in front of a high cable with a rope attachment, letting you progressively overload the abs.', 'abs' UNION ALL
  SELECT 'Ab Wheel Rollout', 'An anti-extension core exercise rolling an ab wheel forward while holding a rigid body. Punishing and highly effective.', 'abs'
) e
WHERE d.key='bodybuilding'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Update existing 10 exercises with enriched content
UPDATE app_exercise SET
    movement_pattern = 'squat',
    description = 'The foundational compound lift for developing lower-body strength and size. The bar rests across the upper back while the lifter squats to depth and drives back up.',
    how_to_steps = json_array(
        'Set the bar across your upper traps, not your neck, and grip it tight with elbows pulled down.',
        'Brace your core hard, unrack, and walk back with two or three controlled steps.',
        'Sit down and back at the same time, keeping knees tracking over your toes.',
        'Descend until your hip crease is at or below the top of your knee.',
        'Drive through your midfoot and stand up without letting your chest collapse forward.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Barbell Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'horizontal_push',
    description = 'The benchmark horizontal press — a barbell press from the chest while lying flat, training chest, shoulders, and triceps.',
    how_to_steps = json_array(
        'Set your feet flat, arch your upper back slightly, and squeeze your shoulder blades together.',
        'Grip the bar just wider than shoulder-width and unrack it over your chest.',
        'Lower the bar to your lower chest with your elbows at roughly 45 degrees from your sides.',
        'Press up and slightly back toward your face, not straight up.',
        'Lock out without letting your shoulder blades come off the bench.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Bench Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'hinge',
    description = 'The benchmark pull from the floor — hinge, grip, and lift. The most complete test of posterior chain strength.',
    how_to_steps = json_array(
        'Set your feet hip-width with the bar directly over your mid-foot.',
        'Hinge down, grip the bar just outside your shins, and pull the slack out.',
        'Take a big breath, brace your core, and push the floor away.',
        'Keep the bar in contact with your legs the entire way up.',
        'Lock out by squeezing your glutes — don''t lean back past neutral.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Deadlift' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'vertical_push',
    description = 'A standing press of a barbell from the front rack to overhead — the benchmark test of upper-body pressing strength.',
    how_to_steps = json_array(
        'Set your feet hip-width, grip just outside shoulder-width, bar resting on your front delts.',
        'Brace your core hard and squeeze your glutes to prevent lower-back hyperextension.',
        'Press the bar straight up, pulling your head back slightly so it travels past your face.',
        'Push your head through at the top until the bar is over your mid-foot.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Overhead Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'vertical_pull',
    description = 'A bodyweight vertical pull from a bar with an overhand grip. The benchmark upper-body pulling movement.',
    how_to_steps = json_array(
        'Grip the bar just wider than shoulder-width, palms facing away.',
        'Hang with shoulders engaged — don''t start from a dead relaxed position.',
        'Pull your chest toward the bar by driving your elbows down and back.',
        'Lower under control to a full hang without swinging.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Pull-Up' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'vertical_pull',
    description = 'A cable machine vertical pull that mimics the pull-up pattern, letting the lifter load below bodyweight for volume work.',
    how_to_steps = json_array(
        'Grip the bar wider than shoulder-width with palms facing forward.',
        'Lock your thighs under the pad and lean back slightly from the hips.',
        'Pull the bar to your upper chest by driving your elbows down.',
        'Control the bar back up without letting your shoulders shrug to your ears.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Lat Pulldown' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'horizontal_pull',
    description = 'A single-arm row braced against a bench, isolating one side of the back at a time with a long range of motion.',
    how_to_steps = json_array(
        'Place one knee and the same-side hand on the bench, other foot planted on the floor.',
        'Let the dumbbell hang straight down, shoulder stretched forward.',
        'Pull the dumbbell to your hip by driving your elbow back toward the ceiling.',
        'Lower it fully, letting the shoulder blade protract at the bottom.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dumbbell Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'squat',
    description = 'A seated or angled machine squat that loads the legs while supporting the torso, allowing heavy loads with low technical demand.',
    how_to_steps = json_array(
        'Plant your feet shoulder-width on the platform, heels flat.',
        'Keep your lower back pressed firmly into the pad — never let it round.',
        'Lower the sled until your knees reach roughly 90 degrees, no deeper if it causes your lower back to lift.',
        'Press through your whole foot and stop just short of locking out.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Leg Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'shoulder_isolation',
    description = 'An isolation exercise lifting dumbbells out to the sides, targeting the side delt for shoulder width.',
    how_to_steps = json_array(
        'Stand tall with a slight forward lean, dumbbells at your sides.',
        'Raise your arms out to the sides with a slight bend in the elbows.',
        'Stop when your hands reach shoulder height — don''t lift higher.',
        'Lower under control, resisting the drop.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Lateral Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    movement_pattern = 'arm_isolation',
    description = 'A cable isolation for the triceps, pressing a bar or rope down from chest height to full extension.',
    how_to_steps = json_array(
        'Stand facing a high cable with a bar or rope attachment.',
        'Pin your upper arms to your sides and keep them there for the whole set.',
        'Extend your arms until the bar reaches your thighs.',
        'Return slowly until your forearms are just above parallel.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Triceps Pressdown' AND owner_user_id IS NULL;

-- Set how_to_steps for all 59 new resistance exercises
UPDATE app_exercise SET
    how_to_steps = json_array(
        'Rack the bar across your front delts with elbows pointed high and fingertips under the bar.',
        'Keep your elbows up throughout the lift — if they drop, you lose the bar.',
        'Sit straight down with a vertical torso, not back like a low-bar squat.',
        'Drive up through your midfoot and keep your chest tall.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Barbell Front Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold the weight vertically against your chest, cupping the top head with both hands.',
        'Brace your core and pull your elbows down inside your knees on the descent.',
        'Squat until your elbows graze the inside of your knees at the bottom.',
        'Stand up driving through your whole foot, keeping the weight tight to your chest.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Goblet Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Step into a long split stance with your front foot flat and back heel raised.',
        'Hold a dumbbell in each hand at your sides, arms relaxed.',
        'Lower straight down until your back knee is just above the floor.',
        'Drive up through the front heel, keeping your torso upright.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dumbbell Split Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Place your rear foot laces-down on a bench roughly knee height.',
        'Step your front foot far enough forward that your knee doesn''t cave inward at the bottom.',
        'Lower your back knee toward the floor with a slight forward lean.',
        'Push straight up through the front foot without bouncing out of the bottom.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Bulgarian Split Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Position your feet shoulder-width on the platform with your back flat against the pad.',
        'Unlock the safeties and lower under control until your thighs are parallel to the platform.',
        'Drive up through your heels without locking out your knees aggressively.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Hack Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand on one leg with the other extended straight out in front of you.',
        'Reach your arms forward as a counterbalance and sit back slowly into the working leg.',
        'Descend as low as you can while keeping your heel down and working knee tracking over your toes.',
        'Drive up through the standing foot without the free leg touching down.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Pistol Squat' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set your feet wide with toes angled out roughly 30 degrees.',
        'Grip the bar with your hands inside your knees, arms vertical.',
        'Drop your hips, spread the floor with your feet, and pull the slack out of the bar.',
        'Push your knees out as you drive up, keeping the bar tight to your body.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Sumo Deadlift' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Start standing with the bar at your hips, knees slightly bent.',
        'Push your hips straight back while keeping the bar sliding down your thighs.',
        'Lower until you feel a strong stretch in your hamstrings — this is usually just below the kneecap.',
        'Drive your hips forward to stand back up, squeezing your glutes at the top.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Romanian Deadlift (Barbell)' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold a dumbbell in each hand with your palms facing your thighs.',
        'Soften your knees slightly and push your hips back, letting the dumbbells slide down your legs.',
        'Stop when you feel your hamstrings stretch, not when the dumbbells touch the floor.',
        'Return by driving your hips forward, not by pulling with your arms.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Romanian Deadlift (Dumbbell)' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Rack the bar across your upper back like a low-bar squat.',
        'Take a small step out, feet under your hips, knees slightly bent.',
        'Hinge forward at the hips until your torso is roughly parallel to the floor.',
        'Drive your hips forward to return — don''t round your back to get up.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Good Morning' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Sit with your upper back against a bench and roll the bar over your hips, using a pad.',
        'Plant your feet flat, hip-width, close enough that your shins are vertical at the top.',
        'Drive your hips up until your torso is parallel to the floor.',
        'Squeeze your glutes hard at the top and lower with control.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Barbell Hip Thrust' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the kettlebell a foot in front of you and hinge to grab it with both hands.',
        'Hike it back between your legs like a football snap.',
        'Snap your hips forward hard — the bell floats up, you don''t lift it with your arms.',
        'Let gravity bring the bell back down, catching it with another hinge.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Kettlebell Swing' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Lock your heels under the pads and set your thighs on the main pad so your hips can fully flex.',
        'Cross your arms or hold a plate at your chest.',
        'Hinge down until you feel a stretch in your hamstrings.',
        'Extend back up by squeezing your glutes — stop at a straight line, don''t hyperextend.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Back Extension' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the bench to roughly 30 degrees — steeper turns it into an overhead press.',
        'Plant your feet, arch your upper back, and retract your shoulder blades.',
        'Lower the bar to your upper chest, just below the collarbone.',
        'Press up and slightly back without flaring your elbows.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Incline Barbell Bench Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Lock your feet under the roller pads before unracking the bar.',
        'Unrack with straight arms and lower the bar to your lower chest.',
        'Press straight up over your shoulders — not toward your face.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Decline Barbell Bench Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Kick the dumbbells up onto your thighs, then lie back to get them into position.',
        'Start with the dumbbells just above your chest, palms facing your feet.',
        'Lower them with control until your elbows break the line of your torso.',
        'Press up and slightly in, stopping just before the dumbbells clang together.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Flat Dumbbell Bench Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the bench to 30 degrees and kick the dumbbells up to the starting position.',
        'Start with the dumbbells level with your upper chest, palms forward.',
        'Lower until you feel a stretch across your upper chest.',
        'Press back up without letting the dumbbells drift forward over your face.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Incline Dumbbell Bench Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set your hands just wider than shoulder-width, directly under your shoulders at the top.',
        'Squeeze your glutes and brace your core so your body forms a straight line.',
        'Lower your chest to within a fist''s height of the floor.',
        'Press back up without letting your hips sag or pike.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Push-Up' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Start in a supported position with straight arms and shoulders down away from your ears.',
        'Lean your torso slightly forward for chest emphasis, stay upright for triceps.',
        'Lower until your upper arms are roughly parallel to the floor.',
        'Press back up without locking the elbows violently.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dip' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Adjust the seat so the handles line up with your mid-chest.',
        'Keep your back flat against the pad and feet planted.',
        'Press out until your arms are almost straight, stopping just short of lockout.',
        'Return under control — don''t let the stack slam.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Machine Chest Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hinge forward until your torso is roughly 45 degrees above parallel, knees soft.',
        'Grip the bar just wider than shoulder-width with an overhand grip.',
        'Pull the bar to your lower ribs by driving your elbows back.',
        'Lower under control without letting your torso pop up.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Barbell Bent-Over Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set up like a deadlift, then hinge until your torso is parallel to the floor.',
        'Pull the bar explosively from the floor to your lower chest.',
        'Lower it all the way back to the floor and dead-stop before the next rep.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Pendlay Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Sit tall with your feet braced and a slight bend in your knees.',
        'Grip the handle and pull your shoulder blades back before starting the row.',
        'Pull the handle to your lower ribs by driving your elbows behind you.',
        'Return under control, letting your arms extend fully but without slumping forward.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Seated Cable Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the bench to about 30-45 degrees and lie chest-down with dumbbells hanging below.',
        'Start with your arms fully extended and shoulder blades relaxed forward.',
        'Row the dumbbells up by driving your elbows toward the ceiling.',
        'Squeeze your shoulder blades at the top before lowering.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Chest-Supported Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Straddle the bar and hinge forward until your torso is 45 degrees from vertical.',
        'Grip the handle with a neutral grip and pull the slack out.',
        'Row the handle into your lower chest, squeezing your mid-back.',
        'Lower under control without letting your torso stand up.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'T-Bar Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set a bar at roughly hip height and lie under it with an overhand grip.',
        'Straighten your body into a rigid plank from heels to shoulders.',
        'Pull your chest to the bar by driving your elbows down and back.',
        'Lower yourself until your arms are straight before the next rep.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Inverted Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the cable to just above eye height and grip the rope with palms facing down.',
        'Step back until your arms are fully extended and under tension.',
        'Pull the rope toward your forehead, ending with your hands beside your ears.',
        'Squeeze your rear delts and upper back at the end position.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Face Pull' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Clean the dumbbells to your shoulders, palms facing forward.',
        'Brace your core and glutes to lock your torso in place.',
        'Press up until the dumbbells touch overhead, without arching your lower back.',
        'Lower under control to ear height before the next rep.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Standing Dumbbell Shoulder Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the bench upright and sit with your back flat against the pad.',
        'Kick the dumbbells up to shoulder height, palms forward.',
        'Press up until the dumbbells meet overhead.',
        'Lower under control, stopping when your elbows pass your torso.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Seated Dumbbell Shoulder Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand in a staggered or split stance holding the bar end at your shoulder.',
        'Brace your core and press the bar up and slightly forward along a diagonal path.',
        'Extend until your arm is straight, keeping your shoulder packed down.',
        'Return slowly along the same path.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Landmine Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Start seated with the dumbbells at shoulder height, palms facing you.',
        'As you press up, rotate your wrists so palms face forward at the top.',
        'Press to full extension overhead.',
        'Reverse the rotation on the way down.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Arnold Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Grip the bar shoulder-width with your palms facing you.',
        'Pull until your chin clears the bar, keeping your chest up.',
        'Lower under control without kipping or swinging.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Chin-Up' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Attach a neutral-grip V-bar or parallel handle to the cable.',
        'Sit tall, lock your thighs down, and grip with palms facing each other.',
        'Pull the handle to your upper chest, focusing on squeezing your lats.',
        'Return under control with full arm extension.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Neutral-Grip Pulldown' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand facing a high cable with a straight bar attached, arms overhead.',
        'Keep a soft bend in the elbows and lock that angle for the entire set.',
        'Pull the bar down to your thighs by driving your hands down in an arc.',
        'Control the bar back to the start without letting it pull your shoulders into a shrug.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Straight-Arm Pulldown' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold dumbbells at your sides or a barbell on your back.',
        'Step forward into a long lunge, lowering your back knee toward the floor.',
        'Drive up through the front heel and step directly into the next lunge.',
        'Keep your torso tall throughout — don''t lean forward to push off.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Walking Lunge' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand tall holding dumbbells or with a bar on your back.',
        'Step one foot straight back and lower your rear knee toward the floor.',
        'Drive up through the front heel and bring the back foot in to meet it.',
        'Alternate legs or finish all reps on one side before switching.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Reverse Lunge' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set a box or bench at roughly knee height.',
        'Hold a dumbbell in each hand at your sides.',
        'Plant your whole foot on the box and drive up to full extension.',
        'Lower under control — don''t push off the back foot to cheat.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dumbbell Step-Up' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand on one leg with a soft bend in the knee, holding a dumbbell in the opposite hand.',
        'Hinge forward, letting the free leg extend straight back as a counterbalance.',
        'Keep your hips square to the floor — don''t let the free hip rotate open.',
        'Return to standing by driving the standing foot into the ground.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Single-Leg Romanian Deadlift' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Stand sideways to a low cable with the handle in your outside hand.',
        'Step out until the cable is under tension at the bottom.',
        'Raise your arm out to the side to shoulder height with a slight elbow bend.',
        'Lower slowly, fighting the cable on the way down.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Cable Lateral Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hinge forward with dumbbells hanging below your chest, elbows softly bent.',
        'Raise your arms out to the sides until they reach shoulder level.',
        'Squeeze your rear delts at the top — don''t use momentum to get there.',
        'Lower under control.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Rear Delt Fly' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold a dumbbell in each hand at the front of your thighs, palms facing in.',
        'Raise one or both arms straight out in front of you to shoulder height.',
        'Pause briefly at the top, then lower without swinging.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Front Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Grip the bar slightly wider than shoulder-width, hanging at arm''s length.',
        'Pull the bar up by driving your elbows out and up.',
        'Stop when your elbows reach shoulder height — higher compresses the shoulder.',
        'Lower under control.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Upright Row' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Grip the bar shoulder-width, standing tall with elbows tucked to your sides.',
        'Curl the bar up by flexing at the elbow, keeping your upper arms still.',
        'Lower the bar under control to a full stretch without locking out hard.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Barbell Curl' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Start with dumbbells at your sides, palms facing in.',
        'Curl up, rotating your palms to face you as the dumbbells pass your thighs.',
        'Squeeze at the top and lower under control to a full stretch.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dumbbell Curl' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold the dumbbells with palms facing each other throughout the set.',
        'Curl up without rotating your wrists, keeping palms facing in.',
        'Lower fully before the next rep.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Hammer Curl' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the pad so your armpit is snug against the top edge.',
        'Start with the arms fully extended, a slight bend in the elbows.',
        'Curl the bar or dumbbells up, keeping your upper arm pinned to the pad.',
        'Lower under strict control — the stretch at the bottom is the whole point.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Preacher Curl' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hold a dumbbell with both hands overhead, arms fully extended.',
        'Lower the dumbbell behind your head by bending at the elbows only.',
        'Extend back to the top by driving your hands up, keeping your upper arms vertical.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Overhead Triceps Extension' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Lie flat on a bench holding the bar above your chest with a close grip.',
        'Keep your upper arms vertical as you bend at the elbows.',
        'Lower the bar toward your forehead or just past it.',
        'Extend back up by squeezing the triceps — don''t drift the elbows out.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Skullcrusher' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Face away from a low cable, straddle it, and grab the rope between your legs.',
        'Step forward until the cable is under tension.',
        'Hinge your hips back, letting the rope travel between your legs.',
        'Drive your hips forward to stand, squeezing your glutes at the top.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Cable Pull-Through' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Attach an ankle strap to a low cable and stand facing the machine.',
        'Keep a slight bend in the working leg and extend it straight back.',
        'Squeeze your glute at full extension — don''t arch your lower back to get more range.',
        'Return under control.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Glute Kickback' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Anchor your feet under a pad or have a partner hold your ankles.',
        'Start kneeling upright with your torso and thighs in a straight line.',
        'Lower yourself forward as slowly as possible by resisting with your hamstrings.',
        'Catch yourself with your hands when you can''t hold any longer, then push back up.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Nordic Curl' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the balls of your feet on a raised platform with heels hanging off.',
        'Drop into a full stretch at the bottom of each rep.',
        'Press up onto your toes as high as you can go.',
        'Pause at the top, then lower back into the stretch.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Standing Calf Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the pad across your lower thighs, balls of the feet on the platform.',
        'Let your heels drop into a full stretch.',
        'Press up as high as you can.',
        'Lower slowly back to the stretched position.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Seated Calf Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Pick up a heavy dumbbell in each hand with a flat back and neutral spine.',
        'Stand tall with shoulders pulled back and down.',
        'Walk with controlled steps, not letting your torso sway side to side.',
        'Set the weights down with a controlled hinge, not a drop.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Farmer''s Carry' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set a cable at chest height and stand sideways to the stack.',
        'Grip the handle with both hands at your sternum.',
        'Press the handle straight out in front of you and resist the cable pulling you toward the stack.',
        'Hold briefly at full extension, then return to your chest.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Pallof Press' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Set the cable high and stand sideways to the stack.',
        'Grip the handle with both hands and pull it diagonally down across your body.',
        'Rotate through your torso, not your arms — keep your arms nearly straight.',
        'Return under control along the same path.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Cable Woodchop' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Hang from a pull-up bar with shoulders engaged, not dead relaxed.',
        'Brace your core and lift your legs with control.',
        'Raise until your thighs are at least parallel to the floor — higher is better.',
        'Lower slowly without swinging.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Hanging Leg Raise' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Kneel in front of a high cable with the rope pulled to the sides of your head.',
        'Hinge forward by flexing your spine, not your hips.',
        'Curl your ribs toward your pelvis — think of a crunching motion, not a bow.',
        'Return under control without using your hips to lift.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Cable Crunch' AND owner_user_id IS NULL;

UPDATE app_exercise SET
    how_to_steps = json_array(
        'Kneel with the wheel directly under your shoulders.',
        'Brace your core hard — think of pulling your ribs down toward your hips.',
        'Roll the wheel forward as far as you can hold a rigid torso.',
        'Pull yourself back by contracting your abs, not your hip flexors.'
    ),
    updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Ab Wheel Rollout' AND owner_user_id IS NULL;

-- Capabilities for new resistance exercises (reps + sets + load + time)
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'reps' FROM app_exercise e WHERE e.name IN (
    'Barbell Front Squat', 'Goblet Squat', 'Dumbbell Split Squat', 'Bulgarian Split Squat',
    'Hack Squat', 'Sumo Deadlift', 'Romanian Deadlift (Barbell)', 'Romanian Deadlift (Dumbbell)',
    'Good Morning', 'Barbell Hip Thrust', 'Kettlebell Swing', 'Back Extension',
    'Incline Barbell Bench Press', 'Decline Barbell Bench Press', 'Flat Dumbbell Bench Press',
    'Incline Dumbbell Bench Press', 'Dip', 'Machine Chest Press',
    'Barbell Bent-Over Row', 'Pendlay Row', 'Seated Cable Row', 'Chest-Supported Row',
    'T-Bar Row', 'Face Pull',
    'Standing Dumbbell Shoulder Press', 'Seated Dumbbell Shoulder Press', 'Landmine Press', 'Arnold Press',
    'Chin-Up', 'Neutral-Grip Pulldown', 'Straight-Arm Pulldown',
    'Walking Lunge', 'Reverse Lunge', 'Dumbbell Step-Up', 'Single-Leg Romanian Deadlift',
    'Cable Lateral Raise', 'Rear Delt Fly', 'Front Raise', 'Upright Row',
    'Barbell Curl', 'Dumbbell Curl', 'Hammer Curl', 'Preacher Curl',
    'Overhead Triceps Extension', 'Skullcrusher',
    'Cable Pull-Through', 'Glute Kickback', 'Standing Calf Raise', 'Seated Calf Raise',
    'Pallof Press', 'Cable Woodchop', 'Cable Crunch'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'sets' FROM app_exercise e WHERE e.name IN (
    'Barbell Front Squat', 'Goblet Squat', 'Dumbbell Split Squat', 'Bulgarian Split Squat',
    'Hack Squat', 'Pistol Squat', 'Sumo Deadlift', 'Romanian Deadlift (Barbell)',
    'Romanian Deadlift (Dumbbell)', 'Good Morning', 'Barbell Hip Thrust', 'Kettlebell Swing',
    'Back Extension', 'Incline Barbell Bench Press', 'Decline Barbell Bench Press',
    'Flat Dumbbell Bench Press', 'Incline Dumbbell Bench Press', 'Push-Up', 'Dip',
    'Machine Chest Press', 'Barbell Bent-Over Row', 'Pendlay Row', 'Seated Cable Row',
    'Chest-Supported Row', 'T-Bar Row', 'Inverted Row', 'Face Pull',
    'Standing Dumbbell Shoulder Press', 'Seated Dumbbell Shoulder Press', 'Landmine Press', 'Arnold Press',
    'Chin-Up', 'Neutral-Grip Pulldown', 'Straight-Arm Pulldown',
    'Walking Lunge', 'Reverse Lunge', 'Dumbbell Step-Up', 'Single-Leg Romanian Deadlift',
    'Cable Lateral Raise', 'Rear Delt Fly', 'Front Raise', 'Upright Row',
    'Barbell Curl', 'Dumbbell Curl', 'Hammer Curl', 'Preacher Curl',
    'Overhead Triceps Extension', 'Skullcrusher', 'Nordic Curl',
    'Cable Pull-Through', 'Glute Kickback', 'Standing Calf Raise', 'Seated Calf Raise',
    'Pallof Press', 'Cable Woodchop', 'Cable Crunch', 'Hanging Leg Raise', 'Ab Wheel Rollout'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'load' FROM app_exercise e WHERE e.name IN (
    'Barbell Front Squat', 'Goblet Squat', 'Dumbbell Split Squat', 'Bulgarian Split Squat',
    'Hack Squat', 'Sumo Deadlift', 'Romanian Deadlift (Barbell)', 'Romanian Deadlift (Dumbbell)',
    'Good Morning', 'Barbell Hip Thrust', 'Kettlebell Swing', 'Back Extension',
    'Incline Barbell Bench Press', 'Decline Barbell Bench Press', 'Flat Dumbbell Bench Press',
    'Incline Dumbbell Bench Press', 'Dip', 'Machine Chest Press',
    'Barbell Bent-Over Row', 'Pendlay Row', 'Seated Cable Row', 'Chest-Supported Row',
    'T-Bar Row', 'Face Pull',
    'Standing Dumbbell Shoulder Press', 'Seated Dumbbell Shoulder Press', 'Landmine Press', 'Arnold Press',
    'Chin-Up', 'Neutral-Grip Pulldown', 'Straight-Arm Pulldown',
    'Walking Lunge', 'Reverse Lunge', 'Dumbbell Step-Up', 'Single-Leg Romanian Deadlift',
    'Cable Lateral Raise', 'Rear Delt Fly', 'Front Raise', 'Upright Row',
    'Barbell Curl', 'Dumbbell Curl', 'Hammer Curl', 'Preacher Curl',
    'Overhead Triceps Extension', 'Skullcrusher',
    'Cable Pull-Through', 'Glute Kickback', 'Standing Calf Raise', 'Seated Calf Raise',
    'Farmer''s Carry', 'Pallof Press', 'Cable Woodchop', 'Cable Crunch'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
    'Barbell Front Squat', 'Goblet Squat', 'Dumbbell Split Squat', 'Bulgarian Split Squat',
    'Hack Squat', 'Pistol Squat', 'Sumo Deadlift', 'Romanian Deadlift (Barbell)',
    'Romanian Deadlift (Dumbbell)', 'Good Morning', 'Barbell Hip Thrust', 'Kettlebell Swing',
    'Back Extension', 'Incline Barbell Bench Press', 'Decline Barbell Bench Press',
    'Flat Dumbbell Bench Press', 'Incline Dumbbell Bench Press', 'Push-Up', 'Dip',
    'Machine Chest Press', 'Barbell Bent-Over Row', 'Pendlay Row', 'Seated Cable Row',
    'Chest-Supported Row', 'T-Bar Row', 'Inverted Row', 'Face Pull',
    'Standing Dumbbell Shoulder Press', 'Seated Dumbbell Shoulder Press', 'Landmine Press', 'Arnold Press',
    'Chin-Up', 'Neutral-Grip Pulldown', 'Straight-Arm Pulldown',
    'Walking Lunge', 'Reverse Lunge', 'Dumbbell Step-Up', 'Single-Leg Romanian Deadlift',
    'Cable Lateral Raise', 'Rear Delt Fly', 'Front Raise', 'Upright Row',
    'Barbell Curl', 'Dumbbell Curl', 'Hammer Curl', 'Preacher Curl',
    'Overhead Triceps Extension', 'Skullcrusher', 'Nordic Curl',
    'Cable Pull-Through', 'Glute Kickback', 'Standing Calf Raise', 'Seated Calf Raise',
    'Farmer''s Carry', 'Pallof Press', 'Cable Woodchop', 'Hanging Leg Raise',
    'Cable Crunch', 'Ab Wheel Rollout'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e
WHERE e.name = 'Farmer''s Carry' AND e.owner_user_id IS NULL;

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Heavy Bag Rounds' AS name, 'Boxing heavy bag work' AS description UNION ALL
  SELECT 'Shadowboxing', 'Footwork and technique without equipment' UNION ALL
  SELECT 'Pad Work', 'Striking drills with pads' UNION ALL
  SELECT 'Speed Bag', 'Hand speed and rhythm training' UNION ALL
  SELECT 'Double-End Bag', 'Timing and accuracy training' UNION ALL
  SELECT 'Sparring', 'Live boxing rounds' UNION ALL
  SELECT 'Defensive Drills', 'Slips, rolls, and blocks practice' UNION ALL
  SELECT 'Footwork Drills', 'Movement and positioning drills' UNION ALL
  SELECT 'Conditioning Rounds', 'High intensity boxing rounds' UNION ALL
  SELECT 'Technical Rounds', 'Low intensity skill-focused rounds'
) e
WHERE d.key='boxing'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);


INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Plank Hold' AS name, 'Isometric core hold' AS description UNION ALL
  SELECT 'Side Plank', 'Lateral core isometric hold' UNION ALL
  SELECT 'Wall Sit', 'Isometric leg hold' UNION ALL
  SELECT 'Dead Hang', 'Grip and shoulder isometric hang' UNION ALL
  SELECT 'Hollow Body Hold', 'Anterior core isometric hold' UNION ALL
  SELECT 'Glute Bridge Hold', 'Hip extension isometric hold' UNION ALL
  SELECT 'L-Sit Hold', 'Advanced seated isometric hold' UNION ALL
  SELECT 'Isometric Push-Up Hold', 'Paused push-up position hold' UNION ALL
  SELECT 'Calf Raise Hold', 'Isometric calf contraction' UNION ALL
  SELECT 'Split Squat Hold', 'Unilateral leg isometric hold'
) e
WHERE d.key='calisthenics'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Plank Hold' AS name, 'Isometric core hold' AS description UNION ALL
  SELECT 'Side Plank', 'Lateral core isometric hold' UNION ALL
  SELECT 'Wall Sit', 'Isometric leg hold' UNION ALL
  SELECT 'Dead Hang', 'Grip and shoulder isometric hang' UNION ALL
  SELECT 'Hollow Body Hold', 'Anterior core isometric hold' UNION ALL
  SELECT 'Glute Bridge Hold', 'Hip extension isometric hold' UNION ALL
  SELECT 'L-Sit Hold', 'Advanced seated isometric hold' UNION ALL
  SELECT 'Isometric Push-Up Hold', 'Paused push-up position hold' UNION ALL
  SELECT 'Calf Raise Hold', 'Isometric calf contraction' UNION ALL
  SELECT 'Split Squat Hold', 'Unilateral leg isometric hold'
) e
WHERE d.key='calisthenics'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Sports exercises (team sports & racket sports with round/period-based tracking)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'tennis' AS disc, 'Tennis Match' AS name, 'Full tennis match or practice game' AS description UNION ALL
  SELECT 'tennis', 'Tennis Drill', 'Targeted tennis technique and footwork drills' UNION ALL
  SELECT 'volleyball', 'Volleyball Match', 'Full volleyball game or scrimmage' UNION ALL
  SELECT 'volleyball', 'Volleyball Drill', 'Passing, setting, and spiking drills' UNION ALL
  SELECT 'badminton', 'Badminton Match', 'Full badminton game or rally practice' UNION ALL
  SELECT 'table_tennis', 'Table Tennis Match', 'Full table tennis game or practice' UNION ALL
  SELECT 'cricket', 'Cricket Match', 'Cricket match or practice session' UNION ALL
  SELECT 'ice_hockey', 'Ice Hockey Match', 'Full ice hockey game or scrimmage' UNION ALL
  SELECT 'baseball', 'Baseball Game', 'Full baseball game or practice' UNION ALL
  SELECT 'american_football', 'American Football Game', 'Full American football game or scrimmage' UNION ALL
  SELECT 'rugby', 'Rugby Match', 'Full rugby game or practice match' UNION ALL
  SELECT 'lacrosse', 'Lacrosse Game', 'Full lacrosse game or scrimmage'
) e ON d.key = e.disc
WHERE NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Exercise-Muscle Group relationships
-- Bench Press: Chest (primary), Triceps, Shoulders
INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 1
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Bench Press' AND e.owner_user_id IS NULL AND mg.name = 'Chest';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Bench Press' AND e.owner_user_id IS NULL AND mg.name = 'Triceps';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Bench Press' AND e.owner_user_id IS NULL AND mg.name = 'Shoulders';

-- Back Squat: Quadriceps (primary), Glutes, Hamstrings
INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 1
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Back Squat' AND e.owner_user_id IS NULL AND mg.name = 'Quadriceps';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Back Squat' AND e.owner_user_id IS NULL AND mg.name = 'Glutes';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Back Squat' AND e.owner_user_id IS NULL AND mg.name = 'Hamstrings';

-- Pull-up: Back (primary), Biceps
INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 1
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Pull-up' AND e.owner_user_id IS NULL AND mg.name = 'Back';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Pull-up' AND e.owner_user_id IS NULL AND mg.name = 'Biceps';

-- Deadlift: Back (primary), Hamstrings, Glutes
INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 1
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Deadlift' AND e.owner_user_id IS NULL AND mg.name = 'Back';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Deadlift' AND e.owner_user_id IS NULL AND mg.name = 'Hamstrings';

INSERT OR IGNORE INTO app_exercise_muscle_group (exercise_id, muscle_group_id, is_primary)
SELECT e.id, mg.id, 0
FROM app_exercise e, app_muscle_group mg
WHERE e.name = 'Deadlift' AND e.owner_user_id IS NULL AND mg.name = 'Glutes';

-- Exercise Capabilities
-- Running exercises: time + distance
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Easy Run', 'Long Run', 'Tempo Run', 'Interval Run', 'Hill Repeats',
  'Fartlek', 'Recovery Run', 'Track Repeats', 'Progression Run', 'Time Trial'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'distance' FROM app_exercise e WHERE e.name IN (
  'Easy Run', 'Long Run', 'Tempo Run', 'Interval Run', 'Hill Repeats',
  'Fartlek', 'Recovery Run', 'Track Repeats', 'Progression Run', 'Time Trial'
) AND e.owner_user_id IS NULL;

-- Running exercises with rounds (intervals)
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Interval Run', 'Hill Repeats', 'Track Repeats'
) AND e.owner_user_id IS NULL;

-- Strength exercises: reps + sets + load + time (for cardio context)
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'reps' FROM app_exercise e WHERE e.name IN (
  'Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press', 'Pull-up',
  'Lat Pulldown', 'Dumbbell Row', 'Leg Press', 'Lateral Raise', 'Triceps Pressdown'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'sets' FROM app_exercise e WHERE e.name IN (
  'Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press', 'Pull-up',
  'Lat Pulldown', 'Dumbbell Row', 'Leg Press', 'Lateral Raise', 'Triceps Pressdown'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'load' FROM app_exercise e WHERE e.name IN (
  'Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press', 'Pull-up',
  'Lat Pulldown', 'Dumbbell Row', 'Leg Press', 'Lateral Raise', 'Triceps Pressdown'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press', 'Pull-up',
  'Lat Pulldown', 'Dumbbell Row', 'Leg Press', 'Lateral Raise', 'Triceps Pressdown'
) AND e.owner_user_id IS NULL;

-- Boxing exercises: time + rounds
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Heavy Bag Rounds', 'Shadowboxing', 'Pad Work', 'Speed Bag',
  'Double-End Bag', 'Sparring', 'Defensive Drills', 'Footwork Drills',
  'Conditioning Rounds', 'Technical Rounds'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Heavy Bag Rounds', 'Shadowboxing', 'Pad Work', 'Speed Bag',
  'Double-End Bag', 'Sparring', 'Defensive Drills', 'Footwork Drills',
  'Conditioning Rounds', 'Technical Rounds'
) AND e.owner_user_id IS NULL;

-- Isometric exercises: hold + time + sets
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'hold' FROM app_exercise e WHERE e.name IN (
  'Plank Hold', 'Side Plank', 'Wall Sit', 'Dead Hang',
  'Hollow Body Hold', 'Glute Bridge Hold', 'L-Sit Hold',
  'Isometric Push-Up Hold', 'Calf Raise Hold', 'Split Squat Hold'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Plank Hold', 'Side Plank', 'Wall Sit', 'Dead Hang',
  'Hollow Body Hold', 'Glute Bridge Hold', 'L-Sit Hold',
  'Isometric Push-Up Hold', 'Calf Raise Hold', 'Split Squat Hold'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'sets' FROM app_exercise e WHERE e.name IN (
  'Plank Hold', 'Side Plank', 'Wall Sit', 'Dead Hang',
  'Hollow Body Hold', 'Glute Bridge Hold', 'L-Sit Hold',
  'Isometric Push-Up Hold', 'Calf Raise Hold', 'Split Squat Hold'
) AND e.owner_user_id IS NULL;

-- Sports exercises: time + rounds (periods/halves/sets)
INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'time' FROM app_exercise e WHERE e.name IN (
  'Tennis Match', 'Tennis Drill', 'Volleyball Match', 'Volleyball Drill',
  'Badminton Match', 'Table Tennis Match', 'Cricket Match', 'Ice Hockey Match',
  'Baseball Game', 'American Football Game', 'Rugby Match', 'Lacrosse Game'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  'Tennis Match', 'Tennis Drill', 'Volleyball Match', 'Volleyball Drill',
  'Badminton Match', 'Table Tennis Match', 'Cricket Match', 'Ice Hockey Match',
  'Baseball Game', 'American Football Game', 'Rugby Match', 'Lacrosse Game'
) AND e.owner_user_id IS NULL;

-- ============================================================================
-- DEFAULT ROUND DURATIONS
-- ============================================================================
-- Sets the sport-specific default period/half/set length for round-based exercises.
-- NULL = use app-wide default (180s / 3 min). Only set for sports where the natural
-- playing unit differs meaningfully from a 3-min boxing round.
-- See Exercise.defaultRoundDurationSecs in lib/data/models/models.dart.
-- Boxing exercises intentionally left as NULL (they use the 3-min default).

-- Team sports — period / half / set lengths
UPDATE app_exercise SET default_round_duration_secs = 1200  -- 20-min set
  WHERE name = 'Tennis Match'            AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Tennis Drill'            AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1500  -- 25-min set
  WHERE name = 'Volleyball Match'        AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Volleyball Drill'        AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1200  -- 20-min game
  WHERE name = 'Badminton Match'         AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min game
  WHERE name = 'Table Tennis Match'      AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1800  -- 30-min innings segment
  WHERE name = 'Cricket Match'           AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1200  -- 20-min period
  WHERE name = 'Ice Hockey Match'        AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1800  -- ~30-min inning
  WHERE name = 'Baseball Game'           AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min quarter
  WHERE name = 'American Football Game'  AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 2400  -- 40-min half
  WHERE name = 'Rugby Match'             AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 720   -- 12-min quarter
  WHERE name = 'Lacrosse Game'           AND owner_user_id IS NULL;

COMMIT;
