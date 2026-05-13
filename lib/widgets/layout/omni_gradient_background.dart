import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import 'noise_overlay_painter.dart';

/// Reusable cosmic gradient background with optional radial highlight
/// Used throughout OMNITRAIN for consistent atmosphere
class OmniGradientBackground extends StatelessWidget {
  final Widget child;
  final bool showRadialHighlight;

  const OmniGradientBackground({
    super.key,
    required this.child,
    this.showRadialHighlight = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [themeColors.backgroundTop, themeColors.backgroundBottom],
        ),
      ),
      child: showRadialHighlight
          ? Stack(
              children: [
                // Radial highlight overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.5,
                        colors: [
                          Colors.white.withOpacity(0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Film grain noise overlay (if enabled)
                if (OmniTheme.enableBackgroundNoise)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: NoiseOverlayPainter(
                        opacity: OmniTheme.backgroundNoiseOpacity,
                        scale: OmniTheme.backgroundNoiseScale,
                      ),
                    ),
                  ),
                // Content
                child,
              ],
            )
          : Stack(
              children: [
                // Film grain noise overlay (if enabled)
                if (OmniTheme.enableBackgroundNoise)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: NoiseOverlayPainter(
                        opacity: OmniTheme.backgroundNoiseOpacity,
                        scale: OmniTheme.backgroundNoiseScale,
                      ),
                    ),
                  ),
                // Content
                child,
              ],
            ),
    );
  }
}
