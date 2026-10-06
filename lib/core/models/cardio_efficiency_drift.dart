// Stats PR 9b — the Cardio Efficiency Drift caution rule and its copy
// (D-1801…D-1817).
//
// The rule compares one cardio exercise's measured pace at the same average
// heart rate over comparable-duration efforts in two windows: the last
// fourteen local days, and the fourteen days from forty-two days ago up to
// twenty-eight days ago. It is pure Dart: `now` and the eligible efforts are
// parameters, so there is no clock here, no repository, no service and no
// Flutter. The efforts come from `StatsProgressService.cardioEfforts` and the
// lifting figures from the Mix layer; the adapter reads them (D-1802, D-1807).

import 'training_load.dart';

/// The signal's priority, below every other caution (D-1809).
const int kCardioEfficiencyDriftPriority = 50;

/// The recent window's span, in local calendar days (D-1801). The boundary is
/// inclusive: day(13) 00:00 is recent, today is recent.
const int kCardioEfficiencyRecentDays = 14;

/// The reference window's far edge, in weeks (D-1801): day(42) 00:00.
const int kCardioEfficiencyReferenceWeeksFrom = 6;

/// The reference window's near edge, in weeks (D-1801): day(28) 00:00.
const int kCardioEfficiencyReferenceWeeksTo = 4;

/// The duration tolerance that keeps two efforts comparable (D-1804). The
/// boundary is inclusive: exactly +10% still groups.
const int kCardioEfficiencyDurationTolerancePercent = 10;

/// The efforts each window needs before a group qualifies (D-1804). The
/// boundary is inclusive: exactly three passes.
const int kCardioEfficiencyMinEffortsPerWindow = 3;

/// The efficiency drop the card needs (D-1805). The boundary is inclusive:
/// exactly 5% worse fires.
const int kCardioEfficiencyDriftPercent = 5;

/// The resistance-load rise the second sentence needs (D-1807). The boundary
/// is inclusive: exactly +15% fires.
const int kCardioEfficiencyLiftLoadRisePercent = 15;

/// The period the lifting sentence reads, in local calendar days (D-1807).
const int kCardioEfficiencyLiftLoadWindowDays = 28;

/// One eligible cardio effort as the rule sees it (D-1802).
///
/// [start] is the instance's own start, [durationSecs] its measured duration,
/// [distanceMetres] the paired, non-estimated distance and [avgHeartRateBpm]
/// the instance summary's average. Eligibility — a finished timed instance
/// with a measured distance and an average heart rate — is decided by
/// `StatsProgressService.cardioEfforts`, never here.
class CardioEffort {
  const CardioEffort({
    required this.exerciseId,
    required this.exerciseName,
    required this.start,
    required this.durationSecs,
    required this.distanceMetres,
    required this.avgHeartRateBpm,
  });

  final String exerciseId;
  final String exerciseName;
  final DateTime start;
  final int durationSecs;
  final double distanceMetres;
  final double avgHeartRateBpm;
}

/// The two windows, as local-midnight boundaries (D-1801).
///
/// [recentStart] is inclusive and [recentEnd] exclusive; the same for the
/// reference pair. The gap between them holds no effort.
class CardioEfficiencyWindows {
  const CardioEfficiencyWindows({
    required this.recentStart,
    required this.recentEnd,
    required this.referenceStart,
    required this.referenceEnd,
  });

  final DateTime recentStart;
  final DateTime recentEnd;
  final DateTime referenceStart;
  final DateTime referenceEnd;
}

/// One comparable-duration group of one exercise (D-1804).
class CardioEffortGroup {
  const CardioEffortGroup({required this.anchorSecs, required this.efforts});

  /// The group's shortest member's duration.
  final int anchorSecs;

  /// The group's members, all one exercise, all within ±10% of [anchorSecs].
  final List<CardioEffort> efforts;
}

/// The rule's result (D-1805…D-1807).
class CardioEfficiencyDriftResult {
  const CardioEfficiencyDriftResult({
    required this.exerciseId,
    required this.exerciseName,
    required this.anchorSecs,
    required this.driftPercent,
    required this.liftRisePercent,
  });

