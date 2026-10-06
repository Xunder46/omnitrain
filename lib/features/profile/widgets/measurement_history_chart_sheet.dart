import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/constants/profile_measurements.dart';
import '../../../core/utils/chart_axis_helper.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../data/models/models.dart';
import '../../../widgets/chart/edge_aware_date_label.dart';
import '../../../widgets/chart/scrollable_trend_chart.dart';
import '../../../state/profile/profile_state.dart';
import '../../../state/settings/settings_state.dart';
import '../../../widgets/dialogs/confirmation_dialog.dart';

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
  // Strip is locked to the most recent entry (D-2). The per-point
  // tap-to-select affordance was removed along with the fl_chart
  // tooltip popup; the only remaining interaction is long-press
  // to delete, which targets this index.
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

  // Chart layout:
  //
  //   ┌──────────────┬────────────────────────────────────┐
  //   │ pinned       │  horizontal scroll view             │
  //   │ y-axis       │  ┌──────────────────────────────┐  │
  //   │ labels       │  │  LineChart (leftTitles off)  │  │
  //   │ (whole #s)   │  │  · · ─ · ·                   │  │
  //   │              │  │  date  date  date  date     │  │
  //   └──────────────┴────────────────────────────────────┘
  //                 ▲ long-press anywhere → delete most recent
  //
  // The wrapper provides the pinned y-axis column (whole numbers
  // via formatYAxisValue with an empty unit) and the horizontal
  // scroll viewport. The inner LineChart disables fl_chart's own
  // leftTitles so the labels don't render twice. The per-point
  // GestureDetector overlay that used to drive the tap-to-select
  // strip is gone; a single chart-area GestureDetector handles
  // long-press to delete the most recent entry.
  Widget _buildChart(ThemeData theme) {
    final values = _entries.map(_toChartValue).toList(growable: false);
    final bounds = ChartAxisHelper.computeBounds(values);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return GestureDetector(
      key: const ValueKey('measurement_chart_area'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _confirmDelete(_selectedIndex),
      child: ScrollableTrendChart(
        themeColors: OmniTheme.colors,
        bounds: bounds,
        // Pass the active unit so the pinned y-axis labels read
        // "62 lbs" / "180 cm" instead of bare "62" / "180".
        // Matches the on-card stats chart style and lets the
        // user read the y-axis scale without cross-referencing
        // the strip below. Unit comes from the same source as
        // the strip label (preferred unit for height/weight,
        // measurement's stored unit for everything else) so
        // the two surfaces never disagree.
        unitLabel: _chartUnitLabel(),
        pointCount: _entries.length,
        chartBuilder: (plotWidth) {
          final spots = <FlSpot>[];
          for (var i = 0; i < _entries.length; i++) {
            spots.add(FlSpot(i.toDouble(), _toChartValue(_entries[i])));
          }
          // Data points sit at the exact integer indices. The
          // shared `buildEdgeAwareDateLabel` helper shifts the
          // first and last x-axis labels by ±22 dp so they don't
          // collide with the pinned y-axis column on the left
          // or overflow the right card border — no plot
          // padding (minX/maxX extension) needed.
          final minX = _entries.length == 1 ? -0.5 : 0.0;
          final maxX = _entries.length == 1
              ? 0.5
              : (_entries.length - 1).toDouble();

          return LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: bounds.min,
              maxY: bounds.max,
              clipData: FlClipData.all(),
              borderData: FlBorderData(show: false),
              // No popup on tap (D-4). The chart area's
              // GestureDetector handles the only remaining
              // interaction (long-press to delete).
              lineTouchData: const LineTouchData(enabled: false),
              // No top headroom (D-5). The wrapper's pinned
              // y-axis column already accounts for the label
              // strip; we don't need fl_chart to reserve any
              // top space.
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false, reservedSize: 0),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                // Pinned column on the left renders the y-axis
                // labels. The wrapper owns that space; the
                // inner chart renders no left labels of its own.
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      // Reject any non-integer value. fl_chart
                      // can call the callback with values outside
                      // the integer grid (e.g. during padding
                      // animations) and we only want one label
                      // per data-point index.
                      if (value != value.truncateToDouble()) {
                        return const SizedBox.shrink();
                      }
                      final index = value.toInt();
                      if (index < 0 || index >= _entries.length) {
                        return const SizedBox.shrink();
                      }
                      if (!ChartAxisHelper.shouldShowDateLabel(
                        index,
                        _entries.length,
                      )) {
                        return const SizedBox.shrink();
                      }
                      // Edge-aware label: same widget, same style,
                      // same horizontal shift as the on-card stats
                      // charts. The shared helper lives at
                      // `lib/widgets/chart/edge_aware_date_label.dart`
                      // and is used by both surfaces so they
                      // speak the same visual language.
                      return buildEdgeAwareDateLabel(
                        meta: meta,
                        text: ChartAxisHelper.formatDateLabel(
                          DateTime.fromMillisecondsSinceEpoch(
                            _entries[index].recordedAtMs,
                          ),
                        ),
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: OmniTheme.colors.textMuted,
                          fontSize: 9,
                        ),
                        isFirst: index == 0,
                        isLast: index == _entries.length - 1,
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: onSurface.withOpacity(0.08), strokeWidth: 1),
              ),
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
        },
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
          // The strip is locked to the most recent entry (D-2),
          // so the key never changes after load — the
          // AnimatedSwitcher stays put instead of animating on
          // every rebuild.
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
    // D-9: the "Tap a point to view" half of the previous hint
    // described a removed affordance. The only remaining touch
    // interaction is long-press to delete.
    return Center(
      child: Text(
        'Long-press to delete',
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
      return UnitFormatter.convertHeightFromCm(
        entry.value,
        widget.settingsState,
      );
    }
    if (entry.unitId == 'unit-kg') {
      return UnitFormatter.convertWeight(entry.value, widget.settingsState);
    }
    return entry.value;
  }

  // Short unit label for the pinned y-axis column. Matches the
  // unit the strip below shows (so "180 cm" axis ↔ "180 cm"
  // strip; "176.4 lbs" axis ↔ "176.4 lbs" strip), keeping the
  // y-axis and the strip in sync. The strip uses a richer
  // formatter (compound feet/inches for height in ftin mode);
  // the y-axis only needs the bare unit so the labels stay
  // compact.
  String _chartUnitLabel() {
    final type = widget.definition.type;
    if (type == 'height') {
      return widget.settingsState.preferredHeightUnit == 'ftin' ? 'in' : 'cm';
    }
    if (type == 'bodyweight') {
      return widget.settingsState.preferredWeightUnit == 'kg' ? 'kg' : 'lbs';
    }
    // Other measurements: read the unit from the first entry
    // (all entries in a single sheet share the same unitId).
    if (_entries.isNotEmpty) {
      return ProfileMeasurements.unitLabelFor(_entries.first.unitId);
    }
    return '';
  }

  Future<void> _confirmDelete(int index) async {
    final entry = _entries[index];
    final date = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
    final dateLabel = ChartAxisHelper.formatDateLabel(date);
    final valueLabel = _formatSelectedValueLabel(entry);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => ConfirmationDialog.twoChoice(
        title: 'Delete entry?',
        body: Text(
          '$dateLabel \u00b7 $valueLabel will be removed from your history.',
        ),
        dismissLabel: 'Cancel',
        confirmLabel: 'Delete',
        dismissKey: const Key('measurement-delete-cancel'),
        confirmKey: const Key('measurement-delete-confirm'),
        isDestructive: true,
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

    // D-7: load the full history (was capped at 10). Older
    // entries are reachable by horizontal scroll on the chart
    // wrapper.
    final orderedEntries = entries.toList().reversed.toList();
    setState(() {
      _entries = orderedEntries;
      _selectedIndex = orderedEntries.isEmpty ? 0 : orderedEntries.length - 1;
      _isLoading = false;
    });
  }
}
