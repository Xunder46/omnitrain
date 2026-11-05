// The Consistency and Training Gap signals' rules (plan 105): how many sessions
// the last completed week held against the weeks before it, and how long it has
// been since the last session against the longest earlier gap. Pure Dart: `now`
// and the week's first day are parameters.

import '../utils/date_utils.dart';

/// The completed weeks the comparison reads, at most (D-17801).
const int kConsistencyWeeks = 8;

/// The completed weeks of history before either signal speaks (D-17801).
const int kConsistencyMinHistoryWeeks = 6;

/// The fewest sessions the last week holds for Consistency to speak.
const int kConsistencyMinWeekSessions = 3;

/// The span the Training Gap compares against: 56 local days ending today.
const int kTrainingGapWindowDays = kConsistencyWeeks * 7;

/// The fewest days since the last session for the gap to speak.
const int kTrainingGapMinDays = 5;

/// The fewest session days in the window before a gap means anything.
const int kTrainingGapMinSessionDays = 4;

/// Consistency ranks below Progression Rate among the positives.
const int kConsistencyPriority = 50;

/// The Training Gap is the lowest caution.
const int kTrainingGapPriority = 25;

DateTime _localDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to], on the dates re-read as UTC so a
/// clock change inside the span never turns a day into 23 or 25 hours.
int _daysApart(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Completed weeks from the week of the earliest of [days] up to the week that
/// starts at [currentWeekStart], that one excluded.
int _completedHistoryWeeks(
  Iterable<DateTime> days,
  DateTime currentWeekStart,
  String startOfWeek,
) {
  final first = days.reduce((a, b) => a.isBefore(b) ? a : b);
  final firstWeekStart = OmniDateUtils.startOfWeek(
    first,
    startOfWeek: startOfWeek,
  );
  return _daysApart(firstWeekStart, currentWeekStart) ~/ 7;
}

/// The last completed week against the weeks before it.
class ConsistencyResult {
  const ConsistencyResult({
    required this.lastWeekSessions,
    required this.weeks,
    required this.totalSessions,
  });

  /// Sessions in the last completed week.
  final int lastWeekSessions;

  /// Completed weeks averaged, the last one included.
  final int weeks;

  /// Sessions in those [weeks] weeks, the last week's included.
  final int totalSessions;

  double get average => totalSessions / weeks;
}

/// Consistency for [sessionStarts] at [now], or null (D-17801).
///
/// The weeks are the completed weeks (the running one is never counted)
/// starting on [startOfWeek] (`monday` or `sunday`). Speaks when at least
/// [kConsistencyMinHistoryWeeks] completed weeks of history exist and the last
/// week holds at least [kConsistencyMinWeekSessions] sessions and at least one
/// more than the average of the (up to [kConsistencyWeeks]) completed weeks.
ConsistencyResult? consistency({
  required List<DateTime> sessionStarts,
  required DateTime now,
  required String startOfWeek,
}) {
  if (sessionStarts.isEmpty) return null;
  final days = [for (final start in sessionStarts) _localDay(start)];
  final currentWeekStart = OmniDateUtils.startOfWeek(
    now,
    startOfWeek: startOfWeek,
  );
  final history = _completedHistoryWeeks(days, currentWeekStart, startOfWeek);
  if (history < kConsistencyMinHistoryWeeks) return null;

  final weeks = history < kConsistencyWeeks ? history : kConsistencyWeeks;
  final windowStart = DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - 7 * weeks,
  );
  final lastWeekStart = DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - 7,
  );
  var total = 0;
  var lastWeek = 0;
  for (final day in days) {
    if (day.isBefore(windowStart) || !day.isBefore(currentWeekStart)) continue;
    total++;
    if (!day.isBefore(lastWeekStart)) lastWeek++;
  }
  if (lastWeek < kConsistencyMinWeekSessions) return null;
  if (lastWeek * weeks < total + weeks) return null;
  return ConsistencyResult(
    lastWeekSessions: lastWeek,
    weeks: weeks,
    totalSessions: total,
  );
}

/// The time since the last session and the longest gap before it.
class TrainingGapResult {
  const TrainingGapResult({required this.days, required this.longestBefore});

  /// Days since the last session day.
  final int days;

  /// The longest gap between two session days in the window.
  final int longestBefore;
}

/// The Training Gap for [sessionStarts] at [now], or null (D-17801).
///
/// Speaks when at least [kConsistencyMinHistoryWeeks] completed weeks of
/// history exist, the last session day is at least [kTrainingGapMinDays] days
/// ago, the last [kTrainingGapWindowDays] days hold at least
/// [kTrainingGapMinSessionDays] session days, and the gap is longer than every
/// gap between two of those session days.
TrainingGapResult? trainingGap({
  required List<DateTime> sessionStarts,
  required DateTime now,
  required String startOfWeek,
}) {
  final today = _localDay(now);
  final days =
      {
        for (final start in sessionStarts) _localDay(start),
      }.where((day) => !day.isAfter(today)).toList()
        ..sort();
  if (days.isEmpty) return null;

  final currentWeekStart = OmniDateUtils.startOfWeek(
    today,
    startOfWeek: startOfWeek,
  );
  if (_completedHistoryWeeks(days, currentWeekStart, startOfWeek) <
      kConsistencyMinHistoryWeeks) {
    return null;
  }

  final gap = _daysApart(days.last, today);
  if (gap < kTrainingGapMinDays) return null;

  final windowStart = DateTime(
    today.year,
    today.month,
    today.day - kTrainingGapWindowDays,
  );
  final inWindow = days.where((day) => !day.isBefore(windowStart)).toList();
  if (inWindow.length < kTrainingGapMinSessionDays) return null;

  var longest = 0;
  for (var i = 1; i < inWindow.length; i++) {
    final apart = _daysApart(inWindow[i - 1], inWindow[i]);
    if (apart > longest) longest = apart;
  }
  if (gap <= longest) return null;
  return TrainingGapResult(days: gap, longestBefore: longest);
}

String _figure(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// The observation on the Consistency card (D-17801).
String consistencyObservation(ConsistencyResult result) =>
    'Last week you logged ${result.lastWeekSessions} sessions, above your '
    'usual ${_figure(result.average)} a week over the last ${result.weeks} '
    'weeks.';

/// The observation on the Training Gap card (D-17801).
String trainingGapObservation(TrainingGapResult result) =>
    'No session in ${result.days} days, longer than any gap in your last '
    '$kConsistencyWeeks weeks (the longest was ${result.longestBefore} '
    '${result.longestBefore == 1 ? 'day' : 'days'}).';
