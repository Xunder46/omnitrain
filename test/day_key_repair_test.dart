// Plan 264: the one-off repair that moves daily targets, water totals and food
// rows stored under the pre-plan-235 day key (local midnight) to the current
// key (the calendar date's UTC midnight).
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/day_key_repair.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'helpers/repository_harness.dart';

DateTime get _now => DateTime.now();
DateTime get _yesterday => DateTime(_now.year, _now.month, _now.day - 1);
DateTime get _twoDaysAgo => DateTime(_now.year, _now.month, _now.day - 2);

int _newKey(DateTime d) => OmniDateUtils.dayKeyMs(d);
int _oldKey(DateTime d) => d.millisecondsSinceEpoch;

Map<String, dynamic> _targetMap(double calories, int dateMs) =>
    NutritionTarget(calories: calories).toMap()..['date_ms'] = dateMs;

Map<String, dynamic> _waterMap(int dateMs, int volumeMl) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': 'water-$dateMs',
    'date_ms': dateMs,
    'volume_ml': volumeMl,
    'created_at_ms': now,
    'updated_at_ms': now,
  };
}

Future<void> _runRepair(HiveWorkoutRepository repo) async {
  final step = repo.dataMigrationStepsForTest().last;
  expect(step.name, 'repairDayKeys');
  await step.run();
}

