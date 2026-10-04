// Stats PR 8a, Phase 1 — the shared nutrition week-block foundation.
//
// Pure Dart: the anchor day is a parameter, so there is no clock, no
// repository and no Flutter. Scenario S-2110 and the block-start,
// month-boundary and logged-days-only-mean contracts of
// `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/nutrition_consistency.dart';

/// Local midnight [daysAgo] local calendar days before [anchor].
DateTime _day(DateTime anchor, int daysAgo) =>
    DateTime(anchor.year, anchor.month, anchor.day - daysAgo);

void main() {
  final anchor = DateTime(2026, 6, 15, 10, 30);

  test('the constant contracts', () {
    expect(kWeekDays, 7);
    expect(kConsistentWeekMinLoggedDays, 5);
  });

  group('weekBlockStarts', () {
    test('eight starts for an 8-week range, oldest first and abutting', () {
      final starts = weekBlockStarts(anchorDay: anchor, weeks: 8);
      expect(starts, [
        _day(anchor, 55),
        _day(anchor, 48),
        _day(anchor, 41),
        _day(anchor, 34),
        _day(anchor, 27),
        _day(anchor, 20),
        _day(anchor, 13),
        _day(anchor, 6),
      ]);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i], _day(starts[i - 1], -kWeekDays));
      }
    });

    test('the last start is the block that contains the anchor', () {
      final starts = weekBlockStarts(anchorDay: anchor, weeks: 6);
      expect(starts.last, _day(anchor, kWeekDays - 1));
      expect(
        loggedDaysInWeek(blockStart: starts.last, loggedDays: [anchor]),
        1,
      );
    });

    test('a block spanning a month end keeps its 7 days', () {
      final starts = weekBlockStarts(
        anchorDay: DateTime(2026, 3, 10),
        weeks: 8,
      );
      expect(starts, contains(DateTime(2026, 1, 28)));
      expect(starts, contains(DateTime(2026, 2, 4)));

      final blockDays = [
        for (var i = 0; i < kWeekDays; i++) DateTime(2026, 1, 28 + i),
      ];
      expect(blockDays.last, DateTime(2026, 2, 3));
      expect(
        loggedDaysInWeek(
          blockStart: DateTime(2026, 1, 28),
          loggedDays: blockDays,
        ),
        kWeekDays,
      );
    });
  });

  group('loggedDaysInWeek and isConsistentWeek', () {
    test('S-2110 exactly 5 of 7 passes and 4 of 7 fails', () {
      final five = [for (var n = 20; n >= 16; n--) _day(anchor, n)];
      final four = [for (var n = 13; n >= 10; n--) _day(anchor, n)];

      final block20 = _day(anchor, 20);
      final block13 = _day(anchor, 13);

      expect(loggedDaysInWeek(blockStart: block20, loggedDays: five), 5);
      expect(isConsistentWeek(blockStart: block20, loggedDays: five), isTrue);

      expect(loggedDaysInWeek(blockStart: block13, loggedDays: four), 4);
      expect(isConsistentWeek(blockStart: block13, loggedDays: four), isFalse);
    });

    test(
      'days outside the block are excluded and a repeated day counts once',
      () {
        final blockStart = _day(anchor, 13);
        final inside = _day(anchor, 12);
        final outside = _day(anchor, 6);
        expect(
          loggedDaysInWeek(
            blockStart: blockStart,
            loggedDays: [inside, inside, outside],
          ),
          1,
        );
      },
    );
  });

  group('loggedDayMean', () {
    test('an empty series is null, never zero', () {
      expect(loggedDayMean(const <double>[]), isNull);
    });

    test('averages the logged days only', () {
      expect(loggedDayMean(const [2000, 2500]), 2250);
    });
  });
}
