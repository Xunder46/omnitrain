import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../state/nutrition/nutrition_primer_state.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import 'add_food_screen.dart';
import 'widgets/calorie_ring_card.dart';
import 'widgets/log_food_row.dart';
import 'widgets/nutrition_primer_sheet.dart';
import 'nutrition_target_screen.dart';

class NutritionScreen extends StatefulWidget {
  final NutritionState nutritionState;
  final FoodLibraryState foodLibraryState;
  final NutritionPrimerState nutritionPrimerState;

  const NutritionScreen({
    super.key,
    required this.nutritionState,
    required this.foodLibraryState,
    required this.nutritionPrimerState,
  });

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  @override
  void initState() {
    super.initState();
    // Load today's nutrition target, today's consumed foods, today's
    // water volume, and the food library in parallel. All four are
    // independent — each is fired and not awaited so the others are
    // not gated on it.
    _loadTodayTarget();
    _loadConsumedToday();
    _loadWaterForToday();
    _loadLibrary();
  }

  Future<void> _loadTodayTarget() async {
    await widget.nutritionState.loadNutritionTarget();
  }

  Future<void> _loadConsumedToday() async {
    await widget.nutritionState.loadConsumedToday();
  }

  Future<void> _loadWaterForToday() async {
    await widget.nutritionState.loadWaterForToday();
  }

  Future<void> _loadLibrary() async {
    await Future.wait([
      widget.foodLibraryState.loadFoodGroups(),
      widget.foodLibraryState.loadFoods(),
    ]);
  }

  void _navigateToTargets() {
    OmniNavigator.push<void>(
      context,
      (context) => NutritionTargetScreen(nutritionState: widget.nutritionState),
    ).then((_) {
      // Reload targets AND today's consumed log AND today's water
      // volume when returning from the edit screen. The target is
      // what the ring renders; the consumed log and water volume are
      // unaffected by target edits, but loading them here keeps the
      // reload path symmetric (one source of truth for "what changed
      // while we were away"). The widget tree will rebuild through
      // `ListenableBuilder` on each notification.
      _loadTodayTarget();
      _loadConsumedToday();
      _loadWaterForToday();
    });
  }

  /// Pushes the Manage Food Library screen. The food library is already loaded
  /// by [initState]; the Manage Food Library screen itself lazily loads the
  /// catalog cache on first paint. No explicit refresh is needed
  /// on return — every add / remove fires a `notifyListeners` on
  /// [FoodLibraryState] (via `addCatalogFoodToLibrary` /
  /// `createCustomFood` / `removeFood`) so the browse card updates
  /// immediately.
  void _openManageLibrary() {
    OmniNavigator.push<void>(
      context,
      (context) => AddFoodScreen(
        nutritionState: widget.nutritionState,
        foodLibraryState: widget.foodLibraryState,
      ),
    );
  }

