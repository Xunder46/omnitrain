// Plan 36c (routine start sync, PR 3), Phase P1 — D-1, D-2, D-3: a routine the
// wrist started opens on the phone as that routine.
//
// The wrist builds its slot ids from the phone's own template effort ids
// (`sx-<effortId>`), so the phone can INFER which of its routines the wrist
// started (D-1) with no wire field, link the adopted session to that routine
// (D-2), and give every `set` effort the routine's CURRENT planned set rows
// (D-3/D-4). A ladder no template covers adopts exactly as it did before (A5).
//
// Plan: `docs/plans/2026-10-15-36c-routine-adoption-plan/2026-10-15-36c-routine-adoption-plan.md`,
// Phase P1. Scenario mapping:
//   S-3640 adoption links the routine                    → `S-3640 ...`
//   S-3641 the planned rows are the template's           → `S-3641 ...`
//   S-3642 the phone's CURRENT template wins             → `S-3642 ...`
//   S-3643 an effort with no targets gets one default row → `S-3643 ...`
//   S-3644 an unmatched ladder adopts as today           → `S-3644 ...`
//   S-3645 the home tile reads the link                  → `S-3645 ...`
//   S-3646 the planned sets round-trip with 36a/36b      → `S-3646 ...`
//   S-3647 a redelivery and a later snapshot             → `S-3647 ...`
//   S-3648 a deleted routine adopts as today             → `S-3648 ...`
//   S-3649 the template's exercise is gone               → `S-3649 ...`
//   S-3653 a null set index is row 0, an explicit one wins → `S-3653 ...`
//   S-3653b the lowest target id wins                    → `S-3653b ...`
//   S-3654 a set-index gap                               → `S-3654 ...`
//
// Both stores run the same fixtures through the same phone: an adoption must
// produce the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository` (the plan's implementation-parity invariant). Plain
// `test()`: no widget is involved, and a Hive write inside a widget test's
// fake-async zone never drains. Every snapshot arrives through the real
// `LiveSessionMirrorState` behind the real `WatchIncomingRouter`, so the bridge
// reads the reconciler's own converged output and the wiring is part of what
// these tests prove.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
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
    show CaptureTransport, observationsUp, sortedObservations;

/// The phone's clock, pinned: every planned row an adoption writes carries the
/// same stamp.
final DateTime _phoneNow = DateTime.utc(2026, 10, 15, 9);

final SyncProtocolValidator _validator = loadProtocolValidator();

// ─── Fixture T (plan 36c) ───────────────────────────────────────────────────

const String _templateId = 'routine-push';
const String _segmentId = 'routine-push-seg';
const String _benchEffortId = 'eff-bench';
const String _plankEffortId = 'eff-plank';
const String _benchSlot = 'sx-eff-bench';
const String _plankSlot = 'sx-eff-plank';
const String _sessionId = 's-w1';
const int _seededAt = 1788000000000;

/// T's bench plan: `(setIndex, reps, weightKg)` per set.
const List<(int?, int, double)> _benchSets = [
  (0, 8, 40.0),
  (1, 8, 40.0),
  (2, 6, 42.5),
];

/// One ladder slot as the wrist sends it: its id, its exercise, its own
/// capabilities and the kind the wrist resolved for it.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId, {
  required String declaredKind,
  List<String> capabilities = const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ],
}) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': capabilities,
  'effortKind': declaredKind,
};

Map<String, Object?> _bench() =>
    _slot(_benchSlot, 'ex-bench', declaredKind: BlockTypes.set);

Map<String, Object?> _plank() => _slot(
  _plankSlot,
  'ex-plank',
  declaredKind: BlockTypes.timed,
  capabilities: const [ExerciseCapability.hold, ExerciseCapability.time],
);

