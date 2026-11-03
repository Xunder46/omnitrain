import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/weight_trend.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../state/settings/settings_state.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// The Weight block: where the body weight stands and how it moved over the
/// last four weeks, in the user's unit (D-17706).
class WeightTrendRow extends StatelessWidget {
  final WeightTrend trend;
  final SettingsState settingsState;
  final OmniThemeColors themeColors;

  const WeightTrendRow({
    super.key,
    required this.trend,
    required this.settingsState,
    required this.themeColors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('weight_trend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OmniCardHeader(title: 'Weight'),
        OmniSurface(
          child: Text(
            weightTrendLine(
              latest: UnitFormatter.convertWeight(
                trend.latestKg,
                settingsState,
              ),
              change: UnitFormatter.convertWeight(
                trend.changeKg,
                settingsState,
              ),
              unitLabel: UnitFormatter.weightLabel(settingsState),
            ),
            key: const Key('weight_trend_line'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: themeColors.textDominant,
            ),
          ),
        ),
      ],
    );
  }
}
