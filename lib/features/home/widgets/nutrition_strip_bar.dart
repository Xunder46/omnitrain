// filepath: lib/features/home/widgets/nutrition_strip_bar.dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// Per-macro calorie contribution rendered as a single segment of
/// the strip's filled bar (D-5 / D-8). Widths and percentages are
/// pre-computed by the caller so the widget stays math-free — it
/// only lays out what it is given.
class StripSegment {
  /// Calorie contribution of this macro, pre-rounded to int.
  /// Used to compute the segment's width and its "% of calories"
  /// label.
  final int kcal;

  /// Color used to fill the segment. Comes from
  /// `OmniTheme.colors.macroChart.<slot>` — the widget itself
  /// never picks a color.
  final Color color;

  /// Human-readable label for the macro (e.g. `"P"`). The widget
  /// renders this as the "% of calories" caption inside the
  /// segment, optionally paired with a "P · " prefix; the caller
  /// is free to pass `"P"` or `"P 25%"` etc. The widget just
  /// measures the final string and hides the label when it does
  /// not fit (S-053).
  final String label;

  const StripSegment({
    required this.kcal,
    required this.color,
    required this.label,
  });
}

/// A full-height home-screen footer that summarizes today's calorie
/// intake against the daily target with a segmented macronutrient
/// bar (D-8 — supersedes the D-5 two-row layout).
///
/// Pure presentation:
///   - no repository / state access — the caller pre-computes
///     `consumedCalories`, `targetCalories`, and the three
///     per-macro calorie contributions via the
///     [NutritionState] getters (D-4 math).
///   - no business logic — empty state vs happy state, segment
///     width math, label-fit measurement, and the chevron
///     silhouette all live here so the strip can be tested in
///     isolation against `WidgetTester` without a live state graph.
///   - all colors come from [OmniTheme.colors]; the strip never
///     picks a color of its own.
///
/// Layout (per D-8 — supersedes D-5):
///   * The **whole strip is the progress bar**. The strip is a
///     single full-height region from the tile-grid bottom +
///     `2 × standardGridSpacing` to the physical bottom edge of
///     the screen. The surface is the track.
///   * Fill width = `consumed / target` capped at 100% (S-052);
///     the fill is subdivided P → C → F by calorie contribution
///     (D-4 math, total carbs for blue). Interior segment
///     boundaries are straight vertical lines; ONLY the fill's
///     leading (right) edge is chevron-shaped, carried by the
///     trailing segment.
///   * Each segment shows `"{M} {pct}%"` inside; the label is
///     hidden when it does not fit (S-053). The full-strip
///     height makes labels fit far smaller widths than the
///     v1 thin-segment failure case (S-050b).
///   * Calorie label `"{consumed} / {target} cal"` overlays
///     top-left in one line with the chevron-right at top-right,
///     with a contrast treatment (shadowed text) legible over
///     fill and track alike.
///   * Top edge: hairline border only — NO upward drop shadow.
///   * Empty state (no target set OR nothing logged): one
///     inviting message, centered, full strip still tappable
///     (S-051). The strip surface is the track in both states.
///
/// Sits inside a `SafeArea(top: false)` (the bottom safe area
/// is the strip's responsibility; the top safe area belongs to
/// the tile grid above).
class NutritionStripBar extends StatelessWidget {
  /// Today's consumed calories (already rounded by the caller).
  final int consumedCalories;

  /// Today's calorie target, or `null` for "no goal" (S-051:
  /// empty state when null OR when `consumedCalories == 0`).
  final int? targetCalories;

  /// Protein calorie contribution. The widget treats the three
  /// segments as `proteinKcal`, `totalCarbsKcal`, `fatKcal` in
  /// that order.
  final int proteinKcal;

  /// Total-carbs calorie contribution. D-8 carries forward D-5:
  /// "total-carb calories for blue" — net carbs (carbs - fiber)
  /// is the donut's keto view per D-4 and is intentionally NOT
  /// what the strip uses.
  final int totalCarbsKcal;

  /// Fat calorie contribution.
  final int fatKcal;

  /// Tap handler. The strip is always tappable; the empty state
  /// does not disable the surface (S-051).
  final VoidCallback onTap;

  /// Optional override for the empty-state copy. The default
  /// matches the D-5 spec example.
  final String emptyMessage;

  /// Pre-computed list of segments. Optional; when omitted the
  /// widget builds the default Protein / Carbs / Fat order from
  /// the per-macro calorie props. Tests use this to inject
  /// custom labels (e.g. "P 25%") or colors without rebuilding
  /// the state plumbing.
  final List<StripSegment>? segmentsOverride;

