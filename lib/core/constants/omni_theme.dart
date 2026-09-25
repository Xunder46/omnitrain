import 'package:flutter/material.dart';
import 'dart:math' as math;

enum AppTheme {
  abyssalNeon,
  forgeEmber,
  obsidianVolt,
  voidPulse,
  crimsonDojo,
  malachiteCore,
}

/// Themed palette for the macro-distribution donut chart. Slots map 1:1
/// to the four sections drawn by `MacroDonutChart`:
///   - `protein`  — high-contrast near-white
///   - `carbs`    — saturated blue (net = carbs − fiber)
///   - `fiber`    — saturated green
///   - `fat`      — saturated amber/yellow
///   - `chartLabelDark` — dark text color used for in-band labels
///     when the section color is light (estimated via
///     `ThemeData.estimateBrightnessForColor`). The light counterpart
///     is the theme's `textDominant` token (the existing palette
///     contract does not duplicate it here).
typedef MacroChartPalette = ({
  Color protein,
  Color carbs,
  Color fiber,
  Color fat,
  Color chartLabelDark,
});

/// Muted palette for the home-screen nutrition summary card
/// (Iteration 5). Distinct from the saturated [MacroChartPalette]
/// above — the card lives next to a raised tile grid on a dark
/// surface, so the bars need to read as "lit panel on dark"
/// rather than as a status light. The three slots are intentionally
/// desaturated: a muted terracotta for protein, a muted steel-blue
/// for carbs, and a muted amber for fat. Values are tuned per
/// theme so each tone clears against its respective `surface`
/// while staying restrained (no bright/saturated primaries).
typedef StripMacroPalette = ({Color protein, Color carbs, Color fat});

/// Intensity ramp for effort-rating UI: 5 steps, step 1 faintest (≥1.8:1 vs surface)
/// to step 5 full strength (primary at 100% opacity). Steps 2–4 space the contrast
/// against surface evenly, so contrast strictly increases. Used for the rating
/// tiles, the Summary EFFORT marker and the calendar day-list tint.
typedef IntensityRampPalette = ({
  Color step1,
  Color step2,
  Color step3,
  Color step4,
  Color step5,
});

typedef OmniThemeColors = ({
  Color backgroundTop,
  Color backgroundBottom,
  Color surface,
  Color primary,
  Color secondary,
  Color textDominant,
  Color textSecondary,
  Color textMuted,
  Color textDisabled,
  Color divider,
  Color surfaceBorder,
  MacroChartPalette macroChart,
  StripMacroPalette stripMacros,
  IntensityRampPalette intensityRamp,
});

/// Core theme constants for OMNITRAIN biomechanical training system
/// Centralized color palette and design tokens
class OmniTheme {
  /// The active theme, exposed as a listenable so surfaces that render
  /// *before* `MyApp` mounts can adopt the user's saved theme mid-startup
  /// rather than sitting on the default until the whole runner finishes.
  /// [StartupPreparingScreen] is the only such surface today.
  ///
  /// Assignment stays source-compatible: `OmniTheme.activeTheme = x` works
  /// exactly as it did when this was a plain field.
  static final ValueNotifier<AppTheme> activeThemeListenable =
      ValueNotifier<AppTheme>(AppTheme.abyssalNeon);

  static AppTheme get activeTheme => activeThemeListenable.value;

  static set activeTheme(AppTheme theme) => activeThemeListenable.value = theme;

  // Unified macro palette colors (abyssalNeon stripMacros base values)
  // Applied to both macroChart and stripMacros across all themes
  static const Color _baseProtein = Color.fromARGB(255, 188, 188, 188);
  static const Color _baseCarbs = Color.fromARGB(255, 102, 172, 186);
  static const Color _baseFiber = Color.fromARGB(255, 87, 167, 112);
  static const Color _baseFat = Color.fromARGB(255, 201, 191, 99);

  /// Cached intensity ramps, keyed on the `(primary, surface)` pair the ramp
  /// is derived from. Computed once per pair to avoid the alpha scans during
  /// build cycles (`colorsForTheme` runs inside builders). Keying on the
  /// colors rather than the `AppTheme` means a palette edit (e.g. after hot
  /// reload) can never be served a ramp derived from the old values.
  static final Map<(Color, Color), IntensityRampPalette> _rampCache = {};

