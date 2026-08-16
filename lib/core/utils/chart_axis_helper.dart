/// Pure-Dart helpers for fl_chart axis computation.
///
/// No Flutter imports — safe to use in plain unit tests.
library;

/// Axis bounds for a trend chart, with a nice label interval.
class ChartAxisBounds {
  final double min;
  final double max;

  /// Spacing between adjacent y-axis tick labels.
  final double interval;

  const ChartAxisBounds({
    required this.min,
    required this.max,
    required this.interval,
  });
}

class ChartAxisHelper {
  ChartAxisHelper._();

  // Shared readability defaults for short mobile charts.
  static const int kMaxYAxisTickCount = 5;
  static const double kMinYAxisLabelSpacing = 22.0;

  /// Compute padded axis bounds from a list of data values.
  ///
  /// Per D-2 (Y-axis label rounding):
  /// - Pads each side by [paddingFraction] × range.
  /// - Clamps min to 0.
  /// - Adds a floor of 1.0 to the range so flat/single-value series still
  ///   produce a visible, non-zero range.
  /// - Rounds the tick interval to a "nice" power-of-10-based step.
  /// - Rounds the minimum DOWN to the nearest multiple of the interval that's
  ///   at or below the padded minimum.
  /// - Rounds the maximum UP to the nearest multiple of the interval that's
  ///   at or above the padded maximum.
  /// - Ensures at least 2 distinct labels with visible range.
  static ChartAxisBounds computeBounds(
    List<double> values, {
    double paddingFraction = 0.15,
  }) {
    assert(values.isNotEmpty, 'computeBounds requires at least one value');

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    final paddedMin = (minVal - range * paddingFraction).clamp(
      0.0,
      double.infinity,
    );
    // The +1.0 floor prevents a zero range when all values are identical.
    final paddedMax = maxVal + range * paddingFraction + 1.0;

    // Divisor of 4.0 yields 5 evenly-spaced ticks (min, +1, +2, +3,
    // max) when the range is divisible. Combined with the
    // [kMaxYAxisTickCount] = 5 cap downstream, this gives up to 5
    // labels on the y-axis.
    final rawInterval = (paddedMax - paddedMin) / 4.0;
    final niceInterval = _niceNumber(rawInterval);

    // Round minimum DOWN to nearest multiple of interval (at or below paddedMin).
    final roundedMin = (paddedMin / niceInterval).floor() * niceInterval;

    // Round maximum UP to nearest multiple of interval (at or above paddedMax).
    final roundedMax = (paddedMax / niceInterval).ceil() * niceInterval;

    // Ensure at least 2 distinct labels with visible range.
    // If rounding collapses the range to zero, expand it.
    if (roundedMax <= roundedMin) {
      // Flat data or rounding artifact: expand to at least one interval.
      return ChartAxisBounds(
        min: roundedMin,
        max: roundedMin + niceInterval,
        interval: niceInterval,
      );
    }

    return ChartAxisBounds(
      min: roundedMin,
      max: roundedMax,
      interval: niceInterval,
    );
  }

  /// Format a y-axis label as a single-line "value unit" string.
  ///
  /// This intentionally returns plain text with a single separating space and
  /// never inserts line breaks so callers can render compact axis labels.
  static String formatYAxisValue(
    double value,
    String unit, {
    int decimals = 0,
  }) {
    return '${value.toStringAsFixed(decimals)} $unit';
  }

  /// Compute a readable y-axis interval for a given chart height.
  ///
  /// Keeps the underlying bounds unchanged while ensuring the visible number of
  /// y-axis labels stays within a spacing budget.
  static double readableIntervalForHeight(
    ChartAxisBounds bounds,
    double chartHeight, {
    double minLabelSpacing = kMinYAxisLabelSpacing,
    int maxTickCount = kMaxYAxisTickCount,
  }) {
    final range = bounds.max - bounds.min;
    if (range <= 0) return bounds.interval;

    final allowedTicks = maxYAxisTickCountForHeight(
      chartHeight,
      minLabelSpacing: minLabelSpacing,
      maxTickCount: maxTickCount,
    );
    if (allowedTicks <= 1) return bounds.interval;

    final minIntervalForBudget = range / (allowedTicks - 1);
    final budgetInterval = _niceNumber(minIntervalForBudget);
    return budgetInterval > bounds.interval ? budgetInterval : bounds.interval;
  }

