// A wrist `rest` event whose `afterEntryId` names an entry the PHONE logged
// closes the phone's own running rest (plan 50b D-1, S-7401..S-7405).
//
// Modelled on `watch_session_rest_timer_append_test.dart` (S-320: the harness
// and the rest event's shape) and `watch_session_merge_test.dart`
// (S-4501..S-4507: the Mock/Hive openers and the phone-logged fixtures). The
// append test's harness is private, so this file carries its own.
//
// Plain `test()`: the rest windows are fixed instants, so there is no widget,
// no real clock and no threshold to race. The event arrives through the real
// mirror and router, the way every other adoption test delivers one.
//
// Plan: `docs/plans/2026-10-21-50b-wrist-next-closes-phone-rest-plan/2026-10-21-50b-wrist-next-closes-phone-rest-plan.md`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/block_types.dart';
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
    show CaptureTransport, observationsUp, seedExercise;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in a scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 21, 9);

/// The fixture's stamps: the phone logged its set at [_setAt], its rest has
/// been running since [_restStart], and the wrist reports that rest's end
/// 90 s after it started.
const String _setAt = '2026-10-21T08:56:00Z';
const String _restStart = '2026-10-21T08:58:00Z';
const String _restEnd = '2026-10-21T08:59:30Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test`. Same pattern as
/// `test/watch_session_merge_test.dart`.
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
    required this.router,
    required this.state,
    required this.failures,
  });

  final WorkoutRepository repository;
  final WatchIncomingRouter router;
  final WorkoutState state;

  /// What the graph reported as a failure: nothing, in these tests.
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
    failures: failures,
  );
}

// ─── The fixtures ───────────────────────────────────────────────────────────

