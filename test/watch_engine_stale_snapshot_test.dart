// The Dart wrist engine drops an older snapshot arriving late, like the
// watchOS engine does (plan 127, Phase 0b: red tests for D-8 — no production
// code).
//
// Plan: `docs/plans/2026-11-05-127-snapshot-timer-accuracy-plan/
// 2026-11-05-127-snapshot-timer-accuracy-plan.md`.
// Decision mapping:
//   D-8  the Dart twin's stale-snapshot guard lives in
//        `lib/watch/session/watch_session_engine.dart`: a snapshot stamped
//        EARLIER than the newest applied is refused whole, equal still applies
//        → `S-127-30`, `-31`, `-32`, `-33`
//   D-9  the Phase 0 gate — the red/green table below was recorded, not forced
//   D-10 no wire, transport or Swift change (no scenario of its own)
// Scenario mapping (the plan table's rows S-127-30..33; this file is separate
// from Phase 0a's `test/watch_snapshot_timer_accuracy_test.dart` so two
// builders can work in parallel):
//   S-127-30 a re-sent older snapshot is refused whole: no timer row, no
//            entry change, the hold B's omission stopped stays stopped
//                                                       → `S-127-30 ...`
//   S-127-31 a snapshot stamped the SAME instant as the newest still applies
//                                                       → `S-127-31 ...`
//   S-127-32 after a restore over the same store the older snapshot is still
//            refused (the guard is seeded from the `snap-` rows)
//                                                       → `S-127-32 ...`
//   S-127-33 the stale snapshot does not bring back an entry the newer one
//            deleted (D-113.2 / plan 63 D-6)             → `S-127-33 ...`
//
// The Dart engine alone: plain `test()`, no testWidgets, no phone graph, no
// Hive — `WatchSessionEngine` over `InMemoryWatchSessionStore`, exactly the
// harness `test/watch_session_engine_test.dart` runs. Fixture asserts come
// before the guard assertions, so a red test is red because the stale
// snapshot is applied (the missing guard), not because the harness is.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/sync_protocol_harness.dart'
    show TestClock, isoUtc, loadProtocolValidator;

/// The snapshot stamps, a whole second or more apart at seconds precision:
/// the guard compares instants, and the equal case on purpose shares t2's.
final DateTime _t1 = DateTime.utc(2026, 3, 4, 5, 6, 7);
final DateTime _t2 = DateTime.utc(2026, 3, 4, 5, 6, 9);
final DateTime _t3 = DateTime.utc(2026, 3, 4, 5, 6, 12);

/// The stale snapshot A and its re-send alone (a `_snapshot`'s `sentAt`
/// argument) — not the engine clock's time.
final String _stampA = isoUtc(_t1);
final String _stampB = isoUtc(_t2);
final String _stampDel = isoUtc(_t3);

/// When the phone started the hold its snapshot names.
final String _holdStartedAt = '2026-03-04T05:05:30Z';

/// When the set A carries was logged on the phone.
final String _entryLoggedAt = '2026-03-04T05:05:00Z';

const String _sessionId = 's-w-127';
const String _slotId = 'sx-bench';
const String _entryId = 'e1';

class _Harness {
  final InMemoryWatchSessionStore store = InMemoryWatchSessionStore();

  /// The engine clock: after every stamp the snapshots carry, so the rows the
  /// engine itself writes are never read as wire stamps.
  final TestClock clock = TestClock(DateTime.utc(2026, 3, 4, 5, 7, 30));
  final List<Map<String, Object?>> emitted = [];
  int _records = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over
  /// (`test/watch_session_engine_test.dart`'s harness shape).
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: loadProtocolValidator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_records}',
    sessionIdFactory: () => _sessionId,
  );
}

Map<String, Object?> _slot() => {
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-sx-bench',
  'name': 'Barbell Bench Press',
  'capabilities': ['reps', 'sets', 'load'],
};

/// One entry the snapshot carries, in the wire shape the engine's own tests
/// spell a snapshot set (`test/watch_session_engine_test.dart`'s `_entry`).
Map<String, Object?> _carriedEntry() => {
  'entryId': _entryId,
  'eventId': _entryId,
  'kind': 'set',
  'loggedAt': _entryLoggedAt,
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-sx-bench',
  'reps': 8,
  'loadKg': 80,
};

Map<String, Object?> _snapshot(
  String messageId, {
  required int revision,
  required String sentAt,
  bool withEntry = false,
  Map<String, Object?> timers = const <String, Object?>{},
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': _sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': sentAt,
  'payload': <String, Object?>{
    'sessionId': _sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_slot()],
    'entries': [if (withEntry) _carriedEntry()],
    'timers': timers,
  },
};

/// Snapshot A: one set, the phone's hold running from [_holdStartedAt].
Map<String, Object?> _snapshotA(String messageId) => _snapshot(
  messageId,
  revision: 7,
  sentAt: _stampA,
  withEntry: true,
  timers: {
    'hold': {
      'kind': 'hold',
      'state': 'running',
      'startedAt': _holdStartedAt,
      'accumulatedPauseMs': 0,
      'sessionExerciseId': _slotId,
    },
  },
);

/// Snapshot B: newer, no hold (omission stops a phone-written hold, S-12101),
/// and one entry fewer than A.
Map<String, Object?> _snapshotB(String messageId) =>
    _snapshot(messageId, revision: 8, sentAt: _stampB, timers: const {});

