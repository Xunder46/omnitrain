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
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/data/models/models.dart';
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

/// Opens a fresh in-memory database holding the schema contract, with
/// foreign keys on, exactly as the pipeline test below executes it. Opens
/// through the FFI factory directly, leaving sqflite's global default alone.
Future<Database> _openSchemaDatabase() async {
  sqfliteFfiInit();
  final schemaSql = await File(
    '${Directory.current.path}/scripts/sqlite_schema.sql',
  ).readAsString();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
  for (final stmt in _executableStatements(schemaSql)) {
    await db.execute(stmt);
  }
  return db;
}

/// The database's refusal of [row], or `null` when [table] accepts it. Lets a
/// refused model row fail an assertion instead of escaping as an exception.
Future<DatabaseException?> _insertRefusal(
  Database db,
  String table,
  Map<String, Object?> row,
) async {
  try {
    await db.insert(table, row);
    return null;
  } on DatabaseException catch (refusal) {
    return refusal;
  }
}

Future<Set<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

const _sqlSession = 's-sql-1';

Future<void> _insertSession(Database db) async {
  await db.insert('app_training_session', {
    'id': _sqlSession,
    'owner_user_id': 'user-1',
    'started_at_ms': 1000,
    'ended_at_ms': 5000,
    'created_at_ms': 1000,
    'updated_at_ms': 5000,
  });
}

/// The parent rows one effort observation needs: a session, its segment, a
/// timed effort, and the metric definitions and unit the rows name.
Future<void> _insertEffortFixture(Database db) async {
  await _insertSession(db);
  await db.insert('app_session_segment', {
    'id': 'seg-sql-1',
    'session_id': _sqlSession,
    'order_index': 0,
    'segment_type': 'workout',
    'created_at_ms': 1000,
    'updated_at_ms': 1000,
  });
  await db.insert('app_segment_effort', {
    'id': 'eff-sql-1',
    'segment_id': 'seg-sql-1',
    'order_index': 0,
    'effort_kind': 'timed',
    'created_at_ms': 1000,
    'updated_at_ms': 1000,
  });
  for (final row in [
    {'id': MetricIds.distance, 'key': 'distance', 'data_type': 'real'},
    {'id': MetricIds.reps, 'key': 'reps', 'data_type': 'int'},
  ]) {
    await db.insert('app_metric_definition', {
      ...row,
      'name': row['key'],
      'created_at_ms': 1000,
    });
  }
  await db.insert('app_unit', {
    'id': MetricIds.unitMeters,
    'key': 'm',
    'name': 'metres',
    'created_at_ms': 1000,
  });
}

/// A raw observation row: exactly one value column, as the CHECK requires —
/// `EffortObservation.toMap` cannot be used here because it always writes
/// `value_bool` (Open Item O-4).
Map<String, Object?> _observationRow({
  required String id,
  required String metricId,
  Object? valueInt,
  Object? valueReal,
  Object? valueText,
  Object? valueBool,
  String? valueSource,
}) => {
  'id': id,
  'effort_id': 'eff-sql-1',
  'metric_id': metricId,
  'value_int': valueInt,
  'value_real': valueReal,
  'value_text': valueText,
  'value_bool': valueBool,
  'value_source': valueSource,
  'created_at_ms': 1000,
  'updated_at_ms': 1000,
};

/// One summary per scope, plus a measured zero step count (D-125).
List<SensorSummary> _sampleSummaries() => [
  SensorSummary(
    sessionId: _sqlSession,
    scope: SensorSummary.scopeSession,
    targetId: _sqlSession,
    windowStartMs: 1000,
    windowEndMs: 5000,
    avgHeartRateBpm: 143,
    maxHeartRateBpm: 180,
    createdAtMs: 6000,
  ),
  SensorSummary(
    sessionId: _sqlSession,
    scope: SensorSummary.scopeEffort,
    targetId: 'eff-bench',
    windowStartMs: 3000,
    windowEndMs: 4000,
    avgHeartRateBpm: 130,
    maxHeartRateBpm: 150,
    createdAtMs: 6000,
  ),
  SensorSummary(
    sessionId: _sqlSession,
    scope: SensorSummary.scopeTimedInstance,
    targetId: 'ti-run',
    windowStartMs: 1000,
    windowEndMs: 2000,
    avgHeartRateBpm: 140,
    maxHeartRateBpm: 160,
    steps: 3200,
    createdAtMs: 6000,
  ),
  SensorSummary(
    sessionId: _sqlSession,
    scope: SensorSummary.scopeTimedInstance,
    targetId: 'ti-walk',
    windowStartMs: 2000,
    windowEndMs: 2100,
    steps: 0,
    createdAtMs: 6000,
  ),
  SensorSummary(
    sessionId: _sqlSession,
    scope: SensorSummary.scopeRoundInstance,
    targetId: 'ri-1',
    windowStartMs: 2500,
    windowEndMs: 2800,
    avgHeartRateBpm: 160,
    maxHeartRateBpm: 170,
    createdAtMs: 6000,
  ),
];

