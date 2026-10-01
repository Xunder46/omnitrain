// Stats PR 3b, Phase 2 — the import records where a distance came from, and a
// new timed entry never reuses an instance id.
//
// The wire carries `distanceSource` on a timed entry that also carries
// `distanceMeters` (D-334). The import stores it, or `entered` when the watch
// sent none — a watch session never runs GPS, so a distance that arrives
// without a source was dialled by hand (D-335). A distance the phone wrote is
// never rewritten by a later sync, in value or in source (D-336).
//
// Scenarios S-876, S-877, S-878 and S-880 of
// `docs/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/utils/distance_source.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart' hide seedExercise;

const String _sessionId = 's-ds';

/// The phone's clock: fixed, so every stamp the inbox writes is the same.
final DateTime _phoneNow = DateTime.utc(2026, 9, 27, 11);

Future<MockWorkoutRepository> _repository() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedCaptureCatalog(repository);
  return repository;
}

WatchSessionInbox _inbox(
  WorkoutRepository repository,
  CaptureTransport transport,
) {
  var ids = 0;
  return WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: loadProtocolValidator(),
    clock: () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    // A failure inside the inbox fails the test where it happened.
    onFailure: Error.throwWithStackTrace,
  );
}

/// Delivers [events] one envelope each.
Future<void> _deliverEach(
  WatchSessionInbox inbox,
  List<Map<String, Object?>> events, {
  String tag = 'a',
}) async {
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_sessionId, [events[i]], messageId: 'msg-$tag-$i'),
    );
  }
}

/// A timed event in the protocol's shape. The window is the twenty minutes
/// before [loggedAt], and `eventId` equals `entryId`.
Map<String, Object?> _timed(
  String entryId, {
  required String loggedAt,
  num? distanceMeters,
  String? distanceSource,
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
    'distanceSource': ?distanceSource,
  };
}

Map<String, Object?> _end() => {
  'entryId': 'end-$_sessionId',
  'eventId': 'end-$_sessionId',
  'kind': 'session_end',
  'loggedAt': '2026-09-27T11:30:00Z',
  'startedAt': '2026-09-27T10:00:00Z',
  'endedAt': '2026-09-27T11:30:00Z',
  'status': 'completed',
};

/// The run effort's id, as the import names it.
String get _run =>
    WatchSessionImporter.effortIdFor(_sessionId, 'sx-run', 'ex-run', 'timed');

/// Each of the run's distance rows as (metres, raw source), in entry order.
///
/// The raw stored source, not the one the readers resolve to, so a row that
/// arrived with no source reads null here (S-876, S-877, M4).
Future<List<(double, String?)>> _storedDistances(
  WorkoutRepository repository,
) async => [
  for (final row in EntryRows.ordered(
    await storedRows(repository, _run, MetricIds.distance),
  ))
    ((row.valueReal ?? 0.0), row.valueSource),
];

/// What the phone reads for the run's distances: metres and the source the
/// reader resolves, in entry order.
List<(double, String)> _readDistances(WorkoutState workout) => [
  for (final entry in workout.getEffortDistanceEntries(_run))
    (entry.metres, DistanceSource.resolve(entry.row?.valueSource)),
];