  /// The effort-rating intensity ramp derived from [primary] over [surface]
  /// (see [_calculateIntensityRamp]), cached per color pair.
  static IntensityRampPalette intensityRampFor(Color primary, Color surface) =>
      _rampCache.putIfAbsent(
        (primary, surface),
        () => _calculateIntensityRamp(primary, surface),
      );

  /// Calculate the 5-step intensity ramp for effort rating.
  /// Step 5 is primary at 100% (full strength).
  /// Step 1 is the minimum alpha to reach 1.8:1 contrast with surface.
  /// Steps 2–4 have their contrast against surface spaced evenly between
  /// step 1 and step 5, so contrast strictly increases.
  static IntensityRampPalette _calculateIntensityRamp(
    Color primary,
    Color surface,
  ) {
    // Step 5 is always primary at full opacity (100%)
    final step5 = primary;

    // Calculate step 1: find minimum alpha where composite ≥ 1.8:1 vs surface
    double alpha1 = 0.0;
    for (double testAlpha = 0.05; testAlpha <= 1.0; testAlpha += 0.01) {
      final composite = _compositeColorWithAlpha(primary, surface, testAlpha);
      if (_contrastRatio(composite, surface) >= 1.8) {
        alpha1 = testAlpha;
        break;
      }
    }
    alpha1 = alpha1.clamp(0.05, 0.95);
    final step1 = _compositeColorWithAlpha(primary, surface, alpha1);

    // Get contrast values for step 1 and step 5
    final c1 = _contrastRatio(step1, surface);
    final c5 = _contrastRatio(step5, surface);

    // Steps 2–4 have contrasts evenly spaced between c1 and c5
    // Target contrasts: c1 + (c5 - c1) * (k-1) / 4 for step k
    final targetC2 = c1 + (c5 - c1) * 1 / 4;
    final targetC3 = c1 + (c5 - c1) * 2 / 4;
    final targetC4 = c1 + (c5 - c1) * 3 / 4;

    // Find alphas that produce the target contrasts
    final alpha2 = _findAlphaForTargetContrast(primary, surface, targetC2);
    final alpha3 = _findAlphaForTargetContrast(primary, surface, targetC3);
    final alpha4 = _findAlphaForTargetContrast(primary, surface, targetC4);

    final step2 = _compositeColorWithAlpha(primary, surface, alpha2);
    final step3 = _compositeColorWithAlpha(primary, surface, alpha3);
    final step4 = _compositeColorWithAlpha(primary, surface, alpha4);

    return (
      step1: step1,
      step2: step2,
      step3: step3,
      step4: step4,
      step5: step5,
    );
  }

  /// Linear scan for the alpha whose composite contrast against [surface]
  /// is closest to [targetContrast]. Resolution: 0.005 steps from 0.01 to 0.99.
  static double _findAlphaForTargetContrast(
    Color primary,
    Color surface,
    double targetContrast,
  ) {
    double bestAlpha = 0.1;
    double bestError = double.infinity;

    // Search from 0.01 to 0.99 with 0.005 resolution
    for (double alpha = 0.01; alpha <= 0.99; alpha += 0.005) {
      final composite = _compositeColorWithAlpha(primary, surface, alpha);
      final contrast = _contrastRatio(composite, surface);
      final error = (contrast - targetContrast).abs();

      if (error < bestError) {
        bestError = error;
        bestAlpha = alpha;
      }
    }

    return bestAlpha;
  }

  /// Composite a color with alpha over a background surface (opaque).
  static Color _compositeColorWithAlpha(
    Color foreground,
    Color background,
    double alpha,
  ) {
    final r = (_channel8(foreground.r) * alpha + _channel8(background.r) * (1 - alpha)).round();
    final g =
        (_channel8(foreground.g) * alpha + _channel8(background.g) * (1 - alpha)).round();
    final b = (_channel8(foreground.b) * alpha + _channel8(background.b) * (1 - alpha)).round();
    return Color.fromARGB(255, r, g, b);
  }

  /// Contrast ratio between two colors (WCAG formula).
  /// Calculate WCAG contrast ratio between two colors.
  /// Public API for text color selection and accessibility checks.
  static double contrastRatio(Color color1, Color color2) {
    return _contrastRatio(color1, color2);
  }

