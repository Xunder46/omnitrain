import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/routine_session_manifest.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

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
    group('computePRs', () {
      test('detects a new PR when no previous best exists', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-NEW',
            name: 'Bench Press',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 80.0,
            executionOrder: 0,
          ),
        ]);

        expect(prs, hasLength(1));
        expect(prs[0].exerciseName, 'Bench Press');
        expect(prs[0].newBest, 80.0);
        expect(prs[0].previousBest, 0); // no prior record
      });

      test('detects a new PR when exceeding previous best', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;
        final service = SessionSummaryService(repo);

        // Seed a completed session with 60 kg for this exercise
        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 60.0,
        );

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
            executionOrder: 0,
          ),
        ]);

        expect(prs, hasLength(1));
        expect(prs[0].newBest, 70.0);
        expect(prs[0].previousBest, 60.0);
      });

      test('no PR when bestWeight equals previous best', () async {
        final repo = await _freshRepo();
        final exercises = await repo.getExercises();
        final ex = exercises.first;
        final service = SessionSummaryService(repo);

        await _seedCompletedSetSession(
          repo,
          sessionId: 'past',
          startedAtMs: 1000,
          endedAtMs: 2000,
          exerciseId: ex.id,
          reps: 5,
          weight: 70.0,
        );

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: ex.id,
            name: ex.name,
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 70.0,
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
            executionOrder: 0,
          ),
        ]);

        expect(prs, isEmpty);
      });

      test('skips exercises with null or zero bestWeight', () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        final prs = await service.computePRs([
          ExerciseSummary(
            exerciseId: 'ex-1',
            name: 'Bodyweight Squat',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: 0.0,
            executionOrder: 0,
          ),
          ExerciseSummary(
            exerciseId: 'ex-2',
            name: 'Pull-up',
            effortKind: 'set',
            setsCompleted: 3,
            bestWeight: null,
            executionOrder: 1,
          ),
        ]);

        expect(prs, isEmpty);
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

          final session = TrainingSession(
            id: 'session-rest',
            ownerUserId: 'u-1',
            startedAtMs: 1000,
            endedAtMs: 4000,
            createdAtMs: 1000,
            updatedAtMs: 4000,
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
        'buildGroupMetrics counts timed entries as rounds for cardio',
        () async {
          final repo = await _freshRepo();
          final service = SessionSummaryService(repo);

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
        },
      );
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
}
