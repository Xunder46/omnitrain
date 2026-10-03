// Stats PR 6b — the Progression Rate's pure math.
//
// `now` is a parameter, so there is no clock here, no repository and no
// Flutter: the two windows, the samples they count, the rates and the three
// thresholds are all decided from the arguments alone.

/// The span of each of the two windows, in days.
const int kProgressionRateWindowDays = 28;

/// The fewest counted exercise-sessions each period needs to show the card.
const int kProgressionRateMinCounted = 8;

/// The recent rate the card needs, as the fraction `3/4`.
const double kProgressionRateMinRate = 0.75;

/// The improvement the recent rate needs over the prior rate, as the fraction
/// `1/10`.
const double kProgressionRateMinImprovement = 0.10;

/// The signal's priority, the highest among positives.
const int kProgressionRatePriority = 100;

// The two thresholds above as exact fractions. The qualification test compares
// these, not the doubles: `0.75 - 0.65` is `0.09999999999999998`, so a
// `double` comparison would refuse a rate that is exactly 75% against exactly
// 65% (S-1805).
const int _minRateNumerator = 3;
const int _minRateDenominator = 4;
const int _minImprovementNumerator = 1;
const int _minImprovementDenominator = 10;

/// One exercise's best on its native metric in one completed session.
///
/// The value is the exercise's own metric — estimated 1RM on the weight axis,
/// best reps on the reps axis — read over that session's set efforts alone.
class ProgressionSample {
  const ProgressionSample({
    required this.exerciseId,
    required this.sessionStartMs,
    required this.value,
  });

  final String exerciseId;
  final int sessionStartMs;
  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionSample &&
          other.exerciseId == exerciseId &&
          other.sessionStartMs == sessionStartMs &&
          other.value == value;

  @override
  int get hashCode => Object.hash(exerciseId, sessionStartMs, value);

  @override
  String toString() =>
      'ProgressionSample($exerciseId, $sessionStartMs, $value)';
}

/// A qualified rate: each period's counted exercise-sessions, its progression
/// count, its exact rate and the whole number the card shows.
class ProgressionRate {
  const ProgressionRate({
    required this.recentCounted,
    required this.recentProgressions,
    required this.priorCounted,
    required this.priorProgressions,
    required this.recentRate,
    required this.priorRate,
    required this.recentPercent,
    required this.priorPercent,
  });

  /// Builds the rates from the four counts, so the exact fractions and the
  /// rounded percentages are derived one way only.
  factory ProgressionRate.fromCounts({
    required int recentProgressions,
    required int recentCounted,
    required int priorProgressions,
    required int priorCounted,
  }) {
    final recentRate = progressionRateOf(recentProgressions, recentCounted);
    final priorRate = progressionRateOf(priorProgressions, priorCounted);
    return ProgressionRate(
      recentCounted: recentCounted,
      recentProgressions: recentProgressions,
      priorCounted: priorCounted,
      priorProgressions: priorProgressions,
      recentRate: recentRate,
      priorRate: priorRate,
      recentPercent: progressionRatePercentOf(recentRate),
      priorPercent: progressionRatePercentOf(priorRate),
    );
  }

  /// Counted exercise-sessions in the last [kProgressionRateWindowDays] days.
  final int recentCounted;

  /// Of those, the ones that matched or beat their predecessor.
  final int recentProgressions;

  /// Counted exercise-sessions in the [kProgressionRateWindowDays] days before.
  final int priorCounted;

  /// Of those, the ones that matched or beat their predecessor.
  final int priorProgressions;

  /// The exact recent fraction, `recentProgressions / recentCounted`.
  final double recentRate;

  /// The exact prior fraction, `priorProgressions / priorCounted`.
  final double priorRate;

  /// [recentRate] as the whole number the card shows.
  final int recentPercent;

  /// [priorRate] as the whole number the card shows.
  final int priorPercent;
}

/// The rate of [progressions] out of [counted]; a period with nothing counted
/// is zero.
double progressionRateOf(int progressions, int counted) =>
    counted <= 0 ? 0 : progressions / counted;

/// The whole number the card shows for [rate].
int progressionRatePercentOf(double rate) => (rate * 100).round();

/// The first instant of the recent window.
int progressionRecentWindowStartMs(DateTime now) => now
    .subtract(const Duration(days: kProgressionRateWindowDays))
    .millisecondsSinceEpoch;

