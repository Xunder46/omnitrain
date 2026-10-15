// The real transport: one radio, two ends, and what each end does with a frame.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phase 1 (D-1) and Phase 2 (D-2).
// Scenario mapping:
//   S-001 phone → watch delivery              → `S-001 ...`
//   S-002 watch → phone delivery              → `S-002 ...`
//   S-003 the phone answers a routine request → `S-003 ...`
//   S-006 the transport is chosen by platform → `S-006 ...`
//   S-102 the request frames match the contract → `S-102 ...`
//   Phase 2 item 6: phone fixtures carry no null → `Phase 2 item 6: ...`
//   S-253 every sync is answered with preferences → `S-253 ...`
//         (Stats PR 2, `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//         D-113, D-115)
//
// The loopback below is a channel, not a transport: it carries frames in memory
// in the order they were sent, which is the one property a fake can hold a real
// implementation to. Everything above it — the frame vocabulary, both ends'
// dispatch, and the graph `createWatchSync` builds — is the shipping code.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/no_watch_transport.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/platform_watch_transport_factory.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/nutrition/watch_nutrition_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/fake_preferences_service.dart';

final DateTime _now = DateTime.utc(2026, 9, 21, 12);

/// One food the phone's library holds, and the group it sits in — enough for the
/// wrist to quick-log it and for the phone to place the row.
final FoodGroup _group = FoodGroup(
  id: 'group-breakfast',
  name: 'Breakfast',
  createdAtMs: _now.millisecondsSinceEpoch,
  updatedAtMs: _now.millisecondsSinceEpoch,
);

final Food _food = Food(
  id: 'food-oatmeal',
  name: 'Oatmeal',
  groupId: _group.id,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  protein: 5,
  carbs: 30,
  fat: 3,
  createdAtMs: _now.millisecondsSinceEpoch,
  updatedAtMs: _now.millisecondsSinceEpoch,
);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
};

/// The shared protocol fixtures and schemas, read from the repository rather
/// than restated here.
const String _protocolRoot = 'watch/sync_protocol';

Map<String, Object?> _readJson(String relativePath) => _asObject(
  jsonDecode(
    File('${Directory.current.path}/$relativePath').readAsStringSync(),
  ),
);

/// The values both watch clients must agree on.
Map<String, Object?> _contract() =>
    _readJson('watch/contract/watch_start_paths_contract.json');

/// The instant a later sync's `since` is pinned to in the contract.
final DateTime _syncedAt = DateTime.utc(2026, 7, 13, 17);

/// Every path in [value] that holds a JSON null, as `a.b[0].c`.
List<String> _nullPaths(Object? value, [String path = '']) {
  if (value == null) return [path.isEmpty ? '<root>' : path];
  if (value is List) {
    return [
      for (var index = 0; index < value.length; index++)
        ..._nullPaths(value[index], '$path[$index]'),
    ];
  }
  if (value is Map) {
    return [
      for (final entry in value.entries)
        ..._nullPaths(entry.value, path.isEmpty ? '${entry.key}' : '$path.${entry.key}'),
    ];
  }
  return const [];
}

/// One end of a two-ended in-memory link. What this end sends appears on the
/// other end's stream, once, in order.
class _Endpoint implements WatchMessageChannel {
  _Endpoint({required this.outbound, required this.inbound});

  final StreamController<Map<String, Object?>> outbound;
  final Stream<Map<String, Object?>> inbound;

  /// Everything this end handed to the radio, in order.
  final List<Map<String, Object?>> sent = [];

  bool reachable = true;

  /// A send the radio refuses, so the refusal path can be exercised.
  /// Null means every send is taken.
  Object? sendFailure;

  @override
  Future<bool> get isPaired async => true;

  @override
  Future<bool> get isReachable async => reachable;

  @override
  Stream<Map<String, Object?>> get messages => inbound;

  @override
  Future<void> send(Map<String, Object?> frame) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    sent.add(frame);
    outbound.add(frame);
  }
}

/// Two channels wired to each other: the phone's and the wrist's.
class _Link {
  _Link() {
    phone = _Endpoint(outbound: _toWatch, inbound: _toPhone.stream);
    watch = _Endpoint(outbound: _toPhone, inbound: _toWatch.stream);
  }

  final StreamController<Map<String, Object?>> _toPhone =
      StreamController<Map<String, Object?>>.broadcast();
  final StreamController<Map<String, Object?>> _toWatch =
      StreamController<Map<String, Object?>>.broadcast();

