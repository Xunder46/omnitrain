// filepath: lib/features/nutrition/widgets/nutrition_primer_sheet.dart
//
// One-shot orientation sheet for the Daily Nutrition page (see
// `.github/agents/plans/nutrition-page-primer-plan.md`).
//
// The page inverts the usual food-logging model and packs several
// unfamiliar ideas onto one screen (curate a "Foods I Eat" list once
// from the global library, check foods off daily with an adjustable
// per-food portion, watch the day roll up into a calories/macros
// ring + water + sodium). This sheet explains the model in three
// short blocks on the user's first home-strip tap, and is reopenable
// from the nutrition page header "?" at any time.
//
// Architecture notes:
// - **Pure presentation.** No repository or state access. The seen
//   state lives in `NutritionPrimerState` (see
//   `lib/state/nutrition/nutrition_primer_state.dart`) and is
//   mutated by the host screen AFTER the sheet pops, NOT here. The
//   sheet is reused by the home strip (which marks seen on dismiss)
//   and the header "?" (which does NOT mark seen) — the host
//   decides what dismiss means via [onDismiss].
// - **Single self-contained sheet.** No `PageView`, no step
//   indicators, no Next/Back navigation, no pointers anchored to
//   live on-screen widgets. The copy must read correctly even if
//   the page layout changes.
// - **Explicit button shape.** The "Got it" CTA sets
//   `shape: RoundedRectangleBorder(borderRadius: BorderRadius
//   .circular(OmniTheme.buttonBorderRadius))` — never the Material 3
//   default `StadiumBorder`. This matches the rest of the app's
//   primary CTAs.

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// Public widget. Renders the three primer blocks + a single "Got it"
/// CTA inside a scrollable column. The host screen wraps this in a
/// `showModalBottomSheet(isScrollControlled: true, ...)` and is
/// responsible for the sheet chrome (drag handle, rounded top, fade
/// gradient, safe-area bottom padding).
///
/// [onDismiss] is fired AFTER `Navigator.pop` resolves, so the host
/// can run side-effects (e.g. `NutritionPrimerState.markSeen()` or
/// `OmniNavigator.push(NutritionScreen)`) once the sheet is fully
/// gone. If `onDismiss` is `null`, dismissal just closes the sheet.
class NutritionPrimerSheet extends StatelessWidget {
  /// Optional callback fired on dismiss. If `null`, dismissal just
  /// closes the sheet.
  final VoidCallback? onDismiss;

  const NutritionPrimerSheet({super.key, this.onDismiss});

  /// Three labeled primer blocks. Each has a canonical D-1 header
  /// (via `OmniCardHeader`) and one or two plain sentences below.
  ///
  /// Keys: `nutrition_primer_block_curate`,
  /// `nutrition_primer_block_check`,
  /// `nutrition_primer_block_rollup` — used by the tests to assert
  /// the rendered structure (S-004).
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
              'DAILY NUTRITION',
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
          // Block 1: curated "Foods I Eat" list.
          const _PrimerBlock(
            key: Key('nutrition_primer_block_curate'),
            label: 'YOUR LIST, BUILT ONCE',
            body:
                'Add foods from the library into "Foods I Eat" once. '
                'They stay, grouped by category, until you remove them. '
                'Manage the list anytime from the edit control.',
          ),
          const SizedBox(height: 16),
          // Block 2: daily check-off with adjustable portion.
          const _PrimerBlock(
            key: Key('nutrition_primer_block_check'),
            label: 'CHECK TO LOG, SET THE AMOUNT',
            body:
                'Each day, check off what you ate to count it toward today. '
                'Adjust the amount per food — the portion is yours to set, not fixed.',
          ),
          const SizedBox(height: 16),
          // Block 3: rollup — calories, macros, water, sodium.
          const _PrimerBlock(
            key: Key('nutrition_primer_block_rollup'),
            label: 'TODAY AND OVER TIME',
            body:
                'Check-offs roll into the donut chart, '
                'and your stats screen tracks your nutrition trends across days and weeks.',
          ),
          const SizedBox(height: 24),
          // Single primary action — explicit shape, theme token, no
          // StadiumBorder. Keyed for tests.
          SizedBox(
            height: OmniTheme.buttonPrimaryHeight,
            width: double.infinity,
            child: FilledButton(
              key: const Key('nutrition_primer_dismiss'),
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
                // Pop first so the host's post-dismiss logic runs
                // against a stable, sheet-less tree.
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

/// One primer block: a canonical D-1 header plus the explanation
/// sentence(s). Used internally by `NutritionPrimerSheet`; exposed
/// as a private widget because the structure is owned by the sheet.
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
        // `OmniCardHeader` enforces the contract (labelSmall, weight
        // 600, letter-spacing 2.0, color textMuted). This keeps the
        // primer visually consistent with every other section/card
        // header in the app (see `docs/global_conventions.md` and
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
