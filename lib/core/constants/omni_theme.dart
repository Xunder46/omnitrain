import 'package:flutter/material.dart';

/// Core theme constants for OMNITRAIN biomechanical training system
/// Centralized color palette and design tokens
class OmniTheme {
  // ═══════════════════════════════════════════════════════════
  // BACKGROUND GRADIENTS
  // ═══════════════════════════════════════════════════════════

  /// Deep cosmic background gradient (top to bottom)
  static const backgroundGradientTop = Color(0xFF0F1F33);
  static const backgroundGradientBottom = Color(0xFF060B14);

  // ═══════════════════════════════════════════════════════════
  // SURFACE COLORS
  // ═══════════════════════════════════════════════════════════

  /// Dark navy surface for cards and panels
  static const surfaceColor = Color(0xFF0E223A);

  /// Subtle inner stroke color for surfaces
  static const surfaceBorderColor = Color(0x0FFFFFFF); // White 6%

  // ═══════════════════════════════════════════════════════════
  // TEXT COLORS
  // ═══════════════════════════════════════════════════════════

  /// Primary text color
  static const textPrimary = Color(0xE6FFFFFF); // White 90%

  /// Secondary text color
  static const textSecondary = Color(0xB3FFFFFF); // White 70%

  // ═══════════════════════════════════════════════════════════
  // SHADOWS
  // ═══════════════════════════════════════════════════════════

  /// Deep shadow for elevated surfaces
  static BoxShadow get deepShadow => BoxShadow(
    color: Colors.black.withOpacity(0.55),
    blurRadius: 30,
    offset: const Offset(0, 14),
  );

  /// Glow effect for energy cores
  static BoxShadow glowShadow(Color color, {double opacity = 0.35}) =>
      BoxShadow(
        color: color.withOpacity(opacity),
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
  static const double pressedScale = 0.96;

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
}
