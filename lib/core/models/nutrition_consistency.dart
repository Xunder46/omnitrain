// Stats PR 8a — the shared nutrition week-block foundation (D-1401).
//
// Pure Dart: the anchor day and the logged days are parameters, so there is no
// clock here, no repository, no service and no Flutter. The rule both the Fuel
// vs Load and the Protein Consistency signals read lives on top of this file.

/// The number of local calendar days in a week block (D-1404).
const int kWeekDays = 7;

/// The smallest number of logged days a week block needs before it counts as
/// consistent (D-1404). The boundary is inclusive: exactly five passes.
const int kConsistentWeekMinLoggedDays = 5;

/// The local-midnight starts of the [weeks] consecutive 7-day blocks ending
/// with the block that contains [anchorDay], oldest first (D-1404).
///
/// The starts abut — each is exactly seven calendar days after the one before
/// it — and never overlap. The arithmetic is calendar-based
/// (`DateTime(y, m, d − n)`), never a [Duration], so a DST transition cannot
/// shift a boundary.
List<DateTime> weekBlockStarts({
  required DateTime anchorDay,
  required int weeks,
}) {
  final anchor = _localDay(anchorDay);
  final starts = <DateTime>[];
  for (var i = 0; i < weeks; i++) {
    starts.add(_addDays(anchor, -(kWeekDays - 1) - i * kWeekDays));
  }
  return starts.reversed.toList();
}

/// How many distinct local calendar days in [loggedDays] fall inside the block
/// that starts at [blockStart] (D-1403, D-1404).
///
/// A day with more than one row counts once; a day outside the block's seven
/// days counts not at all.
int loggedDaysInWeek({
  required DateTime blockStart,
  required Iterable<DateTime> loggedDays,
}) {
  final start = _localDay(blockStart);
  final end = _addDays(start, kWeekDays - 1);
  final distinct = <DateTime>{};
  for (final day in loggedDays) {
    final local = _localDay(day);
    if (local.isBefore(start) || local.isAfter(end)) continue;
    distinct.add(local);
  }
  return distinct.length;
}

/// Whether the block starting at [blockStart] holds at least
/// [kConsistentWeekMinLoggedDays] logged days (D-1404).
bool isConsistentWeek({
  required DateTime blockStart,
  required Iterable<DateTime> loggedDays,
}) =>
    loggedDaysInWeek(blockStart: blockStart, loggedDays: loggedDays) >=
    kConsistentWeekMinLoggedDays;

/// The mean of [values], or null when there is no value at all (D-1409).
///
/// The caller passes one value per logged day, so the divisor is the logged-day
/// count and never the window length. An empty series is absent, never zero.
double? loggedDayMean(Iterable<double> values) {
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    total += value;
    count++;
  }
  if (count == 0) return null;
  return total / count;
}

/// [t]'s local calendar day at midnight.
DateTime _localDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// [day] shifted by [days] calendar days, so a month or year end rolls over.
DateTime _addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
