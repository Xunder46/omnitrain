// Stats PR 5a Phase 2 — `StatsProgressService.computeMixLayer` over both
// repository harnesses, and its agreement with the Instruments list.
//
// Plan: `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

/// A session with an explicit start, end, rating and rolling flag, plus the one
/// segment its efforts hang on.
///
/// The shared `seedSession` cannot express these: it hard-codes a 60-minute
/// non-rolling session, takes no rating, and leaves a rolling session with no
/// end (an unfinished session, which D-911 excludes).
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  required DateTime end,
  int? rating,
  bool isRolling = false,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: end.millisecondsSinceEpoch,
      sessionFeeling: rating,
      isRolling: isRolling,
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

/// The plan's "rated-ready" baseline: one 60-minute session rated 4 in each of
/// four distinct 7-calendar-day blocks before [fromDay].
Future<void> _seedRatedBaseline(
  WorkoutRepository repo,
  DateTime fromDay, {
  int sessions = 4,
}) async {
  const offsets = [80, 60, 40, 20];
  for (var i = 0; i < sessions; i++) {
    final day = DateTime(fromDay.year, fromDay.month, fromDay.day - offsets[i]);
    await _seedSession(
      repo,
      id: 'baseline-$i',
      start: DateTime(day.year, day.month, day.day, 9),
      end: DateTime(day.year, day.month, day.day, 10),
      rating: 4,
    );
  }
}

/// A 60-minute session on [day] at 09:00, with [efforts] hung on its segment.
Future<void> _seedHourSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime day,
  int? rating,
  bool isRolling = false,
}) async {
  await _seedSession(
    repo,
    id: id,
    start: DateTime(day.year, day.month, day.day, 9),
    end: DateTime(day.year, day.month, day.day, 10),
    rating: rating,
    isRolling: isRolling,
  );
}

/// A lifting effort on [sessionId]'s segment, so the session reads as work.
Future<void> _seedLiftingEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  int entryCount = 3,
}) async {
  await seedExercise(repo, id: exerciseId, name: 'Deadlift');
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'ef-$sessionId',
    exerciseId: exerciseId,
    entryCount: entryCount,
    hasExtraWeight: false,
  );
}

// ─── Read helpers ───────────────────────────────────────────────────────────

StatsWindow _window(DateTime from, DateTime to) => StatsWindow(
  fromMs: from,
  toMs: to,
  label: 'Test window',
  isPeriodScoped: false,
);

Future<MixLayerData?> _mix(
  WorkoutRepository repo, {
  required StatsWindow window,
  required DateTime now,
  String startOfWeek = 'monday',
}) => StatsProgressService(repo).computeMixLayer(
  window: window,
  now: now,
  startOfWeek: startOfWeek,
);

MixSegment _segment(MixLayerData data, ExerciseSection section) =>
    data.segments.firstWhere((segment) => segment.section == section);

List<ExerciseSection> _sectionsOf(List<MixSegment> segments) => [
  for (final segment in segments) segment.section,
];

List<int> _percentsOf(List<MixSegment> segments) => [
  for (final segment in segments) segment.percent,
];

int _percentTotal(List<MixSegment> segments) =>
    segments.fold<int>(0, (sum, segment) => sum + segment.percent);

double _weekTotal(List<MixWeek> weeks) =>
    weeks.fold<double>(0, (sum, week) => sum + week.measure);

/// A comparable description of a bar, so two repositories can be compared
/// value for value.
List<String> _barShape(List<MixSegment> segments) => [
  for (final segment in segments)
    '${segment.section.name}:${segment.measure}:${segment.percent}',
];

List<String> _layerShape(MixLayerData data) => [
  'measure=${data.measure.name}',
  'segments=${_barShape(data.segments)}',
  'baseline=${_barShape(data.baselineSegments)}',
  'unrated=${data.unratedSessionCount}',
  'ratedBaselineWeeks=${data.ratedBaselineWeeks}',
  for (final week in data.weeks)
    'week=${week.weekStart.toIso8601String()}|${week.measure}'
        '|${week.inProgress}|${_barShape(week.segments)}',
];

