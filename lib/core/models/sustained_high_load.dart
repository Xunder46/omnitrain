// Stats PR 9a — the Sustained High Load caution rule and its copy
// (D-1701…D-1714).
//
// The rule walks the completed calendar weeks and finds the longest run of
// consecutive weeks each at least 110% of the user's usual load, where the
// usual is the twelve weeks immediately before the run. It is pure Dart: the
// week list and the Mix gate are parameters, so there is no clock here, no
// repository, no service and no Flutter. The weeks come from
// `StatsProgressService.weeklyLoads` and the gate from the Mix layer; the
// adapter reads them (D-1703, D-1709).

import 'training_load.dart';

/// The signal's priority, below Protein Consistency and above Cardio
/// Efficiency Drift (D-1713).
const int kSustainedHighLoadPriority = 100;

/// The run length the card needs, in completed weeks (D-1708). The boundary is
/// inclusive: exactly five weeks shows the card.
const int kSustainedHighLoadMinStreakWeeks = 5;

/// The rated weeks a candidate's twelve-week baseline needs (D-1706). The
/// boundary is inclusive: exactly eight passes.
const int kSustainedHighLoadMinRatedWeeks = 8;

/// The load a week must reach against its usual to be a higher-load week
/// (D-1707). The boundary is inclusive: exactly 110% is higher.
const int kSustainedHighLoadHigherPercent = 110;

/// The load a week must fall to against the usual to be an easier week
/// (D-1707, D-1710). The boundary is inclusive: exactly 80% is easier.
const int kSustainedHighLoadEasierPercent = 80;

/// The gaps between consecutive easier weeks the history fact needs (D-1711).
const int kSustainedHighLoadMinEasierGaps = 2;

/// The shortest gap the history fact accepts, in weeks (D-1711).
const int kSustainedHighLoadGapMinWeeks = 3;

/// The longest gap the history fact accepts, in weeks (D-1711).
const int kSustainedHighLoadGapMaxWeeks = 5;

/// One candidate's twelve-week baseline (D-1705, D-1706).
class SustainedHighLoadBaseline {
  const SustainedHighLoadBaseline({
    required this.usualLoadMinutes,
    required this.ratedWeeks,
  });

  /// The baseline's usual: its summed load ÷ the twelve weeks, an empty week
  /// counting as zero.
  final double usualLoadMinutes;

  /// How many of the twelve baseline weeks carry a rated session.
  final int ratedWeeks;
}

/// The winning run (D-1708).
class SustainedHighLoadStreak {
  const SustainedHighLoadStreak({
    required this.firstWeekStart,
    required this.weekCount,
    required this.usualLoadMinutes,
    required this.ratedBaselineWeeks,
  });

  /// The run's first week's start, or null when no candidate qualifies.
  final DateTime? firstWeekStart;

  /// The run's length in weeks, 0 when no candidate qualifies.
  final int weekCount;

  /// The winning candidate's own usual load, 0 when none qualifies.
  final double usualLoadMinutes;

  /// The winning candidate's baseline rated-week count, 0 when none qualifies.
  final int ratedBaselineWeeks;
}

/// The composed rule's result (D-1708, D-1711).
class SustainedHighLoad {
  const SustainedHighLoad({
    required this.streakWeeks,
    required this.easierGapWeeks,
  });

  /// The streak's length in weeks.
  final int streakWeeks;

  /// The median interval between the earlier easier weeks, or null when the
  /// history does not show the habit (D-1711).
  final int? easierGapWeeks;
}

/// The card's copy: the observation and the suggestion (D-1712).
class SustainedHighLoadCopy {
  const SustainedHighLoadCopy({
    required this.observation,
    required this.suggestion,
  });

  final String observation;
  final String suggestion;
}

/// One candidate's baseline: the [kTrainingLoadBaselineWeeks] weeks immediately
/// before [beforeIndex], pooled (D-1705).
///
/// The baseline lies strictly before the candidate, so a run can never inflate
/// its own baseline. The usual is the twelve weeks' sum ÷ twelve — an empty
/// week counts as zero, never the mean of the rated weeks only. Returns null
/// when fewer than twelve weeks precede [beforeIndex].
SustainedHighLoadBaseline? sustainedHighLoadBaseline({
  required List<WeeklyLoad> weeks,
  required int beforeIndex,
}) {
  if (beforeIndex < kTrainingLoadBaselineWeeks) return null;
  var total = 0.0;
  var rated = 0;
  for (var i = beforeIndex - kTrainingLoadBaselineWeeks; i < beforeIndex; i++) {
    total += weeks[i].loadMinutes;
    if (weeks[i].hasRatedSession) rated++;
  }
  return SustainedHighLoadBaseline(
    usualLoadMinutes: total / kTrainingLoadBaselineWeeks,
    ratedWeeks: rated,
  );
}

/// Whether [week] is a higher-load week against [usual] (D-1707).
///
/// The comparison is the exact cross-multiplication
/// `loadMinutes × 100 >= usual × kSustainedHighLoadHigherPercent`, never a
/// rounded percentage.
bool sustainedHighLoadHigherWeek({
  required WeeklyLoad week,
  required double usual,
}) => week.loadMinutes * 100 >= usual * kSustainedHighLoadHigherPercent;

