// A wrist session becomes phone history: the watch session inbox stages what
// the wrist sends, and the importer turns a completed session into an
// ordinary `TrainingSession`.
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 3b — D-110, D-132 – D-138, D-140, D-142.
// Scenario mapping:
//   S-261 import from the offline stream        → `S-261 ...`
//   S-262 arrival order does not matter         → `S-262 ...`
//   S-263 redelivery                            → `S-263 ...`
//   S-264 the phone's rating is final           → `S-264 ...`
//   S-265 abandoned                             → `S-265 ...`
//   S-266 tombstones                            → `S-266 ...`
//   S-267 live corrections                      → `S-267 ...`
//   S-268 two offline sessions                  → `S-268 ...`
//   S-269 no sensors                            → `S-269 ...`
//   S-270 no platform health write              → `S-270 ...`
//   S-271 calendar liveness                     → `S-271 ...`
//   S-273 empty completed session               → `S-273 ...`
//   S-274 shape parity with phone logging       → `S-274 ...`
//   S-281, S-284 the phone-rating API (state)   → `S-281 ...`, `S-284 ...`
// S-272 (Hive ↔ Mock) is `test/watch_capture_contract_test.dart`.
//
// Every value the full-case tests expect is the capture contract's own
// (`watch/contract/watch_capture_contract.json`); see
// `test/helpers/watch_capture_import_harness.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/core/services/health_sync_service.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/calendar/calendar_state.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _capId = 's-cap-1';

/// The phone's clock: fixed, so every stamp the inbox writes is the same in
/// every arrival order.
final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

Future<MockWorkoutRepository> _repository() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedCaptureCatalog(repository);
  return repository;
}

WatchSessionInbox _inbox(
  WorkoutRepository repository,
  CaptureTransport transport, {
  Future<void> Function()? onHistoryChanged,
}) {
  var ids = 0;
  return WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: loadProtocolValidator(),
    clock: () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    onHistoryChanged: onHistoryChanged,
    // A failure inside the inbox fails the test where it happened.
    onFailure: Error.throwWithStackTrace,
  );
}

/// Delivers [events] one envelope each, the way S-261 delivers F-CAP.
Future<List<WatchInboxResult>> _deliverEach(
  WatchSessionInbox inbox,
  String sessionId,
  List<Map<String, Object?>> events, {
  String tag = 'a',
}) async => [
  for (var i = 0; i < events.length; i++)
    await inbox.receive(
      observationsUp(sessionId, [events[i]], messageId: 'msg-$tag-$i'),
    ),
];

Map<String, Object?> _eventOf(String caseName, String entryId) =>
    captureEvents(caseName).singleWhere((e) => e['entryId'] == entryId);

/// The calendar on 2026-09: where 2026-09-25's sessions land, which is the
/// month F-CAP runs in.
Future<CalendarState> septemberCalendar(WorkoutRepository repository) async {
  final calendar = CalendarState(repository);
  while (calendar.year * 12 + calendar.month > 2026 * 12 + 9) {
    await calendar.goToPreviousMonth();
  }
  while (calendar.year * 12 + calendar.month < 2026 * 12 + 9) {
    await calendar.goToNextMonth();
  }
  return calendar;
}

/// The one calendar entry for [sessionId], or null when the loaded month does
/// not hold it.
CalendarEntry? calendarEntryIn(CalendarState calendar, String sessionId) {
  for (final entries in calendar.entriesByDay.values) {
    for (final entry in entries) {
      if (entry.session?.id == sessionId) return entry;
    }
  }
  return null;
}

