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
}
