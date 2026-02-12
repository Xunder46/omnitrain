import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../layout/omni_surface.dart';
import 'energy_core.dart';

/// Premium training category tile with energy core visualization
/// Features biomechanical aesthetic with depth and subtle animations
class EnergyTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final bool isActive;

  const EnergyTile({
    super.key,
    required this.title,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<EnergyTile> createState() => _EnergyTileState();
}

class _EnergyTileState extends State<EnergyTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? OmniTheme.pressedScale : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: scale,
        duration: OmniTheme.animationDuration,
        curve: OmniTheme.animationCurve,
        child: _buildSurface(),
      ),
    );
  }

  Widget _buildSurface() {
    // Active tile has enhanced border and glow effect
    if (widget.isActive) {
      return Container(
        decoration: BoxDecoration(
          color: OmniTheme.surfaceColor,
          borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
          // Active border - brightened and thicker
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 2.0,
          ),
          boxShadow: [
            OmniTheme.deepShadow,
            // Additional glow for active state
            BoxShadow(
              color: widget.gradientColors.first.withOpacity(0.25),
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: _buildContent(),
      );
    }

    // Inactive tile uses standard OmniSurface
    return OmniSurface(
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Energy core with enhanced glow when active
        EnergyCore(
          icon: widget.icon,
          gradientColors: widget.gradientColors,
          glowColor: widget.gradientColors.first,
          isActive: _isPressed || widget.isActive,
        ),
        const SizedBox(height: 20),
        // Title text
        Text(
          widget.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: OmniTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: OmniTheme.titleLetterSpacing,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
