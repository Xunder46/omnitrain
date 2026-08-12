/// Plain Dart value types for Stats screen progress views.
/// No Flutter imports — safe to use in pure unit tests.
library;

/// A single chronological data point in a trend series.
class TrendPoint {
  final DateTime date;
  final double value;

  /// Optional annotation carrying added-weight context for the
  /// day — populated only on reps-axis trend points where at
  /// least one set was performed with a loaded belt / vest
  /// (the `metric-extra-weight` observation on the set). The
  /// value is the day's max added weight in kg; `null` means
  /// no added weight was used that day (pure bodyweight, or the
  /// trend belongs to a loaded-only exercise that has no
  /// annotation concept).
  ///
  /// This is annotation-only: it never contributes to the kg
  /// Total Volume figure, never produces a separate weight
  /// record, and never flips the exercise onto a weight axis.
  /// A loaded set on a reps-axis exercise contributes its reps
  /// to [value] and its added weight here — and that's it.
  final double? extraWeightKg;

  const TrendPoint({
    required this.date,
    required this.value,
    this.extraWeightKg,
  });
}

/// A single chronological data point in a cardio trend series.
class CardioTrendPoint {
  final DateTime date;
  final int durationSecs;

  /// Total distance in metres for the training day. Null if no distance was logged.
  final double? distanceM;

  /// Pace in seconds per kilometre. Null if no distance was logged or distanceM == 0.
  final double? paceSecPerKm;

  const CardioTrendPoint({
    required this.date,
    required this.durationSecs,
    this.distanceM,
    this.paceSecPerKm,
  });
}

/// Strength progress for one exercise (e1RM and volume trends).
class LiftProgress {
  final String exerciseName;

  /// Max e1RM per training day, sorted chronologically. Empty for
  /// exercises tracked exclusively on the reps axis (bodyweight
  /// movements — see [repsTrend]).
  final List<TrendPoint> e1RmTrend;

  /// Total volume (reps × weight) per training day, sorted
  /// chronologically. Empty for exercises tracked exclusively on
  /// the reps axis.
  final List<TrendPoint> volumeTrend;

  /// Max reps per training day, sorted chronologically. Populated
  /// for bodyweight exercises (sets performed without added
  /// external weight); an exercise is on the reps axis if ANY of
  /// its logged sets has `weight == 0`. For mixed-axis exercises
  /// (some sets with added weight, some without) the reps axis is
  /// still used because the added-weight sets stay on the reps
  /// axis as annotations only (see the bodyweight-inclusion plan
  /// in `.github/agents/plans/stats-summary-fix-pack-plan.md`,
  /// Item 2). Empty for exercises that have only weighted sets.
  final List<TrendPoint> repsTrend;

  const LiftProgress({
    required this.exerciseName,
    this.e1RmTrend = const [],
    this.volumeTrend = const [],
    this.repsTrend = const [],
  });
}

/// Cardio progress for one exercise.
class CardioProgress {
  final String exerciseName;

  /// Aggregated cardio data per training day, sorted chronologically.
  final List<CardioTrendPoint> trend;

  const CardioProgress({required this.exerciseName, required this.trend});
}

/// A personal record event (new all-time high for an exercise).
///
/// Exactly one of [e1Rm] or [reps] is non-null on any given instance:
///   - `e1Rm != null, reps == null` → loaded-exercise (weight-based) PR.
///   - `e1Rm == null, reps != null` → bodyweight-exercise (reps-based) PR.
class StatsPR {
  final String exerciseName;
  final DateTime date;

  /// Epley 1-rep-max at the moment the record was set. Null for
  /// bodyweight exercises (which carry a [reps] PR instead).
  final double? e1Rm;

  /// Max reps in a single set at the moment the record was set.
  /// Null for loaded exercises (which carry an [e1Rm] PR instead).
  final int? reps;

  const StatsPR({
    required this.exerciseName,
    required this.date,
    this.e1Rm,
    this.reps,
  }) : assert(
          (e1Rm != null) ^ (reps != null),
          'Exactly one of e1Rm or reps must be non-null on a StatsPR',
        );
}

/// A single chronological data point in the Stats-screen feeling
/// trend. The feeling value is the post-session self-report captured
/// by the session summary sheet (1–5; 1 = Rough, 5 = Great). Only
/// sessions that have a recorded feeling produce a point — sessions
/// without a feeling are omitted from the series entirely (no
/// zero-fill, no synthetic flat line).
class FeelingTrendPoint {
  /// Local-midnight `DateTime` for the day this point represents.
  final DateTime date;

  /// Post-session feeling, 1..5 inclusive.
  final int feeling;

