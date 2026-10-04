/// Service that computes progress-focused stats data from the workout history.
///
/// Works against the [WorkoutRepository] interface — runs identically on
/// [MockWorkoutRepository] (web/test) and any native SQLite implementation.
library;

import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/metric_ids.dart';
import '../models/exercise_metric.dart';
import '../models/fuel_summary.dart';
import '../models/instrument_list.dart';
import '../models/interference.dart';
import '../models/progression_rate.dart';
import '../models/stats_progress.dart';
import '../models/training_load.dart';
import '../utils/date_utils.dart';
import '../utils/distance_source.dart';
import '../utils/entry_rows.dart';
import '../utils/observation_grouper.dart';

/// An in-memory, read-only snapshot of the whole training history,
/// pre-grouped by parent id.
///
/// ## Why this exists
///
/// The repository's per-parent getters (`getSessionSegments`,
/// `getSegmentEfforts`, `getEffortObservations`, `getTimedInstances`)
/// each scan and deserialize their entire store before filtering. Called
/// from the nested session → segment → effort walk this service performs,
/// that is quadratic: a 100-session history took ~11 s to compute and a
/// 400-session history several minutes, on the main isolate, which is an
/// ANR on Android and a watchdog kill on iOS.
///
/// Building this snapshot costs one pass per store — seven bulk reads
/// total, regardless of history size — and every subsequent lookup is a
/// map hit. The traversal logic in this service is unchanged; only where
/// it reads from moved.
///
/// Group ordering is produced by the repository, so it matches the
/// per-parent getters exactly.
class _HistoryIndex {
  const _HistoryIndex({
    required this.sessions,
    required this.segmentsBySession,
    required this.effortsBySegment,
    required this.observationsByEffort,
    required this.timedInstancesByEffort,
    required this.roundInstancesByEffort,
    required this.sensorByTarget,
  });

  final List<TrainingSession> sessions;
  final Map<String, List<SessionSegment>> segmentsBySession;
  final Map<String, List<SegmentEffort>> effortsBySegment;
  final Map<String, List<EffortObservation>> observationsByEffort;
  final Map<String, List<TimedInstance>> timedInstancesByEffort;
  final Map<String, List<RoundInstance>> roundInstancesByEffort;

  /// Every sensor summary on the device, keyed `'<scope>|<targetId>'`. A
  /// summary's target is unique within its scope, so the pair is the key.
  final Map<String, SensorSummary> sensorByTarget;

  SensorSummary? sensorFor(String scope, String targetId) =>
      sensorByTarget['$scope|$targetId'];

  List<SessionSegment> segmentsOf(String sessionId) =>
      segmentsBySession[sessionId] ?? const <SessionSegment>[];

  List<SegmentEffort> effortsOf(String segmentId) =>
      effortsBySegment[segmentId] ?? const <SegmentEffort>[];

  List<EffortObservation> observationsOf(String effortId) =>
      observationsByEffort[effortId] ?? const <EffortObservation>[];

  List<TimedInstance> timedInstancesOf(String effortId) =>
      timedInstancesByEffort[effortId] ?? const <TimedInstance>[];

  List<RoundInstance> roundInstancesOf(String effortId) =>
      roundInstancesByEffort[effortId] ?? const <RoundInstance>[];
}

class StatsProgressService {
  final WorkoutRepository _repository;

  StatsProgressService(this._repository);

  /// Cached history snapshot. Built on first use and reused for the
  /// lifetime of the instance, so a screen that calls several `compute*`
  /// methods in one load pays for the read once. Callers that need fresh
  /// data after a write construct a new service.
  _HistoryIndex? _historyIndex;

  /// Exercise lookups memoised alongside the index. `getExerciseById` is
  /// a keyed read, but it is called once per exercise id per compute
  /// method; caching keeps repeated passes off the repository entirely.
  final Map<String, Exercise?> _exerciseCache = <String, Exercise?>{};

  Future<_HistoryIndex> _loadHistory() async {
    final cached = _historyIndex;
    if (cached != null) return cached;

    // Independent reads — issue them together rather than serially.
    final sessions = await _repository.getAllSessions();
    final segments = await _repository.getSegmentsBySession();
    final efforts = await _repository.getEffortsBySegment();
    final observations = await _repository.getObservationsByEffort();
    final timedInstances = await _repository.getTimedInstancesByEffort();
    final roundInstances = await _repository.getRoundInstancesByEffort();
    final sensorSummaries = await _repository.getSensorSummariesBySession();

    final sensorByTarget = <String, SensorSummary>{};
    for (final summaries in sensorSummaries.values) {
      for (final summary in summaries) {
        sensorByTarget['${summary.scope}|${summary.targetId}'] = summary;
      }
    }

    final index = _HistoryIndex(
      sessions: sessions,
      segmentsBySession: segments,
      effortsBySegment: efforts,
      observationsByEffort: observations,
      timedInstancesByEffort: timedInstances,
      roundInstancesByEffort: roundInstances,
      sensorByTarget: sensorByTarget,
    );
    _historyIndex = index;
    return index;
  }

  Future<Exercise?> _exerciseById(String id) async {
    if (_exerciseCache.containsKey(id)) return _exerciseCache[id];
    final exercise = await _repository.getExerciseById(id);
    _exerciseCache[id] = exercise;
    return exercise;
  }

  /// The cap on the lifts whose full history the PR scan walks. Not a
  /// display list: the Stats screen shows the resulting PRs, not the
  /// lifts themselves.
  static const int kTopLiftCount = 3;

  /// Maximum number of recent PRs to return in [StatsProgressData.recentPRs].
  static const int kRecentPRCount = 5;

  /// Single tunable: the number of most-recent "training days"
  /// (calendar days with at least one completed session) that
  /// define the recent-days window used for exercise selection
  /// when no active training period qualifies. Changing this
  /// constant changes the window everywhere it applies.
  static const int kRecentTrainingDaysWindow = 14;

  /// Recency floor (calendar days) for top-lift selection. An
  /// exercise whose most-recent training day is older than this many
  /// days ago is dropped from the displayed top slots — even when
  /// its historical frequency is high — so currently-trained work
  /// takes precedence over stale work.
  ///
  /// 30 days is generous enough that a weekly or biweekly rotation
  /// does not flicker a lift in and out between sessions; dropping
  /// out signals genuine abandonment, not normal spacing
  /// (`docs/plans/stats-summary-fix-pack-plan.md`,
  /// Item 3). Trend charts and PR lists for exercises that DO
  /// appear are unaffected — only which exercises fill the top-N
  /// slots is filtered.
  static const int kTopExerciseRecencyDays = 30;

  /// Default "visible window" hint for the nutrition trend. The trend
  /// screen scrolls through **full** history (the scrollable
  /// `ScrollableTrendChart` shows as much as fits and lets the user
  /// drag for older days). The constant stays as a soft default
  /// for callers that want a fixed window; the trend screen uses
  /// `days: null`.
  static const int kNutritionTrendDays = 10;

  /// Window length, in calendar days, over which the Fuel row averages
  /// intake and counts logged days. Seven days matches the weekly
  /// cadence a user reasons about their eating in.
  static const int kFuelWindowDays = 7;

  /// How far back the Fuel row looks for any logged food before it hides
  /// itself entirely.
  ///
  /// Deliberately longer than [kFuelWindowDays]: the row compares the
  /// current window against the previous one, so a user who has logged
  /// nothing in the last seven days still sees a meaningful previous-week
  /// average instead of an empty row. Much wider and the row would
  /// describe the past rather than the present.
  static const int kFuelVisibilityDays = 14;