  late final _Endpoint phone;
  late final _Endpoint watch;

  Future<void> close() async {
    await _toPhone.close();
    await _toWatch.close();
  }
}

/// Lets the link's broadcast streams deliver everything already queued.
Future<void> _settle() => pumpEventQueue();

/// A routine with one segment and one exercise, as a phone would hold one.
Future<void> _seedRoutine(
  MockWorkoutRepository repository, {
  required String templateId,
  required String name,
  required String exerciseId,
  required String effortKind,
}) async {
  await repository.createTemplate(
    WorkoutTemplate(
      id: templateId,
      ownerUserId: null,
      name: name,
      description: null,
      focusModality: null,
      primaryDisciplineId: null,
      note: null,
      isBuiltInDemo: false,
      createdAtMs: _now.millisecondsSinceEpoch,
      updatedAtMs: _now.millisecondsSinceEpoch,
    ),
  );
  await repository.createTemplateSegment(
    TemplateSegment(
      id: '$templateId-seg',
      templateId: templateId,
      orderIndex: 0,
      segmentType: 'strength_sets',
      disciplineId: null,
      name: 'Main',
      note: null,
      createdAtMs: _now.millisecondsSinceEpoch,
      updatedAtMs: _now.millisecondsSinceEpoch,
    ),
  );
  await repository.createTemplateEffort(
    TemplateEffort(
      id: '$templateId-eff',
      templateSegmentId: '$templateId-seg',
      orderIndex: 0,
      effortKind: effortKind,
      modality: null,
      exerciseId: exerciseId,
      note: null,
      restSeconds: null,
      restType: null,
      createdAtMs: _now.millisecondsSinceEpoch,
    ),
  );
}

