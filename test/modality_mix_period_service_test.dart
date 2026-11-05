// Stats PR 7a Phase 1 — `StatsProgressService.computeMixPeriod` over both
// repository harnesses: the period payload is the Mix layer's own figures
// (S-1907), the time measure abstains (S-1904a) and the period's bounds and
// abutting baseline blocks are exact (S-1913).
//
// Plan: `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

/// The plan's `now`: a fixed anchor, so `day(n)` is a calendar date and the
/// fixture never moves with the clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// The plan's `day(n)`: the local-midnight day `n` days before `now`.
DateTime _day(int daysAgo) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo);

/// [hour]:00 local on `day(daysAgo)`.
DateTime _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour);
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

/// A session with an explicit start, end and rating, plus the one segment its
/// efforts hang on. The shared `seedSession` cannot express these: it
/// hard-codes a 60-minute session and takes no rating.
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

/// A rated hour session starting at [start], carrying one effort of [kind]
/// lasting [seconds] — `timed` (cardio), `drill` (isometric), `round` (sports)
/// or `set` (resistance, which measures no time at all).
Future<void> _seedWork(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required String kind,
  required int seconds,
  int rating = 4,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: start,
    end: start.add(const Duration(hours: 1)),
    rating: rating,
  );
  final exerciseId = 'ex-$id';
  await seedExercise(repo, id: exerciseId, name: 'Work');
  switch (kind) {
    case 'timed':
    case 'drill':
      await seedHoldEffort(
        repo,
        segmentId: 'seg-$id',
        effortId: 'ef-$id',
        exerciseId: exerciseId,
        entryCount: 1,
        secondsPerEntry: seconds,
        effortKind: kind,
      );
    case 'round':
      await seedRoundEffort(
        repo,
        segmentId: 'seg-$id',
        effortId: 'ef-$id',
        exerciseId: exerciseId,
        rounds: [roundInstance('ef-$id', 0, durationSecs: seconds)],
      );
    case 'set':
      await seedSetEffort(
        repo,
        segmentId: 'seg-$id',
        effortId: 'ef-$id',
        exerciseId: exerciseId,
        entryCount: 3,
        hasExtraWeight: false,
      );
  }
}

/// F-MIX: a mixed history — rated sessions across the last twelve weeks carrying
/// resistance, cardio, isometric and sports work, five rated baseline blocks
/// before `day(27)`, and a period bar with more than one non-zero modality.
Future<void> _seedFMix(WorkoutRepository repo) async {
  // The period `[day(27), now]`: cardio and resistance.
  await _seedWork(
    repo,
    id: 'fmix-p1',
    start: _at(20, 9),
    kind: 'timed',
    seconds: 600,
  );
  await _seedWork(
    repo,
    id: 'fmix-p2',
    start: _at(10, 9),
    kind: 'timed',
    seconds: 1200,
    rating: 3,
  );

  // One rated session in each of the baseline blocks 4…8 — days 80, 73, 66, 59
  // and 52 ago. All five sit inside the 12 rated weeks ending at the period's
  // end day (rated block `11 − ⌊d / 7⌋` = 0…4, D-17105), so with the period's
  // own sessions — days 20 and 10 ago, rated blocks 9 and 10 — the payload
  // counts 7 rated weeks. Rated blocks 5…8 and 11 stay empty, so a session
  // that lands there is visible in `ratedWeeks`.
  await _seedWork(
    repo,
    id: 'fmix-b0',
    start: _at(80, 9),
    kind: 'drill',
    seconds: 1200,
  );
  await _seedWork(
    repo,
    id: 'fmix-b1',
    start: _at(73, 9),
    kind: 'round',
    seconds: 600,
    rating: 3,
  );
  await _seedWork(
    repo,
    id: 'fmix-b2',
    start: _at(66, 9),
    kind: 'set',
    seconds: 0,
  );
  await _seedWork(
    repo,
    id: 'fmix-b3',
    start: _at(59, 9),
    kind: 'timed',
    seconds: 900,
    rating: 2,
  );
  await _seedWork(
    repo,
    id: 'fmix-b4',
    start: _at(52, 9),
    kind: 'set',
    seconds: 0,
  );
}

/// S-1913's three extra sessions: the period's first instant, one millisecond
/// before it, and the first instant of the day after it.
Future<void> _seedS1913(WorkoutRepository repo) async {
  await _seedWork(
    repo,
    id: 's1913-x',
    start: _day(27),
    kind: 'drill',
    seconds: 1200,
  );
  await _seedWork(
    repo,
    id: 's1913-y',
    start: _day(27).subtract(const Duration(milliseconds: 1)),
    kind: 'round',
    seconds: 600,
  );
  await _seedWork(
    repo,
    id: 's1913-z',
    start: _day(28),
    kind: 'round',
    seconds: 600,
  );
}

