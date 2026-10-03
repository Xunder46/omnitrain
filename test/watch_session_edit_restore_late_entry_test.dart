// Stats PR 3d, Phase 1 — the failing probe: a wrist entry that arrives while an
// Edit Session is open is lost when the user Discards.
//
// Plan: `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/
// 2026-10-02-03d-stats-pr3d-late-watch-entry-plan.md`, Phase 1.
//
// Edit mode writes structural changes straight to the repository, and Discard
// undoes them with `WorkoutState.restoreSessionSnapshot`, which replaces every
// snapshotted effort's rows with the rows it held at snapshot time. An entry
// the wrist delivers after that snapshot is not among those rows, so the
// restore deletes it — and the wrist never re-sends it, because the inbox
// stamped it applied when it arrived. The entry is gone for good.
//
// Every case imports F-CAP's `full` case
// (`watch/contract/watch_capture_contract.json`) minus the entry it needs to
// arrive late, runs on `MockWorkoutRepository` and on `HiveWorkoutRepository`
// (a temp directory), and drives the state the way the edit screen does:
// `loadHistoricalSession` (opened from history), `loadSessionData` then
// `snapshotSessionState` (edit mode entered), the late delivery, the user's
// edit, then `restoreSessionSnapshot` (Discard) or
// `normalizeRoundsToFinished` (Save).
//
// This phase ends red by design. S-1401, S-1402, S-1404, S-1405, S-1406 and
// S-1410 fail on both stores; S-1403, S-1407, S-1408, S-1409, S-1413 and
// S-1414 already pass, because they assert behaviour the bug does not break.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/session_edit_snapshot.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _capId = 's-cap-1';

/// The F-CAP entries these scenarios move around the snapshot.
const String _eRun = 'e-run';
const String _eR3 = 'e-r3';
const String _eSet2 = 'e-set2';
const String _eSet3 = 'e-set3';

final String _run = WatchSessionImporter.effortIdFor(
  _capId,
  'sx-run',
  'ex-run',
  'timed',
);
final String _bjj = WatchSessionImporter.effortIdFor(
  _capId,
  'sx-bjj',
  'ex-bjj',
  'round',
);
final String _bench = WatchSessionImporter.effortIdFor(
  _capId,
  'sx-bench',
  'ex-bench',
  'set',
);

/// F-CAP's summary for the run, the one a late `e-run` brings back.
const String _runSummary = 'sensor-timed_instance-timed-s-cap-1-e-run';

/// Stand-in for the path_provider channel, which has no implementation under
/// `flutter_test` (same pattern as `test/watch_session_edit_restore_summaries_test.dart`).
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return _root.path;
            default:
              return null;
          }
        });
  }
}

/// One repository implementation, opened over its own storage.
abstract class _Store {
  String get name;
  Future<WorkoutRepository> open();
  Future<void> close();
}

class _MockStore implements _Store {
  @override
  String get name => 'Mock';

  @override
  Future<WorkoutRepository> open() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  @override
  Future<void> close() async {}
}

class _HiveStore implements _Store {
  Directory? _dir;
  bool _closed = false;

  @override
  String get name => 'Hive';

  @override
  Future<WorkoutRepository> open() async {
    final dir = await Directory.systemTemp.createTemp(
      'watch_edit_restore_late_entry_',
    );
    _dir = dir;
    _closed = false;
    _PathProviderChannel.install(dir);
    Hive.init(dir.path);
    final repository = HiveWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  /// Hive caches open boxes by name process-wide, so a store that has to start
  /// empty again (S-1410's second fixture) must close before it re-opens.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Hive.deleteFromDisk();
    final dir = _dir;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }
}

/// An imported session, with the inbox that imported it and the transport the
/// inbox answered on.
class _Imported {
  const _Imported(this.repository, this.inbox, this.transport);

  final WorkoutRepository repository;
  final WatchSessionInbox inbox;
  final CaptureTransport transport;
}

/// Opens [store] and imports F-CAP's `full` case the way a wrist delivers it:
/// one `observations_up` per stored event, minus the entries in [without],
/// which are then free to arrive late.
Future<_Imported> _import(
  _Store store, {
  Set<String> without = const {},
}) async {
  final repository = await store.open();
  await seedCaptureCatalog(repository);
  final transport = CaptureTransport();
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: loadProtocolValidator(),
    clock: () => DateTime.utc(2026, 9, 25, 11),
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
  );
  var sent = 0;
  for (final event in captureEvents('full')) {
    if (without.contains(event['entryId'])) continue;
    await inbox.receive(
      observationsUp(_capId, [event], messageId: 'msg-import-${++sent}'),
    );
  }
  return _Imported(repository, inbox, transport);
}

