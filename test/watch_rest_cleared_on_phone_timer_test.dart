import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` writes capabilities through `setExerciseCapabilities`, which is
// the only way they reach a repository: the projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 10, 19, 9);

/// The session both devices know.
const String _sessionId = 's-w-timers';

/// The one slot the fixture puts in the ladder, and its effort id on the phone
/// (D-3: the wrist's slot id IS the phone's effort id).
const String _slotId = 'sx-run';

/// A rest start unlike any default: the instant the phone logged the set.
final DateTime _restStart = DateTime.utc(2026, 3, 4, 5, 6, 7);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// A catalog the phone can adopt a timed slot for.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Run',
    capabilities: ['time', 'distance'],
  );
}

/// One ladder slot as the protocol spells it: a timed exercise.
Map<String, Object?> _slot() => <String, Object?>{
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-run',
  'name': 'Run',
  'effortKind': 'timed',
  'capabilities': ['time', 'distance'],
};

var _wristMessageCount = 0;

/// One `timer_state` frame as the wrist sends it.
Map<String, Object?> _wristTimerFrame(Map<String, Object?> timers) => {
  'protocolVersion': 1,
  'messageId': 'msg-wrist-timers-${_wristMessageCount++}',
  'sessionId': _sessionId,
  'type': 'timer_state',
  'origin': 'watch',
  'sentAt': utcIso(_now),
  'payload': {'timers': timers},
};

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it cannot
/// carry the way the platform channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed.
  final List<Map<String, Object?>> attempted = [];

  /// True while the wrist is out of range: `send` carries nothing and answers
  /// `undelivered` without a failure.
  bool unreachable = false;

  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    attempted.add(envelope);
    if (unreachable) return WatchDelivery.undelivered;
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _PhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Map<String, Object?>> wristFrames;
  late List<Object> failures;

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption and to the timer push in
  /// `lib/main.dart`; the scenarios bind the push themselves, once their
  /// fixture has settled.
  Future<WatchSyncGraph> startGraph() async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
    ))!;
    created.adoption.bindWorkoutState(phoneState);
    return created;
  }

  /// The wrist starts [_sessionId] with one timed slot, and the phone adopts
  /// it: the fixture every scenario starts from.
  Future<void> wristStartsTimedSession() async {
    await engine.createSession(modality: null, exercises: [_slot()]);
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      _sessionId,
      reason: "the fixture: the phone's own session is the wrist's",
    );
    expect(graph.mirror.sessionId, _sessionId);
    final effort = phoneState
        .getEffortsForSegment(phoneState.segments.single.id)
        .single;
    expect(effort.id, _slotId, reason: 'D-3: the slot id is the effort id');
    expect(
      effort.effortKind,
      'timed',
      reason: 'the fixture: the slot logs as a timed effort',
    );
  }

  /// The phone starts one interval of the slot's effort and returns the stored
  /// instance the push must compose from.
  Future<InProgressWorkTimer> startInterval() async {
    await phoneState.startTimedEntry(_slotId, 0);
    final timers = phoneState.inProgressWorkTimers();
    expect(
      timers,
      hasLength(1),
      reason: 'the fixture: one in-progress work timer',
    );
    return timers.single;
  }

  /// Every timer frame the phone sent, in order.
  List<Map<String, Object?>> timerFrames() => radio.ofType('timer_state');

  /// The `timers` object of [envelope].
  Map<String, Object?> timersOf(Map<String, Object?> envelope) =>
      _asObject(_payload(envelope)['timers']);

  /// The phone opens a rest on [effortId]'s entry [entryIndex] the way the
  /// session screen does, then pins its stamps to [_restStart] (and the pause
  /// fields to the fixture's values) so no scenario reads the wall clock.
  Future<EntryRest> openPhoneRest({
    String? effortId,
    int entryIndex = 0,
    DateTime? startedAt,
    bool paused = false,
    DateTime? pausedAt,
    int accumulatedPauseMs = 0,
  }) async {
    final effort = effortId ?? _slotId;
    final start = startedAt ?? _restStart;
    await phoneState.recordRestStart(effort, entryIndex);

    final stored = (await repository.getEntryRests(
      effort,
    )).firstWhere((rest) => rest.entryIndex == entryIndex);
    final pinned = stored.copyWith(
      restStartMs: start.millisecondsSinceEpoch,
      restIsPaused: paused,
      restPausedAtMs: paused
          ? (pausedAt ?? start).millisecondsSinceEpoch
          : null,
      restPausedDurationMs: accumulatedPauseMs,
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    );
    await repository.updateEntryRest(pinned);
    await phoneState.refreshEfforts([effort]);
    return pinned;
  }

  /// Hands the mirror a rest the wrist reports, the way the radio does.
  Future<void> mirrorRest({
    required DateTime startedAt,
    String state = 'running',
    DateTime? pausedAt,
    int accumulatedPauseMs = 0,
  }) async {
    await radio.fromWrist(
      _wristTimerFrame({
        'rest': {
          'kind': 'rest',
          'state': state,
          'startedAt': utcIso(startedAt),
          'accumulatedPauseMs': accumulatedPauseMs,
          if (pausedAt != null) 'pausedAt': utcIso(pausedAt),
        },
      }),
    );
    await _settle();
  }

  /// Starts the wrist's own rest and forwards its frame, the way the watch
  /// logs a set: the fixture every wrist-owned rest starts from.
  Future<DateTime> startWristRest() async {
    await engine.startTimer(WatchTimerKind.rest);
    await radio.fromWrist(wristFrames.last);
    await _settle();
    expect(
      engine.timerFor(WatchTimerKind.rest)?.state,
      WatchTimerState.running,
      reason: 'fixture: the wrist is resting',
    );
    return engine.timerFor(WatchTimerKind.rest)!.startedAt;
  }

  /// Applies the phone's timer frames to the wrist engine, in the order they
  /// were sent, the way the watch app applies each frame it receives.
  Future<void> applyRestFramesToWrist() async {
    for (final f in timerFrames()) {
      await engine.applyMessage(f);
    }
  }

  /// True when [f]'s `timers` object clears the rest.
  bool clearsRest(Map<String, Object?> f) {
    final t = timersOf(f);
    return t.containsKey('rest') && t['rest'] == null;
  }

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _PhoneRadio(failures.add);
    graph = await startGraph();

    wristFrames = [];
    wristStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => _sessionId,
      onEmit: wristFrames.add,
    );
  });

  group('S-13601 a phone work timer stops the wrist\'s own running rest', () {
    test(
      'S-13601 the clear is its own frame and the wrist\'s rest ends',
      () async {
        await wristStartsTimedSession();
        graph.timerAdoption.bindWorkoutState(phoneState);
        graph.timerPush.bindWorkoutState(phoneState);
        await startWristRest();
        await phoneState.startTimedEntry(_slotId, 0);
        await graph.timerPush.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(timerFrames().any(clearsRest), isTrue);
        await applyRestFramesToWrist();
        expect(
          engine.timerFor(WatchTimerKind.rest)?.state ==
              WatchTimerState.running,
          isFalse,
        );
        expect(failures, isEmpty);
      },
    );
  });

  group(
    'S-13602 a wrist rest that started after the phone timer is not cleared',
    () {
      test('S-13602 no frame clears the newer wrist rest', () async {
        await wristStartsTimedSession();
        graph.timerAdoption.bindWorkoutState(phoneState);
        graph.timerPush.bindWorkoutState(phoneState);
        final timer = await startInterval();
        await mirrorRest(
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            timer.startedAtMs + 5000,
            isUtc: true,
          ),
        );
        await graph.timerPush.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(timerFrames().any(clearsRest), isFalse);
        expect(failures, isEmpty);
      });
    },
  );

  group('S-13603 a wrist rest already stopped is not cleared', () {
    test('S-13603 no frame clears the ended rest', () async {
      await wristStartsTimedSession();
      graph.timerAdoption.bindWorkoutState(phoneState);
      graph.timerPush.bindWorkoutState(phoneState);
      await startWristRest();
      await engine.stopTimer(kind: WatchTimerKind.rest);
      final stopped = _asObject(
        _asObject(_payload(wristFrames.last)['timers'])['rest'],
      );
      expect(
        stopped['state'],
        'stopped',
        reason: 'the fixture: the wrist reports its own stop',
      );
      await radio.fromWrist(wristFrames.last);
      await _settle();
      await startInterval();
      await graph.timerPush.flush();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(timerFrames().any(clearsRest), isFalse);
      expect(failures, isEmpty);
    });
  });

  group('S-13604 the wrist rest is cleared once', () {
    test(
      'S-13604 later passes and a stale mirror copy send no second clear',
      () async {
        await wristStartsTimedSession();
        graph.timerAdoption.bindWorkoutState(phoneState);
        graph.timerPush.bindWorkoutState(phoneState);
        final restStart = await startWristRest();
        await phoneState.startTimedEntry(_slotId, 0);
        await graph.timerPush.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(
          timerFrames().any(clearsRest),
          isTrue,
          reason: 'the fixture: the rest was cleared on the first pass',
        );
        await graph.timerPush.flush();
        await mirrorRest(startedAt: restStart);
        await graph.timerPush.flush();
        expect(timerFrames().where(clearsRest).length, 1);
        expect(failures, isEmpty);
      },
    );
  });

  group(
    'S-13605 an undelivered clear is owed while the wrist is unreachable',
    () {
      test(
        'S-13605 the clear is sent when the wrist is back in reach',
        () async {
          await wristStartsTimedSession();
          graph.timerAdoption.bindWorkoutState(phoneState);
          graph.timerPush.bindWorkoutState(phoneState);
          await startWristRest();
          radio.unreachable = true;
          await phoneState.startTimedEntry(_slotId, 0);
          await graph.timerPush.flush();
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(
            radio.sent.any(clearsRest),
            isFalse,
            reason: 'nothing was delivered while the radio was unreachable',
          );
          radio.unreachable = false;
          await graph.timerPush.flushClears();
          await _settle();
          expect(timerFrames().where(clearsRest).length, 1);
          expect(failures, isEmpty);
        },
      );
    },
  );

  group('S-13606 a paused wrist rest is cleared the same way', () {
    test('S-13606 the clear is sent for a paused mirror rest', () async {
      await wristStartsTimedSession();
      graph.timerAdoption.bindWorkoutState(phoneState);
      graph.timerPush.bindWorkoutState(phoneState);
      await mirrorRest(
        startedAt: DateTime.utc(2026, 10, 19, 9),
        state: 'paused',
        pausedAt: DateTime.utc(2026, 10, 19, 9, 0, 1),
        accumulatedPauseMs: 1000,
      );
      await startInterval();
      await graph.timerPush.flush();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(timerFrames().any(clearsRest), isTrue);
      expect(failures, isEmpty);
    });
  });

  group(
    'S-13607 a phone rest cleared by a same-slot interval stays one clear',
    () {
      test('S-13607 exactly one rest:null frame travels', () async {
        await wristStartsTimedSession();
        graph.timerAdoption.bindWorkoutState(phoneState);
        graph.timerPush.bindWorkoutState(phoneState);
        await openPhoneRest();
        await graph.timerPush.flush();
        await startInterval();
        await graph.timerPush.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(timerFrames().where(clearsRest).length, 1);
        expect(failures, isEmpty);
      });
    },
  );

  group('S-13608 a rest the phone holds is never cleared as the wrist\'s', () {
    test(
      'S-13608 the phone runs its own rest beside a running interval and the '
      'wrist reports an older rest: no frame clears the rest',
      () async {
        await wristStartsTimedSession();
        graph.timerAdoption.bindWorkoutState(phoneState);
        graph.timerPush.bindWorkoutState(phoneState);
        await startInterval();
        await graph.timerPush.flush();
        await openPhoneRest();
        await mirrorRest(startedAt: DateTime.utc(2026, 10, 19, 9));
        await graph.timerPush.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(
          timerFrames().where(clearsRest),
          isEmpty,
          reason: 'the phone holds a rest of its own: its frame supersedes',
        );
        expect(failures, isEmpty);
      },
    );
  });
}
