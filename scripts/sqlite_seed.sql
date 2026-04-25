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

-- New sports disciplines (Phase 4)
INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'squash', 'Squash', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='squash');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'padel', 'Padel', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='padel');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'mma', 'MMA', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='mma');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'karate', 'Karate', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='karate');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'judo', 'Judo', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='judo');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'golf', 'Golf', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='golf');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'climbing', 'Climbing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='climbing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'isometric_holds', 'Isometric Holds', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='isometric_stretching' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='isometric_holds');

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

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Heavy Bag Rounds' AS name,
    'Timed rounds on the heavy bag — combinations, power work, and conditioning at moderate-to-high intensity.' AS description,
    json_array('Hands back to the guard after every punch — no hanging.','Turn the hip and shoulder into straight punches; don''t arm-punch.','Move around the bag between combinations, don''t stand square.','Breathe out on every strike.') AS how_to_steps
  UNION ALL
  SELECT 'Shadowboxing',
    'Timed rounds of punching in open space — footwork, head movement, and combination rehearsal without resistance.',
    json_array('Watch yourself in a mirror or film one round to audit form.','Throw every punch with the intent you would against a bag.','Include defense — slips, rolls, pulls — not just offense.','Finish every combination with movement off line.')
  UNION ALL
  SELECT 'Pad Work',
    'Timed rounds with a coach or partner holding focus mitts or Thai pads — called combinations, reactive work, and counters.',
    json_array('Respond to the call, don''t anticipate it.','Reset the guard between combinations — don''t drift.','Hit the pad, don''t slap it — turn punches over at contact.','Footwork moves first, then the hands.')
  UNION ALL
  SELECT 'Speed Bag',
    'Timed rounds on the speed bag — rhythm, hand speed, and shoulder endurance.',
    json_array('Strike with the side of the fist on the downswing, not a punch.','Keep elbows up at bag height — don''t let them drop.','Find the three-beat rhythm: bag hits front wall, back wall, front wall.','Switch lead hand every round.')
  UNION ALL
  SELECT 'Double-End Bag',
    'Timed rounds on a tethered reflex bag — timing, accuracy, and defensive reactions against a moving target.',
    json_array('Stay in range — close enough to hit, far enough to slip.','Don''t chase the bag; let it come back to you.','Work in combinations of two or three, not singles.','Slip or pull after every shot — the bag is swinging back at you.')
  UNION ALL
  SELECT 'Sparring',
    'Live rounds with a partner at an agreed intensity. Technique-focused light sparring or harder competition-prep rounds.',
    NULL
  UNION ALL
  SELECT 'Defensive Drills',
    'Timed rounds of slipping, rolling, parrying, and blocking against a partner''s feed or shadowed in open space.',
    json_array('Move the head off the centerline, not just back.','Hands don''t drop when the head moves.','Slip short — enough to miss the punch, not more.','Counter out of every defensive movement.')
  UNION ALL
  SELECT 'Footwork Drills',
    'Timed rounds of movement patterns — pivots, cuts, in-and-out rhythm, lateral steps. Done on floor markings, ladder, or open space.',
    json_array('Stay in stance — the feet never cross.','Push off the back foot moving forward, front foot moving back.','Small, fast steps — not long strides.','Reset stance after every pivot.')
  UNION ALL
  SELECT 'Conditioning Rounds',
    'High-output rounds — bag work, pads, or shadow — run at competition intensity to build round-specific conditioning.',
    json_array('Throw in volume — don''t pace.','Nasal breathing between exchanges where possible.','Keep form honest when tired; collapsing form is the drill failing.','Log how you feel at minute 2:30 of each round — that''s the true signal.')
  UNION ALL
  SELECT 'Technical Rounds',
    'Low-intensity rounds focused on one technical element — a specific combination, footwork pattern, or defensive sequence.',
    json_array('Pick one thing to work on before the round starts.','Slow is fast — technique first, speed later.','If form breaks, stop and reset rather than push through.','Finish every round with a clean rep of the focus technique.')
) e
WHERE d.key='boxing'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Update boxing exercise descriptions and cues (for pre-existing rows)
UPDATE app_exercise SET
  description = 'Timed rounds on the heavy bag — combinations, power work, and conditioning at moderate-to-high intensity.',
  how_to_steps = json_array('Hands back to the guard after every punch — no hanging.','Turn the hip and shoulder into straight punches; don''t arm-punch.','Move around the bag between combinations, don''t stand square.','Breathe out on every strike.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Heavy Bag Rounds' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds of punching in open space — footwork, head movement, and combination rehearsal without resistance.',
  how_to_steps = json_array('Watch yourself in a mirror or film one round to audit form.','Throw every punch with the intent you would against a bag.','Include defense — slips, rolls, pulls — not just offense.','Finish every combination with movement off line.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Shadowboxing' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds with a coach or partner holding focus mitts or Thai pads — called combinations, reactive work, and counters.',
  how_to_steps = json_array('Respond to the call, don''t anticipate it.','Reset the guard between combinations — don''t drift.','Hit the pad, don''t slap it — turn punches over at contact.','Footwork moves first, then the hands.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Pad Work' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds on the speed bag — rhythm, hand speed, and shoulder endurance.',
  how_to_steps = json_array('Strike with the side of the fist on the downswing, not a punch.','Keep elbows up at bag height — don''t let them drop.','Find the three-beat rhythm: bag hits front wall, back wall, front wall.','Switch lead hand every round.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Speed Bag' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds on a tethered reflex bag — timing, accuracy, and defensive reactions against a moving target.',
  how_to_steps = json_array('Stay in range — close enough to hit, far enough to slip.','Don''t chase the bag; let it come back to you.','Work in combinations of two or three, not singles.','Slip or pull after every shot — the bag is swinging back at you.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Double-End Bag' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Live rounds with a partner at an agreed intensity. Technique-focused light sparring or harder competition-prep rounds.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Sparring' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds of slipping, rolling, parrying, and blocking against a partner''s feed or shadowed in open space.',
  how_to_steps = json_array('Move the head off the centerline, not just back.','Hands don''t drop when the head moves.','Slip short — enough to miss the punch, not more.','Counter out of every defensive movement.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Defensive Drills' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Timed rounds of movement patterns — pivots, cuts, in-and-out rhythm, lateral steps. Done on floor markings, ladder, or open space.',
  how_to_steps = json_array('Stay in stance — the feet never cross.','Push off the back foot moving forward, front foot moving back.','Small, fast steps — not long strides.','Reset stance after every pivot.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Footwork Drills' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'High-output rounds — bag work, pads, or shadow — run at competition intensity to build round-specific conditioning.',
  how_to_steps = json_array('Throw in volume — don''t pace.','Nasal breathing between exchanges where possible.','Keep form honest when tired; collapsing form is the drill failing.','Log how you feel at minute 2:30 of each round — that''s the true signal.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Conditioning Rounds' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Low-intensity rounds focused on one technical element — a specific combination, footwork pattern, or defensive sequence.',
  how_to_steps = json_array('Pick one thing to work on before the round starts.','Slow is fast — technique first, speed later.','If form breaks, stop and reset rather than push through.','Finish every round with a clean rep of the focus technique.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Technical Rounds' AND owner_user_id IS NULL;


-- Isometric holds — migrate existing 10 exercises to discipline-isometric-holds and update descriptions/cues
UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Front-facing isometric hold supported on forearms and toes, targeting the anterior core, shoulders, and glutes. A baseline test of full-body bracing.',
  how_to_steps = json_array('Stack elbows directly under shoulders, forearms parallel.','Squeeze glutes and brace the abs — ribs tucked, no sag at the hips.','Hold a neutral neck, eyes on the floor just ahead of the hands.','Breathe shallow through the nose; don''t hold your breath.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Plank Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Lateral isometric hold on one forearm and the side of one foot, targeting the obliques, quadratus lumborum, and shoulder stabilizers.',
  how_to_steps = json_array('Stack shoulder over elbow, feet stacked or staggered for balance.','Drive the hips up so the body forms one straight line from head to heels.','Reach the top arm skyward or rest it on the hip — pick one and keep it still.','Keep the bottom shoulder packed, not collapsed toward the ear.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Side Plank' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Isometric squat hold with the back flat against a wall and thighs parallel to the floor. Targets the quads, with secondary glute and calf engagement.',
  how_to_steps = json_array('Slide down until thighs are parallel to the floor — knees at roughly 90 degrees.','Knees stacked over ankles, not forward over the toes.','Press the full back flat against the wall, no gap at the low back.','Breathe steadily; the burn will spike around 30 seconds in.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Wall Sit' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Passive isometric hang from a pull-up bar with arms fully extended. Trains grip endurance and decompresses the shoulders and spine.',
  how_to_steps = json_array('Grip the bar at roughly shoulder width, thumbs wrapped.','Let the body hang fully — don''t actively shrug the shoulders up.','Keep the ribcage down and core lightly engaged so you''re not swaying.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Dead Hang' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Supine isometric hold with arms overhead and legs extended, pressing the low back firmly into the floor. Trains anterior core tension used in gymnastics and Olympic lifting.',
  how_to_steps = json_array('Press the low back flat — no daylight between the floor and your spine.','Lift shoulders and legs just enough that lockout is maintained, not higher.','Arms by the ears, legs straight, toes pointed.','If the low back arches, raise the legs higher until you can flatten it again.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Hollow Body Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Supine hip-extension hold with shoulders on the floor, knees bent, hips driven up. Targets the glutes and hamstrings.',
  how_to_steps = json_array('Feet flat, heels close enough that a brushed fingertip barely touches them.','Drive through the heels and squeeze the glutes to lift the hips.','Ribs stay down — don''t hyperextend the low back to get higher.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Glute Bridge Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Seated isometric hold with the body supported on straight arms, legs extended straight out parallel to the floor. Trains the anterior core, hip flexors, and tricep lockout.',
  how_to_steps = json_array('Press down hard through straight arms to lift the hips clear of the floor.','Extend legs straight forward — lock the knees, point the toes.','If straight legs are impossible, bend the knees (tuck L-sit) as a regression.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'L-Sit Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Paused hold at the bottom of a push-up, typically with the chest an inch off the floor. Targets the chest, triceps, and anterior core.',
  how_to_steps = json_array('Lower to the bottom of a push-up and hold — chest hovering just off the floor.','Elbows at roughly 45 degrees to the torso, not flared wide.','Maintain full plank body line; don''t let the hips sag.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Isometric Push-Up Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Isometric hold at the top of a calf raise, up on the balls of the feet. Trains calf endurance and ankle stability.',
  how_to_steps = json_array('Rise to the top of a calf raise on both feet.','Hold the highest point — don''t settle into a mid-range position.','Keep the ankles tracking straight, not rolling outward.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Calf Raise Hold' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  discipline_id = (SELECT d.id FROM app_discipline d WHERE d.key = 'isometric_holds'),
  description = 'Unilateral isometric lunge hold in the bottom position. Targets the front-leg quad and glute, with a long-lever stretch on the rear-leg hip flexor.',
  how_to_steps = json_array('Front knee stacked over the front ankle, rear knee hovering an inch off the floor.','Torso tall, front heel planted.','Shift weight onto the front leg — the rear leg is a kickstand, not a driver.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Split Squat Hold' AND owner_user_id IS NULL;

-- New Isometric Holds (core, lower-body, upper-body)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'RKC Plank' AS name,
    'Maximum-tension variant of the standard plank. Same position, but every muscle — glutes, quads, abs, lats — contracts as hard as possible throughout the hold.' AS description,
    json_array('Set up in a standard plank, then actively pull elbows toward toes without moving them.','Squeeze glutes and quads hard enough that they shake.','Cap holds at 10–20 seconds — this is an intensity drill, not a duration one.') AS how_to_steps
  UNION ALL
  SELECT 'Long-Lever Plank',
    'Plank variant with the elbows placed further forward than the shoulders, increasing the lever arm and anti-extension demand on the core.',
    json_array('Start in a standard plank, then walk the elbows 4–6 inches forward.','Fight hard to keep the lower back from arching — ribs stay pulled down.','Expect to hold significantly less time than a standard plank.')
  UNION ALL
  SELECT 'Dead Bug Hold',
    'Supine anti-extension hold with opposite arm and opposite leg extended, low back pinned to the floor. A more accessible alternative to the hollow body hold.',
    json_array('Pin the low back down before extending anything.','Lower one arm overhead and the opposite leg toward the floor, holding short of contact.','Don''t let the ribs flare or the back arch as the limbs extend.')
  UNION ALL
  SELECT 'Copenhagen Plank',
    'Side plank variant with the top leg elevated on a bench, targeting the adductors of the top leg alongside the obliques. A groin-resilience staple.',
    json_array('Place the inside of the top ankle or knee on the bench; shorter lever (knee) is the regression.','Drive the top leg down into the bench to lift the hips.','Keep the hips square, shoulder stacked over elbow.')
  UNION ALL
  SELECT 'Single-Leg Glute Bridge Hold',
    'Unilateral version of the glute bridge hold, performed with one leg extended. Exposes side-to-side glute asymmetries.',
    json_array('Set up in a glute bridge, then extend one leg straight out.','Keep the hips level — don''t let the extended-leg side drop.','Drive through the heel of the planted foot, squeeze the working glute.')
  UNION ALL
  SELECT 'Single-Leg Calf Raise Hold',
    'Unilateral calf raise hold. Doubles the load on the working calf and exposes ankle-stability deficits.',
    json_array('Rise to the top of a single-leg calf raise, using fingertips against a wall for balance if needed.','Keep the standing ankle tracking straight.','If the ankle wobbles, drop the non-working foot and scale back to a two-leg hold.')
  UNION ALL
  SELECT 'Pistol Squat Hold',
    'Advanced unilateral hold at the bottom of a pistol squat — one leg folded deep, the other extended forward. Requires significant ankle mobility and single-leg strength.',
    json_array('Plant the working foot flat, extend the free leg forward.','Keep arms extended forward as a counterbalance.','If ankle mobility fails, hold a wall or rack for assistance.')
  UNION ALL
  SELECT 'Cossack Squat Hold',
    'Bottom-position hold of a deep lateral squat — one leg bent underneath, the other extended to the side. Trains adductor length and hip mobility under load.',
    json_array('Sit the hips down and back over the bent leg.','Extended leg stays straight, heel down, toes up if possible.','Chest up, don''t collapse forward.')
  UNION ALL
  SELECT 'Active Hang',
    'Hang from a pull-up bar with shoulders actively pulled down and packed — a scapular-retraction hold. The starting position for any pull-up.',
    json_array('Start from a dead hang, then pull the shoulder blades down and back without bending the elbows.','Chest rises slightly, shoulders move away from the ears.','Hold the packed position without letting elbows bend.')
  UNION ALL
  SELECT 'Tuck Front Lever Hold',
    'Entry-level front lever progression hung from a bar with knees tucked tight to the chest and the torso pulled horizontal. Trains the lats, core, and scapular depressors.',
    json_array('From an active hang, pull the knees to the chest and the hips up until the torso is horizontal.','Drive the arms straight down — don''t bend the elbows.','Keep the tuck tight; opening up too soon collapses the position.')
  UNION ALL
  SELECT 'Advanced Tuck Front Lever Hold',
    'Progression between tuck front lever and straddle front lever, with the hips opened so the thighs are roughly parallel to the floor but knees still bent.',
    json_array('Start in a tuck front lever, then open the hips until thighs are parallel to the floor.','Knees stay bent at roughly 90 degrees.','Lats pulled down hard; torso stays horizontal.')
  UNION ALL
  SELECT 'Tuck Back Lever Hold',
    'Entry-level back lever progression with the body inverted and tucked, facing away from the bar. Trains the biceps, anterior delts, and core anti-extension.',
    json_array('Invert into a tucked inverted hang first, then lower the torso away from the bar until the back is horizontal and facing down.','Knees tucked tight to the chest, hips at bar level.','Keep arms straight and locked throughout.')
  UNION ALL
  SELECT 'Ring Support Hold',
    'Straight-arm support hold on gymnastic rings at the top of a ring dip. Trains pressing stability, scapular control, and wrist strength. Highly unstable.',
    json_array('Press to full lockout on the rings, arms straight, body vertical.','Turn the rings slightly outward (external rotation) to lock out the shoulders.','Hollow body shape — ribs tucked, glutes squeezed.')
  UNION ALL
  SELECT 'Handstand Hold (Wall-Supported)',
    'Inverted isometric hold against a wall with hands shoulder-width, heels against the wall. Trains shoulder stability, wrist strength, and full-body tension upside down.',
    json_array('Kick up with hands roughly six inches from the wall, heels resting against it.','Push the floor away — shoulders fully shrugged up by the ears.','Squeeze glutes and abs; don''t let the low back arch off into a "banana."')
) e
WHERE d.key='isometric_holds'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- New Stretches and Mobility Holds
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Standing Hamstring Stretch' AS name,
    'Static stretch for the hamstrings, performed by hinging at the hips and folding forward over straight legs.' AS description,
    json_array('Hinge from the hips, not the low back.','Let the head and arms hang heavy.','Bend the knees slightly if the low back rounds aggressively.') AS how_to_steps
  UNION ALL
  SELECT 'Seated Forward Fold',
    'Seated hamstring and low-back stretch with legs extended, reaching toward the toes.',
    json_array('Sit tall first, then hinge forward from the hips.','Reach for the toes or shins — wherever the hands naturally land.','Don''t force a rounded back to go deeper.')
  UNION ALL
  SELECT 'Standing Quad Stretch',
    'Stretch for the front of the thigh, pulling one heel toward the glute while standing on the opposite leg.',
    json_array('Pull the heel toward the glute, knee pointing straight down.','Keep the knees close together — don''t let the working knee drift forward.','Squeeze the glute on the stretched side to deepen the hip-flexor stretch.')
  UNION ALL
  SELECT 'Couch Stretch',
    'Deep hip-flexor and quad stretch with the rear foot elevated against a wall or couch and the front leg in a lunge position.',
    json_array('Rear shin vertical against the wall, rear knee on a pad.','Tuck the pelvis under — squeeze the rear glute to intensify the hip-flexor stretch.','Stay tall through the torso; don''t lean forward.')
  UNION ALL
  SELECT 'Kneeling Hip Flexor Stretch',
    'Classic hip-flexor stretch in a half-kneeling position, shifting the hips forward over the front foot.',
    json_array('Half-kneeling, front foot flat, rear knee on a pad.','Tuck the pelvis and squeeze the rear glute before shifting forward.','Don''t just push the hips forward — the stretch comes from the posterior pelvic tilt.')
  UNION ALL
  SELECT 'Pigeon Pose',
    'Deep stretch for the glutes, piriformis, and outer hip, with the front leg folded under the torso and the rear leg extended straight back.',
    json_array('Front shin angled across the body, rear leg extended straight back with the top of the foot down.','Square the hips as much as possible — use a block under the front-side hip if it floats.','Walk the hands forward to deepen; keep the breath steady.')
  UNION ALL
  SELECT 'Seated Piriformis Stretch (Figure-4)',
    'Seated stretch for the piriformis and deep hip rotators, crossing one ankle over the opposite knee and folding forward.',
    json_array('Cross the ankle over the opposite knee, foot flexed to protect the knee.','Hinge from the hips and fold forward.','If the knee of the crossed leg sits high, support it with a cushion rather than forcing it down.')
  UNION ALL
  SELECT 'Doorway Chest Stretch',
    'Stretch for the pecs and anterior shoulder, with the forearm pressed against a doorframe and the body rotated away.',
    json_array('Forearm flat against the doorframe, elbow at roughly shoulder height.','Step the front foot through and rotate the torso away.','Try elbow heights above and below shoulder level to hit different pec fibers.')
  UNION ALL
  SELECT 'Lat Stretch (Overhead Reach)',
    'Stretch for the lats and lateral torso, reaching one arm overhead and bending sideways, often assisted by holding a rack or doorframe.',
    json_array('Grip a rack or doorframe with one hand overhead.','Sink the hips back and away from the grip.','Rotate the torso slightly to aim the stretch into the lat.')
  UNION ALL
  SELECT 'Overhead Triceps Stretch',
    'Stretch for the triceps and lats, reaching one arm overhead with the elbow bent and the hand reaching down the back.',
    json_array('Reach one arm overhead, bend the elbow so the hand drops behind the head.','Use the opposite hand to gently pull the elbow across and down.','Keep ribs tucked — don''t arch the back to cheat depth.')
  UNION ALL
  SELECT 'Neck Side Stretch',
    'Gentle lateral neck stretch, tilting the head toward one shoulder to stretch the upper trap and levator scapulae.',
    json_array('Tilt the ear toward the shoulder — don''t raise the shoulder to meet the ear.','Anchor the opposite shoulder down by sitting on the opposite hand.','Gentle pressure with the same-side hand only; no forceful pulls.')
  UNION ALL
  SELECT 'Standing Calf Stretch',
    'Stretch for the gastrocnemius, performed with the rear leg straight and heel pressed down, front leg bent forward.',
    json_array('Rear leg straight, heel firmly planted.','Front leg bent, lean forward from the ankle, not the waist.','Toes of the rear foot point straight forward.')
  UNION ALL
  SELECT 'Soleus Stretch (Bent-Knee Calf Stretch)',
    'Variant of the calf stretch targeting the soleus, performed with the rear knee bent rather than straight.',
    json_array('Same setup as a calf stretch, but bend the rear knee.','Keep the rear heel planted.','Sink straight down into the rear ankle.')
  UNION ALL
  SELECT 'Child''s Pose',
    'Kneeling rest position with hips sitting back onto the heels and arms extended forward. Gentle stretch for the low back, lats, and shoulders.',
    json_array('Knees wide, big toes together, hips sinking back to the heels.','Reach the arms long in front, chest heavy toward the floor.','Breathe into the low back.')
  UNION ALL
  SELECT '90/90 Hip Hold',
    'Seated hold with both hips at 90 degrees — front leg bent in front, rear leg bent to the side. Stretches internal rotation of the front hip and external rotation of the rear.',
    json_array('Sit with front shin parallel to the body, rear shin parallel to the body on the other side.','Keep the torso upright; hinge forward over the front leg to deepen.','Swap sides evenly — this asymmetry exposes mobility imbalances.')
  UNION ALL
  SELECT 'Frog Stretch',
    'Quadruped stretch with knees wide and feet flared, pressing the hips back toward the heels. Stretches the adductors and inner groin.',
    json_array('Knees wide, shins aligned with thighs, feet flared outward.','Rock the hips back toward the heels; find the first meaningful resistance and hold there.','Keep the torso supported on forearms.')
  UNION ALL
  SELECT 'Deep Squat Hold',
    'Bottom-position squat hold with feet flat, hips dropped as low as possible, elbows inside the knees pressing them open. Trains ankle, hip, and thoracic mobility simultaneously.',
    json_array('Feet roughly shoulder-width, toes turned slightly out.','Heels stay planted — elevate them on a plate if they lift.','Elbows inside the knees, gently pressing them open; chest up.')
  UNION ALL
  SELECT 'Thoracic Rotation Hold',
    'Quadruped hold rotating one arm up toward the ceiling, threading the thoracic spine. Targets mid-back rotation.',
    json_array('Start in quadruped, place one hand behind the head.','Rotate the elbow up toward the ceiling, opening the chest.','Hips stay square — the rotation comes from the mid-back, not the low back.')
  UNION ALL
  SELECT 'Cat-Cow Hold',
    'Quadruped spinal mobility drill alternating between full flexion (cat) and full extension (cow), holding each end-range briefly. Not a flowing sequence — hold each position for time.',
    json_array('Quadruped, wrists under shoulders, knees under hips.','Hold each end-range position for the programmed duration before switching.','Move the whole spine — not just the low back.')
  UNION ALL
  SELECT 'World''s Greatest Stretch Hold',
    'Multi-joint mobility hold in a deep lunge position with the same-side hand reaching up toward the ceiling, opening the thoracic spine. Held for time rather than flowed through.',
    json_array('Step one foot forward into a deep lunge, opposite hand planted inside the foot.','Reach the same-side arm up, rotating the torso open.','Hold the end position; don''t flow between sides until the duration ends.')
  UNION ALL
  SELECT 'Seated Butterfly Hold',
    'Seated adductor and groin stretch with soles of the feet together and knees dropped out to the sides.',
    json_array('Sit tall, soles of the feet together, hands on the ankles.','Let the knees drop under their own weight — don''t force them down.','Hinge forward from the hips to deepen, keeping the back long.')
) e
WHERE d.key='stretching'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Sports exercises (racket sports, team sports, combat sports)
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'tennis' AS disc, 'Tennis Match' AS name,
    'A full singles or doubles match, or an internal practice match. Use periods as sets.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'tennis', 'Tennis Drill',
    'Technique and footwork drill blocks — groundstrokes, volleys, approach shots, or movement patterns fed by a partner, coach, or ball machine.',
    json_array('Split-step the moment the feeder makes contact.','Take the racquet back on the turn, not after the bounce.','Contact point in front of the body, not beside it.','Recover to the center after every shot, even in drill mode.')
  UNION ALL
  SELECT 'tennis', 'Tennis Serve Practice',
    'Dedicated serving session — baskets of balls from one or both sides, flats, slices, and kicks.',
    json_array('Same ball toss every time — in front, slightly to the right for a righty.','Trophy position before the drop — don''t rush the load.','Hit up and out, not down on the ball.','Land inside the baseline with the hitting leg.')
  UNION ALL
  SELECT 'tennis', 'Tennis Return Practice',
    'Return-of-serve reps against a live server or ball machine. Focus on read, split, and short swing.',
    json_array('Split-step earlier than you think — before the server makes contact.','Keep the takeback short — no full loop on a first serve.','Neutralize first, attack second serves.','Pick a target before the ball is tossed.')
  UNION ALL
  SELECT 'badminton', 'Badminton Match',
    'A full singles or doubles match played to standard game format, or a rally-based practice game.',
    NULL
  UNION ALL
  SELECT 'badminton', 'Badminton Drill',
    'Targeted drill blocks — clears, drops, smashes, net play, or multi-shuttle footwork patterns fed by a partner or coach.',
    json_array('Ready position with racquet up, weight on the balls of the feet.','Recover to center court after every shot.','Wrist and forearm do the work on overheads, not the shoulder.','Lunge and push back — don''t step and stop at the net.')
  UNION ALL
  SELECT 'table_tennis', 'Table Tennis Match',
    'A full match played to standard game format, or a practice game against a partner or robot.',
    NULL
  UNION ALL
  SELECT 'table_tennis', 'Table Tennis Drill',
    'Multi-ball or partner-fed drill blocks — forehand/backhand loops, blocks, pushes, or footwork patterns.',
    json_array('Bent knees, weight forward, paddle up at all times.','Rotate from the waist on loops — don''t arm the ball.','Recover to neutral after every stroke.','Read the opponent''s paddle angle, not the ball off the bounce.')
  UNION ALL
  SELECT 'volleyball', 'Volleyball Match',
    'A full match or scrimmage, indoor or beach. Use periods as sets.',
    NULL
  UNION ALL
  SELECT 'volleyball', 'Volleyball Drill',
    'Drill blocks — passing, setting, hitting, blocking, or serve-receive patterns fed by a coach or partner.',
    json_array('Low, balanced platform on every pass — don''t swing the arms.','Square shoulders to the target before contact.','Jump off two feet on attacks, not one.','Call every ball, even in drills.')
  UNION ALL
  SELECT 'squash', 'Squash Match',
    'A full match played to 11 or 15, or a practice game against a regular partner. Use periods as games.',
    NULL
  UNION ALL
  SELECT 'squash', 'Squash Drill',
    'Solo or partner drill blocks — length, boasts, volleys, or ghosting patterns.',
    json_array('Keep the T — every shot should aim to return you there.','Swing through the ball on a straight line parallel to the side wall.','Watch the ball onto the strings, not off them.','Stay low on the split — don''t stand tall between rallies.')
  UNION ALL
  SELECT 'padel', 'Padel Match',
    'A full doubles match, or a practice game with a regular pairing. Use periods as sets.',
    NULL
  UNION ALL
  SELECT 'padel', 'Padel Drill',
    'Partner-fed drill blocks — wall plays, volleys at the net, lobs, and bandeja/vibora patterns.',
    json_array('Hold the net position — don''t retreat unless lobbed.','Let the ball come off the wall before playing defensively.','Flat, short swings — no topspin loops.','Communicate on every ball with your partner — "mine," "yours," "out."')
  UNION ALL
  SELECT 'cricket', 'Cricket Match',
    'A full match — T20, ODI, multi-day, or club — or a practice match. Use periods as innings or sessions.',
    NULL
  UNION ALL
  SELECT 'cricket', 'Cricket Practice',
    'A net or field practice session — batting, bowling, and fielding work.',
    NULL
  UNION ALL
  SELECT 'ice_hockey', 'Ice Hockey Match',
    'A full game or scrimmage. Use periods as game periods.',
    NULL
  UNION ALL
  SELECT 'ice_hockey', 'Ice Hockey Practice',
    'A full team practice — skating, passing, shooting, systems, and scrimmage.',
    NULL
  UNION ALL
  SELECT 'baseball', 'Baseball Game',
    'A full game or scrimmage. Use periods as innings.',
    NULL
  UNION ALL
  SELECT 'baseball', 'Baseball Practice',
    'A full team practice — batting, fielding, pitching, and situational work.',
    NULL
  UNION ALL
  SELECT 'american_football', 'American Football Game',
    'A full game or scrimmage. Use periods as quarters.',
    NULL
  UNION ALL
  SELECT 'american_football', 'American Football Practice',
    'A full team practice — individual drills, position work, and team periods.',
    NULL
  UNION ALL
  SELECT 'rugby', 'Rugby Match',
    'A full match — 15s, 10s, or 7s — or a practice match. Use periods as halves.',
    NULL
  UNION ALL
  SELECT 'rugby', 'Rugby Training',
    'A full team training session — fitness, skills, phase play, and contact work.',
    NULL
  UNION ALL
  SELECT 'lacrosse', 'Lacrosse Game',
    'A full game or scrimmage — men''s field, women''s field, or box. Use periods as quarters.',
    NULL
  UNION ALL
  SELECT 'lacrosse', 'Lacrosse Practice',
    'A full team practice — stick work, shooting, defense, and team periods.',
    NULL
) e ON d.key = e.disc
WHERE NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Update existing sports exercise descriptions (for pre-existing rows)
UPDATE app_exercise SET
  description = 'A full singles or doubles match, or an internal practice match. Use periods as sets.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Tennis Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Technique and footwork drill blocks — groundstrokes, volleys, approach shots, or movement patterns fed by a partner, coach, or ball machine.',
  how_to_steps = json_array('Split-step the moment the feeder makes contact.','Take the racquet back on the turn, not after the bounce.','Contact point in front of the body, not beside it.','Recover to the center after every shot, even in drill mode.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Tennis Drill' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full match or scrimmage, indoor or beach. Use periods as sets.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Volleyball Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'Drill blocks — passing, setting, hitting, blocking, or serve-receive patterns fed by a coach or partner.',
  how_to_steps = json_array('Low, balanced platform on every pass — don''t swing the arms.','Square shoulders to the target before contact.','Jump off two feet on attacks, not one.','Call every ball, even in drills.'),
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Volleyball Drill' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full singles or doubles match played to standard game format, or a rally-based practice game.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Badminton Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full match played to standard game format, or a practice game against a partner or robot.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Table Tennis Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full match — T20, ODI, multi-day, or club — or a practice match. Use periods as innings or sessions.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Cricket Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full game or scrimmage. Use periods as game periods.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Ice Hockey Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full game or scrimmage. Use periods as innings.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Baseball Game' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full game or scrimmage. Use periods as quarters.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'American Football Game' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full match — 15s, 10s, or 7s — or a practice match. Use periods as halves.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Rugby Match' AND owner_user_id IS NULL;

UPDATE app_exercise SET
  description = 'A full game or scrimmage — men''s field, women''s field, or box. Use periods as quarters.',
  updated_at_ms = (strftime('%s','now') * 1000)
WHERE name = 'Lacrosse Game' AND owner_user_id IS NULL;

-- BJJ exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'BJJ Class' AS name,
    'A full scheduled class — warm-up, technique instruction, drilling, and rolling. Log as one session; use periods for class segments if desired.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'BJJ Drilling',
    'Partner drilling blocks — repping a specific technique, transition, or sequence without resistance.',
    json_array('Drill the movement, not the outcome — no muscling reps.','Switch partners regularly for different body types.','Keep a count — quality reps per round matter more than time.','If the technique fails, ask before repeating it wrong.')
  UNION ALL
  SELECT 'BJJ Rolling',
    'Live rolling rounds with rotating partners — open sparring at a negotiated intensity.',
    NULL
  UNION ALL
  SELECT 'BJJ Positional Sparring',
    'Rolling rounds starting from a fixed position — guard, side control, mount, back — reset to the starting position on escape or submission.',
    json_array('Pick a position and stick to it for the whole round.','Lose the position before you reset — don''t bail early.','Track what works and what doesn''t during the round, not after.','Alternate top and bottom between rounds.')
  UNION ALL
  SELECT 'BJJ Guard Retention Practice',
    'Partner drill — the bottom player defends the guard against systematic passing attempts, reset when passed.',
    json_array('Hips first, legs second — frame with the hips before the knees.','Keep at least one point of connection with the passer at all times.','Re-guard before recovering offense — don''t scramble to attack.','Breathe through the tight positions, don''t hold breath.')
  UNION ALL
  SELECT 'BJJ Guard Passing Practice',
    'Partner drill — the top player works through a passing sequence against a defending guard, reset on pass or sweep.',
    json_array('Control grips or frames before moving the hips.','Kill one leg before trying to pass around or over.','Stay heavy through the shoulder, not the hands.','If the pass stalls, reset pressure instead of forcing.')
  UNION ALL
  SELECT 'BJJ Submission Practice',
    'Targeted drilling of specific submissions from a fixed position — entries, finishes, and common defenses.',
    json_array('Drill the setup, not just the finish.','Control the posture and grips before committing to the submission.','Finish with technique — no cranking for leverage.','Drill both the attack and the common escape.')
) e
WHERE d.key='bjj'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Muay Thai exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Muay Thai Class' AS name,
    'A full scheduled class — shadow, pads, bag work, clinch, and optional sparring. Log as one session.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Muay Thai Pad Work',
    'Timed rounds on Thai pads with a coach — kicks, knees, elbows, and punch-kick combinations.',
    json_array('Turn the hip fully on every kick — the shin follows the hip.','Return to stance on the same line you left, not wider.','Step, then strike — never the other way around.','Close combinations with a defensive movement.')
  UNION ALL
  SELECT 'Muay Thai Bag Work',
    'Timed rounds on a banana bag — full toolkit of punches, kicks, knees, and elbows with movement between combinations.',
    json_array('Hit hard once, then reset — no spammed kicks.','Check into every kick — balance on landing matters more than power.','Include knees and elbows, not only kicks and punches.','Work around the bag — don''t stand square.')
  UNION ALL
  SELECT 'Muay Thai Clinch Practice',
    'Timed rounds of clinch work with a partner — hand fighting, posture control, knees, sweeps, and turns.',
    json_array('Fight for the inside position on the head and neck.','Stay tall — don''t let the partner bend you forward.','Short, snapping knees from the hip, not full extensions.','Reset posture after every exchange.')
  UNION ALL
  SELECT 'Muay Thai Sparring',
    'Live rounds with a partner at agreed intensity — technical sparring or harder prep rounds with shin guards and control.',
    NULL
) e
WHERE d.key='muay_thai'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- MMA exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'MMA Class' AS name,
    'A full scheduled class — mixed striking, grappling, and transition work. Log as one session.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'MMA Pad Work',
    'Timed rounds on pads with striking plus takedown entries, cage work, or ground transitions mixed in.',
    json_array('Treat every strike as a setup for the next phase — takedown, clinch, or exit.','Hands back to guard after every combination — the fight isn''t over.','Level change realistically — don''t fake shots.','Finish combinations with a distance reset.')
  UNION ALL
  SELECT 'MMA Sparring',
    'Live rounds with a partner covering all phases — striking, clinch, takedowns, and ground — at agreed intensity.',
    NULL
  UNION ALL
  SELECT 'MMA Situational Sparring',
    'Live rounds starting from a fixed situation — back against the cage, bottom guard, in the clinch — reset to the starting position.',
    json_array('Pick the situation before the round, don''t drift between them.','Both partners fight honestly from the position — no easing off.','Reset the instant the situation ends — don''t keep rolling past it.','Alternate which role you start in between rounds.')
) e
WHERE d.key='mma'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Karate exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Karate Class' AS name,
    'A full scheduled class — kihon, kata, and kumite. Log as one session.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Karate Kumite',
    'Sparring rounds — point sparring, continuous sparring, or controlled full-contact depending on style.',
    NULL
  UNION ALL
  SELECT 'Karate Kata Practice',
    'Solo practice of prescribed forms — timed blocks of kata repetitions at varying intensities.',
    json_array('Full kime on every technique — no throwaway reps.','Breathe with the technique, not against it.','Stances drop as low as they do in the first rep; don''t ride high when tired.','Visualize the opponent at every count.')
) e
WHERE d.key='karate'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Judo exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Judo Class' AS name,
    'A full scheduled class — ukemi, uchi-komi, drilling, and randori. Log as one session.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Judo Randori',
    'Live sparring rounds with rotating partners — standing, ground, or combined depending on the session''s focus.',
    NULL
  UNION ALL
  SELECT 'Judo Uchi-Komi',
    'Repetitive throw entries with a partner — no follow-through, focused on grip, kuzushi, and entry position.',
    json_array('Break the partner''s balance before stepping in.','Get under the center of gravity on every entry — don''t reach.','Match tempo to your partner — don''t rush.','Alternate sides between rounds.')
  UNION ALL
  SELECT 'Judo Nage-Komi',
    'Partner drilling of full throws with follow-through, typically onto a crash mat. Technique reps at varying intensities.',
    json_array('Commit fully to the throw — half-throws build bad habits.','Maintain grip through the landing, don''t release early.','Alternate who throws between rounds.','Drill breakfalls as part of the rep, not as an afterthought.')
) e
WHERE d.key='judo'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Soccer exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Soccer Match' AS name,
    'A full match — competitive, small-sided, or internal — played at standard or reduced duration. Use periods as halves or quarters.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Soccer Training',
    'A full team training session — warm-up, technical work, tactical phases, and scrimmages.',
    NULL
  UNION ALL
  SELECT 'Soccer Shooting Practice',
    'Dedicated finishing drill blocks — shots from distance, inside the box, one-touch finishes, or set-piece rehearsal.',
    json_array('Plant foot next to the ball, not behind it.','Strike through the middle of the ball for power, under for lift.','Follow through toward the target, don''t cut the swing short.','Finish into the corners, not down the goalkeeper''s center.')
  UNION ALL
  SELECT 'Soccer Passing Practice',
    'Drill blocks focused on passing patterns — short, long, switches, or combination play under varying pressure.',
    json_array('Open the body before receiving — don''t square up to the passer.','Weight of pass first, accuracy second.','Scan before the ball arrives, not after.','Receive across the body into the next action.')
) e
WHERE d.key='soccer'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Basketball exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Basketball Game' AS name,
    'A full game — full court or half-court, competitive or pickup. Use periods as quarters or halves.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Basketball Practice',
    'A full team or solo practice session — skill work, plays, and scrimmage.',
    NULL
  UNION ALL
  SELECT 'Basketball Shooting Practice',
    'Dedicated shooting session — catch-and-shoot, off-the-dribble, spot-up, or free throw reps.',
    json_array('Feet set before the catch — jump from a balanced base.','Elbow under the ball, not out to the side.','Follow through with a full wrist snap — hold it until the ball lands.','Same form on every rep, regardless of distance.')
  UNION ALL
  SELECT 'Basketball Free Throw Practice',
    'Dedicated free throw reps — same routine every shot, tracked as made/missed.',
    json_array('Use the same pre-shot routine on every attempt.','Align the shooting foot with the center of the rim.','Eyes on the back of the rim, not the front.','Shoot with arc — flat shots have no margin.')
  UNION ALL
  SELECT 'Basketball Ball Handling Practice',
    'Solo dribbling drill blocks — stationary, moving, two-ball, or cone patterns.',
    json_array('Keep the dribble at or below the hip.','Eyes up — use peripheral vision for the ball.','Push the ball, don''t slap it.','Change pace within the drill — not just speed but rhythm.')
) e
WHERE d.key='basketball'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Golf exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Golf Round' AS name,
    'A full round — 9 or 18 holes — stroke play, match play, or casual. Use periods as nines or sets of holes.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Golf Range Practice',
    'A driving range session — full swings, club-by-club work, or targeted shot shaping.',
    json_array('Go through a full pre-shot routine on every ball, not just the first few.','Hit to specific targets, not just out into the range.','Change clubs every few shots rather than bucket-bashing one.','Log misses as left/right/thin/fat — track patterns, not just outcomes.')
  UNION ALL
  SELECT 'Golf Short Game Practice',
    'Dedicated session around the green — chipping, pitching, and bunker work from varied lies and distances.',
    json_array('Land the ball on a chosen spot, not at the flag.','Weight forward on chips — don''t try to scoop the ball up.','Accelerate through contact on bunker shots.','Vary the club for chips — don''t default to one.')
  UNION ALL
  SELECT 'Golf Putting Practice',
    'Dedicated putting session — distance control, lag putting, short putts, or breaking putts.',
    json_array('Read the putt, pick a line, commit — no second-guessing over the ball.','Match stroke length to distance, not swing speed.','Keep the head still through contact — don''t track the ball.','Drill short putts at the end when tired, not at the start.')
) e
WHERE d.key='golf'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

-- Climbing exercises
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, how_to_steps, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description, e.how_to_steps,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Climbing Session' AS name,
    'An open-ended climbing session — gym or outdoor, bouldering or roped. Use periods as problem/route attempts if tracking.' AS description,
    NULL AS how_to_steps
  UNION ALL
  SELECT 'Climbing Projecting',
    'Working a specific problem or route at or near the limit — attempts interspersed with rest.',
    json_array('Rest fully between attempts — 3–5 minutes minimum on hard projects.','Work the project in sections before trying it linked.','Rehearse the sequence mentally before each attempt.','Call it after 4–5 quality attempts — diminishing returns after that.')
  UNION ALL
  SELECT 'Climbing Volume',
    'High-quantity climbing at sub-maximal grades — mileage for technique, capacity, and movement literacy.',
    json_array('Stay 2–3 grades below limit — this isn''t projecting.','Focus on footwork — silent feet, weight through the toe.','Climb efficiently, not fast — static where possible.','Stop before form breaks down, not after.')
  UNION ALL
  SELECT 'Climbing Hangboard Session',
    'Structured hangboard protocol — max hangs, repeaters, or specific grip work.',
    json_array('Warm up fully before touching the board — no cold max hangs.','Shoulders engaged, not shrugged — active hang only.','Stop the set before form degrades, not when time expires.','Do not hangboard on fatigued fingers — reschedule if needed.')
) e
WHERE d.key='climbing'
AND NOT EXISTS (
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
  -- Racket sports
  'Tennis Match', 'Tennis Drill', 'Tennis Serve Practice', 'Tennis Return Practice',
  'Volleyball Match', 'Volleyball Drill',
  'Badminton Match', 'Badminton Drill',
  'Table Tennis Match', 'Table Tennis Drill',
  'Squash Match', 'Squash Drill',
  'Padel Match', 'Padel Drill',
  -- Team sports
  'Cricket Match', 'Cricket Practice',
  'Ice Hockey Match', 'Ice Hockey Practice',
  'Baseball Game', 'Baseball Practice',
  'American Football Game', 'American Football Practice',
  'Rugby Match', 'Rugby Training',
  'Lacrosse Game', 'Lacrosse Practice',
  'Soccer Match', 'Soccer Training', 'Soccer Shooting Practice', 'Soccer Passing Practice',
  'Basketball Game', 'Basketball Practice', 'Basketball Shooting Practice',
  'Basketball Free Throw Practice', 'Basketball Ball Handling Practice',
  -- Combat sports
  'BJJ Class', 'BJJ Drilling', 'BJJ Rolling', 'BJJ Positional Sparring',
  'BJJ Guard Retention Practice', 'BJJ Guard Passing Practice', 'BJJ Submission Practice',
  'Muay Thai Class', 'Muay Thai Pad Work', 'Muay Thai Bag Work',
  'Muay Thai Clinch Practice', 'Muay Thai Sparring',
  'MMA Class', 'MMA Pad Work', 'MMA Sparring', 'MMA Situational Sparring',
  'Karate Class', 'Karate Kumite', 'Karate Kata Practice',
  'Judo Class', 'Judo Randori', 'Judo Uchi-Komi', 'Judo Nage-Komi',
  -- Individual sports
  'Golf Round', 'Golf Range Practice', 'Golf Short Game Practice', 'Golf Putting Practice',
  'Climbing Session', 'Climbing Projecting', 'Climbing Volume', 'Climbing Hangboard Session'
) AND e.owner_user_id IS NULL;

INSERT OR IGNORE INTO app_exercise_capability (exercise_id, capability)
SELECT e.id, 'rounds' FROM app_exercise e WHERE e.name IN (
  -- Racket sports
  'Tennis Match', 'Tennis Drill', 'Tennis Serve Practice', 'Tennis Return Practice',
  'Volleyball Match', 'Volleyball Drill',
  'Badminton Match', 'Badminton Drill',
  'Table Tennis Match', 'Table Tennis Drill',
  'Squash Match', 'Squash Drill',
  'Padel Match', 'Padel Drill',
  -- Team sports
  'Cricket Match', 'Cricket Practice',
  'Ice Hockey Match', 'Ice Hockey Practice',
  'Baseball Game', 'Baseball Practice',
  'American Football Game', 'American Football Practice',
  'Rugby Match', 'Rugby Training',
  'Lacrosse Game', 'Lacrosse Practice',
  'Soccer Match', 'Soccer Training', 'Soccer Shooting Practice', 'Soccer Passing Practice',
  'Basketball Game', 'Basketball Practice', 'Basketball Shooting Practice',
  'Basketball Free Throw Practice', 'Basketball Ball Handling Practice',
  -- Combat sports
  'BJJ Class', 'BJJ Drilling', 'BJJ Rolling', 'BJJ Positional Sparring',
  'BJJ Guard Retention Practice', 'BJJ Guard Passing Practice', 'BJJ Submission Practice',
  'Muay Thai Class', 'Muay Thai Pad Work', 'Muay Thai Bag Work',
  'Muay Thai Clinch Practice', 'Muay Thai Sparring',
  'MMA Class', 'MMA Pad Work', 'MMA Sparring', 'MMA Situational Sparring',
  'Karate Class', 'Karate Kumite', 'Karate Kata Practice',
  'Judo Class', 'Judo Randori', 'Judo Uchi-Komi', 'Judo Nage-Komi',
  -- Individual sports
  'Golf Round', 'Golf Range Practice', 'Golf Short Game Practice', 'Golf Putting Practice',
  'Climbing Session', 'Climbing Projecting', 'Climbing Volume', 'Climbing Hangboard Session'
) AND e.owner_user_id IS NULL;

-- ============================================================================
-- DEFAULT ROUND DURATIONS
-- ============================================================================
-- Sets the sport-specific default period/half/set length for round-based exercises.
-- NULL = use app-wide default (180s / 3 min). Only set for sports where the natural
-- playing unit differs meaningfully from a 3-min boxing round.
-- See Exercise.defaultRoundDurationSecs in lib/data/models/models.dart.
-- Boxing exercises intentionally left as NULL (they use the 3-min default).
-- Combat sport new entries (BJJ, Muay Thai, MMA, Karate, Judo) also NULL.

-- Racket sports
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
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Badminton Drill'         AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min game
  WHERE name = 'Table Tennis Match'      AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Table Tennis Drill'      AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min game
  WHERE name = 'Squash Match'            AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Squash Drill'            AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 1200  -- 20-min set equivalent
  WHERE name = 'Padel Match'             AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min drill
  WHERE name = 'Padel Drill'             AND owner_user_id IS NULL;
-- Team sports
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
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Rugby Training'          AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 720   -- 12-min quarter
  WHERE name = 'Lacrosse Game'           AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Lacrosse Practice'       AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Ice Hockey Practice'     AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'American Football Practice' AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Baseball Practice'       AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Cricket Practice'        AND owner_user_id IS NULL;
-- Soccer
UPDATE app_exercise SET default_round_duration_secs = 2700  -- 45-min half
  WHERE name = 'Soccer Match'            AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min phase
  WHERE name = 'Soccer Training'         AND owner_user_id IS NULL;
-- Basketball
UPDATE app_exercise SET default_round_duration_secs = 720   -- 12-min quarter (NBA)
  WHERE name = 'Basketball Game'         AND owner_user_id IS NULL;
UPDATE app_exercise SET default_round_duration_secs = 900   -- 15-min block
  WHERE name = 'Basketball Practice'     AND owner_user_id IS NULL;
-- Golf
UPDATE app_exercise SET default_round_duration_secs = 5400  -- 90-min per 9 holes
  WHERE name = 'Golf Round'              AND owner_user_id IS NULL;
-- Climbing
UPDATE app_exercise SET default_round_duration_secs = 600   -- 10-min block
  WHERE name = 'Climbing Session'        AND owner_user_id IS NULL;

COMMIT;
