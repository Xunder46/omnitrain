// Stats PR 8a — the Fuel vs Load caution rule and its copy (D-1405…D-1415).
//
// The rule compares the load of the last three weeks with the three weeks
// before it and fires only when the load rose while the logged-days-only
// average intake did not. It is pure Dart: `now` is a parameter, so there is no
// clock here, no repository, no service and no Flutter. The period payloads and
// the per-day intake series are the caller's; the adapter reads them from
// `StatsProgressService` (D-1418).

import 'nutrition_consistency.dart';
import 'training_load.dart';

/// The span of each of the two periods the rule compares, in local calendar
/// days (D-1405). Each period is three 7-day blocks.
const int kFuelVsLoadWindowDays = 21;

/// The load rise the card needs (D-1408). The boundary is inclusive: exactly
/// +20% fires.
const int kFuelVsLoadLoadRisePercent = 20;

/// The intake rise the card tolerates (D-1410). The boundary is inclusive:
/// exactly +5% still fires, +6% does not.
const int kFuelVsLoadIntakeTolerancePercent = 5;

/// The signal's priority, below Modality Mix Shift and above Protein
/// Consistency (D-1415).
const int kFuelVsLoadPriority = 300;

/// One logged day as the rule sees it (D-1403).
///
/// [day] is the local calendar day and [intake] that day's own rounded intake
/// total. A day with no logged food is absent from the list, never present with
/// a zero.
class LoggedDay {
  const LoggedDay({required this.day, required this.intake});

  final DateTime day;
  final double intake;
}

/// The rule's result: the load rise the card reports (D-1412).
class FuelVsLoad {
  const FuelVsLoad({required this.loadRisePercent});

  final int loadRisePercent;
}

/// The card's copy: the observation and the suggestion.
class FuelVsLoadCopy {
  const FuelVsLoadCopy({required this.observation, required this.suggestion});

  final String observation;
  final String suggestion;
}

/// Whether both periods are the Mix layer's load measure (D-1407).
///
/// A period the layer measures in time is not "the Mix layer showing load", so
/// the card abstains.
bool fuelVsLoadMeasureGate({
  required MixMeasure recentMeasure,
  required MixMeasure priorMeasure,
}) => recentMeasure == MixMeasure.load && priorMeasure == MixMeasure.load;

/// Whether all six blocks — the three recent and the three prior — are
/// consistent (D-1406).
///
/// The block starts are the six 7-day blocks ending with the one that contains
/// [now]'s local day. One block below [kConsistentWeekMinLoggedDays] logged days
/// abstains whatever the other figures say; the window is never widened and no
/// day is zero-filled.
bool fuelVsLoadGate({
  required DateTime now,
  required Iterable<LoggedDay> loggedDays,
}) {
  final anchor = DateTime(now.year, now.month, now.day);
  final days = loggedDays.map((d) => d.day);
  for (final start in weekBlockStarts(anchorDay: anchor, weeks: 6)) {
    if (!isConsistentWeek(blockStart: start, loggedDays: days)) return false;
  }
  return true;
}

/// Whether the load rose by at least [kFuelVsLoadLoadRisePercent] (D-1408).
///
/// The comparison is the exact fraction `100 × recentLoad >= (100 + rise) ×
/// priorLoad`, never a rounded percentage. A prior load of zero abstains.
bool fuelVsLoadLoadTest({
  required double recentLoad,
  required double priorLoad,
}) {
  if (priorLoad <= 0) return false;
  return 100 * recentLoad >= (100 + kFuelVsLoadLoadRisePercent) * priorLoad;
}

/// Whether the average intake did not rise beyond
/// [kFuelVsLoadIntakeTolerancePercent] (D-1410).
///
/// The two averages are the logged-days-only means, so the comparison is the
/// exact fraction `100 × recentTotal × priorDays <= (100 + tolerance) ×
/// priorTotal × recentDays` (D-1409). Either period with no logged day or no
/// prior intake abstains.
bool fuelVsLoadIntakeTest({
  required double recentIntakeTotal,
  required int recentLoggedDays,
  required double priorIntakeTotal,
  required int priorLoggedDays,
}) {
  if (recentLoggedDays <= 0 || priorLoggedDays <= 0) return false;
  if (priorIntakeTotal <= 0) return false;
  return 100 * recentIntakeTotal * priorLoggedDays <=
      (100 + kFuelVsLoadIntakeTolerancePercent) *
          priorIntakeTotal *
          recentLoggedDays;
}

/// The rule over [loggedDays] at [now], or null when it abstains
/// (D-1405–D-1411).
///
/// The recent period is the [kFuelVsLoadWindowDays] local calendar days ending
/// with [now]'s day; the prior period is the same span immediately before it,
/// so the two abut with no gap and no overlap (D-1405). A load that fell never
/// fires, whatever the intake did (D-1411).
FuelVsLoad? fuelVsLoad({
  required DateTime now,
  required MixMeasure recentMeasure,
  required MixMeasure priorMeasure,
  required double recentLoad,
  required double priorLoad,
  required List<LoggedDay> loggedDays,
}) {
  if (!fuelVsLoadMeasureGate(
    recentMeasure: recentMeasure,
    priorMeasure: priorMeasure,
  )) {
    return null;
  }
  if (!fuelVsLoadGate(now: now, loggedDays: loggedDays)) return null;
  if (!fuelVsLoadLoadTest(recentLoad: recentLoad, priorLoad: priorLoad)) {
    return null;
  }

  final anchor = DateTime(now.year, now.month, now.day);
  final recentStart = DateTime(
    anchor.year,
    anchor.month,
    anchor.day - (kFuelVsLoadWindowDays - 1),
  );
  final priorStart = DateTime(
    anchor.year,
    anchor.month,
    anchor.day - (2 * kFuelVsLoadWindowDays - 1),
  );

  var recentTotal = 0.0;
  var recentDays = 0;
  var priorTotal = 0.0;
  var priorDays = 0;
  for (final logged in loggedDays) {
    final day = DateTime(logged.day.year, logged.day.month, logged.day.day);
    if (!day.isBefore(recentStart) && !day.isAfter(anchor)) {
      recentTotal += logged.intake;
      recentDays++;
    } else if (!day.isBefore(priorStart) && day.isBefore(recentStart)) {
      priorTotal += logged.intake;
      priorDays++;
    }
  }

  if (!fuelVsLoadIntakeTest(
    recentIntakeTotal: recentTotal,
    recentLoggedDays: recentDays,
    priorIntakeTotal: priorTotal,
    priorLoggedDays: priorDays,
  )) {
    return null;
  }

  return FuelVsLoad(
    loadRisePercent: ((recentLoad / priorLoad - 1) * 100).round(),
  );
}

/// The card's copy for [result] (D-1412, D-1413).
///
/// The observation names the load percentage and the span — derived from
/// [kFuelVsLoadWindowDays], never written as a literal — and no intake figure
/// at all. The suggestion is the pack's verbatim sentence.
FuelVsLoadCopy fuelVsLoadCopy(FuelVsLoad result) => FuelVsLoadCopy(
  observation:
      'Training load is up ${result.loadRisePercent}% over the last '
      '${kFuelVsLoadWindowDays ~/ 7} weeks; your average daily intake has not '
      'risen with it.',
  suggestion: 'Worth checking that intake is keeping up with training.',
);
