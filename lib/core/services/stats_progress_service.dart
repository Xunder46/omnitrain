/// Service that computes progress-focused stats data from the workout history.
///
/// Works against the [WorkoutRepository] interface — runs identically on
/// [MockWorkoutRepository] (web/test) and any native SQLite implementation.
library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/stats_progress.dart';
import '../utils/date_utils.dart';
import '../utils/observation_grouper.dart';

class StatsProgressService {
  final WorkoutRepository _repository;

  StatsProgressService(this._repository);

  /// Maximum number of top lifts to include in [StatsProgressData.topLifts].
  static const int kTopLiftCount = 3;

  /// Maximum number of top cardio activities to include in
  /// [StatsProgressData.topCardio].
  static const int kTopCardioCount = 2;

  /// Maximum number of recent PRs to return in [StatsProgressData.recentPRs].
  static const int kRecentPRCount = 5;

  /// Single tunable: the number of most-recent "training days"
  /// (calendar days with at least one completed session) that
  /// define the recent-days window used for exercise selection
  /// when no active training period qualifies. Changing this
  /// constant changes the window everywhere it applies.
  static const int kRecentTrainingDaysWindow = 14;

  /// Default "visible window" hint for the NUTRITION card. The card
  /// now scrolls through **full** history (the scrollable
  /// `ScrollableTrendChart` shows as much as fits and lets the user
  /// drag for older days). The constant stays as a soft default
  /// for callers that want a fixed window; the card itself uses
  /// `days: null`.
  static const int kNutritionTrendDays = 10;

  /// Compute all progress data for the Stats screen.
  ///
  /// Complexity: O(sessions × segments × efforts + food rows in window).
  /// Acceptable for any foreseeable on-device history without caching in v1.
  Future<StatsProgressData> computeProgressData() async {
    final allSessions = await _repository.getAllSessions();
    final completed = allSessions.where((s) => s.endedAtMs != null).toList();

    // Resolve the current-state window for exercise SELECTION.
    // Trends and PRs use the full `completed` list — only the
    // bucket that drives the "who appears in Strength/Cardio"
    // decision is windowed.
    final periods = await _repository.getPeriods();
    final window = resolveWindow(periods: periods, completedSessions: completed);

    // exerciseId → { training-day → list of SetTuple }
    final setsByExercise = <String, Map<DateTime, List<_SetTuple>>>{};

    // exerciseId → { training-day → accumulated _CardioDay }
    final cardioByExercise = <String, Map<DateTime, _CardioDay>>{};

    for (final session in completed) {
      if (!_sessionInWindow(session, window)) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
      final sessionDay = DateTime(sessionDt.year, sessionDt.month, sessionDt.day);

      final segments = await _repository.getSessionSegments(session.id);
      for (final segment in segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          switch (effort.effortKind) {
            case 'set':
              await _processSetEffort(effort, sessionDay, setsByExercise);
            case 'timed':
              await _processTimedEffort(effort, sessionDay, cardioByExercise);
            default:
              // drill, round → not tracked in progress views
              break;
          }
        }
      }
    }

    // Resolve exercise names for all referenced exercise IDs.
    final nameCache = <String, String>{};
    for (final id in {...setsByExercise.keys, ...cardioByExercise.keys}) {
      if (!nameCache.containsKey(id)) {
        final exercise = await _repository.getExerciseById(id);
        nameCache[id] = exercise?.name ?? id;
      }
    }

    // Select top-N exercises by distinct training-day count.
    final topLiftIds = _selectTopN(setsByExercise, kTopLiftCount, nameCache);
    final topCardioIds = _selectTopN(cardioByExercise, kTopCardioCount, nameCache);

    // Trends and PRs are FULL-HISTORY for the selected exercises
    // — the window only decided who appears. Walk the unfiltered
    // `completed` list once and aggregate per-selected-exercise
    // day maps.
    final fullSetsByExercise = await _buildFullSetsForExercises(
      completed,
      topLiftIds,
    );
    final fullCardioByExercise = await _buildFullCardioForExercises(
      completed,
      topCardioIds,
    );

    // Build LiftProgress + collect PRs.
    final topLifts = <LiftProgress>[];
    final allPRs = <StatsPR>[];

