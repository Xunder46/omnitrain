import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/services/data_migration_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

import 'helpers/repository_harness.dart';

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

/// The version a store holds before step 15 exists — the shape S-156
/// describes.
const int _preRepairDataVersion = 14;

/// The version implied by the last legacy one-shot marker
/// (`food_category_groupid_migrated_v1`). It is history, not
/// [currentDataVersion]: steps appended after it still run for a legacy
/// install, which is why the shim maps a fully-migrated legacy device to
/// this value and the service then runs step 15.
const int _lastLegacyMarkerVersion = 14;

const int _s156StartMs = 1_700_000_000_000;

TrainingSession _s156Session({required String id, required int? endedAtMs}) {
  return TrainingSession(
    id: id,
    ownerUserId: 'user-s156',
    startedAtMs: _s156StartMs,
    endedAtMs: endedAtMs,
    title: 'Session $id',
    isRolling: false,
    createdAtMs: _s156StartMs - 60_000,
    updatedAtMs: _s156StartMs - 60_000,
  );
}

/// Three stored rows standing for a store written before step 15: `a` is
/// inverted, `b` is running, `c` is already valid.
List<TrainingSession> _s156Fixture() => [
  _s156Session(id: 'a', endedAtMs: _s156StartMs - 1_000_000),
  _s156Session(id: 'b', endedAtMs: null),
  _s156Session(id: 'c', endedAtMs: _s156StartMs + 60_000),
];

/// Asserts the S-156 expectations for one stored row against [session]:
/// `a` is repaired (end clamped up to the untouched start), `b` is a
/// running row, `c` keeps its original window.
void _expectS156Window(String id, TrainingSession? session) {
  expect(session, isNotNull, reason: '$id must still be stored');
  expect(session!.startedAtMs, equals(_s156StartMs));
  switch (id) {
    case 'a':
      expect(
        session.endedAtMs,
        equals(_s156StartMs),
        reason: 'the end is clamped up to the start',
      );
    case 'b':
      expect(session.endedAtMs, isNull, reason: 'a running row is untouched');
    case 'c':
      expect(session.endedAtMs, equals(_s156StartMs + 60_000));
  }
}

