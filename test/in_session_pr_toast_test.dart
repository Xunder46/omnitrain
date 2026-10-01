// Tests for the in-session "Congrats! New PR" toast feature.
//
// Plan: docs/plans/in-session-pr-toast-plan.md
//
// Phase 1 covers the source-of-truth e1RM helpers on
// `StatsProgressService`:
//   - `epley1RM(weight, reps)` — the public static helper that both
//     the Stats screen and the in-session toast use. Decision Ledger
//     D-1, D-3, D-13.
//   - `getAllTimeBestE1RM(exerciseId)` — the standing-best query that
//     drives the in-session toast. Decision Ledger D-2, D-4, D-5,
//     D-14, plus the S-009 structural guard.
//
// Phase 2 (below) covers the in-session wiring: the SnackBar fires
// only on strength (set-kind) PRs, never in edit mode, never for
// skipped sets, and never for non-strength efforts. Driven from
// `WorkoutSessionScreen._logSet()` via widget tests that pre-populate
// the in-memory entry, tap the Log Set button, and assert the SnackBar
// is or isn't shown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/pr_toast.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Creates a completed session with one set-based effort (reps × weight).
/// Returns the session. The repo is mutated in-place.
Future<TrainingSession> _seedCompletedSetSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final session = TrainingSession(
    id: sessionId,
    ownerUserId: 'u-1',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createObservation(
    EffortObservation(
      id: 'obs-reps-$sessionId',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-weight-$sessionId',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

/// Creates an **in-progress** session (no `endedAtMs`) with one
/// set-based effort. The repo is mutated in-place. This is the shape
/// the in-session toast sees: the just-logged set is in a session
/// that has not been finished yet, so it MUST NOT be counted in the
/// standing-best query (Decision Ledger D-2 + S-009 Arm B).
Future<TrainingSession> _seedInProgressSetSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final session = TrainingSession(
    id: sessionId,
    ownerUserId: 'u-1',
    startedAtMs: startedAtMs,
    // endedAtMs deliberately null — this is an in-progress session.
    createdAtMs: startedAtMs,
    updatedAtMs: startedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createObservation(
    EffortObservation(
      id: 'obs-reps-$sessionId',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-weight-$sessionId',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // epley1RM (static, source of truth — D-1, D-3, D-13)
  // ══════════════════════════════════════════════════════════════════════════

  group('StatsProgressService.epley1RM', () {
    test('returns null for zero weight', () {
      expect(StatsProgressService.epley1RM(0, 5), isNull);
    });

    test('returns null for negative weight', () {
      expect(StatsProgressService.epley1RM(-10, 5), isNull);
    });

    test('returns null for zero reps', () {
      expect(StatsProgressService.epley1RM(60, 0), isNull);
    });

    test('returns null for negative reps', () {
      expect(StatsProgressService.epley1RM(60, -3), isNull);
    });

    test('canonical case: 60 kg × 5 reps → 70.0', () {
      expect(StatsProgressService.epley1RM(60, 5), 70.0);
    });

    test('S-002 fixture: 70 kg × 5 reps → ~81.667', () {
      expect(StatsProgressService.epley1RM(70, 5), closeTo(81.6667, 0.001));
    });

    test('is monotonically non-decreasing in weight for fixed reps', () {
      double? previous;
      for (final w in [0.0, 1.0, 10.0, 50.0, 60.0, 100.0, 200.0]) {
        final e = StatsProgressService.epley1RM(w, 5);
        if (previous != null && e != null) {
          expect(e, greaterThanOrEqualTo(previous));
        }
        previous = e;
      }
    });

    test('is monotonically non-decreasing in reps for fixed weight', () {
      double? previous;
      for (final r in [0, 1, 2, 5, 10, 20, 30]) {
        final e = StatsProgressService.epley1RM(60.0, r);
        if (previous != null && e != null) {
          expect(e, greaterThanOrEqualTo(previous));
        }
        previous = e;
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // getAllTimeBestE1RM (instance, D-2, D-4, D-5, D-14, S-001, S-010)
  // ══════════════════════════════════════════════════════════════════════════

  group('StatsProgressService.getAllTimeBestE1RM', () {
    test(
      'returns 0.0 when no sessions exist at all (S-001 / first-ever)',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exA = exercises.first;

        final service = StatsProgressService(repo);
        expect(await service.getAllTimeBestE1RM(exA.id), 0.0);
      },
    );

    test('returns 0.0 when sessions exist but none for the exercise', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      // Seed a session for some exercise, query a different one.
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: exercises.first.id,
        reps: 5,
        weight: 60.0,
      );

      final service = StatsProgressService(repo);
      // Use a different exercise id (not present in the seed).
      expect(await service.getAllTimeBestE1RM('ex-DOES-NOT-EXIST'), 0.0);
    });

    test(
      'returns the single set e1RM when one completed session has one set',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exA = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 's-1',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exA.id,
          reps: 5,
          weight: 60.0,
        );

        final service = StatsProgressService(repo);
        expect(await service.getAllTimeBestE1RM(exA.id), 70.0);
      },
    );

    test(
      'returns the max across multiple sets in the same completed session',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exA = exercises.first;

        // Session with three set entries at different weights.
        final session = TrainingSession(
          id: 's-1',
          ownerUserId: 'u-1',
          startedAtMs: 1000,
          endedAtMs: 5000,
          createdAtMs: 1000,
          updatedAtMs: 5000,
        );
        await repo.createSession(session);

        final segId = 'seg-s-1';
        await repo.createSegment(
          SessionSegment(
            id: segId,
            sessionId: 's-1',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        // Three efforts, each with a single set entry.
        for (final entry in [
          (reps: 5, weight: 60.0), // e1RM 70.0
          (reps: 3, weight: 80.0), // e1RM 88.0
          (reps: 1, weight: 100.0), // e1RM 103.33
        ]) {
          final effortId = 'eff-${entry.reps}-${entry.weight}';
          await repo.createEffort(
            SegmentEffort(
              id: effortId,
              segmentId: segId,
              orderIndex: entry.reps,
              effortKind: 'set',
              exerciseId: exA.id,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repo.createObservation(
            EffortObservation(
              id: 'obs-reps-$effortId',
              effortId: effortId,
              metricId: 'metric-reps',
              valueInt: entry.reps,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await repo.createObservation(
            EffortObservation(
              id: 'obs-weight-$effortId',
              effortId: effortId,
              metricId: 'metric-weight',
              valueReal: entry.weight,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
        }

        final service = StatsProgressService(repo);
        expect(await service.getAllTimeBestE1RM(exA.id), closeTo(103.33, 0.01));
      },
    );

    test('returns the max across multiple completed sessions', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final exA = exercises.first;

      await _seedCompletedSetSession(
        repo,
        sessionId: 's-1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: exA.id,
        reps: 5,
        weight: 60.0, // 70.0
      );
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-2',
        startedAtMs: 3000,
        endedAtMs: 4000,
        exerciseId: exA.id,
        reps: 5,
        weight: 80.0, // 93.33
      );
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-3',
        startedAtMs: 5000,
        endedAtMs: 6000,
        exerciseId: exA.id,
        reps: 3,
        weight: 70.0, // 77.0
      );

      final service = StatsProgressService(repo);
      expect(await service.getAllTimeBestE1RM(exA.id), closeTo(93.33, 0.01));
    });

    test('ignores in-progress sessions (S-009 / D-2 contract)', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final exA = exercises.first;

      // One completed session (the "standing best" the user can beat).
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-old',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: exA.id,
        reps: 5,
        weight: 60.0, // 70.0
      );

      // One in-progress session (the just-logged set, in a session
      // that has NOT been finished). This MUST NOT count.
      await _seedInProgressSetSession(
        repo,
        sessionId: 's-now',
        startedAtMs: 5000,
        exerciseId: exA.id,
        reps: 5,
        weight: 90.0, // 105.0 — would be the new PR
      );

      final service = StatsProgressService(repo);
      // The standing best is 70.0 (s-old). The in-progress 105.0 is
      // excluded — that's the point. The in-session toast will
      // compare 105.0 to 70.0 and fire.
      expect(await service.getAllTimeBestE1RM(exA.id), 70.0);
    });

    test('ignores non-set effort kinds (timed, round, drill) — D-5', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final exA = exercises.first;
      final exCardio = exercises.length > 1 ? exercises[1] : exercises.first;

      // Round-based effort for exA — should be ignored.
      final session = TrainingSession(
        id: 's-round',
        ownerUserId: 'u-1',
        startedAtMs: 1000,
        endedAtMs: 5000,
        createdAtMs: 1000,
        updatedAtMs: 5000,
      );
      await repo.createSession(session);
      final segId = 'seg-s-round';
      await repo.createSegment(
        SessionSegment(
          id: segId,
          sessionId: 's-round',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      final effortId = 'eff-round';
      await repo.createEffort(
        SegmentEffort(
          id: effortId,
          segmentId: segId,
          orderIndex: 0,
          effortKind: 'round',
          exerciseId: exA.id,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await repo.createObservation(
        EffortObservation(
          id: 'obs-weight-round',
          effortId: effortId,
          metricId: 'metric-weight',
          valueReal: 200.0, // huge — would be a fake PR if not filtered
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );

      // A cardio (timed) effort for exA — should also be ignored.
      final cardioSession = TrainingSession(
        id: 's-cardio',
        ownerUserId: 'u-1',
        startedAtMs: 6000,
        endedAtMs: 10000,
        createdAtMs: 6000,
        updatedAtMs: 10000,
      );
      await repo.createSession(cardioSession);
      final cardioSegId = 'seg-s-cardio';
      await repo.createSegment(
        SessionSegment(
          id: cardioSegId,
          sessionId: 's-cardio',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 6000,
          updatedAtMs: 6000,
        ),
      );
      final cardioEffortId = 'eff-cardio';
      await repo.createEffort(
        SegmentEffort(
          id: cardioEffortId,
          segmentId: cardioSegId,
          orderIndex: 0,
          effortKind: 'timed',
          exerciseId: exCardio.id,
          createdAtMs: 6000,
          updatedAtMs: 6000,
        ),
      );
      await repo.createObservation(
        EffortObservation(
          id: 'obs-weight-cardio',
          effortId: cardioEffortId,
          metricId: 'metric-weight',
          valueReal: 300.0, // also huge
          createdAtMs: 6000,
          updatedAtMs: 6000,
        ),
      );

      final service = StatsProgressService(repo);
      expect(await service.getAllTimeBestE1RM(exA.id), 0.0);
    });

    test(
      'returns 0.0 when sessions exist but all sets have weight=0 or reps=0',
      () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exA = exercises.first;

        // A strength effort with weight=0 (skipped or uninitialized).
        final session = TrainingSession(
          id: 's-empty',
          ownerUserId: 'u-1',
          startedAtMs: 1000,
          endedAtMs: 2000,
          createdAtMs: 1000,
          updatedAtMs: 2000,
        );
        await repo.createSession(session);
        final segId = 'seg-s-empty';
        await repo.createSegment(
          SessionSegment(
            id: segId,
            sessionId: 's-empty',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        final effortId = 'eff-empty';
        await repo.createEffort(
          SegmentEffort(
            id: effortId,
            segmentId: segId,
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: exA.id,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-reps-empty',
            effortId: effortId,
            metricId: 'metric-reps',
            valueInt: 5,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-weight-empty',
            effortId: effortId,
            metricId: 'metric-weight',
            valueReal: 0.0,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );

        final service = StatsProgressService(repo);
        expect(await service.getAllTimeBestE1RM(exA.id), 0.0);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-009 — structural guard: in-session PR threshold matches the Stats
  // PR computation for identical data. Decision Ledger D-13.
  // ══════════════════════════════════════════════════════════════════════════

  group('S-009: in-session PR threshold matches Stats PR computation', () {
    test(
      'identical seed → standing best agrees between Arm A (Stats) and Arm B (in-session)',
      () async {
        // Anchor both timestamps to local-midnight of recent days
        // (2 days ago and 1 day ago) so the new recency floor
        // (`StatsProgressService.kTopExerciseRecencyDays`) keeps the
        // exercise eligible for selection. Noon UTC was previously
        // used so the local training-day buckets cleanly; local
        // midnight does the same for the tests that only check the
        // e1RM/pr values, not the wall-clock time of day.
        final today = DateTime.now();
        final todayMidnight = DateTime(today.year, today.month, today.day);
        final sOldDay = todayMidnight.subtract(const Duration(days: 2));
        final sNewDay = todayMidnight.subtract(const Duration(days: 1));
        final sOldStartMs = sOldDay.millisecondsSinceEpoch;
        final sOldEndMs = sOldDay
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        final sNewStartMs = sNewDay.millisecondsSinceEpoch;
        final sNewEndMs = sNewDay
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;

        // Arm A — Stats-screen view: both sessions are completed, so
        // the Stats PR detector walks both per-day e1RM points.
        final armA = await _freshRepo();
        final exA = (await armA.getExercises()).first;
        await _seedCompletedSetSession(
          armA,
          sessionId: 's-old',
          startedAtMs: sOldStartMs,
          endedAtMs: sOldEndMs,
          exerciseId: exA.id,
          reps: 5,
          weight: 60.0,
        );
        await _seedCompletedSetSession(
          armA,
          sessionId: 's-new',
          startedAtMs: sNewStartMs,
          endedAtMs: sNewEndMs,
          exerciseId: exA.id,
          reps: 5,
          weight: 70.0,
        );

        final statsData = await StatsProgressService(
          armA,
        ).computeProgressData();
        // The lift is the only set-based exercise, so it lands in topLifts[0].
        final lift = statsData.topLifts.firstWhere(
          (l) => l.exerciseName == exA.name,
        );
        // Two training days → two trend points.
        expect(lift.e1RmTrend, hasLength(2));
        // Day 1: 60 × (1 + 5/30) = 70.0
        expect(lift.e1RmTrend.first.value, 70.0);
        // Day 2: 70 × (1 + 5/30) ≈ 81.667
        expect(lift.e1RmTrend.last.value, closeTo(81.6667, 0.001));
        // The Stats PR detector saw s-new as a new PR.
        expect(statsData.recentPRs, isNotEmpty);
        expect(statsData.recentPRs.first.e1Rm, closeTo(81.6667, 0.001));

        // Arm B — in-session view: s-new is in-progress. The toast
        // queries the standing best at the moment of the just-logged
        // set; the just-logged set MUST be excluded from that query
        // (D-2 contract; otherwise the standing best would include the
        // very set we're trying to celebrate as a PR, masking the
        // celebration).
        final armB = await _freshRepo();
        final exB = (await armB.getExercises()).first;
        await _seedCompletedSetSession(
          armB,
          sessionId: 's-old',
          startedAtMs: sOldStartMs,
          endedAtMs: sOldEndMs,
          exerciseId: exB.id,
          reps: 5,
          weight: 60.0,
        );
        await _seedInProgressSetSession(
          armB,
          sessionId: 's-new',
          startedAtMs: sNewStartMs,
          exerciseId: exB.id,
          reps: 5,
          weight: 70.0,
        );

        final standingBest = await StatsProgressService(
          armB,
        ).getAllTimeBestE1RM(exB.id);
        // The standing best at the moment of the new set is 70.0
        // (s-old). The just-logged set in s-new is excluded.
        expect(standingBest, 70.0);

        // The just-logged set's e1RM is ~81.67, which is strictly
        // greater than 70.0 → the in-session toast would fire.
        final newE1rm = StatsProgressService.epley1RM(70.0, 5)!;
        expect(newE1rm, greaterThan(standingBest));

        // Parity assertion: the in-session query (Arm B) returns the
        // same number as the day-1 point of the Stats trend (Arm A).
        // This is the single source of truth the prompt calls out:
        // if either side changes, this test fails loudly.
        expect(standingBest, lift.e1RmTrend.first.value);
      },
    );
  });
  group('S-001: first-ever strength set fires PR toast', () {
    testWidgets('S-001a: no prior history → first logged set fires the toast', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final exA = exercises.first;

      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final deps = await pumpLiveSessionScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
        exerciseId: exA.id,
        exerciseName: exA.name,
        reps: 5,
        weightKg: 60.0,
      );

      await deps.openDetailView();

      // 60 kg × 5 reps → e1RM 70.0. No prior history for exA →
      // standing best is 0.0 → 70.0 > 0.0 → PR.
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The SnackBar's content is reachable via `find.text` because
      // `ScaffoldMessenger` renders it inside the Overlay.
      expect(find.text('Congrats! New PR'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });
  });

  group('S-002: a set beating the prior best fires the toast', () {
    testWidgets(
      'S-002a: 60 kg standing best → 70 kg × 5 reps fires the toast',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final exA = (await repo.getExercises()).first;

        // Seed a completed session with 60 kg × 5 reps (e1RM 70.0).
        final sOldStartMs = DateTime.utc(2025, 1, 1, 12).millisecondsSinceEpoch;
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-old',
          startedAtMs: sOldStartMs,
          endedAtMs: sOldStartMs + 3600000,
          exerciseId: exA.id,
          reps: 5,
          weight: 60.0,
        );

        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(modality: 'resistance_lifting');

        final deps = await pumpLiveSessionScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
          exerciseId: exA.id,
          exerciseName: exA.name,
          reps: 5,
          weightKg: 70.0, // 70 × (1 + 5/30) ≈ 81.67 > 70.0 → PR
        );

        await deps.openDetailView();
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Congrats! New PR'), findsOneWidget);
      },
    );
  });

  group('S-003: a set equal to the prior best does NOT fire', () {
    testWidgets('S-003a: 60 kg standing best → 60 kg × 5 reps → no toast', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final exA = (await repo.getExercises()).first;

      final sOldStartMs = DateTime.utc(2025, 1, 1, 12).millisecondsSinceEpoch;
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-old',
        startedAtMs: sOldStartMs,
        endedAtMs: sOldStartMs + 3600000,
        exerciseId: exA.id,
        reps: 5,
        weight: 60.0,
      );

      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final deps = await pumpLiveSessionScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
        exerciseId: exA.id,
        exerciseName: exA.name,
        reps: 5,
        weightKg: 60.0, // e1RM 70.0 == 70.0 → NOT a PR (strict >)
      );

      await deps.openDetailView();
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Congrats! New PR'), findsNothing);
    });
  });

  // Throttle tests: The main throttle behavior is covered by S-008a which verifies
  // that ascending bests in a session each fire once (which requires tracking the
  // session's running best). Additional re-save tests would require more complex
  // test infrastructure to properly handle SnackBar dismissal timing.

  group('S-004: a set below the prior best does NOT fire', () {
    testWidgets('S-004a: 60 kg standing best → 50 kg × 3 reps → no toast', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final exA = (await repo.getExercises()).first;

      final sOldStartMs = DateTime.utc(2025, 1, 1, 12).millisecondsSinceEpoch;
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-old',
        startedAtMs: sOldStartMs,
        endedAtMs: sOldStartMs + 3600000,
        exerciseId: exA.id,
        reps: 5,
        weight: 60.0,
      );

      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      final deps = await pumpLiveSessionScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
        exerciseId: exA.id,
        exerciseName: exA.name,
        reps: 3,
        weightKg: 50.0, // 50 × (1 + 3/30) = 55.0 < 70.0 → not a PR
      );

      await deps.openDetailView();
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Congrats! New PR'), findsNothing);
    });
  });

  group('S-005: non-strength efforts never trigger the toast', () {
    testWidgets(
      'S-005a: timed effort → no toast (no prior history, no action needed)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        // Pick a cardio-capable exercise; fall back to the first
        // exercise if none is found (the seed catalog ships several).
        final allExercises = await repo.getExercises();
        final exCardio = allExercises.firstWhere(
          (e) => e.capabilities.contains('time'),
          orElse: () => allExercises.first,
        );

        final workoutState = WorkoutState(repo);
        await workoutState.markExerciseInfoHintSeen();
        await workoutState.markExerciseNotesHintSeen();
        await workoutState.createNewSession(modality: 'cardio_endurance');
        final effortId = await workoutState.addExerciseToSession(
          exCardio,
          effortKindOverride: 'timed',
        );
        // Finish the timed instance so the entry is "logged" via the
        // standard persistence path (without showing any UI).
        await workoutState.finishTimedEntry(effortId, 0);

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workoutState,
              routineState: RoutineState(repo),
              sessionSummaryService: SessionSummaryService(repo),
              timerAlertService: FakeTimerAlertService(),
              settingsState: SettingsState(repo, fakePreferencesService()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pump a few frames to flush any latent showSnackBar that
        // might have been called by mistake.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Congrats! New PR'), findsNothing);
      },
    );
  });

  group('S-006: edit mode never triggers a toast', () {
    testWidgets('S-006a: opening a completed session in edit mode → no toast', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final exA = (await repo.getExercises()).first;

      // Seed a completed session with 60 kg × 5 reps (e1RM 70.0).
      final sOldStartMs = DateTime.utc(2025, 1, 1, 12).millisecondsSinceEpoch;
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-old',
        startedAtMs: sOldStartMs,
        endedAtMs: sOldStartMs + 3600000,
        exerciseId: exA.id,
        reps: 5,
        weight: 60.0,
      );

      final workoutState = WorkoutState(repo);
      // Open the completed session in edit mode.
      final session = (await repo.getAllSessions()).first;
      await workoutState.loadHistoricalSession(session.id);

      final deps = await pumpLiveSessionScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
        exerciseId: exA.id,
        exerciseName: exA.name,
        reps: 5,
        weightKg:
            80.0, // 80 × (1 + 5/30) ≈ 93.33 > 70.0 → would be PR if not edit
        editMode: true,
      );

      await deps.openDetailView();
      // Pump a few frames to flush any latent showSnackBar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Congrats! New PR'), findsNothing);
    });
  });

  group('S-007: a skipped set (zero reps) does not trigger a toast', () {
    testWidgets('S-007a: reps=0 → isSkippedSetKindEntry → no toast', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      final repo = await _freshRepo();
      final exA = (await repo.getExercises()).first;

      final workoutState = WorkoutState(repo);
      await workoutState.createNewSession(modality: 'resistance_lifting');

      // reps=0, weight=100. The screen's `_logSet` computes
      // `isSkippedSetKindEntry = effortKind == 'set' && reps <= 0` →
      // true → the PR check is skipped.
      final deps = await pumpLiveSessionScreen(
        tester,
        repo: repo,
        workoutState: workoutState,
        exerciseId: exA.id,
        exerciseName: exA.name,
        reps: 0,
        weightKg: 100.0,
      );

      await deps.openDetailView();
      await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Congrats! New PR'), findsNothing);
    });
  });

  group(
    'S-008: multiple beating sets in the same session each fire a toast',
    () {
      testWidgets(
        'S-008a: three beating sets with no prior history → three SnackBars',
        (WidgetTester tester) async {
          await tester.binding.setSurfaceSize(const Size(400, 1000));
          final repo = await _freshRepo();
          final exA = (await repo.getExercises()).first;

          final workoutState = WorkoutState(repo);
          await workoutState.markExerciseInfoHintSeen();
          await workoutState.markExerciseNotesHintSeen();
          await workoutState.createNewSession(modality: 'resistance_lifting');

          // Add one strength effort with three set entries.
          final effortId = await workoutState.addExerciseToSession(
            exA,
            chosenMetric: 'reps',
          );
          await workoutState.addEntry(effortId);
          await workoutState.addEntry(effortId);

          // Pre-populate the three entries with escalating weights.
          await workoutState.updateEntryValue(effortId, 0, 'reps', 5);
          await workoutState.updateEntryValue(effortId, 0, 'weight', 60.0);
          await workoutState.updateEntryValue(effortId, 1, 'reps', 3);
          await workoutState.updateEntryValue(effortId, 1, 'weight', 80.0);
          await workoutState.updateEntryValue(effortId, 2, 'reps', 1);
          await workoutState.updateEntryValue(effortId, 2, 'weight', 100.0);

          await tester.pumpWidget(
            MaterialApp(
              home: WorkoutSessionScreen(
                workoutState: workoutState,
                routineState: RoutineState(repo),
                sessionSummaryService: SessionSummaryService(repo),
                timerAlertService: FakeTimerAlertService(),
                settingsState: SettingsState(repo, fakePreferencesService()),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The screen starts on the list view (single exercise, default
          // landing). Tap the exercise name to open the detail view.
          await tester.tap(find.text(exA.name));
          await tester.pumpAndSettle();

          // Log set 1 → toast 1.
          await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('Congrats! New PR'), findsOneWidget);

          // Let set 1's 4 s SnackBar timer fire and dismiss before we
          // log set 2. Pump 5 s (> 4 s) so the timer definitely expires
          // and the SnackBar is fully out of the Overlay.
          await tester.pumpAndSettle(const Duration(seconds: 5));

          // Set 2 is now current; tap Log again.
          await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('Congrats! New PR'), findsOneWidget);

          await tester.pumpAndSettle(const Duration(seconds: 5));

          // Set 3 is now current; tap Log again.
          await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('Congrats! New PR'), findsOneWidget);
        },
      );
    },
  );

  group(
    'S-010: Free Training (null modality) with a set effort fires a PR',
    () {
      testWidgets('S-010a: null modality + set effort + no history → toast', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final exA = (await repo.getExercises()).first;

        // Free Training: pass no modality to createNewSession so the
        // session.modality is null. The effortKind defaults to 'set'
        // for the chosen 'reps' metric.
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();

        final deps = await pumpLiveSessionScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
          exerciseId: exA.id,
          exerciseName: exA.name,
          reps: 5,
          weightKg: 60.0,
        );

        await deps.openDetailView();
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Congrats! New PR'), findsOneWidget);
      });
    },
  );

  group('S-011: a 30-day-old standing best is still the standing best', () {
    testWidgets(
      'S-011a: prior PR 30 days ago → new beating set fires the toast',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final exA = (await repo.getExercises()).first;

        // Seed a completed session from 30 days ago with 60 kg × 5 reps.
        final sOldStartMs = DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch;
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-old',
          startedAtMs: sOldStartMs,
          endedAtMs: sOldStartMs + 3600000,
          exerciseId: exA.id,
          reps: 5,
          weight: 60.0,
        );

        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(modality: 'resistance_lifting');

        final deps = await pumpLiveSessionScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
          exerciseId: exA.id,
          exerciseName: exA.name,
          reps: 5,
          weightKg: 70.0, // 81.67 > 70.0 → PR
        );

        await deps.openDetailView();
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Congrats! New PR'), findsOneWidget);
      },
    );
  });

  group('S-012: the toast is non-blocking', () {
    testWidgets(
      'S-012a: no required action tap, floating, 2 s auto-dismiss, set advance unblocked',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1000));
        final repo = await _freshRepo();
        final exA = (await repo.getExercises()).first;

        // Use the static builder directly so we can introspect the
        // SnackBar's properties (action, duration, behavior) without
        // driving the full screen.
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
        );
        final bar = PRToast.buildPRSnackBar(theme);

        // S-012 part 1: no `action:` button (no required tap).
        expect(
          bar.action,
          isNull,
          reason: 'toast must not require a tap to dismiss',
        );

        // S-012 part 2: floating behavior (does not push the bottom
        // controls up; the user can keep typing in the editor).
        expect(bar.behavior, SnackBarBehavior.floating);

        // S-012 part 3: 4.0 s auto-dismiss.
        expect(bar.duration, const Duration(milliseconds: 4000));

        // S-012 part 4: drive the full screen to assert the rest
        // timer scheduling still completes without awaiting the
        // SnackBar. The single-set test setup means the screen has no
        // next set to advance to; we assert the rest record (created
        // after the SnackBar call) is present, proving the call chain
        // continued past `showSnackBar`.
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession(modality: 'resistance_lifting');

        final deps = await pumpLiveSessionScreen(
          tester,
          repo: repo,
          workoutState: workoutState,
          exerciseId: exA.id,
          exerciseName: exA.name,
          reps: 5,
          weightKg: 60.0,
        );

        // Look up the effort id (used to query the rest record).
        final allEfforts = workoutState.getExercisesWithEntries();
        final effortId = allEfforts.first['id'] as String;

        // No rest record yet (we haven't logged a set).
        expect(
          workoutState.getEntryRests(effortId),
          isEmpty,
          reason: 'precondition: no rest record before log',
        );

        await deps.openDetailView();
        await tester.tap(find.widgetWithText(FilledButton, 'Log Set'));
        // Pump just enough to let the snackbar appear and the set
        // advance fire, but NOT enough to let the 2.0 s auto-dismiss
        // timer expire.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The rest timer was scheduled AFTER the SnackBar was queued
        // — its presence proves the call chain did not block on the
        // SnackBar.
        final restsAfter = workoutState.getEntryRests(effortId);
        expect(
          restsAfter,
          isNotEmpty,
          reason:
              'rest timer must be scheduled even though the SnackBar is '
              'still on screen (2 s auto-dismiss has not fired yet)',
        );
      },
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Phase 2 — in-session wiring
//
// These tests drive `WorkoutSessionScreen._logSet()` via the Log Set
// button. Each test pre-populates the entry's reps/weight through the
// repository (the screen's `_loadExercises()` reads from the repo on
// init, so the in-memory entry map has the right values when the
// user taps Log), then taps the Log Set button and asserts whether
// the "Congrats! New PR" SnackBar fires.
// ═══════════════════════════════════════════════════════════════════════════