    for (final exerciseId in topLiftIds) {
      final name = nameCache[exerciseId] ?? exerciseId;
      final dayMap = fullSetsByExercise[exerciseId] ?? const {};
      final days = dayMap.keys.toList()..sort();

      final e1RmTrend = <TrendPoint>[];
      final volumeTrend = <TrendPoint>[];

      for (final day in days) {
        final sets = dayMap[day]!;
        double maxE1Rm = 0;
        double totalVolume = 0;

        for (final set in sets) {
          final e1rm = epley1RM(set.weight, set.reps);
          if (e1rm != null) {
            if (e1rm > maxE1Rm) maxE1Rm = e1rm;
            totalVolume += set.weight * set.reps;
          }
        }

        if (maxE1Rm > 0) {
          e1RmTrend.add(TrendPoint(date: day, value: maxE1Rm));
        }
        if (totalVolume > 0) {
          volumeTrend.add(TrendPoint(date: day, value: totalVolume));
        }
      }

      topLifts.add(LiftProgress(
        exerciseName: name,
        e1RmTrend: e1RmTrend,
        volumeTrend: volumeTrend,
      ));

      // PR detection: walk the e1RM trend chronologically.
      double bestSoFar = 0;
      for (final point in e1RmTrend) {
        if (point.value > bestSoFar) {
          bestSoFar = point.value;
          allPRs.add(StatsPR(
            exerciseName: name,
            e1Rm: point.value,
            date: point.date,
          ));
        }
      }
    }

    // Sort PRs newest-first, then deduplicate: one entry per exercise at its
    // current best (highest e1RM). Tiebreaker: most recent date, then alpha.
    final dedupedPRs = <String, StatsPR>{};
    for (final pr in allPRs) {
      final existing = dedupedPRs[pr.exerciseName];
      if (existing == null ||
          pr.e1Rm > existing.e1Rm ||
          (pr.e1Rm == existing.e1Rm && pr.date.isAfter(existing.date))) {
        dedupedPRs[pr.exerciseName] = pr;
      }
    }

