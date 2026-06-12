// filepath: lib/features/nutrition/add_food_screen.dart
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/utils/food_helpers.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import 'edit_food_screen.dart';
import 'widgets/food_form.dart';
import 'widgets/food_thumbnail.dart';

/// Sentinel used by [_DeleteCategoryDialog] to distinguish "user
/// tapped Cancel" from "user picked Ungrouped (which is a legitimate
/// `null` destination)". The dialog returns this sentinel for cancel
/// and the raw destination (which may itself be `null` for
/// Ungrouped) for confirm.
const Object _cancelledSentinel = Object();

/// Manage Food Library screen — two-tab flow for adding and removing
/// foods to/from the user's library.
///
/// Tab 1 (default): Library — flat alphabetical list of bundled
/// catalog foods. Each row renders a state-dependent trailing
/// affordance:
///
///   * **Add** (primary background) when the catalog food is NOT in
///     the user's library. Tap → `FoodLibraryState.addCatalogFoodToLibrary`.
///   * **Remove** (red `theme.colorScheme.error` background, white
///     `Icons.delete_outline`) when the food IS in the library. Tap →
///     `FoodLibraryState.removeFood` (and, if the food is currently
///     logged today, `NutritionState.unlogFoodToday` first so the
///     day-log stays consistent).
///
/// Both actions stay on the screen — the user can add and remove
/// several foods in one visit and only leaves via the system back
/// arrow. The catalog itself is never modified.
///
/// Tab 2: + New Item — form for a user-owned custom food (name,
/// category, unit type, reference, macros). The custom food is added
/// to the library only; the catalog is not modified. On save, the
/// screen pops back to the nutrition page (one-shot form).
///
/// Pure presentation:
///   - No repository access (all writes go through [FoodLibraryState]
///     and [NutritionState]).
///   - All colors come from [OmniTheme.colors] / `ThemeData.colorScheme`.
class AddFoodScreen extends StatefulWidget {
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const AddFoodScreen({
    super.key,
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Ensure the catalog cache is loaded when the screen opens so the
    // first tab has something to render. Safe to call when already
    // loaded (idempotent).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.foodLibraryState.loadCatalogFoods();
      widget.foodLibraryState.loadFoods();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Food Library'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Library'),
            Tab(text: 'My Foods'),
            Tab(text: 'Categories'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FromCatalogTab(
            foodLibraryState: widget.foodLibraryState,
            nutritionState: widget.nutritionState,
          ),
          _MyFoodsTab(
            foodLibraryState: widget.foodLibraryState,
            nutritionState: widget.nutritionState,
          ),
          _CategoriesTab(foodLibraryState: widget.foodLibraryState),
        ],
      ),
    );
  }
}

/// Edit screen shim for **legacy library-only customs** (D-2
/// compatibility shim).
///
/// `EditFoodScreen.push` always routes through
/// [FoodLibraryState.updateCatalogFood], which throws when given a
/// non-catalog row. Legacy rows (`isCatalog = false`, pre-D-2) need
/// to route through [FoodLibraryState.updateCustomFood] instead.
///
/// This screen wraps the shared [FoodForm] widget with a save
/// callback that dispatches to the correct update path based on
/// `food.isCatalog`. Once all legacy rows are deleted (or migrated)
/// this shim can be removed.
class _LegacyLibraryEditScreen extends StatelessWidget {
  final Food food;
  final FoodLibraryState foodLibraryState;

  const _LegacyLibraryEditScreen({
    required this.food,
    required this.foodLibraryState,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Food')),
      body: FoodForm(
        initial: food,
        foodLibraryState: foodLibraryState,
        saveLabel: 'Save',
        showNotesField: true,
        onSave: (draft) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            if (food.isCatalog) {
              await foodLibraryState.updateCatalogFood(food, draft);
            } else {
              await foodLibraryState.updateCustomFood(
                id: food.id,
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
            return true;
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not save ${food.name}: $e')),
            );
            return false;
          }
        },
      ),
    );
  }
}

// ─── Tab 1: Library ─────────────────────────────────────────────────────

