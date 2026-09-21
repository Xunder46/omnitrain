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
      // The large-screen centered column is a built-in behavior of
      // this widget: when the surface is at least
      // `OmniTheme.kColumnMinActivationWidth` dp wide, the `child` is
      // wrapped in a horizontally centered column of
      // `OmniTheme.kColumnMaxWidth` dp. Below the threshold the
      // `child` passes through unchanged, so every phone (and a
      // foldable in folded state) renders byte-for-byte identical
      // to before. Vertical sizes are unaffected at every width —
      // the gradient `Container` and the radial highlight / noise
      // overlays continue to fill the full surface so the
      // atmosphere is unchanged. Because every screen-level route
      // wraps its page in `OmniGradientBackground` (per the
      // navigation contract), and the home / onboarding surfaces
      // are wrapped in the gradient inside `MaterialApp.builder`,
      // the cap reaches every screen automatically with no
      // per-screen logic.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLarge =
              constraints.maxWidth >= OmniTheme.kColumnMinActivationWidth;
          Widget content = child;
          if (isLarge) {
            content = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OmniTheme.kColumnMaxWidth,
                ),
                child: content,
              ),
            );
          }
          return showRadialHighlight
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
                    content,
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
                    content,
                  ],
                );
        },
      ),
    );
  }
}