  /// Compute the Stats screen's lift progress and personal records.
  ///
  /// Returns the lifts the PR scan covers ([StatsProgressData.topLifts]),
  /// the most-recent PRs and the window that selected the lifts.
  /// Complexity: O(sessions × segments × efforts). Acceptable for any
  /// foreseeable on-device history without caching in v1.
  Future<StatsProgressData> computeProgressData() async {
    final allSessions = (await _loadHistory()).sessions;
    final completed = allSessions.where((s) => s.endedAtMs != null).toList();

    // Resolve the current-state window for exercise SELECTION.
    // Trends and PRs use the full `completed` list — only the
    // bucket that decides which lifts enter the PR scan is windowed.
    final periods = await _repository.getPeriods();
    final window = resolveWindow(
      periods: periods,
      completedSessions: completed,
    );

    // exerciseId → { training-day → list of SetTuple } (loaded sets)
    final setsByExercise = <String, Map<DateTime, List<_SetTuple>>>{};

    // exerciseId → { training-day → max reps } (bodyweight sets)
    // Populated by `_processSetEffort` for entries with weight == 0.
    // The reps axis lets bodyweight movements compete for the
    // lift top slots on the same training-frequency basis as
    // loaded lifts (`docs/plans/stats-summary-fix-pack-plan.md`,
    // Item 2).
    final repsByExercise = <String, Map<DateTime, _RepsDay>>{};

    for (final session in completed) {
      if (!_sessionInWindow(session, window.fromMs, window.toMs)) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(
        session.startedAtMs,
      );
      final sessionDay = DateTime(
        sessionDt.year,
        sessionDt.month,
        sessionDt.day,
      );

      final segments = (await _loadHistory()).segmentsOf(session.id);
      for (final segment in segments) {
        final efforts = (await _loadHistory()).effortsOf(segment.id);
        for (final effort in efforts) {
          switch (effort.effortKind) {
            case 'set':
              await _processSetEffort(
                effort,
                sessionDay,
                setsByExercise,
                repsByExercise,
              );
            default:
              break;
          }
        }
      }
    }

    // Resolve exercise names for all referenced exercise IDs.
    final nameCache = <String, String>{};
    for (final id in {...setsByExercise.keys, ...repsByExercise.keys}) {
      if (!nameCache.containsKey(id)) {
        final exercise = await _exerciseById(id);
        nameCache[id] = exercise?.name ?? id;
      }
    }

    // Strength selection pools both axes: a training day is a
    // training day regardless of whether the set was loaded or
    // bodyweight. Combined days drive the frequency ranking; the
    // recency floor (kTopExerciseRecencyDays) drops stale lifts.
    final liftTrainingDays = <String, Set<DateTime>>{};
    for (final entry in setsByExercise.entries) {
      liftTrainingDays
          .putIfAbsent(entry.key, () => <DateTime>{})
          .addAll(entry.value.keys);
    }
    for (final entry in repsByExercise.entries) {
      liftTrainingDays
          .putIfAbsent(entry.key, () => <DateTime>{})
          .addAll(entry.value.keys);
    }

    final topLiftIds = _selectTopNWithRecencyFloor(
      liftTrainingDays,
      kTopLiftCount,
      nameCache,
    );
    // Trends and PRs are FULL-HISTORY for the selected exercises
    // — the window only decided who appears. Walk the unfiltered
    // `completed` list once and aggregate per-selected-exercise
    // day maps.
    final fullSetsByExercise = await _buildFullSetsForExercises(
      completed,
      topLiftIds,
    );
    final fullRepsByExercise = await _buildFullRepsForExercises(
      completed,
      topLiftIds,
    );
    // Build LiftProgress + collect PRs.
    final topLifts = <LiftProgress>[];
    final allPRs = <StatsPR>[];

    for (final exerciseId in topLiftIds) {
      final name = nameCache[exerciseId] ?? exerciseId;
      final setDayMap = fullSetsByExercise[exerciseId] ?? const {};
      final repsDayMap = fullRepsByExercise[exerciseId] ?? const {};

      // ── Per-exercise axis decision ──
      // An exercise is reps-axis if it has ANY bodyweight set
      // (`weight == 0`) in its history; otherwise it is
      // weight-axis. The decision is per-exercise, not per-set —
      // a mixed history never produces both an e1RM card and a
      // reps card; the reps axis wins the moment any bodyweight
      // set exists, and any added weight on weighted sets
      // becomes a per-day annotation on the reps trend. See the
      // Push-Up mixed-axis bug fix in
      // `docs/plans/stats-summary-fix-pack-plan.md`
      // and the user report "Push-Up weight-based stats".
      final isRepsAxis = repsDayMap.isNotEmpty;

      // ── Reps-axis trend (bodyweight + weighted bodyweight) ──
      final repsTrend = <TrendPoint>[];
      if (isRepsAxis) {
        final repsDays = repsDayMap.keys.toList()..sort();
        for (final day in repsDays) {
          final dayValue = repsDayMap[day]!;
          repsTrend.add(
            TrendPoint(
              date: day,
              value: dayValue.reps.toDouble(),
              extraWeightKg: dayValue.extraWeightKg > 0
                  ? dayValue.extraWeightKg
                  : null,
            ),
          );
        }
      }

      // ── Weight-axis trends (e1RM + volume) ──
      // Only built when the exercise is weight-axis. A mixed
      // exercise drops these to keep the card reps-only — the
      // weighted sets are still on the reps axis as annotations.
      final e1RmTrend = <TrendPoint>[];
      final volumeTrend = <TrendPoint>[];
      if (!isRepsAxis) {
        final setDays = setDayMap.keys.toList()..sort();
        for (final day in setDays) {
          final sets = setDayMap[day]!;
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
      }

      topLifts.add(
        LiftProgress(
          exerciseName: name,
          e1RmTrend: e1RmTrend,
          volumeTrend: volumeTrend,
          repsTrend: repsTrend,
        ),
      );

      // ── PR detection: weight axis (only on weight-axis exercises) ──
      double bestSoFar = 0;
      if (!isRepsAxis) {
        for (final point in e1RmTrend) {
          if (point.value > bestSoFar) {
            bestSoFar = point.value;
            allPRs.add(
              StatsPR(exerciseName: name, e1Rm: point.value, date: point.date),
            );
          }
        }
      }

      // ── PR detection: reps axis (only on reps-axis exercises) ──
      // A "best reps in a single set" PR fires when the day's
      // max-reps exceeds all earlier days' max-reps for this
      // exercise. Same strict `>` comparison as the e1RM walker.
      // The PR is the first day the running max was reached.
      int bestRepsSoFar = 0;
      if (isRepsAxis) {
        for (final point in repsTrend) {
          final reps = point.value.toInt();
          if (reps > bestRepsSoFar) {
            bestRepsSoFar = reps;
            allPRs.add(
              StatsPR(exerciseName: name, reps: reps, date: point.date),
            );
          }
        }
      }
    }

    // Sort PRs newest-first, then deduplicate: one entry per
    // exercise at its current best. An exercise is on exactly
    // one axis (see the per-exercise axis decision above), so
    // the dedup simplifies to "keep the higher value on the
    // same axis, with later date as the tiebreaker."
    final dedupedPRs = <String, StatsPR>{};
    for (final pr in allPRs) {
      final existing = dedupedPRs[pr.exerciseName];
      if (existing == null) {
        dedupedPRs[pr.exerciseName] = pr;
        continue;
      }
      // Each exercise is on exactly one axis, so `existing` and
      // `pr` share the same verdict shape. Keep the higher value
      // on that axis; tiebreak by later date.
      final prIsReps = pr.reps != null;
      final existingValue = prIsReps ? existing.reps! : existing.e1Rm!;
      final prValue = prIsReps ? pr.reps! : pr.e1Rm!;
      if (prValue > existingValue ||
          (prValue == existingValue && pr.date.isAfter(existing.date))) {
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

    return StatsProgressData(
      topLifts: topLifts,
      recentPRs: recentPRs,
      window: window,
    );
  }

  /// The all-time totals the Stats screen and Records & Trends both show:
  /// how many sessions are complete, and how long they lasted.
  ///
  /// A rolling session is a completed session and counts, but it contributes
  /// no time — it has no end the user waited for. The streak is deliberately
  /// absent: it stays `CalendarState.streakDays`, so the calendar keeps
  /// owning that rule.
  Future<StatsTotals> computeTotals() async {
    final sessions = (await _loadHistory()).sessions;

    var completedSessions = 0;
    var durationMs = 0;
    for (final session in sessions) {
      final endedAtMs = session.endedAtMs;
      if (endedAtMs == null) continue;
      completedSessions++;
      if (!session.isRolling) durationMs += endedAtMs - session.startedAtMs;
    }

    return StatsTotals(
      completedSessions: completedSessions,
      durationMs: durationMs,
    );
  }

  /// The Mix layer's whole payload: the window's bar, the user's usual split,
  /// the two counts and the weekly strip (D-916, D-917).
  ///
  /// One walk of the cached history snapshot serves all three reads — the
  /// window's sessions, the baseline's and the strip's — so the screen pays for
  /// no extra repository read (D-919). Null when the window holds no time at
  /// all: there is nothing to split, and a bar of nothing is not a bar (D-914).
  ///
  /// The measure is load only when the baseline is rated enough and the window
  /// is rated enough; otherwise it is time (D-908). The baseline is the 12
  /// calendar blocks before the window's start day and never uses
  /// [startOfWeek]; that setting moves the strip's weeks and nothing else
  /// (D-934, D-935).
  Future<MixLayerData?> computeMixLayer({
    required StatsWindow window,
    required DateTime now,
    required String startOfWeek,
  }) async {
    final history = await _loadHistory();

    final fromDay = localMidnightDay(window.fromMs);
    final baselineStarts = baselineBlockStarts(fromDay);
    final baselineEndMs = fromDay.millisecondsSinceEpoch;

    final currentWeekStart = OmniDateUtils.startOfWeek(
      now,
      startOfWeek: startOfWeek,
    );
    final weekStarts = [
      for (var i = kMixStripWeeks - 1; i >= 0; i--)
        DateTime(
          currentWeekStart.year,
          currentWeekStart.month,
          currentWeekStart.day - i * 7,
        ),
    ];

    return _mixPayload(
      history: history,
      fromMs: window.fromMs,
      toMs: window.toMs,
      baselineStarts: baselineStarts,
      baselineEndMs: baselineEndMs,
      weekStarts: weekStarts,
      startOfWeek: startOfWeek,
    );
  }

  /// The Mix payload for the period `[fromMs, toMs]` — the same figures the Mix
  /// layer shows for the equivalent window, with no weekly strip (D-1204).
  ///
  /// The period is the last [kModalityMixShiftPeriodDays] days, so its baseline
  /// is the 12 calendar blocks before its own start day and its measure gate is
  /// the same one the layer applies (D-1203). The strip is the layer's alone:
  /// the period has no `now` to anchor it to, so [MixLayerData.weeks] is empty.
  Future<MixLayerData?> computeMixPeriod({
    required DateTime fromMs,
    required DateTime toMs,
  }) async {
    final history = await _loadHistory();

    final fromDay = localMidnightDay(fromMs);
    return _mixPayload(
      history: history,
      fromMs: fromMs,
      toMs: toMs,
      baselineStarts: baselineBlockStarts(fromDay),
      baselineEndMs: fromDay.millisecondsSinceEpoch,
      weekStarts: const [],
      startOfWeek: 'monday',
    );
  }

  /// One [InterferenceSession] per completed session in the cached history,
  /// ordered by start and then by id (D-1316).
  ///
  /// The walk is the signal layer's only read: it carries each session's
  /// rating, its Sports load in load minutes, whether it holds a Resistance
  /// effort, and the best each exercise reached. The Sports load comes from
  /// [_sessionSplit], the same split the Mix layer renders, so the two surfaces
  /// cannot disagree (D-1317). One pass over the cached history index — no
  /// second repository read.
  Future<List<InterferenceSession>> interferenceSessions() async {
    final history = await _loadHistory();

    final logsBySession = <String, Map<String, List<_ExerciseLog>>>{};
    final exerciseIds = <String>{};
    final hasSetEffort = <String, bool>{};

    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      final byExercise = <String, List<_ExerciseLog>>{};
      var hasSet = false;
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          if (_sectionForKind(effort.effortKind) ==
              ExerciseSection.resistance) {
            hasSet = true;
          }
          final exerciseId = effort.exerciseId;
          if (exerciseId == null) continue;
          exerciseIds.add(exerciseId);
          (byExercise[exerciseId] ??= <_ExerciseLog>[]).add(
            _ExerciseLog(
              session: session,
              effort: effort,
              dayMs: localMidnightDay(
                DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
              ).millisecondsSinceEpoch,
            ),
          );
        }
      }
      logsBySession[session.id] = byExercise;
      hasSetEffort[session.id] = hasSet;
    }

    final repsAxis = await _repsAxisExercises(exerciseIds);

    final walk = <InterferenceSession>[];
    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      final byExercise = logsBySession[session.id] ?? const {};

      final bests = <String, double>{};
      for (final entry in byExercise.entries) {
        final section = _sectionForLogs(entry.value);
        if (section == null) continue;
        final value = await _nativeValueFor(
          entry.value,
          section,
          repsAxis.contains(entry.key),
        );
        if (value == null || value.value <= 0) continue;
        bests[entry.key] = value.value;
      }

      final split = _sessionSplit(history, session);
      walk.add(
        InterferenceSession(
          id: session.id,
          startMs: session.startedAtMs,
          endMs: session.endedAtMs!,
          rating: session.sessionFeeling,
          sportsLoadMinutes:
              split.loadBySection[ExerciseSection.sports] ?? 0.0,
          hasSetEffort: hasSetEffort[session.id] ?? false,
          bests: bests,
        ),
      );
    }