/// Flat alphabetical list of catalog foods. Each row's trailing
/// affordance reflects whether the catalog food is in the user's
/// library (see [_CatalogRow]). The tab listens to BOTH
/// [FoodLibraryState] (for add/remove) and [NutritionState] (so the
/// "is logged today?" check stays live while the user is on the tab).
///
/// A search field at the top of the tab filters the catalog by food
/// name. The filter is local (no network call) and runs in
/// `FoodLibraryState.searchCatalogFoods` (case-insensitive substring
/// on `name`, alphabetical order).
class _FromCatalogTab extends StatefulWidget {
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _FromCatalogTab({
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  State<_FromCatalogTab> createState() => _FromCatalogTabState();
}

class _FromCatalogTabState extends State<_FromCatalogTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.foodLibraryState, widget.nutritionState]),
      builder: (context, _) {
        if (widget.foodLibraryState.isLoadingCatalogFoods) {
          return const Center(child: CircularProgressIndicator());
        }

        // Local filter: drives off the cached catalog and the current
        // query. The state's `searchCatalogFoods` is a pure local
        // pass — no network call. Clearing the field restores the
        // full alphabetical list.
        final all = _sorted(widget.foodLibraryState.catalogFoods);
        final lower = _query.trim().toLowerCase();
        final catalog = lower.isEmpty
            ? all
            : all.where((f) => f.name.toLowerCase().contains(lower)).toList();

        if (all.isEmpty) {
          return Center(
            child: Text(
              'No catalog foods available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: OmniTheme.colors.textMuted,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                key: const Key('catalog_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search catalog',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (catalog.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No matches for "${_query.trim()}"',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textMuted,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: catalog.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final f = catalog[i];
                    return _CatalogRow(
                      food: f,
                      foodLibraryState: widget.foodLibraryState,
                      nutritionState: widget.nutritionState,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// Case-insensitive alphabetical sort. Pure helper.
  static List<Food> _sorted(List<Food> foods) {
    final copy = [...foods];
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }
}

// ─── Tab 2: My Foods ───────────────────────────────────────────────────

/// Shows user-owned foods (D-2 / S-031):
///
///   * **userCreatedCatalogFoods** — every food in the catalog whose
///     id is NOT a bundled default. These are the foods the user
///     created via the + New Item form (and any pre-D-2 user
///     catalog rows).
///   * **legacy library-only customs** — non-archived rows with
///     `isCatalog = false` (created via the pre-D-2
///     [FoodLibraryState.createCustomFood] path). These need to stay
///     manageable until the user deletes them.
///
/// Bundled (default) catalog foods never appear here. Every
/// user-created food appears exactly once.
///
/// Value class that captures the identity tuple used by
/// `FoodLibraryState._matchesIdentity` (name + reference + macros).
///
/// The single source of truth for the identity rule lives in
/// [FoodLibraryState]; this class is the dedup-key mirror of that
/// rule for the My Foods tab. If the state rule ever expands (e.g.
/// per-locale normalization), update both.
///
/// Equality is by value, NOT by id: two [Food] rows with the same
/// name/reference/macros hash to the same [_FoodIdentity], so a D-2
/// catalog row and its auto-created library copy collide here and
/// only the first one (catalog row, by iteration order) is kept.
@immutable
class _FoodIdentity {
  final String nameLower;
  final FoodUnitType unitType;
  final double referenceAmount;
  final String referenceLabel;
  final int protein;
  final int carbs;
  final int? fiber;
  final int fat;
  final int? sodium;

  const _FoodIdentity({
    required this.nameLower,
    required this.unitType,
    required this.referenceAmount,
    required this.referenceLabel,
    required this.protein,
    required this.carbs,
    required this.fiber,
    required this.fat,
    required this.sodium,
  });

  factory _FoodIdentity.fromFood(Food f) => _FoodIdentity(
        nameLower: f.name.toLowerCase(),
        unitType: f.unitType,
        referenceAmount: f.referenceAmount,
        referenceLabel: f.referenceLabel,
        protein: f.protein,
        carbs: f.carbs,
        fiber: f.fiber,
        fat: f.fat,
        sodium: f.sodium,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _FoodIdentity &&
        nameLower == other.nameLower &&
        unitType == other.unitType &&
        referenceAmount == other.referenceAmount &&
        referenceLabel == other.referenceLabel &&
        protein == other.protein &&
        carbs == other.carbs &&
        fiber == other.fiber &&
        fat == other.fat &&
        sodium == other.sodium;
  }

  @override
  int get hashCode => Object.hash(
        nameLower,
        unitType,
        referenceAmount,
        referenceLabel,
        protein,
        carbs,
        fiber,
        fat,
        sodium,
      );
}

/// Row tap opens the **Edit Food** screen (D-2 / S-034). Tapping the
/// row (not the trailing delete button) routes to the catalog edit
/// path for catalog foods, and the library edit path for legacy
/// library-only customs.
class _MyFoodsTab extends StatelessWidget {
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _MyFoodsTab({
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: foodLibraryState,
      builder: (context, _) {
        // S-031a / Phase 3.1 — three sources, one deduplicated list:
        //
        //   1. **userCreatedCatalogFoods** (D-2 path). The user
        //      created this food via the + New Item form; the row
        //      lives in the catalog box (`isCatalog = true`) and its
        //      id is NOT a bundled default. Always surfaced.
        //
        //   2. **legacy library-only customs**. Rows in the library
        //      box with `isCatalog = false` that have NO catalog
        //      identity twin — i.e. `catalogIdFor(row) == null`.
        //      The catalogIdFor check is critical: without it, a
        //      library copy of a bundled catalog food (created by
        //      the user tapping Add on a row in the Library tab)
        //      would leak into My Foods and look like a user-created
        //      custom. The single identity rule
        //      (FoodLibraryState._matchesIdentity) is shared with
        //      libraryIdFor, so the inverse lookup is in lockstep.
        //
        //   3. **no third source**. The D-2 catalog row and its
        //      auto-created library copy have different ids, so a
        //      naive id-dedup would render the D-2 custom TWICE
        //      (once as the catalog row, once as the fresh-id
        //      library copy). The legacy filter is on the library
        //      side only, so a user-created D-2 custom's library
        //      twin IS excluded here. Identity-key dedup
        //      (Food identity tuple) is the belt-and-braces second
        //      line of defense; the two sources are disjoint by
        //      construction after this filter.
        final userCatalog = foodLibraryState.userCreatedCatalogFoods
            .where((f) => !f.isArchived)
            .toList();
        final legacyLibrary = foodLibraryState.foods
            .where(
              (f) =>
                  !f.isArchived &&
                  !f.isCatalog &&
                  foodLibraryState.catalogIdFor(f) == null,
            )
            .toList();

        // Identity-key dedup (belt-and-braces). The tuple is the
        // (name, reference, macros) shape that _matchesIdentity
        // uses; encoding the same fields here would invite drift,
        // so the helper is reused. The map keeps the FIRST
        // occurrence (userCatalog has priority because it is
        // iterated first) so the catalog row wins over a stale
        // library twin with the same data.
        final seenIdentities = <_FoodIdentity>{};
        final merged = <Food>[];
        void addIfNew(Food f) {
          if (seenIdentities.add(_FoodIdentity.fromFood(f))) {
            merged.add(f);
          }
        }

        for (final f in userCatalog) {
          addIfNew(f);
        }
        for (final f in legacyLibrary) {
          addIfNew(f);
        }
        merged.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        if (merged.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 64,
                    color: OmniTheme.colors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No custom foods yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: OmniTheme.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your own foods to use in your nutrition tracking',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _AddNewFoodButton(foodLibraryState: foodLibraryState),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: merged.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final f = merged[i];
                  return _UserFoodRow(
                    food: f,
                    foodLibraryState: foodLibraryState,
                    nutritionState: nutritionState,
                  );
                },
              ),
            ),
            // Add New Food button at bottom
            Padding(
              padding: const EdgeInsets.all(16),
              child: _AddNewFoodButton(foodLibraryState: foodLibraryState),
            ),
          ],
        );
      },
    );
  }
}

