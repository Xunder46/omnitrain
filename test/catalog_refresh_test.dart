import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/models/demo_routine_spec.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/catalog_source.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

/// A [CatalogSource] whose bundled catalog can be supplied directly,
/// independent of [SeedData]. Lets tests stage the "old vs new catalog"
/// scenario without rebuilding the seed data.
class _FakeCatalogSource implements CatalogSource {
  _FakeCatalogSource({
    required this.version,
    required this.exercises,
    required this.exerciseCapabilities,
    required this.exerciseMuscleGroups,
    required this.foodCatalog,
    // No test stages demo routines through this fake yet, so the analyzer
    // sees the parameter as dead. Kept so the fake mirrors the full
    // CatalogSource surface — `routineTemplates` is a required interface
    // member, and a fake that cannot express it would quietly block the
    // first test that needs a demo-routine refresh scenario.
    // ignore: unused_element_parameter
    this.routineTemplates = const [],
  });

  @override
  final int version;

  @override
  final List<Exercise> exercises;

  @override
  final Map<String, List<String>> exerciseCapabilities;

  @override
  final Map<String, List<String>> exerciseMuscleGroups;

  @override
  final List<Food> foodCatalog;

  @override
  final List<DemoRoutineBundle> routineTemplates;
}

CatalogSource _bundledSource() {
  return _FakeCatalogSource(
    version: bundledCatalogVersion,
    exercises: SeedData.sampleExercises,
    exerciseCapabilities: SeedData.exerciseCapabilityRelationships,
    exerciseMuscleGroups: SeedData.exerciseMuscleGroupRelationships,
    foodCatalog: FoodCatalogSeed.sampleCatalogFoods,
  );
}

/// A repo that throws on the SECOND `setExerciseCapabilities` call (the
/// first call is the test setup that strips `bilateral` from the seed
/// entry; the second call is the refresh's corrective write). Models a
/// real mid-refresh failure where the first write succeeds but the second
/// fails (e.g. a transient I/O error).
class _OnceThrowingRepo extends MockWorkoutRepository {
  _OnceThrowingRepo();

  int _callCount = 0;

  @override
  Future<void> setExerciseCapabilities(
    String exerciseId,
    List<String> capabilities,
  ) async {
    _callCount++;
    if (_callCount == 2) {
      throw StateError('simulated mid-refresh failure');
    }
    return super.setExerciseCapabilities(exerciseId, capabilities);
  }
}