  const NutritionStripBar({
    super.key,
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.totalCarbsKcal,
    required this.fatKcal,
    required this.onTap,
    this.emptyMessage = 'Track your nutrition — tap to start',
    this.segmentsOverride,
  });

  /// True when the strip should render the empty state
  /// (no target set OR nothing logged).
  bool get _isEmpty =>
      targetCalories == null || targetCalories! <= 0 || consumedCalories <= 0;

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;

    // Decoration lives OUTSIDE the SafeArea so the strip
    // background (track) extends to the physical bottom edge of
    // the screen (S-056). The content (label overlay, empty
    // message) lives INSIDE the SafeArea(top: false) so the
    // bottom home-indicator inset does not cover the text.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: themeColors.surface,
            border: Border(
              top: BorderSide(
                color: themeColors.surfaceBorder,
                width: OmniTheme.surfaceBorderWidth,
              ),
            ),
            // D-8: hairline top border only — no upward drop
            // shadow over the tile grid.
          ),
          child: _isEmpty
              ? SafeArea(
                  top: false,
                  child: _EmptyStrip(message: emptyMessage),
                )
              : SafeArea(
                  top: false,
                  child: _FilledStrip(
                    consumedCalories: consumedCalories,
                    targetCalories: targetCalories!,
                    proteinKcal: proteinKcal,
                    totalCarbsKcal: totalCarbsKcal,
                    fatKcal: fatKcal,
                    segmentsOverride: segmentsOverride,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Empty-state row (S-051). No bar, no numbers. Tap lives on the
/// parent `InkWell`. Centred per D-8 (was left-aligned in the
/// D-5 layout; the full-strip height makes the centre alignment
/// read as a deliberate "tap-to-log" affordance).
class _EmptyStrip extends StatelessWidget {
  final String message;
  const _EmptyStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    return SizedBox(
      key: const Key('nutrition_strip_empty'),
      height: NutritionStripBarMetrics.contentHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: themeColors.textDominant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
          ),
        ),
      ),
    );
  }
}

/// Happy-state full-strip layout: a single region where the
/// track IS the strip. The fill renders inside the strip; the
/// calorie label overlays top-left with a contrast scrim and
/// the chevron-right overlays top-right.
class _FilledStrip extends StatelessWidget {
  final int consumedCalories;
  final int targetCalories;
  final int proteinKcal;
  final int totalCarbsKcal;
  final int fatKcal;
  final List<StripSegment>? segmentsOverride;

  const _FilledStrip({
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.totalCarbsKcal,
    required this.fatKcal,
    required this.segmentsOverride,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final segments = segmentsOverride ??
        <StripSegment>[
          StripSegment(
            kcal: proteinKcal,
            color: themeColors.macroChart.protein,
            label: 'P',
          ),
          StripSegment(
            kcal: totalCarbsKcal,
            color: themeColors.macroChart.netCarbs,
            label: 'C',
          ),
          StripSegment(
            kcal: fatKcal,
            color: themeColors.macroChart.fat,
            label: 'F',
          ),
        ];

    return SizedBox(
      key: const Key('nutrition_strip_filled'),
      height: NutritionStripBarMetrics.contentHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              // Layer 1: the track + segmented fill. Paints the
              // full strip width so the track visibly continues
              // past the fill to 100% (S-050b).
              Positioned.fill(
                child: _SegmentedBar(
                  segments: segments,
                  trackColor: themeColors.divider,
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                  availableWidth: width,
                ),
              ),
              // Layer 2: in-segment labels. Drawn as positioned
              // `Text` widgets so they survive widget tests
              // (`find.textContaining('P 25%')` is the canonical
              // S-050b / S-053 probe). Each label hides itself
              // when the segment is too narrow (S-053).
              Positioned.fill(
                child: _SegmentLabels(
                  segments: segments,
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                ),
              ),
              // Layer 3: overlay content (calorie label +
              // chevron-right). The enclosing SafeArea(top:
              // false) keeps the content above the bottom
              // home-indicator inset.
              Positioned.fill(
                child: _OverlayLabel(
                  consumedCalories: consumedCalories,
                  targetCalories: targetCalories,
                ),
              ),
            ],
          );
        },
      ),
    );
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

/// The calorie-label overlay drawn on top of the bar. Uses a
/// dark text-shadow so the label is legible over both the
/// fill and the track (D-8 contrast requirement). A solid
/// scrim would obscure the segments; a shadow keeps the
/// segments visible while the text still reads.
class _OverlayLabel extends StatelessWidget {
  final int consumedCalories;
  final int targetCalories;

