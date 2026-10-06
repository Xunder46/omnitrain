// The merge: a set the watch logged in a session the phone holds becomes a set
// in that session on the phone, in the order logged, once.
//
// Plan: `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan/2026-10-05-15b-watch-session-sync-pr2-plan.md`,
// Phase 1 — the merge — and Phase 2 — the live screen and the wiring
// (D-13 – D-19, R1 – R5, R7).
// Scenario mapping:
//   S-9  a wrist set reaches the live phone session     → `S-9 ...`
//   S-10 a redelivery, and a second set                 → `S-10 ...`
//   S-11 the phone's own rows are the user's            → `S-11 ...`
//   S-12 a slot the session does not have               → `S-12 ...`
//   S-13 a correction on a merged row                   → `S-13 ...`
//   S-14 the phone finished first                       → `S-14 ...`
//   S-15 the wrist's end and rating, with sets behind   → `a set logged on the
//     watch lands in the session the phone holds` (Phase 1's override rewrote
//     `test/watch_session_finish_test.dart` onto S-15's fixture, end and rating
//     included)
//   S-16 the screen, and the running timer              → `S-16 ...`
//   S-17 a session the phone does not hold is untouched → `S-17 ...`
//   S-19 a set logged while the phone was out of reach  → `S-19 ...`
//   D-17 the efforts a merge wrote into                 → `D-17 ...`
//   D-19 the wrist's end for a session the phone holds   → `D-19 ...` (the
//     summary attaches, an abandoned end included, and an end the phone cannot
//     read attaches nothing)
//
// Both groups run the same fixtures through the same phone: the merge must
// produce the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository` (the plan's implementation-parity invariant). Plain
// `test()`: no widget is involved, and a Hive write inside a widget test's
// fake-async zone never drains.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
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
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show
        CaptureTransport,
        importedEfforts,
        observationsUp,
        seedExercise,
        sortedObservations;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

