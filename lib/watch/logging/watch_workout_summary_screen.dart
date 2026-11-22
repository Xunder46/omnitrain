/// The Wear wrist's end-of-workout summary screen: the title, the rows the state
/// built, and Done.
///
/// Plan: `docs/plans/2026-11-22-292-wear-workout-summary-plan/2026-11-22-292-wear-workout-summary-plan.md`
/// (D-29204). The Dart counterpart of the Apple client's
/// `WatchWorkoutSummaryView`. Every decision behind what it shows is
/// `WatchWorkoutSummaryState`'s; this screen binds to the built summary and
/// nothing else. The body scrolls, so a short screen never overflows.
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../widgets/watch_controls.dart';
import 'watch_workout_summary.dart';

class WatchWorkoutSummaryScreen extends StatelessWidget {
  const WatchWorkoutSummaryScreen({
    super.key,
    required this.summary,
    required this.onDone,
  });

  final WatchWorkoutSummary summary;
  final VoidCallback onDone;

  static const Key doneKey = Key('watch_workout_summary_done');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    final compact = WatchLayout.isCompact(context);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            Semantics(
              header: true,
              child: Text(
                WatchWorkoutSummaryCopy.title,
                style: styles.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            for (final row in summary.rows)
              Semantics(
                container: true,
                excludeSemantics: true,
                label: row.label,
                value: row.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        row.label,
                        style: styles.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        row.value,
                        style: styles.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton(
              key: doneKey,
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonBorderRadius,
                    ),
                  ),
                ),
                minimumSize: WidgetStateProperty.all(
                  Size.fromHeight(
                    compact
                        ? WatchLayout.compactButtonHeight
                        : OmniTheme.buttonPrimaryHeight,
                  ),
                ),
                tapTargetSize: compact
                    ? MaterialTapTargetSize.shrinkWrap
                    : null,
              ),
              onPressed: onDone,
              child: const Text(WatchWorkoutSummaryCopy.done),
            ),
          ],
        ),
      ),
    );
  }
}
