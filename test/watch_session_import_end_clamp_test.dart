// Plan 164 — an end the phone receives from the wrist can no longer stretch a
// workout into the future. Every point where the importer applies an arriving
// end reads one bound: the phone's own clock at decision time plus
// `kFutureEndClampMs` (5 minutes). Created history, the D-14604 catch-up (the
// end moves out to the wrist's end or to a later set), and the catch-up that
// finds nothing to do all go through it.
//
// Scenario mapping (`docs/plans/2026-11-14-164-end-time-upper-bound-plan/`):
//   S-16404 a future wrist end is clamped at creation → `S-16404 ...`
//   S-16405 the catch-up clamps the end it moves      → `S-16405 ...`
//   S-16406 a future set stamp cannot pass the bound  → `S-16406 ...`
//   S-16407 a clamp never drags an end backward       → `S-16407 ...`
//   S-16408 the start floor: zero length, never less  → `S-16408 ...`
//   S-16409 a past end is a legitimate late sync      → `S-16409 ...`
//
// A separate file rather than a group in `test/watch_session_import_test.dart`
// because plan 160's run is editing that file (see the plan's Phase 2 item 4).
// Mock-first by construction, so nothing here needs Hive.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _sessionId = 'w-cap-1';
const String _slot = 'sx-bench';
const String _exerciseId = 'ex-bench';

/// The phone's clock at decision time — `T` in the plan.
final DateTime _now = DateTime.utc(2026, 9, 25, 12);

final int _t = _now.millisecondsSinceEpoch;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

Future<MockWorkoutRepository> _repository() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedExercise(
    repository,
    id: _exerciseId,
    name: 'Bench Press',
    capabilities: const ['reps', 'load'],
  );
  return repository;
}

/// A `session_end` event as the wrist sends it.
Map<String, Object?> _end({
  required int startedAtMs,
  required int endedAtMs,
  String status = 'completed',
}) => {
  'entryId': 'end-$_sessionId',
  'eventId': 'end-$_sessionId',
  'kind': 'session_end',
  'loggedAt': _iso(endedAtMs),
  'startedAt': _iso(startedAtMs),
  'endedAt': _iso(endedAtMs),
  'status': status,
};

/// One set event in the protocol's shape.
Map<String, Object?> _set(String entryId, {required int loggedAtMs}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': _iso(loggedAtMs),
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'reps': 5,
  'loadKg': 80,
};

/// A [HealthSyncService] that records the rewrites the inbox asks for, so a
/// test can read the `previousEndedAtMs` a moved end owes — the pass's own
/// `endMovedFromMs` (D-14634).
class _RewriteSpy extends HealthSyncService {
  _RewriteSpy(WorkoutRepository repository)
    : super(
        platform: _RecordingHealthPlatform(),
        repository: repository,
        isWriteEnabled: () => true,
        isReadEnabled: () => false,
      );

  final List<({TrainingSession session, int previousEndedAtMs})> rewrites = [];

  @override
  Future<void> rewriteWorkout(
    TrainingSession session, {
    required int previousEndedAtMs,
  }) async {
    rewrites.add((session: session, previousEndedAtMs: previousEndedAtMs));
  }
}

/// A Health platform that holds nothing: these scenarios are about the span the
/// phone re-writes, not about the store.
class _RecordingHealthPlatform implements HealthPlatformService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// The phone: history, the inbox that imports into it, and the rewrites it asks
/// for.
class _Phone {
  _Phone({
    required this.repository,
    required this.health,
    required this.inbox,
    required this.historyChanges,
  });

  final MockWorkoutRepository repository;
  final _RewriteSpy health;
  final WatchSessionInbox inbox;

  /// One entry per `onHistoryChanged` the inbox made (D-142).
  final List<int> historyChanges;

  bool get historyChanged => historyChanges.isNotEmpty;

  Future<TrainingSession?> session() => repository.getSession(_sessionId);