  const FeelingTrendPoint({required this.date, required this.feeling});
}

/// A single chronological data point in the Stats-screen nutrition
/// trend (NUTRITION card).
///
/// Sums the same day's [ConsumedFood] rows: calories from each
/// row's pre-rounded [ConsumedFood.caloriesConsumed], macro grams
/// from `macro × amountConsumed / referenceAmount` accumulated as
/// a double and rounded **once** per day. Days with no logged food
/// are skipped, not zero-filled.
class NutritionTrendPoint {
  /// Local-midnight `DateTime` for the day this point represents.
  final DateTime date;

  /// Σ [ConsumedFood.caloriesConsumed] for the day (kcal).
  final int calories;

  /// Σ `(protein × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once.
  final int protein;

  /// Σ `(carbs × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once. Uses **total** carbs
  /// grams (not net carbs) so the line colour slot — which is
  /// `macroChart.carbs` — still matches the home strip's "total
  /// carbs for blue" semantics.
  final int carbs;

  /// Σ `(fat × amountConsumed / referenceAmount)` for the day,
  /// accumulated as double and rounded once.
  final int fat;

  const NutritionTrendPoint({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Top-level container returned by [StatsProgressService].
class StatsProgressData {
  /// Up to [StatsProgressService.kTopLiftCount] lifts, sorted by training frequency.
  final List<LiftProgress> topLifts;

  /// Up to [StatsProgressService.kTopCardioCount] activities, sorted by training frequency.
  final List<CardioProgress> topCardio;

  /// Most-recent personal records across all tracked lifts (newest first).
  final List<StatsPR> recentPRs;

  /// Per-day nutrition trend for the NUTRITION card on the Stats
  /// screen, sorted ascending by date. Days with no logged food are
  /// skipped (not zero-filled). Empty list = no food logged in the
  /// window; the card hides itself in that case.
  final List<NutritionTrendPoint> nutritionTrend;

  /// Per-session feeling trend for the HOW DID IT FEEL card on the Stats
  /// screen, sorted ascending by date. Only completed sessions that
  /// have a recorded `sessionFeeling` (1..5) appear; sessions without
  /// a feeling are omitted entirely (no zero-fill). Empty list = no
  /// feeling logged in the current window; the card renders an
  /// explicit empty state in that case.
  final List<FeelingTrendPoint> feelingTrend;

  /// The "current window" that decided which exercises were eligible
  /// for [topLifts] and [topCardio]. The window is a date range plus
  /// a human-readable label so the UI can explain its selection.
  /// The trend charts for selected exercises and the Recent PRs
  /// list are NOT restricted by this window — they use full
  /// history.
  final StatsWindow window;

  const StatsProgressData({
    required this.topLifts,
    required this.topCardio,
    required this.recentPRs,
    this.nutritionTrend = const [],
    this.feelingTrend = const [],
    required this.window,
  });

  static final StatsProgressData empty = StatsProgressData(
    topLifts: const [],
    topCardio: const [],
    recentPRs: const [],
    window: StatsWindow.empty,
  );
}

/// The "current window" used to select which exercises appear in the
/// Stats screen's Strength and Cardio sections. Resolved once per
/// `StatsProgressService.computeProgressData()` call from either:
///   - the user-defined training period that covers today and contains
///     at least one qualifying completed session, or
///   - the most recent N "training days" (calendar days with at
///     least one completed session) when no period qualifies, where
///     N is `StatsProgressService.kRecentTrainingDaysWindow`.
///
/// Only the exercise **selection** is restricted to this window;
/// trend charts for the selected exercises and the Recent PRs list
/// continue to use full history (progression lives there, and a
/// PR's whole point is being a lifetime high).
class StatsWindow {
  /// Local-midnight `DateTime` for the start of the window. When
  /// the window has no qualifying days (zero training days), this
  /// is start-of-today so the filter cleanly yields zero sessions.
  final DateTime fromMs;

  /// End-of-day `DateTime` for the end of the window (today by
  /// default; the period's end-day when period-scoped).
  final DateTime toMs;

  /// Human-readable label for the on-screen window chip.
  /// e.g. `"Off-Season Strength Block"` or `"Last 14 training days"`.
  final String label;

  /// True when the window was resolved from a `TrainingPeriod`;
  /// false when it was resolved from recent training days.
  final bool isPeriodScoped;

  /// Period id when [isPeriodScoped]; null otherwise.
  final String? periodId;

  /// Period name when [isPeriodScoped]; null otherwise. Mirrors
  /// [label] for period-scoped windows but kept separate so the
  /// UI can map back to the period row if it wants to highlight
  /// the period's color.
  final String? periodName;

  /// N (number of training days) when `!isPeriodScoped`; null
  /// otherwise. The size of the window in calendar-day slots,
  /// measured by "training days" (distinct days with ≥1 completed
  /// session) — not calendar days, so rest days do not shrink
  /// the data.
  final int? recentDays;

  const StatsWindow({
    required this.fromMs,
    required this.toMs,
    required this.label,
    required this.isPeriodScoped,
    this.periodId,
    this.periodName,
    this.recentDays,
  });

  /// True when this window was resolved to a real, non-empty set of
  /// sessions. A recent-days window with zero training days returns
  /// false (and the Stats screen renders its existing empty states
  /// for both sections).
  bool get hasData => !isPeriodScoped
      ? (recentDays != null && recentDays! > 0)
      : true;

  /// Sentinel empty window used by [StatsProgressData.empty].
  /// Not user-visible; the screen never reaches this state because
  /// `computeProgressData` always resolves a real window from
  /// periods or recent days.
  static final StatsWindow empty = StatsWindow(
    fromMs: DateTime.fromMillisecondsSinceEpoch(0),
    toMs: DateTime.fromMillisecondsSinceEpoch(0),
    label: 'No data',
    isPeriodScoped: false,
    recentDays: 0,
  );
}

// ── Per-exercise records (PR 2b records section) ────────────────────────────
//
// For every exercise with at least one logged effort, the
// `StatsProgressService.computeExerciseRecords` aggregator returns
// an `ExerciseRecord` carrying the best observed value per
// metric with the date that value was set. Metrics that the
// exercise has never been logged against stay null — no
// zero-fill, no fabricated "0 kg" records on a 0-set exercise.
//
// All values are stored in the app's canonical units (kg, seconds,
// metres). Conversion to user-display units (lbs, mi) happens at
// the screen boundary through `UnitFormatter`; the service never
// carries a display unit.

/// One metric's best value on a single exercise, with the date
/// that value was set. The `value` field's semantics depend on
/// the metric — see the `heaviestLoad`, `mostRepsAtLoad`,
/// `longestDuration`, and `longestDistance` getters on
/// [ExerciseRecord], which return `RecordValue` shaped to match
/// the metric (kg × reps, reps, seconds, metres respectively).
class RecordValue {
  /// The metric's value in the app's canonical unit. The
  /// accompanying [date] is the training day that produced it.
  final double value;

  /// The training day (local-midnight DateTime) that produced the
  /// record. When two sets on different days tie at the same
  /// value, the earlier date is kept (records never move forward
  /// when a tie is re-set).
  final DateTime date;

  const RecordValue({required this.value, required this.date});
}

/// Per-exercise record of best observed values across the user's
/// full history. Every metric the exercise has logged is
/// populated; metrics the exercise has never been logged against
/// stay null. Modality is captured for per-modality grouping on
/// the Stats screen's RECORDS section.
class ExerciseRecord {
  final String exerciseId;
  final String exerciseName;

  /// Modality the user most often trains this exercise in. Null
  /// when every session was Free Training. The screen uses this
  /// for grouping and is never displayed verbatim — see the
  /// Modality display-name helper in `lib/core/constants/modality.dart`
  /// if a label is needed.
  final String? modality;

  /// Heaviest load × reps figure (kg·reps) across all completed
  /// sets of this exercise, with the date that figure was set.
  /// `null` when every set was bodyweight (0 kg × N reps = 0 is
  /// not a meaningful record).
  final RecordValue? heaviestLoad;

  /// The single set with the highest rep count, plus the load
  /// (kg) it was performed at. Bodyweight sets are included
  /// with `loadKg: 0.0` so a 12-rep pull-up shows up here even
  /// when no weighted pull-up set exists.
  final MostRepsRecord? mostRepsAtLoad;

  /// Total duration (seconds) of timed efforts on the longest
  /// day for this exercise, with that day. Per-day sum so a
  /// day with two 1 km runs shows 2 km, not 1.
  final DurationRecord? longestDuration;

  /// Total distance (metres) of timed efforts on the longest
  /// day for this exercise, with that day. Same per-day-sum
  /// contract as [longestDuration].
  final DistanceRecord? longestDistance;

  const ExerciseRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.modality,
    this.heaviestLoad,
    this.mostRepsAtLoad,
    this.longestDuration,
    this.longestDistance,
  });
}

/// Specialised [RecordValue] for the most-reps-at-load record —
/// carries the load (kg) alongside the rep count so the Stats
/// screen can render "12 reps @ 60 kg" without round-tripping
/// the value through a string.
class MostRepsRecord {
  final int reps;
  final double loadKg;
  final DateTime date;
  const MostRepsRecord({
    required this.reps,
    required this.loadKg,
    required this.date,
  });
}

/// Specialised [RecordValue] for the longest-duration record —
/// seconds (int) for the timeline display, plus the date.
class DurationRecord {
  final int durationSecs;
  final DateTime date;
  const DurationRecord({
    required this.durationSecs,
    required this.date,
  });
}

/// Specialised [RecordValue] for the longest-distance record —
/// metres (double) so fractional sub-metre precision survives
/// the walk, plus the date.
class DistanceRecord {
  final double distanceM;
  final DateTime date;
  const DistanceRecord({
    required this.distanceM,
    required this.date,
  });
}

// ── Volume / time / distance trends (PR 2b volume-trends section) ──────────

/// One bucket on a volume / time / distance trend. The
/// `periodStart` is local-midnight of the first day of the
/// period; the unit of [value] depends on the trend
/// (kg for tonnage, seconds for time, metres for distance).
class VolumeTrendPoint {
  final DateTime periodStart;
  final double value;
  const VolumeTrendPoint({
    required this.periodStart,
    required this.value,
  });
}

/// A single-metric trend (tonnage, time, or distance) bucketed
/// by ISO week. Carries one overall series (sum across all
/// modalities in the bucket) and per-modality series keyed by
/// the modality key stored on `TrainingSession.modality` (null
/// key = Free Training). Empty buckets are not emitted — the
/// trend only contains periods that had at least one qualifying
/// effort in the current-state window.
class VolumeTrend {
  /// Human-readable label, e.g. `"Tonnage (kg)"` or `"Time (h:mm)"`.
  /// Surfaces on the VOLUME TRENDS section's tab toggle and the
  /// per-line legend.
  final String label;

