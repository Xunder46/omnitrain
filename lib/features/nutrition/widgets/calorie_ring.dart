// filepath: lib/features/nutrition/widgets/calorie_ring.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// A donut/ring widget that shows today's consumed calories against the
/// daily calorie target. Renders three label branches in the center:
///
///   - target set + consumed > 0 : `consumed / target kcal` (and
///     optionally a "· over by N" caption when consumed > target)
///   - target set + consumed == 0: `0 / target kcal` with the
///     [emptyHint] subtext
///   - target null + consumed > 0: `consumed kcal` with a
///     "no goal set" subtext
///   - target null + consumed == 0: `0 kcal` with the [emptyHint] subtext
///
/// When [target] is null OR `<= 0` the ring renders consumed-only (track
/// only, no goal arc). When [consumed] > [target] the fill is clamped to
/// 1.0 so the arc does not overflow past the track.
///
/// All colors come from [OmniTheme.colors] — no hardcoded values. Safe
/// for any environment that supports the standard Flutter canvas API
/// (web and native).
class CalorieRing extends StatelessWidget {
  /// Today's consumed calories (non-negative). Fractional values are
  /// rounded for display.
  final double consumed;

  /// Daily calorie target, or `null` for consumed-only mode. Values
  /// `<= 0` are also treated as "no target".
  final double? target;

  /// Outer diameter of the ring in logical pixels. Default 160.
  final double size;

  /// Stroke width of the track and arc. Default 14.
  final double strokeWidth;

  /// Subtext shown when consumed is zero (both target set and target
  /// unset). Default "Log a food to start filling".
  final String emptyHint;

  /// Optional widget to render in the center of the ring in place
  /// of the default calories text. When `null` (the default), the
  /// ring renders its standard `consumed / target kcal` view.
  /// When non-null, the override is shown in the same centered
  /// column and the default calories text is hidden.
  ///
  /// Used by `CalorieRingCard` to swap the center to a focused
  /// macro's `MacroFocusContent` while a section is focused.
  final Widget? centerOverride;

  const CalorieRing({
    super.key,
    required this.consumed,
    required this.target,
    this.size = 160,
    this.strokeWidth = 14,
    this.emptyHint = 'Log a food to start filling',
    this.centerOverride,
  });

  /// Returns true when a goal arc should be drawn (target set and > 0).
  bool get _hasTarget => target != null && target! > 0;

  /// Fill fraction, clamped to [0, 1]. Zero when no target.
  double get _fillFraction {
    if (!_hasTarget) return 0;
    final t = target!;
    if (t <= 0) return 0;
    return (consumed / t).clamp(0.0, 1.0).toDouble();
  }

  /// `true` when consumed exceeds target (over-goal). Requires a target.
  bool get _isOver => _hasTarget && consumed > target!;

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final theme = Theme.of(context);
    final consumedRounded = consumed.round();
    final targetRounded = target?.round() ?? 0;

    // Center text style and subtext style
    final centerStyle =
        theme.textTheme.headlineSmall?.copyWith(
          color: themeColors.textDominant,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle();
    final subtextStyle =
        theme.textTheme.bodySmall?.copyWith(color: themeColors.textMuted) ??
        const TextStyle();

    // Compose the center label from the four branches.
    final String primary;
    final String? secondary;
    if (_hasTarget) {
      primary =
          '${_formatThousands(consumedRounded)} / ${_formatThousands(targetRounded)} kcal';
      if (consumedRounded == 0) {
        secondary = emptyHint;
      } else if (_isOver) {
        secondary =
            'over by ${_formatThousands(consumedRounded - targetRounded)}';
      } else {
        secondary = null;
      }
    } else {
      // Consumed-only mode (no target set)
      primary = '${_formatThousands(consumedRounded)} kcal';
      if (consumedRounded == 0) {
        secondary = emptyHint;
      } else {
        secondary = 'no goal set';
      }
    }

    return Semantics(
      container: true,
      label: _semanticLabel(),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The donut track + filled arc.
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                fill: _fillFraction,
                strokeWidth: strokeWidth,
                trackColor: themeColors.divider,
                arcColor: themeColors.primary,
                showArc: _hasTarget,
              ),
            ),
            // The centered label column. When a `centerOverride`
            // is provided, swap the default calories view for the
            // override with a cross-fade. The override is
            // responsible for its own styling.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AnimatedSwitcher(
                duration: OmniTheme.animationDuration,
                child: centerOverride != null
                    ? KeyedSubtree(
                        key: const ValueKey('center_override'),
                        child: centerOverride!,
                      )
                    : KeyedSubtree(
                        key: const ValueKey('center_default'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              primary,
                              textAlign: TextAlign.center,
                              style: centerStyle,
                            ),
                            if (secondary != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                secondary,
                                textAlign: TextAlign.center,
                                style: subtextStyle,
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Comma-grouped integer (e.g. 2,350). Negative values get a leading "-".
  String _formatThousands(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }

  String _semanticLabel() {
    final c = consumed.round();
    if (_hasTarget) {
      return 'Calories: $c of ${target!.round()}';
    }
    return 'Calories: $c, no goal set';
  }
}

// ─── Painter ────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double fill; // 0..1
  final double strokeWidth;
  final Color trackColor;
  final Color arcColor;
  final bool showArc;

  const _RingPainter({
    required this.fill,
    required this.strokeWidth,
    required this.trackColor,
    required this.arcColor,
    required this.showArc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (!showArc || fill <= 0) return;

    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start at the top (12 o'clock) and sweep clockwise.
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.arcColor != arcColor ||
      old.showArc != showArc;
}
