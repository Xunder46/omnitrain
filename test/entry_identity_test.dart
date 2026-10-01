// Stats PR 3a2, Phase 2 — every write, delete and reader lands on the entry the
// user chose.
//
// Deleting a set or a timed entry removes exactly that entry's rows (D-326), an
// edit or a skip addresses the entry the rule names (D-324), a late extra weight
// joins its own set (D-325), and a leftover row never counts and is never
// deleted (D-321, D-322). Both stores must end identical, a Hive restart
// included.
//
// Scenarios S-851–S-860 of
// `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`, and
// S-862–S-864 from that plan's review round. The Summary's own rows are
// `test/entry_identity_summary_test.dart`'s.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/utils/distance_source.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

/// The entries `getExercisesWithEntries` reports for [effortId].
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

/// The reps each set of [effortId] reads, and whether it is marked skipped.
List<(int, bool)> _setValues(WorkoutState state, String effortId) => [
  for (final entry in _entriesOf(state, effortId))
    (entry['reps'] as int, entry['skipped'] as bool? ?? false),
];

void main() {
  // ─── S-851 / S-852: SP-1, deleting two sets ──────────────────────────────

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — writes and deletes', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      // Red before the fix: the second delete removed the rows named
      // `obs-<effort>-1-…`, which after the first delete are reps 7's (G4).
      test('S-851 deleting two sets removes the chosen ones, live', () async {
        await seedSession(repo, sessionId: 's-851', isRolling: true);
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench Press',
          capabilities: ['load'],
        );

        final state = WorkoutState(repo);
        await state.createNewSession(isRolling: true);
        final effortId = await state.addExerciseToSession(
          Exercise(
            id: 'ex-bench',
            name: 'Bench Press',
            capabilities: const ['load'],
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
          effortKindOverride: 'set',
        );
        for (final reps in [5, 6, 7]) {
          await state.updateEntryValue(
            effortId,
            _entriesOf(state, effortId).length - 1,
            'reps',
            reps,
          );
          if (reps != 7) await state.addEntry(effortId);
        }

        expect(_setValues(state, effortId), [
          (5, false),
          (6, false),
          (7, false),
        ]);

        await state.deleteEntry(effortId, 0);
        await state.deleteEntry(effortId, 1);

        expect(_setValues(state, effortId), [(6, false)]);
        expect(await storedRows(repo, effortId, MetricIds.reps), hasLength(1));
      });

      // Red before the fix for the same reason, and the restart makes sure the
      // store, not the in-memory list, is what the second delete read.
      test('S-852 the same on a reopened session', () async {
        await seedSession(repo, sessionId: 's-852');
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench Press',
          capabilities: ['load'],
        );
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-852',
          effortId: 'e-bench',
          exerciseId: 'ex-bench',
          entryCount: 3,
          hasExtraWeight: false,
          repsBase: 5,
        );

        repo = await harness.restart();
        var state = await loadState(repo, 's-852');
        await state.deleteEntry('e-bench', 0);
        await state.deleteEntry('e-bench', 1);

        repo = await harness.restart();
        state = await loadState(repo, 's-852');
        expect(_setValues(state, 'e-bench'), [(6, false)]);
      });

      // Red before the fix on Hive: display entry 2 is raw row 2, which is
      // set 10 (G2).
      test('S-853 an edit lands on its set', () async {
        await seedSession(repo, sessionId: 's-853');
        await seedWeightedSets(repo, segmentId: 'seg-s-853', effortId: 'e-row');

        repo = await harness.restart();
        var state = await loadState(repo, 's-853');
        await state.updateEntryValue('e-row', 2, 'reps', 99);

        repo = await harness.restart();
        state = await loadState(repo, 's-853');
        final reps = {
          for (final row in await storedRows(repo, 'e-row', MetricIds.reps))
            row.id: row.valueInt,
        };
        expect(reps['obs-e-row-2-reps'], 99);
        expect(reps['obs-e-row-10-reps'], 11);
      });

      // Red before the fix on Hive: the skip marked set 10 (G2).
      test('S-854 a skip lands on its set', () async {
        await seedSession(repo, sessionId: 's-854');
        await seedWeightedSets(repo, segmentId: 'seg-s-854', effortId: 'e-row');

        repo = await harness.restart();
        var state = await loadState(repo, 's-854');
        await state.markSetSkipped('e-row', 2);

        repo = await harness.restart();
        state = await loadState(repo, 's-854');
        final entries = _entriesOf(state, 'e-row');
        expect(entries[2]['reps'], 0);
        expect(entries[2]['skipped'], isTrue);
        expect(entries[10]['reps'], 11);
        expect(entries[10]['skipped'], isFalse);
      });

      // Red before the fix: the second delete found no row to remove, so the
      // 2000 m row paired with entry 0 (G5).
      test('S-855 deleting the first timed entry twice', () async {
        await seedSession(
          repo,
          sessionId: 's-855',
          modality: 'cardio_endurance',
        );
        await seedTimedEntries(
          repo,
          segmentId: 'seg-s-855',
          effortId: 'e-run4',
          entryCount: 4,
          metresBase: 1000.0,
        );

        repo = await harness.restart();
        var state = await loadState(repo, 's-855');
        await state.deleteEntry('e-run4', 0);
        await state.deleteEntry('e-run4', 0);

        expect(_distances(state, 'e-run4'), [3000.0, 4000.0]);
        expect(
          {
            for (final row in await storedRows(
              repo,
              'e-run4',
              MetricIds.distance,
            ))
              row.id: row.valueReal,
          },
          {'obs-e-run4-2-distance': 3000.0, 'obs-e-run4-3-distance': 4000.0},
        );
        expect(
          (await storedRowIds(
            repo,
            'e-run4',
          )).where((id) => id.contains('extra-weight')),
          {'obs-e-run4-2-extra-weight', 'obs-e-run4-3-extra-weight'},
        );
      });

      // Red before the fix: the first add overwrote a stored row, so the
      // 2000 m was not on "· 4" (G5).
      test('S-856 the F-5 sequence, live and reopened', () async {
        await seedExercise(repo, id: 'ex-run', name: 'Easy Run');

        final state = WorkoutState(repo);
        await state.createNewSession();
        final effortId = await state.addExerciseToSession(
          Exercise(
            id: 'ex-run',
            name: 'Easy Run',
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
          effortKindOverride: 'timed',
        );
        for (var i = 0; i < 3; i++) {
          await state.addEntry(effortId);
        }

        await state.deleteEntry(effortId, 0);
        // An instance id carries the index and the millisecond it was minted in
        // (O-4), so a real gap keeps this add off the instance it replaced.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await state.addEntry(effortId);
        await state.setEntryDistance(effortId, 3, 2000.0);
        await state.addEntry(effortId);

        final distanceIds = (await storedRowIds(
          repo,
          effortId,
        )).where((id) => id.contains('distance')).toSet();
        expect(distanceIds, {
          'obs-$effortId-1-distance',
          'obs-$effortId-2-distance',
          'obs-$effortId-3-distance',
          'obs-$effortId-4-distance',
          'obs-$effortId-5-distance',
        });

        // The 2000 m sits on "· 4", and "· 5" holds no distance.
        expect(_distances(state, effortId), [0.0, 0.0, 0.0, 2000.0, 0.0]);
        final live = _entriesOf(state, effortId);
        expect(live, hasLength(5));
        expect(live[3]['distance'], 2000.0);
        expect(live[4]['distance'], 0.0);

        repo = await harness.restart();
        final reopened = await loadState(repo, state.currentSession!.id);
        final stored = {
          for (final row in await storedRows(
            repo,
            effortId,
            MetricIds.distance,
          ))
            row.id: row.valueReal,
        };
        expect(stored, {
          'obs-$effortId-1-distance': 0.0,
          'obs-$effortId-2-distance': 0.0,
          'obs-$effortId-3-distance': 0.0,
          'obs-$effortId-4-distance': 2000.0,
          'obs-$effortId-5-distance': 0.0,
        });
        expect(_distances(reopened, effortId), [0.0, 0.0, 0.0, 2000.0, 0.0]);
        expect(_entriesOf(reopened, effortId)[3]['distance'], 2000.0);
      });

      // Red before the fix: the created id was `obs-e-dip-1-extra-weight`,
      // the entry's position rather than set 2's own number (G3, SP-5).
      test('S-857 a late extra weight joins its own set', () async {
        await seedSession(repo, sessionId: 's-857');
        await seedExercise(repo, id: 'ex-dip', name: 'Dip');
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-857',
          effortId: 'e-dip',
          exerciseId: 'ex-dip',
          entryCount: 2,
          hasExtraWeight: true,
          numbers: [0, 2],
          extraWeightNumbers: [0],
          weightFactor: 0.0,
        );

        repo = await harness.restart();
        var state = await loadState(repo, 's-857');
        await state.updateEntryValue('e-dip', 1, 'extra-weight', 5.0);

        final created = await storedRows(repo, 'e-dip', MetricIds.extraWeight);
        expect(created.map((row) => row.id).toSet(), {
          'obs-e-dip-0-extra-weight',
          'obs-e-dip-2-extra-weight',
        });
        expect(
          created
              .firstWhere((row) => row.id == 'obs-e-dip-2-extra-weight')
              .valueReal,
          5.0,
        );

        repo = await harness.restart();
        state = await loadState(repo, 's-857');
        final entries = _entriesOf(state, 'e-dip');
        expect(entries, hasLength(2));
        expect(entries[1]['extra-weight'], 5.0);
      });

      // Green before and after: it pins D-321 and D-322.
      test('S-858 leftovers never show, never count and stay stored', () async {
        await seedSession(
          repo,
          sessionId: 's-858',
          modality: 'cardio_endurance',
        );
        await seedExercise(repo, id: 'ex-lo', name: 'Easy Run');
        await repo.createEffort(
          SegmentEffort(
            id: 'e-lo',
            segmentId: 'seg-s-858',
            orderIndex: 0,
            effortKind: 'timed',
            exerciseId: 'ex-lo',
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        await repo.createTimedInstance(
          timedInstance('e-lo', 0, durationSecs: 1800, entryIndex: 0),
        );
        await repo.createObservation(
          distanceRow('e-lo', 0, 5000.0, atMs: fixtureRowAt(0)),
        );
        await repo.createObservation(
          distanceRow('e-lo', 7, 1000.0, atMs: fixtureRowAt(7)),
        );

        repo = await harness.restart();
        var state = await loadState(repo, 's-858');
        await state.setEntryDistance('e-lo', 0, 5500.0);

        expect(_distances(state, 'e-lo'), [5500.0]);

        repo = await harness.restart();
        state = await loadState(repo, 's-858');
        final leftover = (await storedRows(
          repo,
          'e-lo',
          MetricIds.distance,
        )).firstWhere((row) => row.id == 'obs-e-lo-7-distance');
        expect(leftover.valueReal, 1000.0);
      });

      // Red before the fix: it failed on Hive at the second delete (step 2).
      test('S-860 the scripted sequence ends identical', () async {
        await seedSession(repo, sessionId: 's-860');
        await seedWeightedSets(repo, segmentId: 'seg-s-860', effortId: 'e-row');
        await seedTimedEntries(
          repo,
          segmentId: 'seg-s-860',
          effortId: 'e-run',
          exerciseId: 'ex-run2',
          exerciseName: 'Easy Run',
        );

        repo = await harness.restart();
        var state = await loadState(repo, 's-860');

        Future<void> reload() async {
          repo = await harness.restart();
          state = await loadState(repo, 's-860');
        }

        await state.deleteEntry('e-row', 0);
        await reload();
        await state.deleteEntry('e-row', 5);
        await reload();
        await state.updateEntryValue('e-row', 1, 'reps', 77);
        await reload();
        await state.addEntry('e-row');
        await reload();
        await state.markSetSkipped('e-row', 3);
        await reload();
        await state.deleteEntry('e-run', 0);
        await reload();
        await state.deleteEntry('e-run', 0);
        await reload();
        await state.setEntryDistance('e-run', 2, 2500.0);
        await reload();
        await state.addEntry('e-run');
        await reload();

        final sets = _setValues(state, 'e-row');
        expect(
          [for (final (reps, _) in sets) reps],
          [2, 77, 4, 0, 6, 8, 9, 10, 11, 12, 10],
        );
        expect(sets[3], (0, true), reason: 'entry 3 is the skipped one');
        expect(_distances(state, 'e-run'), [
          300.0,
          400.0,
          2500.0,
          600.0,
          700.0,
          800.0,
          900.0,
          1000.0,
          1100.0,
          1200.0,
          0.0,
        ]);

        // Every surviving row is the one the scripted steps left: nothing was
        // renumbered, nothing was renamed, and the deleted entries' rows are
        // the only ones gone (D-322, D-326).
        final runRows = await repo.getEffortObservations('e-run');
        expect(
          {
            for (final row in runRows)
              if (row.metricId == MetricIds.distance) row.id: row.valueReal,
          },
          {
            'obs-e-run-2-distance': 300.0,
            'obs-e-run-3-distance': 400.0,
            'obs-e-run-4-distance': 2500.0,
            'obs-e-run-5-distance': 600.0,
            'obs-e-run-6-distance': 700.0,
            'obs-e-run-7-distance': 800.0,
            'obs-e-run-8-distance': 900.0,
            'obs-e-run-9-distance': 1000.0,
            'obs-e-run-10-distance': 1100.0,
            'obs-e-run-11-distance': 1200.0,
            'obs-e-run-12-distance': 0.0,
          },
        );
        expect(
          {
            for (final row in runRows)
              if (row.metricId == MetricIds.extraWeight) row.id,
          },
          {for (var n = 2; n <= 12; n++) 'obs-e-run-$n-extra-weight'},
        );
        expect(
          (await repo.getEffortObservations(
            'e-row',
          )).map((row) => row.id).toSet(),
          {
            for (final n in [1, 2, 3, 4, 5, 7, 8, 9, 10, 11]) ...[
              'obs-e-row-$n-reps',
              'obs-e-row-$n-weight',
            ],
            // The set the sequence added, with the added-weight row every new
            // set gets.
            'obs-e-row-12-reps',
            'obs-e-row-12-weight',
            'obs-e-row-12-extra-weight',
          },
        );
      });

      // ─── The review round's probes ─────────────────────────────────────────

      // Red before the fix: the overlay paired added weight by row position, so
      // the list read 1, 2, 2 kg where Stats and the PR read none, 1, 2 (F-5).
      test('S-862 a set reads its own added weight', () async {
        await seedSession(repo, sessionId: 's-862');
        await seedExercise(repo, id: 'ex-pull2', name: 'Pull-up');
        await seedSetEffort(
          repo,
          segmentId: 'seg-s-862',
          effortId: 'e-pull2',
          exerciseId: 'ex-pull2',
          entryCount: 3,
          hasExtraWeight: true,
          extraWeightNumbers: [1, 2],
          weightFactor: 0.0,
        );

        repo = await harness.restart();
        final state = await loadState(repo, 's-862');

        final entries = _entriesOf(state, 'e-pull2');
        expect(entries.map((e) => e['reps']).toList(), [1, 2, 3]);
        expect(
          entries.map((e) => e['extra-weight']).toList(),
          [0.0, 1.0, 2.0],
          reason: 'set 1 holds 1 kg and set 2 holds 2 kg, not 2 kg twice',
        );
      });

      // Red before the fix: the new row took the entry's own position as a
      // number, which was a stored row's id — hold 1's 7 kg became 5 kg and
      // hold 2 read nothing (F-4).
      test('S-863 a hold reads its own added weight', () async {
        await seedSession(repo, sessionId: 's-863');
        await seedExercise(repo, id: 'ex-plank', name: 'Plank');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-863',
          effortId: 'e-plank',
          exerciseId: 'ex-plank',
          entryCount: 2,
          rows: [
            distanceRow('e-plank', 0, 0.0, atMs: fixtureRowAt(0)),
            extraWeightRow('e-plank', 1, 7.0, atMs: fixtureRowAt(1)),
          ],
        );

        repo = await harness.restart();
        final state = await loadState(repo, 's-863');
        await state.updateEntryValue('e-plank', 1, 'extra-weight', 5.0);

        expect(
          {
            for (final row in await storedRows(
              repo,
              'e-plank',
              MetricIds.extraWeight,
            ))
              row.id: row.valueReal,
          },
          {
            'obs-e-plank-1-extra-weight': 7.0,
            'obs-e-plank-2-extra-weight': 5.0,
          },
          reason: 'the stored 7 kg is not overwritten',
        );
        expect(
          _entriesOf(state, 'e-plank').map((e) => e['extra-weight']).toList(),
          [7.0, 5.0],
        );
      });

      // Red before the fix: with no row of its own, the new row took number 0,
      // so the 5 kg the user typed on hold 2 showed on hold 1 (F-4).
      test('S-864 the later of two row-less holds keeps its value', () async {
        await seedSession(repo, sessionId: 's-864');
        await seedExercise(repo, id: 'ex-side', name: 'Side Plank');
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-864',
          effortId: 'e-side',
          exerciseId: 'ex-side',
          entryCount: 2,
          rows: [distanceRow('e-side', 0, 0.0, atMs: fixtureRowAt(0))],
        );

        repo = await harness.restart();
        final state = await loadState(repo, 's-864');
        await state.updateEntryValue('e-side', 1, 'extra-weight', 5.0);

        expect(
          {
            for (final row in await storedRows(
              repo,
              'e-side',
              MetricIds.extraWeight,
            ))
              row.id: row.valueReal,
          },
          {'obs-e-side-1-extra-weight': 0.0, 'obs-e-side-2-extra-weight': 5.0},
          reason: 'the fill row joins hold 1, so hold 2 is the second row',
        );
        expect(
          _entriesOf(state, 'e-side').map((e) => e['extra-weight']).toList(),
          [0.0, 5.0],
        );
      });
    });
  }

  // ─── S-841's rule on the set paths, without a store ──────────────────────

  group('the rule addresses what the delete removed', () {
    test('a gap left by an old delete is not renumbered', () {
      final rows = [
        repsRow('e-gap', 0, 5, atMs: fixtureRowAt(0)),
        weightRow('e-gap', 0, 0.0, atMs: fixtureRowAt(0)),
        repsRow('e-gap', 2, 7, atMs: fixtureRowAt(2)),
        weightRow('e-gap', 2, 0.0, atMs: fixtureRowAt(2)),
      ];

      final groups = EntryRows.setGroups(rows);
      expect(groups.map((group) => group.number).toList(), [0, 2]);
      expect(groups[1].rowFor(MetricIds.reps)?.valueInt, 7);
      expect(EntryRows.numberForNewRow(rows), 3);
    });
  });
}