  /// Canonical unit string for the trend's value. The screen
  /// converts to display units at the boundary through
  /// `UnitFormatter`; the service carries the canonical label
  /// only.
  final String unit;

  /// One row per ISO week, sorted ascending by period start.
  /// The value is the Σ across all modalities in that week.
  final List<VolumeTrendPoint> overall;

  /// Per-modality series keyed by `TrainingSession.modality`.
  /// A null key holds the Free-Training series. Empty when no
  /// modality has any qualifying effort in the window.
  final Map<String, List<VolumeTrendPoint>> byModality;

  const VolumeTrend({
    required this.label,
    required this.unit,
    required this.overall,
    required this.byModality,
  });
}

// ── Consistency (PR 2b consistency section) ────────────────────────────────

/// One bucket on a consistency (sessions-per-period) trend. The
/// `periodStart` is local-midnight of the first day of the
/// period; [count] is the number of completed sessions whose
/// `startedAtMs` falls inside the period.
class ConsistencyPoint {
  final DateTime periodStart;
  final int count;
  const ConsistencyPoint({
    required this.periodStart,
    required this.count,
  });
}

/// A sessions-per-period trend (week or month). Carries one
/// overall series (all modalities) and per-modality series
/// keyed by `TrainingSession.modality`. Empty when no
/// completed sessions exist in any period.
class ConsistencyTrend {
  /// Human-readable label, e.g. `"Sessions / week"`.
  final String label;

