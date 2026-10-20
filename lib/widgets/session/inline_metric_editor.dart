import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import 'metric_crown_widget.dart';

export 'metric_crown_widget.dart' show MetricStepCalc, showMetricEditPopup;

/// Font size of the live count-up readout (interval and hold elapsed digits).
const double kCountUpDigitsFontSize = 112;

/// Font size of the ring digits: the `dominant` tier (40 sp) 20% larger.
const double kRingDigitsFontSize = 48;

enum MetricEmphasisTier {
  dominant,
  secondary,
  muted,

  /// The count-up readout, 112 sp ([kCountUpDigitsFontSize]).
  hero,
}

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

  /// Gap between the number and the unit label in the column layout.
  ///
  /// Defaults to 16, the historical spacing, so callers that do not name one
  /// are unchanged; [ValueStepperRow] passes 0 so the label hugs the number.
  final double unitGap;

  /// When true — and the editor is not [isReadOnly] — a dim `tap to type`
  /// line (key `tap-hint`) sits under the unit label.
  final bool showTapHint;

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

  /// Called when the number is tapped (not read-only), before the tap is
  /// handed to [onTap] or the edit popup.
  final VoidCallback? onNumberTap;

  /// Optional emphasis tier for the main value rendering.
  ///
  /// When omitted, rendering stays backward-compatible with the previous
  /// displayLarge-based styling.
  final MetricEmphasisTier? emphasisTier;

  /// Overrides the tier's font size; the ring passes [kRingDigitsFontSize].
  final double? valueFontSize;

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
    this.unitGap = 16,
    this.showTapHint = false,
    this.onTap,
    this.onNumberTap,
    this.emphasisTier,
    this.valueFontSize,
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
        return OmniDateUtils.formatTimerDigits(seconds);
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
    widget.onNumberTap?.call();
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
      case MetricEmphasisTier.hero:
        valueStyle = baseLarge?.copyWith(
          fontSize: kCountUpDigitsFontSize,
          fontWeight: FontWeight.w300,
          letterSpacing: -4,
          height: 1.0,
          color: OmniTheme.colors.textDominant,
        );
      case null:
        valueStyle = baseLarge?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: -2,
          color: null,
        );
    }

    if (widget.valueFontSize != null) {
      valueStyle = valueStyle?.copyWith(fontSize: widget.valueFontSize);
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
          Text(displayText, textAlign: TextAlign.center, style: valueStyle),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(widget.unitLabel.toUpperCase(), style: unitStyle),
          ),
        ],
      );
    } else {
      valueAndUnit = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(displayText, textAlign: TextAlign.center, style: valueStyle),
          if (widget.unitLabel.isNotEmpty) ...[
            SizedBox(height: widget.unitGap),
            Text(
              widget.unitLabel.toUpperCase(),
              textAlign: TextAlign.center,
              style: unitStyle,
            ),
          ],
          if (widget.showTapHint && !widget.isReadOnly) ...[
            const SizedBox(height: 2),
            Text(
              'tap to type',
              key: const Key('tap-hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: OmniTheme.colors.textMuted,
              ),
            ),
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
      children: [tappableValue],
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
