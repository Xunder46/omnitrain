// F-1 (Stats PR 2 code review): leaving history edit mode with Discard returns
// an imported wrist session to exactly the sensor summaries it had before the
// edit; Save keeps D-131's loss.
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
// `## Feedback`, F-1 (A-70, O-15).
//
// Edit mode writes structural changes straight to the repository, and Discard
// undoes them with `WorkoutState.restoreSessionSnapshot`, which deletes and
// re-creates efforts, timed instances and round instances. D-131 deletes a
// summary together with its target, so the live edit (deleting a round,
// removing an exercise) and the restore itself both take summaries with them.
// Re-creating a row does not bring its summary back; the snapshot has to carry
// the summaries.
//
// Every case imports F-CAP's `full` case (`watch/contract/
// watch_capture_contract.json`) and runs on `MockWorkoutRepository` and on
// `HiveWorkoutRepository` (a temp directory, read back after a restart). The
// state calls are the edit screen's: `loadHistoricalSession` (opened from
// history), `loadSessionData` then `snapshotSessionState` (edit mode entered),
// the structural edit, then `restoreSessionSnapshot` (Discard) or, for Save,
// `normalizeRoundsToFinished` and no restore.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/session_edit_snapshot.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _capId = 's-cap-1';

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

const String _sessionSummary = 'sensor-session-s-cap-1';
const String _benchSummary =
    'sensor-effort-effort-s-cap-1-sx-bench-ex-bench-set';
const String _runSummary = 'sensor-timed_instance-timed-s-cap-1-e-run';
const String _round1Summary = 'sensor-round_instance-round-s-cap-1-e-r1';
const String _round2Summary = 'sensor-round_instance-round-s-cap-1-e-r2';
const String _round3Summary = 'sensor-round_instance-round-s-cap-1-e-r3';

/// A summary as these tests compare it: its id and what the wrist measured.
Map<String, Object?> _summary(
  String id,
  double avgHeartRateBpm,
  double maxHeartRateBpm, {
  int? steps,
}) => {
  'id': id,
  'avgHeartRateBpm': avgHeartRateBpm,
  'maxHeartRateBpm': maxHeartRateBpm,
  'steps': steps,
};

/// F-CAP's six summaries after the import, in the order the repository lists
/// them (scope, then window start).
final List<Map<String, Object?>> _fCapSummaries = [
  _summary(_sessionSummary, 143, 180),
  _summary(_benchSummary, 130, 150),
  _summary(_runSummary, 140, 160, steps: 3200),
  _summary(_round1Summary, 160, 170),
  _summary(_round2Summary, 165, 180),
  _summary(_round3Summary, 155, 165),
];

List<Map<String, Object?>> _fCapWithout(String id) => [
  for (final summary in _fCapSummaries)
    if (summary['id'] != id) summary,
];

Future<List<SensorSummary>> _summaries(WorkoutRepository repository) =>
    repository.getSensorSummariesForSession(_capId);

List<Map<String, Object?>> _values(List<SensorSummary> summaries) => [
  for (final s in summaries)
    {
      'id': s.id,
      'avgHeartRateBpm': s.avgHeartRateBpm,
      'maxHeartRateBpm': s.maxHeartRateBpm,
      'steps': s.steps,
    },
];

/// Every stored field, window and creation stamp included.
List<Map<String, dynamic>> _rows(List<SensorSummary> summaries) => [
  for (final s in summaries) s.toMap(),
];

/// Stand-in for the path_provider channel, which has no implementation under
/// `flutter_test` (same pattern as `test/watch_capture_contract_test.dart`).
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

/// One repository implementation, reopened over the same storage as an app
/// restart would.
abstract class _Store {
  String get name;
  Future<WorkoutRepository> open();
  Future<WorkoutRepository> restart();
  Future<void> close();
}

class _MockStore implements _Store {
  MockWorkoutRepository? _repository;

  @override
  String get name => 'Mock';

  @override
  Future<WorkoutRepository> open() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    return _repository = repository;
  }

  /// In-memory storage has no restart: the same store comes back.
  @override
  Future<WorkoutRepository> restart() async => _repository!;

  @override
  Future<void> close() async {}
}

class _HiveStore implements _Store {
  Directory? _dir;

  @override
  String get name => 'Hive';