  /// Delivers [events] one envelope each, as the wrist sends them.
  Future<void> deliver(List<Map<String, Object?>> events) async {
    for (final event in events) {
      final entryId = event['entryId']! as String;
      await inbox.receive(
        observationsUp(_sessionId, [event], messageId: 'msg-$entryId'),
      );
    }
  }
}

Future<_Phone> _phone(MockWorkoutRepository repository) async {
  final health = _RewriteSpy(repository);
  final historyChanges = <int>[];
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: CaptureTransport(),
    validator: loadProtocolValidator(),
    clock: () => _now,
    idFactory: () => 'msg-clamp-${++ids}',
    healthSync: health,
    onHistoryChanged: () async => historyChanges.add(1),
    onFailure: Error.throwWithStackTrace,
  );
  return _Phone(
    repository: repository,
    health: health,
    inbox: inbox,
    historyChanges: historyChanges,
  );
}

/// `w-cap-1` already in history, ended at [endedAtMs].
Future<void> _seedHistory(
  MockWorkoutRepository repository, {
  required int endedAtMs,
}) async {
  await repository.createSession(
    TrainingSession(
      id: _sessionId,
      ownerUserId: LoggedEntryRows.ownerUserId,
      startedAtMs: endedAtMs - 1800000,
      endedAtMs: endedAtMs,
      createdAtMs: endedAtMs - 1800000,
      updatedAtMs: endedAtMs,
    ),
  );
}

