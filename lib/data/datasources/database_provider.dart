import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'migrations.dart';

class DatabaseProvider {
  DatabaseProvider._();
  static final DatabaseProvider instance = DatabaseProvider._();

  Database? _db;

  /// Opens the database. If [inMemory] is true, an in-memory DB is used (useful for tests).
  /// Optionally provide [schemaSql] and [seedSql] to override assets (helps testing).
  Future<Database> open({
    String? schemaSql,
    String? seedSql,
    bool inMemory = false,
    int version = 5,
  }) async {
    if (_db != null && _db!.isOpen) return _db!;

    FutureOr<void> onConfigure(Database db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    if (inMemory) {
      _db = await openDatabase(
        inMemoryDatabasePath,
        version: version,
        onConfigure: onConfigure,
        onCreate: (db, version) async {},
        onUpgrade: applyMigrations,
      );
    } else {
      final docs = await getApplicationDocumentsDirectory();
      final path = p.join(docs.path, 'omnitrain.db');
      _db = await openDatabase(
        path,
        version: version,
        onConfigure: onConfigure,
        onCreate: (db, version) async {},
        onUpgrade: applyMigrations,
      );
    }

    // If the main tables don't exist yet, apply schema and seeds.
    final String schema = schemaSql ?? await rootBundle.loadString('scripts/sqlite_schema.sql');
    final String seed = seedSql ?? await rootBundle.loadString('scripts/sqlite_seed.sql');    

    final tables = await _db!.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='app_sport_category'");
    if (tables.isEmpty) {
      // Apply schema and seed statements directly. Avoid wrapping in an
      // explicit transaction here to reduce risk of nested-transaction
      // issues across different drivers.
      await _runSqlScriptExecutor(_db!, schema);


      await _runSqlScriptExecutor(_db!, seed);
    }

    return _db!;
  }

  // Helper that accepts a DatabaseExecutor so it can be used with a
  // Transaction as well as Database.
  Future<void> _runSqlScriptExecutor(DatabaseExecutor exec, String sql) async {
    // Strip block comments and line comments first.
    var cleaned = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final lines = cleaned.split(RegExp(r'\r?\n'));
    cleaned = lines
        .map((l) => l.replaceFirst(RegExp(r'\s*--.*$'), ''))
        .where((l) => l.trim().isNotEmpty)
        .join('\n');

    final statements = cleaned
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .where((s) {
      final lower = s.toLowerCase();
      if (lower == 'begin transaction' || lower == 'commit') return false;
      if (lower.startsWith('pragma foreign_keys')) return false;
      return true;
    });

    for (final stmt in statements) {
      await exec.execute(stmt);
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
