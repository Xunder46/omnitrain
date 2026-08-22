import '../../core/models/demo_routine_spec.dart';
import '../../data/models/models.dart';
import '../../mock/food_catalog_seed.dart';
import '../../mock/seed_data.dart';
import '../constants/catalog_version.dart';
import 'catalog_source.dart';

/// The default [CatalogSource] used by [CatalogRefreshService]: reads the
/// bundled catalog that ships with the app (the seed data + the food
/// catalog seed + the seeded demo routines).
///
/// All getters are pure reads of compile-time [SeedData] /
/// [FoodCatalogSeed] constants — they have no side effects and are safe
/// to call repeatedly from the refresh loop.
class BundledCatalogSource implements CatalogSource {
  const BundledCatalogSource();

  @override
  int get version => bundledCatalogVersion;

  @override
  List<Exercise> get exercises => SeedData.sampleExercises;

  @override
  Map<String, List<String>> get exerciseCapabilities =>
      SeedData.exerciseCapabilityRelationships;

  @override
  List<MuscleGroup> get muscleGroups => SeedData.sampleMuscleGroups;

  @override
  Map<String, List<String>> get exerciseMuscleGroups =>
      SeedData.exerciseMuscleGroupRelationships;

  @override
  List<Food> get foodCatalog => FoodCatalogSeed.sampleCatalogFoods;

  @override
  List<DemoRoutineBundle> get routineTemplates =>
      SeedData.sampleDemoRoutineBundles;
}