import '../../core/models/demo_routine_spec.dart';
import '../../data/models/models.dart';

/// A bundled snapshot of the app-authored catalog.
///
/// [CatalogRefreshService] consumes a [CatalogSource] instead of reading
/// [SeedData] directly so the data backing the refresh can later be swapped
/// (e.g., a remote / server-provided catalog) without touching the
/// version-check logic.
///
/// Implementations MUST be cheap to read repeatedly within a single refresh
/// pass — [CatalogRefreshService] iterates the source's collections multiple
/// times per entity type.
abstract class CatalogSource {
  /// The version this catalog represents. When the device's stored version
  /// is less than [version], the refresh runs.
  int get version;

  /// Bundled exercises (`Exercise.id` is the storage key).
  List<Exercise> get exercises;

  /// Bundled exercise capabilities: `exerciseId → list of capability keys`.
  Map<String, List<String>> get exerciseCapabilities;

  /// Bundled muscle groups (`MuscleGroup.id` is the storage key).
  ///
  /// Refreshed before [exerciseMuscleGroups] so a relationship never points
  /// at a group the device does not yet have.
  List<MuscleGroup> get muscleGroups;

  /// Bundled exercise / muscle-group relationships: `exerciseId → muscleGroupIds`.
  Map<String, List<String>> get exerciseMuscleGroups;

  /// Bundled food catalog rows (each row carries `isCatalog = true`).
  List<Food> get foodCatalog;

  /// Bundled demo workout templates (each carries `isBuiltInDemo = true`).
  ///
  /// Arriving on a device via the same versioned refresh pipeline used for
  /// exercises and food; demo deletion / edit tombstones live under
  /// [SeedEntryType.routineTemplate].
  List<DemoRoutineBundle> get routineTemplates;
}
