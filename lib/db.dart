import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> getDB() async {
    if (_db != null) return _db!;
    
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'workouts.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE workout(
            id TEXT PRIMARY KEY,
            sportType TEXT,
            startedAt INTEGER,
            endedAt INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE exercise(
            id TEXT PRIMARY KEY,
            workoutId TEXT,
            name TEXT,
            "order" INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE set_table(
            id TEXT PRIMARY KEY,
            exerciseId TEXT,
            reps INTEGER,
            weight REAL,
            duration INTEGER,
            timestamp INTEGER
          )
        ''');
      },
    );

    return _db!;
  }
}
