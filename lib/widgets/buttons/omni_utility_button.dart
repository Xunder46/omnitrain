import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// The one utility button: an outlined, content-width control with a leading
/// icon, for a secondary action that sits inline among other controls (the
/// package-serving switch on the food form).
///
/// It is the "Utility" row of the Button Variants table in
/// `docs/design_system.md`. A plain text link does not read as a control, so
/// an inline action uses this piece instead of a `TextButton`. Its shape is
/// [OmniTheme.buttonUtilityRadius]; colours come from the theme (primary
/// outline and label). `test/omni_utility_button_test.dart` pins the look.
///
/// [buttonKey] lands on the inner button so a test can read and tap it.
class OmniUtilityButton extends StatelessWidget {
  /// Button text. May wrap onto a second line on a narrow screen.
  final String label;

  /// Leading icon, drawn at a small fixed size.
  final IconData icon;

  /// Called when the button is tapped. `null` disables it.
  final VoidCallback? onPressed;

  /// Key placed on the inner [OutlinedButton].
  final Key? buttonKey;

  const OmniUtilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.buttonKey,
  });

  /// Size of the leading icon.
  static const double iconSize = 16;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      icon: Icon(icon, size: iconSize),
      label: Text(label),
    );
  }
}

/// The icon-only form of [OmniUtilityButton]: the same outlined rounded
/// square with no label, for an inline action whose icon is enough to name it
/// (the pen beside the effort rating and the pen at the end of a distance row
/// on the session summary).
///
/// A bare icon does not read as a control, so the piece always draws the
/// outline; it is [OmniTheme.buttonUtilityRadius] on a square of [size], which
/// is also the smallest tap target the app allows. [tooltip] is both the
/// tooltip and the screen-reader label and is required, so an icon-only button
/// can never ship unnamed. `test/omni_utility_button_test.dart` pins the look.
class OmniUtilityIconButton extends StatelessWidget {
  /// Icon drawn in the middle of the square.
  final IconData icon;

  /// Tooltip and screen-reader label, e.g. `Change rating`.
  final String tooltip;

  /// Called when the button is tapped. `null` disables it.
  final VoidCallback? onPressed;

  /// Key placed on the inner [OutlinedButton].
  final Key? buttonKey;

  const OmniUtilityIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  /// Side of the square, which is the minimum tap target.
  static const double size = 48;

  /// Size of the icon inside the square.
  static const double iconSize = 20;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onPressed,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          ),
          fixedSize: const WidgetStatePropertyAll(Size.square(size)),
          minimumSize: const WidgetStatePropertyAll(Size.square(size)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
        child: Icon(icon, size: iconSize, semanticLabel: tooltip),
      ),
    );
  }
}