void main() {
  group('S-164 the importer bounds an arriving end', () {
    test('S-16404 a future wrist end is clamped at creation', () async {
      final repository = await _repository();
      final phone = await _phone(repository);

      // A wrong watch clock: the workout is claimed to end a day from now.
      await phone.deliver([
        _end(startedAtMs: _t - 600000, endedAtMs: _t + 86400000),
        _set('set-1', loggedAtMs: _t + 400000),
      ]);

      final session = await phone.session();
      expect(
        session?.endedAtMs,
        _t + 300000,
        reason: 'S-16404 the created end is the bound, not the claimed instant',
      );
      expect(
        session?.updatedAtMs,
        _t + 300000,
        reason: 'S-16404 and the row\'s own stamp follows it',
      );
      expect(
        session?.startedAtMs,
        _t - 600000,
        reason: 'S-16404 the start is the wrist\'s own, untouched',
      );
      expect(
        await importedEfforts(repository, _sessionId),
        hasLength(1),
        reason: 'S-16404 clamp-and-keep: the frame\'s rows are imported',
      );
      final efforts = await importedEfforts(repository, _sessionId);
      expect(
        await sortedObservations(repository, efforts.single.id),
        isNotEmpty,
        reason: 'S-16404 the set behind the clamped end still lands',
      );
      expect(
        phone.historyChanged,
        isTrue,
        reason: 'S-16404 history changed, so the calendar is told',
      );
      expect(
        phone.health.rewrites,
        isEmpty,
        reason: 'S-16404 a created session owes no rewrite',
      );
    });

    test('S-16405 the catch-up clamps the end it moves', () async {
      final repository = await _repository();
      final historyEndMs = _t - 1800000;
      await _seedHistory(repository, endedAtMs: historyEndMs);
      final phone = await _phone(repository);

      await phone.deliver([
        _end(startedAtMs: _t - 1800000, endedAtMs: _t + 86400000),
        _set('set-1', loggedAtMs: _t + 400000),
      ]);

      expect(
        (await phone.session())?.endedAtMs,
        _t + 300000,
        reason: 'S-16405 the end moves to the bound, not to the claim',
      );
      expect(
        phone.health.rewrites,
        hasLength(1),
        reason: 'S-16405 a moved end still rewrites the window it hangs on',
      );
      expect(phone.health.rewrites.single.session.id, _sessionId);
      expect(
        phone.health.rewrites.single.session.endedAtMs,
        _t + 300000,
        reason: 'S-16405 the rewrite follows the bounded end',
      );
      expect(
        phone.health.rewrites.single.previousEndedAtMs,
        historyEndMs,
        reason: 'S-16405 and names the end the workout had (endMovedFromMs)',
      );
    });

    test('S-16406 a future set stamp cannot pass the bound', () async {
      final repository = await _repository();
      final historyEndMs = _t - 1800000;
      await _seedHistory(repository, endedAtMs: historyEndMs);
      final phone = await _phone(repository);

      // The end the wrist sent is the phone's own; a set stamped a day ahead is
      // what would push the end out (D-14604).
      await phone.deliver([
        _end(startedAtMs: _t - 1800000, endedAtMs: historyEndMs),
        _set('set-1', loggedAtMs: _t + 86400000),
      ]);

      expect(
        (await phone.session())?.endedAtMs,
        _t + 300000,
        reason: 'S-16406 the latest-over-sets end is bounded too',
      );
      expect(
        phone.health.rewrites.single.previousEndedAtMs,
        historyEndMs,
        reason: 'S-16406 the set moved the end, so it owes the rewrite',
      );
    });

    test('S-16407 a clamp never drags an end backward', () async {
      final repository = await _repository();
      // The phone's own clock was behind when it stored this end, so the row
      // already sits beyond what the bound allows now.
      final storedEndMs = _t + 600000;
      await _seedHistory(repository, endedAtMs: storedEndMs);
      final phone = await _phone(repository);

      await phone.deliver([
        _end(startedAtMs: _t - 1800000, endedAtMs: _t + 86400000),
      ]);

      expect(
        (await phone.session())?.endedAtMs,
        storedEndMs,
        reason: 'S-16407 the stored end is later than the bound, so it stands',
      );
      expect(
        phone.health.rewrites,
        isEmpty,
        reason: 'S-16407 nothing moved, so endMovedFromMs is null and no '
            'window is rewritten',
      );
      expect(
        (await phone.session())?.updatedAtMs,
        storedEndMs,
        reason: 'S-16407 the wrist\'s later claim loses to the phone\'s own end, '
            'so no end write touched the row',
      );
    });

    test('S-16408 a future start yields zero length, never a negative one',
        () async {
      final repository = await _repository();
      final phone = await _phone(repository);

      // A whole workout a day ahead: the bound would put the end before the
      // start, so the start is the floor (D-16408).
      final futureStartMs = _t + 86400000;
      await phone.deliver([
        _end(startedAtMs: futureStartMs, endedAtMs: futureStartMs + 600000),
        _set('set-1', loggedAtMs: futureStartMs + 300000),
      ]);

      final session = await phone.session();
      expect(
        session?.startedAtMs,
        futureStartMs,
        reason: 'S-16408 the wrist\'s own start is kept',
      );
      expect(
        session?.endedAtMs,
        futureStartMs,
        reason: 'S-16408 the end floors at the start: a zero-length row, no '
            'negative duration',
      );
    });

    test('S-16409 a past end is a legitimate late sync', () async {
      final repository = await _repository();
      final phone = await _phone(repository);

      // Started ~25 h ago, finished a day ago, syncing now: no lower bound.
      await phone.deliver([
        _end(startedAtMs: _t - 90000000, endedAtMs: _t - 86400000),
        _set('set-1', loggedAtMs: _t - 86500000),
      ]);

      final session = await phone.session();
      expect(
        session?.endedAtMs,
        _t - 86400000,
        reason: 'S-16409 a past end is data, not an error',
      );
      expect(
        session?.startedAtMs,
        _t - 90000000,
        reason: 'S-16409 and its start is untouched',
      );
      expect(
        phone.health.rewrites,
        isEmpty,
        reason: 'S-16409 nothing was clamped, so nothing is rewritten',
      );
    });
  });
}
