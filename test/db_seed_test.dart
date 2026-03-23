import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/datasources/database_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Ensure sqflite uses ffi implementation when running on desktop/test.
void _initFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DB seeds applied', () async {
    _initFfi();
    final schema = await rootBundle.loadString('scripts/sqlite_schema.sql');
    final seed = await rootBundle.loadString('scripts/sqlite_seed.sql');

    final db = await DatabaseProvider.instance.open(inMemory: true, schemaSql: schema, seedSql: seed);

    final units = await db.query('app_unit', where: 'key = ?', whereArgs: ['kg']);
    expect(units, isNotEmpty);

    final cmUnits = await db.query(
      'app_unit',
      where: 'id = ?',
      whereArgs: ['unit-cm'],
    );
    expect(cmUnits, isNotEmpty);

    final pctUnits = await db.query(
      'app_unit',
      where: 'id = ?',
      whereArgs: ['unit-pct'],
    );
    expect(pctUnits, isNotEmpty);

    final metrics = await db.query('app_metric_definition', where: 'key = ?', whereArgs: ['reps']);
    expect(metrics, isNotEmpty);

    final profileTables = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'app_user_profile'],
    );
    expect(profileTables, isNotEmpty);

    final measurementTables = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'app_body_measurement_entry'],
    );
    expect(measurementTables, isNotEmpty);

    await DatabaseProvider.instance.close();
  });
}
