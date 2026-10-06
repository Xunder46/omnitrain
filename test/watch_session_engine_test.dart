// Watch session engine — kill-safe lifecycle, append-only storage, timer math.
//
// Plan: `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
// Scenario mapping:
//   S-001 force-kill restores an in-progress session   → `S-001 ...`
//   S-002 reboot restores the session identically       → `S-002 ...`
//   S-003 phone unreachable, delivery exactly once      → `S-003 ...`
//   S-004 append-only enforcement at the storage API    → `S-004 ...`
//   S-005 unconfirmed data is never pruned              → `S-005 ...`
//   S-006 confirmed data may be pruned                  → `S-006 ...`
//   S-007 protocol fixture conformance                  → `S-007 ...`
//
// Process death is simulated the way the watch experiences it: a brand-new
// engine is constructed over the same storage and asked to restore. Nothing is
// handed across in memory, so anything the engine fails to persist is lost by
// construction.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/session_reconciler.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_timer_math.dart';

const String _protocolRoot = 'watch/sync_protocol';

/// Deterministic clock: the engine reads time only through its injected clock,
/// which is what lets the tests assert wall-clock derivation instead of
/// counters.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _exercise(String slot) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': slot,
  'capabilities': ['reps', 'sets', 'load'],
};

/// A schema-conformant `set` observation, the way the watch's logging surfaces
/// (item 7) will hand it to the engine.
Map<String, Object?> _setEvent(
  _Clock clock, {
  required String entryId,
  String slot = 'sx-bench',
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': _iso(clock.now),
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'reps': 5,
  'loadKg': 80,
};

/// One entry as the wire spells a `set` — the shape a snapshot hands back for
/// an id the wrist no longer holds.
Map<String, Object?> _entry(String entryId, {int loadKg = 80}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': '2026-07-13T06:00:00Z',
  'sessionExerciseId': 'sx-bench',
  'exerciseId': 'ex-sx-bench',
  'reps': 8,
  'loadKg': loadKg,
};

/// One `session_snapshot` from the phone, over the wrist's own session.
Map<String, Object?> _snapshot(
  String sessionId, {
  required String messageId,
  required int revision,
  required List<Map<String, Object?>> entries,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_exercise('sx-bench')],
    'entries': entries,
    'timers': <String, Object?>{},
  },
};

/// One `structure_change` from the phone, over the wrist's own session.
Map<String, Object?> _structureChange(
  String sessionId, {
  required String changeId,
  required List<Map<String, Object?>> changes,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$changeId',
  'sessionId': sessionId,
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{'changeId': changeId, 'changes': changes},
};

/// The value the projection shows for one entry's field — what the wrist's
/// surfaces read, as opposed to the row that was appended.
Object? _shown(WatchSessionEngine engine, String entryId, String field) =>
    engine.entries.firstWhere((entry) => entry.entryId == entryId).payload[field];

String _iso(DateTime instant) =>
    '${instant.toUtc().toIso8601String().split('.').first}Z';

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _readJson(String relativePath) => _asObject(
  jsonDecode(
    File('${Directory.current.path}/$relativePath').readAsStringSync(),
  ),
);

/// Every schema document, keyed the way `$ref` addresses it — relative to
/// `schemas/`. Duplicated from `sync_protocol_fixtures_test.dart` on purpose:
/// the engine's pipeline is validated against the same documents the gate uses,
/// loaded from the repository rather than from an asset bundle.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// The session the phone's reference reconciler would have built for the same
/// engine session — used to prove the watch's output materialises on the phone.
SyncSessionReconciler _phoneSession(
  String sessionId,
  List<Map<String, Object?>> slots,
) => SyncSessionReconciler.fromSnapshot({
  'sessionId': sessionId,
  'status': 'active',
  'revision': 0,
  'currentExerciseIndex': 0,
  'exercises': slots,
  'entries': const <Object?>[],
  'timers': <String, Object?>{},
});

class _Harness {
  _Harness({WatchSessionStore? store, this.sessionId = 's-watch-1'})
    : clock = _Clock(DateTime.utc(2026, 7, 13, 6)),
      store = store ?? InMemoryWatchSessionStore();

  final _Clock clock;
  final WatchSessionStore store;
  final String sessionId;
  final List<Map<String, Object?>> emitted = [];
  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => sessionId,
  );

  /// An engine that has already restored, i.e. one that is running.
  Future<WatchSessionEngine> runningEngine({WatchSessionEngine? engine}) async {
    final live = engine ?? newEngine();
    await live.restore();
    return live;
  }
}

