// filepath: lib/features/nutrition/widgets/water_tracker_control.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/constants/water_constants.dart';

/// A compact, tap-only +/− stepper for the day's water volume. Lives in
/// the bottom-right of the calorie-ring card, horizontally opposite the
/// sodium readout in the bottom-left.
///
/// Composition (left-to-right):
///   - A vertical pair: glass icon (`Icons.local_drink_outlined`) on
///     top, `250 ml` annotation below. Stacking them vertically instead
///     of laying them out horizontally keeps the row's total width
///     tight enough to fit alongside the sodium chip on the same card
///     row. The annotation is still sourced from the canonical
///     [kWaterGlassMl] constant; if the per-glass amount ever changes,
///     the displayed text follows it.
///   - A minus `IconButton` (disabled at 0).
///   - A whole-number glass count, derived from the stored ml at the
///     display boundary (`volumeMl ~/ kWaterGlassMl`). The count is
///     **never** a volume figure — the icon carries the unit.
///   - A plus `IconButton`.
///
/// **Pure presentation**: no repository access, no business logic, no
/// keyboard / text-entry field. All buttons follow the explicit
/// `shape:` + `OmniTheme.buttonIconRadius` contract; all colors come
/// from `Theme.colorScheme`.
///
/// The widget is dumb about persistence — the parent screen owns the
/// `NutritionState` and is responsible for invoking its
/// `incrementWaterForDate` / `decrementWaterForDate` on each tap.
class WaterTrackerControl extends StatelessWidget {
  /// Current glass count for the day. Always `>= 0`. The widget
  /// does not accept a typed amount — the count is the only
  /// signal the parent can pass in.
  final int glasses;

  /// Tap handler for the plus button. The widget does not invoke
  /// the state directly; the parent owns the persistence wiring.
  final VoidCallback onIncrement;

  /// Tap handler for the minus button. The widget also passes
  /// `null` to the `IconButton.onPressed` (disabled state) when
  /// [glasses] is `0` so the visual and the no-op agree.
  final VoidCallback onDecrement;

  const WaterTrackerControl({
    super.key,
    required this.glasses,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colors;

    return Semantics(
      container: true,
      label: 'Water tracker: $glasses glasses of ${kWaterGlassMl}ml',
      child: Row(
        key: const Key('water_tracker_control'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glass icon stacked above the `250 ml` annotation. The icon
          // is the primary visual; the annotation is a caption-style
          // hint so the per-glass amount is decoded at a glance.
          // Vertical stacking keeps the row's total width tight —
          // ~22 dp narrower than the horizontal layout — so the
          // control fits alongside the sodium chip on the same card
          // row without crowding.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // `Icons.local_drink_outlined` reads as a tumbler / cup
              // with water and pairs cleanly with the dark-theme card
              // chrome.
              Icon(
                Icons.local_drink_outlined,
                size: 18,
                color: themeColors.textMuted,
              ),
              const SizedBox(height: 1),
              // The "250 ml" annotation. Sourced from `kWaterGlassMl`
              // so a future per-glass amount change propagates here.
              Text(
                '$kWaterGlassMl ml',
                key: const Key('water_tracker_label'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: themeColors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          // Minus button. Explicit shape + theme radius token.
          // Disabled (`onPressed: null`) at 0 glasses — the no-op
          // contract is enforced visually and programmatically.
          IconButton(
            key: const Key('water_tracker_minus'),
            onPressed: glasses <= 0 ? null : onDecrement,
            icon: Icon(
              Icons.remove,
              size: 18,
              color: glasses <= 0
                  ? themeColors.textDisabled
                  : theme.colorScheme.primary,
            ),
            tooltip: 'Remove one glass',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Whole glass count. Wider tabular-figures box so the
          // value doesn't reflow as the count grows from 1 to 2 to
          // 3 digits.
          Container(
            key: const Key('water_tracker_count'),
            constraints: const BoxConstraints(minWidth: 24),
            alignment: Alignment.center,
            child: Text(
              '$glasses',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: themeColors.textDominant,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Plus button. Mirror of the minus button — explicit shape +
          // theme radius token.
          IconButton(
            key: const Key('water_tracker_plus'),
            onPressed: onIncrement,
            icon: Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
            tooltip: 'Add one glass',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