// ─── The shared fixtures the parity group seeds into both stores ────────────

/// S-1503's fixture: a rated free-training session with one 20-minute hold.
Future<void> _seedS1503(WorkoutRepository repo) async {
  final t = DateTime(2026, 5, 13, 10);
  await _seedSession(
    repo,
    id: 's1503',
    start: t,
    end: DateTime(2026, 5, 13, 11),
    rating: 3,
  );
  await seedExercise(repo, id: 'ex-hold', name: 'Plank');
  await seedHoldEffort(
    repo,
    segmentId: 'seg-s1503',
    effortId: 'ef-hold',
    exerciseId: 'ex-hold',
    entryCount: 1,
    secondsPerEntry: 1200,
  );
  await _seedRatedBaseline(repo, DateTime(2026, 5, 12));
}

/// S-1513's fixture: five unrated 60-minute sessions at the plan's offsets from
/// [now].
Future<void> _seedS1513(WorkoutRepository repo, DateTime now) async {
  for (final days in [0, 7, 8, 30, 90]) {
    await _seedHourSession(
      repo,
      id: 's1513-$days',
      day: DateTime(now.year, now.month, now.day - days),
    );
    await _seedLiftingEffort(
      repo,
      sessionId: 's1513-$days',
      exerciseId: 'ex-dl-$days',
    );
  }
}

