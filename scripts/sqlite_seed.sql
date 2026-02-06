PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

-- Units (idempotent)
INSERT OR IGNORE INTO app_unit (id, key, name, unit_type, created_at_ms)
VALUES
  (lower(hex(randomblob(16))), 'kg', 'Kilogram', 'mass', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'lb', 'Pound', 'mass', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'sec', 'Second', 'time', (strftime('%s','now') * 1000));

-- Metric definitions (idempotent)
INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, applies_to_effort_kind, created_at_ms)
SELECT lower(hex(randomblob(16))), 'reps', 'Repetitions', 'int', NULL, 1, 'set', (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='reps');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, applies_to_effort_kind, created_at_ms)
SELECT lower(hex(randomblob(16))), 'weight_kg', 'Weight (kg)', 'real', NULL, 1, 'set', (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='weight_kg');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, applies_to_effort_kind, created_at_ms)
SELECT lower(hex(randomblob(16))), 'duration_sec', 'Duration (sec)', 'int', NULL, 1, 'interval', (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='duration_sec');

-- Categories
INSERT OR IGNORE INTO app_sport_category (id, key, name, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'strength', 'Strength', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'cardio', 'Cardio/Endurance', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'combat', 'Martial Arts/Combat', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'mobility', 'Mobility/Isometric', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));

-- Disciplines (using category lookup)
INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'running', 'Running', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='running');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'cycling', 'Cycling', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='cycling');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'rowing', 'Rowing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='cardio' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='rowing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'boxing', 'Boxing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='boxing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bjj', 'Brazilian Jiu-Jitsu', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bjj');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'muay_thai', 'Muay Thai', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='muay_thai');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'powerlifting', 'Powerlifting', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='powerlifting');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bodybuilding', 'Bodybuilding', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bodybuilding');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'calisthenics', 'Calisthenics', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='calisthenics');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'yoga', 'Yoga', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='mobility' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='yoga');

-- Equipment
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Barbell', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Kettlebell', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Treadmill', (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_equipment (id, name, created_at_ms)
VALUES (lower(hex(randomblob(16))), 'Heavy Bag', (strftime('%s','now') * 1000));

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
INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Run', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='running' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Run' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Treadmill Run', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='running' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Treadmill Run' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Bench Press', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='powerlifting' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Bench Press' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Back Squat', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='powerlifting' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Back Squat' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Pull-up', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='calisthenics' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Pull-up' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Couch Stretch', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='yoga' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Couch Stretch' AND owner_user_id IS NULL);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, 'Heavy Bag Rounds', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
WHERE d.key='boxing' AND NOT EXISTS (SELECT 1 FROM app_exercise WHERE name='Heavy Bag Rounds' AND owner_user_id IS NULL);

-- Exercise-Muscle Group relationships
-- Note: These INSERT statements use subqueries to look up IDs by name.
-- In production, you may want to use fixed UUIDs for consistency across devices.

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

COMMIT;
