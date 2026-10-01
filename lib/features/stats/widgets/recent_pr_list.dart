import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/stats_progress.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../state/settings/settings_state.dart';
import '../../../widgets/layout/omni_surface.dart';

/// The Recent PRs card.
///
/// Owned here so the Stats screen and Records & Trends show the same list
/// from the same `recentPRs` field, rendered the same way.
class RecentPRList extends StatelessWidget {
  final List<StatsPR> prs;
  final SettingsState settingsState;

  const RecentPRList({
    super.key,
    required this.prs,
    required this.settingsState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(settingsState.appTheme);
    final weightLabel = UnitFormatter.weightLabel(settingsState);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent PRs',
            style: theme.textTheme.titleSmall?.copyWith(
              color: OmniTheme.colors.textDominant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...prs.map((pr) {
            final dateStr =
                '${OmniDateUtils.shortMonthName(pr.date.month)} ${pr.date.day},'
                ' ${pr.date.year}';
            // Reps-axis PR (bodyweight) and weight-axis PR (e1RM) render
            // differently on the right side:
            //   - `pr.reps != null` → `${reps} reps`
            //   - `pr.e1Rm != null` → `${displayE1Rm} $weightLabel`
            // Exactly one of the two is non-null on any given PR (asserted
            // in `StatsPR`).
            final String valueText;
            if (pr.reps != null) {
              valueText = '${pr.reps} reps';
            } else {
              final displayE1Rm = UnitFormatter.convertWeight(
                pr.e1Rm!,
                settingsState,
              );
              valueText = '${displayE1Rm.toStringAsFixed(1)} $weightLabel';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 16,
                    color: themeColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pr.exerciseName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: themeColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
