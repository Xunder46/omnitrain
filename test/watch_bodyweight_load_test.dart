// A bodyweight exercise's added weight survives the wire, both ways (plan 52c).
//
// A set of an exercise without the `load` capability (Push-Up) keeps its added
// weight — or a negative band assist — in the set's extra-weight row; the wire
// carries it as the set's `loadKg`. Plan:
// `docs/plans/2026-10-21-52c-phone-bodyweight-load-plan/2026-10-21-52c-phone-bodyweight-load-plan.md`
// (D-1..D-4). Scenario mapping:
//   S-8001 a wrist push-up set with `loadKg` 10 keeps it in the extra-weight
//        row, the weight row at 0; a bench set is unchanged  → `S-8001 ...`
//   S-8002 an assist: `loadKg` -20 lands in the extra-weight row → `S-8002 ...`
//   S-8003 the same wrist set delivered twice stays one set of rows, and a
//        changed `loadKg` rewrites the extra-weight row → `S-8003 ...`
//   S-8004 a correction of `loadKg` edits the extra-weight row (push-up) and
//        still the weight row (bench)                    → `S-8004 ...`
//   S-8005 a wrist set fills a phone-planned push-up row with its `loadKg`
//                                                          → `S-8005 ...`
//   S-8006 the projection carries a no-load set's extra-weight as `loadKg`
//        (0 omits the key, below the floor omits the entry) → `S-8006 ...`
//   S-8007 the bridge's `plannedSets` carry the extra-weight row → `S-8007 ...`
//   S-8008 round trip: the wrist's own set is not sent back → `S-8008 ...`
//   S-8009 a loadKg correction staged before the import stamps the
//        extra-weight row (push-up) / the weight row (bench) → `S-8009 ...`
//   S-8010 a pass that did not finish is recognised: the entry rewrites its
//        own rows, no second copy                       → `S-8010 ...`
//   S-8011 the bridge's entries carry the extra-weight row as loadKg
//                                                          → `S-8011 ...`
//
// The importer scenarios copy the harness of `test/watch_session_import_test.dart`
// (S-274 seeds `ex-pushup` with `['sets','reps']`; S-267 stages a correction;
// A-51 stages a phone change through the inbox). The projection scenarios copy
// the wiring of `test/watch_session_projection_test.dart` (S-3621) and
// `test/watch_session_merge_test.dart` (S-3604's fill). Plain `test()`
// everywhere: no widget is involved, and no real clock is awaited.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/phone_entries.dart';
import 'package:omnitrain/core/sync_protocol/wire_limits.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/sync_protocol_harness.dart' show loadProtocolValidator;
import 'helpers/watch_capture_import_harness.dart';

/// The phone's clock: fixed, so every stamp is the same in every order.
final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// The stamp the phone's planned rows carry: earlier than every wrist set's.
const String _plannedAt = '2026-09-25T09:00:00.000Z';

/// The capture catalog plus the no-load exercise these scenarios run on.
Future<MockWorkoutRepository> _repository() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedCaptureCatalog(repository);
  await seedExercise(
    repository,
    id: 'ex-pushup',
    name: 'Push-up',
    capabilities: const ['sets', 'reps'],
  );
  return repository;
}

WatchSessionInbox _inbox(
  WorkoutRepository repository,
  CaptureTransport transport, {
  DateTime Function()? clock,
  bool Function(String sessionId)? phoneOwnsSession,
  Future<void> Function(String sessionId, Iterable<String> effortIds)?
  onSessionRowsChanged,
}) {
  var ids = 0;
  return WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: loadProtocolValidator(),
    clock: clock ?? () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    // A failure inside the inbox fails the test where it happened.
    onFailure: Error.throwWithStackTrace,
    phoneOwnsSession: phoneOwnsSession,
    onSessionRowsChanged: onSessionRowsChanged,
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
}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': endedAt,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'status': 'completed',
};

/// A `structure_change` the phone stages for a session already in history,
/// the way the live screen's transport stages one (D-137, A-51's staging).
Map<String, Object?> _correction(
  String sessionId,
  String changeId,
  String entryId,
  Map<String, Object?> correction,
) => {
  'type': 'structure_change',
  'sessionId': sessionId,
  'payload': {
    'changeId': changeId,
    'changes': [
      {'kind': 'correct_entry', 'entryId': entryId, 'correction': correction},
    ],
  },
};