/// The first instant of the prior window.
int progressionPriorWindowStartMs(DateTime now) => now
    .subtract(const Duration(days: 2 * kProgressionRateWindowDays))
    .millisecondsSinceEpoch;

/// True when a session starting at [sessionStartMs] counts in the recent
/// window, whose bounds are inclusive.
bool inRecentProgressionWindow(int sessionStartMs, DateTime now) =>
    sessionStartMs >= progressionRecentWindowStartMs(now) &&
    sessionStartMs <= now.millisecondsSinceEpoch;

/// True when a session starting at [sessionStartMs] counts in the prior
/// window: from [progressionPriorWindowStartMs] up to but excluding the recent
/// window's first instant.
bool inPriorProgressionWindow(int sessionStartMs, DateTime now) =>
    sessionStartMs >= progressionPriorWindowStartMs(now) &&
    sessionStartMs < progressionRecentWindowStartMs(now);

/// True when [rate] meets all three thresholds.
///
/// The counted floors are integer comparisons; the rate and the improvement
/// are cross-multiplied exact fractions. Every comparison is inclusive.
bool progressionRateQualifies(ProgressionRate rate) {
  if (rate.recentCounted < kProgressionRateMinCounted) return false;
  if (rate.priorCounted < kProgressionRateMinCounted) return false;

  // `recentProgressions / recentCounted >= 3/4`.
  if (rate.recentProgressions * _minRateDenominator <
      _minRateNumerator * rate.recentCounted) {
    return false;
  }

  // `recentProgressions / recentCounted - priorProgressions / priorCounted
  // >= 1/10`.
  final improvement =
      rate.recentProgressions * rate.priorCounted -
      rate.priorProgressions * rate.recentCounted;
  return improvement * _minImprovementDenominator >=
      _minImprovementNumerator * rate.recentCounted * rate.priorCounted;
}

/// The rate the samples describe, or null when it does not qualify.
///
/// Samples are grouped by exercise and ordered by session start; each
/// exercise's first sample is dropped from both totals, and every later sample
/// counts in the window its own session start falls in, as a progression when
/// its value matches or beats its predecessor's — including an exact tie. A
/// comparison is therefore attributed to the later session, whose predecessor
/// may sit outside both windows.
///
/// A sample whose value is not above zero is the exercise's native-metric zero
/// fallback rather than a performance, so it enters neither total.
ProgressionRate? progressionRate({
  required List<ProgressionSample> samples,
  required DateTime now,
}) {
  final byExercise = <String, List<ProgressionSample>>{};
  for (final sample in samples) {
    if (sample.value <= 0) continue;
    (byExercise[sample.exerciseId] ??= <ProgressionSample>[]).add(sample);
  }

  var recentCounted = 0;
  var recentProgressions = 0;
  var priorCounted = 0;
  var priorProgressions = 0;

  for (final exerciseSamples in byExercise.values) {
    exerciseSamples.sort((a, b) {
      final byStart = a.sessionStartMs.compareTo(b.sessionStartMs);
      return byStart != 0 ? byStart : a.value.compareTo(b.value);
    });

    for (var i = 1; i < exerciseSamples.length; i++) {
      final progressed =
          exerciseSamples[i].value >= exerciseSamples[i - 1].value;
      final startMs = exerciseSamples[i].sessionStartMs;
      if (inRecentProgressionWindow(startMs, now)) {
        recentCounted++;
        if (progressed) recentProgressions++;
      } else if (inPriorProgressionWindow(startMs, now)) {
        priorCounted++;
        if (progressed) priorProgressions++;
      }
    }
  }

  final rate = ProgressionRate.fromCounts(
    recentProgressions: recentProgressions,
    recentCounted: recentCounted,
    priorProgressions: priorProgressions,
    priorCounted: priorCounted,
  );
  return progressionRateQualifies(rate) ? rate : null;
}

/// The card's copy: the observation and the suggestion.
class ProgressionRateCopy {
  const ProgressionRateCopy({
    required this.observation,
    required this.suggestion,
  });

  final String observation;
  final String suggestion;
}

/// The card's copy for [rate], naming the user's two whole-number
/// percentages.
ProgressionRateCopy progressionRateCopy(ProgressionRate rate) =>
    ProgressionRateCopy(
      observation:
          'Resistance progression rate is ${rate.recentPercent}% over the last '
          '4 weeks, up from ${rate.priorPercent}%.',
      suggestion: 'The current approach is working.',
    );
