PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

-- Units (idempotent)
INSERT OR IGNORE INTO app_unit (id, key, name, unit_type, created_at_ms)
VALUES
  (lower(hex(randomblob(16))), 'kg', 'Kilogram', 'weight', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'lb', 'Pound', 'weight', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'sec', 'Second', 'time', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'min', 'Minute', 'time', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'm', 'Meter', 'distance', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'km', 'Kilometer', 'distance', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'mi', 'Mile', 'distance', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'cal', 'Calorie', 'energy', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'bpm', 'Beats per Minute', 'heart_rate', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'reps', 'Repetitions', 'count', (strftime('%s','now') * 1000)),
  (lower(hex(randomblob(16))), 'rounds', 'Rounds', 'count', (strftime('%s','now') * 1000));

-- Metric definitions (idempotent)
INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'reps', 'Repetitions', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='reps');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'weight', 'Weight', 'real', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='weight');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'rpe', 'RPE (Rate of Perceived Exertion)', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='rpe');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'duration', 'Duration', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='duration');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'rest', 'Rest Time', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='rest');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'distance', 'Distance', 'real', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='distance');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'pace', 'Pace (min/km)', 'real', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='pace');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'rounds', 'Rounds', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='rounds');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'round_duration', 'Round Duration', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='round_duration');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'score', 'Score', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='score');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'quality', 'Quality Rating', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='quality');

INSERT INTO app_metric_definition (id, key, name, data_type, default_unit_id, is_core, created_at_ms)
SELECT lower(hex(randomblob(16))), 'heart_rate', 'Heart Rate', 'int', NULL, 1, (strftime('%s','now') * 1000)
WHERE NOT EXISTS (SELECT 1 FROM app_metric_definition WHERE key='heart_rate');

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

-- Categories (with new fields)
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'cardio_endurance', 'Cardio / Endurance', 'Running, cycling, swimming, rowing', 'directions_run', 1, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'strength_resistance', 'Strength / Resistance', 'Weightlifting, bodybuilding, powerlifting', 'fitness_center', 2, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'martial_arts_combat', 'Martial Arts / Combat', 'Boxing, BJJ, Muay Thai, wrestling', 'sports_mma', 3, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'sports_games', 'Sports / Games', 'Soccer, basketball, tennis, general sports', 'sports_soccer', 4, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'mobility_flexibility', 'Mobility / Flexibility', 'Yoga, stretching, mobility work', 'self_improvement', 5, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));
INSERT OR IGNORE INTO app_sport_category (id, key, name, description, icon_name, sort_order, created_at_ms, updated_at_ms)
VALUES (lower(hex(randomblob(16))), 'recovery_rehab', 'Recovery / Rehab', 'Active recovery, physical therapy, rehab', 'spa', 6, (strftime('%s','now') * 1000), (strftime('%s','now') * 1000));

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
SELECT lower(hex(randomblob(16))), c.id, 'boxing', 'Boxing', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='martial_arts_combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='boxing');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bjj', 'Brazilian Jiu-Jitsu', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='martial_arts_combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bjj');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'muay_thai', 'Muay Thai', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='martial_arts_combat' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='muay_thai');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'powerlifting', 'Powerlifting', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength_resistance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='powerlifting');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'bodybuilding', 'Bodybuilding', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength_resistance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='bodybuilding');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'weightlifting', 'Olympic Weightlifting', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength_resistance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='weightlifting');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'calisthenics', 'Calisthenics', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='strength_resistance' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='calisthenics');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'soccer', 'Soccer', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports_games' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='soccer');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'basketball', 'Basketball', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='sports_games' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='basketball');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'yoga', 'Yoga', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='mobility_flexibility' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='yoga');

INSERT INTO app_discipline (id, category_id, key, name, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), c.id, 'stretching', 'Stretching', (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_sport_category c
WHERE c.key='mobility_flexibility' AND NOT EXISTS (SELECT 1 FROM app_discipline WHERE key='stretching');

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
  SELECT 'Easy Run', 'Low intensity steady run' UNION ALL
  SELECT 'Long Run', 'Extended endurance run' UNION ALL
  SELECT 'Tempo Run', 'Sustained threshold pace run' UNION ALL
  SELECT 'Interval Run', 'Repeated fast efforts with rest' UNION ALL
  SELECT 'Hill Repeats', 'Uphill running intervals' UNION ALL
  SELECT 'Fartlek', 'Unstructured pace variation run' UNION ALL
  SELECT 'Recovery Run', 'Very easy recovery pace run' UNION ALL
  SELECT 'Track Repeats', 'Measured distance intervals on track' UNION ALL
  SELECT 'Progression Run', 'Run with gradually increasing pace' UNION ALL
  SELECT 'Time Trial', 'Max effort over fixed distance or time'
) e
WHERE d.key='running'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Barbell Squat', 'Back squat with barbell' UNION ALL
  SELECT 'Bench Press', 'Barbell bench press' UNION ALL
  SELECT 'Deadlift', 'Conventional barbell deadlift' UNION ALL
  SELECT 'Overhead Press', 'Standing barbell shoulder press' UNION ALL
  SELECT 'Pull-Up', 'Bodyweight vertical pull' UNION ALL
  SELECT 'Lat Pulldown', 'Cable vertical pull' UNION ALL
  SELECT 'Dumbbell Row', 'Single-arm dumbbell row' UNION ALL
  SELECT 'Leg Press', 'Machine-based squat pattern' UNION ALL
  SELECT 'Lateral Raise', 'Dumbbell shoulder isolation' UNION ALL
  SELECT 'Triceps Pressdown', 'Cable triceps extension'
) e
WHERE d.key='bodybuilding'
AND NOT EXISTS (
  SELECT 1 FROM app_exercise WHERE name=e.name AND owner_user_id IS NULL
);

INSERT INTO app_exercise (id, owner_user_id, discipline_id, name, description, created_at_ms, updated_at_ms)
SELECT lower(hex(randomblob(16))), NULL, d.id, e.name, e.description,
       (strftime('%s','now') * 1000), (strftime('%s','now') * 1000)
FROM app_discipline d
JOIN (
  SELECT 'Heavy Bag Rounds', 'Boxing heavy bag work' UNION ALL
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
  SELECT 'Plank Hold', 'Isometric core hold' UNION ALL
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
  SELECT 'Plank Hold', 'Isometric core hold' UNION ALL
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

COMMIT;
