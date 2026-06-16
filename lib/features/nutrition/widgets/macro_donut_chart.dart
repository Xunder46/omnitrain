// filepath: lib/features/nutrition/widgets/macro_donut_chart.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// A donut chart that surrounds the calorie ring on the daily
/// nutrition screen. Renders up to four colored arc sections —
/// **Net Carbs**, **Fiber**, **Fat**, **Protein** — in fixed
/// order. The donut is **interactive**: tapping a section focuses
/// it. Focus state is owned by the widget and surfaced via
/// [onSectionFocusChange]; per-section opacities are controlled by
/// the parent via [sectionOpacities].
///
/// When the total of all four macros is 0, the chart renders an
/// empty `SizedBox` of the requested size so the parent can fall
/// back to the calorie ring alone.
///
/// The widget is **pure presentation**:
///   - No repository access. State is read by the parent and passed
///     in as primitives.
///   - No business logic — section angles, hit-test, and the
///     focus-content widget are all pure / testable without a
///     widget tree.
///   - All colors come from [OmniTheme.colors.macroChart] and
///     [OmniTheme.colors.textDominant]. No hardcoded values.
///
/// See `.github/agents/plans/daily-nutrition-macro-chart-plan.md`
/// for the full spec (scenarios S-001..S-014).
class MacroDonutChart extends StatefulWidget {
  /// Consumed protein grams today. Negative values are clamped to 0.
  final int protein;

  /// Consumed net carbs (carbs − fiber) grams today. The parent
  /// computes this from `NutritionState`; the chart does not derive
  /// it itself. Negative values are clamped to 0.
  final int netCarbs;

  /// Consumed fiber grams today. Negative values are clamped to 0.
  final int fiber;

  /// Consumed fat grams today. Negative values are clamped to 0.
  final int fat;

  /// Outer diameter of the donut in logical pixels. The donut's
  /// band fills this size; the calorie ring (rendered separately
  /// on top) should be sized to fit inside the band's inner edge.
  /// Default 240.
  final double size;

  /// Thickness of the donut band. Default 36 — substantially thicker
  /// than the calorie ring's 14 px stroke so the donut reads as a
  /// wide ring around the calorie ring.
  final double strokeWidth;

  /// Angular gap between adjacent sections, in degrees. Default 1.5.
  final double gapDegrees;

  /// Per-section opacity values applied in the same order as the
  /// section list returned by [computeMacroSections].
  /// `sectionOpacities[i]` is the opacity of the `i`-th non-zero
  /// section. When `null` (the default), every section renders at
  /// 1.0 — the parent is responsible for passing 0.4 for unfocused
  /// sections when a focus is active.
  final List<double>? sectionOpacities;

  /// Fired when the user taps inside the donut and the focus
  /// changes. Receives the new focused section index, or `null`
  /// when the focus is cleared (tap on the same section, or tap on
  /// the empty center). Not fired when the focus is unchanged.
  final ValueChanged<int?>? onSectionFocusChange;

  const MacroDonutChart({
    super.key,
    required this.protein,
    required this.netCarbs,
    required this.fiber,
    required this.fat,
    this.size = 300,
    this.strokeWidth = 40,
    this.gapDegrees = 0.5,
    this.sectionOpacities,
    this.onSectionFocusChange,
  });

  @override
  State<MacroDonutChart> createState() => _MacroDonutChartState();
}

class _MacroDonutChartState extends State<MacroDonutChart> {
  /// Index of the focused section in the chart's section list, or
  /// `null` for the default (no focus) state.
  int? _focusedSectionIndex;

