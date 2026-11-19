// Plan 36 (routine start sync), Phase C — S-3609: the round trip of a set the
// wrist logged into a session the phone holds.
//
// The phone's session starts from the routine, so its set rows are the plan's
// presets. A set the wrist logs FILLS the next planned row (D-4) and opens the
// rest at that row's spot + 1 (D-6), so the phone reads it as a logged set (A4)
// — and what the phone answers the wrist with (`projectSession`, composed out
// of `PhoneEntries.project`) carries the sets the phone logged **itself**, never
// the wrist's own: a live watch-inbox row claims the group stamped like it
// (D-34), because the wrist already holds that set and naming it back under
// `entry-sl-1-0` would double it. A row the phone never logged is a planned
// value and is left out too (I-1).
//
// Plan: `docs/plans/2026-10-14-36-routine-start-sync-plan/2026-10-14-36-routine-start-sync-plan.md`,
// Phase C. Scenario mapping:
//   S-3609 the planned sets round-trip without echoing the wrist's → `S-3609 ...`
//
// Plain `test()` on the Mock store, the phone-session setup pattern of
// `test/watch_session_merge_test.dart`: no widget is involved, and every future
// here is a microtask of the mock repository, so no real clock or Hive write
// runs. The phone's own logging is `WorkoutState.recordRestStart`, the call
// `_logSet` makes when the user taps Log Set.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
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
    show CaptureTransport, observationsUp, seedExercise, sortedObservations;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

const String _t1 = '2026-10-05T10:10:00Z';
const String _t4 = '2026-10-05T10:40:00Z';

/// The stamp the phone's planned rows carry (plan 36 D-4): the routine wrote
/// them before the session, so it is earlier than every wrist set's.
const String _plannedAt = '2026-10-05T09:00:00Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// One phone, wired the way `createWatchSync` wires it: the adoption bridge
/// first, the inbox that asks it whether a session is the phone's own, the
/// mirror behind the entry-staging transport, and the router that drives them.
class _Phone {
  _Phone({
    required this.router,
    required this.state,
    required this.bridge,
    required this.failures,
  });

  final WatchIncomingRouter router;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;

  /// What the graph reported as a failure: nothing, in this scenario.
  final List<Object> failures;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _phoneNow,
    onFailure: (error, stack) => failures.add(error),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: _validator,
    clock: () => _phoneNow,
    onHistoryChanged: () async {},
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
    failures: failures,
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

/// Fixture F (plan 36 D-4): the phone's own slot holds [count] planned rows —
/// a routine's presets, 10 reps at 40.0 kg — with no rest after any of them,
/// so the phone reads none of them as logged (I-1).
Future<void> _plannedRows(WorkoutRepository repository, {int count = 3}) async {
  for (var index = 0; index < count; index++) {
    for (final row in LoggedEntryRows.setObservations(
      effortId: 'sl-1',
      entryIndex: index,
      reps: 10,
      weightKg: 40.0,
      exerciseHasLoad: true,
      atMs: _msOf(_plannedAt),
    )) {
      await repository.createObservation(row);
    }
  }
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

// ─── Reading what the phone answered ────────────────────────────────────────

List<Map<String, Object?>> _entries(Map<String, Object?>? payload) => [
  for (final entry in ((payload?['entries'] as List?) ?? const []))
    (entry as Map).cast<String, Object?>(),
];

List<String> _entryIds(Map<String, Object?>? payload) => [
  for (final entry in _entries(payload)) entry['entryId']! as String,
];

Map<String, Object?> _entryById(
  Map<String, Object?>? payload,
  String entryId,
) => _entries(payload).singleWhere((entry) => entry['entryId'] == entryId);

void main() {
  group('Mock', () {
    late WorkoutRepository repository;

    setUp(() async {
      final mock = MockWorkoutRepository();
      await mock.initialize();
      await _seed(mock);
      repository = mock;
    });

    test('S-3609 the set the wrist logged is never echoed back to it', () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _plannedRows(repository);

      expect(
        _entryIds(await phone.bridge.projectSession(null)),
        isEmpty,
        reason:
            'S-3609 nothing the phone logged itself is sent: the three rows the routine '
            'wrote are planned values, and a planned row is no set of the phone\'s (I-1)',
      );

      // The wrist logs set 1. It FILLS row 0 of the plan and opens the rest the
      // owner asked for at that row's spot + 1, which is what makes the phone
      // read the row as logged.
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
        _entryIds(await phone.bridge.projectSession(null)),
        isEmpty,
        reason:
            'S-3609 the set the wrist logged is not echoed back as `entry-sl-1-0`: its '
            'stamp claims the row it filled (D-34), and a row the wrist holds needs no '
            'phone entry',
      );

      // The user logs set 2 on the phone itself: the row after the filled one.
      await phone.state.recordRestStart('sl-1', 2);

      final afterThePhoneLogged = await phone.bridge.projectSession(null);
      expect(
        _entryIds(afterThePhoneLogged),
        ['entry-sl-1-1'],
        reason:
            'S-3609 the set the phone logged itself rides back, and only it: row 0 is the '
            'wrist\'s own and row 2 is still planned',
      );
      expect(
        _entryById(afterThePhoneLogged, 'entry-sl-1-1')['reps'],
        10,
        reason: 'S-3609 carrying the planned row\'s own reps',
      );
      expect(
        _entryById(afterThePhoneLogged, 'entry-sl-1-1')['loadKg'],
        40.0,
        reason: 'S-3609 and the 40 kg the routine presets that row with',
      );

      // The user logs the last planned row too, so every row is a set of the
      // phone's and none is left to fill.
      await phone.state.recordRestStart('sl-1', 3);

      expect(
        _entryIds(await phone.bridge.projectSession(null)),
        ['entry-sl-1-1', 'entry-sl-1-2'],
        reason:
            'S-3609 every set the phone logged rides back, in entry order, and the wrist\'s '
            'own row still does not',
      );

      // A fourth wrist set: with every planned row filled and rested there is no
      // row left to fill, so it appends an entry of its own.
      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-2',
            slot: 'sl-1',
            exerciseId: 'ex-1',
            reps: 6,
            loadKg: 45.0,
            loggedAt: _t4,
          ),
        ], messageId: 'msg-fill-4'),
      );

      expect(
        [
          for (final row in await sortedObservations(repository, 'sl-1'))
            row.id,
        ],
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
        reason:
            'S-3609 the fourth wrist set appended a row group of its own: the effort holds '
            'the three planned sets and that one',
      );

      expect(
        _entryIds(await phone.bridge.projectSession(null)),
        ['entry-sl-1-1', 'entry-sl-1-2'],
        reason:
            'S-3609 and it is not echoed back either: the phone answers with the two sets it '
            'logged itself, never `entry-sl-1-3` for the row the wrist\'s own set appended',
      );
      expect(phone.failures, isEmpty);
    });
  });
}
