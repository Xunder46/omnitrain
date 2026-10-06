// Stats PR 6b, Phase 1 — the Progression Rate's sample walk.
//
// `StatsProgressService.progressionSamples()` enumerates one sample per
// completed session and exercise that logged a `set` effort, valued by the
// native-value rule and the axis classification the Instruments rows already
// use, ordered by exercise and then by session start, off the cached history
// index. Scenarios S-1807, S-1808, S-1810 and S-1811 of
// `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/progression_rate.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── The F-PR fixture ───────────────────────────────────────────────────────

/// F-PR's nine sessions, in the order the plan's table lists them.
const List<int> _fprDays = [61, 54, 47, 40, 33, 26, 19, 12, 5];

/// F-PR's weights per exercise, one rep per set, so the estimated 1RM is
/// monotone in the weight.
const Map<String, List<double>> _fprWeights = {
  'ex-a': [100, 110, 120, 130, 140, 150, 160, 170, 180],
  'ex-b': [200, 210, 220, 215, 230, 240, 250, 245, 260],
  'ex-c': [300, 310, 305, 320, 330, 340, 335, 350, 360],
  'ex-d': [400, 410, 405, 420, 415, 430, 425, 440, 450],
  'ex-e': [500, 510, 505, 500, 495, 520, 515, 530, 540],
};

/// F-PR: nine completed sessions carrying all five exercises.
Future<void> seedFpr(WorkoutRepository repo) async {
  for (final id in _fprWeights.keys) {
    await seedExercise(repo, id: id, name: id);
  }
  for (var i = 0; i < _fprDays.length; i++) {
    final day = _fprDays[i];
    await seedSession(
      repo,
      sessionId: 'fpr-s$day',
      modality: 'resistance',
      daysAgo: day,
    );
    for (final entry in _fprWeights.entries) {
      await seedSetEffort(
        repo,
        segmentId: 'seg-fpr-s$day',
        effortId: 'fpr-e$day-${entry.key}',
        exerciseId: entry.key,
        entryCount: 1,
        hasExtraWeight: false,
        weightFactor: entry.value[i],
      );
    }
  }
}

/// One `set` effort of [exerciseId] at [weightKg], on [segmentId].
Future<void> seedOneSet(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  required double weightKg,
  int reps = 1,
  bool hasExtraWeight = false,
}) => seedSetEffort(
  repo,
  segmentId: segmentId,
  effortId: effortId,
  exerciseId: exerciseId,
  entryCount: 1,
  hasExtraWeight: hasExtraWeight,
  weightFactor: weightKg,
  repsBase: reps,
);

