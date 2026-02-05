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

  // No migrations yet (initial version 1)
}
