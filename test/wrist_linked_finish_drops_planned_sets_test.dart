// Plan 218 P1 — a workout the watch took part in drops its planned sets at
// the end.
//
// The same rule as plan 157a, with one difference: the drop never removes an
// exercise (a late wrist set for a removed exercise would be lost), and in
// the production wiring it waits behind the inbox's queued import passes.
//
// Scenarios S-21801..S-21803 of
// `docs/plans/2026-11-16-218-wrist-linked-workouts-drop-planned-sets-plan/2026-11-16-218-wrist-linked-workouts-drop-planned-sets-plan.md`.
// S-21802 (an exercise with only placeholders keeps its effort) lives in the
// rewritten S-15713 of `test/finish_drops_unlogged_sets_test.dart`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — a wrist-linked finish drops the planned sets', () {
      late WorkoutRepository repo;
      late WorkoutState state;
      late String effortId;
      final queueCalls = <String>[];

      setUp(() async {
        repo = await harness.open();
        queueCalls.clear();
      });
      tearDown(() async => await harness.close());

      Future<void> openLiveSession({bool wristRuns = false}) async {
        state = WorkoutState(
          repo,
          wristRunsSession: wristRuns ? (_) => true : null,
          afterPendingWristImports: (action) async {
            queueCalls.add('queued');
            await action();
            queueCalls.add('ran');
          },
        );
        await state.createNewSession();
      }

      Future<String> seedAndAdd(String id, String name) async {
        await seedExercise(repo, id: id, name: name, capabilities: ['load']);
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == id,
        );
        return state.addExerciseToSession(exercise);
      }

      Future<void> fillSet(int i, {required int reps, required double weight}) async {
        await state.updateEntryValue(effortId, i, 'reps', reps);
        await state.updateEntryValue(effortId, i, 'weight', weight);
      }

      Future<void> logSet(int i) => state.recordRestStart(effortId, i + 1);

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

      Future<void> stageWristSetRow() => repo.stageWatchInboxEntry(
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

      test('S-21801 a phone end of a session with a staged wrist row drops '
          'the planned sets and keeps the effort', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);
        await stageWristSetRow();

        await state.endSession();

        final sets = await storedSets();
        expect(sets, hasLength(1), reason: 'the two placeholders are gone');
        expect(sets.single['reps'], 3);
        expect(sets.single['weight'], 100.0);
        expect(await repoRestIndexes(), [1]);
        expect(stateRestIndexes(), [1]);
        expect(
          (await repo.getSegmentEfforts(segmentId())).map((e) => e.id),
          contains(effortId),
          reason: 'the effort stays for the wrist set still on its way',
        );
      });

      test('S-21803 the wrist\'s own end drops the planned sets, re-keys the '
          'rests and stores that instant', () async {
        await openLiveSession();
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 5, weight: 50.0);
        await fillSet(2, reps: 7, weight: 70.0);
        await logSet(0);
        await logSet(2);
        final atMs = state.currentSession!.startedAtMs + 600000;

        await state.endSession(writeToHealth: false, atMs: atMs);

        final sets = await storedSets();
        expect(sets, hasLength(2), reason: 'the middle placeholder is gone');
        expect(sets[0]['reps'], 5);
        expect(sets[0]['weight'], 50.0);
        expect(sets[1]['reps'], 7);
        expect(sets[1]['weight'], 70.0);
        expect(
          await repoRestIndexes(),
          [1, 2],
          reason: 'the re-key kept the second set logged (like S-15702)',
        );
        expect(stateRestIndexes(), [1, 2]);
        expect(state.currentSession!.endedAtMs, atMs);
      });

      test('S-21801b the drop waits for the queue, and the phone-only case '
          'never calls the queue', () async {
        await openLiveSession(wristRuns: true);
        effortId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);

        await state.endSession();

        expect(queueCalls, ['queued', 'ran'], reason: 'the drop ran in it');
        expect(await storedSets(), hasLength(1));

        // The phone-only case: no staged wrist row, no wrist running the
        // session — the queue is never consulted.
        queueCalls.clear();
        await openLiveSession(wristRuns: false);
        effortId = await seedAndAdd('ex-bench', 'Bench Press');
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await fillSet(0, reps: 3, weight: 100.0);
        await logSet(0);

        await state.endSession();

        expect(queueCalls, isEmpty, reason: 'the drop ran directly');
        expect(await storedSets(), hasLength(1));
      });
    });
  }
}