  /// One row per period, sorted ascending by period start.
  final List<ConsistencyPoint> overall;

  /// Per-modality series keyed by `TrainingSession.modality`.
  /// A null key holds the Free-Training series.
  final Map<String, List<ConsistencyPoint>> byModality;

  const ConsistencyTrend({
    required this.label,
    required this.overall,
    required this.byModality,
  });
}

// ── Nutrition adherence (PR 2b nutrition adherence section) ───────────────

/// One point on the nutrition-target piecewise line. The
/// `date` is local-midnight of the day the point starts at;
/// the target values extend from this point forward until the
/// next point in the series (or to the end of the actuals'
/// x-axis for the final point). The piecewise line is built by
/// walking `WorkoutRepository.getNutritionTargetForDate` for
/// every saved target change, so a save on day 10 produces a
/// step at day 10 — historical actuals are never rewritten.
class NutritionAdherenceTargetPoint {
  final DateTime date;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const NutritionAdherenceTargetPoint({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Companion to `StatsProgressData.nutritionTrend` for the
/// NUTRITION card's target-line overlay. `actuals` re-uses
/// the existing `NutritionTrendPoint` series (same
/// per-day math, same skip-empty rule). `targetLine` is empty
/// when no target has ever been saved — the screen omits the
/// dashed target line in that case.
class NutritionAdherence {
  final List<NutritionTrendPoint> actuals;
  final List<NutritionAdherenceTargetPoint> targetLine;

  const NutritionAdherence({
    required this.actuals,
    required this.targetLine,
  });
}
