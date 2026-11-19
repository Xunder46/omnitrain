import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/foods_i_eat_order.dart';
import '../../core/utils/food_helpers.dart';
import '../../data/models/models.dart';
import '../../state/food_library_state.dart';
import '../../state/nutrition_state.dart';
import '../../state/nutrition/nutrition_primer_state.dart';
import '../../core/navigation/navigation.dart';
import '../../widgets/buttons/omni_utility_button.dart';
import '../../widgets/common/omni_empty_state.dart';
import '../../widgets/feedback/omni_message.dart';
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
  /// True once the screen has shown its content. Later reloads (coming back
  /// from Daily Targets) keep the content on screen, so the scroll position and
  /// any amount typed in a food row survive (plan 265).
  bool _hasShownContent = false;

  @override
  void initState() {
    super.initState();
    // Every visit starts on today (plan 247); silent: the first build follows.
    widget.nutritionState.resetDayView();
    // Load today's nutrition target, today's consumed foods, today's
    // water volume, and the food library in parallel. All four are
    // independent — each is fired and not awaited so the others are
    // not gated on it.
    _loadTodayTarget();
    _loadConsumedToday();
    _loadWaterForToday();
    _loadLibrary();
    // The one-shot primer rises over this screen the first time it opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.nutritionPrimerState.shouldShowPrimer) {
        _showPrimer(markSeen: true);
      }
    });
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

  void _showPreviousDay() =>
      unawaited(widget.nutritionState.shiftViewedDay(-1));

  void _showNextDay() => unawaited(widget.nutritionState.shiftViewedDay(1));

  /// `TODAY`, `YESTERDAY`, then the short date uppercased, with the year when
  /// it is not [today]'s year (plan 247, D-24708).
  static String dayTitle(DateTime day, DateTime today) {
    final d = DateTime(day.year, day.month, day.day);
    final t = DateTime(today.year, today.month, today.day);
    if (d == t) return 'TODAY';
    if (d == DateTime(t.year, t.month, t.day - 1)) return 'YESTERDAY';
    final short = OmniDateUtils.formatShort(d).toUpperCase();
    return d.year == t.year ? short : '$short, ${d.year}';
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

  /// Show the primer sheet. On first open ([markSeen] true) the seen flag
  /// is marked when the sheet is dismissed; the header "?" reopens it with
  /// [markSeen] false, which never changes the flag.
  Future<void> _showPrimer({required bool markSeen}) async {
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
            onDismiss: markSeen
                ? () => unawaited(widget.nutritionPrimerState.markSeen())
                : null,
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
            onPressed: () => _showPrimer(markSeen: false),
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
          if (widget.nutritionState.isLoading && !_hasShownContent) {
            return const Center(child: CircularProgressIndicator());
          }
          _hasShownContent = true;

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
                    leading: _DayArrow(
                      buttonKey: const Key('nutrition_day_prev'),
                      icon: Icons.chevron_left,
                      tooltip: 'Previous day',
                      onPressed: _showPreviousDay,
                    ),
                    trailing: _DayArrow(
                      buttonKey: const Key('nutrition_day_next'),
                      icon: Icons.chevron_right,
                      tooltip: 'Next day',
                      onPressed: widget.nutritionState.canViewNextDay
                          ? _showNextDay
                          : null,
                    ),
                    titleMinWidth: 120,
                    title: dayTitle(
                      DateTime.fromMillisecondsSinceEpoch(
                        widget.nutritionState.viewedDayMs,
                      ),
                      DateTime.fromMillisecondsSinceEpoch(
                        widget.nutritionState.todayDayMs,
                      ),
                    ),
                    actions: [
                      // The target is today's: no button on an earlier day.
                      if (widget.nutritionState.isViewingToday)
                        Builder(
                          builder: (context) {
                            final target =
                                widget.nutritionState.nutritionTarget;
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
                  ListenableBuilder(
                    listenable: widget.foodLibraryState,
                    builder: (context, _) => CalorieRingCard(
                      nutritionState: widget.nutritionState,
                      onEditTap: _navigateToTargets,
                      emptyHint:
                          !widget.foodLibraryState.isLoadingFoods &&
                              widget.foodLibraryState.foods.isEmpty
                          ? 'Pick your foods to get started'
                          : null,
                    ),
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
                    // An earlier day's rows are built only once its reads have
                    // landed, and keyed by the day, so every row starts from
                    // that day's amounts (a row reads its amount once).
                    child: widget.nutritionState.isViewedDayLoaded
                        ? KeyedSubtree(
                            key: ValueKey(widget.nutritionState.viewedDayMs),
                            child: _FoodLibraryBrowseSection(
                              foodLibraryState: widget.foodLibraryState,
                              nutritionState: widget.nutritionState,
                              onChooseFoods: _openManageLibrary,
                            ),
                          )
                        : const SizedBox(
                            height: 96,
                            child: Center(child: CircularProgressIndicator()),
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

/// One day-step arrow of the header (plan 247): 48 dp tap target, muted when
/// disabled.
class _DayArrow extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _DayArrow({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      key: buttonKey,
      icon: Icon(
        icon,
        size: 24,
        color: onPressed == null
            ? OmniTheme.colors.textDisabled
            : theme.colorScheme.primary,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
        ),
      ),
    );
  }
}

class _FoodLibraryBrowseSection extends StatefulWidget {
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;
  final VoidCallback onChooseFoods;

  const _FoodLibraryBrowseSection({
    required this.foodLibraryState,
    required this.nutritionState,
    required this.onChooseFoods,
  });

  @override
  State<_FoodLibraryBrowseSection> createState() =>
      _FoodLibraryBrowseSectionState();
}

class _FoodLibraryBrowseSectionState extends State<_FoodLibraryBrowseSection> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Plan 256: the catalog cache is what the search offers; load it once when
    // it is empty (the same call `AddFoodScreen` makes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.foodLibraryState.catalogFoods.isEmpty) {
        unawaited(widget.foodLibraryState.loadCatalogFoods());
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: const Key('nutrition_search_field'),
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search foods',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  key: const Key('nutrition_search_clear'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: _clearSearch,
                ),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  /// Puts a catalog food into Foods I Eat and logs it on the day the screen
  /// shows, with its first portion (plan 256 D-25605).
  Future<void> _addAndLog(Food catalogFood) async {
    if (_adding) return;
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    setState(() => _adding = true);
    var ok = false;
    try {
      final libraryId = await widget.foodLibraryState.addCatalogFoodToLibrary(
        catalogFood.id,
      );
      Food? food;
      for (final f in widget.foodLibraryState.foods) {
        if (f.id == libraryId) {
          food = f;
          break;
        }
      }
      if (food != null) {
        final amount = food.unitType == FoodUnitType.grams
            ? food.referenceAmount
            : 1.0;
        final id = await widget.nutritionState.logConsumedFoodViewed(
          food,
          amount,
        );
        ok = id != null;
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _adding = false);
    if (!ok) {
      OmniMessage.errorOn(
        messenger,
        theme,
        'Could not add the food. Try again.',
      );
      return;
    }
    _clearSearch();
    OmniMessage.showOn(messenger, theme, 'Added to Foods I Eat and logged');
  }

  /// What the typed query finds (plan 256 D-25603): the matching Foods I Eat
  /// under their headings, then the catalog foods that match and are not in
  /// Foods I Eat yet.
  List<Widget> _searchResults(List<Food> foods, String query) {
    final foodLibraryState = widget.foodLibraryState;
    final mine = [
      for (final f in foods)
        if (f.name.toLowerCase().contains(query)) f,
    ];
    final catalog = [
      for (final f in foodLibraryState.catalogFoods)
        if (!f.isArchived &&
            f.name.toLowerCase().contains(query) &&
            !foodLibraryState.isInLibrary(f.id))
          f,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final shownCatalog = catalog.take(20).toList();
    if (mine.isEmpty && shownCatalog.isEmpty) {
      return [
        OmniEmptyState(
          icon: Icons.search_off,
          title: 'No foods match "${_query.trim()}"',
          hint: 'Try a different search.',
        ),
      ];
    }
    final sections = foodsIEatSections(
      foods: mine,
      groups: foodLibraryState.activeFoodGroups,
    );
    final theme = Theme.of(context);
    return [
      for (final section in sections)
        _GroupBlock(
          groupName: section.title,
          foods: section.foods,
          foodLibraryState: foodLibraryState,
          nutritionState: widget.nutritionState,
        ),
      if (shownCatalog.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From the catalog',
                key: const Key('nutrition_search_catalog_heading'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: OmniTheme.titleLetterSpacing,
                  color: OmniTheme.colors.textDominant,
                ),
              ),
              const SizedBox(height: 8),
              for (final f in shownCatalog)
                _CatalogMatchRow(
                  food: f,
                  busy: _adding,
                  onAddAndLog: () => unawaited(_addAndLog(f)),
                ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final foodLibraryState = widget.foodLibraryState;
    final nutritionState = widget.nutritionState;
    return ListenableBuilder(
      listenable: Listenable.merge([foodLibraryState, nutritionState]),
      builder: (context, _) {
        if (foodLibraryState.isLoadingGroups ||
            foodLibraryState.isLoadingFoods) {
          return const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final foods = foodLibraryState.foods;

        // A typed query replaces the list with what it finds (plan 256).
        final query = _query.trim().toLowerCase();
        if (query.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_searchField(), ..._searchResults(foods, query)],
          );
        }

        // Foods logged on the viewed day that the library no longer holds. A
        // logged row carries its own name and numbers, so each one can be
        // shown and edited (plan 247).
        final libraryIds = {for (final f in foods) f.id};
        final removed = [
          for (final c in nutritionState.viewedConsumed)
            if (c.sourceFoodId == null || !libraryIds.contains(c.sourceFoodId))
              c,
        ]..sort((a, b) => a.loggedAtMs.compareTo(b.loggedAtMs));

        // Empty state: show whenever the user's Foods I Eat list is empty and
        // no removed foods are logged on the viewed day, regardless of category
        // count. The Choose foods button leads to the picker (the Library) via
        // [onChooseFoods]. The search box above it lets a new user find and
        // log a catalog food without opening the picker (plan 256).
        if (foods.isEmpty && removed.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchField(),
              OmniEmptyState(
                icon: Icons.restaurant_menu_outlined,
                title: 'Pick the foods you eat',
                hint:
                    'Choose them from the library, then tick them off each day.',
                action: FilledButton(
                  key: const Key('foods_i_eat_choose_button'),
                  onPressed: widget.onChooseFoods,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                  ),
                  child: const Text('Choose foods'),
                ),
              ),
            ],
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
            _searchField(),
            for (final section in sections)
              _GroupBlock(
                groupName: section.title,
                foods: section.foods,
                foodLibraryState: foodLibraryState,
                nutritionState: nutritionState,
              ),
            if (removed.isNotEmpty)
              _GroupBlock(
                groupName: 'No longer in Foods I Eat',
                foods: [for (final c in removed) foodFromConsumedSnapshot(c)],
                removedRows: removed,
                foodLibraryState: foodLibraryState,
                nutritionState: nutritionState,
              ),
          ],
        );
      },
    );
  }
}

/// One catalog food a search found: its name, its calories per portion and an
/// Add & log button (plan 256 D-25604).
class _CatalogMatchRow extends StatelessWidget {
  final Food food;
  final bool busy;
  final VoidCallback onAddAndLog;

  const _CatalogMatchRow({
    required this.food,
    required this.busy,
    required this.onAddAndLog,
  });

  String get _caption {
    final cal = calculateCalories(food);
    if (food.unitType != FoodUnitType.grams) return '$cal cal each';
    final amount = food.referenceAmount;
    final shown = amount == amount.truncateToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(1);
    return '$cal cal per $shown ${foodUnitCaption(food)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  food.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: OmniTheme.colors.textDominant,
                  ),
                ),
                Text(
                  _caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OmniUtilityButton(
            buttonKey: Key('nutrition_search_add_${food.id}'),
            label: 'Add & log',
            icon: Icons.add,
            onPressed: busy ? null : onAddAndLog,
          ),
        ],
      ),
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

  /// Parallel to [foods] for the removed-foods section; null for a library group.
  final List<ConsumedFood>? removedRows;
  final FoodLibraryState foodLibraryState;
  final NutritionState nutritionState;

  const _GroupBlock({
    required this.groupName,
    required this.foods,
    this.removedRows,
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
              key: removedRows == null ? null : ValueKey(removedRows![i].id),
              food: foods[i],
              removedRow: removedRows?[i],
              foodLibraryState: foodLibraryState,
              nutritionState: nutritionState,
            ),
          ],
        ],
      ),
    );
  }
}