void main() {
  group('DayKeyRepair.newKeyFor (S-26401)', () {
    test('a UTC midnight is already new-style', () {
      expect(DayKeyRepair.newKeyFor(_newKey(_yesterday)), isNull);
    });

    test('a local midnight in this zone maps to its date UTC midnight', () {
      expect(DayKeyRepair.newKeyFor(_oldKey(_yesterday)), _newKey(_yesterday));
    });

    test('a midnight saved in another zone rounds to its own date', () {
      final date = DateTime.utc(2026, 11, 15);
      // Saved in UTC+9: local midnight is 15:00 UTC the day before.
      final east = date
          .subtract(const Duration(hours: 9))
          .millisecondsSinceEpoch;
      // Saved in UTC-8: local midnight is 08:00 UTC the same day.
      final west = date.add(const Duration(hours: 8)).millisecondsSinceEpoch;
      for (final k in [east, west]) {
        final local = DateTime.fromMillisecondsSinceEpoch(k);
        final isLocalMidnightHere =
            local.hour == 0 && local.minute == 0 && local.second == 0;
        // A true local midnight in this zone keeps its local date; any other
        // key (saved in another zone) rounds to its own UTC date.
        final expected = isLocalMidnightHere
            ? OmniDateUtils.dayKeyMs(local)
            : date.millisecondsSinceEpoch;
        expect(DayKeyRepair.newKeyFor(k), expected);
      }
    });
  });

  group('Hive repair of old-style day keys', () {
    late HiveRepositoryHarness harness;
    late HiveWorkoutRepository repo;
    late Box<Map> targets;
    late Box<Map> water;
    late Box<Map> foods;

    setUp(() async {
      harness = HiveRepositoryHarness();
      repo = await harness.open() as HiveWorkoutRepository;
      targets = Hive.box<Map>('nutrition_targets_by_date');
      water = Hive.box<Map>('water_log');
      foods = Hive.box<Map>('consumed_foods');
    });

    tearDown(() => harness.close());

    test('S-26402 an old-style target is found again and rolls forward',
        () async {
      await targets.put(
        _oldKey(_twoDaysAgo).toString(),
        _targetMap(2000, _oldKey(_twoDaysAgo)),
      );
      // Before the repair the app cannot see it.
      expect(
        (await repo.getNutritionTargetForDate(_oldKey(_yesterday)))?.calories,
        isNull,
      );

      await _runRepair(repo);

      expect(
        (await repo.getNutritionTargetForDate(_oldKey(_twoDaysAgo)))?.calories,
        2000,
      );
      expect(
        (await repo.getNutritionTargetForDate(_oldKey(_yesterday)))?.calories,
        2000,
      );
      expect(targets.containsKey(_oldKey(_twoDaysAgo).toString()), isFalse);
    });

    test('S-26403 a newer new-style target for the same date wins', () async {
      await targets.put(
        _oldKey(_yesterday).toString(),
        _targetMap(1800, _oldKey(_yesterday)),
      );
      await repo.saveNutritionTargetForDate(
        _oldKey(_yesterday),
        NutritionTarget(calories: 2500),
      );

      await _runRepair(repo);

      expect(
        (await repo.getNutritionTargetForDate(_oldKey(_yesterday)))?.calories,
        2500,
      );
      expect(targets.containsKey(_oldKey(_yesterday).toString()), isFalse);
    });

    test('S-26404 old water comes back and adds to a new total', () async {
      await water.put(
        _oldKey(_twoDaysAgo).toString(),
        _waterMap(_oldKey(_twoDaysAgo), 500),
      );
      await water.put(
        _oldKey(_yesterday).toString(),
        _waterMap(_oldKey(_yesterday), 400),
      );
      await repo.saveWaterVolumeForDate(_oldKey(_yesterday), 250);
      expect(await repo.getWaterVolumeForDate(_oldKey(_twoDaysAgo)), 0);

      await _runRepair(repo);

      expect(await repo.getWaterVolumeForDate(_oldKey(_twoDaysAgo)), 500);
      expect(await repo.getWaterVolumeForDate(_oldKey(_yesterday)), 650);
      expect(
        water.get(_newKey(_twoDaysAgo).toString())!['id'],
        WaterLogEntry.idForDate(_newKey(_twoDaysAgo)),
      );
      expect(water.containsKey(_oldKey(_twoDaysAgo).toString()), isFalse);
    });

    test('S-26405 a logged food row gets the new-style day', () async {
      final ms = _oldKey(_yesterday);
      final row = ConsumedFood(
        id: 'c-264',
        loggedAtMs: ms + 3600000,
        dateMs: ms,
        sourceFoodId: 'f',
        name: 'Egg',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: '1 egg',
        protein: 6,
        carbs: 1,
        fat: 5,
        amountConsumed: 2,
        targetCalories: 0,
        targetProtein: 0,
        targetCarbs: 0,
        targetFat: 0,
        createdAtMs: ms,
        updatedAtMs: ms,
      );
      await foods.put('c-264', row.toMap()..['date_ms'] = ms);
      expect(foods.get('c-264')!['date_ms'], ms);

      await _runRepair(repo);

      expect(foods.get('c-264')!['date_ms'], _newKey(_yesterday));
      final back = await repo.getConsumedFoodsForDate(ms);
      expect(back.map((c) => c.id), ['c-264']);
    });

    test('S-26406 running it twice changes nothing more', () async {
      await water.put(
        _oldKey(_yesterday).toString(),
        _waterMap(_oldKey(_yesterday), 400),
      );
      await targets.put(
        _oldKey(_yesterday).toString(),
        _targetMap(2000, _oldKey(_yesterday)),
      );
      await _runRepair(repo);
      final waterAfter = Map<dynamic, dynamic>.from(water.toMap());
      final targetsAfter = Map<dynamic, dynamic>.from(targets.toMap());

      await _runRepair(repo);

      expect(water.toMap(), waterAfter);
      expect(targets.toMap(), targetsAfter);
      expect(await repo.getWaterVolumeForDate(_oldKey(_yesterday)), 400);
    });

    test('S-26407 a device at version 19 repairs on its next start', () async {
      await targets.put(
        _oldKey(_yesterday).toString(),
        _targetMap(2100, _oldKey(_yesterday)),
      );
      await repo.setDataVersion(19);

      final restarted = await harness.restart() as HiveWorkoutRepository;

      expect(await restarted.getDataVersion(), 20);
      expect(
        (await restarted.getNutritionTargetForDate(
          _oldKey(_yesterday),
        ))?.calories,
        2100,
      );
    });
  });
}