  @override
  Future<WorkoutRepository> open() async {
    final dir = await Directory.systemTemp.createTemp(
      'watch_edit_restore_summaries_',
    );
    _dir = dir;
    _PathProviderChannel.install(dir);
    Hive.init(dir.path);
    final repository = HiveWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  @override
  Future<WorkoutRepository> restart() async {
    await Hive.close();
    final repository = HiveWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  @override
  Future<void> close() async {
    await Hive.deleteFromDisk();
    final dir = _dir;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Opens [store] and imports F-CAP's `full` case the way a wrist delivers
/// it: one `observations_up` per stored event.
Future<WorkoutRepository> _importFullCase(_Store store) async {
  final repository = await store.open();
  await seedCaptureCatalog(repository);
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => DateTime.utc(2026, 9, 25, 11),
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
  );
  final events = captureEvents('full');
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_capId, [events[i]], messageId: 'msg-$i'),
    );
  }
  return repository;
}

/// The imported session opened from history, then edit mode entered: the
/// edit screen reloads the session and snapshots it.
Future<({WorkoutState workout, SessionEditSnapshot snapshot})> _enterEditMode(
  WorkoutRepository repository,
) async {
  final workout = WorkoutState(repository);
  await workout.loadHistoricalSession(_capId);
  await workout.loadSessionData();
  expect(workout.error, isNull, reason: 'the session loads');
  final snapshot = workout.snapshotSessionState();
  expect(snapshot, isNotNull, reason: 'edit mode holds a snapshot');
  return (workout: workout, snapshot: snapshot!);
}

Future<int> _benchSets(WorkoutRepository repository) async => [
  for (final o in await repository.getEffortObservations(_bench))
    if (o.metricId == MetricIds.reps) o,
].length;

Future<List<String>> _bjjRounds(WorkoutRepository repository) async => [
  for (final r in await repository.getRoundInstances(_bjj)) r.id,
];

Future<List<String>> _effortIds(WorkoutRepository repository) async => [
  for (final e in await importedEfforts(repository, _capId)) e.id,
];

/// One structural edit made in edit mode.
class _Edit {
  const _Edit({
    required this.name,
    required this.apply,
    required this.tookEffect,
    required this.summariesAfterEdit,
  });

  final String name;
  final Future<void> Function(WorkoutState workout) apply;

  /// Checks that the edit reached the repository, so a Discard that
  /// restores the summaries is restoring something.
  final Future<void> Function(WorkoutRepository repository, String label)
  tookEffect;

  /// What the repository holds right after the edit, before Discard or Save.
  final List<Map<String, Object?>> summariesAfterEdit;
}

final List<_Edit> _edits = [
  _Edit(
    name: 'add a set to the bench',
    apply: (workout) => workout.addEntry(_bench),
    tookEffect: (repository, label) async {
      expect(
        await _benchSets(repository),
        4,
        reason: '$label: the bench holds a fourth set',
      );
    },
    // Adding a set deletes nothing; the restore's own deletes are what used
    // to take the run's and the rounds' summaries.
    summariesAfterEdit: _fCapSummaries,
  ),
  _Edit(
    name: 'delete round 1 of the BJJ',
    apply: (workout) => workout.deleteEntry(_bjj, 0),
    tookEffect: (repository, label) async {
      expect(await _bjjRounds(repository), [
        WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r2'),
        WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r3'),
      ], reason: '$label: round 1 is deleted');
    },
    // D-131: the round's summary went with the round, live.
    summariesAfterEdit: _fCapWithout(_round1Summary),
  ),
  _Edit(
    name: 'remove the bench',
    apply: (workout) => workout.removeExerciseFromSession(_bench),
    tookEffect: (repository, label) async {
      expect(await _effortIds(repository), [
        _run,
        _bjj,
      ], reason: '$label: the bench is removed');
    },
    // D-131: the bench's summary went with the effort, live.
    summariesAfterEdit: _fCapWithout(_benchSummary),
  ),
];

