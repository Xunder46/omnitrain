import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// A full-width footer strip for the home screen that serves as the
/// placeholder entry point to the nutrition feature.
///
/// Phase 2 ships a zero-state placeholder only — the label is hard-coded and
/// tapping opens a placeholder destination. Phase 3 will plug the real daily
/// calorie total into [label] and route to the day-log screen.
///
/// Sits above the device's bottom system-gesture / home-indicator safe area
/// via the inner `SafeArea(top: false)`. The strip is a thin footer element,
/// not a `FloatingActionButton`, and is intentionally separate from the
/// training-tile grid so it does not displace or compete with the modality
/// tiles.
class NutritionStripButton extends StatelessWidget {
  /// Callback invoked when the strip is tapped.
  final VoidCallback onTap;

  /// Visible label. Defaults to the Phase 2 zero-state copy. Phase 3 will
  /// supply a real "X calories today" string here.
  final String label;

  const NutritionStripButton({
    super.key,
    required this.onTap,
    this.label = '0 calories today',
  });

  @override
  Widget build(BuildContext context) {
    // Active theme tokens. The app shell keeps OmniTheme.activeTheme in sync
    // with SettingsState, so the static getter is correct here and avoids
    // threading a theme parameter through the call site.
    final themeColors = OmniTheme.colors;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: themeColors.surface,
              border: Border(
                top: BorderSide(
                  color: themeColors.surfaceBorder,
                  width: OmniTheme.surfaceBorderWidth,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_dining_outlined,
                    size: 20,
                    color: themeColors.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: themeColors.textDominant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: themeColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
