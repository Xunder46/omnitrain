import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/constants/profile_measurements.dart';
import '../../../core/utils/chart_axis_helper.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../data/models/models.dart';
import '../../../state/profile/profile_state.dart';
import '../../../state/settings/settings_state.dart';

class MeasurementHistoryChartSheet extends StatefulWidget {
  final ProfileState profileState;
  final ProfileMeasurementDefinition definition;
  final SettingsState settingsState;
  final Future<void> Function() onLogNew;

  const MeasurementHistoryChartSheet({
    super.key,
    required this.profileState,
    required this.definition,
    required this.settingsState,
    required this.onLogNew,
  });

  @override
  State<MeasurementHistoryChartSheet> createState() =>
      _MeasurementHistoryChartSheetState();
}

class _MeasurementHistoryChartSheetState
    extends State<MeasurementHistoryChartSheet> {
  List<BodyMeasurementEntry> _entries = [];
  bool _isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: OmniTheme.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(theme),
              _buildTitle(theme),
              const SizedBox(height: 12),
              if (_isLoading)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                _buildEmptyState(theme)
              else
                _buildChart(theme),
              const SizedBox(height: 12),
              if (!_isLoading && _entries.isNotEmpty) _buildLabelStrip(theme),
              if (!_isLoading && _entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildHintText(theme),
              ],
              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.onSurface.withOpacity(0.12)),
              const SizedBox(height: 8),
              _buildLogButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle(ThemeData theme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 10),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withOpacity(0.30),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        widget.definition.label.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: OmniTheme.colors.textDominant,
          letterSpacing: 2.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return SizedBox(
      height: 220,
      child: Center(
        child: Text(
          'No entries yet',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: OmniTheme.colors.textSecondary.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildChart(ThemeData theme) {
    final chartMetrics = _buildChartMetrics(theme);

    // The chart is rendered at a fixed 440 dp width (A20's 200 dp
    // bumped to 440 dp, then narrowed from 440 dp so the sheet's
    // own 12 dp horizontal padding becomes a visible breathing
    // gap on the left of the chart on phone-sized surfaces). It
    // stays centered horizontally so it reads as a focused
    // detail-view chart rather than a full-width data panel.
    //
    // Y-axis value labels render on the LEFT (via
    // `leftTitles.reservedSize`, bumped from 50 → 60 dp so labels
    // like `176.4` or `180.3` no longer overflow the reserved
    // strip). The empty `rightTitles` reserves additional
    // horizontal space on the right (no labels shown). Together
    // these reserved sizes shrink the chart's plot area
    // symmetrically, so the first and last dots are visibly inset
    // from the chart's left and right edges and the line no longer
    // reads as clipped.
    //
    // Horizontal padding (40 dp on the right) keeps the LineChart
    // off the rounded sheet corner. The X-axis dates live in the
    // bottom `reservedSize` strip; their visibility is improved by
    // reserving 32 dp and bumping the font size to 11 pt.
    return Center(
      child: SizedBox(
        width: 440,
        height: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 40, 0),
          child: Stack(
            children: [
              LineChart(chartMetrics.data),
              _buildDotTapTargets(chartMetrics),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelStrip(ThemeData theme) {
    final selected = _entries[_selectedIndex.clamp(0, _entries.length - 1)];
    final selectedDate = DateTime.fromMillisecondsSinceEpoch(
      selected.recordedAtMs,
    );
    final valueLabel = _formatSelectedValueLabel(selected);

    return SizedBox(
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: OmniTheme.animationDuration,
        switchInCurve: OmniTheme.animationCurve,
        switchOutCurve: OmniTheme.animationCurve,
        child: Center(
          key: ValueKey(_selectedIndex),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ChartAxisHelper.formatDateLabel(selectedDate),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: OmniTheme.colors.textSecondary.withOpacity(0.70),
                ),
              ),
              Text(
                '·',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: OmniTheme.colors.textSecondary.withOpacity(0.55),
                ),
              ),
              Text(
                valueLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.90),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogButton() {
    return SizedBox(
      width: double.infinity,
      height: OmniTheme.buttonPrimaryHeight,
      child: FilledButton(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
            ),
          ),
        ),
        onPressed: _handleLogNew,
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Log New Entry'),
        ),
      ),
    );
  }

  Widget _buildHintText(ThemeData theme) {
    return Center(
      child: Text(
        'Tap a point to view \u00b7 Long-press to delete',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: OmniTheme.colors.textSecondary.withOpacity(0.55),
        ),
      ),
    );
  }

  // Render the selected point's value with the active unit. Height
  // is unit-aware (cm or compound feet/inches); weight is unit-aware
  // (kg or lbs); everything else uses the bare "<value> <unit>"
  // fallback.
  String _formatSelectedValueLabel(BodyMeasurementEntry selected) {
    if (selected.measurementType == 'height') {
      return UnitFormatter.formatHeight(selected.value, widget.settingsState);
    }
    if (selected.unitId == 'unit-kg') {
      return UnitFormatter.formatWeight(selected.value, widget.settingsState);
    }
    return '${ProfileMeasurements.formatValue(selected.value)} '
        '${ProfileMeasurements.unitLabelFor(selected.unitId)}';
  }

  // Plot the entry's canonical value in the chart's y-axis unit.
  // - weight → display-unit (kg/lbs) so the line moves with the
  //   weight preference toggle.
  // - height in cm mode → passthrough.
  // - height in ftin mode → total whole inches (so the y-axis
  //   shows numeric inches and the selected-point label shows the
  //   compound feet/inches form).
  // - everything else → passthrough.
  double _toChartValue(BodyMeasurementEntry entry) {
    if (entry.measurementType == 'height') {
      return UnitFormatter.convertHeightFromCm(entry.value, widget.settingsState);
    }
    if (entry.unitId == 'unit-kg') {
      return UnitFormatter.convertWeight(entry.value, widget.settingsState);
    }
    return entry.value;
  }

  Future<void> _confirmDelete(int index) async {
    final entry = _entries[index];
    final date = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
    final dateLabel = ChartAxisHelper.formatDateLabel(date);
    final valueLabel = _formatSelectedValueLabel(entry);

    if (!mounted) return;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          '$dateLabel \u00b7 $valueLabel will be removed from your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(theme.colorScheme.error),
              foregroundColor: WidgetStateProperty.all(
                theme.colorScheme.onError,
              ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.profileState.deleteMeasurementEntry(
        entry.id,
        widget.definition.type,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete entry: $e')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    await _loadEntries();
  }

  Future<void> _handleLogNew() async {
    await widget.onLogNew();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    await _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.profileState.getMeasurementHistory(
      widget.definition.type,
    );
    if (!mounted) return;

    final orderedEntries = entries.take(10).toList().reversed.toList();
    setState(() {
      _entries = orderedEntries;
      _selectedIndex = orderedEntries.isEmpty ? 0 : orderedEntries.length - 1;
      _isLoading = false;
    });
  }

  Widget _buildDotTapTargets(_ChartMetrics chartMetrics) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The chart's plot area is narrower than the LineChart widget
          // by `leftReserved` + `rightReserved` (the title-side reserved
          // sizes). Subtract them from the overlay's bounds so tap
          // targets line up with the rendered dots.
          final plotLeft = chartMetrics.leftReserved;
          final plotWidth = max(
            0.0,
            constraints.maxWidth -
                chartMetrics.leftReserved -
                chartMetrics.rightReserved,
          );
          final plotHeight = max(0.0, constraints.maxHeight - 28);
          final yRange = max(chartMetrics.yMax - chartMetrics.yMin, 1.0);

          return Stack(
            children: [
              for (var i = 0; i < _entries.length; i++)
                Builder(
                  builder: (context) {
                    final x = _entries.length == 1
                        ? plotLeft + plotWidth / 2
                        : plotLeft + (i / (_entries.length - 1)) * plotWidth;
                    final displayValue = _toChartValue(_entries[i]);
                    final yRatio = (displayValue - chartMetrics.yMin) / yRange;
                    final y = (plotHeight - (yRatio * plotHeight)).clamp(
                      0.0,
                      plotHeight,
                    );

                    return Positioned(
                      left: x - 24,
                      top: y - 24,
                      child: GestureDetector(
                        key: ValueKey('chart_dot_$i'),
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          setState(() {
                            _selectedIndex = i;
                          });
                        },
                        onLongPress: () => _confirmDelete(i),
                        child: const SizedBox(width: 48, height: 48),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  _ChartMetrics _buildChartMetrics(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final spots = <FlSpot>[];

    for (var i = 0; i < _entries.length; i++) {
      final displayValue = _toChartValue(_entries[i]);
      spots.add(FlSpot(i.toDouble(), displayValue));
    }

    final values = _entries
        .map(_toChartValue)
        .toList(growable: false);

    // Y-axis bounds: delegate to the canonical `ChartAxisHelper.computeBounds`
    // so the padded range + nice tick interval are computed in one place.
    // `readableIntervalForHeight` then shrinks the tick count to fit a
    // 220 dp chart without overlapping labels.
    final bounds = ChartAxisHelper.computeBounds(values);
    final plotHeight = 220.0 - 32.0 - 8.0; // minus bottom + top padding
    final yInterval = ChartAxisHelper.readableIntervalForHeight(
      bounds,
      plotHeight,
    );
    final yMin = bounds.min;
    final yMax = bounds.max;

    // Reserved sizes for the LEFT (Y-axis labels) and RIGHT (no labels,
    // just breathing room) titles. Together they inset the chart's plot
    // area so the first/last dots are visibly inside the chart bounds
    // rather than flush against them.
    //
    // `leftReserved = 50 dp` is wide enough for the longest
    // whole-number Y-axis label (3 chars at 10 pt) without
    // overflowing. The Y-axis renders whole numbers only — see
    // the `getTitlesWidget` below — so a `76.3` and a `76` tick
    // can't sit so close vertically that they read as the same
    // value at 10 pt.
    const leftReserved = 50.0;
    const rightReserved = 30.0;

    final minX = _entries.length == 1 ? -0.5 : 0.0;
    final maxX = _entries.length == 1 ? 0.5 : (_entries.length - 1).toDouble();

    return _ChartMetrics(
      yMin: yMin,
      yMax: yMax,
      leftReserved: leftReserved,
      rightReserved: rightReserved,
      data: LineChartData(
        minX: minX,
        maxX: maxX,
        minY: yMin,
        maxY: yMax,
        clipData: FlClipData.all(),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(),
        // Subtle horizontal grid lines at each labeled tick so the
        // Y-axis values have a visual anchor across the chart area.
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: onSurface.withOpacity(0.08), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftReserved,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                // Show only the in-range tick labels; fl_chart may
                // call us with values outside [yMin, yMax] when
                // fitting the interval grid.
                if (value < yMin - 1e-9 || value > yMax + 1e-9) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    // Whole-number labels only. The chart's Y-axis
                    // tick interval is rounded to a "nice" step
                    // (e.g. 1, 2, 5), so a decimal tick (76.3)
                    // would either render the same as its whole
                    // neighbor (76) or sit so close vertically that
                    // the two are indistinguishable at 10 pt. Show
                    // only the rounded whole number — the user can
                    // read precise values from the selected-point
                    // label strip below the chart, which still
                    // shows one decimal where it matters.
                    value.toStringAsFixed(0),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: OmniTheme.colors.textSecondary.withOpacity(0.70),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: false,
              // No labels rendered here, but the reserved size still
              // shrinks the chart's plot area on the right — giving
              // the data line the requested horizontal breathing
              // room so the last dot doesn't touch the chart edge.
              reservedSize: rightReserved,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Bumped from 28 → 32 so the X-axis date labels have
              // enough room to render at the bumped 11 pt font
              // without being clipped by the chart's 220 dp
              // height (data area = 220 − 32 = 188 dp tall).
              reservedSize: 32,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= _entries.length) {
                  return const SizedBox.shrink();
                }
                if (_entries.length > 6 && index.isOdd) {
                  return const SizedBox.shrink();
                }

                final date = DateTime.fromMillisecondsSinceEpoch(
                  _entries[index].recordedAtMs,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ChartAxisHelper.formatDateLabel(date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: OmniTheme.colors.textSecondary.withOpacity(0.60),
                      // [E] Chart axis — dense instrumentation label; getTitlesWidget has no BuildContext
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: primary.withOpacity(0.70),
            barWidth: 2,
            isCurved: false,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, _, _, index) {
                final isSelected = index == _selectedIndex;
                return FlDotCirclePainter(
                  radius: isSelected ? 6.5 : 5.0,
                  color: isSelected ? onSurface : primary,
                  strokeColor: isSelected ? primary : onSurface,
                  strokeWidth: isSelected ? 2.0 : 1.5,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: _entries.length >= 2,
              color: primary.withOpacity(0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartMetrics {
  final double yMin;
  final double yMax;
  final double leftReserved;
  final double rightReserved;
  final LineChartData data;

  const _ChartMetrics({
    required this.yMin,
    required this.yMax,
    required this.leftReserved,
    required this.rightReserved,
    required this.data,
  });
}