/// The largest qualifying candidate (D-1705…D-1708).
///
/// [weeks] is the completed weeks, oldest first. Candidate `m` is the last `m`
/// weeks; it qualifies when its own twelve-week baseline meets the rated floor
/// and every one of its weeks is higher-load against that baseline's usual. The
/// streak is the largest qualifying `m`, 0 when none qualifies. The result's
/// usual and rated count are the winning candidate's own, so the copy and the
/// history fact read the same usual.
SustainedHighLoadStreak sustainedHighLoadStreak({
  required List<WeeklyLoad> weeks,
}) {
  final n = weeks.length;
  var best = 0;
  SustainedHighLoadBaseline? bestBaseline;
  for (var m = 1; m <= n - kTrainingLoadBaselineWeeks; m++) {
    final beforeIndex = n - m;
    final baseline = sustainedHighLoadBaseline(
      weeks: weeks,
      beforeIndex: beforeIndex,
    );
    if (baseline == null) continue;
    if (baseline.ratedWeeks < kSustainedHighLoadMinRatedWeeks) continue;
    var qualifies = true;
    for (var i = beforeIndex; i < n; i++) {
      if (!sustainedHighLoadHigherWeek(
        week: weeks[i],
        usual: baseline.usualLoadMinutes,
      )) {
        qualifies = false;
        break;
      }
    }
    if (!qualifies) continue;
    best = m;
    bestBaseline = baseline;
  }
  if (best == 0 || bestBaseline == null) {
    return const SustainedHighLoadStreak(
      firstWeekStart: null,
      weekCount: 0,
      usualLoadMinutes: 0,
      ratedBaselineWeeks: 0,
    );
  }
  return SustainedHighLoadStreak(
    firstWeekStart: weeks[n - best].weekStart,
    weekCount: best,
    usualLoadMinutes: bestBaseline.usualLoadMinutes,
    ratedBaselineWeeks: bestBaseline.ratedWeeks,
  );
}

/// The median interval between the easier weeks strictly before [beforeIndex],
/// or null when the history does not show the habit (D-1710, D-1711).
///
/// An easier week there is a week at or below
/// [kSustainedHighLoadEasierPercent] of [usual], compared exactly as
/// `loadMinutes × 100 <= usual × 80`; an empty week is an easier week. The gaps
/// are the differences between consecutive easier weeks' indices, oldest first.
/// The fact needs at least [kSustainedHighLoadMinEasierGaps] gaps, every one
/// within [kSustainedHighLoadGapMinWeeks]..[kSustainedHighLoadGapMaxWeeks], and
/// reports the median — the sorted list's element at index `(n - 1) ~/ 2`.
int? sustainedHighLoadEasierGapWeeks({
  required List<WeeklyLoad> weeks,
  required int beforeIndex,
  required double usual,
}) {
  final easier = <int>[];
  for (var i = 0; i < beforeIndex && i < weeks.length; i++) {
    if (weeks[i].loadMinutes * 100 <= usual * kSustainedHighLoadEasierPercent) {
      easier.add(i);
    }
  }
  if (easier.length < kSustainedHighLoadMinEasierGaps + 1) return null;
  final gaps = <int>[
    for (var i = 1; i < easier.length; i++) easier[i] - easier[i - 1],
  ];
  for (final gap in gaps) {
    if (gap < kSustainedHighLoadGapMinWeeks ||
        gap > kSustainedHighLoadGapMaxWeeks) {
      return null;
    }
  }
  gaps.sort();
  return gaps[(gaps.length - 1) ~/ 2];
}

/// The composed rule (D-1708…D-1711), or null when the card does not fire.
///
/// [mixShowsLoad] is the Mix layer's answer for the streak's own period
/// (D-1709): a period measured in time abstains. The rule applies the floor
/// itself, so a run shorter than [kSustainedHighLoadMinStreakWeeks] never fires
/// whatever the gate says.
SustainedHighLoad? sustainedHighLoad({
  required List<WeeklyLoad> weeks,
  required bool mixShowsLoad,
}) {
  final streak = sustainedHighLoadStreak(weeks: weeks);
  if (streak.weekCount < kSustainedHighLoadMinStreakWeeks) return null;
  if (!mixShowsLoad) return null;
  return SustainedHighLoad(
    streakWeeks: streak.weekCount,
    easierGapWeeks: sustainedHighLoadEasierGapWeeks(
      weeks: weeks,
      beforeIndex: weeks.length - streak.weekCount,
      usual: streak.usualLoadMinutes,
    ),
  );
}

/// The card's copy for [result] (D-1712).
///
/// The observation names the streak count; the second sentence is present only
/// when the history fact fired. The suggestion is the pack's sentence with its
/// unobservable causal clause dropped.
SustainedHighLoadCopy sustainedHighLoadCopy(SustainedHighLoad result) {
  final observation = StringBuffer(
    "You've had ${result.streakWeeks} consecutive weeks above your usual "
    'training load, with no easier week.',
  );
  final gap = result.easierGapWeeks;
  if (gap != null) {
    observation.write(
      ' Earlier in your history, you usually had an easier week every '
      '$gap weeks.',
    );
  }
  return SustainedHighLoadCopy(
    observation: observation.toString(),
    suggestion: 'An easier week is one option.',
  );
}
