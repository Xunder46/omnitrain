// filepath: lib/features/nutrition/widgets/calorie_ring_card.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../state/nutrition_state.dart';
import 'calorie_ring.dart';
import 'macro_donut_chart.dart';

/// A `Card` wrapper around [CalorieRing] for the top of the nutrition
/// page. Reads consumed + target data from [NutritionState] and
/// rebuilds on every [Listenable] notification. Hosts the small
/// edit-targets icon in the card's top-right corner.
///
/// Composition:
///   - A [MacroDonutChart] (outer) that shows today's macro
///     distribution as colored arc sections. Each section is
///     tappable; tapping a section focuses it.
///   - A [CalorieRing] (inner) nested inside the donut's hollow
///     center. The ring's center content swaps between the
///     default calories view and a focused-macro
///     [MacroFocusContent] based on the card's focus state.
///
/// **Focus behavior** (Iteration 2, S-008..S-014):
///   - On first paint, no section is focused; the ring shows
///     calories.
///   - Tapping a section focuses it; the unfocused sections and
///     the calorie ring fade to `0.4` opacity; the ring's center
///     swaps to the focused macro's name + grams + percent.
///   - Tapping the same section again, or tapping the empty
///     center, deselects.
///   - Tapping a different section moves the focus directly (no
///     required deselect step).
///
/// **Focus survival** (S-013): when the underlying state changes
/// (food logged / deleted), the focus index is preserved as long
/// as the focused section still has non-zero grams. If the
/// focused section disappears (e.g. the only protein food is
/// deleted), the focus falls back to `null` and the default
/// calories view returns.
///
/// Pure presentation:
///   - No repository access (state is injected via constructor).
///   - No business logic — all consumed/target math lives in
///     [NutritionState] and [ConsumedFood].
///   - All colors come from [OmniTheme.colors].
class CalorieRingCard extends StatefulWidget {
  /// Source of today's target and consumed-foods cache. Required.
  final NutritionState nutritionState;

  /// Tap handler for the edit-targets icon. The widget does not
  /// navigate itself — the parent screen owns the routing contract
  /// (so this widget stays presentational and testable).
  final VoidCallback onEditTap;

  const CalorieRingCard({
    super.key,
    required this.nutritionState,
    required this.onEditTap,
  });

  @override
  State<CalorieRingCard> createState() => _CalorieRingCardState();
}

class _CalorieRingCardState extends State<CalorieRingCard> {
  /// Index of the focused section in the chart's section list, or
  /// `null` for the default (no focus) state. Owned here so the
  /// card can drive the per-section opacities, the ring's
  /// `centerOverride`, and the ring's wrapper opacity.
  int? _focusedSectionIndex;