/// Button to add a new custom food to the catalog.
class _AddNewFoodButton extends StatelessWidget {
  final FoodLibraryState foodLibraryState;

  const _AddNewFoodButton({required this.foodLibraryState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: OmniTheme.buttonPrimaryHeight,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _openNewFoodForm(context),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Food'),
      ),
    );
  }

  void _openNewFoodForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _NewFoodFormScreen(
          foodLibraryState: foodLibraryState,
        ),
      ),
    );
  }
}

/// Full-screen form for creating a new custom food.
///
/// On save (D-2 / S-030): the draft is written to the **catalog** via
/// [FoodLibraryState.createCatalogFood] (so the food becomes part of
/// the user's "My Foods" collection), then immediately copied into
/// the user's personal library via
/// [FoodLibraryState.addCatalogFoodToLibrary] (so the food is
/// reachable from the Foods I Eat card without a second tap).
///
/// Failure handling:
///   * If `createCatalogFood` throws, the form stays open and reports
///     the error via the snackbar — nothing was persisted.
///   * If `addCatalogFoodToLibrary` throws after the catalog write
///     succeeded, the catalog row is preserved (it remains in My
///     Foods and is editable from there) and a snackbar surfaces the
///     library-add error. The form still pops, so the user is not
///     trapped on a save screen.
class _NewFoodFormScreen extends StatelessWidget {
  final FoodLibraryState foodLibraryState;

