// Plan 24, phase P3 — `StatsWindow.dayCount` (S-4011, D-4007).
//
// The Instruments caption states the length of the range the change compares
// against, and that range is `StatsProgressService.previousRangeFor`'s own
// arithmetic over the window's local-midnight bounds: inclusive of both ends,
// counted in calendar days rather than in a duration. This file pins `dayCount`
// against that function's output instead of copying its `+ 1`, so the two can
// never drift.
//
// Plain `test()`: no repository, no widget, no clock of its own.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';

/// The calendar-day length of a range `previousRangeFor` returned: the number
/// of distinct local days its inclusive bounds cover.
int _rangeDayCount(({int fromMs, int toMs}) range) {
  final first = DateTime.fromMillisecondsSinceEpoch(range.fromMs);
  final last = DateTime.fromMillisecondsSinceEpoch(range.toMs);
  return DateTime.utc(last.year, last.month, last.day)
          .difference(DateTime.utc(first.year, first.month, first.day))
          .inDays +
      1;
}

StatsWindow _window(DateTime from, DateTime to) => StatsWindow(
  fromMs: from,
  toMs: to,
  label: 'Test window',
  isPeriodScoped: false,
);

void main() {
  final now = DateTime.now();
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  /// Local midnight [daysAgo] days back, built the way `resolveWindow` builds
  /// it (`DateTime(y, m, d - n)`), so a month or a DST transition normalizes.
  DateTime day(int daysAgo) =>
      DateTime(now.year, now.month, now.day - daysAgo);

  group('S-4011 StatsWindow.dayCount is the previous range\'s own length', () {
    test('a recent-days window counts its days inclusively', () {
      final window = _window(day(13), todayEnd);

      expect(window.dayCount, 14);
      expect(
        window.dayCount,
        _rangeDayCount(StatsProgressService.previousRangeFor(window)),
      );
    });

    test('a longer recent-days window reads its own span', () {
      // The flagship fixture's shape: 14 training days spanning 15 calendar
      // days, because the window ends at the end of today.
      final window = _window(day(14), todayEnd);

      expect(window.dayCount, 15);
      expect(
        window.dayCount,
        _rangeDayCount(StatsProgressService.previousRangeFor(window)),
      );
    });

    test('a period window counts its own calendar days', () {
      final window = _window(day(19), todayEnd);

      expect(window.dayCount, 20);
      expect(
        window.dayCount,
        _rangeDayCount(StatsProgressService.previousRangeFor(window)),
      );
    });

    test('a single-day window is one day', () {
      final window = _window(todayMidnight, todayEnd);

      expect(window.dayCount, 1);
      expect(
        window.dayCount,
        _rangeDayCount(StatsProgressService.previousRangeFor(window)),
      );
    });

    test('the count is calendar days, not the elapsed duration', () {
      // A window from midnight to partway through today: thirteen whole days of
      // elapsed time, but the fourteen calendar days from its first day through
      // today. `previousRangeFor` sizes the comparison from the same days.
      final window = _window(
        day(13),
        DateTime(now.year, now.month, now.day, 9, 15),
      );

      expect(window.toMs.difference(window.fromMs).inDays, 13);
      expect(window.dayCount, 14);
      expect(
        window.dayCount,
        _rangeDayCount(StatsProgressService.previousRangeFor(window)),
      );
    });
  });
}
