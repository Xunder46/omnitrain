import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/demo_routine_spec.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/catalog_source.dart';
import 'package:omnitrain/core/services/demo_routines_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';
import 'package:omnitrain/mock/seed_data.dart';

/// A [CatalogSource] carrying only what's needed to exercise the
/// routine-demos refresh path. Tests can swap the bundled list in and
/// out to model "old device", "fresh install", etc.
class _RoutinesFakeCatalogSource implements CatalogSource {
  _RoutinesFakeCatalogSource({
    required this.version,
    required this.exercises,
    required this.exerciseCapabilities,
    required this.exerciseMuscleGroups,
    required this.foodCatalog,
    required this.routineTemplates,
  });

  @override
  final int version;

  @override
  final List<Exercise> exercises;

  @override
  final Map<String, List<String>> exerciseCapabilities;

  @override
  List<MuscleGroup> get muscleGroups => SeedData.sampleMuscleGroups;

  @override
  final Map<String, List<String>> exerciseMuscleGroups;

  @override
  final List<Food> foodCatalog;

  @override
  final List<DemoRoutineBundle> routineTemplates;
}

CatalogSource _bundledSource({int? versionOverride}) {
  return _RoutinesFakeCatalogSource(
    version: versionOverride ?? bundledCatalogVersion,
    exercises: SeedData.sampleExercises,
    exerciseCapabilities: SeedData.exerciseCapabilityRelationships,
    exerciseMuscleGroups: SeedData.exerciseMuscleGroupRelationships,
    foodCatalog: FoodCatalogSeed.sampleCatalogFoods,
    routineTemplates: SeedData.sampleDemoRoutineBundles,
  );
}

