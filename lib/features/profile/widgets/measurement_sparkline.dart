import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/constants/profile_measurements.dart';
import '../../../core/utils/chart_axis_helper.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../data/models/models.dart';
import '../../../state/profile/profile_state.dart';
import '../../../state/settings/settings_state.dart';

/// Small history visualization for a single body measurement.
///
/// Renders one of three states based on the entry count read from
/// [ProfileState.getMeasurementHistory]:
///
/// - **0 entries** — centered muted text `"No history yet"`.
/// - **1 entry** — the same full chart frame as the 2+ case
///   (Y-axis line, X-axis line, Y-axis scale labels, X-axis date
///   strip) with **a single horizontal line** crossing **a single
///   filled dot** at the entry's value. Both Y-axis labels show the
///   same value (since minV == maxV); both X-axis labels show the
///   same date (since minMs == maxMs). This replaces the legacy
///   `Divider`-only hairline so the chart frame stays visually
///   stable across all three entry-count branches (0, 1, 2+).
/// - **2+ entries** — a compact chart inside a 60 dp container:
///   - **Axes**: a vertical Y-axis line on the **left** of the chart
///     area (boundary between the y-axis label column and the data
///     area) and a horizontal X-axis line at the **bottom** of the
///     chart area (boundary between the data area and the x-axis
///     date strip). Both are 1 dp `theme.dividerColor` strokes.
///   - **Y-axis scale**: a max value label at top-LEFT and a min
///     value label at bottom-LEFT of the chart area (in the
///     y-axis label column to the left of the Y-axis line),
///     rendered in `labelSmall` + `textMuted` + 9 pt. The value is
///     the **display-unit** value: a `unit-kg` measurement is
///     converted from canonical kilograms to the active weight unit
///     (kg/lbs) via `UnitFormatter`, matching the history sheet, and
///     every other measurement is plotted as stored. Format is
///     `ProfileMeasurements.formatValue` (integer when whole, else
///     one decimal) — the unit is intentionally **omitted** because
///     the header above the card (`BODY WEIGHT` / `HEIGHT` / etc.)
///     already names the measurement, and the value column to the
///     right shows the current value WITH its unit (e.g. `159 lbs`).
///     Adding the unit to the axis label would crowd the 38 dp LEFT
///     column and force a smaller font; dropping the unit lets the
///     label fit comfortably at the same font size as the x-axis date
///     labels. `overflow: TextOverflow.ellipsis` clips gracefully
///     if the column is too narrow for any edge case.
///   - **X-axis scale**: a first date label at bottom-left and a
///     last date label at bottom-right via
///     [ChartAxisHelper.formatDateLabel] (`MMM d`, e.g. `Jun 17`).
///     The labels live in the bottom 12 dp of the container; the
///     area lives in the top 38 dp.
///   - **Line + dots**: `theme.colorScheme.primary` 1.5 dp stroke
///     line through the points with a 2 dp filled dot at **every**
///     entry. X positioning is **time-based** (each entry's
///     `recordedAtMs` is mapped linearly across the chart width),
///     so two entries months apart sit at the chart's leftmost and
///     rightmost x positions while many entries clustered in time
///     sit close together. Falls back to mid-width when all
///     timestamps are equal.
///
/// The whole sparkline area is wrapped in an [InkWell] with the
/// caller-supplied [onTap] so tapping anywhere opens the existing
/// history sheet (see `MeasurementHistoryChartSheet`).
///
/// **Refresh model**: the entry list is loaded asynchronously in
/// [State.initState]. The widget subscribes to [profileState] in
/// `initState` (removed in [State.dispose]) and re-fetches whenever
/// `profileState.notifyListeners` fires. When the parent rebuilds
/// with a different `definition.type`, [State.didUpdateWidget] also
/// reloads. The listener is the only reliable way to refresh the
/// chart after a new measurement is added via the log sheet —
/// `didUpdateWidget` would not fire when the host rebuilds with the
/// same `definition` (the common case after a save). See the plan's
/// Phase 4 verification for the regression test that exercises this.
///
/// Sized at **60 dp tall** (A18 final; was 56 dp intermediate, 38 dp
/// before axes, 60 dp pre-A17). The chart now fills the entire
/// card row — the user wanted the chart to use the available
/// vertical space rather than sit with breathing room. Card total
/// height stays 88 dp (60 dp chart + 28 dp card padding).
///
/// Presentation-only: no repository access of its own (delegates to
/// the injected [ProfileState]), no service access, no business logic.
class MeasurementSparkline extends StatefulWidget {
  const MeasurementSparkline({
    super.key,
    required this.definition,
    required this.profileState,
    required this.settingsState,
    this.onTap,
  });

