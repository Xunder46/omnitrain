import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// The one header "+": create a new item for the list on this screen.
///
/// Every header "+" in the app is this piece (plan 91, D-91.1), so it has the
/// same size, colour, press shrink and spoken label everywhere. A header
/// action that goes somewhere else uses an icon for that place instead.
/// `test/ui_standards_contract_test.dart` (group `S-9158 header plus`) fails
/// when a header builds its own "+".
///
/// [label] is both the tooltip and the screen-reader label; nothing is drawn
/// as text. [buttonKey] lands on the inner [IconButton], so a test can read
/// the button through it. The icon keeps the `IconButton` default size, which
/// is what keeps every instance the same size whatever its label.
///
/// While a finger is down the piece shrinks to [OmniTheme.pressedScale] and
/// returns on release or cancel; with reduced motion the scale applies
/// without animation. The shrink never delays [onPressed].
class OmniHeaderAddButton extends StatefulWidget {
  /// Tooltip and screen-reader label, e.g. `New Exercise`.
  final String label;

  /// Called when the button is tapped.
  final VoidCallback onPressed;

  /// Key placed on the inner [IconButton].
  final Key? buttonKey;

  const OmniHeaderAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.buttonKey,
  });

  @override
  State<OmniHeaderAddButton> createState() => _OmniHeaderAddButtonState();
}

class _OmniHeaderAddButtonState extends State<OmniHeaderAddButton> {
  bool _isPressed = false;

  void _setPressed(bool pressed) {
    if (!mounted || _isPressed == pressed) return;
    setState(() => _isPressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scale = _isPressed ? OmniTheme.pressedScale : 1.0;

    final Widget button = IconButton(
      key: widget.buttonKey,
      icon: const Icon(Icons.add),
      tooltip: widget.label,
      color: OmniTheme.colors.textDominant,
      onPressed: widget.onPressed,
    );

    final Widget scaled = reduceMotion
        ? Transform.scale(scale: scale, child: button)
        : AnimatedScale(
            scale: scale,
            duration: OmniTheme.animationDuration,
            curve: OmniTheme.animationCurve,
            child: button,
          );

    // A Listener watches the pointer without joining the gesture arena, so
    // the IconButton's own tap handling (and its cancel when the finger
    // slides off) is untouched. No Semantics wrapper: the IconButton's
    // tooltip already gives the one screen-reader node its label, button
    // role and tap; a wrapper would add a second stop that cannot be tapped.
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: scaled,
    );
  }
}
