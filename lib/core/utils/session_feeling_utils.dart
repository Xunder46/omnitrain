import 'package:flutter/material.dart';

import '../constants/omni_theme.dart';

/// Single source of truth for the per-rating color used on every
/// effort-rating surface (post-workout survey tile, day-session-list
/// border tint, future analytics surfaces).
///
/// The helper takes the active `OmniThemeColors`. Ratings 1..5 are drawn from
/// the theme's intensity ramp, which uses the theme accent at varying
/// opacities to create a consistent one-color gradient from faintest
/// (1 = very easy) to full strength (5 = max effort).
///
/// Effort ratings follow the intensity scale: 1 (very easy) shows
/// the faintest ramp color; 5 (max effort) shows the theme's primary
/// accent at full strength. Ratings are never null (1–5); unrated
/// sessions pass null and should display a neutral placeholder.
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
