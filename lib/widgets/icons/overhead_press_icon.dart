import 'package:flutter/material.dart';

import '../../core/constants/tile_artwork_metrics.dart';

/// Minimalist geometric stick figure performing an overhead barbell press.
///
/// Fully filled rectangular silhouette — no strokes. Style matches the
/// geometric icon language of the other modality tiles.
///
/// ## Integration
/// Tiles never construct this widget at a fixed size. A tile definition
/// references [artwork] as a [TileArtworkBuilder]; the tile resolves the size
/// from [TileArtworkMetrics] and calls the builder with it, so this figure
/// scales and drops out at exactly the same points as a standard [Icon].
///
/// ```dart
/// HomeTileConfig(
///   key: 'resistance',
///   artworkBuilder: OverheadPressIcon.artwork,
///   ...
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

  /// [TileArtworkBuilder] adapter. Referenced as a tear-off from tile
  /// definitions so the definition never states a size.
  static Widget artwork(double size, Color color) =>
      OverheadPressIcon(size: size, color: color);

  /// How far the barbell plates overshoot the top of the widget's box, as a
  /// fraction of [size].
  ///
  /// The plates start at y = -20 on the 240×280 reference canvas, which is
  /// deliberate — it is what makes the barbell read as held overhead rather
  /// than resting on the figure's head. Exposed so the tile-bounds test can
  /// assert the overshoot still lands inside the tile's own padding instead
  /// of hard-coding the ratio in the test.
  static const double topOvershootRatio = 20 / 280;

  /// How far the barbell shaft overshoots the right of the widget's box, as
  /// a fraction of [size]. The shaft is drawn a full reference-canvas width
  /// starting at x = 2, so it runs 2 units past the right edge.
  static const double rightOvershootRatio = 2 / 240;

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
    canvas.drawCircle(Offset(x(124), y(50)), w * (19.0 / 240), paint);

    // ── TORSO ─────────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(95), y(82), w * (60 / 240), h * (105 / 280)),
      paint,
    );

    // ── LEFT UPPER ARM ────────────────────────────────────────────────────────
    final leftUpperArm = Path()
      ..moveTo(x(103), y(83))
      ..lineTo(x(95), y(110))
      ..lineTo(x(70), y(58))
      ..lineTo(x(86), y(50))
      ..close();
    canvas.drawPath(leftUpperArm, paint);

    // ── LEFT FOREARM ──────────────────────────────────────────────────────────
    final leftForearm = Path()
      ..moveTo(x(72), y(62))
      ..lineTo(x(88), y(55))
      ..lineTo(x(72), y(18))
      ..lineTo(x(52), y(18))
      ..close();
    canvas.drawPath(leftForearm, paint);

    // ── RIGHT UPPER ARM ───────────────────────────────────────────────────────
    final rightUpperArm = Path()
      ..moveTo(x(145), y(83))
      ..lineTo(x(153), y(110))
      ..lineTo(x(176), y(58))
      ..lineTo(x(161), y(50))
      ..close();
    canvas.drawPath(rightUpperArm, paint);

    // ── RIGHT FOREARM ─────────────────────────────────────────────────────────
    final rightForearm = Path()
      ..moveTo(x(174), y(62))
      ..lineTo(x(159), y(55))
      ..lineTo(x(174), y(18))
      ..lineTo(x(194), y(18))
      ..close();
    canvas.drawPath(rightForearm, paint);

    // ── LEFT LEG ──────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(95), y(186), w * (20 / 240), h * (80 / 280)),
      paint,
    );

    // ── RIGHT LEG ─────────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(x(135), y(186), w * (20 / 240), h * (80 / 280)),
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
