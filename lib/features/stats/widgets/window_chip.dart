import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/stats_progress.dart';

/// Which "current window" decided which exercises appear in the section it sits
/// in. Reads as `· Off-Season Strength Block` (a period) or
/// `· Last 14 training days` (the recent-days fallback).
///
/// Owned here so every section that explains itself — the four Instruments
/// headers and, until 4c, the four legacy headers — renders one chip the same
/// way rather than each drawing its own.
class StatsWindowChip extends StatelessWidget {
  final StatsWindow window;
  final OmniThemeColors themeColors;

  const StatsWindowChip({
    super.key,
    required this.window,
    required this.themeColors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      key: const Key('stats_window_chip'),
      '· ${window.label}',
      style: theme.textTheme.labelSmall?.copyWith(
        color: themeColors.textMuted,
        fontStyle: FontStyle.italic,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
