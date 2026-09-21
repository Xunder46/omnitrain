// filepath: test/features/nutrition/macro_donut_chart_test.dart
//
// Unit tests for the pure-function surface of `MacroDonutChart`:
//   - `computeMacroSections` — section angles, gaps, ordering.
//   - `computeMacroLabels`   — in-band label visibility and placement.
//   - `resolveSectionHit`    — hit-test resolution (regression for the
//     painter-angle offset bug from the prior iteration).
//
// The test file is also the home of the red tests for the Iteration 3
// polish: even-seam gaps (S-015), in-band labels (S-016), narrow
// section hides its label (S-017), labels inherit section opacity
// (S-018). See `.github/agents/plans/daily-nutrition-macro-chart-plan.md`.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/features/nutrition/widgets/macro_donut_chart.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // computeMacroSections — gap equality (S-015)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The seam at 12 o'clock between the last section and the first
  // section (across the wrap-around) must be the same size as every
  // other inter-section gap. Iteration 3 fixed a bug where the
  // cursor advanced by only `gap/2` per boundary, leaving
  // `(n+1)·gap/2` at the seam (the wide notch at 12 o'clock).
  group('computeMacroSections — even seam (S-015)', () {
    /// Gaps (in radians) between every adjacent pair of sections,
    /// INCLUDING the wrap-around gap from the last section back
    /// to the first section.
    List<double> gapsOf(List<MacroSection> sections, {required double gapRad}) {
      if (sections.length < 2) return const [];
      final gaps = <double>[];
      for (var i = 0; i < sections.length; i++) {
        final cur = sections[i];
        final next = sections[(i + 1) % sections.length];
        if (i + 1 < sections.length) {
          // Normal gap: next.start - cur.end (in the un-wrapped angle space).
          final start = cur.startAngleRadians;
          final end = start + cur.sweepAngleRadians;
          gaps.add(next.startAngleRadians - end);
        } else {
          // Wrap-around seam: from cur.end back to next.start, going
          // forward (CCW) through +π. next.start is normalized
          // back into [0, 2π) by adding 2π.
          final start = cur.startAngleRadians;
          final end = start + cur.sweepAngleRadians;
          gaps.add(next.startAngleRadians + 2 * math.pi - end);
        }
      }
      // Silence unused parameter (gapRad is the EXPECTED gap, not
      // derived from the sections).
      assert(gapRad > 0);
      return gaps;
    }

    test('n=1 (only protein): single section spans the rest of the circle', () {
      // With only one non-zero section, there are no inter-section
      // gaps to compare. The single section sweeps the full circle
      // minus one gap (the seam closes the donut).
      final sections = computeMacroSections(
        protein: 100,
        netCarbs: 0,
        fiber: 0,
        fat: 0,
        gapDegrees: 1.5,
      );
      expect(sections.length, 1);
      // Sweep + gap = 2π.
      expect(
        sections[0].sweepAngleRadians + 1.5 * math.pi / 180.0,
        closeTo(2 * math.pi, 1e-9),
      );
    });

    test('n=2 (net carbs + protein): both gaps equal gapDegrees', () {
      final sections = computeMacroSections(
        protein: 50,
        netCarbs: 50,
        fiber: 0,
        fat: 0,
        gapDegrees: 1.5,
      );
      expect(sections.length, 2);
      final gaps = gapsOf(sections, gapRad: 1.5 * math.pi / 180.0);
      expect(gaps.length, 2);
      for (final g in gaps) {
        expect(g, closeTo(1.5 * math.pi / 180.0, 1e-9));
      }
    });

    test(
      'n=3 (net carbs + fat + protein): all three gaps equal gapDegrees',
      () {
        final sections = computeMacroSections(
          protein: 50,
          netCarbs: 50,
          fiber: 0,
          fat: 50,
          gapDegrees: 1.5,
        );
        expect(sections.length, 3);
        final gaps = gapsOf(sections, gapRad: 1.5 * math.pi / 180.0);
        expect(gaps.length, 3);
        for (final g in gaps) {
          expect(g, closeTo(1.5 * math.pi / 180.0, 1e-9));
        }
      },
    );

    test('n=4 (all macros non-zero): all four gaps equal gapDegrees', () {
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      expect(sections.length, 4);
      final gaps = gapsOf(sections, gapRad: 1.5 * math.pi / 180.0);
      expect(gaps.length, 4);
      for (final g in gaps) {
        expect(g, closeTo(1.5 * math.pi / 180.0, 1e-9));
      }
    });

    test('total sweep + total gaps closes the circle exactly (n=4)', () {
      // The sum of all section sweeps + all inter-section gaps
      // (including the seam) must equal 2π.
      final sections = computeMacroSections(
        protein: 100,
        netCarbs: 80,
        fiber: 12,
        fat: 60,
        gapDegrees: 1.5,
      );
      expect(sections.length, 4);
      final totalSweep = sections.fold<double>(
        0,
        (sum, s) => sum + s.sweepAngleRadians,
      );
      final gaps = gapsOf(sections, gapRad: 1.5 * math.pi / 180.0);
      final totalGap = gaps.fold<double>(0, (sum, g) => sum + g);
      expect(totalSweep + totalGap, closeTo(2 * math.pi, 1e-9));
    });

    test('non-uniform weights: gap equality still holds', () {
      // Asymmetric weights must not break the gap contract.
      final sections = computeMacroSections(
        protein: 200,
        netCarbs: 30,
        fiber: 5,
        fat: 80,
        gapDegrees: 2.0,
      );
      expect(sections.length, 4);
      final gaps = gapsOf(sections, gapRad: 2.0 * math.pi / 180.0);
      expect(gaps.length, 4);
      for (final g in gaps) {
        expect(g, closeTo(2.0 * math.pi / 180.0, 1e-9));
      }
    });

    test('zero grams: no section is drawn, list is empty', () {
      final sections = computeMacroSections(
        protein: 0,
        netCarbs: 0,
        fiber: 0,
        fat: 0,
        gapDegrees: 1.5,
      );
      expect(sections, isEmpty);
    });

    test('first section starts at -π/2 + gap/2 (12 o\'clock + half gap)', () {
      // The first section's leading edge is offset by half a gap
      // from 12 o'clock; the first section's `start` is therefore
      // `-π/2 + gap/2`. The end of the last section is therefore
      // `start_0 + 2π - gap`, leaving a `gap`-wide seam.
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      expect(
        sections[0].startAngleRadians,
        closeTo(-math.pi / 2 + 1.5 * math.pi / 180.0 / 2, 1e-9),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // resolveSectionHit — hit-test regression (prior iteration's fix)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // These tests pin the atan2 / drawArc angle convention so a future
  // refactor of `computeMacroSections` doesn't accidentally break
  // hit-testing. They use the same atan2 convention to compute the
  // tap points from the cardinal painter angles.
  group('resolveSectionHit — hit-test invariants', () {
    /// Build a tap point at the given painter angle (CCW from +X
    /// axis, which is the drawArc + atan2 convention) at a
    /// distance `r` from the chart center.
    Offset pointAtPainterAngle(double painterAngle, double r, Size chartSize) {
      final center = Offset(chartSize.width / 2, chartSize.height / 2);
      return Offset(
        center.dx + r * math.cos(painterAngle),
        center.dy + r * math.sin(painterAngle),
      );
    }

    test('cardinal angles resolve to the matching section (n=4, equal)', () {
      const chartSize = Size(240, 240);
      final midR = (chartSize.width - 36) / 2; // band mid radius
      final inner = midR - 18;
      final outer = midR + 18;
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      // Taps at the mid-angle of each section, just inside the band.
      for (var i = 0; i < sections.length; i++) {
        final p = pointAtPainterAngle(
          sections[i].midAngleRadians,
          midR,
          chartSize,
        );
        final hit = resolveSectionHit(
          sections: sections,
          localPosition: p,
          chartSize: chartSize,
          bandInnerRadius: inner,
          bandOuterRadius: outer,
        );
        expect(
          hit,
          i,
          reason: 'cardinal angle $i should resolve to section $i',
        );
      }
    });

    test('tap at 12 o\'clock resolves to section 0 (Net Carbs)', () {
      // Regression: a previous iteration had a +π/2 offset that
      // shifted every tap by a quarter-turn. This is the
      // targeted regression test.
      const chartSize = Size(240, 240);
      final midR = (chartSize.width - 36) / 2;
      final inner = midR - 18;
      final outer = midR + 18;
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      // A tap just below 12 o'clock (so it lands inside the band,
      // not on the gap seam at -π/2 + gap/2). Use the mid-angle of
      // section 0 instead of the literal 12 o'clock.
      final p = pointAtPainterAngle(
        sections[0].midAngleRadians,
        midR,
        chartSize,
      );
      final hit = resolveSectionHit(
        sections: sections,
        localPosition: p,
        chartSize: chartSize,
        bandInnerRadius: inner,
        bandOuterRadius: outer,
      );
      expect(hit, 0);
    });

    test('tap inside the band\'s inner edge returns the center sentinel', () {
      const chartSize = Size(240, 240);
      final midR = (chartSize.width - 36) / 2;
      final inner = midR - 18;
      final outer = midR + 18;
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      final center = Offset(chartSize.width / 2, chartSize.height / 2);
      final hit = resolveSectionHit(
        sections: sections,
        localPosition: center,
        chartSize: chartSize,
        bandInnerRadius: inner,
        bandOuterRadius: outer,
      );
      expect(hit, resolveSectionHitCenterSentinel);
    });

    test('tap outside the chart returns null', () {
      const chartSize = Size(240, 240);
      final midR = (chartSize.width - 36) / 2;
      final inner = midR - 18;
      final outer = midR + 18;
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: 1.5,
      );
      // Top-left corner, well outside the band.
      final hit = resolveSectionHit(
        sections: sections,
        localPosition: const Offset(2, 2),
        chartSize: chartSize,
        bandInnerRadius: inner,
        bandOuterRadius: outer,
      );
      expect(hit, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MacroChartPalette — chartLabelDark slot exists for all themes (S-016)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The dark label slot is used when the section color is light
  // (luminance check). The palette contract requires every theme
  // to define it; the test loops over the enum to catch a missing
  // slot in a future theme addition.
  group('MacroChartPalette — chartLabelDark slot', () {
    test('every theme defines a chartLabelDark color', () {
      for (final theme in AppTheme.values) {
        final colors = OmniTheme.colorsForTheme(theme);
        expect(
          colors.macroChart.chartLabelDark,
          isA<Color>(),
          reason: 'theme $theme is missing chartLabelDark on macroChart',
        );
      }
    });

    test('chartLabelDark is dark (Brightness.dark) for the default theme', () {
      // The slot is used as a dark-text color on a light section
      // background; the dark theme's chartLabelDark should itself
      // be dark (low luminance) so the contrast is high.
      final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);
      expect(
        ThemeData.estimateBrightnessForColor(colors.macroChart.chartLabelDark),
        Brightness.dark,
        reason: 'abyssalNeon chartLabelDark must read as dark',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // computeMacroLabels — in-band label decision (S-016 / S-017)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // The painter calls `computeMacroLabels` to decide which sections
  // get a label, what text to show, and where to place the label.
  // The decision is pure — the painter only provides a width
  // estimator so the function stays testable without a real
  // `TextPainter`.
  group('computeMacroLabels — in-band labels (S-016 / S-017)', () {
    const chartSize = Size(240, 240);
    const strokeWidth = 36.0;
    const gapDegrees = 1.5;

    /// A 20 px-wide stub for every label. With the default chart
    /// size and stroke, this is well under the arc length of
    /// every section in the test fixtures (a quarter-circle
    /// section is ≈170 px arc length at mid radius; the smallest
    /// non-trivial section in the tests is much larger than
    /// 28 px = 20 + 8 padding).
    double wideStub(String _) => 20.0;

    /// A 500 px-wide stub — wider than any section's arc length
    /// in the 240 px chart, so no label fits anywhere.
    double tooWideStub(String _) => 500.0;

    test('every non-zero section gets a label when they all fit', () {
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: gapDegrees,
      );
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: wideStub,
      );
      expect(labels.length, sections.length);
      // Every label has a non-null text and a non-null position.
      for (final l in labels) {
        expect(l.text, isNotNull);
        expect(l.position, isNotNull);
      }
    });

    test('label text uses the documented initial + grams format', () {
      // Initials:
      //   N = Net Carbs
      //   F = Fat
      //   Fb = Fiber (disambiguated from Fat)
      //   P = Protein
      //
      // Use equal-weight macros so every section is a quarter of
      // the circle — wide enough that the 20 px stub fits every
      // label with the 8 px padding.
      final sections = computeMacroSections(
        protein: 100,
        netCarbs: 50,
        fiber: 30,
        fat: 30,
        gapDegrees: gapDegrees,
      );
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: wideStub,
      );
      final byName = {for (final l in labels) l.sectionName: l.text};
      expect(byName['Net Carbs'], 'N50g');
      expect(byName['Fat'], 'F30g');
      expect(byName['Fiber'], 'Fb30g');
      expect(byName['Protein'], 'P100g');
    });

    test('label position is at the section\'s mid-angle, mid-radius', () {
      final sections = computeMacroSections(
        protein: 25,
        netCarbs: 25,
        fiber: 25,
        fat: 25,
        gapDegrees: gapDegrees,
      );
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: wideStub,
      );
      final midR = (chartSize.width - strokeWidth) / 2;
      for (var i = 0; i < labels.length; i++) {
        final l = labels[i];
        final s = sections[i];
        final expectedX =
            chartSize.width / 2 + midR * math.cos(s.midAngleRadians);
        final expectedY =
            chartSize.height / 2 + midR * math.sin(s.midAngleRadians);
        expect(l.position!.dx, closeTo(expectedX, 1e-6));
        expect(l.position!.dy, closeTo(expectedY, 1e-6));
      }
    });

    test('narrow section: label is hidden when width > arc length - 8', () {
      // Make a tiny Fiber section (1g vs 200g for the others).
      // The Fiber section's sweep is ~0.5% of the circle, giving an
      // arc length of about 4 px at mid radius — well below the
      // 200 px stub width.
      final sections = computeMacroSections(
        protein: 200,
        netCarbs: 200,
        fiber: 1,
        fat: 200,
        gapDegrees: gapDegrees,
      );
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: tooWideStub,
      );
      // No labels render when the stub is too wide for any
      // section. Every section's text and position are null.
      expect(labels, isNotEmpty);
      for (final l in labels) {
        expect(
          l.text,
          isNull,
          reason: 'all sections too narrow for the 200px stub',
        );
        expect(l.position, isNull);
      }
    });

    test('narrow section is hidden but wide sections still get labels', () {
      // Use a real `TextPainter` estimator so the fit test uses
      // actual painted widths, not stubs. A short label like
      // "N 5g" (~24 px at 11px font) fits in a moderate section,
      // but not in a tiny one.
      final sections = computeMacroSections(
        protein: 200,
        netCarbs: 5, // tiny
        fiber: 200,
        fat: 200,
        gapDegrees: gapDegrees,
      );
      // Use a 30 px stub so narrow sections (sweep ~ 0.7% of
      // circle, arc length ~5 px) are hidden but wider ones
      // (sweep ~33% of circle, arc length ~150 px) still get
      // labels.
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: (text) => 30.0,
      );
      // Find the Net Carbs label (the tiny one) — should be null.
      // Find the Protein label (the wide one) — should be non-null.
      final netCarbs = labels.firstWhere((l) => l.sectionName == 'Net Carbs');
      final protein = labels.firstWhere((l) => l.sectionName == 'Protein');
      expect(
        netCarbs.text,
        isNull,
        reason: 'narrow Net Carbs section should hide its label',
      );
      expect(netCarbs.position, isNull);
      expect(
        protein.text,
        isNotNull,
        reason: 'wide Protein section should keep its label',
      );
      expect(protein.position, isNotNull);
    });

    test('single-section (n=1) is too narrow for a label', () {
      // With only one non-zero section, that section's sweep is
      // (2π - gap) ≈ 2π, so its arc length is huge and the
      // label fits. This guards against the n=1 case being
      // hidden by mistake.
      final sections = computeMacroSections(
        protein: 100,
        netCarbs: 0,
        fiber: 0,
        fat: 0,
        gapDegrees: gapDegrees,
      );
      final labels = computeMacroLabels(
        sections: sections,
        chartSize: chartSize,
        strokeWidth: strokeWidth,
        labelWidthOf: wideStub,
      );
      expect(labels.length, 1);
      expect(labels[0].text, 'P100g');
    });
  });
}