  final String exerciseId;
  final String exerciseName;

  /// The reported group's shortest member's duration.
  final int anchorSecs;

  /// How much worse the recent mean is, rounded to a whole percentage point.
  final int driftPercent;

  /// The resistance-load rise, or null when the second sentence is absent.
  final int? liftRisePercent;
}

/// The card's copy: the observation and the suggestion (D-1808).
class CardioEfficiencyDriftCopy {
  const CardioEfficiencyDriftCopy({
    required this.observation,
    required this.suggestion,
  });

  final String observation;
  final String suggestion;
}

/// One effort's efficiency: `distanceMetres × 60 ÷ (avgHeartRateBpm ×
/// durationSecs)` — metres per heart-rate-minute, distance per unit of
/// heart-rate exposure, larger is better (D-1803).
///
/// The arithmetic is exact on the stored values: with an average heart rate of
/// 150 and a 480-second effort the divisor is 72000, so 3000 m reads 2.5,
/// 2850 m reads 2.375 and 2400 m reads 2.0.
double cardioEfficiency(CardioEffort effort) =>
    effort.distanceMetres * 60 / (effort.avgHeartRateBpm * effort.durationSecs);

/// The two windows off [now]'s own local date (D-1801).
///
/// Built with `DateTime(y, m, d − n)` and never a [Duration], so a DST
/// transition cannot move a boundary:
///
/// - recent = `[day(kCardioEfficiencyRecentDays − 1), day(−1))` =
///   `[day(13) 00:00, tomorrow 00:00)`, the last fourteen local days, today
///   included;
/// - reference = `[day(kCardioEfficiencyReferenceWeeksFrom × 7),
///   day(kCardioEfficiencyReferenceWeeksTo × 7))` = `[day(42) 00:00,
///   day(28) 00:00)`, fourteen days from forty-two days ago up to but not
///   including twenty-eight days ago.
///
/// The lower bound is inclusive and the upper bound exclusive, so day(13)
/// 00:00 is recent, day(14) 23:59 is in the gap, day(42) 00:00 is reference
/// and day(28) 00:00 is in the gap.
CardioEfficiencyWindows cardioEfficiencyWindows(DateTime now) {
  final year = now.year;
  final month = now.month;
  final day = now.day;
  return CardioEfficiencyWindows(
    recentStart: DateTime(year, month, day - (kCardioEfficiencyRecentDays - 1)),
    recentEnd: DateTime(year, month, day + 1),
    referenceStart: DateTime(
      year,
      month,
      day - kCardioEfficiencyReferenceWeeksFrom * 7,
    ),
    referenceEnd: DateTime(
      year,
      month,
      day - kCardioEfficiencyReferenceWeeksTo * 7,
    ),
  );
}

/// The comparable-duration groups of [efforts] (D-1804).
///
/// The efforts are partitioned by exercise id — a group never holds two
/// exercises — and within one exercise sorted by duration ascending, then
/// start, then exercise id. Grouping is greedy and anchored: the shortest
/// ungrouped effort is the group's anchor, and the group is that effort plus
/// every ungrouped effort whose duration is within
/// [kCardioEfficiencyDurationTolerancePercent] of the anchor
/// (`dur × 100 <= anchor × 110`, inclusive). There is no chaining, so every
/// member is within ±10% of the anchor and a 30-minute and a 45-minute effort
/// can never share a group.
List<CardioEffortGroup> cardioEffortGroups(List<CardioEffort> efforts) {
  final byExercise = <String, List<CardioEffort>>{};
  for (final effort in efforts) {
    byExercise
        .putIfAbsent(effort.exerciseId, () => <CardioEffort>[])
        .add(effort);
  }

  final groups = <CardioEffortGroup>[];
  for (final id in byExercise.keys.toList()..sort()) {
    final list = byExercise[id]!;
    list.sort((a, b) {
      final byDuration = a.durationSecs.compareTo(b.durationSecs);
      if (byDuration != 0) return byDuration;
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.exerciseId.compareTo(b.exerciseId);
    });

    final used = List<bool>.filled(list.length, false);
    for (var i = 0; i < list.length; i++) {
      if (used[i]) continue;
      final anchor = list[i];
      used[i] = true;
      final members = <CardioEffort>[anchor];
      for (var j = i + 1; j < list.length; j++) {
        if (used[j]) continue;
        if (list[j].durationSecs * 100 <=
            anchor.durationSecs *
                (100 + kCardioEfficiencyDurationTolerancePercent)) {
          used[j] = true;
          members.add(list[j]);
        }
      }
      groups.add(
        CardioEffortGroup(anchorSecs: anchor.durationSecs, efforts: members),
      );
    }
  }
  return groups;
}

