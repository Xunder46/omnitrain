import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/catalog_source.dart';
import 'package:omnitrain/core/models/demo_routine_spec.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';
import 'package:omnitrain/mock/seed_data.dart';
import 'package:omnitrain/state/routine/routine_state.dart';

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

CatalogSource _bundledSource() {
  return _RoutinesFakeCatalogSource(
    version: bundledCatalogVersion,
    exercises: SeedData.sampleExercises,
    exerciseCapabilities: SeedData.exerciseCapabilityRelationships,
    exerciseMuscleGroups: SeedData.exerciseMuscleGroupRelationships,
    foodCatalog: FoodCatalogSeed.sampleCatalogFoods,
    routineTemplates: SeedData.sampleDemoRoutineBundles,
  );
}

void main() {
  group('RoutineState demo-tombstone wiring', () {
    test(
      'DS-001: deleting a built-in demo via RoutineState sets the tombstone',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final routineState = RoutineState(repo);
        await routineState.loadRoutines();
        final demo = routineState.routines.firstWhere((r) => r.isBuiltInDemo);
        await routineState.deleteRoutine(demo.id);

        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.routineTemplate,
            demo.id,
          ),
          isTrue,
          reason:
              'the state must tombstone a user-deleted demo so the refresh '
              'does not resurrect it',
        );
      },
    );

    test(
      'DS-002: deleting a user-created routine does NOT set the tombstone',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);

        final now = DateTime.now().millisecondsSinceEpoch;
        const userTemplateId = 'template-user-squat-day';
        await repo.createTemplate(
          WorkoutTemplate(
            id: userTemplateId,
            name: 'My Squat Day',
            isBuiltInDemo: false,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );

        final routineState = RoutineState(repo);
        await routineState.loadRoutines();
        await routineState.deleteRoutine(userTemplateId);

        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.routineTemplate,
            userTemplateId,
          ),
          isFalse,
          reason:
              'user-created routines must never be tombstoned by the state',
        );
      },
    );

    test(
      'DS-003: editing (rename) a demo via the editor sets the tombstone so '
      'a subsequent refresh does not overwrite the user-chosen name',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await repo.setCatalogVersion(bundledCatalogVersion - 1);
        await CatalogRefreshService(repo, _bundledSource()).refresh();

        final routineState = RoutineState(repo);
        await routineState.loadRoutines();
        final demo = routineState.routines.firstWhere((r) => r.isBuiltInDemo);
        await routineState.loadRoutineForEditing(demo.id);
        await routineState.updateRoutineName('My Renamed Demo');

        // The name change triggers an autosave. Force it to flush.
        await Future<void>.delayed(const Duration(milliseconds: 800));

        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.routineTemplate,
            demo.id,
          ),
          isTrue,
          reason:
              'editing a demo via the editor must mark the demo as touched so '
              'a refresh does not overwrite the user-chosen name',
        );

        // Subsequent refresh preserves the name.
        await CatalogRefreshService(repo, _bundledSource()).refresh();
        final after = await repo.getTemplateById(demo.id);
        expect(after, isNotNull);
        expect(after!.name, equals('My Renamed Demo'));
      },
    );
  });
}