    walk.sort((a, b) {
      final byStart = a.startMs.compareTo(b.startMs);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return walk;
  }

  /// One walk of [history] serving the window's bar, the baseline's and the
  /// strip's (D-916, D-917, D-919).
  ///
  /// [weekStarts] is the strip's own week starts, oldest first; an empty list
  /// means no strip at all. Null when the window holds no time at all: there is
  /// nothing to split, and a bar of nothing is not a bar (D-914).
  MixLayerData? _mixPayload({
    required _HistoryIndex history,
    required DateTime fromMs,
    required DateTime toMs,
    required List<DateTime> baselineStarts,
    required int baselineEndMs,
    required List<DateTime> weekStarts,
    required String startOfWeek,
  }) {
    final windowTime = <ExerciseSection, double>{};
    final windowLoad = <ExerciseSection, double>{};
    var windowTimeSeconds = 0.0;
    var unratedTimeSeconds = 0.0;
    var unratedSessionCount = 0;

    final baselineLoad = <ExerciseSection, double>{};
    final ratedBaselineBlocks = <int>{};

    final weekTime = <int, Map<ExerciseSection, double>>{};
    final weekLoad = <int, Map<ExerciseSection, double>>{};

    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      final startMs = session.startedAtMs;

      final split = _sessionSplit(history, session);

      if (_sessionInWindow(session, fromMs, toMs)) {
        _addAll(windowTime, split.timeBySection);
        _addAll(windowLoad, split.loadBySection);
        windowTimeSeconds += split.timeSeconds;
        if (session.sessionFeeling == null) {
          unratedSessionCount++;
          unratedTimeSeconds += split.timeSeconds;
        }
      }

      if (startMs < baselineEndMs) {
        final block = _baselineBlockFor(baselineStarts, startMs);
        if (block != null) {
          _addAll(baselineLoad, split.loadBySection);
          if (session.sessionFeeling != null) ratedBaselineBlocks.add(block);
        }
      }

      final weekIndex = _weekIndexFor(weekStarts, startMs, startOfWeek);
      if (weekIndex != null) {
        _addAll(
          weekTime[weekIndex] ??= <ExerciseSection, double>{},
          split.timeBySection,
        );
        _addAll(
          weekLoad[weekIndex] ??= <ExerciseSection, double>{},
          split.loadBySection,
        );
      }
    }

    if (windowTimeSeconds <= 0) return null;

    final ratedBaselineWeeks = ratedBaselineBlocks.length;
    final measure =
        ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks &&
            unratedTimeSeconds / windowTimeSeconds <=
                kTrainingLoadMaxUnratedShare
        ? MixMeasure.load
        : MixMeasure.time;

    final measureBySection = measure == MixMeasure.load
        ? windowLoad
        : _minutesBySection(windowTime);
    final baselineTotal = baselineLoad.values.fold<double>(0, (a, b) => a + b);

    return MixLayerData(
      measure: measure,
      segments: mixSegments(measureBySection),
      baselineSegments: measure == MixMeasure.load && baselineTotal > 0
          ? mixSegments(baselineLoad)
          : const [],
      unratedSessionCount: unratedSessionCount,
      ratedBaselineWeeks: ratedBaselineWeeks,
      weeks: [
        for (var i = 0; i < weekStarts.length; i++)
          _mixWeek(
            weekStart: weekStarts[i],
            measure: measure,
            timeBySection: weekTime[i] ?? const {},
            loadBySection: weekLoad[i] ?? const {},
            inProgress: i == weekStarts.length - 1,
          ),
      ],
    );
  }

  /// One strip week, in the measure the bar uses (D-917).
  static MixWeek _mixWeek({
    required DateTime weekStart,
    required MixMeasure measure,
    required Map<ExerciseSection, double> timeBySection,
    required Map<ExerciseSection, double> loadBySection,
    required bool inProgress,
  }) {
    final bySection = measure == MixMeasure.load
        ? loadBySection
        : _minutesBySection(timeBySection);
    return MixWeek(
      weekStart: weekStart,
      segments: mixSegments(bySection),
      measure: bySection.values.fold<double>(0, (a, b) => a + b),
      inProgress: inProgress,
    );
  }

  /// The same split in minutes, so the time measure reads in the unit the
  /// surface labels it with (D-916).
  static Map<ExerciseSection, double> _minutesBySection(
    Map<ExerciseSection, double> secondsBySection,
  ) => {
    for (final entry in secondsBySection.entries) entry.key: entry.value / 60.0,
  };

  /// One completed session's time and load, split by section (D-1317).
  ///
  /// The Mix walk and the interference walk both read a session's Sports load
  /// from here, so the layer's bar and the signal's figure cannot disagree.
  /// [session] must be completed: the split needs its end.
  _SessionSplit _sessionSplit(_HistoryIndex history, TrainingSession session) {
    final measured = _measuredSecsFor(history, session);
    final dominant = _dominantSectionFor(history, session);
    final durationSecs = session.isRolling
        ? 0
        : ((session.endedAtMs! - session.startedAtMs) / 1000).round();
    final timeBySection = sessionTimeByModality(
      durationSecs: durationSecs,
      isRolling: session.isRolling,
      measuredSecs: measured,
      dominantSection: dominant,
    );
    return _SessionSplit(
      timeBySection: timeBySection,
      loadBySection: sessionLoadByModality(
        timeByModality: timeBySection,
        rating: session.sessionFeeling,
      ),
    );
  }

  /// The measured active seconds of [session] per modality (D-903).
  ///
  /// The effort's kind decides which instance store to read — never a literal
  /// kind string, always [_sectionForKind] (D-902). A `set` effort measures
  /// nothing: its time is the session's remainder.
  Map<ExerciseSection, double> _measuredSecsFor(
    _HistoryIndex history,
    TrainingSession session,
  ) {
    final measured = <ExerciseSection, double>{};
    for (final segment in history.segmentsOf(session.id)) {
      for (final effort in history.effortsOf(segment.id)) {
        final section = _sectionForKind(effort.effortKind);
        if (section == null) continue;
        switch (section) {
          case ExerciseSection.cardio:
          case ExerciseSection.isometric:
            for (final instance in history.timedInstancesOf(effort.id)) {
              if (instance.state != TimedState.finished) continue;
              measured[section] =
                  (measured[section] ?? 0) + instance.actualDurationSecs;
            }
          case ExerciseSection.sports:
            for (final instance in history.roundInstancesOf(effort.id)) {
              if (instance.state != RoundState.finished) continue;
              if (instance.startedAtMs <= 0) continue;
              if (instance.finishedAtMs == null) continue;
              measured[section] =
                  (measured[section] ?? 0) + instance.actualDurationSecs;
            }
          case ExerciseSection.resistance:
            break;
        }
      }
    }
    return measured;
  }

  /// The section [session]'s efforts most often belong to, ties resolving in
  /// [ExerciseSection] declaration order (D-905).
  ///
  /// An effort with no exercise still counts: the mapping is by kind, and the
  /// session's own shape is what the remainder falls back to.
  ExerciseSection? _dominantSectionFor(
    _HistoryIndex history,
    TrainingSession session,
  ) {
    final counts = <ExerciseSection, int>{};
    for (final segment in history.segmentsOf(session.id)) {
      for (final effort in history.effortsOf(segment.id)) {
        final section = _sectionForKind(effort.effortKind);
        if (section == null) continue;
        counts[section] = (counts[section] ?? 0) + 1;
      }
    }

    ExerciseSection? winner;
    var winnerCount = 0;
    for (final section in ExerciseSection.values) {
      final count = counts[section] ?? 0;
      if (count > winnerCount) {
        winner = section;
        winnerCount = count;
      }
    }
    return winner;
  }

