// Stats 99a P1 — the four-week window (`statsWindow`) and the Mix payload's
// empty-window behaviour, over both repository harnesses.
//
// Plan: `docs/plans/2026-11-02-99a-stats-four-week-window-plan/
// 2026-11-02-99a-stats-four-week-window-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers (copied from mix_layer_service_test.dart) ──────────────

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

    group('${harness.name} — four-week window', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-17001 statsWindow is the 28 calendar days ending today', () {
        final window = StatsProgressService.statsWindow(now: now);

        expect(window.fromMs, DateTime(2026, 10, 6));
        expect(window.toMs, DateTime(2026, 11, 2, 23, 59, 59, 999));
        expect(window.label, 'Last 4 weeks');
        expect(window.dayCount, 28);
        expect(window.isPeriodScoped, isFalse);
      });

      test('S-17002 statsWindow spans a DST spring-forward in calendar days',
          () {
        final marchNow = DateTime(2026, 3, 15, 9);
        final window = StatsProgressService.statsWindow(now: marchNow);

        expect(window.fromMs, DateTime(2026, 2, 16));
        expect(window.dayCount, 28);

        final previous = StatsProgressService.previousRangeFor(window);
        expect(previous.fromMs, DateTime(2026, 1, 19).millisecondsSinceEpoch);
        expect(
          previous.toMs,
          DateTime(2026, 2, 16).millisecondsSinceEpoch - 1,
        );
      });

      test('S-17003 the day-28 session is outside the window', () async {
        await _seedSession(
          repo,
          id: 's17003-in',
          start: DateTime(2026, 10, 6, 9),
          end: DateTime(2026, 10, 6, 10),
        );
        await _seedSession(
          repo,
          id: 's17003-out',
          start: DateTime(2026, 10, 5, 9),
          end: DateTime(2026, 10, 5, 10),
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.unratedSessionCount, 1);
        expect(data.segments.length, 1);
        expect(data.segments.first.section, ExerciseSection.resistance);
        expect(data.segments.first.percent, 100);
      });

      test('S-17006 an empty window with history returns the empty payload',
          () async {
        await _seedSession(
          repo,
          id: 's17006-a',
          start: DateTime(2026, 9, 28, 9),
          end: DateTime(2026, 9, 28, 10),
        );
        await _seedSession(
          repo,
          id: 's17006-b',
          start: DateTime(2026, 9, 3, 9),
          end: DateTime(2026, 9, 3, 10),
        );

        final data = (await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        ))!;

        expect(data.windowIsEmpty, isTrue);
        expect(data.segments, isEmpty);
        expect(data.weeks, isEmpty);
        expect(data.lastSessionDay, DateTime(2026, 9, 28));
      });

      test('S-17008 no completed session at all returns null', () async {
        final data = await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        );

        expect(data, isNull);
      });

      test('S-17009 a zero-duration session inside the window returns null',
          () async {
        await _seedSession(
          repo,
          id: 's17009',
          start: DateTime(2026, 10, 31, 9),
          end: DateTime(2026, 10, 31, 9),
        );

        final data = await _mix(
          repo,
          window: StatsProgressService.statsWindow(now: now),
          now: now,
        );

        expect(data, isNull);
      });

      test('S-17010 computeMixPeriod stays null for an empty period', () async {
        await _seedSession(
          repo,
          id: 's17010-a',
          start: DateTime(2026, 9, 28, 9),
          end: DateTime(2026, 9, 28, 10),
        );
        await _seedSession(
          repo,
          id: 's17010-b',
          start: DateTime(2026, 9, 3, 9),
          end: DateTime(2026, 9, 3, 10),
        );

        final data = await StatsProgressService(repo).computeMixPeriod(
          fromMs: DateTime(2026, 10, 6),
          toMs: DateTime(2026, 11, 2, 23, 59, 59, 999),
        );

        expect(data, isNull);
      });
    });
  }
}