/// One `session_snapshot` from the wrist, adopting [sessionId] onto the phone.
Map<String, Object?> _snapshot({
  String sessionId = _sessionId,
  int revision = 3,
  List<Map<String, Object?>>? exercises,
  String messageId = 'msg-snapshot',
}) {
  final ladder = exercises ?? [_bench(), _plank()];
  return {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': messageId,
    'sessionId': sessionId,
    'type': 'session_snapshot',
    'origin': 'watch',
    'sentAt': '2026-10-15T08:59:00Z',
    'payload': {
      'sessionId': sessionId,
      'revision': revision,
      'status': WatchSessionStatus.active,
      'currentExerciseIndex': 0,
      'exercises': [...ladder],
      'entries': <Object?>[],
      'timers': <String, Object?>{},
    },
  };
}

// ─── The phone ──────────────────────────────────────────────────────────────

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

/// One phone, wired the way `createWatchSync` wires it: the adoption bridge,
/// the inbox that asks it whether a session is the phone's own, the mirror
/// behind the entry-staging transport, and the router that drives them.
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

  /// What the graph reported as a failure: nothing, in these scenarios.
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

// ─── The fixture's rows ─────────────────────────────────────────────────────

/// A phone holding fixture T, its catalog, or neither, on the Mock store.
Future<WorkoutRepository> _openMock({
  bool withTemplate = true,
  List<(int?, int, double)> benchSets = _benchSets,
  bool catalogBench = true,
}) async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seedCatalog(repository, withBench: catalogBench);
  if (withTemplate) {
    await _seedTemplate(repository, benchSets: benchSets);
  }
  return repository;
}

Directory? _hiveDir;

/// The same phone over Hive, in a temp directory: the store the app runs on.
Future<WorkoutRepository> _openHive({
  bool withTemplate = true,
  List<(int?, int, double)> benchSets = _benchSets,
  bool catalogBench = true,
}) async {
  final dir = await Directory.systemTemp.createTemp('watch_adoption_');
  _hiveDir = dir;
  _PathProviderChannel.install(dir);
  Hive.init(dir.path);
  final repository = HiveWorkoutRepository();
  await repository.initialize();
  await _seedCatalog(repository, withBench: catalogBench);
  if (withTemplate) {
    await _seedTemplate(repository, benchSets: benchSets);
  }
  return repository;
}

/// Closes Hive's boxes and removes the temp directory.
Future<void> _closeHive() async {
  await Hive.deleteFromDisk();
  final dir = _hiveDir;
  if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  _hiveDir = null;
}

/// The in-memory store owns nothing outside the process.
Future<void> _closeNoop() async {}

/// The catalog the fixture's slots name: a loaded bench and a bodyweight plank.
///
/// [withBench] is off in S-3649, which needs the template to still name a bench
/// the phone's library no longer holds.
Future<void> _seedCatalog(
  WorkoutRepository repository, {
  bool withBench = true,
}) async {
  if (withBench) {
    await _seedExercise(
      repository,
      id: 'ex-bench',
      name: 'Barbell Bench Press',
      capabilities: const [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
        ExerciseCapability.load,
      ],
    );
  }
  await _seedExercise(
    repository,
    id: 'ex-plank',
    name: 'Plank',
    capabilities: const [ExerciseCapability.hold, ExerciseCapability.time],
  );
}

/// One catalog exercise with its capabilities, the way the app stores them.
Future<void> _seedExercise(
  WorkoutRepository repository, {
  required String id,
  required String name,
  required List<String> capabilities,
}) async {
  await repository.createExercise(
    Exercise(
      id: id,
      name: name,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    ),
  );
  await repository.setExerciseCapabilities(id, capabilities);
}