bool _inRecent(CardioEffort effort, CardioEfficiencyWindows windows) =>
    !effort.start.isBefore(windows.recentStart) &&
    effort.start.isBefore(windows.recentEnd);

bool _inReference(CardioEffort effort, CardioEfficiencyWindows windows) =>
    !effort.start.isBefore(windows.referenceStart) &&
    effort.start.isBefore(windows.referenceEnd);

double _meanEfficiency(List<CardioEffort> efforts) {
  var total = 0.0;
  for (final effort in efforts) {
    total += cardioEfficiency(effort);
  }
  return total / efforts.length;
}

/// The efficiency half of the rule (D-1801, D-1804…D-1806), or null when the
/// card does not fire.
///
/// The windows are applied first: only efforts whose start falls in the recent
/// or the reference window survive, so a gap effort (days 27 down to 14) or an
/// effort older than day 42 is ignored entirely and can never become an anchor.
/// The survivors are then partitioned and grouped by [cardioEffortGroups]. A
/// group qualifies when it holds at least
/// [kCardioEfficiencyMinEffortsPerWindow] efforts in each window; it fires when
/// `recentMean × 100 <= referenceMean × (100 − kCardioEfficiencyDriftPercent)`
/// — exactly 5% worse fires, 4% does not — and `referenceMean > 0`. The
/// reported group is the largest drift, ties broken by exercise id ascending
/// and then by the shorter anchor duration (D-1806).
CardioEfficiencyDriftResult? cardioEfficiencyDriftFor({
  required List<CardioEffort> efforts,
  required DateTime now,
}) {
  final windows = cardioEfficiencyWindows(now);
  final windowed = <CardioEffort>[
    for (final effort in efforts)
      if (_inRecent(effort, windows) || _inReference(effort, windows)) effort,
  ];

  CardioEfficiencyDriftResult? best;
  for (final group in cardioEffortGroups(windowed)) {
    final recent = <CardioEffort>[
      for (final effort in group.efforts)
        if (_inRecent(effort, windows)) effort,
    ];
    final reference = <CardioEffort>[
      for (final effort in group.efforts)
        if (_inReference(effort, windows)) effort,
    ];
    if (recent.length < kCardioEfficiencyMinEffortsPerWindow) continue;
    if (reference.length < kCardioEfficiencyMinEffortsPerWindow) continue;

    final recentMean = _meanEfficiency(recent);
    final referenceMean = _meanEfficiency(reference);
    if (referenceMean <= 0) continue;
    if (recentMean * 100 >
        referenceMean * (100 - kCardioEfficiencyDriftPercent)) {
      continue;
    }

    final first = group.efforts.first;
    best = _better(
      best,
      CardioEfficiencyDriftResult(
        exerciseId: first.exerciseId,
        exerciseName: first.exerciseName,
        anchorSecs: group.anchorSecs,
        driftPercent: ((1 - recentMean / referenceMean) * 100).round(),
        liftRisePercent: null,
      ),
    );
  }
  return best;
}

