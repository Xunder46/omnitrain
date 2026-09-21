import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter for the Zen Event Horizon Halo
/// Draws an imperfect Enso-style arc with gradient and taper effect
class ZenHaloPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0 (stroke draw animation)
  final double strokeWidth;
  final List<Color> colors;
  final double rotationAngle; // In radians

  ZenHaloPainter({
    required this.progress,
    required this.strokeWidth,
    required this.colors,
    this.rotationAngle = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2);

    // Create the Enso arc path (leaving ~19% gap = ~290° sweep = 5.06 radians)
    final sweepAngle = 5.06; // radians (~290°)
    final baseStartAngle = -math.pi / 2; // Start at top

    // Apply rotation to the arc itself
    final startAngle = baseStartAngle + rotationAngle;

    // Only draw the portion revealed by progress
    final currentSweep = sweepAngle * progress;

    if (currentSweep <= 0) return;

    // Create sweep gradient (also rotated to match arc)
    final gradient = SweepGradient(
      colors: colors,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      transform: GradientRotation(rotationAngle),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = gradient.createShader(rect);

    // Main arc with full stroke width
    final mainPaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final path = Path();
    path.addArc(rect, startAngle, currentSweep);
    canvas.drawPath(path, mainPaint);

    // Taper effect: draw thinner arc at the tail (last ~8% of stroke)
    if (progress > 0.92) {
      final taperProgress = (progress - 0.92) / 0.08;
      final taperSweep = sweepAngle * 0.08 * taperProgress;
      final taperStartAngle = startAngle + (currentSweep - taperSweep);

      final taperPaint = Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            strokeWidth *
            0.43 // Taper to ~43% of original
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      final taperPath = Path();
      taperPath.addArc(rect, taperStartAngle, taperSweep);
      canvas.drawPath(taperPath, taperPaint);
    }
  }

  @override
  bool shouldRepaint(ZenHaloPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.colors != colors;
  }
}
