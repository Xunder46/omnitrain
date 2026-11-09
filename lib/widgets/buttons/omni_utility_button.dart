import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// The one utility button: an outlined, content-width control with a leading
/// icon, for a secondary action that sits inline among other controls (Change
/// rating on the session summary, the package-serving switch on the food
/// form).
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
