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

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      tooltip: label,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
        ),
      ),
      onPressed: onPressed,
    );
  }
}
