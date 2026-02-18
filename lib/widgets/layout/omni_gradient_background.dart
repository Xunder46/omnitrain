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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            OmniTheme.backgroundGradientTop,
            OmniTheme.backgroundGradientBottom,
          ],
        ),
      ),
      child: showRadialHighlight
          ? Stack(
              children: [
                // Radial highlight overlay
                Container(
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
                // Film grain noise overlay (if enabled)
                if (OmniTheme.enableBackgroundNoise)
                  CustomPaint(
                    painter: NoiseOverlayPainter(
                      opacity: OmniTheme.backgroundNoiseOpacity,
                      scale: OmniTheme.backgroundNoiseScale,
                    ),
                    child: Container(),
                  ),
                // Content
                child,
              ],
            )
          : Stack(
              children: [
                // Film grain noise overlay (if enabled)
                if (OmniTheme.enableBackgroundNoise)
                  CustomPaint(
                    painter: NoiseOverlayPainter(
                      opacity: OmniTheme.backgroundNoiseOpacity,
                      scale: OmniTheme.backgroundNoiseScale,
                    ),
                    child: Container(),
                  ),
                // Content
                child,
              ],
            ),
    );
  }
}