/// The effort a wrist set of [slot]/[exerciseId] lands in.
String _effortOf(String sessionId, String slot, String exerciseId) =>
    WatchSessionImporter.effortIdFor(sessionId, slot, exerciseId, 'set');

/// A set position's three row values, by metric key.
Future<Map<String, double?>> _rowValues(
  WorkoutRepository repository,
  String effortId,
  int index,
) async => {
  'reps': (await observationAt(repository, effortId, index, 'reps'))
      ?.valueInt
      ?.toDouble(),
  'weight': (await observationAt(repository, effortId, index, 'weight'))
      ?.valueReal,
  'extra-weight': (await observationAt(
    repository,
    effortId,
    index,
    'extra-weight',
  ))?.valueReal,
};

/// The extra-weight rows of [effortId], in id order.
Future<List<EffortObservation>> _extraWeightRows(
  WorkoutRepository repository,
  String effortId,
) async => [
  for (final row in await sortedObservations(repository, effortId))
    if (row.metricId == MetricIds.extraWeight) row,
];

/// One phone, wired the way `createWatchSync` wires it (the merge test's
/// `_phone`): the adoption bridge, the inbox that asks it whether a session is
/// the phone's own, the mirror behind the entry-staging transport, and the
/// router that drives them.
class _Phone {
  _Phone({
    required this.repository,
    required this.router,
    required this.bridge,
    required this.state,
  });

  final WorkoutRepository repository;
  final WatchIncomingRouter router;
  final WatchSessionAdoptionBridge bridge;
  final WorkoutState state;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _phoneNow,
    onFailure: Error.throwWithStackTrace,
  );
  final inbox = _inbox(
    repository,
    transport,
    phoneOwnsSession: bridge.holdsSession,
    onSessionRowsChanged: bridge.refreshHeldEfforts,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: loadProtocolValidator(),
    projection: bridge.projectSession,
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);
  return _Phone(
    repository: repository,
    router: WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: loadProtocolValidator(),
        transport: transport,
      ),
      adoption: bridge,
    ),
    bridge: bridge,
    state: state,
  );
}

/// One ladder slot as the wrist's adoption snapshot spells it.
Map<String, Object?> _slot(String id, String exerciseId, List<String> caps) => {
  'sessionExerciseId': id,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': caps,
};

/// A wrist `session_snapshot` adopting [sessionId], holding [slots], with no
/// entries of its own.
Map<String, Object?> _snapshot(
  String sessionId,
  List<Map<String, Object?>> slots,
) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-snapshot-$sessionId',
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-09-25T10:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': 1,
    'status': 'active',
    'currentExerciseIndex': 0,
    'exercises': slots,
    'entries': const <Object?>[],
    'timers': const <String, Object?>{},
  },
};

/// Writes [rows] the way every phone writer does.
Future<void> _writeRows(
  WorkoutRepository repository,
  List<EffortObservation> rows,
) async {
  for (final row in rows) {
    await repository.createObservation(row);
  }
}

