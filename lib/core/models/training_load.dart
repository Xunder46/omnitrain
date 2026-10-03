/// Plain Dart value types and pure arithmetic for the training-load figures.
///
/// This is the single home for session load, the effort→modality rule, the
/// per-session time split, the load split, the percentage rounding and the
/// baseline period's calendar blocks (D-918). It imports no Flutter and no
/// repository, so a later signal imports these definitions rather than
/// restating them. Nothing here is persisted.
///
/// The rules are the decision-ledger entries D-901 … D-907, D-912, D-913 and
/// D-934 of
/// `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.md`.
library;

import 'exercise_metric.dart';

/// The number of weeks the Mix layer's weekly strip holds (D-917).
const int kMixStripWeeks = 8;

/// The number of 7-calendar-day blocks the load baseline spans (D-934).
const int kTrainingLoadBaselineWeeks = 12;

/// The rated baseline weeks the load measure needs before it is shown (D-908).
const int kTrainingLoadMinRatedWeeks = 4;

/// The largest share of a window's time that may be unrated for the load
/// measure to be shown; the boundary is inclusive (D-908).
const double kTrainingLoadMaxUnratedShare = 0.25;

/// Which measure the Mix layer shows: training time, or session load (D-908).
enum MixMeasure { time, load }

/// One modality's share of a bar: its measure and its rounded percentage.
///
/// [measure] is the exact figure the segment was built from — seconds in the
/// time measure, load minutes in the load measure. [percent] is the rounded
/// share; segment widths use the exact proportions, never [percent] (D-912).
class MixSegment {
  final ExerciseSection section;
  final double measure;
  final int percent;

  const MixSegment({
    required this.section,
    required this.measure,
    required this.percent,
  });
}

/// One week of the Mix layer's weekly strip (D-917).
///
/// [weekStart] is the local-midnight start of the week. [segments] is empty
/// for a week with no work — an empty week is present, never dropped.
/// [inProgress] marks the week containing `now`.
class MixWeek {
  final DateTime weekStart;
  final List<MixSegment> segments;
  final double measure;
  final bool inProgress;

  const MixWeek({
    required this.weekStart,
    required this.segments,
    required this.measure,
    required this.inProgress,
  });
}

/// The whole payload the Mix layer renders (D-916, D-917).
///
/// [measure] names the measure the bar and the strip both use; the surface
/// derives its own label from it, so the two can never disagree. [segments] is
/// the window's bar, [baselineSegments] the user's usual split, and [weeks] the
/// strip. [unratedSessionCount] and [ratedBaselineWeeks] are the two counts the
/// surface reports.
class MixLayerData {
  final MixMeasure measure;
  final List<MixSegment> segments;
  final List<MixSegment> baselineSegments;
  final int unratedSessionCount;
  final int ratedBaselineWeeks;
  final List<MixWeek> weeks;

  const MixLayerData({
    required this.measure,
    required this.segments,
    required this.baselineSegments,
    required this.unratedSessionCount,
    required this.ratedBaselineWeeks,
    required this.weeks,
  });
}

/// A session's load in minutes: its time in minutes times its rating (D-901).
///
/// [rating] is `TrainingSession.sessionFeeling` (1–5). The caller guarantees a
/// rating in that range — the stored rating's own range — and a value outside
/// it is **not** clamped here. A session with no rating has zero load and is
/// never estimated or filled in; a session with no positive time has zero load.
/// The result is accumulated as a `double` and rounded once, at display.
double sessionLoadMinutes({
  required int sessionTimeSecs,
  required int? rating,
}) {
  if (rating == null || sessionTimeSecs <= 0) return 0.0;
  return sessionTimeSecs / 60.0 * rating;
}

/// The local-midnight day of [t] (D-934).
DateTime localMidnightDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// The 12 local-midnight starts of the consecutive 7-calendar-day blocks that
/// tile `[fromDay − kTrainingLoadBaselineWeeks × 7 days, fromDay)`, oldest
/// first (D-934).
///
/// The blocks are built with `DateTime(y, m, d − n)` and never a [Duration], so
/// a DST transition cannot shift a boundary. The last block ends the instant
/// before [fromDay], so the period abuts the window with no gap and no overlap.
/// The blocks are anchored at [fromDay] itself and do not use the saved
/// start-of-week setting (D-935).
List<DateTime> baselineBlockStarts(DateTime fromDay) {
  final day = localMidnightDay(fromDay);
  return [
    for (var i = 0; i < kTrainingLoadBaselineWeeks; i++)
      DateTime(
        day.year,
        day.month,
        day.day - (kTrainingLoadBaselineWeeks - i) * 7,
      ),
  ];
}