/// One event of the `full` case, as the wrist stored it.
Map<String, Object?> _event(String entryId) =>
    captureEvents('full').singleWhere((event) => event['entryId'] == entryId);

/// Delivers one stored wrist entry late, as a re-send of a message the phone
/// never acknowledged looks.
Future<void> _deliver(
  WatchSessionInbox inbox,
  String entryId, {
  required String tag,
}) async {
  final result = await inbox.receive(
    observationsUp(_capId, [_event(entryId)], messageId: 'msg-$tag-$entryId'),
  );
  expect(
    result.outcome,
    anyOf(WatchInboxOutcome.staged, WatchInboxOutcome.unchanged),
    reason: '$tag: $entryId reaches the inbox',
  );
}

/// A `structure_change` the phone stages before it sends it.
Map<String, Object?> _phoneChange(String changeId, Map<String, Object?> body) =>
    {
      'type': 'structure_change',
      'sessionId': _capId,
      'payload': {
        'changeId': changeId,
        'changes': [body],
      },
    };

/// The session opened from history, then edit mode entered: the edit screen
/// reads the watermark, reloads the session, and snapshots it with the
/// watermark (D-801).
Future<({WorkoutState workout, SessionEditSnapshot snapshot})> _enterEditMode(
  WorkoutRepository repository, {
  WatchLateEntryRecovery? recovery,
  bool watermark = true,
}) async {
  final workout = WorkoutState(repository, watchLateEntryRecovery: recovery);
  await workout.loadHistoricalSession(_capId);
  final applied = watermark ? await workout.appliedWatchEntryIds() : null;
  await workout.loadSessionData();
  expect(workout.error, isNull, reason: 'the session loads');
  final snapshot = workout.snapshotSessionState(
    watchEntryIdsAppliedAtSnapshot: applied,
  );
  expect(snapshot, isNotNull, reason: 'edit mode holds a snapshot');
  return (workout: workout, snapshot: snapshot!);
}

/// The screen's reload after the repository moved under it.
Future<void> _reload(WorkoutState workout) async {
  await workout.loadSessionData();
  expect(workout.error, isNull, reason: 'the session reloads');
}

/// Discard, as `_discardEditChanges` runs it: the restore happens only when
/// the screen saw a structural change of its own.
Future<void> _discard(
  WorkoutState workout,
  SessionEditSnapshot snapshot, {
  bool structuralChanges = true,
}) async {
  if (structuralChanges) await workout.restoreSessionSnapshot(snapshot);
  expect(workout.error, isNull, reason: 'Discard leaves no error');
}

Future<int> _benchSets(WorkoutRepository repository) async => [
  for (final observation in await repository.getEffortObservations(_bench))
    if (observation.metricId == MetricIds.reps) observation,
].length;

/// One bench entry's reps and weight, or `[null, null]` when no entry sits at
/// [entryIndex].
Future<List<Object?>> _setAt(
  WorkoutRepository repository,
  int entryIndex,
) async {
  final reps = await observationAt(repository, _bench, entryIndex, 'reps');
  final weight = await observationAt(repository, _bench, entryIndex, 'weight');
  return [reps?.valueInt, weight?.valueReal];
}

/// The ids of the bench's reps rows, which carry each entry's number.
Future<List<String>> _benchSetIds(WorkoutRepository repository) async => [
  for (final observation in await sortedObservations(repository, _bench))
    if (observation.metricId == MetricIds.reps) observation.id,
];

Future<List<String>> _effortIds(WorkoutRepository repository) async => [
  for (final effort in await importedEfforts(repository, _capId)) effort.id,
];

Future<List<String>> _roundIds(WorkoutRepository repository) async => [
  for (final round in await repository.getRoundInstances(_bjj)) round.id,
];

Future<List<String>> _timedIds(WorkoutRepository repository) async => [
  for (final instance in await repository.getTimedInstances(_run)) instance.id,
];

Future<SensorSummary?> _summary(WorkoutRepository repository, String id) async {
  for (final summary in await repository.getSensorSummariesForSession(_capId)) {
    if (summary.id == id) return summary;
  }
  return null;
}