CardioEfficiencyDriftResult _better(
  CardioEfficiencyDriftResult? best,
  CardioEfficiencyDriftResult candidate,
) {
  if (best == null) return candidate;
  if (candidate.driftPercent != best.driftPercent) {
    return candidate.driftPercent > best.driftPercent ? candidate : best;
  }
  final byId = candidate.exerciseId.compareTo(best.exerciseId);
  if (byId != 0) return byId < 0 ? candidate : best;
  return candidate.anchorSecs < best.anchorSecs ? candidate : best;
}

/// The whole rule (D-1807, D-1814), or null when the efficiency drift does not
/// fire.
///
/// [liftRecentLoad] and [liftUsualLoad] are the Mix layer's summed resistance
/// measures over the last [kCardioEfficiencyLiftLoadWindowDays] days and over
/// its twelve-week baseline; [liftMeasure] names the measure that payload is
/// in. The second sentence needs `liftMeasure == MixMeasure.load`,
/// `liftUsualLoad > 0` and the per-day comparison
/// `liftRecentLoad × 84 × 100 >= liftUsualLoad × 28 × (100 +
/// kCardioEfficiencyLiftLoadRisePercent)` — exactly +15% fires. The lifting
/// figure is an addition to a card the drift already earned: a lift rise with
/// no drift shows nothing.
CardioEfficiencyDriftResult? cardioEfficiencyDrift({
  required List<CardioEffort> efforts,
  required DateTime now,
  required double liftRecentLoad,
  required double liftUsualLoad,
  required MixMeasure liftMeasure,
}) {
  final result = cardioEfficiencyDriftFor(efforts: efforts, now: now);
  if (result == null) return null;
  return CardioEfficiencyDriftResult(
    exerciseId: result.exerciseId,
    exerciseName: result.exerciseName,
    anchorSecs: result.anchorSecs,
    driftPercent: result.driftPercent,
    liftRisePercent: _liftRisePercent(
      liftRecentLoad: liftRecentLoad,
      liftUsualLoad: liftUsualLoad,
      liftMeasure: liftMeasure,
    ),
  );
}

int? _liftRisePercent({
  required double liftRecentLoad,
  required double liftUsualLoad,
  required MixMeasure liftMeasure,
}) {
  // The payload's baseline spans kTrainingLoadBaselineWeeks seven-day blocks
  // (84 days) while the period spans kCardioEfficiencyLiftLoadWindowDays
  // (28), so the two are compared per day, as exact integer arithmetic.
  const baselineDays = kTrainingLoadBaselineWeeks * 7;
  const windowDays = kCardioEfficiencyLiftLoadWindowDays;
  if (liftMeasure != MixMeasure.load) return null;
  if (liftUsualLoad <= 0) return null;
  if (liftRecentLoad * baselineDays * 100 <
      liftUsualLoad *
          windowDays *
          (100 + kCardioEfficiencyLiftLoadRisePercent)) {
    return null;
  }
  return (((liftRecentLoad * baselineDays) / (liftUsualLoad * windowDays) - 1) *
          100)
      .round();
}

/// The card's copy for [result] (D-1808).
///
/// The span is built from [kCardioEfficiencyReferenceWeeksTo] and
/// [kCardioEfficiencyReferenceWeeksFrom] (`4–6`), never written as a literal.
/// The second sentence is present only when the lifting test fired. The
/// suggestion is the pack's sentence with its unobservable causal clause
/// dropped.
CardioEfficiencyDriftCopy cardioEfficiencyDriftCopy(
  CardioEfficiencyDriftResult result,
) {
  final span =
      '$kCardioEfficiencyReferenceWeeksTo–$kCardioEfficiencyReferenceWeeksFrom';
  final observation = StringBuffer(
    'At similar durations, your ${result.exerciseName} efforts are about '
    '${result.driftPercent}% less efficient (slower pace at the same heart '
    'rate) than $span weeks ago.',
  );
  final lift = result.liftRisePercent;
  if (lift != null) {
    observation.write(
      ' Lifting load is $lift% above your usual over the same period.',
    );
  }
  return CardioEfficiencyDriftCopy(
    observation: observation.toString(),
    suggestion: 'An easier week is one option.',
  );
}
