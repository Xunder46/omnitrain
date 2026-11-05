// Plan 38f P1 — a deleted entry takes its rest with it.
//
// A `set` entry counts as logged exactly when an `EntryRest` sits at its index
// + 1, so deleting the set has to remove that rest and move every rest above it
// down with the rows that stayed (D-1). The same rule holds for `timed` and
// `round` efforts, and an edit-mode delete that is cancelled must put the rests
// back (D-9).
//
// Scenarios S-4301..S-4304 and S-4318 of
// `docs/plans/2026-10-15-38f-logger-polish-plan/2026-10-15-38f-logger-polish-plan.md`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — deleteEntry takes the rest with the entry', () {
      late WorkoutRepository repo;
      late WorkoutState state;
      late String effortId;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A session holding one barbell-squat effort of [kind] with [sets]
      /// entries, opened the way the edit screens open a stored session.
      Future<String> seedEffort({String kind = 'set', int sets = 3}) async {
        await seedSession(repo, sessionId: 's-rests');
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Barbell Back Squat',
          capabilities: ['load'],
        );
        state = await loadState(repo, 's-rests');
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == 'ex-squat',
        );
        final id = await state.addExerciseToSession(
          exercise,
          effortKindOverride: kind,
        );
        for (var i = 1; i < sets; i++) {
          await state.addEntry(id);
        }
        return id;
      }

      /// Closed rests at [indexes], written straight to the store with the
      /// stamps `index * 1000` ms — the shape a stored session holds.
      Future<void> seedRests(List<int> indexes) async {
        for (final index in indexes) {
          final at = index * 1000;
          await repo.createEntryRest(
            EntryRest(
              id: 'rest-$effortId-$index',
              effortId: effortId,
              entryIndex: index,
              restStartMs: at,
              restEndMs: at + 100,
              createdAtMs: at,
              updatedAtMs: at,
            ),
          );
        }
        await state.loadSessionData();
      }

      List<int> indexesOf(List<EntryRest> rests) => [
        for (final rest in rests) rest.entryIndex,
      ];

      Future<List<int>> repoIndexes() async =>
          indexesOf(await repo.getEntryRests(effortId));

      test('S-4301 deleting the last set takes its rest, so a new set reads '
          'unlogged', () async {
        effortId = await seedEffort();
        await seedRests([1, 2, 3]);

        await state.deleteEntry(effortId, 2);

        expect(await repoIndexes(), [1, 2]);
        expect(indexesOf(state.getEntryRests(effortId)), [1, 2]);

        // The replacement set 3 is a NEW set: no rest covers it.
        await state.addEntry(effortId);
        expect(await repoIndexes(), [1, 2]);
        expect(
          indexesOf(state.getEntryRests(effortId)),
          [1, 2],
          reason: 'the new set 3 is not logged',
        );
      });

      test('S-4302 deleting the first set moves every rest down with the sets '
          'it keeps', () async {
        effortId = await seedEffort();
        await seedRests([1, 2, 3]);

        await state.deleteEntry(effortId, 0);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1, 2]);
        expect(
          [for (final rest in rests) rest.id],
          ['rest-$effortId-1', 'rest-$effortId-2'],
          reason: 'a re-keyed rest carries the id shape the importer writes',
        );
        expect(
          [for (final rest in rests) rest.restStartMs],
          [2000, 3000],
          reason: 'the durations move with the sets they belong to',
        );
        expect([for (final rest in rests) rest.restEndMs], [2100, 3100]);
        expect(indexesOf(state.getEntryRests(effortId)), [1, 2]);
      });

      test('S-4303 deleting a middle set drops its own rest and moves the rest '
          'above it down', () async {
        effortId = await seedEffort();
        await seedRests([1, 2]);

        await state.deleteEntry(effortId, 1);

        expect(await repoIndexes(), [1]);
        expect(
          indexesOf(state.getEntryRests(effortId)),
          [1],
          reason: 'set 1 stays logged, the old set 3 is unlogged',
        );
      });

      test('S-4304 timed: the rest of the deleted interval closes over it', () async {
        effortId = await seedEffort(kind: 'timed', sets: 2);
        await state.recordRestStart(effortId, 1);
        await state.recordRestStart(effortId, 2);
        final before = state.getEntryRests(effortId);

        await state.deleteEntry(effortId, 0);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1]);
        expect(rests.single.id, 'rest-$effortId-1');
        expect(rests.single.restStartMs, before.last.restStartMs);
        expect(
          rests.single.restEndMs,
          before.last.restEndMs,
          reason: 'an open rest stays open and moves down',
        );
        expect(indexesOf(state.getEntryRests(effortId)), [1]);
      });

      test('S-4304 round: the rest of the deleted round closes over it', () async {
        effortId = await seedEffort(kind: 'round', sets: 2);
        await state.recordRestStart(effortId, 1);
        await state.recordRestStart(effortId, 2);
        final before = state.getEntryRests(effortId);

        await state.deleteEntry(effortId, 0);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1]);
        expect(rests.single.id, 'rest-$effortId-1');
        expect(rests.single.restStartMs, before.last.restStartMs);
        expect(rests.single.restEndMs, before.last.restEndMs);
        expect(indexesOf(state.getEntryRests(effortId)), [1]);
      });

      test('S-4318 an edit-mode delete that is cancelled puts the rests back', () async {
        effortId = await seedEffort();
        await seedRests([1, 2, 3]);

        final snapshot = state.snapshotSessionState()!;
        await state.deleteEntry(effortId, 1);
        await state.restoreSessionSnapshot(snapshot);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1, 2, 3]);
        expect(
          [for (final rest in rests) rest.restStartMs],
          [1000, 2000, 3000],
          reason: 'the snapshot stamps come back per set',
        );
        expect(indexesOf(state.getEntryRests(effortId)), [1, 2, 3]);
      });

      test('S-4327 a re-keyed delete leaves the cache sorted by entryIndex', () async {
        effortId = await seedEffort();
        // Rests written out of order, the way a session recorded on the fly and
        // read back through `recordRestStart` can hold them.
        await state.recordRestStart(effortId, 3);
        await state.recordRestStart(effortId, 1);
        await state.recordRestStart(effortId, 2);

        await state.deleteEntry(effortId, 0);

        expect(
          indexesOf(state.getEntryRests(effortId)),
          [1, 2],
          reason: 'the in-memory cache is ordered, not only the store',
        );
      });

      test('S-4328 restoring a snapshot drops rests the snapshot never held', () async {
        effortId = await seedEffort();
        await seedRests([1, 2, 3]);

        final snapshot = state.snapshotSessionState()!;
        // A rest that arrived after the snapshot was taken.
        await state.recordRestStart(effortId, 4);

        await state.restoreSessionSnapshot(snapshot);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1, 2, 3]);
        expect(
          [for (final rest in rests) rest.restStartMs],
          [1000, 2000, 3000],
          reason: 'the snapshot stamps come back per set',
        );
      });

      test('S-4329 restoring brings back the rests of an exercise removed while '
          'editing', () async {
        effortId = await seedEffort();
        await seedRests([1, 2, 3]);

        final snapshot = state.snapshotSessionState()!;
        await state.removeExerciseFromSession(effortId);
        expect(
          await repoIndexes(),
          isEmpty,
          reason: 'the removed exercise takes its rests with it',
        );

        await state.restoreSessionSnapshot(snapshot);

        final rests = await repo.getEntryRests(effortId);
        expect(indexesOf(rests), [1, 2, 3]);
        expect(
          [for (final rest in rests) rest.restStartMs],
          [1000, 2000, 3000],
          reason: 'the snapshot stamps come back with the exercise',
        );
      });
    });
  }
}
