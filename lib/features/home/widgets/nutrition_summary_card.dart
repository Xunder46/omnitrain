// filepath: lib/features/home/widgets/nutrition_summary_card.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../widgets/layout/omni_surface.dart';

/// A single self-contained gauge card on the home screen that
/// summarizes today's calorie intake against the daily goal
/// (Iteration 5 / S-100..S-106 — supersedes the Phase 4.1
/// `NutritionStripBar`).
///
/// Visually belongs to the same instrument-panel family as the
/// training tiles: rounded corners, a raised/lit look, a hairline
/// border, and an inset margin from the screen edges. NOT a
/// full-bleed rectangle, NOT square corners, NOT a pure-white
/// block. The ENTIRE card is one tap target; the chevron is a
/// visual cue only.
///
/// Priority of information on the card (S-100):
///   1. The **calorie figure** (`"{consumed} / {target} Cal"`) is
///      the headline — the largest, brightest text on the card.
///   2. A **single horizontal gauge** below the figure: fill
///      length = `consumed / target` (capped at 100%), subdivided
///      by protein / carbs / fat calorie contribution to the
///      consumed total. The unfilled remainder is the remaining
///      budget; the track visibly continues past the fill.
///   3. A **caption row** below the gauge with three
///      `(colorMarker, "M N%")` entries — protein, carbs, fat.
///      Captions carry the actual macro percentages, so the
///      user never has to read the bar segments precisely.
///
/// Pure presentation:
///   - No repository / state access — the caller pre-computes
///     `consumedCalories`, `targetCalories`, and the three
///     per-macro calorie contributions via the `NutritionState`
///     getters.
///   - No business logic — empty state vs happy state, segment
///     width math, and the warning-tone switch all live here so
///     the card can be tested in isolation against
///     `WidgetTester` without a live state graph.
///   - All colors come from `OmniTheme.colors`; the card never
///     picks a color of its own. Macro segments use the muted
///     `stripMacros` palette (terracotta / steel-blue / amber),
///     NOT the saturated `macroChart` palette — the card reads
///     as a lit panel, not a status light.
///
/// Required states:
///   The empty state is split across two orthogonal axes — the
///   gauge needs a **goal** (`consumed / target`) while the caption
///   needs **data to split** (P/C/F kcal share of consumed).
///
///   - **Empty — both axes** (S-104 / S-201): no food logged
///     (`consumedCalories == 0`). The figure shows
///     `"0 / {target} Cal"` (or `"0 / — Cal"` when no target is
///     set), the gauge fill has zero width, and the caption row
///     renders DASHES (`—`) for each macro — NOT `0%`. We do not
///     imply a real split when there is no data. The card is
///     still tappable.
///   - **Empty — gauge only** (S-200): no target configured
///     (`targetCalories == null`) but food has been logged. The
///     figure shows `"{n} / — Cal"`, the gauge fill is hidden
///     (no goal to fill against), and the caption row renders
///     the **real** macro percentages so the user gets
///     actionable feedback. The track still renders at full
///     width so the card layout stays stable.
///   - **Over-budget** (S-105): `consumedCalories > targetCalories`
///     (with `targetCalories > 0`). The figure text switches to
///     the theme's warning tone (`colorScheme.error`); the gauge
///     fill clamps to 100% of the track width (no overflow); the
///     macro segments sum to `trackWidth`. The captions still
///     show the actual macro percentages (the data is real).
///
/// The whole card sits inside an outer `Padding(EdgeInsets
/// .symmetric(horizontal: 16, vertical: 12))` so it is inset
/// from the screen edges — matching the training-tile grid's
/// 16 px side margin. The caller (HomeScreen) owns the
/// top-gap (`2 × standardGridSpacing`) above the card; the
/// card itself only handles its own inset.
class NutritionSummaryCard extends StatelessWidget {
  /// Today's consumed calories (already rounded by the caller).
  final int consumedCalories;

  /// Today's calorie target, or `null` for "no goal". The card
  /// renders the same in both empty-state cases
  /// (no target OR nothing logged); both render dashes in the
  /// caption row and an empty gauge.
  final int? targetCalories;

  /// Protein calorie contribution (D-4: `protein × 4`).
  final int proteinKcal;

