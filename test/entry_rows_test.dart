// Stats PR 3a2, Phase 1 — the entry rule, new-row numbering and duplicated
// blocks.
//
// An entry's rows are found by the number in their id (D-324), a new row is
// numbered above every row the effort holds (D-325), and a duplicated block's
// rows are named for the effort they were copied into (D-329). Both stores must
// read the same, and a Hive restart must not change the answer.
//
// Scenarios S-841–S-847 of
// `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`, and S-1305
// and S-1306 of
// `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/utils/distance_source.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

/// The entries `getExercisesWithEntries` reports for [effortId] — the list the
/// UI reads.
List<Map<String, dynamic>> _entriesOf(WorkoutState state, String effortId) {
  final exercise = state.getExercisesWithEntries().firstWhere(
    (e) => e['id'] == effortId,
  );
  return (exercise['entries'] as List).cast<Map<String, dynamic>>();
}

/// The distance each entry of a timed effort owns, read through the pairing
/// every distance reader goes through.
List<double> _distances(WorkoutState state, String effortId) {
  final paired = DistancePairing.forEntries(
    distanceRows: state.getObservationsForEffort(effortId),
    entryCount: state.getTimedInstancesForEffort(effortId).length,
  );
  return [for (final row in paired) row?.valueReal ?? 0.0];
}