/// Fixture T: template "Push A", one segment, a `set` bench effort with
/// [benchSets] as its plan, and a `timed` plank effort with no targets.
Future<void> _seedTemplate(
  WorkoutRepository repository, {
  List<(int?, int, double)> benchSets = _benchSets,
}) async {
  await repository.createTemplate(
    WorkoutTemplate(
      id: _templateId,
      ownerUserId: null,
      name: 'Push A',
      description: null,
      focusModality: null,
      primaryDisciplineId: null,
      note: null,
      isBuiltInDemo: false,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: _segmentId,
      templateId: _templateId,
      orderIndex: 0,
      segmentType: 'strength_sets',
      disciplineId: null,
      name: 'Main',
      note: null,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: _benchEffortId,
      templateSegmentId: _segmentId,
      orderIndex: 0,
      effortKind: BlockTypes.set,
      modality: null,
      exerciseId: 'ex-bench',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _seededAt,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: _plankEffortId,
      templateSegmentId: _segmentId,
      orderIndex: 1,
      effortKind: BlockTypes.timed,
      modality: null,
      exerciseId: 'ex-plank',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _seededAt,
    ),
  );
  await _addBenchTargets(repository, benchSets);
}

/// The bench effort's plan: one reps target and one weight target per set.
Future<void> _addBenchTargets(
  WorkoutRepository repository,
  List<(int?, int, double)> benchSets,
) async {
  for (final (setIndex, reps, weightKg) in benchSets) {
    await repository.createTemplateTarget(
      TemplateTarget(
        id: 'tgt-bench-${setIndex ?? 'none'}-reps',
        templateEffortId: _benchEffortId,
        metricId: MetricIds.reps,
        setIndex: setIndex,
        targetInt: reps,
        createdAtMs: _seededAt,
        updatedAtMs: _seededAt,
      ),
    );
    await repository.createTemplateTarget(
      TemplateTarget(
        id: 'tgt-bench-${setIndex ?? 'none'}-weight',
        templateEffortId: _benchEffortId,
        metricId: MetricIds.weight,
        setIndex: setIndex,
        targetMin: weightKg,
        createdAtMs: _seededAt,
        updatedAtMs: _seededAt,
      ),
    );
  }
}

/// Edits the routine the phone holds, the way its own routine editor would:
/// the bench plan becomes [benchSets] and nothing of the old one is left.
Future<void> _replanBench(
  WorkoutRepository repository,
  List<(int?, int, double)> benchSets,
) async {
  await repository.deleteTemplateTargetsForEffort(_benchEffortId);
  await _addBenchTargets(repository, benchSets);
}

/// Adds an effort to the routine the wrist's ladder does not have (S-3642).
Future<void> _addTemplateEffort(
  WorkoutRepository repository, {
  required String id,
  required int orderIndex,
}) async {
  await repository.createTemplateEffort(
    TemplateEffort(
      id: id,
      templateSegmentId: _segmentId,
      orderIndex: orderIndex,
      effortKind: BlockTypes.set,
      modality: null,
      exerciseId: 'ex-row',
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _seededAt,
    ),
  );
}

/// The adopted session's efforts, in ladder order.
Future<List<SegmentEffort>> _efforts(WorkoutRepository repository) async {
  final segments = await repository.getSessionSegments(_sessionId);
  if (segments.isEmpty) return const [];
  return repository.getSegmentEfforts(segments.single.id);
}

/// One effort's set entries as `(number, reps, weightKg)`, in entry order.
Future<List<(int, int, double)>> _sets(
  WorkoutRepository repository,
  String effortId,
) async => [
  for (final group in EntryRows.setGroups(
    await repository.getEffortObservations(effortId),
  ))
    (
      group.number,
      (group.entry['reps'] as int?) ?? 0,
      (group.entry['weight'] as double?) ?? 0.0,
    ),
];

/// The today-behaviour assertions A5 describes: the session is adopted, and
/// nothing links it to a routine and gives it no planned rows.
Future<void> _expectFreeAdoption(
  WorkoutRepository repository, {
  List<String> slots = const [_benchSlot, _plankSlot],
}) async {
  final session = await repository.getSession(_sessionId);
  expect(session, isNotNull, reason: 'A5 the session is still adopted');
  expect(session!.title, isNull, reason: 'A5 no routine title');
  expect(session.intent, isNull, reason: 'A5 no routine intent');
  expect(
    session.routineTemplateId,
    isNull,
    reason: 'A5 nothing links the session to a routine',
  );
  expect(
    [for (final effort in await _efforts(repository)) effort.id],
    slots,
    reason: 'A5 the wrist\'s ladder is adopted as it always was',
  );
  for (final slot in slots) {
    expect(
      await repository.getEffortObservations(slot),
      isEmpty,
      reason: 'A5 no planned row is written',
    );
  }
}

