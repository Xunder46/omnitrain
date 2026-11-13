// A session the wrist has ended never comes back — not the current one, and
// not one the user has moved on from.
//
// Plan: `docs/plans/2026-11-13-151-ended-session-not-current-fix-plan/
// 2026-11-13-151-ended-session-not-current-fix-plan.md`.
// Scenario mapping:
//   S-15101 a snapshot for an ended, non-current session keeps the end
//           → `S-15101 ...`
//   S-15101 the Phase 4 four-action trace (refuse a wrist frame, finish, start
//           again) stays converged → `S-15101 ...`
//   S-15102 seed 857's trace converges: a discarded workout owes nothing →
//           `S-15102 ...`
//
// The defect these tests hold down was found by the convergence sweep
// (`.work/2026-11-10-145-convergence-test`): the wrist kept a `completed` row
// for session 1, the phone never adopted it, and two `active` snapshots for
// session 1 arriving while the wrist ran session 2 put session 1 back to
// `active` — a completed session resurrected by a stale summary of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/watch_pair_harness.dart';

const int _protocolVersion = SyncProtocolValidator.protocolVersion;

final DateTime _now = DateTime.utc(2026, 7, 13, 12);

Map<String, Object?> _exercise(String slot) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': slot,
  'capabilities': ['reps', 'sets', 'load'],
};

Map<String, Object?> _entry(String entryId, String slot) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': '2026-07-13T11:59:00Z',
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'reps': 5,
  'loadKg': 80,
};

Map<String, Object?> _snapshot(
  String sessionId, {
  required String messageId,
  required int revision,
  required String sentAt,
  String status = WatchSessionStatus.active,
  List<String> slots = const ['sx-bench'],
  List<Map<String, Object?>> entries = const [],
}) => {
  'protocolVersion': _protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': sentAt,
  'payload': <String, Object?>{
    'sessionId': sessionId,
    'revision': revision,
    'status': status,
    'currentExerciseIndex': 0,
    'exercises': [for (final slot in slots) _exercise(slot)],
    'entries': entries,
    'timers': <String, Object?>{},
  },
};

Map<String, Object?> _lifecycle(
  String sessionId, {
  required String messageId,
  required String sentAt,
  required String state,
}) => {
  'protocolVersion': _protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'phone',
  'sentAt': sentAt,
  'payload': <String, Object?>{'state': state, 'at': sentAt},
};

/// The last row the wrist stored for [sessionId] — the status it reports.
WatchSessionRecord _lastRow(List<WatchSessionRecord> rows, String sessionId) =>
    rows.lastWhere((row) => row.sessionId == sessionId);

/// Starts a session from the phone's snapshot and ends it with the phone's
/// lifecycle, leaving [sessionId] with a terminal row.
Future<void> _runThenEnd(
  WatchSessionEngine engine,
  String sessionId, {
  required String sentAt,
  List<String> slots = const ['sx-bench'],
}) async {
  await engine.applyMessage(
    _snapshot(
      sessionId,
      messageId: 'msg-$sessionId-live',
      revision: 1,
      sentAt: sentAt,
      slots: slots,
    ),
  );
  await engine.applyMessage(
    _lifecycle(
      sessionId,
      messageId: 'msg-$sessionId-end',
      sentAt: sentAt,
      state: WatchSessionStatus.completed,
    ),
  );
}

