import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../inputs/numeric_field_with_done_bar.dart';

// ── Step / clamp math (shared between MetricCrownWidget and InlineMetricEditor) ─

/// Static helper that encapsulates value-adjustment math for a given
/// [metricType].  The calculation is identical to the original
/// `InlineMetricEditor._calculateNewValue` so behaviour is unchanged.
///
/// [deltaY] is the raw vertical drag delta in logical pixels (positive = down =
/// decrease, negative = up = increase), accumulated since the last step
/// boundary.  The caller is responsible for accumulation; this function is
/// pure.
class MetricStepCalc {
  MetricStepCalc._();

  static dynamic apply(String metricType, dynamic currentValue, double deltaY) {
    // Negative deltaY = swipe up = increase
    // Positive deltaY = swipe down = decrease
    final change = -deltaY;

    switch (metricType) {
      case 'reps':
        final current = (currentValue as int?) ?? 0;
        final newValue = (current + (change / 10).round()).clamp(0, 999);
        return newValue;
      case 'weight':
        final current = (currentValue as double?) ?? 0.0;
        const increment = 0.5;
        final steps = (change / 10).truncate();
        final newValue = (current + steps * increment).clamp(0.0, 999.0);
        return double.parse(newValue.toStringAsFixed(1));
      case 'duration':
        final current = (currentValue as int?) ?? 0;
        const increment = 5;
        final newValue =
            (current + (change / 10).round() * increment).clamp(0, 3600);
        return newValue;
      case 'rpe':
        final current = (currentValue as int?) ?? 5;
        final newValue = (current + (change / 20).round()).clamp(1, 10);
        return newValue;
      case 'extra-weight':
        final current = (currentValue as double?) ?? 0.0;
        const increment = 0.5;
        final steps = (change / 10).truncate();
        final newValue = (current + steps * increment).clamp(-100.0, 200.0);
        return double.parse(newValue.toStringAsFixed(1));
      default:
        return currentValue;
    }
  }

  /// Parse a string as a double and clamp to the metric's valid range.
  /// Returns `null` if the text is empty or cannot be parsed.
  /// For 'reps' returns an [int]; for others returns a [double].
  static dynamic parseAndClamp(String metricType, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Normalise '-0' to '0' before parsing.
    final normalised = trimmed == '-0' ? '0' : trimmed;

    // Accept an optional leading '+' that double.tryParse would reject.
    final withoutLeadingPlus = normalised.startsWith('+')
        ? normalised.substring(1)
        : normalised;

    final parsed = double.tryParse(withoutLeadingPlus);
    if (parsed == null) return null;

    switch (metricType) {
      case 'reps':
        return parsed.round().clamp(0, 999);
      case 'weight':
        return double.parse(parsed.clamp(-200.0, 999.0).toStringAsFixed(1));
      case 'duration':
        return parsed.round().clamp(0, 3600);
      case 'rpe':
        return parsed.round().clamp(1, 10);
      case 'extra-weight':
        return double.parse(parsed.clamp(-100.0, 200.0).toStringAsFixed(1));
      default:
        return parsed;
    }
  }
}

// ── Crown painter ─────────────────────────────────────────────────────────────

class _CrownPainter extends CustomPainter {
  final Color bodyColor;
  final Color borderColor;
  final Color ridgeColor;

  const _CrownPainter({
    required this.bodyColor,
    required this.borderColor,
    required this.ridgeColor,
  });

  static const double _width = 28.0;
  static const double _height = 56.0;
  static const double _rx = 6.0;
  static const int _ridgeCount = 6;

  @override
  void paint(Canvas canvas, Size size) {
    // Centre the crown inside whatever size is given to the CustomPaint.
    final dx = (size.width - _width) / 2;
    final dy = (size.height - _height) / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(dx, dy, _width, _height),
      const Radius.circular(_rx),
    );

    // Body fill
    final bodyPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, bodyPaint);

    // Border stroke
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rect, borderPaint);

    // Ridges — evenly spaced horizontal lines inside the body.
    final ridgePaint = Paint()
      ..color = ridgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final spacing = _height / (_ridgeCount + 1);
    for (int i = 1; i <= _ridgeCount; i++) {
      final y = dy + i * spacing;
      // Inset slightly from the left/right edges.
      canvas.drawLine(
        Offset(dx + 4, y),
        Offset(dx + _width - 4, y),
        ridgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CrownPainter old) =>
      old.bodyColor != bodyColor ||
      old.borderColor != borderColor ||
      old.ridgeColor != ridgeColor;
}

// ── MetricCrownWidget ─────────────────────────────────────────────────────────

/// Rotation factor: 2π radians per [_kPixelsPerRevolution] logical pixels of
/// drag travel.
const double _kPixelsPerRevolution = 120.0;
const double _kRotationFactor = 2 * math.pi / _kPixelsPerRevolution;

/// A vertical thumb-wheel (crown) control that adjusts a numeric metric value
/// by dragging.
///
/// - Dragging the crown fires [onValueChanged] using the same step/clamp math
///   as the original drag-on-number interaction.
/// - The crown rotates proportionally to drag distance (~2× travel), stopping
///   immediately on release.  There is NO momentum or idle animation.
/// - Visual styling uses neutral [OmniTheme] tokens regardless of the parent
///   emphasis tier.
class MetricCrownWidget extends StatefulWidget {
  /// One of: 'reps', 'weight', 'duration', 'rpe', 'extra-weight'.
  final String metricType;

