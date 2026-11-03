import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/fuel_summary.dart';
import '../../../core/services/stats_progress_service.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// The name the split's training side reads under.
const String kFuelTrainingLabel = 'Training';

/// The name the split's rest side reads under.
const String kFuelRestLabel = 'Rest';

/// What a figure reads when there is nothing to show.
///
/// Absence is never zero here: a week with no logged day is a week without
/// data, not a week of fasting, so every missing average, comparison and side
/// reads this rather than `'0 kcal'` / `'0 g'`.
const String kFuelAbsent = '—';

/// The Fuel row: intake averaged over the 7 finished days ending yesterday,
/// split by training and rest days, against the day's target — and the entry
/// point to the full-history nutrition trend.
///
/// The averages are means over **logged** days only, so a week with three
/// logged days is a three-day mean; the row states how many days it averaged
/// so that figure is never read as a whole week. Below [kFuelMinLoggedDays]
/// logged days the row says so in words instead of drawing averages. Every
/// average is compared with the day's target where one is set, and with the
/// previous window otherwise; a field with neither reads [kFuelAbsent].
///
/// Its first line names its own fixed window in words (`Last 7 days`), so the
/// screen's four-week window never changes what this row shows.
class FuelSection extends StatelessWidget {
  final FuelSummary summary;
  final OmniThemeColors themeColors;
  final VoidCallback onTap;

  const FuelSection({
    super.key,
    required this.summary,
    required this.themeColors,
    required this.onTap,
  });

  static String _whole(double value) => value.round().toString();

  static String _figure(double? value, String unit) =>
      value == null ? kFuelAbsent : '${_whole(value)} $unit';

  /// The comparison against [reference] — the target where one is set, the
  /// previous window otherwise — or [kFuelAbsent] when there is nothing to
  /// compare, including a difference too small to survive whole-unit
  /// rounding, which would otherwise read as a change of zero.
  static String _change(double? value, double? reference, String unit) {
    if (value == null || reference == null) return kFuelAbsent;
    final delta = value.round() - reference.round();
    if (delta == 0) return kFuelAbsent;
    final arrow = delta > 0 ? '↑' : '↓';
    final sign = delta > 0 ? '+' : '-';
    return '$arrow $sign${delta.abs()} $unit';
  }

  static String _split(String label, double? calories, double? protein) {
    if (calories == null || protein == null) return '$label $kFuelAbsent';
    return '$label ${_whole(calories)} kcal · ${_whole(protein)} g';
  }

  /// The reference a field is compared against: its target when one is set,
  /// else the previous window.
  static double? _reference(bool hasTarget, double target, double? previous) =>
      hasTarget ? target : previous;