void main() {
  group('DataMigrationService', () {
    // ─────────────────────────────────────────────────────────────────────
    // S-001: Fresh install runs all steps in order, lands at current version
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-001: fresh install runs all steps in order and lands at target',
      () async {
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
          expect(
            (step as _RecordingStep).callCount,
            equals(1),
            reason: '${step.name} should have run exactly once',
          );
        }
        expect(await repo.getDataVersion(), equals(_stubTargetVersion));
        final transition = await repo.getLastDataVersionTransition();
        expect(transition, isNotNull);
        expect(transition!.from, equals(1));
        expect(transition.to, equals(_stubTargetVersion));
      },
    );

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
      expect(
        applied.map((s) => s.targetVersion).toList(),
        equals([2, 5, 8, 11]),
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-002: Legacy install with all markers → current version, no-op
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-002: legacy install with all markers maps to target and runs no steps',
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

        expect(
          await repo.getLegacyAppliedDataVersion(),
          equals(_lastLegacyMarkerVersion),
          reason:
              'shim should detect all legacy markers and map to the '
              'version the last legacy marker implied',
        );

        final steps = _stubSteps();
        final service = DataMigrationService(
          repository: repo,
          targetVersion: _stubTargetVersion,
          steps: steps,
        );
        final result = await service.run();

        expect(result.from, equals(_lastLegacyMarkerVersion));
        expect(result.to, equals(_lastLegacyMarkerVersion));
        expect(result.appliedSteps, isEmpty);
        for (final step in steps) {
          expect(
            (step as _RecordingStep).callCount,
            equals(0),
            reason:
                '${step.name} must not run on a fully migrated legacy '
                'install',
          );
        }
        expect(await repo.getDataVersion(), equals(_lastLegacyMarkerVersion),
            reason: 'the shim writes the mapped version, not the target');
      },
    );

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
      expect(
        result.appliedSteps.map((s) => s.name).toList(),
        equals(['stub-6', 'stub-7', 'stub-8', 'stub-9', 'stub-10']),
      );
      for (final step in steps.take(5)) {
        expect(
          (step as _RecordingStep).callCount,
          equals(0),
          reason: '${step.name} already applied by legacy code, must skip',
        );
      }
      for (final step in steps.skip(5)) {
        expect(
          (step as _RecordingStep).callCount,
          equals(1),
          reason: '${step.name} is pending, must run',
        );
      }
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
    });

    // ─────────────────────────────────────────────────────────────────────
    // S-004: A failing step leaves the version unchanged
    // ─────────────────────────────────────────────────────────────────────
    test(
      'S-004: a failing step leaves the version unchanged and is retried',
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
        expect(
          caught,
          isA<StateError>(),
          reason: 'simulated failure must propagate to the caller',
        );

        // Version must have advanced past the steps BEFORE the failing one,
        // but NOT past the failing one. The failing step has targetVersion=5.
        expect(
          await repo.getDataVersion(),
          equals(4),
          reason: 'failing step must not advance past itself',
        );
        // Steps 1..3 (targetVersion 2..4) ran; step 4 (failing) ran once
        // but did not advance; steps 5.. did not run.
        for (final step in steps.take(3)) {
          expect(
            (step as _RecordingStep).callCount,
            equals(1),
            reason: '${step.name} succeeded',
          );
        }
        expect(
          (steps[3] as _RecordingStep).callCount,
          equals(1),
          reason: 'failing step ran but its throw prevented the advance',
        );
        for (final step in steps.skip(4)) {
          expect(
            (step as _RecordingStep).callCount,
            equals(0),
            reason: '${step.name} must not run after a prior step failed',
          );
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
        expect(
          result.appliedSteps.map((s) => s.name).toList(),
          equals([
            'stub-4',
            'stub-5',
            'stub-6',
            'stub-7',
            'stub-8',
            'stub-9',
            'stub-10',
          ]),
        );
        expect(await repo.getDataVersion(), equals(_stubTargetVersion));
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // S-005: Running at the current version is a no-op
    // ─────────────────────────────────────────────────────────────────────
    test('S-005: running at target version is a no-op', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.setDataVersion(_stubTargetVersion);
      await repo.setLastDataVersionTransition(
        _stubTargetVersion,
        _stubTargetVersion,
      );

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
        expect(
          (step as _RecordingStep).callCount,
          equals(0),
          reason: 'no step should run at the target version',
        );
      }
      expect(await repo.getDataVersion(), equals(_stubTargetVersion));
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // S-006: Behavioral parity — one step's effect matches the legacy
  // ─────────────────────────────────────────────────────────────────────
  test(
    'S-006: consolidated step list lands the repo at currentDataVersion '
    'and produces the same end state as a manual full-sequence run',
    () async {
      final consolidated = MockWorkoutRepository();
      await consolidated.initialize();
      expect(
        await consolidated.getDataVersion(),
        equals(currentDataVersion),
        reason:
            'the consolidated sequence inside initialize() must take a '
            'fresh MockWorkoutRepository all the way to currentDataVersion',
      );
      expect(
        await consolidated.getUnits(),
        isNotEmpty,
        reason: 'seed units migration effect must be present',
      );
      expect(
        await consolidated.getCatalogFoods(),
        isNotEmpty,
        reason: 'food catalog migration effect must be present',
      );
      expect(
        await consolidated.getFoodGroups(),
        isNotEmpty,
        reason: 'default food groups migration effect must be present',
      );

      // Sanity-check the back-compat shim against a partial legacy state.
      final partial = MockWorkoutRepository();
      await partial.setPreferenceBool('seed_loaded', true);
      await partial.setPreferenceBool('seed_units_migrated_v1', true);
      await partial.initialize();
      expect(
        await partial.getDataVersion(),
        equals(currentDataVersion),
        reason:
            'partial legacy install must be mapped to currentDataVersion '
            'via the shim and complete the remaining steps in one launch',
      );
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // S-007: Catalog versioning still runs every launch (orthogonality)
  // ─────────────────────────────────────────────────────────────────────
  test(
    'S-007: catalog versioning is independent of data-migration version',
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
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // S-156: a stored inverted session window is repaired once, in both stores
  // ─────────────────────────────────────────────────────────────────────
  test('S-156: step 15 is appended to both migration sequences', () async {
    expect(currentDataVersion, equals(15));

    final mockSteps = MockWorkoutRepository().dataMigrationStepsForTest();
    final hiveSteps = HiveWorkoutRepository().dataMigrationStepsForTest();

    expect(mockSteps.last.targetVersion, equals(15));
    expect(mockSteps.last.name, equals('clampInvertedSessionWindows'));
    expect(hiveSteps.last.targetVersion, equals(15));
    expect(hiveSteps.last.name, equals('clampInvertedSessionWindows'));
    expect(
      mockSteps.map((step) => '${step.targetVersion}:${step.name}').toList(),
      equals(
        hiveSteps.map((step) => '${step.targetVersion}:${step.name}').toList(),
      ),
      reason: 'both stores must walk the same version sequence',
    );
  });

  test(
    'S-156: the Mock repairs an inverted row once and a re-run writes nothing',
    () async {
      final mock = MockWorkoutRepository();
      for (final session in _s156Fixture()) {
        await mock.createSession(session);
      }
      // The store is at the version that predates step 15, so initialize()
      // reaches the repair through step 15 alone.
      await mock.setDataVersion(_preRepairDataVersion);

      await mock.initialize();
      expect(await mock.getDataVersion(), equals(currentDataVersion));

      for (final session in _s156Fixture()) {
        _expectS156Window(session.id, await mock.getSession(session.id));
      }
      expect(
        (await mock.getSession('b'))!.toMap(),
        equals(_s156Fixture()[1].toMap()),
        reason: 'a running row is byte-identical after the step',
      );
      expect(
        (await mock.getSession('c'))!.toMap(),
        equals(_s156Fixture()[2].toMap()),
        reason: 'an already-valid row is byte-identical after the step',
      );

      final before = {
        for (final session in _s156Fixture())
          session.id: (await mock.getSession(session.id))!.toMap(),
      };
      await mock.setDataVersion(_preRepairDataVersion);
      final rerun = await DataMigrationService(
        repository: mock,
        targetVersion: currentDataVersion,
        steps: mock.dataMigrationStepsForTest(),
      ).run();

      expect(
        rerun.appliedSteps.map((step) => step.name).toList(),
        equals(['clampInvertedSessionWindows']),
      );
      expect(await mock.getDataVersion(), equals(currentDataVersion));
      for (final session in _s156Fixture()) {
        expect((await mock.getSession(session.id))!.toMap(), equals(before[session.id]));
      }
    },
  );

  group('S-156: a Hive store seeded before step 15', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('s156_mig_');
      PathProviderChannel.install(tempDir);
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('S-156: Hive repairs the store and matches the Mock', () async {
      final sessionsBox = await Hive.openBox<Map>('sessions');
      for (final session in _s156Fixture()) {
        await sessionsBox.put(session.id, session.toMap());
      }
      final metaBox = await Hive.openBox('meta');
      await metaBox.put('data_version', _preRepairDataVersion);

      final writes = <BoxEvent>[];
      final subscription = sessionsBox.watch().listen(writes.add);

      final repo = HiveWorkoutRepository();
      await repo.initialize();
      await pumpEventQueue();

      expect(await repo.getDataVersion(), equals(currentDataVersion));
      for (final session in _s156Fixture()) {
        _expectS156Window(session.id, await repo.getSession(session.id));
      }
      expect(
        writes.where((event) => event.key == 'a').length,
        equals(1),
        reason: 'the repair writes the row once',
      );
      expect(
        writes.where((event) => event.key == 'b' || event.key == 'c'),
        isEmpty,
        reason: 'running and already-valid rows are never rewritten',
      );

      final before = {
        for (final session in _s156Fixture())
          session.id: (await repo.getSession(session.id))!.toMap(),
      };
      writes.clear();
      await repo.setDataVersion(_preRepairDataVersion);
      final rerun = await DataMigrationService(
        repository: repo,
        targetVersion: currentDataVersion,
        steps: repo.dataMigrationStepsForTest(),
      ).run();
      await pumpEventQueue();

      expect(
        rerun.appliedSteps.map((step) => step.name).toList(),
        equals(['clampInvertedSessionWindows']),
      );
      expect(await repo.getDataVersion(), equals(currentDataVersion));
      expect(writes, isEmpty, reason: 'a retry of the step writes nothing');
      for (final session in _s156Fixture()) {
        expect((await repo.getSession(session.id))!.toMap(), equals(before[session.id]));
      }

      await subscription.cancel();

      // Parity: the Mock, seeded with the same three rows, returns equal
      // values for every one of them.
      final mock = MockWorkoutRepository();
      for (final session in _s156Fixture()) {
        await mock.createSession(session);
      }
      await mock.initialize();
      for (final session in _s156Fixture()) {
        final hiveSession = await repo.getSession(session.id);
        final mockSession = await mock.getSession(session.id);
        expect(
          hiveSession!.toMap(),
          equals(mockSession!.toMap()),
          reason: 'both stores must return equal values for ${session.id}',
        );
      }
    });
  });
}
