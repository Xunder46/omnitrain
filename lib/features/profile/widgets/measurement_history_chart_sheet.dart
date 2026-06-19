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

    // The chart is rendered at a fixed 340 dp width (user-tweaked
    // from A20's 200 dp) and centered horizontally inside the
    // sheet so it reads as a focused detail-view chart rather than
    // a full-width data panel. Vertical axis values (Y-axis labels
    // + horizontal grid lines that communicate value levels) are
    // hidden entirely per A20 — only the data line + dots + bottom
    // X-axis dates remain.
    //
    // Horizontal padding (16 dp on each side) gives the line
    // breathing room from the chart's left/right edges so the
    // start/end dots don't touch the rounded chart bounds. The
    // X-axis dates (the only axis labels that render) live in the
    // bottom `reservedSize` strip; their visibility is improved
    // by reserving 32 dp and bumping the font size to 11 pt.
    return Center(
      child: SizedBox(
        width: 340,
        height: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
    final valueLabel = selected.unitId == 'unit-kg'
        ? UnitFormatter.formatWeight(selected.value, widget.settingsState)
        : '${ProfileMeasurements.formatValue(selected.value)} ${ProfileMeasurements.unitLabelFor(selected.unitId)}';

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

  Future<void> _confirmDelete(int index) async {
    final entry = _entries[index];
    final date = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
    final dateLabel = ChartAxisHelper.formatDateLabel(date);
    final valueLabel = entry.unitId == 'unit-kg'
        ? UnitFormatter.formatWeight(entry.value, widget.settingsState)
        : '${ProfileMeasurements.formatValue(entry.value)} '
              '${ProfileMeasurements.unitLabelFor(entry.unitId)}';

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
              backgroundColor: WidgetStateProperty.all(
                theme.colorScheme.error,
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete entry: $e')),
      );
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
          final plotWidth = constraints.maxWidth;
          final plotHeight = max(0.0, constraints.maxHeight - 28);
          final yRange = max(chartMetrics.yMax - chartMetrics.yMin, 1.0);

          return Stack(
            children: [
              for (var i = 0; i < _entries.length; i++)
                Builder(
                  builder: (context) {
                    final x = _entries.length == 1
                        ? plotWidth / 2
                        : (i / (_entries.length - 1)) * plotWidth;
                    final displayValue = _entries[i].unitId == 'unit-kg'
                        ? UnitFormatter.convertWeight(
                            _entries[i].value,
                            widget.settingsState,
                          )
                        : _entries[i].value;
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
      final displayValue = _entries[i].unitId == 'unit-kg'
          ? UnitFormatter.convertWeight(_entries[i].value, widget.settingsState)
          : _entries[i].value;
      spots.add(FlSpot(i.toDouble(), displayValue));
    }

    final values = _entries
        .map((entry) {
          return entry.unitId == 'unit-kg'
              ? UnitFormatter.convertWeight(entry.value, widget.settingsState)
              : entry.value;
        })
        .toList(growable: false);
    final minValue = values.reduce(min);
    final maxValue = values.reduce(max);
    final range = (maxValue - minValue).abs();
    final verticalPadding = range < 1 ? 1.0 : range * 0.15;
    final yMin = minValue - verticalPadding;
    final yMax = maxValue + verticalPadding;

    final minX = _entries.length == 1 ? -0.5 : 0.0;
    final maxX = _entries.length == 1 ? 0.5 : (_entries.length - 1).toDouble();

    return _ChartMetrics(
      yMin: yMin,
      yMax: yMax,
      data: LineChartData(
        minX: minX,
        maxX: maxX,
        minY: yMin,
        maxY: yMax,
        clipData: FlClipData.all(),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(),
        // Horizontal grid lines hidden per A20 — the user wants no
        // vertical axis values to show at all (the Y-axis labels are
        // already hidden in `titlesData`; the grid lines were the
        // last remaining hint of a value scale on the vertical axis).
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
  final LineChartData data;

  const _ChartMetrics({
    required this.yMin,
    required this.yMax,
    required this.data,
  });
}
