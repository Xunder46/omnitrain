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
      expect(maxTicks, lessThanOrEqualTo(4));
      expect(maxTicks, greaterThanOrEqualTo(2));
    });

    test('readable interval enforces spacing budget for dense ranges', () {
      final bounds = ChartAxisHelper.computeBounds([0, 3000]);
      final interval = ChartAxisHelper.readableIntervalForHeight(bounds, 120);
      final estimatedTicks = ((bounds.max - bounds.min) / interval).floor() + 1;

      expect(estimatedTicks, lessThanOrEqualTo(4));
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

    test('total=10: two intermediate indices at 1/3 and 2/3 are true', () {
      // 10 ~/ 3 = 3,  2*10 ~/ 3 = 6
      expect(ChartAxisHelper.shouldShowDateLabel(3, 10), isTrue);
      expect(ChartAxisHelper.shouldShowDateLabel(6, 10), isTrue);
    });

    test('total=10: other indices (1, 2, 4, 5, 7, 8) return false', () {
      for (final idx in [1, 2, 4, 5, 7, 8]) {
        expect(
          ChartAxisHelper.shouldShowDateLabel(idx, 10),
          isFalse,
          reason: 'index $idx should not be labelled in a 10-point series',
        );
      }
    });

    test('total=5: at most 4 true values', () {
      var trueCount = 0;
      for (var i = 0; i < 5; i++) {
        if (ChartAxisHelper.shouldShowDateLabel(i, 5)) trueCount++;
      }
      expect(trueCount, lessThanOrEqualTo(4));
    });

    test('always shows first and last for any total ≥ 2', () {
      for (final total in [2, 5, 10, 20, 50]) {
        expect(
          ChartAxisHelper.shouldShowDateLabel(0, total),
          isTrue,
          reason: 'first idx for total=$total',
        );
        expect(
          ChartAxisHelper.shouldShowDateLabel(total - 1, total),
          isTrue,
          reason: 'last idx for total=$total',
        );
      }
    });
  });
}