  static double _contrastRatio(Color color1, Color color2) {
    final lum1 = _relativeLuminance(color1);
    final lum2 = _relativeLuminance(color2);
    final lighter = lum1 > lum2 ? lum1 : lum2;
    final darker = lum1 > lum2 ? lum2 : lum1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Relative luminance per WCAG (sRGB).
  static double _relativeLuminance(Color color) {
    final r = _linearizeChannel(_channel8(color.r) / 255.0);
    final g = _linearizeChannel(_channel8(color.g) / 255.0);
    final b = _linearizeChannel(_channel8(color.b) / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// A 0–1 color component as an 8-bit channel value (0–255).
  static int _channel8(double component) =>
      (component * 255.0).round().clamp(0, 255);

  /// Linearize an sRGB channel.
  static double _linearizeChannel(double c) {
    return c <= 0.04045
        ? c / 12.92
        : (math.pow((c + 0.055) / 1.055, 2.4) as double);
  }

  static OmniThemeColors colorsForTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.abyssalNeon:
        final primary = Color(0xFF2DE2E6);
        final surface = Color(0xFF102842);
        return (
          backgroundTop: Color(0xFF0F1F33),
          backgroundBottom: Color(0xFF060B14),
          surface: surface,
          primary: primary,
          secondary: Color(0xFF1B9AAA),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF8B98A9),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF36455E),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF0B1424),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
      case AppTheme.forgeEmber:
        final primary = Color(0xFFFF7B45);
        final surface = Color(0xFF3A2712);
        return (
          backgroundTop: Color(0xFF33210F),
          backgroundBottom: Color(0xFF120B06),
          surface: surface,
          primary: primary,
          secondary: Color(0xFFCC4A1A),
          textDominant: Color(0xF0FFF5EA),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFFB4907E),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF574029),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF1A0B05),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
      case AppTheme.obsidianVolt:
        final primary = Color(0xFFE8B420);
        final surface = Color(0xFF262626);
        return (
          backgroundTop: Color(0xFF1E1E1E),
          backgroundBottom: Color(0xFF0D0D0D),
          surface: surface,
          primary: primary,
          secondary: Color(0xFF8A6600),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFFA99868),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF3A3A3A),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF0B0B0B),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
      case AppTheme.voidPulse:
        final primary = Color(0xFFA478FF);
        final surface = Color(0xFF2A2350);
        return (
          backgroundTop: Color(0xFF221C40),
          backgroundBottom: Color(0xFF110D26),
          surface: surface,
          primary: primary,
          secondary: Color(0xFF6D3FD4),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFFA091C6),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF474078),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF0A071A),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
      case AppTheme.crimsonDojo:
        final primary = Color(0xFFFF4C47);
        final surface = Color(0xFF3A1A16);
        return (
          backgroundTop: Color(0xFF331612),
          backgroundBottom: Color(0xFF130806),
          surface: surface,
          primary: primary,
          secondary: Color(0xFFD32F2F),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFFC29380),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF5A2E26),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF1A0606),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
      case AppTheme.malachiteCore:
        final primary = Color(0xFF24B85A);
        final surface = Color(0xFF182E1B);
        return (
          backgroundTop: Color(0xFF102613),
          backgroundBottom: Color(0xFF060C08),
          surface: surface,
          primary: primary,
          secondary: Color(
            0xFF10863E,
          ), // D-14: Corrected to 3.11:1 vs surface, 4.66:1 white label
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF7FAA7F),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF2E4A32),
          surfaceBorder: Color(0x30FFFFFF),
          macroChart: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fiber: _baseFiber,
            fat: _baseFat,
            chartLabelDark: Color(0xFF0C0F0A),
          ),
          stripMacros: (
            protein: _baseProtein,
            carbs: _baseCarbs,
            fat: _baseFat,
          ),
          intensityRamp: intensityRampFor(primary, surface),
        );
    }
  }

  /// Shorthand for the current theme colors.
  static OmniThemeColors get colors => colorsForTheme(activeTheme);

  static String displayNameForTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.abyssalNeon:
        return 'Abyssal Neon';
      case AppTheme.forgeEmber:
        return 'Forge & Ember';
      case AppTheme.obsidianVolt:
        return 'Obsidian Volt';
      case AppTheme.voidPulse:
        return 'Void Pulse';
      case AppTheme.crimsonDojo:
        return 'Crimson Dojo';
      case AppTheme.malachiteCore:
        return 'Malachite Core';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SHADOWS
  // ═══════════════════════════════════════════════════════════

  /// Deep shadow for elevated surfaces
  static BoxShadow get deepShadow => BoxShadow(
    color: Colors.black.withValues(alpha: 0.55),
    blurRadius: 30,
    offset: const Offset(0, 14),
  );

  /// Soft shadow for small, low-elevation surfaces (e.g. the home-screen logo
  /// tile). Proportionally matches the training tiles' inactive shadow
  /// (alpha 0.32, blur 26, spread -8, offset 10) scaled for a ~50px surface.
  /// Uses a neutral black color since small tiles typically lack a per-instance
  /// accent color.
  static BoxShadow get softShadow => BoxShadow(
    color: Colors.black.withValues(alpha: 0.25),
    blurRadius: 5,
    spreadRadius: -3,
    offset: const Offset(-5, 0),
  );

  /// Glow effect for energy cores
  static BoxShadow glowShadow(Color color, {double opacity = 0.35}) =>
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: 24,
        spreadRadius: 0,
      );

  // ═══════════════════════════════════════════════════════════
  // DIMENSIONS
  // ═══════════════════════════════════════════════════════════

  static const double surfaceBorderRadius = 20.0;
  static const double energyCoreSize = 78.0;
  static const double surfaceBorderWidth = 1.0;

  // ═══════════════════════════════════════════════════════════
  // TYPOGRAPHY
  // ═══════════════════════════════════════════════════════════

  static const double titleLetterSpacing = 0.4;
  static const double headerLetterSpacing = 3.0;

  // ═══════════════════════════════════════════════════════════
  // ANIMATION
  // ═══════════════════════════════════════════════════════════

  static const Duration animationDuration = Duration(milliseconds: 180);
  static const Curve animationCurve = Curves.easeInOut;
  static const double pressedScale = 0.9;

  // ═══════════════════════════════════════════════════════════
  // ZEN HALO LOGO
  // ═══════════════════════════════════════════════════════════

  /// Zen Halo gradient colors (aqua cyan sweep)
  static const List<Color> zenHaloColors = [
    Color(0xE600F5FF), // #00F5FF @ 90% opacity
    Color(0xE600C2FF), // #00C2FF @ 90% opacity
    Color(0xE600A8FF), // #00A8FF @ 90% opacity
    Color(0xE600F5FF), // #00F5FF @ 90% (loop)
  ];

  /// Zen Halo stroke width
  static const double zenHaloStrokeWidth = 7.0;

  /// Zen Halo default display size
  static const double zenHaloSize = 160.0;

  /// Event horizon core glow color
  static const Color zenCoreGlowColor = Color(0xFF00CFFF);

  /// Splash screen display duration
  static const Duration splashDuration = Duration(milliseconds: 2800);

  /// Zen Halo stroke draw animation duration
  static const Duration strokeDrawDuration = Duration(milliseconds: 1200);

  /// Zen Halo breathing cycle duration
  static const Duration breathingDuration = Duration(milliseconds: 3000);

  /// Zen Halo rotation cycle duration
  static const Duration rotationDuration = Duration(milliseconds: 8000);

  // ═══════════════════════════════════════════════════════════
  // BACKGROUND TEXTURE
  // ═══════════════════════════════════════════════════════════

  /// Film grain noise overlay opacity (2.5% white - subtle but perceptible)
  static const double backgroundNoiseOpacity = 0.025;

  /// Film grain noise scale in pixels (organic grain size)
  static const double backgroundNoiseScale = 2.0;

  /// Enable background noise texture for premium finish
  static const bool enableBackgroundNoise = false;

  // ═══════════════════════════════════════════════════════════
  // BUTTONS
  // ═══════════════════════════════════════════════════════════

  /// Standard border radius for primary and row-pair buttons.
  /// Matches "Finish Workout" / "Start Workout" reference style.
  static const double buttonBorderRadius = 12.0;

  /// Border radius for compact utility buttons ("+ Add Exercise").
  static const double buttonUtilityRadius = 8.0;

  /// Border radius for square icon-only buttons (FAB-style add).
  static const double buttonIconRadius = 10.0;

  /// Fixed height for full-width primary and row-pair buttons.
  static const double buttonPrimaryHeight = 56.0;

  /// Fixed size for icon-only square buttons.
  static const double buttonIconSize = 60.0;

  /// Shared size for secondary header actions — the trailing
  /// notes / info / discard buttons that sit on the header row
  /// alongside the back arrow. Matches the compact header
  /// action style used elsewhere in the app (calendar `+`
  /// button, period-list add button, etc.) so every secondary
  /// header action — icon-only [IconButton] or labeled
  /// [OutlinedButton] — renders at exactly the same height
  /// regardless of widget type. Keeps the header row visually
  /// aligned across the list ↔ detail navigation without
  /// crowding the title column.
  ///
  /// Pair with [VisualDensity.compact] on the receiving widget
  /// so the [IconButton]s / [OutlinedButton]s settle at 40 dp
  /// instead of the Material default 48 dp tap-target.
  static const double headerSecondaryActionSize = 40.0;

  // ═══════════════════════════════════════════════════════════
  // BOTTOM CTA
  // ═══════════════════════════════════════════════════════════

  /// Horizontal margin applied on each side of every primary
  /// bottom CTA. Keeps the button inset from the screen edge on
  /// both phone and tablet form factors, and matches the column
  /// padding used elsewhere in the app.
  static const double bottomCTAHorizontalPadding = 16.0;

  /// Top padding inside the bottom CTA footer. Sits between the
  /// content above and the CTA so the gradient fade reads as a
  /// deliberate break instead of crowding the button.
  static const double bottomCTAVerticalTopPadding = 24.0;

  /// Bottom padding inside the bottom CTA footer — the gap
  /// between the button's bottom edge and the device's home
  /// indicator / Android nav bar. Combined with `SafeArea(top:
  /// false)` (bottom on by default) this gives a stable
  /// safe-area-aware vertical anchor.
  static const double bottomCTAVerticalBottomPadding = 16.0;

  /// Bottom padding applied to scrollable form bodies so the
  /// last form field is never hidden behind the bottom CTA.
  /// Tuned to the shared CTA footprint
  /// (`bottomCTAVerticalTopPadding` + `buttonPrimaryHeight` +
  /// `bottomCTAVerticalBottomPadding` + breathing room).
  static const double formBottomCTAClearance = 112.0;

  /// Reserved height of the docked rest-timer strip on every workout
  /// surface (the list views and the exercise detail view). When
  /// the strip is visible it always occupies exactly this many
  /// dp above the primary bottom action button, regardless of
  /// which surface is foregrounded. The chip's intrinsic height
  /// is `restOverlayChipHeight`; the rest of the strip is the
  /// breathing room above and below the chip.
  ///
  /// The strip lives in its own reserved horizontal strip so it
  /// never overlaps any other widget; the rest timer reads as a
  /// passive readout that does not compete with primary actions
  /// for the same pixels.
  static const double restStripHeight = 72.0;

  /// Horizontal padding around the rest-timer chip inside the
  /// docked strip. Symmetric — left and right margins match the
  /// bottom CTA's horizontal padding so the chip's bounding box
  /// sits visually aligned with the CTA's footprint.
  static const double restStripHorizontalPadding = 20.0;

  /// Intrinsic rendered height of the rest-overlay chip. The chip
  /// is 48 dp tall (the touch-target floor) plus its own internal
  /// vertical padding, so this matches the chip's own
  /// `constraints(minHeight: 48)` plus its vertical inset.
  static const double restOverlayChipHeight = 48.0;

  /// Bottom offset for the rest-timer overlay chip. The chip is
  /// the single rest indicator used on the session list view and
  /// the exercise detail view.
  ///
  /// **Deprecated** — the chip is no longer a floating overlay.
  /// It is hosted by `RestTimerStrip` (see
  /// `lib/features/session/rest_timer_strip.dart`), which docks
  /// it directly above the primary bottom action button on every
  /// workout surface. Retained so existing imports keep
  /// resolving; new code should use `RestTimerStrip` instead.
  @Deprecated(
    'Use RestTimerStrip (lib/features/session/rest_timer_strip.dart) — '
    'the rest timer is now docked, not floating.',
  )
  static const double restOverlayBottomOffset = 176.0;

  /// Minimum vertical gap between the rest overlay chip and the
  /// top edge of the bottom CTA.
  ///
  /// **Deprecated** — the chip is no longer floating above the
  /// CTA; the docked strip replaces this fixed gap with an
  /// in-flow reserved strip.
  @Deprecated(
    'Use RestTimerStrip (lib/features/session/rest_timer_strip.dart) — '
    'the rest timer is now docked, not floating.',
  )
  static const double kRestOverlayToCTAGap = 80.0;

  // ═══════════════════════════════════════════════════════════
  // LARGE-SCREEN CONTENT COLUMN
  // ═══════════════════════════════════════════════════════════

  /// Maximum width of the centered content column on large-screen
  /// devices (tablets, iPads, large unfolded foldables). Below the
  /// activation threshold the content fills the surface with zero
  /// added side margins; above the threshold the content sits in a
  /// column of [kColumnMaxWidth] dp, horizontally centered, with
  /// equal empty margins on the left and right.
  ///
  /// Tuned to roughly match a large phone (iPhone 16 Pro Max ≈
  /// 430 dp + breathing room), keeping related information visually
  /// close and the dense instrument-panel feel intact on big
  /// screens. The width is a hard cap: it does not grow toward the
  /// screen edges as the surface gets wider.
  static const double kColumnMaxWidth = 480.0;

  /// Minimum surface width at which the centered content column
  /// activates. Any surface below this threshold (every phone class
  /// — including the largest phones at ~430 dp) renders content
  /// full-bleed with no added margins, preserving the existing phone
  /// layout exactly. A foldable in folded (phone-width) state is
  /// below the threshold; an unfolded large foldable or any tablet
  /// is above it.
  ///
  /// Set just above the largest phone width so the cap is fully
  /// inert on phones. Tuned with a small buffer so a future phone
  /// size bump (e.g. 440–460 dp) still does not activate the cap.
  static const double kColumnMinActivationWidth = 500.0;

  // ═══════════════════════════════════════════════════════════
  // TEXT SCALE CLAMP
  // ═══════════════════════════════════════════════════════════

  /// Minimum allowed system text scale factor.
  /// Prevents text from becoming unreadably tiny on small Android devices.
  static const double kTextScaleMin = 1.1;

  /// Maximum allowed system text scale factor.
  /// Above this threshold dense screens (session logger, calendar) remain
  /// usable but feel tighter — accepted tradeoff between aesthetics and
  /// accessibility. Configured once in MaterialApp.builder; never per-screen.
  static const double kTextScaleMax = 1.6;

  // ═══════════════════════════════════════════════════════════
  // TEXT THEME
  // ═══════════════════════════════════════════════════════════

  /// Builds the full application TextTheme.
  ///
  /// All 13 Material 3 roles are specified so that feature code has exactly
  /// one correct path: `Theme.of(context).textTheme.<role>?.copyWith(...)`.
  /// Raw `TextStyle(fontSize: N)` declarations are a review blocker outside
  /// of chart-axis labels — see typography_contract.md.
  static TextTheme buildTextTheme({
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return ThemeData.dark().textTheme.copyWith(
      // Display — hero headings (onboarding splash)
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      // Headlines — section titles, feature page titles
      headlineLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      // Titles — sheet headers, screen names
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: titleLetterSpacing,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      ),
      // Body — descriptions, row content
      bodyLarge: TextStyle(fontSize: 15, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
      bodySmall: TextStyle(fontSize: 13, color: textSecondary),
      // Labels — dense instrumentation, chips, metadata
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        letterSpacing: titleLetterSpacing,
        color: textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        letterSpacing: 0.5,
        color: textSecondary,
      ),
    );
  }
}

