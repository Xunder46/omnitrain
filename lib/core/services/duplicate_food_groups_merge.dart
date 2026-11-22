import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/shipped_food_groups.dart';

/// ONE-OFF (plan 303) — retire after launch.
///
/// Merges food categories that share a name. Until plan 303 nothing stopped
/// two active categories carrying the same name (the Categories tab accepted
/// any rename, the plan 137 repair un-archived a shipped category beside a
/// custom one, and default seeding skipped a shipped category whose name was
/// already taken), so the library listed two "Dairy" headings and a default
/// food could not be moved between them.
///
/// For every group of active categories whose trimmed, case-insensitive names
/// match:
///
/// - the keeper is the shipped category (`shippedFoodGroupIds`) when the group
///   holds one, otherwise the oldest by `createdAtMs` (then id);
/// - every library food and every catalog food (bundled rows included, which
///   is how a default food such as Cottage cheese comes back) filed under a
///   duplicate is re-filed under the keeper;
/// - the duplicate is then archived, never deleted. A shipped category is
///   never archived, so two shipped categories that share a name (one was
///   renamed) are left alone.
///
/// A shipped category that is missing from storage while an active category
/// of the same name exists (the old seeding skip) is re-created from
/// [shippedGroups] first and then wins the merge. A shipped category found
/// archived beside an active same-name category is un-archived.
///
/// Foods keep their rows, ids and logged entries; only `groupId` changes.
/// Every write is awaited with no try/catch: a throw propagates so
/// `DataMigrationService` does not advance `data_version` and the next launch
/// re-runs the step. Re-filing happens before archiving, so a re-run after a
/// partial pass finishes the job; after a full pass nothing matches and a
/// second run writes nothing.
///
/// Runs as data-migration step 21 (`mergeDuplicateFoodGroups`).
///
/// Retirement procedure: replace the step's `run` body with a no-op keeping its
/// version and name, delete this service and its test file, and update
/// `docs/db_integration.md`; never renumber or remove a version.
class DuplicateFoodGroupsMerge {
  DuplicateFoodGroupsMerge(
    this._repository, {
    required List<FoodGroup> shippedGroups,
  }) : _shippedGroups = shippedGroups;

  final WorkoutRepository _repository;

  /// The shipped categories as the app seeds them (`SeedData.defaultFoodGroups`
  /// on the real stores): the source of a missing shipped row.
  final List<FoodGroup> _shippedGroups;

  /// The name two categories are compared by.
  static String nameKey(String name) => name.trim().toLowerCase();

  Future<void> run() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Step 1: bring a missing or archived shipped category back when an active
    // category of the same name stands in its place.
    var groups = await _repository.getFoodGroups(includeArchived: true);
    final activeNames = {
      for (final g in groups)
        if (!g.isArchived) nameKey(g.name),
    };
    for (final shipped in _shippedGroups) {
      if (!activeNames.contains(nameKey(shipped.name))) continue;
      final stored = groups.where((g) => g.id == shipped.id).toList();
      if (stored.isEmpty) {
        await _repository.createFoodGroup(
          FoodGroup(
            id: shipped.id,
            name: shipped.name,
            color: shipped.color,
            isArchived: false,
            createdAtMs: shipped.createdAtMs,
            updatedAtMs: now,
          ),
        );
      } else if (stored.single.isArchived) {
        final g = stored.single;
        await _repository.updateFoodGroup(
          FoodGroup(
            id: g.id,
            name: g.name,
            color: g.color,
            isArchived: false,
            createdAtMs: g.createdAtMs,
            updatedAtMs: now,
          ),
        );
      }
    }

    // Step 2: merge each set of active same-name categories.
    groups = await _repository.getFoodGroups();
    final byName = <String, List<FoodGroup>>{};
    for (final g in groups) {
      byName.putIfAbsent(nameKey(g.name), () => []).add(g);
    }

    for (final set in byName.values) {
      if (set.length < 2) continue;
      final keeper = _keeperOf(set);
      final losers = [
        for (final g in set)
          if (g.id != keeper.id && !isShippedFoodGroupId(g.id)) g,
      ];
      if (losers.isEmpty) continue;
      final loserIds = {for (final g in losers) g.id};

      final libraryIds = [
        for (final f in await _repository.getFoods(includeArchived: true))
          if (f.groupId != null && loserIds.contains(f.groupId)) f.id,
      ];
      await _repository.reassignFoodsToGroup(libraryIds, keeper.id);

      final catalogIds = [
        for (final f in await _repository.getCatalogFoods(
          includeArchived: true,
        ))
          if (f.groupId != null && loserIds.contains(f.groupId)) f.id,
      ];
      await _repository.reassignCatalogFoodsToGroup(catalogIds, keeper.id);

      for (final loser in losers) {
        await _repository.archiveFoodGroup(loser.id);
      }
    }
  }

  /// The shipped category when the set holds one (the oldest if several),
  /// otherwise the oldest category; ties break on id so both stores agree.
  static FoodGroup _keeperOf(List<FoodGroup> set) {
    int byAge(FoodGroup a, FoodGroup b) {
      final byCreated = a.createdAtMs.compareTo(b.createdAtMs);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    }

    final shipped = [
      for (final g in set)
        if (isShippedFoodGroupId(g.id)) g,
    ]..sort(byAge);
    if (shipped.isNotEmpty) return shipped.first;
    return ([...set]..sort(byAge)).first;
  }
}
