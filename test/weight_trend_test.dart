// The weight line (plan 104): the pure rule, its copy and its service.
//
// Scenarios S-17701 … S-17703 of `docs/plans/2026-11-03-104-weight-line-plan/`.
// Plain `test()`, never `testWidgets`: Hive's real file I/O settles only on the
// real event loop. The harness is opened in `setUp`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/weight_trend.dart';
import 'package:omnitrain/core/services/weight_trend_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// The fixed "today" every model fixture counts back from.
final DateTime _now = DateTime(2026, 3, 20, 12);

/// Local noon [daysAgo] days before [_now].
DateTime _daysAgo(int daysAgo) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo, 12);

BodyMeasurementEntry _entry(
  String id,
  double value,
  DateTime at, {
  String type = 'bodyweight',
  String unit = MetricIds.unitKg,
}) => BodyMeasurementEntry(
  id: id,
  measurementType: type,
  value: value,
  unitId: unit,
  recordedAtMs: at.millisecondsSinceEpoch,
);

void main() {
  group('S-17701 weightTrend', () {
    test('the constants the rule is built from are the ones the plan names', () {
      expect(kWeightTrendWindowDays, 28);
      expect(kWeightTrendMinSpanDays, 7);
    });

    test('27 days apart: the latest figure and the change', () {
      final trend = weightTrend(
        entries: [_entry('a', 80.8, _daysAgo(27)), _entry('b', 80.2, _daysAgo(0))],
        now: _now,
      );
      expect(trend, isNotNull);
      expect(trend!.latestKg, 80.2);
      expect(trend.changeKg, closeTo(-0.6, 1e-9));
    });

    test('6 days apart is too close: no trend', () {
      expect(
        weightTrend(
          entries: [_entry('a', 80.8, _daysAgo(6)), _entry('b', 80.2, _daysAgo(0))],
          now: _now,
        ),
        isNull,
      );
    });

    test('exactly 7 days apart is enough', () {
      final trend = weightTrend(
        entries: [_entry('a', 80.8, _daysAgo(7)), _entry('b', 80.2, _daysAgo(0))],
        now: _now,
      );
      expect(trend, isNotNull);
      expect(trend!.changeKg, closeTo(-0.6, 1e-9));
    });

    test('one weigh-in, or none, is no trend', () {
      expect(weightTrend(entries: [_entry('a', 80.2, _daysAgo(0))], now: _now), isNull);
      expect(weightTrend(entries: const [], now: _now), isNull);
    });

    test('a weigh-in 28 days ago is outside the window', () {
      expect(
        weightTrend(
          entries: [_entry('a', 81.0, _daysAgo(28)), _entry('b', 80.0, _daysAgo(0))],
          now: _now,
        ),
        isNull,
      );
    });

    test('a pound entry and a height entry are not weigh-ins in kilograms', () {
      expect(
        weightTrend(
          entries: [
            _entry('lb', 180, _daysAgo(20), unit: 'unit-lb'),
            _entry('h', 180, _daysAgo(20), type: 'height'),
            _entry('kg', 80.2, _daysAgo(0)),
          ],
          now: _now,
        ),
        isNull,
      );
    });

    test('the order of the list does not matter', () {
      final trend = weightTrend(
        entries: [_entry('b', 80.2, _daysAgo(0)), _entry('a', 80.8, _daysAgo(27))],
        now: _now,
      );
      expect(trend!.latestKg, 80.2);
      expect(trend.changeKg, closeTo(-0.6, 1e-9));
    });

    test('three weigh-ins: the change is last minus first', () {
      final trend = weightTrend(
        entries: [
          _entry('a', 80.0, _daysAgo(20)),
          _entry('b', 82.0, _daysAgo(10)),
          _entry('c', 80.5, _daysAgo(1)),
        ],
        now: _now,
      );
      expect(trend!.latestKg, 80.5);
      expect(trend.changeKg, closeTo(0.5, 1e-9));
    });

    test('a spring-forward day inside the week does not shorten it', () {
      // 2026-03-08 is a 23-hour day in a zone with daylight saving: noon on
      // Mar 5 to noon on Mar 12 is 167 hours, which `Duration.inDays` reads as
      // 6. The rule counts calendar days, so this is a true 7-day gap.
      final now = DateTime(2026, 3, 12, 18);
      final trend = weightTrend(
        entries: [
          _entry('a', 80.8, DateTime(2026, 3, 5, 12)),
          _entry('b', 80.2, DateTime(2026, 3, 12, 12)),
        ],
        now: now,
      );
      expect(trend, isNotNull);
    });
  });

  group('S-17702 weightTrendLine', () {
    test('a fall reads with a true minus sign', () {
      expect(
        weightTrendLine(latest: 80.2, change: -0.6, unitLabel: 'kg'),
        '80.2 kg, −0.6 kg over 4 weeks',
      );
    });

    test('a rise reads with a plus sign', () {
      expect(
        weightTrendLine(latest: 80.2, change: 0.44, unitLabel: 'kg'),
        '80.2 kg, +0.4 kg over 4 weeks',
      );
    });

    test('a change that rounds to 0.0 reads no change, either way', () {
      expect(
        weightTrendLine(latest: 80.2, change: 0.04, unitLabel: 'kg'),
        '80.2 kg, no change over 4 weeks',
      );
      expect(
        weightTrendLine(latest: 80.2, change: -0.04, unitLabel: 'kg'),
        '80.2 kg, no change over 4 weeks',
      );
    });

    test('the unit label is the caller\'s', () {
      expect(
        weightTrendLine(latest: 176.8, change: -1.3, unitLabel: 'lbs'),
        '176.8 lbs, −1.3 lbs over 4 weeks',
      );
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-17703 WeightTrendService — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        // The Mock harness may open with sample measurements: start empty.
        for (final entry in await repo.getMeasurementHistory('bodyweight')) {
          await repo.deleteMeasurementEntry(entry.id);
        }
      });

      tearDown(() async {
        await harness.close();
      });

      test('no entries gives null', () async {
        expect(await WeightTrendService(repo).compute(now: _now), isNull);
      });

      test('two kilogram entries 14 days apart give the trend', () async {
        await repo.saveMeasurementEntry(_entry('w1', 80.8, _daysAgo(14)));
        await repo.saveMeasurementEntry(_entry('w2', 80.2, _daysAgo(0)));

        final trend = await WeightTrendService(repo).compute(now: _now);

        expect(trend, isNotNull);
        expect(trend!.latestKg, 80.2);
        expect(trend.changeKg, closeTo(-0.6, 1e-9));
      });
    });
  }
}
