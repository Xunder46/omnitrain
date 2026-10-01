import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Horizontal shift (in dp) applied to the first and last
/// x-axis date labels on a scrollable `LineChart`. fl_chart
/// centers each `SideTitleWidget` on the data point, so the
/// leftmost label would otherwise sit on top of the pinned
/// y-axis label and the rightmost label would extend past
/// the right card border.
const double kEdgeLabelHorizontalShift = 22.0;

/// Renders a bottom-axis date label with horizontal inset on the
/// first and last positions so the text doesn't overlap the
/// pinned y-axis column on the left or overflow the card on
/// the right. Used by the stats screen charts and the profile
/// measurement history sheet so both surfaces speak the same
/// visual language.
///
/// Style is intentionally left to the caller — the `style`
/// argument drives the `Text`'s appearance. Both call sites
/// pass `theme.textTheme.labelSmall` (9 px) with the active
/// theme's muted text color so the labels read as secondary
/// chrome against the chart line.
///
/// Top-level function on purpose: the Dart analyzer doesn't
/// trace references inside inline `getTitlesWidget:` closures
/// passed to fl_chart, so a private method on the host state
/// class gets flagged as "unused element" and then fails to
/// resolve at every call site, breaking the build. A
/// library-scope function is unambiguously reachable.
Widget buildEdgeAwareDateLabel({
  required dynamic meta,
  required String text,
  required TextStyle style,
  required bool isFirst,
  required bool isLast,
}) {
  final shift = isFirst
      ? const Offset(kEdgeLabelHorizontalShift, 0)
      : isLast
      ? const Offset(-kEdgeLabelHorizontalShift, 0)
      : Offset.zero;
  return SideTitleWidget(
    meta: meta,
    space: 8,
    child: Transform.translate(
      offset: shift,
      child: Text(text, style: style),
    ),
  );
}
