import 'package:sqflite/sqflite.dart';

/// Apply incremental migrations when upgrading database versions.
/// For now this is a placeholder that can be extended with real migration
/// SQL per version.
Future<void> applyMigrations(Database db, int oldVersion, int newVersion) async {
  if (oldVersion >= newVersion) return;

  // Example migration pattern:
  // if (oldVersion < 2) {
  //   await db.execute("ALTER TABLE app_example ADD COLUMN new_col TEXT DEFAULT ''");
  // }

  if (oldVersion < 2) {
    await db.execute(
      'ALTER TABLE app_training_session ADD COLUMN modality TEXT',
    );
    await db.execute(
      'ALTER TABLE app_training_session ADD COLUMN intent TEXT',
    );
  }

  if (oldVersion < 3) {
    await db.execute(
      'ALTER TABLE app_training_session ADD COLUMN session_feeling INTEGER',
    );
    await db.execute(
      'ALTER TABLE app_training_session ADD COLUMN quality_rating INTEGER',
    );
    await db.execute(
      'ALTER TABLE app_effort_observation ADD COLUMN rpe_rating INTEGER',
    );
    await db.execute(
      'ALTER TABLE app_effort_observation ADD COLUMN rest_duration_ms INTEGER',
    );
  }

  if (oldVersion < 4) {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_entry_rest (
        id            TEXT    NOT NULL PRIMARY KEY,
        effort_id     TEXT    NOT NULL,
        entry_index   INTEGER NOT NULL,
        rest_start_ms INTEGER NOT NULL,
        rest_end_ms   INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS UX_entry_rest_effort_index ON app_entry_rest(effort_id, entry_index)',
    );
  }

  if (oldVersion < 5) {
    await db.execute('ALTER TABLE app_exercise ADD COLUMN how_to_steps TEXT');
    await db.execute(
      'ALTER TABLE app_exercise ADD COLUMN image_asset_path TEXT',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_exercise_note (
        id              TEXT    NOT NULL PRIMARY KEY,
        exercise_id     TEXT    NOT NULL,
        note            TEXT    NOT NULL,
        last_session_id TEXT,
        created_at_ms   INTEGER NOT NULL,
        updated_at_ms   INTEGER NOT NULL,
        FOREIGN KEY(exercise_id) REFERENCES app_exercise(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS UX_exercise_note_exercise ON app_exercise_note(exercise_id)',
    );
  }

  if (oldVersion < 6) {
    await db.execute(
      'ALTER TABLE app_training_session ADD COLUMN is_rolling INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_session_block (
        id             TEXT    NOT NULL PRIMARY KEY,
        session_id     TEXT    NOT NULL,
        name           TEXT    NOT NULL,
        order_index    INTEGER NOT NULL DEFAULT 0,
        created_at_ms  INTEGER NOT NULL,
        updated_at_ms  INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES app_training_session(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS IX_session_block_session ON app_session_block(session_id, order_index)',
    );
    await db.execute(
      'ALTER TABLE app_segment_effort ADD COLUMN block_id TEXT REFERENCES app_session_block(id) ON DELETE SET NULL',
    );
  }
}