  /// Opacity applied to unfocused sections when a section is
  /// focused. Tuned per the Q&A: mild fade so the focus is
  /// communicated by contrast, not disappearance.
  static const double _unfocusedOpacity = 0.4;

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.nutritionState,
      builder: (context, _) {
        // The target is "set" only when it's a non-null
        // NutritionTarget AND its calories value is > 0. A target
        // whose calories field is 0 (e.g. cleared or only macros
        // set) is treated as "no goal" for the ring.
        final target = widget.nutritionState.nutritionTarget;
        final targetCalories = (target != null && target.calories > 0)
            ? target.calories
            : null;
        final consumed = widget.nutritionState.todayConsumedCalories;

        // The chart's section list drives both the chart's
        // opacities and the center content. Compute it here so
        // we can also derive the focus-survival fallback.
        final protein = widget.nutritionState.todayConsumedProtein;
        final netCarbsRaw = math.max(
          0,
          widget.nutritionState.todayConsumedCarbs -
              widget.nutritionState.todayConsumedFiber,
        );
        final fiber = widget.nutritionState.todayConsumedFiber;
        final fat = widget.nutritionState.todayConsumedFat;
        final sections = computeMacroSections(
          protein: protein,
          netCarbs: netCarbsRaw,
          fiber: fiber,
          fat: fat,
          gapDegrees: 1.5,
        );

        // If a focus was set but the focused section has
        // disappeared (grams dropped to 0), clear the focus.
        // We don't mutate the index here; we just ignore it for
        // rendering. The next valid tap will replace it.
        final effectiveFocus = (_focusedSectionIndex != null &&
                _focusedSectionIndex! < sections.length)
            ? _focusedSectionIndex
            : null;

        // Per-section opacities: 1.0 for the focused section,
        // _unfocusedOpacity for the rest, 1.0 for all when no
        // section is focused.
        final opacities = <double>[
          for (var i = 0; i < sections.length; i++)
            (effectiveFocus == null || effectiveFocus == i)
                ? 1.0
                : _unfocusedOpacity,
        ];

        // Center content: default calories vs the focused
        // macro's content. Per S-041 / D-4, the focused view shows
        // grams + the macro's share of *consumed calories* (never
        // "of target"). Calories per macro follow D-4:
        //   protein*4 + carbs*4 + fat*9
        // Net carbs and protein are scaled to the reference
        // amount already, so we multiply by 4 (kcal per gram).
        // Fiber contributes zero calories, so it falls into the
        // `informational` branch.
        final Widget? centerOverride;
        if (effectiveFocus != null) {
          final s = sections[effectiveFocus];
          final proteinKcal = protein * 4;
          final netCarbsKcal = netCarbsRaw * 4;
          final fatKcal = fat * 9;
          // D-4 totals calories from protein + net carbs + fat
          // (fiber is informational only and excluded from the
          // sum).
          final totalKcal = proteinKcal + netCarbsKcal + fatKcal;
          int? pct;
          if (totalKcal > 0) {
            final sectionKcal = switch (s.name) {
              'Protein' => proteinKcal,
              'Net Carbs' => netCarbsKcal,
              'Fat' => fatKcal,
              // Fiber is informational; never reach the percent
              // math here because `informational: true` makes the
              // widget skip the percent.
              _ => 0,
            };
            pct = totalKcal == 0
                ? 0
                : (sectionKcal * 100 / totalKcal).round();
          }
          final isInformational = s.name == 'Fiber';
          centerOverride = MacroFocusContent(
            name: s.name,
            grams: s.grams,
            percentOfCalories: pct ?? 0,
            color: s.color,
            informational: isInformational,
          );
        } else {
          centerOverride = null;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Note: Edit targets icon moved to header section outside
                // the card (in NutritionScreen, alongside "Today" title).
                // Donut chart (outer) + calorie ring (inner) in a
                // Stack. The donut is hidden when no macros are
                // logged — the calorie ring stays visible alone at
                // its full 160 px size. When the donut IS present,
                // the ring fades to 0.4 opacity whenever a section
                // is focused.
                Center(
                  child: SizedBox(
                    width: 280,
                    height: 280,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Inner calorie ring (bottom of the
                        // stack). Always rendered first so the
                        // outer macro donut is on top for hit
                        // testing.
                        // Pass centerOverride to CalorieRing so it
                        // hides its internal center content when
                        // focused (uses AnimatedSwitcher). Only the
                        // ring itself fades - the center content is
                        // handled separately below.
                        CalorieRing(
                          consumed: consumed.toDouble(),
                          target: targetCalories,
                          size: 200,
                          centerOverride: centerOverride,
                        ),
                        // Outer macro donut on top — its
                        // GestureDetector owns hit testing for
                        // the whole chart. Taps in the band's
                        // arc resolve to a section index; taps
                        // inside the inner radius (the empty
                        // center, where the calorie ring is)
                        // resolve to the center sentinel and
                        // deselect. The ring underneath is
                        // therefore never the tap target — the
                        // user only ever interacts with the
                        // donut.
                        // Note: The chart uses per-section opacities
                        // (1.0 focused, 0.4 unfocused) so no
                        // additional wrapper opacity is needed.
                        MacroDonutChart(
                          protein: protein,
                          netCarbs: netCarbsRaw,
                          fiber: fiber,
                          fat: fat,
                          size: 280,
                          sectionOpacities: opacities,
                          onSectionFocusChange: (newIndex) {
                            // No-op if the index didn't change.
                            if (newIndex == _focusedSectionIndex) return;
                            setState(() => _focusedSectionIndex = newIndex);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Sodium daily-total label at bottom left (D-7 / S-043).
                // Format: "Na 148 mg". Single rounding per D-7;
                // null source sodium is treated as 0 by the
                // state's `todayConsumedSodium` getter, so this
                // line always shows a number (including 0 on
                // empty days).
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0, top: 8),
                    child: _SodiumTotalChip(
                      sodiumMg: widget
                          .nutritionState.todayConsumedSodium,
                      themeColors: themeColors,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Small chip-style label that renders today's consumed sodium as
/// `"Na 148 mg"`. Lives in the calorie-ring card's top-right corner
/// to the left of the edit-targets icon (D-7 / S-043).
///
/// Uses comma-grouped integers for the mg value so large numbers
/// (e.g. 1,250 mg) read at a glance. The label is muted-text in
/// the active color scheme so it does not compete with the
/// "Today" title or the edit icon.
class _SodiumTotalChip extends StatelessWidget {
  /// Today's consumed sodium in milligrams (already rounded to int
  /// by the state's `todayConsumedSodium` getter). Rendered as-is.
  final int sodiumMg;

  final OmniThemeColors themeColors;

  const _SodiumTotalChip({
    required this.sodiumMg,
    required this.themeColors,
  });

  /// Comma-grouped integer (e.g. 1,250). Negative values get a
  /// leading "-". Mirrors the helper in [CalorieRing] so the two
  /// corners of the card use the same formatting rules.
  String _formatThousands(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Na ${_formatThousands(sodiumMg)} mg',
      key: const Key('nutrition_sodium_total'),
      style: theme.textTheme.labelMedium?.copyWith(
        color: themeColors.textMuted,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Small icon button (the edit-targets affordance). Renders as a plain
/// `IconButton` with an explicit tooltip for screen readers and a stable
/// key so tests can find it.
///
/// Visual choice: a 40×40 square tinted with the active theme's primary
/// at 60% opacity — visible against the dark card surface without
/// competing with the ring itself. Does not use the full
/// `OmniTheme.buttonIconSize` (60×60) so it does not overpower the
/// 160 px ring.
class _EditTargetsIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final OmniThemeColors themeColors;

  const _EditTargetsIconButton({
    required this.onPressed,
    required this.themeColors,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('edit_targets_icon'),
      icon: Icon(
        Icons.tune,
        size: 20,
        color: themeColors.primary,
      ),
      tooltip: 'Edit targets',
      onPressed: onPressed,
      // 40×40 hit target — comfortably above the 48 dp Material minimum
      // when paired with the screen's 16 dp card padding.
      visualDensity: VisualDensity.compact,
      style: ButtonStyle(
        // Explicit shape to avoid Material 3's StadiumBorder default.
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
          ),
        ),
        backgroundColor: WidgetStateProperty.all(
          themeColors.primary.withValues(alpha: 0.12),
        ),
        padding: WidgetStateProperty.all(const EdgeInsets.all(8)),
      ),
    );
  }
}
