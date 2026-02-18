import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Custom painter that generates a subtle film grain noise overlay
/// Creates organic, non-repeating noise for a premium, tactile surface aesthetic
class NoiseOverlayPainter extends CustomPainter {
  final double opacity;
  final double scale;

  NoiseOverlayPainter({
    required this.opacity,
    required this.scale,
  });

  /// Simple pseudo-random noise using Perlin-like approach
  /// Returns value between 0 and 1
  static double _noise(double x, double y) {
    final n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return n - n.floorToDouble();
  }

  /// Smooth interpolation for grain
  static double _fade(double t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  /// Perlin-like noise with smoothing
  static double _perlinNoise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;

    final u = _fade(xf);
    final v = _fade(yf);

    final n00 = _noise(xi.toDouble(), yi.toDouble());
    final n10 = _noise((xi + 1).toDouble(), yi.toDouble());
    final n01 = _noise(xi.toDouble(), (yi + 1).toDouble());
    final n11 = _noise((xi + 1).toDouble(), (yi + 1).toDouble());

    final nx0 = n00 * (1 - u) + n10 * u;
    final nx1 = n01 * (1 - u) + n11 * u;
    return nx0 * (1 - v) + nx1 * v;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    // Generate sparse grain across the entire canvas
    // Larger steps = fewer visible grain particles = more subtle
    final stepSize = scale;
    
    for (double y = 0; y < size.height; y += stepSize) {
      for (double x = 0; x < size.width; x += stepSize) {
        // Generate noise value for this position
        final noiseValue = _perlinNoise(x / scale, y / scale);

        // Draw grain on moderate-to-high noise peaks (balanced visibility)
        if (noiseValue > 0.5) {
          final grainOpacity = ((noiseValue - 0.4) / 0.4) * opacity;
          final dotSize = (noiseValue * 1.2) % 0.8;

          canvas.drawCircle(
            Offset(x, y),
            dotSize,
            paint..color = Colors.white.withOpacity(grainOpacity),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(NoiseOverlayPainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.scale != scale;
  }
}
