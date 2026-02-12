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
  static BoxShadow glowShadow(Color color, {double opacity = 0.35}) => BoxShadow(
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
}
