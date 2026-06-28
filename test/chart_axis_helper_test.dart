import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/chart_axis_helper.dart';

void main() {
  // ── computeBounds ─────────────────────────────────────────────────────────

  group('ChartAxisHelper.computeBounds', () {
    test('ascending data: min padded below lowest value, max above highest', () {
      final bounds = ChartAxisHelper.computeBounds([90, 95, 100, 110]);
      // range=20, paddedMin = max(0, 90 - 3) = 87 (NOT clamped to 0 — data is far from 0)
      expect(bounds.min, closeTo(87.0, 0.5));
      // paddedMax = 110 + 3 + 1 = 114
      expect(bounds.max, closeTo(114.0, 0.5));
      expect(bounds.interval, greaterThan(0.0));
    });

    test(
      'descending data (Conventional Deadlift decline): full range preserved',
      () {
        final bounds = ChartAxisHelper.computeBounds([200, 190, 180, 170]);
        // Range is 30, padded 15% each side → paddedMin ≈ 170 - 4.5 = 165.5, paddedMax ≈ 200 + 4.5 + 1 = 205.5.
        expect(bounds.min, greaterThanOrEqualTo(0.0));
        expect(bounds.min, closeTo(165.5, 1.0));
        expect(bounds.max, closeTo(205.5, 1.0));
        // The full decline magnitude (≥30) should be visible.
        expect(bounds.max - bounds.min, greaterThan(30.0));
        expect(bounds.interval, greaterThan(0.0));
      },
    );

    test(
      'flat data: non-zero range due to +1 floor, min stays at flat value',
      () {
        final bounds = ChartAxisHelper.computeBounds([100, 100, 100]);
        // range=0, paddedMin = max(0, 100) = 100; paddedMax = 100 + 0 + 1 = 101.
        expect(bounds.min, equals(100.0));
        expect(bounds.max, greaterThan(100.0)); // at least 101
        expect(bounds.interval, greaterThan(0.0));
      },
    );

    test('single value: no crash, valid non-zero range', () {
      final bounds = ChartAxisHelper.computeBounds([150.0]);
      // range=0, paddedMin = max(0, 150) = 150; paddedMax = 150 + 1 = 151.
      expect(bounds.min, equals(150.0));
      expect(bounds.max, greaterThan(150.0));
      expect(bounds.interval, greaterThan(0.0));
    });

    test('near-zero data: paddedMin clamped to 0 when it would go negative', () {
      // range=5, paddedMin = max(0, 1 - 0.75) = max(0, 0.25) = 0.25 (barely positive)
      // range=2, paddedMin = max(0, 0 - 0.3) = max(0, -0.3) = 0 (clamped)
      final bounds = ChartAxisHelper.computeBounds([0.0, 1.0, 2.0]);
      expect(bounds.min, greaterThanOrEqualTo(0.0));
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