  /// The index of the baseline block holding [startMs], or null when it falls
  /// outside every block (D-934).
  static int? _baselineBlockFor(List<DateTime> starts, int startMs) {
    for (var i = starts.length - 1; i >= 0; i--) {
      if (starts[i].millisecondsSinceEpoch <= startMs) return i;
    }
    return null;
  }

  /// The index of the strip week holding [startMs], or null when the session
  /// started before the strip's first week (D-917).
  static int? _weekIndexFor(
    List<DateTime> weekStarts,
    int startMs,
    String startOfWeek,
  ) {
    final weekStart = OmniDateUtils.startOfWeek(
      DateTime.fromMillisecondsSinceEpoch(startMs),
      startOfWeek: startOfWeek,
    );
    final weekStartMs = weekStart.millisecondsSinceEpoch;
    for (var i = weekStarts.length - 1; i >= 0; i--) {
      if (weekStarts[i].millisecondsSinceEpoch == weekStartMs) return i;
    }
    return null;
  }

  static void _addAll(
    Map<ExerciseSection, double> target,
    Map<ExerciseSection, double> source,
  ) {
    for (final entry in source.entries) {
      target[entry.key] = (target[entry.key] ?? 0) + entry.value;
    }
  }

  /// One summary per exercise logged in at least one completed session that
  /// started inside `[fromMs, toMs]`. Null bounds mean all history.
  ///
  /// The section is the effort kind the exercise was most often logged under
  /// inside the range; the native value is the best the section's own rule
  /// yields over the range. Both are computed here once, so Records & Trends,
  /// Exercise Progress and the Instruments rows read the same answer.
  Future<List<ExerciseMetricSummary>> computeExerciseMetrics({
    int? fromMs,
    int? toMs,
  }) async {
    final history = await _loadHistory();

    final inRange = <TrainingSession>[];
    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      if (fromMs != null && session.startedAtMs < fromMs) continue;
      if (toMs != null && session.startedAtMs > toMs) continue;
      inRange.add(session);
    }
    if (inRange.isEmpty) return const <ExerciseMetricSummary>[];

