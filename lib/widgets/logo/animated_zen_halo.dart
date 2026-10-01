import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import 'zen_halo_painter.dart';

/// Animated Zen Event Horizon Halo
/// Features: stroke-draw animation, slow rotation, breathing pulse, event horizon core
/// Fully configurable and reusable across splash, loading, and session screens
class AnimatedZenHalo extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final List<Color> colors;
  final bool enableRotation;
  final bool enableBreathing;
  final bool animateStroke;

  const AnimatedZenHalo({
    super.key,
    this.size = OmniTheme.zenHaloSize,
    this.strokeWidth = OmniTheme.zenHaloStrokeWidth,
    this.colors = OmniTheme.zenHaloColors,
    this.enableRotation = true,
    this.enableBreathing = true,
    this.animateStroke = true,
  });

  @override
  State<AnimatedZenHalo> createState() => _AnimatedZenHaloState();
}

class _AnimatedZenHaloState extends State<AnimatedZenHalo>
    with TickerProviderStateMixin {
  late AnimationController _strokeController;
  late AnimationController _rotationController;
  late AnimationController _breathingController;

  late Animation<double> _strokeAnimation;
  late Animation<double> _breathingAnimation;

  @override
  void initState() {
    super.initState();

    // Stroke-draw animation (0 → 1, once)
    _strokeController = AnimationController(
      vsync: this,
      duration: OmniTheme.strokeDrawDuration,
    );

    _strokeAnimation = CurvedAnimation(
      parent: _strokeController,
      curve: Curves.easeInOutCubic,
    );

    // Rotation animation (continuous loop)
    _rotationController = AnimationController(
      vsync: this,
      duration: OmniTheme.rotationDuration,
    );

    // Breathing animation (1.0 ↔ 1.04, repeat reverse)
    _breathingController = AnimationController(
      vsync: this,
      duration: OmniTheme.breathingDuration,
    );

    _breathingAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    // Start animations
    if (widget.animateStroke) {
      _strokeController.forward();
    } else {
      _strokeController.value = 1.0; // Skip to full stroke
    }

    if (widget.enableRotation) {
      _rotationController.repeat();
    }

    if (widget.enableBreathing) {
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _strokeController.dispose();
    _rotationController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) {
        return AnimatedBuilder(
          animation: _breathingAnimation,
          builder: (context, child) {
            return AnimatedBuilder(
              animation: _strokeAnimation,
              builder: (context, child) {
                Widget haloWidget = SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Zen Halo Arc
                      CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: ZenHaloPainter(
                          progress: _strokeAnimation.value,
                          strokeWidth: widget.strokeWidth,
                          colors: widget.colors,
                          rotationAngle: widget.enableRotation
                              ? _rotationController.value * 2 * math.pi
                              : 0.0,
                        ),
                      ),
                      // Event Horizon Core (black with cyan glow)
                      Container(
                        width: 10.0,
                        height: 10.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          boxShadow: [
                            BoxShadow(
                              color: OmniTheme.zenCoreGlowColor.withOpacity(
                                0.25,
                              ),
                              blurRadius: 20.0,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                // Apply breathing scale if enabled
                if (widget.enableBreathing) {
                  haloWidget = Transform.scale(
                    scale: _breathingAnimation.value,
                    child: haloWidget,
                  );
                }

                return haloWidget;
              },
            );
          },
        );
      },
    );
  }
}
