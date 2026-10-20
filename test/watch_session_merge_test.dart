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
// Plan: `docs/plans/2026-10-14-36-routine-start-sync-plan/2026-10-14-36-routine-start-sync-plan.md`,
// Phase B — a wrist set FILLS the phone's planned set (D-4), opens the rest at
// that row's spot + 1 (D-6), and the wrist's own rest closes that row in place
// (D-7). Scenario mapping:
//   S-3604 a wrist set fills the planned row            → `S-3604 ...`
//   S-3605 a second set fills the next planned row      → `S-3605 ...`
//   S-3606 a fourth set appends once the plan is filled → `S-3606 ...`
//   S-3607 the phone's own logged set is never filled   → `S-3607 ...`
//   S-3608 the wrist's rest closes the fill's rest      → `S-3608 ...`
//   S-3616 a skipped planned row is not logged          → `S-3616 ...`
//   S-3618 the wrist's set ends the phone's older rest  → `S-3618 ...`
//
// Plan: `docs/plans/2026-10-16-38g-importer-positional-rests-plan/2026-10-16-38g-importer-positional-rests-plan.md`,
// Phase 1 — the importer reads and writes rests by POSITION (D-1..D-3). A
// rest's `entryIndex` is a position — the rest at `k` marks the set at position
// `k - 1` logged — while a set row's id number is never renumbered, so a phone
// delete leaves the numbers holed. Scenario mapping:
//   S-4501 the wrist's set after the phone's delete  → `S-4501 ...`
//   S-4502 the wrist's late rest report              → `S-4502a ...`,
//     `S-4502b ...`
//   S-4503 a fill after the phone's delete           → `S-4503 ...`
//   S-4504 a fill below an open rest                 → `S-4504 ...`
//   S-4505 a delete of a wrist set re-keys the rests → `S-4505 ...`
//   S-4506 the numbers and the positions disagree    → `S-4506 ...`
//   S-4507 the only rest goes with its set           → `S-4507 ...`
//   S-4509 a retry opens no second rest              → `S-4509 ...`
//   S-4510 a delete of a set appended after a hole   → `S-4510 ...`
//   S-4511 two wrist sets in one message             → `S-4511 ...`
//
// Both groups run the same fixtures through the same phone: the merge must
// produce the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository` (the plan's implementation-parity invariant). Plain
// `test()`: no widget is involved, and a Hive write inside a widget test's
// fake-async zone never drains.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
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

/// The wrist's rest window (18b D-166): 70 s, after the first set's stamp.
const String _restStart = '2026-10-05T10:11:00Z';
const String _restEnd = '2026-10-05T10:12:10Z';

/// A fourth wrist set's stamp, for a pass that outruns the planned rows.
const String _t4 = '2026-10-05T10:40:00Z';

/// The stamp the phone's planned rows carry (plan 36 D-4): the routine wrote
/// them before the session, so it is earlier than every wrist set's.
const String _plannedAt = '2026-10-05T09:00:00Z';

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

