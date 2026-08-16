import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'contrast_helpers.dart';

void main() {
  group('Color scheme completeness verification (Phase 1 - Item 1)', () {
    test('All themes have container roles distinct from raw accents', () {
      for (final theme in AppTheme.values) {
        final colors = OmniTheme.colorsForTheme(theme);
        final onPrimary = getOnPrimaryForTheme(theme);

        final builtTheme = buildTheme(
          theme: theme,
          brightness: Brightness.dark,
          background: colors.backgroundBottom,
          surface: colors.surface,
          secondary: colors.secondary,
          textPrimary: colors.textDominant,
          textSecondary: colors.textSecondary,
          divider: colors.divider,
          onPrimary: onPrimary,
          onSecondary: getOnSecondaryForTheme(theme),
        );

        // Primary container should not equal primary
        expect(
          builtTheme.colorScheme.primaryContainer,
          isNotNull,
          reason: '${theme.name}: primaryContainer must be defined',
        );
        expect(
          builtTheme.colorScheme.primaryContainer,
          isNot(equals(builtTheme.colorScheme.primary)),
          reason:
              '${theme.name}: primaryContainer must not equal primary accent',
        );

        // Secondary container should not equal secondary
        expect(
          builtTheme.colorScheme.secondaryContainer,
          isNotNull,
          reason: '${theme.name}: secondaryContainer must be defined',
        );
        expect(
          builtTheme.colorScheme.secondaryContainer,
          isNot(equals(builtTheme.colorScheme.secondary)),
          reason:
              '${theme.name}: secondaryContainer must not equal secondary accent',
        );

        // All "on" colors should clear 4.5:1 against their paired base colors
        expect(
          contrastRatio(
            builtTheme.colorScheme.onPrimaryContainer,
            builtTheme.colorScheme.primaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
          reason:
              '${theme.name}: onPrimaryContainer vs primaryContainer contrast must be >= 4.5:1',
        );

        expect(
          contrastRatio(
            builtTheme.colorScheme.onSecondaryContainer,
            builtTheme.colorScheme.secondaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
          reason:
              '${theme.name}: onSecondaryContainer vs secondaryContainer contrast must be >= 4.5:1',
        );

        expect(
          contrastRatio(
            builtTheme.colorScheme.onTertiaryContainer,
            builtTheme.colorScheme.tertiaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
          reason:
              '${theme.name}: onTertiaryContainer vs tertiaryContainer contrast must be >= 4.5:1',
        );
      }
    });

    test('Rest timer container is dim, not saturated accent', () {
      // Verify that primaryContainer is darker than primary accent
      // (i.e., lower relative luminance)
      for (final theme in AppTheme.values) {
        final colors = OmniTheme.colorsForTheme(theme);
        final onPrimary = getOnPrimaryForTheme(theme);

        final builtTheme = buildTheme(
          theme: theme,
          brightness: Brightness.dark,
          background: colors.backgroundBottom,
          surface: colors.surface,
          secondary: colors.secondary,
          textPrimary: colors.textDominant,
          textSecondary: colors.textSecondary,
          divider: colors.divider,
          onPrimary: onPrimary,
          onSecondary: getOnSecondaryForTheme(theme),
        );

        // Container should be darker (lower luminance) than the raw accent
        final primaryLuminance = _relativeLuminanceForColor(
          builtTheme.colorScheme.primary,
        );
        final containerLuminance = _relativeLuminanceForColor(
          builtTheme.colorScheme.primaryContainer,
        );

        expect(
          containerLuminance,
          lessThan(primaryLuminance),
          reason:
              '${theme.name}: primaryContainer luminance must be lower than primary accent',
        );
      }
    });
  });
}

/// Calculate relative luminance for a color (WCAG 2.1).
double _relativeLuminanceForColor(Color color) {
  return _relativeLuminance(color);
}

double _linearizeChannel(double c) {
  return c <= 0.04045
      ? c / 12.92
      : ((c + 0.055) / 1.055 * (c + 0.055) / 1.055 * (c + 0.055) / 1.055);
}

double _relativeLuminance(Color color) {
  final r = _linearizeChannel(color.red / 255);
  final g = _linearizeChannel(color.green / 255);
  final b = _linearizeChannel(color.blue / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
