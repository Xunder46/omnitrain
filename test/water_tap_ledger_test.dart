// Plan 94 (PR 94a) Phase 2 — the per-day water tap ledger.
//
// A wrist tap is applied to the day's water at most once: the tap's id is
// kept in the same storage row as the volume, so the volume and the ledger
// change in one write (D-3, D-4, D-5). Every storage scenario runs on both
// `MockWorkoutRepository` and `HiveWorkoutRepository` (I-2).
//
// Plan: `docs/plans/2026-11-01-94-watch-water-logging-plan/`.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/water_constants.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition_state.dart';

import 'helpers/repository_harness.dart';

/// Fixture W: local calendar days, never pinned to a time zone (D-16).
final int dMs = DateTime(2026, 11, 1).millisecondsSinceEpoch;
final int pMs = DateTime(2026, 10, 31).millisecondsSinceEpoch;
final int nMs = DateTime(2026, 11, 2).millisecondsSinceEpoch;
final int qMs = DateTime(2026, 10, 30).millisecondsSinceEpoch;

void main() {
  group('water constants (D-11)', () {
    test('waterGlassesFor is whole glasses of kWaterGlassMl', () {
      expect(waterGlassesFor(0), 0);
      expect(waterGlassesFor(249), 0);
      expect(waterGlassesFor(250), 1);
      expect(waterGlassesFor(350), 1);
      expect(waterGlassesFor(850), 3);
      expect(kWatchWaterTapsPerDay, 500);
    });
  });

  group('WaterLogEntry round trip (D-4)', () {
    test('appliedTapIds survives toMap → fromMap, in order', () {
      const entry = WaterLogEntry(
        id: 'water-1',
        dateMs: 1,
        volumeMl: 500,
        createdAtMs: 2,
        updatedAtMs: 3,
        appliedTapIds: ['w-2', 'w-1'],
      );
      final back = WaterLogEntry.fromMap(entry.toMap());
      expect(back.appliedTapIds, ['w-2', 'w-1']);
      expect(back.volumeMl, 500);
      expect(back.id, 'water-1');
      expect(back.dateMs, 1);
      expect(back.createdAtMs, 2);
      expect(back.updatedAtMs, 3);
    });

    test('a map without applied_tap_ids reads as an empty ledger', () {
      final entry = WaterLogEntry.fromMap(<String, dynamic>{
        'id': 'water-1',
        'date_ms': 1,
        'volume_ml': 750,
        'created_at_ms': 2,
        'updated_at_ms': 3,
      });
      expect(entry.appliedTapIds, isEmpty);
      const bare = WaterLogEntry(
        id: 'water-1',
        dateMs: 1,
        volumeMl: 0,
        createdAtMs: 2,
        updatedAtMs: 3,
      );
      expect(bare.appliedTapIds, isEmpty);
      expect(WaterLogEntry.fromMap(bare.toMap()).appliedTapIds, isEmpty);
    });

    test('the Hive row shape (a list) reads as the same ledger', () {
      final entry = WaterLogEntry.fromMap(<String, dynamic>{
        'id': 'water-1',
        'date_ms': 1,
        'volume_ml': 250,
        'created_at_ms': 2,
        'updated_at_ms': 3,
        'applied_tap_ids': <dynamic>['w-1'],
      });
      expect(entry.appliedTapIds, ['w-1']);
    });

    test('copyWith replaces the ledger and keeps it otherwise', () {
      const entry = WaterLogEntry(
        id: 'water-1',
        dateMs: 1,
        volumeMl: 0,
        createdAtMs: 2,
        updatedAtMs: 3,
        appliedTapIds: ['w-1'],
      );
      expect(entry.copyWith(volumeMl: 250).appliedTapIds, ['w-1']);
      expect(entry.copyWith(appliedTapIds: ['w-9']).appliedTapIds, ['w-9']);
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('water tap ledger — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-94a-3 add and remove math matches the phone buttons, including '
          'volumes that are not whole glasses', () async {
        final starts = <int, int>{dMs: 0, pMs: 100, nMs: 600, qMs: 600};
        for (final e in starts.entries) {
          await repo.saveWaterVolumeForDate(e.key, e.value);
        }

        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'a1',
            deltaMl: kWaterGlassMl,
          ),
          isTrue,
        );
        expect(
          await repo.applyWaterTap(
            dateMs: pMs,
            tapId: 'a2',
            deltaMl: -kWaterGlassMl,
          ),
          isTrue,
        );
        expect(
          await repo.applyWaterTap(
            dateMs: nMs,
            tapId: 'a3',
            deltaMl: kWaterGlassMl,
          ),
          isTrue,
        );
        expect(
          await repo.applyWaterTap(
            dateMs: qMs,
            tapId: 'a4',
            deltaMl: -kWaterGlassMl,
          ),
          isTrue,
        );

        final volumes = [
          for (final day in [dMs, pMs, nMs, qMs])
            await repo.getWaterVolumeForDate(day),
        ];
        expect(volumes, [250, 0, 850, 350]);
        expect(volumes.map(waterGlassesFor).toList(), [1, 0, 3, 1]);

        // Parity (I-3): the phone's own buttons over a third repository
        // seeded alike reach the same four volumes.
        final phoneRepo = MockWorkoutRepository();
        await phoneRepo.initialize();
        for (final e in starts.entries) {
          await phoneRepo.saveWaterVolumeForDate(e.key, e.value);
        }
        final phone = NutritionState(phoneRepo);
        await phone.incrementWaterForDate(dMs);
        await phone.decrementWaterForDate(pMs);
        await phone.incrementWaterForDate(nMs);
        await phone.decrementWaterForDate(qMs);
        expect([
          for (final day in [dMs, pMs, nMs, qMs])
            await phoneRepo.getWaterVolumeForDate(day),
        ], volumes);
      });

      test('S-94a-4 a remove at 0 is recorded once', () async {
        expect(await repo.getAppliedWaterTapIds(dMs), isEmpty);
        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-0',
            deltaMl: -kWaterGlassMl,
          ),
          isTrue,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 0);
        expect(await repo.getAppliedWaterTapIds(dMs), ['w-0']);
        if (harness.name == 'Hive') {
          final row = Hive.box<Map>('water_log').get(dMs.toString());
          expect(row, isNotNull, reason: 'a row with 0 ml exists');
          expect(row!['volume_ml'], 0);
        }

        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-0',
            deltaMl: -kWaterGlassMl,
          ),
          isFalse,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 0);
        expect(await repo.getAppliedWaterTapIds(dMs), ['w-0']);
      });

      test('S-94a-5 a duplicate changes nothing, before and after a '
          'relaunch', () async {
        await repo.saveWaterVolumeForDate(dMs, 500);
        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-1',
            deltaMl: kWaterGlassMl,
          ),
          isTrue,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 750);

        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-1',
            deltaMl: kWaterGlassMl,
          ),
          isFalse,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 750);

        repo = await harness.restart();
        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-1',
            deltaMl: kWaterGlassMl,
          ),
          isFalse,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 750);
        expect(await repo.getAppliedWaterTapIds(dMs), ['w-1']);
      });

      test('S-94a-6 the phone\'s own write keeps the ledger', () async {
        await repo.applyWaterTap(
          dateMs: dMs,
          tapId: 'w-1',
          deltaMl: kWaterGlassMl,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 250);

        await repo.saveWaterVolumeForDate(dMs, 500);
        expect(await repo.getWaterVolumeForDate(dMs), 500);
        expect(await repo.getAppliedWaterTapIds(dMs), ['w-1']);

        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-1',
            deltaMl: kWaterGlassMl,
          ),
          isFalse,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 500);
      });

      test('S-94a-7 the per-day cap refuses tap 501', () async {
        for (var i = 0; i < kWatchWaterTapsPerDay; i++) {
          final id = 't-${i.toString().padLeft(3, '0')}';
          expect(
            await repo.applyWaterTap(
              dateMs: dMs,
              tapId: id,
              deltaMl: kWaterGlassMl,
            ),
            isTrue,
            reason: id,
          );
        }
        expect(await repo.getWaterVolumeForDate(dMs), 125000);

        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 't-500',
            deltaMl: kWaterGlassMl,
          ),
          isFalse,
        );
        expect(await repo.getWaterVolumeForDate(dMs), 125000);
        final ledger = await repo.getAppliedWaterTapIds(dMs);
        expect(ledger.length, 500);
        expect(ledger.first, 't-000');
        expect(ledger.last, 't-499');
      });

      test('S-94a-8 days are independent; an old row has no ledger', () async {
        await repo.saveWaterVolumeForDate(pMs, 250);
        if (harness.name == 'Hive') {
          // A row written before 94a: no applied_tap_ids key.
          await Hive.box<Map>(
            'water_log',
          ).put(dMs.toString(), <String, dynamic>{
            'id': WaterLogEntry.idForDate(dMs),
            'date_ms': dMs,
            'volume_ml': 750,
            'created_at_ms': 1,
            'updated_at_ms': 1,
          });
        } else {
          await repo.saveWaterVolumeForDate(dMs, 750);
        }

        expect(
          await repo.applyWaterTap(
            dateMs: pMs,
            tapId: 'w-p',
            deltaMl: kWaterGlassMl,
          ),
          isTrue,
        );
        expect(await repo.getWaterVolumeForDate(pMs), 500);
        expect(await repo.getAppliedWaterTapIds(pMs), ['w-p']);

        expect(await repo.getAppliedWaterTapIds(dMs), isEmpty);
        expect(
          await repo.applyWaterTap(
            dateMs: dMs,
            tapId: 'w-d',
            deltaMl: kWaterGlassMl,
          ),
          isTrue,
        );
        expect(await repo.getAppliedWaterTapIds(dMs), ['w-d']);
        expect(await repo.getWaterVolumeForDate(dMs), 1000);
        expect(await repo.getAppliedWaterTapIds(dMs), isNot(contains('w-p')));
        // The other days were never written.
        expect(await repo.getAppliedWaterTapIds(nMs), isEmpty);
        expect(await repo.getWaterVolumeForDate(nMs), 0);
      });
    });
  }

  test('Mock clear() empties the ledger with the volumes', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    await repo.applyWaterTap(dateMs: dMs, tapId: 'w-1', deltaMl: kWaterGlassMl);
    repo.clear();
    expect(await repo.getWaterVolumeForDate(dMs), 0);
    expect(await repo.getAppliedWaterTapIds(dMs), isEmpty);
    expect(
      await repo.applyWaterTap(
        dateMs: dMs,
        tapId: 'w-1',
        deltaMl: kWaterGlassMl,
      ),
      isTrue,
    );
  });
}