Map<String, Object?> _summaryValues(SensorSummary? summary) => {
  'avgHeartRateBpm': summary?.avgHeartRateBpm,
  'maxHeartRateBpm': summary?.maxHeartRateBpm,
  'steps': summary?.steps,
};

/// The entry ids the inbox has stamped applied: the watermark an edit session
/// taken now would carry.
Future<Set<String>> _appliedIds(WorkoutRepository repository) async => {
  for (final row in await repository.getWatchInboxEntriesForSession(_capId))
    if (row.appliedAtMs != null) row.entryId,
};

/// Every row the session holds, inbox included.
Future<Map<String, Object?>> _rows(WorkoutRepository repository) =>
    importedRows(repository, _capId);

void main() {
  for (final factory in <_Store Function()>[_MockStore.new, _HiveStore.new]) {
    final name = factory().name;

    group('PR 3d $name: a late wrist entry and Edit Session Discard', () {
      late _Store store;

      setUp(() => store = factory());

      tearDown(() => store.close());

      test(
        'S-1401 $name: a late wrist set survives Discard and the user\'s own '
        'set does not',
        () async {
          final label = 'S-1401 $name';
          final session = await _import(store, without: {_eSet3});
          expect(
            await _benchSets(session.repository),
            2,
            reason: '$label: the import holds two sets',
          );

          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await _deliver(session.inbox, _eSet3, tag: 'late');
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the wrist\'s late set is applied before the edit',
          );

          await workout.addEntry(_bench);
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            4,
            reason: '$label: the user added a set',
          );

          await _discard(workout, snapshot);

          expect(
            await _benchSets(session.repository),
            3,
            reason:
                '$label: the wrist\'s three sets — the late entry survives '
                'Discard',
          );
          expect(
            await _setAt(session.repository, 2),
            [5, 80.0],
            reason: '$label: the third set is the wrist\'s, as it sent it',
          );
          expect(
            await _setAt(session.repository, 3),
            [null, null],
            reason: '$label: the user\'s added set is gone',
          );
        },
      );

      test('S-1402 $name: a late entry that creates a new effort brings its '
          'instance and its summary', () async {
        final label = 'S-1402 $name';
        final session = await _import(store, without: {_eRun});
        expect(
          await _effortIds(session.repository),
          unorderedEquals([_bjj, _bench]),
          reason: '$label: the import holds no run',
        );

        final (:workout, :snapshot) = await _enterEditMode(
          session.repository,
          recovery: session.inbox,
        );

        await _deliver(session.inbox, _eRun, tag: 'late');
        await _reload(workout);
        expect(
          await _effortIds(session.repository),
          unorderedEquals([_run, _bjj, _bench]),
          reason: '$label: the run arrives and becomes history',
        );
        expect(
          await _timedIds(session.repository),
          [WatchSessionImporter.timedInstanceIdFor(_capId, _eRun)],
          reason: '$label: the run has its instance',
        );

        await workout.addEntry(_bench);
        await _reload(workout);
        expect(
          await _benchSets(session.repository),
          4,
          reason: '$label: the user added a set to the bench',
        );

        await _discard(workout, snapshot);

        expect(
          await _effortIds(session.repository),
          unorderedEquals([_run, _bjj, _bench]),
          reason: '$label: the late run effort is back',
        );
        expect(await _timedIds(session.repository), [
          WatchSessionImporter.timedInstanceIdFor(_capId, _eRun),
        ], reason: '$label: with its instance');
        expect(
          _summaryValues(await _summary(session.repository, _runSummary)),
          {'avgHeartRateBpm': 140, 'maxHeartRateBpm': 160, 'steps': 3200},
          reason: '$label: and with the summary the wrist measured for it',
        );
        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: the wrist\'s sets, and not the user\'s added one',
        );
      });

      test(
        'S-1403 $name: a late entry the user deleted during edit mode returns',
        () async {
          final label = 'S-1403 $name';
          final session = await _import(store);
          await expectCaptureImport(
            session.repository,
            captureExpectedImport('full'),
            receiptedEntryIds: session.transport.receiptedEntryIds,
            reasonPrefix: '$label: the fixture',
          );
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the import holds three sets',
          );

          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await workout.deleteEntry(_bench, 2);
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            2,
            reason: '$label: the user deleted the third set',
          );

          await _discard(workout, snapshot);

          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: Discard undoes the user\'s deletion',
          );
          expect(
            await _setAt(session.repository, 2),
            [5, 80.0],
            reason: '$label: and the set is the wrist\'s again',
          );
        },
      );

      test('S-1404 $name: a late entry the user edited returns as the wrist '
          'sent it', () async {
        final label = 'S-1404 $name';
        final session = await _import(store, without: {_eSet3});
        final (:workout, :snapshot) = await _enterEditMode(
          session.repository,
          recovery: session.inbox,
        );

        await _deliver(session.inbox, _eSet3, tag: 'late');
        await _reload(workout);
        expect(
          await _setAt(session.repository, 2),
          [5, 80.0],
          reason: '$label: the late set is applied before the edit',
        );

        await workout.updateEntryValue(_bench, 2, 'reps', 12);
        await _reload(workout);
        expect(
          await _setAt(session.repository, 2),
          [12, 80.0],
          reason: '$label: the user\'s edit of the late set reached it',
        );

        await _discard(workout, snapshot);

        expect(
          await _setAt(session.repository, 2),
          [5, 80.0],
          reason:
              '$label: the late set reads the wrist\'s reps, not the '
              'user\'s 12',
        );
        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: the late set is still there',
        );
      });

      test('S-1405 $name: two late entries both return', () async {
        final label = 'S-1405 $name';
        final session = await _import(store, without: {_eSet3, _eR3});
        expect(
          await _benchSets(session.repository),
          2,
          reason: '$label: the import holds two sets',
        );
        expect(
          await _roundIds(session.repository),
          [
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r1'),
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r2'),
          ],
          reason: '$label: the import holds two rounds',
        );

        final (:workout, :snapshot) = await _enterEditMode(
          session.repository,
          recovery: session.inbox,
        );

        await _deliver(session.inbox, _eSet3, tag: 'late-set');
        await _deliver(session.inbox, _eR3, tag: 'late-round');
        await _reload(workout);
        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: both late entries are applied',
        );
        expect(
          await _roundIds(session.repository),
          [
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r1'),
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r2'),
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r3'),
          ],
          reason: '$label: the late round is applied',
        );

        await workout.addEntry(_bench);
        await _reload(workout);
        expect(
          await _benchSets(session.repository),
          4,
          reason: '$label: the user added a set',
        );

        await _discard(workout, snapshot);

        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: the wrist\'s three sets are back',
        );
        expect(
          await _roundIds(session.repository),
          [
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r1'),
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r2'),
            WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r3'),
          ],
          reason: '$label: and the wrist\'s three rounds',
        );
        expect(
          await _setAt(session.repository, 3),
          [null, null],
          reason: '$label: the user\'s added set is gone',
        );
      });

      test(
        'S-1406 $name: a second sync after Discard duplicates nothing',
        () async {
          final label = 'S-1406 $name';
          final session = await _import(store, without: {_eSet3});
          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await _deliver(session.inbox, _eSet3, tag: 'late');
          await _reload(workout);
          await workout.addEntry(_bench);
          await _reload(workout);

          await _discard(workout, snapshot);

          final before = await _benchSetIds(session.repository);
          final rowsBefore = await _rows(session.repository);

          // The wrist re-sends the entry it never got a receipt for, and a
          // settle runs for the session.
          await _deliver(session.inbox, _eSet3, tag: 'resend');
          await session.inbox.resume();

          final after = await _benchSetIds(session.repository);
          expect(
            after,
            before,
            reason: '$label: no row is duplicated, and none is renumbered',
          );
          expect(
            await _rows(session.repository),
            rowsBefore,
            reason: '$label: the session holds exactly what it held',
          );
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the wrist\'s three sets, once each',
          );
          expect(
            await _effortIds(session.repository),
            unorderedEquals([_run, _bjj, _bench]),
            reason: '$label: and no second effort appears',
          );
        },
      );

      test(
        'S-1407 $name: Discard with no structural change is a no-op',
        () async {
          final label = 'S-1407 $name';
          final session = await _import(store, without: {_eSet3});
          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await _deliver(session.inbox, _eSet3, tag: 'late');
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the late set is applied',
          );

          // The user made no structural change, so `_discardEditChanges`
          // never calls the restore.
          await _discard(workout, snapshot, structuralChanges: false);

          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the late entry was never at risk',
          );
          expect(
            await _setAt(session.repository, 2),
            [5, 80.0],
            reason: '$label: and still reads as the wrist sent it',
          );
        },
      );

      test(
        'S-1408 $name: Save keeps the late entry and the user\'s edits',
        () async {
          final label = 'S-1408 $name';
          final session = await _import(store, without: {_eSet3});
          final (:workout, snapshot: _) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await _deliver(session.inbox, _eSet3, tag: 'late');
          await _reload(workout);
          await workout.addEntry(_bench);
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            4,
            reason: '$label: the wrist\'s three sets and the user\'s',
          );

          // Save: the screen flushes its metric buffer, finishes every round
          // and drops the snapshot. Nothing is restored.
          await workout.normalizeRoundsToFinished();
          expect(workout.error, isNull, reason: '$label: the edit is saved');

          expect(
            await _benchSets(session.repository),
            4,
            reason: '$label: the late entry and the user\'s edit are both kept',
          );
          expect(
            await _setAt(session.repository, 2),
            [5, 80.0],
            reason: '$label: the late set is still the wrist\'s',
          );
        },
      );

      test(
        'S-1409 $name: a deletion applied before edit mode stays deleted',
        () async {
          final label = 'S-1409 $name';
          final session = await _import(store);
          await session.inbox.stagePhoneChanges(
            _phoneChange('chg-1409-delete', {
              'kind': 'delete_entry',
              'entryId': _eSet3,
            }),
          );
          expect(
            await _benchSets(session.repository),
            2,
            reason: '$label: the phone\'s deletion is applied before the edit',
          );
          expect(
            await _appliedIds(session.repository),
            contains(WatchInboxEntry.phoneChangeId('chg-1409-delete', 0)),
            reason: '$label: and it is in the watermark',
          );

          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
          );

          await workout.addEntry(_bench);
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the user added a set',
          );

          await _discard(workout, snapshot);

          expect(
            await _benchSets(session.repository),
            2,
            reason: '$label: the deleted set does not come back',
          );

          await _deliver(session.inbox, _eSet3, tag: 'resend');
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            2,
            reason: '$label: and a later wrist re-send does not bring it back',
          );
        },
      );

      test(
        'S-1410 $name: a late phone correction and a late phone deletion are '
        'recovered too',
        () async {
          final label = 'S-1410 $name';

          // Fixture A — a correction the phone applied after the snapshot.
          final a = await _import(store);
          final first = await _enterEditMode(a.repository, recovery: a.inbox);
          await a.inbox.stagePhoneChanges(
            _phoneChange('chg-1410-correct', {
              'kind': 'correct_entry',
              'entryId': _eSet2,
              'correction': {'reps': 9},
            }),
          );
          await _reload(first.workout);
          expect(
            await _setAt(a.repository, 1),
            [9, 80.0],
            reason: '$label A: the correction is applied before the edit',
          );

          await first.workout.addEntry(_bench);
          await _reload(first.workout);
          await _discard(first.workout, first.snapshot);

          expect(
            await _setAt(a.repository, 1),
            [9, 80.0],
            reason: '$label A: the corrected reps are re-imported, not undone',
          );
          expect(
            await _benchSets(a.repository),
            3,
            reason: '$label A: and the wrist\'s three sets are back',
          );

          // Fixture B — a deletion the phone applied after the snapshot. A
          // fresh store, because Hive caches open boxes process-wide.
          await store.close();
          final b = await _import(store);
          final second = await _enterEditMode(b.repository, recovery: b.inbox);
          await b.inbox.stagePhoneChanges(
            _phoneChange('chg-1410-delete', {
              'kind': 'delete_entry',
              'entryId': _eSet3,
            }),
          );
          await _reload(second.workout);
          expect(
            await _benchSets(b.repository),
            2,
            reason: '$label B: the deletion is applied before the edit',
          );

          await second.workout.addEntry(_bench);
          await _reload(second.workout);
          await _discard(second.workout, second.snapshot);

          expect(
            await _benchSets(b.repository),
            2,
            reason: '$label B: the late deletion is re-applied',
          );
          expect(
            await _setAt(b.repository, 2),
            [null, null],
            reason: '$label B: the deleted set is gone',
          );
        },
      );

      test('S-1413 $name: a session with no late entry is untouched by the '
          'recovery', () async {
        final label = 'S-1413 $name';
        final session = await _import(store);
        final (:workout, :snapshot) = await _enterEditMode(
          session.repository,
          recovery: session.inbox,
        );
        final appliedBefore = await _appliedIds(session.repository);

        await workout.addEntry(_bench);
        await _reload(workout);
        expect(
          await _benchSets(session.repository),
          4,
          reason: '$label: the user added a set',
        );

        await _discard(workout, snapshot);

        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: the wrist\'s three sets, and not the user\'s',
        );
        expect(
          await _appliedIds(session.repository),
          appliedBefore,
          reason: '$label: no inbox row\'s applied stamp changed',
        );
      });

      test(
        'S-1414 $name: a snapshot taken with no watermark recovers nothing',
        () async {
          final label = 'S-1414 $name';
          final session = await _import(store, without: {_eSet3});
          final (:workout, :snapshot) = await _enterEditMode(
            session.repository,
            recovery: session.inbox,
            watermark: false,
          );

          await _deliver(session.inbox, _eSet3, tag: 'late');
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            3,
            reason: '$label: the late set is applied before the edit',
          );

          await workout.addEntry(_bench);
          await _reload(workout);
          expect(
            await _benchSets(session.repository),
            4,
            reason: '$label: the user added a set',
          );

          await _discard(workout, snapshot);

          expect(
            await _benchSets(session.repository),
            2,
            reason:
                '$label: a null watermark means no recovery — the pre-fix '
                'behaviour, deliberately preserved',
          );
        },
      );
    });
  }

  // S-1415 — the screen's own watermark capture. The scenarios above drive the
  // state layer directly, so they stay green if the screen stops reading the
  // watermark; this group drives the real `WorkoutSessionScreen` and Discards
  // through the screen's own path, so that regression fails here.
  //
  // Mock only: a Hive store seeded inside a `testWidgets` body hangs the suite.
  group('PR 3d Mock: the screen reads the watermark (S-1415)', () {
    testWidgets(
      'S-1415 Mock: the real screen recovers a late wrist set on Discard',
      (tester) async {
        final label = 'S-1415 Mock';
        await tester.binding.setSurfaceSize(const Size(600, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final session = await _import(_MockStore(), without: {_eSet3});
        expect(
          await _benchSets(session.repository),
          2,
          reason: '$label: the import holds two sets',
        );

        final workout = WorkoutState(
          session.repository,
          watchLateEntryRecovery: session.inbox,
        );
        // The screen raises two coach marks the first time an exercise is
        // opened ("View exercise info", then "Add notes for this exercise"),
        // each behind a modal backdrop that would absorb the tap below. Mark
        // both seen before the screen mounts so neither appears.
        await workout.markExerciseInfoHintSeen();
        await workout.markExerciseNotesHintSeen();
        await workout.loadHistoricalSession(_capId);

        final settingsState = SettingsState(
          session.repository,
          fakePreferencesService(),
        );
        await settingsState.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: WorkoutSessionScreen(
              workoutState: workout,
              routineState: RoutineState(session.repository),
              sessionSummaryService: SessionSummaryService(
                session.repository,
              ),
              timerAlertService: FakeTimerAlertService(),
              settingsState: settingsState,
              editMode: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The screen has entered edit mode: it read the watermark and took the
        // snapshot. The late set now arrives, as the wrist's re-send does.
        await _deliver(session.inbox, _eSet3, tag: 'late');
        expect(
          await _benchSets(session.repository),
          3,
          reason: '$label: the late set is applied while the screen is open',
        );

        // The state layer reloads, as the app's history refresh does, so the
        // next entry the user adds is numbered above the wrist's.
        await _reload(workout);

        // The user's own structural change, through the screen: open the bench
        // and add a set.
        await tester.tap(find.text('Barbell Bench Press').first);
        await tester.pumpAndSettle();

        final addSet = find.byIcon(Icons.add);
        await tester.ensureVisible(addSet);
        await tester.tap(addSet);
        await tester.pumpAndSettle();
        expect(
          await _benchSets(session.repository),
          4,
          reason: '$label: the user added a set',
        );

        // Back to the list, then Back again: the unsaved-changes dialog.
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back).first);
        await tester.pumpAndSettle();
        expect(
          find.text('Unsaved changes'),
          findsOneWidget,
          reason: '$label: the screen asks before discarding',
        );

        // Discard, through the screen's own path.
        await tester.tap(
          find.byKey(const Key('session-edit-unsaved-discard')),
        );
        await tester.pumpAndSettle();

        expect(
          await _benchSets(session.repository),
          3,
          reason:
              '$label: the wrist\'s three sets — the screen read the '
              'watermark before the rows',
        );
        expect(
          await _setAt(session.repository, 2),
          [5, 80.0],
          reason: '$label: the third set is the wrist\'s, as it sent it',
        );
      },
    );
  });
}
