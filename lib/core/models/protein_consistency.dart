// Stats PR 8b — the Protein Consistency caution rule and its copy
// (D-1502…D-1517).
//
// The rule compares the average protein of the last two weeks with the user's
// own per-day target, or — with no target — with their usual level over the
// consistent weeks before the window. It is pure Dart: `now` is a parameter,
// so there is no clock here, no repository, no service and no Flutter. The
// period payloads, the per-day series and the bodyweight are the caller's; the
// adapter reads them from `StatsProgressService` (D-1519).

import '../utils/food_helpers.dart';
import 'nutrition_consistency.dart';

/// The window the rule reads, in local calendar days (D-1502).
const int kProteinConsistencyWindowDays = 14;

/// The smallest number of logged days the window needs (D-1504). The boundary
/// is inclusive: exactly ten passes.
const int kProteinConsistencyMinLoggedDays = 10;

/// The shortfall the card needs, as a percentage below the comparison
/// (D-1508). The boundary is inclusive: exactly 15% below fires.
const int kProteinConsistencyShortfallPercent = 15;

/// The smallest number of completed resistance sessions the window needs
/// (D-1510). The boundary is inclusive: exactly two passes.
const int kProteinConsistencyMinResistanceSessions = 2;

/// The smallest number of consistent baseline blocks the own-baseline
/// comparison needs (D-1509).
const int kProteinConsistencyMinBaselineWeeks = 2;

/// The number of 7-day blocks the own baseline reads (D-1509).
const int kProteinConsistencyBaselineWeeks = 8;

/// The commonly cited strength-training guidance, in grams per kilogram of
/// bodyweight (D-1515). Written as a fraction so this definition file holds no
/// decimal literal of its own (S-2213).
const double kProteinGuidancePerKg = 8 / 5;

/// The signal's priority, below Fuel vs Load (D-1517).
const int kProteinConsistencyPriority = 200;

/// One logged day as the rule sees it (D-1503).
///
/// [day] is the local calendar day and [protein] that day's own protein total.
/// A day with no logged food is absent from the list, never present with a
/// zero.
class ProteinDay {
  const ProteinDay({required this.day, required this.protein});

  final DateTime day;
  final double protein;
}

/// Which comparison the card made (D-1506).
enum ProteinComparisonMode { target, ownBaseline }

/// The rule's result (D-1507, D-1508, D-1512, D-1513).
class ProteinConsistency {
  const ProteinConsistency({
    required this.mode,
    required this.average,
    required this.comparisonMean,
    required this.shortfallPercent,
    required this.perKg,
  });

  /// The comparison the card made.
  final ProteinComparisonMode mode;

  /// The window's logged-days-only protein average.
  final double average;

  /// The figure the average was compared with: the mean per-day stored target
  /// in target mode, or the usual level in own-baseline mode.
  final double comparisonMean;

  /// How far below [comparisonMean] the average is, rounded to a whole
  /// percentage point. Only the target-mode observation renders it (D-1512).
  final int shortfallPercent;

  /// The average per kilogram of bodyweight, rounded to one decimal, or null
  /// when no bodyweight is on file (D-1511, D-1514).
  final double? perKg;
}

/// The card's copy: the observation and the suggestion (D-1512…D-1515).
class ProteinConsistencyCopy {
  const ProteinConsistencyCopy({required this.observation, this.suggestion});

  final String observation;

  /// Null when the card carries no suggestion at all (D-1515).
  final String? suggestion;
}

/// The pooled own baseline: how many of the eight blocks are consistent and
/// the total and count of their logged days (D-1509).
class ProteinBaseline {
  const ProteinBaseline({
    required this.consistentBlocks,
    required this.total,
    required this.days,
  });

  /// The number of the eight blocks with at least
  /// [kConsistentWeekMinLoggedDays] logged days.
  final int consistentBlocks;

  /// The sum of the protein of every logged day in those blocks.
  final double total;

  /// How many logged days that sum covers.
  final int days;

  /// The pooled mean, or null when no consistent block holds a logged day.
  double? get mean => days == 0 ? null : total / days;
}

/// Whether the window holds at least [kProteinConsistencyMinLoggedDays]
/// logged days (D-1504).
bool proteinConsistencyGate({required Iterable<ProteinDay> recentDays}) =>
    recentDays.length >= kProteinConsistencyMinLoggedDays;