/// A wrist event, a session end, and each phone annotation kind.
List<WatchInboxEntry> _sampleInboxEntries() => [
  WatchInboxEntry(
    entryId: 'e-set1',
    watchSessionId: _sqlSession,
    kind: WatchInboxEntry.kindSet,
    origin: WatchInboxEntry.originWatch,
    payload: {
      'eventId': 'e-set1',
      'entryId': 'e-set1',
      'kind': 'set',
      'reps': 5,
      'loadKg': 80,
    },
    receivedAtMs: 7000,
    appliedAtMs: 7100,
  ),
  WatchInboxEntry(
    entryId: 'end-$_sqlSession',
    watchSessionId: _sqlSession,
    kind: WatchInboxEntry.kindSessionEnd,
    origin: WatchInboxEntry.originWatch,
    payload: {'kind': 'session_end', 'status': 'completed'},
    receivedAtMs: 7001,
  ),
  WatchInboxEntry(
    entryId: WatchInboxEntry.phoneRatingId(_sqlSession),
    watchSessionId: _sqlSession,
    kind: WatchInboxEntry.kindPhoneRating,
    origin: WatchInboxEntry.originPhone,
    payload: {'rating': 3},
    receivedAtMs: 7002,
  ),
  WatchInboxEntry(
    entryId: WatchInboxEntry.phoneChangeId('chg-1', 0),
    watchSessionId: _sqlSession,
    kind: WatchInboxEntry.kindPhoneCorrection,
    origin: WatchInboxEntry.originPhone,
    payload: {
      'kind': 'correct_entry',
      'entryId': 'e-set1',
      'correction': {'reps': 6},
    },
    receivedAtMs: 7003,
  ),
  WatchInboxEntry(
    entryId: WatchInboxEntry.phoneChangeId('chg-1', 1),
    watchSessionId: _sqlSession,
    kind: WatchInboxEntry.kindPhoneDeletion,
    origin: WatchInboxEntry.originPhone,
    payload: {'kind': 'delete_entry', 'entryId': 'e-set2'},
    receivedAtMs: 7004,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pipeline schema documentation', () {
    test('sqlite_schema.sql and sqlite_seed.sql execute against an in-memory '
        'test database and produce the documented seed rows', () async {
      _initFfi();

      // Repo root is the parent of `test/` — load the SQL files directly
      // from disk, the way the agent pipeline docs reference them, not
      // through any live app source file.
      final repoRoot = Directory.current.path;
      final schemaSql = await File(
        '$repoRoot/scripts/sqlite_schema.sql',
      ).readAsString();
      final seedSql = await File(
        '$repoRoot/scripts/sqlite_seed.sql',
      ).readAsString();

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
      final units = await db.query(
        'app_unit',
        where: 'key = ?',
        whereArgs: ['kg'],
      );
      expect(units, isNotEmpty, reason: 'app_unit seed for kg is missing');

      final cmUnits = await db.query(
        'app_unit',
        where: 'id = ?',
        whereArgs: ['unit-cm'],
      );
      expect(
        cmUnits,
        isNotEmpty,
        reason: 'app_unit seed for unit-cm is missing',
      );

      final pctUnits = await db.query(
        'app_unit',
        where: 'id = ?',
        whereArgs: ['unit-pct'],
      );
      expect(
        pctUnits,
        isNotEmpty,
        reason: 'app_unit seed for unit-pct is missing',
      );

      final metrics = await db.query(
        'app_metric_definition',
        where: 'key = ?',
        whereArgs: ['reps'],
      );
      expect(
        metrics,
        isNotEmpty,
        reason: 'app_metric_definition seed for reps is missing',
      );

      final profileTables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'app_user_profile'],
      );
      expect(
        profileTables,
        isNotEmpty,
        reason: 'app_user_profile table missing from schema',
      );

      final measurementTables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'app_body_measurement_entry'],
      );
      expect(
        measurementTables,
        isNotEmpty,
        reason: 'app_body_measurement_entry table missing from schema',
      );

      await db.close();
    });
  });

  // Stats PR 2, Phase 2 (D-131 / D-132): the watch-capture tables belong to
  // the contract, and their models cannot drift away from them.
  group('Watch capture schema contract (D-131 / D-132)', () {
    late Database db;

    setUp(() async {
      db = await _openSchemaDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'D-131/D-132 app_sensor_summary and app_watch_inbox_entry exist, '
      'and every toMap key of their models is one of their columns',
      () async {
        for (final table in ['app_sensor_summary', 'app_watch_inbox_entry']) {
          final rows = await db.query(
            'sqlite_master',
            where: 'type = ? AND name = ?',
            whereArgs: ['table', table],
          );
          expect(rows, isNotEmpty, reason: '$table missing from schema');
        }

        final summaryColumns = await _columnsOf(db, 'app_sensor_summary');
        for (final summary in _sampleSummaries()) {
          expect(
            summary.toMap().keys.toSet().difference(summaryColumns),
            isEmpty,
            reason:
                'D-131: SensorSummary.toMap writes keys app_sensor_summary '
                'lacks',
          );
        }
        final inboxColumns = await _columnsOf(db, 'app_watch_inbox_entry');
        for (final entry in _sampleInboxEntries()) {
          expect(
            entry.toMap().keys.toSet().difference(inboxColumns),
            isEmpty,
            reason:
                'D-132: WatchInboxEntry.toMap writes keys '
                'app_watch_inbox_entry lacks',
          );
        }
      },
    );

    test('D-131/D-132 every model row inserts as toMap writes it and reads '
        'back as the same model', () async {
      await _insertSession(db);
      for (final summary in _sampleSummaries()) {
        expect(
          await _insertRefusal(db, 'app_sensor_summary', summary.toMap()),
          isNull,
          reason: 'D-131: app_sensor_summary accepts ${summary.id} as-is',
        );
      }
      for (final entry in _sampleInboxEntries()) {
        expect(
          await _insertRefusal(db, 'app_watch_inbox_entry', entry.toMap()),
          isNull,
          reason: 'D-132: app_watch_inbox_entry accepts ${entry.entryId} as-is',
        );
      }

      final summaries = _sampleSummaries()
        ..sort((a, b) => a.id.compareTo(b.id));
      final summaryRows = await db.query('app_sensor_summary', orderBy: 'id');
      expect(
        [
          for (final row in summaryRows) {...row},
        ],
        [for (final summary in summaries) summary.toMap()],
        reason: 'D-131: app_sensor_summary stores what toMap writes',
      );
      expect(
        [
          for (final row in summaryRows)
            SensorSummary.fromMap({...row}).toMap(),
        ],
        [for (final summary in summaries) summary.toMap()],
        reason: 'D-131: model ↔ app_sensor_summary round trip',
      );

      final entries = _sampleInboxEntries()
        ..sort((a, b) => a.entryId.compareTo(b.entryId));
      final inboxRows = await db.query(
        'app_watch_inbox_entry',
        orderBy: 'entry_id',
      );
      expect(
        [
          for (final row in inboxRows) {...row},
        ],
        [for (final entry in entries) entry.toMap()],
        reason: 'D-132: app_watch_inbox_entry stores what toMap writes',
      );
      expect(
        [
          for (final row in inboxRows)
            WatchInboxEntry.fromMap({...row}).toMap(),
        ],
        [for (final entry in entries) entry.toMap()],
        reason: 'D-132: model ↔ app_watch_inbox_entry round trip',
      );
    });

    test('D-131 the CHECK constraints refuse a zero heart rate, an average '
        'above the maximum, steps outside a timed entry and an empty '
        'row', () async {
      await _insertSession(db);
      Map<String, Object?> sample(String scope) => _sampleSummaries()
          .firstWhere((summary) => summary.scope == scope)
          .toMap();
      final session = sample(SensorSummary.scopeSession);
      final timed = sample(SensorSummary.scopeTimedInstance);
      final round = sample(SensorSummary.scopeRoundInstance);
      Future<void> refused(Map<String, Object?> row, String rule) async {
        await expectLater(
          db.insert('app_sensor_summary', row),
          throwsA(isA<DatabaseException>()),
          reason: 'D-131: app_sensor_summary refuses $rule',
        );
      }

      await refused({
        ...round,
        'avg_heart_rate_bpm': 0.0,
        'max_heart_rate_bpm': 0.0,
      }, 'a zero heart rate');
      await refused({
        ...round,
        'avg_heart_rate_bpm': 171.0,
      }, 'an average above the maximum');
      await refused({...round, 'steps': 40}, 'steps on a round');
      await refused({
        ...round,
        'avg_heart_rate_bpm': null,
        'max_heart_rate_bpm': null,
      }, 'an empty row');
      await refused({
        ...round,
        'max_heart_rate_bpm': null,
      }, 'an average without a maximum');
      await refused({...timed, 'steps': -1}, 'negative steps');
      await refused({
        ...round,
        'scope': 'set_block',
        'id': 'sensor-set_block-ri-1',
      }, 'an unknown scope');
      await refused({
        ...round,
        'id': 'sensor-round_instance-ri-9',
      }, 'an id not derived from its scope and target');
      await refused({
        ...session,
        'target_id': 's-elsewhere',
        'id': 'sensor-session-s-elsewhere',
      }, 'a session summary for another session');
      await refused({
        ...round,
        'window_end_ms': (round['window_start_ms'] as int) - 1,
      }, 'a window that ends before it starts');
      await refused({...round, 'source': 'phone'}, 'an unknown source');
      await refused({
        ...round,
        'session_id': 's-missing',
      }, 'a summary of a session that does not exist');

      await db.insert('app_sensor_summary', round);
      await refused({
        ...round,
        'created_at_ms': 1,
      }, 'a second row for the same scope and target');
      expect(await db.query('app_sensor_summary'), hasLength(1));
    });

    test(
      'D-132 the CHECK constraints refuse a kind outside its origin\'s '
      'vocabulary and phone ids that are not the deterministic ones',
      () async {
        Map<String, Object?> sample(String kind) => _sampleInboxEntries()
            .firstWhere((entry) => entry.kind == kind)
            .toMap();
        final wrist = sample(WatchInboxEntry.kindSet);
        final rating = sample(WatchInboxEntry.kindPhoneRating);
        final correction = sample(WatchInboxEntry.kindPhoneCorrection);
        Future<void> refused(Map<String, Object?> row, String rule) async {
          await expectLater(
            db.insert('app_watch_inbox_entry', row),
            throwsA(isA<DatabaseException>()),
            reason: 'D-132: app_watch_inbox_entry refuses $rule',
          );
        }

        await refused({
          ...wrist,
          'origin': 'phone',
        }, 'a wrist event as the phone\'s');
        await refused({
          ...wrist,
          'kind': 'nutrition_log',
        }, 'a kind it never stages');
        await refused({...wrist, 'origin': 'wear'}, 'an unknown origin');
        await refused({
          ...rating,
          'origin': 'watch',
        }, 'a phone annotation from the watch');
        await refused({
          ...rating,
          'entry_id': 'phone-rating-s-other',
        }, 'a phone rating under another session\'s id');
        await refused({
          ...correction,
          'entry_id': 'e-set2',
        }, 'a phone change not keyed by its change');

        await db.insert('app_watch_inbox_entry', wrist);
        await refused({
          ...wrist,
          'received_at_ms': 1,
        }, 'a second row with the same entry id');
        expect(await db.query('app_watch_inbox_entry'), hasLength(1));
      },
    );
  });

  // Stats PR 3a, Phase 1 (D-301, D-311): a distance records where it came
  // from, the column belongs to the contract, and the CHECK refuses a source
  // that could not have been written.
  group('Distance source schema contract (D-301 / D-311)', () {
    late Database db;

    setUp(() async {
      db = await _openSchemaDatabase();
      await _insertEffortFixture(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'D-311 app_effort_observation has value_source, and every toMap key of '
      'the model is one of its columns',
      () async {
        final columns = await _columnsOf(db, 'app_effort_observation');
        expect(columns, contains('value_source'));

        final written = EffortObservation(
          id: 'obs-eff-sql-1-0-distance',
          effortId: 'eff-sql-1',
          metricId: MetricIds.distance,
          unitId: MetricIds.unitMeters,
          valueReal: 4873.6,
          valueSource: EffortObservation.sourceEstimated,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ).toMap();
        expect(
          written.keys.toSet().difference(columns),
          isEmpty,
          reason:
              'D-311: EffortObservation.toMap writes keys '
              'app_effort_observation lacks',
        );
      },
    );

    test(
      'S-803 the CHECK refuses a source on another metric and an unknown '
      'source, and accepts an estimate on a distance',
      () async {
        expect(
          await _insertRefusal(
            db,
            'app_effort_observation',
            _observationRow(
              id: 'obs-eff-sql-1-0-reps',
              metricId: MetricIds.reps,
              valueInt: 8,
              valueSource: EffortObservation.sourceEntered,
            ),
          ),
          isNotNull,
          reason: 'D-311: a source belongs to a metric-distance row',
        );
        expect(
          await _insertRefusal(
            db,
            'app_effort_observation',
            _observationRow(
              id: 'obs-eff-sql-1-0-distance',
              metricId: MetricIds.distance,
              valueReal: 1000.0,
              valueSource: 'manual',
            ),
          ),
          isNotNull,
          reason: 'D-311: the vocabulary is gps, entered, estimated',
        );
        expect(
          await _insertRefusal(
            db,
            'app_effort_observation',
            _observationRow(
              id: 'obs-eff-sql-1-0-distance',
              metricId: MetricIds.distance,
              valueReal: 3000.0,
              valueSource: EffortObservation.sourceEstimated,
            ),
          ),
          isNull,
          reason: 'D-311: an estimated distance is a storable row',
        );
      },
    );
  });
}