  const _NewFoodFormScreen({required this.foodLibraryState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Food'),
      ),
      body: FoodForm(
        initial: null,
        foodLibraryState: foodLibraryState,
        saveLabel: 'Create',
        onSave: (draft) async {
          final messenger = ScaffoldMessenger.of(context);
          String? catalogId;
          try {
            catalogId = await foodLibraryState.createCatalogFood(draft);
          } catch (_) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Could not create food')),
            );
            return false;
          }
          try {
            await foodLibraryState.addCatalogFoodToLibrary(catalogId);
          } catch (e) {
            // Catalog row is preserved; the user can re-add to
            // library from the My Foods tab. Surface the error so
            // the user is not silently left without a library copy.
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Food saved, but adding to your library failed: $e',
                ),
              ),
            );
            // Pop so the user can see My Foods and the new catalog
            // row. The catalog write succeeded; only the library
            // copy failed.
            return true;
          }
          if (context.mounted) Navigator.of(context).pop();
          return true;
        },
      ),
    );
  }
}

/// A single user-created catalog food row with delete button.
class _UserFoodRow extends StatefulWidget {
  final Food food;
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _UserFoodRow({
    required this.food,
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  State<_UserFoodRow> createState() => _UserFoodRowState();
}

class _UserFoodRowState extends State<_UserFoodRow> {
  bool _busy = false;

  static const double _deleteTrailingSize = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cal = calculateCalories(widget.food);
    final macroText =
        '$cal cal · ${widget.food.protein}P · ${widget.food.carbs}C · ${widget.food.fat}F';

    // D-2 / S-034: tapping the row surface (thumbnail, name, macro
    // text, or padding) opens the Edit Food screen. The trailing
    // delete button consumes its own tap and does NOT bubble.
    return InkWell(
      onTap: () => _openEdit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Thumbnail
            FoodThumbnail(
              key: Key('food_user_thumb_${widget.food.id}'),
              imagePath: widget.food.imagePath,
            ),
            const SizedBox(width: 12),
            // Name + macros
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.food.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textDominant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    macroText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: OmniTheme.colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Delete button
            SizedBox(
              width: _deleteTrailingSize,
              height: _deleteTrailingSize,
              child: FilledButton(
                key: Key('delete_user_food_${widget.food.id}'),
                onPressed: _busy ? null : () => _onDelete(context),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(OmniTheme.buttonIconRadius),
                  ),
                ),
                child:
                    Icon(Icons.delete_outline, color: theme.colorScheme.onError),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open the Edit Food screen for this row. The screen pops on
  /// successful save; the state notifies listeners so the row
  /// reflects the updated values.
  ///
  /// Branches on provenance:
  ///   * **isCatalog = true** (user-created catalog food, D-2 path)
  ///     → [EditFoodScreen], which routes through
  ///     [FoodLibraryState.updateCatalogFood] (updates the catalog
  ///     row and syncs any matching library copies).
  ///   * **isCatalog = false** (legacy library-only custom, pre-D-2
  ///     path) → [EditFoodScreen] is not appropriate
  ///     (`updateCatalogFood` throws on non-catalog rows). Push a
  ///     `_LegacyLibraryEditScreen` shim that routes through
  ///     [FoodLibraryState.updateCustomFood].
  void _openEdit(BuildContext context) {
    if (widget.food.isCatalog) {
      EditFoodScreen.push(
        context,
        food: widget.food,
        foodLibraryState: widget.foodLibraryState,
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _LegacyLibraryEditScreen(
            food: widget.food,
            foodLibraryState: widget.foodLibraryState,
          ),
        ),
      );
    }
  }

  Future<void> _onDelete(BuildContext context) async {
    // Capture the messenger before any await so the snackbar
    // survives a context unmount mid-flight (defensive: the row is
    // a child of the navigation stack and a delete can rebuild the
    // tree).
    final messenger = ScaffoldMessenger.of(context);
    final isBundled = widget.foodLibraryState.isBundledCatalogFood(widget.food.id);

    if (isBundled) {
      // Show warning dialog for bundled foods - shouldn't happen for user-created foods
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: Text(
            '"${widget.food.name}" is a default catalog food and cannot be deleted. '
            'You can only remove it from your personal library using the Library tab.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Show confirmation dialog for user-created foods
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Food?'),
        content: Text(
          'Are you sure you want to delete "${widget.food.name}"? '
          'Your past nutrition logs will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.food.isCatalog) {
        // User-created catalog food (D-2 / S-032). The catalog row
        // owns the identity; the library row is a sibling that
        // mirrors the same data. We must remove the library copy
        // first (so the day-log + library caches stay consistent)
        // and only then delete the catalog row.
        //
        // 1. If the user has logged this food today, unlog it
        //    before any structural change so today's ring/strip
        //    totals drop in lockstep with the row going away.
        // 2. Remove the matching library copy (if any). Identity
        //    match is name+reference+macros via
        //    `libraryIdFor(catalogId)`.
        // 3. Hard-delete the catalog row. Past ConsumedFood
        //    snapshots are byte-identical (frozen at log time).
        final libraryId = widget.foodLibraryState.libraryIdFor(
          widget.food.id,
        );
        if (libraryId != null &&
            widget.nutritionState.isFoodLoggedToday(libraryId)) {
          await widget.nutritionState.unlogFoodToday(libraryId);
        }
        if (libraryId != null) {
          await widget.foodLibraryState.removeFood(libraryId);
        }
        await widget.foodLibraryState.deleteCatalogFood(widget.food.id);
      } else {
        // Legacy library-only custom (pre-D-2 row). The catalog
        // was never involved; removeFood is the right path.
        if (widget.nutritionState.isFoodLoggedToday(widget.food.id)) {
          await widget.nutritionState.unlogFoodToday(widget.food.id);
        }
        await widget.foodLibraryState.removeFood(widget.food.id);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${widget.food.name}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// A single catalog row: name + per-reference macros on the left, a
/// state-dependent trailing button on the right.
///
/// State derives from [FoodLibraryState.libraryIdFor] (uses the
/// name + reference + macros identity rule, so it is robust to the
/// fresh-id allocation done by `addCatalogFoodToLibrary`).
///
/// Trailing actions (both wrapped in a fixed-width `SizedBox` so the
/// row's name column does not reflow when the state flips):
///
///   * **Not in library** — a primary "Add" `FilledButton` with text.
/// A single catalog row in the **Library** tab: a 40×40 thumbnail
/// (image or placeholder) on the left, food name + per-reference
/// macros in the middle, and a state-dependent trailing button on
/// the right.
///
/// Tapping the row surface (outside the trailing Add / Remove
/// button) opens the **Edit Food** screen for the catalog food;
/// this is the iteration-3 entry point to the edit affordance for
/// the global managed library. The trailing Add / Remove button
/// consumes its own tap and does NOT bubble to the row-level
/// `onRowTap` handler.
///
/// State derives from [FoodLibraryState.libraryIdFor] (uses the
/// name + reference + macros identity rule, so it is robust to the
/// fresh-id allocation done by `addCatalogFoodToLibrary`).
///
/// Trailing actions (both wrapped in a fixed-width `SizedBox` so
/// the row's name column does not reflow when the state flips):
///
///   * **Not in library** — a primary "Add" `FilledButton` with text.
///   * **In library** — a square red `FilledButton` containing only a
///     white trashcan icon (`Icons.delete_outline`); tapping it
///     removes the food. No text label — the trash icon is
///     universally legible and the red surface already signals
///     "destructive" (per UX direction).
class _CatalogRow extends StatefulWidget {
  final Food food;
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _CatalogRow({
    required this.food,
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

class _CatalogRowState extends State<_CatalogRow> {
  /// Fixed width for the textual "Add" trailing action. Sized once
  /// so the row does not reflow on a single add.
  static const double _addTrailingWidth = 88;

  /// Square size for the icon-only "Remove" trailing action. Matches
  /// the size of the `CalorieRingCard` edit-targets icon for visual
  /// parity with the rest of the nutrition page.
  static const double _removeTrailingSize = 40;

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cal = calculateCalories(widget.food);
    final macroText =
        '$cal cal · ${widget.food.protein}P · ${widget.food.carbs}C · ${widget.food.fat}F';

    // libraryIdFor walks the user's library cache (O(n) over
    // user-owned foods). The list rebuilds under a ListenableBuilder
    // that listens to both FoodLibraryState and NutritionState, so the
    // answer stays live as the user adds / removes / logs / unlogs.
    // A non-null id means the catalog food is in the library.
    final libraryId = widget.foodLibraryState.libraryIdFor(widget.food.id);

    final row = InkWell(
      onTap: () => _openEdit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // ── Thumbnail: 40×40 image or placeholder (S-006) ────
            // Always rendered (placeholder when null) so the
            // trailing Add / Remove button column does not reflow
            // when an image is added or removed.
            FoodThumbnail(
              key: Key('food_catalog_thumb_${widget.food.id}'),
              imagePath: widget.food.imagePath,
            ),
            const SizedBox(width: 12),
            // ── Name + macros (takes remaining space) ───────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.food.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.colors.textDominant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    macroText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: OmniTheme.colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Add / Remove button (consumes its own tap) ───────
            libraryId != null
                ? _buildRemoveButton(context)
                : _buildAddButton(context),
          ],
        ),
      ),
    );
    return row;
  }

  /// Open the Edit Food screen for this catalog food. Wired to the
  /// row's `onTap` so tapping the row surface (thumbnail, name,
  /// macro text, or padding) edits the food.
  void _openEdit(BuildContext context) {
    EditFoodScreen.push(
      context,
      food: widget.food,
      foodLibraryState: widget.foodLibraryState,
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _addTrailingWidth,
      child: FilledButton(
        key: Key('add_catalog_food_${widget.food.id}'),
        onPressed: _busy ? null : () => _onAdd(context),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
        ),
        child: const Text('Add'),
      ),
    );
  }

  Widget _buildRemoveButton(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _addTrailingWidth,
      height: _removeTrailingSize,
      child: FilledButton(
        key: Key('remove_catalog_food_${widget.food.id}'),
        onPressed: _busy ? null : () => _onRemove(context),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: theme.colorScheme.onError,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
          ),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onError),
      ),
    );
  }

  /// Add the catalog food to the user's library. The screen stays
  /// open; the [ListenableBuilder] in [_FromCatalogTab] rebuilds the
  /// row in its Remove (trashcan) state.
  Future<void> _onAdd(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.foodLibraryState.addCatalogFoodToLibrary(widget.food.id);
      // No pop. The cache update + notifyListeners flips the row.
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add ${widget.food.name}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Remove the library copy of this catalog food. If the food is
  /// currently in today's consumed log, unlog it first so the
  /// day-log stays consistent with the library. The screen stays
  /// open; the row rebuilds in its Add state.
  Future<void> _onRemove(BuildContext context) async {
    if (_busy) return;
    final libraryId = widget.foodLibraryState.libraryIdFor(widget.food.id);
    if (libraryId == null) {
      // Defensive: the row is in the Remove state but no matching
      // library row exists (e.g. the cache is mid-update). Bail out
      // silently — the ListenableBuilder will re-render shortly.
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.nutritionState.isFoodLoggedToday(libraryId)) {
        await widget.nutritionState.unlogFoodToday(libraryId);
      }
      await widget.foodLibraryState.removeFood(libraryId);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove ${widget.food.name}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ─── Tab 2: + New Item ───────────────────────────────────────────────────

/// Form for a new food in the **global managed library** (the
/// catalog). Per the iteration-3 re-scope, every new food the
/// user creates goes into the catalog — the user can then add it
/// to their personal library via the **Add** button on the row in
/// the **Library** tab. Delegates to the shared [FoodForm] widget
// ─── Tab 3: Categories ───────────────────────────────────────────────

/// Manage the food groups that organize the library.
///
/// Each row has an inline `TextField` for renaming the group (the
/// rename is committed when the field is unfocused / the IME action
/// fires) and a trash `IconButton` on the right. Deleting a non-empty
/// group opens a confirmation dialog with a destination dropdown
/// (Ungrouped + every other active group, Ungrouped default); on
/// confirm the group's foods are reassigned and the group is
/// archived. Deleting an empty group is silent (no confirmation).
///
/// A "+ New Category" button at the bottom of the list creates a new
/// group with a default name and focuses the new row's `TextField`.
///
/// The synthetic "Ungrouped" row at the bottom of the list is
/// informational (food count) and cannot be renamed or deleted.
class _CategoriesTab extends StatefulWidget {
  final FoodLibraryState foodLibraryState;

  const _CategoriesTab({required this.foodLibraryState});

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  /// Tracks the `TextEditingController` for each group's name field,
  /// keyed by group id. The list rebuilds under a `ListenableBuilder`
  /// on every notify, so controllers are created lazily and disposed
  /// when the group leaves the list.
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controllerFor(String groupId, String name) {
    final existing = _controllers[groupId];
    if (existing != null) return existing;
    final c = TextEditingController(text: name);
    _controllers[groupId] = c;
    return c;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.foodLibraryState,
      builder: (context, _) {
        final groups = _sorted(widget.foodLibraryState.activeFoodGroups);
        final foods = widget.foodLibraryState.foods;

        // Drop controllers for groups no longer in the active list.
        final activeIds = groups.map((g) => g.id).toSet();
        _controllers.removeWhere((id, _) => !activeIds.contains(id));

        // Count foods per group id (for the ungrouped row and the
        // empty-delete check).
        final foodsByGroup = <String?, int>{};
        for (final f in foods) {
          if (f.isArchived || f.isCatalog) continue;
          foodsByGroup[f.groupId] = (foodsByGroup[f.groupId] ?? 0) + 1;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final g in groups)
                    _CategoryRow(
                      group: g,
                      controller: _controllerFor(g.id, g.name),
                      foodCount: foodsByGroup[g.id] ?? 0,
                      onRename: (newName) =>
                          widget.foodLibraryState.renameFoodGroup(
                            g.id,
                            newName,
                          ),
                      onDelete: () => _confirmAndDeleteGroup(
                        context,
                        g,
                        foodsByGroup[g.id] ?? 0,
                        groups,
                      ),
                    ),
                  _UngroupedRow(foodCount: foodsByGroup[null] ?? 0),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  key: const Key('new_category_button'),
                  icon: const Icon(Icons.add),
                  label: const Text('+ New Category'),
                  onPressed: _createCategory,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Create a new category with a default name. The new row is
  /// added to the bottom of the list; the user taps the row's
  /// `TextField` to rename it (the row does not auto-focus to keep
  /// the keyboard from popping up unexpectedly on the new-category
  /// button tap).
  Future<void> _createCategory() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.foodLibraryState.createFoodGroup('New Category');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create category')),
      );
    }
  }

  /// Confirm a non-empty group delete, then reassign + archive.
  /// Empty groups archive silently.
  Future<void> _confirmAndDeleteGroup(
    BuildContext context,
    FoodGroup group,
    int foodCount,
    List<FoodGroup> allGroups,
  ) async {
    if (foodCount == 0) {
      // Silent no-confirm delete; foodCount is already 0 so the
      // reassignment is a no-op too.
      try {
        await widget.foodLibraryState.deleteFoodGroupReassigningFoods(
          group.id,
          null,
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete ${group.name}')),
        );
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    // The dialog returns the sentinel for cancel; null means
    // "Ungrouped"; a non-null id means "move to that group".
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => _DeleteCategoryDialog(
        groupName: group.name,
        foodCount: foodCount,
        otherGroups: [
          for (final g in allGroups)
            if (g.id != group.id) g,
        ],
      ),
    );
    if (identical(picked, _cancelledSentinel)) return; // user cancelled
    // `picked` is null for "Ungrouped" (legitimate), or a group id.
    final destination = picked;
    try {
      await widget.foodLibraryState.deleteFoodGroupReassigningFoods(
        group.id,
        destination,
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${group.name}')),
      );
    }
  }

  static List<FoodGroup> _sorted(List<FoodGroup> groups) {
    final copy = [...groups];
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }
}

/// A single category row: editable name on the left, trash icon on
/// the right. The TextField commits the rename on `onEditingComplete`
/// (IME action / unfocus) and on `onSubmitted` (Enter key).
class _CategoryRow extends StatelessWidget {
  final FoodGroup group;
  final TextEditingController controller;
  final int foodCount;
  final Future<void> Function(String newName) onRename;
  final Future<void> Function() onDelete;

  const _CategoryRow({
    required this.group,
    required this.controller,
    required this.foodCount,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: Key('category_name_${group.id}'),
              controller: controller,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: 'Category name',
                suffixText: foodCount == 0
                    ? 'empty'
                    : '$foodCount food${foodCount == 1 ? '' : 's'}',
                suffixStyle: theme.textTheme.bodySmall?.copyWith(
                  color: OmniTheme.colors.textMuted,
                ),
              ),
              textInputAction: TextInputAction.done,
              onEditingComplete: () => onRename(controller.text),
              onSubmitted: (_) => onRename(controller.text),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: OmniTheme.buttonIconSize / 2,
            height: OmniTheme.buttonIconSize / 2,
            child: IconButton(
              key: Key('category_delete_${group.id}'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete category',
              onPressed: () => onDelete(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only "Ungrouped" row at the bottom of the Categories tab.
/// No edit / delete affordances — the row is purely informational.
class _UngroupedRow extends StatelessWidget {
  final int foodCount;
  const _UngroupedRow({required this.foodCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.label_off_outlined,
            color: OmniTheme.colors.textMuted,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ungrouped',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: OmniTheme.colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Text(
            '$foodCount food${foodCount == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: OmniTheme.colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog for deleting a non-empty category.
///
/// The destination dropdown defaults to "Ungrouped" (null). Returns
/// the picked destination group id, or `null` for Ungrouped. The
/// `null` return value from the dialog itself means the user
/// cancelled.
class _DeleteCategoryDialog extends StatefulWidget {
  final String groupName;
  final int foodCount;
  final List<FoodGroup> otherGroups;

  const _DeleteCategoryDialog({
    required this.groupName,
    required this.foodCount,
    required this.otherGroups,
  });

  @override
  State<_DeleteCategoryDialog> createState() => _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends State<_DeleteCategoryDialog> {
  /// Default: Ungrouped (null).
  String? _destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete category?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete "${widget.groupName}"?',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.foodCount == 1
                ? '1 food will be moved to:'
                : '${widget.foodCount} foods will be moved to:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: OmniTheme.colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('delete_category_destination'),
            value: _destination,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Destination',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Ungrouped'),
              ),
              for (final g in widget.otherGroups)
                DropdownMenuItem<String?>(
                  value: g.id,
                  child: Text(g.name),
                ),
            ],
            onChanged: (v) => setState(() => _destination = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_cancelledSentinel),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete_category_confirm'),
          onPressed: () => Navigator.of(context).pop(_destination),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
            ),
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
