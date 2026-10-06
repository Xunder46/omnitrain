import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/exercise_metric.dart';
import '../../../core/models/instrument_list.dart';
import '../../../state/settings/settings_state.dart';
import 'instrument_sparkline.dart';
import 'native_value_format.dart';

/// One exercise in an Instruments section: what it is worth now, how it has
/// moved since the previous window of the same length, and the trend line
/// behind that figure.
class InstrumentRowTile extends StatelessWidget {
  final InstrumentRow row;
  final SettingsState settingsState;
  final OmniThemeColors themeColors;
  final VoidCallback onTap;

  const InstrumentRowTile({
    super.key,
    required this.row,
    required this.settingsState,
    required this.themeColors,
    required this.onTap,
  });

  /// The parts that exist, in this order: the value's own secondary figure
  /// (`Total hold 2:30`), the mean heart rate, the cadence. Resistance rows
  /// carry no secondary line — their added weight is inside the figure above.
  String? _secondaryLine(NativeValue best) {
    final parts = <String>[];

    final label = nativeSecondaryLabel(best.secondaryMetric);
    final value = formatNativeSecondary(best, settingsState);
    if (label != null && value != null) parts.add('$label $value');

    final bpm = row.averageHeartRateBpm;
    if (bpm != null) parts.add('$bpm bpm');

    final cadence = row.cadenceStepsPerMin;
    if (cadence != null) parts.add('$cadence steps/min');

    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = row.summary;
    final best = summary.best;
    final secondary = _secondaryLine(best);
    final previous = row.previousValue;
    final delta = previous == null ? null : best.value - previous.value;

    return InkWell(
      key: Key('instrument_row_${summary.exerciseId}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary != null)
                    Text(
                      secondary,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: themeColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            InstrumentSparkline(
              key: Key('instrument_sparkline_${summary.exerciseId}'),
              points: summary.points,
              themeColors: themeColors,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatNativeValue(best, settingsState),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InstrumentChangeChip(
                  key: Key('instrument_change_${summary.exerciseId}'),
                  label: delta == null
                      ? null
                      : formatNativeChange(best.metric, delta, settingsState),
                  delta: delta,
                  themeColors: themeColors,
                  theme: theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The row's change readout. Reads `'—'` when there is no comparable previous
/// value, and otherwise carries the direction of the raw numeric change, so a
/// slower pace reads `↑` like any other increase.
class InstrumentChangeChip extends StatelessWidget {
  /// The formatted change, or null when there is nothing comparable.
  final String? label;
  final double? delta;
  final OmniThemeColors themeColors;
  final ThemeData theme;

  const InstrumentChangeChip({
    super.key,
    required this.label,
    required this.delta,
    required this.themeColors,
    required this.theme,
  });

  static const String _noChange = '—';

  @override
  Widget build(BuildContext context) {
    final change = delta;
    final Color color;
    if (change == null || change == 0) {
      color = themeColors.textMuted;
    } else if (change > 0) {
      color = theme.colorScheme.primary;
    } else {
      color = theme.colorScheme.error.withValues(alpha: 0.8);
    }

    return SizedBox(
      width: 92,
      child: Text(
        label ?? _noChange,
        textAlign: TextAlign.right,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
      ),
    );
  }
}
