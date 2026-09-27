import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../inputs/numeric_field_with_done_bar.dart';

// ── Parse / clamp math (used by the numeric edit dialog below) ─

/// Static helper that parses and clamps a typed metric value.
class MetricStepCalc {
  MetricStepCalc._();

  /// The largest distance the dialog accepts, in display units.
  static const double maxDistanceUnits = 999.99;

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
      case 'distance':
        return double.parse(
          parsed.clamp(0.0, maxDistanceUnits).toStringAsFixed(2),
        );
      default:
        return parsed;
    }
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
    case 'distance':
      return 'Distance';
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
    case 'distance':
      return ((currentValue as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
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
          signed:
              widget.metricType == 'weight' ||
              widget.metricType == 'extra-weight',
          decimal:
              widget.metricType == 'weight' ||
              widget.metricType == 'extra-weight' ||
              widget.metricType == 'distance',
        ),
        decoration: InputDecoration(labelText: widget.unitLabel),
        textAlign: TextAlign.center,
        autofocus: true,
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
