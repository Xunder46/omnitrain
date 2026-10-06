// Stats PR 7b Phase 2 — `StatsProgressService.interferenceSessions()` over
// both repository harnesses: the per-session payloads (D-1316), the shared
// split's Sports figure (S-2012), the unrated session's zero (S-2009) and the
// exclusion of the other follow-ups from a prior average (S-2011).
//
// Plan: `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/interference.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── The plan's clock and days ──────────────────────────────────────────────

/// The plan's `now`: a fixed anchor, so `day(n)` is a calendar date and the
/// fixture never moves with the clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// The plan's `day(n)`: the local-midnight day `n` days before `now`.
DateTime _day(int daysAgo) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo);

/// 09:00 local on `day(daysAgo)` — every fixture session starts there.
DateTime _at(int daysAgo) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, 9);
}

/// The end of `now`'s own day, so a window call covers the whole of it.
final DateTime _todayEnd = DateTime(
  _now.year,
  _now.month,
  _now.day,
  23,
  59,
  59,
);

// ─── F-INT: the seeded fixture ──────────────────────────────────────────────

/// F-INT's rated sports sessions: `daysAgo: (rating, round seconds)`, the round
/// effort being the session's whole duration.
const Map<int, (int, int)> _sportsSessions = {
  88: (4, 60),
  80: (4, 120),
  70: (4, 180),
  60: (4, 300),
  44: (4, 360),
  30: (5, 600),
  20: (4, 420),
  10: (5, 492),
};

/// F-INT's rated lifting sessions, all one `ex-lift` set of 1 rep at 100 kg.
const List<int> _liftDays = [62, 55, 50, 40, 33, 26, 22, 12, 6, 2];

/// F-INT's follow-ups: `daysAgo: weight`, one `ex-lift` set of 1 rep.
const Map<int, double> _followUps = {29: 84.0, 19: 90.0, 9: 89.0};

/// The rated sessions that put the Mix layer on the load measure: 4 distinct
/// 7-calendar-day blocks before `day(89)`, the window's start day (D-908).
/// They carry no efforts, so they cannot reach the rule.
const List<int> _baselineDays = [96, 110, 124, 138];

/// A session with an explicit start, end and rating, plus the one segment its
/// efforts hang on. The shared `seedSession` cannot express these: it
/// hard-codes a 60-minute non-rolling session and takes no rating.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required DateTime end,
  int? rating,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: end.millisecondsSinceEpoch,
      sessionFeeling: rating,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

/// A sports session whose single finished round effort is its whole duration,
/// so its time and load are Sports only.
Future<void> _seedSportsSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required int seconds,
  int? rating,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: start,
    end: start.add(Duration(seconds: seconds)),
    rating: rating,
  );
  await seedExercise(repo, id: 'ex-$id', name: 'Sports');
  await seedRoundEffort(
    repo,
    segmentId: 'seg-$id',
    effortId: 'ef-$id',
    exerciseId: 'ex-$id',
    rounds: [roundInstance('ef-$id', 0, durationSecs: seconds)],
  );
}

/// A one-hour lifting session carrying one `ex-lift` set of 1 rep at
/// [weightKg].
Future<void> _seedLiftingSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required double weightKg,
  int? rating = 4,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: start,
    end: start.add(const Duration(hours: 1)),
    rating: rating,
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$id',
    effortId: 'ef-$id',
    exerciseId: 'ex-lift',
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: weightKg,
    repsBase: 1,
  );
}