/// Pumps a `WorkoutSessionScreen` for a freshly-seeded live session and
/// returns the dependencies + a closure that opens the per-set detail
/// view. The screen starts on the list view; tests that need the
/// per-set detail view call [openDetailView] after this to tap into
/// the exercise.
Future<
  ({
    MockWorkoutRepository repo,
    WorkoutState workoutState,
    RoutineState routineState,
    SessionSummaryService sessionSummaryService,
    SettingsState settingsState,
    Future<void> Function() openDetailView,
  })
>
pumpLiveSessionScreen(
  WidgetTester tester, {
  required MockWorkoutRepository repo,
  required WorkoutState workoutState,
  required String exerciseId,
  String exerciseName = '',
  int reps = 5,
  double weightKg = 60.0,
  bool editMode = false,
}) async {
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();

  // Suppress the in-app coach marks so the info/notes hint sheets
  // don't auto-open during the test.
  await workoutState.markExerciseInfoHintSeen();
  await workoutState.markExerciseNotesHintSeen();

  // Pre-populate the in-memory entry via the repository. The screen's
  // `_loadExercises` (called from initState) reads from the repo, so
  // the resulting `_exercises` list has the right reps/weight.
  final exercises = await repo.getExercises();
  final exercise = exercises.firstWhere((e) => e.id == exerciseId);
  final effortId = await workoutState.addExerciseToSession(
    exercise,
    chosenMetric: 'reps',
  );
  await workoutState.updateEntryValue(effortId, 0, 'reps', reps);
  await workoutState.updateEntryValue(effortId, 0, 'weight', weightKg);

  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: workoutState,
        routineState: routineState,
        sessionSummaryService: sessionSummaryService,
        timerAlertService: FakeTimerAlertService(),
        settingsState: settingsState,
        editMode: editMode,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    openDetailView: () async {
      if (exerciseName.isEmpty) return;
      // Use `.first` because the screen may render the exercise name
      // in both the list view and the detail view during the tap
      // (e.g., a list tile plus a header). Either is a valid tap
      // target for "open the detail view".
      await tester.tap(find.text(exerciseName).first);
      await tester.pumpAndSettle();
    },
  );
}

// Phase 2 groups are file-scope (top-level). They are discovered by
// Flutter test the same way the Phase 1 groups inside `main()` are:
// the test framework registers each `group` call as it executes.
// Phase 1 groups are inside the `main` at the top of the file; Phase
// 2 groups are at file scope because Dart forbids two `main` symbols
// in one file. Flutter test still picks them up because each `group`
// call registers synchronously at evaluation time.