/// The stamp the phone's own rows carry: the adoption happened at `_phoneNow`.
final int _plannedStampMs = _phoneNow.millisecondsSinceEpoch;

/// A set the wrist logged, naming the slot it belongs to (36a's event shape).
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

/// When the wrist logged the set S-3646 fills a planned row with — after the
/// adoption, so the fill is visibly the wrist's own write.
const String _fillStamp = '2026-10-15T09:05:00Z';
final int _fillStampMs = DateTime.parse(
  _fillStamp,
).toUtc().millisecondsSinceEpoch;

void main() {
  group('Mock', () => _adoptionTests(open: _openMock, close: _closeNoop));
  group('Hive', () => _adoptionTests(open: _openHive, close: _closeHive));
}

/// The same scenarios over whichever store `open` hands back: every assertion
/// holds for both, or the parity invariant is broken.
void _adoptionTests({
  required Future<WorkoutRepository> Function({
    bool withTemplate,
    List<(int?, int, double)> benchSets,
    bool catalogBench,
  })
  open,
  required Future<void> Function() close,
}) {
  tearDown(close);

  test('S-3640 the snapshot adopts as the routine the wrist started', () async {
    final repository = await open();
    final phone = await _phone(repository);

    await phone.router.receive(_snapshot());

    final session = await repository.getSession(_sessionId);
    expect(session, isNotNull);
    expect(
      session!.routineTemplateId,
      _templateId,
      reason: 'D-2 the adopted session names the routine the wrist started',
    );
    expect(session.title, 'Push A', reason: 'D-2 the template\'s own name');
    expect(
      session.intent,
      'routine',
      reason: 'D-2 the home tile\'s rule reads exactly this',
    );
    expect(
      session.modality,
      isNull,
      reason: 'A1 a routine session carries no modality',
    );
    expect(
      [for (final effort in await _efforts(repository)) effort.id],
      [_benchSlot, _plankSlot],
      reason:
          'A3 the wrist\'s ladder stays the authority: slot ids and order are '
          'what the template matched, not what it would have built',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-3641 the adopted effort holds the template\'s planned sets',
    () async {
      final repository = await open();
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(
        await _sets(repository, _benchSlot),
        [(0, 8, 40.0), (1, 8, 40.0), (2, 6, 42.5)],
        reason:
            'D-3/D-4 one row per planned set, read from the phone\'s CURRENT '
            'template targets',
      );
      expect(
        [
          for (final row in await repository.getEffortObservations(_benchSlot))
            row.id,
        ]..sort(),
        [
          'obs-$_benchSlot-0-reps',
          'obs-$_benchSlot-0-weight',
          'obs-$_benchSlot-1-reps',
          'obs-$_benchSlot-1-weight',
          'obs-$_benchSlot-2-reps',
          'obs-$_benchSlot-2-weight',
        ],
        reason:
            'I-6 the rows are the ones the phone\'s own add writes: same id '
            'pattern, reps and weight only for a loaded exercise',
      );
      expect(
        await repository.getEntryRests(_benchSlot),
        isEmpty,
        reason: 'A2 the planned rows are not logged sets: no rest follows one',
      );
      expect(
        await repository.getEffortObservations(_plankSlot),
        isEmpty,
        reason: 'A4 a timed effort of the same routine gets no planned rows',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-3643 an effort with no targets gets one default row', () async {
    final repository = await open();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot(
            _plankSlot,
            'ex-plank',
            declaredKind: BlockTypes.set,
            capabilities: const [
              ExerciseCapability.sets,
              ExerciseCapability.reps,
            ],
          ),
        ],
      ),
    );

    expect(
      await _sets(repository, _plankSlot),
      [(0, 10, 0.0)],
      reason:
          'D-3 an effort with no targets is one set, and its row carries the '
          'phone\'s own defaults',
    );
  });

  test(
    'S-3644a no template covers the ladder: a free session as today',
    () async {
      final repository = await open(withTemplate: false);
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(await repository.getTemplates(), isEmpty);
      await _expectFreeAdoption(repository);
    },
  );

  test('S-3644b slot ids the template does not hold: a free session', () async {
    final repository = await open();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(
        exercises: [
          _slot('sx-ex-bench', 'ex-bench', declaredKind: BlockTypes.set),
          _slot(
            'sx-ex-plank',
            'ex-plank',
            declaredKind: BlockTypes.timed,
            capabilities: const [
              ExerciseCapability.hold,
              ExerciseCapability.time,
            ],
          ),
        ],
      ),
    );

    await _expectFreeAdoption(
      repository,
      slots: const ['sx-ex-bench', 'sx-ex-plank'],
    );
  });

  test('S-3644c a mixed ladder: a free session as today', () async {
    final repository = await open();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(
        exercises: [
          _bench(),
          _slot('sx-ex-extra', 'ex-extra', declaredKind: BlockTypes.set),
        ],
      ),
    );

    await _expectFreeAdoption(
      repository,
      slots: const [_benchSlot, 'sx-ex-extra'],
    );
    expect(
      await repository.getEffortObservations(_benchSlot),
      isEmpty,
      reason:
          'I-3 one slot outside the template means no match at all: not even '
          'the slot the template does hold gets rows',
    );
  });

  test(
    'S-3648 a routine deleted before the snapshot: a free session',
    () async {
      final repository = await open();
      await repository.deleteTemplate(_templateId);
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(await repository.getTemplates(), isEmpty);
      await _expectFreeAdoption(repository);
    },
  );

  test('S-3642 the phone\'s current routine is the source of truth', () async {
    final repository = await open();
    // The routine moves on between the wrist's start and the adoption: set 2
    // becomes 5 reps at 45 kg, and a third effort joins it.
    await _replanBench(repository, [(0, 8, 40.0), (1, 8, 40.0), (2, 5, 45.0)]);
    await _addTemplateEffort(repository, id: 'eff-row', orderIndex: 2);
    final phone = await _phone(repository);

    await phone.router.receive(_snapshot());

    final session = await repository.getSession(_sessionId);
    expect(
      session!.routineTemplateId,
      _templateId,
      reason:
          'D-1 the ladder still covers the routine (an extra effort is '
          'not a mismatch)',
    );
    expect(session.title, 'Push A');
    expect(
      await _sets(repository, _benchSlot),
      [(0, 8, 40.0), (1, 8, 40.0), (2, 5, 45.0)],
      reason:
          'I-2 the rows are the phone\'s CURRENT targets: 5 and 45.0, not the '
          '6 and 42.5 the wrist started with',
    );
    expect(
      [for (final effort in await _efforts(repository)) effort.id],
      [_benchSlot, _plankSlot],
      reason:
          'A3 the effort the wrist never saw is not added: the ladder is the '
          'wrist\'s, the values are the phone\'s',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-3645 the adopted session reads as the routine\'s, and is active',
    () async {
      final repository = await open();
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      final held = phone.state.currentSession;
      expect(held, isNotNull);
      expect(
        held!.intent,
        'routine',
        reason: 'the Routines tile\'s rule reads exactly this intent',
      );
      expect(held.routineTemplateId, _templateId);
      expect(
        phone.state.hasActiveSession,
        isTrue,
        reason:
            'the tile needs a session in progress too: the same two facts '
            'a phone-started routine shows',
      );
    },
  );

  test(
    'S-3646 the planned sets round-trip, and a wrist set fills one',
    () async {
      final repository = await open();
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      final projection = await phone.bridge.projectSession(null);
      expect(projection, isNotNull);
      final slots = [
        for (final slot in projection!['exercises']! as List)
          (slot! as Map).cast<String, Object?>(),
      ];
      final bench = slots.singleWhere(
        (slot) => slot['sessionExerciseId'] == _benchSlot,
      );
      expect(
        bench['plannedSets'],
        [
          {'reps': 8, 'loadKg': 40.0},
          {'reps': 8, 'loadKg': 40.0},
          {'reps': 6, 'loadKg': 42.5},
        ],
        reason: 'D-2 the wrist dials each set from the plan the phone adopted',
      );
      expect(
        projection['entries'],
        isEmpty,
        reason: 'A2 a planned row is not a logged entry: neither rides back',
      );

      await phone.router.receive(
        observationsUp('s-w1', [
          _set(
            'sx-set-1',
            slot: _benchSlot,
            exerciseId: 'ex-bench',
            reps: 9,
            loadKg: 41,
            loggedAt: _fillStamp,
          ),
        ], messageId: 'msg-fill-1'),
      );

      expect(
        await _sets(repository, _benchSlot),
        [(0, 9, 41.0), (1, 8, 40.0), (2, 6, 42.5)],
        reason:
            'D-6 the wrist\'s set fills planned row 0 — three rows, not four — '
            'and the planned rows behind it stand',
      );
      final rows = await sortedObservations(repository, _benchSlot);
      expect(rows, hasLength(6));
      expect(rows[0].valueInt, 9);
      expect(rows[0].createdAtMs, _fillStampMs);
      expect(rows[1].valueReal, 41.0);
      expect(
        rows[2].valueInt,
        8,
        reason: 'the untouched planned row still holds the template\'s 8',
      );
      expect(rows[2].createdAtMs, _plannedStampMs);
      final rests = await repository.getEntryRests(_benchSlot);
      expect(
        [for (final rest in rests) rest.toMap()],
        [
          {
            'id': 'rest-$_benchSlot-1',
            'effort_id': _benchSlot,
            'entry_index': 1,
            'rest_start_ms': _fillStampMs,
            'rest_end_ms': null,
            'rest_is_paused': 0,
            'rest_paused_at_ms': null,
            'rest_paused_duration_ms': 0,
            'created_at_ms': _fillStampMs,
            'updated_at_ms': _fillStampMs,
          },
        ],
        reason:
            'D-6 an open rest at the filled row + 1, run from the wrist\'s log '
            'time — so the phone reads the row as logged at once',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-3647 a redelivery and a later snapshot change nothing', () async {
    final repository = await open();
    final phone = await _phone(repository);

    await phone.router.receive(_snapshot());
    await phone.router.receive(_snapshot());
    await phone.router.receive(
      _snapshot(revision: 4, messageId: 'msg-snapshot-2'),
    );

    expect(
      await repository.getAllSessions(),
      hasLength(1),
      reason: 'I-4 the same session is adopted once',
    );
    expect(
      [for (final effort in await _efforts(repository)) effort.id],
      [_benchSlot, _plankSlot],
      reason: 'I-4 no second effort per slot',
    );
    expect(
      await _sets(repository, _benchSlot),
      [(0, 8, 40.0), (1, 8, 40.0), (2, 6, 42.5)],
      reason: 'I-4 the planned rows are written once',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-3649 the routine\'s exercise is gone: the phone\'s own fallback rows',
    () async {
      final repository = await open(catalogBench: false);
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      // `sortedObservations` sorts by id, which puts `-extra-weight` before
      // `-reps`, so the expectation is built in that order too.
      final expectedIds = [
        for (var index = 0; index < 3; index++) ...[
          'obs-$_benchSlot-$index-extra-weight',
          'obs-$_benchSlot-$index-reps',
          'obs-$_benchSlot-$index-weight',
        ],
      ];
      expect(
        [
          for (final row in await sortedObservations(repository, _benchSlot))
            row.id,
        ],
        expectedIds,
        reason:
            'S-3649 an unknown exercise carries no load, so each set gets the '
            'extra-weight row the phone\'s own add writes for one',
      );
      expect(
        await _sets(repository, _benchSlot),
        [(0, 8, 40.0), (1, 8, 40.0), (2, 6, 42.5)],
        reason: 'S-3649 the plan is still the template\'s',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test(
    'S-3653 a null set index is row 0, and an explicit index beats it',
    () async {
      final repository = await open();
      // Two reps targets and two weight targets both mean set 1 — one with a
      // null index, one with 0 — and the explicit index is the more specific
      // of the two, so row 0 carries it whatever order the store lists them
      // in.
      await _replanBench(repository, [(null, 12, 30.0), (0, 7, 20.0)]);
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(
        await _sets(repository, _benchSlot),
        [(0, 7, 20.0)],
        reason:
            'S-3653 `setIndex ?? 0` puts both on row 0, the explicit target '
            'wins there, and the highest index + 1 still counts one set',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test(
    'S-3653c an explicit index beats a null one whatever the ids sort to',
    () async {
      final repository = await open();
      // The null-index target's id sorts BEFORE the explicit one's, so only
      // the specificity rule can put the explicit target on row 0: the id
      // tie-break alone would pick the null one.
      await repository.deleteTemplateTargetsForEffort(_benchEffortId);
      for (final (id, setIndex, reps, weightKg)
          in <(String, int?, int, double)>[
            ('a-null', null, 12, 30.0),
            ('z-zero', 0, 7, 20.0),
          ]) {
        await repository.createTemplateTarget(
          TemplateTarget(
            id: '$id-reps',
            templateEffortId: _benchEffortId,
            metricId: MetricIds.reps,
            setIndex: setIndex,
            targetInt: reps,
            createdAtMs: _seededAt,
            updatedAtMs: _seededAt,
          ),
        );
        await repository.createTemplateTarget(
          TemplateTarget(
            id: '$id-weight',
            templateEffortId: _benchEffortId,
            metricId: MetricIds.weight,
            setIndex: setIndex,
            targetMin: weightKg,
            createdAtMs: _seededAt,
            updatedAtMs: _seededAt,
          ),
        );
      }
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(
        await _sets(repository, _benchSlot),
        [(0, 7, 20.0)],
        reason:
            'S-3653c the explicit set index 0 is the more specific target, '
            'so it wins over the null-index one with the lower id',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-3653b the lowest id wins between two targets of one set', () async {
    final repository = await open();
    // Two explicit 0-index reps targets, `b-target` created first so the
    // store lists it first: the pick ignores that order and the lowest id
    // wins.
    TemplateTarget zeroIndex(String id, int reps) => TemplateTarget(
      id: id,
      templateEffortId: _benchEffortId,
      metricId: MetricIds.reps,
      setIndex: 0,
      targetInt: reps,
      createdAtMs: _seededAt,
      updatedAtMs: _seededAt,
    );
    await repository.deleteTemplateTargetsForEffort(_benchEffortId);
    await repository.createTemplateTarget(zeroIndex('b-target', 12));
    await repository.createTemplateTarget(zeroIndex('a-target', 7));
    final phone = await _phone(repository);

    await phone.router.receive(_snapshot());

    expect(
      await _sets(repository, _benchSlot),
      [(0, 7, 0.0)],
      reason:
          'S-3653b `a-target` is the lower id of the two, and the template '
          'plans no weight, so row 0 keeps the phone\'s own default load',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-3654 a set-index gap leaves the middle row at the defaults',
    () async {
      final repository = await open();
      await _replanBench(repository, [(0, 8, 40.0), (2, 7, 50.0)]);
      final phone = await _phone(repository);

      await phone.router.receive(_snapshot());

      expect(
        await _sets(repository, _benchSlot),
        [(0, 8, 40.0), (1, 10, 0.0), (2, 7, 50.0)],
        reason:
            'S-3654 the count is the highest index + 1, and a row the template '
            'has no target for carries the phone\'s own defaults',
      );
      expect(phone.failures, isEmpty);
    },
  );
}