void main() {
  group('S-001 force-kill restores an in-progress session', () {
    test('restores entries, position, and the wall-clock rest timer', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_exercise('sx-bench'), _exercise('sx-plank')],
      );

      for (final entryId in ['e-1', 'e-2', 'e-3']) {
        await engine.appendObservation(
          _setEvent(harness.clock, entryId: entryId),
        );
        harness.clock.advance(const Duration(minutes: 2));
      }
      await engine.startTimer(
        WatchTimerKind.rest,
        plannedDurationMs: const Duration(minutes: 3).inMilliseconds,
      );

      // Killed 30 s into the rest timer; relaunched two minutes later.
      harness.clock.advance(const Duration(seconds: 30));
      await engine.advanceExercise();
      harness.clock.advance(const Duration(minutes: 2));

      final relaunched = await harness.runningEngine();

      expect(relaunched.session!.currentExerciseIndex, 1);
      expect(relaunched.session!.status, WatchSessionStatus.active);
      expect(relaunched.observations.map((record) => record.entryId), [
        'e-1',
        'e-2',
        'e-3',
      ]);
      expect(relaunched.observations.first.payload['reps'], 5);

      final rest = relaunched.timerFor(WatchTimerKind.rest)!;
      expect(rest.state, WatchTimerState.running);
      expect(
        remainingMs(rest, harness.clock.now),
        const Duration(minutes: 3).inMilliseconds -
            const Duration(minutes: 2, seconds: 30).inMilliseconds,
        reason:
            'remaining time derives from startedAt and the current clock, '
            'never from a counter frozen at kill time',
      );
    });

    test(
      'a paused timer restores paused, with its remaining time held',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-plank')],
        );

        await engine.startTimer(
          WatchTimerKind.rest,
          plannedDurationMs: const Duration(minutes: 2).inMilliseconds,
        );
        harness.clock.advance(const Duration(seconds: 20));
        await engine.pauseTimer();

        final relaunched = await harness.runningEngine();
        final rest = relaunched.timerFor(WatchTimerKind.rest)!;

        expect(rest.state, WatchTimerState.paused);
        expect(
          remainingMs(rest, harness.clock.now),
          const Duration(minutes: 2).inMilliseconds -
              const Duration(seconds: 20).inMilliseconds,
        );
      },
    );

    test('restoring over an untouched store yields no session', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();

      expect(engine.session, isNull);
      expect(engine.observations, isEmpty);
      expect(engine.timerFor(WatchTimerKind.rest), isNull);
    });
  });

  group('S-002 reboot restores the session identically', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('watch_session_');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a session persisted through Hive survives a reboot', () async {
      final first = _Harness(store: HiveWatchSessionStore());
      final engine = await first.runningEngine();
      await engine.createSession(
        modality: 'cardio_endurance',
        exercises: [_exercise('sx-row')],
      );
      await engine.appendObservation(_setEvent(first.clock, entryId: 'e-1'));
      await engine.startTimer(
        WatchTimerKind.elapsed,
        plannedDurationMs: const Duration(minutes: 10).inMilliseconds,
      );
      first.clock.advance(const Duration(minutes: 4));

      // Reboot: every box is closed, then a brand-new store opens the same
      // files and a brand-new engine restores from them.
      await Hive.close();
      Hive.init(tempDir.path);

      final second = _Harness(
        store: HiveWatchSessionStore(),
        sessionId: first.sessionId,
      );
      second.clock.now = first.clock.now;
      final relaunched = await second.runningEngine();

      expect(relaunched.session!.modality, 'cardio_endurance');
      expect(
        relaunched.session!.startedAt,
        first.clock.now.subtract(const Duration(minutes: 4)),
      );
      expect(relaunched.observations.map((r) => r.entryId), ['e-1']);
      expect(
        remainingMs(
          relaunched.timerFor(WatchTimerKind.elapsed)!,
          second.clock.now,
        ),
        const Duration(minutes: 6).inMilliseconds,
      );
    });
  });

  group('S-003 logging with the phone unreachable delivers exactly once', () {
    test(
      'every entry is persisted, emitted, and re-emitted with its identity',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-bench')],
        );

        for (final entryId in ['e-1', 'e-2', 'e-3']) {
          await engine.appendObservation(
            _setEvent(harness.clock, entryId: entryId),
          );
          harness.clock.advance(const Duration(minutes: 1));
        }

        // A session start announces itself; the three entries follow it.
        expect(harness.emitted.map((envelope) => envelope['type']), [
          'session_lifecycle',
          'observations_up',
          'observations_up',
          'observations_up',
        ]);

        // Killed before anything left the watch: the replay rebuilds the same
        // events from persisted rows rather than inventing new ones.
        final logged = harness.emitted
            .where((envelope) => envelope['type'] == 'observations_up')
            .toList();
        final relaunched = await harness.runningEngine();
        final replay = relaunched.pendingObservations();
        expect(replay.map((envelope) => envelope['messageId']), [
          for (final envelope in logged) envelope['messageId'],
        ]);

        final phone = _phoneSession(harness.sessionId, [_exercise('sx-bench')]);
        for (final envelope in [...harness.emitted, ...replay]) {
          expect(_validator().validateEnvelope(envelope), isEmpty);
          phone.applyMessage(envelope);
        }

        final entries = phone.convergedState()['entries']! as List;
        expect(entries, hasLength(3));
        expect(
          entries.map((entry) => _asObject(entry)['entryId']),
          ['e-1', 'e-2', 'e-3'],
          reason: 're-delivery must not duplicate: the phone keys on eventId',
        );
      },
    );
  });

  group('S-004 append-only enforcement at the storage API', () {
    test('the store contract is append-only, and the engine keeps to it', () async {
      // Exactly five names are deliberate. `pruneConfirmed` and
      // `pruneSensorSamples` are the two ways anything leaves the store, and
      // each is gated on having nothing left to lose: confirmed observations
      // for the first, and for the second a session that is over whose numbers
      // the phone has already recorded in full. A third prune, or a wider gate,
      // has to be added here on purpose.
      const allowed = {
        'append',
        'readAll',
        'pruneConfirmed',
        'pruneSensorSamples',
      };

      final sessionLayer =
          Directory('${Directory.current.path}/lib/watch/session')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .toList();
      expect(sessionLayer, isNotEmpty);

      for (final file in sessionLayer) {
        final declared = _declaredMethods(
          _stripComments(file.readAsStringSync()),
        );
        expect(
          declared.where(_mutatingName.hasMatch),
          isEmpty,
          reason:
              '${file.path} declares a mutating operation. Synced entities are '
              'append-only: nothing may be named for a mutation.',
        );
      }

      // Every store is pinned to the same public surface, not just the
      // interface: a method added to an implementation is a mutation entry
      // point the rule forbids, wherever it lives.
      final stores = sessionLayer
          .where((file) => file.path.endsWith('store.dart'))
          .toList();
      expect(stores, isNotEmpty);

      for (final store in stores) {
        final exposed = _declaredMethods(
          _stripComments(store.readAsStringSync()),
        ).where((name) => !name.startsWith('_'));
        expect(
          exposed,
          unorderedEquals(allowed),
          reason:
              '${store.uri.pathSegments.last} exposes $exposed. The store '
              'contract is exactly ${allowed.join(', ')}; anything else is a '
              'mutation entry point the append-only rule forbids.',
        );
      }

      final engineSource = _stripComments(
        File(
          '${Directory.current.path}/lib/watch/session/watch_session_engine.dart',
        ).readAsStringSync(),
      );
      expect(
        RegExp(r'(?<![\w])_store\.(\w+)')
            .allMatches(engineSource)
            .map((match) => match.group(1)!)
            .toSet()
            .difference(allowed),
        isEmpty,
        reason:
            'the engine reaches for a store method outside the append-only '
            'contract',
      );
    });

    test(
      'every record type is written through one append entry point',
      () async {
        final store = InMemoryWatchSessionStore();
        final clock = _Clock(DateTime.utc(2026, 7, 13, 6));

        await store.append(
          WatchSessionRecord(
            recordId: 's-1',
            sessionId: 's-1',
            recordedAt: clock.now,
            startedAt: clock.now,
            modality: null,
            source: 'watch',
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0,
            exercises: [_exercise('sx-bench')],
          ),
        );

        expect(
          (await store.readAll()).sessions.map((record) => record.sessionId),
          ['s-1'],
        );
        expect(store, isA<WatchSessionStore>());
      },
    );
  });

  group('S-005 unconfirmed data is never pruned', () {
    test(
      'retention keeps unconfirmed entries and drops only confirmed ones',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-bench')],
        );

        for (final entryId in ['e-1', 'e-2', 'e-3', 'e-4', 'e-5']) {
          await engine.appendObservation(
            _setEvent(harness.clock, entryId: entryId),
          );
        }
        await engine.confirmObservations(['e-1', 'e-2']);

        final pruned = await engine.pruneConfirmed();

        expect(pruned.toSet(), {'e-1', 'e-2'});
        expect(engine.observations.map((record) => record.entryId), [
          'e-3',
          'e-4',
          'e-5',
        ]);
        expect(
          (await harness.store.readAll()).observations.map((r) => r.entryId),
          ['e-3', 'e-4', 'e-5'],
        );
        expect(
          engine.pendingObservations().map((envelope) => envelope['messageId']),
          hasLength(3),
          reason: 'what the phone has not confirmed is still owed to it',
        );
      },
    );
  });

  group('S-006 confirmed data may be pruned', () {
    test('a confirmed entry is pruned once retention runs', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: null,
        exercises: [_exercise('sx-bench')],
      );
      await engine.appendObservation(_setEvent(harness.clock, entryId: 'e-1'));

      await engine.confirmObservations(['e-1']);
      expect(
        engine.observations.single.confirmedAt,
        harness.clock.now,
        reason:
            'confirmation is durable: the watch must remember what it may '
            'drop across a relaunch',
      );

      final relaunched = await harness.runningEngine();
      expect(await relaunched.pruneConfirmed(), ['e-1']);
      expect(relaunched.observations, isEmpty);
    });
  });

  group('S-48 a pruned row takes its lens with it (G3)', () {
    test('a pruned entry takes the phone\'s correction with it', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: null,
        exercises: [_exercise('sx-bench')],
      );
      for (final entryId in ['e-1', 'e-2', 'e-3']) {
        await engine.appendObservation(
          _setEvent(harness.clock, entryId: entryId),
        );
      }
      expect(
        await engine.applyMessage(
          _structureChange(
            harness.sessionId,
            changeId: 'chg-correct-1',
            changes: [
              {
                'kind': 'correct_entry',
                'entryId': 'e-1',
                'correction': {'loadKg': 70},
              },
            ],
          ),
        ),
        isTrue,
      );
      expect(
        _shown(engine, 'e-1', 'loadKg'),
        70,
        reason: 'S-48 the phone\'s correction is what the wrist shows',
      );
      await engine.confirmObservations(['e-1', 'e-2']);

      expect(
        (await engine.pruneConfirmed()).toSet(),
        {'e-1', 'e-2'},
        reason: 'S-48 the confirmed rows are the ones dropped',
      );

      expect(
        await engine.applyMessage(
          _snapshot(
            harness.sessionId,
            messageId: 'msg-resend-1',
            revision: 7,
            entries: [_entry('e-1', loadKg: 60)],
          ),
        ),
        isTrue,
      );

      expect(engine.entries.map((entry) => entry.entryId), [
        'e-1',
        'e-3',
      ], reason: 'S-48 the re-carried id is a fresh row, and the unconfirmed entry is untouched');
      expect(
        _shown(engine, 'e-1', 'loadKg'),
        60,
        reason:
            'S-48/G3 a pruned row takes its correction with it: the fresh row '
            'shows what was delivered, not 70',
      );
    });

    test('a pruned entry takes the phone\'s deletion marker with it', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: null,
        exercises: [_exercise('sx-bench')],
      );
      await engine.appendObservation(_setEvent(harness.clock, entryId: 'e-1'));

      await engine.applyMessage(
        _structureChange(
          harness.sessionId,
          changeId: 'chg-delete-1',
          changes: [
            {'kind': 'delete_entry', 'entryId': 'e-1'},
          ],
        ),
      );
      expect(
        engine.entries,
        isEmpty,
        reason: 'S-48 the phone\'s deletion hides the entry',
      );

      await engine.confirmObservations(['e-1']);
      expect(await engine.pruneConfirmed(), [
        'e-1',
      ], reason: 'S-48 the deleted row is still a stored row, so a prune drops it');

      await engine.applyMessage(
        _snapshot(
          harness.sessionId,
          messageId: 'msg-resend-2',
          revision: 8,
          entries: [_entry('e-1', loadKg: 60)],
        ),
      );

      expect(
        engine.entries.map((entry) => entry.entryId),
        ['e-1'],
        reason:
            'S-48/G3 the deletion marker went with the pruned row, so a '
            're-carried id is shown again',
      );
    });
  });

  group('S-007 protocol fixture conformance', () {
    final manifest = _readJson('$_protocolRoot/fixtures/manifest.json');

    test(
      'every valid observations-up event flows through the emission pipeline',
      () async {
        final entries = (manifest['valid']! as List)
            .map(_asObject)
            .where((entry) => entry['type'] == 'observations_up');
        expect(entries, isNotEmpty);

        final validator = _validator();
        for (final entry in entries) {
          final fixture = _readJson('$_protocolRoot/fixtures/${entry['path']}');
          final events = (_asObject(fixture['payload'])['events']! as List).map(
            _asObject,
          );

          final harness = _Harness();
          final engine = await harness.runningEngine();
          await engine.createSession(modality: null);

          for (final event in events) {
            await engine.appendObservation(event);
          }

          final emitted = harness.emitted
              .where((envelope) => envelope['type'] == 'observations_up')
              .toList();
          expect(emitted, hasLength(events.length));
          for (final envelope in emitted) {
            expect(
              validator.validateEnvelope(envelope),
              isEmpty,
              reason: '${entry['path']} produced a non-conformant envelope',
            );
          }
        }
      },
    );

    test(
      'every invalid observations-up fixture is rejected before persisting',
      () async {
        final invalid = (manifest['invalid']! as List)
            .map(_asObject)
            .where((entry) => entry['type'] == 'observations_up');
        expect(invalid, isNotEmpty);

        for (final entry in invalid) {
          final fixture = _readJson('$_protocolRoot/fixtures/${entry['path']}');
          final events = (_asObject(fixture['payload'])['events']! as List)
              .map(_asObject)
              .toList(growable: false);

          final harness = _Harness();
          final engine = await harness.runningEngine();
          await engine.createSession(modality: null);

          for (final event in events) {
            expect(
              () => engine.appendObservation(event),
              throwsA(
                isA<WatchEmissionRejected>()
                    .having(
                      (error) => error.decision.rejectionCodes,
                      'rejectionCodes',
                      contains(entry['expectedCode']),
                    )
                    .having(
                      (error) => error.decision.rejections
                          .map((rejection) => rejection.message)
                          .join(' | '),
                      'message',
                      contains(entry['expectedReasonContains'] as String),
                    ),
              ),
              reason: '${entry['path']} must not reach storage',
            );
          }

          expect((await harness.store.readAll()).observations, isEmpty);
          expect(
            harness.emitted.where(
              (envelope) => envelope['type'] == 'observations_up',
            ),
            isEmpty,
            reason: 'a refused event is never emitted',
          );
        }
      },
    );

    test(
      'emitted timer messages carry timestamps and pause bookkeeping only',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-row')],
        );

        for (final kind in WatchTimerKind.all) {
          await engine.startTimer(kind);
          await engine.pauseTimer();
          await engine.resumeTimer();
        }

        final timerMessages = harness.emitted
            .where((envelope) => envelope['type'] == 'timer_state')
            .toList();
        expect(timerMessages, hasLength(WatchTimerKind.all.length * 3));

        final validator = _validator();
        for (final envelope in timerMessages) {
          expect(validator.validateEnvelope(envelope), isEmpty);
          final timers = _asObject(_asObject(envelope['payload'])['timers']!);
          for (final timer in timers.values) {
            expect(
              _asObject(timer).keys,
              isNot(contains(anyOf('remainingMs', 'remainingSeconds'))),
              reason:
                  'timers travel as timestamps; a receiver derives remaining '
                  'time from its own clock',
            );
          }
        }
      },
    );
  });

  group('Timer derivation', () {
    test('remaining time follows the clock across every state', () {
      final start = DateTime.utc(2026, 7, 13, 6);
      WatchTimerRecord timer({
        DateTime? pausedAt,
        DateTime? stoppedAt,
        int accumulatedPauseMs = 0,
        int? plannedDurationMs,
      }) => WatchTimerRecord(
        recordId: 't-1',
        sessionId: 's-1',
        recordedAt: start,
        kind: WatchTimerKind.rest,
        startedAt: start,
        pausedAt: pausedAt,
        stoppedAt: stoppedAt,
        accumulatedPauseMs: accumulatedPauseMs,
        plannedDurationMs: plannedDurationMs,
      );

      final running = timer(plannedDurationMs: 180000);
      expect(
        activeElapsedMs(running, start.add(const Duration(seconds: 45))),
        45000,
      );
      expect(
        remainingMs(running, start.add(const Duration(seconds: 45))),
        135000,
      );
      expect(
        remainingMs(running, start.add(const Duration(minutes: 30))),
        0,
        reason: 'a finished timer reads zero, never a negative remainder',
      );

      final paused = timer(
        pausedAt: start.add(const Duration(seconds: 30)),
        plannedDurationMs: 180000,
      );
      expect(
        remainingMs(paused, start.add(const Duration(hours: 1))),
        150000,
        reason: 'pause freezes the remaining time',
      );

      final resumed = timer(
        accumulatedPauseMs: 45000,
        plannedDurationMs: 180000,
      );
      expect(
        activeElapsedMs(resumed, start.add(const Duration(minutes: 2))),
        75000,
        reason: 'paused time is accounted for, not counted as work',
      );

      final stopped = timer(
        stoppedAt: start.add(const Duration(seconds: 10)),
        plannedDurationMs: 180000,
      );
      expect(
        remainingMs(stopped, start.add(const Duration(hours: 2))),
        170000,
        reason: 'a stopped timer stops moving',
      );

      expect(
        remainingMs(timer(), start.add(const Duration(minutes: 5))),
        isNull,
        reason: 'an elapsed timer has no remaining time',
      );
    });

    test(
      'pause and resume accumulate the pause without touching startedAt',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-row')],
        );

        await engine.startTimer(
          WatchTimerKind.rest,
          plannedDurationMs: const Duration(minutes: 2).inMilliseconds,
        );
        harness.clock.advance(const Duration(seconds: 30));
        await engine.pauseTimer();
        harness.clock.advance(const Duration(seconds: 40));
        await engine.resumeTimer();
        harness.clock.advance(const Duration(seconds: 20));

        final rest = engine.timerFor(WatchTimerKind.rest)!;
        expect(
          rest.startedAt,
          harness.clock.now.subtract(const Duration(minutes: 1, seconds: 30)),
        );
        expect(rest.accumulatedPauseMs, 40000);
        expect(rest.state, WatchTimerState.running);
        expect(
          remainingMs(rest, harness.clock.now),
          const Duration(minutes: 2).inMilliseconds -
              const Duration(seconds: 50).inMilliseconds,
        );
      },
    );

    test('advancing past the last exercise stays on it', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: null,
        exercises: [_exercise('sx-bench'), _exercise('sx-row')],
      );

      await engine.advanceExercise();
      await engine.advanceExercise();
      expect(engine.session!.currentExerciseIndex, 1);

      await engine.finishSession();
      expect(engine.session!.status, WatchSessionStatus.completed);
    });
  });

  group('Closing a session', () {
    test(
      'abandoning keeps what was already logged, across a relaunch',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_exercise('sx-bench')],
        );
        for (final entryId in ['e-1', 'e-2']) {
          await engine.appendObservation(
            _setEvent(harness.clock, entryId: entryId),
          );
        }

        await engine.abandonSession();
        expect(engine.session!.status, WatchSessionStatus.abandoned);

        final relaunched = await harness.runningEngine();
        expect(relaunched.session!.status, WatchSessionStatus.abandoned);
        expect(
          relaunched.observations.map((record) => record.entryId),
          ['e-1', 'e-2'],
          reason:
              'giving up on the session does not discard work already logged',
        );
      },
    );
  });

  group('Stopping a timer', () {
    test('a stopped timer freezes the time it had reached', () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      await engine.createSession(
        modality: null,
        exercises: [_exercise('sx-row')],
      );

      await engine.startTimer(
        WatchTimerKind.rest,
        plannedDurationMs: const Duration(minutes: 3).inMilliseconds,
      );
      harness.clock.advance(const Duration(seconds: 45));
      await engine.stopTimer();

      final stopped = engine.timerFor(WatchTimerKind.rest)!;
      expect(stopped.state, WatchTimerState.stopped);
      expect(stopped.stoppedAt, harness.clock.now);

      // Killed ten minutes after the stop: the readout derives from the stored
      // stop instant, so it must not have kept counting.
      harness.clock.advance(const Duration(minutes: 10));
      final relaunched = await harness.runningEngine();
      final restored = relaunched.timerFor(WatchTimerKind.rest)!;
      expect(restored.state, WatchTimerState.stopped);
      expect(
        remainingMs(restored, harness.clock.now),
        const Duration(minutes: 2, seconds: 15).inMilliseconds,
      );
    });
  });
}

