import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/exercise_metric.dart';

/// The trend line beside an Instruments row: one point per training day the
/// window covers.
///
/// Fewer than two points is not a trend, so this draws nothing at all — no box,
/// no placeholder line, no reserved space — rather than an empty frame.
class InstrumentSparkline extends StatelessWidget {
  final List<ExerciseMetricPoint> points;
  final OmniThemeColors themeColors;

  const InstrumentSparkline({
    super.key,
    required this.points,
    required this.themeColors,
  });

  static const Size _size = Size(56, 24);

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    return SizedBox.fromSize(
      size: _size,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: [for (final point in points) point.value.value],
          color: themeColors.primary,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var min = values.first;
    var max = values.first;
    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final span = max - min;

    final path = Path();
    final step = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      // A flat series has no span to normalise against, so it draws on the
      // centre line instead of dividing by zero.
      final fraction = span == 0 ? 0.5 : (values[i] - min) / span;
      final dx = step * i;
      final dy = size.height - (fraction * size.height);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}