/// Whether every logged day in the window carries a positive stored protein
/// target, which selects the target comparison (D-1506).
///
/// A single logged day with a zero or missing target selects the own-baseline
/// comparison instead; there is no third mode.
bool proteinConsistencyTargetMode({
  required Iterable<ProteinDay> recentDays,
  required Map<DateTime, double> proteinTargets,
}) {
  var any = false;
  for (final entry in recentDays) {
    any = true;
    final target = proteinTargets[_midnight(entry.day)];
    if (target == null || target <= 0) return false;
  }
  return any;
}

/// The eight 7-day blocks that abut the window, pooled over their logged days
/// (D-1509).
///
/// The blocks are the [kProteinConsistencyBaselineWeeks] blocks ending with
/// the one that ends the day before the window's first day, so they abut the
/// window with no gap and no overlap. Only blocks with at least
/// [kConsistentWeekMinLoggedDays] logged days contribute, and their logged
/// days are pooled — the mean is over all of them, not the mean of the block
/// means. The baseline is never widened, never shortened, and no day is ever
/// zero-filled.
ProteinBaseline proteinBaselinePool({
  required DateTime now,
  required Iterable<ProteinDay> baselineDays,
}) {
  final windowStart = _plusDays(
    _midnight(now),
    -(kProteinConsistencyWindowDays - 1),
  );
  final starts = weekBlockStarts(
    anchorDay: _plusDays(windowStart, -1),
    weeks: kProteinConsistencyBaselineWeeks,
  );
  final loggedDays = [for (final entry in baselineDays) entry.day];

  var consistentBlocks = 0;
  var total = 0.0;
  var days = 0;
  for (final start in starts) {
    if (!isConsistentWeek(blockStart: start, loggedDays: loggedDays)) continue;
    consistentBlocks++;
    final end = _plusDays(start, kWeekDays - 1);
    final seen = <DateTime>{};
    for (final entry in baselineDays) {
      final day = _midnight(entry.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      if (!seen.add(day)) continue;
      total += entry.protein;
      days++;
    }
  }
  return ProteinBaseline(
    consistentBlocks: consistentBlocks,
    total: total,
    days: days,
  );
}

/// Whether [recentTotal] is at least [kProteinConsistencyShortfallPercent]
/// below the per-day target total (D-1508).
///
/// The comparison is the exact fraction
/// `100 × recentTotal <= (100 − p) × targetSum` — equivalently
/// `20 × recentTotal <= 17 × targetSum` — never a rounded percentage.
bool proteinShortfallTestAgainstTarget({
  required double recentTotal,
  required double targetSum,
}) {
  if (targetSum <= 0) return false;
  return 100 * recentTotal <=
      (100 - kProteinConsistencyShortfallPercent) * targetSum;
}

/// Whether [recentTotal] is at least [kProteinConsistencyShortfallPercent]
/// below the usual level (D-1508).
///
/// Both sides are the logged-days-only means, so the comparison is the exact
/// fraction
/// `100 × recentTotal × usualDays <= (100 − p) × usualTotal × recentDays` —
/// equivalently `20 × recentTotal × usualDays <= 17 × usualTotal × recentDays`
/// — never a rounded percentage.
bool proteinShortfallTestAgainstBaseline({
  required double recentTotal,
  required int recentDays,
  required double usualTotal,
  required int usualDays,
}) {
  if (recentDays <= 0 || usualDays <= 0 || usualTotal <= 0) return false;
  return 100 * recentTotal * usualDays <=
      (100 - kProteinConsistencyShortfallPercent) * usualTotal * recentDays;
}

/// The rule over the window ending with [now]'s local day, or null when it
/// abstains (D-1502…D-1510).
///
/// [recentDays] is the window's logged days; [proteinTargets] the per-day
/// stored protein targets keyed by local day; [resistanceSessions] the count
/// of completed sessions in the window holding at least one resistance effort;
/// [baselineDays] the logged days of the eight blocks before the window; and
/// [bodyWeightKg] the latest bodyweight in kilograms, or null.
///
/// Protein above the comparison never produces a card: the rule is
/// one-directional (D-1508).
ProteinConsistency? proteinConsistency({
  required DateTime now,
  required Iterable<ProteinDay> recentDays,
  required Map<DateTime, double> proteinTargets,
  required int resistanceSessions,
  required Iterable<ProteinDay> baselineDays,
  double? bodyWeightKg,
}) {
  final anchor = _midnight(now);
  final windowStart = _plusDays(anchor, -(kProteinConsistencyWindowDays - 1));
  final window = <ProteinDay>[];
  for (final entry in recentDays) {
    final day = _midnight(entry.day);
    if (day.isBefore(windowStart) || day.isAfter(anchor)) continue;
    window.add(ProteinDay(day: day, protein: entry.protein));
  }

  if (!proteinConsistencyGate(recentDays: window)) return null;
  if (resistanceSessions < kProteinConsistencyMinResistanceSessions) {
    return null;
  }

  var recentTotal = 0.0;
  for (final entry in window) {
    recentTotal += entry.protein;
  }
  final recentLoggedDays = window.length;
  final average = recentTotal / recentLoggedDays;

  final mode =
      proteinConsistencyTargetMode(
        recentDays: window,
        proteinTargets: proteinTargets,
      )
      ? ProteinComparisonMode.target
      : ProteinComparisonMode.ownBaseline;

  final double comparisonMean;
  if (mode == ProteinComparisonMode.target) {
    var targetSum = 0.0;
    for (final entry in window) {
      targetSum += proteinTargets[entry.day]!;
    }
    if (!proteinShortfallTestAgainstTarget(
      recentTotal: recentTotal,
      targetSum: targetSum,
    )) {
      return null;
    }
    comparisonMean = targetSum / recentLoggedDays;
  } else {
    final baseline = proteinBaselinePool(now: now, baselineDays: baselineDays);
    if (baseline.consistentBlocks < kProteinConsistencyMinBaselineWeeks) {
      return null;
    }
    final usualMean = baseline.mean;
    if (usualMean == null) return null;
    if (!proteinShortfallTestAgainstBaseline(
      recentTotal: recentTotal,
      recentDays: recentLoggedDays,
      usualTotal: baseline.total,
      usualDays: baseline.days,
    )) {
      return null;
    }
    comparisonMean = usualMean;
  }

  return ProteinConsistency(
    mode: mode,
    average: average,
    comparisonMean: comparisonMean,
    shortfallPercent: ((1 - average / comparisonMean) * 100).round(),
    perKg: bodyWeightKg != null && bodyWeightKg > 0
        ? (average / bodyWeightKg * 10).round() / 10
        : null,
  );
}

/// The card's copy for [result] (D-1512…D-1515).
///
/// The observation names the average and the span — derived from
/// [kProteinConsistencyWindowDays], never written as a literal — and, in
/// target mode, the deficit and the target; in own-baseline mode it names the
/// usual level instead and carries no percentage. The per-kilogram figure
/// rides the observation in both modes when a bodyweight is on file. The
/// suggestion is the pack's verbatim sentence, or null when there is neither a
/// target nor a bodyweight.
ProteinConsistencyCopy proteinConsistencyCopy(ProteinConsistency result) {
  final average = formatGrams(result.average.roundToDouble());
  final comparison = formatGrams(result.comparisonMean.roundToDouble());
  final perKg = result.perKg == null
      ? ''
      : ' (${result.perKg!.toStringAsFixed(1)} g/kg)';
  final span = kProteinConsistencyWindowDays ~/ 7;

  final tail = result.mode == ProteinComparisonMode.target
      ? 'about ${result.shortfallPercent}% under your $comparison g target.'
      : 'down from your usual $comparison g.';

  final String? suggestion;
  if (result.mode == ProteinComparisonMode.target) {
    suggestion = 'Bringing protein back toward your target is one option.';
  } else if (result.perKg != null) {
    suggestion =
        'Commonly cited guidance for strength training is around '
        '$kProteinGuidancePerKg g/kg of bodyweight.';
  } else {
    suggestion = null;
  }

  return ProteinConsistencyCopy(
    observation:
        'Protein has averaged $average g/day$perKg over the last $span weeks, '
        '$tail',
    suggestion: suggestion,
  );
}

/// [t]'s local calendar day at midnight.
DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

/// [day] shifted by [days] calendar days, so a month or year end rolls over.
DateTime _plusDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
