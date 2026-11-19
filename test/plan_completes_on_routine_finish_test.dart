// Plan 251 P2 — the tests for "finishing a routine completes its plan"
// (S-25101..S-25108).
//
// When a workout started from a routine is finished (Finish stores the end),
// the app marks the unstarted plan for the SAME routine on the day the workout
// STARTED completed and linked to that workout, exactly like the day-list path
// does. Plain `test()`: every scenario runs on Mock AND Hive through
// `harnessFactories`.
//
// Plan: `docs/plans/2026-11-19-251-plan-completes-on-routine-finish-plan/2026-11-19-251-plan-completes-on-routine-finish-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

final _today = DateTime(2026, 11, 18);
final _nov17 = DateTime(2026, 11, 17);
final _nov19 = DateTime(2026, 11, 19);

Future<void> seedRoutines(WorkoutRepository repo) async {
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-push',
      name: 'Push',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
  );
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-pull',
      name: 'Pull',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
  );
}

Future<void> seedPlan(
  WorkoutRepository repo, {
  required String id,
  String? routineId,
  String? modality,
  required DateTime day,
  int createdAtMs = 1000,
  bool completed = false,
  String? linkedSessionId,
}) => repo.createPlannedSession(
  PlannedSession(
    id: id,
    ownerUserId: 'user-1',
    scheduledDateMs: OmniDateUtils.startOfDayMs(day),
    modality: modality,
    routineTemplateId: routineId,
    isCompleted: completed,
    linkedSessionId: linkedSessionId,
    createdAtMs: createdAtMs,
    updatedAtMs: createdAtMs,
  ),
);

Future<PlannedSession?> planById(WorkoutRepository repo, String id) async {
  for (final plan in await repo.getPlannedSessions()) {
    if (plan.id == id) return plan;
  }
  return null;
}

/// The calendar wired to the repository and a `WorkoutState` whose clock is
/// the test's own closure; Finish tells the calendar through
/// `onSessionEnded`. Starts the session and returns the state and its id;
/// the test ends it with `endSession(writeToHealth: false)`.
Future<(WorkoutState, String)> startWorkout(
  WorkoutRepository repo,
  CalendarState calendar,
  DateTime Function() clock, {
  String? routineTemplateId = 'tpl-push',
  Future<void> Function(TrainingSession session)? onSessionEnded,
}) async {
  final state = WorkoutState(
    repo,
    clock: clock,
    onSessionEnded: onSessionEnded ?? calendar.completePlanFor,
  );
  await state.createNewSession(
    modality: Modality.resistanceLifting,
    routineTemplateId: routineTemplateId,
    intent: routineTemplateId == null ? null : 'routine',
    includeDefaultSegment: false,
  );
  final sessionId = state.currentSession!.id;
  return (state, sessionId);
}

Future<void> finish(WorkoutState state) =>
    state.endSession(writeToHealth: false);

