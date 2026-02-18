import 'package:flutter/material.dart';

/// Scrollable metric editor for quick value adjustment via vertical drag.
/// Supports reps, weight, duration, and rpe.
/// Changes persist immediately via callback.
class InlineMetricEditor extends StatefulWidget {
  /// The metric type: 'reps', 'weight', 'duration', 'rpe'
  final String metricType;

  /// Current value to display
  final dynamic currentValue;

  /// Unit label to display (e.g., 'lbs', 'seconds')
  final String unitLabel;

  /// Called when value changes, passes new value
  final Function(dynamic) onValueChanged;

  const InlineMetricEditor({
    super.key,
    required this.metricType,
    required this.currentValue,
    required this.unitLabel,
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
        final increment = 2.5; // 2.5 lbs per swipe unit
        final newValue = (current + (change / 10) * increment).clamp(0.0, 999.0);
        return double.parse(newValue.toStringAsFixed(1));
      case 'duration':
        final current = (widget.currentValue as int?) ?? 0;
        final increment = 5; // 5 seconds per swipe unit
        final newValue = (current + (change / 10).round() * increment).clamp(0, 3600);
        return newValue;
      case 'rpe':
        final current = (widget.currentValue as int?) ?? 5;
        final newValue = (current + (change / 20).round()).clamp(1, 10);
        return newValue;
      default:
        return widget.currentValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = _formatValue();

    return GestureDetector(
      onVerticalDragUpdate: (details) {
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
      onVerticalDragEnd: (_) {
        setState(() {
          _accumulatedDelta = 0;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main value display
            Text(
              displayText,
              textAlign: TextAlign.center,
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 16),
            // Unit label
            Text(
              widget.unitLabel.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1,
                color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}