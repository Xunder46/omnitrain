import 'package:flutter/material.dart';

enum AppTheme { abyssalNeon, forgeEmber, obsidianVolt, voidPulse, crimsonDojo, malachiteCore }

/// Themed palette for the macro-distribution donut chart. Slots map 1:1
/// to the four sections drawn by `MacroDonutChart`:
///   - `protein`  — high-contrast near-white
///   - `netCarbs`  — saturated blue (net = carbs − fiber)
///   - `fiber`     — saturated green
///   - `fat`       — saturated amber/yellow
///   - `chartLabelDark` — dark text color used for in-band labels
///     when the section color is light (estimated via
///     `ThemeData.estimateBrightnessForColor`). The light counterpart
///     is the theme's `textDominant` token (the existing palette
///     contract does not duplicate it here).
typedef MacroChartPalette = ({
  Color protein,
  Color netCarbs,
  Color fiber,
  Color fat,
  Color chartLabelDark,
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
});

/// Core theme constants for OMNITRAIN biomechanical training system
/// Centralized color palette and design tokens
class OmniTheme {
  static AppTheme activeTheme = AppTheme.abyssalNeon;

  static OmniThemeColors colorsForTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.abyssalNeon:
        return (
          backgroundTop: Color(0xFF0F1F33),
          backgroundBottom: Color(0xFF060B14),
          surface: Color(0xFF0E223A),
          primary: Color(0xFF2DE2E6),
          secondary: Color(0xFF1B9AAA),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF7A8899),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF1F2937),
          surfaceBorder: Color(0x0FFFFFFF),
          macroChart: (
            protein: Color(0xFFEDEDED),
            netCarbs: Color(0xFF4F8DF7),
            fiber: Color(0xFF3FBF67),
            fat: Color(0xFFE8B420),
            chartLabelDark: Color(0xFF0B1424),
          ),
        );
      case AppTheme.forgeEmber:
        return (
          backgroundTop: Color(0xFF1C1008),
          backgroundBottom: Color(0xFF0A0603),
          surface: Color(0xFF211407),
          primary: Color(0xFFFF7B45),
          secondary: Color(0xFFCC4A1A),
          textDominant: Color(0xF0FFF5EA),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF8A5C4E),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF2A1C10),
          surfaceBorder: Color(0x0DFFFFFF),
          macroChart: (
            protein: Color(0xFFEDE3D2),
            netCarbs: Color(0xFF5BA8F2),
            fiber: Color(0xFF54C97A),
            fat: Color(0xFFF2C84B),
            chartLabelDark: Color(0xFF1A0B05),
          ),
        );
      case AppTheme.obsidianVolt:
        return (
          backgroundTop: Color(0xFF111111),
          backgroundBottom: Color(0xFF050505),
          surface: Color(0xFF161616),
          primary: Color(0xFFE8B420),
          secondary: Color(0xFF9C7400),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF6E6240),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF1F1F1F),
          surfaceBorder: Color(0x12FFFFFF),
          macroChart: (
            protein: Color(0xFFEDEDED),
            netCarbs: Color(0xFF4F8DF7),
            fiber: Color(0xFF3FBF67),
            fat: Color(0xFFE8B420),
            chartLabelDark: Color(0xFF0B0B0B),
          ),
        );
      case AppTheme.voidPulse:
        return (
          backgroundTop: Color(0xFF120F24),
          backgroundBottom: Color(0xFF0A071A),
          surface: Color(0xFF110D20),
          primary: Color(0xFFA478FF),
          secondary: Color(0xFF6D3FD4),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF6B5B8A),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF1A1230),
          surfaceBorder: Color(0x0FFFFFFF),
          macroChart: (
            protein: Color(0xFFEDEAFA),
            netCarbs: Color(0xFF6E94F2),
            fiber: Color(0xFF5BC982),
            fat: Color(0xFFE8B420),
            chartLabelDark: Color(0xFF0A071A),
          ),
        );
      case AppTheme.crimsonDojo:
        return (
          backgroundTop: Color(0xFF1A0806),
          backgroundBottom: Color(0xFF080302),
          surface: Color(0xFF3A1A16),
          primary: Color(0xFFFF4C47),
          secondary: Color(0xFFD32F2F),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFFA07060),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF2A0F0C),
          surfaceBorder: Color(0x0DFFFFFF),
          macroChart: (
            protein: Color(0xFFEDE3DE),
            netCarbs: Color(0xFF5BA8F2),
            fiber: Color(0xFF54C97A),
            fat: Color(0xFFF2C84B),
            chartLabelDark: Color(0xFF1A0606),
          ),
        );
      case AppTheme.malachiteCore:
        return (
          backgroundTop: Color(0xFF0D1F10),
          backgroundBottom: Color(0xFF060C08),
          surface: Color(0xFF122214),
          primary: Color(0xFF24B85A),
          secondary: Color(0xFF128A40),
          textDominant: Color(0xF2FFFFFF),
          textSecondary: Color(0x99FFFFFF),
          textMuted: Color(0xFF7FAA7F),
          textDisabled: Color(0x4DFFFFFF),
          divider: Color(0xFF172A18),
          surfaceBorder: Color(0x0DFFFFFF),
          macroChart: (
            protein: Color(0xFFEDEDE7),
            netCarbs: Color(0xFF4F8DF7),
            fiber: Color(0xFF3FBF67),
            fat: Color(0xFFE8B420),
            chartLabelDark: Color(0xFF0C0F0A),
          ),
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

  /// Bottom offset for the rest-timer overlay chip. The chip is the
  /// single rest indicator used on the session list view and the
  /// exercise detail view, so this value is the **shared vertical
  /// anchor** for both screens — the rest indicator must feel like
  /// it lives in one consistent spot.
  ///
  /// Tuned to sit `kRestOverlayToCTAGap` dp above the top edge of
  /// the bottom CTA (CTA footprint is
  /// `bottomCTAVerticalTopPadding` + `buttonPrimaryHeight` +
  /// `bottomCTAVerticalBottomPadding` = 96 dp before SafeArea), so
  /// the chip never crowds the Log Set / Finish Workout button.
  static const double restOverlayBottomOffset = 176.0;

  /// Minimum vertical gap between the rest overlay chip and the
  /// top edge of the bottom CTA. 80 dp — leaves a clear, calm
  /// separation on the smallest supported screen heights without
  /// pushing the chip into the metric content on larger phones.
  static const double kRestOverlayToCTAGap = 80.0;

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
      bodyLarge: TextStyle(
        fontSize: 15,
        color: textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        color: textSecondary,
      ),
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