void main() {
  group('S-8001..S-8005 the importer keeps a no-load set\'s loadKg in its '
      'extra-weight row', () {
    test('S-8001 a wrist push-up set with loadKg 10 keeps it in the '
        'extra-weight row, and a bench set is unchanged', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      await _deliverEach(inbox, 's-8001', [
        _set(
          'e-pu',
          loggedAt: '2026-09-25T10:10:00.000Z',
          slot: 'sx-pushup',
          exerciseId: 'ex-pushup',
          reps: 12,
          loadKg: 10,
        ),
        _set('e-bench', loggedAt: '2026-09-25T10:11:00.000Z', loadKg: 10),
        _end(
          's-8001',
          startedAt: '2026-09-25T10:00:00.000Z',
          endedAt: '2026-09-25T10:20:00.000Z',
        ),
      ]);

      final pushup = _effortOf('s-8001', 'sx-pushup', 'ex-pushup');
      expect(
        await _rowValues(repository, pushup, 0),
        {'reps': 12.0, 'weight': 0.0, 'extra-weight': 10.0},
        reason: 'S-8001 the push-up keeps its added weight where the phone '
            'keeps one, and the weight row stays 0',
      );
      expect(
        await sortedObservations(repository, pushup),
        hasLength(3),
        reason: 'S-8001 exactly the three rows a phone-logged push-up set has',
      );

      final bench = _effortOf('s-8001', 'sx-bench', 'ex-bench');
      expect(
        await _rowValues(repository, bench, 0),
        {'reps': 5.0, 'weight': 10.0, 'extra-weight': null},
        reason: 'S-8001 an exercise with load still writes the weight row and '
            'no extra-weight row',
      );
    });

    test('S-8002 a band assist lands in the extra-weight row with its sign',
        () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      await _deliverEach(inbox, 's-8002', [
        _set(
          'e-pu',
          loggedAt: '2026-09-25T10:10:00.000Z',
          slot: 'sx-pushup',
          exerciseId: 'ex-pushup',
          reps: 12,
          loadKg: -20,
        ),
        _end(
          's-8002',
          startedAt: '2026-09-25T10:00:00.000Z',
          endedAt: '2026-09-25T10:20:00.000Z',
        ),
      ]);

      final pushup = _effortOf('s-8002', 'sx-pushup', 'ex-pushup');
      expect(
        await _rowValues(repository, pushup, 0),
        {'reps': 12.0, 'weight': 0.0, 'extra-weight': -20.0},
        reason: 'S-8002 the assist is not clamped and does not touch the '
            'weight row',
      );
    });

    test('S-8003 the same wrist set delivered twice stays one set of rows, '
        'and a changed loadKg rewrites the extra-weight row', () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);
      final events = [
        _set(
          'e-pu',
          loggedAt: '2026-09-25T10:10:00.000Z',
          slot: 'sx-pushup',
          exerciseId: 'ex-pushup',
          reps: 12,
          loadKg: 10,
        ),
        _end(
          's-8003',
          startedAt: '2026-09-25T10:00:00.000Z',
          endedAt: '2026-09-25T10:20:00.000Z',
        ),
      ];
      final pushup = _effortOf('s-8003', 'sx-pushup', 'ex-pushup');

      await _deliverEach(inbox, 's-8003', events, tag: 'first');
      expect(
        await sortedObservations(repository, pushup),
        hasLength(3),
        reason: 'S-8003 the fixture: reps, weight, extra-weight',
      );

      // The wrist re-sends the same stream: put-if-absent refuses the copy,
      // the pass re-runs, and nothing doubles.
      final results = await _deliverEach(inbox, 's-8003', events, tag: 'second');
      expect(
        results.map((r) => r.outcome),
        everyElement(WatchInboxOutcome.unchanged),
        reason: 'S-8003 the resend is refused by put-if-absent',
      );
      expect(
        await sortedObservations(repository, pushup),
        hasLength(3),
        reason: 'S-8003 still exactly one set of rows',
      );

      // A changed loadKg reaches the row the way a phone correction does
      // (D-137): the wire's put-if-absent refuses an altered copy of the same
      // entry, so a changed value can only arrive as a correction (S-267's
      // staging, A-51's path).
      await inbox.stagePhoneChanges(
        _correction('s-8003', 'chg-8003', 'e-pu', {'loadKg': 15}),
      );
      final extras = await _extraWeightRows(repository, pushup);
      expect(
        extras,
        hasLength(1),
        reason: 'S-8003 the rewrite edited the row, it did not add one',
      );
      expect(
        extras.single.valueReal,
        15.0,
        reason: 'S-8003 the extra-weight row holds the changed load',
      );
      expect(
        (await observationAt(repository, pushup, 0, 'weight'))?.valueReal,
        0.0,
        reason: 'S-8003 the weight row is untouched',
      );
    });

    test('S-8004 a correction of loadKg staged after the import edits the '
        'extra-weight row, and a bench correction still edits the weight row',
        () async {
      final repository = await _repository();
      final transport = CaptureTransport();
      final inbox = _inbox(repository, transport);

      await _deliverEach(inbox, 's-8004', [
        _set(
          'e-pu',
          loggedAt: '2026-09-25T10:10:00.000Z',
          slot: 'sx-pushup',
          exerciseId: 'ex-pushup',
          reps: 12,
          loadKg: 10,
        ),
        _set('e-bench', loggedAt: '2026-09-25T10:11:00.000Z', loadKg: 80),
        _end(
          's-8004',
          startedAt: '2026-09-25T10:00:00.000Z',
          endedAt: '2026-09-25T10:20:00.000Z',
        ),
      ]);

      await inbox.stagePhoneChanges(
        _correction('s-8004', 'chg-pu', 'e-pu', {'loadKg': 25}),
      );
      await inbox.stagePhoneChanges(
        _correction('s-8004', 'chg-bench', 'e-bench', {'loadKg': 85}),
      );

      final pushup = _effortOf('s-8004', 'sx-pushup', 'ex-pushup');
      expect(
        await _rowValues(repository, pushup, 0),
        {'reps': 12.0, 'weight': 0.0, 'extra-weight': 25.0},
        reason: 'S-8004 the push-up\'s correction edits the extra-weight row '
            'and leaves the weight row at 0',
      );
      final bench = _effortOf('s-8004', 'sx-bench', 'ex-bench');
      expect(
        await _rowValues(repository, bench, 0),
        {'reps': 5.0, 'weight': 85.0, 'extra-weight': null},
        reason: 'S-8004 the bench\'s correction still edits the weight row',
      );
    });

    test('S-8005 a wrist set fills a phone-planned push-up row with its '
        'loadKg', () async {
      final repository = await _repository();
      final phone = await _phone(repository);
      await phone.router.receive(
        _snapshot('s-8005', [_slot('sl-1', 'ex-pushup', const ['sets', 'reps'])]),
      );
      expect(
        phone.state.currentSession?.id,
        's-8005',
        reason: 'S-8005 the fixture: the phone holds the session',
      );

      // The routine's planned row: reps 10, weight 0, extra-weight 5.
      await _writeRows(
        repository,
        LoggedEntryRows.setObservations(
          effortId: 'sl-1',
          entryIndex: 0,
          reps: 10,
          weightKg: 0,
          exerciseHasLoad: false,
          extraWeightKg: 5,
          atMs: _msOf(_plannedAt),
        ),
      );

      await phone.router.receive(
        observationsUp('s-8005', [
          _set(
            'sx-1',
            loggedAt: '2026-09-25T10:10:00.000Z',
            slot: 'sl-1',
            exerciseId: 'ex-pushup',
            reps: 8,
            loadKg: 12.5,
          ),
        ], messageId: 'msg-fill-1'),
      );

      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        rows,
        hasLength(3),
        reason: 'S-8005 one set at the position: reps, weight, extra-weight',
      );
      expect(
        await _rowValues(repository, 'sl-1', 0),
        {'reps': 8.0, 'weight': 0.0, 'extra-weight': 12.5},
        reason: 'S-8005 the filled row holds the wrist\'s reps and its loadKg '
            'as the added weight',
      );
      expect(
        [for (final row in rows) row.valueReal],
        isNot(contains(5.0)),
        reason: 'S-8005 no row of the planned group is left over',
      );
    });
  });

  group('S-8006..S-8008 the projection carries the extra-weight row as loadKg', () {
    /// One no-load or with-load set, projected pure (S-8006's arrangement).
    List<Map<String, Object?>> projectOne({
      required bool exerciseHasLoad,
      required double weightKg,
      required double extraWeightKg,
    }) {
      final rows = LoggedEntryRows.setObservations(
        effortId: 'effort-1',
        entryIndex: 0,
        reps: 10,
        weightKg: weightKg,
        exerciseHasLoad: exerciseHasLoad,
        extraWeightKg: extraWeightKg,
        atMs: _msOf(_plannedAt),
      );
      return PhoneEntries.project(
        sessionExerciseId: 'sx-1',
        exerciseId: 'ex-1',
        groups: EntryRows.setGroups(rows),
        wristLoggedAtMs: const [],
        loggedNumbers: const {0},
        exerciseHasLoad: exerciseHasLoad,
      );
    }

    test('S-8006 a no-load set\'s extra-weight rides as loadKg, a with-load '
        'set\'s weight does, 0 omits the key, and below the floor omits the '
        'entry', () {
      final pushup = projectOne(
        exerciseHasLoad: false,
        weightKg: 0,
        extraWeightKg: 12.5,
      );
      expect(pushup, hasLength(1), reason: 'S-8006 the fixture: one entry');
      expect(
        pushup.single['loadKg'],
        12.5,
        reason: 'S-8006 the added weight is what loadKg carries',
      );

      final bench = projectOne(
        exerciseHasLoad: true,
        weightKg: 60,
        extraWeightKg: 0,
      );
      expect(
        bench.single['loadKg'],
        60.0,
        reason: 'S-8006 an exercise with load still sends its weight row',
      );

      final zero = projectOne(
        exerciseHasLoad: false,
        weightKg: 0,
        extraWeightKg: 0,
      );
      expect(
        zero.single.containsKey('loadKg'),
        isFalse,
        reason: 'S-8006 an added weight of exactly 0 carries no loadKg, as a '
            'weight of 0 does not',
      );

      final assist = projectOne(
        exerciseHasLoad: false,
        weightKg: 0,
        extraWeightKg: -10,
      );
      expect(
        assist.single['loadKg'],
        -10.0,
        reason: 'S-8006 an assist is carried with its sign',
      );

      expect(
        projectOne(
          exerciseHasLoad: false,
          weightKg: 0,
          extraWeightKg: WireLimits.minLoadKg - 0.1,
        ),
        isEmpty,
        reason: 'S-8006 a value below the wire floor omits the entry, as a '
            'weight below it does',
      );
    });

    test('S-8007 the bridge\'s plannedSets carry the extra-weight row for a '
        'no-load slot, and the bench\'s rows their weight', () async {
      final repository = await _repository();
      const start = 1788000000000;
      await repository.createSession(
        TrainingSession(
          id: 's-8007',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: start,
          endedAtMs: null,
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await repository.createSegment(
        LoggedEntryRows.defaultSegment(
          id: 'segment-s-8007',
          sessionId: 's-8007',
          atMs: start,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: 'sl-pushup',
          segmentId: 'segment-s-8007',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: 'ex-pushup',
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: 'sl-bench',
          segmentId: 'segment-s-8007',
          orderIndex: 1,
          effortKind: 'set',
          exerciseId: 'ex-bench',
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      for (var index = 0; index < 3; index++) {
        await _writeRows(
          repository,
          LoggedEntryRows.setObservations(
            effortId: 'sl-pushup',
            entryIndex: index,
            reps: 10,
            weightKg: 0,
            exerciseHasLoad: false,
            extraWeightKg: const [5.0, 7.5, 0.0][index],
            atMs: start,
          ),
        );
        await _writeRows(
          repository,
          LoggedEntryRows.setObservations(
            effortId: 'sl-bench',
            entryIndex: index,
            reps: 10,
            weightKg: 60,
            exerciseHasLoad: true,
            atMs: start,
          ),
        );
      }

      final state = WorkoutState(repository);
      await state.loadHistoricalSession('s-8007');
      final bridge = WatchSessionAdoptionBridge(
        repository: repository,
        clock: () => _phoneNow,
        onFailure: Error.throwWithStackTrace,
      );
      bridge.bindWorkoutState(state);

      final snapshot = await bridge.projectSession(null);
      expect(snapshot, isNotNull, reason: 'S-8007 the fixture: an active session');
      final slots = {
        for (final slot in (snapshot!['exercises']! as List).cast<Map>())
          slot['sessionExerciseId']! as String: slot,
      };
      expect(
        slots['sl-pushup']!['plannedSets'],
        [
          {'reps': 10, 'loadKg': 5.0},
          {'reps': 10, 'loadKg': 7.5},
          {'reps': 10},
        ],
        reason: 'S-8007 the wrist dials the push-up from the extra-weight row, '
            'and a 0 row carries no loadKg',
      );
      expect(
        slots['sl-bench']!['plannedSets'],
        [
          {'reps': 10, 'loadKg': 60.0},
          {'reps': 10, 'loadKg': 60.0},
          {'reps': 10, 'loadKg': 60.0},
        ],
        reason: 'S-8007 the bench\'s rows carry their weight as before',
      );
    });

    test('S-8008 a wrist set the phone merged is not sent back, and the '
        'planned rows are unaffected', () async {
      final repository = await _repository();
      final phone = await _phone(repository);
      await phone.router.receive(
        _snapshot('s-8008', [_slot('sl-1', 'ex-pushup', const ['sets', 'reps'])]),
      );
      await _writeRows(
        repository,
        LoggedEntryRows.setObservations(
          effortId: 'sl-1',
          entryIndex: 0,
          reps: 10,
          weightKg: 0,
          exerciseHasLoad: false,
          extraWeightKg: 5,
          atMs: _msOf(_plannedAt),
        ),
      );
      await phone.router.receive(
        observationsUp('s-8008', [
          _set(
            'sx-1',
            loggedAt: '2026-09-25T10:10:00.000Z',
            slot: 'sl-1',
            exerciseId: 'ex-pushup',
            reps: 8,
            loadKg: 10,
          ),
        ], messageId: 'msg-fill-1'),
      );
      expect(
        (await observationAt(repository, 'sl-1', 0, 'extra-weight'))?.valueReal,
        10.0,
        reason: 'S-8008 the fixture: the wrist\'s set filled the planned row',
      );

      final snapshot = await phone.bridge.projectSession(null);
      expect(
        snapshot!['entries'],
        isEmpty,
        reason: 'S-8008 the wrist\'s own entry claims the phone record the '
            'importer wrote for it, so no second copy rides back (D-34)',
      );
      expect(
        (snapshot['exercises']! as List)
            .cast<Map>()
            .first['plannedSets'],
        [
          {'reps': 8, 'loadKg': 10.0},
        ],
        reason: 'S-8008 the planned row reads as the wrist left it, with no '
            'extra row beside it',
      );
    });
  });

  group('S-8009..S-8011 the stamps, the unfinished pass and the bridge carry '
      'the extra-weight row', () {
    test('S-8009 a loadKg correction staged before the import stamps the '
        'extra-weight row, and the bench\'s weight row as before', () async {
      final repository = await _repository();
      final inbox = _inbox(repository, CaptureTransport());

      // Staged while nothing is imported (S-281's order): the correction's
      // staging stamp is the inbox clock's, unlike every loggedAt below.
      await inbox.stagePhoneChanges(
        _correction('s-8009', 'chg-pu', 'e-pu', {'loadKg': 25}),
      );
      await inbox.stagePhoneChanges(
        _correction('s-8009', 'chg-bench', 'e-bench', {'loadKg': 85}),
      );

      await _deliverEach(inbox, 's-8009', [
        _set(
          'e-pu',
          loggedAt: '2026-09-25T10:10:00.000Z',
          slot: 'sx-pushup',
          exerciseId: 'ex-pushup',
          reps: 12,
          loadKg: 10,
        ),
        _set('e-bench', loggedAt: '2026-09-25T10:11:00.000Z', loadKg: 10),
        _end(
          's-8009',
          startedAt: '2026-09-25T10:00:00.000Z',
          endedAt: '2026-09-25T10:20:00.000Z',
        ),
      ]);

      final stagedAt = _phoneNow.millisecondsSinceEpoch;
      final pushup = _effortOf('s-8009', 'sx-pushup', 'ex-pushup');
      final extra = await observationAt(repository, pushup, 0, 'extra-weight');
      expect(
        extra?.valueReal,
        25.0,
        reason: 'S-8009 the extra-weight row holds the corrected value',
      );
      expect(
        extra?.updatedAtMs,
        stagedAt,
        reason: 'S-8009 the extra-weight row is stamped with the correction\'s '
            'staging time, not the import\'s',
      );
      final weight = await observationAt(repository, pushup, 0, 'weight');
      expect(
        weight?.valueReal,
        0.0,
        reason: 'S-8009 the weight row stays 0',
      );
      expect(
        weight?.updatedAtMs,
        _msOf('2026-09-25T10:10:00.000Z'),
        reason: 'S-8009 the weight row carries the import\'s own stamp, not '
            'the correction\'s',
      );

      final bench = _effortOf('s-8009', 'sx-bench', 'ex-bench');
      final benchWeight = await observationAt(repository, bench, 0, 'weight');
      expect(
        benchWeight?.valueReal,
        85.0,
        reason: 'S-8009 the bench\'s correction is in its weight row',
      );
      expect(
        benchWeight?.updatedAtMs,
        stagedAt,
        reason: 'S-8009 the bench\'s weight row is stamped with the '
            'correction\'s staging time, as before',
      );
      expect(
        await observationAt(repository, bench, 0, 'extra-weight'),
        isNull,
        reason: 'S-8009 the bench creates no extra-weight row',
      );
    });

    test('S-8010 a pass that did not finish is recognised: the entry '
        'rewrites its own rows instead of adding a second copy', () async {
      final repository = await _repository();
      final phone = await _phone(repository);
      await phone.router.receive(
        _snapshot('s-8010', [_slot('sl-1', 'ex-pushup', const ['sets', 'reps'])]),
      );

      // What the unfinished pass left at the position (S-4509's arrangement):
      // the set's rows, stamped with the entry's loggedAt and holding exactly
      // what it would write, plus the rest that marked the set — already
      // closed by the wrist's own report. The rest makes the fill skip the
      // spot, so only the unfinished-pass recognition can find the rows.
      const loggedAt = '2026-09-25T10:10:00.000Z';
      await _writeRows(
        repository,
        LoggedEntryRows.setObservations(
          effortId: 'sl-1',
          entryIndex: 0,
          reps: 12,
          weightKg: 0,
          exerciseHasLoad: false,
          extraWeightKg: 10,
          atMs: _msOf(loggedAt),
        ),
      );
      await repository.createEntryRest(
        EntryRest(
          id: 'rest-sl-1-1',
          effortId: 'sl-1',
          entryIndex: 1,
          restStartMs: _msOf('2026-09-25T10:10:30.000Z'),
          restEndMs: _msOf('2026-09-25T10:11:30.000Z'),
          createdAtMs: _msOf(loggedAt),
          updatedAtMs: _msOf('2026-09-25T10:11:30.000Z'),
        ),
      );

      await phone.router.receive(
        observationsUp('s-8010', [
          _set(
            'sx-1',
            loggedAt: loggedAt,
            slot: 'sl-1',
            exerciseId: 'ex-pushup',
            reps: 12,
            loadKg: 10,
          ),
        ], messageId: 'msg-8010-retry'),
      );

      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        [for (final row in rows) row.id]..sort(),
        ['obs-sl-1-0-extra-weight', 'obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-8010 exactly one set of rows, at the position the '
            'unfinished pass put them — no second position',
      );
      expect(
        await _rowValues(repository, 'sl-1', 0),
        {'reps': 12.0, 'weight': 0.0, 'extra-weight': 10.0},
        reason: 'S-8010 the rows hold the entry\'s values',
      );
    });

    test('S-8011 the bridge passes the exercise\'s load capability to the '
        'entry projection', () async {
      final repository = await _repository();
      const start = 1788000000000;
      await repository.createSession(
        TrainingSession(
          id: 's-8011',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: start,
          endedAtMs: null,
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await repository.createSegment(
        LoggedEntryRows.defaultSegment(
          id: 'segment-s-8011',
          sessionId: 's-8011',
          atMs: start,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: 'sl-pushup',
          segmentId: 'segment-s-8011',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: 'ex-pushup',
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: 'sl-bench',
          segmentId: 'segment-s-8011',
          orderIndex: 1,
          effortKind: 'set',
          exerciseId: 'ex-bench',
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await _writeRows(
        repository,
        LoggedEntryRows.setObservations(
          effortId: 'sl-pushup',
          entryIndex: 0,
          reps: 10,
          weightKg: 0,
          exerciseHasLoad: false,
          extraWeightKg: 12.5,
          atMs: start,
        ),
      );
      await _writeRows(
        repository,
        LoggedEntryRows.setObservations(
          effortId: 'sl-bench',
          entryIndex: 0,
          reps: 10,
          weightKg: 60,
          exerciseHasLoad: true,
          atMs: start,
        ),
      );
      // The rests that make both sets count as logged (D-1): a rest at the
      // set's position + 1.
      await repository.createEntryRest(
        EntryRest(
          id: 'rest-sl-pushup-1',
          effortId: 'sl-pushup',
          entryIndex: 1,
          restStartMs: start,
          restEndMs: start + 60000,
          createdAtMs: start,
          updatedAtMs: start + 60000,
        ),
      );
      await repository.createEntryRest(
        EntryRest(
          id: 'rest-sl-bench-1',
          effortId: 'sl-bench',
          entryIndex: 1,
          restStartMs: start,
          restEndMs: start + 60000,
          createdAtMs: start,
          updatedAtMs: start + 60000,
        ),
      );

      final state = WorkoutState(repository);
      await state.loadHistoricalSession('s-8011');
      final bridge = WatchSessionAdoptionBridge(
        repository: repository,
        clock: () => _phoneNow,
        onFailure: Error.throwWithStackTrace,
      );
      bridge.bindWorkoutState(state);

      final snapshot = await bridge.projectSession(null);
      expect(snapshot, isNotNull, reason: 'S-8011 the fixture: an active session');
      final entries = {
        for (final entry in (snapshot!['entries']! as List).cast<Map>())
          entry['sessionExerciseId']! as String: entry,
      };
      expect(
        entries['sl-pushup']?['loadKg'],
        12.5,
        reason: 'S-8011 the phone-logged push-up set rides with its extra '
            'weight as loadKg',
      );
      expect(
        entries['sl-bench']?['loadKg'],
        60.0,
        reason: 'S-8011 the logged bench set rides with its weight as loadKg',
      );
    });
  });
}
