import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain1/src/data/database_provider.dart';
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

    final metrics = await db.query('app_metric_definition', where: 'key = ?', whereArgs: ['reps']);
    expect(metrics, isNotEmpty);

    await DatabaseProvider.instance.close();
  });
}
