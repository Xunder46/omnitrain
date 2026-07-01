import 'package:flutter/material.dart';

import '../constants/omni_theme.dart';

/// Single source of truth for the per-rating color used on every
/// feeling surface (post-workout survey tile, day-session-list
/// border tint, stats-screen trend dots, future surfaces).
///
/// The helper is theme-pure: it takes the active `OmniThemeColors`
/// directly instead of a `BuildContext`. This eliminates the
/// `Theme.of(context).primaryColor` indirection that previously
/// gave rating-5 a second, separate path to the same accent —
/// `themeColors.primary` is now the only source for #5, matching
/// the chart line, the FilledButton, and every other accent on
/// the screen (DRY).
///
/// Ratings 1..4 keep the established Material palette (semantic
/// traffic-light shape: red → orange → yellow → green); rating 5
/// is the theme's saturated `primary` accent.
Color feelingColor(int feeling, OmniThemeColors themeColors) {
  switch (feeling) {
    case 1:
      return Colors.red;
    case 2:
      return Colors.orange;
    case 3:
      return Colors.yellow[700]!;
    case 4:
      return Colors.green;
    case 5:
      return themeColors.primary;
    default:
      return themeColors.primary;
  }
}
