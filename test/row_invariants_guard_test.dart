// Stats PR 3b, Phase 3 — the row guard: add, edit, delete, skip, duplicate and
// watch-import sequences, run step by step on Mock and on Hive, checking after
// every step that no effort holds a leftover, stray or unsourced row (D-339).
//
// Scenarios S-883 – S-887 of
// `.github/agents/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.md`.
// The invariants are `test/helpers/row_invariants.dart`. The import builders are
// this file's own copies, as the plan requires (never an import across test
// files).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';
import 'helpers/row_invariants.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart' hide seedExercise;

const String _watchSessionId = 's-887';

/// The phone's clock: fixed, so every stamp the inbox writes is the same.
final DateTime _phoneNow = DateTime.utc(2026, 9, 27, 11);

// ─── Reads ──────────────────────────────────────────────────────────────────

/// The entries the state groups for [effortId], in entry order.
List<Map<String, dynamic>> _entriesOf(WorkoutState state, String effortId) =>
    (state.getExercisesWithEntries().firstWhere(
              (e) => e['id'] == effortId,
            )['entries']
            as List)
        .cast<Map<String, dynamic>>();

/// The reps each set of [effortId] reads, in entry order.
List<int> _reps(WorkoutState state, String effortId) => [
  for (final entry in _entriesOf(state, effortId)) entry['reps'] as int,
];

/// The weight each set of [effortId] reads, in entry order — the row a loaded
/// exercise (`load` capability) writes instead of an extra-weight companion.
List<double> _weights(WorkoutState state, String effortId) => [
  for (final entry in _entriesOf(state, effortId)) entry['weight'] as double,
];

/// The extra weight each entry of an effort holds, in entry order. Read from
/// the stored rows through the pairing every reader uses, so a row no entry
/// owns cannot pass as one that is owned.
List<double> _extraWeights(
  WorkoutState state,
  String effortId, {
  required int entries,
}) => [
  for (final row in EntryRows.companions(
    rows: state
        .getObservationsForEffort(effortId)
        .where((row) => row.metricId == MetricIds.extraWeight),
    metricId: MetricIds.extraWeight,
    entryCount: entries,
  ))
    row?.valueReal ?? 0.0,
];

/// How many rows of [metricId] the effort holds, read back from the store.
Future<int> _rowCount(
  WorkoutRepository repo,
  String effortId,
  String metricId,
) async => (await repo.getEffortObservations(
  effortId,
)).where((row) => row.metricId == metricId).length;

/// The efforts of [sessionId] logging [exerciseId], in store order.
Future<List<SegmentEffort>> _effortsFor(
  WorkoutRepository repo,
  String sessionId,
  String exerciseId,
) async {
  final found = <SegmentEffort>[];
  for (final segment in await repo.getSessionSegments(sessionId)) {
    for (final effort in await repo.getSegmentEfforts(segment.id)) {
      if (effort.exerciseId == exerciseId) found.add(effort);
    }
  }
  return found;
}

/// The id of the one effort [sessionId] logs [exerciseId] in.
Future<String> _effortIdFor(
  WorkoutRepository repo,
  String sessionId,
  String exerciseId,
) async => (await _effortsFor(repo, sessionId, exerciseId)).single.id;

// ─── The watch import, as `test/distance_source_import_test.dart` builds it ──

/// Counts the phone's message ids. One counter for the whole file: the store
/// is reopened between steps, so the inbox is rebuilt over it, and a rebuilt
/// inbox must not re-use an id an earlier one staged.
var _mailIds = 0;

WatchSessionInbox _inbox(
  WorkoutRepository repository,
  CaptureTransport transport,
) => WatchSessionInbox(
  repository: repository,
  transport: transport,
  validator: loadProtocolValidator(),
  clock: () => _phoneNow,
  idFactory: () => 'msg-phone-${++_mailIds}',
  onFailure: Error.throwWithStackTrace,
);

Future<void> _deliverEach(
  WatchSessionInbox inbox,
  List<Map<String, Object?>> events, {
  String tag = 'a',
}) async {
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_watchSessionId, [events[i]], messageId: 'msg-$tag-$i'),
    );
  }
}

Map<String, Object?> _timed(
  String entryId, {
  required String loggedAt,
  num? distanceMeters,
}) {
  final loggedAtMs = DateTime.parse(loggedAt);
  return {
    'entryId': entryId,
    'eventId': entryId,
    'kind': 'timed',
    'loggedAt': loggedAt,
    'sessionExerciseId': 'sx-run',
    'exerciseId': 'ex-run',
    'startedAt': loggedAtMs
        .subtract(const Duration(minutes: 20))
        .toIso8601String(),
    'endedAt': loggedAt,
    'distanceMeters': ?distanceMeters,
  };
}