void main() {
  final now = DateTime(2026, 5, 13, 10);

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — computeMixLayer', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-1501 a 60-minute session rated 4 is 240 load', () async {
        await _seedSession(
          repo,
          id: 's1501',
          start: now,
          end: DateTime(2026, 5, 13, 11),
          rating: 4,
        );
        await _seedRatedBaseline(repo, DateTime(2026, 5, 12));

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.load);
        expect(_sectionsOf(data.segments), [ExerciseSection.resistance]);
        expect(_segment(data, ExerciseSection.resistance).measure, 240.0);
        expect(_percentsOf(data.segments), [100]);
        expect(data.unratedSessionCount, 0);
        expect(data.ratedBaselineWeeks, 4);
        expect(data.baselineSegments, isNotEmpty);
      });

      test('S-1502 an unrated 60-minute session adds no load and '
          'one unrated count', () async {
        await _seedSession(
          repo,
          id: 's1502',
          start: now,
          end: DateTime(2026, 5, 13, 11),
        );

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(_sectionsOf(data.segments), [ExerciseSection.resistance]);
        expect(_segment(data, ExerciseSection.resistance).measure, 60.0);
        expect(_percentsOf(data.segments), [100]);
        expect(data.unratedSessionCount, 1);
        expect(data.ratedBaselineWeeks, 0);
        expect(data.baselineSegments, isEmpty);
      });

      test('S-1503 a rated free-training session is 67/33 in load', () async {
        await _seedS1503(repo);

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.load);
        expect(_sectionsOf(data.segments), [
          ExerciseSection.resistance,
          ExerciseSection.isometric,
        ]);
        expect(_segment(data, ExerciseSection.resistance).measure, 120.0);
        expect(_segment(data, ExerciseSection.resistance).percent, 67);
        expect(_segment(data, ExerciseSection.isometric).measure, 60.0);
        expect(_segment(data, ExerciseSection.isometric).percent, 33);
        expect(_percentTotal(data.segments), 100);
      });

      test('S-1505 a 75-minute lifting session with a 15-minute '
          'timed warm-up', () async {
        await _seedSession(
          repo,
          id: 's1505',
          start: now,
          end: DateTime(2026, 5, 13, 11, 15),
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1505',
          exerciseId: 'ex-dl',
        );
        await seedExercise(repo, id: 'ex-tread', name: 'Treadmill');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s1505',
          effortId: 'ef-warm',
          exerciseId: 'ex-tread',
          entryCount: 1,
          secondsPerEntry: 900,
          effortKind: 'timed',
        );

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(_sectionsOf(data.segments), [
          ExerciseSection.resistance,
          ExerciseSection.cardio,
        ]);
        expect(_segment(data, ExerciseSection.resistance).measure, 60.0);
        expect(_segment(data, ExerciseSection.cardio).measure, 15.0);
        expect(_percentsOf(data.segments), [80, 20]);
      });

      test('S-1509 a sets-only rolling session contributes nothing', () async {
        final window = _window(DateTime(2026, 5, 12), DateTime(2026, 5, 14));
        await _seedHourSession(
          repo,
          id: 's1509-roll',
          day: DateTime(2026, 5, 12),
          isRolling: true,
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1509-roll',
          exerciseId: 'ex-roll',
          entryCount: 5,
        );

        expect(await _mix(repo, window: window, now: now), isNull);

        await _seedSession(
          repo,
          id: 's1509-lift',
          start: DateTime(2026, 5, 13, 9),
          end: DateTime(2026, 5, 13, 9, 30),
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1509-lift',
          exerciseId: 'ex-dl',
        );

        final data = (await _mix(repo, window: window, now: now))!;

        expect(_sectionsOf(data.segments), [ExerciseSection.resistance]);
        expect(_segment(data, ExerciseSection.resistance).measure, 30.0);
        expect(_percentsOf(data.segments), [100]);
      });

      test('S-1510 A exactly 4 rated baseline weeks shows load', () async {
        for (final day in [10, 11, 12, 13]) {
          await _seedHourSession(
            repo,
            id: 's1510a-$day',
            day: DateTime(2026, 5, day),
            rating: 4,
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1510a-$day',
            exerciseId: 'ex-dl-$day',
          );
        }
        await _seedRatedBaseline(repo, DateTime(2026, 5, 10));

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 13, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.load);
        expect(data.ratedBaselineWeeks, 4);
        expect(_segment(data, ExerciseSection.resistance).measure, 960.0);
        expect(data.baselineSegments, isNotEmpty);
      });

      test('S-1510 B three rated baseline weeks shows time', () async {
        for (final day in [10, 11, 12, 13]) {
          await _seedHourSession(
            repo,
            id: 's1510b-$day',
            day: DateTime(2026, 5, day),
            rating: 4,
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1510b-$day',
            exerciseId: 'ex-dl-$day',
          );
        }
        await _seedRatedBaseline(repo, DateTime(2026, 5, 10), sessions: 3);

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 13, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(data.ratedBaselineWeeks, 3);
        expect(data.baselineSegments, isEmpty);
      });

      test('S-1510 C exactly 25% unrated still shows load', () async {
        final ratings = <int, int?>{10: 4, 11: 5, 12: 3, 13: null};
        for (final entry in ratings.entries) {
          await _seedHourSession(
            repo,
            id: 's1510c-${entry.key}',
            day: DateTime(2026, 5, entry.key),
            rating: entry.value,
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1510c-${entry.key}',
            exerciseId: 'ex-dl-${entry.key}',
          );
        }
        await _seedRatedBaseline(repo, DateTime(2026, 5, 10));

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 13, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.load);
        expect(data.unratedSessionCount, 1);
        expect(_segment(data, ExerciseSection.resistance).measure, 720.0);
      });

      test('S-1510 D a third of the window unrated shows time', () async {
        final ratings = <int, int?>{11: 4, 12: 4, 13: null};
        for (final entry in ratings.entries) {
          await _seedHourSession(
            repo,
            id: 's1510d-${entry.key}',
            day: DateTime(2026, 5, entry.key),
            rating: entry.value,
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1510d-${entry.key}',
            exerciseId: 'ex-dl-${entry.key}',
          );
        }
        await _seedRatedBaseline(repo, DateTime(2026, 5, 10));

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 13, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(data.unratedSessionCount, 1);
        expect(data.ratedBaselineWeeks, 4);
        expect(_segment(data, ExerciseSection.resistance).measure, 180.0);
      });

      test('S-1510 E a wholly unrated window never reads as load', () async {
        for (final day in [12, 13]) {
          await _seedHourSession(
            repo,
            id: 's1510e-$day',
            day: DateTime(2026, 5, day),
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1510e-$day',
            exerciseId: 'ex-dl-$day',
          );
        }
        await _seedRatedBaseline(repo, DateTime(2026, 5, 10));

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 13, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(data.unratedSessionCount, 2);
        expect(data.ratedBaselineWeeks, 4);
        expect(data.baselineSegments, isEmpty);
      });

      test('S-1511 the baseline is the 12 blocks before the window, '
          'with no gap', () async {
        final w = DateTime(2026, 5, 11);
        expect(w.weekday, DateTime.monday);
        // W−1d, W−84d, W−85d, and W+1d inside the window.
        await _seedHourSession(
          repo,
          id: 's1511-before',
          day: DateTime(2026, 5, 10),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-first',
          day: DateTime(2026, 2, 16),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-older',
          day: DateTime(2026, 2, 15),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-window',
          day: DateTime(2026, 5, 12),
          rating: 4,
        );

        final window = _window(w, DateTime(2026, 5, 17, 23, 59));
        final data = (await _mix(repo, window: window, now: now))!;

        // The block holding W−84d counts, the one before it does not, and the
        // window's own session is never in its own baseline.
        expect(data.ratedBaselineWeeks, 2);
        expect(data.unratedSessionCount, 0);
        expect(_segment(data, ExerciseSection.resistance).measure, 60.0);
        // The plan's S-1511 sentence about a baseline segment conflicts with
        // its own step 2 (baseline segments exist in the load measure only);
        // step 2 wins — the plan's Assumption Log entry 2 records the
        // divergence.
        expect(data.measure, MixMeasure.time);
        expect(data.baselineSegments, isEmpty);
      });

      test('S-1511 fixture B a period-scoped window keeps the same baseline '
          'and the same bar', () async {
        final w = DateTime(2026, 5, 11);
        final period = TrainingPeriod(
          id: 'period-1',
          name: 'Spring block',
          startDateMs: w.millisecondsSinceEpoch,
          endDateMs: DateTime(2026, 5, 24).millisecondsSinceEpoch,
          createdAtMs: w.millisecondsSinceEpoch,
          updatedAtMs: w.millisecondsSinceEpoch,
        );

        // Fixture A's sessions: W−1d, W−84d, W−85d and W+1d inside the window.
        await _seedHourSession(
          repo,
          id: 's1511b-before',
          day: DateTime(2026, 5, 10),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511b-first',
          day: DateTime(2026, 2, 16),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511b-older',
          day: DateTime(2026, 2, 15),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511b-window',
          day: DateTime(2026, 5, 12),
          rating: 4,
        );
        // Three more sessions inside the period.
        for (final day in [13, 15, 20]) {
          await _seedHourSession(
            repo,
            id: 's1511b-in-$day',
            day: DateTime(2026, 5, day),
            rating: 4,
          );
        }

        final window = StatsProgressService.resolveWindow(
          periods: [period],
          completedSessions: await repo.getAllSessions(),
          now: now,
        );
        expect(window.isPeriodScoped, isTrue);
        expect(window.fromMs, w);

        final data = (await _mix(repo, window: window, now: now))!;

        // The bar covers the period's sessions (W+1d and the three in-period
        // ones), never the sessions before it.
        expect(_sectionsOf(data.segments), [ExerciseSection.resistance]);
        expect(_segment(data, ExerciseSection.resistance).measure, 240.0);
        expect(data.unratedSessionCount, 0);
        // The baseline still ends at the local-midnight day of the window's
        // own start, so the same two blocks as fixture A count.
        expect(data.ratedBaselineWeeks, 2);
        expect(data.measure, MixMeasure.time);
        expect(data.baselineSegments, isEmpty);

        // ... and that end is the window's own start day, not its end: the
        // same period pulled back one day to W−1d drops the W−1d block, which
        // leaves the W−84d block as the only rated one. A baseline that ran to
        // the window's end instead would pull the four in-period sessions in
        // and report two.
        final earlierPeriod = TrainingPeriod(
          id: 'period-0',
          name: 'Spring block, pulled back a day',
          startDateMs: DateTime(2026, 5, 10).millisecondsSinceEpoch,
          endDateMs: period.endDateMs,
          createdAtMs: w.millisecondsSinceEpoch,
          updatedAtMs: w.millisecondsSinceEpoch,
        );
        final earlierWindow = StatsProgressService.resolveWindow(
          periods: [earlierPeriod],
          completedSessions: await repo.getAllSessions(),
          now: now,
        );
        expect(earlierWindow.fromMs, DateTime(2026, 5, 10));
        final earlierData = (await _mix(
          repo,
          window: earlierWindow,
          now: now,
        ))!;
        expect(earlierData.ratedBaselineWeeks, 1);

        // The flag is never read: an equivalent hand-built non-period window
        // produces the identical payload.
        final handBuilt = _window(window.fromMs, window.toMs);
        final handData = (await _mix(repo, window: handBuilt, now: now))!;
        expect(_layerShape(data), _layerShape(handData));
      });

      test('S-1511 twin the start-of-week setting never moves a baseline '
          'boundary', () async {
        final w = DateTime(2026, 5, 11);
        await _seedHourSession(
          repo,
          id: 's1511-before',
          day: DateTime(2026, 5, 10),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-first',
          day: DateTime(2026, 2, 16),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-older',
          day: DateTime(2026, 2, 15),
          rating: 4,
        );
        await _seedHourSession(
          repo,
          id: 's1511-window',
          day: DateTime(2026, 5, 12),
          rating: 4,
        );

        final window = _window(w, DateTime(2026, 5, 17, 23, 59));
        final monday = (await _mix(repo, window: window, now: now))!;
        final sunday = (await _mix(
          repo,
          window: window,
          now: now,
          startOfWeek: 'sunday',
        ))!;

        expect(sunday.ratedBaselineWeeks, monday.ratedBaselineWeeks);
        expect(_barShape(sunday.baselineSegments), _barShape(monday.baselineSegments));
        expect(_barShape(sunday.segments), _barShape(monday.segments));
        // The setting moves the strip, and only the strip (D-935).
        expect(monday.weeks.last.weekStart, DateTime(2026, 5, 11));
        expect(sunday.weeks.last.weekStart, DateTime(2026, 5, 10));
      });

      test('S-1513 the strip is 8 weeks, keeps empty weeks and '
          'ignores the window', () async {
        expect(now.weekday, DateTime.wednesday);
        await _seedS1513(repo, now);

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 11), DateTime(2026, 5, 17, 23, 59)),
          now: now,
        ))!;

        expect(data.weeks, hasLength(kMixStripWeeks));
        expect(data.weeks.last.weekStart, DateTime(2026, 5, 11));
        expect(data.weeks.last.inProgress, isTrue);
        expect(data.weeks.first.weekStart, DateTime(2026, 3, 23));
        expect(
          data.weeks.last.weekStart.difference(data.weeks.first.weekStart).inDays,
          (kMixStripWeeks - 1) * 7,
        );
        for (final week in data.weeks.take(kMixStripWeeks - 1)) {
          expect(week.inProgress, isFalse);
        }

        // now lands in the last week, now−7d and now−8d in the one before it.
        expect(data.weeks.last.measure, 60.0);
        expect(data.weeks[6].measure, 120.0);
        // now−30d lands in its own week even though it is outside the window.
        expect(data.weeks[3].measure, 60.0);
        expect(data.weeks[3].weekStart, DateTime(2026, 4, 13));
        // Empty weeks are present, not dropped.
        for (final index in [0, 1, 2, 4, 5]) {
          expect(data.weeks[index].measure, 0.0);
          expect(data.weeks[index].segments, isEmpty);
        }
        // now−90d appears in no week at all.
        expect(_weekTotal(data.weeks), 240.0);
      });

      test('S-1513 twin a Sunday start shifts every week', () async {
        await _seedS1513(repo, now);

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 11), DateTime(2026, 5, 17, 23, 59)),
          now: now,
          startOfWeek: 'sunday',
        ))!;

        for (final week in data.weeks) {
          expect(week.weekStart.weekday, DateTime.sunday);
          expect(week.weekStart, OmniDateUtils.startOfWeek(week.weekStart, startOfWeek: 'sunday'));
        }
        expect(data.weeks.last.weekStart, DateTime(2026, 5, 10));
        expect(data.weeks.last.measure, 60.0);
        expect(data.weeks[6].weekStart, DateTime(2026, 5, 3));
        expect(data.weeks[6].measure, 120.0);
        expect(_weekTotal(data.weeks), 240.0);
      });

      test('S-1514 the mix and the Instruments list agree on the modality', () async {
        await _seedSession(
          repo,
          id: 's1514',
          start: now,
          end: DateTime(2026, 5, 13, 11),
        );
        await seedExercise(repo, id: 'ex-plank', name: 'Plank');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s1514',
          effortId: 'ef-plank',
          exerciseId: 'ex-plank',
          entryCount: 1,
          secondsPerEntry: 600,
          effortKind: 'timed',
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1514',
          exerciseId: 'ex-dl',
        );

        final window = _window(
          DateTime(2026, 5, 12, 10),
          DateTime(2026, 5, 14, 10),
        );
        final data = (await _mix(repo, window: window, now: now))!;

        expect(_sectionsOf(data.segments), [
          ExerciseSection.resistance,
          ExerciseSection.cardio,
        ]);
        expect(_segment(data, ExerciseSection.cardio).measure, 10.0);
        expect(_segment(data, ExerciseSection.resistance).measure, 50.0);

        final sections = await StatsProgressService(
          repo,
        ).computeInstrumentSections(window: window);
        final InstrumentSectionData cardio = sections.firstWhere(
          (section) => section.section == ExerciseSection.cardio,
        );
        final InstrumentSectionData resistance = sections.firstWhere(
          (section) => section.section == ExerciseSection.resistance,
        );
        expect([for (final row in cardio.rows) row.summary.name], contains('Plank'));
        expect([
          for (final row in resistance.rows) row.summary.name,
        ], contains('Deadlift'));
      });

      test('S-1515 a lifting-only window is one full-width '
          'Resistance segment', () async {
        final days = [10, 11, 12];
        final ratings = [4, 4, null];
        for (var i = 0; i < days.length; i++) {
          await _seedHourSession(
            repo,
            id: 's1515-$i',
            day: DateTime(2026, 5, days[i]),
            rating: ratings[i],
          );
          await _seedLiftingEffort(
            repo,
            sessionId: 's1515-$i',
            exerciseId: 'ex-dl-$i',
          );
        }

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 10), DateTime(2026, 5, 12, 23, 59)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(data.segments, hasLength(1));
        expect(_sectionsOf(data.segments), [ExerciseSection.resistance]);
        expect(_segment(data, ExerciseSection.resistance).percent, 100);
        expect(_segment(data, ExerciseSection.resistance).measure, 180.0);
        expect(data.unratedSessionCount, 1);
      });

      test('S-1516 a session holding every modality splits four ways '
          'and sums to 100', () async {
        await _seedSession(
          repo,
          id: 's1516',
          start: now,
          end: DateTime(2026, 5, 13, 11),
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1516',
          exerciseId: 'ex-dl',
        );
        await seedExercise(repo, id: 'ex-run', name: 'Run');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s1516',
          effortId: 'ef-run',
          exerciseId: 'ex-run',
          entryCount: 1,
          secondsPerEntry: 600,
          effortKind: 'timed',
        );
        await seedExercise(repo, id: 'ex-hold', name: 'Plank');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s1516',
          effortId: 'ef-hold',
          exerciseId: 'ex-hold',
          entryCount: 1,
          secondsPerEntry: 600,
        );
        await seedExercise(repo, id: 'ex-rounds', name: 'Rounds');
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s1516',
          effortId: 'ef-rounds',
          exerciseId: 'ex-rounds',
          rounds: [roundInstance('ef-rounds', 0, durationSecs: 600)],
        );

        final data = (await _mix(
          repo,
          window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
          now: now,
        ))!;

        expect(data.measure, MixMeasure.time);
        expect(_sectionsOf(data.segments), [
          ExerciseSection.resistance,
          ExerciseSection.cardio,
          ExerciseSection.isometric,
          ExerciseSection.sports,
        ]);
        expect(_segment(data, ExerciseSection.resistance).measure, 30.0);
        expect(_segment(data, ExerciseSection.cardio).measure, 10.0);
        expect(_segment(data, ExerciseSection.isometric).measure, 10.0);
        expect(_segment(data, ExerciseSection.sports).measure, 10.0);
        expect(_percentsOf(data.segments), [50, 17, 17, 16]);
        expect(_percentTotal(data.segments), 100);
      });

      test('S-1517 a session crossing midnight belongs to the week '
          'it started in', () async {
        final start = DateTime(2026, 5, 10, 23, 30);
        expect(start.weekday, DateTime.sunday);
        await _seedSession(
          repo,
          id: 's1517',
          start: start,
          end: DateTime(2026, 5, 11, 0, 30),
        );
        await _seedLiftingEffort(
          repo,
          sessionId: 's1517',
          exerciseId: 'ex-dl',
        );

        final window = _window(
          DateTime(2026, 5, 10),
          DateTime(2026, 5, 12, 23, 59),
        );
        final data = (await _mix(repo, window: window, now: now))!;

        // Midnight does not split a session: its own time is the full hour.
        expect(_segment(data, ExerciseSection.resistance).measure, 60.0);
        // It belongs to the week of Monday May 4, not the week containing now.
        expect(data.weeks[6].weekStart, DateTime(2026, 5, 4));
        expect(data.weeks[6].measure, 60.0);
        expect(data.weeks.last.weekStart, DateTime(2026, 5, 11));
        expect(data.weeks.last.measure, 0.0);
        expect(data.weeks.last.segments, isEmpty);
        expect(_weekTotal(data.weeks), 60.0);

        final sunday = (await _mix(
          repo,
          window: window,
          now: now,
          startOfWeek: 'sunday',
        ))!;
        final index = sunday.weeks.indexWhere(
          (week) =>
              week.weekStart ==
              OmniDateUtils.startOfWeek(start, startOfWeek: 'sunday'),
        );
        expect(index, sunday.weeks.length - 1);
        expect(sunday.weeks[index].measure, 60.0);
      });
    });
  }

  group('Mock and Hive — value-for-value parity', () {
    late RepositoryHarness mock;
    late RepositoryHarness hive;
    late WorkoutRepository mockRepo;
    late WorkoutRepository hiveRepo;

    setUp(() async {
      mock = MockRepositoryHarness();
      hive = HiveRepositoryHarness();
      mockRepo = await mock.open();
      hiveRepo = await hive.open();
    });

    tearDown(() async {
      await mock.close();
      await hive.close();
    });

    test('S-1503 the two stores agree', () async {
      await _seedS1503(mockRepo);
      await _seedS1503(hiveRepo);

      final mockData = (await _mix(
        mockRepo,
        window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
        now: now,
      ))!;
      final hiveData = (await _mix(
        hiveRepo,
        window: _window(DateTime(2026, 5, 12, 10), DateTime(2026, 5, 14, 10)),
        now: now,
      ))!;

      expect(_layerShape(hiveData), _layerShape(mockData));
      expect(mockData.measure, MixMeasure.load);
      expect(_barShape(mockData.segments), ['resistance:120.0:67', 'isometric:60.0:33']);
      expect(mockData.ratedBaselineWeeks, 4);
      expect(mockData.baselineSegments, isNotEmpty);
    });

    test('S-1513 the two stores agree', () async {
      await _seedS1513(mockRepo, now);
      await _seedS1513(hiveRepo, now);

      final window = _window(DateTime(2026, 5, 11), DateTime(2026, 5, 17, 23, 59));
      final mockData = (await _mix(mockRepo, window: window, now: now))!;
      final hiveData = (await _mix(hiveRepo, window: window, now: now))!;

      expect(_layerShape(hiveData), _layerShape(mockData));
      expect(hiveData.weeks, hasLength(kMixStripWeeks));
      expect(_weekTotal(hiveData.weeks), 240.0);
    });
  });
}
