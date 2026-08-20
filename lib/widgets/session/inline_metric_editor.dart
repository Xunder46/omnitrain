import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import 'metric_crown_widget.dart';

export 'metric_crown_widget.dart' show MetricStepCalc, showMetricEditPopup;

enum MetricEmphasisTier { dominant, secondary, muted }

/// Metric editor with tap-to-edit popup as the sole value-change mechanism.
///
/// The number itself is the only value-change affordance.
///
/// **Interaction model:**
/// - Number tap:
///   - When [onTap] is provided (e.g. timer-toggle or duration-entry dialog in
///     edit mode): tapping the number calls [onTap].
///   - When [onTap] is null and the editor is not read-only: tapping the number
///     opens [showMetricEditPopup] for exact numeric entry.
///   - When [isReadOnly] is true: no tap or drag affordances are shown.
///
/// The outer [GestureDetector] retains [onTap] for backward-compatible
/// callers that attach timer-toggle handlers.
class InlineMetricEditor extends StatefulWidget {
  /// The metric type: 'reps', 'weight', 'duration', 'rpe', 'extra-weight'
  final String metricType;

  /// Current value to display
  final dynamic currentValue;

  /// Unit label to display (e.g., 'lbs', 'seconds')
  final String unitLabel;

  /// Whether tap-to-edit is disabled.
  /// When true the widget renders as read-only and tapping the value does
  /// nothing.
  final bool isReadOnly;

  /// Optional override color for the unit label.
  final Color? unitLabelColor;

  /// When true, the unit is shown inline beside the value instead of below it.
  final bool showUnitInline;

  /// Optional tap handler.
  ///
  /// When provided, tapping the number value delegates to this callback
  /// instead of opening the generic [showMetricEditPopup].  This is used for
  /// timer-toggle (live timed/round/drill) and duration-entry dialogs (edit
  /// mode).
  ///
  /// The outer [GestureDetector] fires this callback; the inner number-tap
  /// gesture also delegates here when [onTap] is not null.
  final VoidCallback? onTap;

  /// Optional emphasis tier for the main value rendering.
  ///
  /// When omitted, rendering stays backward-compatible with the previous
  /// displayLarge-based styling.
  final MetricEmphasisTier? emphasisTier;

  /// Called when value changes, passes new value
  final Function(dynamic) onValueChanged;

  /// Optional override for the editor's own padding.
  ///
  /// Defaults to a symmetric 32 px inset. Callers that stack another element
  /// directly beneath the value (e.g. the timed/drill status row) trim the
  /// bottom inset so the two read as one group instead of drifting apart.
  final EdgeInsetsGeometry? padding;

  const InlineMetricEditor({
    super.key,
    required this.metricType,
    required this.currentValue,
    required this.unitLabel,
    this.isReadOnly = false,
    this.unitLabelColor,
    this.showUnitInline = false,
    this.onTap,
    this.emphasisTier,
    this.padding,
    required this.onValueChanged,
  });

  @override
  State<InlineMetricEditor> createState() => _InlineMetricEditorState();
}

class _InlineMetricEditorState extends State<InlineMetricEditor> {
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

  void _onNumberTap() {
    if (widget.isReadOnly) return;
    if (widget.onTap != null) {
      // Delegate to caller-supplied handler (e.g. timer toggle, duration dialog).
      widget.onTap!();
    } else {
      // Generic tap-to-edit popup.
      showMetricEditPopup(
        context,
        metricType: widget.metricType,
        currentValue: widget.currentValue,
        unitLabel: widget.unitLabel,
        onValueChanged: widget.onValueChanged,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = _formatValue();

    final baseLarge = theme.textTheme.displayLarge;
    final baseMedium = theme.textTheme.displayMedium ?? baseLarge;

    TextStyle? valueStyle;
    switch (widget.emphasisTier) {
      case MetricEmphasisTier.dominant:
        valueStyle = baseLarge?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: -2,
          color: OmniTheme.colors.textDominant,
        );
      case MetricEmphasisTier.secondary:
        valueStyle = baseMedium?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: -1,
          color: OmniTheme.colors.textSecondary,
        );
      case MetricEmphasisTier.muted:
        valueStyle = baseMedium?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: -1,
          color: OmniTheme.colors.textMuted,
        );
      case null:
        valueStyle = baseLarge?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: -2,
          color: null,
        );
    }

    if (widget.isReadOnly && widget.emphasisTier == null) {
      valueStyle = valueStyle?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha((0.45 * 255).round()),
      );
    }

    final unitStyle = theme.textTheme.labelMedium?.copyWith(
      letterSpacing: 1,
      color:
          widget.unitLabelColor ??
          theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
    );

    // ── Value + unit column ───────────────────────────────────────────────────
    //
    // Wrapped in its own GestureDetector so the tap target is the number/unit
    // area only.  The outer GestureDetector retains [onTap] for callers that
    // use it as a timer-toggle (live timed/round/drill wrapped in a parent
    // GestureDetector).

    Widget valueAndUnit;
    if (widget.showUnitInline && widget.unitLabel.isNotEmpty) {
      valueAndUnit = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
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
      );
    } else {
      valueAndUnit = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayText, textAlign: TextAlign.center, style: valueStyle),
          if (widget.unitLabel.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(widget.unitLabel.toUpperCase(), style: unitStyle),
          ],
        ],
      );
    }

    // Wrap with tap-to-edit gesture (only when not read-only).
    final tappableValue = widget.isReadOnly
        ? valueAndUnit
        : GestureDetector(
            onTap: _onNumberTap,
            behavior: HitTestBehavior.opaque,
            child: valueAndUnit,
          );

    // ── Row: [value+unit] ────────────────────────────────────────────────────

    final contentRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tappableValue,
      ],
    );

    // ── Outer GestureDetector (retains onTap for timer-toggle callers) ────────

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding:
            widget.padding ??
            const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: contentRow,
      ),
    );
  }
}