void main() {
  // ─── S-876 / S-877: the import records the source ────────────────────────

  test('S-876 the import stores each source the watch sent', () async {
    final repository = await _repository();
    final inbox = _inbox(repository, CaptureTransport());

    await _deliverEach(inbox, [
      _timed(
        'e-g',
        loggedAt: '2026-09-27T10:30:00Z',
        distanceMeters: 5000,
        distanceSource: 'gps',
      ),
      _timed(
        'e-n',
        loggedAt: '2026-09-27T10:52:00Z',
        distanceMeters: 3000,
        distanceSource: 'entered',
      ),
      _timed(
        'e-s',
        loggedAt: '2026-09-27T11:14:00Z',
        distanceMeters: 4200,
        distanceSource: 'estimated',
      ),
      _end(),
    ]);

    expect(await _storedDistances(repository), [
      (5000.0, EffortObservation.sourceGps),
      (3000.0, EffortObservation.sourceEntered),
      (4200.0, EffortObservation.sourceEstimated),
    ]);
  });

  test(
    'S-877 a dialled distance is stored as entered; no distance gets no source',
    () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      await _deliverEach(inbox, [
        _timed('e-d', loggedAt: '2026-09-27T10:30:00Z', distanceMeters: 2500),
        _timed('e-z', loggedAt: '2026-09-27T10:52:00Z'),
        _end(),
      ]);

      expect(await _storedDistances(repository), [
        (2500.0, EffortObservation.sourceEntered),
        (0.0, null),
      ]);
    },
  );

  test('S-880 a new timed entry never reuses an instance id', () {
    expect(
      TimerManager.uniqueTimedInstanceId(
        existingIds: const ['timed-e-t-1-1000'],
        effortId: 'e-t',
        entryIndex: 1,
        nowMs: 1000,
      ),
      'timed-e-t-1-1001',
    );
    expect(
      TimerManager.uniqueTimedInstanceId(
        existingIds: const ['timed-e-t-1-1000', 'timed-e-t-1-1001'],
        effortId: 'e-t',
        entryIndex: 1,
        nowMs: 1000,
      ),
      'timed-e-t-1-1002',
    );
    expect(
      TimerManager.uniqueTimedInstanceId(
        existingIds: const [],
        effortId: 'e-t',
        entryIndex: 1,
        nowMs: 1000,
      ),
      'timed-e-t-1-1000',
    );
  });
  // ─── S-880: the writer, not only the helper ──────────────────────────────

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the timed entry writer', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-880 an add after a delete in the same millisecond does not '
          'reuse the id', () async {
        // The clock stands still, so every add names the same millisecond:
        // the third call (the add after the delete) repeats the count and
        // the millisecond of the instance the delete left behind, which is
        // the collision D-338 exists for.
        final timer = TimerManager(
          repo,
          notify: () {},
          setError: (_) {},
          clearError: () {},
          clock: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        );

        await timer.addTimedEntry('e-t');
        await timer.addTimedEntry('e-t');
        await timer.deleteTimedEntry('e-t', 0);
        await timer.addTimedEntry('e-t');

        final ids = [
          for (final held in await repo.getTimedInstances('e-t')) held.id,
        ];
        expect(ids, hasLength(2), reason: 'S-880 two entries are left');
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: 'S-880 no two entries hold the same id, got $ids',
        );
      });
    });
  }

  // ─── S-878: a phone-written distance survives every later sync ───────────

  for (final factory in harnessFactories) {
    final harness = factory();

    group(
      '${harness.name} — a later sync leaves the phone’s distance alone',
      () {
        late WorkoutRepository repo;
        late WatchSessionInbox inbox;

        setUp(() async {
          repo = await harness.open();
          await seedCaptureCatalog(repo);
          inbox = _inbox(repo, CaptureTransport());
        });
        tearDown(() async => await harness.close());

        test(
          'S-878 a redelivery and a move keep its value and its source',
          () async {
            final redelivered = _timed(
              'e-r',
              loggedAt: '2026-09-27T10:30:00Z',
              distanceMeters: 3000,
              distanceSource: 'estimated',
            );
            await _deliverEach(inbox, [redelivered, _end()]);

            // The phone loads the imported session and corrects the distance.
            var workout = WorkoutState(repo);
            await workout.loadHistoricalSession(_sessionId);
            await workout.setEntryDistance(_run, 0, 5200.0);
            expect(
              await _storedDistances(repo),
              [(5200.0, EffortObservation.sourceEntered)],
              reason: 'S-878 the phone wrote 5200, recorded as entered',
            );

            // (a) The same event arrives again under a new messageId.
            await _deliverEach(inbox, [redelivered], tag: 'again');
            expect(
              await _storedDistances(repo),
              [(5200.0, EffortObservation.sourceEntered)],
              reason: 'S-878 a redelivery changes nothing',
            );

            // (b) A late entry logs before it, which moves e-r to entry 1.
            await _deliverEach(inbox, [
              _timed(
                'e-early',
                loggedAt: '2026-09-27T10:05:00Z',
                distanceMeters: 1000,
              ),
            ], tag: 'late');

            workout = WorkoutState(repo);
            await workout.loadHistoricalSession(_sessionId);
            expect(
              await _storedDistances(repo),
              [
                (1000.0, EffortObservation.sourceEntered),
                (5200.0, EffortObservation.sourceEntered),
              ],
              reason:
                  'S-878 the moved row keeps the value and the source it had',
            );
            expect(
              _readDistances(workout),
              [
                (1000.0, EffortObservation.sourceEntered),
                (5200.0, EffortObservation.sourceEntered),
              ],
              reason: 'S-878 and the reader pairs them with the same entries',
            );
          },
        );
      },
    );
  }
}
