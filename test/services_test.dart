import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/routine_session_manifest.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<List<String>> _captureDebugPrint(Future<void> Function() action) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };

  try {
    await action();
  } finally {
    debugPrint = original;
  }

  return logs;
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
      id: 'obs-$effortId-0-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-0-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

/// Creates a completed session with one round-based effort and one finished round.
/// Returns the session. The repo is mutated in-place.
Future<TrainingSession> _seedCompletedRoundSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String exerciseId,
  required int roundDurationSecs,
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
      effortKind: 'round',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createRoundInstance(
    RoundInstance(
      id: 'round-$sessionId-0',
      effortId: effortId,
      roundIndex: 0,
      plannedDurationSecs: roundDurationSecs,
      actualDurationSecs: roundDurationSecs,
      startedAtMs: startedAtMs,
      finishedAtMs: startedAtMs + (roundDurationSecs * 1000),
      completed: true,
      state: RoundState.finished,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs + (roundDurationSecs * 1000),
    ),
  );

  return session;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // SessionSummaryService
  // ══════════════════════════════════════════════════════════════════════════

  group('SessionSummaryService', () {
    // ── compareToPreviousSession ──────────────────────────────────────────
    //
    // NOTE — scope of these tests:
    //   • `weight:` values passed to `_seedCompletedSetSession` are canonical
    //     kg values (i.e. the post-fix storage format; 1 kg = 1 kg).
    //   • `currentVolume` is passed as a pre-computed double that simulates
    //     what `SessionSummaryBuilder` would produce for the active session.
    //     These tests do NOT exercise the display→kg write-path conversion;
    //     that is covered by `test/data_tracking_fixes_test.dart`
    //     (Volume calculation group).
    //   • `previousVolume` IS computed from stored observations via
    //     `_computeSessionVolume` → `_computeVolumeFromObservations`, so the
    //     observation-based aggregation path is exercised here.
    group('compareToPreviousSession', () {
      test('returns null delta when no previous session exists', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final session = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: 'ex-1',
          reps: 10,
          weight: 50.0,
        );

        final result = await service.compareToPreviousSession(session, 500.0);
        expect(result.currentVolume, 500.0);
        expect(result.previousVolume, isNull);
        expect(result.delta, isNull);
        expect(result.hasPrevious, false);
      });

      test('computes delta against most recent previous session', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exId = exercises.first.id;
        final service = SessionSummaryService(repo);

        // Previous session: 10 reps × 40 kg = 400 volume
        await _seedCompletedSetSession(
          repo,
          sessionId: 'prev',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exId,
          reps: 10,
          weight: 40.0,
        );

        // Current session
        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: exId,
          reps: 10,
          weight: 50.0,
        );

        // Current volume is 500 (10 × 50)
        final result = await service.compareToPreviousSession(current, 500.0);
        expect(result.currentVolume, 500.0);
        expect(result.previousVolume, 400.0);
        expect(result.delta, 100.0);
        expect(result.hasPrevious, true);
      });

      test('ignores sessions without endedAtMs (incomplete)', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        // Incomplete previous session (no endedAtMs)
        final incompleteSession = TrainingSession(
          id: 'incomplete',
          ownerUserId: 'u-1',
          startedAtMs: 1000,
          endedAtMs: null,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.createSession(incompleteSession);

        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: 'ex-1',
          reps: 5,
          weight: 20.0,
        );

        final result = await service.compareToPreviousSession(current, 100.0);
        expect(result.hasPrevious, false);
      });

      test('picks most recent previous, not oldest', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exId = exercises.first.id;
        final service = SessionSummaryService(repo);

        // Older session: 5 × 30 = 150
        await _seedCompletedSetSession(
          repo,
          sessionId: 'older',
          startedAtMs: 1000,
          endedAtMs: 1500,
          exerciseId: exId,
          reps: 5,
          weight: 30.0,
        );

        // More recent session: 8 × 25 = 200
        await _seedCompletedSetSession(
          repo,
          sessionId: 'newer',
          startedAtMs: 3000,
          endedAtMs: 3500,
          exerciseId: exId,
          reps: 8,
          weight: 25.0,
        );

        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 5500,
          exerciseId: exId,
          reps: 10,
          weight: 50.0,
        );

        final result = await service.compareToPreviousSession(current, 500.0);
        // Should compare against 'newer' (200 volume), not 'older' (150)
        expect(result.previousVolume, 200.0);
        expect(result.delta, 300.0);
      });
    });

    // ── getPreferredWeightUnit ───────────────────────────────────────────
    group('getPreferredWeightUnit', () {
      test('returns kg when no preference is stored', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        expect(await service.getPreferredWeightUnit(), 'kg');
      });

      test('returns kg when stored value is kg', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        await repo.setPreferenceString('preferred_weight_unit', 'kg');

        expect(await service.getPreferredWeightUnit(), 'kg');
      });

      test('returns lbs when stored value is lb', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        await repo.setPreferenceString('preferred_weight_unit', 'lb');

        expect(await service.getPreferredWeightUnit(), 'lbs');
      });

      test('returns lbs when stored value is lbs', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        await repo.setPreferenceString('preferred_weight_unit', 'lbs');

        expect(await service.getPreferredWeightUnit(), 'lbs');
      });

      test('returns lbs for uppercase and mixed-case values', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        await repo.setPreferenceString('preferred_weight_unit', 'LBS');
        expect(await service.getPreferredWeightUnit(), 'lbs');

        await repo.setPreferenceString('preferred_weight_unit', 'Lbs');
        expect(await service.getPreferredWeightUnit(), 'lbs');
      });

      test(
        'returns lbs when stored value has surrounding whitespace',
        () async {
          final repo = await _freshRepo();
          final service = SessionSummaryService(repo);

          await repo.setPreferenceString('preferred_weight_unit', ' lbs ');

          expect(await service.getPreferredWeightUnit(), 'lbs');
        },
      );

      test('returns kg for unrecognised stored values', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        for (final rawValue in ['pounds', 'kilograms']) {
          await repo.setPreferenceString('preferred_weight_unit', rawValue);
          expect(await service.getPreferredWeightUnit(), 'kg');
        }
      });
    });

    // ── computePRs ────────────────────────────────────────────────────────
    //
    // Plan: docs/plans/summary-pr-parity-plan.md
    //
    // PR definition here matches the in-workout toast and the Stats
    // screen: Epley e1RM, `weight × (1 + reps / 30)`, via
    // `StatsProgressService.epley1RM`. The summary used to compare
    // raw top weight — those tests were repointed at the e1RM
    // definition here so they assert the behavior the rest of the
    // app already uses (single source of truth).
    group('computePRs', () {
      test('detects a new PR when no previous best exists', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        // 80 kg × 5 reps → e1RM = 80 × (1 + 5/30) = 93.333…
        const newE1rm = 80.0 * (1 + 5 / 30);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-NEW',
            name: 'Bench Press',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 80.0,
            bestE1RM: newE1rm,
            executionOrder: 0,
          ),
        ]);

        expect(prs, hasLength(1));
        expect(prs[0].exerciseName, 'Bench Press');
        expect(prs[0].newBest, closeTo(newE1rm, 0.001));
        expect(prs[0].previousBest, 0); // no prior record
      });

      test('detects a new PR when exceeding previous best (e1RM)', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;
        final service = SessionSummaryService(repo);

        // Seed a completed session with `60 × 5` (e1RM 70.0) for this
        // exercise. The current set `70 × 5` (e1RM ~81.67) must register
        // as a PR — both old (raw-weight) and new (e1RM) definitions
        // happen to detect this one, so the assertion shape is the
        // same here.
        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0,
        );

        const newE1rm = 70.0 * (1 + 5 / 30); // ~81.67

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: newE1rm,
            executionOrder: 0,
          ),
        ]);

        expect(prs, hasLength(1));
        expect(prs[0].newBest, closeTo(newE1rm, 0.001));
        expect(prs[0].previousBest, 70.0); // historical e1RM
      });

      test('no PR when bestE1RM equals previous best (strict >)', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;
        final service = SessionSummaryService(repo);

        // History: 70 × 5 → e1RM 81.667. Current set has identical e1RM.
        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 70.0,
        );

        const e1rm = 70.0 * (1 + 5 / 30);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: e1rm,
            executionOrder: 0,
          ),
        ]);

        expect(prs, isEmpty);
      });

      test('skips non-set effort kinds', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-1',
            name: 'Running',
            effortKind: 'timed',
            setsCompleted: 1,
            bestWeight: null,
            bestE1RM: null,
            executionOrder: 0,
          ),
        ]);

        expect(prs, isEmpty);
      });

      test('skips exercises with null or zero bestE1RM', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-1',
            name: 'Bodyweight Squat',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 0.0,
            bestE1RM: 0.0,
            executionOrder: 0,
          ),
          ExerciseSummary(
            exerciseId: 'ex-2',
            name: 'Pull-up',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: null,
            bestE1RM: null,
            executionOrder: 1,
          ),
        ]);

        expect(prs, isEmpty);
      });

      // ── New scenarios (parity plan) ────────────────────────────────────

      // S-T-001: cross-surface parity — the same seed yields the same
      // "is this a PR" verdict in all three surfaces.
      test('S-T-001 cross-surface parity: same set, '
          'toast + Stats + summary all record a PR', () async {
        // ── Surface A: in-session toast ───────────────────────────
        // At the moment the user logs the new set, s-new is in-progress.
        // getAllTimeBestE1RM(exA) excludes in-progress sessions, so the
        // standing best is s-old's 70.0.
        final toastRepo = await _freshRepo();
        final toastEx = (await toastRepo.getExercises()).first;
        await _seedCompletedSetSession(
          toastRepo,
          sessionId: 's-old',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: toastEx.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        // In-progress session with the new set (reps=5, weight=70 → e1RM ~81.67).
        final toastSession = await _seedCompletedSetSession(
          toastRepo,
          sessionId: 's-new',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: toastEx.id,
          reps: 5,
          weight: 70.0,
        );
        // Re-write s-new as in-progress by clearing endedAtMs.
        await toastRepo.updateSession(
          TrainingSession(
            id: toastSession.id,
            ownerUserId: toastSession.ownerUserId,
            startedAtMs: toastSession.startedAtMs,
            // endedAtMs: null — the toast sees an in-progress session.
            createdAtMs: toastSession.createdAtMs,
            updatedAtMs: toastSession.startedAtMs,
          ),
        );
        final standingBestA = await StatsProgressService(
          toastRepo,
        ).getAllTimeBestE1RM(toastEx.id);
        expect(standingBestA, 70.0);
        final justLoggedE1rmA = StatsProgressService.epley1RM(70.0, 5)!;
        expect(justLoggedE1rmA, greaterThan(standingBestA));

        // ── Surface B: Stats screen ────────────────────────────────
        // Both sessions completed; Stats PR detection walks the per-day
        // e1RM trend and must register s-new as a PR.
        // Sessions are anchored to recent days so the new
        // recency floor (`StatsProgressService.kTopExerciseRecencyDays`)
        // keeps the exercise eligible for selection.
        final statsRepo = await _freshRepo();
        final statsEx = (await statsRepo.getExercises()).first;
        final now = DateTime.now();
        final todayMidnight = DateTime(now.year, now.month, now.day);
        final sOldMs = todayMidnight
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch;
        final sNewMs = todayMidnight
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;
        await _seedCompletedSetSession(
          statsRepo,
          sessionId: 's-old',
          startedAtMs: sOldMs,
          endedAtMs: sOldMs + 3600000,
          exerciseId: statsEx.id,
          reps: 5,
          weight: 60.0,
        );
        await _seedCompletedSetSession(
          statsRepo,
          sessionId: 's-new',
          startedAtMs: sNewMs,
          endedAtMs: sNewMs + 3600000,
          exerciseId: statsEx.id,
          reps: 5,
          weight: 70.0,
        );
        final statsData = await StatsProgressService(
          statsRepo,
        ).computeProgressData();
        final statsPRs = statsData.recentPRs
            .where((pr) => pr.exerciseName == statsEx.name)
            .toList();
        expect(statsPRs, hasLength(1));
        expect(statsPRs.first.e1Rm, closeTo(81.6667, 0.001));

        // ── Surface C: Session Summary ─────────────────────────────
        // s-new is the just-finished session. computePRs must use
        // getAllTimeBestE1RM with excludeSessionId so the just-finished
        // session's own PR is not compared against itself.
        final summaryRepo = await _freshRepo();
        final summaryEx = (await summaryRepo.getExercises()).first;
        await _seedCompletedSetSession(
          summaryRepo,
          sessionId: 's-old',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: summaryEx.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        final summarySession = await _seedCompletedSetSession(
          summaryRepo,
          sessionId: 's-new',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: summaryEx.id,
          reps: 5,
          weight: 70.0, // e1RM ~81.67
        );
        const newE1rm = 70.0 * (1 + 5 / 30);

        final summaryPRs = await SessionSummaryService(summaryRepo).computePRs([
          ExerciseSummary(
            exerciseId: summaryEx.id,
            name: summaryEx.name,
            effortKind: 'set',
            setsCompleted: 1,
            bestWeight: 70.0,
            bestE1RM: newE1rm,
            executionOrder: 0,
          ),
        ], currentSessionId: summarySession.id);

        expect(summaryPRs, hasLength(1));
        expect(summaryPRs.first.exerciseName, summaryEx.name);
        expect(summaryPRs.first.newBest, closeTo(newE1rm, 0.001));
        expect(summaryPRs.first.previousBest, 70.0);

        // ── Parity assertion ─────────────────────────────────────
        // The summary's recorded PR e1RM equals the toast's
        // justLoggedE1rm and the Stats screen's recorded PR e1RM.
        expect(summaryPRs.first.newBest, statsPRs.first.e1Rm);
        expect(summaryPRs.first.newBest, justLoggedE1rmA);
      });

      // S-T-002: first-ever performance is a PR.
      test('S-T-002 first-ever performance is a PR', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // No prior sessions for ex. The just-finished session carries
        // the user's first set.
        final session = await _seedCompletedSetSession(
          repo,
          sessionId: 'first',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        const newE1rm = 60.0 * (1 + 5 / 30);

        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 1,
            bestWeight: 60.0,
            bestE1RM: newE1rm,
            executionOrder: 0,
          ),
        ], currentSessionId: session.id);

        expect(prs, hasLength(1));
        expect(prs.first.previousBest, 0);
        expect(prs.first.newBest, closeTo(newE1rm, 0.001));
      });

      // S-T-003: rep-driven PR — more reps at a lower weight can
      // produce a higher e1RM. Under the OLD raw-weight definition
      // this was hidden; the new definition surfaces it.
      test('S-T-003 rep-driven PR: more reps at a lower weight → PR', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // History: 100 × 1 → e1RM 103.333. Old definition would have
        // used raw top weight (100) and would not detect a PR when
        // the new set's top weight is lower (80). New definition
        // uses e1RM and DOES detect a PR.
        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 1,
          weight: 100.0,
        );
        final session = await _seedCompletedSetSession(
          repo,
          sessionId: 'now',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 10,
          weight: 80.0, // e1RM = 80 × (1 + 10/30) = 106.667
        );

        // Recompute the actually-logged e1RM using the canonical
        // helper (the summary uses the same formula).
        final newE1rm = StatsProgressService.epley1RM(80.0, 10)!;
        expect(newE1rm, closeTo(106.6667, 0.001));

        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 1,
            bestWeight: 80.0, // lower than historical top weight
            bestE1RM: newE1rm,
            executionOrder: 0,
          ),
        ], currentSessionId: session.id);

        expect(prs, hasLength(1));
        expect(prs.first.previousBest, closeTo(103.3333, 0.001));
        expect(prs.first.newBest, closeTo(106.6667, 0.001));
      });

      // S-T-004: non-strength effort never produces a PR even when
      // bestE1RM is artificially populated.
      test('S-T-004 non-strength effort is never a PR', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-cardio',
            name: 'Running',
            effortKind: 'timed',
            setsCompleted: 1,
            bestWeight: null,
            bestE1RM: 150.0, // intentional red herring
            executionOrder: 0,
          ),
        ]);

        expect(prs, isEmpty);
      });

      // S-T-005: bestE1RM equal to the standing best is NOT a PR (strict).
      test('S-T-005 equal-e1RM is NOT a PR (strict >)', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        final session = await _seedCompletedSetSession(
          repo,
          sessionId: 'now',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // same e1RM 70.0
        );

        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 1,
            bestWeight: 60.0,
            bestE1RM: 70.0,
            executionOrder: 0,
          ),
        ], currentSessionId: session.id);

        expect(prs, isEmpty);
      });

      // S-T-006: bestE1RM below the standing best is NOT a PR.
      test('S-T-006 lower-e1RM is NOT a PR', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        final session = await _seedCompletedSetSession(
          repo,
          sessionId: 'now',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 3,
          weight: 50.0, // e1RM 55.0
        );

        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 1,
            bestWeight: 50.0,
            bestE1RM: 55.0,
            executionOrder: 0,
          ),
        ], currentSessionId: session.id);

        expect(prs, isEmpty);
      });

      // S-T-007: getAllTimeBestE1RM zero-arg path unchanged.
      // (Locks down that the toast's behavior is preserved by adding
      // the optional excludeSessionId parameter — D-3 / D-6.)
      test('S-T-007 getAllTimeBestE1RM with no excludeSessionId '
          'excludes in-progress sessions only', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 's-old',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        // Build an in-progress session manually so we can set its
        // observation e1RM above the historical best without
        // _seedCompletedSetSession forcibly closing it.
        final session = TrainingSession(
          id: 's-in-progress',
          ownerUserId: 'u-1',
          startedAtMs: 3000,
          // endedAtMs: null → in-progress
          createdAtMs: 3000,
          updatedAtMs: 3000,
        );
        await repo.createSession(session);
        final segId = 'seg-s-in-progress';
        await repo.createSegment(
          SessionSegment(
            id: segId,
            sessionId: 's-in-progress',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: 3000,
            updatedAtMs: 3000,
          ),
        );
        final effortId = 'eff-s-in-progress';
        await repo.createEffort(
          SegmentEffort(
            id: effortId,
            segmentId: segId,
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: ex.id,
            createdAtMs: 3000,
            updatedAtMs: 3000,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-reps-in-progress',
            effortId: effortId,
            metricId: 'metric-reps',
            valueInt: 5,
            createdAtMs: 3000,
            updatedAtMs: 3000,
          ),
        );
        await repo.createObservation(
          EffortObservation(
            id: 'obs-weight-in-progress',
            effortId: effortId,
            metricId: 'metric-weight',
            valueReal: 90.0, // e1RM 105
            createdAtMs: 3001,
            updatedAtMs: 3001,
          ),
        );

        final service = StatsProgressService(repo);
        // Zero-arg (toast path): in-progress excluded → 70.0.
        expect(await service.getAllTimeBestE1RM(ex.id), 70.0);
        // Explicit exclude (summary path): same answer, 70.0.
        expect(
          await service.getAllTimeBestE1RM(
            ex.id,
            excludeSessionId: 's-in-progress',
          ),
          70.0,
        );
        // And the in-progress session's e1RM does NOT show up in
        // either call — its 105.0 must remain hidden.
      });

      // S-T-008: getAllTimeBestE1RM(excludeSessionId) excludes only
      // the named session.
      test('S-T-008 getAllTimeBestE1RM(excludeSessionId) '
          'excludes only the named session', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 's-1',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-2',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 5,
          weight: 80.0, // e1RM ~93.33
        );

        final service = StatsProgressService(repo);
        // Unfiltered: max of both = ~93.33.
        expect(
          await service.getAllTimeBestE1RM(ex.id),
          closeTo(93.3333, 0.001),
        );
        // Exclude s-2: just s-1 = 70.0.
        expect(
          await service.getAllTimeBestE1RM(ex.id, excludeSessionId: 's-2'),
          70.0,
        );
        // Exclude s-1: just s-2 = ~93.33.
        expect(
          await service.getAllTimeBestE1RM(ex.id, excludeSessionId: 's-1'),
          closeTo(93.3333, 0.001),
        );
        // Excluding an unrelated id is a no-op.
        expect(
          await service.getAllTimeBestE1RM(
            ex.id,
            excludeSessionId: 's-does-not-exist',
          ),
          closeTo(93.3333, 0.001),
        );
      });

      // ── Stats & Summary Fix Pack — PR 1 (PR de-duplication) ─────────────
      //
      // Plan: docs/plans/stats-summary-fix-pack-plan.md
      //
      // One session can produce only one new record per exercise.
      // When the same exercise appears in more than one block (e.g.
      // a user clones a block three times) the current implementation
      // emits one `PRAchievement` per `ExerciseSummary` (one per
      // block), burying the genuine best among duplicates. The
      // fixed `computePRs` collapses the list to at most one entry
      // per exercise per session, at the session's true maximum.
      //
      // The verdict ("is this a PR") is unchanged — only the entry
      // count collapses. Set count, total volume, and the per-exercise
      // breakdown are byte-equal before and after this change.

      // S-001: same exercise in 3 cloned blocks, all beating the prior
      // best → exactly one PR entry at the true maximum.
      test('S-001 same exercise in 3 cloned blocks → exactly one PR entry '
          'at the true maximum', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // Prior history: 60 × 5 → e1RM 70.0.
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-prior',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0,
        );
        final currentSession = await _seedCompletedSetSession(
          repo,
          sessionId: 's-current',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 5,
          weight: 70.0, // e1RM ~81.67
        );

        // Three `ExerciseSummary` entries for the same exercise,
        // simulating three cloned blocks that each logged the
        // same set. Each entry's `bestE1RM` is the same — the
        // session's only qualifying effort — but they are
        // independent `ExerciseSummary` rows so the bug-fix has
        // to actually collapse them.
        const newE1rm = 70.0 * (1 + 5 / 30);
        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: newE1rm,
            executionOrder: 0,
            blockId: 'block-1',
          ),
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: newE1rm,
            executionOrder: 1,
            blockId: 'block-2',
          ),
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: newE1rm,
            executionOrder: 2,
            blockId: 'block-3',
          ),
        ], currentSessionId: currentSession.id);

        expect(prs, hasLength(1));
        expect(prs.first.exerciseName, ex.name);
        expect(prs.first.newBest, closeTo(newE1rm, 0.001));
        expect(prs.first.previousBest, 70.0);
      });

      // S-002: two different exercises, each in multiple blocks → one
      // entry each, at their respective maximums.
      test(
        'S-002 two exercises across multiple blocks → one entry each',
        () async {
          final repo = await _freshRepo();
          final allExercises = await repo.getExercises();
          // Pick two distinct seeded exercises — the seed provides
          // multiple resistance exercises.
          final exA = allExercises.first;
          final exB = allExercises[1];

          // Prior history for both: 60 × 5 → e1RM 70.0 each.
          await _seedCompletedSetSession(
            repo,
            sessionId: 's-prior-A',
            startedAtMs: 1000,
            endedAtMs: 2000,
            exerciseId: exA.id,
            reps: 5,
            weight: 60.0,
          );
          await _seedCompletedSetSession(
            repo,
            sessionId: 's-prior-B',
            startedAtMs: 1100,
            endedAtMs: 2100,
            exerciseId: exB.id,
            reps: 5,
            weight: 60.0,
          );
          final currentSession = await _seedCompletedSetSession(
            repo,
            sessionId: 's-current-A',
            startedAtMs: 3000,
            endedAtMs: 4000,
            exerciseId: exA.id,
            reps: 5,
            weight: 70.0,
          );

          // exA's session maximum is 80 × 5 = e1RM 93.33 across
          // three cloned blocks; exB's is 70 × 5 = e1RM 81.67
          // across two cloned blocks.
          const newE1rmA = 80.0 * (1 + 5 / 30);
          const newE1rmB = 70.0 * (1 + 5 / 30);

          final prs = await SessionSummaryService(repo).computePRs([
            ExerciseSummary(
              exerciseId: exA.id,
              name: exA.name,
              effortKind: 'set',
              setsCompleted: 3,
              bestWeight: 80.0,
              bestE1RM: newE1rmA,
              executionOrder: 0,
              blockId: 'A-block-1',
            ),
            ExerciseSummary(
              exerciseId: exA.id,
              name: exA.name,
              effortKind: 'set',
              setsCompleted: 3,
              bestWeight: 80.0,
              bestE1RM: newE1rmA,
              executionOrder: 1,
              blockId: 'A-block-2',
            ),
            ExerciseSummary(
              exerciseId: exA.id,
              name: exA.name,
              effortKind: 'set',
              setsCompleted: 3,
              bestWeight: 80.0,
              bestE1RM: newE1rmA,
              executionOrder: 2,
              blockId: 'A-block-3',
            ),
            ExerciseSummary(
              exerciseId: exB.id,
              name: exB.name,
              effortKind: 'set',
              setsCompleted: 3,
              bestWeight: 70.0,
              bestE1RM: newE1rmB,
              executionOrder: 3,
              blockId: 'B-block-1',
            ),
            ExerciseSummary(
              exerciseId: exB.id,
              name: exB.name,
              effortKind: 'set',
              setsCompleted: 3,
              bestWeight: 70.0,
              bestE1RM: newE1rmB,
              executionOrder: 4,
              blockId: 'B-block-2',
            ),
          ], currentSessionId: currentSession.id);

          expect(prs, hasLength(2));
          final byName = {for (final p in prs) p.exerciseName: p};
          expect(byName[exA.name]?.newBest, closeTo(newE1rmA, 0.001));
          expect(byName[exA.name]?.previousBest, 70.0);
          expect(byName[exB.name]?.newBest, closeTo(newE1rmB, 0.001));
          expect(byName[exB.name]?.previousBest, 70.0);
        },
      );

      // S-003: cloned block that does NOT beat the prior best →
      // zero record entries for that exercise.
      test('S-003 cloned blocks below prior best → zero PR entries', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        // Prior history: 80 × 5 → e1RM ~93.33 (high bar).
        await _seedCompletedSetSession(
          repo,
          sessionId: 's-prior',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 80.0,
        );
        final currentSession = await _seedCompletedSetSession(
          repo,
          sessionId: 's-current',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 5,
          weight: 70.0, // e1RM ~81.67 — strictly below 93.33
        );

        // Two cloned blocks, both below the prior best.
        const belowBest = 70.0 * (1 + 5 / 30);
        final prs = await SessionSummaryService(repo).computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: belowBest,
            executionOrder: 0,
            blockId: 'block-1',
          ),
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: belowBest,
            executionOrder: 1,
            blockId: 'block-2',
          ),
        ], currentSessionId: currentSession.id);

        expect(prs, isEmpty);
      });

      // S-004: collapsing across blocks picks the maximum even when
      // entries disagree on `bestE1RM` (e.g. block-1 had 70 kg × 5,
      // block-2 had 80 kg × 5 — same exercise, different block
      // maxima). The single surviving entry must be at 80 × 5.
      test('S-004 collapsing picks the maximum across blocks', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;

        await _seedCompletedSetSession(
          repo,
          sessionId: 's-prior',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0, // e1RM 70.0
        );
        final currentSession = await _seedCompletedSetSession(
          repo,
          sessionId: 's-current',
          startedAtMs: 3000,
          endedAtMs: 4000,
          exerciseId: ex.id,
          reps: 5,
          weight: 80.0,
        );

        const e1rm70 = 70.0 * (1 + 5 / 30); // ~81.67
        const e1rm80 = 80.0 * (1 + 5 / 30); // ~93.33

        final prs = await SessionSummaryService(repo).computePRs([
          // Lower block — appears first in executionOrder but is
          // NOT the session maximum.
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            bestE1RM: e1rm70,
            executionOrder: 0,
            blockId: 'block-lower',
          ),
          // Higher block — must win.
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 80.0,
            bestE1RM: e1rm80,
            executionOrder: 1,
            blockId: 'block-higher',
          ),
        ], currentSessionId: currentSession.id);

        expect(prs, hasLength(1));
        expect(prs.first.newBest, closeTo(e1rm80, 0.001));
        expect(prs.first.previousBest, 70.0);
      });
    });

    group('session summary redesign helpers', () {
      test(
        'computeSessionRestTimeMs sums closed rests and excludes open rests',
        () async {
          final repo = await _freshRepo();
          final exercises = await repo.getExercises();
          final exId = exercises.first.id;
          final service = SessionSummaryService(repo);

          // Session window must encompass all rest intervals so clipping
          // does not affect the 70 000 ms expected sum.
          final session = TrainingSession(
            id: 'session-rest',
            ownerUserId: 'u-1',
            startedAtMs: 1000,
            endedAtMs: 200000,
            createdAtMs: 1000,
            updatedAtMs: 200000,
          );
          await repo.createSession(session);

          final segId = 'seg-rest';
          await repo.createSegment(
            SessionSegment(
              id: segId,
              sessionId: session.id,
              orderIndex: 0,
              segmentType: 'main',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          final effortId = 'eff-rest';
          await repo.createEffort(
            SegmentEffort(
              id: effortId,
              segmentId: segId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exId,
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );

          await repo.createEntryRest(
            EntryRest(
              id: 'closed-a',
              effortId: effortId,
              entryIndex: 0,
              restStartMs: 10000,
              restEndMs: 40000,
              createdAtMs: 10000,
              updatedAtMs: 40000,
            ),
          );
          await repo.createEntryRest(
            EntryRest(
              id: 'closed-b',
              effortId: effortId,
              entryIndex: 1,
              restStartMs: 50000,
              restEndMs: 90000,
              createdAtMs: 50000,
              updatedAtMs: 90000,
            ),
          );
          await repo.createEntryRest(
            EntryRest(
              id: 'open-c',
              effortId: effortId,
              entryIndex: 2,
              restStartMs: 100000,
              restEndMs: null,
              createdAtMs: 100000,
              updatedAtMs: 100000,
            ),
          );

          final totalMs = await service.computeSessionRestTimeMs(session.id);
          expect(totalMs, 70000);
        },
      );

      test(
        'computeSessionRestTimeMs merges overlapping rests across two efforts',
        () async {
          // Exercise A rest: T=60 000 → T=120 000 (60 s)
          // Exercise B rest: T=80 000 → T=140 000 (60 s)
          // Merged:          T=60 000 → T=140 000 (80 s)
          final repo = await _freshRepo();
          final exercises = await repo.getExercises();
          final exId = exercises.first.id;
          final service = SessionSummaryService(repo);

          const sessionStart = 0;
          const sessionEnd = 200000;
          const sessionId = 'session-overlap';

          final session = TrainingSession(
            id: sessionId,
            ownerUserId: 'u-1',
            startedAtMs: sessionStart,
            endedAtMs: sessionEnd,
            createdAtMs: sessionStart,
            updatedAtMs: sessionEnd,
          );
          await repo.createSession(session);

          final segId = 'seg-overlap';
          await repo.createSegment(
            SessionSegment(
              id: segId,
              sessionId: sessionId,
              orderIndex: 0,
              segmentType: 'main',
              createdAtMs: sessionStart,
              updatedAtMs: sessionStart,
            ),
          );

          final effortIdA = 'eff-overlap-a';
          await repo.createEffort(
            SegmentEffort(
              id: effortIdA,
              segmentId: segId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exId,
              createdAtMs: sessionStart,
              updatedAtMs: sessionStart,
            ),
          );

          final effortIdB = 'eff-overlap-b';
          await repo.createEffort(
            SegmentEffort(
              id: effortIdB,
              segmentId: segId,
              orderIndex: 1,
              effortKind: 'set',
              exerciseId: exId,
              createdAtMs: sessionStart,
              updatedAtMs: sessionStart,
            ),
          );

          await repo.createEntryRest(
            EntryRest(
              id: 'rest-a',
              effortId: effortIdA,
              entryIndex: 0,
              restStartMs: 60000,
              restEndMs: 120000,
              createdAtMs: 60000,
              updatedAtMs: 120000,
            ),
          );
          await repo.createEntryRest(
            EntryRest(
              id: 'rest-b',
              effortId: effortIdB,
              entryIndex: 0,
              restStartMs: 80000,
              restEndMs: 140000,
              createdAtMs: 80000,
              updatedAtMs: 140000,
            ),
          );

          final totalMs = await service.computeSessionRestTimeMs(sessionId);
          // Merged window: 60 000 → 140 000 = 80 000 ms (not 120 000 ms)
          expect(totalMs, 80000);
          expect(totalMs, lessThanOrEqualTo(sessionEnd - sessionStart));
        },
      );

      test(
        'computeSessionRestTimeMs clips rest intervals to session window',
        () async {
          // Rest extends 5 s before session start and 5 s beyond session end.
          // Only the portion inside the window should be counted.
          final repo = await _freshRepo();
          final exercises = await repo.getExercises();
          final exId = exercises.first.id;
          final service = SessionSummaryService(repo);

          const sessionStart = 10000;
          const sessionEnd = 50000;
          const sessionId = 'session-clip';

          final session = TrainingSession(
            id: sessionId,
            ownerUserId: 'u-1',
            startedAtMs: sessionStart,
            endedAtMs: sessionEnd,
            createdAtMs: sessionStart,
            updatedAtMs: sessionEnd,
          );
          await repo.createSession(session);

          final segId = 'seg-clip';
          await repo.createSegment(
            SessionSegment(
              id: segId,
              sessionId: sessionId,
              orderIndex: 0,
              segmentType: 'main',
              createdAtMs: sessionStart,
              updatedAtMs: sessionStart,
            ),
          );

          final effortId = 'eff-clip';
          await repo.createEffort(
            SegmentEffort(
              id: effortId,
              segmentId: segId,
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: exId,
              createdAtMs: sessionStart,
              updatedAtMs: sessionStart,
            ),
          );

          // Rest starts before session and ends after session.
          await repo.createEntryRest(
            EntryRest(
              id: 'rest-wide',
              effortId: effortId,
              entryIndex: 0,
              restStartMs: sessionStart - 5000, // 5 s before session
              restEndMs: sessionEnd + 5000, // 5 s after session
              createdAtMs: sessionStart,
              updatedAtMs: sessionEnd,
            ),
          );

          final totalMs = await service.computeSessionRestTimeMs(sessionId);
          // Clipped to [sessionStart, sessionEnd] = 40 000 ms
          expect(totalMs, sessionEnd - sessionStart);
        },
      );

      test(
        'computeSessionRestTimeMs returns 0 for session with no rest records',
        () async {
          final repo = await _freshRepo();
          final service = SessionSummaryService(repo);

          final session = TrainingSession(
            id: 'session-no-rests',
            ownerUserId: 'u-1',
            startedAtMs: 0,
            endedAtMs: 60000,
            createdAtMs: 0,
            updatedAtMs: 60000,
          );
          await repo.createSession(session);

          final totalMs = await service.computeSessionRestTimeMs(session.id);
          expect(totalMs, 0);
        },
      );

      test('buildGroupMetrics counts timed entries as rounds for cardio', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        // NOTE: totalVolume is pre-computed and passed in here — this test
        // validates grouping/metric logic, not the write-path kg canonicalization.
        // Round-trip canonicalization is covered in data_tracking_fixes_test.dart.
        final summary = SessionSummary(
          sessionId: 's1',
          title: 'test',
          startedAtMs: 1000,
          endedAtMs: 2000,
          totalDurationMs: 1000,
          totalVolume: 1200,
          totalSets: 5,
          totalRounds: 3,
          totalCardioDurationMs: 90000,
          totalDrillDurationMs: 45000,
          exercises: [
            ExerciseSummary(
              exerciseId: 'a',
              name: 'Run',
              effortKind: 'timed',
              setsCompleted: 4,
              bestWeight: null,
              executionOrder: 0,
              totalDurationMs: 90000,
            ),
            ExerciseSummary(
              exerciseId: 'b',
              name: 'Plank',
              effortKind: 'drill',
              setsCompleted: 2,
              bestWeight: null,
              executionOrder: 1,
              totalDurationMs: 45000,
            ),
            ExerciseSummary(
              exerciseId: 'c',
              name: 'Spar',
              effortKind: 'round',
              setsCompleted: 3,
              bestWeight: null,
              executionOrder: 2,
              totalRounds: 3,
            ),
          ],
        );

        final metrics = await service.buildGroupMetrics(summary);
        expect(metrics['cardio']?.primaryCount, 4);
        expect(metrics['cardio']?.effortDurationMs, 90000);
        expect(metrics['rounds']?.primaryCount, 3);
        expect(metrics['isometric']?.primaryCount, 2);
      });
    });

    // ── saveRoutineFromDraft ──────────────────────────────────────────────
    group('saveRoutineFromDraft', () {
      test('creates template, segment, efforts, and targets in repo', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final draft = SessionTemplateDraft(
          name: 'Push Day',
          focusModality: 'resistance_lifting',
          exercises: [
            SessionTemplateExercise(
              exerciseId: 'ex-1',
              name: 'Bench Press',
              effortKind: 'set',
              targets: [
                TemplateTargetDraft(
                  metricId: 'metric-reps',
                  setIndex: 0,
                  unitId: 'unit-reps',
                  valueReal: null,
                  valueInt: 8,
                  valueText: null,
                ),
                TemplateTargetDraft(
                  metricId: 'metric-weight',
                  setIndex: 0,
                  unitId: 'unit-kg',
                  valueReal: 60.0,
                  valueInt: null,
                  valueText: null,
                ),
              ],
            ),
          ],
        );

        final templateId = await service.saveRoutineFromDraft(draft);
        expect(templateId, isNotEmpty);

        // Verify template was persisted
        final template = await repo.getTemplateById(templateId);
        expect(template, isNotNull);
        expect(template!.name, 'Push Day');
        expect(template.focusModality, 'resistance_lifting');

        // Verify segment
        final segments = await repo.getTemplateSegments(templateId);
        expect(segments, hasLength(1));
        expect(segments.first.segmentType, 'main');

        // Verify effort
        final efforts = await repo.getTemplateEfforts(segments.first.id);
        expect(efforts, hasLength(1));
        expect(efforts.first.exerciseId, 'ex-1');
        expect(efforts.first.effortKind, 'set');

        // Verify targets
        final targets = await repo.getTemplateTargets(efforts.first.id);
        expect(targets, hasLength(2));
      });

      test('uses focusModality override when provided', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final draft = SessionTemplateDraft(
          name: 'Workout',
          focusModality: 'cardio_endurance',
          exercises: [],
        );

        final templateId = await service.saveRoutineFromDraft(
          draft,
          focusModality: 'resistance_lifting',
        );

        final template = await repo.getTemplateById(templateId);
        expect(template!.focusModality, 'resistance_lifting');
      });

      test(
        'handles draft with no exercises (creates empty template)',
        () async {
          final repo = await _freshRepo();
          final service = SessionSummaryService(repo);

          final draft = SessionTemplateDraft(
            name: 'Empty',
            focusModality: null,
            exercises: [],
          );

          final templateId = await service.saveRoutineFromDraft(draft);
          expect(templateId, isNotEmpty);

          final template = await repo.getTemplateById(templateId);
          expect(template, isNotNull);

          final segments = await repo.getTemplateSegments(templateId);
          expect(segments, hasLength(1)); // Segment still created
        },
      );
    });

    // ── compareGroupsToPreviousSession ────────────────────────────────────
    group('compareGroupsToPreviousSession', () {
      test('returns hasPrevious=false when no previous session', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: 'ex-1',
          reps: 10,
          weight: 50.0,
        );

        // NOTE: totalVolume is a pre-computed input here — this tests comparison
        // logic only (hasPrevious=false because there is no prior session).
        // Write-path kg canonicalization is covered in data_tracking_fixes_test.dart.
        final summary = SessionSummary(
          sessionId: 'current',
          title: 'Workout',
          startedAtMs: 5000,
          endedAtMs: 6000,
          totalDurationMs: 1000,
          totalVolume: 500.0,
          totalSets: 1,
          exercises: [],
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          summary,
        );
        expect(result.containsKey('strength'), true);
        expect(result['strength']!.hasPrevious, false);
        expect(result['strength']!.delta, isNull);
      });

      test('computes delta for strength group with previous session', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final exId = exercises.first.id;
        final service = SessionSummaryService(repo);

        // Previous: 10 × 40 = 400
        await _seedCompletedSetSession(
          repo,
          sessionId: 'prev',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: exId,
          reps: 10,
          weight: 40.0,
        );

        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: exId,
          reps: 10,
          weight: 50.0,
        );

        // NOTE: totalVolume (500.0 kg) is pre-computed. This tests the delta
        // calculation logic. Both current and previous volumes are canonical kg;
        // the actual write-path canonicalization is tested in data_tracking_fixes_test.dart.
        final summary = SessionSummary(
          sessionId: 'current',
          title: 'Workout',
          startedAtMs: 5000,
          endedAtMs: 6000,
          totalDurationMs: 1000,
          totalVolume: 500.0,
          totalSets: 1,
          exercises: [],
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          summary,
        );
        expect(result['strength']!.hasPrevious, true);
        expect(result['strength']!.delta, 100.0); // 500 - 400
        expect(result['strength']!.unit, 'kg');
      });

      test('only includes groups with non-zero values', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final current = await _seedCompletedSetSession(
          repo,
          sessionId: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          exerciseId: 'ex-1',
          reps: 10,
          weight: 50.0,
        );

        // NOTE: totalVolume is pre-computed — this tests group filtering logic only.
        final summary = SessionSummary(
          sessionId: 'current',
          title: 'Workout',
          startedAtMs: 5000,
          endedAtMs: 6000,
          totalDurationMs: 1000,
          totalVolume: 500.0,
          totalSets: 1,
          exercises: [],
          totalRounds: 0,
          totalCardioDurationMs: 0,
          totalDrillDurationMs: 0,
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          summary,
        );
        // Only 'strength' should be present (totalVolume > 0)
        expect(result.containsKey('strength'), true);
        expect(result.containsKey('cardio'), false);
        expect(result.containsKey('rounds'), false);
        expect(result.containsKey('isometric'), false);
      });

      test('uses duration delta and ms unit for rounds group', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final roundExerciseId = exercises
            .firstWhere((e) => e.capabilities.contains('rounds'))
            .id;
        final service = SessionSummaryService(repo);

        await _seedCompletedRoundSession(
          repo,
          sessionId: 'prev-round',
          startedAtMs: 1000,
          endedAtMs: 220000,
          exerciseId: roundExerciseId,
          roundDurationSecs: 300,
        );

        final current = await _seedCompletedRoundSession(
          repo,
          sessionId: 'current-round',
          startedAtMs: 400000,
          endedAtMs: 700000,
          exerciseId: roundExerciseId,
          roundDurationSecs: 306,
        );

        final summary = SessionSummary(
          sessionId: 'current-round',
          title: 'Sports Session',
          startedAtMs: 400000,
          endedAtMs: 700000,
          totalDurationMs: 300000,
          totalVolume: 0,
          totalSets: 0,
          totalRounds: 1,
          totalRoundDurationMs: 306000,
          exercises: const [],
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          summary,
        );

        expect(result['rounds']!.hasPrevious, true);
        expect(result['rounds']!.unit, 'ms');
        expect(result['rounds']!.delta, 6000.0);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RoutineSessionService
  // ══════════════════════════════════════════════════════════════════════════

  group('RoutineSessionService', () {
    // ── Helper to seed a template in the repo ────────────────────────────
    Future<String> seedTemplate(
      MockWorkoutRepository repo, {
      String templateId = 'tmpl-1',
      String? exerciseId,
      int setCount = 3,
    }) async {
      final exercises = await repo.getExercises();
      final exId = exerciseId ?? exercises.first.id;

      await repo.createTemplate(
        WorkoutTemplate(
          id: templateId,
          name: 'Test Routine',
          focusModality: 'resistance_lifting',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-1',
          templateId: templateId,
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-1',
          templateSegmentId: 'tseg-1',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: exId,
          restSeconds: 90,
          restType: 'fixed',
          createdAtMs: 100,
        ),
      );

      // Create targets for each set
      for (int i = 0; i < setCount; i++) {
        await repo.createTemplateTarget(
          TemplateTarget(
            id: 'ttgt-reps-$i',
            templateEffortId: 'teff-1',
            metricId: 'metric-reps',
            setIndex: i,
            targetInt: 8,
            createdAtMs: 100,
            updatedAtMs: 100,
          ),
        );
        await repo.createTemplateTarget(
          TemplateTarget(
            id: 'ttgt-weight-$i',
            templateEffortId: 'teff-1',
            metricId: 'metric-weight',
            setIndex: i,
            targetMin: 50.0,
            createdAtMs: 100,
            updatedAtMs: 100,
          ),
        );
      }

      return templateId;
    }

    test('builds manifest from a valid template', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);
      final templateId = await seedTemplate(repo);

      final manifest = await service.buildSessionFromTemplate(templateId);

      expect(manifest.isEmpty, false);
      expect(manifest.segments, hasLength(1));
      expect(manifest.totalExercises, 1);
      expect(manifest.exercises.first.effortKind, 'set');
      expect(manifest.exercises.first.setCount, 3);
      expect(manifest.exercises.first.restSeconds, 90);
      expect(manifest.exercises.first.restType, 'fixed');
    });

    test('throws when template not found', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);

      expect(
        () => service.buildSessionFromTemplate('nonexistent'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Template not found'),
          ),
        ),
      );
    });

    test('throws when template has no segments', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);

      // Create template with no segments
      await repo.createTemplate(
        WorkoutTemplate(
          id: 'empty-tmpl',
          name: 'Empty',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      expect(
        () => service.buildSessionFromTemplate('empty-tmpl'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no segments'),
          ),
        ),
      );
    });

    test('throws when template has segments but no exercises', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);

      await repo.createTemplate(
        WorkoutTemplate(
          id: 'no-ex-tmpl',
          name: 'No Exercises',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-empty',
          templateId: 'no-ex-tmpl',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      expect(
        () => service.buildSessionFromTemplate('no-ex-tmpl'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no exercises'),
          ),
        ),
      );
    });

    test('skips efforts with null exerciseId', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final service = RoutineSessionService(repo);

      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-skip',
          name: 'With Skip',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-skip',
          templateId: 'tmpl-skip',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      // Effort with null exerciseId (should be skipped)
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-null',
          templateSegmentId: 'tseg-skip',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: null,
          createdAtMs: 100,
        ),
      );

      // Effort with valid exerciseId
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-valid',
          templateSegmentId: 'tseg-skip',
          orderIndex: 1,
          effortKind: 'set',
          exerciseId: exercises.first.id,
          createdAtMs: 100,
        ),
      );

      final manifest = await service.buildSessionFromTemplate('tmpl-skip');
      expect(manifest.totalExercises, 1);
    });

    test('skipps efforts referencing deleted/missing exercises', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);

      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-miss',
          name: 'Missing Ex',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-miss',
          templateId: 'tmpl-miss',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      // Effort referencing a non-existent exercise
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-miss',
          templateSegmentId: 'tseg-miss',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: 'nonexistent-exercise',
          createdAtMs: 100,
        ),
      );

      // All exercises skipped → should throw "no exercises"
      expect(
        () => service.buildSessionFromTemplate('tmpl-miss'),
        throwsA(isA<Exception>()),
      );
    });

    test('defaults setCount to 1 when no targets exist', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final service = RoutineSessionService(repo);

      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-notargets',
          name: 'No Targets',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-nt',
          templateId: 'tmpl-notargets',
          orderIndex: 0,
          segmentType: 'main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-nt',
          templateSegmentId: 'tseg-nt',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: exercises.first.id,
          createdAtMs: 100,
        ),
      );
      // No targets created

      final manifest = await service.buildSessionFromTemplate('tmpl-notargets');
      expect(manifest.exercises.first.setCount, 1);
    });

    test('sorts segments by orderIndex', () async {
      final repo = await _freshRepo();
      final exercises = await repo.getExercises();
      final service = RoutineSessionService(repo);

      await repo.createTemplate(
        WorkoutTemplate(
          id: 'tmpl-sort',
          name: 'Sort Test',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      // Create segments in reverse order
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-second',
          templateId: 'tmpl-sort',
          orderIndex: 1,
          segmentType: 'accessory',
          name: 'Accessory',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );
      await repo.createTemplateSegment(
        TemplateSegment(
          id: 'tseg-first',
          templateId: 'tmpl-sort',
          orderIndex: 0,
          segmentType: 'main',
          name: 'Main',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      );

      // Add exercises to both segments
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-s1',
          templateSegmentId: 'tseg-first',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: exercises.first.id,
          createdAtMs: 100,
        ),
      );
      await repo.createTemplateEffort(
        TemplateEffort(
          id: 'teff-s2',
          templateSegmentId: 'tseg-second',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: exercises.last.id,
          createdAtMs: 100,
        ),
      );

      final manifest = await service.buildSessionFromTemplate('tmpl-sort');
      expect(manifest.segments, hasLength(2));
      expect(manifest.segments[0].segment.name, 'Main');
      expect(manifest.segments[1].segment.name, 'Accessory');
    });

    test('getTargetsForSet filters by setIndex', () async {
      final repo = await _freshRepo();
      final service = RoutineSessionService(repo);
      final templateId = await seedTemplate(repo, setCount: 3);

      final manifest = await service.buildSessionFromTemplate(templateId);
      final entry = manifest.exercises.first;

      // Each set should have 2 targets (reps + weight)
      expect(entry.getTargetsForSet(0), hasLength(2));
      expect(entry.getTargetsForSet(1), hasLength(2));
      expect(entry.getTargetsForSet(2), hasLength(2));
      expect(entry.getTargetsForSet(99), isEmpty); // nonexistent set
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // VolumeComparison model
  // ══════════════════════════════════════════════════════════════════════════

  group('VolumeComparison', () {
    test('hasPrevious returns true when both fields are non-null', () {
      final vc = VolumeComparison(
        currentVolume: 500,
        previousVolume: 400,
        delta: 100,
      );
      expect(vc.hasPrevious, true);
    });

    test('hasPrevious returns false when previousVolume is null', () {
      final vc = VolumeComparison(
        currentVolume: 500,
        previousVolume: null,
        delta: null,
      );
      expect(vc.hasPrevious, false);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // RoutineSessionManifest model
  // ══════════════════════════════════════════════════════════════════════════

  group('RoutineSessionManifest', () {
    test('isEmpty when segments list is empty', () {
      final manifest = RoutineSessionManifest(
        template: WorkoutTemplate(
          id: 't-1',
          name: 'Test',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        segments: [],
      );
      expect(manifest.isEmpty, true);
      expect(manifest.totalExercises, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TimerAlertService (web diagnostics)
  // ══════════════════════════════════════════════════════════════════════════

  group('TimerAlertService web diagnostics', () {
    test('logs effort timer alert with sound id on web', () async {
      final service = TimerAlertService.forTesting(isWeb: true);

      final logs = await _captureDebugPrint(() async {
        await service.fireEffortTimerAlert('digital_buzzer');
      });

      expect(
        logs.where((m) => m.contains('[TimerAlertService][web]')),
        isNotEmpty,
      );
      expect(logs.where((m) => m.contains('alert=effort_timer')), isNotEmpty);
      expect(
        logs.where((m) => m.contains('soundId=digital_buzzer')),
        isNotEmpty,
      );
    });

    test('logs rest ping alert with sound id on web', () async {
      final service = TimerAlertService.forTesting(isWeb: true);

      final logs = await _captureDebugPrint(() async {
        await service.fireRestPingAlert('soft_chime');
      });

      expect(
        logs.where((m) => m.contains('[TimerAlertService][web]')),
        isNotEmpty,
      );
      expect(logs.where((m) => m.contains('alert=rest_ping')), isNotEmpty);
      expect(logs.where((m) => m.contains('soundId=soft_chime')), isNotEmpty);
    });

    test('logs sound preview request with sound id on web', () async {
      final service = TimerAlertService.forTesting(isWeb: true);

      final logs = await _captureDebugPrint(() async {
        await service.playPreview('signal_tone');
      });

      expect(
        logs.where((m) => m.contains('[TimerAlertService][web]')),
        isNotEmpty,
      );
      expect(logs.where((m) => m.contains('alert=sound_preview')), isNotEmpty);
      expect(logs.where((m) => m.contains('soundId=signal_tone')), isNotEmpty);
    });
  });
}