/// A rest the wrist observed (18b D-166), naming the entry it followed. The
/// phone logs its own rest with [WorkoutState.recordRestStart] instead.
Map<String, Object?> _rest(
  String entryId, {
  required String slot,
  required String exerciseId,
  required String startedAt,
  required String endedAt,
  required String afterEntryId,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'rest',
  'loggedAt': endedAt,
  'sessionExerciseId': slot,
  'exerciseId': exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'afterEntryId': afterEntryId,
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

/// A `structure_change` the phone is about to send, deleting one entry.
Map<String, Object?> _deleteEnvelope(String changeId, String entryId) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$changeId',
  'sessionId': 's-w1',
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': _t2,
  'payload': {
    'changeId': changeId,
    'changes': [
      {'kind': 'delete_entry', 'entryId': entryId},
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

/// Fixture F (plan 36 D-4): the phone's own slot holds [count] planned rows —
/// a routine's presets, 10 reps at 40.0 kg — with no rest after any of them,
/// so the phone reads none of them as logged (I-1).
Future<void> _plannedRows(
  WorkoutRepository repository, {
  int count = 3,
}) async {
  for (var index = 0; index < count; index++) {
    await _phoneRows(
      repository,
      effortId: 'sl-1',
      entryIndex: index,
      reps: 10,
      weightKg: 40.0,
      atMs: _msOf(_plannedAt),
    );
  }
}

/// One effort's rests, in entry-index order, so a scenario can name them.
Future<List<EntryRest>> _rests(WorkoutRepository repository, String effortId) =>
    repository.getEntryRests(effortId).then(
          (rests) => [...rests]
            ..sort((a, b) => a.entryIndex.compareTo(b.entryIndex)),
        );

/// A rest the phone counted itself and finished, at [entryIndex] — the rest a
/// set it logged leaves behind. Only a rest at `index + 1` reads as logged
/// (I-1), so a fixture whose phone logged sets writes one per logged set.
Future<void> _phoneRest(
  WorkoutRepository repository, {
  required String effortId,
  required int entryIndex,
  required int startedAtMs,
  required int endedAtMs,
}) => repository.createEntryRest(
  EntryRest(
    id: 'rest-$effortId-$entryIndex',
    effortId: effortId,
    entryIndex: entryIndex,
    restStartMs: startedAtMs,
    restEndMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs,
  ),
);

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
    // Each of those rows is a logged set, so a rest follows it (I-1): the
    // wrist's set then finds no unlogged row and appends, as it always did.
    await _phoneRest(
      repository,
      effortId: 'sl-1',
      entryIndex: 1,
      startedAtMs: _msOf(_t2),
      endedAtMs: _msOf(_t2) + 60000,
    );
    await _phoneRest(
      repository,
      effortId: 'sl-1',
      entryIndex: 2,
      startedAtMs: _msOf(_t3),
      endedAtMs: _msOf(_t3) + 60000,
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

    // The phone's own rest timer is not left running beside the set's: the
    // set's arrival closes the older open rest, exactly as the phone's own
    // flow does (A4), and opens its own at the spot it took + 1 (D-6).
    final restAfter = phone.state.getEntryRests('sl-1');
    expect(
      restAfter,
      hasLength(2),
      reason:
          'S-16 the phone\'s own rest record and the one the placement '
          'opened',
    );
    final ownRest = restAfter.singleWhere((rest) => rest.id == restBefore.single.id);
    expect(
      ownRest.restStartMs,
      restBefore.single.restStartMs,
      reason: 'S-16 the rest is the same record, not a re-created one',
    );
    expect(
      ownRest.entryIndex,
      restBefore.single.entryIndex,
      reason: 'S-16 and it keeps the spot it was logged at',
    );
    expect(
      ownRest.restEndMs,
      math.max(restBefore.single.restStartMs, _msOf(_t1)),
      reason:
          'S-16 the phone\'s older open rest is closed where the wrist\'s set '
          'landed — never before the moment it started (A4)',
    );
    expect(
      ownRest.restIsPaused,
      isFalse,
      reason: 'S-16 a closed rest is not still counted as paused',
    );
    expect(
      ownRest.restPausedAtMs,
      isNull,
      reason: 'S-16 and holds no pause instant',
    );
    final openedRest = restAfter.singleWhere((rest) => rest.id != ownRest.id);
    expect(
      openedRest.id,
      'rest-sl-1-1',
      reason: 'S-16 keyed on the spot the set took + 1 (D-167)',
    );
    expect(
      openedRest.entryIndex,
      1,
      reason: 'S-16 the rest the set\'s arrival opened',
    );
    expect(
      openedRest.restEndMs,
      isNull,
      reason: 'S-16 and it is the one rest the merge leaves running',
    );
    expect(
      [for (final rest in restAfter) rest.restEndMs],
      [math.max(restBefore.single.restStartMs, _msOf(_t1)), null],
      reason: 'S-16 exactly one rest is open after the merge (A4)',
    );
    expect(
      phone.state.hasRestRecord('sl-1', 0),
      isFalse,
      reason: 'S-16 the phone\'s own rest timer is no longer the running one',
    );
    expect(
      phone.state.hasRestRecord('sl-1', 1),
      isTrue,
      reason: 'S-16 the rest timer runs on the spot the wrist\'s set took',
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

  group('the wrist\'s rests (D-210)', () {
    test('S-320 a wrist rest lands beside the set in the phone\'s own effort',
        () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      expect(
        await repository.getEntryRests('sl-1'),
        isEmpty,
        reason: 'S-320 the fixture starts with no rest',
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
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-1',
          ),
        ], messageId: 'msg-rest-1'),
      );

      final rests = await repository.getEntryRests('sl-1');
      expect(rests, hasLength(1), reason: 'S-320 one rest event, one row');
      expect(
        rests.single.toMap(),
        {
          'id': 'rest-sl-1-1',
          'effort_id': 'sl-1',
          'entry_index': 1,
          'rest_start_ms': _msOf(_restStart),
          'rest_end_ms': _msOf(_restEnd),
          'rest_is_paused': 0,
          'rest_paused_at_ms': null,
          'rest_paused_duration_ms': 0,
          'created_at_ms': _msOf(_restEnd),
          'updated_at_ms': _msOf(_restEnd),
        },
        reason:
            'S-320 D-167\'s row: keyed on the index the set took + 1, the '
            'window as sent, never paused — and the same row under Mock and '
            'under Hive',
      );
      expect(
        await _ids(repository, 'sl-1'),
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-320 a rest is not an entry: the effort still holds one set',
      );
      expect(
        _lastReceipt(phone),
        containsAll(['sx-1', 'rest-a1']),
        reason: 'S-320 both rows are used, so the wrist may forget both',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-320 a late rest tops up the set the phone already merged',
        () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());

      // The set landed on an earlier pass, when the wrist had no rest to
      // report: the effort holds the set and no rest for it.
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
      final opened = await repository.getEntryRests('sl-1');
      expect(
        opened,
        hasLength(1),
        reason: 'S-320 the set arrived alone, so it opened its rest (D-6)',
      );
      expect(opened.single.id, 'rest-sl-1-1', reason: 'S-320 keyed on its spot');
      expect(
        opened.single.restEndMs,
        isNull,
        reason: 'S-320 the rest the set\'s arrival opened is still running',
      );
      final afterSet = phone.refreshes.length;

      // The rest arrives on its own, later.
      await phone.router.receive(
        observationsUp('s-w1', [
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-1',
          ),
        ], messageId: 'msg-rest-1'),
      );

      final rests = await repository.getEntryRests('sl-1');
      expect(
        rests,
        hasLength(1),
        reason:
            'S-320 the late rest closed the running row in place — one rest, '
            'never two (D-7)',
      );
      expect(
        rests.single.id,
        'rest-sl-1-1',
        reason: 'S-320 the id names the effort and the index the set holds + 1',
      );
      expect(
        rests.single.id,
        opened.single.id,
        reason: 'S-320 it is the row the set\'s arrival opened',
      );
      expect(
        rests.single.restStartMs,
        _msOf(_restStart),
        reason: 'S-320 and it holds the window the wrist observed',
      );
      expect(
        rests.single.restEndMs,
        _msOf(_restEnd),
        reason: 'S-320 which the wrist\'s own end closed',
      );
      expect(
        rests.single.entryIndex,
        1,
        reason:
            'S-320 the pass placed no entry: the set it follows was already '
            'in the effort, at index 0',
      );
      expect(
        await _ids(repository, 'sl-1'),
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-320 the top-up added no entry to the effort',
      );
      expect(
        phone.refreshes,
        hasLength(afterSet + 1),
        reason:
            'S-320 a written rest is a write, so the pass reports history '
            'changed and the calendar is refreshed (D-17)',
      );
      expect(
        _lastReceipt(phone),
        ['rest-a1'],
        reason: 'S-320 the rest alone is receipted',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-325 the phone\'s own rest at that spot wins', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());

      // The phone logged the same set itself, at the same instant and with the
      // same values, and counted a rest after it. So the set the wrist sends
      // belongs where the phone's own rows already are, and the rest it sends
      // names the spot the phone's own rest holds.
      await _phoneRows(
        repository,
        effortId: 'sl-1',
        entryIndex: 0,
        reps: 8,
        weightKg: 40.0,
        atMs: _msOf(_t1),
      );
      await phone.state.recordRestStart('sl-1', 1);
      // The phone's own rest at that spot is finished: a rest the phone
      // counted and closed is the phone's record, and the wrist's later report
      // of the same rest never rewrites it (D-216).
      await phone.state.recordRestEnd('sl-1', 1);
      final phoneRest = (await repository.getEntryRests('sl-1')).single.toMap();
      expect(
        phoneRest['entry_index'],
        1,
        reason: 'S-325 the fixture\'s own rest is at the spot the wrist names',
      );
      expect(
        phoneRest['rest_end_ms'],
        isNotNull,
        reason: 'S-325 the fixture\'s own rest is finished',
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
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-1',
          ),
        ], messageId: 'msg-rest-1'),
      );

      expect(
        await _ids(repository, 'sl-1'),
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-325 the wrist\'s set belongs where the phone\'s own set is',
      );
      final rests = await repository.getEntryRests('sl-1');
      expect(
        rests,
        hasLength(1),
        reason: 'S-325 the wrist\'s rest wrote no second row',
      );
      expect(
        rests.single.toMap(),
        phoneRest,
        reason:
            'S-325 the phone counted this rest itself, so its own record '
            'stands — start, end and stamp unchanged',
      );
      expect(
        phone.transport.receiptedEntryIds,
        contains('rest-a1'),
        reason: 'S-325 the wrist is told the rest is settled, so it stops',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-338 a rest after the last set takes the next index', () async {
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
          _set(
            'sx-2',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 10,
            loadKg: 40,
            loggedAt: _t2,
          ),
          _rest(
            'rest-b1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-2',
          ),
        ], messageId: 'msg-two-sets'),
      );

      final rests = await repository.getEntryRests('sl-1');
      expect(
        rests,
        hasLength(2),
        reason:
            'S-338 one rest event, one row — plus the rest each set\'s arrival '
            'opened (D-6)',
      );
      final closed = rests.singleWhere((rest) => rest.id == 'rest-sl-1-2');
      expect(
        closed.id,
        'rest-sl-1-2',
        reason:
            'S-338 the rest follows the last of two entries, so its spot is '
            'the third',
      );
      expect(
        closed.restStartMs,
        _msOf(_restStart),
        reason: 'S-338 it holds the window the wrist observed',
      );
      expect(
        closed.restEndMs,
        _msOf(_restEnd),
        reason: 'S-338 closed where the wrist saw it end',
      );
      final between = rests.singleWhere((rest) => rest.id == 'rest-sl-1-1');
      expect(
        between.entryIndex,
        1,
        reason: 'S-338 keyed on the spot the first set took + 1',
      );
      expect(
        between.restEndMs,
        _msOf(_t2),
        reason:
            'S-338 the second set ends the rest the first one opened — one '
            'rest runs at a time (A4)',
      );
      expect(
        await _ids(repository, 'sl-1'),
        [
          'obs-sl-1-0-reps',
          'obs-sl-1-0-weight',
          'obs-sl-1-1-reps',
          'obs-sl-1-1-weight',
        ],
        reason: 'S-338 both sets landed, and the rest added no entry',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-337 a rest whose after-entry is gone is dropped and consumed',
        () async {
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
      expect(
        await _ids(repository, 'sl-1'),
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-337 the set to delete is in the effort',
      );

      // The user deletes the set on the phone; the wrist then sends the rest
      // that followed it, beside a set it logged meanwhile.
      await phone.state.deleteEntry('sl-1', 0);
      expect(
        await _ids(repository, 'sl-1'),
        isEmpty,
        reason: 'S-337 the user deleted the set',
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-2',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 10,
            loadKg: 40,
            loggedAt: _t2,
          ),
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-1',
          ),
        ], messageId: 'msg-rest-1'),
      );

      final leftovers = await repository.getEntryRests('sl-1');
      expect(
        leftovers,
        hasLength(1),
        reason:
            'S-337 the rest the deleted set\'s arrival opened is still there '
            '— the wrist\'s rest wrote no row of its own',
      );
      expect(
        leftovers.single.id,
        'rest-sl-1-1',
        reason: 'S-337 the entry the rest named is gone, so nothing keyed to it',
      );
      expect(
        leftovers.single.restEndMs,
        isNull,
        reason: 'S-337 nothing closed the rest the deleted set left behind',
      );
      expect(
        (await _staged(repository))['rest-a1']?.appliedAtMs,
        isNotNull,
        reason:
            'S-337 a row nothing can use is not one the wrist re-sends forever',
      );
      expect(
        await _ids(repository, 'sl-1'),
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'S-337 the set the wrist logged meanwhile still lands',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-328 an unresolvable rest is consumed in the merge too', () async {
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
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-ghost',
          ),
        ], messageId: 'msg-rest-1'),
      );

      final afterDrop = await repository.getEntryRests('sl-1');
      expect(
        afterDrop,
        hasLength(1),
        reason: 'S-328 the rest names no entry the merge placed — no row added',
      );
      expect(
        afterDrop.single.id,
        'rest-sl-1-1',
        reason: 'S-328 the only rest is the one the set\'s arrival opened',
      );
      expect(
        afterDrop.single.restEndMs,
        isNull,
        reason: 'S-328 and it is still running',
      );
      expect(
        (await _staged(repository))['rest-a1']?.appliedAtMs,
        isNotNull,
        reason: 'S-328 the merge consumes a row it drops, so it is not retried',
      );
      expect(
        _lastReceipt(phone),
        containsAll(['sx-1', 'rest-a1']),
        reason: 'S-328 the wrist is told both rows are settled',
      );

      // A retry pass — the wrist never got the receipt — writes nothing more.
      await repository.clearWatchInboxApplied(['rest-a1']);
      await phone.router.receive(
        observationsUp('s-w1', [
          _rest(
            'rest-a1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            startedAt: _restStart,
            endedAt: _restEnd,
            afterEntryId: 'sx-ghost',
          ),
        ], messageId: 'msg-rest-1-again'),
      );
      expect(
        (await repository.getEntryRests('sl-1')).map((rest) => rest.toMap()),
        afterDrop.map((rest) => rest.toMap()),
        reason: 'S-328 the retry is dropped again: the entry is still unknown',
      );
      expect(phone.failures, isEmpty);
    });
  });

  // Plan 36 (routine start sync), Phase B: a set the wrist logged FILLS the
  // phone's next planned set — the row the routine put there, which the phone
  // reads as unlogged because no rest follows it (I-1) — and opens the rest at
  // that row's spot + 1 (D-6). Rows behind the filled one keep the plan's
  // stamp, so a fill replaces exactly one planned set and adds nothing (A3).
  group('S-3604..S-3608 a wrist set fills the planned set', () {
    test('S-3604 a wrist set fills the planned row and opens its rest', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      expect(
        await repository.getEntryRests('sl-1'),
        isEmpty,
        reason: 'S-3604 the fixture\'s planned rows carry no rest',
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-1'),
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
        reason: 'S-3604 the set fills row 0: the effort still holds three sets',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        rows[0].valueInt,
        8,
        reason: 'S-3604 the filled row holds the wrist\'s reps',
      );
      expect(
        rows[0].createdAtMs,
        _msOf(_t1),
        reason: 'S-3604 carrying the wrist\'s stamp, so a later pass finds it',
      );
      expect(
        rows[1].valueReal,
        42.5,
        reason: 'S-3604 and the wrist\'s load',
      );
      expect(
        rows[1].createdAtMs,
        _msOf(_t1),
        reason: 'S-3604 stamped like its reps row',
      );
      expect(
        rows[2].valueInt,
        10,
        reason: 'S-3604 the planned rows behind it stand',
      );
      expect(
        rows[2].createdAtMs,
        _msOf(_plannedAt),
        reason: 'S-3604 with the plan\'s own stamp',
      );
      expect(
        rows[4].valueInt,
        10,
        reason: 'S-3604 and the last planned row too',
      );
      expect(
        (await repository.getEntryRests('sl-1')).map((rest) => rest.toMap()),
        [
          {
            'id': 'rest-sl-1-1',
            'effort_id': 'sl-1',
            'entry_index': 1,
            'rest_start_ms': _msOf(_t1),
            'rest_end_ms': null,
            'rest_is_paused': 0,
            'rest_paused_at_ms': null,
            'rest_paused_duration_ms': 0,
            'created_at_ms': _msOf(_t1),
            'updated_at_ms': _msOf(_t1),
          },
        ],
        reason:
            'S-3604 an open rest at the filled row + 1, run from the wrist\'s '
            'log time (D-6, A4) — so the phone reads the row as logged at once',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3605 a second wrist set fills the next planned row', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-1'),
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-2',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 6,
            loadKg: 45.0,
            loggedAt: _t2,
          ),
        ], messageId: 'msg-fill-2'),
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
        reason:
            'S-3605 the second set fills row 1 — it is not appended after the '
            'row the first set took',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(rows[0].valueInt, 8, reason: 'S-3605 the first fill stands');
      expect(rows[2].valueInt, 6, reason: 'S-3605 the second fill is row 1');
      expect(
        rows[2].createdAtMs,
        _msOf(_t2),
        reason: 'S-3605 carrying the second set\'s stamp',
      );
      expect(rows[3].valueReal, 45.0, reason: 'S-3605 and its load');
      expect(
        rows[4].valueInt,
        10,
        reason: 'S-3605 the last planned row is still the plan\'s',
      );
      expect(
        rows[4].createdAtMs,
        _msOf(_plannedAt),
        reason: 'S-3605 with the plan\'s stamp',
      );
      final rests = await _rests(repository, 'sl-1');
      expect(
        [for (final rest in rests) rest.entryIndex],
        [1, 2],
        reason: 'S-3605 a rest at each filled row\'s spot + 1',
      );
      expect(
        [for (final rest in rests) rest.restStartMs],
        [_msOf(_t1), _msOf(_t2)],
        reason: 'S-3605 each run from the set it followed',
      );
      expect(
        [for (final rest in rests) rest.restEndMs],
        [_msOf(_t2), null],
        reason:
            'S-3605 the second set ends the rest the first one opened — one '
            'rest runs at a time (A4) — and only the second set\'s own rest '
            'is still open',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3606 a fourth set appends once the planned rows are filled',
        () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
          _set(
            'sx-2',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 6,
            loadKg: 45.0,
            loggedAt: _t2,
          ),
          _set(
            'sx-3',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 5,
            loadKg: 45.0,
            loggedAt: _t3,
          ),
          _set(
            'sx-4',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 4,
            loadKg: 40.0,
            loggedAt: _t4,
          ),
        ], messageId: 'msg-fill-4'),
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
          'obs-sl-1-3-reps',
          'obs-sl-1-3-weight',
        ],
        reason: 'S-3606 three planned rows fill, and the fourth set appends one',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        [for (final row in rows) row.createdAtMs],
        [
          _msOf(_t1),
          _msOf(_t1),
          _msOf(_t2),
          _msOf(_t2),
          _msOf(_t3),
          _msOf(_t3),
          _msOf(_t4),
          _msOf(_t4),
        ],
        reason: 'S-3606 every row holds its own wrist set, in logged order',
      );
      expect(
        [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
        [1, 2, 3, 4],
        reason: 'S-3606 a rest after each of the four sets, the appended one too',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3607 the phone\'s own logged set is never filled', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      // The user logged set 0 on the phone itself and finished its rest: rows
      // of the user's own, and a closed rest at the spot the wrist's set would
      // otherwise take (I-2).
      await _phoneRows(
        repository,
        effortId: 'sl-1',
        entryIndex: 0,
        reps: 12,
        weightKg: 50.0,
        atMs: _msOf(_t2),
      );
      await phone.state.recordRestStart('sl-1', 1);
      await phone.state.recordRestEnd('sl-1', 1);
      final ownRest = (await repository.getEntryRests('sl-1')).single.toMap();

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-1'),
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
        reason: 'S-3607 the wrist\'s set fills row 1, the phone\'s own row stands',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        rows[0].valueInt,
        12,
        reason: 'S-3607 the user\'s own set keeps what they logged',
      );
      expect(
        rows[0].createdAtMs,
        _msOf(_t2),
        reason: 'S-3607 and the stamp they logged it at',
      );
      expect(rows[1].valueReal, 50.0, reason: 'S-3607 and their load');
      expect(rows[2].valueInt, 8, reason: 'S-3607 the wrist\'s set is row 1');
      expect(
        rows[2].createdAtMs,
        _msOf(_t1),
        reason: 'S-3607 with the wrist\'s stamp',
      );
      final rests = await _rests(repository, 'sl-1');
      expect(
        [for (final rest in rests) rest.entryIndex],
        [1, 2],
        reason:
            'S-3607 the phone\'s own rest, and the one the fill opened after '
            'the row it filled',
      );
      expect(
        rests.first.toMap(),
        ownRest,
        reason: 'S-3607 the phone\'s own closed rest is left alone',
      );
      expect(
        rests.last.restStartMs,
        _msOf(_t1),
        reason: 'S-3607 the fill\'s rest runs from the wrist\'s log time',
      );
      expect(
        rests.last.restEndMs,
        isNull,
        reason: 'S-3607 and is open, like every rest the merge opens',
      );
      expect(phone.failures, isEmpty);
    });

    test(
        'S-4334 after the phone deleted a middle set the wrist\'s set appends '
        'and no logged set is filled', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      // The user logged all three planned sets on the phone itself, each with
      // its own finished rest (I-1), then deleted the middle one: `deleteEntry`
      // re-keys the rests by POSITION — {1, 2} — while the row NUMBERS keep
      // their hole — {0, 2} — because an id is never renumbered (G1/G4).
      const stamps = [_t2, _t3, _t4];
      const reps = [12, 11, 10];
      const weights = [50.0, 51.0, 52.0];
      for (var index = 0; index < 3; index++) {
        await _phoneRows(
          repository,
          effortId: 'sl-1',
          entryIndex: index,
          reps: reps[index],
          weightKg: weights[index],
          atMs: _msOf(stamps[index]),
        );
      }
      // The rows are the user's own: the phone's own state reads them before it
      // deletes one, as it does when the user logged them on the screen.
      await phone.state.refreshEfforts(['sl-1']);
      for (var index = 0; index < 3; index++) {
        await phone.state.recordRestStart('sl-1', index + 1);
        await phone.state.recordRestEnd('sl-1', index + 1);
      }
      await phone.state.deleteEntry('sl-1', 1);
      expect(
        await _ids(repository, 'sl-1'),
        [
          'obs-sl-1-0-reps',
          'obs-sl-1-0-weight',
          'obs-sl-1-2-reps',
          'obs-sl-1-2-weight',
        ],
        reason: 'S-4334 the fixture: the middle set is gone, the numbers holed',
      );
      expect(
        [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
        [1, 2],
        reason:
            'S-4334 and its rest went with it, the later rest moving down a '
            'position — the numbers did not',
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-4334'),
      );

      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        rows[0].valueInt,
        12,
        reason: 'S-4334 the user\'s first set keeps what they logged',
      );
      expect(
        rows[0].createdAtMs,
        _msOf(_t2),
        reason: 'S-4334 and the stamp they logged it at',
      );
      expect(
        rows[2].valueInt,
        10,
        reason:
            'S-4334 the set right after the hole is the user\'s own, not one '
            'the wrist\'s set took',
      );
      expect(
        rows[2].createdAtMs,
        _msOf(_t4),
        reason: 'S-4334 with its own stamp',
      );
      expect(
        rows[3].valueReal,
        52.0,
        reason: 'S-4334 and its load',
      );
      expect(
        await _ids(repository, 'sl-1'),
        [
          'obs-sl-1-0-reps',
          'obs-sl-1-0-weight',
          'obs-sl-1-2-reps',
          'obs-sl-1-2-weight',
          'obs-sl-1-3-reps',
          'obs-sl-1-3-weight',
        ],
        reason:
            'S-4334 the phone reads every remaining set as logged, so the '
            'wrist\'s set appends the number after the last row — it fills none '
            'of the user\'s',
      );
      expect(
        rows[4].valueInt,
        8,
        reason: 'S-4334 the wrist\'s set is the row the phone appended',
      );
      expect(
        rows[4].createdAtMs,
        _msOf(_t1),
        reason: 'S-4334 with the wrist\'s stamp',
      );
      expect(
        rows[5].valueReal,
        42.5,
        reason: 'S-4334 and its load',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3608 the wrist\'s rest closes the rest the fill opened', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-1'),
      );
      expect(
        (await _rests(repository, 'sl-1')).single.restEndMs,
        isNull,
        reason: 'S-3608 the set\'s arrival left the rest open',
      );

      // The rest the wrist counted behind that set: 60 s, T1 to T1 + 60 s.
      final rest = _rest(
        'rest-a1',
        slot: 'sl-1',
        exerciseId: 'ex-1',
        startedAt: _t1,
        endedAt: _restStart,
        afterEntryId: 'sx-1',
      );
      await phone.router.receive(
        observationsUp('s-w1', [rest], messageId: 'msg-fill-rest'),
      );

      final rests = await _rests(repository, 'sl-1');
      expect(
        rests,
        hasLength(1),
        reason: 'S-3608 the wrist\'s rest closes the row the fill opened — no second row',
      );
      expect(
        rests.single.toMap(),
        {
          'id': 'rest-sl-1-1',
          'effort_id': 'sl-1',
          'entry_index': 1,
          'rest_start_ms': _msOf(_t1),
          'rest_end_ms': _msOf(_restStart),
          'rest_is_paused': 0,
          'rest_paused_at_ms': null,
          'rest_paused_duration_ms': 0,
          'created_at_ms': _msOf(_restStart),
          'updated_at_ms': _msOf(_restStart),
        },
        reason:
            'S-3608 the window the wrist measured, stamped when it was '
            'reported (D-7)',
      );
      final closed = rests.single.toMap();

      // The wrist re-sends it — the phone never got the receipt.
      await phone.router.receive(
        observationsUp('s-w1', [rest], messageId: 'msg-fill-rest-again'),
      );
      expect(
        (await _rests(repository, 'sl-1')).map((row) => row.toMap()),
        [closed],
        reason: 'S-3608 a rest the phone already holds closed is left alone',
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
        reason: 'S-3608 a rest is not an entry: the effort still holds three',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3616 a skipped planned row is not logged, so the wrist fills it',
        () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      // The user marked the first set as skipped: the row reads reps 0, and no
      // rest follows it, so the phone does not count it as logged (I-1).
      await _phoneRows(
        repository,
        effortId: 'sl-1',
        entryIndex: 0,
        reps: 0,
        weightKg: 40.0,
        atMs: _msOf(_plannedAt),
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-1'),
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
        reason: 'S-3616 the wrist\'s set fills the skipped row 0',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(
        rows[0].valueInt,
        8,
        reason: 'S-3616 the skipped row now holds the wrist\'s reps',
      );
      expect(
        rows[0].createdAtMs,
        _msOf(_t1),
        reason: 'S-3616 with the wrist\'s stamp — a skip is not a log',
      );
      expect(rows[2].valueInt, 10, reason: 'S-3616 the planned rows behind stand');
      expect(
        rows[2].createdAtMs,
        _msOf(_plannedAt),
        reason: 'S-3616 untouched, plan stamp and all',
      );
      expect(
        [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
        [1],
        reason: 'S-3616 the rest lands at the filled row\'s spot + 1',
      );
      expect(phone.failures, isEmpty);
    });

    test('S-3618 the wrist\'s set ends the phone\'s older open rest', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);
      // The phone logged set 0 itself: the rest it started after that set is
      // still running when the wrist's next set arrives.
      await repository.createEntryRest(
        EntryRest(
          id: 'rest-sl-1-1',
          effortId: 'sl-1',
          entryIndex: 1,
          restStartMs: _msOf(_t1) - 90000,
          restEndMs: null,
          createdAtMs: _msOf(_t1) - 90000,
          updatedAtMs: _msOf(_t1) - 90000,
        ),
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-1',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 8,
            loadKg: 42.5,
            loggedAt: _t1,
          ),
        ], messageId: 'msg-fill-open'),
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
        reason:
            'S-3618 the set fills row 1 — the phone\'s rest leaves row 0 read '
            'as logged, so the fill takes the next unlogged row',
      );
      final rows = await sortedObservations(repository, 'sl-1');
      expect(rows[2].valueInt, 8, reason: 'S-3618 the wrist\'s reps fill row 1');
      expect(rows[3].valueReal, 42.5, reason: 'S-3618 and the wrist\'s load');

      final rests = await _rests(repository, 'sl-1');
      expect(
        [for (final rest in rests) rest.toMap()],
        [
          {
            'id': 'rest-sl-1-1',
            'effort_id': 'sl-1',
            'entry_index': 1,
            'rest_start_ms': _msOf(_t1) - 90000,
            'rest_end_ms': _msOf(_t1),
            'rest_is_paused': 0,
            'rest_paused_at_ms': null,
            'rest_paused_duration_ms': 0,
            'created_at_ms': _msOf(_t1) - 90000,
            'updated_at_ms': _msOf(_t1),
          },
          {
            'id': 'rest-sl-1-2',
            'effort_id': 'sl-1',
            'entry_index': 2,
            'rest_start_ms': _msOf(_t1),
            'rest_end_ms': null,
            'rest_is_paused': 0,
            'rest_paused_at_ms': null,
            'rest_paused_duration_ms': 0,
            'created_at_ms': _msOf(_t1),
            'updated_at_ms': _msOf(_t1),
          },
        ],
        reason:
            'S-3618 the phone\'s older open rest ends where the wrist\'s set '
            'landed, and the rest that set opened sits at its spot + 1 (A4: '
            'one rest running, D-6)',
      );
      expect(
        [for (final rest in rests) rest.restEndMs],
        [_msOf(_t1), null],
        reason:
            'S-3618 exactly one rest on the effort is open — the older open '
            'rest is closed, not left running beside the new one',
      );
      expect(phone.failures, isEmpty);
    });
  });

  group('S-4501..S-4507 a rest is keyed on the POSITION', () {
    // ─── S-4501..S-4507: rests are positional, the numbers are not ──────────
    //
    // D-1..D-3. The importer has to read a placed entry by POSITION when it
    // writes the rest a set leaves behind, and it has to re-key the effort's
    // rests after it deletes a wrist set, exactly as the phone's own
    // `deleteEntry` does.

    /// The fixture S-4334 and S-4501/4502 share: three sets the user logged on
    /// the phone, each with its own finished rest (I-1), then the middle one
    /// deleted — the rest positions close up to {1, 2} while the row numbers
    /// keep their hole, {0, 2} (G1/G4).
    Future<void> holedEffort(_Phone phone) async {
      await _plannedRows(repository);
      const stamps = [_t2, _t3, _t4];
      const reps = [12, 11, 10];
      const weights = [50.0, 51.0, 52.0];
      for (var index = 0; index < 3; index++) {
        await _phoneRows(
          repository,
          effortId: 'sl-1',
          entryIndex: index,
          reps: reps[index],
          weightKg: weights[index],
          atMs: _msOf(stamps[index]),
        );
      }
      // The rows are the user's own: the phone's own state reads them before it
      // deletes one, as it does when the user logged them on the screen.
      await phone.state.refreshEfforts(['sl-1']);
      for (var index = 0; index < 3; index++) {
        await phone.state.recordRestStart('sl-1', index + 1);
        await phone.state.recordRestEnd('sl-1', index + 1);
      }
      await phone.state.deleteEntry('sl-1', 1);
    }

    /// A wrist set stamped before every row the phone holds, so it lands after
    /// the hole: on the shared fixture the last row's NUMBER is 2 and its
    /// POSITION is 1.
    Map<String, Object?> wristSet(
      String entryId,
      int reps, {
      String loggedAt = _t1,
    }) => _set(
      entryId,
      slot: 'sl-1',
      exerciseId: 'ex-1',
      reps: reps,
      loadKg: 42.5,
      loggedAt: loggedAt,
    );

    test(
      'S-4501 after the phone deleted a middle set the wrist\'s set opens its '
      'rest at its POSITION + 1, not the row number + 1',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await holedEffort(phone);
        expect(
          [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
          [1, 2],
          reason:
              'S-4501 the fixture: the rest positions closed up, the row '
              'numbers did not',
        );

        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4501-append',
          ),
        );

        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
            'obs-sl-1-3-reps',
            'obs-sl-1-3-weight',
          ],
          reason: 'S-4501 the wrist\'s set appends the number after the last row',
        );
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4501 the appended set is the effort\'s third POSITION (the '
              'numbered rows are 0, 2 and 3), so its rest sits at 3 — keyed on '
              'the row number it carries, 3, the importer writes 4 instead',
        );
        expect(rests.last.id, 'rest-sl-1-3');
        expect(rests.last.restStartMs, _msOf(_t1));
        expect(rests.last.restEndMs, isNull, reason: 'S-4501 the rest runs');
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4502a the wrist\'s late rest report closes the rest the appended set '
      'opened', () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await holedEffort(phone);
        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4502a-append',
          ),
        );

        await phone.router.receive(
          observationsUp(
            's-w1',
            [
              _rest(
                'rx-1',
                slot: 'sl-1',
                exerciseId: 'ex-1',
                startedAt: _restStart,
                endedAt: _restEnd,
                afterEntryId: 'sx-1',
              ),
            ],
            messageId: 'msg-4502a-rest',
          ),
        );

        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4502a the report lands on the rest the appended set opened — '
              'at its position + 1 — and opens no second one at the row number '
              '+ 1',
        );
        expect(rests.last.id, 'rest-sl-1-3');
        expect(rests.last.restStartMs, _msOf(_restStart));
        expect(rests.last.restEndMs, _msOf(_restEnd));
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4502b the same, with the set and its report in one message',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await holedEffort(phone);

        await phone.router.receive(
          observationsUp(
            's-w1',
            [
              wristSet('sx-1', 8),
              _rest(
                'rx-1',
                slot: 'sl-1',
                exerciseId: 'ex-1',
                startedAt: _restStart,
                endedAt: _restEnd,
                afterEntryId: 'sx-1',
              ),
            ],
            messageId: 'msg-4502b',
          ),
        );

        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4502b the report closes the rest the same pass opened, not a '
              'rest at the row number + 1',
        );
        expect(rests.last.id, 'rest-sl-1-3');
        expect(rests.last.restStartMs, _msOf(_restStart));
        expect(rests.last.restEndMs, _msOf(_restEnd));
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4503 a wrist set after the phone\'s delete fills the first unlogged '
      'POSITION and opens its rest there',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository, count: 4);
        await phone.state.refreshEfforts(['sl-1']);
        await phone.state.recordRestStart('sl-1', 1);
        await phone.state.recordRestEnd('sl-1', 1);
        await phone.state.deleteEntry('sl-1', 1);
        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
            'obs-sl-1-3-reps',
            'obs-sl-1-3-weight',
          ],
          reason: 'S-4503 the fixture: number 1 is the hole, the rest sits at 1',
        );

        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4503-fill',
          ),
        );

        final rows = await sortedObservations(repository, 'sl-1');
        expect(rows[2].id, 'obs-sl-1-2-reps');
        expect(
          rows[2].valueInt,
          8,
          reason:
              'S-4503 the wrist\'s set takes the first POSITION no rest marks '
              'logged — position 1, the row numbered 2',
        );
        expect(rows[2].createdAtMs, _msOf(_t1));
        expect(rows[4].id, 'obs-sl-1-3-reps');
        expect(
          rows[4].valueInt,
          10,
          reason: 'S-4503 the row past it is still the routine\'s preset',
        );
        expect(rows[4].createdAtMs, _msOf(_plannedAt));
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2],
          reason:
              'S-4503 the filled position is 1, so its rest sits at 2 — keyed '
              'on the filled row\'s number, 2, the importer writes 3',
        );
        expect(rests.last.id, 'rest-sl-1-2');
        expect(rests.last.restStartMs, _msOf(_t1));
        expect(rests.last.restEndMs, isNull);
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4504 a fill below an open rest leaves that rest running',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository, count: 5);
        await phone.state.refreshEfforts(['sl-1']);
        await phone.state.recordRestStart('sl-1', 1);
        await phone.state.recordRestEnd('sl-1', 1);
        await phone.state.recordRestStart('sl-1', 5);
        await phone.state.deleteEntry('sl-1', 1);
        await phone.state.deleteEntry('sl-1', 1);
        expect(
          [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
          [1, 3],
          reason:
              'S-4504 the fixture: two deletes leave the finished rest at 1 '
              'and the running one at 3',
        );
        final runningBefore = (
          await _rests(repository, 'sl-1')
        ).firstWhere((rest) => rest.entryIndex == 3).toMap();

        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4504-fill',
          ),
        );

        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4504 the wrist\'s set fills position 1 (the row numbered 3) '
              'and its rest sits at 2 — keyed on the row number, the importer '
              'writes 4 instead and closes the running rest beside it',
        );
        expect(
          rests.first.restEndMs,
          isNotNull,
          reason: 'S-4504 the finished rest below the fill is untouched',
        );
        expect(rests[1].id, 'rest-sl-1-2');
        expect(rests[1].restStartMs, _msOf(_t1));
        expect(rests[1].restEndMs, isNull, reason: 'S-4504 it is running');
        expect(
          rests.last.toMap(),
          runningBefore,
          reason:
              'S-4504 the running rest two POSITIONS above the fill is not the '
              'one that ends: the set landed below it',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4505 the phone\'s delete of a wrist set re-keys the rests the merge '
      'wrote',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository);
        const stamps = [_t1, _t2, _t3];
        for (var index = 0; index < 3; index++) {
          await phone.router.receive(
            observationsUp(
              's-w1',
              [wristSet('sx-${index + 1}', 8 + index, loggedAt: stamps[index])],
              messageId: 'msg-4505-set-${index + 1}',
            ),
          );
        }
        await phone.router.receive(
          observationsUp(
            's-w1',
            [
              _rest(
                'rx-1',
                slot: 'sl-1',
                exerciseId: 'ex-1',
                startedAt: _restStart,
                endedAt: _restEnd,
                afterEntryId: 'sx-1',
              ),
            ],
            messageId: 'msg-4505-rest-1',
          ),
        );
        await phone.router.receive(
          observationsUp(
            's-w1',
            [
              _rest(
                'rx-2',
                slot: 'sl-1',
                exerciseId: 'ex-1',
                startedAt: '2026-10-05T10:21:00Z',
                endedAt: '2026-10-05T10:22:00Z',
                afterEntryId: 'sx-2',
              ),
            ],
            messageId: 'msg-4505-rest-2',
          ),
        );
        final before = [
          for (final rest in await _rests(repository, 'sl-1')) rest.toMap(),
        ];
        expect(
          [for (final rest in before) rest['entry_index']],
          [1, 2, 3],
          reason: 'S-4505 the fixture: each filled set left its own rest',
        );

        await phone.inbox.stagePhoneChanges(
          _deleteEnvelope('del-4505', 'sx-2'),
        );

        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
          ],
          reason: 'S-4505 the deleted set\'s rows go and no other row moves',
        );
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2],
          reason:
              'S-4505 the deleted set\'s rest goes and the later one moves '
              'down a POSITION — the importer leaves the rests where they were',
        );
        expect(
          rests.first.toMap(),
          before.first,
          reason: 'S-4505 the rest below the delete does not change',
        );
        expect(rests.last.id, 'rest-sl-1-2');
        expect(rests.last.restStartMs, _msOf(_t3));
        expect(
          rests.last.restEndMs,
          isNull,
          reason: 'S-4505 the later rest keeps the stamps it had, running',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4506 the delete re-keys by position where the numbers and the '
      'positions disagree',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository);
        await _phoneRest(
          repository,
          effortId: 'sl-1',
          entryIndex: 3,
          startedAtMs: _msOf(_t3),
          endedAtMs: _msOf(_t4),
        );
        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4506-set',
          ),
        );
        expect(
          [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
          [1, 3],
          reason: 'S-4506 the fixture: the fill\'s rest at 1, the user\'s at 3',
        );

        await phone.inbox.stagePhoneChanges(
          _deleteEnvelope('del-4506', 'sx-1'),
        );

        final rows = await sortedObservations(repository, 'sl-1');
        expect(
          [for (final row in rows) row.id],
          [
            'obs-sl-1-1-reps',
            'obs-sl-1-1-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
          ],
          reason:
              'S-4506 the deleted set\'s rows go and the user\'s own rows keep '
              'their numbers',
        );
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [2],
          reason:
              'S-4506 the user\'s rest marked the set at POSITION 2 (the row '
              'numbered 3); with the set below it gone it marks POSITION 1 (the '
              'row numbered 2) — the importer leaves it at 3',
        );
        expect(rests.single.id, 'rest-sl-1-2');
        expect(rests.single.restStartMs, _msOf(_t3));
        expect(
          EntryRows.loggedSetNumbersOf(EntryRows.setGroups(rows), rests),
          {2},
          reason:
              'S-4506 position 0 (the row numbered 1) reads unlogged and '
              'position 1 (the row numbered 2) logged',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4507 the delete of the only wrist set takes its rest with it, once '
      'per change',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository, count: 1);
        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4507-set',
          ),
        );
        expect(
          [for (final rest in await _rests(repository, 'sl-1')) rest.entryIndex],
          [1],
          reason: 'S-4507 the fixture: the fill is position 0, so its rest is 1',
        );

        await phone.inbox.stagePhoneChanges(
          _deleteEnvelope('del-4507', 'sx-1'),
        );

        expect(
          [
            for (final row in await sortedObservations(repository, 'sl-1'))
              row.createdAtMs,
          ],
          isNot(contains(_msOf(_t1))),
          reason: 'S-4507 no row the deleted set wrote is left',
        );
        expect(
          await _rests(repository, 'sl-1'),
          isEmpty,
          reason:
              'S-4507 the only rest on the effort was the deleted set\'s own '
              'mark — the delete takes it with it',
        );

        await phone.inbox.stagePhoneChanges(
          _deleteEnvelope('del-4507', 'sx-1'),
        );

        expect(
          await _rests(repository, 'sl-1'),
          isEmpty,
          reason: 'S-4507 a redelivered change changes nothing',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4509 a retry of the pass that wrote the appended set opens no second '
      'rest, and leaves the one it left closed',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await holedEffort(phone);
        // What the pass that placed the wrist's set wrote before it stopped,
        // short of marking the row applied: the set's rows at the number after
        // the last one the phone holds, and the rest that marked it — already
        // closed by the wrist's own report. The set comes back, so the pass
        // runs again over a spot that already holds everything it would write.
        await _phoneRows(
          repository,
          effortId: 'sl-1',
          entryIndex: 3,
          reps: 8,
          weightKg: 42.5,
          atMs: _msOf(_t1),
        );
        await repository.createEntryRest(
          EntryRest(
            id: 'rest-sl-1-3',
            effortId: 'sl-1',
            entryIndex: 3,
            restStartMs: _msOf(_restStart),
            restEndMs: _msOf(_restEnd),
            createdAtMs: _msOf(_t1),
            updatedAtMs: _msOf(_restEnd),
          ),
        );

        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4509-retry',
          ),
        );

        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
            'obs-sl-1-3-reps',
            'obs-sl-1-3-weight',
          ],
          reason:
              'S-4509 the retry rewrites the set\'s own rows where the first '
              'pass put them and appends nothing after them',
        );
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4509 the rest at 3 is the one the first pass left: a set whose '
              'spot the effort\'s rests already mark opens no second one',
        );
        expect(rests.last.id, 'rest-sl-1-3');
        expect(rests.last.restStartMs, _msOf(_restStart));
        expect(
          rests.last.restEndMs,
          _msOf(_restEnd),
          reason:
              'S-4509 the rest the wrist\'s report closed stays closed — the '
              'retry does not write an open one over it',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4510 the delete of a wrist set appended after a hole re-keys the '
      'effort\'s rests by POSITION',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await holedEffort(phone);
        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8)],
            messageId: 'msg-4510-append',
          ),
        );
        final before = [
          for (final rest in await _rests(repository, 'sl-1')) rest.toMap(),
        ];
        expect(
          [for (final rest in before) rest['entry_index']],
          [1, 2, 3],
          reason:
              'S-4510 the fixture: the wrist\'s set carries number 3, its rest '
              'sits at POSITION 2 + 1',
        );

        await phone.inbox.stagePhoneChanges(
          _deleteEnvelope('del-4510', 'sx-1'),
        );

        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
          ],
          reason: 'S-4510 the deleted set\'s rows go and no other row moves',
        );
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2],
          reason:
              'S-4510 the set sits at POSITION 2, so the rest at 3 goes with '
              'it — reading the POSITION off the row number (3) finds no rest '
              'at 4 and leaves all three',
        );
        expect(
          [for (final rest in rests) rest.toMap()],
          [before[0], before[1]],
          reason:
              'S-4510 the rests the phone finished itself are the ones the '
              'delete keeps, each exactly as it was',
        );
        expect(phone.failures, isEmpty);
      },
    );

    test(
      'S-4511 two wrist sets in one message fill two POSITIONS, not the same '
      'one twice',
      () async {
        final phone = await _phone(repository);
        await phone.router.receive(_snapshot());
        await _plannedRows(repository, count: 4);
        await phone.state.refreshEfforts(['sl-1']);
        await phone.state.recordRestStart('sl-1', 1);
        await phone.state.recordRestEnd('sl-1', 1);
        await phone.state.deleteEntry('sl-1', 1);

        await phone.router.receive(
          observationsUp(
            's-w1',
            [wristSet('sx-1', 8), wristSet('sx-2', 9, loggedAt: _t2)],
            messageId: 'msg-4511-two',
          ),
        );

        expect(
          await _ids(repository, 'sl-1'),
          [
            'obs-sl-1-0-reps',
            'obs-sl-1-0-weight',
            'obs-sl-1-2-reps',
            'obs-sl-1-2-weight',
            'obs-sl-1-3-reps',
            'obs-sl-1-3-weight',
          ],
          reason:
              'S-4511 the two sets take the two POSITIONS the phone reads as '
              'unlogged, 1 and 2, and the numbers stay holed at 1',
        );
        final rows = await sortedObservations(repository, 'sl-1');
        expect(
          rows[2].valueInt,
          8,
          reason: 'S-4511 the first set is the one at number 2',
        );
        expect(rows[2].createdAtMs, _msOf(_t1));
        expect(
          rows[4].valueInt,
          9,
          reason:
              'S-4511 the second set takes the next POSITION, not the first '
              'one a second time',
        );
        expect(rows[4].createdAtMs, _msOf(_t2));
        final rests = await _rests(repository, 'sl-1');
        expect(
          [for (final rest in rests) rest.entryIndex],
          [1, 2, 3],
          reason:
              'S-4511 each fill opens its own rest: the pass has to remember, '
              'as it places, that the spot it just filled is taken',
        );
        expect(rests[1].id, 'rest-sl-1-2');
        expect(rests[1].restStartMs, _msOf(_t1));
        expect(
          rests[1].restEndMs,
          _msOf(_t2),
          reason:
              'S-4511 one rest runs at a time: the set that landed above the '
              'running one ends it',
        );
        expect(rests[2].id, 'rest-sl-1-3');
        expect(rests[2].restStartMs, _msOf(_t2));
        expect(rests[2].restEndMs, isNull, reason: 'S-4511 the last one runs');
        expect(phone.failures, isEmpty);
      },
    );
  });
}