void main() {
  group('CatalogRefreshService', () {
    // ─────────────────────────────────────────────────────────────────────
    // S-001: version gating — no refresh when versions match
    // ─────────────────────────────────────────────────────────────────────
    test('S-001: no refresh when stored version equals bundled version', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();

      await repo.setCatalogVersion(bundledCatalogVersion);

      final service = CatalogRefreshService(repo, _bundledSource());
      final didRefresh = await service.refresh();

      expect(didRefresh, isFalse);
      expect(
        await repo.getCatalogVersion(),
        equals(bundledCatalogVersion),
        reason: 'stored version must not change when no refresh runs',
      );
    });

    test(
      'S-001b: stored version above bundled version is treated as no-op',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion + 10);

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isFalse);
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-002: catalog change reaches existing install (bilateral arrives)
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-002: missing seed capability on existing install is added by refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();

        // Simulate an "old" device: stored version is one behind, and the
        // bilateral capability is missing from the seed entry that ships
        // with the bundled catalog.
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preRefreshCaps = await repo.getExerciseCapabilities(
          dumbbellCurlId,
        );
        expect(
          preRefreshCaps,
          contains(ExerciseCapability.bilateral),
          reason:
              'bundled seed should contain bilateral; if this fails, the '
              'scenario setup is wrong',
        );
        // Strip bilateral without setting a tombstone: this models a
        // device that simply hasn't received the new flag yet.
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preRefreshCaps
              .where((c) => c != ExerciseCapability.bilateral)
              .toList(),
        );
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          isNot(contains(ExerciseCapability.bilateral)),
          reason: 'setup must produce a device without the bilateral flag',
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          contains(ExerciseCapability.bilateral),
          reason: 'refresh must add the missing capability to the device',
        );
        expect(
          await repo.getCatalogVersion(),
          equals(bundledCatalogVersion),
          reason: 'stored version must advance to the bundled version',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-003: user-created entry is preserved
    // ─────────────────────────────────────────────────────────────────────
    test('S-003: a user-created exercise is not touched by the refresh', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setCatalogVersion(bundledCatalogVersion - 1);

      final now = DateTime.now().millisecondsSinceEpoch;
      const userId = 'exercise-user-custom-squat';
      await repo.createExercise(
        Exercise(
          id: userId,
          name: 'My Custom Squat',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.setExerciseCapabilities(userId, const ['reps', 'sets']);
      final before = await repo.getExerciseById(userId);

      final service = CatalogRefreshService(repo, _bundledSource());
      await service.refresh();

      final after = await repo.getExerciseById(userId);
      expect(after, isNotNull);
      expect(after!.name, equals('My Custom Squat'));
      expect(after.capabilities, equals(const ['reps', 'sets']));
      expect(after.createdAtMs, equals(before!.createdAtMs));
      expect(
        await repo.isSeedEntryTouched(SeedEntryType.exercise, userId),
        isFalse,
        reason: 'a user-created entry must never be tombstoned by refresh',
      );
    });

    test('S-003b: a user-created food is not touched by the refresh', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setCatalogVersion(bundledCatalogVersion - 1);

      final now = DateTime.now().millisecondsSinceEpoch;
      const userFoodId = 'food-user-mine-1';
      await repo.createFood(
        Food(
          id: userFoodId,
          name: 'My Recipe',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 12,
          carbs: 30,
          fat: 5,
          isCatalog: false,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final service = CatalogRefreshService(repo, _bundledSource());
      await service.refresh();

      final after = await repo.getFoodById(userFoodId);
      expect(after, isNotNull);
      expect(after!.name, equals('My Recipe'));
      expect(after.protein, equals(12));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-004: user-edited seed entry is not overwritten
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-004: a seed entry the user has edited is not overwritten by the refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final original = await repo.getExerciseById(dumbbellCurlId);
        expect(original, isNotNull);
        await repo.updateExercise(
          original!.copyWith(name: 'DB Curl (mine)'),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          dumbbellCurlId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getExerciseById(dumbbellCurlId);
        expect(after, isNotNull);
        expect(
          after!.name,
          equals('DB Curl (mine)'),
          reason: 'user-edited seed entry must retain its user-provided name',
        );
      },
    );

    test(
      'S-004b: a user-edited catalog food is not overwritten by the refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const eggId = 'egg';
        final original = await repo.getCatalogFoodById(eggId);
        expect(original, isNotNull);
        await repo.updateCatalogFood(
          original!.copyWith(name: 'My Eggs', protein: 7),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.foodCatalog,
          eggId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getCatalogFoodById(eggId);
        expect(after, isNotNull);
        expect(after!.name, equals('My Eggs'));
        expect(after.protein, equals(7));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-005: idempotency
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-005: running refresh twice yields identical state with no duplicates',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final exercisesBefore = await repo.getExercises();
        final catalogFoodsBefore = await repo.getCatalogFoods();

        final service = CatalogRefreshService(repo, _bundledSource());
        final firstRefresh = await service.refresh();
        final exercisesAfterFirst = await repo.getExercises();
        final catalogAfterFirst = await repo.getCatalogFoods();

        expect(firstRefresh, isTrue);
        expect(
          exercisesAfterFirst.length,
          equals(exercisesBefore.length),
          reason: 'no exercise ids should be added beyond what was already '
              'on the device',
        );
        expect(catalogAfterFirst.length, equals(catalogFoodsBefore.length));

        final secondRefresh = await service.refresh();
        expect(secondRefresh, isFalse);

        final exercisesAfterSecond = await repo.getExercises();
        final catalogAfterSecond = await repo.getCatalogFoods();
        expect(exercisesAfterSecond.length, equals(exercisesAfterFirst.length));
        expect(catalogAfterSecond.length, equals(catalogAfterFirst.length));
        final firstIds = exercisesAfterFirst.map((e) => e.id).toSet();
        final secondIds = exercisesAfterSecond.map((e) => e.id).toSet();
        expect(secondIds, equals(firstIds));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-007: 150 → 168 expansion upgrade path
    //
    // The bundled catalog was expanded from 150 to 168 by the
    // 2026-08-07 expansion (added chicken wings, ground chicken, beef
    // patty, roast beef deli, salmon raw, tuna raw, cabbage, jalapeño,
    // green onion, sourdough bread, croissant, blueberry muffin,
    // pepperoni pizza slice, vanilla ice cream, California roll, half
    // and half, whipped cream, diet cola). `bundledCatalogVersion` was
    // bumped from 4 to 5 to deliver all new foods to existing installs
    // on next launch.
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-007: upgrade from prior catalog version advances the stored version '
      'and confirms the 16 new foods are present',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        // Simulate an existing install pinned to the prior version. The
        // mock seeds the catalog from the v5 bundle regardless of the
        // stored version; the upgrade path under test is the version
        // advance + refresh idempotency. The actual *delivery* of new
        // foods to a real device that was previously on v4 is covered
        // by the JSON-vs-seed parity test in `food_catalog_load_test.dart`
        // (S-014) — the catalog the device would be on once the v5
        // refresh runs is the same catalog the mock starts with.
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final preVersion = await repo.getCatalogVersion();
        expect(preVersion, equals(bundledCatalogVersion - 1));

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue,
            reason: 'refresh must report work when stored version is behind');
        expect(
          await repo.getCatalogVersion(),
          equals(bundledCatalogVersion),
          reason: 'stored version must advance to bundled on success',
        );

        final afterIds =
            (await repo.getCatalogFoods()).map((f) => f.id).toSet();
        const expectedNewIds = {
          'chicken_wing',
          'ground_chicken',
          'beef_patty',
          'roast_beef_deli',
          'salmon_raw',
          'tuna_raw',
          'cabbage',
          'jalapeno',
          'green_onion',
          'sourdough_bread',
          'croissant',
          'blueberry_muffin',
          'pizza_pepperoni_slice',
          'ice_cream_vanilla',
          'california_roll',
          'half_and_half',
          'whipped_cream',
          'diet_cola',
        };
        final missing = expectedNewIds.difference(afterIds);
        expect(
          missing,
          isEmpty,
          reason: missing.isEmpty
              ? 'never reached'
              : 'These new foods were not present after the upgrade refresh:\n'
                    '${missing.join('\n')}',
        );
      },
    );

    test(
      'S-007b: upgrade preserves user-edited values for pre-existing foods',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // The user has edited chicken_breast before this update lands.
        const eggId = 'chicken_breast';
        final original = await repo.getCatalogFoodById(eggId);
        expect(original, isNotNull);
        await repo.updateCatalogFood(
          original!.copyWith(name: 'My Chicken', protein: 40),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.foodCatalog,
          eggId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getCatalogFoodById(eggId);
        expect(after, isNotNull);
        expect(
          after!.name,
          equals('My Chicken'),
          reason:
              'user-edited seed entry must retain its user-provided name across the 150→168 refresh',
        );
        expect(after.protein, equals(40));
      },
    );

    test(
      'S-007c: running the upgrade refresh twice yields identical results',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final service = CatalogRefreshService(repo, _bundledSource());
        final first = await service.refresh();
        final firstIds =
            (await repo.getCatalogFoods()).map((f) => f.id).toSet();

        final second = await service.refresh();
        final secondIds =
            (await repo.getCatalogFoods()).map((f) => f.id).toSet();

        expect(first, isTrue);
        expect(second, isFalse,
            reason: 'second refresh at matching versions is a no-op');
        expect(secondIds, equals(firstIds));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // Delivery validation suite (2026-08-08 catalog delivery
    // hardening). The "drift went unnoticed for a whole release"
    // failure mode is locked out by the tests in this block:
    //
    //   * S-006: a device at the previous stored version receives
    //     every food in the bundled catalog and every Tier 1 + Tier
    //     2 correction to an untouched row.
    //   * S-007: a second refresh on the same device is a no-op.
    //   * S-008: a user-edited catalog food is not overwritten by
    //     the refresh (tombstone respected).
    //
    // Tier 1 = the 6-row nutrition correction pack:
    //   * chia_seeds.fiber 10 → 4.1
    //   * flax_seeds.fiber 8 → 1.9
    //   * mustard.{calories 8→9, carbs 0.6→0.9, fiber 1→0.6}
    //   * sports_drink.{calories 42→24, carbs 10.6→6.0, sodium 110→45}
    //   * sourdough_bread per-slice (1 slice)
    //   * mango per-100g (was per-fruit)
    //
    // Tier 2 = whey_protein moved from Drinks to Proteins.
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-006: refresh delivers all bundled foods and Tier 1 + Tier 2 corrections',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // Drive the device's catalog back to the pre-bump state so
        // the refresh has real diff work to do. The mock seeds from
        // the current bundle (which already has the Tier 1/2
        // corrections and the hidden state); we walk specific rows
        // back to their pre-bump values. `MockWorkoutRepository.
        // updateCatalogFood` does not auto-set the tombstone marker,
        // so the refresh will diff these rows against the bundled
        // source and apply the corrections. This is the same
        // pattern the existing S-007 (hidden state) and S-007b
        // (chicken_breast) tests use.
        Future<void> preBump(String id, Food pre) async {
          await repo.updateCatalogFood(pre);
        }

        await preBump('chia_seeds', const Food(
          id: 'chia_seeds',
          name: 'Chia seeds',
          groupId: 'food-group-nuts-seeds-fats',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 2,
          carbs: 5,
          fiber: 10, // pre-correction: 10
          fat: 4,
          sodium: 2,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        await preBump('flax_seeds', const Food(
          id: 'flax_seeds',
          name: 'Flax seeds',
          groupId: 'food-group-nuts-seeds-fats',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 1.3,
          carbs: 2,
          fiber: 8, // pre-correction: 8
          fat: 3,
          sodium: 3,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        await preBump('mustard', const Food(
          id: 'mustard',
          name: 'Mustard',
          groupId: 'food-group-condiments',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 4,
          carbs: 0.6, // pre-correction: 0.6
          fiber: 1, // pre-correction: 1
          fat: 4,
          sodium: 56,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        await preBump('sports_drink', const Food(
          id: 'sports_drink',
          name: 'Sports drink',
          groupId: 'food-group-drinks',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'ml',
          isCatalog: true,
          protein: 0,
          carbs: 10.6, // pre-correction: 10.6
          fat: 0,
          sodium: 110, // pre-correction: 110
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        await preBump('sourdough_bread', const Food(
          id: 'sourdough_bread',
          name: 'Sourdough bread',
          groupId: 'food-group-grains-starches',
          unitType: FoodUnitType.grams, // pre-correction: grams (per 100 g)
          referenceAmount: 100, // pre-correction: 100
          referenceLabel: 'g',
          isCatalog: true,
          protein: 11,
          carbs: 49,
          fiber: 2.4,
          fat: 1.6,
          sodium: 590,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        await preBump('mango', const Food(
          id: 'mango',
          name: 'Mango, medium', // pre-correction: per-fruit
          groupId: 'food-group-fruits',
          unitType: FoodUnitType.count, // pre-correction: count (1 fruit)
          referenceAmount: 1, // pre-correction: 1 fruit
          referenceLabel: 'fruit',
          isCatalog: true,
          protein: 1.4,
          carbs: 25,
          fiber: 2.6,
          fat: 0.6,
          sodium: 2,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));
        // Tier 2: whey_protein in Drinks (pre-correction).
        await preBump('whey_protein', const Food(
          id: 'whey_protein',
          name: 'Whey protein',
          groupId: 'food-group-drinks', // pre-correction: Drinks
          unitType: FoodUnitType.count,
          referenceAmount: 1,
          referenceLabel: 'scoop',
          isCatalog: true,
          protein: 24,
          carbs: 3,
          fiber: 1,
          fat: 1.5,
          sodium: 50,
          createdAtMs: 1700000000000,
          updatedAtMs: 1700000000000,
        ));

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));

        // Every food in the current bundle is present on the device.
        final deviceIds =
            (await repo.getCatalogFoods(includeArchived: true))
                .map((f) => f.id)
                .toSet();
        final bundledIds =
            FoodCatalogSeed.sampleCatalogFoods.map((f) => f.id).toSet();
        final missing = bundledIds.difference(deviceIds);
        expect(
          missing,
          isEmpty,
          reason:
              'refresh from v${bundledCatalogVersion - 1} to v'
              '$bundledCatalogVersion must deliver every bundled food; '
              'missing:\n${missing.join('\n')}',
        );

        // Tier 1 corrections: the macro / unit changes ship to the device.
        Future<Food> load(String id) async =>
            (await repo.getCatalogFoodById(id))!;
        expect((await load('chia_seeds')).fiber, 4.1);
        expect((await load('flax_seeds')).fiber, 1.9);
        expect((await load('mustard')).carbs, 0.9);
        expect((await load('mustard')).fiber, 0.6);
        expect((await load('mustard')).calories, 9);
        expect((await load('sports_drink')).calories, 24);
        expect((await load('sports_drink')).carbs, 6.0);
        expect((await load('sports_drink')).sodium, 45);
        expect(
          (await load('sourdough_bread')).unitType,
          FoodUnitType.count,
        );
        expect((await load('sourdough_bread')).referenceAmount, 1);
        expect((await load('sourdough_bread')).referenceLabel, 'slice');
        expect((await load('sourdough_bread')).calories, 141);
        expect((await load('mango')).unitType, FoodUnitType.grams);
        expect((await load('mango')).referenceAmount, 100);
        expect((await load('mango')).referenceLabel, 'g');
        expect((await load('mango')).name, 'Mango');

        // Tier 2 correction: whey_protein moved to Proteins.
        expect((await load('whey_protein')).groupId, 'food-group-proteins');

        // The 2026-08-08 hidden state for the two retired rows
        // arrives through the same refresh path (S-007 above).
        expect((await load('beer_regular')).isArchived, isTrue);
        expect((await load('red_wine')).isArchived, isTrue);
      },
    );

    test(
      'S-007: refresh from the previous stored version is a no-op the second time',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        // Second pass: versions match, refresh must be a no-op.
        final second = await service.refresh();
        expect(
          second,
          isFalse,
          reason:
              'after a successful refresh, the stored version equals the '
              'bundled version; subsequent refreshes must not perform '
              'work',
        );
        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));
      },
    );

    test(
      'S-008: refresh respects the user-edit tombstone (does not overwrite '
      'a user-edited catalog food)',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // The user has personally edited chia_seeds (a Tier 1
        // correction target) — fiber back to the pre-correction 10.
        // The tombstone marker is what blocks the refresh.
        const chiaSeedsId = 'chia_seeds';
        final original = await repo.getCatalogFoodById(chiaSeedsId);
        expect(original, isNotNull);
        await repo.updateCatalogFood(
          original!.copyWith(fiber: 10, name: 'Chia (mine)'),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.foodCatalog,
          chiaSeedsId,
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getCatalogFoodById(chiaSeedsId);
        expect(after, isNotNull);
        expect(
          after!.fiber,
          10,
          reason:
              'tombstoned row must keep its user-set fiber; the published '
              'Tier 1 correction (4.1) must not overwrite it',
        );
        expect(
          after.name,
          'Chia (mine)',
          reason: 'tombstoned row must keep its user-set name',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-007/S-008/S-009 (refresh-side, beer/wine retirement)
    //
    // The 2026-08-08 bump publishes `beer_regular` and `red_wine`
    // with `hidden: true` (because the calorie model cannot
    // represent alcohol-derived energy — see
    // `.github/agents/plans/2026-08-08-retire-alcohol-catalog-rows-plan.md`).
    // The existing `CatalogRefreshService._foodDiffers` already
    // compares `isArchived`, so the published hidden state arrives
    // on every existing device through the same per-row diff path
    // that ships a nutrition correction. These three scenarios cover
    // the three outcomes:
    //
    //   * S-007: an untouched stored row receives the new hidden state.
    //   * S-008: a stored row that is currently hidden is unhidden when
    //     the bundle flips the row back to visible (reversibility).
    //   * S-009: a user-touched row is skipped — the user-set hidden
    //     state wins over the published state.
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-007: refresh publishes the hidden state for beer_regular and red_wine',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // The mock starts from the bundled source already (v8), so
        // beer and wine are seeded as hidden. Walk the device back
        // to a pre-retirement state: stored version one behind, both
        // rows present with `isArchived = false` (the user's prior
        // catalog had no `hidden` field and parsed to false).
        const beerId = 'beer_regular';
        const wineId = 'red_wine';
        final beerBefore = await repo.getCatalogFoodById(beerId);
        final wineBefore = await repo.getCatalogFoodById(wineId);
        expect(beerBefore, isNotNull);
        expect(wineBefore, isNotNull);
        await repo.updateCatalogFood(beerBefore!.copyWith(isArchived: false));
        await repo.updateCatalogFood(wineBefore!.copyWith(isArchived: false));
        expect((await repo.getCatalogFoodById(beerId))!.isArchived, isFalse);
        expect((await repo.getCatalogFoodById(wineId))!.isArchived, isFalse);

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(await repo.getCatalogVersion(), equals(bundledCatalogVersion));

        // Both rows are now archived on the device.
        final beerAfter = (await repo.getCatalogFoodById(beerId))!;
        final wineAfter = (await repo.getCatalogFoodById(wineId))!;
        expect(beerAfter.isArchived, isTrue);
        expect(wineAfter.isArchived, isTrue);

        // Every other field is preserved — the retirement is
        // non-destructive. (Calories are not asserted; they are
        // derived from the macros on the model.)
        expect(beerAfter.name, 'Beer, regular');
        expect(beerAfter.protein, 0.5);
        expect(beerAfter.carbs, 3.6);
        expect(beerAfter.fat, 0);
        expect(beerAfter.sodium, 10);
        expect(wineAfter.name, 'Red wine');
        expect(wineAfter.protein, 0.1);
        expect(wineAfter.carbs, 2.6);
        expect(wineAfter.fat, 0);
        expect(wineAfter.sodium, 6);
      },
    );

    test(
      'S-008: refresh reverses a hidden state when the bundle flips the row '
      'visible again',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // Device is currently on the pre-retirement bundle: both
        // rows present and archived (because the v8 mock already
        // seeded them as hidden). Reset to that state explicitly
        // so the test stays robust to the bundled seed changing.
        const beerId = 'beer_regular';
        await repo.updateCatalogFood(
          (await repo.getCatalogFoodById(beerId))!.copyWith(isArchived: true),
        );

        // Bundle now publishes beer_regular as visible. Bump the
        // source version so the refresh actually runs.
        final visibleBeer = (await repo.getCatalogFoodById(beerId))!
            .copyWith(isArchived: false);
        final source = _FakeCatalogSource(
          version: bundledCatalogVersion + 1,
          exercises: SeedData.sampleExercises,
          exerciseCapabilities: SeedData.exerciseCapabilityRelationships,
          exerciseMuscleGroups: SeedData.exerciseMuscleGroupRelationships,
          foodCatalog: [
            for (final f in FoodCatalogSeed.sampleCatalogFoods)
              if (f.id == beerId) visibleBeer else f,
          ],
        );

        final service = CatalogRefreshService(repo, source);
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(
          await repo.getCatalogVersion(),
          equals(bundledCatalogVersion + 1),
        );
        final after = (await repo.getCatalogFoodById(beerId))!;
        expect(
          after.isArchived,
          isFalse,
          reason:
              'a freshly-published visible state must overwrite a stored '
              'hidden state for an untouched row',
        );
        // Every other field is preserved across the reversal.
        expect(after.name, 'Beer, regular');
        expect(after.protein, 0.5);
      },
    );

    test(
      'S-009: refresh skips a user-touched row and leaves its hidden state alone',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        // The user has personally un-hidden beer_regular (and the
        // tombstone is set so the refresh must skip this row).
        const beerId = 'beer_regular';
        final original = await repo.getCatalogFoodById(beerId);
        expect(original, isNotNull);
        await repo.updateCatalogFood(
          original!.copyWith(isArchived: false, name: 'Beer (mine)'),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.foodCatalog,
          beerId,
        );

        // Bundle still publishes it hidden.
        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();

        final after = await repo.getCatalogFoodById(beerId);
        expect(after, isNotNull);
        expect(
          after!.isArchived,
          isFalse,
          reason:
              'user-tombstoned row keeps the user-set hidden state; the '
              'published `hidden: true` does not override it',
        );
        expect(
          after.name,
          'Beer (mine)',
          reason: 'user-set name is also preserved across the refresh',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-006: interruption safety
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-006: a mid-refresh failure leaves prior data intact and the stored '
      'version is not advanced',
      () async {
        final repo = _OnceThrowingRepo();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
        );
        final storedVersionBefore = await repo.getCatalogVersion();

        final service = CatalogRefreshService(repo, _bundledSource());

        Object? caughtError;
        try {
          await service.refresh();
        } catch (e) {
          caughtError = e;
        }
        expect(
          caughtError,
          isNotNull,
          reason: 'refresh must propagate the simulated failure',
        );

        expect(
          await repo.getCatalogVersion(),
          equals(storedVersionBefore),
          reason: 'on failure the stored version must stay at the old value',
        );
        final postCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        expect(
          postCaps,
          isNot(contains(ExerciseCapability.bilateral)),
          reason: 'failed refresh must not leave partial state behind',
        );
      },
    );

    test(
      'S-006b: after a failed refresh the next launch retries from scratch',
      () async {
        final repo = _OnceThrowingRepo();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        const dumbbellCurlId = 'exercise-dumbbell-curl';
        final preCaps = await repo.getExerciseCapabilities(dumbbellCurlId);
        await repo.setExerciseCapabilities(
          dumbbellCurlId,
          preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
        );

        final service = CatalogRefreshService(repo, _bundledSource());
        try {
          await service.refresh();
          fail('expected refresh to throw');
        } catch (_) {
          // Expected.
        }

        final secondRefresh = await service.refresh();
        expect(secondRefresh, isTrue);
        expect(
          await repo.getExerciseCapabilities(dumbbellCurlId),
          contains(ExerciseCapability.bilateral),
        );
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  // S-007: real catalog-loading path delivers the change (masking test)
  // ────────────────────────────────────────────────────────────────────────
  testWidgets(
    'S-007: bilateral note visible through the real startup path',
    (WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setCatalogVersion(bundledCatalogVersion - 1);
      const dumbbellCurlId = 'exercise-dumbbell-curl';
      final preCaps = await repository.getExerciseCapabilities(dumbbellCurlId);
      await repository.setExerciseCapabilities(
        dumbbellCurlId,
        preCaps.where((c) => c != ExerciseCapability.bilateral).toList(),
      );

      final refresh = CatalogRefreshService(repository, _bundledSource());
      await refresh.refresh();

      await repository.setPreferenceBool('hint_seen_exercise_info', true);
      await repository.setPreferenceBool('hint_seen_exercise_notes', true);
      final workoutState = WorkoutState(repository);
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final bilateralExercise = (await workoutState
          .getExercisesRankedForModality(modality: 'resistance_lifting'))
          .firstWhere(
        (e) => e.capabilities.contains(ExerciseCapability.bilateral),
      );
      await workoutState.addExerciseToSession(
        bilateralExercise,
        chosenMetric: 'reps',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(
              repository,
              fakePreferencesService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(bilateralExercise.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exercise-info-button')));
      await tester.pumpAndSettle();

      expect(find.text('LOGGING NOTE'), findsOneWidget);
      expect(
        find.textContaining('Log both sides as a single combined set'),
        findsOneWidget,
      );
    },
  );
}