/// Names that may not appear on a synced entity: a record is appended and never
/// rewritten, so nothing may be *named* for a mutation. The verb list is
/// deliberately over-inclusive, and the optional leading `_` matters — a private
/// mutator is still a mutator.
final RegExp _mutatingName = RegExp(
  r'^_?(update|delete|remove|replace|edit|overwrite|write|clear|purge|wipe|'
  r'reset|drop|truncate|erase|forget|modify|mutate|destroy|set)',
  caseSensitive: false,
);

/// Method names declared at member level (two-space indent, no deeper nesting).
/// Constructors are skipped: a declaration is a method only when its name is
/// not capitalised.
Set<String> _declaredMethods(String source) =>
    RegExp(
          r'^ {2}(?!\s)(?:Future<[^>]*>|void|[\w<>,?\s]+)\s+(\w+)(?:<[^>]*>)?\s*\(',
          multiLine: true,
        )
        .allMatches(source)
        .map((match) => match.group(1)!)
        .where((name) => name[0].toLowerCase() == name[0])
        .toSet();

/// Strips `//` line comments and `/* … */` blocks so a doc comment cannot trip
/// a source guard — the same approach as
/// `test/navigation_contract_enforcement_test.dart`.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return withoutBlocks
      .split('\n')
      .map((line) {
        final index = line.indexOf('//');
        return index < 0 ? line : line.substring(0, index);
      })
      .join('\n');
}