  /// Net-carbs calorie contribution (`carbs - fiber`, then × 4).
  /// Uses net carbs for consistency with the donut chart's
  /// percentage calculation.
  final int carbsKcal;

  /// Fat calorie contribution (D-4: `fat × 9`).
  final int fatKcal;

  /// Tap handler. The card is always tappable; the empty state
  /// does NOT disable the surface.
  final VoidCallback onTap;

  const NutritionSummaryCard({
    super.key,
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.carbsKcal,
    required this.fatKcal,
    required this.onTap,
  });

  /// True when the user has NOT configured a daily calorie target.
  /// Independent of whether food has been logged.
  bool get _isNoTarget => targetCalories == null || targetCalories! <= 0;

  /// True when the user has not logged any food yet.
  bool get _hasNoConsumedData => consumedCalories <= 0;

  /// True when there is no macro split to show — either no food
  /// logged, or the macros on the logged foods sum to zero.
  /// Captures the S-202 case (consumed > 0 but P/C/F all 0).
  bool get _hasNoMacroData =>
      _hasNoConsumedData || (proteinKcal + carbsKcal + fatKcal) <= 0;

  /// True when the gauge should be hidden. The gauge represents
  /// `consumed / target`, which is undefined without a target — we
  /// hide the bar entirely rather than implying a progress value
  /// against an unknown goal. Also hidden when there is no
  /// consumed data, so the bar does not look broken on a fresh
  /// day (S-200).
  bool get _hideGauge => _isNoTarget || _hasNoConsumedData;

  /// True when the caption row should render dashes instead of real
  /// percentages. The caption only needs DATA to split, not a goal —
  /// it stays live whenever macros exist, even with `target == null`
  /// (S-200). Dashes return when there is nothing to split (no food
  /// logged, or all macros zero — S-201 / S-202).
  bool get _captionEmpty => _hasNoMacroData;

  /// Backwards-compatible alias for callers/tests that still reason
  /// in terms of a single "empty" state. True when the card has
  /// neither a target nor consumed data — i.e., the headline
  /// renders a fully empty figure AND the gauge AND the caption are
  /// both empty.
  bool get _isEmpty => _isNoTarget && _hasNoConsumedData;

