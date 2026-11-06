// Plan 128 Phase 0 red tests: a session the phone ended is owed to the watch
// until the watch has it. Assertions read the plan's "Expected (after the
// fix)" column, so most scenarios are red today; the plan's Today column says
// which guards (S-12807, S-12809, S-12816) and which fixture asserts must
// pass now. No production code is touched here.
//
// Plan: docs/plans/2026-11-05-128-session-end-retry-plan/
// …-session-end-retry-plan.md. Harness: copied from the plan's probe source
// (…-probe-source.dart.txt: queueing radio `_QRadio`, shipping graph
// `createWatchSync`, a real Dart `WatchSessionEngine` over
// `InMemoryWatchSessionStore`, probes P1..P6) and extended with a mutable
// clock (S-12803, S-12808, S-12812), a settable wrist session id so one engine
// can run two sessions (S-12806, S-12807), and a helper that applies every
// frame the phone sent to a wrist engine.
//
// Decision/scenario map:
//   D-1 ledger bounds and confirmations -> S-12809, S-12810, S-12811, S-12812
//   D-2(a) wrist frame re-offers the end (once per 30 s per session)
//                                       -> S-12801, S-12802, S-12803, S-12808
//   D-2(b) link back into reach re-offers -> S-12804
//   D-3 storedrow fallback after a restart -> S-12805; S-12813 b (discard: no row)
//   D-4 watch ends silently -> S-12815 (recorded by the governor, not here)
//   D-5 reinstall is handed nothing session-related -> S-12814
//   D-6 no age check on the wrist -> S-12807 (P6 half, green guard)
//   D-7 a discard is owed like a finish -> S-12813 a
//   D-8 no wire change (OS queue keeps the newest lifecycle) -> S-12806
//   D-9 S-217 stays true; today's healing paths keep working -> S-12816
// Probe map: P1, P2 -> S-12816; P3 -> S-12801; P4 -> S-12804; P5 -> S-12814;
// P6 -> S-12807.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _clockBase = DateTime.utc(2026, 11, 5, 9);
DateTime _clockNow = DateTime.utc(2026, 11, 5, 9);
String _wristSid = _sid;

const String _sid = 's-w-128';
const String _sidB = 's-w-128-B';
const String _slotId = 'sx-run';

String _iso() => utcIso(_clockNow);

Map<String, Object?> _slot() => {
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-run',
  'name': 'Run',
  'effortKind': 'timed',
  'capabilities': ['time', 'distance'],
};

/// One `timer_state` frame as the wrist sends it (probe P3's shape).
Map<String, Object?> _timerFrame(String messageId, {String sessionId = _sid}) =>
    {
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': messageId,
      'sessionId': sessionId,
      'type': 'timer_state',
      'origin': 'watch',
      'sentAt': _iso(),
      'payload': <String, Object?>{'timers': <String, Object?>{}},
    };

/// One `set` observation as the wrist's logging surface hands it to the
/// engine, so the frame leaves the way a wrist `observations_up` leaves.
Map<String, Object?> _setEvent({required String entryId}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': WatchObservationKind.set,
  'loggedAt': _iso(),
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-run',
  'reps': 5,
  'loadKg': 80,
};

class _QRadio implements WatchTransport, WatchLinkSource {
  final sent = <Map<String, Object?>>[];
  final attempted = <Map<String, Object?>>[];
  final queued = <Map<String, Object?>>[];
  bool unreachable = false;
  WatchInboundHandler? _h;
  final _link = StreamController<WatchLinkInfo>.broadcast();
  void emitLink({required bool reachable}) => _link.add(
    WatchLinkInfo(paired: true, appInstalled: true, reachable: reachable),
  );
  @override
  bool get isPhoneReachable => true;
  @override
  void onIncoming(WatchInboundHandler h) => _h = h;
  @override
  Future<void> refreshReachability() async {}
  @override
  Future<void> requestRoutines({DateTime? since}) async {}
  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());
  @override
  Future<WatchDelivery> send(Map<String, Object?> e) async {
    attempted.add(e);
    if (!unreachable) {
      sent.add(e);
      return WatchDelivery.delivered;
    }
    if (WatchConnectivityTransport.isDurable(e)) {
      if (const {
        'session_snapshot',
        'session_lifecycle',
        'structure_change',
      }.contains(e['type'])) {
        queued.removeWhere((q) => q['type'] == e['type']);
      }
      queued.add(e);
      return WatchDelivery.queued;
    }
    return WatchDelivery.undelivered;
  }

  Future<void> fromWrist(Map<String, Object?> f) async => _h!(f);
  @override
  Future<WatchLinkInfo> linkInfo() async =>
      const WatchLinkInfo(paired: true, appInstalled: true, reachable: true);
  @override
  Stream<WatchLinkInfo> get linkChanges => _link.stream;
  @override
  Stream<DateTime> get heard => const Stream.empty();
  List<Map<String, Object?>> ofType(String t) => [
    for (final e in sent)
      if (e['type'] == t) e,
  ];
}

