// Plan 157a P1 — Finish keeps only the sets that were logged.
//
// A `set` entry is logged exactly when an `EntryRest` sits at its position
// + 1 (the session screen's `_isSetLogged`). At Finish every `set` entry no
// rest marks logged goes, a skip-marked one stays, a set exercise left with
// no entry is removed, timed and round efforts are untouched, and an
// edit-mode Save over an already-ended session drops nothing.
//
// Scenarios S-15701..S-15708 of
// `docs/plans/2026-11-13-157a-stats-unlogged-sets-plan/2026-11-13-157a-stats-unlogged-sets-plan.md`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — endSession drops unlogged sets', () {
      late WorkoutRepository repo;
      late WorkoutState state;
      late String effortId;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A live (open) session with [id]/'name' seeded, so the effort can be
      /// added the way a real workout starts. `seedSession` writes an ended
      /// session, which `endSession` refuses to touch.
      Future<void> openLiveSession() async {
        state = WorkoutState(repo);
        await state.createNewSession();
      }

      Future<String> seedAndAdd(
        String id,
        String name, {
        String? effortKindOverride,
      }) async {
        await seedExercise(
          repo,
          id: id,
          name: name,
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == id,
        );
        return state.addExerciseToSession(
          exercise,
          effortKindOverride: effortKindOverride,
        );
      }

      /// Fills the set at [i] with [reps] x [weight], the values the user
      /// typed into the logger.
      Future<void> fillSet(int i, {required int reps, required double weight}) async {
        await state.updateEntryValue(effortId, i, 'reps', reps);
        await state.updateEntryValue(effortId, i, 'weight', weight);
      }

      /// LOGS the set at [i] the way the screen does: a rest at position + 1.
      Future<void> logSet(int i) => state.recordRestStart(effortId, i + 1);

      /// The effort's set entries as the store holds them.
      Future<List<Map<String, dynamic>>> storedSets() async => [
        for (final group in EntryRows.setGroups(
          await repo.getEffortObservations(effortId),
        ))
          group.entry,
      ];

      Future<List<int>> repoRestIndexes() async => [
        for (final rest in await repo.getEntryRests(effortId)) rest.entryIndex,
      ];

      List<int> stateRestIndexes() => [
        for (final rest in state.getEntryRests(effortId)) rest.entryIndex,
      ];

      String segmentId() => state.segments.first.id;

      test('S-15701 Finish keeps the logged set and deletes the two untouched '
          'placeholders', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(1), reason: 'the placeholders are gone');
        expect(sets.single['reps'], 3);
        expect(sets.single['weight'], 100.0);
        expect(await repoRestIndexes(), [1]);
        expect(stateRestIndexes(), [1]);
        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          contains(effortId),
          reason: 'a set exercise with a logged set stays',
        );
      });

      test('S-15702 Finish keeps the logged sets and re-keys the rest above '
          'the dropped middle one', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 5, weight: 50.0);
        await fillSet(2, reps: 7, weight: 70.0);
        await logSet(0);
        await logSet(2);

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(2));
        expect(sets[0]['reps'], 5);
        expect(sets[0]['weight'], 50.0);
        expect(sets[1]['reps'], 7);
        expect(sets[1]['weight'], 70.0);
        expect(
          await repoRestIndexes(),
          [1, 2],
          reason: 'the re-key kept the second set logged',
        );
        expect(stateRestIndexes(), [1, 2]);
      });

      test('S-15703 Finish removes a set exercise left with no entry at all '
          'and keeps the one that was logged', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        final yId = await seedAndAdd('ex-bench', 'Bench Press');
        await state.addEntry(yId);
        await state.addEntry(yId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);

        await state.endSession();

        final efforts = await repo.getSegmentEfforts(segmentId());
        expect(efforts.map((e) => e.id), [effortId]);
        expect(state.getEffortsForSegment(segmentId()).map((e) => e.id), [
          effortId,
        ]);
        expect(
          await repo.getEffortObservations(yId),
          isEmpty,
          reason: 'Y holds no set any more',
        );
      });

      test('S-15704 Finish keeps the logged set and the skip-marked one, and '
          'drops the untouched one', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        await state.markSetSkipped(effortId, 1);

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(2));
        expect(sets[0]['reps'], 3);
        expect(sets[0]['weight'], 100.0);
        expect(sets[1]['skipped'], isTrue);
        expect(await repoRestIndexes(), [1]);
      });

      test('S-15705 an edit-mode Save over an ended session drops nothing', () async {
        await seedSession(repo, sessionId: 's-old');
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Barbell Back Squat',
          capabilities: ['load'],
        );
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-old',
          effortId: 'effort-old',
          exerciseId: 'ex-squat',
          entryCount: 1,
          hasExtraWeight: false,
        );
        await repo.createEntryRest(
          EntryRest(
            id: 'rest-effort-old-1',
            effortId: 'effort-old',
            entryIndex: 1,
            restStartMs: fixtureStart + 1000,
            restEndMs: fixtureStart + 1100,
            createdAtMs: fixtureStart + 1000,
            updatedAtMs: fixtureStart + 1000,
          ),
        );
        state = await loadState(repo, 's-old');
        effortId = 'effort-old';
        await state.addEntry(effortId);
        await state.updateEntryValue(effortId, 1, 'reps', 8);
        await state.updateEntryValue(effortId, 1, 'weight', 40.0);

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(2));
        expect(sets[1]['reps'], 8);
        expect(sets[1]['weight'], 40.0);
      });

      test('S-15706 the wrist\'s own end keeps the planned sets and stores '
          'that instant', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        final atMs = state.currentSession!.startedAtMs + 600000;

        await state.endSession(writeToHealth: false, atMs: atMs);

        final sets = await storedSets();
        expect(sets, hasLength(3), reason: 'the wrist sets still on their way');
        expect(sets.first['reps'], 3);
        expect(sets.first['weight'], 100.0);
        expect(await repoRestIndexes(), [1]);
        expect(state.currentSession!.endedAtMs, atMs);
      });

      test('S-15712 a session with a staged wrist row keeps its planned sets',
          () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        await repo.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: 'e-late',
            watchSessionId: state.currentSession!.id,
            kind: WatchInboxEntry.kindSet,
            origin: WatchInboxEntry.originWatch,
            payload: {
              'eventId': 'e-late',
              'entryId': 'e-late',
              'kind': 'set',
              'reps': 5,
              'loadKg': 60,
            },
            receivedAtMs: fixtureStart,
          ),
        );

        await state.endSession();

        expect(await storedSets(), hasLength(3), reason: 'D-11');
      });

      test('S-15712b a staged phone annotation alone does not stop the drop',
          () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        await repo.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: WatchInboxEntry.phoneRatingId(state.currentSession!.id),
            watchSessionId: state.currentSession!.id,
            kind: WatchInboxEntry.kindPhoneRating,
            origin: WatchInboxEntry.originPhone,
            payload: {'rating': 3},
            receivedAtMs: fixtureStart,
          ),
        );

        await state.endSession();

        expect(await storedSets(), hasLength(1));
      });

      test('S-15713 a session the wrist runs keeps its planned sets', () async {
        state = WorkoutState(repo, wristRunsSession: (_) => true);
        await state.createNewSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);

        await state.endSession();

        expect(await storedSets(), hasLength(3), reason: 'D-11');
      });

      test('S-15707 Finish leaves timed and round efforts with their entries '
          'alone', () async {
        await openLiveSession();
        final timedId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );
        final roundId = await seedAndAdd(
          'ex-bag',
          'Heavy Bag',
          effortKindOverride: 'round',
        );
        final timedBefore = (await repo.getTimedInstances(timedId)).length;
        final roundBefore = (await repo.getRoundInstances(roundId)).length;

        await state.endSession();

        final efforts = await repo.getSegmentEfforts(segmentId());
        expect(efforts.map((e) => e.id), containsAll([timedId, roundId]));
        expect(
          (await repo.getTimedInstances(timedId)).length,
          timedBefore,
          reason: 'the never-started interval is untouched',
        );
        expect(
          (await repo.getRoundInstances(roundId)).length,
          roundBefore,
          reason: 'the not-started round is untouched',
        );
      });

      test('S-15708 the summary and the all-time best read only the logged '
          'set after Finish', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        await state.addEntry(
          effortId,
          previousValues: {'reps': 10, 'weight': 100.0},
        );

        final before = state.computeSessionSummary();
        expect(before.totalSets, 2, reason: 'the bug this change fixes');
        expect(before.totalVolume, closeTo(1300.0, 1e-9));

        await state.endSession();

        final after = state.computeSessionSummary();
        expect(after.totalSets, 1);
        expect(after.totalVolume, closeTo(300.0, 1e-9));
        final squat = after.exercises.firstWhere(
          (e) => e.exerciseId == 'ex-squat',
        );
        expect(squat.setsCompleted, 1);
        expect(squat.bestE1RM, closeTo(110.0, 1e-9));
        expect(
          await StatsProgressService(repo).getAllTimeBestE1RM('ex-squat'),
          closeTo(110.0, 1e-9),
        );
      });

      test('S-15710 Finish reads the rests from the store, not the cache', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        // The importer's route: the rest lands straight in the repository,
        // and no state call here refreshes the rest cache first.
        await repo.createEntryRest(
          EntryRest(
            id: 'rest-$effortId-1',
            effortId: effortId,
            entryIndex: 1,
            restStartMs: fixtureStart + 1000,
            restEndMs: fixtureStart + 1100,
            createdAtMs: fixtureStart + 1000,
            updatedAtMs: fixtureStart + 1000,
          ),
        );

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(1), reason: 'the rest was read from the store');
        expect(sets.single['reps'], 3);
        expect(sets.single['weight'], 100.0);
      });

      test('S-15714 two untouched sets below a logged one keep the logged '
          'set\'s rest', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(2, reps: 7, weight: 70.0);
        await logSet(2);

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(1), reason: 'the two placeholders are gone');
        expect(sets.single['reps'], 7);
        expect(sets.single['weight'], 70.0);
        expect(
          await repoRestIndexes(),
          [1],
          reason: 'the logged set kept its rest where it sits',
        );
        expect(stateRestIndexes(), [1]);
      });

      test('S-15715 a set exercise that holds no entry at all is left alone',
          () async {
        await openLiveSession();
        final xId = effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        final eId = await seedAndAdd('ex-bench', 'Bench Press');
        await state.deleteEntry(eId, 0);
        expect(
          await repo.getEffortObservations(eId),
          isEmpty,
          reason: 'the precondition: E holds no entry',
        );

        await state.endSession();

        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          containsAll([xId, eId]),
          reason: 'an effort with no entry is not an effort with dropped sets',
        );
        expect(
          state.getEffortsForSegment(segmentId()).map((e) => e.id),
          containsAll([xId, eId]),
        );
      });

      test('S-15716 a set that only the store holds is judged by the store',
          () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        // Straight to the repository, bypassing the state: the store's view
        // must judge it, not the session's cache.
        for (final row in LoggedEntryRows.setObservations(
          effortId: effortId,
          entryIndex: 1,
          reps: 10,
          weightKg: 100.0,
          exerciseHasLoad: true,
          atMs: fixtureStart,
        )) {
          await repo.createObservation(row);
        }

        await state.endSession();

        final sets = await storedSets();
        expect(
          sets,
          hasLength(1),
          reason: 'the store-only set is unlogged there and goes',
        );
        expect(sets.single['reps'], 3);
        expect(sets.single['weight'], 100.0);
      });

      test('S-15717 a removed exercise leaves no rest in the session\'s cache',
          () async {
        await openLiveSession();
        final xId = effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        final yId = await seedAndAdd('ex-bench', 'Bench Press');
        await state.addEntry(yId);
        await state.recordRestStart(yId, 0);

        await state.endSession();

        expect(state.getEntryRests(yId), isEmpty, reason: 'the cache is clean');
        expect(await repo.getEntryRests(yId), isEmpty);
        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          [xId],
          reason: 'Y went, and its rest went with it',
        );
      });
    });
  }

  group('Mock — a failing drop never blocks Finish', () {
    test('S-15711 Finish still ends the session when the drop throws', () async {
      final repo = _ThrowingDeleteRepository();
      await repo.initialize();
      final state = WorkoutState(repo);
      await state.createNewSession();
      await seedExercise(
        repo,
        id: 'ex-squat',
        name: 'Barbell Back Squat',
        capabilities: ['load'],
      );
      final exercise = (await repo.getExercises()).firstWhere(
        (e) => e.id == 'ex-squat',
      );
      final effortId = await state.addExerciseToSession(exercise);
      await state.addEntry(effortId);
      await state.recordRestStart(effortId, 1);

      await state.endSession();

      expect(state.currentSession!.endedAtMs, isNotNull);
      expect(state.error, isNull);
      expect(
        EntryRows.setGroups(await repo.getEffortObservations(effortId)),
        hasLength(2),
        reason: 'the placeholder stays where the drop left off',
      );
    });
  });
}

class _ThrowingDeleteRepository extends MockWorkoutRepository {
  @override
  Future<void> deleteObservation(String id) async {
    throw StateError('boom');
  }
}
