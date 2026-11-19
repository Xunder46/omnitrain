// Plan 257 P2 — Finish drops the intervals, holds and rounds nobody started.
//
// At Finish every `timed`, `drill` and `round` entry whose timer state is
// `notStarted` goes through the manager's own delete (the same re-indexing
// and rest re-key the logger's delete does), a running or paused entry is
// not dropped, an exercise left with no entry is removed unless the watch
// took part in the workout, and the set drop of plan 157a is untouched.
//
// Scenarios S-25701..S-25709 of
// `docs/plans/2026-11-19-257-finish-drops-never-started-timers-plan/2026-11-19-257-finish-drops-never-started-timers-plan.md`.
// Both stores must end identical (S-25708 is Mock only: it needs a throwing
// repository subclass).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final make in harnessFactories) {
    final harness = make();

    group('${harness.name} — endSession drops never-started timers', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A live (open) session, so the efforts can be added the way a real
      /// workout starts. `seedSession` writes an ended session, which
      /// `endSession` refuses to touch.
      Future<void> openLiveSession() async {
        state = WorkoutState(repo);
        await state.createNewSession();
      }

      Future<String> seedAndAdd(
        String id,
        String name, {
        String? effortKindOverride,
      }) async {
        await seedExercise(repo, id: id, name: name, capabilities: ['load']);
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == id,
        );
        return state.addExerciseToSession(
          exercise,
          effortKindOverride: effortKindOverride,
        );
      }

      /// Runs the entry at [i] to its end the way the logger does.
      Future<void> runFinished(String effortId, int i) async {
        await state.startTimedEntry(effortId, i);
        await state.finishTimedEntry(effortId, i);
      }

      String segmentId() => state.segments.first.id;

      /// [effortId]'s timed instances as the store holds them after Finish.
      Future<List<TimedInstance>> storedTimed(String effortId) async =>
          (await repo.getTimedInstancesByEffort())[effortId] ?? const [];

      /// [effortId]'s round instances as the store holds them after Finish.
      Future<List<RoundInstance>> storedRounds(String effortId) async =>
          (await repo.getRoundInstancesByEffort())[effortId] ?? const [];

      Future<List<int>> repoRestIndexes(String effortId) async => [
        for (final rest in await repo.getEntryRests(effortId)) rest.entryIndex,
      ];

      test('S-25701 Finish keeps the finished interval and drops the two '
          'never-started ones', () async {
        await openLiveSession();
        final effortId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await runFinished(effortId, 1);

        await state.endSession();

        final timed = await storedTimed(effortId);
        expect(timed, hasLength(1), reason: 'the never-started ones are gone');
        expect(timed.single.state, TimedState.finished);
        expect(timed.single.entryIndex, 0);
        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          contains(effortId),
        );
      });

      test('S-25702 Finish removes a hold exercise whose two entries were '
          'never started and keeps the set exercise', () async {
        await openLiveSession();
        final holdId = await seedAndAdd(
          'ex-plank',
          'Plank Hold',
          effortKindOverride: 'drill',
        );
        await state.addEntry(holdId);
        final setId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.updateEntryValue(setId, 0, 'reps', 3);
        await state.updateEntryValue(setId, 0, 'weight', 100.0);
        await state.recordRestStart(setId, 1);

        await state.endSession();

        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id).toList(),
          [setId],
          reason: 'the hold exercise with no entry goes, the set one stays',
        );
        expect(await storedTimed(holdId), isEmpty);
      });

      test('S-25703 Finish keeps the finished round and drops the two '
          'never-started ones', () async {
        await openLiveSession();
        final roundId = await seedAndAdd(
          'ex-bag',
          'Heavy Bag',
          effortKindOverride: 'round',
        );
        await state.addEntry(roundId);
        await state.addEntry(roundId);
        await state.startRound(roundId, 0);
        await state.completeRound(roundId, 0);

        await state.endSession();

        final rounds = await storedRounds(roundId);
        expect(rounds, hasLength(1), reason: 'the never-started rounds go');
        expect(rounds.single.state, RoundState.finished);
        expect(rounds.single.roundIndex, 0);
        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          contains(roundId),
        );
      });

      test(
        'S-25704 Finish re-keys the rests with the dropped interval',
        () async {
          await openLiveSession();
          final effortId = await seedAndAdd(
            'ex-run',
            'Easy Run',
            effortKindOverride: 'timed',
          );
          await state.addEntry(effortId);
          await state.addEntry(effortId);
          await runFinished(effortId, 0);
          await state.recordRestStart(effortId, 1);
          await runFinished(effortId, 2);
          await state.recordRestStart(effortId, 3);

          await state.endSession();

          final timed = await storedTimed(effortId);
          expect(timed, hasLength(2));
          expect(timed.map((t) => t.entryIndex), [0, 1]);
          expect(timed.map((t) => t.state), everyElement(TimedState.finished));
          expect(
            await repoRestIndexes(effortId),
            [1, 2],
            reason:
                'the rest that marked the dropped entry is gone, the later one '
                'moved down',
          );
        },
      );

      test('S-25705 Finish keeps the running interval and drops the '
          'never-started one', () async {
        await openLiveSession();
        final effortId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );
        await state.addEntry(effortId);
        await state.startTimedEntry(effortId, 0);

        await state.endSession();

        final timed = await storedTimed(effortId);
        expect(timed, hasLength(1), reason: 'the running entry is not dropped');
        expect(timed.single.state, isNot(TimedState.notStarted));
        expect(timed.single.startedAtMs, isNotNull);
        expect(timed.single.entryIndex, 0);
      });

      test('S-25706 a workout the watch took part in keeps a hold exercise '
          'whose only entry was never started', () async {
        state = WorkoutState(repo, wristRunsSession: (_) => true);
        await state.createNewSession();
        final holdId = await seedAndAdd(
          'ex-plank',
          'Plank Hold',
          effortKindOverride: 'drill',
        );

        await state.endSession();

        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          contains(holdId),
          reason: 'the exercise stays for a late wrist set (keepEfforts)',
        );
        expect(await storedTimed(holdId), isEmpty, reason: 'its entry went');
      });

      test('S-25707 a workout holding only a never-started interval would '
          'save nothing and keeps no effort', () async {
        await openLiveSession();
        final effortId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );

        expect(await state.finishWouldSaveNothing(), isTrue);

        await state.endSession();

        expect(await repo.getSegmentEfforts(segmentId()), isEmpty);
        expect(await storedTimed(effortId), isEmpty);
      });

      test('S-25709 Finish still drops the unlogged set and keeps the logged '
          'one (plan 157a)', () async {
        await openLiveSession();
        final effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.updateEntryValue(effortId, 0, 'reps', 5);
        await state.updateEntryValue(effortId, 0, 'weight', 50.0);
        await state.updateEntryValue(effortId, 1, 'reps', 7);
        await state.updateEntryValue(effortId, 1, 'weight', 70.0);
        await state.recordRestStart(effortId, 1);

        await state.endSession();

        final sets = [
          for (final group in EntryRows.setGroups(
            await repo.getEffortObservations(effortId),
          ))
            group.entry,
        ];
        expect(
          sets,
          hasLength(1),
          reason: 'the unlogged set goes, the logged one stays',
        );
        expect(sets.single['reps'], 5);
        expect(sets.single['weight'], 50.0);
        expect(await repoRestIndexes(effortId), [1]);
      });

      test(
        'S-25710 Finish re-keys the rests with a dropped round',
        () async {
          await openLiveSession();
          final effortId = await seedAndAdd(
            'ex-bag',
            'Heavy Bag',
            effortKindOverride: 'round',
          );
          await state.addEntry(effortId);
          await state.addEntry(effortId);
          await state.addEntry(effortId);
          await state.addEntry(effortId);
          await state.startRound(effortId, 0);
          await state.completeRound(effortId, 0);
          await state.recordRestStart(effortId, 1);
          await state.startRound(effortId, 2);
          await state.completeRound(effortId, 2);
          await state.recordRestStart(effortId, 3);

          await state.endSession();

          final rounds = await storedRounds(effortId);
          expect(rounds, hasLength(2));
          expect(rounds.map((r) => r.roundIndex), [0, 1]);
          expect(rounds.map((r) => r.state), everyElement(RoundState.finished));
          expect(
            await repoRestIndexes(effortId),
            [1, 2],
            reason:
                'the rest that marked the dropped round is gone, the later one '
                'moved down',
          );
        },
      );
    });
  }

  group('Mock — a failing timer drop never blocks Finish', () {
    test(
      'S-25708 Finish still ends the session when the timer drop throws',
      () async {
        final repo = _ThrowingTimedDelete();
        await repo.initialize();
        final state = WorkoutState(repo);
        await state.createNewSession();
        await seedExercise(
          repo,
          id: 'ex-run',
          name: 'Easy Run',
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == 'ex-run',
        );
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        await state.addEntry(effortId);
        await state.startTimedEntry(effortId, 0);
        await state.finishTimedEntry(effortId, 0);
        final sessionId = state.currentSession!.id;

        await state.endSession();

        expect((await repo.getSession(sessionId))!.endedAtMs, isNotNull);
        expect(state.error, isNull);
        // The throwing delete really ran: the never-started entry is still
        // there (a failing drop leaves the placeholder where it is, D-10).
        expect((await repo.getTimedInstances(effortId)).length, 2);
      },
    );
  });
}

class _ThrowingTimedDelete extends MockWorkoutRepository {
  @override
  Future<void> deleteTimedInstance(String id) async {
    throw StateError('boom');
  }
}
