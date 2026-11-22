/// The phone's theme accent, as the Wear wrist wears it.
///
/// Plan: `docs/plans/2026-11-21-286-wear-accent-theming-plan/2026-11-21-286-wear-accent-theming-plan.md`
/// (D-28601). The Dart twin of the Apple client's `WatchAccent`
/// (`watch/watchos/Sources/WatchSessionEngine/WatchAccent.swift`): the wrist never
/// trusts the string it is given to be renderable, it parses the hex itself, and
/// an accent too dark to read on a black screen is refused here, so no screen has
/// to decide. The luminance and both contrast ratios are WCAG 2.x; the six accents
/// the two clients agree on are `watch/contract/watch_accent_contract.json`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One accent colour, and what can be said about it.
class WatchAccent {
  const WatchAccent._(this.red, this.green, this.blue);

  /// The sRGB channels, each 0..255, as `#RRGGBB` names them.
  final int red;
  final int green;
  final int blue;

  /// The floor an accent must clear to be worn: an accent whose contrast against
  /// black is below it is ignored and the wrist keeps its default look.
  static const double minContrastAgainstBlack = 3.0;

  /// The phone's default theme accent (`abyssalNeon` in the contract table), what
  /// the wrist wears before a sync has carried a usable accent.
  static const String fallbackHex = '#2DE2E6';

  static final RegExp _shape = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// Parses `#RRGGBB` and nothing else, the shape `preferences_down`'s
  /// `accentColorHex` is validated against: no short form, no alpha, no bare hex,
  /// no surrounding space. A string that does not fit reads null.
  static WatchAccent? tryParse(String hex) {
    if (!_shape.hasMatch(hex)) return null;
    final value = int.parse(hex.substring(1), radix: 16);
    return WatchAccent._(
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    );
  }

  /// The accent a preference copy names, or null when there is none, when the
  /// string is not `#RRGGBB`, and when the accent is too dark to wear.
  static WatchAccent? usable(String? hex) {
    if (hex == null) return null;
    final accent = tryParse(hex);
    if (accent == null || !accent.isUsable) return null;
    return accent;
  }

  static final WatchAccent _fallback = tryParse(fallbackHex)!;

  /// The accent the wrist wears for the hex the phone sent, or the phone's
  /// default theme accent when there is none, when the string does not parse, or
  /// when the accent is too dark to wear.
  static WatchAccent worn(String? hex) => usable(hex) ?? _fallback;

  /// WCAG 2.x relative luminance: each sRGB channel linearised, then weighted.
  double get relativeLuminance =>
      0.2126 * _linear(red) + 0.7152 * _linear(green) + 0.0722 * _linear(blue);

  /// Contrast against black, 1..21.
  double get contrastAgainstBlack => (relativeLuminance + 0.05) / 0.05;

  /// Contrast against white, 1..21.
  double get contrastAgainstWhite => 1.05 / (relativeLuminance + 0.05);

  /// Whether dark labels belong on this accent: true exactly when black text
  /// reads at least as well on it as white text does.
  bool get labelIsDark => contrastAgainstBlack >= contrastAgainstWhite;

  /// Whether the wrist wears this accent at all.
  bool get isUsable => contrastAgainstBlack >= minContrastAgainstBlack;

  /// The accent as Flutter draws it, opaque.
  Color get color => Color.fromARGB(255, red, green, blue);

  /// The label that reads on [color]: black where black has the higher contrast,
  /// white otherwise.
  Color get labelColor => labelIsDark ? Colors.black : Colors.white;

  static double _linear(int channel) {
    final c = channel / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }
}