void main() {
  late MockWorkoutRepository repo;
  late WorkoutState phone;
  late SettingsState settings;
  late _QRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late List<Map<String, Object?>> wristFrames;

  Future<WatchSyncGraph> startGraph() async {
    final g = (await createWatchSync(
      repository: repo,
      nutritionState: NutritionState(repo),
      foodLibraryState: FoodLibraryState(repo),
      settingsState: settings,
      transport: radio,
      clock: () => _clockNow,
    ))!;
    g.adoption.bindWorkoutState(phone);
    g.autoPush.bindWorkoutState(phone);
    g.timerPush.bindWorkoutState(phone);
    return g;
  }

  /// The wrist starts a session, the phone adopts it, one flush composes and
  /// remembers it (F-A).
  Future<void> wristStarts([String sessionId = _sid]) async {
    _wristSid = sessionId;
    await engine.createSession(modality: null, exercises: [_slot()]);
    await radio.fromWrist(engine.sessionSnapshot()!);
    await pumpEventQueue();
    expect(
      phone.currentSession?.id,
      sessionId,
      reason: 'fixture F-A: the phone adopts the wrist session',
    );
    await graph.autoPush.flush();
  }

  /// E-away: the phone ends while the wrist is away, the OS-queue copy is then
  /// lost. The fixture asserts (engine active before, row has endedAtMs) must
  /// pass today.
  Future<void> phoneEndsWhileAway([String sessionId = _sid]) async {
    expect(
      engine.session?.status,
      WatchSessionStatus.active,
      reason: 'fixture F-A: the wrist still holds the session',
    );
    radio.unreachable = true;
    await phone.endSession(writeToHealth: false);
    await graph.autoPush.flush();
    expect(
      (await repo.getSession(sessionId))?.endedAtMs,
      isNotNull,
      reason: 'fixture F-A: the session row has endedAtMs after the phone ends',
    );
    radio.queued.clear();
    radio.unreachable = false;
  }

  /// E-away with a discard: the phone's discard leaves no row (D-7).
  Future<void> phoneDiscardsWhileAway([String sessionId = _sid]) async {
    expect(
      engine.session?.status,
      WatchSessionStatus.active,
      reason: 'fixture F-A: the wrist still holds the session',
    );
    radio.unreachable = true;
    await phone.discardCurrentSession();
    await graph.autoPush.flush();
    expect(
      await repo.getSession(sessionId),
      isNull,
      reason: 'fixture F-A: a discarded session has no row',
    );
    radio.queued.clear();
    radio.unreachable = false;
  }

  /// Every frame the phone actually sent, applied to a wrist engine in order.
  Future<void> applyPhoneAnswersTo(WatchSessionEngine wrist) async {
    for (final frame in List<Map<String, Object?>>.of(radio.sent)) {
      await wrist.applyMessage(frame);
    }
  }

  Future<void> sendWristFrame(Map<String, Object?> frame) async {
    await radio.fromWrist(frame);
    await pumpEventQueue();
  }

  List<Map<String, Object?>> lifecyclesSent() =>
      radio.ofType('session_lifecycle');

  /// Exactly one delivered `session_lifecycle`, naming [sessionId] with
  /// [state] — the Expected column of S-12801 and its siblings.
  void expectOneEndOffered(String sessionId, String state) {
    final frames = lifecyclesSent();
    expect(frames, hasLength(1), reason: 'one re-offer, not a flood');
    expect(
      frames.single['sessionId'],
      sessionId,
      reason: 'no frame ends a session it does not name',
    );
    expect((frames.single['payload'] as Map)['state'], state);
  }

  setUp(() async {
    _clockNow = _clockBase;
    _wristSid = _sid;
    repo = MockWorkoutRepository();
    await repo.initialize();
    await seedExercise(
      repo,
      id: 'ex-run',
      name: 'Run',
      capabilities: ['time', 'distance'],
    );
    phone = WorkoutState(repo);
    settings = SettingsState(repo, fakePreferencesService());
    await settings.initialize();
    radio = _QRadio();
    wristFrames = [];
    graph = await startGraph();
    engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _clockNow,
      sessionIdFactory: () => _wristSid,
      onEmit: wristFrames.add,
    );
  });

  test(
    'Fixture F-A: the wrist leans back on the phone ending (asserts pass today)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      expect(engine.session?.status, WatchSessionStatus.active);
      expect((await repo.getSession(_sid))?.endedAtMs, isNotNull);
    },
  );

  test(
    'S-12801 the wrist sends timer_state after the phone ended: answered completed (D-2a)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      await sendWristFrame(_timerFrame('m-t1'));
      expectOneEndOffered(_sid, WatchLifecycleState.completed);
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12802 the wrist sends a logged-set observation frame: answered completed (D-2a)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      await engine.appendObservation(_setEvent(entryId: 'entry-1'));
      final ups = [
        for (final f in wristFrames)
          if (f['type'] == 'observations_up') f,
      ];
      expect(
        ups,
        hasLength(1),
        reason: 'harness: the engine emitted one observation frame',
      );
      radio.sent.clear();
      await sendWristFrame(ups.single);
      expectOneEndOffered(_sid, WatchLifecycleState.completed);
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12803 five frames inside 30 s answer once; past 30 s the next frame answers again (D-1 iv, D-2a)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      for (var i = 0; i < 5; i++) {
        await sendWristFrame(_timerFrame('m-burst-$i'));
      }
      expect(
        lifecyclesSent(),
        hasLength(1),
        reason: 'a timer tick must not flood: at most one offer per 30 s',
      );
      _clockNow = _clockNow.add(const Duration(seconds: 31));
      await sendWristFrame(_timerFrame('m-burst-31s'));
      expect(
        lifecyclesSent(),
        hasLength(2),
        reason: 'after the 30 s window the wrist is told again',
      );
    },
  );

  test(
    'S-12804 the watch comes back into reach: the unconfirmed end is sent (D-2b)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      radio.emitLink(reachable: true);
      await pumpEventQueue();
      await graph.autoPush.flush();
      await pumpEventQueue();
      expectOneEndOffered(_sid, WatchLifecycleState.completed);
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12805 phone restart, empty ledger, wrist frame: answered from the stored row (D-3)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      graph = await startGraph(); // second createWatchSync over the same repo
      radio.sent.clear();
      await sendWristFrame(_timerFrame('m-restart'));
      expectOneEndOffered(_sid, WatchLifecycleState.completed);
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12806 two sessions A then B, each ended while away: each answered once, the right id (D-8)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      // The wrist moves on: it abandons its own A (that frame stays in the
      // wrist's outbox, never delivered) and starts B, which the phone adopts
      // and ends while away too. Two unconfirmed ends now sit in the ledger.
      await engine.abandonSession();
      await wristStarts(_sidB);
      await phoneEndsWhileAway(_sidB);
      radio.sent.clear();

      await sendWristFrame(_timerFrame('m-names-a', sessionId: _sid));
      expectOneEndOffered(_sid, WatchLifecycleState.completed);

      await sendWristFrame(_timerFrame('m-names-b', sessionId: _sidB));
      expect(lifecyclesSent(), hasLength(2));
      expect(lifecyclesSent().last['sessionId'], _sidB);
      expect(
        (lifecyclesSent().last['payload'] as Map)['state'],
        WatchLifecycleState.completed,
      );

      // The engine holds B: A's late end must not end it, B's must.
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12807 end of A, wrist holds B: B stays active, a frame naming B sends nothing for A (D-6)',
    () async {
      await wristStarts();
      // End A while away, but keep the OS-queue copy (no lost queue here).
      expect(
        engine.session?.status,
        WatchSessionStatus.active,
        reason: 'fixture F-A: the wrist still holds the session',
      );
      radio.unreachable = true;
      await phone.endSession(writeToHealth: false);
      await graph.autoPush.flush();
      expect((await repo.getSession(_sid))?.endedAtMs, isNotNull);
      final queuedEnds = [
        for (final q in radio.queued)
          if (q['type'] == 'session_lifecycle') q,
      ];
      expect(queuedEnds, hasLength(1));
      final lateEndOfA = queuedEnds.single;
      radio.unreachable = false;

      // The OS delivers A's old end onto a wrist that now holds session B.
      final wristB = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _clockNow,
        sessionIdFactory: () => _sidB,
        onEmit: (_) {},
      );
      await wristB.createSession(modality: null, exercises: [_slot()]);
      radio.sent.clear();
      await wristB.applyMessage(lateEndOfA);
      expect(
        wristB.session?.status,
        WatchSessionStatus.active,
        reason: 'the end of A must not end B (guardSession, D-6)',
      );

      // And the ledger never ends B because of A: a wrist frame naming B
      // answers nothing for either session.
      final queuedBefore = List.of(radio.queued);
      await sendWristFrame(_timerFrame('m-names-b', sessionId: _sidB));
      await graph.autoPush.flush();
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'A is named by no frame; B is spoken of and never ended',
      );
      expect(radio.queued, queuedBefore);
    },
  );

  test(
    'S-12808 a second identical frame answers again only after 30 s, always completed (D-1 iv)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      await sendWristFrame(_timerFrame('m-first'));
      await sendWristFrame(_timerFrame('m-repeat'));
      expect(
        lifecyclesSent(),
        hasLength(1),
        reason: 'the second frame inside the window offers nothing again',
      );
      _clockNow = _clockNow.add(const Duration(seconds: 31));
      await sendWristFrame(_timerFrame('m-later'));
      final frames = lifecyclesSent();
      expect(frames, hasLength(2));
      for (final frame in frames) {
        expect(frame['sessionId'], _sid);
        expect(
          (frame['payload'] as Map)['state'],
          WatchLifecycleState.completed,
          reason: 'never a different state',
        );
      }
    },
  );

  test(
    'S-12809 a running session, frames and link flaps, sends no lifecycle ever (D-1)',
    () async {
      await wristStarts();
      radio.sent.clear();
      radio.queued.clear();
      await sendWristFrame(_timerFrame('m-run-1'));
      await sendWristFrame(_timerFrame('m-run-2'));
      radio.emitLink(reachable: false);
      await pumpEventQueue();
      radio.emitLink(reachable: true);
      await pumpEventQueue();
      await graph.autoPush.flush();
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'an end is re-offered only for a session the row says ended',
      );
      expect([
        for (final q in radio.queued)
          if (q['type'] == 'session_lifecycle') q,
      ], isEmpty);
      expect(engine.session?.status, WatchSessionStatus.active);
    },
  );

  test(
    'S-12809 b a phone restart while the session still runs: the stored row is not ended, so a frame sends nothing (D-3)',
    () async {
      await wristStarts();
      graph =
          await startGraph(); // empty ledger; the mirror holds no session id
      radio.sent.clear();
      radio.queued.clear();
      await sendWristFrame(_timerFrame('m-run-restart'));
      radio.emitLink(reachable: true);
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'the row seam answers only for a row with endedAtMs set',
      );
      expect(engine.session?.status, WatchSessionStatus.active);
    },
  );

  test(
    'S-12810 a wrist lifecycle completed confirms the end: afterwards a frame sends nothing (D-1 i)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      await engine.finishSession(); // wrist own end, emitted as its own frame
      final ownEnds = [
        for (final f in wristFrames)
          if (f['type'] == 'session_lifecycle' &&
              (f['payload'] as Map)['state'] == WatchLifecycleState.completed)
            f,
      ];
      expect(
        ownEnds,
        hasLength(1),
        reason: 'harness: the wrist emitted its own completed lifecycle',
      );
      await sendWristFrame(ownEnds.single);
      await pumpEventQueue();
      await sendWristFrame(_timerFrame('m-after-confirm'));
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'the wrist said it has the end; nothing is re-offered',
      );
    },
  );

  test(
    'S-12810 b an ended wrist snapshot confirms the end: afterwards a frame sends nothing (D-1 i)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      await engine.finishSession();
      await sendWristFrame(engine.sessionSnapshot()!);
      await pumpEventQueue();
      final afterSnapshot = lifecyclesSent().length;
      await sendWristFrame(_timerFrame('m-after-confirm'));
      await pumpEventQueue();
      expect(
        lifecyclesSent().length,
        afterSnapshot,
        reason:
            'once the wrist shows the session ended, a later frame sends nothing',
      );
    },
  );

  test(
    'S-12811 the wrist names a different session: entry removed, nothing sent for A or B (D-1 ii)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      radio.queued.clear();
      await sendWristFrame(_timerFrame('m-moved-on', sessionId: _sidB));
      await graph.autoPush.flush();
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'naming another session confirms A and never ends B',
      );
      expect([
        for (final q in radio.queued)
          if (q['type'] == 'session_lifecycle') q,
      ], isEmpty);
      expect(engine.session?.status, WatchSessionStatus.active);
      // Only an ended state the wrist announces for another session proves it
      // left A (D-1 ii as built: a plain frame naming B does not, S-12806): the
      // wrist's completed lifecycle for B retires A's debt, so a later frame
      // naming A (after the 30 s window) and the link returning send nothing.
      await sendWristFrame({
        ..._timerFrame('m-b-ended', sessionId: _sidB),
        'type': 'session_lifecycle',
        'payload': <String, Object?>{
          'state': WatchLifecycleState.completed,
          'at': _iso(),
        },
      });
      _clockNow = _clockNow.add(const Duration(seconds: 31));
      await sendWristFrame(_timerFrame('m-names-a-later'));
      radio.emitLink(reachable: true);
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'naming another session retired the ledger entry of A',
      );
    },
  );

  test(
    'S-12812 a frames 31 s apart, four times: exactly three re-offers, the fourth sends none (D-1 iv)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      for (var i = 0; i < 4; i++) {
        if (i > 0) {
          _clockNow = _clockNow.add(const Duration(seconds: 31));
        }
        await sendWristFrame(_timerFrame('m-spaced-$i'));
      }
      expect(
        lifecyclesSent(),
        hasLength(3),
        reason: 'at three re-offers the ledger stops talking',
      );
    },
  );

  test('S-12812 b clock advanced 25 h, then a frame: none (D-1 iv)', () async {
    await wristStarts();
    await phoneEndsWhileAway();
    radio.sent.clear();
    _clockNow = _clockNow.add(const Duration(hours: 25));
    await sendWristFrame(_timerFrame('m-much-later'));
    expect(lifecyclesSent(), isEmpty, reason: 'the ledger never outlives 24 h');
  });

  test(
    'S-12813 a discard while away, queue dropped, link back, wrist frame: abandoned (D-7)',
    () async {
      await wristStarts();
      await phoneDiscardsWhileAway();
      radio.emitLink(reachable: true);
      await pumpEventQueue();
      radio.sent.clear();
      await sendWristFrame(_timerFrame('m-discard-frame'));
      await graph.autoPush.flush();
      await pumpEventQueue();
      final frames = lifecyclesSent();
      expect(frames, isNotEmpty, reason: 'a discard is owed like a finish');
      for (final frame in frames) {
        expect(frame['sessionId'], _sid);
        expect(
          (frame['payload'] as Map)['state'],
          WatchLifecycleState.abandoned,
        );
      }
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.abandoned);
    },
  );

  test(
    'S-12813 b after a phone restart a discarded end is not answered (D-3)',
    () async {
      await wristStarts();
      await phoneDiscardsWhileAway();
      graph = await startGraph();
      radio.sent.clear();
      await sendWristFrame(_timerFrame('m-after-restart'));
      await graph.autoPush.flush();
      await pumpEventQueue();
      expect(
        lifecyclesSent(),
        isEmpty,
        reason: 'no row exists to tell a discard from a wrist-only session',
      );
    },
  );

  test(
    'S-12814 a reinstalled wrist asks for a snapshot, gets no ended session (D-5)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      final fresh = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _clockNow,
        sessionIdFactory: () => 's-w-fresh',
        onEmit: (_) {},
      );
      radio.sent.clear();
      await sendWristFrame(WatchTransportRequest.snapshotFrame());
      final snapshotIds = [
        for (final e in radio.sent)
          if (e['type'] == 'session_snapshot')
            (e['payload'] as Map)['sessionId'],
      ];
      expect(
        snapshotIds,
        isNot(contains(_sid)),
        reason: 'a request means I hold nothing; an ended one is not a join',
      );
      await applyPhoneAnswersTo(fresh);
      expect(
        fresh.session,
        isNull,
        reason: 'the new wrist holds nothing, not an old finished session',
      );
    },
  );

  test(
    'S-12816 P1 wrist opens a snapshot conversation, same phone run: ended (D-9)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      radio.sent.clear();
      await sendWristFrame(engine.sessionSnapshot()!);
      await pumpEventQueue();
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );

  test(
    'S-12816 P2 wrist snapshot after a phone restart: still ended (D-3)',
    () async {
      await wristStarts();
      await phoneEndsWhileAway();
      graph = await startGraph();
      radio.sent.clear();
      await sendWristFrame(engine.sessionSnapshot()!);
      await pumpEventQueue();
      await applyPhoneAnswersTo(engine);
      expect(engine.session?.status, WatchSessionStatus.completed);
    },
  );
}
