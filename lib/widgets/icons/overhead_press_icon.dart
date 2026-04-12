import 'package:flutter/material.dart';

/// Minimalist geometric stick figure performing an overhead barbell press.
///
/// Fully filled rectangular silhouette — no strokes. Style matches the
/// geometric icon language of the other modality tiles.
///
/// ## Integration
/// EnergyCore currently accepts only [IconData] and renders via Flutter's
/// [Icon] widget. To use this custom painter, EnergyCore must be updated to
/// accept an optional [Widget? customIcon] parameter. When [customIcon] is
/// provided, it is rendered instead of the [Icon] widget.
///
/// Usage inside EnergyCore (after update):
/// ```dart
/// EnergyCore(
///   customIcon: OverheadPressIcon(size: size * 0.55),
///   gradientColors: ...,
///   glowColor: ...,
/// )
/// ```
///
/// The widget uses a 240×280 internal canvas (width × height) so the figure
/// fills the available space without clipping the plates at the top or the
/// legs at the bottom. Pass a square [size] — the aspect ratio is handled
/// internally by mapping x and y independently.
class OverheadPressIcon extends StatelessWidget {
  final double size;
  final Color color;

  const OverheadPressIcon({
    super.key,
    required this.size,
    this.color = const Color.fromARGB(255, 231, 231, 231),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _OverheadPressPainter(color: color),
    );
  }
}

class _OverheadPressPainter extends CustomPainter {
  final Color color;

  const _OverheadPressPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Internal reference canvas: 240 wide × 280 tall.
    // x and y scale independently so the figure fills the widget
    // without clipping at any edge.
    double x(double v) => v / 240 * w;
    double y(double v) => v / 280 * h;

    // ── HEAD ──────────────────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(x(124), y(50)),
      w * (19.0 / 240),
      paint,
    );

    // ── TORSO ─────────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(95), y(82), w * (60 / 240), h * (100 / 280)),
      paint,
    );

    // ── LEFT UPPER ARM ────────────────────────────────────────────────────────
    final leftUpperArm = Path()
      ..moveTo(x(103), y(83))
      ..lineTo(x(95), y(110))
      ..lineTo(x(70), y(58))
      ..lineTo(x(85), y(50))
      ..close();
    canvas.drawPath(leftUpperArm, paint);

    // ── LEFT FOREARM ──────────────────────────────────────────────────────────
    final leftForearm = Path()
      ..moveTo(x(72), y(62))
      ..lineTo(x(87), y(55))
      ..lineTo(x(71), y(18))
      ..lineTo(x(52), y(18))
      ..close();
    canvas.drawPath(leftForearm, paint);

    // ── RIGHT UPPER ARM ───────────────────────────────────────────────────────
    final rightUpperArm = Path()
      ..moveTo(x(145), y(83))
      ..lineTo(x(153), y(110))
      ..lineTo(x(176), y(58))
      ..lineTo(x(162), y(50))
      ..close();
    canvas.drawPath(rightUpperArm, paint);

    // ── RIGHT FOREARM ─────────────────────────────────────────────────────────
    final rightForearm = Path()
      ..moveTo(x(174), y(62))
      ..lineTo(x(160), y(55))
      ..lineTo(x(175), y(18))
      ..lineTo(x(194), y(18))
      ..close();
    canvas.drawPath(rightForearm, paint);

    // ── LEFT LEG ──────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(95), y(181), w * (20 / 240), h * (85 / 280)),
      paint,
    );

    // ── RIGHT LEG ─────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(135), y(181), w * (20 / 240), h * (85 / 280)),
      paint,
    );

    // ── BARBELL SHAFT ─────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(2), y(10), w * (240 / 240), h * (9 / 280)),
      paint,
    );

    // ── LEFT PLATE ────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(22), y(-20), w * (15 / 240), h * (70 / 280)),
      paint,
    );

    // ── RIGHT PLATE ────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(208), y(-20), w * (15 / 240), h * (70 / 280)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_OverheadPressPainter old) => old.color != color;
}