void main() {
  for (final store in <_Store Function()>[_MockStore.new, _HiveStore.new]) {
    final name = store().name;

    group('F-1 $name: Discard returns the summaries the session had', () {
      for (final edit in _edits) {
        test('F-1 $name: ${edit.name}, then Discard — the six summaries are '
            'back, unchanged, and survive a restart', () async {
          final label = 'F-1 $name ${edit.name}';
          final s = store();
          addTearDown(s.close);
          final repository = await _importFullCase(s);

          final (:workout, :snapshot) = await _enterEditMode(repository);
          final before = await _summaries(repository);
          expect(
            _values(before),
            _fCapSummaries,
            reason: '$label: the import holds F-CAP\'s six summaries',
          );

          await edit.apply(workout);
          expect(workout.error, isNull, reason: '$label: the edit is made');
          await edit.tookEffect(repository, label);
          expect(
            _values(await _summaries(repository)),
            edit.summariesAfterEdit,
            reason: '$label: the summaries right after the edit',
          );

          await workout.restoreSessionSnapshot(snapshot);
          expect(workout.error, isNull, reason: '$label: Discard restores');

          final after = await _summaries(repository);
          expect(
            _values(after),
            _fCapSummaries,
            reason: '$label: Discard brings back every summary, same values',
          );
          expect(
            _rows(after),
            _rows(before),
            reason: '$label: every stored field is as it was before the edit',
          );

          // The restore itself ran: the rows the summaries target are back.
          expect(await _effortIds(repository), [
            _run,
            _bjj,
            _bench,
          ], reason: '$label: efforts restored');
          expect(
            await _benchSets(repository),
            3,
            reason: '$label: bench sets restored',
          );
          expect(await _bjjRounds(repository), [
            for (final entryId in const ['e-r1', 'e-r2', 'e-r3'])
              WatchSessionImporter.roundInstanceIdFor(_capId, entryId),
          ], reason: '$label: rounds restored');
          expect(
            [for (final t in await repository.getTimedInstances(_run)) t.id],
            [WatchSessionImporter.timedInstanceIdFor(_capId, 'e-run')],
            reason: '$label: the run restored',
          );

          final reopened = await s.restart();
          expect(
            _rows(await _summaries(reopened)),
            _rows(before),
            reason: '$label: the restored summaries are stored, not cached',
          );
        });
      }
    });

    test('F-1 $name: delete round 1 of the BJJ, then Save — D-131 keeps that '
        'round\'s summary deleted and nothing else changes', () async {
      final label = 'F-1 $name Save';
      final s = store();
      addTearDown(s.close);
      final repository = await _importFullCase(s);

      final (:workout, snapshot: _) = await _enterEditMode(repository);
      final before = await _summaries(repository);
      expect(
        _values(before),
        _fCapSummaries,
        reason: '$label: the import holds F-CAP\'s six summaries',
      );

      await workout.deleteEntry(_bjj, 0);
      // Save: the screen flushes its (empty) metric buffer, finishes every
      // round and drops the snapshot. Nothing is restored.
      await workout.normalizeRoundsToFinished();
      expect(workout.error, isNull, reason: '$label: the edit is saved');

      final expected = [
        for (final row in _rows(before))
          if (row['id'] != _round1Summary) row,
      ];
      expect(
        _values(await _summaries(repository)),
        _fCapWithout(_round1Summary),
        reason: '$label: the deleted round\'s summary is gone (D-131)',
      );
      expect(
        _rows(await _summaries(repository)),
        expected,
        reason: '$label: the other five are exactly as they were',
      );

      final reopened = await s.restart();
      expect(
        _rows(await _summaries(reopened)),
        expected,
        reason: '$label: after a restart',
      );
    });

    test('F-1 $name: after that Save, a later edit and Discard do not bring '
        'the deleted round\'s summary back', () async {
      final label = 'F-1 $name Save, then Discard';
      final s = store();
      addTearDown(s.close);
      final repository = await _importFullCase(s);

      final (:workout, snapshot: _) = await _enterEditMode(repository);
      final before = await _summaries(repository);
      await workout.deleteEntry(_bjj, 0);
      await workout.normalizeRoundsToFinished();
      expect(workout.error, isNull, reason: '$label: the edit is saved');

      // Edit again from the Summary: the screen reloads the session and
      // takes a new snapshot, then the user adds a set and discards.
      await workout.loadSessionData();
      final again = workout.snapshotSessionState()!;
      await workout.addEntry(_bench);
      await workout.restoreSessionSnapshot(again);
      expect(workout.error, isNull, reason: '$label: Discard restores');

      expect(
        _rows(await _summaries(repository)),
        [
          for (final row in _rows(before))
            if (row['id'] != _round1Summary) row,
        ],
        reason:
            '$label: the five the Save kept, and no summary for a round '
            'that no longer exists',
      );
    });
  }
}
