// filepath: lib/features/nutrition/widgets/water_tracker_control.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/constants/water_constants.dart';
import '../../../core/utils/unit_formatter.dart';

/// A compact, tap-only +/− stepper for the day's water. Lives in the
/// bottom-right of the calorie-ring card, horizontally opposite the
/// sodium readout in the bottom-left.
///
/// Composition (left-to-right):
///   - A vertical pair: glass icon (`Icons.local_drink_outlined`) on
///     top, the per-tap step below (`250 ml` or `8 oz`, from
///     `UnitFormatter.waterStepLabel`). Stacking them vertically keeps
///     the row's total width tight enough to fit alongside the sodium
///     chip on the same card row.
///   - A minus `IconButton` (disabled at 0 ml).
///   - The day's **total** in the user's volume unit (`750 ml`,
///     `1.5 L`, `48 oz`, from `UnitFormatter.formatWaterTotal`).
///   - A plus `IconButton`.
///
/// **Pure presentation**: no repository access, no business logic, no
/// keyboard / text-entry field. The control takes the stored volume in
/// milliliters and the volume unit; all conversion and wording go
/// through `UnitFormatter`. All buttons follow the explicit
/// `shape:` + `OmniTheme.buttonIconRadius` contract; all colors come
/// from `Theme.colorScheme`.
///
/// The widget is dumb about persistence — the parent screen owns the
/// `NutritionState` and is responsible for invoking its
/// `incrementWaterForDate` / `decrementWaterForDate` on each tap.
class WaterTrackerControl extends StatelessWidget {
  /// The day's stored water in milliliters. Always `>= 0`.
  final int volumeMl;

  /// The user's volume unit (`ml` or `floz`), as `NutritionState.waterVolumeUnit`.
  final String volumeUnit;

  /// Tap handler for the plus button. The widget does not invoke
  /// the state directly; the parent owns the persistence wiring.
  final VoidCallback onIncrement;

  /// Tap handler for the minus button. The widget also passes
  /// `null` to the `IconButton.onPressed` (disabled state) when
  /// [volumeMl] is `0` so the visual and the no-op agree.
  final VoidCallback onDecrement;

  const WaterTrackerControl({
    super.key,
    required this.volumeMl,
    required this.volumeUnit,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colors;
    final stepSpoken = UnitFormatter.formatWaterSpoken(
      waterStepMlFor(volumeUnit),
      volumeUnit,
    );

    return Semantics(
      container: true,
      label:
          'Water today: ${UnitFormatter.formatWaterSpoken(volumeMl, volumeUnit)}',
      child: Row(
        key: const Key('water_tracker_control'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glass icon stacked above the per-tap step. The icon is the
          // primary visual; the caption tells the user what one tap adds.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.local_drink_outlined,
                size: 18,
                color: themeColors.textMuted,
              ),
              const SizedBox(height: 1),
              Text(
                UnitFormatter.waterStepLabel(volumeUnit),
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
          // Disabled (`onPressed: null`) at 0 ml.
          IconButton(
            key: const Key('water_tracker_minus'),
            onPressed: volumeMl <= 0 ? null : onDecrement,
            icon: Icon(
              Icons.remove,
              size: 18,
              color: volumeMl <= 0
                  ? themeColors.textDisabled
                  : theme.colorScheme.primary,
            ),
            tooltip: 'Remove $stepSpoken',
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
          // The day's total. Tabular figures so the digits do not jitter;
          // never wraps (a long total such as `10.5 L` stays on one line).
          Container(
            key: const Key('water_tracker_count'),
            constraints: const BoxConstraints(minWidth: 24),
            alignment: Alignment.center,
            child: Text(
              UnitFormatter.formatWaterTotal(volumeMl, volumeUnit),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: themeColors.textDominant,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Plus button. Mirror of the minus button.
          IconButton(
            key: const Key('water_tracker_plus'),
            onPressed: onIncrement,
            icon: Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
            tooltip: 'Add $stepSpoken',
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