  /// Protein averaging below a target that is set: the one comparison the app
  /// knows is the wrong way round. Rounded the way [_change] rounds, so a gap
  /// that reads as no change is never red (D-17206).
  bool get _proteinBelowTarget {
    final average = summary.proteinAverage;
    return summary.hasProteinTarget &&
        average != null &&
        average.round() < summary.targetProtein.round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('fuel_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OmniCardHeader(title: 'Fuel'),
        OmniSurface(
          padding: EdgeInsets.zero,
          child: Semantics(
            label: 'Nutrition trend',
            button: true,
            child: InkWell(
              key: const Key('fuel_row'),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _caption(
                      theme,
                      key: const Key('fuel_horizon'),
                      text: 'Last ${StatsProgressService.kFuelWindowDays} days',
                    ),
                    const SizedBox(height: 8),
                    if (summary.showsAverages) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _metric(
                              theme,
                              labelKey: const Key('fuel_calories_label'),
                              label: 'Calories',
                              valueKey: const Key('fuel_calories'),
                              changeKey: const Key('fuel_calories_change'),
                              targetKey: const Key('fuel_calories_target'),
                              value: _figure(summary.caloriesAverage, 'kcal'),
                              change: _change(
                                summary.caloriesAverage,
                                _reference(
                                  summary.hasCalorieTarget,
                                  summary.targetCalories,
                                  summary.previousCaloriesAverage,
                                ),
                                'kcal',
                              ),
                              target: summary.hasCalorieTarget
                                  ? 'of ${_whole(summary.targetCalories)} kcal '
                                        'target'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _metric(
                              theme,
                              labelKey: const Key('fuel_protein_label'),
                              label: 'Protein',
                              valueKey: const Key('fuel_protein'),
                              changeKey: const Key('fuel_protein_change'),
                              targetKey: const Key('fuel_protein_target'),
                              value: _figure(summary.proteinAverage, 'g'),
                              change: _change(
                                summary.proteinAverage,
                                _reference(
                                  summary.hasProteinTarget,
                                  summary.targetProtein,
                                  summary.previousProteinAverage,
                                ),
                                'g',
                              ),
                              target: summary.hasProteinTarget
                                  ? 'of ${_whole(summary.targetProtein)} g target'
                                  : null,
                              bad: _proteinBelowTarget,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _metric(
                              theme,
                              labelKey: const Key('fuel_carbs_label'),
                              label: 'Carbs',
                              valueKey: const Key('fuel_carbs'),
                              changeKey: const Key('fuel_carbs_change'),
                              targetKey: const Key('fuel_carbs_target'),
                              value: _figure(summary.carbsAverage, 'g'),
                              change: _change(
                                summary.carbsAverage,
                                _reference(
                                  summary.hasCarbsTarget,
                                  summary.targetCarbs,
                                  summary.previousCarbsAverage,
                                ),
                                'g',
                              ),
                              target: summary.hasCarbsTarget
                                  ? 'of ${_whole(summary.targetCarbs)} g target'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _metric(
                              theme,
                              labelKey: const Key('fuel_fat_label'),
                              label: 'Fat',
                              valueKey: const Key('fuel_fat'),
                              changeKey: const Key('fuel_fat_change'),
                              targetKey: const Key('fuel_fat_target'),
                              value: _figure(summary.fatAverage, 'g'),
                              change: _change(
                                summary.fatAverage,
                                _reference(
                                  summary.hasFatTarget,
                                  summary.targetFat,
                                  summary.previousFatAverage,
                                ),
                                'g',
                              ),
                              target: summary.hasFatTarget
                                  ? 'of ${_whole(summary.targetFat)} g target'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!summary.showsAverages) ...[
                      Text(
                        'Log food on $kFuelMinLoggedDays days to see a weekly average',
                        key: const Key('fuel_not_enough_days'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: themeColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _caption(
                      theme,
                      key: const Key('fuel_logged_days'),
                      text:
                          '${summary.loggedDays}/'
                          '${StatsProgressService.kFuelWindowDays} days logged',
                    ),
                    if (summary.showsAverages) ...[
                      _caption(
                        theme,
                        key: const Key('fuel_split_training'),
                        text: _split(
                          kFuelTrainingLabel,
                          summary.trainingCaloriesAverage,
                          summary.trainingProteinAverage,
                        ),
                      ),
                      _caption(
                        theme,
                        key: const Key('fuel_split_rest'),
                        text: _split(
                          kFuelRestLabel,
                          summary.restCaloriesAverage,
                          summary.restProteinAverage,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One field: the window average, its comparison, and the target it is
  /// measured against when one is set.
  Widget _metric(
    ThemeData theme, {
    required Key labelKey,
    required String label,
    required Key valueKey,
    required Key changeKey,
    required Key targetKey,
    required String value,
    required String change,
    required String? target,
    bool bad = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          key: labelKey,
          style: theme.textTheme.labelSmall?.copyWith(
            color: themeColors.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          change,
          key: changeKey,
          style: theme.textTheme.labelSmall?.copyWith(
            color: _changeColor(theme, change, bad: bad),
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (target != null)
          Text(
            target,
            key: targetKey,
            style: theme.textTheme.labelSmall?.copyWith(
              color: themeColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  /// The comparison's colour: muted when there is nothing to compare, the error
  /// colour only for a figure the app knows is going the wrong way ([bad]), and
  /// neutral for every other comparison — under a calorie target is often the
  /// goal, so a direction alone says nothing (D-17206).
  Color _changeColor(ThemeData theme, String change, {bool bad = false}) {
    if (change == kFuelAbsent) return themeColors.textMuted;
    if (bad) return theme.colorScheme.error.withValues(alpha: 0.8);
    return themeColors.textSecondary;
  }

  Widget _caption(ThemeData theme, {required Key key, required String text}) {
    return Text(
      text,
      key: key,
      style: theme.textTheme.labelSmall?.copyWith(color: themeColors.textMuted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