/// Per-theme dark on-primary label colors (D-1).
/// These are the authoritative mappings; all theme references derive from here.
Color getOnPrimaryForTheme(AppTheme theme) {
  switch (theme) {
    case AppTheme.abyssalNeon:
      return const Color(0xFF0B1424);
    case AppTheme.forgeEmber:
      return const Color(0xFF1A0B05);
    case AppTheme.obsidianVolt:
      return const Color(0xFF0B0B0B);
    case AppTheme.voidPulse:
      return const Color(0xFF0A071A);
    case AppTheme.crimsonDojo:
      return const Color(0xFF1A0606);
    case AppTheme.malachiteCore:
      return const Color(0xFF0C0F0A);
  }
}

/// Per-theme on-secondary label colors (D-2).
/// Dark for Abyssal Neon; white for all other themes.
/// These are the authoritative mappings; all theme references derive from here.
Color getOnSecondaryForTheme(AppTheme theme) {
  switch (theme) {
    case AppTheme.abyssalNeon:
      return const Color(0xFF0B1424);
    case AppTheme.forgeEmber:
    case AppTheme.obsidianVolt:
    case AppTheme.voidPulse:
    case AppTheme.crimsonDojo:
    case AppTheme.malachiteCore:
      return Colors.white;
  }
}
