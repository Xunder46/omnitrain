import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_colors.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/utils/session_feeling_utils.dart';
import 'package:omnitrain/widgets/cards/energy_tile.dart';
import 'package:omnitrain/app.dart';
import 'contrast_helpers.dart';
import 'dart:math' as math;

void main() {
  group('Palette legibility contract (Iteration 2 - Checks 1-17)', () {
    test('All 17 checks pass for all six themes', () {
      final results = <String, List<String>>{};

      for (final theme in AppTheme.values) {
        final colors = OmniTheme.colorsForTheme(theme);
        results[theme.name] = [];

        // Check 1: Background gradient top stop: L* ≥ 10
        final bgTopLightness = _getLabLightness(colors.backgroundTop);
        if (bgTopLightness < 10) {
          results[theme.name]!.add(
            'Check 1 FAIL: backgroundTop L* = $bgTopLightness (required ≥ 10)',
          );
        }

        // Check 2: Background gradient bottom stop: L* ≥ 2.5
        final bgBottomLightness = _getLabLightness(colors.backgroundBottom);
        if (bgBottomLightness < 2.5) {
          results[theme.name]!.add(
            'Check 2 FAIL: backgroundBottom L* = $bgBottomLightness (required ≥ 2.5)',
          );
        }

        // Check 3: Surface strictly lighter than background top by ≥ 1.5 L*
        final surfaceLightness = _getLabLightness(colors.surface);
        final lightnessDelta = surfaceLightness - bgTopLightness;
        if (lightnessDelta < 1.5) {
          results[theme.name]!.add(
            'Check 3 FAIL: surface L* ($surfaceLightness) vs background top L* ($bgTopLightness), delta = $lightnessDelta (required ≥ 1.5)',
          );
        }

        // Check 4: Muted text vs surface: contrast ≥ 4.5:1
        final mutedContrast = contrastRatio(colors.textMuted, colors.surface);
        if (mutedContrast < 4.5) {
          results[theme.name]!.add(
            'Check 4 FAIL: textMuted vs surface contrast = $mutedContrast (required ≥ 4.5:1)',
          );
        }

        // Check 5: Secondary text (composited @ 60% white) vs surface: contrast ≥ 4.5:1
        final secondaryTextComposited = _compositeOverSurface(
          Colors.white.withValues(alpha: 0.6),
          colors.surface,
        );
        final secondaryTextContrast = contrastRatio(
          secondaryTextComposited,
          colors.surface,
        );
        if (secondaryTextContrast < 4.5) {
          results[theme.name]!.add(
            'Check 5 FAIL: secondary text (60% white) vs surface contrast = $secondaryTextContrast (required ≥ 4.5:1)',
          );
        }

        // Check 6: Surface border (composited @ current alpha) vs surface: contrast ≥ 1.8:1
        final borderComposited = _compositeOverSurface(
          colors.surfaceBorder,
          colors.surface,
        );
        final borderContrast = contrastRatio(borderComposited, colors.surface);
        if (borderContrast < 1.8) {
          results[theme.name]!.add(
            'Check 6 FAIL: surfaceBorder vs surface contrast = $borderContrast (required ≥ 1.8:1)',
          );
        }

        // Check 7: Divider vs surface: contrast ≥ 1.3:1
        final dividerContrast = contrastRatio(colors.divider, colors.surface);
        if (dividerContrast < 1.3) {
          results[theme.name]!.add(
            'Check 7 FAIL: divider vs surface contrast = $dividerContrast (required ≥ 1.3:1)',
          );
        }

        // Check 8: Primary accent vs surface: contrast ≥ 3:1
        final primaryContrast = contrastRatio(colors.primary, colors.surface);
        if (primaryContrast < 3.0) {
          results[theme.name]!.add(
            'Check 8 FAIL: primary vs surface contrast = $primaryContrast (required ≥ 3:1)',
          );
        }

        // Check 9: On-primary label vs primary accent: contrast ≥ 4.5:1
        final onPrimary = getOnPrimaryForTheme(theme);
        final onPrimaryContrast = contrastRatio(onPrimary, colors.primary);
        if (onPrimaryContrast < 4.5) {
          results[theme.name]!.add(
            'Check 9 FAIL: onPrimary vs primary contrast = $onPrimaryContrast (required ≥ 4.5:1)',
          );
        }

        // Check 10: On-secondary label vs secondary accent: contrast ≥ 4.5:1
        final onSecondary = getOnSecondaryForTheme(theme);
        final onSecondaryContrast = contrastRatio(
          onSecondary,
          colors.secondary,
        );
        if (onSecondaryContrast < 4.5) {
          results[theme.name]!.add(
            'Check 10 FAIL: onSecondary vs secondary contrast = $onSecondaryContrast (required ≥ 4.5:1)',
          );
        }

        // Build theme to access ColorScheme roles
        final builtTheme = buildTheme(
          theme: theme,
          brightness: Brightness.dark,
          background: colors.backgroundBottom,
          surface: colors.surface,
          secondary: colors.secondary,
          textPrimary: colors.textDominant,
          textSecondary: colors.textSecondary,
          divider: colors.divider,
          onPrimary: getOnPrimaryForTheme(theme),
          onSecondary: getOnSecondaryForTheme(theme),
        );
        final scheme = builtTheme.colorScheme;

        // Check 11: Outline vs surface: contrast ≥ 3:1
        final outlineComposited = _compositeOverSurface(
          scheme.outline,
          colors.surface,
        );
        final outlineContrast = contrastRatio(
          outlineComposited,
          colors.surface,
        );
        if (outlineContrast < 3.0) {
          results[theme.name]!.add(
            'Check 11 FAIL: outline ${scheme.outline} vs surface contrast = $outlineContrast (required ≥ 3:1)',
          );
        }

        // Check 12: Outline-variant vs surface: contrast ≥ 1.8:1
        final outlineVariantComposited = _compositeOverSurface(
          scheme.outlineVariant,
          colors.surface,
        );
        final outlineVariantContrast = contrastRatio(
          outlineVariantComposited,
          colors.surface,
        );
        if (outlineVariantContrast < 1.8) {
          results[theme.name]!.add(
            'Check 12 FAIL: outlineVariant ${scheme.outlineVariant} vs surface contrast = $outlineVariantContrast (required ≥ 1.8:1)',
          );
        }

        // Check 13: Highest-elevation surface container lighter than surface by ≥ 2 L*
        late Color containerHighest;
        containerHighest = scheme.surfaceContainerHighest;
              final containerHighestLightness = _getLabLightness(containerHighest);
        final containerDelta = containerHighestLightness - surfaceLightness;
        if (containerDelta < 2.0) {
          results[theme.name]!.add(
            'Check 13 FAIL: surfaceContainerHighest L* ($containerHighestLightness) vs surface L* ($surfaceLightness), delta = $containerDelta (required ≥ 2:1)',
          );
        }

        // Check 14: On-surface-variant vs surface: contrast ≥ 4.5:1
        late Color onSurfaceVariant;
        onSurfaceVariant = scheme.onSurfaceVariant;
              final onSurfaceVariantContrast = contrastRatio(
          onSurfaceVariant,
          colors.surface,
        );
        if (onSurfaceVariantContrast < 4.5) {
          results[theme.name]!.add(
            'Check 14 FAIL: onSurfaceVariant $onSurfaceVariant vs surface contrast = $onSurfaceVariantContrast (required ≥ 4.5:1)',
          );
        }
        // ── Checks 15-16: home tile fills ────────────────────────────────
        // Tiles are the modality accent composited over the background
        // gradient, so their legibility depends on BOTH the modality colour
        // and the theme — neither of which the checks above cover. That gap
        // is why the tile fills drifted through the palette re-anchoring
        // unnoticed. The background TOP stop is the worst case: it is the
        // lightest point of the gradient, so it produces the lightest fill
        // and the weakest contrast for the tile's near-white label.
        //
        // These read the opacities from EnergyTile rather than restating
        // them, so retuning the tiles moves the gate with them. What is
        // pinned here is the legibility floor, not the aesthetic value.
        for (final entry in ModalityColors.byModality.entries) {
          final fill = _compositeOverSurface(
            entry.value.withValues(alpha: EnergyTile.primaryFillOpacity),
            colors.backgroundTop,
          );
          final labelOnFill = _compositeOverSurface(colors.textDominant, fill);
          final tileContrast = contrastRatio(labelOnFill, fill);
          if (tileContrast < 4.5) {
            results[theme.name]!.add(
              'Check 15 FAIL: primary tile label on ${entry.key} fill = $tileContrast (required ≥ 4.5:1)',
            );
          }
        }

        // ── Check 17: modality accents at full opacity ───────────────────
        // Calendar dots, chips and period markers paint ModalityColors at
        // FULL opacity directly on the theme surface, with no compositing to
        // soften them. On the month grid the dot is the only thing saying
        // which modality a session was, so it is a graphical object carrying
        // meaning and owes WCAG 1.4.11's 3:1 against its backdrop.
        //
        // This check exists because the palette re-anchoring lightened five
        // surfaces and silently pushed the free-training accent from passing
        // to ~2.7:1 on all five. Nothing caught it — modality colours are
        // global constants while surfaces are per-theme, so only a check that
        // crosses the two can see the interaction.
        for (final entry in ModalityColors.byModality.entries) {
          final c = contrastRatio(entry.value, colors.surface);
          if (c < 3.0) {
            results[theme.name]!.add(
              'Check 17 FAIL: modality accent ${entry.key} vs surface = $c (required ≥ 3:1)',
            );
          }
        }

        // Secondary tiles run one tier quieter, and their label is white at
        // 70% rather than textDominant — the weakest text on any tile.
        for (final entry in ModalityColors.byModality.entries) {
          final fill = _compositeOverSurface(
            entry.value.withValues(alpha: EnergyTile.secondaryFillOpacity),
            colors.backgroundTop,
          );
          final labelOnFill = _compositeOverSurface(
            const Color(0xFFFFFFFF).withValues(alpha: 0.70),
            fill,
          );
          final tileContrast = contrastRatio(labelOnFill, fill);
          if (tileContrast < 4.5) {
            results[theme.name]!.add(
              'Check 16 FAIL: secondary tile label on ${entry.key} fill = $tileContrast (required ≥ 4.5:1)',
            );
          }
        }

        // ── Checks 18-20: Effort-rating intensity ramp ─────────────────────
        // The intensity ramp is used for effort-rating tiles, calendar tints,
        // and future analytics displays. All five steps must pass three checks:
        //
        // Check 18a: Each step ≥ 1.8:1 vs surface (minimum legible tint).
        // Check 18b: Contrast strictly increases from step 1 to 5.
        // Check 18c: Number text (headlineSmall) on each step tile ≥ 3:1,
        //           using whichever of onPrimary or textDominant passes.
        //
        // The ramp is guaranteed to exist (calculated per theme in omni_theme.dart).
        final ramp = colors.intensityRamp;
        final rampSteps = [ramp.step1, ramp.step2, ramp.step3, ramp.step4, ramp.step5];
        final rampNames = ['step1', 'step2', 'step3', 'step4', 'step5'];

        // Check 18a: All steps ≥ 1.8:1 vs surface
        for (int i = 0; i < rampSteps.length; i++) {
          final rampContrast = contrastRatio(rampSteps[i], colors.surface);
          if (rampContrast < 1.8) {
            results[theme.name]!.add(
              'Check 18a FAIL: intensity ${rampNames[i]} vs surface = $rampContrast (required ≥ 1.8:1)',
            );
          }
        }

        // Check 18b: Contrast strictly increases 1→5
        for (int i = 0; i < rampSteps.length - 1; i++) {
          final contrastI = contrastRatio(rampSteps[i], colors.surface);
          final contrastI1 = contrastRatio(rampSteps[i + 1], colors.surface);
          if (contrastI1 <= contrastI) {
            results[theme.name]!.add(
              'Check 18b FAIL: intensity contrast does not strictly increase: ${rampNames[i]} = $contrastI, ${rampNames[i + 1]} = $contrastI1 (required: strict increase)',
            );
          }
        }

        // Check 18c: Number text on each tile ≥ 3:1
        // Use the same helper the UI uses for selecting text color on effort tiles
        // (onPrimary was already obtained for Check 9)
        for (int i = 1; i <= 5; i++) {
          final textColor = effortTileTextColor(i, colors, onPrimary: onPrimary);
          final rampStep = feelingColor(i, colors);
          final textContrast = contrastRatio(textColor, rampStep);
          if (textContrast < 3.0) {
            results[theme.name]!.add(
              'Check 18c FAIL: text on intensity step $i tile: contrast = $textContrast (required ≥ 3:1)',
            );
          }
        }
      }

      // Report all failures
      final allFailures = <String>[];
      for (final theme in AppTheme.values) {
        if (results[theme.name]!.isNotEmpty) {
          allFailures.add('${theme.name}:');
          allFailures.addAll(results[theme.name]!.map((f) => '  $f'));
        }
      }

      if (allFailures.isNotEmpty) {
        fail(
          'Palette legibility contract violations:\n${allFailures.join('\n')}',
        );
      }
    });
  });
}

/// Get CIELAB L* (lightness) for a color.
double _getLabLightness(Color color) {
  final luminance = _relativeLuminance(color);
  // Convert sRGB relative luminance to CIELAB L*
  final fy = luminance > 0.008856
      ? math.pow(luminance, 1.0 / 3.0)
      : (7.787 * luminance) + (16.0 / 116.0);
  return (116.0 * fy) - 16.0;
}

/// Composite a color with alpha over a background surface.
/// Assumes the background is fully opaque.
Color _compositeOverSurface(Color foreground, Color background) {
  final fgAlpha = foreground.alpha / 255.0;

  final r = (foreground.red * fgAlpha + background.red * (1 - fgAlpha)).round();
  final g = (foreground.green * fgAlpha + background.green * (1 - fgAlpha))
      .round();
  final b = (foreground.blue * fgAlpha + background.blue * (1 - fgAlpha))
      .round();

  return Color.fromARGB(255, r, g, b);
}

double _linearizeChannel(double c) {
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _linearizeChannel(color.red / 255);
  final g = _linearizeChannel(color.green / 255);
  final b = _linearizeChannel(color.blue / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