void main() {
  group('Seeded Demo Routines — Catalog Refresh integration', () {
    test(
      'D-001: fresh install (stored version < bundled) lands demos on device',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        // Stored = 0 simulates a fresh install on first launch.
        await repo.setCatalogVersion(0);

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isTrue);
        expect(await repo.getCatalogVersion(), bundledCatalogVersion);

        final demos = (await repo.getTemplates())
            .where((t) => t.isBuiltInDemo)
            .toList();
        expect(
          demos.length,
          greaterThanOrEqualTo(6),
          reason: 'must ship ≥6 demo routines spanning modalities',
        );
        for (final demo in demos) {
          expect(demo.id, startsWith('demo-template-'));
        }
      },
    );

    test(
      'D-002: existing user routine is not touched by the refresh path',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final now = DateTime.now().millisecondsSinceEpoch;
        const userTemplateId = 'template-user-custom-squat';
        await repo.createTemplate(
          WorkoutTemplate(
            id: userTemplateId,
            name: 'My Squat Day',
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
        await repo.createTemplateSegment(
          TemplateSegment(
            id: 'tseg-user-1',
            templateId: userTemplateId,
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );

        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final after = await repo.getTemplateById(userTemplateId);
        expect(after, isNotNull);
        expect(after!.name, equals('My Squat Day'));
        expect(after.isBuiltInDemo, isFalse);
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.routineTemplate,
            userTemplateId,
          ),
          isFalse,
          reason: 'user-created routine must never be tombstoned by refresh',
        );
      },
    );

    test(
      'D-007: a below-template change reaches a device that already has the demo',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(0);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        // Stand in for a device carrying an older shape of the routine:
        // an effort that still has a rest interval the bundle has dropped.
        const templateId = 'demo-template-hit-full-body';
        final segments = await repo.getTemplateSegments(templateId);
        final efforts = await repo.getTemplateEfforts(segments.first.id);
        final stale = efforts.first;
        await repo.updateTemplateEffort(
          TemplateEffort(
            id: stale.id,
            templateSegmentId: stale.templateSegmentId,
            orderIndex: stale.orderIndex,
            effortKind: stale.effortKind,
            exerciseId: stale.exerciseId,
            restSeconds: 180,
            createdAtMs: stale.createdAtMs,
          ),
        );

        // The user has not edited the routine, so no tombstone exists and
        // the refresh owns the body.
        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.routineTemplate,
            templateId,
          ),
          isFalse,
        );

        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final refreshedSegments = await repo.getTemplateSegments(templateId);
        final refreshedEfforts = await repo.getTemplateEfforts(
          refreshedSegments.first.id,
        );
        expect(
          refreshedEfforts.every((e) => e.restSeconds == null),
          isTrue,
          reason:
              'a template-row-only patch cannot deliver this; the refresh '
              'must rewrite the body of an untouched demo',
        );
        expect(
          refreshedEfforts.length,
          equals(6),
          reason: 'Compound block must still hold its six efforts',
        );
      },
    );

    test(
      'D-008: a user-edited demo keeps its body across the refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(0);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        const templateId = 'demo-template-hit-full-body';
        final segments = await repo.getTemplateSegments(templateId);
        final firstSegmentId = segments.first.id;

        // The user edits the routine — the state layer tombstones it.
        await repo.markSeedEntryTouched(
          SeedEntryType.routineTemplate,
          templateId,
        );
        await repo.deleteTemplateSegment(firstSegmentId);

        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final after = await repo.getTemplateSegments(templateId);
        expect(
          after.any((s) => s.id == firstSegmentId),
          isFalse,
          reason:
              'the body rewrite must not resurrect a segment the user '
              'deleted from a demo they have taken ownership of',
        );
      },
    );

    test(
      'D-003: deleting a seeded demo does NOT resurrect it on the next refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        await CatalogRefreshService(repo, _bundledSource()).refresh();

        // Pick the first demo that shipped in this build.
        final demos = (await repo.getTemplates())
            .where((t) => t.isBuiltInDemo)
            .toList();
        expect(demos, isNotEmpty);
        final firstId = demos.first.id;

        // The refresh must have written it.
        expect(
          (await repo.getTemplateById(firstId)) != null,
          isTrue,
          reason: 'setup: refresh must have seeded the demo',
        );

        // User deletes it — repo + tombstone.
        await repo.deleteTemplate(firstId);
        await repo.markSeedEntryTouched(
          SeedEntryType.routineTemplate,
          firstId,
        );

        // Trigger another refresh (simulating a re-bundled catalog).
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        expect(
          await repo.getTemplateById(firstId),
          isNull,
          reason: 'a user-deleted demo must not be resurrected by refresh',
        );
      },
    );

    test(
      'D-004: user-edited demo keeps the user-chosen name across refresh',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final targetId = (await repo.getTemplates())
            .firstWhere((t) => t.isBuiltInDemo)
            .id;
        final original = await repo.getTemplateById(targetId);
        expect(original, isNotNull);
        expect(original!.isBuiltInDemo, isTrue);

        await repo.updateTemplate(
          original.copyWith(name: 'My Renamed Demo'),
        );
        await repo.markSeedEntryTouched(
          SeedEntryType.routineTemplate,
          targetId,
        );

        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final after = await repo.getTemplateById(targetId);
        expect(after, isNotNull);
        expect(
          after!.name,
          equals('My Renamed Demo'),
          reason: 'user edit must be preserved across refresh',
        );
      },
    );

    test(
      'D-005: refresh is a no-op when stored version equals bundled version',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion);

        final service = CatalogRefreshService(repo, _bundledSource());
        final didRefresh = await service.refresh();

        expect(didRefresh, isFalse);
        expect(
          (await repo.getTemplates()).where((t) => t.isBuiltInDemo).length,
          equals(0),
          reason:
              'a never-seeded device whose stored version already equals the '
              'bundled one must NOT populate demos on this path (demos ship '
              'on the version-bump refresh, not on every launch)',
        );
      },
    );

    test(
      'D-006: idempotent refresh — running twice produces no duplicate demos',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final service = CatalogRefreshService(repo, _bundledSource());
        await service.refresh();
        final firstCount = (await repo.getTemplates())
            .where((t) => t.isBuiltInDemo)
            .length;

        await service.refresh();
        final secondCount = (await repo.getTemplates())
            .where((t) => t.isBuiltInDemo)
            .length;

        expect(secondCount, equals(firstCount));
      },
    );
  });

  group('Seeded Demo Routines — Validator', () {
    final exerciseIds = SeedData.sampleExercises.map((e) => e.id).toSet();
    final capabilities = SeedData.exerciseCapabilityRelationships;

    test('V-001: every demo exerciseId resolves to the bundled catalog', () {
      final result = DemoRoutinesValidator.validate(
        SeedData.sampleDemoRoutineBundles,
        exerciseIds,
        exerciseCapabilities: capabilities,
      );
      expect(
        result.isValid,
        isTrue,
        reason:
            'every demo must reference a real exercise in the bundled catalog; '
            'failures: ${result.failures.join(", ")}',
      );
    });

    test('V-002: every demo effort carries targets appropriate to its kind', () {
      final result = DemoRoutinesValidator.validate(
        SeedData.sampleDemoRoutineBundles,
        exerciseIds,
        exerciseCapabilities: capabilities,
      );
      expect(
        result.isValid,
        isTrue,
        reason:
            'every demo effort must declare its kind-appropriate targets; '
            'failures: ${result.failures.join(", ")}',
      );
    });

    test('V-005: a hold-capable drill may declare no targets at all', () {
      final hold = _syntheticOneExerciseDemo(
        exerciseId: 'exercise-side-plank',
        effortKind: 'drill',
        metrics: const [],
      );

      // exercise-side-plank carries the `hold` capability, so a count-up
      // hold with nothing to preset is valid.
      expect(
        capabilities['exercise-side-plank'],
        contains(ExerciseCapability.hold),
        reason: 'fixture assumption: side plank must be hold-capable',
      );

      final result = DemoRoutinesValidator.validate(
        [hold],
        exerciseIds,
        exerciseCapabilities: capabilities,
      );
      expect(
        result.isValid,
        isTrue,
        reason: 'failures: ${result.failures.join(", ")}',
      );
    });

    test('V-006: a drill that is not a hold still requires a duration', () {
      final drill = _syntheticOneExerciseDemo(
        exerciseId: 'exercise-bjj-drilling',
        effortKind: 'drill',
        metrics: const [],
      );

      expect(
        capabilities['exercise-bjj-drilling'] ?? const <String>[],
        isNot(contains(ExerciseCapability.hold)),
        reason: 'fixture assumption: bjj drilling must not be hold-capable',
      );

      final result = DemoRoutinesValidator.validate(
        [drill],
        exerciseIds,
        exerciseCapabilities: capabilities,
      );
      expect(result.isValid, isFalse);
    });

    test('V-007: without capabilities, every drill needs a duration', () {
      final hold = _syntheticOneExerciseDemo(
        exerciseId: 'exercise-side-plank',
        effortKind: 'drill',
        metrics: const [],
      );

      // The exemption is opt-in: a caller that cannot supply capabilities
      // keeps the stricter rule rather than silently relaxing it.
      final result = DemoRoutinesValidator.validate([hold], exerciseIds);
      expect(result.isValid, isFalse);
    });

    test('V-003: validator flags a dangling exercise reference', () {
      final orphan = _syntheticOneExerciseDemo(
        exerciseId: 'exercise-does-not-exist',
      );
      final result = DemoRoutinesValidator.validate(
        [orphan],
        exerciseIds,
      );
      expect(result.isValid, isFalse);
      expect(result.failures, isNotEmpty);
    });

    test('V-004: validator flags a missing reps target on a set effort', () {
      final bad = _syntheticOneExerciseDemo(
        exerciseId: 'exercise-push-up',
        effortKind: 'set',
        metrics: const [
          DemoRoutineTargetSpec(
            metricId: MetricIds.weight,
            setIndex: 0,
            targetMin: 0.0,
          ),
        ],
      );
      final result = DemoRoutinesValidator.validate(
        [bad],
        exerciseIds,
      );
      expect(result.isValid, isFalse);
    });
  });

  group('Seeded Demo Routines — Bundle shape', () {
    test('demo IDs are namespaced under the demo prefix', () {
      for (final demo in SeedData.sampleDemoRoutineBundles) {
        expect(demo.template.id, startsWith('demo-template-'));
      }
    });

    test('no demo id collides with user-creatable ids', () {
      // User routines are formatted as 'template-{ms}' — confirm no demo
      // template starts with 'template-' (which would be ambiguous).
      for (final demo in SeedData.sampleDemoRoutineBundles) {
        expect(
          demo.template.id.startsWith('template-'),
          isFalse,
          reason:
              'demo template id ${demo.template.id} must not use the user prefix',
        );
      }
    });

    test('user template ids are absent from the demo bundle', () {
      const userTemplateId = 'template-1234567890';
      expect(
        SeedData.sampleDemoRoutineBundles.any(
          (d) => d.template.id == userTemplateId,
        ),
        isFalse,
      );
    });
  });
}

