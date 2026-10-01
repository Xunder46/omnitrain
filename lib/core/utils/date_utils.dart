/// Date utility helpers for calendar and session grouping.
/// All operations are local-time safe — they construct DateTime objects
/// from local time components, avoiding UTC-offset pitfalls.
library;

class OmniDateUtils {
  /// Returns the epoch-ms of the start of the given day (midnight local time).
  static int startOfDayMs(DateTime date) =>
      DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;

  /// Returns the epoch-ms of the start of today (midnight local time).
  /// Convenience wrapper over [startOfDayMs] using [DateTime.now].
  static int todayMidnightMs() => startOfDayMs(DateTime.now());

  /// Returns the epoch-ms of the end of the given day (23:59:59.999 local time).
  static int endOfDayMs(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
    23,
    59,
    59,
    999,
  ).millisecondsSinceEpoch;

  /// True if [date] is in a past day relative to today (local time).
  static bool isPastDay(DateTime date) {
    final today = _today();
    final d = DateTime(date.year, date.month, date.day);
    return d.isBefore(today);
  }

  /// True if [date] is today (local time).
  static bool isToday(DateTime date) {
    final today = _today();
    final d = DateTime(date.year, date.month, date.day);
    return d == today;
  }

  /// True if [date] is today or in the future.
  static bool isTodayOrFuture(DateTime date) => !isPastDay(date);

  /// Returns DateTime at midnight local-time for today.
  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Returns DateTime from epoch-ms interpreted in local time.
  static DateTime fromMs(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);

  /// Builds the ordered list of DateTime values (midnight each day) for a
  /// month grid, starting from the anchor weekday determined by [startOfWeek].
  ///
  /// [startOfWeek] accepts `'monday'` (default, ISO week — Mon=col 0) or
  /// `'sunday'` (US week — Sun=col 0). The grid always has complete weeks
  /// (multiples of 7 cells).
  static List<DateTime?> buildMonthGrid(
    int year,
    int month, {
    String startOfWeek = 'monday',
  }) {
    final firstOfMonth = DateTime(year, month, 1);
    // weekday: 1=Mon … 7=Sun (Dart convention)
    final int leadingBlanks;
    if (startOfWeek == 'sunday') {
      // Sunday-first: Sun=0, Mon=1, … Sat=6
      // Dart: Sun=7 → 7%7=0, Mon=1 → 1%7=1, … Sat=6 → 6%7=6
      leadingBlanks = firstOfMonth.weekday % 7;
    } else {
      // Monday-first: Mon=0, Tue=1, … Sun=6
      leadingBlanks = (firstOfMonth.weekday - 1) % 7;
    }

    final daysInMonth = DateTime(year, month + 1, 0).day; // day 0 of next month

    final totalCells = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;

    return List<DateTime?>.generate(totalCells, (i) {
      final dayIndex = i - leadingBlanks;
      if (dayIndex < 0 || dayIndex >= daysInMonth) return null;
      return DateTime(year, month, dayIndex + 1);
    });
  }

  /// Short month name (e.g. "Mar").
  static String shortMonthName(int month) {
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

  /// Full month name (e.g. "March").
  static String fullMonthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[(month - 1).clamp(0, 11)];
  }

  /// Formats a date as "Mon DD" (e.g. "Mar 08").
  static String formatShort(DateTime date) =>
      '${shortMonthName(date.month)} ${date.day.toString().padLeft(2, '0')}';

  /// Formats a date range as "MMM DD – MMM DD, YYYY".
  static String formatRange(int startMs, int endMs) {
    final start = fromMs(startMs);
    final end = fromMs(endMs);
    final sameYear = start.year == end.year;
    final startStr = '${shortMonthName(start.month)} ${start.day}';
    final endStr = '${shortMonthName(end.month)} ${end.day}, ${end.year}';
    return sameYear
        ? '$startStr – $endStr'
        : '$startStr, ${start.year} – $endStr';
  }

  /// Formats a duration in milliseconds as "Xh Ym" (rounded to the nearest
  /// minute). Suitable for all-time aggregate totals where sub-minute
  /// precision is not meaningful.
  ///
  /// Examples:
  ///   0          → "0m"
  ///   45_000     → "0m"   (< 1 min rounds to 0)
  ///   3_600_000  → "1h 0m"
  ///   5_400_000  → "1h 30m"
  static String formatDurationHoursMins(int ms) {
    final totalMinutes = (ms / 60000).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  /// Formats a duration in milliseconds as a clock: "m:ss", or "h:mm:ss" once
  /// it passes the hour. The shape a value is read in mid-effort, where
  /// seconds still matter.
  static String formatClock(int ms) {
    final totalSeconds = (ms < 0 ? 0 : ms / 1000).round();
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final minutes = totalSeconds ~/ 60;
    if (minutes < 60) return '$minutes:$seconds';
    final hours = minutes ~/ 60;
    return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$seconds';
  }
}
