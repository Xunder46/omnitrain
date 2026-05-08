import 'package:flutter/material.dart';

/// Scrollable metric editor for quick value adjustment via vertical drag.
/// Supports reps, weight, duration, rpe, and extra-weight.
/// Changes persist immediately via callback.
class InlineMetricEditor extends StatefulWidget {
  /// The metric type: 'reps', 'weight', 'duration', 'rpe', 'extra-weight'
  final String metricType;

  /// Current value to display
  final dynamic currentValue;

  /// Unit label to display (e.g., 'lbs', 'seconds')
  final String unitLabel;

  /// Whether user interaction (drag) is disabled.
  /// When true the widget renders as read-only: drags are ignored and the
  /// value text is dimmed to signal that editing is not available.
  final bool isReadOnly;

  /// Optional override color for the unit label.
  final Color? unitLabelColor;

  /// When true, the unit is shown inline beside the value instead of below it.
  final bool showUnitInline;

  /// Optional tap handler.  Coexists with the vertical-drag handler on the
  /// underlying [GestureDetector]; Flutter's gesture arena disambiguates
  /// short press-lifts (tap) from drags (movement).
  final VoidCallback? onTap;

  /// Called when value changes, passes new value
  final Function(dynamic) onValueChanged;

  const InlineMetricEditor({
    super.key,
    required this.metricType,
    required this.currentValue,
    required this.unitLabel,
    this.isReadOnly = false,
    this.unitLabelColor,
    this.showUnitInline = false,
    this.onTap,
    required this.onValueChanged,
  });

  @override
  State<InlineMetricEditor> createState() => _InlineMetricEditorState();
}

class _InlineMetricEditorState extends State<InlineMetricEditor> {
  double _accumulatedDelta = 0.0;

  String _formatValue() {
    if (widget.currentValue == null) return '0';

    switch (widget.metricType) {
      case 'reps':
        return (widget.currentValue as int?)?.toString() ?? '0';
      case 'weight':
        return (widget.currentValue as double?)?.toStringAsFixed(1) ?? '0.0';
      case 'duration':
        final seconds = widget.currentValue as int? ?? 0;
        final minutes = seconds ~/ 60;
        final secs = seconds % 60;
        return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      case 'rpe':
        return (widget.currentValue as int?)?.toString() ?? '5';
      case 'extra-weight':
        final ew = (widget.currentValue as double?) ?? 0.0;
        final sign = ew > 0 ? '+' : '';
        return '$sign${ew.toStringAsFixed(1)}';
      default:
        return widget.currentValue.toString();
    }
  }

  dynamic _calculateNewValue(double deltaY) {
    // Negative deltaY = swipe up = increase
    // Positive deltaY = swipe down = decrease
    final change = -deltaY;

    switch (widget.metricType) {
      case 'reps':
        final current = (widget.currentValue as int?) ?? 0;
        final newValue = (current + (change / 10).round()).clamp(0, 999);
        return newValue;
      case 'weight':
        final current = (widget.currentValue as double?) ?? 0.0;
        final increment = 0.5; // 0.5 kg/lbs per swipe step
        final steps = (change / 10).truncate();
        final newValue = (current + steps * increment).clamp(0.0, 999.0);
        return double.parse(newValue.toStringAsFixed(1));
      case 'duration':
        final current = (widget.currentValue as int?) ?? 0;
        final increment = 5; // 5 seconds per swipe unit
        final newValue = (current + (change / 10).round() * increment).clamp(
          0,
          3600,
        );
        return newValue;
      case 'rpe':
        final current = (widget.currentValue as int?) ?? 5;
        final newValue = (current + (change / 20).round()).clamp(1, 10);
        return newValue;
      case 'extra-weight':
        final current = (widget.currentValue as double?) ?? 0.0;
        final increment = 0.5; // 0.5 kg/lbs per swipe step
        final steps = (change / 10).truncate();
        final newValue = (current + steps * increment).clamp(-100.0, 200.0);
        return double.parse(newValue.toStringAsFixed(1));
      default:
        return widget.currentValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = _formatValue();

    final valueStyle = theme.textTheme.displayLarge?.copyWith(
      fontWeight: FontWeight.w300,
      letterSpacing: -2,
      color: widget.isReadOnly
          ? theme.colorScheme.onSurface.withAlpha((0.45 * 255).round())
          : null,
    );
    final unitStyle = theme.textTheme.labelMedium?.copyWith(
      letterSpacing: 1,
      color:
          widget.unitLabelColor ??
          theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
    );

    return GestureDetector(
      onTap: widget.onTap,
      onVerticalDragUpdate: widget.isReadOnly
          ? null
          : (details) {
              setState(() {
                _accumulatedDelta += details.delta.dy;

                // Update value every 10 pixels of drag
                if (_accumulatedDelta.abs() >= 10) {
                  final newValue = _calculateNewValue(_accumulatedDelta);
                  if (newValue != widget.currentValue) {
                    widget.onValueChanged(newValue);
                  }
                  _accumulatedDelta = 0;
                }
              });
            },
      onVerticalDragEnd: widget.isReadOnly
          ? null
          : (_) {
              setState(() {
                _accumulatedDelta = 0;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showUnitInline && widget.unitLabel.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayText,
                    textAlign: TextAlign.center,
                    style: valueStyle,
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      widget.unitLabel.toUpperCase(),
                      style: unitStyle,
                    ),
                  ),
                ],
              )
            else
              Text(displayText, textAlign: TextAlign.center, style: valueStyle),
            if (!widget.showUnitInline && widget.unitLabel.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(widget.unitLabel.toUpperCase(), style: unitStyle),
            ],
          ],
        ),
      ),
    );
  }
}
