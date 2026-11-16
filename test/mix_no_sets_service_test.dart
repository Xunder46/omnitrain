// Plan 179 P2 — the service scenarios for the no-sets rule: a Free Training
// session that holds timed work and NO set effort now shares its whole
// duration across the measured modalities, over both repository harnesses.
//
// Scenarios S-20007..S-20011.
//
// Plan: `docs/plans/2026-11-15-179-stats-mix-no-sets-plan/2026-11-15-179-stats-mix-no-sets-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── The plan's clock and window ────────────────────────────────────────────

/// The plan's `now`: a fixed anchor, so the fixture never moves with the clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// The window the Mix reads run against, holding the 2026-05-13 sessions.
StatsWindow _mixWindow() => StatsWindow(
  fromMs: DateTime(2026, 5, 12, 10),
  toMs: DateTime(2026, 5, 14, 10),
  label: 'Test window',
  isPeriodScoped: false,
);

Future<MixLayerData?> _mix(WorkoutRepository repo) => StatsProgressService(
  repo,
).computeMixLayer(window: _mixWindow(), now: _now, startOfWeek: 'monday');

// ─── Fixture helpers ────────────────────────────────────────────────────────

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

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the no-sets rule', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-20007 a timed-only session reads cardio 100% and no resistance '
          'time', () async {
        await _seedSession(
          repo,
          id: 's20007',
          start: DateTime(2026, 5, 13, 10),
          end: DateTime(2026, 5, 13, 10, 40),
          rating: 3,
        );
        await seedExercise(repo, id: 'ex-run', name: 'Run');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s20007',
          effortId: 'ef-s20007',
          exerciseId: 'ex-run',
          entryCount: 1,
          secondsPerEntry: 1800,
          effortKind: 'timed',
        );

        final data = (await _mix(repo))!;

        expect(data.segments.length, 1);
        expect(data.segments.single.section, ExerciseSection.cardio);
        expect(data.segments.single.percent, 100);
        expect(
          await StatsProgressService(repo).sessionTimeBySectionFor('s20007'),
          {ExerciseSection.cardio: 2400.0},
        );
      });

      test('S-20008 a drill-only session (3 x 360 s holds) reads isometric '
          '100%', () async {
        await _seedSession(
          repo,
          id: 's20008',
          start: DateTime(2026, 5, 13, 10),
          end: DateTime(2026, 5, 13, 11),
          rating: 3,
        );
        await seedExercise(repo, id: 'ex-hold', name: 'Plank');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s20008',
          effortId: 'ef-s20008',
          exerciseId: 'ex-hold',
          entryCount: 3,
          secondsPerEntry: 360,
        );

        final data = (await _mix(repo))!;

        expect(data.segments.length, 1);
        expect(data.segments.single.section, ExerciseSection.isometric);
        expect(data.segments.single.percent, 100);
      });

      test(
        'S-20009 a session holding a set keeps the remainder rule',
        () async {
          await _seedSession(
            repo,
            id: 's20009',
            start: DateTime(2026, 5, 13, 10),
            end: DateTime(2026, 5, 13, 11),
            rating: 3,
          );
          await seedExercise(repo, id: 'ex-lift', name: 'Lift');
          await seedSetEffort(
            repo,
            segmentId: 'seg-s20009',
            effortId: 'ef-s20009-set',
            exerciseId: 'ex-lift',
            entryCount: 1,
            hasExtraWeight: false,
          );
          await seedExercise(repo, id: 'ex-tread', name: 'Treadmill');
          await seedHoldEffort(
            repo,
            segmentId: 'seg-s20009',
            effortId: 'ef-s20009-run',
            exerciseId: 'ex-tread',
            entryCount: 1,
            secondsPerEntry: 600,
            effortKind: 'timed',
          );

          expect(
            await StatsProgressService(repo).sessionTimeBySectionFor('s20009'),
            {ExerciseSection.resistance: 3000.0, ExerciseSection.cardio: 600.0},
          );
        },
      );

      test('S-20010 the timed-only session still counts its full 40 minutes '
          'of weekly load', () async {
        await _seedSession(
          repo,
          id: 's20010',
          start: DateTime(2026, 4, 29, 10),
          end: DateTime(2026, 4, 29, 10, 40),
          rating: 3,
        );
        await seedExercise(repo, id: 'ex-run', name: 'Run');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s20010',
          effortId: 'ef-s20010',
          exerciseId: 'ex-run',
          entryCount: 1,
          secondsPerEntry: 1800,
          effortKind: 'timed',
        );

        final weeks = await StatsProgressService(repo).weeklyLoads(now: _now);

        final loaded = weeks.where((w) => w.loadMinutes > 0).toList();
        expect(loaded.length, 1);
        expect(loaded.single.loadMinutes, closeTo(120.0, 1e-9));
      });

      test('S-20011 a round-only session\'s Sports load covers the whole '
          'hour', () async {
        await _seedSession(
          repo,
          id: 's20011',
          start: DateTime(2026, 4, 29, 10),
          end: DateTime(2026, 4, 29, 11),
          rating: 3,
        );
        await seedExercise(repo, id: 'ex-sport', name: 'Sport');
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s20011',
          effortId: 'ef-s20011',
          exerciseId: 'ex-sport',
          rounds: [
            roundInstance('ef-s20011', 0, durationSecs: 1200),
            roundInstance('ef-s20011', 1, durationSecs: 1200),
          ],
        );

        final walk = await StatsProgressService(repo).interferenceSessions();

        final session = walk.firstWhere((s) => s.id == 's20011');
        expect(session.sportsLoadMinutes, closeTo(180.0, 1e-9));
      });
    });
  }
}
