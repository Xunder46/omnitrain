import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/shipped_food_groups.dart';

/// ONE-OFF (plan 137) — retire after launch.
///
/// Restores the shipped food categories after the pre-137 bug allowed
/// archiving them, leaving library copies of shipped catalog foods
/// stranded under "Uncategorized":
///
/// Rule 1 — every food group with `isArchived == true` whose id is a
/// shipped category id (`shippedFoodGroupIds`) is rewritten un-archived;
/// name, color and `createdAtMs` are unchanged and `updatedAtMs` becomes
/// now. Archived custom groups stay archived.
///
/// Rule 2 — for every active library food (`getFoods()`, `isCatalog ==
/// false`) with `groupId == null` and a non-null `catalogId`, the catalog
/// row is re-read; when that row's `groupId` is a shipped category id, the
/// copy goes back under that category via `reassignFoodsToGroup` (one call
/// per target group). Copies that already have any category, library
/// foods with no `catalogId`, and copies whose catalog row is a
/// user-created food (its own category was cleared by the archive and
/// cannot be known) are untouched.
///
/// Both writes are awaited, with no try/catch: a throw propagates so
/// `DataMigrationService` does not advance `data_version` and the next
/// launch re-runs the step. After one run no group matches rule 1 and no
/// copy matches rule 2, so a second run writes nothing — idempotent and
/// resumable. Fresh installs have nothing archived and no uncategorized
/// copies, so the run is a no-op.
///
/// Runs as data-migration step 19 (`restoreShippedFoodGroups`).
///
/// Retirement procedure: replace the step's `run` body with a no-op keeping
/// its version and name, delete this service and its test file, and update
/// `docs/db_integration.md` and `docs/constants_reference.md`; never
/// renumber or remove a version (a device below it would stop short of
/// `currentDataVersion`).
class ShippedFoodGroupsRepair {
  ShippedFoodGroupsRepair(this._repository);

  final WorkoutRepository _repository;

  Future<void> run() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Rule 1: a shipped category that was archived comes back.
    for (final group in await _repository.getFoodGroups(includeArchived: true)) {
      if (!group.isArchived || !isShippedFoodGroupId(group.id)) continue;
      await _repository.updateFoodGroup(
        FoodGroup(
          id: group.id,
          name: group.name,
          color: group.color,
          isArchived: false,
          createdAtMs: group.createdAtMs,
          updatedAtMs: now,
        ),
      );
    }

    // Rule 2: a library copy of a food with a shipped category, sitting
    // under no category, goes back under that category.
    final targets = <String, List<String>>{};
    for (final food in await _repository.getFoods()) {
      if (food.isCatalog || food.groupId != null) continue;
      final catalogId = food.catalogId;
      if (catalogId == null) continue;
      final row = await _repository.getCatalogFoodById(catalogId);
      final target = row?.groupId;
      if (target == null || !isShippedFoodGroupId(target)) continue;
      targets.putIfAbsent(target, () => []).add(food.id);
    }
    for (final entry in targets.entries) {
      await _repository.reassignFoodsToGroup(entry.value, entry.key);
    }
  }
}