/// The workout the day-list path never saw: started and finished in one go.
Future<(WorkoutState, String)> runWorkout(
  WorkoutRepository repo,
  CalendarState calendar,
  DateTime Function() clock, {
  String? routineTemplateId = 'tpl-push',
  Future<void> Function(TrainingSession session)? onSessionEnded,
}) async {
  final (state, sessionId) = await startWorkout(
    repo,
    calendar,
    clock,
    routineTemplateId: routineTemplateId,
    onSessionEnded: onSessionEnded,
  );
  await finish(state);
  return (state, sessionId);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: finishing a routine completes its plan', () {
      late RepositoryHarness harness;
      setUp(() => harness = make());
      tearDown(() => harness.close());

      test('S-25101 finishing the routine workout completes its unstarted '
          'plan for today and links it', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(repo, id: 'p1', routineId: 'tpl-push', day: _today);
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        final (state, sessionId) = await runWorkout(repo, calendar, () => now);

        final p1 = (await planById(repo, 'p1'))!;
        expect(p1.isCompleted, isTrue);
        expect(p1.linkedSessionId, sessionId);
        expect(sessionId, isNotNull);
      });

      test('S-25102 plans for other days are untouched', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(repo, id: 'p-y', routineId: 'tpl-push', day: _nov17);
        await seedPlan(repo, id: 'p-t', routineId: 'tpl-push', day: _nov19);
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        await runWorkout(repo, calendar, () => now);

        final yesterday = (await planById(repo, 'p-y'))!;
        final tomorrow = (await planById(repo, 'p-t'))!;
        expect(yesterday.isCompleted, isFalse);
        expect(yesterday.linkedSessionId, isNull);
        expect(tomorrow.isCompleted, isFalse);
        expect(tomorrow.linkedSessionId, isNull);
      });

      test('S-25103 another routine plan and a free plan stay untouched, '
          'also after a workout with no routine', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(repo, id: 'p-pull', routineId: 'tpl-pull', day: _today);
        await seedPlan(
          repo,
          id: 'p-free',
          modality: 'resistance_lifting',
          day: _today,
        );
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        final (first, _) = await startWorkout(
          repo,
          calendar,
          () => now,
          routineTemplateId: 'tpl-push',
        );
        await finish(first);

        var pPull = (await planById(repo, 'p-pull'))!;
        var pFree = (await planById(repo, 'p-free'))!;
        expect(pPull.isCompleted, isFalse);
        expect(pPull.linkedSessionId, isNull);
        expect(pFree.isCompleted, isFalse);
        expect(pFree.linkedSessionId, isNull);

        // A free session (no routine) completes nothing.
        final (second, _) = await runWorkout(
          repo,
          calendar,
          () => now,
          routineTemplateId: null,
        );
        expect(second.currentSession!.routineTemplateId, isNull);

        pPull = (await planById(repo, 'p-pull'))!;
        pFree = (await planById(repo, 'p-free'))!;
        expect(pPull.isCompleted, isFalse);
        expect(pPull.linkedSessionId, isNull);
        expect(pFree.isCompleted, isFalse);
        expect(pFree.linkedSessionId, isNull);
      });

      test('S-25104 an already completed plan is never taken again', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(
          repo,
          id: 'p-done',
          routineId: 'tpl-push',
          day: _today,
          completed: true,
          linkedSessionId: 's-old',
        );
        await seedPlan(
          repo,
          id: 'p2',
          routineId: 'tpl-push',
          day: _today,
          createdAtMs: 2000,
        );
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        final (_, sessionId) = await runWorkout(repo, calendar, () => now);

        final done = (await planById(repo, 'p-done'))!;
        final p2 = (await planById(repo, 'p2'))!;
        expect(p2.isCompleted, isTrue);
        expect(p2.linkedSessionId, sessionId);
        expect(done.linkedSessionId, 's-old');
        expect(done.isCompleted, isTrue);
      });

      test('S-25105 two unstarted plans for the routine today: the one '
          'created first is linked', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        // B written first; A carries the earlier createdAtMs.
        await seedPlan(
          repo,
          id: 'b',
          routineId: 'tpl-push',
          day: _today,
          createdAtMs: 2000,
        );
        await seedPlan(
          repo,
          id: 'a',
          routineId: 'tpl-push',
          day: _today,
          createdAtMs: 1000,
        );
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        final (_, sessionId) = await runWorkout(repo, calendar, () => now);

        final a = (await planById(repo, 'a'))!;
        final b = (await planById(repo, 'b'))!;
        expect(a.linkedSessionId, sessionId);
        expect(a.isCompleted, isTrue);
        expect(b.isCompleted, isFalse);
        expect(b.linkedSessionId, isNull);
      });

      test(
        'S-25106 a second endSession writes the plan nothing more',
        () async {
          final repo = await harness.open();
          await seedRoutines(repo);
          await seedPlan(repo, id: 'p1', routineId: 'tpl-push', day: _today);
          final calendar = CalendarState(repo);
          await calendar.init();

          var now = DateTime(2026, 11, 18, 10);
          final (state, sessionId) = await startWorkout(
            repo,
            calendar,
            () => now,
          );
          await finish(state);

          final first = (await planById(repo, 'p1'))!;
          expect(first.isCompleted, isTrue);
          expect(first.linkedSessionId, sessionId);
          final updatedAtAfterFirst = first.updatedAtMs;

          await finish(state);

          final second = (await planById(repo, 'p1'))!;
          expect(second.isCompleted, isTrue);
          expect(second.linkedSessionId, sessionId);
          expect(second.updatedAtMs, updatedAtAfterFirst);
        },
      );

      test(
        'S-25107 a failing plan completion never fails the Finish',
        () async {
          final repo = await harness.open();
          await seedRoutines(repo);
          await seedPlan(repo, id: 'p1', routineId: 'tpl-push', day: _today);
          final calendar = CalendarState(repo);
          await calendar.init();

          var now = DateTime(2026, 11, 18, 10);
          final (state, sessionId) = await startWorkout(
            repo,
            calendar,
            () => now,
            onSessionEnded: (_) async => throw StateError('boom'),
          );
          await finish(state);

          final stored = (await repo.getSession(sessionId))!;
          expect(stored.endedAtMs, isNotNull);
          expect(state.error, isNull);
          final p1 = (await planById(repo, 'p1'))!;
          expect(p1.isCompleted, isFalse);
          expect(p1.linkedSessionId, isNull);
        },
      );

      test('S-25108 a workout started 23:50 and ended 00:20 completes the '
          'plan of the day it started', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(
          repo,
          id: 'p-d1',
          routineId: 'tpl-push',
          day: DateTime(2026, 11, 18),
        );
        await seedPlan(
          repo,
          id: 'p-d2',
          routineId: 'tpl-push',
          day: DateTime(2026, 11, 19),
        );
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 23, 50);
        final (state, sessionId) = await startWorkout(
          repo,
          calendar,
          () => now,
        );
        now = DateTime(2026, 11, 19, 0, 20);
        await finish(state);

        expect(state.currentSession!.startedAtMs, isNotNull);
        final d1 = (await planById(repo, 'p-d1'))!;
        final d2 = (await planById(repo, 'p-d2'))!;
        expect(d1.isCompleted, isTrue);
        expect(d1.linkedSessionId, sessionId);
        expect(d2.isCompleted, isFalse);
        expect(d2.linkedSessionId, isNull);
      });

      test('S-25109 an unstarted plan already linked elsewhere is never '
          'taken again', () async {
        final repo = await harness.open();
        await seedRoutines(repo);
        await seedPlan(
          repo,
          id: 'p-linked-only',
          routineId: 'tpl-push',
          day: _today,
          linkedSessionId: 's-old',
        );
        await seedPlan(
          repo,
          id: 'p2',
          routineId: 'tpl-push',
          day: _today,
          createdAtMs: 2000,
        );
        final calendar = CalendarState(repo);
        await calendar.init();

        var now = DateTime(2026, 11, 18, 10);
        final (_, sessionId) = await runWorkout(repo, calendar, () => now);

        final linkedOnly = (await planById(repo, 'p-linked-only'))!;
        final p2 = (await planById(repo, 'p2'))!;
        expect(p2.isCompleted, isTrue);
        expect(p2.linkedSessionId, sessionId);
        expect(linkedOnly.isCompleted, isFalse);
        expect(linkedOnly.linkedSessionId, 's-old');
      });

      test(
        'S-25110 a completed plan with no link is never taken again',
        () async {
          final repo = await harness.open();
          await seedRoutines(repo);
          await seedPlan(
            repo,
            id: 'p-done-no-link',
            routineId: 'tpl-push',
            day: _today,
            createdAtMs: 500,
            completed: true,
          );
          await seedPlan(
            repo,
            id: 'p2',
            routineId: 'tpl-push',
            day: _today,
            createdAtMs: 2000,
          );
          final calendar = CalendarState(repo);
          await calendar.init();

          var now = DateTime(2026, 11, 18, 10);
          final (_, sessionId) = await runWorkout(repo, calendar, () => now);

          final doneNoLink = (await planById(repo, 'p-done-no-link'))!;
          final p2 = (await planById(repo, 'p2'))!;
          expect(p2.isCompleted, isTrue);
          expect(p2.linkedSessionId, sessionId);
          expect(doneNoLink.linkedSessionId, isNull);
        },
      );

      test(
        'S-25111 a workout a plan is already linked to changes nothing',
        () async {
          final repo = await harness.open();
          await seedRoutines(repo);
          final calendar = CalendarState(repo);
          await calendar.init();

          var now = DateTime(2026, 11, 18, 10);
          final (state, sessionId) = await startWorkout(
            repo,
            calendar,
            () => now,
          );
          // A path linked the plan to the session while it was running.
          await seedPlan(
            repo,
            id: 'p-linked',
            routineId: 'tpl-push',
            day: _today,
            completed: true,
            linkedSessionId: sessionId,
          );
          await seedPlan(
            repo,
            id: 'p-other',
            routineId: 'tpl-push',
            day: _today,
            createdAtMs: 2000,
          );
          await finish(state);

          final other = (await planById(repo, 'p-other'))!;
          final linked = (await planById(repo, 'p-linked'))!;
          expect(other.isCompleted, isFalse);
          expect(other.linkedSessionId, isNull);
          expect(linked.isCompleted, isTrue);
          expect(linked.linkedSessionId, sessionId);
        },
      );
    });
  }
}