  /// Reopen the one-shot primer sheet at any time. The seen state is
  /// NOT mutated — the primer can be reopened as many times as the
  /// user wants (it just won't auto-show on the next home-strip tap
  /// unless the seen flag is still false). Sheet host: this method.
  Future<void> _reopenPrimer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: NutritionPrimerSheet(
            // onDismiss intentionally null — reopening never marks
            // seen, so the next home-strip tap can still auto-show
            // if the seen flag is still false. The header "?" is the
            // way to read the primer without committing.
            onDismiss: null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Nutrition'),
        // Persistent "?" control — visible at all times so the user
        // can reopen the primer at any moment. The icon button does
        // not mutate the seen state; it just shows the sheet.
        actions: [
          IconButton(
            key: const Key('nutrition_primer_help'),
            icon: Icon(
              Icons.help_outline,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            tooltip: 'About Daily Nutrition',
            onPressed: _reopenPrimer,
          ),
        ],
      ),
      // The bottom "Manage Food Library" CTA was removed: it pushed the
      // last foods of the long library list off-screen. The new
      // affordance is a pencil icon in the top-right of the Food
      // Library card header (see below). The Daily Targets summary
      // card is also gone — the Calorie Ring already shows
      // consumed/target; the standalone card was redundant.
      body: ListenableBuilder(
        listenable: widget.nutritionState,
        builder: (context, child) {
          if (widget.nutritionState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calorie ring header with edit icon — now an
                  // OmniCardHeader per the unified card-and-header
                  // plan. The edit icon lives in the actions slot
                  // (D-2: controls pertinent to a card live in its
                  // header). The previous `SizedBox(height: 12)` gap
                  // is replaced by the header's built-in 8 dp bottom
                  // padding.
                  OmniCardHeader(
                    title: 'TODAY',
                    actions: [
                      IconButton(
                        key: const Key('edit_targets_icon'),
                        icon: Icon(
                          Icons.tune,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        tooltip: 'Edit targets',
                        onPressed: _navigateToTargets,
                      ),
                    ],
                  ),
                  CalorieRingCard(
                    nutritionState: widget.nutritionState,
                    onEditTap: _navigateToTargets,
                  ),
                  const SizedBox(height: 24),
                  // Food Library header with edit icon — OmniCardHeader
                  // above an OmniSurface (the foods card). The food
                  // library card used to be a raw Flutter `Card()`; it
                  // now shares the same surface chrome as every other
                  // outlined card in the app.
                  OmniCardHeader(
                    title: 'Foods I Eat',
                    actions: [
                      IconButton(
                        key: const Key('food_library_manage_pencil'),
                        icon: Icon(
                          Icons.edit,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        tooltip: 'Manage food library',
                        onPressed: _openManageLibrary,
                      ),
                    ],
                  ),
                  OmniSurface(
                    padding: const EdgeInsets.all(16),
                    child: _FoodLibraryBrowseSection(
                      foodLibraryState: widget.foodLibraryState,
                      nutritionState: widget.nutritionState,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Read-only, scrollable, grouped list of foods for the Food Library card.
///Each row is a [LogFoodRow] — the food library card now doubles as
/// the "log a food as consumed" affordance. The per-row checkbox +
/// amount input live in [LogFoodRow]; this section is responsible for
/// the grouped list layout only.
class _FoodLibraryBrowseSection extends StatelessWidget {
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _FoodLibraryBrowseSection({
    required this.foodLibraryState,
    required this.nutritionState,
  });

  /// Sort groups alphabetically (case-insensitive). Pure helper so it can
  /// be reasoned about (and refactored) independently of build.
  static List<FoodGroup> _sortedGroups(List<FoodGroup> groups) =>
      _sortedByName<FoodGroup>(groups, (g) => g.name);

  /// Sort foods alphabetically (case-insensitive).
  static List<Food> _sortedFoods(List<Food> foods) =>
      _sortedByName<Food>(foods, (f) => f.name);

  /// Generic case-insensitive alphabetical sort by a `name` accessor. Pure;
  /// does not mutate the input list.
  static List<T> _sortedByName<T>(List<T> items, String Function(T) nameOf) {
    final copy = [...items];
    copy.sort(
      (a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()),
    );
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: foodLibraryState,
      builder: (context, _) {
        if (foodLibraryState.isLoadingGroups ||
            foodLibraryState.isLoadingFoods) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final groups = _sortedGroups(foodLibraryState.foodGroups);
        final foods = foodLibraryState.foods;

        // Empty state: show whenever the user's Foods I Eat list is empty,
        // regardless of category count. The presence of 0, 9, or any number of
        // default/custom categories has no effect on this condition.
        if (foods.isEmpty) {
          return SizedBox(
            height: 48,
            child: Center(
              child: Text(
                'Your Foods I Eat list is empty. Tap the pencil to add foods.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: OmniTheme.colors.textMuted,
                ),
              ),
            ),
          );
        }

        // Bucket foods by FoodGroup id (D-1 / S-042). The category
        // label is the FoodGroup's name from the live cache; null
        // groupId maps to the synthetic "Ungrouped" section. The
        // section header mirrors the Groups tab exactly — the
        // rename propagates here on the next notifyListeners.
        final Map<String, List<Food>> byGroup = {};
        for (final f in foods) {
          byGroup.putIfAbsent(f.groupId ?? '', () => []).add(f);
        }

        // Sort: groups alpha (case-insensitive) by name, "Ungrouped"
        // last. The empty key is our sentinel for Ungrouped.
        final groupNameById = <String, String>{
          for (final g in groups) g.id: g.name,
        };
        String labelFor(String groupId) {
          if (groupId.isEmpty) return 'Ungrouped';
          return groupNameById[groupId] ?? 'Ungrouped';
        }

        final orderedGroupIds = <String>[];
        for (final g in groups) {
          if (byGroup.containsKey(g.id)) orderedGroupIds.add(g.id);
        }
        if (byGroup.containsKey('')) orderedGroupIds.add('');

        final List<Widget> children = [];
        for (final groupId in orderedGroupIds) {
          final groupFoods = _sortedFoods(byGroup[groupId] ?? const <Food>[]);
          children.add(
            _GroupBlock(
              groupName: labelFor(groupId),
              foods: groupFoods,
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      },
    );
  }
}

/// Renders a single category header and its food rows.
/// Category is the FoodGroup name resolved through the live state
/// cache; "Ungrouped" is the synthetic section for foods with
/// `groupId == null` or whose group id is no longer in the active
/// list (e.g. archived).
class _GroupBlock extends StatelessWidget {
  final String groupName;
  final List<Food> foods;
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _GroupBlock({
    required this.groupName,
    required this.foods,
    required this.foodLibraryState,
    required this.nutritionState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: OmniTheme.titleLetterSpacing,
              color: themeColors.textDominant,
            ),
          ),
          const SizedBox(height: 8),
          // Iteration 1 (S-006): 1 px hairline divider between
          // rows within a group, no divider above the first row
          // and no divider after the last row. The collection-if
          // + spread builds [row, divider, row, divider, row]
          // without trailing chrome. The `Key` is the per-group
          // divider index so tests can assert presence/absence
          // by index.
          for (var i = 0; i < foods.length; i++) ...[
            if (i > 0)
              Divider(
                key: Key('group_${groupName}_divider_$i'),
                color: themeColors.divider,
                height: 1,
                thickness: 1,
              ),
            LogFoodRow(
              food: foods[i],
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ],
        ],
      ),
    );
  }
}
