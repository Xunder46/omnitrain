import 'package:flutter/foundation.dart';
import '../core/constants/catalog_version.dart';
import '../core/models/food_draft.dart';
import '../core/services/image_storage_service.dart';
import '../data/models/models.dart';
import '../data/repositories/workout_repository.dart';

/// State manager for the food library (groups and foods).
///
/// Provides caching, loading, CRUD operations, and search functionality
/// for user-created food groups and food items. Caches are populated on demand
/// and refreshed via load* methods.
///
/// All operations route through the injected WorkoutRepository interface,
/// allowing environment-agnostic persistence (Hive web, SQLite native).

/// Thrown by [FoodLibraryState.deleteFoodGroupReassigningFoods] when
/// the deletion would strand at least one bundled catalog food —
/// i.e. a food whose id is in [FoodLibraryState._bundledCatalogFoodIds]
/// still has `groupId` equal to the category being deleted.
///
/// The constraint (see
/// `docs/plans/2026-08-08-food-edit-orphan-category-plan.md`):
/// we cannot rewrite a bundled catalog food's `groupId` to "fix" the
/// stranded-ness, because the catalog refresh restores the bundled
/// food's category on every launch — so any such rewrite would
/// silently revert and the user would watch their action undo
/// itself. The honest answer is to refuse the deletion and tell the
/// user which category is blocking it; the UI catches this error and
/// surfaces it as a snackbar.
///
/// Subclass of [StateError] so the existing
/// `try { ... } catch (_) { snackbar }` handlers in
/// `add_food_screen.dart` continue to treat it as a soft failure
/// (no rethrow, no rollback); a typed `catch` is preferred so a
/// future migration to surface specific copy can discriminate.
class FoodGroupHasBundledFoodsError extends StateError {
  /// The id of the category the user tried to delete. Surfaced so the
  /// UI can build copy that names the category.
  final String groupId;

  /// The display name of the category, captured at throw time.
  final String groupName;

  /// The bundled food ids that currently reference [groupId] and
  /// would be stranded if the deletion proceeded. Surfaced so the
  /// UI can list the first few names in the snackbar.
  final List<String> bundledFoodIds;

  FoodGroupHasBundledFoodsError({
    required this.groupId,
    required this.groupName,
    required this.bundledFoodIds,
  }) : super(
         'Cannot delete category "$groupName" ($groupId): ${bundledFoodIds.length} '
         'bundled catalog food(s) still reference it.',
       );
}

class FoodLibraryState extends ChangeNotifier {
  final WorkoutRepository _repository;

  /// Optional image-storage helper. When provided, the state
  /// self-heals stale food `imagePath`s on load (D-4) and deletes
  /// the previous managed file when a food's photo is replaced or
  /// removed (D-3, D-7). When null, these behaviours are no-ops —
  /// used only by tests that do not exercise image persistence.
  final ImageStorageService? _imageStorage;

  // ─── Private cache fields ─────────────────────────────────────────────────
  Map<String, FoodGroup> _foodGroups = {};
  Map<String, Food> _foods = {};
  Map<String, Food> _catalogFoods = {};

  bool _isLoadingGroups = false;
  bool _isLoadingFoods = false;
  bool _isLoadingCatalog = false;

  // ─── Public getters for UI ────────────────────────────────────────────────

  /// Returns the cached food groups (including archived). Callers
  /// that only want the active list (e.g. UI rendering) should
  /// filter with `where((g) => !g.isArchived)`. Mirrors the
  /// pre-archive semantic where the cache was the source of truth
  /// and the repo's `getFoodGroups(includeArchived: false)` was
  /// the filtered view.
  List<FoodGroup> get foodGroups => _foodGroups.values.toList();

  /// Returns the active (non-archived) cached food groups. The
  /// default view for UI; the [foodGroups] getter returns the full
  /// cache for state-internal logic.
  List<FoodGroup> get activeFoodGroups =>
      _foodGroups.values.where((g) => !g.isArchived).toList();

  /// Returns an unmodifiable list of cached foods.
  List<Food> get foods => _foods.values.toList();

  /// Returns an unmodifiable list of cached catalog foods (bundled,
  /// read-only). Empty until [loadCatalogFoods] has been awaited at
  /// least once.
  List<Food> get catalogFoods => _catalogFoods.values.toList();

  bool get isLoadingGroups => _isLoadingGroups;
  bool get isLoadingFoods => _isLoadingFoods;
  bool get isLoadingCatalogFoods => _isLoadingCatalog;

  // ─── Constructor ──────────────────────────────────────────────────────────

  FoodLibraryState(this._repository, {ImageStorageService? imageStorage})
    : _imageStorage = imageStorage;

  /// Non-null accessor for the image storage helper. Screens that
  /// host the food-photo picker (`FoodForm`) read this to perform
  /// the file-system copy before calling the state save methods.
  /// The production `main.dart` always injects a real service;
  /// tests that do not exercise the picker should not read this
  /// getter.
  ImageStorageService get imageStorage {
    final svc = _imageStorage;
    if (svc == null) {
      throw StateError(
        'FoodLibraryState.imageStorage was read but no service was '
        'injected. main.dart must construct an ImageStorageService '
        'and pass it to FoodLibraryState. See '
        'docs/plans/image-persistence-fix-plan.md (D-8).',
      );
    }
    return svc;
  }

  /// Nullable accessor for the image storage helper. Used by the
  /// rendering widgets (`FoodThumbnail`, `FoodFormImageTile`) which
  /// receive the service as an optional parameter and degrade
  /// gracefully when no service is injected (legacy / test path).
  ImageStorageService? get imageStorageOrNull => _imageStorage;