  /// Which measurement to read history for (e.g., bodyweight, height).
  final ProfileMeasurementDefinition definition;

  /// Source of the measurement history (loaded via `getMeasurementHistory`).
  final ProfileState profileState;

  /// The active unit preferences. Only the weight unit is read: a
  /// `unit-kg` measurement is converted from canonical kilograms to the
  /// preferred unit (kg/lbs) before the chart plots and labels it, matching
  /// `MeasurementHistoryChartSheet`. Every other measurement is plotted in
  /// its stored unit.
  final SettingsState settingsState;

  /// Tapping anywhere inside the sparkline area fires this callback.
  /// The caller wires it to `_showMeasurementHistory(definition)`.
  final VoidCallback? onTap;

  @override
  State<MeasurementSparkline> createState() => _MeasurementSparklineState();
}

class _MeasurementSparklineState extends State<MeasurementSparkline> {
  Future<List<BodyMeasurementEntry>>? _entriesFuture;

  @override
  void initState() {
    super.initState();
    // Subscribe to profileState so the sparkline refreshes when a new
    // measurement is added via the log sheet (Phase 4 review feedback —
    // didUpdateWidget is a no-op when the parent rebuilds with the same
    // `definition.type`, so a listener is the only reliable way to
    // re-fetch the history).
    widget.profileState.addListener(_onProfileStateChanged);
    _loadEntries();
  }

  @override
  void dispose() {
    widget.profileState.removeListener(_onProfileStateChanged);
    super.dispose();
  }

  void _onProfileStateChanged() {
    if (!mounted) return;
    _loadEntries();
  }