Map<String, Object?> _set(
  String entryId, {
  required String loggedAt,
  int reps = 5,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': loggedAt,
  'sessionExerciseId': 'sx-bench',
  'exerciseId': 'ex-bench',
  'reps': reps,
  'loadKg': 80,
};

Map<String, Object?> _end() => {
  'entryId': 'end-$_watchSessionId',
  'eventId': 'end-$_watchSessionId',
  'kind': 'session_end',
  'loggedAt': '2026-09-27T11:00:00Z',
  'startedAt': '2026-09-27T10:00:00Z',
  'endedAt': '2026-09-27T11:00:00Z',
  'status': 'completed',
};

// ─── Scenarios ──────────────────────────────────────────────────────────────

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the row guard', () {
      late WorkoutRepository repo;
      late WorkoutState state;
      late String sessionId;

      setUp(() async {
        repo = await harness.open();
        // `seedExercise` (the `repository_harness.dart` copy this file uses)
        // only sets `Exercise.capabilities` on the object it creates —
        // `getExerciseById` reads capabilities from the separate
        // `setExerciseCapabilities` store instead (both repositories), so
        // without this call every exercise below hydrates with none, and
        // `addExerciseToSession`'s `hasLoad` check (session_core_entry.dart)
        // never sees bench's `load` capability.
        await seedExercise(
          repo,
          id: 'ex-run',
          name: 'Easy Run',
          capabilities: const ['time', 'distance'],
        );
        await repo.setExerciseCapabilities('ex-run', const [
          'time',
          'distance',
        ]);
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench Press',
          capabilities: const ['reps', 'sets', 'load'],
        );
        await repo.setExerciseCapabilities('ex-bench', const [
          'reps',
          'sets',
          'load',
        ]);
        await seedExercise(
          repo,
          id: 'ex-pull',
          name: 'Pull-up',
          capabilities: const ['reps', 'sets'],
        );
        await repo.setExerciseCapabilities('ex-pull', const ['reps', 'sets']);
        await seedExercise(
          repo,
          id: 'ex-plank',
          name: 'Plank',
          capabilities: const ['hold'],
        );
        await repo.setExerciseCapabilities('ex-plank', const ['hold']);
      });

      tearDown(() async => await harness.close());

      /// Reopens the store the way an app restart does, reloads the session
      /// from it, and checks the invariants after [step].
      Future<void> check(String step) async {
        repo = await harness.restart();
        state = WorkoutState(repo);
        await state.loadHistoricalSession(sessionId);
        await expectRowInvariants(repo, sessionId, step: step);
      }

      /// Starts a session and remembers the id the guard reads the store by.
      Future<void> startSession(
        String modality, {
        bool isRolling = false,
      }) async {
        state = WorkoutState(repo);
        await state.createNewSession(modality: modality, isRolling: isRolling);
        sessionId = state.currentSession!.id;
      }

      /// Adds [exerciseId] through the phone's own add path, which also gives
      /// it its first entry.
      Future<String> addExercise(
        String exerciseId, {
        required String name,
        required List<String> capabilities,
        String? effortKindOverride,
      }) => state.addExerciseToSession(
        Exercise(
          id: exerciseId,
          name: name,
          capabilities: capabilities,
          createdAtMs: fixtureStart,
          updatedAtMs: fixtureStart,
        ),
        effortKindOverride: effortKindOverride,
      );

      // ─── S-883: a phone timed sequence ──────────────────────────────────

      test('S-883 a phone timed sequence', () async {
        await startSession('cardio_endurance');
        final run = await addExercise(
          'ex-run',
          name: 'Easy Run',
          capabilities: const ['time', 'distance'],
        );

        for (var i = 0; i < 3; i++) {
          await state.addEntry(run);
        }
        await check('1 addEntry x 3');

        await state.setEntryDistance(run, 2, 3000.0);
        await check('2 setEntryDistance(run, 2, 3000.0)');

        // The live screen's own timed write goes through `updateEntryValue`,
        // not the Summary's dialog, so the source rule is checked on that path
        // too (F-4). A positive value records `entered`; writing it back to
        // zero records none, which is how a distance is removed.
        await state.updateEntryValue(run, 0, 'distance', 1500.0);
        await check('2a updateEntryValue(run, 0, distance, 1500)');
        expect(
          state.getEffortDistanceEntries(run)[0].row?.valueSource,
          EffortObservation.sourceEntered,
          reason: 'S-883 a distance written through the edit path has a source',
        );

        await state.updateEntryValue(run, 0, 'distance', 0.0);
        await check('2b updateEntryValue(run, 0, distance, 0)');
        expect(
          state.getEffortDistanceEntries(run)[0].row?.valueSource,
          isNull,
          reason: 'S-883 a zero distance carries no source',
        );

        await state.deleteEntry(run, 0);
        await check('3 deleteEntry(run, 0)');

        await state.addEntry(run);
        await check('4 addEntry(run)');

        await state.updateEntryValue(run, 1, 'extra-weight', 5.0);
        await check('5 updateEntryValue(run, 1, extra-weight)');

        await state.deleteEntry(run, 1);
        await check('6 deleteEntry(run, 1)');

        final entries = state.getTimedInstancesForEffort(run).length;
        expect(entries, 3, reason: 'S-883 three entries are left');
        expect(
          [
            for (final entry in state.getEffortDistanceEntries(run))
              entry.metres,
          ],
          [0.0, 0.0, 0.0],
          reason: 'S-883 the 3000 m entry is the one deleted',
        );
        expect(
          _extraWeights(state, run, entries: entries),
          [0.0, 0.0, 0.0],
          reason: 'S-883 the 5 kg entry is the one deleted',
        );
        expect(
          await _rowCount(repo, run, MetricIds.distance),
          3,
          reason: 'S-883 three distance rows are left',
        );
        expect(
          await _rowCount(repo, run, MetricIds.extraWeight),
          3,
          reason: 'S-883 three extra-weight rows are left',
        );
      });

      // ─── S-884: a phone set sequence ────────────────────────────────────

      test('S-884 a phone set sequence', () async {
        await startSession('resistance_lifting');
        final bench = await addExercise(
          'ex-bench',
          name: 'Bench Press',
          capabilities: const ['reps', 'sets', 'load'],
        );
        for (var i = 0; i < 2; i++) {
          await state.addEntry(bench);
        }
        final pull = await addExercise(
          'ex-pull',
          name: 'Pull-up',
          capabilities: const ['reps', 'sets'],
        );
        for (var i = 0; i < 2; i++) {
          await state.addEntry(pull);
        }
        await check('0 the session as set up');

        await state.updateEntryValue(bench, 1, 'reps', 9);
        await check('1 updateEntryValue(bench, 1, reps, 9)');

        await state.updateEntryValue(bench, 1, 'weight', 82.5);
        await check('1b updateEntryValue(bench, 1, weight, 82.5)');

        await state.markSetSkipped(bench, 2);
        await check('2 markSetSkipped(bench, 2)');

        await state.deleteEntry(bench, 0);
        await check('3 deleteEntry(bench, 0)');

        await state.addEntry(bench);
        await check('4 addEntry(bench)');

        await state.updateEntryValue(pull, 1, 'extra-weight', 5.0);
        await check('5 updateEntryValue(pull, 1, extra-weight)');

        await state.deleteEntry(pull, 0);
        await check('6 deleteEntry(pull, 0)');

        await state.addEntry(pull);
        await check('7 addEntry(pull)');

        expect(_reps(state, bench), [9, 0, 10], reason: 'S-884 bench reps');
        expect(
          _weights(state, bench),
          [82.5, 0.0, 0.0],
          reason: 'S-884 the loaded set keeps its weight, not an extra-weight row',
        );
        expect(
          await _rowCount(repo, bench, MetricIds.extraWeight),
          0,
          reason: 'S-884 a loaded exercise writes no extra-weight row at all',
        );
        expect(
          _extraWeights(state, pull, entries: _entriesOf(state, pull).length),
          [5.0, 0.0, 0.0],
          reason: 'S-884 pull-up extra weights',
        );
      });

      // ─── S-885: a hold sequence ─────────────────────────────────────────

      test('S-885 a hold sequence', () async {
        await startSession('isometric_stretching');
        final plank = await addExercise(
          'ex-plank',
          name: 'Plank',
          capabilities: const ['hold'],
        );
        for (var i = 0; i < 2; i++) {
          await state.addEntry(plank);
        }
        await check('0 the session as set up');

        await state.updateEntryValue(plank, 2, 'extra-weight', 7.0);
        await check('1 updateEntryValue(plank, 2, extra-weight, 7.0)');

        await state.deleteEntry(plank, 0);
        await check('2 deleteEntry(plank, 0)');

        await state.addEntry(plank);
        await check('3 addEntry(plank)');

        final entries = state.getTimedInstancesForEffort(plank).length;
        expect(entries, 3, reason: 'S-885 three holds are left');
        expect(
          _extraWeights(state, plank, entries: entries),
          [0.0, 7.0, 0.0],
          reason: 'S-885 the 7 kg hold moved down by one',
        );
        expect(
          await _rowCount(repo, plank, MetricIds.extraWeight),
          3,
          reason: 'S-885 three extra-weight rows are left',
        );
      });

      // ─── S-886: duplicating a block ─────────────────────────────────────

      test('S-886 duplicating a block', () async {
        await startSession('cardio_endurance', isRolling: true);
        final blockId = await state.addSessionBlock();

        final run = await addExercise(
          'ex-run',
          name: 'Easy Run',
          capabilities: const ['time', 'distance'],
        );
        await state.addEntry(run);
        await state.assignEffortToBlock(run, blockId);
        await state.setEntryDistance(run, 1, 2000.0);

        final bench = await addExercise(
          'ex-bench',
          name: 'Bench Press',
          capabilities: const ['reps', 'sets', 'load'],
          effortKindOverride: 'set',
        );
        await state.addEntry(bench);
        await state.assignEffortToBlock(bench, blockId);
        await check('0 the block as set up');

        await state.cloneSessionBlock(blockId);
        await check('1 cloneSessionBlock(blockId)');

        final runs = await _effortsFor(repo, sessionId, 'ex-run');
        expect(runs, hasLength(2), reason: 'S-886 the block’s run is copied');
        final copyRun = runs.singleWhere((e) => e.id != run).id;

        await state.deleteEntry(copyRun, 0);
        await check('2 deleteEntry(copyRun, 0)');

        await state.addEntry(copyRun);
        await check('3 addEntry(copyRun)');

        expect(
          [
            for (final entry in state.getEffortDistanceEntries(run))
              entry.metres,
          ],
          [0.0, 2000.0],
          reason: 'S-886 the original is untouched',
        );
        expect(
          [
            for (final entry in state.getEffortDistanceEntries(copyRun))
              entry.metres,
          ],
          [2000.0, 0.0],
          reason: 'S-886 the copy keeps 2000 and its new entry holds 0',
        );
      });

      // ─── S-887: a watch import, phone edits, then late watch entries ────

      test('S-887 a watch import, phone edits, then late entries', () async {
        final transport = CaptureTransport();

        /// Delivers [events] through an inbox over the repository that is live
        /// now — the store is reopened between steps — and then guards.
        Future<void> deliver(
          String step,
          List<Map<String, Object?>> events,
        ) async {
          await _deliverEach(_inbox(repo, transport), events, tag: step);
          await check(step);
        }

        // The session id is the import's own, so the guard can read the store
        // before a state has loaded it.
        sessionId = _watchSessionId;
        await deliver('0 the imported session', [
          _timed('e-r', loggedAt: '2026-09-27T10:30:00Z', distanceMeters: 3000),
          _set('e-b1', loggedAt: '2026-09-27T10:40:00Z'),
          _set('e-b2', loggedAt: '2026-09-27T10:45:00Z'),
          _end(),
        ]);

        final run = WatchSessionImporter.effortIdFor(
          sessionId,
          'sx-run',
          'ex-run',
          'timed',
        );
        final bench = WatchSessionImporter.effortIdFor(
          sessionId,
          'sx-bench',
          'ex-bench',
          'set',
        );
        expect(
          await _effortIdFor(repo, sessionId, 'ex-run'),
          run,
          reason: 'S-887 the import names the run effort as this test does',
        );

        await state.setEntryDistance(run, 0, 3500.0);
        await check('1 setEntryDistance(run, 0, 3500.0)');

        await state.deleteEntry(bench, 0);
        await check('2 deleteEntry(bench, 0)');

        await state.addEntry(bench);
        await check('3 addEntry(bench)');

        await deliver('4 the late set e-b3', [
          _set('e-b3', loggedAt: '2026-09-27T10:50:00Z', reps: 6),
        ]);

        await deliver('5 the late timed e-r0', [
          _timed(
            'e-r0',
            loggedAt: '2026-09-27T10:05:00Z',
            distanceMeters: 1000,
          ),
        ]);

        expect(
          state.getTimedInstancesForEffort(run).length,
          2,
          reason: 'S-887 the late timed entry joins the run',
        );
        expect(
          [
            for (final entry in state.getEffortDistanceEntries(run))
              (entry.metres, entry.row?.valueSource),
          ],
          [
            (1000.0, EffortObservation.sourceEntered),
            (3500.0, EffortObservation.sourceEntered),
          ],
          reason: 'S-887 1000 m arrived late, 3500 m is the phone’s own',
        );
        expect(
          _reps(state, bench),
          [5, 10, 6],
          reason:
              'S-887 the late set takes the next number, not the added '
              'set’s',
        );
      });
    });
  }
}
