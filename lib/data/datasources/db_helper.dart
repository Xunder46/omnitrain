import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> getDB() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'omnitrain.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // For now, drop all tables and recreate
        await _dropTables(db);
        await _createTables(db);
      },
    );

    return _db!;
  }

  static Future<void> _createTables(Database db) async {
    // Core tables for workout functionality
    await db.execute('''
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
        row_version INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE app_training_session (
        id TEXT NOT NULL PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        started_at_ms INTEGER NOT NULL,
        ended_at_ms INTEGER,
        title TEXT,
        note TEXT,
        location_text TEXT,
        perceived_session_rpe REAL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        row_version INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
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
        FOREIGN KEY(session_id) REFERENCES app_training_session(id)
      )
    ''');

    await db.execute('''
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
        FOREIGN KEY(segment_id) REFERENCES app_session_segment(id),
        FOREIGN KEY(exercise_id) REFERENCES app_exercise(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_unit (
        id TEXT NOT NULL PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        unit_type TEXT,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
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
      )
    ''');

    await db.execute('''
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
        FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id),
        FOREIGN KEY(metric_id) REFERENCES app_metric_definition(id),
        FOREIGN KEY(unit_id) REFERENCES app_unit(id)
      )
    ''');

    // Insert basic units and metrics
    await _insertSeedData(db);
  }

  static Future<void> _dropTables(Database db) async {
    await db.execute('DROP TABLE IF EXISTS app_effort_observation');
    await db.execute('DROP TABLE IF EXISTS app_metric_definition');
    await db.execute('DROP TABLE IF EXISTS app_unit');
    await db.execute('DROP TABLE IF EXISTS app_segment_effort');
    await db.execute('DROP TABLE IF EXISTS app_session_segment');
    await db.execute('DROP TABLE IF EXISTS app_training_session');
    await db.execute('DROP TABLE IF EXISTS app_exercise');
  }

  static Future<void> _insertSeedData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Units
    await db.insert('app_unit', {
      'id': 'unit-kg',
      'key': 'kg',
      'name': 'Kilograms',
      'unit_type': 'weight',
      'created_at_ms': now,
    });

    await db.insert('app_unit', {
      'id': 'unit-lbs',
      'key': 'lbs',
      'name': 'Pounds',
      'unit_type': 'weight',
      'created_at_ms': now,
    });

    await db.insert('app_unit', {
      'id': 'unit-reps',
      'key': 'reps',
      'name': 'Repetitions',
      'unit_type': 'count',
      'created_at_ms': now,
    });

    // Metrics
    await db.insert('app_metric_definition', {
      'id': 'metric-weight',
      'key': 'weight',
      'name': 'Weight',
      'data_type': 'real',
      'default_unit_id': 'unit-kg',
      'is_core': 1,
      'applies_to_effort_kind': 'strength',
      'created_at_ms': now,
    });

    await db.insert('app_metric_definition', {
      'id': 'metric-reps',
      'key': 'reps',
      'name': 'Repetitions',
      'data_type': 'int',
      'default_unit_id': 'unit-reps',
      'is_core': 1,
      'applies_to_effort_kind': 'strength',
      'created_at_ms': now,
    });
  }

  // Database operations
  static Future<String> insertTrainingSession(Map<String, dynamic> data) async {
    final db = await getDB();
    final id = data['id'] as String;
    await db.insert('app_training_session', data);
    return id;
  }

  static Future<String> insertExercise(Map<String, dynamic> data) async {
    final db = await getDB();
    final id = data['id'] as String;
    await db.insert('app_exercise', data);
    return id;
  }

  static Future<String> insertSessionSegment(Map<String, dynamic> data) async {
    final db = await getDB();
    final id = data['id'] as String;
    await db.insert('app_session_segment', data);
    return id;
  }

  static Future<String> insertSegmentEffort(Map<String, dynamic> data) async {
    final db = await getDB();
    final id = data['id'] as String;
    await db.insert('app_segment_effort', data);
    return id;
  }

  static Future<String> insertEffortObservation(Map<String, dynamic> data) async {
    final db = await getDB();
    final id = data['id'] as String;
    await db.insert('app_effort_observation', data);
    return id;
  }

  static Future<List<Map<String, dynamic>>> getExercises() async {
    final db = await getDB();
    return await db.query('app_exercise', where: 'is_archived = 0 AND deleted_at_ms IS NULL');
  }

  static Future<Map<String, dynamic>?> getTrainingSession(String id) async {
    final db = await getDB();
    final results = await db.query('app_training_session', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  static Future<List<Map<String, dynamic>>> getSessionSegments(String sessionId) async {
    final db = await getDB();
    return await db.query('app_session_segment',
        where: 'session_id = ? AND deleted_at_ms IS NULL',
        whereArgs: [sessionId],
        orderBy: 'order_index');
  }

  static Future<List<Map<String, dynamic>>> getSegmentEfforts(String segmentId) async {
    final db = await getDB();
    return await db.query('app_segment_effort',
        where: 'segment_id = ? AND deleted_at_ms IS NULL',
        whereArgs: [segmentId],
        orderBy: 'order_index');
  }

  static Future<List<Map<String, dynamic>>> getEffortObservations(String effortId) async {
    final db = await getDB();
    return await db.query('app_effort_observation',
        where: 'effort_id = ? AND deleted_at_ms IS NULL',
        whereArgs: [effortId],
        orderBy: 'created_at_ms');
  }
}