  /// Maximum readable y-axis tick count for [chartHeight].
  ///
  /// Returns a value in [2, maxTickCount] for positive heights.
  static int maxYAxisTickCountForHeight(
    double chartHeight, {
    double minLabelSpacing = kMinYAxisLabelSpacing,
    int maxTickCount = kMaxYAxisTickCount,
  }) {
    if (chartHeight <= 0) return 2;
    if (minLabelSpacing <= 0) return maxTickCount;

    final bySpacing = (chartHeight / minLabelSpacing).floor() + 1;
    final capped = bySpacing < 2 ? 2 : bySpacing;
    return capped > maxTickCount ? maxTickCount : capped;
  }

  /// Format a [DateTime] as "MMM d" (e.g. "Jan 5", "Dec 31").
  static String formatDateLabel(DateTime date) {
    return '${_shortMonthName(date.month)} ${date.day}';
  }

  /// Whether index [idx] (0-based) in a series of [total] should carry a date
  /// label. Always shows the first. For series > 7 (the scrollable
  /// threshold matching [kScrollableTrendMaxVisiblePoints]) shows
  /// every 3rd index so labels stay evenly spaced, and adds the
  /// last point only when it sits ≥ 2 indices past the nearest
  /// multiple-of-3 (so adjacent dates like "Jun 25" / "Jun 26"
  /// never collide). The visible viewport (always the last 8
  /// points when the chart opens scrolled to the newest value)
  /// reliably carries 3 evenly-spaced labels.
  static bool shouldShowDateLabel(int idx, int total) {
    if (total <= 0) return false;
    if (total <= 7) return true;

    // Always show first.
    if (idx == 0) return true;

    // Scrollable series: label every 3rd index. With a 8-point
    // visible viewport this yields 2-3 labels in view, all
    // separated by ≥ 2 indices so adjacent date strings (e.g.
    // "Jun 25" / "Jun 26") never sit on top of each other.
    if (idx % 3 == 0) return true;

    // Show the last point only when it's at least 2 indices
    // past the nearest multiple-of-3 label. (total - 1) % 3 == 2
    // means the last is 2 after a multiple of 3, so the gap is
    // exactly 2 indices (visually clean). If the last is 0 or 1
    // past a multiple of 3, it's already covered or would
    // collide, so we skip it.
    if (idx == total - 1 && (total - 1) % 3 == 2) return true;

    return false;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Round [value] up to the nearest "nice" number: 1, 2, 5, 10, 20, 50, …
  static double _niceNumber(double value) {
    if (value <= 0) return 1.0;

    final magnitude = _pow10(_floor10(value));
    final fraction = value / magnitude;

    final double niceFraction;
    if (fraction <= 1.0) {
      niceFraction = 1.0;
    } else if (fraction <= 2.0) {
      niceFraction = 2.0;
    } else if (fraction <= 5.0) {
      niceFraction = 5.0;
    } else {
      niceFraction = 10.0;
    }

    return niceFraction * magnitude;
  }

  /// floor(log10(value)), e.g. value=35 → 1 (10^1 = 10 ≤ 35 < 100).
  static int _floor10(double value) {
    if (value <= 0) return 0;
    int exp = 0;
    double v = value;
    while (v >= 10.0) {
      v /= 10.0;
      exp++;
    }
    while (v < 1.0) {
      v *= 10.0;
      exp--;
    }
    return exp;
  }

  static double _pow10(int exp) {
    double result = 1.0;
    if (exp >= 0) {
      for (int i = 0; i < exp; i++) {
        result *= 10.0;
      }
    } else {
      for (int i = 0; i > exp; i--) {
        result /= 10.0;
      }
    }
    return result;
  }

  static String _shortMonthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