  /// True when the user has exceeded the daily calorie goal.
  /// Only meaningful when there IS a target and there IS consumed
  /// data — otherwise the gauge is hidden anyway.
  bool get _isOverBudget {
    if (_isNoTarget || _hasNoConsumedData) return false;
    return consumedCalories > targetCalories!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The card chrome — rounded corners, surface fill, hairline
    // border, soft shadow lift — routes through `OmniSurface`
    // (the single source of truth for outlined-card chrome per
    // `docs/global_conventions.md`). The chrome matches the
    // training-tile visual family (EnergyTile uses
    // `OmniTheme.surfaceBorderRadius` and a similar surface
    // fill) so the card reads as part of the same instrument
    // panel, not a status bar bolted under the cockpit.
    //
    // The outer Padding is HORIZONTAL-only: 16 px inset from
    // the screen edges on each side, matching the training-tile
    // grid's side margin. Vertical padding is the home screen's
    // responsibility (top gap = 2 × standardGridSpacing; bottom
    // safe-area clearance added by the home screen) so the
    // card's outer top edge is exactly 32 px below the tile
    // grid bottom — a stable anchor for the widget tests.
    //
    // The `Material(type: transparency) + InkWell` pair wraps
    // the `OmniSurface` so the entire card body is one tap
    // target (S-101) and the splash is clipped to the card's
    // rounded corners. The `InkWell` does NOT need a custom
    // `BoxDecoration` — the splash paints on the `Material`'s
    // surface, which is the `OmniSurface`'s `Container` clip.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        key: const Key('nutrition_card'),
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
          child: OmniSurface(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Headline(
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                  isEmpty: _isEmpty,
                  isOverBudget: _isOverBudget,
                  warningColor: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                _Gauge(
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                  proteinKcal: proteinKcal,
                  carbsKcal: carbsKcal,
                  fatKcal: fatKcal,
                  isEmpty: _hideGauge,
                ),
                const SizedBox(height: 10),
                _CaptionRow(
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                  proteinKcal: proteinKcal,
                  carbsKcal: carbsKcal,
                  fatKcal: fatKcal,
                  isEmpty: _captionEmpty,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Headline row (S-100, S-104, S-105): small dining icon, the
/// `{consumed} / {target} Cal` text (the brightest, largest
/// text on the card), spacer, chevron-right navigation cue.
///
/// Color rules:
///   - Happy / empty: `themeColors.textDominant` (the only
///     element that earns white emphasis).
///   - Over-budget: `theme.colorScheme.error` (restrained
///     warning tone; not celebratory, not alarming).
///   - Empty: still `textDominant` — the figure is real (0 vs
///     the goal), not a placeholder.
class _Headline extends StatelessWidget {
  final int consumedCalories;
  final int? targetCalories;
  final bool isEmpty;
  final bool isOverBudget;
  final Color warningColor;

  const _Headline({
    required this.consumedCalories,
    required this.targetCalories,
    required this.isEmpty,
    required this.isOverBudget,
    required this.warningColor,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final headlineColor = isOverBudget
        ? warningColor
        : themeColors.textDominant;

    return Row(
      key: const Key('nutrition_card_headline'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.local_dining_outlined, size: 18, color: headlineColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _formatHeadline(consumedCalories, targetCalories),
            key: const Key('nutrition_card_headline_text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: headlineColor,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.chevron_right,
          key: const Key('nutrition_card_chevron'),
          size: 22,
          color: themeColors.textDominant,
        ),
      ],
    );
  }

  /// Format the headline figure with comma-grouped thousands.
  /// `1234567` → `1,234,567`. When [target] is `null` the
  /// target slot reads `—` (the figure still renders, the
  /// card stays tappable).
  static String _formatHeadline(int consumed, int? target) {
    final consumedStr = _fmt(consumed);
    final targetStr = target == null ? '—' : _fmt(target);
    return '$consumedStr / $targetStr Cal';
  }

  static String _fmt(int v) {
    final negative = v < 0;
    final digits = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }
}

/// The horizontal gauge: a track (full width) and a fill
/// (clamped to consumed / goal, subdivided by macro kcal
/// share of consumed). The track is the remaining budget; the
/// fill is what has been eaten so far.
///
/// S-103: the segments are sized as a share of CONSUMED
/// calories (not the full bar). The fill clamps to 100% of the
/// track when consumed > goal (S-105).
class _Gauge extends StatelessWidget {
  final int consumedCalories;
  final int? targetCalories;
  final int proteinKcal;
  final int carbsKcal;
  final int fatKcal;
  final bool isEmpty;

  const _Gauge({
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.carbsKcal,
    required this.fatKcal,
    required this.isEmpty,
  });

  static const double _gaugeHeight = 12.0;

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final macros = themeColors.stripMacros;

    return SizedBox(
      key: const Key('nutrition_card_gauge'),
      height: _gaugeHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          // S-102: fill fraction = consumed / target, clamped to 1.0.
          // The `isEmpty` parameter is the parent's `_hideGauge` flag:
          // true when there's no goal (target == null) OR no data
          // (consumed == 0) — see `NutritionSummaryCard._hideGauge`.
          // We collapse to a zero-width fill in that case rather than
          // implying progress against an unknown goal (S-200).
          final fillFraction = isEmpty
              ? 0.0
              : (consumedCalories / targetCalories!).clamp(0.0, 1.0);
          final fillWidth = trackWidth * fillFraction;
          final totalMacroKcal = proteinKcal + carbsKcal + fatKcal;
          return Stack(
            children: [
              // Layer 1: the track — full-width divider-colored
              // pill. This is the "remaining budget" surface.
              // S-105: still rendered at full width when the
              // user is over budget; the fill clamps on top of
              // it.
              Positioned.fill(
                child: DecoratedBox(
                  key: const Key('nutrition_card_gauge_track'),
                  decoration: BoxDecoration(
                    color: themeColors.divider,
                    borderRadius: BorderRadius.circular(_gaugeHeight / 2),
                  ),
                ),
              ),
              // Layer 2: the fill — a Row of three macro
              // segments, each sized as a share of CONSUMED
              // calories (S-103). The fill clips to its width
              // so segments never bleed past the consumed
              // target (S-105).
              if (fillWidth > 0 && totalMacroKcal > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fillWidth,
                  child: ClipRRect(
                    key: const Key('nutrition_card_gauge_fill'),
                    borderRadius: BorderRadius.circular(_gaugeHeight / 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        _GaugeSegment(
                          key: const Key('nutrition_card_gauge_segment_0'),
                          width: fillWidth * (proteinKcal / totalMacroKcal),
                          color: macros.protein,
                        ),
                        _GaugeSegment(
                          key: const Key('nutrition_card_gauge_segment_1'),
                          width: fillWidth * (carbsKcal / totalMacroKcal),
                          color: macros.carbs,
                        ),
                        _GaugeSegment(
                          key: const Key('nutrition_card_gauge_segment_2'),
                          width: fillWidth * (fatKcal / totalMacroKcal),
                          color: macros.fat,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A single segment of the gauge fill. Sized to its share of
/// CONSUMED calories (S-103) and clipped by the fill's
/// `ClipRRect` so it cannot bleed past the consumed target.
class _GaugeSegment extends StatelessWidget {
  final double width;
  final Color color;

  const _GaugeSegment({super.key, required this.width, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: double.infinity,
      child: ColoredBox(color: color),
    );
  }
}

/// The caption row (S-100, S-104, S-105): three
/// `(colorMarker, "M N%")` groups, evenly spaced across the
/// card width. The macro percentages are the macro's share
/// of CONSUMED calories (S-103). The empty state renders
/// DASHES (`—`), NOT `0%` — we do not imply a real split
/// when there is no data.
class _CaptionRow extends StatelessWidget {
  final int consumedCalories;
  final int? targetCalories;
  final int proteinKcal;
  final int carbsKcal;
  final int fatKcal;
  final bool isEmpty;

  const _CaptionRow({
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.carbsKcal,
    required this.fatKcal,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final macros = themeColors.stripMacros;
    final totalMacroKcal = proteinKcal + carbsKcal + fatKcal;
    // The caption row is laid out across the full card
    // content width with spaceBetween so the three entries
    // mirror each other. Each entry is a `Row(mainAxisSize:
    // MainAxisSize.min)` of (marker dot, label text).
    return Row(
      key: const Key('nutrition_card_caption'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CaptionEntry(
          key: const Key('nutrition_card_caption_protein'),
          color: macros.protein,
          label: 'P',
          percent: _macroPercent(proteinKcal, totalMacroKcal),
          isEmpty: isEmpty,
          textColor: themeColors.textSecondary,
        ),
        _CaptionEntry(
          key: const Key('nutrition_card_caption_carbs'),
          color: macros.carbs,
          label: 'C',
          percent: _macroPercent(carbsKcal, totalMacroKcal),
          isEmpty: isEmpty,
          textColor: themeColors.textSecondary,
        ),
        _CaptionEntry(
          key: const Key('nutrition_card_caption_fat'),
          color: macros.fat,
          label: 'F',
          percent: _macroPercent(fatKcal, totalMacroKcal),
          isEmpty: isEmpty,
          textColor: themeColors.textSecondary,
        ),
      ],
    );
  }

  /// Returns the integer-rounded percentage of the macro's
  /// share of total consumed macro calories. Returns `null`
  /// when there is no data (empty state) so the caller can
  /// render the dash placeholder.
  static int? _macroPercent(int macroKcal, int totalMacroKcal) {
    if (totalMacroKcal <= 0) return null;
    return ((macroKcal / totalMacroKcal) * 100).round();
  }
}

/// Single caption entry: a small color marker dot, a 6-px
/// gap, and the `"{M} {pct}%"` (or `"—"` for empty-state)
/// label text in tabular figures.
class _CaptionEntry extends StatelessWidget {
  final Color color;
  final String label;
  final int? percent;
  final bool isEmpty;
  final Color textColor;

  const _CaptionEntry({
    super.key,
    required this.color,
    required this.label,
    required this.percent,
    required this.isEmpty,
    required this.textColor,
  });

  static const double _markerSize = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Empty state: show the dash placeholder, NOT `0%`.
    final captionText = isEmpty ? '—' : '$label ${percent ?? 0}%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: _markerSize,
          height: _markerSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          captionText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