void main() {
  // ─── S-841: the parser, on its own ────────────────────────────────────────

  group('S-841 every id shape reads its number', () {
    test('the shapes every writer has used', () {
      expect(EntryRows.numberInId('obs-e1-3-reps'), 3);
      expect(EntryRows.numberInId('obs-e1-3-extra-weight'), 3);
      expect(EntryRows.numberInId('obs-e1-3-round-duration'), 3);
      expect(EntryRows.numberInId('obs-effort-1727000000000-0-11-weight'), 11);
      // A suffixed id carries no number: the suffix is not part of the shape
      // the rule reads (D-704, S-1305).
      expect(EntryRows.numberInId('obs-e1-4-distance-1727000000123'), isNull);
      expect(EntryRows.numberInId('obs-e1-x-reps'), isNull);
      expect(
        EntryRows.numberInId('9f1c8a44-3b2e-4c0d-8f6a-1d2e3f4a5b6c'),
        isNull,
      );
    });

    test('the metric key is read with the number', () {
      expect(EntryRows.parseId('obs-e1-3-round-duration'), (
        number: 3,
        metricKey: 'round-duration',
      ));
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the rule', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-842 twelve weighted sets read the same', () async {
        await seedSession(repo, sessionId: 's-842');
        await seedWeightedSets(repo, segmentId: 'seg-s-842', effortId: 'e-row');

        repo = await harness.restart();
        final state = await loadState(repo, 's-842');

        final entries = _entriesOf(state, 'e-row');
        expect(entries, hasLength(12));
        for (var k = 0; k < 12; k++) {
          expect(entries[k]['reps'], k + 1, reason: 'entry $k reads its reps');
          expect(entries[k]['weight'], 10.0 * (k + 1));
        }
      });

      // Red before the fix on Hive: the store returns 0, 1, 10, 11, 2, … (G1,
      // G3), and the id pattern could not read `…-extra-weight` at all.
      test('S-843 twelve bodyweight sets group by number', () async {
        await seedSession(repo, sessionId: 's-843');
        await seedBodyweightSets(
          repo,
          segmentId: 'seg-s-843',
          effortId: 'e-pull',
        );

        repo = await harness.restart();
        final state = await loadState(repo, 's-843');

        final entries = _entriesOf(state, 'e-pull');
        expect(entries, hasLength(12));
        for (var k = 0; k < 12; k++) {
          expect(entries[k]['reps'], k + 1, reason: 'entry $k reads its reps');
          expect(
            entries[k]['extra-weight'],
            k.toDouble(),
            reason: 'entry $k reads its own added weight',
          );
        }
      });

      test('S-844 twelve timed entries pair their companions', () async {
        await seedSession(repo, sessionId: 's-844');
        await seedTimedEntries(repo, segmentId: 'seg-s-844', effortId: 'e-run');

        repo = await harness.restart();
        final state = await loadState(repo, 's-844');

        final entries = _entriesOf(state, 'e-run');
        expect(entries, hasLength(12));
        for (var k = 0; k < 12; k++) {
          expect(entries[k]['distance'], (k + 1) * 100.0);
          expect(entries[k]['extra-weight'], k.toDouble());
        }

        expect(_distances(state, 'e-run'), [
          for (var k = 0; k < 12; k++) (k + 1) * 100.0,
        ]);
      });

      // Red before the fix: the add mints the number the deleted entry had and
      // overwrites the stored 3000 m row (G5).
      test('S-845 new rows never collide', () async {
        final exercise = Exercise(
          id: 'ex-run',
          name: 'Easy Run',
          createdAtMs: fixtureStart,
          updatedAtMs: fixtureStart,
        );
        await seedExercise(repo, id: 'ex-run', name: 'Easy Run');

        final state = WorkoutState(repo);
        await state.createNewSession();
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );

        // `addExerciseToSession` logs the first entry itself; two more make
        // three, as the scenario's fixture says.
        for (var i = 0; i < 2; i++) {
          await state.addEntry(effortId);
        }
        await state.setEntryDistance(effortId, 0, 1000.0);
        await state.setEntryDistance(effortId, 1, 2000.0);
        await state.setEntryDistance(effortId, 2, 3000.0);

        await state.deleteEntry(effortId, 0);
        await state.addEntry(effortId);

        final ids = await storedRowIds(repo, effortId);
        expect(
          ids,
          containsAll(<String>[
            'obs-$effortId-1-distance',
            'obs-$effortId-2-distance',
            'obs-$effortId-3-distance',
            'obs-$effortId-3-extra-weight',
          ]),
        );

        final allRows = await storedRows(repo, effortId, MetricIds.distance);
        final metres = {for (final row in allRows) row.id: row.valueReal};
        expect(metres['obs-$effortId-1-distance'], 2000.0, reason: '$metres');
        expect(metres['obs-$effortId-2-distance'], 3000.0);
        expect(metres['obs-$effortId-3-distance'], 0.0);

        expect(
          _distances(state, effortId),
          [2000.0, 3000.0, 0.0],
          reason:
              'instances: ${state.getTimedInstancesForEffort(effortId).length} '
              'rows: ${state.getObservationsForEffort(effortId).map((r) => r.id)}',
        );
      });

      // Red before the fix: the suffixed row read as unnumbered and sorted
      // last, so the pairing came out [0, 0, 0, 0, 2000] (F-5).
      test('S-846 a 3a suffixed id sits at its number', () async {
        await seedSession(repo, sessionId: 's-846');
        await seedExercise(repo, id: 'ex-f5', name: 'Easy Run');
        await repo.createEffort(
          SegmentEffort(
            id: 'e-f5',
            segmentId: 'seg-s-846',
            orderIndex: 0,
            effortKind: 'timed',
            exerciseId: 'ex-f5',
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        for (var i = 0; i < 5; i++) {
          await repo.createTimedInstance(
            timedInstance('e-f5', i, durationSecs: 60, entryIndex: i),
          );
        }
        for (final row in <EffortObservation>[
          distanceRow('e-f5', 1, 0.0, atMs: fixtureRowAt(0)),
          distanceRow('e-f5', 2, 0.0, atMs: fixtureRowAt(1)),
          distanceRow('e-f5', 3, 0.0, atMs: fixtureRowAt(2)),
          distanceRow('e-f5', 4, 0.0, atMs: fixtureRowAt(4)),
        ]) {
          await repo.createObservation(row);
        }

        repo = await harness.restart();
        final state = await loadState(repo, 's-846');

        expect(_distances(state, 'e-f5'), [0.0, 0.0, 0.0, 0.0, 0.0]);
      });

      // Red before the fix: the copied rows were given random UUIDs (G9).
      test('S-847 duplicated blocks stay addressable', () async {
        await seedSession(repo, sessionId: 's-847', isRolling: true);
        await seedExercise(
          repo,
          id: 'ex-row',
          name: 'Row',
          capabilities: ['load'],
        );
        await repo.createSessionBlock(
          SessionBlock(
            id: 'b-1',
            sessionId: 's-847',
            name: 'Block',
            orderIndex: 0,
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-847',
          effortId: 'e-s',
          exerciseId: 'ex-row',
          entryCount: 3,
          hasExtraWeight: false,
          weightFactor: 0.0,
          repsBase: 5,
        );
        // The timed effort holds S-846's own shape — numbers 1, 2, 3 and 4 —
        // across five instances.
        await seedExercise(repo, id: 'ex-run-row', name: 'Easy Run');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-847',
          effortId: 'e-d',
          exerciseId: 'ex-run-row',
          entryCount: 5,
          effortKind: 'timed',
          rows: [
            distanceRow('e-d', 1, 0.0, atMs: fixtureRowAt(0)),
            distanceRow('e-d', 2, 0.0, atMs: fixtureRowAt(1)),
            distanceRow('e-d', 3, 0.0, atMs: fixtureRowAt(2)),
            distanceRow('e-d', 4, 0.0, atMs: fixtureRowAt(4)),
          ],
        );
        for (final effortId in ['e-s', 'e-d']) {
          final effort = (await repo.getSegmentEfforts(
            'seg-s-847',
          )).firstWhere((e) => e.id == effortId);
          await repo.updateEffort(
            SegmentEffort(
              id: effort.id,
              segmentId: effort.segmentId,
              orderIndex: effort.orderIndex,
              effortKind: effort.effortKind,
              exerciseId: effort.exerciseId,
              blockId: 'b-1',
              createdAtMs: effort.createdAtMs,
              updatedAtMs: effort.updatedAtMs,
            ),
          );
        }

        final cloneBlockId = await repo.cloneSessionBlock('b-1');
        expect(cloneBlockId, isNotEmpty);

        final clones = {
          for (final effort in (await repo.getSegmentEfforts(
            'seg-s-847',
          )).where((e) => e.blockId == cloneBlockId))
            effort.id: effort.effortKind,
        };
        expect(clones, hasLength(2));
        final cloneSets = clones.entries
            .firstWhere((e) => e.value == 'set')
            .key;
        final cloneTimed = clones.entries
            .firstWhere((e) => e.value == 'timed')
            .key;

        // Every copied row is named for the effort it was copied into, with the
        // source's own number and the source's value.
        final copiedRows = await repo.getEffortObservations(cloneSets);
        expect(copiedRows.map((row) => row.id).toSet(), {
          'obs-$cloneSets-0-reps',
          'obs-$cloneSets-0-weight',
          'obs-$cloneSets-1-reps',
          'obs-$cloneSets-1-weight',
          'obs-$cloneSets-2-reps',
          'obs-$cloneSets-2-weight',
        });
        expect(
          copiedRows.firstWhere((row) => row.id.endsWith('-2-reps')).valueInt,
          7,
        );
        // The copy holds one row per source row, so nothing is merged and its
        // entries pair the way the source's do.
        expect(
          (await repo.getEffortObservations(
            cloneTimed,
          )).map((row) => row.id).toSet(),
          {
            'obs-$cloneTimed-1-distance',
            'obs-$cloneTimed-2-distance',
            'obs-$cloneTimed-3-distance',
            'obs-$cloneTimed-4-distance',
          },
        );

        final state = await loadState(repo, 's-847');
        await state.updateEntryValue(cloneSets, 1, 'reps', 60);

        final copyEntries = _entriesOf(state, cloneSets);
        expect(copyEntries.map((e) => e['reps']).toList(), [5, 60, 7]);
        expect(
          _entriesOf(state, 'e-s').map((e) => e['reps']).toList(),
          [5, 6, 7],
          reason: 'the source block is untouched',
        );
        expect(_distances(state, 'e-d'), [0.0, 0.0, 0.0, 0.0, 0.0]);
        expect(_distances(state, cloneTimed), [0.0, 0.0, 0.0, 0.0, 0.0]);
      });

      // ─── S-1305 / S-1306: a row with no number pairs with nothing ────────

      test(
        'S-1305 a suffixed row pairs with nothing and stays stored',
        () async {
          await seedSession(repo, sessionId: 's-1305');
          await seedExercise(repo, id: 'ex-1305', name: 'Easy Run');
          await repo.createEffort(
            SegmentEffort(
              id: 'e-1305',
              segmentId: 'seg-s-1305',
              orderIndex: 0,
              effortKind: 'timed',
              exerciseId: 'ex-1305',
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
          for (var i = 0; i < 2; i++) {
            await repo.createTimedInstance(
              timedInstance('e-1305', i, durationSecs: 60, entryIndex: i),
            );
          }
          await repo.createObservation(
            distanceRow('e-1305', 0, 0.0, atMs: fixtureRowAt(0)),
          );
          await repo.createObservation(
            distanceRow(
              'e-1305',
              1,
              2000.0,
              atMs: fixtureRowAt(1),
              source: EffortObservation.sourceEntered,
              id: 'obs-e-1305-1-distance-9000',
            ),
          );

          repo = await harness.restart();
          final state = await loadState(repo, 's-1305');

          expect(EntryRows.numberInId('obs-e-1305-1-distance-9000'), isNull);
          expect(_distances(state, 'e-1305'), [0.0, 0.0]);
          expect(
            state.getEffortDistanceEntries('e-1305')[1].row,
            isNull,
            reason: 'S-1305 the suffixed row belongs to no entry',
          );

          // Every read leaves it stored.
          final stored = await storedRows(repo, 'e-1305', MetricIds.distance);
          expect(stored.map((row) => row.id).toSet(), {
            'obs-e-1305-0-distance',
            'obs-e-1305-1-distance-9000',
          });
          expect(
            stored.firstWhere((row) => row.id.endsWith('-9000')).valueReal,
            2000.0,
          );
        },
      );

      test('S-1306 a copied suffixed row gets a fresh id', () async {
        await seedSession(repo, sessionId: 's-1306', isRolling: true);
        await seedExercise(
          repo,
          id: 'ex-1306',
          name: 'Row',
          capabilities: ['load'],
        );
        await repo.createSessionBlock(
          SessionBlock(
            id: 'b-1306',
            sessionId: 's-1306',
            name: 'Block',
            orderIndex: 0,
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-1306',
          effortId: 'e-1306-s',
          exerciseId: 'ex-1306',
          entryCount: 2,
          hasExtraWeight: false,
          weightFactor: 0.0,
          repsBase: 5,
        );
        await seedExercise(repo, id: 'ex-1306-run', name: 'Easy Run');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-1306',
          effortId: 'e-1306-d',
          exerciseId: 'ex-1306-run',
          entryCount: 2,
          effortKind: 'timed',
          rows: [
            distanceRow('e-1306-d', 0, 0.0, atMs: fixtureRowAt(0)),
            distanceRow(
              'e-1306-d',
              1,
              2000.0,
              atMs: fixtureRowAt(1),
              source: EffortObservation.sourceEntered,
              id: 'obs-e-1306-d-1-distance-9000',
            ),
          ],
        );
        for (final effortId in ['e-1306-s', 'e-1306-d']) {
          final effort = (await repo.getSegmentEfforts(
            'seg-s-1306',
          )).firstWhere((e) => e.id == effortId);
          await repo.updateEffort(
            SegmentEffort(
              id: effort.id,
              segmentId: effort.segmentId,
              orderIndex: effort.orderIndex,
              effortKind: effort.effortKind,
              exerciseId: effort.exerciseId,
              blockId: 'b-1306',
              createdAtMs: effort.createdAtMs,
              updatedAtMs: effort.updatedAtMs,
            ),
          );
        }

        final cloneBlockId = await repo.cloneSessionBlock('b-1306');
        expect(cloneBlockId, isNotEmpty);
        final clones = {
          for (final effort in (await repo.getSegmentEfforts(
            'seg-s-1306',
          )).where((e) => e.blockId == cloneBlockId))
            effort.id: effort.effortKind,
        };
        final cloneSets = clones.entries
            .firstWhere((e) => e.value == 'set')
            .key;
        final cloneTimed = clones.entries
            .firstWhere((e) => e.value == 'timed')
            .key;

        // The numbered rows keep the source's number and metric key.
        expect(
          (await repo.getEffortObservations(
            cloneSets,
          )).map((row) => row.id).toSet(),
          {
            'obs-$cloneSets-0-reps',
            'obs-$cloneSets-0-weight',
            'obs-$cloneSets-1-reps',
            'obs-$cloneSets-1-weight',
          },
        );

        // The suffixed row is copied under a fresh unique id, so it pairs with
        // no entry in the copy either.
        final copiedTimed = await repo.getEffortObservations(cloneTimed);
        expect(copiedTimed, hasLength(2));
        final copiedSuffixed = copiedTimed.firstWhere(
          (row) => row.valueReal == 2000.0,
        );
        expect(copiedSuffixed.id, isNot('obs-$cloneTimed-1-distance-9000'));
        expect(EntryRows.numberInId(copiedSuffixed.id), isNull);
        expect(copiedSuffixed.valueSource, EffortObservation.sourceEntered);

        final state = await loadState(repo, 's-1306');
        expect(_distances(state, cloneTimed), [0.0, 0.0]);
        expect(_distances(state, 'e-1306-d'), [0.0, 0.0]);
        expect(
          (await storedRows(
            repo,
            'e-1306-d',
            MetricIds.distance,
          )).map((row) => row.id).toSet(),
          {'obs-e-1306-d-0-distance', 'obs-e-1306-d-1-distance-9000'},
          reason: 'S-1306 the source stays readable',
        );
      });
    });
  }
}