  @override
  Widget build(BuildContext context) {
    final sections = computeMacroSections(
      protein: widget.protein,
      netCarbs: widget.netCarbs,
      fiber: widget.fiber,
      fat: widget.fat,
      gapDegrees: widget.gapDegrees,
    );

    if (sections.isEmpty) {
      return SizedBox(width: widget.size, height: widget.size);
    }

    // The band is a stroked annulus at mid-line radius
    // `(size - strokeWidth) / 2`. The band's inner edge is at
    // `midLine - strokeWidth/2` and the outer edge at
    // `midLine + strokeWidth/2`.
    final bandMidRadius = (widget.size - widget.strokeWidth) / 2;
    final bandInnerRadius = bandMidRadius - widget.strokeWidth / 2;
    final bandOuterRadius = bandMidRadius + widget.strokeWidth / 2;

    final opacities = widget.sectionOpacities ??
        List<double>.filled(sections.length, 1.0);

    // In-band label styling. The painter has no `BuildContext`,
    // so the widget reads the theme once and forwards the
    // resolved text style + light/dark label colors.
    final theme = Theme.of(context);
    final labelTextStyle = theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
    final themeColors = OmniTheme.colors;
    final lightLabelColor = themeColors.textDominant;
    final darkLabelColor = themeColors.macroChart.chartLabelDark;

    return Semantics(
      container: true,
      label: _semanticLabel(sections, _focusedSectionIndex),
      child: SizedBox(
        key: const Key('macro_donut_chart'),
        width: widget.size,
        height: widget.size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTap(
            details.localPosition,
            sections,
            bandInnerRadius,
            bandOuterRadius,
          ),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _MacroDonutPainter(
              sections: sections,
              strokeWidth: widget.strokeWidth,
              opacities: opacities,
              labelTextStyle: labelTextStyle,
              lightLabelColor: lightLabelColor,
              darkLabelColor: darkLabelColor,
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(
    Offset localPosition,
    List<MacroSection> sections,
    double bandInnerRadius,
    double bandOuterRadius,
  ) {
    final hit = resolveSectionHit(
      sections: sections,
      localPosition: localPosition,
      chartSize: Size(widget.size, widget.size),
      bandInnerRadius: bandInnerRadius,
      bandOuterRadius: bandOuterRadius,
    );
    if (hit == null) return; // outside the chart — no-op
    if (hit == resolveSectionHitCenterSentinel) {
      if (_focusedSectionIndex != null) {
        setState(() => _focusedSectionIndex = null);
        widget.onSectionFocusChange?.call(null);
      }
      return;
    }
    final tapped = hit;
    if (_focusedSectionIndex == tapped) {
      setState(() => _focusedSectionIndex = null);
      widget.onSectionFocusChange?.call(null);
    } else {
      setState(() => _focusedSectionIndex = tapped);
      widget.onSectionFocusChange?.call(tapped);
    }
  }

  String _semanticLabel(List<MacroSection> sections, int? focused) {
    if (focused == null) {
      return 'Macro distribution. Tap a section for details.';
    }
    final s = sections[focused];
    final total = sections.fold<int>(0, (sum, x) => sum + x.grams);
    final pct = total == 0 ? 0 : (s.grams * 100 / total).round();
    return '${s.name} focused, ${s.grams} grams, $pct percent. '
        'Tap again or tap the center to clear.';
  }
}

// ─── Hit-test pure function ─────────────────────────────────────────────────

/// Sentinel returned by [resolveSectionHit] when the tap landed in
/// the donut's empty center (i.e. inside the inner edge of the
/// band — where the calorie ring lives). The chart's gesture
/// handler converts this to a deselect action.
const int resolveSectionHitCenterSentinel = -1;

/// Resolves a local-position tap inside the macro donut to:
///   - the **index** of the section whose `[start, start+sweep]`
///     arc contains the tap (when the tap is inside the band), or
///   - [resolveSectionHitCenterSentinel] (when the tap is inside
///     the band's inner edge — i.e. the empty middle), or
///   - `null` (when the tap is outside the chart entirely).
///
/// Inputs are in the chart's local coordinates (origin at the
/// chart's top-left).
///
/// **Angle convention.** `Canvas.drawArc` measures angles from
/// the +X axis (3 o'clock), CCW. `math.atan2(dy, dx)` measures
/// the same way. The macro section's `startAngleRadians` is
/// therefore in the same convention as the tap's atan2 result
/// — no offset is needed. A section whose `startAngleRadians
/// == -π/2` is drawn from 12 o'clock and sweeps clockwise; the
/// matching atan2 angle for a tap at 12 o'clock is also `-π/2`.
///
/// Pure / no widget tree — fully unit-testable.
int? resolveSectionHit({
  required List<MacroSection> sections,
  required Offset localPosition,
  required Size chartSize,
  required double bandInnerRadius,
  required double bandOuterRadius,
}) {
  final center = Offset(chartSize.width / 2, chartSize.height / 2);
  final dx = localPosition.dx - center.dx;
  final dy = localPosition.dy - center.dy;
  final r = math.sqrt(dx * dx + dy * dy);

  if (r < bandInnerRadius) return resolveSectionHitCenterSentinel;
  if (r > bandOuterRadius) return null;

  // atan2(dy, dx) is the angle in the painter's convention
  // (CCW from +X). It directly matches a section's
  // `startAngleRadians` (also CCW from +X).
  final painterAngle = math.atan2(dy, dx);

  for (var i = 0; i < sections.length; i++) {
    final s = sections[i];
    // We use a half-open interval `[start, end)` for each
    // section's range. This is the natural fit for the
    // painter's `drawArc`, which draws the arc from `start`
    // through `start + sweep` — a tap at exactly `start +
    // sweep` is at the *end* of the previous section's drawn
    // arc and the *start* of the next section's drawn arc.
    // Claiming the boundary for the next section (rather than
    // the previous) makes the iteration order the source of
    // truth: a tap on a boundary is owned by the section whose
    // `[start, end)` contains it.
    //
    // For the rare case where a section wraps across the 0
    // angle (e.g. when only one macro is non-zero and its
    // sweep spans most of the circle), the range is split:
    // `[start, π] ∪ [-π, end]`.
    var start = s.startAngleRadians;
    final end = start + s.sweepAngleRadians;
    if (start >= -math.pi && end > math.pi) {
      // Wraps past π. Split into [start, π] and [-π, end - 2π].
      if (painterAngle >= start || painterAngle < end - 2 * math.pi) {
        return i;
      }
    } else if (start < -math.pi) {
      // Normalize start up to (-π, π].
      start += 2 * math.pi;
      final normalizedEnd = end + 2 * math.pi;
      if (painterAngle >= start && painterAngle < normalizedEnd) return i;
    } else {
      // No wrap. painterAngle is in (-π, π]; start and end
      // are both in (-π, π] (or end == π is the boundary).
      if (painterAngle >= start && painterAngle < end) return i;
    }
  }
  return null;
}

// ─── Pure section computation ───────────────────────────────────────────────

/// One slice of the macro donut. Computed by [computeMacroSections]
/// from the four input grams. `startAngleRadians` and
/// `midAngleRadians` are in the **`drawArc` / `atan2` convention**
/// (CCW from the +X axis, i.e. 3 o'clock). A `startAngleRadians
/// == -π/2` is drawn from 12 o'clock and sweeps clockwise when
/// the sweep is positive. The hit-test uses the same convention
/// — no offset — so the geometric relationship between the
/// section ranges and the tap's atan2 angle is direct.
class MacroSection {
  /// Section name as it appears on the focus content (in the
  /// calorie ring's center, when this section is focused).
  final String name;

  /// Section weight in grams. Non-zero for every section in the
  /// returned list.
  final int grams;

  /// Color slot from `OmniTheme.colors.macroChart`.
  final Color color;

  /// Start angle in radians, in the `drawArc` / `atan2`
  /// convention (CCW from the +X axis, i.e. 3 o'clock).
  final double startAngleRadians;

  /// Sweep angle in radians (positive, drawn clockwise by
  /// `drawArc` because Y is down). Always `<= 2π`.
  final double sweepAngleRadians;

  /// Mid angle in radians (used by the painter and hit-test).
  final double midAngleRadians;

  const MacroSection({
    required this.name,
    required this.grams,
    required this.color,
    required this.startAngleRadians,
    required this.sweepAngleRadians,
    required this.midAngleRadians,
  });
}

/// Compute the list of non-zero macro sections, in the fixed visual
/// order **Net Carbs → Fiber → Fat → Protein**, with proportional
/// sweep angles and a uniform angular gap between sections.
///
/// Inputs are clamped to 0 (negative grams are treated as 0).
/// Returns an empty list when the total of all four macros is 0.
List<MacroSection> computeMacroSections({
  required int protein,
  required int netCarbs,
  required int fiber,
  required int fat,
  required double gapDegrees,
}) {
  final palette = OmniTheme.colors.macroChart;
  final gapRad = gapDegrees * math.pi / 180.0;

  final raw = <_RawSection>[
    _RawSection('Net Carbs', math.max(0, netCarbs), palette.netCarbs),
    _RawSection('Fiber', math.max(0, fiber), palette.fiber),
    _RawSection('Fat', math.max(0, fat), palette.fat),
    _RawSection('Protein', math.max(0, protein), palette.protein),
  ];
  final nonzero = raw.where((r) => r.grams > 0).toList();
  if (nonzero.isEmpty) return const [];

  final total = nonzero.fold<int>(0, (s, r) => s + r.grams);
  final totalGap = gapRad * nonzero.length;
  final available = 2 * math.pi - totalGap;

  final sweeps = <double>[];
  for (final r in nonzero) {
    final sweep = available * (r.grams / total);
    sweeps.add(sweep);
  }

  final result = <MacroSection>[];
  // Place the first section's leading edge at 12 o'clock + gap/2
  // (the half-gap offsets the section into the donut so the seam
  // is centered at 12 o'clock rather than the section's own
  // leading edge sitting on 12 o'clock). Each subsequent
  // section's leading edge sits `sweep + gap` later, so the gap
  // between adjacent sections is exactly `gap` radians — and the
  // wrap-around seam is also `gap` radians (no leftover
  // accumulating at 12 o'clock).
  var cursor = -math.pi / 2 + gapRad / 2;
  for (var i = 0; i < nonzero.length; i++) {
    final start = cursor;
    final sweep = sweeps[i];
    final mid = start + sweep / 2;
    result.add(
      MacroSection(
        name: nonzero[i].name,
        grams: nonzero[i].grams,
        color: nonzero[i].color,
        startAngleRadians: start,
        sweepAngleRadians: sweep,
        midAngleRadians: mid,
      ),
    );
    cursor = start + sweep + gapRad;
  }
  return result;
}

class _RawSection {
  final String name;
  final int grams;
  final Color color;
  const _RawSection(this.name, this.grams, this.color);
}

// ─── In-band label decision ──────────────────────────────────────────────────

/// One in-band label decision for a single [MacroSection]. The
/// painter uses [text] and [position] to render the label; when
/// [text] is `null`, the section is too narrow to fit a label and
/// the painter skips it (S-017).
///
/// Initials map (documented design choice — unambiguous against
/// the fixed visual order Net Carbs → Fiber → Fat → Protein):
///
///   - **N**  — Net Carbs
///   - **Fb** — Fiber (disambiguated from Fat's single-letter F)
///   - **F**  — Fat
///   - **P**  — Protein
class MacroLabel {
  /// Section this label belongs to. Used by the painter to look
  /// up the section's color for the luminance-based label-color
  /// pick.
  final String sectionName;

  /// The label text in `"<initial> <N>g"` form (e.g. `"N 22g"`).
  /// `null` when the section is too narrow to fit the label
  /// (S-017) — the painter skips rendering in that case.
  final String? text;

  /// Position of the label's center in chart-local coordinates
  /// (origin at the chart's top-left). The painter draws the
  /// text centered on this point. `null` when [text] is `null`.
  final Offset? position;

  const MacroLabel({
    required this.sectionName,
    this.text,
    this.position,
  });
}

/// Compute the in-band label for every section. Pure / no widget
/// tree — the painter supplies a `labelWidthOf` function that
/// returns the painted width of a given text (typically
/// `TextPainter..layout().width` in the painter, a stub in tests).
///
/// For each section:
///   - If `labelWidthOf(text) > sweep · midRadius − 8`, the label
///     is hidden (text and position are both `null`) — there is
///     not enough arc length to fit the text with the 8 px
///     breathing pad (S-017, mirrors the S-053 narrow-label
///     pattern used elsewhere in the app).
///   - Otherwise, the label is rendered at
///     `(cx + midR·cos(midAngle), cy + midR·sin(midAngle))` —
///     the band's mid-radius at the section's mid-angle, in the
///     painter's CCW-from-`+X` convention. The text is drawn
///     upright (no rotation) so it remains readable at every
///     angle.
List<MacroLabel> computeMacroLabels({
  required List<MacroSection> sections,
  required Size chartSize,
  required double strokeWidth,
  required double Function(String text) labelWidthOf,
}) {
  final midR = (chartSize.width - strokeWidth) / 2;
  const padding = 8.0;
  final cx = chartSize.width / 2;
  final cy = chartSize.height / 2;
  final result = <MacroLabel>[];
  for (final s in sections) {
    final text = _macroLabelText(s);
    final arcLength = s.sweepAngleRadians * midR;
    final width = labelWidthOf(text);
    if (width > arcLength - padding) {
      result.add(MacroLabel(sectionName: s.name));
      continue;
    }
    final pos = Offset(
      cx + midR * math.cos(s.midAngleRadians),
      cy + midR * math.sin(s.midAngleRadians),
    );
    result.add(MacroLabel(
      sectionName: s.name,
      text: text,
      position: pos,
    ));
  }
  return result;
}

/// `"<initial> <N>g"` formatter for an in-band label. See
/// [MacroLabel] for the initial mapping.
String _macroLabelText(MacroSection s) {
  final initial = switch (s.name) {
    'Net Carbs' => 'N',
    'Fiber' => 'Fb',
    'Fat' => 'F',
    'Protein' => 'P',
    _ => '?',
  };
  return '$initial${s.grams}g';
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _MacroDonutPainter extends CustomPainter {
  final List<MacroSection> sections;
  final double strokeWidth;
  final List<double> opacities;

  /// Text style used for in-band labels. The widget supplies a
  /// style derived from the active theme; the painter does not
  /// read `Theme.of(context)` itself (it has no `BuildContext`).
  final TextStyle labelTextStyle;

  /// Light text color used for in-band labels on **dark** section
  /// backgrounds. Typically the theme's `textDominant` token.
  final Color lightLabelColor;

  /// Dark text color used for in-band labels on **light** section
  /// backgrounds. Typically the theme's `macroChart.chartLabelDark`
  /// token.
  final Color darkLabelColor;

  const _MacroDonutPainter({
    required this.sections,
    required this.strokeWidth,
    required this.opacities,
    required this.labelTextStyle,
    required this.lightLabelColor,
    required this.darkLabelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // Pre-compute the label decision once; the painter iterates
    // both lists in parallel (same length, same order).
    final labels = computeMacroLabels(
      sections: sections,
      chartSize: size,
      strokeWidth: strokeWidth,
      labelWidthOf: (text) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: labelTextStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        return tp.width;
      },
    );

    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final opacity = i < opacities.length ? opacities[i] : 1.0;
      // Skip fully-transparent sections to keep the donut quiet
      // when one macro is focused.
      if (opacity <= 0.0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = s.color.withValues(alpha: opacity);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        s.startAngleRadians,
        s.sweepAngleRadians,
        false,
        paint,
      );

      // In-band label: skip when the section is too narrow (the
      // helper returns text == null in that case). The label's
      // alpha inherits the section's focus opacity (S-018) and
      // its color is picked from the section's luminance —
      // light sections get `darkLabelColor`, dark sections get
      // `lightLabelColor` (S-016).
      final label = labels[i];
      final labelText = label.text;
      final labelPos = label.position;
      if (labelText == null || labelPos == null) continue;
      final labelColor = ThemeData.estimateBrightnessForColor(s.color) ==
              Brightness.light
          ? darkLabelColor
          : lightLabelColor;
      final labelPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: labelTextStyle.copyWith(
            color: labelColor.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      // The label is centered on the section's mid-radius at the
      // mid-angle. `TextPainter.paint` takes the top-left of the
      // text, so offset by half the painted size to center.
      labelPainter.paint(
        canvas,
        labelPos - Offset(labelPainter.width / 2, labelPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_MacroDonutPainter old) =>
      old.sections != sections ||
      old.strokeWidth != strokeWidth ||
      !_listEquals(old.opacities, opacities) ||
      old.labelTextStyle != labelTextStyle ||
      old.lightLabelColor != lightLabelColor ||
      old.darkLabelColor != darkLabelColor;

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── Focus content (rendered inside the calorie ring center) ───────────────

/// Widget rendered in the calorie ring's center when a macro
/// section is focused. Shows the macro name on line 1 (with a
/// small accent dot in the macro's color) and `"<N>g · <P>%"` on
/// line 2.
///
/// Used as the `centerOverride` argument on
/// `CalorieRing`.
class MacroFocusContent extends StatelessWidget {
  /// Section name (e.g. `"Protein"`).
  final String name;

  /// Section weight in grams.
  final int grams;

  /// Section's share of today's consumed calories, 0..100. For
  /// `informational` sections (fiber), pass 0 — the widget renders
  final int percentOfCalories;

  /// Color used as a small accent dot next to the name, so the
  /// focused macro's color is visible in the center. Comes from
  /// `OmniTheme.colors.macroChart.<slot>`.
  final Color color;

  /// `true` for sections that do not contribute to total calories
  /// (currently just fiber). When `true`, the widget renders the
  /// informational qualifier instead of a "%" string.
  final bool informational;

  const MacroFocusContent({
    super.key,
    required this.name,
    required this.grams,
    required this.percentOfCalories,
    required this.color,
    this.informational = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colors;
    final theme = Theme.of(context);
    // Sized to fit inside the 160 px calorie ring with its
    // 8 px horizontal padding (144 px usable width). The
    // biggest macro name is "Net Carbs" (~80 px at titleSmall
    // bold); "Protein" / "Fat" / "Fiber" are shorter. The
    // second line can stretch longer; "30 g · 25%"
    // (~22 chars) still fits comfortably at labelSmall.
    final nameStyle = theme.textTheme.titleSmall?.copyWith(
          color: themeColors.textDominant,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle();
    final detailStyle = theme.textTheme.labelSmall?.copyWith(
          color: themeColors.textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle();

    final detail = informational
        ? '$grams g'
        : '$grams g · $percentOfCalories%';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(name, style: nameStyle),
          ],
        ),
        const SizedBox(height: 2),
        Text(detail, style: detailStyle),
      ],
    );
  }
}