    final sortedPRs = dedupedPRs.values.toList()
      ..sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        return a.exerciseName.compareTo(b.exerciseName);
      });

    final recentPRs = sortedPRs.take(kRecentPRCount).toList();

    // Build CardioProgress.
    final topCardio = <CardioProgress>[];
    for (final exerciseId in topCardioIds) {
      final name = nameCache[exerciseId] ?? exerciseId;
      final dayMap = fullCardioByExercise[exerciseId] ?? const {};
      final days = dayMap.keys.toList()..sort();

      final trend = <CardioTrendPoint>[];
      for (final day in days) {
        final cd = dayMap[day]!;
        double? pace;
        if (cd.distanceM != null && cd.distanceM! > 0) {
          pace = cd.durationSecs / (cd.distanceM! / 1000.0);
        }
        trend.add(CardioTrendPoint(
          date: day,
          durationSecs: cd.durationSecs,
          distanceM: cd.distanceM,
          paceSecPerKm: pace,
        ));
      }

      topCardio.add(CardioProgress(exerciseName: name, trend: trend));
    }

    // Nutrition trend (NUTRITION card). Pure-Dart aggregation that
    // depends only on the repository — identical on Hive (web) and
    // any future native SQLite implementation. The card scrolls
    // through full history, so the service is called with
    // `days: null` to remove the 10-day cap.
    final nutritionTrend = await computeNutritionTrend(days: null);

    // Feeling trend (HOW DID IT FEEL card). Walks the same window that
    // drove Strength/Cardio selection so the trend moves in
    // lockstep with the other trends when the window changes.
    // Only sessions with a recorded feeling (1..5) produce a
    // point; sessions without one are omitted (no zero-fill, no
    // synthetic flat line).
    final feelingTrend = await computeFeelingTrend(window: window);

    return StatsProgressData(
      topLifts: topLifts,
      topCardio: topCardio,
      recentPRs: recentPRs,
      nutritionTrend: nutritionTrend,
      feelingTrend: feelingTrend,
      window: window,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _processSetEffort(
    SegmentEffort effort,
    DateTime sessionDay,
    Map<String, Map<DateTime, List<_SetTuple>>> setsByExercise,
  ) async {
    final exerciseId = effort.exerciseId;
    if (exerciseId == null) return;

    final observations = await _repository.getEffortObservations(effort.id);
    final entries = ObservationGrouper.groupByEffortKind('set', observations);

    for (final entry in entries) {
      final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
      final reps = entry['reps'] as int? ?? 0;
      if (weight <= 0 || reps <= 0) continue;

      setsByExercise
          .putIfAbsent(exerciseId, () => {})
          .putIfAbsent(sessionDay, () => [])
          .add(_SetTuple(weight: weight, reps: reps));
    }
  }

  Future<void> _processTimedEffort(
    SegmentEffort effort,
    DateTime sessionDay,
    Map<String, Map<DateTime, _CardioDay>> cardioByExercise,
  ) async {
    final exerciseId = effort.exerciseId;
    if (exerciseId == null) return;

    final timedInstances = await _repository.getTimedInstances(effort.id);
    final totalDuration = timedInstances
        .where((t) => t.state == TimedState.finished)
        .fold<int>(0, (sum, t) => sum + t.actualDurationSecs);

    if (totalDuration <= 0) return;

    final observations = await _repository.getEffortObservations(effort.id);
    final distanceObs = observations
        .where((o) => o.metricId == MetricIds.distance)
        .toList();

    double? newDistanceM;
    if (distanceObs.isNotEmpty) {
      final sum = distanceObs.fold<double>(
        0.0,
        (s, o) => s + (o.valueReal ?? 0.0),
      );
      if (sum > 0) newDistanceM = sum;
    }

    final dayMap = cardioByExercise.putIfAbsent(exerciseId, () => {});
    final existing = dayMap[sessionDay];

    if (existing == null) {
      dayMap[sessionDay] = _CardioDay(
        durationSecs: totalDuration,
        distanceM: newDistanceM,
      );
    } else {
      dayMap[sessionDay] = _CardioDay(
        durationSecs: existing.durationSecs + totalDuration,
        distanceM: (existing.distanceM != null || newDistanceM != null)
            ? (existing.distanceM ?? 0.0) + (newDistanceM ?? 0.0)
            : null,
      );
    }
  }

  /// Returns the top-[n] exercise IDs ordered by distinct training-day count
  /// (descending), with alphabetical name as a tiebreaker.
  List<String> _selectTopN(
    Map<String, Map<DateTime, dynamic>> data,
    int n,
    Map<String, String> nameCache,
  ) {
    final ranked = data.entries.map((e) {
      return (id: e.key, count: e.value.length, name: nameCache[e.key] ?? e.key);
    }).toList()
      ..sort((a, b) {
        final countCmp = b.count.compareTo(a.count);
        if (countCmp != 0) return countCmp;
        return a.name.compareTo(b.name);
      });

    return ranked.take(n).map((e) => e.id).toList();
  }

  /// Compute the per-day nutrition trend. Days with no
  /// `ConsumedFood` rows are skipped, not zero-filled. Returns an
  /// empty list when no food was logged in the window.
  ///
  /// Pass [days] to cap the window (today + N-1 prior, e.g.
  /// `days: 10` for the original 10-day window). Pass `null` (the
  /// default) for **full history** — the NUTRITION card uses this
  /// so its scrollable chart can plot every logged day.
  ///
  /// Per-day math:
  ///   calories = Σ `ConsumedFood.caloriesConsumed` (per-row,
  ///              already rounded)
  ///   macro    = Σ `(macro × amountConsumed / referenceAmount)`,
  ///              accumulated as a `double` and rounded **once** per
  ///              day so per-row fractional grams do not vanish.
  ///
  /// Carbs use the snapshot's **total** carbs (not net carbs). The
  /// line color token happens to be named `netCarbs` (the donut's
  /// blue slot), but the value plotted here is total carbs to
  /// match the home strip's "total carbs for blue" semantics.
  Future<List<NutritionTrendPoint>> computeNutritionTrend({
    int? days = kNutritionTrendDays,
  }) async {
    final todayMs = OmniDateUtils.todayMidnightMs();
    final fromMs = days == null
        // Full history: from epoch so even year-old rows come back.
        // The repository filters by dateMs and we never carry more
        // than the user actually logged.
        ? 0
        // Windowed: fromMs = local midnight of (today - (days-1)).
        : DateTime(
            DateTime.fromMillisecondsSinceEpoch(todayMs)
                .subtract(Duration(days: days - 1))
                .year,
            DateTime.fromMillisecondsSinceEpoch(todayMs)
                .subtract(Duration(days: days - 1))
                .month,
            DateTime.fromMillisecondsSinceEpoch(todayMs)
                .subtract(Duration(days: days - 1))
                .day,
          ).millisecondsSinceEpoch;
    // toMs = end of "today" (23:59:59.999 local) so today's row is
    // included even though dateMs is today's local midnight.
    final toMs = OmniDateUtils.endOfDayMs(
      DateTime.fromMillisecondsSinceEpoch(todayMs),
    );

    final rows = await _repository.getConsumedFoodsInRange(fromMs, toMs);
    if (rows.isEmpty) return const [];

    // dateMs (int) → running accumulators. Per-row scaling uses
    // `amountConsumed / referenceAmount`; we accumulate as double
    // and round once at the end so sub-gram totals do not drop to
    // zero from per-row rounding.
    final dayCalories = <int, int>{};
    final dayProteinD = <int, double>{};
    final dayCarbsD = <int, double>{};
    final dayFatD = <int, double>{};
    final dayDate = <int, DateTime>{};

    for (final r in rows) {
      final dayKey = r.dateMs;
      // Per-row, pre-rounded calories. Sum is a sum-of-rounded
      // values; matches the calorie ring's total.
      dayCalories[dayKey] =
          (dayCalories[dayKey] ?? 0) + r.caloriesConsumed;
      // Macro grams: accumulate as double, round once at the end.
      final scale = r.amountConsumed / r.referenceAmount;
      dayProteinD[dayKey] = (dayProteinD[dayKey] ?? 0) + r.protein * scale;
      dayCarbsD[dayKey] = (dayCarbsD[dayKey] ?? 0) + r.carbs * scale;
      dayFatD[dayKey] = (dayFatD[dayKey] ?? 0) + r.fat * scale;
      // Local-midnight DateTime, derived from dateMs (which is
      // already local midnight per the seed contract).
      final dt = DateTime.fromMillisecondsSinceEpoch(dayKey);
      dayDate[dayKey] = DateTime(dt.year, dt.month, dt.day);
    }

    final dayKeys = dayDate.keys.toList()..sort();
    return dayKeys
        .map(
          (k) => NutritionTrendPoint(
            date: dayDate[k]!,
            calories: dayCalories[k] ?? 0,
            protein: (dayProteinD[k] ?? 0).round(),
            carbs: (dayCarbsD[k] ?? 0).round(),
            fat: (dayFatD[k] ?? 0).round(),
          ),
        )
        .toList();
  }

  /// Compute the per-session feeling trend (HOW DID IT FEEL card on the
  /// Stats screen). One `FeelingTrendPoint` per completed session
  /// whose `sessionFeeling` is in 1..5 and whose `startedAtMs`
  /// falls inside the supplied [window]. Sessions without a
  /// recorded feeling are omitted entirely (no zero-fill, no
  /// synthetic flat line). Empty list when no qualifying session
  /// exists in the window — the UI then renders an explicit
  /// empty-state card.
  ///
  /// Universal across modalities: this aggregator reads only
  /// `TrainingSession.sessionFeeling` and the window boundaries.
  /// It does not touch `SegmentEffort`, `Exercise`, or any
  /// modality / strength-specific table, so an all-running or
  /// all-grappling user renders identically to a lifter.
  ///
  /// Points are sorted ascending by date. The window is inclusive
  /// on both ends, matching the boundary check used for Strength
  /// and Cardio selection so the feeling trend moves in lockstep
  /// with the other trends when the window changes.
  Future<List<FeelingTrendPoint>> computeFeelingTrend({
    required StatsWindow window,
  }) async {
    final allSessions = await _repository.getAllSessions();
    final completed = allSessions.where((s) => s.endedAtMs != null).toList();

    final fromMs = window.fromMs.millisecondsSinceEpoch;
    final toMs = window.toMs.millisecondsSinceEpoch;

    final points = <FeelingTrendPoint>[];
    for (final session in completed) {
      if (session.startedAtMs < fromMs || session.startedAtMs > toMs) {
        continue;
      }
      final feeling = session.sessionFeeling;
      if (feeling == null || feeling < 1 || feeling > 5) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(session.startedAtMs);
      points.add(
        FeelingTrendPoint(
          date: DateTime(dt.year, dt.month, dt.day),
          feeling: feeling,
        ),
      );
    }
    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }

  /// Epley 1-rep-max estimate: weight × (1 + reps / 30).
  /// Returns null when weight or reps is zero/negative.
  ///
  /// **Source of truth.** The Stats screen (`computeProgressData`'s
  /// PR detection loop) and the in-session "Congrats! New PR" toast
  /// (see `.github/agents/plans/in-session-pr-toast-plan.md`) both
  /// call this method. Do not introduce a second e1RM helper — keep
  /// the formula in one place so the two surfaces cannot drift.
  static double? epley1RM(double weight, int reps) {
    if (weight <= 0 || reps <= 0) return null;
    return weight * (1 + reps / 30.0);
  }

  /// Returns the highest [epley1RM] ever logged for [exerciseId]
  /// across all **completed** sessions. Returns `0.0` (not `null`)
  /// when no prior set exists for the exercise, so callers can use a
  /// single strict `>` comparison to detect a new personal record —
  /// a first-ever set is a PR because its positive e1RM is greater
  /// than `0.0` (Decision Ledger D-2, D-3 in
  /// `.github/agents/plans/in-session-pr-toast-plan.md`).
  ///
  /// **Source of truth.** This is the same walk `computeProgressData`
  /// performs when it detects PRs for the Stats screen. In-progress
  /// sessions are intentionally excluded so the in-session toast and
  /// the Stats screen agree on the standing best at the moment of a
  /// new set. Only `effortKind == 'set'` efforts are considered,
  /// matching the "Effort-Type Keying" rule in `docs/stats_screen.md`.
  ///
  /// S-009 (in `.github/agents/plans/in-session-pr-toast-plan.md`)
  /// is the structural-guard test that locks this method to the
  /// Stats screen's PR detector for the same input data.
  Future<double> getAllTimeBestE1RM(String exerciseId) async {
    final sessions = await _repository.getAllSessions();
    final completed = sessions.where((s) => s.endedAtMs != null).toList();

    double best = 0.0;
    for (final session in completed) {
      final segments = await _repository.getSessionSegments(session.id);
      for (final segment in segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          if (effort.exerciseId != exerciseId) continue;

          final observations =
              await _repository.getEffortObservations(effort.id);
          final entries =
              ObservationGrouper.groupByEffortKind('set', observations);
          for (final entry in entries) {
            final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
            final reps = entry['reps'] as int? ?? 0;
            final e1rm = epley1RM(weight, reps);
            if (e1rm != null && e1rm > best) {
              best = e1rm;
            }
          }
        }
      }
    }
    return best;
  }

  // ── Window resolution (current-state window for exercise selection) ───────

  /// Resolves the [StatsWindow] used to select which exercises
  /// appear in the Strength and Cardio sections. Both sections
  /// always share one window in a given load.
  ///
  /// Selection rule (executed in order):
  /// 1. If today is inside any [TrainingPeriod] that contains at
  ///    least one [completedSessions] entry, use that period's
  ///    `[startDateMs, endDateMs]` as the window. If more than one
  ///    period qualifies, the one with the latest `startDateMs`
  ///    wins (tiebreak by id ascending for determinism).
  /// 2. Otherwise, take the N most-recent distinct training days
  ///    (calendar days with ≥ 1 completed session), where
  ///    N = [kRecentTrainingDaysWindow]. The window's `fromMs` is
  ///    the start-of-day of the earliest selected day, and `toMs`
  ///    is end-of-day of today.
  /// 3. If no completed sessions exist, the recent-days window
  ///    reports `recentDays: 0`; `fromMs`/`toMs` collapse to today
  ///    so the filter cleanly yields zero sessions and the screen
  ///    shows its existing empty states.
  static StatsWindow resolveWindow({
    required List<TrainingPeriod> periods,
    required List<TrainingSession> completedSessions,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final todayEnd =
        DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
    final todayMidnightMs = todayMidnight.millisecondsSinceEpoch;

    // 1) Active training period that covers today and contains
    //    at least one qualifying session.
    TrainingPeriod? chosen;
    for (final period in periods) {
      // Period covers today when start-of-day ≤ today ≤ end-of-day.
      if (period.startDateMs > todayEnd.millisecondsSinceEpoch) continue;
      if (period.endDateMs < todayMidnightMs) continue;
      final hasSessionInRange = completedSessions.any(
        (s) =>
            s.endedAtMs != null &&
            s.startedAtMs >= period.startDateMs &&
            s.startedAtMs <= period.endDateMs,
      );
      if (!hasSessionInRange) continue;
      if (chosen == null ||
          period.startDateMs > chosen.startDateMs ||
          (period.startDateMs == chosen.startDateMs &&
              period.id.compareTo(chosen.id) < 0)) {
        chosen = period;
      }
    }
    if (chosen != null) {
      return StatsWindow(
        fromMs: DateTime.fromMillisecondsSinceEpoch(chosen.startDateMs),
        toMs: DateTime.fromMillisecondsSinceEpoch(chosen.endDateMs),
        label: chosen.name,
        isPeriodScoped: true,
        periodId: chosen.id,
        periodName: chosen.name,
      );
    }

    // 2) Recent training days. N is the single tunable.
    const n = kRecentTrainingDaysWindow;
    final distinctDays = <DateTime>{};
    for (final s in completedSessions) {
      if (s.endedAtMs == null) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs);
      distinctDays.add(DateTime(dt.year, dt.month, dt.day));
    }
    if (distinctDays.isEmpty) {
      return StatsWindow(
        fromMs: todayMidnight,
        toMs: todayEnd,
        label: 'Last $n training days',
        isPeriodScoped: false,
        recentDays: 0,
      );
    }
    final sortedDesc = distinctDays.toList()
      ..sort((a, b) => b.compareTo(a));
    final selected = sortedDesc.take(n).toList()..sort();
    final earliest = selected.first;
    return StatsWindow(
      fromMs: DateTime(earliest.year, earliest.month, earliest.day),
      toMs: todayEnd,
      label: 'Last $n training days',
      isPeriodScoped: false,
      recentDays: selected.length,
    );
  }

  /// True when [session]'s `startedAtMs` falls within the
  /// [StatsWindow] date range. The window is inclusive on both
  /// ends; the helper centralizes the boundary check so the
  /// selection iteration and the future consumers all agree.
  static bool _sessionInWindow(TrainingSession session, StatsWindow window) {
    return session.startedAtMs >=
            window.fromMs.millisecondsSinceEpoch &&
        session.startedAtMs <= window.toMs.millisecondsSinceEpoch;
  }

  /// Builds a per-selected-exercise full-history set trend map.
  /// Walks the unfiltered [completed] list and aggregates `_SetTuple`
  /// entries per training day for the given exercise IDs only.
  /// The window decides which exercises are eligible; the trend
  /// itself reaches back to every training day for those exercises.
  Future<Map<String, Map<DateTime, List<_SetTuple>>>>
      _buildFullSetsForExercises(
    List<TrainingSession> completed,
    List<String> exerciseIds,
  ) async {
    final result = <String, Map<DateTime, List<_SetTuple>>>{};
    if (exerciseIds.isEmpty) return result;
    final selected = exerciseIds.toSet();
    for (final session in completed) {
      if (session.endedAtMs == null) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(
        session.startedAtMs,
      );
      final sessionDay =
          DateTime(sessionDt.year, sessionDt.month, sessionDt.day);
      final segments = await _repository.getSessionSegments(session.id);
      for (final segment in segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          final exId = effort.exerciseId;
          if (exId == null || !selected.contains(exId)) continue;
          await _processSetEffort(effort, sessionDay, result);
        }
      }
    }
    return result;
  }

  /// Builds a per-selected-exercise full-history cardio trend map.
  /// See [_buildFullSetsForExercises] for the parallel contract.
  Future<Map<String, Map<DateTime, _CardioDay>>>
      _buildFullCardioForExercises(
    List<TrainingSession> completed,
    List<String> exerciseIds,
  ) async {
    final result = <String, Map<DateTime, _CardioDay>>{};
    if (exerciseIds.isEmpty) return result;
    final selected = exerciseIds.toSet();
    for (final session in completed) {
      if (session.endedAtMs == null) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(
        session.startedAtMs,
      );
      final sessionDay =
          DateTime(sessionDt.year, sessionDt.month, sessionDt.day);
      final segments = await _repository.getSessionSegments(session.id);
      for (final segment in segments) {
        final efforts = await _repository.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'timed') continue;
          final exId = effort.exerciseId;
          if (exId == null || !selected.contains(exId)) continue;
          await _processTimedEffort(effort, sessionDay, result);
        }
      }
    }
    return result;
  }
}

// ── Internal accumulator types ────────────────────────────────────────────────

class _SetTuple {
  final double weight;
  final int reps;

  const _SetTuple({required this.weight, required this.reps});
}

class _CardioDay {
  final int durationSecs;
  final double? distanceM;

  const _CardioDay({required this.durationSecs, required this.distanceM});
}
