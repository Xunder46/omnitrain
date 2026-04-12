import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Circular energy core with radial gradient and glow
/// Represents the biomechanical power source for each training modality
class EnergyCore extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final List<Color> gradientColors;
  final Color glowColor;
  final bool isActive;
  final double size;

  const EnergyCore({
    super.key,
    this.icon,
    this.iconWidget,
    required this.gradientColors,
    required this.glowColor,
    this.isActive = false,
    this.size = OmniTheme.energyCoreSize,
  });

  @override
  Widget build(BuildContext context) {
    // Enhanced glow when active
    final glowOpacity = isActive ? 0.45 : 0.35;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: gradientColors,
          center: Alignment.topLeft,
          radius: 1.2,
        ),
        boxShadow: [
          OmniTheme.glowShadow(glowColor, opacity: glowOpacity),
        ],
      ),
      child: iconWidget ?? Icon(
        icon!,
        size: size * 0.4, // Icon is 40% of core size
        color: OmniTheme.textPrimary,
      ),
    );
  }
}