void main() {
  group('S-15101 a snapshot for an ended, non-current session keeps the end',
      () {
    test('S-15101 the wrist holds another ended session: the ended session '
        'stays ended and only its entries merge', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(store, clock: () => _now);

      await _runThenEnd(engine, 's-1', sentAt: '2026-07-13T10:00:00Z');
      await _runThenEnd(engine, 's-2', sentAt: '2026-07-13T10:05:00Z');

      final rowsBefore = (await store.readAll()).sessions;
      await engine.applyMessage(
        _snapshot(
          's-1',
          messageId: 'msg-s-1-late',
          revision: 7,
          sentAt: '2026-07-13T10:10:00Z',
          slots: const ['sx-bench', 'sx-squat'],
          entries: [_entry('e-late-1', 'sx-bench')],
        ),
      );

      final rowsAfter = (await store.readAll()).sessions;
      expect(
        rowsAfter.length,
        rowsBefore.length,
        reason: 'a session that has ended takes no new row',
      );
      expect(
        _lastRow(rowsAfter, 's-1').status,
        WatchSessionStatus.completed,
      );
      expect(
        _lastRow(rowsAfter, 's-1').revision,
        1,
        reason: 'the ended session keeps the revision it ended on',
      );
      expect(
        _lastRow(rowsAfter, 's-1').exercises.map(
              (exercise) => exercise['sessionExerciseId'],
            ),
        ['sx-bench'],
        reason: 'an ended session keeps the ladder it ended on',
      );
      expect(
        (await store.readAll()).observations.map((row) => row.entryId),
        contains('e-late-1'),
        reason: 'a set the phone logged is still news worth keeping',
      );
    });

    test('S-15101 the wrist holds a live session with an empty ladder: the '
        'ended session stays ended', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(store, clock: () => _now);

      await _runThenEnd(engine, 's-1', sentAt: '2026-07-13T10:00:00Z');
      await engine.applyMessage(
        _snapshot(
          's-2',
          messageId: 'msg-s-2-empty',
          revision: 1,
          sentAt: '2026-07-13T10:05:00Z',
          slots: const [],
        ),
      );

      final rowsBefore = (await store.readAll()).sessions;
      await engine.applyMessage(
        _snapshot(
          's-1',
          messageId: 'msg-s-1-late',
          revision: 7,
          sentAt: '2026-07-13T10:10:00Z',
          entries: [_entry('e-late-2', 'sx-bench')],
        ),
      );

      final rowsAfter = (await store.readAll()).sessions;
      expect(rowsAfter.length, rowsBefore.length);
      expect(
        _lastRow(rowsAfter, 's-1').status,
        WatchSessionStatus.completed,
      );
      expect(
        (await store.readAll()).observations.map((row) => row.entryId),
        contains('e-late-2'),
      );
    });

    test('S-15101 the wrist holds a live session of its own: the ended '
        'session stays ended (D-78 unchanged)', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(store, clock: () => _now);

      await _runThenEnd(engine, 's-1', sentAt: '2026-07-13T10:00:00Z');
      await engine.applyMessage(
        _snapshot(
          's-2',
          messageId: 'msg-s-2-live',
          revision: 1,
          sentAt: '2026-07-13T10:05:00Z',
        ),
      );

      final rowsBefore = (await store.readAll()).sessions;
      await engine.applyMessage(
        _snapshot(
          's-1',
          messageId: 'msg-s-1-late',
          revision: 7,
          sentAt: '2026-07-13T10:10:00Z',
          entries: [_entry('e-late-3', 'sx-bench')],
        ),
      );

      final rowsAfter = (await store.readAll()).sessions;
      expect(rowsAfter.length, rowsBefore.length);
      expect(
        _lastRow(rowsAfter, 's-1').status,
        WatchSessionStatus.completed,
      );
      expect(
        (await store.readAll()).observations.map((row) => row.entryId),
        contains('e-late-3'),
      );
    });

    test('S-15101 the ended session stays out of the current session '
        'whatever else the wrist holds', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(store, clock: () => _now);

      await _runThenEnd(engine, 's-1', sentAt: '2026-07-13T10:00:00Z');
      await _runThenEnd(engine, 's-2', sentAt: '2026-07-13T10:05:00Z');
      final currentBefore = engine.session?.sessionId;

      await engine.applyMessage(
        _snapshot(
          's-1',
          messageId: 'msg-s-1-late',
          revision: 7,
          sentAt: '2026-07-13T10:10:00Z',
          entries: [_entry('e-late-4', 'sx-bench')],
        ),
      );

      expect(engine.session?.sessionId, currentBefore);
      expect(
        engine.session?.status,
        isNot(WatchSessionStatus.active),
        reason: 'the snapshot moved nothing to active',
      );
    });
  });

  group('S-15101 the Phase 4 four-action trace', () {
    test('S-15101 a wrist finish, a second workout and two stale phone '
        'snapshots of the first converge', () async {
      final run = await ConvergenceRun.replayActions([
        WristStartsFreeWorkout(serial: 1),
        RefuseLiveFrame(serial: 2, from: PairActor.wrist),
        WristFinishes(serial: 3),
        WristStartsFreeWorkout(serial: 4),
      ]);

      expect(
        run.failures,
        isEmpty,
        reason: 'the trace is the smallest one the sweep found: '
            '${run.failures}',
      );
      expect(run.converged, isTrue);
    });
  });

  group('S-15102 a discarded workout owes the other side nothing', () {
    // Seed 857 (plan 151 investigation A2) was first read as a lost set; the
    // phone had logged it on a workout it then discarded, and a discarded
    // workout is deleted with its sets (owner O-7, plan 146c D-14632). Check 3
    // therefore skips an abandoned session, and this trace converges.
    test('S-15102 a set on a workout the phone then discards is not owed to '
        'the wrist', () async {
      final run = await ConvergenceRun.replayActions([
        RefuseLiveFrame(serial: 1, from: PairActor.phone),
        WristStartsFreeWorkout(serial: 2),
        PhoneLogsSet(serial: 3),
        PhoneDiscards(serial: 4),
        PhoneStartsSession(serial: 5),
      ]);

      expect(run.failures, isEmpty, reason: 'the trace: ${run.failures}');
      expect(run.converged, isTrue);
    });
  });
}