/// The three distinct stamps of the base fixture, `T1 < T2 < T3`.
const String _t1 = '2026-10-05T10:10:00Z';
const String _t2 = '2026-10-05T10:20:00Z';
const String _t3 = '2026-10-05T10:30:00Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// A clock the scenario moves, so a staging stamp (`receivedAtMs`, the
/// correction's) can be one of `T1 < T2 < T3`.
class _Clock {
  DateTime now = _phoneNow;
}

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test`. `HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`, which asks it for the documents directory.
/// Same pattern as `test/watch_capture_repository_parity_test.dart`.
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return _root.path;
      default:
        return null;
    }
  }
}

/// One phone, wired the way `createWatchSync` wires it: the adoption bridge
/// first, the inbox that asks it whether a session is the phone's own, the
/// mirror behind the entry-staging transport, and the router that drives them.
class _Phone {
  _Phone({
    required this.repository,
    required this.transport,
    required this.inbox,
    required this.router,
    required this.state,
    required this.bridge,
    required this.clock,
    required this.failures,
    required this.refreshes,
  });

  final WorkoutRepository repository;
  final CaptureTransport transport;
  final WatchSessionInbox inbox;
  final WatchIncomingRouter router;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;
  final _Clock clock;

  /// What the graph reported as a failure: nothing, in these tests.
  final List<Object> failures;

  /// One entry per history change the inbox reported — the calendar's refresh
  /// in the shipping graph (D-17).
  final List<int> refreshes;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final refreshes = <int>[];
  final clock = _Clock();
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => clock.now,
    onFailure: (error, stack) => failures.add(error),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: _validator,
    clock: () => clock.now,
    onHistoryChanged: () async => refreshes.add(1),
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
    phoneOwnsSession: bridge.holdsSession,
    onSessionRowsChanged: bridge.refreshHeldEfforts,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
    projection: bridge.projectSession,
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);

  return _Phone(
    repository: repository,
    transport: transport,
    inbox: inbox,
    router: WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    ),
    state: state,
    bridge: bridge,
    clock: clock,
    failures: failures,
    refreshes: refreshes,
  );
}

// ─── The base fixture ───────────────────────────────────────────────────────

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(String sessionExerciseId, String exerciseId) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ],
};

/// One `session_snapshot` from the wrist, adopting `s-w1` onto the phone.
Map<String, Object?> _snapshot({String messageId = 'msg-snapshot'}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': 's-w1',
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:00:00Z',
  'payload': {
    'sessionId': 's-w1',
    'revision': 3,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 1,
    'exercises': [_slot('sl-1', 'ex-1'), _slot('sl-2', 'ex-2')],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// A set the wrist logged, naming the slot it belongs to.
Map<String, Object?> _set(
  String entryId, {
  required String slot,
  required String exerciseId,
  required int reps,
  required num loadKg,
  required String loggedAt,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': loggedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'reps': reps,
  'loadKg': loadKg,
};

/// The wrist's own end for [sessionId], heart rate included — the summary the
/// phone attaches comes from those two numbers.
Map<String, Object?> _end(String sessionId, {String status = 'completed'}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': _t2,
  'startedAt': _t1,
  'endedAt': _t2,
  'status': status,
  'avgHeartRateBpm': 140,
  'maxHeartRateBpm': 165,
};

/// The wrist's rating for [sessionId].
Map<String, Object?> _rating(String sessionId, int rating) => {
  'entryId': 'rating-$sessionId',
  'eventId': 'rating-$sessionId',
  'kind': 'effort_rating',
  'loggedAt': _t2,
  'rating': rating,
};

/// A `structure_change` the phone is about to send, carrying one correction.
Map<String, Object?> _correctionEnvelope({
  required String changeId,
  required String entryId,
  required int reps,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-change',
  'sessionId': 's-w1',
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': _t2,
  'payload': {
    'changeId': changeId,
    'changes': [
      {
        'kind': 'correct_entry',
        'entryId': entryId,
        'correction': {'reps': reps},
      },
    ],
  },
};

// ─── Reading what happened ──────────────────────────────────────────────────

/// The staged rows of `s-w1` by entry id.
Future<Map<String, WatchInboxEntry>> _staged(
  WorkoutRepository repository,
) async => {
  for (final row in await repository.getWatchInboxEntriesForSession('s-w1'))
    row.entryId: row,
};

/// The `entryIds` of the last receipt the phone sent.
List<String> _lastReceipt(_Phone phone) {
  final receipts = phone.transport.ofType('receipt');
  if (receipts.isEmpty) return const [];
  return [
    for (final id in (receipts.last['payload']! as Map)['entryIds']! as List)
      id as String,
  ];
}

/// One effort's observation ids, in id order — the id carries the entry index.
Future<List<String>> _ids(WorkoutRepository repository, String effortId) async =>
    [for (final row in await sortedObservations(repository, effortId)) row.id];

/// The efforts of the held session, by id: `sl-1` and `sl-2` unless a scenario
/// removed one.
Future<List<String>> _effortIds(WorkoutRepository repository) async =>
    [for (final effort in await importedEfforts(repository, 's-w1')) effort.id];

/// Writes one entry's rows the way the phone's own logging does, under [atMs].
Future<void> _phoneRows(
  WorkoutRepository repository, {
  required String effortId,
  required int entryIndex,
  required int reps,
  required double weightKg,
  required int atMs,
}) async {
  for (final row in LoggedEntryRows.setObservations(
    effortId: effortId,
    entryIndex: entryIndex,
    reps: reps,
    weightKg: weightKg,
    exerciseHasLoad: true,
    atMs: atMs,
  )) {
    await repository.createObservation(row);
  }
}

// ─── The scenarios ──────────────────────────────────────────────────────────

void main() {
  group('Mock', () => _mergeTests(open: _openMock, close: () async {}));
  group('Hive', () => _mergeTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('watch_merge_');
  _hiveDir = dir;
  _PathProviderChannel.install(dir);
  Hive.init(dir.path);
  final repository = HiveWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Future<void> _closeHive() async {
  await Hive.deleteFromDisk();
  final dir = _hiveDir;
  if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  _hiveDir = null;
}

/// The base fixture's catalog: both slots' exercises carry `reps` and `load`.
Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-1',
    name: 'Barbell Bench Press',
    capabilities: [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
  await seedExercise(
    repository,
    id: 'ex-2',
    name: 'Barbell Back Squat',
    capabilities: [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
}

void _mergeTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test('S-9 a wrist set reaches the live phone session', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    expect(
      phone.state.currentSession?.id,
      's-w1',
      reason: 'S-9 the phone holds the session the wrist is running',
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
      reason: 'S-9 the wrist\'s set is one entry of the phone\'s own effort',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(rows[0].valueInt, 8, reason: 'S-9 the wrist\'s reps');
    expect(rows[0].createdAtMs, _msOf(_t1), reason: 'S-9 the wrist\'s stamp');
    expect(rows[1].valueReal, 40.0, reason: 'S-9 the wrist\'s load');
    expect(rows[1].createdAtMs, _msOf(_t1), reason: 'S-9 the wrist\'s stamp');

    expect(
      (await _staged(repository))['sx-1']?.appliedAtMs,
      isNotNull,
      reason: 'S-9 the merged row is applied, so the wrist may forget it',
    );
    expect(
      phone.transport.receiptedEntryIds,
      contains('sx-1'),
      reason: 'S-9 the receipt names the set',
    );
    expect(
      await repository.getAllSessions(),
      hasLength(1),
      reason: 'S-9 no session is created',
    );
    expect(
      await repository.getSessionSegments('s-w1'),
      hasLength(1),
      reason: 'S-9 no segment is created',
    );
    expect(
      await _effortIds(repository),
      ['sl-1', 'sl-2'],
      reason: 'S-9 no effort is created',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-10 a redelivery, and a second set', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );
    // The wrist re-sends the same row, as an entry it has no receipt for must
    // be re-sent.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1-again'),
    );
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-2',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 10,
          loadKg: 45,
          loggedAt: _t2,
        ),
      ], messageId: 'msg-set-2'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      [
        'obs-sl-1-0-reps',
        'obs-sl-1-0-weight',
        'obs-sl-1-1-reps',
        'obs-sl-1-1-weight',
      ],
      reason: 'S-10 exactly two entries: the redelivery wrote no third',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(rows[0].valueInt, 8, reason: 'S-10 entry 0 is the set from T1');
    expect(rows[0].createdAtMs, _msOf(_t1));
    expect(rows[2].valueInt, 10, reason: 'S-10 entry 1 is the set from T2');
    expect(rows[2].createdAtMs, _msOf(_t2));
    expect(
      await _effortIds(repository),
      ['sl-1', 'sl-2'],
      reason: 'S-10 a redelivery makes no second effort',
    );
    final staged = await _staged(repository);
    expect(staged['sx-1']?.appliedAtMs, isNotNull, reason: 'S-10 sx-1 applied');
    expect(staged['sx-2']?.appliedAtMs, isNotNull, reason: 'S-10 sx-2 applied');
    expect(
      _lastReceipt(phone),
      ['sx-2'],
      reason:
          'S-10 the receipt for the settle that placed sx-2 names only sx-2 — '
          'sx-1 was receipted when it landed',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-11 the phone\'s own rows are the user\'s', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    // The phone logged one set, and the user added one by hand: both are the
    // user's rows, and the merge must not move, edit or delete either.
    await _phoneRows(
      repository,
      effortId: 'sl-1',
      entryIndex: 0,
      reps: 6,
      weightKg: 60,
      atMs: _msOf(_t2),
    );
    await _phoneRows(
      repository,
      effortId: 'sl-1',
      entryIndex: 1,
      reps: 7,
      weightKg: 70,
      atMs: _msOf(_t3),
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      [
        'obs-sl-1-0-reps',
        'obs-sl-1-0-weight',
        'obs-sl-1-1-reps',
        'obs-sl-1-1-weight',
        'obs-sl-1-2-reps',
        'obs-sl-1-2-weight',
      ],
      reason: 'S-11 the wrist\'s set lands after the user\'s rows',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(rows[0].valueInt, 6, reason: 'S-11 the phone\'s row keeps its value');
    expect(rows[0].createdAtMs, _msOf(_t2), reason: 'S-11 and its stamp');
    expect(rows[1].valueReal, 60.0, reason: 'S-11 the phone\'s row');
    expect(rows[1].createdAtMs, _msOf(_t2), reason: 'S-11 and its stamp');
    expect(rows[2].valueInt, 7, reason: 'S-11 the user\'s row keeps its value');
    expect(rows[2].createdAtMs, _msOf(_t3), reason: 'S-11 and its stamp');
    expect(rows[3].valueReal, 70.0, reason: 'S-11 the user\'s row');
    expect(rows[3].createdAtMs, _msOf(_t3), reason: 'S-11 and its stamp');
    expect(rows[4].valueInt, 8, reason: 'S-11 the wrist\'s set is the new last');
    expect(rows[4].createdAtMs, _msOf(_t1), reason: 'S-11 carrying its own stamp');
    expect(rows[5].valueReal, 40.0, reason: 'S-11 the wrist\'s load');
    expect(rows[5].createdAtMs, _msOf(_t1));
    expect(phone.failures, isEmpty);
  });

  test('S-12 a slot the session does not have', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    // The user deleted the sl-2 exercise from the session on the phone.
    await repository.deleteEffort('sl-2');
    final before = await repository.getAllSessions();

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-3',
          slot: 'sl-2',
          exerciseId: 'ex-2',
          reps: 12,
          loadKg: 50,
          loggedAt: _t1,
        ),
        _set(
          'sx-4',
          slot: 'sl-9',
          exerciseId: 'ex-1',
          reps: 12,
          loadKg: 50,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-orphans'),
    );

    final staged = await _staged(repository);
    expect(
      staged['sx-3']?.appliedAtMs,
      isNotNull,
      reason: 'S-12 a row for a slot the session lacks is acknowledged',
    );
    expect(staged['sx-4']?.appliedAtMs, isNotNull, reason: 'S-12 and so is its twin');
    expect(
      phone.transport.receiptedEntryIds,
      containsAll(['sx-3', 'sx-4']),
      reason: 'S-12 the wrist is told to forget both',
    );
    expect(
      await repository.getEffortObservations('sl-1'),
      isEmpty,
      reason: 'S-12 sl-1 is untouched',
    );
    expect(
      await _effortIds(repository),
      ['sl-1'],
      reason: 'S-12 no effort sl-2 or sl-9 exists',
    );
    expect(
      await repository.getAllSessions(),
      hasLength(before.length),
      reason: 'S-12 no session is created',
    );
    expect(
      await repository.getSessionSegments('s-w1'),
      hasLength(1),
      reason: 'S-12 no segment is created',
    );
    expect(
      phone.refreshes,
      isEmpty,
      reason: 'S-12 nothing was written, so the calendar holds no new entry',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-13 a correction on a merged row', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );

    // The phone's own correction, staged at T2 as the staging transport stages
    // it before the message leaves.
    phone.clock.now = DateTime.parse(_t2);
    await phone.inbox.stagePhoneChanges(
      _correctionEnvelope(changeId: 'ch-1', entryId: 'sx-1', reps: 12),
    );

    expect(
      await _ids(repository, 'sl-1'),
      ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
      reason: 'S-13 the correction edits the entry, it does not add one',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(rows[0].valueInt, 12, reason: 'S-13 the field the correction named');
    expect(rows[0].createdAtMs, _msOf(_t1), reason: 'S-13 the row\'s own stamp stands');
    expect(
      rows[0].updatedAtMs,
      _msOf(_t2),
      reason: 'S-13 the correction\'s staging time stamps the edit',
    );
    expect(
      rows[1].valueReal,
      40.0,
      reason: 'S-13 the field the correction did not name keeps its value',
    );
    expect(rows[1].createdAtMs, _msOf(_t1));
    expect(rows[1].updatedAtMs, _msOf(_t1), reason: 'S-13 and its stamp');
    expect(
      (await _staged(repository))[WatchInboxEntry.phoneChangeId('ch-1', 0)]
          ?.appliedAtMs,
      isNotNull,
      reason: 'S-13 the correction row is applied',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-19 a set logged while the phone was out of reach', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The phone was out of reach since T1: both sets arrive in one message, and
    // the later one is staged first — arrival order must not decide order.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-2',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 10,
          loadKg: 45,
          loggedAt: _t3,
        ),
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-both'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      [
        'obs-sl-1-0-reps',
        'obs-sl-1-0-weight',
        'obs-sl-1-1-reps',
        'obs-sl-1-1-weight',
      ],
      reason: 'S-19 both sets land, once each',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(
      rows[0].valueInt,
      8,
      reason: 'S-19 entry 0 is the earlier set, though it was staged second',
    );
    expect(rows[0].createdAtMs, _msOf(_t1), reason: 'S-19 its own stamp');
    expect(rows[2].valueInt, 10, reason: 'S-19 entry 1 is the later set');
    expect(rows[2].createdAtMs, _msOf(_t3), reason: 'S-19 its own stamp');
    final staged = await _staged(repository);
    expect(staged['sx-1']?.appliedAtMs, isNotNull, reason: 'S-19 sx-1 applied');
    expect(staged['sx-2']?.appliedAtMs, isNotNull, reason: 'S-19 sx-2 applied');
    expect(
      phone.transport.receiptedEntryIds,
      containsAll(['sx-1', 'sx-2']),
      reason: 'S-19 both are receipted',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-14 the phone finished first', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The phone ended its own session at T2, and the wrist kept logging.
    final session = (await repository.getSession('s-w1'))!;
    await repository.updateSession(
      TrainingSession.fromMap({
        ...session.toMap(),
        'ended_at_ms': _msOf(_t2),
        'updated_at_ms': _msOf(_t2),
      }),
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
        _set(
          'sx-2',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 10,
          loadKg: 45,
          loggedAt: _t2,
        ),
      ], messageId: 'msg-after-end'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      [
        'obs-sl-1-0-reps',
        'obs-sl-1-0-weight',
        'obs-sl-1-1-reps',
        'obs-sl-1-1-weight',
      ],
      reason: 'S-14 both sets land in sl-1, in logged order',
    );
    final rows = await sortedObservations(repository, 'sl-1');
    expect(rows[0].valueInt, 8, reason: 'S-14 entry 0 is T1');
    expect(rows[2].valueInt, 10, reason: 'S-14 entry 1 is T2');
    final after = (await repository.getSession('s-w1'))!;
    expect(after.endedAtMs, _msOf(_t2), reason: 'S-14 the phone\'s end stands');
    expect(
      phone.refreshes,
      isNotEmpty,
      reason: 'S-14 the history signal fires so the calendar refreshes',
    );
    expect(
      phone.transport.receiptedEntryIds,
      containsAll(['sx-1', 'sx-2']),
      reason: 'S-14 both are receipted',
    );
    expect(phone.failures, isEmpty);
  });

  test('D-19 a held session takes the wrist\'s end summary, abandoned or not',
      () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The wrist abandoned the session it was running while the phone still
    // holds it: the phone's own end owns the session's fate (G2/D-5), and the
    // heart rate is a measurement the wrist did make.
    await phone.router.receive(
      observationsUp('s-w1', [
        _end('s-w1', status: 'abandoned'),
      ], messageId: 'msg-abandoned-end'),
    );

    expect(
      (await _staged(repository))['end-s-w1']?.appliedAtMs,
      isNotNull,
      reason: 'D-19 the held session consumes the wrist\'s end',
    );
    final summaries = await repository.getSensorSummariesForSession('s-w1');
    expect(
      summaries.map((summary) => summary.id),
      ['sensor-session-s-w1'],
      reason: 'D-19 the wrist measured this heart rate, so it is kept',
    );
    expect(summaries.single.avgHeartRateBpm, 140);
    expect(summaries.single.maxHeartRateBpm, 165);
    expect(
      (await repository.getSession('s-w1'))?.endedAtMs,
      isNull,
      reason: 'D-19 the wrist\'s end never ends the phone\'s session',
    );
    expect(phone.state.currentSession?.endedAtMs, isNull);
    expect(phone.failures, isEmpty);
  });

  test('D-19 an end the phone cannot read attaches no summary', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // A `session_end` without its `loggedAt` cannot travel the protocol — the
    // schema requires it — so the row is staged directly: the phone must treat
    // a row it cannot read as nothing to apply, never as a failure.
    await repository.stageWatchInboxEntry(
      WatchInboxEntry(
        entryId: 'end-s-w1',
        watchSessionId: 's-w1',
        kind: WatchInboxEntry.kindSessionEnd,
        origin: WatchInboxEntry.originWatch,
        payload: <String, dynamic>{
          'entryId': 'end-s-w1',
          'eventId': 'end-s-w1',
          'kind': 'session_end',
          'startedAt': _t1,
          'endedAt': _t2,
          'status': 'completed',
          'avgHeartRateBpm': 140,
          'maxHeartRateBpm': 165,
        },
        receivedAtMs: _msOf(_t1),
      ),
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-with-bad-end'),
    );

    expect(
      await _ids(repository, 'sl-1'),
      ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
      reason: 'D-19 an unreadable end does not stop the merge of the same pass',
    );
    expect(
      (await _staged(repository))['end-s-w1']?.appliedAtMs,
      isNotNull,
      reason: 'D-19 a row nothing can use is not one the wrist re-sends forever',
    );
    expect(
      await repository.getSensorSummariesForSession('s-w1'),
      isEmpty,
      reason: 'D-19 an end the phone cannot read attaches no summary',
    );
    expect(phone.failures, isEmpty);
  });

  test('D-17 a merge names the efforts it wrote into', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // A set and the wrist's rating wait together. The rating is applied before
    // any effort is touched, so a merge that asked the pass "did you write
    // anything?" would find it already true and name no effort at all.
    await repository.stageWatchInboxEntry(
      WatchInboxEntry(
        entryId: 'sx-1',
        watchSessionId: 's-w1',
        kind: WatchInboxEntry.kindSet,
        origin: WatchInboxEntry.originWatch,
        payload: _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
        receivedAtMs: _msOf(_t1),
      ),
    );
    await repository.stageWatchInboxEntry(
      WatchInboxEntry(
        entryId: 'rating-s-w1',
        watchSessionId: 's-w1',
        kind: WatchInboxEntry.kindEffortRating,
        origin: WatchInboxEntry.originWatch,
        payload: {'rating': 4},
        receivedAtMs: _msOf(_t1),
      ),
    );

    final pass = await WatchSessionImporter(
      repository: repository,
      clock: () => phone.clock.now,
    ).apply('s-w1', phoneOwnsSession: true);

    expect(
      pass.changedEffortIds,
      ['sl-1'],
      reason: 'D-17 the merge names sl-1 — the rating top-up is not an effort',
    );
    expect(pass.historyChanged, isTrue, reason: 'D-17 it wrote');
    expect(
      pass.appliedEntryIds,
      containsAll(['sx-1', 'rating-s-w1']),
      reason: 'D-18 the wrist may forget both',
    );
    expect(
      await _ids(repository, 'sl-1'),
      ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
      reason: 'D-17 the set did land, so the name is not vacuous',
    );
    expect(
      (await repository.getSession('s-w1'))?.sessionFeeling,
      4,
      reason: 'D-19 the rating was topped up in the same pass',
    );
  });

  test('S-17 a session the phone does not hold still imports unchanged',
      () async {
    final phone = await _phone(repository);

    // The phone holds nothing: `s-w1` is the wrist's own session, so the
    // ordinary import runs and the live state is never touched (R7).
    expect(phone.state.currentSession, isNull, reason: 'S-17 nothing is held');

    var notifications = 0;
    phone.state.addListener(() => notifications += 1);

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
        _rating('s-w1', 4),
        _end('s-w1'),
      ], messageId: 'msg-import-1'),
    );

    expect(
      [for (final session in await repository.getAllSessions()) session.id],
      ['s-w1'],
      reason: 'S-17 the merge did not swallow the import',
    );
    expect(
      (await repository.getSession('s-w1'))?.sessionFeeling,
      4,
      reason: 'S-17 the wrist\'s rating is the imported session\'s rating',
    );
    expect(
      await repository.getSensorSummariesForSession('s-w1'),
      isNotEmpty,
      reason: 'S-17 the wrist\'s heart rate attached its summary',
    );

    final efforts = await importedEfforts(repository, 's-w1');
    expect(efforts, hasLength(1), reason: 'S-17 the wrist\'s one effort');
    final rows = await sortedObservations(repository, efforts.single.id);
    expect(
      [for (final row in rows) row.id.split('-').last],
      ['reps', 'weight'],
      reason: 'S-17 the set the wrist logged is in the imported session',
    );
    expect(rows.first.valueInt, 8, reason: 'S-17 the reps the wrist logged');
    expect(rows.last.valueReal, 40.0, reason: 'S-17 the load the wrist logged');

    expect(
      _lastReceipt(phone),
      containsAll(['sx-1', 'rating-s-w1', 'end-s-w1']),
      reason: 'S-17 everything was used, so the wrist may forget all three',
    );
    expect(
      notifications,
      0,
      reason:
          'S-17 no held session, so nothing was refreshed on the live state',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-16 the live screen shows the merged set and keeps a running rest',
      () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // A rest timer is running on the phone's own effort. It is written through
    // the live state, so it is both in the timer manager and in the repository.
    await phone.state.recordRestStart('sl-1', 0);
    final restBefore = phone.state.getEntryRests('sl-1');
    expect(restBefore, hasLength(1), reason: 'S-16 the fixture has an open rest');
    expect(
      phone.state.hasRestRecord('sl-1', 0),
      isTrue,
      reason: 'S-16 the rest timer is running before the merge',
    );

    var notifications = 0;
    phone.state.addListener(() => notifications += 1);

    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );

    expect(
      notifications,
      1,
      reason:
          'S-16 the merge refreshes the touched effort once — a whole-session '
          'reload would notify more than once',
    );

    // The merged set is on the phone's live state, at once, for the effort the
    // merge wrote — and nowhere else.
    final visible = {
      for (final o in phone.state.getObservationsForEffort('sl-1')) o.id: o,
    };
    expect(
      visible.keys.toSet(),
      {'obs-sl-1-0-reps', 'obs-sl-1-0-weight'},
      reason: 'S-16 the merged set is visible on the phone\'s live session',
    );
    expect(
      visible['obs-sl-1-0-reps']?.valueInt,
      8,
      reason: 'S-16 the reps the wrist logged',
    );
    expect(
      visible['obs-sl-1-0-weight']?.valueReal,
      40.0,
      reason: 'S-16 the load the wrist logged',
    );
    expect(
      phone.state.getObservationsForEffort('sl-2'),
      isEmpty,
      reason: 'S-16 an effort the merge did not touch is untouched',
    );

    // The rest timer is still running: the refresh cleared nothing.
    final restAfter = phone.state.getEntryRests('sl-1');
    expect(restAfter, hasLength(1), reason: 'S-16 nothing cleared the rest');
    expect(
      restAfter.single.id,
      restBefore.single.id,
      reason: 'S-16 the rest is the same record, not a re-created one',
    );
    expect(
      restAfter.single.restEndMs,
      isNull,
      reason: 'S-16 the rest is still open — the running timer survived',
    );
    expect(
      phone.state.hasRestRecord('sl-1', 0),
      isTrue,
      reason: 'S-16 the rest timer is still running after the merge',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-16 the refresh does nothing for a session the phone does not hold',
      () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    var notifications = 0;
    phone.state.addListener(() => notifications += 1);

    await phone.bridge.refreshHeldEfforts('s-other', ['sl-1']);

    expect(
      notifications,
      0,
      reason:
          'S-16 a session the phone does not hold is never refreshed — the '
          'merge belongs to another session, or to none',
    );
    expect(
      phone.state.getObservationsForEffort('sl-1'),
      isEmpty,
      reason: 'S-16 nothing was re-read for a session the phone does not hold',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-16 a pass that wrote nothing does not refresh', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1'),
    );

    var notifications = 0;
    phone.state.addListener(() => notifications += 1);

    // The wrist re-sends the row it has not been receipted for: the merge
    // writes nothing, so it names no effort and refreshes nothing.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set(
          'sx-1',
          slot: 'sl-1',
          exerciseId: 'ex-1',
          reps: 8,
          loadKg: 40,
          loggedAt: _t1,
        ),
      ], messageId: 'msg-set-1-again'),
    );

    expect(
      notifications,
      0,
      reason:
          'S-16 a redelivery writes nothing, so the hook never fires and the '
          'screen is not refreshed',
    );
    expect(phone.failures, isEmpty);
  });
}