/// F-INT: the plan's seeded fixture. [omitSportsDays] drops a sports session so
/// S-2005(b) can seed the seven-session population.
Future<void> _seedFInt(
  WorkoutRepository repo, {
  Set<int> omitSportsDays = const <int>{},
}) async {
  await seedExercise(
    repo,
    id: 'ex-lift',
    name: 'Lift',
    capabilities: const ['load', 'reps'],
  );
  for (final entry in _sportsSessions.entries) {
    if (omitSportsDays.contains(entry.key)) continue;
    await _seedSportsSession(
      repo,
      id: 'sports-${entry.key}',
      start: _at(entry.key),
      seconds: entry.value.$2,
      rating: entry.value.$1,
    );
  }
  for (final day in _liftDays) {
    await _seedLiftingSession(
      repo,
      id: 'lift-$day',
      start: _at(day),
      weightKg: 100.0,
    );
  }
  for (final entry in _followUps.entries) {
    await _seedLiftingSession(
      repo,
      id: 'fu-${entry.key}',
      start: _at(entry.key),
      weightKg: entry.value,
    );
  }
  for (final day in _baselineDays) {
    await _seedSession(
      repo,
      id: 'base-$day',
      start: _at(day),
      end: _at(day).add(const Duration(hours: 1)),
      rating: 4,
    );
  }
}

// ─── Read helpers ───────────────────────────────────────────────────────────

InterferenceSession _payload(List<InterferenceSession> walk, String id) =>
    walk.firstWhere((session) => session.id == id);

StatsWindow _window(DateTime from, DateTime to) => StatsWindow(
  fromMs: from,
  toMs: to,
  label: 'Test window',
  isPeriodScoped: true,
);

