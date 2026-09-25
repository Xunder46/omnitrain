import 'package:flutter/material.dart';

import '../constants/omni_theme.dart';

/// Single source of truth for the per-rating color used on every
/// effort-rating surface (rating-sheet tiles, the Session Summary EFFORT
/// marker, the day-session-list border tint).
///
/// The helper takes the active `OmniThemeColors`. Ratings 1..5 are drawn from
/// the theme's intensity ramp, which uses the theme accent at varying
/// opacities to create a consistent one-color gradient from faintest
/// (1 = very easy) to full strength (5 = max effort).
///
/// A stored rating is 1..5. `null` (an unrated session) and any
/// out-of-range value return [Colors.transparent]; callers decide what, if
/// anything, to draw for an unrated session.
Color feelingColor(int? feeling, OmniThemeColors themeColors) {
  if (feeling == null) {
    // Unrated; return a neutral/transparent result. Callers handle display.
    return Colors.transparent;
  }
  switch (feeling) {
    case 1:
      return themeColors.intensityRamp.step1;
    case 2:
      return themeColors.intensityRamp.step2;
    case 3:
      return themeColors.intensityRamp.step3;
    case 4:
      return themeColors.intensityRamp.step4;
    case 5:
      return themeColors.intensityRamp.step5;
    default:
      // Invalid rating; return transparent
      return Colors.transparent;
  }
}

/// Helper for tile number text color on effort-rating tiles.
/// Returns the color that achieves the highest contrast on the given ramp step.
/// Used for selected tile numbers in the effort-rating survey sheet.
///
/// Takes both the OmniTheme colors and Material theme's onPrimary color
/// to pick the best text color for contrast.
Color effortTileTextColor(
  int rating,
  OmniThemeColors themeColors, {
  required Color onPrimary,
}) {
  final stepColor = feelingColor(rating, themeColors);
  if (stepColor == Colors.transparent) {
    return themeColors.textDominant;
  }

  // Try both onPrimary and textDominant, pick the one with better contrast
  final onPrimaryContrast = OmniTheme.contrastRatio(onPrimary, stepColor);
  final textDominantContrast = OmniTheme.contrastRatio(
    themeColors.textDominant,
    stepColor,
  );

  return onPrimaryContrast >= textDominantContrast
      ? onPrimary
      : themeColors.textDominant;
}