  @override
  void didUpdateWidget(covariant MeasurementSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition.type != widget.definition.type) {
      _loadEntries();
    }
  }

  void _loadEntries() {
    setState(() {
      _entriesFuture = widget.profileState.getMeasurementHistory(
        widget.definition.type,
      );
    });
  }

  /// Canonical → display value for one entry, in the active unit.
  ///
  /// `unit-kg` measurements are stored in kilograms and convert to the
  /// preferred weight unit; every other measurement is plotted in its stored
  /// unit. Mirrors `MeasurementHistoryChartSheet._toChartValue` so the quick
  /// chart and the history sheet never disagree on the scale.
  double _toChartValue(BodyMeasurementEntry entry) {
    if (entry.unitId == 'unit-kg') {
      return UnitFormatter.convertWeight(entry.value, widget.settingsState);
    }
    return entry.value;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('measurement_sparkline'),
      height: 60,
      child: InkWell(
        key: const Key('measurement_sparkline_tap'),
        onTap: widget.onTap,
        child: FutureBuilder<List<BodyMeasurementEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final entries = snapshot.data!;
            if (entries.isEmpty) return _emptyState(context);
            // 1 entry: the painter renders the full chart frame
            // (axes + scale + a horizontal line + a single dot).
            // 2+ entries: the painter renders the line + dots.
            // The chart frame is identical across both branches.
            return _lineChart(context, entries);
          },
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Text(
        'No history yet',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: OmniTheme.colors.textMuted),
      ),
    );
  }

  Widget _lineChart(BuildContext context, List<BodyMeasurementEntry> entries) {
    final theme = Theme.of(context);

    final values = entries.map(_toChartValue).toList();
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);

    final timestamps = entries.map((e) => e.recordedAtMs).toList();
    final minMs = timestamps.reduce((a, b) => a < b ? a : b);
    final maxMs = timestamps.reduce((a, b) => a > b ? a : b);

    // X-axis and Y-axis labels share a single text style. The Y-axis
    // labels drop the unit (the header above already names the
    // measurement and the value column to the right shows the unit)
    // so a single fontSize 9 fits both columns without crowding.
    final scaleStyle = theme.textTheme.labelSmall?.copyWith(
      color: OmniTheme.colors.textMuted,
      fontSize: 9,
    );

    return SizedBox(
      height: 65,
      child: Stack(
        children: [
          // Layer 1: painter fills the entire widget. The painter
          // draws the Y-axis line (vertical at x=40), the X-axis
          // line (horizontal at y=38), the data line, and the dots.
          Positioned.fill(
            child: CustomPaint(
              painter: _SparklinePainter(
                entries: entries,
                values: values,
                color: theme.colorScheme.primary,
                axisColor: theme.dividerColor,
                yAxisLineX: 40,
                xAxisLineY: 38,
              ),
            ),
          ),
          // Layer 2: y-axis scale — max at top-LEFT, min at bottom-LEFT
          // of the chart area, in the y-axis label column (left=0,
          // width=38 — 2 dp margin from the Y-axis line at x=40).
          // Right-aligned so the rendered text visually anchors to
          // the line.
          Positioned(
            key: const Key('measurement_sparkline_y_max'),
            top: 0,
            left: 0,
            width: 38,
            child: Text(
              ProfileMeasurements.formatValue(maxV),
              style: scaleStyle,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            key: const Key('measurement_sparkline_y_min'),
            top: 26,
            left: 0,
            width: 38,
            child: Text(
              ProfileMeasurements.formatValue(minV),
              style: scaleStyle,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Layer 3: x-axis date strip — first date at bottom-left
          // (just to the right of the Y-axis line at x=40), last
          // date at bottom-right (4 dp right margin). The strip
          // occupies the bottom 12 dp of the container; there is a
          // 2 dp gap between the X-axis line (y=24) and the strip
          // (y=26+).
          Positioned(
            key: const Key('measurement_sparkline_x_first'),
            bottom: 0,
            left: 30,
            child: Text(
              ChartAxisHelper.formatDateLabel(
                DateTime.fromMillisecondsSinceEpoch(minMs),
              ),
              style: scaleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            key: const Key('measurement_sparkline_x_last'),
            bottom: 0,
            right: 0,
            child: Text(
              ChartAxisHelper.formatDateLabel(
                DateTime.fromMillisecondsSinceEpoch(maxMs),
              ),
              style: scaleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter for the sparkline (handles 1, 2, and 3+ entries).
///
/// The painter's canvas is the full widget area (60 dp tall, full
/// width). Layout inside the canvas:
///
/// - **Y-axis label column**: x=0 to x=38 (38 dp wide, on the LEFT).
///   Host renders the Y-max and Y-min labels here as `Positioned`
///   `Text` widgets.
/// - **Y-axis line**: vertical 1 dp stroke at x=40, from y=0 to
///   y=[xAxisLineY] (= 38 for the standard 60 dp widget).
/// - **X-axis line**: horizontal 1 dp stroke at y=[xAxisLineY],
///   from x=40 to x=[size.width].
/// - **Data area**: x=42 to x=size.width-4, y=4 to y=xAxisLineY-4
///   (with 2 dp inset from the Y-axis line, 4 dp inset from the
///   right edge, and 4 dp inset from top/bottom of the chart
///   area).
/// - **X-axis date strip**: y=xAxisLineY to y=size.height (the
///   bottom 22 dp; rendered by the host with `Positioned(bottom:
///   0)` `Text` widgets).
///
/// **Axes lines are always drawn**, even with 0 entries, so the
/// chart frame stays stable across the 0/1/2+ branch transitions.
///
/// **1 entry**: the painter draws a horizontal 1.5 dp `color` line
/// across the full data-area width (x=yAxisLineX+2 to
/// x=size.width-4) at the entry's y position, plus a single 2 dp
/// filled dot at the entry's (x, y) position. With one entry,
/// `minV == maxV` (so `yForValue` falls back to chart-mid
/// `xAxisLineY / 2` = 19) and `minMs == maxMs` (so `xForTimestamp`
/// falls back to data-area mid `yAxisLineX + 2 +
/// 0.5 × effectiveChartWidth`). The host still renders the
/// Y-max / Y-min / X-first / X-last labels (both Y labels show the
/// same value; both X labels show the same date) so the chart
/// frame matches the 2+ entries case.
///
/// **2+ entries**: X positioning is **time-based** — each entry's
/// `recordedAtMs` is mapped linearly across `effectiveChartWidth`
/// (= size.width - 46, the data area width). Two entries months
/// apart sit at the chart's leftmost and rightmost x positions;
/// many entries clustered in time sit close together. Y positioning
/// normalizes the value range against `(maxV - minV)` across
/// `effectiveChartHeight` (= xAxisLineY - 8, the data area height).
/// The painter draws a 1.5 dp line through the points and a 2 dp
/// filled dot at **every** entry position (not just the last) so
/// the user can see each data point clearly even when several
/// cluster together.
///
/// When two entries land on the same second (`maxMs == minMs`),
/// the x-coordinate falls back to the horizontal mid of the data
/// area — same fallback as the 1-entry case.
class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.entries,
    required this.values,
    required this.color,
    required this.axisColor,
    required this.yAxisLineX,
    required this.xAxisLineY,
  });

  final List<BodyMeasurementEntry> entries;

  /// Display values for [entries], aligned 1:1 by index, already converted
  /// from canonical kilograms to the active unit by the host. The painter
  /// only positions by value and must not read `entry.value` directly.
  final List<double> values;

  final Color color;

  /// Color used for the Y-axis and X-axis lines.
  final Color axisColor;

  /// X-coordinate (in canvas coords) of the vertical Y-axis line.
  final double yAxisLineX;

  /// Y-coordinate (in canvas coords) of the horizontal X-axis line.
  final double xAxisLineY;

  @override
  void paint(Canvas canvas, Size size) {
    // Axes lines are drawn even with 0 entries (so the chart frame
    // stays stable across branch transitions). With 1+ entries the
    // data line + dot(s) follow.
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(yAxisLineX, 0),
      Offset(yAxisLineX, xAxisLineY),
      axisPaint,
    );
    canvas.drawLine(
      Offset(yAxisLineX, xAxisLineY),
      Offset(size.width, xAxisLineY),
      axisPaint,
    );

    if (entries.isEmpty) return;

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs();

    const paddingLeft = 2.0;
    const paddingRight = 4.0;
    const paddingTop = 4.0;
    const paddingBottom = 4.0;

    final effectiveChartWidth =
        size.width - yAxisLineX - paddingLeft - paddingRight;
    final effectiveChartHeight = xAxisLineY - paddingTop - paddingBottom;

    final timestamps = entries.map((e) => e.recordedAtMs).toList();
    final minMs = timestamps.reduce((a, b) => a < b ? a : b);
    final maxMs = timestamps.reduce((a, b) => a > b ? a : b);
    final timeRange = (maxMs - minMs).toDouble();

    double xForTimestamp(int ms) {
      if (timeRange == 0) {
        // Single entry OR multiple entries sharing a timestamp —
        // fall back to the data-area mid so the dot sits at the
        // centre of the chart rather than crashing on a div-by-zero.
        return yAxisLineX + paddingLeft + 0.5 * effectiveChartWidth;
      }
      return yAxisLineX +
          paddingLeft +
          ((ms - minMs) / timeRange) * effectiveChartWidth;
    }

    double yForValue(double v) {
      if (range == 0) {
        // Single entry OR multiple entries with the same value —
        // place at chart mid vertically so the horizontal line sits
        // in the middle of the data area.
        return xAxisLineY / 2;
      }
      return xAxisLineY -
          paddingBottom -
          ((v - minV) / range) * effectiveChartHeight;
    }

    if (entries.length == 1) {
      // 1-entry branch: a horizontal line across the full data-area
      // width at the entry's y position, plus a single 2 dp filled
      // dot at the entry's (x, y) position. The line CROSSES the dot
      // (the dot sits at the same y as the line). With 1 entry,
      // `xForTimestamp` falls back to chart mid and `yForValue`
      // falls back to chart mid, so the dot lands at the visual
      // centre of the chart.
      final entry = entries.first;
      final y = yForValue(values.first);
      final x = xForTimestamp(entry.recordedAtMs);

      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(yAxisLineX + paddingLeft, y),
        Offset(size.width - paddingRight, y),
        linePaint,
      );

      final dotPaint = Paint()..color = color;
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
      return;
    }

    // 2+ entries branch: connect every entry with a polyline, then
    // draw a 2 dp filled dot at each entry position.
    final path = Path();
    for (var i = 0; i < entries.length; i++) {
      final x = xForTimestamp(entries[i].recordedAtMs);
      final y = yForValue(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < entries.length; i++) {
      final x = xForTimestamp(entries[i].recordedAtMs);
      final y = yForValue(values[i]);
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.entries != entries ||
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.axisColor != axisColor ||
      oldDelegate.yAxisLineX != yAxisLineX ||
      oldDelegate.xAxisLineY != xAxisLineY;
}