double _epley(double weightKg, int reps) =>
    StatsProgressService.epley1RM(weightKg, reps)!;

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — interferenceSessions', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('D-1316 the walk carries every completed session\'s payload', () async {
        await _seedFInt(repo);

        final walk = await StatsProgressService(repo).interferenceSessions();

        final completed = (await repo.getAllSessions())
            .where((session) => session.endedAtMs != null)
            .map((session) => session.id)
            .toSet();
        expect(walk.map((session) => session.id).toSet(), completed);

        // Ordered by start, ties by id.
        for (var i = 1; i < walk.length; i++) {
          final previous = walk[i - 1];
          final current = walk[i];
          expect(
            previous.startMs < current.startMs ||
                (previous.startMs == current.startMs &&
                    previous.id.compareTo(current.id) < 0),
            isTrue,
            reason: 'payloads $i and ${i - 1} are out of order',
          );
        }

        final sports = _payload(walk, 'sports-30');
        expect(sports.sportsLoadMinutes, closeTo(50.0, 1e-9));
        expect(sports.rating, 5);
        expect(sports.hasSetEffort, isFalse);
        expect(sports.startMs, _at(30).millisecondsSinceEpoch);
        expect(sports.endMs, _at(30).add(const Duration(seconds: 600)).millisecondsSinceEpoch);
        expect(sports.bests, isNot(contains('ex-lift')));

        final lift = _payload(walk, 'lift-62');
        expect(lift.sportsLoadMinutes, 0.0);
        expect(lift.rating, 4);
        expect(lift.hasSetEffort, isTrue);
        expect(lift.bests, hasLength(1));
        expect(lift.bests['ex-lift'], closeTo(_epley(100.0, 1), 1e-9));

        final followUp = _payload(walk, 'fu-29');
        expect(followUp.sportsLoadMinutes, 0.0);
        expect(followUp.hasSetEffort, isTrue);
        expect(followUp.bests['ex-lift'], closeTo(_epley(84.0, 1), 1e-9));

        final firstSports = _payload(walk, 'sports-88');
        expect(firstSports.rating, 4);
        expect(firstSports.sportsLoadMinutes, closeTo(4.0, 1e-9));
      });

      test('S-2005 the walk feeds the rule the pack\'s counts', () async {
        await _seedFInt(repo);

        final walk = await StatsProgressService(repo).interferenceSessions();
        final result = crossModalityInterference(sessions: walk, now: _now);

        expect(result, isNotNull);
        expect(result!.k, 3);
        expect(result.n, 3);
        expect(result.lo, 10);
        expect(result.hi, 16);
        expect(result.hasSportsLoadRise, isTrue);
        expect(result.sportsLoadRisePercent, 38);

        final analysis = analyseInterference(sessions: walk, now: _now);
        expect(
          analysis.hardSessionIds.toSet(),
          {'sports-30', 'sports-20', 'sports-10'},
        );
        expect(analysis.followUpIdByHardId, {
          'sports-30': 'fu-29',
          'sports-20': 'fu-19',
          'sports-10': 'fu-9',
        });
      });

      test('S-2005(b) seven rated sports sessions never classify', () async {
        await _seedFInt(repo, omitSportsDays: const {88});

        final walk = await StatsProgressService(repo).interferenceSessions();

        expect(crossModalityInterference(sessions: walk, now: _now), isNull);
      });

      test('S-2011 the prior average excludes the other follow-ups', () async {
        await _seedFInt(repo);

        final walk = await StatsProgressService(repo).interferenceSessions();
        final analysis = analyseInterference(sessions: walk, now: _now);

        // The day-29 follow-up at 84 kg on a 103.3333 average is 16%; the
        // day-19 at 90 kg is exactly one tenth; the day-9 at 89 kg is 11%.
        expect(
          analysis.shortfallMeanByFollowUpId['fu-29'],
          closeTo(0.16, 1e-9),
        );
        expect(
          analysis.shortfallMeanByFollowUpId['fu-19'],
          closeTo(0.10, 1e-9),
        );
        expect(
          analysis.shortfallMeanByFollowUpId['fu-9'],
          closeTo(0.11, 1e-9),
        );
        // The counterfactual: including the day-29 follow-up in the day-19
        // lookback would read 7% and the card would not fire.
        expect(analysis.dippedFollowUpIds.toSet(), {'fu-29', 'fu-19', 'fu-9'});
      });

      test('S-2012 the Sports load is the Mix layer\'s own figure', () async {
        await _seedFInt(repo);

        final service = StatsProgressService(repo);
        final walk = await service.interferenceSessions();
        final data = (await service.computeMixLayer(
          window: _window(_day(89), _todayEnd),
          now: _now,
          startOfWeek: 'monday',
        ))!;

        expect(data.measure, MixMeasure.load);
        final sports = data.segments.firstWhere(
          (segment) => segment.section == ExerciseSection.sports,
        );

        final fromMs = _day(89).millisecondsSinceEpoch;
        final toMs = _todayEnd.millisecondsSinceEpoch;
        final sum = walk
            .where(
              (session) =>
                  session.startMs >= fromMs && session.startMs <= toMs,
            )
            .fold<double>(0, (total, session) => total + session.sportsLoadMinutes);

        expect(sum, closeTo(187.0, 1e-9));
        expect(sports.measure, closeTo(sum, 1e-9));
      });

      test('S-2009 an unrated sports session reports zero Sports load', () async {
        await _seedFInt(repo);
        await _seedSportsSession(
          repo,
          id: 'unrated-sports',
          start: _at(5),
          seconds: 3600,
          rating: null,
        );

        final walk = await StatsProgressService(repo).interferenceSessions();
        final unrated = _payload(walk, 'unrated-sports');
        expect(unrated.rating, isNull);
        expect(unrated.sportsLoadMinutes, 0.0);

        final result = crossModalityInterference(sessions: walk, now: _now);
        expect(result, isNotNull);
        expect(result!.k, 3);
        expect(result.n, 3);
        expect(result.lo, 10);
        expect(result.hi, 16);
        expect(result.sportsLoadRisePercent, 38);
      });

      test('D-1316 the walk orders by start, ties by id', () async {
        final start = _at(10);
        final end = start.add(const Duration(minutes: 30));
        await _seedSession(repo, id: 'sess-b', start: start, end: end, rating: 4);
        await _seedSession(repo, id: 'sess-a', start: start, end: end, rating: 4);
        await _seedSession(
          repo,
          id: 'sess-c',
          start: _at(11),
          end: _at(11).add(const Duration(minutes: 30)),
          rating: 4,
        );

        final walk = await StatsProgressService(repo).interferenceSessions();

        expect(walk.map((session) => session.id).toList(), [
          'sess-c',
          'sess-a',
          'sess-b',
        ]);
      });
    });
  }
}
