// Pipeline schema documentation validation test.
//
// This test is intentionally NOT a behavior test for the live app — the app
// no longer ships a SQLite runtime. Its sole purpose is to validate that
// the pipeline's schema/seed documentation (the SQL files at
// `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql`) remains valid,
// executable SQL. The agent pipeline references these files as the canonical
// data-model contract; this test proves the contract has not drifted.
//
// The test deliberately reads the SQL files from the repository directly
// (no Flutter asset bundle) and runs them through an in-memory
// `sqflite_common_ffi` database that never leaves the test process.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void _initFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Split a SQL script into individual statements.
///
/// Reuses the executor-style split that the previous `DatabaseProvider`
/// used for the same files, inlined here so this test stays independent of
/// the now-retired app source files. Strips block + line comments and
/// respects single-quoted strings so semicolons inside string literals
/// don't terminate statements early.
Iterable<String> _splitStatements(String sql) sync* {
  var cleaned = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final lines = cleaned.split(RegExp(r'\r?\n'));
  cleaned = lines
      .map((l) => l.replaceFirst(RegExp(r'\s*--.*$'), ''))
      .where((l) => l.trim().isNotEmpty)
      .join('\n');

  final buffer = StringBuffer();
  var inSingleQuotedString = false;

  for (var i = 0; i < cleaned.length; i++) {
    final char = cleaned[i];
    if (char == "'") {
      buffer.write(char);
      if (inSingleQuotedString &&
          i + 1 < cleaned.length &&
          cleaned[i + 1] == "'") {
        buffer.write("'");
        i++;
        continue;
      }
      inSingleQuotedString = !inSingleQuotedString;
      continue;
    }
    if (char == ';' && !inSingleQuotedString) {
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) yield stmt;
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) yield tail;
}

/// Filter the statements that the live `DatabaseProvider` would have
/// executed — skip transaction control verbs and the FK pragma that the
/// execution layer applies implicitly.
List<String> _executableStatements(String sql) {
  return _splitStatements(sql).where((s) {
    final lower = s.toLowerCase();
    if (lower.startsWith('pragma')) return false;
    if (lower == 'begin transaction' || lower == 'commit') return false;
    return true;
  }).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pipeline schema documentation', () {
    test(
      'sqlite_schema.sql and sqlite_seed.sql execute against an in-memory '
      'test database and produce the documented seed rows',
      () async {
        _initFfi();

        // Repo root is the parent of `test/` — load the SQL files directly
        // from disk, the way the agent pipeline docs reference them, not
        // through any live app source file.
        final repoRoot = Directory.current.path;
        final schemaSql =
            await File('$repoRoot/scripts/sqlite_schema.sql').readAsString();
        final seedSql =
            await File('$repoRoot/scripts/sqlite_seed.sql').readAsString();

        final db = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (db) async {
              await db.execute('PRAGMA foreign_keys = ON');
            },
          ),
        );

        for (final stmt in _executableStatements(schemaSql)) {
          await db.execute(stmt);
        }
        for (final stmt in _executableStatements(seedSql)) {
          await db.execute(stmt);
        }

        // Sanity-check the seed output. These rows come from the seed file,
        // not from any app source — if the pipeline docs drift, these
        // assertions fail first.
        final units = await db.query('app_unit', where: 'key = ?', whereArgs: ['kg']);
        expect(units, isNotEmpty, reason: 'app_unit seed for kg is missing');

        final cmUnits = await db.query(
          'app_unit',
          where: 'id = ?',
          whereArgs: ['unit-cm'],
        );
        expect(cmUnits, isNotEmpty, reason: 'app_unit seed for unit-cm is missing');

        final pctUnits = await db.query(
          'app_unit',
          where: 'id = ?',
          whereArgs: ['unit-pct'],
        );
        expect(pctUnits, isNotEmpty, reason: 'app_unit seed for unit-pct is missing');

        final metrics = await db.query(
          'app_metric_definition',
          where: 'key = ?',
          whereArgs: ['reps'],
        );
        expect(metrics, isNotEmpty,
            reason: 'app_metric_definition seed for reps is missing');

        final profileTables = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'app_user_profile'],
        );
        expect(profileTables, isNotEmpty,
            reason: 'app_user_profile table missing from schema');

        final measurementTables = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'app_body_measurement_entry'],
        );
        expect(measurementTables, isNotEmpty,
            reason: 'app_body_measurement_entry table missing from schema');

        await db.close();
      },
    );
  });
}
