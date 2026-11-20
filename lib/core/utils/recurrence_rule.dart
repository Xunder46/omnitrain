import 'dart:convert';
import 'dart:math' as math;

import 'date_utils.dart';

/// How often a series repeats (D-27702).
enum RecurrenceUnit { day, week, month }

/// How a series ends (D-27702).
enum RecurrenceEnd { count, date }

/// The repeat rule of a planned-session series, stored as a small JSON text on
/// every row of the series (D-27701, D-27702). Dates come from the pure
/// [dates] function (D-27703): local midnights built with `DateTime(y, m,
/// d + k)` only, so a clock-change day cannot drift an hour.
class RecurrenceRule {
  const RecurrenceRule({
    required this.series,
    required this.unit,
    this.every = 1,
    this.weekdays = const <int>[],
    this.end = RecurrenceEnd.count,
    this.count = 8,
    this.until,
  });

  /// Series id shared by every row of the series (uuid text, non-empty).
  final String series;

  final RecurrenceUnit unit;

  /// Interval; 1..12.
  final int every;

  /// Dart weekdays (1=Mon .. 7=Sun), used only for [RecurrenceUnit.week]
  /// (D-27712).
  final List<int> weekdays;

  final RecurrenceEnd end;

  /// Total sessions including the first; 1..366.
  final int count;

  /// Local date-only bound, used only for [RecurrenceEnd.date].
  final DateTime? until;

  static const _units = <String, RecurrenceUnit>{
    'day': RecurrenceUnit.day,
    'week': RecurrenceUnit.week,
    'month': RecurrenceUnit.month,
  };
  static const _ends = <String, RecurrenceEnd>{
    'count': RecurrenceEnd.count,
    'date': RecurrenceEnd.date,
  };
  static const _weekdayNames = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Forgiving parse (D-27702): returns null for anything unreadable and
  /// never throws. Entries of [weekdays] outside 1..7 are dropped.
  static RecurrenceRule? tryParse(String? text) {
    if (text == null || text.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != 1) return null;
    final series = decoded['series'];
    if (series is! String || series.isEmpty) return null;
    final unit = _units[decoded['unit']];
    if (unit == null) return null;
    final end = _ends[decoded['end']];
    if (end == null) return null;
    final every = decoded['every'];
    if (every is! int || every < 1) return null;
    final count = decoded['count'];
    if (count is! int) return null;
    final rawWeekdays = decoded['weekdays'];
    final List<int> weekdays;
    if (rawWeekdays is List) {
      weekdays = rawWeekdays
          .whereType<int>()
          .where((day) => day >= 1 && day <= 7)
          .toSet()
          .toList();
      weekdays.sort();
    } else {
      weekdays = const <int>[];
    }
    DateTime? until;
    if (end == RecurrenceEnd.date) {
      until = _parseDay(decoded['until']);
      if (until == null) return null;
    }
    return RecurrenceRule(
      series: series,
      unit: unit,
      every: every,
      weekdays: weekdays,
      end: end,
      count: count,
      until: until,
    );
  }

  /// Stable key order (D-27702); `until` only when the end mode is a date.
  String encode() {
    final map = <String, Object?>{
      'v': 1,
      'series': series,
      'unit': unit.name,
      'every': every,
      'weekdays': weekdays,
      'end': end.name,
      'count': count,
    };
    if (end == RecurrenceEnd.date && until != null) {
      map['until'] = _encodeDay(until!);
    }
    return jsonEncode(map);
  }

  /// The repeat dates, always starting with [first] itself (D-27703).
  List<DateTime> dates(DateTime first) {
    final first0 = DateTime(first.year, first.month, first.day);
    var cap = DateTime(first0.year + 1, first0.month, first0.day);
    if (end == RecurrenceEnd.date && until != null) {
      final bound = DateTime(until!.year, until!.month, until!.day);
      if (bound.isBefore(first0)) return <DateTime>[first0];
      if (bound.isBefore(cap)) cap = bound;
    }
    final limit = end == RecurrenceEnd.date ? 366 : count.clamp(1, 366);
    switch (unit) {
      case RecurrenceUnit.day:
        return _dayDates(first0, cap, limit);
      case RecurrenceUnit.week:
        return _weekDates(first0, cap, limit);
      case RecurrenceUnit.month:
        return _monthDates(first0, cap, limit);
    }
  }