/// A set event in the protocol's shape.
Map<String, Object?> _set(
  String entryId, {
  required String loggedAt,
  String slot = 'sx-bench',
  String exerciseId = 'ex-bench',
  int reps = 5,
  num? loadKg = 80,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': loggedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'reps': reps,
  'loadKg': ?loadKg,
};

Map<String, Object?> _end(
  String sessionId, {
  required String startedAt,
  required String endedAt,
  String status = 'completed',
}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': endedAt,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'status': status,
};

Map<String, Object?> _rating(
  String sessionId,
  int rating, {
  required String loggedAt,
}) => {
  'entryId': 'rating-$sessionId',
  'eventId': 'rating-$sessionId',
  'kind': 'effort_rating',
  'loggedAt': loggedAt,
  'rating': rating,
};

/// Whether the phone already holds the rows [entryId] of [caseName] becomes —
/// what a receipt is allowed to name.
Future<bool> _rowsExist(
  WorkoutRepository repository,
  String caseName,
  String entryId,
) async {
  final event = _eventOf(caseName, entryId);
  final session = await repository.getSession(_capId);
  switch (event['kind']) {
    case 'session_end':
      return session != null;
    case 'effort_rating':
      return session?.sessionFeeling == event['rating'];
    case 'timed':
      final effortId = WatchSessionImporter.effortIdFor(
        _capId,
        event['sessionExerciseId']! as String,
        event['exerciseId']! as String,
        'timed',
      );
      return (await repository.getTimedInstances(effortId)).any(
        (t) => t.id == WatchSessionImporter.timedInstanceIdFor(_capId, entryId),
      );
    case 'round':
      final effortId = WatchSessionImporter.effortIdFor(
        _capId,
        event['sessionExerciseId']! as String,
        event['exerciseId']! as String,
        'round',
      );
      return (await repository.getRoundInstances(effortId)).any(
        (r) => r.id == WatchSessionImporter.roundInstanceIdFor(_capId, entryId),
      );
    default:
      final effortId = WatchSessionImporter.effortIdFor(
        _capId,
        event['sessionExerciseId']! as String,
        event['exerciseId']! as String,
        'set',
      );
      final setEntries = [
        for (final e in captureEvents(caseName))
          if (e['kind'] == 'set') e['entryId'],
      ];
      return await observationAt(
            repository,
            effortId,
            setEntries.indexOf(entryId),
            'reps',
          ) !=
          null;
  }
}

/// A repository whose one armed observation write fails — a pass that stops
/// half-way, as a full disk would stop it.
class _FailOnceRepository extends MockWorkoutRepository {
  String? failOn;

  @override
  Future<String> createObservation(EffortObservation observation) async {
    if (observation.id == failOn) {
      failOn = null;
      throw StateError('the store refused ${observation.id}');
    }
    return super.createObservation(observation);
  }
}

/// Records every platform workout write.
class _RecordingHealthPlatform implements HealthPlatformService {
  final List<HealthWorkoutDraft> writes = [];

  @override
  Future<bool> requestWritePermission() async => true;

  @override
  Future<bool> requestReadPermission() async => true;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    writes.add(workout);
    return true;
  }

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

void main() {
  group('S-261 import from the offline stream', () {
    for (final caseName in const ['full', 'no-sensors', 'prompt-off']) {
      test('S-261 $caseName: nine envelopes through the router import exactly '
          'the contract', () async {
        final repository = await _repository();
        final transport = CaptureTransport();
        final inbox = _inbox(repository, transport);
        final router = WatchIncomingRouter(
          inbox: inbox,
          mirror: LiveSessionMirrorState(
            transport: transport,
            snapshot: watchSessionPlaceholder,
            validator: loadProtocolValidator(),
          ),
          nutrition: WatchNutritionLogBridge(
            nutrition: NutritionState(repository),
            library: FoodLibraryState(repository),
            validator: loadProtocolValidator(),
            transport: transport,
          ),
        );

        // A receipt names only what the phone already holds: checked at the
        // moment each receipt leaves.
        final early = <String>[];
        transport.onSend = (envelope) async {
          if (envelope['type'] != 'receipt') return;
          for (final id
              in ((envelope['payload']! as Map)['entryIds']! as List)
                  .cast<String>()) {
            if (!await _rowsExist(repository, caseName, id)) early.add(id);
          }
        };

        final events = captureEvents(caseName);
        for (var i = 0; i < events.length; i++) {
          final receipt = await router.receive(
            observationsUp(_capId, [events[i]], messageId: 'msg-$i'),
          );
          expect(
            receipt.inbox,
            WatchInboxOutcome.staged,
            reason: 'S-261 every event is staged before anything else answers',
          );
        }

        expect(
          early,
          isEmpty,
          reason: 'S-261 receipts are sent after the rows exist',
        );
        await expectCaptureImport(
          repository,
          captureExpectedImport(caseName),
          receiptedEntryIds: transport.receiptedEntryIds,
          reasonPrefix: 'S-261 $caseName',
        );
      });
    }

    test('S-261 an import the phone had not run resumes at start', () async {
      final repository = await _repository();
      // Staged by a phone that stopped before importing (D-132).
      for (final event in captureEvents('full')) {
        await repository.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: event['entryId']! as String,
            watchSessionId: _capId,
            kind: event['kind']! as String,
            origin: WatchInboxEntry.originWatch,
            payload: Map<String, dynamic>.of(event),
            receivedAtMs: _phoneNow.millisecondsSinceEpoch,
          ),
        );
      }
      expect(
        await repository.getSession(_capId),
        isNull,
        reason: 'S-261 nothing is imported before the resume',
      );

      final transport = CaptureTransport();
      await _inbox(repository, transport).resume();

      await expectCaptureImport(
        repository,
        captureExpectedImport('full'),
        receiptedEntryIds: transport.receiptedEntryIds,
        reasonPrefix: 'S-261 resumed',
      );
    });

    test(
      'F-5 the inbox stages before the mirror can answer: at the moment '
      'the mirror re-asserts, the triggering entries are already staged',
      () async {
        const sessionId = 's-f5-order';
        Map<String, Object?> ladder() => {
          'sessionId': sessionId,
          'status': 'active',
          'currentExerciseIndex': 0,
          'exercises': [
            {
              'sessionExerciseId': 'sx-bench',
              'exerciseId': 'ex-bench',
              'name': 'Barbell Bench Press',
              'capabilities': ['sets', 'reps', 'load'],
            },
          ],
          'timers': const <String, Object?>{},
        };

        final repository = await _repository();
        final transport = CaptureTransport();
        final inbox = _inbox(repository, transport);
        final mirror = LiveSessionMirrorState(
          transport: transport,
          validator: loadProtocolValidator(),
          snapshot: {...ladder(), 'revision': 0, 'entries': const <Object?>[]},
        );
        final router = WatchIncomingRouter(
          inbox: inbox,
          mirror: mirror,
          nutrition: WatchNutritionLogBridge(
            nutrition: NutritionState(repository),
            library: FoodLibraryState(repository),
            validator: loadProtocolValidator(),
            transport: transport,
          ),
        );

        var stagedWhenMirrorAnswered = false;
        transport.onSend = (envelope) async {
          if (envelope['type'] != 'session_snapshot') return;
          stagedWhenMirrorAnswered =
              await repository.getWatchInboxEntry('e-f5-order-1') != null;
        };

        // A wrist snapshot at a different revision is a shape the phone
        // disagrees with, which is what makes the mirror re-assert its own
        // (D-130) — the moment F-5 checks.
        await router.receive({
          'protocolVersion': SyncProtocolValidator.protocolVersion,
          'messageId': 'msg-f5-snapshot',
          'sessionId': sessionId,
          'type': 'session_snapshot',
          'origin': 'watch',
          'sentAt': '2026-09-25T10:05:01.000Z',
          'payload': {
            ...ladder(),
            'revision': 1,
            'entries': [
              _set('e-f5-order-1', loggedAt: '2026-09-25T10:05:00.000Z'),
            ],
          },
        });

        expect(
          transport.ofType('session_snapshot'),
          hasLength(1),
          reason: 'F-5 guard: the mirror must actually re-assert for this '
              'test to prove anything',
        );
        expect(
          stagedWhenMirrorAnswered,
          isTrue,
          reason: 'F-5 the inbox stages the entries a snapshot carries '
              'before any other consumer of the message can answer it',
        );
        expect(
          await repository.getWatchInboxEntry('e-f5-order-1'),
          isNotNull,
          reason: 'F-5 sanity: the entry really was staged',
        );
      },
    );
  });

  group('S-262 arrival order does not matter', () {
    final events = captureEvents('full');
    final end = events.singleWhere((e) => e['kind'] == 'session_end');
    final rating = events.singleWhere((e) => e['kind'] == 'effort_rating');
    final orders = {
      'reversed': events.reversed.toList(),
      'session_end first': [end, ...events.where((e) => e != end)],
      'rating first': [rating, ...events.where((e) => e != rating)],
    };

    for (final order in orders.entries) {
      test(
        'S-262 ${order.key} leaves the state of the contract order',
        () async {
          final contract = await _repository();
          final contractTransport = CaptureTransport();
          await _deliverEach(
            _inbox(contract, contractTransport),
            _capId,
            events,
          );

          final other = await _repository();
          final otherTransport = CaptureTransport();
          await _deliverEach(
            _inbox(other, otherTransport),
            _capId,
            order.value,
          );

          await expectCaptureImport(
            other,
            captureExpectedImport('full'),
            receiptedEntryIds: otherTransport.receiptedEntryIds,
            reasonPrefix: 'S-262 ${order.key}',
          );
          expect(
            await importedRows(other, _capId),
            equals(await importedRows(contract, _capId)),
            reason: 'S-262 ${order.key}: identical repository state',
          );
          expect(
            otherTransport.receiptedEntryIds.toSet(),
            contractTransport.receiptedEntryIds.toSet(),
            reason: 'S-262 ${order.key}: the same receipt union',
          );
        },
      );
    }
  });

  group('S-263 redelivery', () {
    test(
      'S-263 a second, altered copy adds nothing and refreshes nothing',
      () async {
        final repository = await _repository();
        final transport = CaptureTransport();
        var refreshes = 0;
        final inbox = _inbox(
          repository,
          transport,
          onHistoryChanged: () async => refreshes++,
        );
        final events = captureEvents('full');
        await _deliverEach(inbox, _capId, events, tag: 'first');
        final before = await importedRows(repository, _capId);
        final refreshesBefore = refreshes;

        // The same stream again, with the run's heart rate altered (still a
        // conformant event, so it is the put-if-absent that refuses it).
        final altered = [
          for (final event in events)
            event['entryId'] == 'e-run'
                ? {...event, 'avgHeartRateBpm': 999, 'maxHeartRateBpm': 999}
                : event,
        ];
        final results = await _deliverEach(
          inbox,
          _capId,
          altered,
          tag: 'second',
        );

        expect(
          results.map((r) => r.outcome).toSet(),
          {WatchInboxOutcome.unchanged},
          reason: 'S-263 every copy is accepted and refused by put-if-absent',
        );
        expect(
          await importedRows(repository, _capId),
          equals(before),
          reason: 'S-263 no new rows and no changed values',
        );
        expect(
          refreshes,
          refreshesBefore,
          reason: 'S-263 a redelivery that changes nothing refreshes nothing',
        );
      },
    );
  });

  group('S-264 the phone’s value is final', () {
    test('S-264 the phone’s rating survives a redelivered, altered wrist '
        'rating', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());
      final events = captureEvents('full');
      await _deliverEach(inbox, _capId, events);
      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        4,
        reason: 'S-264 the wrist rating is imported first',
      );

      await repository.updateSessionFeeling(_capId, 2);
      final summaries = [
        for (final s in await repository.getSensorSummariesForSession(_capId))
          s.toMap(),
      ];
      await _deliverEach(inbox, _capId, [
        ...events,
        {..._eventOf('full', 'rating-$_capId'), 'rating': 5},
      ], tag: 'again');

      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        2,
        reason: 'S-264 the phone’s value is final',
      );
      expect(
        [
          for (final s in await repository.getSensorSummariesForSession(_capId))
            s.toMap(),
        ],
        summaries,
        reason: 'S-264 the summaries are unchanged',
      );
    });

    test('S-264 a wrist rating that arrives after the phone rated changes '
        'nothing', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);
      final events = captureEvents('full');
      await _deliverEach(inbox, _capId, [
        for (final e in events)
          if (e['kind'] != 'effort_rating') e,
      ]);
      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        isNull,
        reason: 'S-264 imported without a rating',
      );

      await repository.updateSessionFeeling(_capId, 2);
      await _deliverEach(inbox, _capId, [
        _eventOf('full', 'rating-$_capId'),
      ], tag: 'late');

      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        2,
        reason: 'S-264 a wrist rating applies only while the phone has none',
      );
      expect(
        transport.receiptedEntryIds,
        contains('rating-$_capId'),
        reason: 'S-264 the late wrist rating is still acknowledged',
      );
    });
  });

  group('S-265 an abandoned session', () {
    test('S-265 is consumed and acknowledged without history', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);

      await _deliverEach(inbox, 's-ab-1', [
        _set('e-ab1', loggedAt: '2026-09-25T09:05:00.000Z'),
        _end(
          's-ab-1',
          startedAt: '2026-09-25T09:00:00.000Z',
          endedAt: '2026-09-25T09:10:00.000Z',
          status: 'abandoned',
        ),
      ]);

      expect(
        await repository.getSession('s-ab-1'),
        isNull,
        reason: 'S-265 an abandoned session creates no history',
      );
      final staged = await repository.getWatchInboxEntriesForSession('s-ab-1');
      expect(
        staged.map((row) => row.appliedAtMs != null),
        everyElement(isTrue),
        reason: 'S-265 every staged row is applied (deliberately discarded)',
      );
      expect(
        transport.receiptedEntryIds.toSet(),
        {'e-ab1', 'end-s-ab-1'},
        reason: 'S-265 the receipt carries the set and the session end',
      );
    });
  });

  group('S-266 deleted history stays deleted', () {
    test('S-266 a deleted session is never re-created', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);
      final events = captureEvents('full');
      await _deliverEach(inbox, _capId, events);
      await repository.deleteSession(_capId);

      final late = _set('e-late', loggedAt: '2026-09-25T10:52:00.000Z');
      await _deliverEach(inbox, _capId, [...events, late], tag: 'again');

      expect(
        await repository.getSession(_capId),
        isNull,
        reason: 'S-266 no session is re-created',
      );
      expect(
        await repository.getSensorSummariesForSession(_capId),
        isEmpty,
        reason: 'S-266 nothing of it comes back',
      );
      expect(
        transport.receiptedEntryIds,
        contains('e-late'),
        reason: 'S-266 the late entry is receipted',
      );
      expect(
        (await repository.getWatchInboxEntry('e-late'))!.appliedAtMs,
        isNotNull,
        reason: 'S-266 and dropped',
      );
    });

    test('S-266 a set deleted through the phone’s edit path is not '
        're-created', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());
      final events = captureEvents('full');
      await _deliverEach(inbox, _capId, events);

      final bench = WatchSessionImporter.effortIdFor(
        _capId,
        'sx-bench',
        'ex-bench',
        'set',
      );
      final workout = WorkoutState(repository);
      await workout.loadHistoricalSession(_capId);
      await workout.deleteEntry(bench, 1);
      expect(
        await observationAt(repository, bench, 1, 'reps'),
        isNull,
        reason: 'S-266 the phone edit path removed e-set2',
      );

      // The redelivery brings a late set with it, so the import runs again
      // over an effort whose e-set2 the user removed.
      await _deliverEach(inbox, _capId, [
        ...events,
        _set('e-set4', loggedAt: '2026-09-25T10:52:00.000Z'),
      ], tag: 'again');

      expect(
        await observationAt(repository, bench, 1, 'reps'),
        isNull,
        reason: 'S-266 e-set2’s rows are not re-created',
      );
      expect(
        await observationAt(repository, bench, 1, 'weight'),
        isNull,
        reason: 'S-266 e-set2’s rows are not re-created',
      );
      expect(
        (await observationAt(repository, bench, 0, 'reps'))?.valueInt,
        5,
        reason: 'S-266 e-set1 is untouched',
      );
      expect(
        (await observationAt(repository, bench, 2, 'reps'))?.valueInt,
        5,
        reason: 'S-266 e-set3 is untouched',
      );
      expect(
        (await observationAt(repository, bench, 3, 'reps'))?.valueInt,
        5,
        reason: 'S-266 the late set joins the effort',
      );
    });
  });

  group('S-267 live corrections carry into history', () {
    /// The mirror holding s-cap-1 live, with its outgoing corrections staged
    /// through [inbox] before they reach [transport].
    LiveSessionMirrorState liveMirror(
      WatchSessionInbox inbox,
      CaptureTransport transport,
    ) => LiveSessionMirrorState(
      transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
      validator: loadProtocolValidator(),
      snapshot: {
        'sessionId': _capId,
        'status': 'active',
        'revision': 0,
        'currentExerciseIndex': 0,
        'exercises': [
          {
            'sessionExerciseId': 'sx-bench',
            'exerciseId': 'ex-bench',
            'name': 'Barbell Bench Press',
            'capabilities': ['sets', 'reps', 'load'],
          },
        ],
        'entries': const <Object?>[],
        'timers': const <String, Object?>{},
      },
    );

    test(
      'S-267 a correction and a deletion staged live apply at import',
      () async {
        final repository = await _repository();
        final transport = CaptureTransport();
        final beforeRestart = _inbox(repository, transport);
        final mirror = liveMirror(beforeRestart, transport);

        // Staged before it is sent: the row exists when the radio takes it.
        final stagedAtSend = <bool>[];
        transport.onSend = (envelope) async {
          if (envelope['type'] != 'structure_change') return;
          final payload = envelope['payload']! as Map;
          stagedAtSend.add(
            await repository.getWatchInboxEntry(
                  WatchInboxEntry.phoneChangeId(
                    payload['changeId']! as String,
                    0,
                  ),
                ) !=
                null,
          );
        };
        await mirror.correctEntry('e-set2', {'reps': 6});
        await mirror.deleteEntry('e-set3');
        expect(stagedAtSend, [
          true,
          true,
        ], reason: 'S-267 each change is staged before it is sent');

        // The phone restarts: a new inbox over the same repository.
        final afterRestart = _inbox(repository, transport);
        await _deliverEach(afterRestart, _capId, captureEvents('full'));

        final bench = WatchSessionImporter.effortIdFor(
          _capId,
          'sx-bench',
          'ex-bench',
          'set',
        );
        expect(
          [
            for (var i = 0; i < 3; i++)
              (await observationAt(repository, bench, i, 'reps'))?.valueInt,
          ],
          [5, 6, null],
          reason: 'S-267 the bench holds 5×80 and 6×80, and nothing for e-set3',
        );
        expect(
          [
            for (var i = 0; i < 2; i++)
              (await observationAt(repository, bench, i, 'weight'))?.valueReal,
          ],
          [80.0, 80.0],
          reason: 'S-267 both sets keep 80 kg',
        );
        expect(
          await sortedObservations(repository, bench),
          hasLength(4),
          reason: 'S-267 two sets, two rows each',
        );
      },
    );

    test(
      'S-267 a correction staged after import updates the imported row',
      () async {
        final repository = await _repository();
        final transport = CaptureTransport();
        final inbox = _inbox(repository, transport);
        await _deliverEach(inbox, _capId, captureEvents('full'));

        await liveMirror(inbox, transport).correctEntry('e-set1', {'reps': 4});

        final bench = WatchSessionImporter.effortIdFor(
          _capId,
          'sx-bench',
          'ex-bench',
          'set',
        );
        expect(
          (await observationAt(repository, bench, 0, 'reps'))?.valueInt,
          4,
          reason: 'S-267 the imported row takes the correction',
        );
        expect(
          (await observationAt(repository, bench, 1, 'reps'))?.valueInt,
          5,
          reason: 'S-267 the other sets keep their values',
        );
      },
    );

    test('S-267 a later correction leaves the user’s own edit of another '
        'metric', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);
      final mirror = liveMirror(inbox, transport);
      final bench = WatchSessionImporter.effortIdFor(
        _capId,
        'sx-bench',
        'ex-bench',
        'set',
      );

      await mirror.correctEntry('e-set1', {'loadKg': 85});
      await _deliverEach(inbox, _capId, captureEvents('full'));
      expect(
        (await observationAt(repository, bench, 0, 'weight'))?.valueReal,
        85.0,
        reason: 'S-267 the live correction is in history',
      );

      // The user edits the weight in history; then the live screen corrects
      // the reps of the same set.
      final workout = WorkoutState(repository);
      await workout.loadHistoricalSession(_capId);
      await workout.updateEntryValue(bench, 0, 'weight', 90.0);
      await mirror.correctEntry('e-set1', {'reps': 4});

      expect(
        (await observationAt(repository, bench, 0, 'reps'))?.valueInt,
        4,
        reason: 'S-267 the later correction applies',
      );
      expect(
        (await observationAt(repository, bench, 0, 'weight'))?.valueReal,
        90.0,
        reason: 'S-267 the user’s own edit of the weight stays',
      );
    });
  });

  group('S-268 two sessions synced after the phone held a third', () {
    test(
      'S-268 each lands in history, and the mirror follows the newest',
      () async {
        final repository = await _repository();
        final transport = CaptureTransport();
        final inbox = _inbox(repository, transport);
        final mirror = LiveSessionMirrorState(
          transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
          validator: loadProtocolValidator(),
          snapshot: {
            'sessionId': 's-prev',
            'status': 'completed',
            'revision': 0,
            'currentExerciseIndex': 0,
            'exercises': [
              {
                'sessionExerciseId': 'sx-p',
                'exerciseId': 'ex-bench',
                'name': 'Barbell Bench Press',
                'capabilities': ['sets', 'reps', 'load'],
              },
            ],
            'entries': [
              _set('e-p1', loggedAt: '2026-09-25T07:05:00.000Z', slot: 'sx-p'),
            ],
            'timers': const <String, Object?>{},
          },
        );
        final router = WatchIncomingRouter(
          inbox: inbox,
          mirror: mirror,
          nutrition: WatchNutritionLogBridge(
            nutrition: NutritionState(repository),
            library: FoodLibraryState(repository),
            transport: transport,
          ),
        );

        final a = [
          _set(
            'e-a1',
            loggedAt: '2026-09-25T08:05:00.000Z',
            slot: 'sx-a',
            loadKg: 60,
          ),
          _end(
            's-off-a',
            startedAt: '2026-09-25T08:00:00.000Z',
            endedAt: '2026-09-25T08:10:00.000Z',
          ),
          _rating('s-off-a', 3, loggedAt: '2026-09-25T08:10:10.000Z'),
        ];
        final b = [
          _set(
            'e-b1',
            loggedAt: '2026-09-25T09:05:00.000Z',
            slot: 'sx-b',
            loadKg: 70,
          ),
          _end(
            's-off-b',
            startedAt: '2026-09-25T09:00:00.000Z',
            endedAt: '2026-09-25T09:10:00.000Z',
          ),
          _rating('s-off-b', 5, loggedAt: '2026-09-25T09:10:10.000Z'),
        ];
        await router.receive(observationsUp('s-off-a', a, messageId: 'msg-a'));
        await router.receive(observationsUp('s-off-b', b, messageId: 'msg-b'));
        await router.receive({
          'protocolVersion': SyncProtocolValidator.protocolVersion,
          'messageId': 'msg-snapshot-b',
          'sessionId': 's-off-b',
          'type': 'session_snapshot',
          'origin': 'watch',
          'sentAt': '2026-09-25T11:00:00Z',
          'payload': {
            'sessionId': 's-off-b',
            'status': 'completed',
            'revision': 0,
            'currentExerciseIndex': 0,
            'exercises': [
              {
                'sessionExerciseId': 'sx-b',
                'exerciseId': 'ex-bench',
                'name': 'Barbell Bench Press',
                'capabilities': ['sets', 'reps', 'load'],
              },
            ],
            'entries': b,
            'timers': const <String, Object?>{},
          },
        });

        expect(mirror.sessionId, 's-off-b', reason: 'S-268 the mirror is on B');
        expect(
          [for (final entry in mirror.entries) entry['entryId']],
          ['e-b1', 'end-s-off-b', 'rating-s-off-b'],
          reason: 'S-268 with its entries only',
        );
        expect(
          {for (final envelope in transport.sent) envelope['type']},
          {'receipt'},
          reason: 'S-268 nothing was sent back but the receipts',
        );
        expect(
          transport.receiptedEntryIds.toSet(),
          {
            for (final e in [...a, ...b]) e['entryId'],
          },
          reason: 'S-268 both sessions events are acknowledged',
        );

        for (final (sessionId, feeling, load) in [
          ('s-off-a', 3, 60.0),
          ('s-off-b', 5, 70.0),
        ]) {
          final session = await repository.getSession(sessionId);
          expect(session?.sessionFeeling, feeling, reason: 'S-268 $sessionId');
          final efforts = await importedEfforts(repository, sessionId);
          expect(efforts, hasLength(1), reason: 'S-268 $sessionId: one effort');
          expect(
            (await observationAt(
              repository,
              efforts.single.id,
              0,
              'weight',
            ))?.valueReal,
            load,
            reason: 'S-268 $sessionId: one set of its own',
          );
          expect(
            await sortedObservations(repository, efforts.single.id),
            hasLength(2),
            reason: 'S-268 each set is two rows',
          );
        }
        expect(
          await repository.getSession('s-prev'),
          isNull,
          reason: 'S-268 nothing from s-prev',
        );
      },
    );
  });

  group('S-269 no sensors', () {
    test(
      'S-269 the session imports with no summary and no measured field',
      () async {
        final repository = await _repository();
        await _deliverEach(
          _inbox(repository, CaptureTransport()),
          _capId,
          captureEvents('no-sensors'),
        );

        expect(
          await repository.getSession(_capId),
          isNotNull,
          reason: 'S-269 the session is imported',
        );
        expect(
          await repository.getSensorSummariesForSession(_capId),
          isEmpty,
          reason: 'S-269 zero SensorSummary rows',
        );
        for (final row in await repository.getWatchInboxEntriesForSession(
          _capId,
        )) {
          for (final field in const [
            'avgHeartRateBpm',
            'maxHeartRateBpm',
            'steps',
            'setBlockHeartRates',
          ]) {
            expect(
              row.payload.containsKey(field),
              isFalse,
              reason: 'S-269 no zero-valued field anywhere (${row.entryId})',
            );
          }
        }
      },
    );
  });

  group('S-270 the phone never writes an imported session to health', () {
    test(
      'S-270 loading and ending the imported session writes nothing',
      () async {
        final repository = await _repository();
        final platform = _RecordingHealthPlatform();
        final workout = WorkoutState(
          repository,
          healthSync: HealthSyncService(
            platform: platform,
            repository: repository,
            isWriteEnabled: () => true,
            isReadEnabled: () => false,
          ),
        );

        await workout.createNewSession();
        await workout.addExerciseToSession(
          (await repository.getExerciseById('ex-bench'))!,
        );
        await workout.endSession();
        expect(
          platform.writes,
          hasLength(1),
          reason: 'S-270 the phone session is written once (unchanged)',
        );

        await _deliverEach(
          _inbox(repository, CaptureTransport()),
          _capId,
          captureEvents('full'),
        );
        await workout.loadHistoricalSession(_capId);
        await workout.endSession();

        expect(
          platform.writes,
          hasLength(1),
          reason: 'S-270 the wrist’s workout is the health record (D-140)',
        );
      },
    );
  });

  group('S-271 the calendar sees an import', () {
    bool holds(CalendarState calendar, String sessionId) =>
        calendarEntryIn(calendar, sessionId) != null;

    test('S-271 one import, one refresh; a redelivery, none', () async {
      final repository = await _repository();
      final calendar = await septemberCalendar(repository);
      expect(
        holds(calendar, _capId),
        isFalse,
        reason: 'S-271 the month starts without s-cap-1',
      );
      var refreshes = 0;
      final inbox = _inbox(
        repository,
        CaptureTransport(),
        onHistoryChanged: () async {
          refreshes++;
          await calendar.refresh();
        },
      );
      final message = observationsUp(
        _capId,
        captureEvents('full'),
        messageId: 'msg-all',
      );

      await inbox.receive(message);
      expect(refreshes, 1, reason: 'S-271 exactly one refresh');
      expect(
        holds(calendar, _capId),
        isTrue,
        reason: 'S-271 the month contains s-cap-1',
      );

      await inbox.receive(message);
      expect(refreshes, 1, reason: 'S-271 a redelivery triggers no refresh');
    });

    test('S-271 each history change refreshes once', () async {
      final repository = await _repository();
      var refreshes = 0;
      final inbox = _inbox(
        repository,
        CaptureTransport(),
        onHistoryChanged: () async => refreshes++,
      );
      final events = captureEvents('full');

      await _deliverEach(inbox, _capId, events);
      expect(
        refreshes,
        2,
        reason: 'S-271 the import at the session end, then the rating top-up',
      );

      await _deliverEach(inbox, _capId, events, tag: 'again');
      expect(refreshes, 2, reason: 'S-271 a redelivery triggers no refresh');
    });
  });

  group('S-273 an empty completed session', () {
    test('S-273 is consumed and acknowledged without history', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      await _deliverEach(_inbox(repository, transport), 's-empty-1', [
        _end(
          's-empty-1',
          startedAt: '2026-09-25T09:00:00.000Z',
          endedAt: '2026-09-25T09:30:00.000Z',
        ),
        _rating('s-empty-1', 3, loggedAt: '2026-09-25T09:30:10.000Z'),
      ]);

      expect(
        await repository.getSession('s-empty-1'),
        isNull,
        reason: 'S-273 nothing imported',
      );
      expect(
        transport.receiptedEntryIds.toSet(),
        {'end-s-empty-1', 'rating-s-empty-1'},
        reason: 'S-273 the receipt carries the end and the rating',
      );
    });
  });

  group('S-274 imported rows have the shape of the phone’s own', () {
    test(
      'S-274 sets, timed work, holds and rounds match phone logging',
      () async {
        final repository = await _repository();
        await seedExercise(
          repository,
          id: 'ex-pushup',
          name: 'Push-up',
          capabilities: const ['sets', 'reps'],
        );
        await seedExercise(
          repository,
          id: 'ex-plank',
          name: 'Plank',
          capabilities: const ['time', 'hold'],
        );

        // The phone logs through WorkoutState.
        final workout = WorkoutState(repository);
        await workout.createNewSession();
        final phoneSessionId = workout.currentSession!.id;
        Future<String> add(String exerciseId, String kind) async =>
            workout.addExerciseToSession(
              (await repository.getExerciseById(exerciseId))!,
              effortKindOverride: kind,
            );
        final bench = await add('ex-bench', 'set');
        await workout.updateEntryValue(bench, 0, 'reps', 5);
        await workout.updateEntryValue(bench, 0, 'weight', 80.0);
        final pushup = await add('ex-pushup', 'set');
        await workout.updateEntryValue(pushup, 0, 'reps', 5);
        final run = await add('ex-run', 'timed');
        await workout.setTimedEntryDuration(run, 0, 1200);
        final plank = await add('ex-plank', 'drill');
        await workout.setTimedEntryDuration(plank, 0, 60);
        final bjj = await add('ex-bjj', 'round');
        await workout.updateRoundPlannedDuration(bjj, 0, 300);
        await workout.setRoundDuration(bjj, 0, 300);
        await workout.endSession();

        // The wrist logs the same, and it is imported.
        const sid = 's-shape-1';
        await _deliverEach(_inbox(repository, CaptureTransport()), sid, [
          _set('e-bench', loggedAt: '2026-09-25T10:01:00.000Z'),
          _set(
            'e-pushup',
            loggedAt: '2026-09-25T10:02:00.000Z',
            slot: 'sx-pushup',
            exerciseId: 'ex-pushup',
            loadKg: null,
          ),
          {
            'entryId': 'e-run',
            'eventId': 'e-run',
            'kind': 'timed',
            'loggedAt': '2026-09-25T10:23:00.000Z',
            'sessionExerciseId': 'sx-run',
            'exerciseId': 'ex-run',
            'startedAt': '2026-09-25T10:03:00.000Z',
            'endedAt': '2026-09-25T10:23:00.000Z',
          },
          {
            'entryId': 'e-plank',
            'eventId': 'e-plank',
            'kind': 'hold',
            'loggedAt': '2026-09-25T10:25:00.000Z',
            'sessionExerciseId': 'sx-plank',
            'exerciseId': 'ex-plank',
            'startedAt': '2026-09-25T10:24:00.000Z',
            'endedAt': '2026-09-25T10:25:00.000Z',
          },
          {
            'entryId': 'e-bjj',
            'eventId': 'e-bjj',
            'kind': 'round',
            'loggedAt': '2026-09-25T10:31:00.000Z',
            'sessionExerciseId': 'sx-bjj',
            'exerciseId': 'ex-bjj',
            'startedAt': '2026-09-25T10:26:00.000Z',
            'endedAt': '2026-09-25T10:31:00.000Z',
            'roundNumber': 1,
          },
          _end(
            sid,
            startedAt: '2026-09-25T10:00:00.000Z',
            endedAt: '2026-09-25T10:35:00.000Z',
          ),
        ]);

        final phoneEfforts = {
          for (final e in await importedEfforts(repository, phoneSessionId))
            e.exerciseId: e,
        };
        final wristEfforts = {
          for (final e in await importedEfforts(repository, sid))
            e.exerciseId: e,
        };
        expect(
          wristEfforts.keys.toSet(),
          phoneEfforts.keys.toSet(),
          reason: 'S-274 the same exercises on both sides',
        );

        // An observation's shape: everything but its ids and timestamps, with
        // the id reduced to the pattern it follows after the effort id.
        Future<List<Map<String, dynamic>>> observationShapes(
          SegmentEffort effort,
        ) async => [
          for (final o in await sortedObservations(repository, effort.id))
            {
              ...o.toMap()..removeWhere(
                (key, _) => const {
                  'id',
                  'effort_id',
                  'created_at_ms',
                  'updated_at_ms',
                }.contains(key),
              ),
              'idPattern': o.id.replaceFirst(
                'obs-${effort.id}-',
                'obs-<effort>-',
              ),
            },
        ];
        // An instance's shape: everything but its ids and timestamps.
        const instanceIdsAndStamps = {
          'id',
          'effort_id',
          'started_at_ms',
          'finished_at_ms',
          'created_at_ms',
          'updated_at_ms',
        };
        Future<List<Map<String, dynamic>>> instanceShapes(
          SegmentEffort effort,
        ) async => [
          for (final t in await repository.getTimedInstances(effort.id))
            t.toMap()..removeWhere((k, _) => instanceIdsAndStamps.contains(k)),
          for (final r in await repository.getRoundInstances(effort.id))
            r.toMap()..removeWhere((k, _) => instanceIdsAndStamps.contains(k)),
        ];

        for (final exerciseId in phoneEfforts.keys) {
          final phone = phoneEfforts[exerciseId]!;
          final wrist = wristEfforts[exerciseId]!;
          expect(
            wrist.effortKind,
            phone.effortKind,
            reason: 'S-274 $exerciseId: effort kind',
          );
          expect(
            await observationShapes(wrist),
            await observationShapes(phone),
            reason:
                'S-274 $exerciseId: metric, unit, values, id pattern and '
                'companion rows',
          );
          expect(
            await instanceShapes(wrist),
            await instanceShapes(phone),
            reason: 'S-274 $exerciseId: instance state and fields',
          );
        }
      },
    );
  });

  group('the phone’s own rating (D-138, D-139 state half)', () {
    // The wrist's rating can reach the phone before its session end (then the
    // import chooses) or after it (then the top-up does): the phone's own
    // rating wins either way (D-138).
    final set = _set('e-l1', loggedAt: '2026-09-25T10:05:00.000Z');
    final end = _end(
      's-live-1',
      startedAt: '2026-09-25T10:00:00.000Z',
      endedAt: '2026-09-25T10:20:00.000Z',
    );
    final wristRating = _rating(
      's-live-1',
      5,
      loggedAt: '2026-09-25T10:20:10.000Z',
    );
    for (final order in {
      'the wrist rating after its session end': [set, end, wristRating],
      'the wrist rating before its session end': [set, wristRating, end],
    }.entries) {
      test('S-281 staged before the import, it wins over the wrist’s '
          '(${order.key})', () async {
        final repository = await _repository();
        final inbox = _inbox(repository, CaptureTransport());

        await inbox.recordPhoneRating('s-live-1', 3);
        expect(
          await repository.getWatchInboxEntry(
            WatchInboxEntry.phoneRatingId('s-live-1'),
          ),
          isNotNull,
          reason: 'S-281 staged as the phone’s own while nothing is imported',
        );

        await _deliverEach(inbox, 's-live-1', order.value);

        expect(
          (await repository.getSession('s-live-1'))!.sessionFeeling,
          3,
          reason: 'S-281 the phone’s rating is the one history keeps',
        );
      });
    }

    test('S-284 after the import, it is written to the session', () async {
      final repository = await _repository();
      var refreshes = 0;
      final inbox = _inbox(
        repository,
        CaptureTransport(),
        onHistoryChanged: () async => refreshes++,
      );
      await _deliverEach(inbox, _capId, captureEvents('full'));
      final refreshesAfterImport = refreshes;

      await inbox.recordPhoneRating(_capId, 2);

      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        2,
        reason: 'S-284 the answer is written to sessionFeeling directly',
      );
      expect(
        await repository.getWatchInboxEntry(
          WatchInboxEntry.phoneRatingId(_capId),
        ),
        isNull,
        reason: 'S-284 nothing is staged for an imported session',
      );
      expect(
        refreshes,
        refreshesAfterImport + 1,
        reason:
            'F-8 a rating written straight to an imported session is a '
            'history change, so the calendar refreshes (D-142)',
      );
    });

    // A-50: the rating scale is 1–5 (D-102), and a rating off it is not a
    // rating — nothing is staged for the wrist to lose to, and nothing a
    // session already in history holds is replaced.
    test('A-50 a rating off the scale is refused before the import', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      for (final rating in [0, -1, 6, 99]) {
        expect(
          await inbox.recordPhoneRating('s-live-1', rating),
          isFalse,
          reason: 'A-50 $rating is not on the 1–5 scale',
        );
      }
      expect(
        await repository.getWatchInboxEntry(
          WatchInboxEntry.phoneRatingId('s-live-1'),
        ),
        isNull,
        reason: 'A-50 nothing was staged for the wrist to lose to',
      );
    });

    test('A-50 a rating off the scale is refused after the import', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());
      await _deliverEach(inbox, _capId, captureEvents('full'));

      expect(
        await inbox.recordPhoneRating(_capId, 6),
        isFalse,
        reason: 'A-50 6 is not on the 1–5 scale',
      );

      expect(
        (await repository.getSession(_capId))!.sessionFeeling,
        4,
        reason: 'A-50 the wrist’s 4 stands: a refusal is not a write',
      );
    });

    test('A-50 the ends of the scale are ratings', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      for (final rating in [1, 5]) {
        final sessionId = 's-live-$rating';
        expect(
          await inbox.recordPhoneRating(sessionId, rating),
          isTrue,
          reason: 'A-50 $rating is on the 1–5 scale',
        );
        expect(
          (await repository.getWatchInboxEntry(
            WatchInboxEntry.phoneRatingId(sessionId),
          ))!.payload['rating'],
          rating,
          reason: 'A-50 $rating is staged as the phone’s own',
        );
      }
    });

    test(
      'A-50 the ends of the scale are ratings after the import too',
      () async {
        final repository = await _repository();
        final inbox = _inbox(repository, CaptureTransport());
        await _deliverEach(inbox, _capId, captureEvents('full'));

        for (final rating in [1, 5]) {
          expect(
            await inbox.recordPhoneRating(_capId, rating),
            isTrue,
            reason: 'A-50 $rating is on the 1–5 scale',
          );
          expect(
            (await repository.getSession(_capId))!.sessionFeeling,
            rating,
            reason: 'A-50 the session takes $rating',
          );
        }
      },
    );

    // F-8, review N2: the refresh must run *after* the write. A refresh ahead
    // of it leaves the calendar showing the rating history no longer holds.
    test('F-8 the calendar shows the rating the write left', () async {
      final repository = await _repository();
      final calendar = await septemberCalendar(repository);
      final inbox = _inbox(
        repository,
        CaptureTransport(),
        onHistoryChanged: calendar.refresh,
      );
      await _deliverEach(inbox, _capId, captureEvents('full'));
      expect(
        calendarEntryIn(calendar, _capId)?.session?.sessionFeeling,
        4,
        reason: 'F-8 the import left the wrist’s rating (S-261)',
      );

      await inbox.recordPhoneRating(_capId, 2);

      expect(
        calendarEntryIn(calendar, _capId)?.session?.sessionFeeling,
        2,
        reason:
            'F-8 the refresh runs after the write, so the calendar holds the '
            'phone’s rating (D-142)',
      );
    });
  });

  group('A-51 the user’s own rows in an imported effort are never '
      'overwritten or moved', () {
    // The user adds rows of their own to an imported effort in history; a wrist
    // entry for that effort arrives later (a late delivery, or a reopened
    // session, S-218). Before A-51 the late entry took its logged-order
    // position — the one the user's row had just taken — and overwrote it.
    String effortOf(String slot, String exercise, String kind) =>
        WatchSessionImporter.effortIdFor(_capId, slot, exercise, kind);
    final bench = effortOf('sx-bench', 'ex-bench', 'set');

    /// F-CAP imported, then opened in history the phone's way.
    Future<
      (MockWorkoutRepository, WatchSessionInbox, CaptureTransport, WorkoutState)
    >
    imported() async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);
      await _deliverEach(inbox, _capId, captureEvents('full'));
      final workout = WorkoutState(repository);
      await workout.loadHistoricalSession(_capId);
      return (repository, inbox, transport, workout);
    }

    Future<List<Object?>> setAt(
      WorkoutRepository repository,
      int index,
    ) async => [
      (await observationAt(repository, bench, index, 'reps'))?.valueInt,
      (await observationAt(repository, bench, index, 'weight'))?.valueReal,
    ];

    /// The phone's own change to a wrist entry, staged as the live screen's
    /// transport stages it (D-137).
    Map<String, Object?> change(String changeId, Map<String, Object?> body) => {
      'type': 'structure_change',
      'sessionId': _capId,
      'payload': {
        'changeId': changeId,
        'changes': [body],
      },
    };

    test('A-51 a late wrist set is placed after the user’s own set, '
        'which keeps its values', () async {
      final (repository, inbox, transport, workout) = await imported();
      await workout.addEntry(
        bench,
        previousValues: {'reps': 8, 'weight': 100.0},
      );
      expect(
        await setAt(repository, 3),
        [8, 100.0],
        reason: 'A-51 the user’s set is the effort’s fourth row',
      );

      await _deliverEach(inbox, _capId, [
        _set('e-set4', loggedAt: '2026-09-25T10:52:00.000Z', reps: 6),
      ], tag: 'late');

      expect(
        await setAt(repository, 3),
        [8, 100.0],
        reason: 'A-51 the user’s set is never overwritten',
      );
      expect(
        await setAt(repository, 4),
        [6, 80.0],
        reason: 'A-51 the late wrist set is placed after it',
      );
      expect(
        [for (var i = 0; i < 3; i++) (await setAt(repository, i)).first],
        [5, 5, 5],
        reason: 'A-51 the imported sets keep their places',
      );
      expect(
        transport.receiptedEntryIds,
        contains('e-set4'),
        reason: 'A-51 the late set is history, so it is acknowledged',
      );
    });

    test(
      'A-51 a late wrist set logged before the others moves nothing',
      () async {
        final (repository, inbox, _, workout) = await imported();
        await workout.addEntry(
          bench,
          previousValues: {'reps': 8, 'weight': 100.0},
        );

        await _deliverEach(inbox, _capId, [
          _set('e-set0', loggedAt: '2026-09-25T10:44:00.000Z', reps: 7),
        ], tag: 'late');

        expect(
          await setAt(repository, 3),
          [8, 100.0],
          reason: 'A-51 the user’s set is never overwritten or moved',
        );
        expect(
          [for (var i = 0; i < 3; i++) (await setAt(repository, i)).first],
          [5, 5, 5],
          reason: 'A-51 nothing already in the effort moves',
        );
        expect(
          await setAt(repository, 4),
          [7, 80.0],
          reason: 'A-51 the late set is placed after the effort’s last row',
        );
      },
    );

    test(
      'A-51 a set the user put where a deleted wrist set was stays there',
      () async {
        final (repository, inbox, _, workout) = await imported();
        // The user removes e-set3 in history, then adds a set of their own: the
        // phone places it at the lowest free index after the highest, which is
        // the one e-set3 held.
        await workout.deleteEntry(bench, 2);
        await workout.addEntry(
          bench,
          previousValues: {'reps': 8, 'weight': 100.0},
        );
        expect(await setAt(repository, 2), [
          8,
          100.0,
        ], reason: 'A-51 the user’s set took index 2');

        await _deliverEach(inbox, _capId, [
          _set('e-set0', loggedAt: '2026-09-25T10:44:00.000Z', reps: 7),
        ], tag: 'late');

        expect(
          await setAt(repository, 2),
          [8, 100.0],
          reason:
              'A-51 the user’s set is never taken for the wrist set it replaced',
        );
        expect(
          [for (var i = 0; i < 2; i++) (await setAt(repository, i)).first],
          [5, 5],
          reason: 'A-51 e-set1 and e-set2 stay where they are',
        );
        expect(
          await setAt(repository, 3),
          [7, 80.0],
          reason: 'A-51 the late set is placed after the effort’s last row',
        );
        expect(
          await observationAt(repository, bench, 4, 'reps'),
          isNull,
          reason: 'A-51 e-set3, which the user deleted, is not re-created',
        );
      },
    );

    test('A-51 a late wrist run is placed after the user’s own timed entry, '
        'which keeps its distance', () async {
      final (repository, inbox, _, workout) = await imported();
      final run = effortOf('sx-run', 'ex-run', 'timed');
      await workout.addEntry(run, previousValues: {'distance': 5000.0});
      expect(
        (await observationAt(repository, run, 1, 'distance'))?.valueReal,
        5000.0,
        reason: 'A-51 the user’s timed entry is the effort’s second row',
      );

      await _deliverEach(inbox, _capId, [
        {
          'entryId': 'e-run2',
          'eventId': 'e-run2',
          'kind': 'timed',
          'loggedAt': '2026-09-25T10:54:00.000Z',
          'sessionExerciseId': 'sx-run',
          'exerciseId': 'ex-run',
          'startedAt': '2026-09-25T10:52:00.000Z',
          'endedAt': '2026-09-25T10:54:00.000Z',
          'distanceMeters': 400,
        },
      ], tag: 'late');

      expect(
        (await observationAt(repository, run, 1, 'distance'))?.valueReal,
        5000.0,
        reason: 'A-51 the user’s timed entry is never overwritten',
      );
      expect(
        (await observationAt(repository, run, 2, 'distance'))?.valueReal,
        400.0,
        reason: 'A-51 the late run is placed after it',
      );
      final instances = await repository.getTimedInstances(run);
      expect(
        instances
            .singleWhere(
              (t) =>
                  t.id ==
                  WatchSessionImporter.timedInstanceIdFor(_capId, 'e-run2'),
            )
            .entryIndex,
        2,
        reason: 'A-51 its instance is where its rows are',
      );
      expect(
        [for (final t in instances) t.entryIndex]..sort(),
        [0, 1, 2],
        reason: 'A-51 no two timed entries share a place',
      );
    });

    test('A-51 a late wrist round takes the next free round, never one the '
        'user added', () async {
      final (repository, inbox, _, workout) = await imported();
      final bjj = effortOf('sx-bjj', 'ex-bjj', 'round');
      await workout.addEntry(bjj);
      final users = [
        for (final r in await repository.getRoundInstances(bjj))
          if (!r.id.startsWith('round-$_capId-')) r,
      ];
      expect(users, hasLength(1), reason: 'A-51 the user added one round');
      expect(users.single.roundIndex, 3, reason: 'A-51 as the fourth');

      await _deliverEach(inbox, _capId, [
        {
          'entryId': 'e-r4',
          'eventId': 'e-r4',
          'kind': 'round',
          'loggedAt': '2026-09-25T10:54:00.000Z',
          'sessionExerciseId': 'sx-bjj',
          'exerciseId': 'ex-bjj',
          'startedAt': '2026-09-25T10:52:00.000Z',
          'endedAt': '2026-09-25T10:54:00.000Z',
          'roundNumber': 4,
        },
      ], tag: 'late');

      final rounds = await repository.getRoundInstances(bjj);
      expect(
        rounds.singleWhere((r) => r.id == users.single.id).toMap(),
        users.single.toMap(),
        reason: 'A-51 the user’s round is untouched',
      );
      expect(
        rounds
            .singleWhere(
              (r) =>
                  r.id ==
                  WatchSessionImporter.roundInstanceIdFor(_capId, 'e-r4'),
            )
            .roundIndex,
        4,
        reason: 'A-51 the late round takes the next free place',
      );
      expect(
        [for (final r in rounds) r.roundIndex]..sort(),
        [0, 1, 2, 3, 4],
        reason: 'A-51 no two rounds share a place',
      );
    });

    test('A-51 a later correction of a wrist set placed after the user’s '
        'reaches that set only', () async {
      final (repository, inbox, _, workout) = await imported();
      await workout.addEntry(
        bench,
        previousValues: {'reps': 8, 'weight': 100.0},
      );
      await _deliverEach(inbox, _capId, [
        _set('e-set4', loggedAt: '2026-09-25T10:52:00.000Z', reps: 6),
      ], tag: 'late');

      await inbox.stagePhoneChanges(
        change('chg-a51-correct', {
          'kind': 'correct_entry',
          'entryId': 'e-set4',
          'correction': {'reps': 9},
        }),
      );

      expect(
        await setAt(repository, 4),
        [9, 80.0],
        reason: 'A-51 the correction reaches the wrist set it names (D-137)',
      );
      expect(await setAt(repository, 3), [
        8,
        100.0,
      ], reason: 'A-51 and never the user’s set');
    });

    test('A-51 a later deletion of a wrist set placed after the user’s '
        'removes that set only', () async {
      final (repository, inbox, _, workout) = await imported();
      await workout.addEntry(
        bench,
        previousValues: {'reps': 8, 'weight': 100.0},
      );
      await _deliverEach(inbox, _capId, [
        _set('e-set4', loggedAt: '2026-09-25T10:52:00.000Z', reps: 6),
      ], tag: 'late');

      await inbox.stagePhoneChanges(
        change('chg-a51-delete', {'kind': 'delete_entry', 'entryId': 'e-set4'}),
      );

      expect(
        await setAt(repository, 4),
        [null, null],
        reason: 'A-51 the deletion removes the wrist set it names (D-137)',
      );
      expect(await setAt(repository, 3), [
        8,
        100.0,
      ], reason: 'A-51 and never the user’s set');
    });

    test('A-51 a late wrist set a failed pass half-wrote is finished where it '
        'was put, not added twice', () async {
      final repository = _FailOnceRepository();
      await repository.initialize();
      await seedCaptureCatalog(repository);
      final failures = <Object>[];
      var ids = 0;
      final inbox = WatchSessionInbox(
        repository: repository,
        transport: CaptureTransport(),
        validator: loadProtocolValidator(),
        clock: () => _phoneNow,
        idFactory: () => 'msg-phone-${++ids}',
        onFailure: (error, _) => failures.add(error),
      );
      await _deliverEach(inbox, _capId, captureEvents('full'));
      final workout = WorkoutState(repository);
      await workout.loadHistoricalSession(_capId);
      await workout.addEntry(
        bench,
        previousValues: {'reps': 8, 'weight': 100.0},
      );

      final late = _set(
        'e-set4',
        loggedAt: '2026-09-25T10:52:00.000Z',
        reps: 6,
      );
      repository.failOn = 'obs-$bench-4-weight';
      await _deliverEach(inbox, _capId, [late], tag: 'late');
      expect(failures, hasLength(1), reason: 'A-51 the pass stopped half-way');
      expect(
        await setAt(repository, 4),
        [6, null],
        reason: 'A-51 it wrote the reps and not the weight',
      );

      // No receipt went back, so the wrist sends it again.
      await _deliverEach(inbox, _capId, [late], tag: 'resent');
      expect(failures, hasLength(1), reason: 'A-51 the second pass completes');
      expect(
        await setAt(repository, 4),
        [6, 80.0],
        reason: 'A-51 the half-written set is finished where it was put',
      );
      expect(
        await observationAt(repository, bench, 5, 'reps'),
        isNull,
        reason: 'A-51 and is not added a second time',
      );
      expect(await setAt(repository, 3), [
        8,
        100.0,
      ], reason: 'A-51 the user’s set is untouched');
    });

    test('A-51 deleting every wrist entry of an effort keeps the user’s own '
        'rows and the effort', () async {
      final (repository, inbox, _, workout) = await imported();
      await workout.addEntry(
        bench,
        previousValues: {'reps': 8, 'weight': 100.0},
      );

      for (final entryId in const ['e-set1', 'e-set2', 'e-set3']) {
        await inbox.stagePhoneChanges(
          change('chg-a51-$entryId', {
            'kind': 'delete_entry',
            'entryId': entryId,
          }),
        );
      }

      expect(
        [for (var i = 0; i < 3; i++) (await setAt(repository, i)).first],
        [null, null, null],
        reason: 'A-51 every wrist set the phone deleted is gone',
      );
      expect(
        await setAt(repository, 3),
        [8, 100.0],
        reason: 'A-51 the user’s set stays, and with it the effort',
      );
    });
  });

  group('what the inbox stages (D-132)', () {
    test('D-132 a nutrition quick-log is never staged', () async {
      final repository = await _repository();
      final result = await _inbox(repository, CaptureTransport()).receive(
        observationsUp('nutrition-2026-09-25', [
          {
            'entryId': 'e-food-1',
            'eventId': 'e-food-1',
            'kind': 'nutrition_quick_log',
            'loggedAt': '2026-09-25T12:00:00.000Z',
            'foodId': 'food-oatmeal',
            'servings': 1,
          },
        ], messageId: 'msg-food'),
      );

      expect(
        result.outcome,
        WatchInboxOutcome.ignored,
        reason: 'D-132 a quick-log is the nutrition bridge alone',
      );
      expect(
        await repository.getWatchInboxEntry('e-food-1'),
        isNull,
        reason: 'D-132 nothing is staged',
      );
    });

    test('D-132 a message the gate refuses stages nothing', () async {
      final repository = await _repository();
      final message = observationsUp(_capId, [
        _eventOf('full', 'e-set1'),
      ], messageId: 'msg-v2');
      message['protocolVersion'] = 2;

      final result = await _inbox(
        repository,
        CaptureTransport(),
      ).receive(message);

      expect(
        result.outcome,
        WatchInboxOutcome.refused,
        reason: 'D-132 the gate refuses a v2 message',
      );
      expect(
        await repository.getWatchInboxEntry('e-set1'),
        isNull,
        reason: 'D-132 nothing is staged',
      );
    });

    test(
      'A-3 a snapshot entry missing its kind’s fields is not staged',
      () async {
        final repository = await _repository();
        final result = await _inbox(repository, CaptureTransport()).receive({
          'protocolVersion': SyncProtocolValidator.protocolVersion,
          'messageId': 'msg-snapshot-partial',
          'sessionId': 's-snap',
          'type': 'session_snapshot',
          'origin': 'watch',
          'sentAt': '2026-09-25T11:00:00Z',
          'payload': {
            'sessionId': 's-snap',
            'status': 'completed',
            'revision': 0,
            'currentExerciseIndex': 0,
            'exercises': const <Object?>[],
            'entries': [
              _set('e-snap-1', loggedAt: '2026-09-25T10:05:00.000Z'),
              {
                'entryId': 'rating-s-snap',
                'eventId': 'rating-s-snap',
                'kind': 'effort_rating',
                'loggedAt': '2026-09-25T10:30:00.000Z',
              },
              {
                'entryId': 'end-s-snap',
                'eventId': 'end-s-snap',
                'kind': 'session_end',
                'loggedAt': '2026-09-25T10:30:00.000Z',
                'startedAt': '2026-09-25T10:00:00.000Z',
              },
            ],
            'timers': const <String, Object?>{},
          },
        });

        expect(
          result.outcome,
          WatchInboxOutcome.staged,
          reason: 'A-3 the complete entry is staged',
        );
        expect(result.stagedEntryIds, [
          'e-snap-1',
        ], reason: 'A-3 only the complete entry');
        expect(
          await repository.getWatchInboxEntry('rating-s-snap'),
          isNull,
          reason: 'A-3 a rating without its value is not staged',
        );
        expect(
          await repository.getWatchInboxEntry('end-s-snap'),
          isNull,
          reason: 'A-3 an end without its times and status is not staged',
        );
      },
    );

    test('D-132 a wrist snapshot alone is enough to import', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      await _inbox(repository, transport).receive({
        'protocolVersion': SyncProtocolValidator.protocolVersion,
        'messageId': 'msg-snapshot-whole',
        'sessionId': 's-snap-1',
        'type': 'session_snapshot',
        'origin': 'watch',
        'sentAt': '2026-09-25T11:00:00Z',
        'payload': {
          'sessionId': 's-snap-1',
          'status': 'completed',
          'revision': 0,
          'currentExerciseIndex': 0,
          'exercises': const <Object?>[],
          'entries': [
            _set('e-snap-2', loggedAt: '2026-09-25T10:05:00.000Z'),
            _end(
              's-snap-1',
              startedAt: '2026-09-25T10:00:00.000Z',
              endedAt: '2026-09-25T10:30:00.000Z',
            ),
            _rating('s-snap-1', 2, loggedAt: '2026-09-25T10:30:10.000Z'),
          ],
          'timers': const <String, Object?>{},
        },
      });

      expect(
        (await repository.getSession('s-snap-1'))?.sessionFeeling,
        2,
        reason: 'D-132 the snapshot session is imported with its rating',
      );
      expect(
        transport.receiptedEntryIds.toSet(),
        {'e-snap-2', 'end-s-snap-1', 'rating-s-snap-1'},
        reason: 'D-132 the snapshot entries are acknowledged',
      );
    });
  });
}
