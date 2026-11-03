// Stats 99b P1 — the rated-weeks count over the last 12 weeks, current ones
// included, over both repository harnesses.
//
// Plan: `docs/plans/2026-11-02-99b-stats-rated-weeks-plan/
// 2026-11-02-99b-stats-rated-weeks-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers (copied from stats_four_week_window_service_test.dart) ──

/// A session with an explicit start, end, rating and rolling flag, plus the one
/// segment its efforts hang on.
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

// ─── Read helpers ───────────────────────────────────────────────────────────

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

void main() {
  final now = DateTime(2026, 11, 2, 14, 30);

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — rated weeks', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-17101 rated sessions in four different current weeks count 4',
          () async {
        await _seedSession(
          repo,
          id: 's17101-a',
          start: DateTime(2026, 11, 2, 9),
          end: DateTime(2026, 11, 2, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17101-b',
          start: DateTime(2026, 10, 25, 9),
          end: DateTime(2026, 10, 25, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17101-c',
          start: DateTime(2026, 10, 18, 9),
          end: DateTime(2026, 10, 18, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17101-d',
          start: DateTime(2026, 10, 11, 9),
          end: DateTime(2026, 10, 11, 10),
          rating: 4,
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.ratedWeeks, 4);
        expect(data.measure, MixMeasure.load);
      });

      test('S-17102 two rated sessions in one week count once', () async {
        await _seedSession(
          repo,
          id: 's17102-a',
          start: DateTime(2026, 11, 2, 9),
          end: DateTime(2026, 11, 2, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17102-b',
          start: DateTime(2026, 10, 30, 9),
          end: DateTime(2026, 10, 30, 10),
          rating: 4,
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.ratedWeeks, 1);
      });

      test('S-17103 an unrated session does not count a week', () async {
        await _seedSession(
          repo,
          id: 's17103-a',
          start: DateTime(2026, 11, 2, 9),
          end: DateTime(2026, 11, 2, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17103-b',
          start: DateTime(2026, 10, 25, 9),
          end: DateTime(2026, 10, 25, 10),
        );
        await _seedSession(
          repo,
          id: 's17103-c',
          start: DateTime(2026, 10, 18, 9),
          end: DateTime(2026, 10, 18, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17103-d',
          start: DateTime(2026, 10, 11, 9),
          end: DateTime(2026, 10, 11, 10),
          rating: 4,
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.ratedWeeks, 3);
      });

      test('S-17104 the 84th day back is outside the 12 weeks', () async {
        // Block of a day d days back is 11 − floor(d / 7): today is block 11,
        // 83 days back is block 0, 84 days back is outside the 12 blocks.
        await _seedSession(
          repo,
          id: 's17104-today',
          start: DateTime(2026, 11, 2, 9),
          end: DateTime(2026, 11, 2, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17104-in',
          start: DateTime(2026, 8, 11, 9),
          end: DateTime(2026, 8, 11, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17104-out',
          start: DateTime(2026, 8, 10, 9),
          end: DateTime(2026, 8, 10, 10),
          rating: 4,
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.ratedWeeks, 2);
      });

      test('S-17105 the period counts weeks anchored at its own end day',
          () async {
        await _seedSession(
          repo,
          id: 's17105-a',
          start: DateTime(2026, 9, 28, 9),
          end: DateTime(2026, 9, 28, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105-b',
          start: DateTime(2026, 9, 18, 9),
          end: DateTime(2026, 9, 18, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105-c',
          start: DateTime(2026, 9, 8, 9),
          end: DateTime(2026, 9, 8, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105-d',
          start: DateTime(2026, 7, 20, 9),
          end: DateTime(2026, 7, 20, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105-unrated',
          start: DateTime(2026, 9, 10, 9),
          end: DateTime(2026, 9, 10, 10),
        );

        final data = (await StatsProgressService(repo).computeMixPeriod(
          fromMs: DateTime(2026, 9, 1),
          toMs: DateTime(2026, 9, 28, 23, 59, 59, 999),
        ))!;

        // Fixture check: from the end day 2026-09-28 the four rated days sit
        // 0, 10, 20 and 70 days back — blocks 11, 10, 9 and 1 of the 12 ending
        // 2026-09-28, each in a different block.
        expect(data.ratedWeeks, 4);
        expect(data.measure, MixMeasure.load);
      });

      test('S-17105 twin a rated session after the period does not count',
          () async {
        await _seedSession(
          repo,
          id: 's17105t-a',
          start: DateTime(2026, 9, 18, 9),
          end: DateTime(2026, 9, 18, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105t-b',
          start: DateTime(2026, 9, 8, 9),
          end: DateTime(2026, 9, 8, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105t-c',
          start: DateTime(2026, 7, 20, 9),
          end: DateTime(2026, 7, 20, 10),
          rating: 4,
        );
        // After the period's end day: it must not count a week.
        await _seedSession(
          repo,
          id: 's17105t-after',
          start: DateTime(2026, 10, 5, 9),
          end: DateTime(2026, 10, 5, 10),
          rating: 4,
        );
        await _seedSession(
          repo,
          id: 's17105t-unrated',
          start: DateTime(2026, 9, 10, 9),
          end: DateTime(2026, 9, 10, 10),
        );

        final data = (await StatsProgressService(repo).computeMixPeriod(
          fromMs: DateTime(2026, 9, 1),
          toMs: DateTime(2026, 9, 28, 23, 59, 59, 999),
        ))!;

        // From the end day 2026-09-28 the three in-period rated days sit 10,
        // 20 and 70 days back — blocks 10, 9 and 1 of the 12 ending
        // 2026-09-28, each in a different block. With the period's upper
        // bound removed, the 2026-10-05 session lands in block 11, which no
        // other rated session holds, so the count would be 4 and the measure
        // load.
        expect(data.ratedWeeks, 3);
        expect(data.measure, MixMeasure.time);
      });

      test('S-17106 ratedWeekBlockStarts tiles the 12 weeks at local midnight',
          () {
        final starts = ratedWeekBlockStarts(DateTime(2026, 11, 2));

        expect(starts.length, 12);
        expect(starts.first, DateTime(2026, 8, 11));
        expect(starts.last, DateTime(2026, 10, 27));

        // The 12 weeks ending 2026-03-15 span the 2026 spring-forward; the
        // `DateTime(y, m, d − n)` arithmetic keeps every start at local
        // midnight.
        final dstStarts = ratedWeekBlockStarts(DateTime(2026, 3, 15));

        expect(dstStarts.first, DateTime(2025, 12, 22));
        for (final start in dstStarts) {
          expect(start.hour, 0);
        }
      });
    });
  }
}
