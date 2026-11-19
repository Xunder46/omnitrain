import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/services/last_performance_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/settings/settings_state.dart';

/// One muted line above the reps controls: when the exercise was last done and
/// what was logged (plan 249), e.g. `Last (Nov 12): 8×80 · 8×80 · 6×82.5 kg`.
class LastSetsLine extends StatelessWidget {
  const LastSetsLine({
    super.key,
    required this.lastSets,
    required this.settingsState,
  });

  final LastSets lastSets;
  final SettingsState settingsState;

  /// Sets named in the line; the rest are counted.
  static const int maxShown = 6;

  /// The line's text. A set with no load shows its reps only; the unit is the
  /// weight unit when any set had a load, else `reps`; more than [maxShown]
  /// sets end with `(+N more)`.
  static String describe(LastSets lastSets, SettingsState settings) {
    final date = OmniDateUtils.formatShort(
      DateTime.fromMillisecondsSinceEpoch(lastSets.startedAtMs),
    );
    final shown = lastSets.sets.take(maxShown).toList();
    final anyLoad = lastSets.sets.any((s) => s.weightKg > 0);
    final parts = [
      for (final s in shown)
        s.weightKg > 0
            ? '${s.reps}×${UnitFormatter.formatWeightValue(s.weightKg, settings)}'
            : '${s.reps}',
    ];
    final unit = anyLoad ? UnitFormatter.weightLabel(settings) : 'reps';
    final extra = lastSets.sets.length - shown.length;
    final more = extra > 0 ? ' (+$extra more)' : '';
    return 'Last ($date): ${parts.join(' · ')} $unit$more';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      describe(lastSets, settingsState),
      key: const Key('last_sets_line'),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: OmniTheme.colors.textMuted),
    );
  }
}