/// One session's time per modality, in seconds (D-904–D-906).
///
/// [measuredSecs] is the session's measured active time per modality (D-903).
/// For a non-rolling session, Resistance takes the remainder
/// `max(0, durationSecs − Σ measured)`; when `Σ measured > durationSecs` the
/// whole session goes to [dominantSection] instead (D-905), and a session with
/// no dominant section contributes nothing. A rolling session has no duration
/// to use: its time is the measured sums only, so its sets add no time (D-906).
Map<ExerciseSection, double> sessionTimeByModality({
  required int durationSecs,
  required bool isRolling,
  required Map<ExerciseSection, double> measuredSecs,
  required ExerciseSection? dominantSection,
}) {
  final measured = <ExerciseSection, double>{
    for (final entry in measuredSecs.entries)
      if (entry.value > 0) entry.key: entry.value,
  };

  if (isRolling) return measured;

  final totalMeasured = measured.values.fold<double>(0, (a, b) => a + b);
  if (totalMeasured > durationSecs) {
    if (dominantSection == null) return const {};
    return {dominantSection: durationSecs.toDouble()};
  }

  final remainder = durationSecs - totalMeasured;
  return {
    ...measured,
    ExerciseSection.resistance: remainder > 0 ? remainder : 0.0,
  };
}

/// One session's load per modality, in load minutes (D-907).
///
/// The session's load is split in proportion to [timeByModality]:
/// `load[section] = loadMinutes × time[section] / sessionTimeSeconds`. When the
/// session's time is zero, or the session is unrated, every section's load is
/// zero. The split is never rounded per session.
Map<ExerciseSection, double> sessionLoadByModality({
  required Map<ExerciseSection, double> timeByModality,
  required int? rating,
}) {
  final sessionTimeSeconds = timeByModality.values.fold<double>(
    0,
    (a, b) => a + b,
  );
  if (sessionTimeSeconds <= 0) {
    return {for (final section in timeByModality.keys) section: 0.0};
  }

  final loadMinutes = sessionLoadMinutes(
    sessionTimeSecs: sessionTimeSeconds.round(),
    rating: rating,
  );
  return {
    for (final entry in timeByModality.entries)
      entry.key: loadMinutes * entry.value / sessionTimeSeconds,
  };
}

/// The ordered segments of one bar, from a measure per modality (D-912, D-913).
///
/// Only sections with a positive measure become segments. The list is in
/// descending measure, ties resolving in [ExerciseSection] declaration order.
/// Percentages use the largest-remainder method: `exact = 100 × measure /
/// total`, `percent = floor(exact)`, and the remaining points
/// (`100 − Σ percent`) go one each to the largest fractional remainders, ties
/// broken by larger exact measure and then by [ExerciseSection] declaration
/// order. The segments of one list always sum to exactly 100.
List<MixSegment> mixSegments(Map<ExerciseSection, double> measureBySection) {
  final entries = <MapEntry<ExerciseSection, double>>[
    for (final section in ExerciseSection.values)
      if ((measureBySection[section] ?? 0) > 0)
        MapEntry(section, measureBySection[section]!),
  ];
  if (entries.isEmpty) return const [];

  entries.sort((a, b) {
    final byMeasure = b.value.compareTo(a.value);
    if (byMeasure != 0) return byMeasure;
    return a.key.index.compareTo(b.key.index);
  });

  final total = entries.fold<double>(0, (a, e) => a + e.value);
  final exact = [for (final entry in entries) 100.0 * entry.value / total];
  final percent = [for (final value in exact) value.floor()];
  var remaining = 100 - percent.fold<int>(0, (a, b) => a + b);

  final byRemainder = List<int>.generate(entries.length, (i) => i)
    ..sort((a, b) {
      final remainder = (exact[b] - percent[b]).compareTo(
        exact[a] - percent[a],
      );
      if (remainder != 0) return remainder;
      final byExact = exact[b].compareTo(exact[a]);
      if (byExact != 0) return byExact;
      return entries[a].key.index.compareTo(entries[b].key.index);
    });
  for (final index in byRemainder) {
    if (remaining <= 0) break;
    percent[index]++;
    remaining--;
  }

  return [
    for (var i = 0; i < entries.length; i++)
      MixSegment(
        section: entries[i].key,
        measure: entries[i].value,
        percent: percent[i],
      ),
  ];
}
