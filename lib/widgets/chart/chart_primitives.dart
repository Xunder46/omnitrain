import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// Reserved height for a chart's bottom date axis.
///
/// Shared by the charts that stay on the Stats screen and the nutrition charts
/// that moved into `lib/features/nutrition/widgets/nutrition_trend_card.dart`,
/// so the two hosts reserve the same axis height.
const double kChartBottomAxisReservedSize = 20;

/// One legend swatch and its label, for a chart's on-card legend row.
Widget buildLegendItem(
  ThemeData theme,
  Color color,
  String label,
  OmniThemeColors themeColors, {
  Color? outline,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: outline == null ? null : Border.all(color: outline),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: themeColors.textMuted,
        ),
      ),
    ],
  );
}

/// Deliberate single-point card for a metric whose history holds exactly one
/// day — the chart is replaced by the one value rather than a one-point line.
Widget buildSinglePointCard({
  required ThemeData theme,
  required OmniThemeColors themeColors,
  required String label,
  required String value,
  required DateTime date,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: themeColors.divider.withAlpha(30),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label $value',
          style: theme.textTheme.bodySmall?.copyWith(
            color: OmniTheme.colors.textDominant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '1 session — log more to see a trend',
          style: theme.textTheme.labelSmall?.copyWith(
            color: themeColors.textMuted,
          ),
        ),
      ],
    ),
  );
}