/// A `structure_change` naming A's set deleted — how every existing test puts
/// an entry deletion on the wrist (S-35 `a re-statement of a deleted id stays
/// deleted`).
Map<String, Object?> _deleteEntry({
  required String changeId,
  required String messageId,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': _sessionId,
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': _stampDel,
  'payload': {
    'changeId': changeId,
    'changes': [
      {'kind': 'delete_entry', 'entryId': _entryId},
    ],
  },
};

Future<int> _timerRows(InMemoryWatchSessionStore store) async =>
    (await store.readAll()).timers.length;

List<String> _entryIdsOf(WatchSessionEngine engine) => [
  for (final entry in engine.entries) entry.entryId,
];

void main() {
  group('S-127-30 the re-sent older snapshot is refused whole', () {
    test('S-127-30 a re-send stamped earlier than the newest applied returns '
        'false and changes nothing: no timer row, no entry change, the hold '
        'stays stopped', () async {
      final harness = _Harness();
      final engine = harness.newEngine();
      await engine.restore();

      expect(
        await engine.applyMessage(_snapshotA('a1')),
        isTrue,
        reason: 'fixture: the older snapshot applies today',
      );
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.running,
        reason: 'fixture: A runs the hold from S_H',
      );
      expect(
        await engine.applyMessage(_snapshotB('b1')),
        isTrue,
        reason: 'fixture: the newer snapshot applies today',
      );
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.stopped,
        reason:
            'fixture: B names no hold, so omission stops it (D-2 of '
            '121a / S-12101)',
      );
      expect(
        await engine.applyMessage(
          _deleteEntry(changeId: 'chg-del-30', messageId: 'msg-chg-del-30'),
        ),
        isTrue,
        reason: 'fixture: the structure change lands',
      );
      expect(
        _entryIdsOf(engine),
        isEmpty,
        reason: 'fixture: the tombstone B made stands after B (S-35)',
      );

      final timersBefore = await _timerRows(harness.store);
      final entriesBefore = engine.entries.length;

      final applied = await engine.applyMessage(_snapshotA('a2'));

      expect(
        applied,
        isFalse,
        reason: 'D-8: the stale snapshot is refused whole',
      );
      expect(
        await _timerRows(harness.store),
        timersBefore,
        reason: 'no new timer row comes of the refused snapshot',
      );
      expect(
        engine.entries,
        hasLength(entriesBefore),
        reason: 'no entry comes of the refused snapshot',
      );
      expect(
        engine.timerFor(WatchTimerKind.hold)!.state,
        WatchTimerState.stopped,
        reason: 'the hold B stopped stays stopped',
      );
      expect(
        engine.session!.deletedEntryIds.contains(_entryId),
        isTrue,
        reason: 'the tombstone stays',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('S-127-31 a snapshot stamped the same instant as the newest applied '
        'still applies', () async {
      final harness = _Harness();
      final engine = harness.newEngine();
      await engine.restore();

      expect(
        await engine.applyMessage(
          _snapshot('a1', revision: 7, sentAt: _stampB),
        ),
        isTrue,
      );
      expect(
        await engine.applyMessage(
          _snapshot('b1', revision: 8, sentAt: _stampB),
        ),
        isTrue,
        reason: 'equal applies — only an earlier stamp is stale (M10)',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('S-127-32 the guard survives a relaunch', () {
    test('S-127-32 after restore() over the same store the older snapshot is '
        'still refused (the guard is seeded from the snap- rows)', () async {
      final harness = _Harness();
      final engine = harness.newEngine();
      await engine.restore();

      expect(await engine.applyMessage(_snapshotA('a1')), isTrue);
      expect(await engine.applyMessage(_snapshotB('b1')), isTrue);
      // B's truth deletes A's set; the structure change is how the existing
      // tests put that deletion on the wrist (S-35 in
      // `watch_session_projection_test.dart`).
      expect(
        await engine.applyMessage(
          _deleteEntry(changeId: 'chg-del-32', messageId: 'msg-chg-del-32'),
        ),
        isTrue,
      );

      final relaunched = harness.newEngine();
      await relaunched.restore();
      expect(
        [for (final entry in relaunched.entries) entry.entryId],
        isEmpty,
        reason: 'fixture: the relaunch reads the tombstone back',
      );

      expect(
        await relaunched.applyMessage(_snapshotA('a2')),
        isFalse,
        reason:
            'D-8: the guard is seeded from the snap- rows, so the '
            'stale snapshot is refused after a relaunch too',
      );
      expect(
        [for (final entry in relaunched.entries) entry.entryId],
        isEmpty,
        reason: 'the refused snapshot still changes nothing',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('S-127-33 the stale snapshot cannot resurrect a deleted entry', () {
    test('S-127-33 a stale snapshot re-carrying an entry the newer one deleted '
        'is refused, and the entry stays gone', () async {
      final harness = _Harness();
      final engine = harness.newEngine();
      await engine.restore();

      expect(
        await engine.applyMessage(
          _snapshot('a1', revision: 7, sentAt: _stampA, withEntry: true),
        ),
        isTrue,
        reason: 'fixture: the older snapshot applies today',
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        [_entryId],
        reason: 'fixture: the wrist holds the set',
      );
      expect(
        await engine.applyMessage(_snapshotB('b1')),
        isTrue,
        reason: 'fixture: the newer snapshot (one entry fewer) applies today',
      );
      expect(
        await engine.applyMessage(
          _deleteEntry(changeId: 'chg-del-33', messageId: 'msg-chg-del-33'),
        ),
        isTrue,
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        isEmpty,
        reason: 'fixture: the entry is gone once the newer state is in',
      );
      expect(
        engine.session!.deletedEntryIds.contains(_entryId),
        isTrue,
        reason: 'fixture: the tombstone stands',
      );

      final applied = await engine.applyMessage(_snapshotA('a2'));

      expect(
        applied,
        isFalse,
        reason:
            'D-8: the stale snapshot is refused, its carried entry with '
            'it',
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        isEmpty,
        reason: 'D-113.2 / plan 63 D-6: the entry stays gone',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