  /// The current value; read on each drag tick to compute the next value.
  final dynamic currentValue;

  /// Called with the new value whenever a drag step fires.
  final Function(dynamic) onValueChanged;

  const MetricCrownWidget({
    super.key,
    required this.metricType,
    required this.currentValue,
    required this.onValueChanged,
  });

  @override
  State<MetricCrownWidget> createState() => MetricCrownWidgetState();
}

/// Exposed as public so tests can access [rotationAngle] via a [GlobalKey].
class MetricCrownWidgetState extends State<MetricCrownWidget> {
  double _accumulatedDelta = 0.0;
  double _rotationAngle = 0.0; // radians; never resets, accumulates for life of the widget

  /// The current rotation angle in radians.  Exposed for tests.
  double get rotationAngle => _rotationAngle;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _accumulatedDelta += details.delta.dy;
      // Update rotation angle continuously.
      _rotationAngle += details.delta.dy * _kRotationFactor;

      // Fire value change every 10 px of accumulated drag.
      if (_accumulatedDelta.abs() >= 10) {
        final newValue = MetricStepCalc.apply(
          widget.metricType,
          widget.currentValue,
          _accumulatedDelta,
        );
        if (newValue != widget.currentValue) {
          widget.onValueChanged(newValue);
        }
        _accumulatedDelta = 0;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _accumulatedDelta = 0;
      // Do NOT reset _rotationAngle — the crown holds its position.
      // Do NOT fire any further value changes.
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = OmniTheme.colors;
    final bodyColor = colors.textMuted.withAlpha((0.20 * 255).round());
    final borderColor = colors.textSecondary.withAlpha((0.30 * 255).round());
    final ridgeColor = colors.textSecondary.withAlpha((0.40 * 255).round());

    return GestureDetector(
      key: Key('crown-metric-${widget.metricType}'),
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 60,
        child: Center(
          child: Transform.rotate(
            angle: _rotationAngle,
            child: CustomPaint(
              size: const Size(44, 60),
              painter: _CrownPainter(
                bodyColor: bodyColor,
                borderColor: borderColor,
                ridgeColor: ridgeColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── showMetricEditPopup ───────────────────────────────────────────────────────

String _titleForMetric(String metricType) {
  switch (metricType) {
    case 'reps':
      return 'Reps';
    case 'weight':
      return 'Weight';
    case 'duration':
      return 'Duration';
    case 'rpe':
      return 'RPE';
    case 'extra-weight':
      return 'Extra Weight';
    default:
      return metricType;
  }
}

String _formatCurrentValue(String metricType, dynamic currentValue) {
  if (currentValue == null) return '0';
  switch (metricType) {
    case 'reps':
      return (currentValue as int?)?.toString() ?? '0';
    case 'weight':
      return (currentValue as double?)?.toStringAsFixed(1) ?? '0.0';
    case 'duration':
      return (currentValue as int?)?.toString() ?? '0';
    case 'rpe':
      return (currentValue as int?)?.toString() ?? '5';
    case 'extra-weight':
      final ew = (currentValue as double?) ?? 0.0;
      return ew.toStringAsFixed(1);
    default:
      return currentValue.toString();
  }
}

/// Opens a small dialog for exact numeric entry of a metric value.
///
/// - Pre-fills the field with [currentValue].
/// - Ok: parses + clamps the typed value, calls [onValueChanged], closes.
/// - Tapping outside the dialog (barrier dismiss) closes without calling
///   [onValueChanged].
/// - If text is empty or unparseable, closes without calling [onValueChanged].
///
/// When [widget.onTap] is provided on [InlineMetricEditor], the number taps
/// that callback instead; [showMetricEditPopup] is only wired when no custom
/// onTap is present.
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MetricEditDialog(
      metricType: metricType,
      currentValue: currentValue,
      unitLabel: unitLabel,
      onValueChanged: onValueChanged,
    ),
  );
}

/// Internal dialog widget that owns the [TextEditingController] lifecycle.
class _MetricEditDialog extends StatefulWidget {
  final String metricType;
  final dynamic currentValue;
  final String unitLabel;
  final Function(dynamic) onValueChanged;

  const _MetricEditDialog({
    required this.metricType,
    required this.currentValue,
    required this.unitLabel,
    required this.onValueChanged,
  });

  @override
  State<_MetricEditDialog> createState() => _MetricEditDialogState();
}

class _MetricEditDialogState extends State<_MetricEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatCurrentValue(widget.metricType, widget.currentValue),
    );
    // Select-all on focus is handled by `NumericFieldWithDoneBar`'s
    // built-in `selectAllOnFocus: true` default (the wrapper creates
    // a `SelectAllOnFocusNode` internally when it owns the focus
    // node). No local one-shot select-all is needed here.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${_titleForMetric(widget.metricType)}'),
      content: NumericFieldWithDoneBar(
        controller: _controller,
        keyboardType: TextInputType.numberWithOptions(
          signed: widget.metricType == 'weight' ||
              widget.metricType == 'extra-weight',
          decimal: widget.metricType == 'weight' ||
              widget.metricType == 'extra-weight',
        ),
        decoration: InputDecoration(
          labelText: widget.unitLabel,
        ),
        textAlign: TextAlign.center,
        onChanged: (_) {},
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          ),
          onPressed: () {
            final parsed = MetricStepCalc.parseAndClamp(
              widget.metricType,
              _controller.text,
            );
            if (parsed != null) {
              widget.onValueChanged(parsed);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Ok'),
        ),
      ],
    );
  }
}