/// A rolling session that has been finished: `isRolling` set with an end, the
/// shape a closed rolling session persists.
Future<void> seedClosedRollingSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
}) async {
  final start = fixtureStart - (daysAgo - 1) * 86400000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + 3600000,
      isRolling: true,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Free Session',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

/// The sample of [exerciseId] in session [sessionId].
Future<ProgressionSample> sampleOf(
  WorkoutRepository repo,
  List<ProgressionSample> samples,
  String exerciseId,
  String sessionId,
) async {
  final session = (await repo.getAllSessions()).firstWhere(
    (s) => s.id == sessionId,
  );
  final matches = samples.where(
    (s) =>
        s.exerciseId == exerciseId && s.sessionStartMs == session.startedAtMs,
  );
  expect(matches, hasLength(1), reason: '$exerciseId in $sessionId');
  return matches.single;
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the Progression Rate samples', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('D-1101 one sample per exercise-session, valued and ordered', () async {
        await seedFpr(repo);
        // An exercise logged only as a `timed` effort contributes nothing: the
        // unit is the exercise-session that logged a `set` effort.
        await repo.createEffort(
          SegmentEffort(
            id: 'fpr-timed',
            segmentId: 'seg-fpr-s5',
            orderIndex: 1,
            effortKind: 'timed',
            exerciseId: 'ex-timed',
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );

        final samples = await StatsProgressService(repo).progressionSamples();

        expect(samples, hasLength(45));
        expect(
          samples.map((s) => s.exerciseId).toSet(),
          {'ex-a', 'ex-b', 'ex-c', 'ex-d', 'ex-e'},
        );

        for (final entry in _fprWeights.entries) {
          for (final day in _fprDays) {
            final sample = await sampleOf(
              repo,
              samples,
              entry.key,
              'fpr-s$day',
            );
            final index = _fprDays.indexOf(day);
            expect(
              sample.value,
              closeTo(
                StatsProgressService.epley1RM(entry.value[index], 1)!,
                1e-9,
              ),
              reason: '${entry.key} at $day days ago',
            );
          }
        }

        // Ordered by exercise, then by session start.
        for (var i = 1; i < samples.length; i++) {
          final previous = samples[i - 1];
          final current = samples[i];
          final byExercise = previous.exerciseId.compareTo(current.exerciseId);
          expect(
            byExercise < 0 ||
                (byExercise == 0 &&
                    previous.sessionStartMs < current.sessionStartMs),
            isTrue,
            reason: 'samples $i and ${i - 1} are out of order',
          );
        }
      });

      test('F-PR matches the plan\'s per-exercise hand-computation', () async {
        await seedFpr(repo);

        final samples = await StatsProgressService(repo).progressionSamples();
        final now = DateTime.now();

        // Prior then recent progressions, re-derived from the walk's samples by
        // the ledger's own rule and compared against the plan's table.
        const expected = <String, List<int>>{
          'ex-a': [4, 4],
          'ex-b': [3, 3],
          'ex-c': [3, 3],
          'ex-d': [2, 3],
          'ex-e': [1, 3],
        };

        for (final entry in expected.entries) {
          final ordered = samples
              .where((s) => s.exerciseId == entry.key)
              .toList()
            ..sort((a, b) => a.sessionStartMs.compareTo(b.sessionStartMs));
          var prior = 0;
          var recent = 0;
          for (var i = 1; i < ordered.length; i++) {
            if (ordered[i].value < ordered[i - 1].value) continue;
            if (inRecentProgressionWindow(ordered[i].sessionStartMs, now)) {
              recent++;
            } else if (inPriorProgressionWindow(
              ordered[i].sessionStartMs,
              now,
            )) {
              prior++;
            }
          }
          expect([prior, recent], entry.value, reason: entry.key);
        }
      });

      test('S-1808 the first-ever session is excluded', () async {
        await seedFpr(repo);
        // A lighter second session, so the exercise's only comparison is
        // counted and is not a progression. Its first session is the 20-day
        // one, and it is dropped.
        await seedExercise(repo, id: 'ex-new', name: 'New Lift');
        for (final (daysAgo, weight) in [(20, 150.0), (5, 120.0)]) {
          await seedSession(
            repo,
            sessionId: 's-1808-$daysAgo',
            modality: 'resistance',
            daysAgo: daysAgo,
          );
          await seedOneSet(
            repo,
            segmentId: 'seg-s-1808-$daysAgo',
            effortId: 'eff-1808-$daysAgo',
            exerciseId: 'ex-new',
            weightKg: weight,
          );
        }

        final service = StatsProgressService(repo);
        final samples = await service.progressionSamples();
        expect(samples, hasLength(47));

        final rate = progressionRate(samples: samples, now: DateTime.now())!;

        // F-PR's 20 recent comparisons plus ex-new's 5-day one, which is not a
        // progression; the 61-day session counts in neither period.
        expect(rate.recentCounted, 21);
        expect(rate.recentProgressions, 16);
        expect(rate.priorCounted, 20);
        expect(rate.priorProgressions, 13);
        expect(rate.recentPercent, 76);
      });

      test('S-1807 the axis follows the existing classification', () async {
        await seedExercise(repo, id: 'ex-bw', name: 'Pull-up');
        await seedExercise(repo, id: 'ex-weighted', name: 'Bench Press');
        for (final (i, daysAgo) in [61, 40, 5].indexed) {
          await seedSession(
            repo,
            sessionId: 's-1807-$daysAgo',
            modality: 'resistance',
            daysAgo: daysAgo,
          );
          // Bodyweight: reps climb, no load, so the reps axis decides.
          await seedOneSet(
            repo,
            segmentId: 'seg-s-1807-$daysAgo',
            effortId: 'eff-1807-bw-$daysAgo',
            exerciseId: 'ex-bw',
            weightKg: 0,
            reps: 5 + i,
          );
          await seedOneSet(
            repo,
            segmentId: 'seg-s-1807-$daysAgo',
            effortId: 'eff-1807-weighted-$daysAgo',
            exerciseId: 'ex-weighted',
            weightKg: 100.0 + 10 * i,
          );
        }

        final samples = await StatsProgressService(repo).progressionSamples();

        for (final (i, daysAgo) in [61, 40, 5].indexed) {
          expect(
            (await sampleOf(repo, samples, 'ex-bw', 's-1807-$daysAgo')).value,
            5 + i,
          );
          expect(
            (await sampleOf(
              repo,
              samples,
              'ex-weighted',
              's-1807-$daysAgo',
            )).value,
            closeTo(StatsProgressService.epley1RM(100.0 + 10 * i, 1)!, 1e-9),
          );
        }
      });

      test('S-1811 rolling and non-lifting sessions, and the span', () async {
        await seedFpr(repo);

        // A closed rolling session's sets count, and a set in a session with
        // no resistance modality counts. Each exercise needs a first-ever
        // session for its later one to be a comparison.
        for (final id in ['ex-roll', 'ex-cardio', 'ex-open']) {
          await seedExercise(repo, id: id, name: id);
        }
        await seedSession(
          repo,
          sessionId: 's-1811-first',
          daysAgo: 61,
        );
        for (final id in ['ex-roll', 'ex-cardio', 'ex-open']) {
          await seedOneSet(
            repo,
            segmentId: 'seg-s-1811-first',
            effortId: 'eff-1811-$id-first',
            exerciseId: id,
            weightKg: 100,
          );
        }

        await seedClosedRollingSession(
          repo,
          sessionId: 's-1811-roll',
          daysAgo: 5,
        );
        await seedOneSet(
          repo,
          segmentId: 'seg-s-1811-roll',
          effortId: 'eff-1811-roll',
          exerciseId: 'ex-roll',
          weightKg: 120,
        );

        await seedSession(
          repo,
          sessionId: 's-1811-cardio',
          modality: 'cardio_endurance',
          daysAgo: 5,
        );
        await seedOneSet(
          repo,
          segmentId: 'seg-s-1811-cardio',
          effortId: 'eff-1811-cardio',
          exerciseId: 'ex-cardio',
          weightKg: 120,
        );

        // An open rolling session's sets do not count: it has no end.
        await seedSession(
          repo,
          sessionId: 's-1811-open',
          isRolling: true,
          daysAgo: 5,
        );
        await seedOneSet(
          repo,
          segmentId: 'seg-s-1811-open',
          effortId: 'eff-1811-open',
          exerciseId: 'ex-open',
          weightKg: 120,
        );

        final samples = await StatsProgressService(repo).progressionSamples();

        // The open session contributes nothing, so ex-open keeps only its
        // first-ever sample.
        expect(samples.where((s) => s.exerciseId == 'ex-open'), hasLength(1));

        final rate = progressionRate(samples: samples, now: DateTime.now())!;

        expect(rate.recentCounted, 22);
        expect(rate.recentProgressions, 18);
        expect(rate.priorCounted, 20);
        expect(rate.priorProgressions, 13);
        expect(rate.recentPercent, 82);
        expect(
          progressionRateCopy(rate).observation,
          contains('over the last 4 weeks'),
        );
      });

      test('S-1810 a session with no readable value changes no rate', () async {
        await seedFpr(repo);
        await seedExercise(repo, id: 'ex-empty', name: 'Empty');
        for (final daysAgo in [61, 5]) {
          await seedSession(
            repo,
            sessionId: 's-1810-$daysAgo',
            modality: 'resistance',
            daysAgo: daysAgo,
          );
          await seedSetEffort(
            repo,
            segmentId: 'seg-s-1810-$daysAgo',
            effortId: 'eff-1810-$daysAgo',
            exerciseId: 'ex-empty',
            entryCount: 0,
            hasExtraWeight: false,
          );
        }

        final samples = await StatsProgressService(repo).progressionSamples();

        expect(samples, hasLength(47));
        for (final sample in samples.where((s) => s.exerciseId == 'ex-empty')) {
          expect(sample.value, 0);
        }

        final rate = progressionRate(samples: samples, now: DateTime.now())!;

        expect(rate.recentCounted, 20);
        expect(rate.priorCounted, 20);
        expect(rate.recentPercent, 80);
        expect(rate.priorPercent, 65);
      });

      test('D-1112 the walk adds no second repository read', () async {
        await seedFpr(repo);
        final service = StatsProgressService(repo);

        final first = await service.progressionSamples();
        expect(first, hasLength(45));

        // A write after the first load: the cached index does not see it, so
        // the second call returns the same samples.
        await seedSession(
          repo,
          sessionId: 's-late',
          modality: 'resistance',
          daysAgo: 5,
        );
        await seedOneSet(
          repo,
          segmentId: 'seg-s-late',
          effortId: 'eff-late',
          exerciseId: 'ex-a',
          weightKg: 999,
        );

        final second = await service.progressionSamples();

        expect(second, first);
      });
    });
  }
}
