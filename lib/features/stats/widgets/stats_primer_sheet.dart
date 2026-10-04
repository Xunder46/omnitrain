// filepath: lib/features/stats/widgets/stats_primer_sheet.dart
//
// One-shot orientation sheet for the Stats screen (see
// `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/`).
//
// A first-time user opening Stats sees one card, "No sessions yet", and
// nothing else: nothing explains what will appear once they train, what
// the Signals cards mean, or what the header chart icon does. This sheet
// explains the screen in three short blocks, auto-opens once on the first
// Stats tap from Home, and is reopenable from the header "?" at any time.
//
// Architecture notes:
// - **Pure presentation.** No repository or state access. The seen state
//   lives in `StatsPrimerState` and is mutated by the host screen AFTER
//   the sheet pops, NOT here. The sheet accepts an optional [onDismiss]
//   for parity with `NutritionPrimerSheet`; every Stats host passes
//   `null`, so the "?" and the empty-card button can never mark seen.
// - **Single self-contained sheet.** No `PageView`, no step indicators,
//   no Next/Back navigation, no pointers anchored to live on-screen
//   widgets. The copy must read correctly even if the page layout changes.
// - **Explicit button shape.** The "Got it" CTA sets
//   `shape: RoundedRectangleBorder(borderRadius: BorderRadius
//   .circular(OmniTheme.buttonBorderRadius))` — never the Material 3
//   default `StadiumBorder`. This matches the rest of the app's primary
//   CTAs.

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// Public widget. Renders the three primer blocks + a single "Got it" CTA
/// inside a scrollable column. The host screen wraps this in a
/// `showModalBottomSheet(isScrollControlled: true, ...)` and is
/// responsible for the sheet chrome (drag handle, rounded top, fade
/// gradient, safe-area bottom padding).
///
/// [onDismiss] is fired AFTER `Navigator.pop` resolves, so the host can run
/// side-effects once the sheet is fully gone. If `onDismiss` is `null`,
/// dismissal just closes the sheet.
class StatsPrimerSheet extends StatelessWidget {
  /// Optional callback fired on dismiss. If `null`, dismissal just closes
  /// the sheet.
  final VoidCallback? onDismiss;

  const StatsPrimerSheet({super.key, this.onDismiss});

  /// Three labeled primer blocks. Each has a canonical D-1 header (via
  /// `OmniCardHeader`) and one plain sentence below.
  ///
  /// Keys: `stats_primer_block_page`, `stats_primer_block_signals`,
  /// `stats_primer_block_records` — used by the tests to assert the
  /// rendered structure.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return OmniSurface(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top eyebrow: short sheet title.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'STATS',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: themeColors.textMuted,
              ),
            ),
          ),
          Text(
            'A quick orientation',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: OmniTheme.titleLetterSpacing,
              color: themeColors.textDominant,
            ),
          ),
          const SizedBox(height: 16),
          // Block 1: what the page itself shows.
          const _PrimerBlock(
            key: Key('stats_primer_block_page'),
            label: 'WHAT THIS PAGE SHOWS',
            body:
                'Your training mix by kind of work, the exercises you have '
                'trained and how they changed since last time, all-time '
                'totals, and your Fuel row once you log food.',
          ),
          const SizedBox(height: 16),
          // Block 2: the Signals cards.
          const _PrimerBlock(
            key: Key('stats_primer_block_signals'),
            label: 'SIGNALS',
            body:
                'Short notes about your own patterns, compared only with '
                'your own history. They start after about four weeks of '
                'rating how hard each workout felt, and a few need food '
                'logging or a watch. Dismiss any card and it stays hidden '
                'for 14 days.',
          ),
          const SizedBox(height: 16),
          // Block 3: the header chart icon.
          const _PrimerBlock(
            key: Key('stats_primer_block_records'),
            label: 'THE CHART ICON',
            body:
                'Opens Records & Trends: your personal records and the full '
                'history of each exercise. Tap an exercise there to see its '
                'progress.',
          ),
          const SizedBox(height: 24),
          // Single primary action — explicit shape, theme token, no
          // StadiumBorder. Keyed for tests.
          SizedBox(
            height: OmniTheme.buttonPrimaryHeight,
            width: double.infinity,
            child: FilledButton(
              key: const Key('stats_primer_dismiss'),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonBorderRadius,
                    ),
                  ),
                ),
              ),
              onPressed: () {
                // Pop first so the host's post-dismiss logic runs against a
                // stable, sheet-less tree.
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Got it'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One primer block: a canonical D-1 header plus the explanation sentence.
/// Used internally by `StatsPrimerSheet`; exposed as a private widget
/// because the structure is owned by the sheet.
class _PrimerBlock extends StatelessWidget {
  final String label;
  final String body;

  const _PrimerBlock({super.key, required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The label uses the canonical D-1 header typography —
        // `OmniCardHeader` enforces the contract (labelSmall, weight 600,
        // letter-spacing 2.0, color textMuted). This keeps the primer
        // visually consistent with every other section/card header in the
        // app (see `docs/global_conventions.md` and
        // `docs/widget_catalog.md` → `OmniCardHeader`).
        OmniCardHeader(
          title: label,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        ),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: themeColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