  const _OverlayLabel({
    required this.consumedCalories,
    required this.targetCalories,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final contrastShadow = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.55),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        key: const Key('nutrition_strip_label'),
        children: [
          Icon(
            Icons.local_dining_outlined,
            size: 18,
            color: themeColors.textDominant,
            shadows: contrastShadow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_FilledStrip._fmt(consumedCalories)} / '
              '${_FilledStrip._fmt(targetCalories)} cal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: themeColors.textDominant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    shadows: contrastShadow,
                  ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: themeColors.textDominant,
            shadows: contrastShadow,
          ),
        ],
      ),
    );
  }
}

/// In-segment labels (e.g. `"P 25%"` inside the protein
/// segment). Each label is positioned at the segment's
/// pixel x-offset and width, with a chevron-cleared right
/// edge for the trailing segment so the text does not
/// collide with the arrow tip.
///
/// Labels are real `Text` widgets (not `TextPainter` in a
/// `CustomPaint`) so widget tests can probe them with
/// `find.textContaining('P 25%')` — that is the S-050b /
/// S-053 contract. Each label hides itself via a
/// `LayoutBuilder` when the segment is too narrow to fit
/// the text (S-053).
class _SegmentLabels extends StatelessWidget {
  final List<StripSegment> segments;
  final int consumedCalories;
  final int targetCalories;

  const _SegmentLabels({
    required this.segments,
    required this.consumedCalories,
    required this.targetCalories,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    // S-052: fill caps at 100% width.
    final fraction = (targetCalories <= 0)
        ? 0.0
        : (consumedCalories / targetCalories).clamp(0.0, 1.0).toDouble();
    final totalKcal = segments.fold<int>(0, (s, seg) => s + seg.kcal);
    if (totalKcal <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillWidth = width * fraction;
        // Per-segment widths in pixels. The last segment
        // absorbs any rounding drift so the segments add up
        // to exactly `fillWidth`.
        final widths = <double>[];
        var cum = 0.0;
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final isLast = i == segments.length - 1;
          final segFrac = seg.kcal / totalKcal;
          final w = isLast
              ? (fillWidth - cum).clamp(0.0, fillWidth - cum)
              : fillWidth * segFrac;
          widths.add(w);
          cum += w;
        }
        // For label placement we shrink the trailing segment
        // a little so the chevron tip does not collide with
        // the right edge of the label.
        final height = constraints.maxHeight;

        var x = 0.0;
        final children = <Widget>[];
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final w = widths[i];
          // Reserve a chevron-clearance gap for the last
          // segment's right edge so the label sits inside the
          // rectangular part, not under the arrow tip.
          final reservedRight = (i == segments.length - 1)
              ? NutritionStripBarMetrics.chevronReserve
              : 0.0;
          children.add(
            Positioned(
              key: Key('nutrition_strip_segment_label_$i'),
              left: x,
              top: 0,
              width: w - reservedRight,
              height: height,
              child: _SegmentLabel(
                seg: seg,
                fraction: seg.kcal / totalKcal,
                textColor: themeColors.textDominant,
              ),
            ),
          );
          x += w;
        }
        return Stack(children: children);
      },
    );
  }
}

/// Single-segment label (e.g. `"P 25%"`). Hidden when the
/// segment is too narrow to fit the text (S-053). The
/// measurement is done via `TextPainter` so the decision
/// survives font-loading changes.
class _SegmentLabel extends StatelessWidget {
  final StripSegment seg;
  final double fraction;
  final Color textColor;

  const _SegmentLabel({
    required this.seg,
    required this.fraction,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (fraction * 100).round();
    final fullText = '${seg.label} $pct%';
    final contrastShadow = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.55),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // Hide when there is no room at all (S-053 base case).
        if (maxWidth < 12) return const SizedBox.shrink();

        final painter = TextPainter(
          text: TextSpan(
            text: fullText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: contrastShadow,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

        // Padding on each side: 2 px so the label is not
        // glued to the segment edge. The 2-px allowance is
        // deliberately tight: D-8's full-strip height
        // (64 px) is the structural guard against the v1
        // thin-segment failure case (S-050b), so the
        // label-fit budget should be as generous as
        // possible.
        final fits = painter.width + 2 <= maxWidth;
        if (!fits) return const SizedBox.shrink();

        return Center(
          child: Text(
            fullText,
            key: ValueKey('nutrition_strip_seg_text_${seg.label}_$pct'),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: contrastShadow,
            ),
          ),
        );
      },
    );
  }
}

/// Renders the segmented fill on top of the track. The track
/// is the full strip surface (a flat divider-color rectangle);
/// the fill is a `CustomPaint` whose path is a chevron whose
/// interior segment boundaries are straight vertical lines
/// (D-8).
class _SegmentedBar extends StatelessWidget {
  final List<StripSegment> segments;
  final Color trackColor;
  final int consumedCalories;
  final int targetCalories;
  final double availableWidth;