    final logsByExercise = <String, List<_ExerciseLog>>{};
    for (final session in inRange) {
      final dayMs = OmniDateUtils.startOfDayMs(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
      );
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          final exerciseId = effort.exerciseId;
          if (exerciseId == null) continue;
          (logsByExercise[exerciseId] ??= <_ExerciseLog>[]).add(
            _ExerciseLog(session: session, effort: effort, dayMs: dayMs),
          );
        }
      }
    }
    if (logsByExercise.isEmpty) return const <ExerciseMetricSummary>[];

    final repsAxis = await _repsAxisExercises(logsByExercise.keys.toSet());

    final summaries = <ExerciseMetricSummary>[];
    for (final entry in logsByExercise.entries) {
      final logs = entry.value;
      final section = _sectionForLogs(logs);
      // An exercise whose only efforts carry no known kind has no section to
      // sit in and no metric to be read by.
      if (section == null) continue;
      final isRepsAxis = repsAxis.contains(entry.key);

      final best =
          await _nativeValueFor(logs, section, isRepsAxis) ??
          _zeroValueFor(section, isRepsAxis);

      final logsByDay = <int, List<_ExerciseLog>>{};
      for (final log in logs) {
        (logsByDay[log.dayMs] ??= <_ExerciseLog>[]).add(log);
      }
      final days = logsByDay.keys.toList()..sort();
      final points = <ExerciseMetricPoint>[];
      for (final dayMs in days) {
        // The same rule the best came from, over one day's logs. A day the
        // exercise's metric cannot be read on contributes no point.
        final value = await _nativeValueFor(
          logsByDay[dayMs]!,
          section,
          isRepsAxis,
        );
        if (value == null) continue;
        points.add(ExerciseMetricPoint(dayMs: dayMs, value: value));
      }

      var lastTrainedMs = 0;
      final sessionIds = <String>{};
      for (final log in logs) {
        sessionIds.add(log.session.id);
        if (log.session.startedAtMs > lastTrainedMs) {
          lastTrainedMs = log.session.startedAtMs;
        }
      }

      final exercise = await _exerciseById(entry.key);
      summaries.add(
        ExerciseMetricSummary(
          exerciseId: entry.key,
          name: exercise?.name ?? entry.key,
          section: section,
          best: best,
          points: points,
          lastTrainedMs: lastTrainedMs,
          sessionCount: sessionIds.length,
        ),
      );
    }

    summaries.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.exerciseId.compareTo(b.exerciseId);
    });
    return summaries;
  }

  // ── The Progression Rate's samples ─────────────────────────────────────────

  /// Every exercise-session the Progression Rate compares: one sample per
  /// completed session and exercise that logged a `set` effort in it, whatever
  /// the session's modality, ordered by exercise and then by session start.
  ///
  /// The value is the exercise's own metric read over that session's set
  /// efforts alone, by the same native-value rule and the same axis
  /// classification the Instruments rows and the progress series use — no
  /// second value rule. The read rides the cached history index, so a load
  /// pays for no extra repository read.
  Future<List<ProgressionSample>> progressionSamples() async {
    final history = await _loadHistory();

    final groupsByExercise = <String, Map<String, _ProgressionGroup>>{};
    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      final dayMs = OmniDateUtils.startOfDayMs(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
      );
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          final exerciseId = effort.exerciseId;
          if (exerciseId == null || effort.effortKind != 'set') continue;
          final bySession = groupsByExercise[exerciseId] ??=
              <String, _ProgressionGroup>{};
          (bySession[session.id] ??= _ProgressionGroup(
            exerciseId: exerciseId,
            sessionStartMs: session.startedAtMs,
          )).logs.add(
            _ExerciseLog(session: session, effort: effort, dayMs: dayMs),
          );
        }
      }
    }
    if (groupsByExercise.isEmpty) return const <ProgressionSample>[];

    final repsAxis = await _repsAxisExercises(groupsByExercise.keys.toSet());

    final groups = <_ProgressionGroup>[];
    for (final entry in groupsByExercise.entries) {
      final sessions = entry.value.values.toList()
        ..sort((a, b) => a.sessionStartMs.compareTo(b.sessionStartMs));
      groups.addAll(sessions);
    }
    groups.sort((a, b) {
      final byExercise = a.exerciseId.compareTo(b.exerciseId);
      return byExercise != 0
          ? byExercise
          : a.sessionStartMs.compareTo(b.sessionStartMs);
    });

    // Independent reads, issued together rather than one per session.
    final values = await Future.wait([
      for (final group in groups)
        _resistanceValue(group.logs, repsAxis.contains(group.exerciseId)),
    ]);

    return [
      for (var i = 0; i < groups.length; i++)
        ProgressionSample(
          exerciseId: groups[i].exerciseId,
          sessionStartMs: groups[i].sessionStartMs,
          value: values[i].value,
        ),
    ];
  }

  // ── The Instruments list ───────────────────────────────────────────────────

  /// The window's work, grouped into the sections the Instruments list shows.
  ///
  /// A section's rank is the number of distinct days in the window on which an
  /// effort of that kind was logged, so the list leads with the biggest block
  /// of work rather than with a fixed order. A section appears only when it has
  /// a row, and a row appears for every exercise the window yields — including
  /// one whose value is the zero fallback, which shows the zero figure and no
  /// sparkline. Rows sort by training days, then name, then id.
  ///
  /// Each row also carries the same exercise's value over the immediately
  /// preceding range of the same calendar length, when the two are comparable,
  /// plus the cadence and heart-rate figures its section reads.
  Future<List<InstrumentSectionData>> computeInstrumentSections({
    required StatsWindow window,
  }) async {
    final fromMs = window.fromMs.millisecondsSinceEpoch;
    final toMs = window.toMs.millisecondsSinceEpoch;

    final current = await computeExerciseMetrics(fromMs: fromMs, toMs: toMs);
    if (current.isEmpty) return const <InstrumentSectionData>[];

    final previousRange = previousRangeFor(window);
    final previous = await computeExerciseMetrics(
      fromMs: previousRange.fromMs,
      toMs: previousRange.toMs,
    );
    final previousByExercise = <String, ExerciseMetricSummary>{
      for (final summary in previous) summary.exerciseId: summary,
    };

    final dayCounts = await _sectionTrainingDayCounts(fromMs, toMs);

    final bySection = <ExerciseSection, List<InstrumentRow>>{};
    for (final summary in current) {
      final previousSummary = previousByExercise[summary.exerciseId];
      final comparable =
          previousSummary != null &&
          previousSummary.best.metric == summary.best.metric;
      final sensors = await _sensorFiguresFor(summary, fromMs, toMs);
      (bySection[summary.section] ??= <InstrumentRow>[]).add(
        InstrumentRow(
          // A value nothing was readable for is the zero fallback: the row
          // still appears, but it has no series to draw.
          summary: summary.best.value <= 0
              ? ExerciseMetricSummary(
                  exerciseId: summary.exerciseId,
                  name: summary.name,
                  section: summary.section,
                  best: summary.best,
                  points: const <ExerciseMetricPoint>[],
                  lastTrainedMs: summary.lastTrainedMs,
                  sessionCount: summary.sessionCount,
                )
              : summary,
          previousValue: comparable ? previousSummary.best : null,
          cadenceStepsPerMin: sensors.cadenceStepsPerMin,
          averageHeartRateBpm: sensors.averageHeartRateBpm,
        ),
      );
    }

    final sections = <InstrumentSectionData>[];
    for (final entry in bySection.entries) {
      final rows = entry.value
        ..sort((a, b) {
          final byDays = b.summary.points.length.compareTo(
            a.summary.points.length,
          );
          if (byDays != 0) return byDays;
          final byName = a.summary.name.compareTo(b.summary.name);
          return byName != 0
              ? byName
              : a.summary.exerciseId.compareTo(b.summary.exerciseId);
        });
      sections.add(
        InstrumentSectionData(
          section: entry.key,
          rows: rows,
          trainingDayCount: dayCounts[entry.key] ?? 0,
        ),
      );
    }

    sections.sort((a, b) {
      final byDays = b.trainingDayCount.compareTo(a.trainingDayCount);
      return byDays != 0 ? byDays : a.section.index.compareTo(b.section.index);
    });
    return sections;
  }

  /// The range immediately before [window], of the same calendar length.
  ///
  /// The arithmetic is on calendar days, never on a duration: a DST transition
  /// inside the range would otherwise shorten or widen it by an hour. The
  /// window's own day count comes from its local-midnight bounds, inclusive.
  static ({int fromMs, int toMs}) previousRangeFor(StatsWindow window) {
    final from = window.fromMs;
    final to = window.toMs;
    final dayCount =
        DateTime.utc(
          to.year,
          to.month,
          to.day,
        ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
        1;
    return (
      fromMs: DateTime(
        from.year,
        from.month,
        from.day - dayCount,
      ).millisecondsSinceEpoch,
      toMs: from.millisecondsSinceEpoch - 1,
    );
  }

  /// The number of distinct days in `[fromMs, toMs]` on which an effort of each
  /// section's kind was logged — the section ordering rank.
  ///
  /// The day key is the local-midnight day of the session's start, an effort
  /// with no exercise is skipped, and only completed sessions count.
  Future<Map<ExerciseSection, int>> _sectionTrainingDayCounts(
    int fromMs,
    int toMs,
  ) async {
    final history = await _loadHistory();
    final daysBySection = <ExerciseSection, Set<int>>{};

    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      if (session.startedAtMs < fromMs || session.startedAtMs > toMs) continue;
      final dayMs = OmniDateUtils.startOfDayMs(
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
      );
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          if (effort.exerciseId == null) continue;
          final section = _sectionForKind(effort.effortKind);
          if (section == null) continue;
          (daysBySection[section] ??= <int>{}).add(dayMs);
        }
      }
    }

    return <ExerciseSection, int>{
      for (final entry in daysBySection.entries) entry.key: entry.value.length,
    };
  }

  /// The cadence and heart-rate figures [summary]'s row carries, read from the
  /// sensor summaries of the exercise's own instances in the window.
  ///
  /// Cadence is Cardio only: the steps summed over the timed instances that
  /// carry a step count, divided by the minutes of exactly those instances.
  /// Heart rate is the mean over the timed (Cardio) or round (Sports) instance
  /// summaries that carry a reading; Resistance and Isometric rows never show
  /// one. Neither figure is rendered when no summary carries it.
  Future<({int? cadenceStepsPerMin, int? averageHeartRateBpm})>
  _sensorFiguresFor(ExerciseMetricSummary summary, int fromMs, int toMs) async {
    final section = summary.section;
    if (section != ExerciseSection.cardio &&
        section != ExerciseSection.sports) {
      return (cadenceStepsPerMin: null, averageHeartRateBpm: null);
    }

    final history = await _loadHistory();
    final instanceScope = section == ExerciseSection.cardio
        ? SensorSummary.scopeTimedInstance
        : SensorSummary.scopeRoundInstance;

    var steps = 0;
    var stepsDurationSecs = 0;
    var heartRateSum = 0.0;
    var heartRateCount = 0;

    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      if (session.startedAtMs < fromMs || session.startedAtMs > toMs) continue;
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          if (effort.exerciseId != summary.exerciseId) continue;
          if (_sectionForKind(effort.effortKind) != section) continue;

          if (section == ExerciseSection.cardio) {
            for (final instance in history.timedInstancesOf(effort.id)) {
              final sensor = history.sensorFor(instanceScope, instance.id);
              final instanceSteps = sensor?.steps;
              if (instanceSteps == null) continue;
              steps += instanceSteps;
              stepsDurationSecs += instance.actualDurationSecs;
            }
            for (final instance in history.timedInstancesOf(effort.id)) {
              final avg = history
                  .sensorFor(instanceScope, instance.id)
                  ?.avgHeartRateBpm;
              if (avg == null) continue;
              heartRateSum += avg;
              heartRateCount++;
            }
          } else {
            for (final instance in history.roundInstancesOf(effort.id)) {
              final avg = history
                  .sensorFor(instanceScope, instance.id)
                  ?.avgHeartRateBpm;
              if (avg == null) continue;
              heartRateSum += avg;
              heartRateCount++;
            }
          }
        }
      }
    }

    return (
      cadenceStepsPerMin: stepsDurationSecs > 0
          ? (steps / (stepsDurationSecs / 60.0)).round()
          : null,
      averageHeartRateBpm: heartRateCount > 0
          ? (heartRateSum / heartRateCount).round()
          : null,
    );
  }

  // ── The native value, per section ──────────────────────────────────────────

  /// The exercise ids among [exerciseIds] that hold a bodyweight set anywhere
  /// in their **full** history — the axis rule `computeProgressData` shares.
  ///
  /// The walk ignores the caller's range on purpose: the axis is a property of
  /// the exercise, so a range that happens to hold only loaded sets does not
  /// move an exercise onto the weight axis, and every point of one series
  /// carries the same metric.
  Future<Set<String>> _repsAxisExercises(Set<String> exerciseIds) async {
    final history = await _loadHistory();
    final repsAxis = <String>{};
    for (final session in history.sessions) {
      if (session.endedAtMs == null) continue;
      for (final segment in history.segmentsOf(session.id)) {
        for (final effort in history.effortsOf(segment.id)) {
          if (effort.effortKind != 'set') continue;
          final exerciseId = effort.exerciseId;
          if (exerciseId == null ||
              !exerciseIds.contains(exerciseId) ||
              repsAxis.contains(exerciseId)) {
            continue;
          }
          if (_hasBodyweightEntry(history.observationsOf(effort.id))) {
            repsAxis.add(exerciseId);
          }
        }
      }
    }
    return repsAxis;
  }

  /// True when a set effort holds an entry of at least one rep and no load —
  /// the shape that puts an exercise on the reps axis.
  static bool _hasBodyweightEntry(List<EffortObservation> rows) {
    for (final entry in ObservationGrouper.groupByEffortKind('set', rows)) {
      final reps = entry['reps'] as int? ?? 0;
      if (reps <= 0) continue;
      if (((entry['weight'] as num?)?.toDouble() ?? 0.0) <= 0) return true;
    }
    return false;
  }

  /// The section an exercise sits in: the effort kind it was logged under most
  /// often, ties resolving in [ExerciseSection] declaration order. Null when
  /// none of its efforts carries a known kind.
  static ExerciseSection? _sectionForLogs(List<_ExerciseLog> logs) {
    final counts = <ExerciseSection, int>{};
    for (final log in logs) {
      final section = _sectionForKind(log.effort.effortKind);
      if (section == null) continue;
      counts[section] = (counts[section] ?? 0) + 1;
    }

    ExerciseSection? winner;
    var winnerCount = 0;
    for (final section in ExerciseSection.values) {
      final count = counts[section] ?? 0;
      if (count > winnerCount) {
        winner = section;
        winnerCount = count;
      }
    }
    return winner;
  }

  static ExerciseSection? _sectionForKind(String effortKind) {
    switch (effortKind) {
      case 'set':
        return ExerciseSection.resistance;
      case 'timed':
        return ExerciseSection.cardio;
      case 'drill':
        return ExerciseSection.isometric;
      case 'round':
        return ExerciseSection.sports;
      default:
        return null;
    }
  }

  /// The value [logs] yield on [section]'s metric, or null when they yield
  /// none — a day with nothing to read contributes no point.
  Future<NativeValue?> _nativeValueFor(
    List<_ExerciseLog> logs,
    ExerciseSection section,
    bool isRepsAxis,
  ) async {
    switch (section) {
      case ExerciseSection.resistance:
        return _resistanceValue(logs, isRepsAxis);
      case ExerciseSection.cardio:
        return _cardioValue(logs);
      case ExerciseSection.isometric:
        return _isometricValue(logs);
      case ExerciseSection.sports:
        return _sportsValue(logs);
    }
  }

  /// The zero an exercise with no usable data reports, on the metric its
  /// section reads it by.
  static NativeValue _zeroValueFor(ExerciseSection section, bool isRepsAxis) {
    switch (section) {
      case ExerciseSection.resistance:
        return isRepsAxis
            ? const NativeValue(metric: NativeMetric.reps, value: 0)
            : const NativeValue(
                metric: NativeMetric.estimatedOneRepMax,
                value: 0,
              );
      case ExerciseSection.cardio:
        return const NativeValue(metric: NativeMetric.duration, value: 0);
      case ExerciseSection.isometric:
        return const NativeValue(
          metric: NativeMetric.hold,
          value: 0,
          secondaryMetric: NativeMetric.duration,
          secondaryValue: 0,
        );
      case ExerciseSection.sports:
        return const NativeValue(
          metric: NativeMetric.rounds,
          value: 0,
          secondaryMetric: NativeMetric.roundMinutes,
          secondaryValue: 0,
        );
    }
  }

  /// Resistance: the highest e1RM on the weight axis, the highest single-set
  /// reps — with that set's added weight noted — on the reps axis.
  Future<NativeValue> _resistanceValue(
    List<_ExerciseLog> logs,
    bool isRepsAxis,
  ) async {
    final history = await _loadHistory();

    var bestE1RM = 0.0;
    var bestReps = 0;
    var bestAddedWeightKg = 0.0;

    for (final log in logs) {
      if (log.effort.effortKind != 'set') continue;
      final entries = ObservationGrouper.groupByEffortKind(
        'set',
        history.observationsOf(log.effort.id),
      );
      for (final entry in entries) {
        final reps = entry['reps'] as int? ?? 0;
        // A zero-rep set — skipped, or an empty row — reads on neither axis.
        if (reps <= 0) continue;
        final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
        final added = (entry['extra-weight'] as num?)?.toDouble() ?? 0.0;

        if (isRepsAxis) {
          if (reps > bestReps) {
            bestReps = reps;
            bestAddedWeightKg = added;
          } else if (reps == bestReps && added > bestAddedWeightKg) {
            bestAddedWeightKg = added;
          }
        } else {
          final e1rm = StatsProgressService.epley1RM(weight, reps);
          if (e1rm != null && e1rm > bestE1RM) bestE1RM = e1rm;
        }
      }
    }

    if (isRepsAxis) {
      if (bestReps <= 0) return _zeroValueFor(ExerciseSection.resistance, true);
      return NativeValue(
        metric: NativeMetric.reps,
        value: bestReps.toDouble(),
        addedWeightKg: bestAddedWeightKg > 0 ? bestAddedWeightKg : null,
      );
    }
    if (bestE1RM <= 0) return _zeroValueFor(ExerciseSection.resistance, false);
    return NativeValue(
      metric: NativeMetric.estimatedOneRepMax,
      value: bestE1RM,
    );
  }

  /// Cardio: the fastest pace when any entry behind a pace carries a distance,
  /// the summed duration of the finished entries otherwise.
  Future<NativeValue> _cardioValue(List<_ExerciseLog> logs) async {
    final history = await _loadHistory();

    var fastestPaceSecPerKm = 0.0;
    var totalDurationSecs = 0;
    var estimated = false;

    for (final log in logs) {
      if (log.effort.effortKind != 'timed') continue;
      final instances = [...history.timedInstancesOf(log.effort.id)]
        ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
      totalDurationSecs += instances
          .where((t) => t.state == TimedState.finished)
          .fold<int>(0, (sum, t) => sum + t.actualDurationSecs);

      final paired = DistancePairing.forEntries(
        distanceRows: history.observationsOf(log.effort.id),
        entryCount: instances.length,
      );
      for (var i = 0; i < paired.length; i++) {
        final row = paired[i];
        final metres = row?.valueReal ?? 0.0;
        // An entry with no distance, an unfinished entry and a zero-length
        // entry carry no pace (D-309).
        if (metres <= 0) continue;
        if (instances[i].state != TimedState.finished) continue;
        final secs = instances[i].actualDurationSecs;
        if (secs <= 0) continue;

        final paceSecPerKm = secs / (metres / 1000.0);
        if (fastestPaceSecPerKm == 0 || paceSecPerKm < fastestPaceSecPerKm) {
          fastestPaceSecPerKm = paceSecPerKm;
        }
        if (DistanceSource.isEstimated(row?.valueSource)) estimated = true;
      }
    }

    if (fastestPaceSecPerKm > 0) {
      return NativeValue(
        metric: NativeMetric.pace,
        value: fastestPaceSecPerKm,
        estimated: estimated,
      );
    }
    if (totalDurationSecs <= 0) {
      return _zeroValueFor(ExerciseSection.cardio, false);
    }
    return NativeValue(
      metric: NativeMetric.duration,
      value: totalDurationSecs.toDouble(),
    );
  }

  /// Isometric: the longest single hold, with its added weight noted, and the
  /// summed hold time as the secondary figure.
  Future<NativeValue> _isometricValue(List<_ExerciseLog> logs) async {
    final history = await _loadHistory();

    var longestHoldSecs = 0;
    var totalHoldSecs = 0;
    var longestHoldAddedWeightKg = 0.0;

    for (final log in logs) {
      if (log.effort.effortKind != 'drill') continue;
      final instances = [...history.timedInstancesOf(log.effort.id)]
        ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex));
      // The added weight belongs to the entry it was logged for, so it is
      // paired by entry rather than read from the effort's first row.
      final paired = EntryRows.companions(
        rows: history.observationsOf(log.effort.id),
        metricId: MetricIds.extraWeight,
        entryCount: instances.length,
      );
      for (var i = 0; i < instances.length; i++) {
        final instance = instances[i];
        if (instance.state != TimedState.finished) continue;
        totalHoldSecs += instance.actualDurationSecs;
        if (instance.actualDurationSecs > longestHoldSecs) {
          longestHoldSecs = instance.actualDurationSecs;
          longestHoldAddedWeightKg = paired[i]?.valueReal ?? 0.0;
        }
      }
    }

    if (totalHoldSecs <= 0) {
      return _zeroValueFor(ExerciseSection.isometric, false);
    }
    return NativeValue(
      metric: NativeMetric.hold,
      value: longestHoldSecs.toDouble(),
      secondaryMetric: NativeMetric.duration,
      secondaryValue: totalHoldSecs.toDouble(),
      addedWeightKg: longestHoldAddedWeightKg > 0
          ? longestHoldAddedWeightKg
          : null,
    );
  }

  /// Sports: the rounds completed, and their total time in minutes.
  ///
  /// The round predicate is `SessionSummaryBuilder`'s own — finished, started,
  /// and with an end stamp — so the two surfaces cannot disagree. The stored
  /// `completed` flag does not decide: a round stopped early still happened.
  Future<NativeValue> _sportsValue(List<_ExerciseLog> logs) async {
    final history = await _loadHistory();

    var rounds = 0;
    var roundMs = 0;
    for (final log in logs) {
      if (log.effort.effortKind != 'round') continue;
      for (final round in history.roundInstancesOf(log.effort.id)) {
        if (round.state != RoundState.finished) continue;
        if (round.startedAtMs <= 0) continue;
        if (round.finishedAtMs == null) continue;
        rounds++;
        roundMs += round.elapsedMs;
      }
    }

    if (rounds <= 0) return _zeroValueFor(ExerciseSection.sports, false);
    return NativeValue(
      metric: NativeMetric.rounds,
      value: rounds.toDouble(),
      secondaryMetric: NativeMetric.roundMinutes,
      secondaryValue: roundMs / 60000.0,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _processSetEffort(
    SegmentEffort effort,
    DateTime sessionDay,
    Map<String, Map<DateTime, List<_SetTuple>>> setsByExercise,
    Map<String, Map<DateTime, _RepsDay>> repsByExercise,
  ) async {
    final exerciseId = effort.exerciseId;
    if (exerciseId == null) return;

    final observations = (await _loadHistory()).observationsOf(effort.id);
    final entries = ObservationGrouper.groupByEffortKind('set', observations);

    for (final entry in entries) {
      final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
      final reps = entry['reps'] as int? ?? 0;
      // Zero-rep entries (skipped sets, or empty rows) contribute
      // to neither axis.
      if (reps <= 0) continue;

      if (weight > 0) {
        // Loaded set — contributes to the weight-axis trends
        // (e1RM + volume). Any `metric-extra-weight` observation
        // that may sit alongside is intentionally ignored: the
        // axis decision is made on `metric-weight`, never on the
        // annotation row, so a 0 kg weight with a 10 kg belt
        // stays on the reps axis (per the bodyweight-inclusion
        // plan in `docs/plans/stats-summary-fix-pack-plan.md`,
        // Item 2). The choice of axis for the whole exercise is
        // made downstream in `computeProgressData` based on
        // whether the exercise has any reps data at all.
        setsByExercise
            .putIfAbsent(exerciseId, () => {})
            .putIfAbsent(sessionDay, () => [])
            .add(_SetTuple(weight: weight, reps: reps));
      } else {
        // Bodyweight set (or weighted bodyweight: weight = 0,
        // extra-weight = some positive value). Contributes to the
        // reps axis. The day's max-reps wins; the day's max
        // added weight is tracked as an annotation that travels
        // with the trend point — see `TrendPoint.extraWeightKg`.
        // Max added weight is computed across ALL sets that day,
        // not just the winning set, so a day where the heaviest
        // set was pure bodyweight but a later weighted set still
        // used extra weight keeps the annotation.
        final extraWeight = (entry['extra-weight'] as num?)?.toDouble() ?? 0.0;
        final dayMap = repsByExercise.putIfAbsent(exerciseId, () => {});
        final existing = dayMap[sessionDay];
        final dayMaxExtra = [
          existing?.extraWeightKg ?? 0.0,
          extraWeight,
        ].reduce((a, b) => a > b ? a : b);
        if (existing == null) {
          dayMap[sessionDay] = _RepsDay(reps: reps, extraWeightKg: extraWeight);
        } else if (reps > existing.reps) {
          dayMap[sessionDay] = _RepsDay(reps: reps, extraWeightKg: dayMaxExtra);
        } else if (dayMaxExtra > existing.extraWeightKg) {
          // Today's heaviest set isn't this one, but a later
          // (non-winning) set just bumped the day's max added
          // weight — keep the existing max reps and only refresh
          // the annotation.
          dayMap[sessionDay] = _RepsDay(
            reps: existing.reps,
            extraWeightKg: dayMaxExtra,
          );
        }
      }
    }
  }

  /// Returns the top-[n] exercise IDs ordered by distinct training-day count
  /// (descending), with alphabetical name as a tiebreaker. Applies
  /// the recency floor ([kTopExerciseRecencyDays]) so any candidate
  /// whose most-recent training day is older than the threshold
  /// drops out of the displayed top slots regardless of its
  /// historical frequency. The threshold is generous enough that a
  /// normal rotation (e.g. weekly / biweekly) does not flicker a
  /// lift in and out between sessions; dropping out signals
  /// genuine abandonment, not normal spacing
  /// (`docs/plans/stats-summary-fix-pack-plan.md`, Item 3).
  ///
  /// The selection input is a `Map<String, Set<DateTime>>` of
  /// `exerciseId → training days`; the function does not care
  /// whether those days came from the weight axis or the reps axis —
  /// selection is identical across both.
  List<String> _selectTopNWithRecencyFloor(
    Map<String, Set<DateTime>> data,
    int n,
    Map<String, String> nameCache, {
    DateTime? now,
  }) {
    if (data.isEmpty) return const [];

    final today = now ?? DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    // Threshold is inclusive on the trailing edge: a training day
    // exactly `kTopExerciseRecencyDays` days ago still qualifies.
    // Anything strictly older drops out.
    final cutoff = todayMidnight.subtract(
      Duration(days: kTopExerciseRecencyDays),
    );

    final ranked =
        data.entries
            .map((e) {
              final days = e.value;
              DateTime? mostRecent;
              for (final d in days) {
                if (mostRecent == null || d.isAfter(mostRecent)) mostRecent = d;
              }
              return (
                id: e.key,
                count: days.length,
                lastDay: mostRecent,
                name: nameCache[e.key] ?? e.key,
              );
            })
            .where((e) => e.lastDay != null && !e.lastDay!.isBefore(cutoff))
            .toList()
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
        //
        // Calendar arithmetic rather than `subtract(Duration(days: n))`:
        // a Duration is an exact hour span, so subtracting it across a
        // DST transition can land on 23:00 of the day BEFORE the one
        // intended, silently widening the window by a day. `DateTime(y,
        // m, d - n)` normalises across month/year boundaries and always
        // lands on local midnight. Same reasoning as `_startOfIsoWeek`.
        : () {
            final today = DateTime.fromMillisecondsSinceEpoch(todayMs);
            return DateTime(
              today.year,
              today.month,
              today.day - (days - 1),
            ).millisecondsSinceEpoch;
          }();
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
      dayCalories[dayKey] = (dayCalories[dayKey] ?? 0) + r.caloriesConsumed;
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

  /// The Fuel row's figures: intake averaged over logged days, split by
  /// whether the day carried a completed session, against the day's target.
  ///
  /// Returns `null` when nothing has been logged within
  /// [kFuelVisibilityDays] — the row is hidden rather than shown empty,
  /// matching the NUTRITION card's behaviour.
  ///
  /// Averages divide by the number of **logged** days in the group, never
  /// by the window length: a week with three logged days is a three-day
  /// mean, so skipping a day of logging does not read as having eaten
  /// nothing. A group with no logged day yields `null` rather than `0`,
  /// and the widget renders that as an absence.
  ///
  /// A day is a training day when a **completed** session started on it —
  /// the same `endedAtMs != null` rule the rest of this service applies.
  /// An in-progress session does not move today's food into the training
  /// bucket.
  Future<FuelSummary?> computeFuelSummary() async {
    final points = await computeNutritionTrend(days: kFuelVisibilityDays);
    if (points.isEmpty) return null;

    final todayMs = OmniDateUtils.todayMidnightMs();
    final today = DateTime.fromMillisecondsSinceEpoch(todayMs);
    // Calendar arithmetic rather than `subtract(Duration(days: n))` for the
    // DST reason documented on `computeNutritionTrend`.
    final windowStart = DateTime(
      today.year,
      today.month,
      today.day - (kFuelWindowDays - 1),
    );
    final previousStart = DateTime(
      today.year,
      today.month,
      today.day - (2 * kFuelWindowDays - 1),
    );

    final window = <NutritionTrendPoint>[];
    final previous = <NutritionTrendPoint>[];
    for (final p in points) {
      if (!p.date.isBefore(windowStart)) {
        window.add(p);
      } else if (!p.date.isBefore(previousStart)) {
        previous.add(p);
      }
    }

    final trainingDays = await _trainingDayKeys(windowStart, today);
    final training = <NutritionTrendPoint>[];
    final rest = <NutritionTrendPoint>[];
    for (final p in window) {
      if (trainingDays.contains(OmniDateUtils.startOfDayMs(p.date))) {
        training.add(p);
      } else {
        rest.add(p);
      }
    }

    final target = await _repository.getNutritionTargetForDate(todayMs);

    return FuelSummary(
      loggedDays: window.length,
      caloriesAverage: _averageOf(window, (p) => p.calories.toDouble()),
      proteinAverage: _averageOf(window, (p) => p.protein.toDouble()),
      previousCaloriesAverage: _averageOf(
        previous,
        (p) => p.calories.toDouble(),
      ),
      previousProteinAverage: _averageOf(previous, (p) => p.protein.toDouble()),
      trainingCaloriesAverage: _averageOf(
        training,
        (p) => p.calories.toDouble(),
      ),
      trainingProteinAverage: _averageOf(training, (p) => p.protein.toDouble()),
      restCaloriesAverage: _averageOf(rest, (p) => p.calories.toDouble()),
      restProteinAverage: _averageOf(rest, (p) => p.protein.toDouble()),
      targetCalories: target?.calories ?? 0,
      targetProtein: target?.protein ?? 0,
    );
  }

  /// Mean of [pick] over [points], or `null` when there is no point to
  /// average. Dividing by the group's own length — never by a window
  /// length — is what keeps unlogged days out of the denominator.
  static double? _averageOf(
    List<NutritionTrendPoint> points,
    double Function(NutritionTrendPoint) pick,
  ) {
    if (points.isEmpty) return null;
    var total = 0.0;
    for (final p in points) {
      total += pick(p);
    }
    return total / points.length;
  }

  /// Epoch-ms of every day in `[from, to]` on which a completed session
  /// started.
  Future<Set<int>> _trainingDayKeys(DateTime from, DateTime to) async {
    final sessions = (await _loadHistory()).sessions;
    final days = <int>{};
    for (final s in sessions) {
      if (s.endedAtMs == null) continue;
      final day = OmniDateUtils.startOfDayMs(
        DateTime.fromMillisecondsSinceEpoch(s.startedAtMs),
      );
      if (day < OmniDateUtils.startOfDayMs(from)) continue;
      if (day > OmniDateUtils.startOfDayMs(to)) continue;
      days.add(day);
    }
    return days;
  }

  /// Epley 1-rep-max estimate: weight × (1 + reps / 30).
  /// Returns null when weight or reps is zero/negative.
  ///
  /// **Source of truth.** The Stats screen (`computeProgressData`'s
  /// PR detection loop) and the in-session "Congrats! New PR" toast
  /// (see `docs/plans/in-session-pr-toast-plan.md`) both
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
  /// `docs/plans/in-session-pr-toast-plan.md`).
  ///
  /// **Source of truth.** This is the same walk `computeProgressData`
  /// performs when it detects PRs for the Stats screen. In-progress
  /// sessions are intentionally excluded so the in-session toast and
  /// the Stats screen agree on the standing best at the moment of a
  /// new set. Only `effortKind == 'set'` efforts are considered,
  /// matching the "Effort-Type Keying" rule in `docs/stats_screen.md`.
  ///
  /// When [excludeSessionId] is non-null, the named completed session
  /// is skipped — used by the Session Summary so the just-finished
  /// workout's own PRs are not compared against themselves. The
  /// zero-arg call (used by the in-session toast) is unchanged.
  ///
  /// S-009 (in `docs/plans/in-session-pr-toast-plan.md`)
  /// is the structural-guard test that locks this method to the
  /// Stats screen's PR detector for the same input data.
  Future<double> getAllTimeBestE1RM(
    String exerciseId, {
    String? excludeSessionId,
  }) async {
    final sessions = (await _loadHistory()).sessions;
    var completed = sessions.where((s) => s.endedAtMs != null).toList();
    if (excludeSessionId != null) {
      completed = completed.where((s) => s.id != excludeSessionId).toList();
    }

    double best = 0.0;
    for (final session in completed) {
      final segments = (await _loadHistory()).segmentsOf(session.id);
      for (final segment in segments) {
        final efforts = (await _loadHistory()).effortsOf(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          if (effort.exerciseId != exerciseId) continue;

          final observations = (await _loadHistory()).observationsOf(effort.id);
          final entries = ObservationGrouper.groupByEffortKind(
            'set',
            observations,
          );
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

  /// Returns the highest single-set **reps** ever logged for
  /// [exerciseId] across all **completed** sessions, walking only
  /// bodyweight sets (`metric-weight == 0` or absent). Returns
  /// `0` when no prior bodyweight set exists, so callers can use a
  /// single strict `>` comparison to detect a new max-reps PR — a
  /// first-ever bodyweight set is a PR because its positive reps
  /// are strictly greater than `0`.
  ///
  /// **Source of truth.** Mirrors [getAllTimeBestE1RM] for the
  /// reps axis. Used by the in-session "Congrats! New PR" toast
  /// (reps variant) and by the Session Summary's rep-based PR
  /// detection so the same set produces the same verdict on both
  /// surfaces, matching the existing e1RM cross-surface parity
  /// contract (`S-T-001` in `services_test.dart`).
  ///
  /// In-progress sessions are intentionally excluded — the same
  /// reason [getAllTimeBestE1RM] excludes them, so the in-session
  /// toast and the Stats screen agree on the standing best at the
  /// moment of a new set.
  ///
  /// Only `effortKind == 'set'` efforts contribute. The reps axis
  /// is populated for ANY set with `weight == 0`, regardless of
  /// the exercise's equipment label — pull-ups and chin-ups are
  /// included the moment they're logged at bodyweight, no
  /// equipment-label lookup required
  /// (`docs/plans/stats-summary-fix-pack-plan.md`,
  /// Item 2).
  ///
  /// When [excludeSessionId] is non-null, the named completed
  /// session is skipped — used by the Session Summary so the
  /// just-finished workout's own PRs are not compared against
  /// themselves. The zero-arg call (used by the in-session toast)
  /// is unchanged.
  Future<int> getAllTimeBestReps(
    String exerciseId, {
    String? excludeSessionId,
  }) async {
    final sessions = (await _loadHistory()).sessions;
    var completed = sessions.where((s) => s.endedAtMs != null).toList();
    if (excludeSessionId != null) {
      completed = completed.where((s) => s.id != excludeSessionId).toList();
    }

    int best = 0;
    for (final session in completed) {
      final segments = (await _loadHistory()).segmentsOf(session.id);
      for (final segment in segments) {
        final efforts = (await _loadHistory()).effortsOf(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          if (effort.exerciseId != exerciseId) continue;

          final observations = (await _loadHistory()).observationsOf(effort.id);
          final entries = ObservationGrouper.groupByEffortKind(
            'set',
            observations,
          );
          for (final entry in entries) {
            final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
            final reps = entry['reps'] as int? ?? 0;
            // Bodyweight sets only — see the axis-decision rule
            // in `_processSetEffort`. Extra-weight annotations are
            // intentionally not consulted.
            if (weight != 0.0) continue;
            if (reps > best) best = reps;
          }
        }
      }
    }
    return best;
  }

  // ── Window resolution (current-state window for exercise selection) ───────

  /// Resolves the [StatsWindow] used to select which exercises
  /// enter the PR scan. Every caller shares one window in a given
  /// load.
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
    final todayEnd = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
      999,
    );
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
    final sortedDesc = distinctDays.toList()..sort((a, b) => b.compareTo(a));
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

  /// True when [session]'s `startedAtMs` falls within `[fromMs, toMs]`. The
  /// range is inclusive on both ends; the helper centralizes the boundary check
  /// so the selection iteration and the future consumers all agree.
  static bool _sessionInWindow(
    TrainingSession session,
    DateTime fromMs,
    DateTime toMs,
  ) {
    return session.startedAtMs >= fromMs.millisecondsSinceEpoch &&
        session.startedAtMs <= toMs.millisecondsSinceEpoch;
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
    // Both axes are fed through `_processSetEffort` so a single
    // walk yields both weight-axis (loaded sets) and reps-axis
    // (bodyweight sets) trend data. The reps result is discarded
    // here — see [_buildFullRepsForExercises] for its own dedicated
    // full-history walk.
    final repsSentinel = <String, Map<DateTime, _RepsDay>>{};
    for (final session in completed) {
      if (session.endedAtMs == null) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(
        session.startedAtMs,
      );
      final sessionDay = DateTime(
        sessionDt.year,
        sessionDt.month,
        sessionDt.day,
      );
      final segments = (await _loadHistory()).segmentsOf(session.id);
      for (final segment in segments) {
        final efforts = (await _loadHistory()).effortsOf(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          final exId = effort.exerciseId;
          if (exId == null || !selected.contains(exId)) continue;
          await _processSetEffort(effort, sessionDay, result, repsSentinel);
        }
      }
    }
    return result;
  }

  /// Builds a per-selected-exercise full-history reps trend map
  /// (max reps per training day for bodyweight sets, plus the
  /// day's max added weight as an annotation). Parallel
  /// contract to [_buildFullSetsForExercises] — full history for
  /// the selected exercises, windowed only at the selection step.
  Future<Map<String, Map<DateTime, _RepsDay>>> _buildFullRepsForExercises(
    List<TrainingSession> completed,
    List<String> exerciseIds,
  ) async {
    final result = <String, Map<DateTime, _RepsDay>>{};
    if (exerciseIds.isEmpty) return result;
    final selected = exerciseIds.toSet();
    // The weight-axis accumulator is discarded — we only want
    // the reps axis here.
    final setsSentinel = <String, Map<DateTime, List<_SetTuple>>>{};
    for (final session in completed) {
      if (session.endedAtMs == null) continue;
      final sessionDt = DateTime.fromMillisecondsSinceEpoch(
        session.startedAtMs,
      );
      final sessionDay = DateTime(
        sessionDt.year,
        sessionDt.month,
        sessionDt.day,
      );
      final segments = (await _loadHistory()).segmentsOf(session.id);
      for (final segment in segments) {
        final efforts = (await _loadHistory()).effortsOf(segment.id);
        for (final effort in efforts) {
          if (effort.effortKind != 'set') continue;
          final exId = effort.exerciseId;
          if (exId == null || !selected.contains(exId)) continue;
          await _processSetEffort(effort, sessionDay, setsSentinel, result);
        }
      }
    }
    return result;
  }

  /// Returns the per-day actuals (re-using the existing
  /// `computeNutritionTrend` aggregation) and a piecewise
  /// target line that steps at every saved target change.
  /// Historical actuals are never rewritten — the target line
  /// is bound to the actuals' x-axis and reflects the
  /// target that was in effect on each actuals day.
  ///
  /// When no target has ever been saved, `targetLine` is
  /// empty. When no food has been logged, both `actuals` and
  /// `targetLine` are empty (the NUTRITION card is hidden in
  /// that case).
  Future<NutritionAdherence> computeNutritionAdherence() async {
    final actuals = await computeNutritionTrend(days: null);
    if (actuals.isEmpty) {
      return const NutritionAdherence(actuals: [], targetLine: []);
    }

    // Walk every distinct target saved on or before the latest
    // actuals day. Each save point produces one step on the
    // piecewise line. The line is bound to the actuals' x-axis
    // so the chart can overlay it directly.
    final actualsDays = actuals.map((p) => p.date).toList()..sort();
    final lastDay = actualsDays.last;

    // Walk every saved target (via the repository's "get on
    // every day in window" pattern) by stepping the actuals'
    // x-axis one day at a time. The repository's
    // `getNutritionTargetForDate` already walks backward to
    // the most recent ancestor target, so the returned target
    // is always the in-effect value for that day.
    final steps = <DateTime, NutritionTarget>{};
    // Seed with the earliest actuals day so the first step is
    // anchored to the actuals x-axis even when the user saved
    // a target before the earliest actuals day.
    final earliestDay = actualsDays.first;
    final firstMs = DateTime(
      earliestDay.year,
      earliestDay.month,
      earliestDay.day,
    ).millisecondsSinceEpoch;
    final firstTarget = await _repository.getNutritionTargetForDate(firstMs);
    if (firstTarget == null) {
      // No target has ever been saved before / on the first
      // actuals day. The line stays empty.
      return NutritionAdherence(actuals: actuals, targetLine: []);
    }
    steps[earliestDay] = firstTarget;

    // Walk forward one day at a time; whenever the in-effect
    // target changes, emit a new step.
    var cursor = earliestDay;
    var currentTarget = firstTarget;
    while (cursor.isBefore(lastDay)) {
      cursor = cursor.add(const Duration(days: 1));
      final ms = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
      ).millisecondsSinceEpoch;
      final t = await _repository.getNutritionTargetForDate(ms);
      if (t == null) {
        // No target extends this far back from the cursor.
        // We have no further data; stop.
        break;
      }
      if (t.calories != currentTarget.calories ||
          t.protein != currentTarget.protein ||
          t.carbs != currentTarget.carbs ||
          t.fat != currentTarget.fat) {
        steps[cursor] = t;
        currentTarget = t;
      }
    }

    final targetLine =
        steps.entries
            .map(
              (e) => NutritionAdherenceTargetPoint(
                date: e.key,
                calories: e.value.calories,
                protein: e.value.protein,
                carbs: e.value.carbs,
                fat: e.value.fat,
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return NutritionAdherence(actuals: actuals, targetLine: targetLine);
  }
}

class _SetTuple {
  final double weight;
  final int reps;

  const _SetTuple({required this.weight, required this.reps});
}

/// One completed session's time and load, split by section (D-1317).
class _SessionSplit {
  const _SessionSplit({
    required this.timeBySection,
    required this.loadBySection,
  });

  /// Active seconds per section.
  final Map<ExerciseSection, double> timeBySection;

  /// Load minutes per section — zero throughout when the session is unrated.
  final Map<ExerciseSection, double> loadBySection;

  double get timeSeconds =>
      timeBySection.values.fold<double>(0, (a, b) => a + b);
}

/// One effort an exercise was logged under, with the session it belongs to and
/// the local day that session started on.
///
/// `computeExerciseMetrics` groups these by exercise, then by day, so the same
/// value rule can be pointed at either the whole range or a single day.
class _ExerciseLog {
  final TrainingSession session;
  final SegmentEffort effort;
  final int dayMs;

  const _ExerciseLog({
    required this.session,
    required this.effort,
    required this.dayMs,
  });
}

/// One exercise's `set` efforts inside one completed session, with the
/// session's start — the unit the Progression Rate compares.
class _ProgressionGroup {
  _ProgressionGroup({required this.exerciseId, required this.sessionStartMs});

  final String exerciseId;
  final int sessionStartMs;
  final List<_ExerciseLog> logs = <_ExerciseLog>[];
}

/// Per-day reps-axis accumulator for a single exercise. Carries
/// the day's max reps (the value used for the trend point) and
/// the day's max added weight (the annotation that travels with
/// the trend point — `TrendPoint.extraWeightKg`). Added weight
/// is annotation only and never contributes to the kg Total
/// Volume figure.
class _RepsDay {
  final int reps;
  final double extraWeightKg;

  const _RepsDay({required this.reps, required this.extraWeightKg});
}
