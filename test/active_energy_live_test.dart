// Plan 134d phase P1 — the live estimate: service + state.
//
// Red reasons: `ActiveEnergyService.liveKcal` and `latestWeightKg` and
// `WorkoutState.latestBodyWeightKg` do not exist yet.
//
// Plan: docs/plans/2026-11-09-134d-live-session-calories-plan/2026-11-09-134d-live-session-calories-plan.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

var _entry = 0;

Future<void> _seedWeight(
  WorkoutRepository repo,
  double value, {
  String unitId = 'unit-kg',
}) async {
  final n = _entry++;
  await repo.saveMeasurementEntry(
    BodyMeasurementEntry(
      id: 'bm-$n',
      measurementType: 'bodyweight',
      value: value,
      unitId: unitId,
      recordedAtMs: fixtureStart + 9676800000 + n,
    ),
  );
}

Future<void> _seedResistanceSession(
  WorkoutRepository repo, {
  required String id,
}) async {
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: 0,
      endedAtMs: 3600000,
      modality: 'resistance_lifting',
      isRolling: false,
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  );
}

ActiveEnergyService _energy(WorkoutRepository repo) =>
    ActiveEnergyService(repo, () => StatsProgressService(repo));

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('S-13440 — liveKcal figures', () {
    test('resistance 1800 s at 80 kg is 100.0', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 1800,
          weightKg: 80,
        ),
        closeTo(100.0, 1e-9),
      );
    });

    test('cardio 600 s at 80 kg is 66.666…', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'cardio_endurance',
          elapsedSecs: 600,
          weightKg: 80,
        ),
        closeTo(66.66666666666667, 1e-9),
      );
    });

    test('isometric 3600 s at 80 kg is 160.0', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'isometric_stretching',
          elapsedSecs: 3600,
          weightKg: 80,
        ),
        closeTo(160.0, 1e-9),
      );
    });

    test('sports 5400 s at 70 kg is 525.0', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'sports',
          elapsedSecs: 5400,
          weightKg: 70,
        ),
        closeTo(525.0, 1e-9),
      );
    });

    test(
      'null modality (Free Training) 3600 s at 80 kg is resistance 200.0',
      () {
        expect(
          ActiveEnergyService.liveKcal(
            modality: null,
            elapsedSecs: 3600,
            weightKg: 80,
          ),
          closeTo(200.0, 1e-9),
        );
      },
    );

    test(
      "unknown id 'conditioning_mixed' 3600 s at 80 kg is resistance 200.0",
      () {
        expect(
          ActiveEnergyService.liveKcal(
            modality: 'conditioning_mixed',
            elapsedSecs: 3600,
            weightKg: 80,
          ),
          closeTo(200.0, 1e-9),
        );
      },
    );
  });

  group('S-13441 — liveKcal guards', () {
    test('weight null is null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 3600,
          weightKg: null,
        ),
        isNull,
      );
    });

    test('weight 0 is null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 3600,
          weightKg: 0,
        ),
        isNull,
      );
    });

    test('weight -5 is null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 3600,
          weightKg: -5,
        ),
        isNull,
      );
    });

    test('weight NaN is null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 3600,
          weightKg: double.nan,
        ),
        isNull,
      );
    });

    test('elapsed -1 is null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: -1,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('elapsed 0 with weight 80 is 0.0, never null', () {
      expect(
        ActiveEnergyService.liveKcal(
          modality: 'resistance_lifting',
          elapsedSecs: 0,
          weightKg: 80,
        ),
        0.0,
      );
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — S-13442 final equals live', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'settle of a 3600 s resistance session at 80 kg equals liveKcal',
        () async {
          await _seedWeight(repo, 80);
          await _seedResistanceSession(repo, id: 's-live');

          final service = _energy(repo);
          await service.settle('s-live');
          final row = await repo.getSessionEnergy('s-live');

          expect(row, isNotNull, reason: 'settle wrote no row');
          expect(
            row!.activeKcal,
            ActiveEnergyService.liveKcal(
              modality: 'resistance_lifting',
              elapsedSecs: 3600,
              weightKg: 80,
            ),
            reason: 'the stored estimate and the live figure share one formula',
          );
          expect(row.activeKcal, closeTo(200.0, 1e-9));
        },
      );
    });

    group('${harness.name} — S-13443 latestWeightKg', () {
      late ActiveEnergyService service;
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        service = _energy(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test('none logged is null', () async {
        expect(await service.latestWeightKg(), isNull);
      });

      test('a kg entry 80 is 80.0', () async {
        await _seedWeight(repo, 80);

        expect(await service.latestWeightKg(), 80.0);
      });

      test('a newer unit-lbs entry wins and answers null', () async {
        await _seedWeight(repo, 80);
        await _seedWeight(repo, 176, unitId: 'unit-lbs');

        expect(await service.latestWeightKg(), isNull);
      });

      test('a kg entry 0 is null', () async {
        await _seedWeight(repo, 0);

        expect(await service.latestWeightKg(), isNull);
      });

      test('two kg entries 80 then 82 answer the newest, 82.0', () async {
        await _seedWeight(repo, 80);
        await _seedWeight(repo, 82);

        expect(await service.latestWeightKg(), 82.0);
      });
    });
  }

  group('S-13444 — WorkoutState passthrough', () {
    test('with the service, an 80 kg entry answers 80.0', () async {
      final repo = await _freshRepo();
      await _seedWeight(repo, 80);

      final state = WorkoutState(repo, activeEnergy: _energy(repo));

      expect(await state.latestBodyWeightKg(), 80.0);
    });

    test('without the service it answers null', () async {
      final repo = await _freshRepo();
      await _seedWeight(repo, 80);

      final state = WorkoutState(repo);

      expect(await state.latestBodyWeightKg(), isNull);
    });
  });
}