/// One ladder slot as the wrist sends it, declaring its kind when it has one.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId, {
  String? effortKind,
}) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': const ['sets', 'reps', 'load'],
  'effortKind': ?effortKind,
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  String messageId = 'msg-snapshot',
  required List<Map<String, Object?>> exercises,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': 's-w1',
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-21T08:50:00Z',
  'payload': {
    'sessionId': 's-w1',
    'revision': 3,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// A wrist `rest` the wrist observed after a PHONE-logged entry (50b D-1):
/// the `afterEntryId` is the id `PhoneEntries` mints for the phone's own
/// entries, which the importer does not hold in its placed map.
Map<String, Object?> _rest(String entryId, String afterEntryId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'rest',
  'loggedAt': _restEnd,
  'sessionExerciseId': 'sl-1',
  'exerciseId': 'ex-bench',
  'startedAt': _restStart,
  'endedAt': _restEnd,
  'afterEntryId': afterEntryId,
};

/// The set the phone logged on [effortId] at [entryIndex] — the rows the
/// regular session screen writes (`LoggedEntryRows`).
Future<void> _phoneSet(
  WorkoutRepository repository, {
  required String effortId,
  required int entryIndex,
}) async {
  for (final row in LoggedEntryRows.setObservations(
    effortId: effortId,
    entryIndex: entryIndex,
    reps: 8,
    weightKg: 40,
    exerciseHasLoad: true,
    atMs: _msOf(_setAt),
  )) {
    await repository.createObservation(row);
  }
}

/// A rest the phone counted itself, at the spot after its set: open when
/// [endedAtMs] is null, finished when it is not.
Future<void> _phoneRest(
  WorkoutRepository repository, {
  required String effortId,
  required int entryIndex,
  required int? endedAtMs,
}) => repository.createEntryRest(
  EntryRest(
    id: 'rest-$effortId-$entryIndex',
    effortId: effortId,
    entryIndex: entryIndex,
    restStartMs: _msOf(_restStart),
    restEndMs: endedAtMs,
    createdAtMs: _msOf(_restStart),
    updatedAtMs: endedAtMs ?? _msOf(_restStart),
  ),
);

/// The timed instance the phone logged on [effortId] at [entryIndex].
Future<void> _phoneTimed(
  WorkoutRepository repository, {
  required String effortId,
  required int entryIndex,
}) => repository.createTimedInstance(
  TimedInstance(
    id: 'timed-$effortId-$entryIndex',
    effortId: effortId,
    entryIndex: entryIndex,
    startedAtMs: _msOf(_setAt),
    finishedAtMs: _msOf(_restStart),
    actualDurationSecs: 120,
    state: TimedState.finished,
    createdAtMs: _msOf(_setAt),
    updatedAtMs: _msOf(_restStart),
  ),
);

/// The round the phone logged on [effortId] at [roundIndex].
Future<void> _phoneRound(
  WorkoutRepository repository, {
  required String effortId,
  required int roundIndex,
}) => repository.createRoundInstance(
  RoundInstance(
    id: 'round-$effortId-$roundIndex',
    effortId: effortId,
    roundIndex: roundIndex,
    startedAtMs: _msOf(_setAt),
    finishedAtMs: _msOf(_restStart),
    actualDurationSecs: 120,
    completed: true,
    state: RoundState.finished,
    createdAtMs: _msOf(_setAt),
    updatedAtMs: _msOf(_restStart),
  ),
);

/// One effort's rests, in entry-index order, so a scenario can name them.
Future<List<EntryRest>> _rests(WorkoutRepository repository, String effortId) =>
    repository.getEntryRests(effortId).then(
      (rests) => [...rests]..sort((a, b) => a.entryIndex.compareTo(b.entryIndex)),
    );

Future<List<Map<String, Object?>>> _restMaps(
  WorkoutRepository repository,
  String effortId,
) async => [for (final rest in await _rests(repository, effortId)) rest.toMap()];

// ─── The scenarios ──────────────────────────────────────────────────────────

void main() {
  group('Mock', () => _phoneEntryTests(open: _openMock, close: () async {}));
  group('Hive', () => _phoneEntryTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('watch_rest_phone_');
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

Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-bench',
    name: 'Bench Press',
    capabilities: const ['sets', 'reps', 'load'],
  );
}

void _phoneEntryTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test(
    'S-7401 a wrist rest after a phone-logged set closes the phone\'s running rest',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(
        _snapshot(exercises: [_slot('sl-1', 'ex-bench')]),
      );
      await _phoneSet(repository, effortId: 'sl-1', entryIndex: 0);
      await _phoneRest(repository, effortId: 'sl-1', entryIndex: 1, endedAtMs: null);

      await phone.router.receive(
        observationsUp('s-w1', [
          _rest('rest-a1', 'entry-sl-1-0'),
        ], messageId: 'msg-7401'),
      );

      final rests = await _rests(repository, 'sl-1');
      expect(
        rests,
        hasLength(1),
        reason:
            'S-7401 still one row: the wrist\'s report closed the phone\'s own '
            'rest, it wrote no second one',
      );
      expect(rests.single.id, 'rest-sl-1-1');
      expect(
        rests.single.restStartMs,
        _msOf(_restStart),
        reason: 'D-7 the running rest takes the wrist\'s window',
      );
      expect(
        rests.single.restEndMs,
        _msOf(_restEnd),
        reason: 'S-7401 and closes at the end the wrist observed',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-7402 the same for an entry on a timed effort', () async {
    final phone = await _phone(repository);
    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot('sl-1', 'ex-bench', effortKind: BlockTypes.timed),
        ],
        messageId: 'msg-7402t-snap',
      ),
    );
    await _phoneTimed(repository, effortId: 'sl-1', entryIndex: 0);
    await _phoneRest(repository, effortId: 'sl-1', entryIndex: 1, endedAtMs: null);

    await phone.router.receive(
      observationsUp('s-w1', [
        _rest('rest-a1', 'entry-sl-1-0'),
      ], messageId: 'msg-7402t'),
    );

    final rests = await _rests(repository, 'sl-1');
    expect(rests, hasLength(1), reason: 'S-7402 still one row');
    expect(
      rests.single.restEndMs,
      _msOf(_restEnd),
      reason: 'S-7402 the timed instance\'s entry closed the phone\'s rest',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-7402 the same for an entry on a round effort', () async {
    final phone = await _phone(repository);
    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot('sl-1', 'ex-bench', effortKind: BlockTypes.round),
        ],
        messageId: 'msg-7402r-snap',
      ),
    );
    await _phoneRound(repository, effortId: 'sl-1', roundIndex: 0);
    await _phoneRest(repository, effortId: 'sl-1', entryIndex: 1, endedAtMs: null);

    await phone.router.receive(
      observationsUp('s-w1', [
        _rest('rest-a1', 'entry-sl-1-0'),
      ], messageId: 'msg-7402r'),
    );

    final rests = await _rests(repository, 'sl-1');
    expect(rests, hasLength(1), reason: 'S-7402 still one row');
    expect(
      rests.single.restEndMs,
      _msOf(_restEnd),
      reason: 'S-7402 the round instance\'s entry closed the phone\'s rest',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-7403 a rest naming an unknown effort or an index beyond the entries is dropped',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(
        _snapshot(exercises: [_slot('sl-1', 'ex-bench')]),
      );
      await _phoneSet(repository, effortId: 'sl-1', entryIndex: 0);
      await _phoneRest(repository, effortId: 'sl-1', entryIndex: 1, endedAtMs: null);
      final before = await _restMaps(repository, 'sl-1');

      await phone.router.receive(
        observationsUp('s-w1', [
          _rest('rest-a1', 'entry-nope-0'),
        ], messageId: 'msg-7403a'),
      );
      await phone.router.receive(
        observationsUp('s-w1', [
          _rest('rest-a2', 'entry-sl-1-9'),
        ], messageId: 'msg-7403b'),
      );

      expect(
        await _restMaps(repository, 'sl-1'),
        before,
        reason: 'S-7403 neither delivery wrote anything',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-7404 a finished phone rest stands', () async {
    final phone = await _phone(repository);
    await phone.router.receive(
      _snapshot(exercises: [_slot('sl-1', 'ex-bench')]),
    );
    await _phoneSet(repository, effortId: 'sl-1', entryIndex: 0);
    await _phoneRest(
      repository,
      effortId: 'sl-1',
      entryIndex: 1,
      endedAtMs: _msOf(_restEnd),
    );
    final before = await _restMaps(repository, 'sl-1');

    await phone.router.receive(
      observationsUp('s-w1', [
        _rest('rest-a1', 'entry-sl-1-0'),
      ], messageId: 'msg-7404'),
    );

    expect(
      await _restMaps(repository, 'sl-1'),
      before,
      reason: 'S-7404 D-216 the phone\'s own finished rest stands: the wrist\'s '
          'later report does not rewrite it',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-7405 a redelivered rest event writes nothing the second time', () async {
    final phone = await _phone(repository);
    await phone.router.receive(
      _snapshot(exercises: [_slot('sl-1', 'ex-bench')]),
    );
    await _phoneSet(repository, effortId: 'sl-1', entryIndex: 0);
    await _phoneRest(repository, effortId: 'sl-1', entryIndex: 1, endedAtMs: null);

    await phone.router.receive(
      observationsUp('s-w1', [
        _rest('rest-a1', 'entry-sl-1-0'),
      ], messageId: 'msg-7405a'),
    );
    final afterFirst = await _rests(repository, 'sl-1');
    expect(
      afterFirst.single.restEndMs,
      _msOf(_restEnd),
      reason: 'S-7405 the fixture: the first delivery closed the rest',
    );

    await phone.router.receive(
      observationsUp('s-w1', [
        _rest('rest-a1', 'entry-sl-1-0'),
      ], messageId: 'msg-7405b'),
    );

    final afterRedelivery = await _rests(repository, 'sl-1');
    expect(afterRedelivery, hasLength(afterFirst.length));
    for (var i = 0; i < afterRedelivery.length; i++) {
      expect(
        afterRedelivery[i].restStartMs,
        afterFirst[i].restStartMs,
        reason: 'S-7405 the redelivery wrote nothing',
      );
      expect(
        afterRedelivery[i].restEndMs,
        afterFirst[i].restEndMs,
        reason: 'S-7405 the redelivery wrote nothing',
      );
    }
    expect(phone.failures, isEmpty);
  });
}
