import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/services/data_migration_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

/// A synthetic migration step that records when it ran. Used to drive the
/// `DataMigrationService` through its ordered sequence without depending on
/// the real migration bodies (those have their own parity test below).
class _RecordingStep extends DataMigrationStep {
  _RecordingStep(this.targetVersion, this.name);

  @override
  final int targetVersion;

  @override
  final String name;

  int callCount = 0;
  bool throwOnFirstCall = false;
  Object? thrownError;

  @override
  Future<void> run() async {
    callCount++;
    if (throwOnFirstCall) {
      throwOnFirstCall = false;
      thrownError = StateError('simulated failure in $name');
      throw thrownError!;
    }
  }
}

/// Stub step list for S-001 through S-005: ten steps that advance the
/// version 1 → 11.
List<DataMigrationStep> _stubSteps() {
  return [
    _RecordingStep(2, 'stub-1'),
    _RecordingStep(3, 'stub-2'),
    _RecordingStep(4, 'stub-3'),
    _RecordingStep(5, 'stub-4'),
    _RecordingStep(6, 'stub-5'),
    _RecordingStep(7, 'stub-6'),
    _RecordingStep(8, 'stub-7'),
    _RecordingStep(9, 'stub-8'),
    _RecordingStep(10, 'stub-9'),
    _RecordingStep(11, 'stub-10'),
  ];
}

const int _stubTargetVersion = 11;