DemoRoutineBundle _syntheticOneExerciseDemo({
  required String exerciseId,
  String effortKind = 'set',
  List<DemoRoutineTargetSpec> metrics = const [
    DemoRoutineTargetSpec(
      metricId: MetricIds.reps,
      setIndex: 0,
      targetInt: 10,
    ),
    DemoRoutineTargetSpec(
      metricId: MetricIds.weight,
      setIndex: 0,
      targetMin: 0.0,
    ),
  ],
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return DemoRoutineBundle(
    template: WorkoutTemplate(
      id: 'demo-template-synthetic-$exerciseId',
      name: 'Synthetic',
      isBuiltInDemo: true,
      focusModality: 'resistance_lifting',
      createdAtMs: now,
      updatedAtMs: now,
    ),
    segments: [
      DemoRoutineSegmentSpec(
        segment: TemplateSegment(
          id: 'demo-tseg-synthetic-$exerciseId',
          templateId: 'demo-template-synthetic-$exerciseId',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: now,
          updatedAtMs: now,
        ),
        efforts: [
          DemoRoutineEffortSpec(
            effort: TemplateEffort(
              id: 'demo-teff-synthetic-$exerciseId',
              templateSegmentId: 'demo-tseg-synthetic-$exerciseId',
              orderIndex: 0,
              effortKind: effortKind,
              exerciseId: exerciseId,
              createdAtMs: now,
            ),
            targets: metrics,
          ),
        ],
      ),
    ],
  );
}
