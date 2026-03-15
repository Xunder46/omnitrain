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
}