  /// Load-time resolve + normalize. See [loadFoods] /
  /// [loadCatalogFoods].
  ///
  /// Resolution contract (D-3): the service searches the current
  /// managed dir, the literal reference path (legacy absolute
  /// paths), and configured candidate directories (picker temp,
  /// app support). If a file matching the basename is reachable
  /// anywhere, the service re-links it into the current managed
  /// dir and returns the basename. If no candidate has the file,
  /// the service returns `null`.
  ///
  /// Persistence rules (D-4, D-6, INV-4):
  ///   * No service injected → no-op.
  ///   * Service returns the same value as stored → no write.
  ///   * Service returns a different basename → persist the
  ///     normalized reference (one-time migration write). The file
  ///     is re-linked by the service.
  ///   * Service returns `null` → persist `imagePath: null`
  ///     (true self-heal; file is truly absent on disk).
  ///
  /// Per-row failures are logged to [debugPrint] but do not
  /// propagate — the next load will retry them. The load itself
  /// never throws because of resolve/normalize.
  Future<void> _resolveAndNormalizeFoodImages() async {
    final svc = _imageStorage;
    if (svc == null) return;
    for (final food in _foods.values.toList()) {
      final stored = food.imagePath;
      if (stored == null || stored.isEmpty) continue;
      final resolved = await svc.resolveOrRelink(stored);
      if (resolved == stored) continue;
      final normalized = food.copyWith(imagePath: resolved);
      try {
        await _repository.updateFood(normalized);
        _foods[normalized.id] = normalized;
      } catch (e) {
        // The state has no general error channel; surface to the
        // debug log and let the next load retry.
        debugPrint(
          'FoodLibraryState resolve/normalize failed for ${food.id}: $e',
        );
      }
    }
  }

  // ─── Food Group Operations ────────────────────────────────────────────────

  /// Load all food groups from the repository, update cache, and notify listeners.
  ///
  /// Set [includeArchived] = true to load archived groups as well.
  Future<void> loadFoodGroups({bool includeArchived = false}) async {
    _isLoadingGroups = true;
    notifyListeners();

    try {
      final groups = await _repository.getFoodGroups(
        includeArchived: includeArchived,
      );
      _foodGroups = {for (final g in groups) g.id: g};
    } catch (e) {
      _foodGroups = {};
      rethrow;
    } finally {
      _isLoadingGroups = false;
      notifyListeners();
    }
  }

  /// Retrieve a food group by ID from cache or repository.
  ///
  /// Returns null if not found.
  Future<FoodGroup?> getFoodGroupById(String id) async {
    // Check cache first
    if (_foodGroups.containsKey(id)) {
      return _foodGroups[id];
    }

    // Fall back to repository
    final group = await _repository.getFoodGroupById(id);
    if (group != null) {
      _foodGroups[id] = group;
      notifyListeners();
    }
    return group;
  }