/// F-TIME: five rated sessions with one timed effort each — three inside the
/// period `[day(27), now]` (days 1, 3 and 5 back, all in rated block 11) and
/// two behind it (days 29 and 36 back, rated blocks 7 and 6) — so the payload
/// counts 3 rated weeks, one short of the 4 the load measure needs (D-17105).
Future<void> _seedFTime(WorkoutRepository repo) async {
  for (final days in [1, 3, 5, 29, 36]) {
    await _seedWork(
      repo,
      id: 'ftime-$days',
      start: _at(days, 9),
      kind: 'timed',
      seconds: 600,
    );
  }
}

// ─── Read helpers ───────────────────────────────────────────────────────────

StatsWindow _window(DateTime from, DateTime to) => StatsWindow(
  fromMs: from,
  toMs: to,
  label: 'Test window',
  isPeriodScoped: false,
);

/// The period payload both phases read: `[day(27), now]`.
Future<MixLayerData?> _period(StatsProgressService service) =>
    service.computeMixPeriod(fromMs: _day(27), toMs: _now);

/// The equivalent window call, with the whole of `now`'s day in range.
Future<MixLayerData?> _layer(StatsProgressService service) =>
    service.computeMixLayer(
      window: _window(_day(27), _todayEnd),
      now: _now,
      startOfWeek: 'monday',
    );

MixSegment _segment(List<MixSegment> segments, ExerciseSection section) =>
    segments.firstWhere((segment) => segment.section == section);

/// A comparable description of a bar, so two payloads can be compared value for
/// value — order, section, exact measure and rounded percent.
List<String> _shape(List<MixSegment> segments) => [
  for (final segment in segments)
    '${segment.section.name}|${segment.measure}|${segment.percent}',
];

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — computeMixPeriod', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'S-1907 the period payload is the Mix layer\'s own figures',
        () async {
          await _seedFMix(repo);
          final service = StatsProgressService(repo);

          final period = (await _period(service))!;
          final layer = (await _layer(service))!;

          expect(period.measure, layer.measure);
          expect(_shape(period.segments), _shape(layer.segments));
          expect(
            _shape(period.baselineSegments),
            _shape(layer.baselineSegments),
          );
          expect(period.unratedSessionCount, layer.unratedSessionCount);
          expect(period.ratedWeeks, layer.ratedWeeks);

          expect(period.measure, MixMeasure.load);
          expect(_shape(period.segments), [
            '${ExerciseSection.resistance.name}|320.0|76',
            '${ExerciseSection.cardio.name}|100.0|24',
          ]);
          expect(period.ratedWeeks, 7);
          expect(period.weeks, isEmpty);
          expect(layer.weeks, isNotEmpty);
        },
      );

      test(
        'S-1904a a period whose baseline is not rated enough reports time',
        () async {
          await _seedFTime(repo);

          final period = (await _period(StatsProgressService(repo)))!;

          expect(period.measure, MixMeasure.time);
          expect(period.baselineSegments, isEmpty);
          expect(period.ratedWeeks, 3);
          expect(period.unratedSessionCount, 0);
          expect(period.segments, isNotEmpty);
        },
      );

      test(
        'S-1913 the period\'s bounds and the abutting baseline are exact',
        () async {
          await _seedFMix(repo);
          await _seedS1913(repo);

          final period = (await _period(StatsProgressService(repo)))!;

          // The session starting exactly at `day(27)` 00:00 is in the period: it
          // is the only isometric work there.
          expect(
            _segment(period.segments, ExerciseSection.isometric).measure,
            80.0,
          );
          expect(
            _segment(period.segments, ExerciseSection.resistance).measure,
            480.0,
          );
          expect(
            period.segments.any(
              (segment) => segment.section == ExerciseSection.sports,
            ),
            isFalse,
          );

          // The session one millisecond earlier is not, and it joins the rated
          // week that abuts the period's start day — block 7, which spans
          // `[endDay − 34, endDay − 27)` and which F-MIX alone leaves empty.
          // The session at `day(28)` 00:00 is in that block too, and the
          // session at `day(27)` 00:00 — the period's own first instant —
          // lands in block 8: the period's sessions count (D-17105). F-MIX
          // alone fills blocks 0…4, 9 and 10; adding 7 and 8 counts 9.
          expect(period.ratedWeeks, 9);
          expect(
            _segment(period.baselineSegments, ExerciseSection.sports).measure,
            110.0,
          );
          expect(
            _segment(
              period.baselineSegments,
              ExerciseSection.isometric,
            ).measure,
            80.0,
          );
          expect(
            _segment(period.baselineSegments, ExerciseSection.cardio).measure,
            30.0,
          );
          expect(
            _segment(
              period.baselineSegments,
              ExerciseSection.resistance,
            ).measure,
            1280.0,
          );
        },
      );
    });
  }
}