  const _SegmentedBar({
    required this.segments,
    required this.trackColor,
    required this.consumedCalories,
    required this.targetCalories,
    required this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    // S-052: fill caps at 100% width; the label row shows the
    // true values separately.
    final fraction = (targetCalories <= 0)
        ? 0.0
        : (consumedCalories / targetCalories).clamp(0.0, 1.0).toDouble();
    final totalKcal = segments.fold<int>(0, (s, seg) => s + seg.kcal);

    final fillWidth = availableWidth * fraction;

    return SizedBox(
      key: const Key('nutrition_strip_bar'),
      width: availableWidth,
      height: NutritionStripBarMetrics.contentHeight,
      child: CustomPaint(
        painter: _SegmentedFillPainter(
          segments: segments,
          fillWidth: fillWidth,
          totalKcal: totalKcal,
        ),
      ),
    );
  }
}

/// The fill painter. Draws the three segments side by side
/// with straight interior vertical boundaries; the trailing
/// segment's right edge is a chevron arrow-shape (D-8). The
/// fill is painted within a `clipRect` so the chevron does
/// not bleed past `fillWidth`.
class _SegmentedFillPainter extends CustomPainter {
  final List<StripSegment> segments;
  final double fillWidth;
  final int totalKcal;

  _SegmentedFillPainter({
    required this.segments,
    required this.fillWidth,
    required this.totalKcal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fillWidth <= 0 || totalKcal <= 0) return;
    final height = size.height;
    // The chevron depth is a fraction of the strip height so
    // the silhouette reads as an arrow, not a notch.
    const chevronDepth = 0.35; // 35% of strip height per arm
    final midY = height / 2;
    final arm = height * chevronDepth;
    final yTop = midY - arm;
    final yBottom = midY + arm;

    // Per-segment widths in pixels. The LAST segment absorbs
    // any rounding drift so the segments add up to exactly
    // `fillWidth`.
    final widths = <double>[];
    var cum = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLast = i == segments.length - 1;
      final segFrac = totalKcal == 0 ? 0.0 : seg.kcal / totalKcal;
      final w = isLast
          ? (fillWidth - cum).clamp(0.0, fillWidth - cum)
          : fillWidth * segFrac;
      widths.add(w);
      cum += w;
    }

    // Bound the fill at `fillWidth` so the chevron does not
    // bleed past the consumed target.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, fillWidth, height));

    // Paint all but the last segment as simple rects.
    cum = 0;
    for (var i = 0; i < segments.length - 1; i++) {
      final w = widths[i];
      final rect = Rect.fromLTWH(cum, 0, w, height);
      canvas.drawRect(rect, Paint()..color = segments[i].color);
      cum += w;
    }
    // Paint the last segment using the chevron path so the
    // trailing edge reads as an arrow. The chevron tip
    // extends `arm * 0.5` past `cum + widths[last]`, which
    // is then clipped by the `clipRect` above.
    final lastIdx = segments.length - 1;
    final lastW = widths[lastIdx];
    final lastPath = Path();
    lastPath.moveTo(cum, 0);
    lastPath.lineTo(cum + lastW, 0);
    lastPath.lineTo(cum + lastW, yTop);
    lastPath.lineTo(cum + lastW + arm * 0.5, midY);
    lastPath.lineTo(cum + lastW, yBottom);
    lastPath.lineTo(cum + lastW, height.toDouble());
    lastPath.lineTo(cum, height.toDouble());
    lastPath.close();
    canvas.drawPath(lastPath, Paint()..color = segments[lastIdx].color);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SegmentedFillPainter old) {
    return old.fillWidth != fillWidth ||
        old.totalKcal != totalKcal ||
        old.segments != segments;
  }
}

/// Design tokens for the strip. The content height is the
/// strip's full painted height (track + fill + label overlay);
/// the home screen extends the strip background to the
/// physical bottom edge via the `Material` / `Ink` decoration
/// (S-056) without bumping the `contentHeight` itself.
class NutritionStripBarMetrics {
  /// Full-strip content height per D-8. The default is
  /// tunable but starts at 64 px (the design-system tuning
  /// mechanic in D-8). All in-strip measurements (label fit,
  /// chevron depth) derive from this constant.
  static const double contentHeight = 64.0;

  /// Reserve this much of the trailing segment's right edge
  /// for the chevron arrow tip so the in-segment label does
  /// not collide with the arrow's right shoulder.
  static const double chevronReserve = 12.0;
}