  /// Create a new food group with the given name and optional color.
  ///
  /// Persists to repository, adds to cache, and notifies listeners.
  Future<String> createFoodGroup(String name, {String? color}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _generateId('group');

    final group = FoodGroup(
      id: id,
      name: name,
      color: color,
      isArchived: false,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _repository.createFoodGroup(group);
    _foodGroups[id] = group;
    notifyListeners();

    return id;
  }

  /// Update an existing food group and persist changes.
  ///
  /// Notifies listeners after update.
  Future<void> updateFoodGroup(FoodGroup group) async {
    final updated = FoodGroup(
      id: group.id,
      name: group.name,
      color: group.color,
      isArchived: group.isArchived,
      createdAtMs: group.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _repository.updateFoodGroup(updated);
    _foodGroups[updated.id] = updated;
    notifyListeners();
  }

  /// Archive a food group (soft-delete: sets isArchived = true).
  ///
  /// Notifies listeners after archival.
  Future<void> archiveFoodGroup(String id) async {
    final group = _foodGroups[id];
    if (group == null) {
      throw Exception('Food group not found: $id');
    }

    await _repository.archiveFoodGroup(id);

    final archived = FoodGroup(
      id: group.id,
      name: group.name,
      color: group.color,
      isArchived: true,
      createdAtMs: group.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _foodGroups[id] = archived;
    notifyListeners();
  }

  /// Rename an existing food group. Thin wrapper that preserves
  /// id / color / createdAtMs / isArchived, updates only `name` and
  /// `updatedAtMs`, and notifies listeners.
  ///
  /// Used by the Groups tab's inline `TextField`. No-ops on
  /// whitespace-only or empty names (returns without mutating).
  /// Throws if the group is not in the cache.
  Future<void> renameFoodGroup(String id, String newName) async {
    final group = _foodGroups[id];
    if (group == null) {
      throw Exception('Food group not found: $id');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == group.name) return;
    final updated = FoodGroup(
      id: group.id,
      name: trimmed,
      color: group.color,
      isArchived: group.isArchived,
      createdAtMs: group.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.updateFoodGroup(updated);
    _foodGroups[id] = updated;
    notifyListeners();
  }

  /// Delete (archive) a group, reassigning its foods to [toGroupId]
  /// (or `null` for "Ungrouped") so no food is lost. The two
  /// writes happen sequentially — the food reassignment is
  /// committed first, then the group is archived. Either step
  /// failing leaves the previous state intact (the cache is
  /// updated only after the underlying repo write succeeds).
  ///
  /// Foods that already had `groupId == toGroupId` are not touched
  /// by the repository (a no-op `UPDATE`). After completion, the
  /// group's row is `isArchived = true` and the cache reflects the
  /// reassignment.
  ///
  /// **Bundled-food guard (S-006)**: refuses the deletion when
  /// at least one bundled catalog food — a food whose id is in
  /// [_bundledCatalogFoodIds] — still has `groupId == id`. We
  /// cannot rewrite a bundled catalog food's `groupId` because
  /// the catalog refresh restores the bundled category on every
  /// launch, so any such rewrite would silently revert and the
  /// user would watch their action undo itself. The honest answer
  /// is to refuse the deletion and surface the reason via a
  /// [FoodGroupHasBundledFoodsError] (caught by
  /// `add_food_screen.dart`'s `_confirmAndDeleteGroup` and shown
  /// as a snackbar). Library foods and user-created catalog foods
  /// in the category are reassigned and the category is archived
  /// exactly as before — only the bundled case is blocked.
  Future<void> deleteFoodGroupReassigningFoods(
    String id,
    String? toGroupId,
  ) async {
    final group = _foodGroups[id];
    if (group == null) {
      throw Exception('Food group not found: $id');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    // The guard below reads the in-memory catalog cache. A cold
    // cache would make it see zero bundled foods and wave the
    // deletion through, stranding every bundled food in the
    // category — the exact outcome the guard exists to prevent.
    // Load the catalog first when it has never been populated.
    if (_catalogFoods.isEmpty) {
      await loadCatalogFoods();
    }
    // Bundled-food guard (S-006): if any bundled catalog food
    // currently points at this group, refuse the deletion. Run
    // this BEFORE the library/user-catalog reassignment so a
    // refused deletion is a true no-op (no row was touched).
    final strandedBundled = _catalogFoods.values
        .where(
          (f) => !f.isArchived && f.groupId == id && isBundledCatalogFood(f.id),
        )
        .map((f) => f.id)
        .toList();
    if (strandedBundled.isNotEmpty) {
      throw FoodGroupHasBundledFoodsError(
        groupId: id,
        groupName: group.name,
        bundledFoodIds: strandedBundled,
      );
    }
    // Reassign library foods first (existing behaviour).
    final foodIds = _foods.values
        .where((f) => !f.isCatalog && !f.isArchived && f.groupId == id)
        .map((f) => f.id)
        .toList();
    if (foodIds.isNotEmpty) {
      await _repository.reassignFoodsToGroup(foodIds, toGroupId);
      // Refresh the food cache: any food whose groupId changed needs
      // an updated copy. Pull the rows back through the repository
      // path so the in-memory state matches the persisted state.
      for (final fid in foodIds) {
        final refreshed = await _repository.getFoodById(fid);
        if (refreshed != null) {
          _foods[fid] = refreshed;
        } else {
          // Defensive: if the repo lost the row between the update
          // and the read, drop it from the cache to stay in sync.
          _foods.remove(fid);
        }
      }
    }
    // Reassign user-owned catalog foods (those created via **+ New
    // Item**) too. The bundled guard above guarantees we never see a
    // bundled id here; the filter on `isBundledCatalogFood == false`
    // is belt-and-suspenders.
    final userCatalogIds = _catalogFoods.values
        .where(
          (f) =>
              !f.isArchived && f.groupId == id && !isBundledCatalogFood(f.id),
        )
        .map((f) => f.id)
        .toList();
    if (userCatalogIds.isNotEmpty) {
      await _repository.reassignCatalogFoodsToGroup(userCatalogIds, toGroupId);
      // Refresh the catalog cache for the moved rows so the in-memory
      // catalog mirrors the persisted state.
      for (final cid in userCatalogIds) {
        final refreshed = await _repository.getCatalogFoodById(cid);
        if (refreshed != null) {
          _catalogFoods[cid] = refreshed;
        } else {
          _catalogFoods.remove(cid);
        }
      }
    }
    // Archive the source group.
    await _repository.archiveFoodGroup(id);
    _foodGroups[id] = FoodGroup(
      id: group.id,
      name: group.name,
      color: group.color,
      isArchived: true,
      createdAtMs: group.createdAtMs,
      updatedAtMs: now,
    );
    notifyListeners();
  }

  /// Pure local filter on [_catalogFoods] by case-insensitive
  /// substring on `name`. Returns an alphabetical list of matches;
  /// empty query returns the full catalog, also alphabetical.
  ///
  /// No network call. Safe to call on every keystroke.
  Future<List<Food>> searchCatalogFoods(String query) async {
    final lower = query.trim().toLowerCase();
    final all = _catalogFoods.values.where((f) => !f.isArchived);
    final filtered = lower.isEmpty
        ? all.toList()
        : all.where((f) => f.name.toLowerCase().contains(lower)).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  // ─── Food Operations ──────────────────────────────────────────────────────

  /// Load all foods from the repository, update cache, and notify listeners.
  ///
  /// Set [includeArchived] = true to load archived foods as well.
  Future<void> loadFoods({bool includeArchived = false}) async {
    _isLoadingFoods = true;
    notifyListeners();

    try {
      final foodsList = await _repository.getFoods(
        includeArchived: includeArchived,
      );
      _foods = {for (final f in foodsList) f.id: f};
      // D-4: load-time resolve + normalize for stale `imagePath`s.
      // Runs after the cache is populated so the renderer never
      // observes a non-null path that points at a gone file. Also
      // re-links legacy absolute-path records to the current
      // managed dir's basename on first load after the fix.
      await _resolveAndNormalizeFoodImages();
    } catch (e) {
      _foods = {};
      rethrow;
    } finally {
      _isLoadingFoods = false;
      notifyListeners();
    }
  }

  /// Retrieve a food by ID from cache or repository.
  ///
  /// Returns null if not found.
  Future<Food?> getFoodById(String id) async {
    // Check cache first
    if (_foods.containsKey(id)) {
      return _foods[id];
    }

    // Fall back to repository
    final food = await _repository.getFoodById(id);
    if (food != null) {
      _foods[id] = food;
      notifyListeners();
    }
    return food;
  }

  /// Create a new food and persist to repository.
  ///
  /// Adds to cache and notifies listeners.
  Future<String> createFood(Food food) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final newFood = Food(
      id: food.id.isEmpty ? _generateId('food') : food.id,
      name: food.name,
      groupId: food.groupId,
      unitType: food.unitType,
      referenceAmount: food.referenceAmount,
      referenceLabel: food.referenceLabel,
      isCatalog: false, // Library foods are always user-owned
      protein: food.protein,
      carbs: food.carbs,
      fiber: food.fiber,
      fat: food.fat,
      sodium: food.sodium,
      isArchived: false,
      notes: food.notes,
      imagePath: food.imagePath,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _repository.createFood(newFood);
    _foods[newFood.id] = newFood;
    notifyListeners();

    return newFood.id;
  }

  /// Update an existing food and persist changes.
  ///
  /// Notifies listeners after update.
  Future<void> updateFood(Food food) async {
    final updated = food.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _repository.updateFood(updated);
    _foods[updated.id] = updated;
    notifyListeners();
  }

  /// Archive a food (soft-delete: sets isArchived = true).
  ///
  /// Notifies listeners after archival.
  Future<void> archiveFood(String id) async {
    final food = _foods[id];
    if (food == null) {
      throw Exception('Food not found: $id');
    }

    await _repository.archiveFood(id);

    final archived = food.copyWith(
      isArchived: true,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _foods[id] = archived;
    notifyListeners();
  }

  /// Remove a food from the library (hard-delete).
  ///
  /// This is a hard-delete — the food row is removed entirely from storage.
  /// Past day logs (ConsumedFood entries) are unaffected because they store
  /// a frozen snapshot of the food at log time. The sourceFoodId reference
  /// may become orphaned, which is expected and supported.
  ///
  /// This method only removes user-owned library foods (isCatalog = false).
  /// Catalog foods are read-only and cannot be removed.
  ///
  /// Does nothing if [id] is not present (no-op, does not throw).
  /// If the food is in the cache, removes it and notifies listeners.
  /// If the food is not in the cache but exists in storage, delegates to
  /// the repository (handles cold-cache case) without notification.
  Future<void> removeFood(String id) async {
    // Delegate to repository (handles both cold-cache and cache-hit cases)
    await _repository.removeFood(id);

    // Only notify if the food was in our cache (UI state changed).
    // Map.remove returns the removed value (non-null on hit, null on miss)
    // and also conveniently drops the entry as a side effect.
    final removed = _foods.remove(id);
    if (removed != null) {
      notifyListeners();
    }
  }

  /// Identity match for the "is this catalog food in my library?" UI
  /// predicate used by the Manage Food Library toggle.
  ///
  /// A catalog food is considered "in the library" when at least one
  /// cached, non-archived, user-owned (`isCatalog = false`) `Food` has
  /// the **same identity** as the catalog source:
  ///
  ///   * case-insensitive `name`,
  ///   * same `unitType`,
  ///   * same `referenceAmount` and `referenceLabel`,
  ///   * same `protein`, `carbs`, `fiber`, `fat`, `sodium`.
  ///
  /// The id is intentionally NOT part of the identity — catalog copies
  /// are inserted with a fresh id by
  /// [WorkoutRepository.addCatalogFoodToLibrary], so an id match would
  /// always miss. The user-facing identity ("I already added this
  /// Chicken Breast") is name + reference + macros.
  ///
  /// Returns `false` for:
  ///   * unknown catalog ids (no row in [_catalogFoods]),
  ///   * archived library rows (the user has removed them, do not show
  ///     a Remove affordance for a hidden row).
  ///
  /// Cold-cache behavior: if the catalog cache is empty, this returns
  /// `false`. The catalog must be loaded first
  /// ([loadCatalogFoods]) for the predicate to be meaningful. Callers
  /// that need a definite answer should await the catalog load before
  /// rendering the catalog tab.
  ///
  /// Complexity is O(n) over the user's library, where n is the number
  /// of user-owned foods (typically tens to low hundreds). This is
  /// preferred over maintaining a separate `Set<String>` of "added
  /// catalog ids" that would have to be kept in sync with [_foods] on
  /// every add / remove.
  bool isInLibrary(String catalogFoodId) => libraryIdFor(catalogFoodId) != null;

  /// Returns the id of the user-owned library row that matches the
  /// given catalog source by identity, or `null` if no match exists.
  ///
  /// This is the underlying lookup that powers [isInLibrary]. It
  /// returns the id in addition to the boolean so the Manage Food
  /// Library toggle can call `removeFood` / `unlogFoodToday` against
  /// the right row without re-implementing the identity rule in the
  /// UI.
  ///
  /// Returns `null` for:
  ///   * unknown catalog ids (no row in [_catalogFoods]),
  ///   * no matching non-archived, user-owned library row.
  ///
  /// Uses durable catalogId linkage when available, falls back to
  /// value-based matching for legacy data without catalogId.
  String? libraryIdFor(String catalogFoodId) {
    // First, try durable catalogId lookup
    for (final f in _foods.values) {
      if (f.isCatalog) continue;
      if (f.isArchived) continue;
      if (f.catalogId == catalogFoodId) {
        return f.id;
      }
    }
    // Fall back to legacy value-based matching for data without catalogId
    final catalog = _catalogFoods[catalogFoodId];
    if (catalog == null) return null;
    for (final f in _foods.values) {
      if (f.isCatalog) continue;
      if (f.isArchived) continue;
      // Skip if already has catalogId (already matched above)
      if (f.catalogId != null) continue;
      if (!_matchesIdentity(catalog, f)) continue;
      return f.id;
    }
    return null;
  }

  /// Inverse of [libraryIdFor]: returns the catalog-food id that the
  /// given user-owned library row is a copy of, or `null` if the
  /// library row has no catalog twin.
  ///
  /// Powers the My Foods tab's "library copy of a bundled food is
  /// not a user-created food" filter (S-031a / Phase 3.1): a
  /// library row whose data matches a bundled catalog row has a
  /// non-null result here and is therefore excluded from the My
  /// Foods tab. A true legacy library-only custom (no catalog
  /// identity twin, even by data) returns `null` and is surfaced.
  ///
  /// Uses durable catalogId when available, falls back to legacy
  /// value-based matching for data without catalogId.
  ///
  /// Cold-cache: if [_catalogFoods] is empty (catalog never
  /// loaded), this returns `null` for every row — the same
  /// tradeoff [libraryIdFor] documents. Callers that need a
  /// definite answer should await the catalog load first.
  ///
  /// Complexity is O(n) over the catalog, which is small (≈100
  /// rows in the bundled seed). Mirrors the existing
  /// [libraryIdFor] O(m) over the user library.
  String? catalogIdFor(Food libraryFood) {
    // First, try durable catalogId lookup
    if (libraryFood.catalogId != null) {
      // Verify the catalog still exists
      if (_catalogFoods.containsKey(libraryFood.catalogId)) {
        return libraryFood.catalogId;
      }
    }
    // Fall back to legacy value-based matching
    for (final catalog in _catalogFoods.values) {
      if (catalog.isArchived) continue;
      if (!_matchesIdentity(catalog, libraryFood)) continue;
      return catalog.id;
    }
    return null;
  }

  /// Pure field-by-field identity check used by [isInLibrary] and
  /// [libraryIdFor]. Only used for legacy fallback when catalogId
  /// is not available. Pulled out so the rule lives in one place.
  static bool _matchesIdentity(Food a, Food b) {
    if (a.unitType != b.unitType) return false;
    if (a.referenceAmount != b.referenceAmount) return false;
    if (a.referenceLabel != b.referenceLabel) return false;
    if (a.protein != b.protein) return false;
    if (a.carbs != b.carbs) return false;
    if (a.fat != b.fat) return false;
    if (a.fiber != b.fiber) return false;
    if (a.sodium != b.sodium) return false;
    return a.name.toLowerCase() == b.name.toLowerCase();
  }

  /// Propagates catalog food edits to all linked library foods.
  /// Called after [updateCatalogFood] saves the catalog change.
  ///
  /// This ensures that when a user edits a catalog food (name, macros,
  /// image, group, etc.), the linked "Foods I Eat" entries automatically
  /// reflect the updated values.
  ///
  /// Uses durable `catalogId` linkage first, then falls back to
  /// identity matching against [oldCatalogFood] (the values BEFORE
  /// the edit) for legacy library foods (those without `catalogId`
  /// set). When a legacy library food is found via identity match, it
  /// is upgraded to use `catalogId` so future propagations work
  /// without identity matching.
  ///
  /// Per-field invariants:
  ///   * Every catalog field the user can edit — name, groupId,
  ///     unitType, referenceAmount, referenceLabel, macros (protein,
  ///     carbs, fiber, fat, sodium), notes, imagePath — propagates
  ///     to the linked library row. The library food's `groupId`
  ///     is NOT treated as user-customizable for catalog copies; the
  ///     catalog's choice wins.
  ///   * `id`, `isCatalog = false`, `catalogId`, and `createdAtMs`
  ///     are preserved from the existing library row so the durable
  ///     link stays intact.
  ///   * `lastAmountConsumed` (per-user remembered portion from
  ///     `NutritionState`, food-last-amount plan) is preserved from
  ///     the existing library row. Catalog rows are always `null`
  ///     for this field, so the propagation must explicitly carry
  ///     the library value forward — otherwise the write-through
  ///     amount the user just logged would be silently wiped.
  ///   * `updatedAtMs` is bumped so the next `notifyListeners()`
  ///     cycle reflects the propagation timestamp.
  Future<void> _propagateCatalogEditToLinkedFoods(
    String catalogFoodId,
    Food oldCatalogFood,
    Food updatedCatalogFood,
  ) async {
    // Find all library foods linked to this catalog via catalogId
    final linkedFoodIds = <String>[];
    final legacyMatches = <Food>[];

    for (final f in _foods.values) {
      if (f.isCatalog) continue;
      if (f.catalogId == catalogFoodId) {
        linkedFoodIds.add(f.id);
      } else if (f.catalogId == null) {
        // Legacy library food without catalogId - try identity match
        // against the OLD catalog values (before the edit), since
        // the library food still has those old values.
        if (_matchesIdentity(oldCatalogFood, f)) {
          legacyMatches.add(f);
        }
      }
    }

    if (linkedFoodIds.isEmpty && legacyMatches.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Update durable-linked library foods
    for (final libId in linkedFoodIds) {
      final libFood = _foods[libId];
      if (libFood == null) continue;

      // Create updated library food with catalog's current values
      // but preserve the library food's own id, catalogId,
      // lastAmountConsumed, and createdAtMs. The catalog's
      // groupId flows through (per the user-stated "any editable
      // field including group" contract).
      final updatedLibFood = updatedCatalogFood.copyWith(
        id: libFood.id,
        catalogId: libFood.catalogId,
        isCatalog: false,
        lastAmountConsumed: libFood.lastAmountConsumed,
        createdAtMs: libFood.createdAtMs,
        updatedAtMs: now,
      );

      // Persist and update cache
      await _repository.updateFood(updatedLibFood);
      _foods[libId] = updatedLibFood;
    }

    // Upgrade and update legacy library foods (found via identity match)
    for (final legacyFood in legacyMatches) {
      final upgradedLibFood = updatedCatalogFood.copyWith(
        id: legacyFood.id,
        catalogId: catalogFoodId, // Upgrade to durable linkage
        isCatalog: false,
        lastAmountConsumed: legacyFood.lastAmountConsumed,
        createdAtMs: legacyFood.createdAtMs,
        updatedAtMs: now,
      );

      // Persist and update cache
      await _repository.updateFood(upgradedLibFood);
      _foods[legacyFood.id] = upgradedLibFood;
    }

    notifyListeners();
  }

  /// Search foods by name (case-insensitive substring match).
  ///
  /// Returns results from the repository without caching.
  /// Set [includeArchived] = true to include archived foods in results.
  Future<List<Food>> searchFoods(
    String query, {
    bool includeArchived = false,
  }) async {
    return await _repository.searchFoods(
      query,
      includeArchived: includeArchived,
    );
  }

  // ─── Catalog Operations (S-003) ────────────────────────────────────────
  // The catalog is a bundled, read-only collection of common foods that
  // ships with the app. Users can browse it and copy individual entries
  // into their personal library, but they cannot edit or delete catalog
  // rows. The state caches the catalog so the Add-from-Catalog tab can
  // re-render on demand without re-hitting the repository every frame.

  /// Load the bundled catalog into the in-memory cache and notify
  /// listeners. Idempotent: a successful call replaces the cache with
  /// the latest repository snapshot. Catalog rows are NEVER exposed in
  /// [foods] — they live in [catalogFoods] only.
  Future<void> loadCatalogFoods({bool includeArchived = false}) async {
    _isLoadingCatalog = true;
    notifyListeners();

    try {
      final catalog = await _repository.getCatalogFoods(
        includeArchived: includeArchived,
      );
      _catalogFoods = {for (final f in catalog) f.id: f};
    } catch (e) {
      _catalogFoods = {};
      rethrow;
    } finally {
      _isLoadingCatalog = false;
      notifyListeners();
    }
  }

  /// Copy a catalog food into the user's library.
  ///
  /// Returns the library food's id. If the food is already in the
  /// user's library (linked via catalogId), returns the existing id
  /// instead of creating a duplicate. If a legacy library food (without
  /// catalogId set) is found via value matching, it is upgraded with
  /// the catalogId so future edits propagate correctly. The new row
  /// has `isCatalog = false`, a fresh id, and all other fields copied
  /// from the catalog source. The catalog itself is not modified.
  /// Throws if the catalog id is unknown.
  ///
  /// The new library food is inserted into the [_foods] cache and
  /// listeners are notified so the browse card on the nutrition page
  /// picks it up immediately.
  Future<String> addCatalogFoodToLibrary(String catalogFoodId) async {
    // First check if there's already a linked library food for this catalog
    final existingId = libraryIdFor(catalogFoodId);
    if (existingId != null) {
      // Check if the existing food has catalogId set; if not (legacy
      // data), upgrade it so future propagation works correctly.
      final existing = _foods[existingId];
      if (existing != null && existing.catalogId == null) {
        final upgraded = existing.copyWith(
          catalogId: catalogFoodId,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _repository.updateFood(upgraded);
        _foods[existingId] = upgraded;
        notifyListeners();
      }
      return existingId;
    }

    final newId = await _repository.addCatalogFoodToLibrary(catalogFoodId);
    // Pull the freshly-inserted library row back through the cache
    // path so the in-memory state matches the persisted state. A
    // getFoodById() miss here is unexpected (the repository just
    // created the row), but we tolerate it by leaving the cache as-is
    // and not throwing.
    final added = await _repository.getFoodById(newId);
    if (added != null) {
      _foods[newId] = added;
      notifyListeners();
    }
    return newId;
  }

  // ─── Catalog Edit (S-001 / S-002) ────────────────────────────────────
  // The **Library** tab on `AddFoodScreen` is the global managed
  // library. Each row tap opens `EditFoodScreen`, which calls
  // [updateCatalogFood] here. The **+ New Item** tab also calls into
  // the catalog box (via [createCatalogFood]) — every new food the
  // user creates goes into the global managed library, and the
  // existing **Add** button on the row is the bridge from the global
  // library into the user's personal logging library.

  /// Update an existing catalog food (S-001). The caller supplies the
  /// full set of editable fields via a [FoodDraft] (from the shared
  /// [FoodForm] widget); the original `id` and `isCatalog = true` are
  /// preserved, only `updatedAtMs` advances. The row is written to the
  /// repository first, then the in-memory catalog cache is updated
  /// and listeners are notified.
  ///
  /// Past [ConsumedFood] snapshots for past days are NOT modified:
  /// the snapshot model freezes name, macros, and reference at log
  /// time, and the snapshot model does not include the image.
  ///
  /// Throws if [existing.id] is not in the catalog cache.
  Future<void> updateCatalogFood(Food existing, FoodDraft draft) async {
    if (existing.isCatalog != true) {
      throw StateError(
        'updateCatalogFood: existing.isCatalog must be true (got '
        '${existing.isCatalog} for id ${existing.id})',
      );
    }
    if (!_catalogFoods.containsKey(existing.id)) {
      throw Exception('Catalog food not found: ${existing.id}');
    }
    // D-7: replace/remove cleanup. Catalog edits may also clear
    // the image; the previous managed file is removed here so the
    // managed directory does not accumulate orphans. The
    // user-library sync loop below re-uses the same `imagePath`,
    // so this single delete covers both the catalog row and any
    // synced user copies that previously held the same file.
    final previousPath = existing.imagePath;
    if (previousPath != draft.imagePath) {
      final svc = _imageStorage;
      if (svc != null && previousPath != null) {
        await svc.deleteIfManaged(previousPath);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      name: draft.name,
      groupId: draft.groupId,
      unitType: draft.unitType,
      referenceAmount: draft.referenceAmount,
      referenceLabel: draft.referenceLabel,
      protein: draft.protein,
      carbs: draft.carbs,
      fiber: draft.fiber,
      fat: draft.fat,
      sodium: draft.sodium,
      notes: draft.notes,
      imagePath: draft.imagePath,
      updatedAtMs: now,
    );
    await _repository.updateCatalogFood(updated);
    _catalogFoods[existing.id] = updated;

    // Mark this catalog row as user-touched so the next catalog
    // refresh does not overwrite the user's edit. The marker is set
    // by the state layer (the only path that can produce a "user
    // edit") and read by `CatalogRefreshService` to decide which
    // seed entries to skip.
    await _repository.markSeedEntryTouched(
      SeedEntryType.foodCatalog,
      existing.id,
    );

    // Propagate catalog edits to all linked library foods using durable
    // catalogId linkage. This ensures edits to the catalog automatically
    // update linked "Foods I Eat" entries. We pass `existing` (the old
    // catalog food values) so the legacy identity-match fallback can
    // identify library foods that were previously value-linked to the
    // catalog before this edit.
    await _propagateCatalogEditToLinkedFoods(existing.id, existing, updated);

    notifyListeners();
  }

  /// Delete a catalog food from the catalog (hard delete).
  /// This permanently removes the food from the catalog.
  /// Does NOT affect user's historical nutrition logs (ConsumedFood entries)
  /// since they store frozen snapshots.
  ///
  /// Throws if the food is a bundled catalog food (cannot be deleted).
  /// Throws if the food is not found.
  Future<void> deleteCatalogFood(String id) async {
    if (isBundledCatalogFood(id)) {
      throw StateError('Cannot delete bundled catalog food: $id');
    }
    await _repository.deleteCatalogFood(id);
    _catalogFoods.remove(id);
    notifyListeners();
  }

  /// Create a new catalog food (S-002 — **+ New Item**). The new row
  /// is inserted into the catalog box with `isCatalog = true` and a
  /// fresh id assigned by the state. The food becomes part of the
  /// **Library** tab on `AddFoodScreen` and can be added to the
  /// user's personal library via the **Add** button on its row.
  ///
  /// Returns the new id. Throws on persistence failure.
  Future<String> createCatalogFood(FoodDraft draft) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _generateId('food');

    final food = Food(
      id: id,
      name: draft.name,
      groupId: draft.groupId,
      unitType: draft.unitType,
      referenceAmount: draft.referenceAmount,
      referenceLabel: draft.referenceLabel,
      isCatalog: true,
      protein: draft.protein,
      carbs: draft.carbs,
      fiber: draft.fiber,
      fat: draft.fat,
      sodium: draft.sodium,
      notes: draft.notes,
      imagePath: draft.imagePath,
      createdAtMs: now,
      updatedAtMs: now,
    );

    final newId = await _repository.createCatalogFood(food);
    // Re-read the freshly-inserted row so the cache matches the
    // persisted state (the repository's id allocation is the source
    // of truth).
    final inserted = await _repository.getCatalogFoodById(newId);
    if (inserted != null) {
      _catalogFoods[newId] = inserted;
    } else {
      // Defensive: a miss here is unexpected (we just inserted the
      // row), but we tolerate it by inserting the locally-built food.
      _catalogFoods[newId] = food.copyWith(id: newId);
    }
    notifyListeners();
    return newId;
  }

  // ─── Custom Food (S-004) ─────────────────────────────────────────────
  // Custom foods are user-owned library rows. They are persisted via the
  // existing [createFood] pipeline, which already enforces `isCatalog =
  // false` and assigns a fresh id when the incoming id is empty. We
  // keep the public surface ([createCustomFood]) parameterized so the
  // AddFoodScreen form does not have to know about the Food model.
  //
  // DEPRECATION (D-2): the + New Item form now writes user-created
  // foods to the **catalog** via [createCatalogFood] and then copies
  // the row into the library via [addCatalogFoodToLibrary]. The
  // legacy library-only path is preserved for backwards compatibility
  // with pre-D-2 data — legacy rows still need to be loaded,
  // rendered, edited, and deleted until the user removes them.
  // [createCustomFood] and [createCustomFoodFromDraft] are kept as
  // @Deprecated to flag the new contract; the methods are not deleted
  // so existing tests and any un-migrated call sites continue to
  // compile.

  /// Create a custom food and persist it to the user's library.
  ///
  /// The new row has `isCatalog = false` and a fresh id assigned by the
  /// state. The custom food does NOT appear in the catalog — the
  /// repository's [WorkoutRepository.createFood] write path is
  /// library-only, and the state never re-reports the new id through
  /// [catalogFoods].
  ///
  /// The optional [imagePath] is forwarded as an opaque native-first
  /// local file path (same contract as `UserProfile.avatarPath`).
  /// Passing `null` is the "no image" case.
  ///
  /// Returns the new id. Throws on persistence failure.
  @Deprecated(
    'User-created foods are now catalog foods (D-2). Use '
    'createCatalogFood(draft) + addCatalogFoodToLibrary(id) so the '
    'food appears in both the My Foods tab and the Foods I Eat '
    'library. This method is preserved for pre-D-2 call sites; new '
    'code should not use it.',
  )
  Future<String> createCustomFood({
    required String name,
    required String? groupId,
    required FoodUnitType unitType,
    required double referenceAmount,
    required String referenceLabel,
    required double protein,
    required double carbs,
    double? fiber,
    required double fat,
    double? sodium,
    String? notes,
    String? imagePath,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _generateId('food');

    final food = Food(
      id: id,
      name: name,
      groupId: groupId,
      unitType: unitType,
      referenceAmount: referenceAmount,
      referenceLabel: referenceLabel,
      isCatalog: false,
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      sodium: sodium,
      notes: notes,
      imagePath: imagePath,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _repository.createFood(food);
    _foods[id] = food;
    notifyListeners();
    return id;
  }

  /// Create a custom food from a [FoodDraft].
  ///
  /// Convenience overload that accepts a [FoodDraft] directly (same
  /// signature as [createCatalogFood]).
  @Deprecated(
    'User-created foods are now catalog foods (D-2). Use '
    'createCatalogFood(draft) + addCatalogFoodToLibrary(id) so the '
    'food appears in both the My Foods tab and the Foods I Eat '
    'library. This method is preserved for pre-D-2 call sites; new '
    'code should not use it.',
  )
  Future<String> createCustomFoodFromDraft(FoodDraft draft) async {
    return createCustomFood(
      name: draft.name,
      groupId: draft.groupId,
      unitType: draft.unitType,
      referenceAmount: draft.referenceAmount,
      referenceLabel: draft.referenceLabel,
      protein: draft.protein,
      carbs: draft.carbs,
      fiber: draft.fiber,
      fat: draft.fat,
      sodium: draft.sodium,
      notes: draft.notes,
      imagePath: draft.imagePath,
    );
  }

  /// Update an existing custom food in the user's library.
  ///
  /// The caller passes the full set of editable fields. The state
  /// preserves the original `id`, `isCatalog = false`, and
  /// `createdAtMs`; only `updatedAtMs` advances. The row is written
  /// to the repository first, then the in-memory cache is updated
  /// and listeners are notified.
  ///
  /// The image is stored as an opaque native-first local file path
  /// (same contract as `UserProfile.avatarPath`). When
  /// [imagePath] differs from the previous value, the state asks
  /// the [ImageStorageService] to delete the previous managed file
  /// (D-3, D-7). Passing `imagePath: null` clears the image and
  /// deletes the previous managed file.
  ///
  /// `ConsumedFood` snapshots for past days are NOT modified: the
  /// snapshot model freezes name, macros, and reference at log
  /// time, so editing a food's name, protein, or image cannot
  /// retroactively change what the user logged yesterday.
  ///
  /// Throws if [id] is not in the library.
  Future<void> updateCustomFood({
    required String id,
    required String name,
    required String? groupId,
    required FoodUnitType unitType,
    required double referenceAmount,
    required String referenceLabel,
    required double protein,
    required double carbs,
    double? fiber,
    required double fat,
    double? sodium,
    String? notes,
    required String? imagePath,
  }) async {
    final existing = _foods[id];
    if (existing == null) {
      throw Exception('Food not found: $id');
    }
    // D-7: replace/remove cleanup. The state owns the
    // "what was the previous image?" knowledge; the service
    // enforces the managed-directory gate (D-3).
    final previousPath = existing.imagePath;
    if (previousPath != imagePath) {
      final svc = _imageStorage;
      if (svc != null && previousPath != null) {
        await svc.deleteIfManaged(previousPath);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = Food(
      id: existing.id,
      name: name,
      groupId: groupId,
      unitType: unitType,
      referenceAmount: referenceAmount,
      referenceLabel: referenceLabel,
      isCatalog: false,
      catalogId: existing.catalogId, // Preserve catalogId if linked to catalog
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      sodium: sodium,
      isArchived: existing.isArchived,
      notes: notes,
      imagePath: imagePath,
      createdAtMs: existing.createdAtMs,
      updatedAtMs: now,
    );

    await _repository.updateFood(updated);
    _foods[id] = updated;
    notifyListeners();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Monotonic counter backing [_generateId]. `DateTime.now()`
  /// alone (even down to microseconds) is not a reliable
  /// uniqueness source: two calls issued back-to-back — the norm
  /// when awaiting an in-memory repository — can land on the same
  /// millisecond *and* the same microsecond, producing duplicate
  /// ids that silently collide as map keys (a later create
  /// overwrites an earlier one instead of coexisting). A static,
  /// ever-incrementing counter guarantees every id generated in
  /// this isolate is unique regardless of clock resolution.
  static int _idCounter = 0;

  /// Generate a deterministic, collision-free ID for a new food
  /// group or food.
  String _generateId(String prefix) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final counter = _idCounter++;
    return '$prefix-$timestamp-$counter';
  }

  /// Known IDs of bundled catalog foods (from assets/data/food_catalog.json).
  /// These foods cannot be hard-deleted - only removed from user's library.
  /// User-created catalog foods have generated IDs and can be hard-deleted.
  static const Set<String> _bundledCatalogFoodIds = {
    'almond_butter',
    'almond_milk',
    'almonds',
    'apple',
    'asparagus',
    'avocado',
    'bacon',
    'bagel',
    'banana',
    'bbq_sauce',
    'beef_jerky',
    'beef_patty',
    'beer_regular',
    'bell_pepper',
    'black_beans',
    'blueberries',
    'blueberry_muffin',
    'breakfast_cereal',
    'broccoli',
    'brown_rice',
    'brussels_sprouts',
    'butter',
    'cabbage',
    'california_roll',
    'cantaloupe',
    'carrots',
    'cashews',
    'cauliflower',
    'celery',
    'cheddar_cheese',
    'cherries',
    'chia_seeds',
    'chicken_breast',
    'chicken_thigh',
    'chicken_wing',
    'chickpeas',
    'chocolate_chip_cookie',
    'coconut_oil',
    'cod',
    'coffee',
    'cola',
    'corn_tortilla',
    'cottage_cheese',
    'couscous',
    'crackers',
    'cream_cheese',
    'croissant',
    'cucumber',
    'dark_chocolate',
    'dates',
    'diet_cola',
    'donut_glazed',
    'edamame',
    'egg',
    'egg_white',
    'english_muffin',
    'feta_cheese',
    'flax_seeds',
    'flour_tortilla',
    'french_fries',
    'granola_bar',
    'grapes',
    'greek_yogurt',
    'green_beans',
    'green_onion',
    'green_peas',
    'green_tea',
    'ground_beef',
    'ground_beef_2',
    'ground_chicken',
    'ground_turkey',
    'guacamole',
    'half_and_half',
    'ham',
    'honey',
    'hot_sauce',
    'hummus',
    'ice_cream_vanilla',
    'jalapeno',
    'kale',
    'ketchup',
    'kidney_beans',
    'kiwi',
    'latte',
    'lentils',
    'mango',
    'maple_syrup',
    'marinara_sauce',
    'mayonnaise',
    'milk_2pct',
    'mozzarella_cheese',
    'mushrooms',
    'mustard',
    'oat_milk',
    'oats',
    'olive_oil',
    'onion',
    'orange',
    'orange_juice',
    'pancake',
    'parmesan_cheese',
    'pasta',
    'peach',
    'peanut_butter',
    'peanuts',
    'pear',
    'pineapple',
    'pistachios',
    'pita_bread',
    'pizza_pepperoni_slice',
    'pizza_slice',
    'popcorn',
    'pork_chop',
    'pork_sausage_link',
    'pork_tenderloin',
    'potato',
    'potato_chips',
    'pretzels',
    'protein_bar',
    'pumpkin_seeds',
    'quinoa',
    'raisins',
    'ramen_prepared',
    'ranch_dressing',
    'raspberries',
    'red_wine',
    'rice_cake',
    'roast_beef_deli',
    'romaine_lettuce',
    'salmon',
    'salmon_raw',
    'salsa',
    'sardines_oil',
    'shrimp',
    'sirloin_steak',
    'skim_milk',
    'sour_cream',
    'sourdough_bread',
    'soy_sauce',
    'spinach',
    'sports_drink',
    'strawberries',
    'string_cheese',
    'sugar_granulated',
    'sunflower_seeds',
    'sweet_corn',
    'sweet_potato',
    'swiss_cheese',
    'tempeh',
    'tilapia',
    'tofu',
    'tomato',
    'tortilla_chips',
    'trail_mix',
    'tuna',
    'tuna_raw',
    'turkey_breast',
    'waffle',
    'walnuts',
    'watermelon',
    'whey_protein',
    'whipped_cream',
    'white_bread',
    'white_rice',
    'whole_milk',
    'whole_wheat_bread',
    'yogurt',
    'zucchini',
  };

  /// Returns true if this catalog food is a bundled/default food that
  /// cannot be hard-deleted. User-created catalog foods can be deleted.
  bool isBundledCatalogFood(String catalogFoodId) {
    return _bundledCatalogFoodIds.contains(catalogFoodId);
  }

  /// Returns catalog foods that were created by the user (not bundled).
  /// These appear in the "My Foods" tab and can be hard-deleted.
  List<Food> get userCreatedCatalogFoods {
    return _catalogFoods.values
        .where((f) => !isBundledCatalogFood(f.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}
