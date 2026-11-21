// The wrist's shared input primitives: the turn counter both rotary surfaces
// accumulate against, and the step button beside their values.
//
// They are one file because they are one pair. A value on the watch is moved
// either by a turn of the crown or by a tap on a control, and both surfaces that
// offer the two must offer them the same way — same detent size, same shape,
// same name for the screen reader.

library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// The wrist's one rule for a small screen (plan 282, D-28201). Real Wear OS
/// watches are 192 to 240 dp tall; a phone-sized window is far above that.
abstract final class WatchLayout {
  /// Screens shorter than this many logical pixels get the compact look.
  static const double compactBelow = 260;

  /// Compact heights (D-28203): the primary button and the shell's Menu button.
  static const double compactButtonHeight = 40;
  static const double compactMenuHeight = 32;

  /// Whether the screen [context] sits on is short enough for the compact look.
  /// Needs a `MediaQuery` above [context] (any widget under a `MaterialApp`).
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).height < compactBelow;
}

/// Turn accumulated between rotary events, holding the travel that did not add
/// up to a whole detent so the next event finishes it.
class WatchRotaryTurn {
  WatchRotaryTurn({this.pointsPerDetent = defaultPointsPerDetent});

  /// Points of turn that count as one detent. A Digital Crown detent and a Wear
  /// OS rotary notch both arrive as a scroll or a drag, and both are counted
  /// against this.
  static const double defaultPointsPerDetent = 32;

  final double pointsPerDetent;

  double _pending = 0;

  /// How many whole detents [travel] completes, keeping the remainder.
  ///
  /// [travel] is signed movement in points, and the gesture axis runs the other
  /// way: a drag up is a negative delta and means more.
  int detentsFor(double travel) {
    final rising = _pending - travel;
    final whole = (rising / pointsPerDetent).truncateToDouble();
    _pending = rising - whole * pointsPerDetent;
    return whole.toInt();
  }
}

/// A step control beside a value: square, at the icon radius, and named.
class WatchStepButton extends StatelessWidget {
  const WatchStepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  /// Wrist-scale icon: `OmniTheme.buttonIconSize` is sized for a full-width
  /// phone screen.
  static const double iconSize = 22;

  final IconData icon;

  /// What the control does, read out as the button's name — an arrow is not a
  /// name.
  final String label;

  /// Null where the control is inert, as on a row a sensor is keeping.
  final VoidCallback? onPressed;

  /// The compact look: a 36 dp square with no tap padding (D-28203).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      tooltip: label,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
        ),
        minimumSize: compact ? const Size.square(36) : null,
        padding: compact ? EdgeInsets.zero : null,
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      ),
      onPressed: onPressed,
    );
  }
}
