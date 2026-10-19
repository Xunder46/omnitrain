import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How much width the ring leaves free, so it never touches the screen edges.
const double _kRingHorizontalInset = 64;

/// One sweep, matched to the screen's 1 Hz tick: the ring and the digits move
/// together instead of the ring lagging a second behind.
const Duration _kSweepDuration = Duration(milliseconds: 1000);

/// The digits keep this much of the ring's width free, so they stay inside the
/// circle (the chord at the text's height is narrower than the box).
const double _kRingDigitsInset = 40;

/// Countdown ring for the round effort: a track circle, an arc that empties as
/// the time runs out, and the digits centred inside it.
///
/// The arc sweeps between the screen's ticks: while [running] a falling
/// [progress] animates over a second, linearly. Everything else is applied at
/// once — a stopped ring (nothing to sweep) and a progress that jumps up
/// because the round length was just edited, which must not read as time left.
///
/// The ring is at most [size] across and never wider than the screen minus
/// 64 dp. The child is bounded to the ring's usable chord, the side minus 40 dp,
/// so it stays inside the circle. Colours come from
/// `Theme.of(context).colorScheme` only.
///
/// Plan: `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.md`
/// (D-1). Covered by `test/timer_ring_test.dart`.
class TimerRing extends StatefulWidget {
  /// The remaining fraction, 1.0 (nothing elapsed) down to 0.0 (expired).
  final double progress;

  /// Whether the ring is counting down — only then does it sweep.
  final bool running;

  /// Centred inside the ring: the remaining-time digits.
  final Widget child;

  /// The largest the ring gets; narrow screens shrink it.
  final double size;

  const TimerRing({
    super.key,
    required this.progress,
    required this.running,
    required this.child,
    this.size = 260,
  });

  @override
  State<TimerRing> createState() => _TimerRingState();
}

class _TimerRingState extends State<TimerRing> {
  /// The progress the ring last showed, so the next sweep knows whether the
  /// value fell (sweep) or rose (apply at once).
  late double _target;

  /// The length of the change currently being painted.
  Duration _sweep = Duration.zero;

  @override
  void initState() {
    super.initState();
    _target = widget.progress;
  }

  @override
  void didUpdateWidget(covariant TimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress == oldWidget.progress) return;
    _sweep = widget.running && widget.progress < _target
        ? _kSweepDuration
        : Duration.zero;
    _target = widget.progress;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          widget.size,
          constraints.maxWidth - _kRingHorizontalInset,
        );

        return Semantics(
          label: 'Time remaining',
          container: true,
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _target),
                      duration: _sweep,
                      curve: Curves.linear,
                      builder: (context, progress, _) => CustomPaint(
                        painter: TimerRingPainter(
                          progress: progress,
                          trackColor: scheme.onSurface.withAlpha(51),
                          arcColor: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: side - _kRingDigitsInset,
                  child: widget.child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Paints the ring: a full [trackColor] circle and a [progress]-long
/// [arcColor] arc, clockwise from the top.
///
/// Both strokes are [strokeWidth] wide and sit inside the box, so the round cap
/// of the arc is not clipped at `1.0`.
class TimerRingPainter extends CustomPainter {
  /// The remaining fraction, 1.0 down to 0.0.
  final double progress;

  /// The colour of the circle behind the arc.
  final Color trackColor;

  /// The colour of the remaining-time arc.
  final Color arcColor;

  /// The width of both strokes.
  final double strokeWidth;

  const TimerRingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
    this.strokeWidth = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant TimerRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
