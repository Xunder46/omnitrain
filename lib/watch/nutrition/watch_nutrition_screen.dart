/// The Wear OS quick-log surface: the foods the user eats, one portion, one log.
///
/// Plan: `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
/// scenarios S-001, S-004 and S-006.
///
/// There is no search, no catalog and no macro editing here: the phone owns all
/// of that, and this screen owns the two-second log of a routine meal. Rotary
/// input is primary — a turn arrives as a scroll or a drag, both of which land
/// in the same accumulation — and the portion row's own controls are the touch
/// fallback. Nothing counts anything down and nothing is cached: the list comes
/// from the synced catalog and the portion is restored on every rebuild, so a
/// screen that was off comes back showing the truth.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../widgets/watch_controls.dart';
import 'watch_food_catalog.dart';
import 'watch_nutrition_state.dart';

class WatchNutritionScreen extends StatefulWidget {
  const WatchNutritionScreen({super.key, required this.state});

  final WatchNutritionState state;

  /// The primary action, and the two touch controls beside the portion. Rotary
  /// input needs no key: it lands wherever the user is looking.
  static const Key logKey = Key('watch_nutrition_log');
  static const Key stepUpKey = Key('watch_nutrition_step_up');
  static const Key stepDownKey = Key('watch_nutrition_step_down');

  /// Wrist-scale layout — the phone's spacing tokens are sized for a full-width
  /// screen, so the watch carries its own values.
  static const double surfaceInset = 8;
  static const double surfaceInsetCompact = 4;
  static const double rowGap = 4;

  @override
  State<WatchNutritionScreen> createState() => _WatchNutritionScreenState();
}

class _WatchNutritionScreenState extends State<WatchNutritionScreen> {
  /// Turn accumulated, waiting to add up to a whole detent. Short travel is
  /// carried to the next event rather than rounding the portion off its step.
  final WatchRotaryTurn _turn = WatchRotaryTurn();

  WatchNutritionState get _state => widget.state;

  /// A turn of the rotary input: [travel] is signed movement in points, and a
  /// turn away from the wrist raises the portion.
  void _rotate(double travel) {
    final detents = _turn.detentsFor(travel);
    if (detents == 0) return;

    setState(() => _state.stepPortion(detents));
  }

  Future<void> _log() async {
    if (_state.selected == null) return;
    await _state.logSelected();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final foods = _state.foods;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WatchNutritionScreen.surfaceInset,
            vertical: WatchNutritionScreen.surfaceInsetCompact,
          ),
          child: foods.isEmpty ? _nothingSynced() : _quickLog(foods),
        ),
      ),
    );
  }

  /// With nothing synced there is no food to log and no search to offer: the
  /// phone owns the list, and saying so beats an empty screen.
  Widget _nothingSynced() {
    return Center(
      child: Text(
        'No foods yet. Sync with your phone to get them.',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _quickLog(List<WatchFood> foods) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: foods.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: WatchNutritionScreen.rowGap),
            itemBuilder: (context, index) {
              final food = foods[index];
              final isSelected = food.foodId == _state.selectedFoodId;
              return _FoodRow(
                label: food.name,
                calories: food.caloriesAt(
                  isSelected ? _state.servings : food.defaultServings,
                ),
                isSelected: isSelected,
                onPressed: () => setState(() => _state.select(food.foodId)),
              );
            },
          ),
        ),
        if (_state.selected != null) ...[
          const SizedBox(height: WatchNutritionScreen.rowGap),
          _portionRow(),
          const SizedBox(height: WatchNutritionScreen.rowGap),
          _logButton(),
        ],
        if (_state.confirmation != null)
          Padding(
            padding: const EdgeInsets.only(top: WatchNutritionScreen.rowGap),
            child: Text(
              _state.confirmation!,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// The portion row: the count, what it means in the food's own unit, the two
  /// touch controls, and both ways to move it with the crown.
  Widget _portionRow() {
    final styles = Theme.of(context).textTheme;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _rotate(event.scrollDelta.dy);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => _rotate(details.delta.dy),
        child: Row(
          children: [
            _stepButton(
              key: WatchNutritionScreen.stepDownKey,
              icon: Icons.remove,
              label: 'Less food',
              onPressed: () => setState(() => _state.stepPortion(-1)),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_state.portionLabel, style: styles.labelMedium),
                  Text('${_state.calories} kcal', style: styles.labelSmall),
                ],
              ),
            ),
            _stepButton(
              key: WatchNutritionScreen.stepUpKey,
              icon: Icons.add,
              label: 'More food',
              onPressed: () => setState(() => _state.stepPortion(1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) =>
      WatchStepButton(key: key, icon: icon, label: label, onPressed: onPressed);

  /// The wrist's primary action: full width, at the token height, with an
  /// explicit shape rather than whatever Material 3 defaults to.
  Widget _logButton() => FilledButton(
    key: WatchNutritionScreen.logKey,
    style: ButtonStyle(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
        ),
      ),
      minimumSize: WidgetStateProperty.all(
        const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
      ),
    ),
    onPressed: _log,
    child: const Text('Log', maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

/// One food in the wrist's list. Selected is stated with a border rather than a
/// colour alone, so the state survives the theme's contrast rules.
class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.label,
    required this.calories,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final int calories;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : OmniTheme.colors.divider,
            ),
          ),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          Text('$calories', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