  /// The text up to and including the weekday list, shared by [summary] and
  /// [describe]: `Every`, the interval, the unit noun and ` on Mon, Thu` for
  /// weeks (ticks = `{...weekdays, first.weekday}`).
  String _pattern(DateTime first) {
    final interval = every == 1 ? '' : ' $every';
    final noun = every == 1 ? '' : 's';
    final buffer = StringBuffer();
    switch (unit) {
      case RecurrenceUnit.day:
        buffer.write('Every$interval day$noun');
      case RecurrenceUnit.week:
        buffer.write('Every$interval week$noun');
      case RecurrenceUnit.month:
        buffer.write('Every$interval month$noun');
    }
    if (unit == RecurrenceUnit.week) {
      final ticks = <int>{...weekdays, first.weekday}.toList()..sort();
      final names = ticks.map((day) => _weekdayNames[day - 1]).join(', ');
      buffer.write(' on $names');
    }
    return buffer.toString();
  }

  /// One plain-words line, e.g. `Every 2 weeks on Mon, Thu · 4 sessions`.
  String summary(DateTime first, int sessions) {
    final buffer = StringBuffer(_pattern(first));
    buffer.write(' · ${sessions == 1 ? '1 session' : '$sessions sessions'}');
    if (end == RecurrenceEnd.date && until != null) {
      buffer.write(
        ' · until ${until!.day} ${OmniDateUtils.shortMonthName(until!.month)}',
      );
    }
    return buffer.toString();
  }

  /// The whole series in plain words, for a row that is already in a series
  /// (the first date is not known there): `Every 2 weeks on Mon, Thu · 8
  /// sessions`, or `... · until 14 Jan` when the series ends on a date.
  String describe(DateTime first) {
    final buffer = StringBuffer(_pattern(first));
    if (end == RecurrenceEnd.date && until != null) {
      buffer.write(
        ' · until ${until!.day} ${OmniDateUtils.shortMonthName(until!.month)}',
      );
    } else {
      buffer.write(' · ${count == 1 ? '1 session' : '$count sessions'}');
    }
    return buffer.toString();
  }

  static DateTime? _parseDay(Object? value) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static String _encodeDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  List<DateTime> _dayDates(DateTime first0, DateTime cap, int limit) {
    var result = <DateTime>[first0];
    for (var k = 1; result.length < limit; k++) {
      final date = DateTime(first0.year, first0.month, first0.day + k * every);
      if (date.isAfter(cap)) break;
      result = <DateTime>[...result, date];
    }
    return result;
  }

  List<DateTime> _weekDates(DateTime first0, DateTime cap, int limit) {
    var result = <DateTime>[first0];
    final monday0 = DateTime(
      first0.year,
      first0.month,
      first0.day - (first0.weekday - 1),
    );
    final allowed = weekdays.isEmpty ? <int>{first0.weekday} : weekdays.toSet();
    for (var k = 1; result.length < limit; k++) {
      final date = DateTime(first0.year, first0.month, first0.day + k);
      if (date.isAfter(cap)) break;
      final weekIndex = _daysBetween(monday0, date) ~/ 7;
      if (weekIndex % every == 0 && allowed.contains(date.weekday)) {
        result = <DateTime>[...result, date];
      }
    }
    return result;
  }

  List<DateTime> _monthDates(DateTime first0, DateTime cap, int limit) {
    var result = <DateTime>[first0];
    for (var k = 1; result.length < limit; k++) {
      final monthStart = DateTime(first0.year, first0.month + k * every, 1);
      final day = math.min(
        first0.day,
        _daysInMonth(monthStart.year, monthStart.month),
      );
      final date = DateTime(monthStart.year, monthStart.month, day);
      if (date.isAfter(cap)) break;
      result = <DateTime>[...result, date];
    }
    return result;
  }
}
