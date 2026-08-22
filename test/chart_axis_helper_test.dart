import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/chart_axis_helper.dart';

void main() {
  // ── computeBounds ─────────────────────────────────────────────────────────

  group('ChartAxisHelper.computeBounds', () {
    test('ascending data: min rounded down, max rounded up to multiples of interval', () {
      final bounds = ChartAxisHelper.computeBounds([90, 95, 100, 110]);
      // D-2: min should be a multiple of interval and ≤ original minimum (90).
      // max should be a multiple of interval and ≥ original maximum (110).
      expect(bounds.min % bounds.interval, closeTo(0.0, 0.01),
          reason: 'min should be multiple of interval');
      expect(bounds.min, lessThanOrEqualTo(90.0),
          reason: 'min should not be above data minimum');
      expect(bounds.max % bounds.interval, closeTo(0.0, 0.01),
          reason: 'max should be multiple of interval');
      expect(bounds.max, greaterThanOrEqualTo(110.0),
          reason: 'max should not be below data maximum');
      expect(bounds.interval, greaterThan(0.0));
    });

    test(
      'descending data (Conventional Deadlift decline): full range preserved',
      () {
        final bounds = ChartAxisHelper.computeBounds([200, 190, 180, 170]);
        // D-2: min at or below 170, max at or above 200, both multiples of interval.
        expect(bounds.min, lessThanOrEqualTo(170.0),
            reason: 'rounded min should be at or below data minimum');
        expect(bounds.max, greaterThanOrEqualTo(200.0),
            reason: 'rounded max should be at or above data maximum');
        expect(bounds.min % bounds.interval, closeTo(0.0, 0.01),
            reason: 'min must be multiple of interval');
        expect(bounds.max % bounds.interval, closeTo(0.0, 0.01),
            reason: 'max must be multiple of interval');
        // The full decline magnitude (≥30) should be visible.
        expect(bounds.max - bounds.min, greaterThan(30.0));
        expect(bounds.interval, greaterThan(0.0));
      },
    );

    test(
      'flat data: produces at least 2 distinct labels with visible range',
      () {
        final bounds = ChartAxisHelper.computeBounds([100, 100, 100]);
        // D-2: At least 2 distinct labels (min and min+interval, or more).
        final labelCount = ((bounds.max - bounds.min) / bounds.interval).floor() + 1;
        expect(labelCount, greaterThanOrEqualTo(2),
            reason: 'flat data should produce at least 2 labels');
        expect(bounds.max, greaterThan(bounds.min),
            reason: 'max should be strictly greater than min');
        expect(bounds.interval, greaterThan(0.0));
      },
    );

    test('single value: produces at least 2 distinct labels', () {
      final bounds = ChartAxisHelper.computeBounds([150.0]);
      // D-2: At least 2 distinct labels with visible range.
      final labelCount = ((bounds.max - bounds.min) / bounds.interval).floor() + 1;
      expect(labelCount, greaterThanOrEqualTo(2),
          reason: 'single value should produce at least 2 labels');
      expect(bounds.max, greaterThan(bounds.min));
      expect(bounds.interval, greaterThan(0.0));
    });

    test('near-zero data: min ≥ 0, max ≥ data max, both multiples of interval', () {
      final bounds = ChartAxisHelper.computeBounds([0.0, 1.0, 2.0]);
      // D-2: min should be ≥ 0 (clamp), max ≥ 2.0 (data max), both multiples.
      expect(bounds.min, greaterThanOrEqualTo(0.0),
          reason: 'min should not go negative');
      expect(bounds.max, greaterThanOrEqualTo(2.0),
          reason: 'max should be at or above data maximum');
      expect(bounds.min % bounds.interval, closeTo(0.0, 0.01),
          reason: 'min must be multiple of interval');
      expect(bounds.max % bounds.interval, closeTo(0.0, 0.01),
          reason: 'max must be multiple of interval');
    });

    test('interval is a nice round number (power-of-10-based)', () {
      // Various data sets — each interval should be 1, 2, 5, or 10×10^n.
      final niceMultiples = [1.0, 2.0, 5.0];
      for (final data in [
        [90.0, 95.0, 100.0, 110.0],
        [200.0, 190.0, 180.0, 170.0],
        [1000.0, 1500.0, 2000.0],
        [0.1, 0.2, 0.3],
      ]) {
        final bounds = ChartAxisHelper.computeBounds(data);
        final interval = bounds.interval;
        // Derive magnitude: interval / 10^floor(log10(interval)) ≈ 1, 2 or 5.
        var v = interval;
        while (v >= 10.0) {
          v /= 10.0;
        }
        while (v < 1.0) {
          v *= 10.0;
        }
        expect(
          niceMultiples.any((m) => (v - m).abs() < 0.001),
          isTrue,
          reason: 'interval $interval (normalised $v) not in {1,2,5}',
        );
      }
    });

    test('small values (0–1 range): interval still > 0', () {
      final bounds = ChartAxisHelper.computeBounds([0.1, 0.15, 0.2]);
      expect(bounds.interval, greaterThan(0.0));
    });

    test('D-2: axis labels are multiples of interval for two-digit, three-digit, four-digit ranges', () {
      // Test that min/max are exact multiples for various ranges.
      for (final data in [
        [10.0, 20.0, 30.0],      // two-digit
        [100.0, 200.0, 300.0],   // three-digit
        [1000.0, 2000.0, 3000.0], // four-digit
      ]) {
        final bounds = ChartAxisHelper.computeBounds(data);
        // Min must be exact multiple of interval (no fractional part).
        expect(bounds.min / bounds.interval, isA<double>(),
            reason: 'min/interval should be a number');
        final minModulo = (bounds.min % bounds.interval).abs();
        expect(minModulo, closeTo(0.0, 0.0001),
            reason: 'min $bounds.min must be exact multiple of interval $bounds.interval');
        // Max must be exact multiple of interval.
        final maxModulo = (bounds.max % bounds.interval).abs();
        expect(maxModulo, closeTo(0.0, 0.0001),
            reason: 'max $bounds.max must be exact multiple of interval $bounds.interval');
      }
    });

    test('D-2: minimum is at or below series minimum for various ranges', () {
      for (final data in [
        [50.0, 75.0, 100.0],
        [500.0, 750.0, 1000.0],
        [5000.0, 7500.0, 10000.0],
      ]) {
        final bounds = ChartAxisHelper.computeBounds(data);
        final seriesMin = data.reduce((a, b) => a < b ? a : b);
        expect(bounds.min, lessThanOrEqualTo(seriesMin),
            reason: 'rounded min $bounds.min should not exceed series min $seriesMin');
      }
    });

    test('D-2: maximum is at or above series maximum for various ranges', () {
      for (final data in [
        [50.0, 75.0, 100.0],
        [500.0, 750.0, 1000.0],
        [5000.0, 7500.0, 10000.0],
      ]) {
        final bounds = ChartAxisHelper.computeBounds(data);
        final seriesMax = data.reduce((a, b) => a > b ? a : b);
        expect(bounds.max, greaterThanOrEqualTo(seriesMax),
            reason: 'rounded max $bounds.max should not be below series max $seriesMax');
      }
    });

    test('D-2: adjacent label spacing is uniform (all multiples of interval)', () {
      final bounds = ChartAxisHelper.computeBounds([100.0, 200.0, 300.0, 400.0, 500.0]);
      // Generate labels by starting at min and stepping by interval.
      final labels = <double>[];
      var label = bounds.min;
      while (label <= bounds.max + 0.001) {
        labels.add(label);
        label += bounds.interval;
      }
      expect(labels.length, greaterThanOrEqualTo(2),
          reason: 'should have at least 2 labels');
      // Verify all labels are multiples of interval.
      for (final lbl in labels) {
        final modulo = (lbl % bounds.interval).abs();
        expect(modulo, closeTo(0.0, 0.0001),
            reason: 'label $lbl must be multiple of interval $bounds.interval');
      }
      // Verify uniform spacing.
      for (var i = 1; i < labels.length; i++) {
        final gap = labels[i] - labels[i - 1];
        expect(gap, closeTo(bounds.interval, 0.0001),
            reason: 'gap between labels should equal interval');
      }
    });
  });

  // ── y-axis label formatting ──────────────────────────────────────────────

  group('ChartAxisHelper.formatYAxisValue', () {
    test('small value stays single-line with unit', () {
      final label = ChartAxisHelper.formatYAxisValue(50, 'lbs');
      expect(label, equals('50 lbs'));
      expect(label.contains('\n'), isFalse);
      expect(label.contains('\r'), isFalse);
    });

    test('large value stays single-line with unit', () {
      final label = ChartAxisHelper.formatYAxisValue(2900, 'lbs');
      expect(label, equals('2900 lbs'));
      expect(label.contains('\n'), isFalse);
      expect(label.contains('\r'), isFalse);
    });
  });

  // ── y-axis spacing budget ────────────────────────────────────────────────

  group('ChartAxisHelper y-axis tick budget', () {
    test('max tick count for 120px chart stays within readable cap', () {
      final maxTicks = ChartAxisHelper.maxYAxisTickCountForHeight(120);
      expect(maxTicks, lessThanOrEqualTo(ChartAxisHelper.kMaxYAxisTickCount));
      expect(maxTicks, lessThanOrEqualTo(5));
      expect(maxTicks, greaterThanOrEqualTo(2));
    });

    test('readable interval enforces spacing budget for dense ranges', () {
      final bounds = ChartAxisHelper.computeBounds([0, 3000]);
      final interval = ChartAxisHelper.readableIntervalForHeight(bounds, 120);
      final estimatedTicks = ((bounds.max - bounds.min) / interval).floor() + 1;

      expect(estimatedTicks, lessThanOrEqualTo(5));
      expect(interval, greaterThan(0));
    });
  });

  // ── formatDateLabel ───────────────────────────────────────────────────────

  group('ChartAxisHelper.formatDateLabel', () {
    test('Jan 5', () {
      expect(
        ChartAxisHelper.formatDateLabel(DateTime(2024, 1, 5)),
        equals('Jan 5'),
      );
    });

    test('Dec 31', () {
      expect(
        ChartAxisHelper.formatDateLabel(DateTime(2024, 12, 31)),
        equals('Dec 31'),
      );
    });

    test('Mar 15', () {
      expect(
        ChartAxisHelper.formatDateLabel(DateTime(2025, 3, 15)),
        equals('Mar 15'),
      );
    });

    test('all 12 month names are correct', () {
      const expected = [
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
      for (var m = 1; m <= 12; m++) {
        expect(
          ChartAxisHelper.formatDateLabel(DateTime(2024, m, 1)),
          startsWith(expected[m - 1]),
        );
      }
    });
  });

  // ── shouldShowDateLabel ───────────────────────────────────────────────────

  group('ChartAxisHelper.shouldShowDateLabel', () {
    test('total=1: only index 0 returns true', () {
      expect(ChartAxisHelper.shouldShowDateLabel(0, 1), isTrue);
    });

    test('total=2: both indices return true', () {
      expect(ChartAxisHelper.shouldShowDateLabel(0, 2), isTrue);
      expect(ChartAxisHelper.shouldShowDateLabel(1, 2), isTrue);
    });

    test('total=3: all three return true', () {
      for (var i = 0; i < 3; i++) {
        expect(ChartAxisHelper.shouldShowDateLabel(i, 3), isTrue);
      }
    });

    test('total=4: all four return true', () {
      for (var i = 0; i < 4; i++) {
        expect(ChartAxisHelper.shouldShowDateLabel(i, 4), isTrue);
      }
    });

    test('total=10: first and last are true', () {
      expect(ChartAxisHelper.shouldShowDateLabel(0, 10), isTrue);
      expect(ChartAxisHelper.shouldShowDateLabel(9, 10), isTrue);
    });

    test('total=10: every 3rd index is labelled (0, 3, 6, 9)', () {
      for (final idx in [0, 3, 6, 9]) {
        expect(ChartAxisHelper.shouldShowDateLabel(idx, 10), isTrue,
            reason: 'idx $idx should be labelled (every 3rd rule)');
      }
    });

    test('total=10: non-multiple-of-3 indices return false', () {
      for (final idx in [1, 2, 4, 5, 7, 8]) {
        expect(
          ChartAxisHelper.shouldShowDateLabel(idx, 10),
          isFalse,
          reason:
              'index $idx is not a multiple of 3 and not first/last, so it should not be labelled',
        );
      }
    });

    test('total ≤ 7: every index is labelled (chart is not scrollable)', () {
      for (final total in [1, 2, 3, 4, 5, 6, 7]) {
        for (var i = 0; i < total; i++) {
          expect(ChartAxisHelper.shouldShowDateLabel(i, total), isTrue,
              reason: 'idx $i should be labelled for short series total=$total');
        }
      }
    });

    test('scrollable series (total ≥ 8): every 3rd index + first + (last '
        'only if ≥ 2 past the last multiple of 3)', () {
      for (final total in [8, 10, 11, 12, 14, 15, 20, 30, 50]) {
        var trueCount = 0;
        for (var i = 0; i < total; i++) {
          if (ChartAxisHelper.shouldShowDateLabel(i, total)) trueCount++;
        }
        // Predicted set: every multiple of 3, plus first (0,
        // already covered if it's a multiple of 3), plus last
        // (total-1) only when (total - 1) % 3 == 2.
        final expected = <int>{};
        for (var i = 0; i < total; i += 3) {
          expected.add(i);
        }
        if ((total - 1) % 3 == 2) {
          expected.add(total - 1);
        }
        expect(trueCount, expected.length,
            reason:
                'total=$total should produce ${expected.length} labels '
                '(multiples of 3 + last when ≥ 2 past the last multiple of 3); '
                'got $trueCount');
      }
    });

    test('scrollable series (total ≥ 8): at least 3 labels in the visible '
        'viewport (last 8 points) with no two adjacent', () {
      // The visible view of a scrollable chart is the last 8
      // points when it opens scrolled to the newest. The chart
      // must show at least 3 date labels inside that window
      // and consecutive labels must be ≥ 2 indices apart so
      // adjacent dates don't sit on top of each other.
      for (final total in [8, 10, 12, 14, 17, 20, 25, 30, 50, 100]) {
        final viewStart = (total - 8).clamp(0, total - 1);
        final visible = <int>[];
        for (var i = viewStart; i < total; i++) {
          if (ChartAxisHelper.shouldShowDateLabel(i, total)) {
            visible.add(i);
          }
        }
        expect(visible.length, greaterThanOrEqualTo(3),
            reason:
                'total=$total should show ≥3 labels in the last 8 points '
                '(idx $viewStart..${total - 1}); got ${visible.length}');
        // Verify no two adjacent labels (≥ 2 indices apart).
        for (var j = 1; j < visible.length; j++) {
          expect(visible[j] - visible[j - 1], greaterThanOrEqualTo(2),
              reason:
                  'consecutive labels at ${visible[j - 1]} and ${visible[j]} would '
                  'collide visually for total=$total');
        }
      }
    });

    test('always shows first for any total ≥ 1', () {
      for (final total in [1, 5, 8, 10, 20, 50]) {
        expect(
          ChartAxisHelper.shouldShowDateLabel(0, total),
          isTrue,
          reason: 'first idx for total=$total',
        );
      }
    });

    test('shows last only when not adjacent to a multiple-of-3 label', () {
      // (total - 1) % 3 == 0 → last is itself a multiple of 3
      // (already labelled).
      // (total - 1) % 3 == 1 → last is 1 after a multiple of 3
      // (would collide, so it is NOT labelled).
      // (total - 1) % 3 == 2 → last is 2 after a multiple of 3
      // (clean gap, so it IS labelled).
      for (final total in [10, 13, 16]) {
        // (total - 1) % 3 == 0
        expect(ChartAxisHelper.shouldShowDateLabel(total - 1, total), isTrue,
            reason: 'last is a multiple of 3 for total=$total');
      }
      for (final total in [8, 11, 14, 17]) {
        // (total - 1) % 3 == 1
        expect(ChartAxisHelper.shouldShowDateLabel(total - 1, total), isFalse,
            reason:
                'last is 1 after a multiple of 3 for total=$total; should be '
                'skipped to avoid collision');
      }
      for (final total in [12, 15, 18]) {
        // (total - 1) % 3 == 2
        expect(ChartAxisHelper.shouldShowDateLabel(total - 1, total), isTrue,
            reason: 'last is 2 after a multiple of 3 for total=$total; '
                'clean gap so it is labelled');
      }
    });
  });
}