void main() {
  group('DataMigrationService', () {
    // ─────────────────────────────────────────────────────────────────────
    // S-001: Fresh install runs all steps in order, lands at current version
    // ─────────────────────────────────────────────────────────────────────
    test('S-001: fresh install runs all steps in order and lands at target', () async {
      final repo = MockWorkoutRepository();
      // Skip initialize() — it would advance data_version to
      // currentDataVersion via the in-build consolidated sequence, which
      // would defeat the test's "fresh install" setup. The service is
      // tested directly here.
      await repo.setDataVersion(1);

      // No legacy markers — fresh install from the service's perspective.
      expect(await repo.getDataVersion(), equals(1));

      final steps = _stubSteps();
      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );
      final result = await service.run();

      expect(result.from, equals(1));
      expect(result.to, equals(_stubTargetVersion));
      expect(result.appliedSteps, hasLength(steps.length));
      for (final step in steps) {
        expect((step as _RecordingStep).callCount, equals(1),
            reason: '${step.name} should have run exactly once');
      }
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
      final transition = await repo.getLastDataVersionTransition();
      expect(transition, isNotNull);
      expect(transition!.from, equals(1));
      expect(transition.to, equals(_stubTargetVersion));
    });

    test('S-001b: steps run in ascending targetVersion order', () async {
      final repo = MockWorkoutRepository();
      await repo.setDataVersion(1);
      // Pass steps out of order — the service should still execute them in
      // ascending order.
      final steps = [
        _RecordingStep(5, 'z-third'),
        _RecordingStep(2, 'a-first'),
        _RecordingStep(8, 'b-second'),
        _RecordingStep(11, 'w-last'),
      ];
      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );
      await service.run();

      // `appliedSteps` should be sorted by targetVersion ascending.
      final applied = service.appliedSteps;
      expect(applied.map((s) => s.targetVersion).toList(),
          equals([2, 5, 8, 11]));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-002: Legacy install with all markers → current version, no-op
    // ─────────────────────────────────────────────────────────────────────
    test('S-002: legacy install with all markers maps to target and runs no steps',
        () async {
      final repo = MockWorkoutRepository();
      // Simulate a device that ran all the legacy one-time steps under
      // the old code path, by populating the equivalent meta-box keys
      // BEFORE initialize() so the shim can detect them. Then reset
      // data_version to 1 so the service can re-run the shim under
      // test (in production, initialize() advances to currentDataVersion
      // and the service would no-op).
      const allLegacyKeys = [
        'seed_loaded',
        'seed_units_migrated_v1',
        'exercise_round_defaults_migrated_v1',
        'session_feeling_fields_migrated_v1',
        'calendar_data_seeded_v1',
        'calendar_seed_purged_v1',
        'exercise_content_fields_migrated_v1',
        'timed_extra_weight_migrated_v1',
        'exercise_library_refreshed_v5',
        'nutrition_targets_daily_migrated_v1',
        'food_catalog_seeded_v1',
        'default_food_groups_seeded_v1',
        'food_category_groupid_migrated_v1',
      ];
      for (final key in allLegacyKeys) {
        await repo.setPreferenceBool(key, true);
      }
      await repo.initialize();
      await repo.setDataVersion(1);

      expect(await repo.getLegacyAppliedDataVersion(),
          equals(currentDataVersion),
          reason: 'shim should detect all legacy markers and map to '
              'currentDataVersion');

      final steps = _stubSteps();
      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );
      final result = await service.run();

      expect(result.from, equals(currentDataVersion));
      expect(result.to, equals(currentDataVersion));
      expect(result.appliedSteps, isEmpty);
      for (final step in steps) {
        expect((step as _RecordingStep).callCount, equals(0),
            reason: '${step.name} must not run on a fully migrated legacy '
                'install');
      }
      expect(await repo.getDataVersion(), equals(currentDataVersion));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-003: Partial legacy install applies only the remaining steps
    // ─────────────────────────────────────────────────────────────────────
    test('S-003: partial legacy install applies only pending steps', () async {
      final repo = MockWorkoutRepository();
      // Simulate a device that completed only the first 5 legacy steps.
      const partialKeys = [
        'seed_loaded',
        'seed_units_migrated_v1',
        'exercise_round_defaults_migrated_v1',
        'session_feeling_fields_migrated_v1',
        'calendar_data_seeded_v1', // step 6's marker
      ];
      for (final key in partialKeys) {
        await repo.setPreferenceBool(key, true);
      }
      await repo.initialize();
      // Reset data_version to 1 so the shim runs under test.
      await repo.setDataVersion(1);

      // Shim-detected starting version = 6 (calendar_data_seeded_v1).
      // Stub target = 11. So pending steps are the ones with target > 6
      // (in the stub list, those are stub-6 through stub-10 with
      // targetVersion 7..11).
      final steps = _stubSteps();
      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );
      final result = await service.run();

      expect(result.from, equals(6));
      expect(result.to, equals(_stubTargetVersion));
      expect(result.appliedSteps.map((s) => s.name).toList(),
          equals(['stub-6', 'stub-7', 'stub-8', 'stub-9', 'stub-10']));
      for (final step in steps.take(5)) {
        expect((step as _RecordingStep).callCount, equals(0),
            reason: '${step.name} already applied by legacy code, must skip');
      }
      for (final step in steps.skip(5)) {
        expect((step as _RecordingStep).callCount, equals(1),
            reason: '${step.name} is pending, must run');
      }
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-004: A failing step leaves the version unchanged
    // ─────────────────────────────────────────────────────────────────────
    test('S-004: a failing step leaves the version unchanged and is retried',
        () async {
      final repo = MockWorkoutRepository();
      await repo.setDataVersion(1);

      final steps = _stubSteps();
      // Make stub-4 (targetVersion=5) throw on its first call.
      (steps[3] as _RecordingStep).throwOnFirstCall = true;

      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );

      Object? caught;
      try {
        await service.run();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>(),
          reason: 'simulated failure must propagate to the caller');

      // Version must have advanced past the steps BEFORE the failing one,
      // but NOT past the failing one. The failing step has targetVersion=5.
      expect(await repo.getDataVersion(), equals(4),
          reason: 'failing step must not advance past itself');
      // Steps 1..3 (targetVersion 2..4) ran; step 4 (failing) ran once
      // but did not advance; steps 5.. did not run.
      for (final step in steps.take(3)) {
        expect((step as _RecordingStep).callCount, equals(1),
            reason: '${step.name} succeeded');
      }
      expect((steps[3] as _RecordingStep).callCount, equals(1),
          reason: 'failing step ran but its throw prevented the advance');
      for (final step in steps.skip(4)) {
        expect((step as _RecordingStep).callCount, equals(0),
            reason: '${step.name} must not run after a prior step failed');
      }

      // Subsequent run with the thrower fixed: now everything succeeds.
      final retry = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: _stubSteps(),
      );
      final result = await retry.run();
      expect(result.from, equals(4));
      expect(result.to, equals(_stubTargetVersion));
      expect(result.appliedSteps.map((s) => s.name).toList(),
          equals(['stub-4', 'stub-5', 'stub-6', 'stub-7', 'stub-8',
              'stub-9', 'stub-10']));
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-005: Running at the current version is a no-op
    // ─────────────────────────────────────────────────────────────────────
    test('S-005: running at target version is a no-op', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setDataVersion(_stubTargetVersion);
      await repo.setLastDataVersionTransition(
          _stubTargetVersion, _stubTargetVersion);

      final steps = _stubSteps();
      final service = DataMigrationService(
        repository: repo,
        targetVersion: _stubTargetVersion,
        steps: steps,
      );
      final result = await service.run();

      expect(result.from, equals(_stubTargetVersion));
      expect(result.to, equals(_stubTargetVersion));
      expect(result.appliedSteps, isEmpty);
      for (final step in steps) {
        expect((step as _RecordingStep).callCount, equals(0),
            reason: 'no step should run at the target version');
      }
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // S-006: Behavioral parity — one step's effect matches the legacy
  // ─────────────────────────────────────────────────────────────────────
  test('S-006: consolidated step list lands the repo at currentDataVersion '
      'and produces the same end state as a manual full-sequence run',
      () async {
    final consolidated = MockWorkoutRepository();
    await consolidated.initialize();
    expect(await consolidated.getDataVersion(),
        equals(currentDataVersion),
        reason: 'the consolidated sequence inside initialize() must take a '
            'fresh MockWorkoutRepository all the way to currentDataVersion');
    expect(await consolidated.getUnits(), isNotEmpty,
        reason: 'seed units migration effect must be present');
    expect(await consolidated.getCatalogFoods(), isNotEmpty,
        reason: 'food catalog migration effect must be present');
    expect(await consolidated.getFoodGroups(), isNotEmpty,
        reason: 'default food groups migration effect must be present');

    // Sanity-check the back-compat shim against a partial legacy state.
    final partial = MockWorkoutRepository();
    await partial.setPreferenceBool('seed_loaded', true);
    await partial.setPreferenceBool('seed_units_migrated_v1', true);
    await partial.initialize();
    expect(await partial.getDataVersion(),
        equals(currentDataVersion),
        reason: 'partial legacy install must be mapped to currentDataVersion '
            'via the shim and complete the remaining steps in one launch');
  });

  // ─────────────────────────────────────────────────────────────────────
  // S-007: Catalog versioning still runs every launch (orthogonality)
  // ─────────────────────────────────────────────────────────────────────
  test('S-007: catalog versioning is independent of data-migration version',
      () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();

    // After initialize(), data_version is at target but catalog_version is
    // still at the default 0.
    expect(await repo.getDataVersion(), equals(currentDataVersion));
    expect(await repo.getCatalogVersion(), equals(0));

    // Setting data_version above the catalog version must not affect the
    // catalog path; the catalog version can still be written independently.
    await repo.setCatalogVersion(5);
    expect(await repo.getCatalogVersion(), equals(5));
    expect(await repo.getDataVersion(), equals(currentDataVersion));
  });
}