void main() {
  late _Link link;
  late MockWorkoutRepository repository;
  late WatchSessionEngine engine;
  late WatchSessionStartPaths paths;
  late WatchSyncOrchestrator orchestrator;
  late WatchTransport watchTransport;
  late WatchTransport phoneTransport;
  late LiveSessionMirrorState? phoneMirror;
  late NutritionState phoneNutrition;
  late FoodLibraryState phoneLibrary;
  late SettingsState phoneSettings;
  late DateTime phoneNow;
  late InMemoryWatchSessionStore watchStore;
  late Object? reportedFailure;
  late int reportedFailureCount;

  void reportFailure(Object error, StackTrace stack) {
    reportedFailure = error;
    reportedFailureCount++;
  }

  /// The wrist: its real engine over an in-memory store, fed by the real
  /// transport, dispatched the way the watch app dispatches.
  Future<WatchLoggingState> startWatchSession(
    List<Map<String, Object?>> exercises,
  ) async {
    await engine.createSession(modality: null, exercises: exercises);
    return WatchLoggingState(engine: engine, clock: () => _now);
  }

  setUp(() async {
    link = _Link();
    reportedFailure = null;
    reportedFailureCount = 0;
    repository = MockWorkoutRepository();
    await repository.initialize();

    watchTransport = WatchConnectivityTransport(
      channel: link.watch,
      onFailure: reportFailure,
    );
    phoneTransport = WatchConnectivityTransport(
      channel: link.phone,
      onFailure: reportFailure,
    );

    watchStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      watchStore,
      clock: () => _now,
      onEmit: watchTransport.send,
    );
    paths = WatchSessionStartPaths(
      engine: engine,
      store: InMemoryWatchSessionStore(),
    );
    orchestrator = WatchSyncOrchestrator(
      transport: watchTransport,
      paths: paths,
      engine: engine,
    );
    watchTransport.onIncoming((frame) async {
      if (WatchTransportRequest.nameOf(frame) != null) {
        await orchestrator.answerSnapshotRequest();
        return;
      }
      await orchestrator.receive(frame);
    });

    // The phone's graph, exactly as production builds it, over the link. The
    // library is loaded from storage before the graph is built, because that is
    // what the bridge looks a quick-logged food up in.
    await repository.createFoodGroup(_group);
    await repository.createFood(_food);
    phoneLibrary = FoodLibraryState(repository);
    await phoneLibrary.loadFoods();
    await phoneLibrary.loadFoodGroups();
    phoneNutrition = NutritionState(repository);
    await phoneNutrition.loadConsumedToday();
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();
    phoneNow = _now;

    phoneMirror = (await createWatchSync(
      repository: repository,
      nutritionState: phoneNutrition,
      foodLibraryState: phoneLibrary,
      settingsState: phoneSettings,
      transport: phoneTransport,
      clock: () => phoneNow,
      onFailure: reportFailure,
    ))?.mirror;
  });

  tearDown(() async {
    await (watchTransport as WatchConnectivityTransport).close();
    await (phoneTransport as WatchConnectivityTransport).close();
    await link.close();
  });

  group('S-001 a message crosses the radio phone → watch', () {
    test('S-001 the phone pushes an exercise into the wrist\'s session',
        () async {
      await startWatchSession([_slot('sx-bench', ['sets', 'reps', 'load'])]);

      // The wrist reports its session; the phone joins it. Nothing else could
      // come first — the phone cannot manage a ladder it has never seen.
      await watchTransport.send(engine.sessionSnapshot()!);
      await _settle();
      expect(phoneMirror!.exercises, hasLength(1));
      expect(phoneMirror!.sessionId, engine.session!.sessionId);

      await phoneMirror!.pushExercise(_slot('sx-pushed', ['time']),
          atIndex: 0);
      await _settle();

      expect(phoneMirror!.exercises, hasLength(2));
      expect(engine.session!.exercises, hasLength(2));
      expect(engine.session!.exercises.first['sessionExerciseId'], 'sx-pushed');
      expect(reportedFailure, isNull);
    });

    test('S-001 a re-delivered message changes nothing', () async {
      await startWatchSession([_slot('sx-bench', ['sets', 'reps', 'load'])]);
      await watchTransport.send(engine.sessionSnapshot()!);
      await _settle();

      final frame = phoneMirror!.snapshotEnvelope(messageId: 'msg-once');
      await watchTransport.send(frame);
      await _settle();
      final revision = engine.session!.revision;

      await watchTransport.send(frame);
      await _settle();

      expect(engine.session!.revision, revision);
      expect(engine.session!.exercises, hasLength(1));
      expect(reportedFailure, isNull);
    });
  });

  group('S-002 a message crosses the radio watch → phone', () {
    test('S-002 a set logged on the wrist reaches the phone once', () async {
      final surface = await startWatchSession([
        _slot('sx-bench', ['sets', 'reps', 'load']),
      ]);
      await phoneMirror!.receive(engine.sessionSnapshot()!);
      await _settle();

      surface.adjust(WatchMetricKey.reps, 2);
      await surface.log();
      await _settle();

      final entries = phoneMirror!.entries;
      expect(entries, hasLength(1));
      expect(entries.single['reps'], 12);

      // The same observation again: the protocol's delivery key makes it a
      // no-op, and the phone is where that is decided.
      final owed = engine.pendingObservations();
      expect(owed, isNotEmpty);
      await watchTransport.send(owed.last);
      await _settle();

      expect(phoneMirror!.entries, hasLength(1));
      expect(reportedFailure, isNull);
    });

    test('S-002 a frame the radio refuses is reported, not thrown', () async {
      link.watch.sendFailure = StateError('no route to phone');

      await watchTransport.send({'protocolVersion': 1});

      expect(reportedFailure, isA<StateError>());
    });

    test('S-002 a food quick-logged on the wrist lands in the phone\'s day log',
        () async {
      final nutrition = WatchNutritionState(
        engine: engine,
        store: watchStore,
        clock: () => _now,
      );
      await nutrition.restore();
      // The wrist only quick-logs from a list the phone sent it.
      await nutrition.applyFoodsDown(
        WatchReferenceSync.buildFoodsDown(
          foods: [_food],
          groups: [_group],
          generatedAt: _now,
        ),
      );

      nutrition.select(_food.id);
      await nutrition.logSelected();
      await _settle();

      // The wrist emitted it (`onEmit` is the real transport) and the phone's
      // own day log is where it has to appear — not in a stand-in. The seed
      // data already logs a food for today, so this asks that the wrist's food
      // is among them rather than that it is the only one.
      final logged = phoneNutrition.consumedToday;
      expect(logged.map((row) => row.sourceFoodId), contains(_food.id));
      expect(
        logged.firstWhere((row) => row.sourceFoodId == _food.id).name,
        _food.name,
        reason: 'the phone froze its own copy of the food onto the row',
      );
      expect(reportedFailure, isNull);
    });

    test('S-002 the phone\'s receipt comes back over the same radio', () async {
      final nutrition = WatchNutritionState(
        engine: engine,
        store: watchStore,
        clock: () => _now,
      );
      await nutrition.restore();
      await nutrition.applyFoodsDown(
        WatchReferenceSync.buildFoodsDown(
          foods: [_food],
          groups: [_group],
          generatedAt: _now,
        ),
      );

      nutrition.select(_food.id);
      final record = await nutrition.logSelected();
      await _settle();

      // The bridge answers on its own transport, so the receipt is a frame on
      // the wire rather than a value a test handed back.
      expect(link.phone.sent, hasLength(1));
      final receipt = link.phone.sent.single;
      expect(receipt['type'], 'receipt');
      expect(_asObject(receipt['payload'])['entryIds'], [record.entryId]);
    });
  });

  group('S-003 the phone answers a request for routines', () {
    test('S-003 a seeded routine is built and sent when the wrist asks',
        () async {
      await _seedRoutine(
        repository,
        templateId: 'routine-push-a',
        name: 'Push A',
        exerciseId: 'exercise-goblet-squat',
        effortKind: 'set',
      );

      await watchTransport.requestRoutines();
      await _settle();

      expect(
        [for (final frame in link.phone.sent) frame['type']],
        ['preferences_down', 'routines_down'],
        reason: 'S-253 every sync is answered with preferences first',
      );
      final message = link.phone.sent.last;
      expect(message['type'], 'routines_down');
      final payload = _asObject(message['payload']);
      expect(_objects(payload['routines']).single['name'], 'Push A');
      expect(
        _objects(payload['fallbackExercises']).single['exerciseId'],
        'exercise-goblet-squat',
      );
    });

    test('S-003 a phone with no routines answers with its preferences only',
        () async {
      await watchTransport.requestRoutines();
      await _settle();

      expect(
        [for (final frame in link.phone.sent) frame['type']],
        ['preferences_down'],
        reason: 'S-253 no routines_down without routines, but the setting '
            'always travels',
      );
      expect(reportedFailure, isNull);
    });

    test('S-003 the wrist can ask the phone for its session', () async {
      await startWatchSession([_slot('sx-bench', ['sets', 'reps', 'load'])]);
      // Reports itself first: the phone cannot answer for a ladder it has never
      // seen, so the join has to happen before the question means anything.
      await watchTransport.send(engine.sessionSnapshot()!);
      await _settle();

      await watchTransport.requestSnapshot();
      await _settle();

      // The phone answered a `snapshot` request with its own session, rather
      // than the wrist answering its own question.
      expect(link.phone.sent, hasLength(1));
      final snapshot = link.phone.sent.single;
      expect(snapshot['type'], 'session_snapshot');
      expect(snapshot['origin'], 'phone');
      expect(_asObject(snapshot['payload'])['sessionId'],
          engine.session!.sessionId);
      expect(reportedFailure, isNull);
    });

    test('S-003 a phone with no ladder answers a snapshot request with silence',
        () async {
      await watchTransport.requestSnapshot();
      await _settle();

      expect(
        link.phone.sent,
        isEmpty,
        reason: 'an empty session is not a state, and sending one would '
            'replace the ladder the wrist is working through',
      );
      expect(reportedFailure, isNull);
    });
  });

  // D-113 and D-115: the setting reaches the wrist only when the wrist asks,
  // so every sync request carries it — before the routines, and even when the
  // phone has no routines to send. The value is SettingsState's own toggle.
  group('S-253 the phone answers every sync with its preferences', () {
    test('S-253 preferences alone, then preferences before routines',
        () async {
      await phoneSettings.setShowFeelingSurvey(false);

      await watchTransport.requestRoutines();
      await _settle();

      expect(
        [for (final frame in link.phone.sent) frame['type']],
        ['preferences_down'],
        reason: 'S-253 a phone with no routines still sends its preferences',
      );
      expect(
        _asObject(link.phone.sent.single['payload']),
        {'generatedAt': utcIso(_now), 'effortRatingPrompt': false, 'restPingSeconds': 0},
        reason: 'S-253 the setting as SettingsState holds it, stamped with '
            'the phone clock at send',
      );

      link.phone.sent.clear();
      await phoneSettings.setShowFeelingSurvey(true);
      await _seedRoutine(
        repository,
        templateId: 'routine-push-a',
        name: 'Push A',
        exerciseId: 'exercise-goblet-squat',
        effortKind: 'set',
      );
      phoneNow = _now.add(const Duration(minutes: 30));

      await watchTransport.requestRoutines();
      await _settle();

      expect(
        [for (final frame in link.phone.sent) frame['type']],
        ['preferences_down', 'routines_down'],
        reason: 'S-253 preferences first, then the routines',
      );
      expect(
        _asObject(link.phone.sent.first['payload']),
        {'generatedAt': utcIso(phoneNow), 'effortRatingPrompt': true, 'restPingSeconds': 0},
        reason: 'S-253 the setting turned on reaches the wrist at its next '
            'sync',
      );
      expect(reportedFailure, isNull);
    });
  });

  group('S-009 the phone removes the exercise the wrist is on', () {
    test('S-009 the wrist advances when the phone removes the current slot',
        () async {
      // Three slots, and the wrist is on the middle one — the position the
      // fixture singles out, because index 1 keeps existing after the removal
      // and now holds what followed.
      final surface = await startWatchSession([
        _slot('sx-bench', ['sets', 'reps', 'load']),
        _slot('sx-plank', ['time', 'hold']),
        _slot('sx-squat', ['sets', 'reps', 'load']),
      ]);
      await engine.advanceExercise();
      expect(engine.session!.currentExerciseIndex, 1);

      // Reports itself first, so the phone owns a ladder before it edits one —
      // and before it can make sense of anything logged against that ladder.
      await watchTransport.send(engine.sessionSnapshot()!);
      await _settle();
      expect(phoneMirror!.exercises, hasLength(3));

      // A set logged against the slot that is about to be removed: history is
      // what happened, and the removal must not take it with it.
      surface.adjust(WatchMetricKey.reps, 2);
      await surface.log();
      await _settle();
      expect(phoneMirror!.entries, hasLength(1));

      // The removal is the phone's to make, and it travels as a message rather
      // than as a fixture replayed into both engines.
      await phoneMirror!.removeExercise('sx-plank');
      await _settle();

      expect(
        engine.session!.exercises
            .map((slot) => slot['sessionExerciseId'])
            .toList(),
        ['sx-bench', 'sx-squat'],
      );
      expect(
        engine.session!.currentExerciseIndex,
        1,
        reason: 'a valid position: index 1 still exists, now holding the '
            'exercise that followed',
      );
      final stored = await watchStore.readAll();
      expect(
        stored.observations
            .where((row) => row.payload['sessionExerciseId'] == 'sx-plank'),
        isNotEmpty,
        reason: 'history keeps what was logged against the removed slot',
      );
      expect(reportedFailure, isNull);
    });
  });

  group('S-006 the transport is chosen by platform', () {
    test('S-006 iOS gets the real transport and other platforms get none',
        () async {
      final ios = await createPlatformWatchTransport(
        platform: TargetPlatform.iOS,
        channelFactory: () => link.phone,
      );
      expect(ios, isA<WatchConnectivityTransport>());

      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final none = await createPlatformWatchTransport(
          platform: platform,
          channelFactory: () => link.phone,
        );
        expect(none, isNull, reason: '$platform has no watch transport');
      }
    });

    test('S-006 a transport that cannot be built answers null', () async {
      final transport = await createPlatformWatchTransport(
        platform: TargetPlatform.iOS,
        channelFactory: () => throw StateError('plugin not registered'),
        onFailure: reportFailure,
      );

      expect(transport, isNull);
      expect(reportedFailure, isA<StateError>());
    });

    test('S-006 reachability comes from the channel', () async {
      final transport = WatchConnectivityTransport(channel: link.watch);
      addTearDown(transport.close);
      expect(transport.isPhoneReachable, isFalse);

      link.watch.reachable = true;
      await transport.refreshReachability();
      expect(transport.isPhoneReachable, isTrue);

      link.watch.reachable = false;
      await transport.refreshReachability();
      expect(transport.isPhoneReachable, isFalse);
    });

    test('S-006 the no-watch transport carries nothing and says so', () async {
      const transport = NoWatchTransport();
      var received = 0;

      transport.onIncoming((frame) async => received++);
      await transport.send({'protocolVersion': 1});
      await transport.requestRoutines();
      await transport.requestSnapshot();

      expect(transport.isPhoneReachable, isFalse);
      expect(received, 0);
    });

    test('S-006 the production graph is not built where no watch exists',
        () async {
      final none = await createWatchSync(
        repository: repository,
        nutritionState: NutritionState(repository),
        foodLibraryState: FoodLibraryState(repository),
        settingsState: phoneSettings,
        transport: const NoWatchTransport(),
      );
      expect(none, isNull);
    });
  });

  // D-190, D-196, D-201: a send answers whether the frame was handed over.
  group('S-206 a send answers whether the frame was handed over', () {
    test('S-206 a reachable counterpart means delivered, and the radio carried '
        'the frame', () async {
      final frame = WatchTransportRequest.snapshotFrame();

      final result = await phoneTransport.send(frame);

      expect(result, WatchDelivery.delivered);
      expect(link.phone.sent, [frame]);
      expect(reportedFailureCount, 0);
    });

    test('S-206 an unreachable counterpart is undelivered, unsent and '
        'unreported', () async {
      link.phone.reachable = false;
      final frame = WatchTransportRequest.snapshotFrame();

      final result = await phoneTransport.send(frame);

      expect(result, WatchDelivery.undelivered);
      expect(
        link.phone.sent,
        isEmpty,
        reason: 'the frame was never handed to the radio',
      );
      expect(
        reportedFailureCount,
        0,
        reason: 'a counterpart that is simply apart is quiet (D-201), not an '
            'error to report on every send',
      );
    });

    test('S-206 a send reads reachability again rather than trusting the last '
        'answer', () async {
      final frame = WatchTransportRequest.snapshotFrame();
      expect(await phoneTransport.send(frame), WatchDelivery.delivered);

      link.phone.reachable = false;

      expect(await phoneTransport.send(frame), WatchDelivery.undelivered);
      expect(
        link.phone.sent,
        [frame],
        reason: 'the hint the last send left behind is not an answer about '
            'this one (D-190)',
      );
      expect(reportedFailureCount, 0);
    });

    test('S-206 a radio that refuses the frame is undelivered and reported '
        'once', () async {
      link.phone.sendFailure = StateError('the radio refused the frame');
      final frame = WatchTransportRequest.snapshotFrame();

      final result = await phoneTransport.send(frame);

      expect(result, WatchDelivery.undelivered);
      expect(link.phone.sent, isEmpty);
      expect(reportedFailure, isA<StateError>());
      expect(reportedFailureCount, 1);
    });

    test('S-218 a transport that cannot carry a frame is undelivered and '
        'quiet', () async {
      const transport = NoWatchTransport();
      var received = 0;
      transport.onIncoming((frame) async => received++);

      final result = await transport.send(WatchTransportRequest.snapshotFrame());

      expect(result, WatchDelivery.undelivered);
      expect(
        reportedFailureCount,
        0,
        reason: 'no wrist means nothing to report, not an error per send',
      );
      expect(received, 0);
    });
  });

  group('S-102 the request frames match the contract', () {
    test('S-102 the three frames equal the contract transportRequests', () {
      final requests = _asObject(_contract()['transportRequests']);

      expect(
        WatchTransportRequest.routinesFrame(),
        _asObject(requests['routines']),
        reason: 'a first sync asks for everything, with no since key at all',
      );
      expect(
        WatchTransportRequest.routinesFrame(since: _syncedAt),
        _asObject(requests['routinesSince']),
        reason: 'a later sync says what the wrist already has',
      );
      expect(
        WatchTransportRequest.snapshotFrame(),
        _asObject(requests['snapshot']),
      );
    });

    test('S-102 a request frame carries no type key', () {
      final frames = [
        WatchTransportRequest.routinesFrame(),
        WatchTransportRequest.routinesFrame(since: _syncedAt),
        WatchTransportRequest.snapshotFrame(),
      ];

      for (final frame in frames) {
        expect(
          WatchTransportRequest.nameOf(frame),
          isNotNull,
          reason: 'a frame carrying type is a message, not a request',
        );
      }
    });

    test('S-102 a first sync omits since rather than nulling it', () {
      expect(
        WatchTransportRequest.routinesFrame().containsKey('since'),
        isFalse,
        reason: 'a null would make the phone\'s send fail',
      );
    });
  });

  group('Phase 2 item 6: phone fixtures carry no null', () {
    for (final name in [
      'routines_down',
      'preferences_down',
      'exercise_push',
      'session_snapshot_round_length',
      'routines_down_round_length',
    ]) {
      test('Phase 2 item 6: $name has no JSON null anywhere', () {
        final fixture = _readJson('$_protocolRoot/fixtures/valid/$name.json');

        expect(
          _nullPaths(fixture),
          isEmpty,
          reason: 'the phone sends this frame with sendMessage, so a null '
              'anywhere in it makes the phone\'s send fail',
        );
      });
    }
  });
}
