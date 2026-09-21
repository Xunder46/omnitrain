import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/foods_i_eat_order.dart';
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
      // `includeArchived: true` so the cache matches what its
      // `foodGroups` getter documents (active + archived). The
      // food editor needs the archived rows to label a food filed
      // under a deleted category with the category's NAME rather
      // than its raw internal id; every display path filters with
      // `activeFoodGroups`.
      widget.foodLibraryState.loadFoodGroups(includeArchived: true),
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
                  // Calorie ring header with edit control — now an
                  // OmniCardHeader per the unified card-and-header
                  // plan. The control lives in the actions slot
                  // (D-2: controls pertinent to a card live in its
                  // header). The previous `SizedBox(height: 12)` gap
                  // is replaced by the header's built-in 8 dp bottom
                  // padding.
                  //
                  // PR 3 / Item 5 of the 2026-07-27 feedback pack
                  // replaces the icon-only `Icons.tune` gear with a
                  // labelled `OutlinedButton.icon` utility variant
                  // whose text reflects the saved-target state:
                  //   - No target saved    → "Set target"
                  //   - Target already set → "Change target"
                  // The button follows the OmniTheme utility-button
                  // shape rule (buttonUtilityRadius, explicit
                  // `shape:` override) and uses
                  // `theme.colorScheme.primary` for the border +
                  // label colour. The tap target still opens the
                  // same `NutritionTargetScreen` via
                  // `_navigateToTargets()`.
                  OmniCardHeader(
                    title: 'TODAY',
                    actions: [
                      Builder(
                        builder: (context) {
                          final target = widget.nutritionState.nutritionTarget;
                          final hasTarget =
                              target != null && target.calories > 0;
                          return OutlinedButton.icon(
                            key: const Key('nutrition_target_button'),
                            icon: Icon(
                              Icons.tune,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            label: Text(
                              hasTarget ? 'Change target' : 'Set target',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  OmniTheme.buttonUtilityRadius,
                                ),
                              ),
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _navigateToTargets,
                          );
                        },
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

        // The list order is the phone's own rule, in one place:
        // `foodsIEatSections` is the function the wrist's synced list is
        // checked against (S-003 of the watch nutrition plan).
        final sections = foodsIEatSections(
          foods: foods,
          groups: foodLibraryState.activeFoodGroups,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final section in sections)
              _GroupBlock(
                groupName: section.title,
                foods: section.foods,
                foodLibraryState: foodLibraryState,
                nutritionState: nutritionState,
              ),
          ],
        );
      },
    );
  }
}

/// Renders a single category header and its food rows.
/// Category is the FoodGroup name resolved through the live state
/// cache; "Uncategorized" is the synthetic section for foods with
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
