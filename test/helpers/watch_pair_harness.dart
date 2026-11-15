/// The phone half and the wrist half of plan 145's convergence harness, the
/// radio between them, and the actions a trace is made of.
///
/// Plan: `docs/plans/2026-11-10-145-convergence-test-plan/2026-11-10-145-convergence-test-plan.md`
/// (D-14501…D-14505, D-14512, D-14513, D-14515; scenario S-14501).
///
/// Three rules shape this file:
///
/// 1. **Both halves are the real thing.** The phone is the shipping graph
///    `createWatchSync` over a `MockWorkoutRepository`; the wrist is a real
///    `WatchSessionEngine` over an `InMemoryWatchSessionStore` with its
///    `WatchSyncOrchestrator` — the pair plan 128's probe built, generalised
///    here (D-14501). Nothing under test is replaced by a double.
/// 2. **The radio models the OS, not a wish.** A frame is delivered live when
///    both devices are reachable, queued when it is durable and the link is
///    down or the radio refuses it, and lost when it is live-only (D-14504,
///    D-14515). Queue withdrawal is the transport's own (D-14512).
/// 3. **Determinism.** Every id minted here comes from a counter and every
///    stamp from the injected [TestClock]/one `PairRadio.clock`, so a replay of
///    the same actions is the same run (D-14503). No `Future.delayed`, no real
///    clock, no unseeded randomness.
///
/// Plan 128's `test/watch_session_end_owed_test.dart` is the probe source for
/// the graph and the queueing radio; its private pieces are copied here and
/// generalised, never imported (D-14502).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart' show pumpEventQueue;
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/end_skew.dart'
    show kEndSkewToleranceMs;
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/entry_rows.dart' show EntryRows;
import 'package:omnitrain/data/models/models.dart'
    show Exercise, SegmentEffort, WatchInboxEntry;
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'fake_preferences_service.dart';
import 'sync_protocol_harness.dart';
import 'watch_capture_import_harness.dart' show seedExercise;

/// Which way a frame crossed the radio.
enum PairLane {
  /// Phone → wrist: the lane the phone's graph sends on.
  phoneToWrist,

  /// Wrist → phone: the lane the wrist's engine and orchestrator send on.
  wristToPhone,
}

/// One frame that crossed the radio, as the trace reads it.
class PairFrame {
  PairFrame({
    required this.lane,
    required this.frame,
    required this.outcome,
    this.actionSerial,
    this.refused = false,
    this.drained = false,
  });

  final PairLane lane;
  final Map<String, Object?> frame;
  final WatchDelivery outcome;

  /// The serial of the [PairAction] that was running when the frame crossed,
  /// or null for a frame a background trigger sent.
  final int? actionSerial;

  /// Whether the radio refused the frame rather than the link being down.
  final bool refused;

  /// Whether the frame came out of the OS queue rather than off the live radio.
  final bool drained;

  String get type {
    final named = frame['type'];
    if (named is String) return named;
    return 'request:${WatchTransportRequest.nameOf(frame)}';
  }

  String? get sessionId {
    final id = frame['sessionId'];
    return id is String ? id : null;
  }

  @override
  String toString() =>
      '${lane.name} $type${sessionId == null ? '' : ' $sessionId'} '
      '${outcome.name}${refused ? ' (refused)' : ''}'
      '${drained ? ' (drained)' : ''}';
}

/// The radio between the two devices: two lanes, one reachability flag, one OS
/// queue per lane.
///
/// The phone lane is the shipping transport's (`send` with
/// [WatchConnectivityTransport.isDurable] and [PairRadio.phoneQueue]); the wrist
/// lane is the wrist's own queue rule (D-14504) and both apply the withdraw
/// rules (D-14512). A refusal is answered exactly as the production `send`
/// answers one (D-14515): durable → queued, live-only → undelivered, never a
/// throw.
class PairRadio implements WatchTransport, WatchLinkSource {
  PairRadio({required this.clock, this.onFailure});

  /// The one clock both halves read.
  final TestClock clock;

  /// Where a handler's failure is reported, as the shipping transport's
  /// `onFailure` reports it.
  final void Function(Object error, StackTrace stack)? onFailure;

  /// Whether the devices can reach each other right now. One flag for both
  /// lanes: the platform reports one.
  bool reachable = true;

  /// Which frames the radio refuses, per lane. Null refuses none. A refusal is a
  /// fault the harness injects, never a property of the OS queue.
  bool Function(PairLane lane, Map<String, Object?> frame)? refuseWhen;

  /// Every frame that crossed, or was handed to a queue, in order.
  final List<PairFrame> frames = [];

  /// The phone→wrist OS queue, in queue order.
  final List<Map<String, Object?>> phoneQueue = [];

  /// The wrist→phone OS queue, in queue order.
  final List<Map<String, Object?>> wristQueue = [];

  /// The serial of the action whose work is running, stamped on each frame.
  int? actionSerial;

  /// The most frames one run may deliver before the radio stops delivering.
  ///
  /// A pair whose every delivery provokes another never gives the event loop
  /// back: pending microtasks run before timers, so neither the run nor the
  /// test's own timeout can end it (one seed of the 200-seed sweep). The budget
  /// turns that into a reported outcome — [runaway] is set and the frames after
  /// it arrive undelivered — instead of a hang that says nothing.
  static const int deliveryBudget = 20000;

  /// Whether the run exceeded [deliveryBudget]: the pair never stopped
  /// answering itself.
  bool runaway = false;

  int _deliveries = 0;

  WatchInboundHandler? _phoneInbound;
  WatchInboundHandler? _wristInbound;
  final StreamController<WatchLinkInfo> _link =
      StreamController<WatchLinkInfo>.broadcast();
  final StreamController<DateTime> _heard =
      StreamController<DateTime>.broadcast();

  /// Binds the wrist's inbound path — what a phone→wrist frame reaches.
  void bindWristInbound(WatchInboundHandler handler) => _wristInbound = handler;

  /// The frames of one protocol type that crossed, in order.
  List<PairFrame> ofType(String type) => [
    for (final frame in frames)
      if (frame.frame['type'] == type) frame,
  ];

  /// Flips the link. The phone's graph hears it through [linkChanges], which is
  /// what a reconnect trigger is.
  void setReachable(bool value) {
    if (reachable == value) return;
    reachable = value;
    _link.add(
      WatchLinkInfo(paired: true, appInstalled: true, reachable: value),
    );
  }

  /// Delivers the queued frames of both lanes, in queue order, oldest first.
  ///
  /// A queued frame may arrive after live frames that were sent later — that is
  /// the reorder the OS queue is (D-14504). Nothing inside a queue is reordered.
  ///
  /// The drain is bounded to the frames the queue held when it started: a
  /// delivery that enqueues another frame — the link is up, so this only
  /// happens when a refusal keeps sending its frames to the queue — leaves it
  /// owed for the next trigger. Draining to an empty queue livelocked the
  /// random run (seed 46: `LinkRises` never returned).
  Future<void> drainQueues() async {
    final queuedOnPhone = phoneQueue.length;
    for (var i = 0; i < queuedOnPhone && phoneQueue.isNotEmpty; i++) {
      final frame = _copy(phoneQueue.removeAt(0));
      frames.add(
        PairFrame(
          lane: PairLane.phoneToWrist,
          frame: _copy(frame),
          outcome: WatchDelivery.delivered,
          actionSerial: actionSerial,
          drained: true,
        ),
      );
      await _deliver(PairLane.phoneToWrist, frame);
    }
    final queuedOnWrist = wristQueue.length;
    for (var i = 0; i < queuedOnWrist && wristQueue.isNotEmpty; i++) {
      final frame = _copy(wristQueue.removeAt(0));
      frames.add(
        PairFrame(
          lane: PairLane.wristToPhone,
          frame: _copy(frame),
          outcome: WatchDelivery.delivered,
          actionSerial: actionSerial,
          drained: true,
        ),
      );
      await _deliver(PairLane.wristToPhone, frame);
    }
  }

  // ── The lanes ────────────────────────────────────────────────────────────

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) =>
      cross(PairLane.phoneToWrist, envelope);

  /// A frame the wrist sends: its engine's emissions and its orchestrator's
  /// requests and answers all leave through here.
  Future<WatchDelivery> deliverFromWrist(Map<String, Object?> envelope) =>
      cross(PairLane.wristToPhone, envelope);

  /// Hands [envelope] across [lane], delivering, queueing or losing it by the
  /// rules of that lane.
  Future<WatchDelivery> cross(
    PairLane lane,
    Map<String, Object?> envelope,
  ) async {
    final frame = _copy(envelope);
    final refused = refuseWhen?.call(lane, frame) ?? false;
    WatchDelivery delivery;
    if (!reachable || refused) {
      delivery = _enqueue(lane, frame)
          ? WatchDelivery.queued
          : WatchDelivery.undelivered;
    } else {
      if (lane == PairLane.phoneToWrist) {
        await _deliver(lane, frame);
      } else {
        // The OS hands a wrist frame to the phone asynchronously: the watch's
        // send completes when the frame has left it. Awaiting the phone's
        // handler here would let a push pass that is mid-`send` deadlock
        // against the flush that handler triggers — a cycle production cannot
        // have, because the phone reads the frame in another process. Broken
        // only by production's 10 s `sendTimeout` (D-98), it cost the seed
        // sweep 10 s per stalled seed (evidence F-lane).
        unawaited(_deliver(lane, frame));
      }
      _withdrawAfterSend(lane, frame);
      delivery = WatchDelivery.delivered;
    }
    frames.add(
      PairFrame(
        lane: lane,
        frame: _copy(frame),
        outcome: delivery,
        actionSerial: actionSerial,
        refused: refused,
      ),
    );
    return delivery;
  }

  /// The withdraw rules on the live path: a frame the OS carries now replaces
  /// the queued copy of the same kind, exactly as the production `send` does
  /// (`watch_transport.dart:384`). Without this a stale queued copy survives a
  /// newer live frame and drains after it — a late frame the real OS never
  /// delivers (D-14512).
  void _withdrawAfterSend(PairLane lane, Map<String, Object?> frame) {
    if (lane == PairLane.phoneToWrist) {
      _withdrawOnPhoneQueue(frame);
    } else {
      _withdrawOnWristQueue(frame);
    }
  }

  /// Cancels the phone-lane copies [frame] replaces (D-14512): the production
  /// transport's `_withdrawSuperseded` rule — the same type and `sessionId`
  /// and, for a `structure_change`, the same payload `changeId`. `receipt` and
  /// `exercise_push` are never withdrawn.
  void _withdrawOnPhoneQueue(Map<String, Object?> frame) {
    final type = frame['type'];
    if (!_phoneReplaceable.contains(type)) return;
    final sessionId = frame['sessionId'];
    if (sessionId is! String) return;
    String? changeId;
    if (type == 'structure_change') {
      final raw = _payload(frame)['changeId'];
      if (raw is! String) return;
      changeId = raw;
    }
    phoneQueue.removeWhere(
      (queued) =>
          queued['type'] == type &&
          queued['sessionId'] == sessionId &&
          (changeId == null || _payload(queued)['changeId'] == changeId),
    );
  }

  /// The phone-lane types a newer copy replaces (`watch_transport.dart:256`).
  static const Set<String> _phoneReplaceable = {
    'session_snapshot',
    'session_lifecycle',
    'structure_change',
  };

  /// Queues [frame] when its lane may carry it, after the withdraw rules of
  /// D-14512. Returns false when the lane may not carry it at all (live-only).
  bool _enqueue(PairLane lane, Map<String, Object?> frame) {
    if (lane == PairLane.phoneToWrist) {
      if (!WatchConnectivityTransport.isDurable(frame)) return false;
      _withdrawOnPhoneQueue(frame);
      phoneQueue.add(frame);
      return true;
    }

    if (!isWristQueueable(frame)) return false;

    // A copy older than one already waiting is not queued; a terminal
    // lifecycle is never stale (D-14512).
    if (!_isTerminalLifecycle(frame) && _isOlderThanWaiting(frame)) return true;
    _withdrawOnWristQueue(frame);
    wristQueue.add(frame);
    return true;
  }

  /// The wrist lane's queue eligibility (D-14504): the observation stream, a
  /// lifecycle of any state, and a snapshot only while it names an active
  /// session. A timer, a request, a static frame and `energy_live` are live-only.
  static bool isWristQueueable(Map<String, Object?> frame) =>
      switch (frame['type']) {
        'observations_up' => true,
        'session_lifecycle' => true,
        'session_snapshot' =>
          _payload(frame)['status'] == WatchSessionStatus.active,
        _ => false,
      };

  static bool _isTerminalLifecycle(Map<String, Object?> frame) {
    if (frame['type'] != 'session_lifecycle') return false;
    final state = _payload(frame)['state'];
    return state == WatchLifecycleState.completed ||
        state == WatchLifecycleState.abandoned;
  }

  bool _isOlderThanWaiting(Map<String, Object?> frame) {
    final sentAt = _instant(frame['sentAt']);
    if (sentAt == null) return false;
    for (final queued in wristQueue) {
      if (queued['type'] != frame['type']) continue;
      if (queued['sessionId'] != frame['sessionId']) continue;
      final waiting = _instant(queued['sentAt']);
      if (waiting != null && sentAt.isBefore(waiting)) return true;
    }
    return false;
  }

  void _withdrawOnWristQueue(Map<String, Object?> frame) {
    final sessionId = frame['sessionId'];
    if (sessionId is! String) return;
    switch (frame['type']) {
      case 'session_snapshot':
        wristQueue.removeWhere(
          (queued) =>
              queued['type'] == 'session_snapshot' &&
              queued['sessionId'] == sessionId,
        );
      case 'session_lifecycle':
        if (_isTerminalLifecycle(frame)) {
          wristQueue.removeWhere(
            (queued) =>
                queued['sessionId'] == sessionId &&
                (queued['type'] == 'session_snapshot' ||
                    (queued['type'] == 'session_lifecycle' &&
                        !_isTerminalLifecycle(queued))),
          );
        } else {
          wristQueue.removeWhere(
            (queued) =>
                queued['type'] == 'session_lifecycle' &&
                queued['sessionId'] == sessionId &&
                !_isTerminalLifecycle(queued),
          );
        }
      default:
        break;
    }
  }

  Future<void> _deliver(PairLane lane, Map<String, Object?> frame) async {
    if (++_deliveries > deliveryBudget) {
      runaway = true;
      return;
    }
    _heard.add(clock.call());
    final handler = lane == PairLane.phoneToWrist
        ? _wristInbound
        : _phoneInbound;
    if (handler == null) {
      onFailure?.call(
        StateError('no inbound handler for ${lane.name}'),
        StackTrace.current,
      );
      return;
    }
    try {
      await handler(frame);
    } catch (error, stack) {
      onFailure?.call(error, stack);
    }
  }

  // ── WatchTransport ───────────────────────────────────────────────────────

  @override
  void onIncoming(WatchInboundHandler handler) => _phoneInbound = handler;

  @override
  bool get isPhoneReachable => reachable;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestSnapshot() => send(WatchTransportRequest.snapshotFrame());

  @override
  Future<void> requestRoutines({DateTime? since}) =>
      send(WatchTransportRequest.routinesFrame(since: since));

  // ── WatchLinkSource ──────────────────────────────────────────────────────

  @override
  Future<WatchLinkInfo> linkInfo() async =>
      WatchLinkInfo(paired: true, appInstalled: true, reachable: reachable);

  @override
  Stream<WatchLinkInfo> get linkChanges => _link.stream;

  @override
  Stream<DateTime> get heard => _heard.stream;

  static Map<String, Object?> _payload(Map<String, Object?> frame) {
    final payload = frame['payload'];
    return payload is Map ? payload.cast<String, Object?>() : const {};
  }

  static DateTime? _instant(Object? iso) =>
      iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

  /// A deep copy through JSON: no frame is ever shared between the two devices
  /// (the input-reality checklist).
  static Map<String, Object?> _copy(Map<String, Object?> frame) =>
      (jsonDecode(jsonEncode(frame)) as Map).cast<String, Object?>();
}

/// Who performed an action.
enum PairActor { phone, wrist, link, time }

/// One thing that happened to the pair, numbered so a trace reads as a story.
sealed class PairAction {
  const PairAction({
    required this.actor,
    required this.serial,
    this.synthetic = false,
  });

  final PairActor actor;

  /// Stable within a run: assigned when the action is minted, never renumbered.
  final int serial;

  /// True only for an action the shipping app cannot perform (D-14513).
  final bool synthetic;

  /// One sentence a trace line reads as.
  String describe();
}

final class PhoneStartsSession extends PairAction {
  const PhoneStartsSession({required super.serial})
    : super(actor: PairActor.phone);

  @override
  String describe() => 'phone starts a session';
}

final class PhoneLogsSet extends PairAction {
  const PhoneLogsSet({required super.serial, this.effortId})
    : super(actor: PairActor.phone);

  /// The effort the set is logged against; null means the session's first.
  final String? effortId;

  @override
  String describe() => 'phone logs a set';
}

final class PhoneFinishes extends PairAction {
  const PhoneFinishes({required super.serial}) : super(actor: PairActor.phone);

  @override
  String describe() => 'phone finishes';
}

final class PhoneDiscards extends PairAction {
  const PhoneDiscards({required super.serial}) : super(actor: PairActor.phone);

  @override
  String describe() => 'phone discards';
}

final class PhoneStartsRest extends PairAction {
  const PhoneStartsRest({required super.serial, this.effortId})
    : super(actor: PairActor.phone);

  final String? effortId;

  @override
  String describe() => 'phone starts a rest timer';
}

/// The one harness-only action (D-14513): a `started` lifecycle for the held
/// session, sent through the phone→wrist lane. The shipping phone never sends
/// one, which is why every trace line it produces is marked synthetic.
final class PhoneReassertsLive extends PairAction {
  const PhoneReassertsLive({required super.serial})
    : super(actor: PairActor.phone, synthetic: true);

  @override
  String describe() => 'phone re-asserts the held session live (harness-only)';
}

final class WristStartsFreeWorkout extends PairAction {
  const WristStartsFreeWorkout({required super.serial})
    : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist starts a Free workout';
}

final class WristLogsSet extends PairAction {
  const WristLogsSet({required super.serial}) : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist logs a set';
}

final class WristFinishes extends PairAction {
  const WristFinishes({required super.serial}) : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist finishes';
}

final class WristDiscards extends PairAction {
  const WristDiscards({required super.serial}) : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist discards';
}

final class WristStartsRest extends PairAction {
  const WristStartsRest({required super.serial})
    : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist starts a rest timer';
}

final class LinkDrops extends PairAction {
  const LinkDrops({required super.serial}) : super(actor: PairActor.link);

  @override
  String describe() => 'link drops';
}

final class LinkRises extends PairAction {
  const LinkRises({required super.serial}) : super(actor: PairActor.link);

  @override
  String describe() => 'link rises and drains the queue';
}

/// Injects a refusal on the next matching send of [from]'s lane (D-14515).
final class RefuseLiveFrame extends PairAction {
  const RefuseLiveFrame({required super.serial, required this.from, this.type})
    : super(actor: PairActor.link);

  final PairActor from;

  /// The protocol type refused; null refuses the next frame of the lane.
  final String? type;

  @override
  String describe() =>
      'a live frame from the ${from.name} refused'
      '${type == null ? '' : ' ($type)'}';
}

final class WristKilled extends PairAction {
  const WristKilled({required super.serial}) : super(actor: PairActor.wrist);

  @override
  String describe() => 'wrist app killed and relaunched';
}

final class TimeAdvances extends PairAction {
  TimeAdvances({required super.serial, required this.seconds})
    : assert(seconds >= 1 && seconds <= 90, 'D-14505: 1 s to 90 s'),
      super(actor: PairActor.time);

  final int seconds;

  @override
  String describe() => 'time advances ${seconds}s';
}

/// What a wrist engine is built from: the arguments [WatchPairHarness] hands a
/// [WristEngineFactory] instead of constructing the engine itself.
///
/// A factory that wants production behaviour calls [buildDefault]; a test that
/// needs a subclass (a `_MutationWrist` overriding `applyMessage`, say) passes
/// the same arguments to its own constructor.
class WristEngineArgs {
  const WristEngineArgs({
    required this.store,
    this.onEmit,
    this.validator,
    this.clock,
    this.idFactory,
    this.sessionIdFactory,
  });

  final InMemoryWatchSessionStore store;
  final WatchMessageSink? onEmit;
  final SyncProtocolValidator? validator;
  final DateTime Function()? clock;
  final String Function()? idFactory;
  final String Function()? sessionIdFactory;

  /// The engine the harness builds when no factory is injected.
  WatchSessionEngine buildDefault() => WatchSessionEngine(
    store,
    onEmit: onEmit,
    validator: validator,
    clock: clock,
    idFactory: idFactory,
    sessionIdFactory: sessionIdFactory,
  );
}

/// The seam a test uses to inject a [WatchSessionEngine] subclass: a factory
/// that receives the arguments the harness would have built the production
/// engine from.
typedef WristEngineFactory = WatchSessionEngine Function(WristEngineArgs args);

/// The phone half's clock: the pair clock's instant, made strictly monotone.
///
/// A standing pair clock mints the same `session-$nowMs` id twice when a
/// session is discarded and another started with no [TimeAdvances][] between,
/// and the runner's per-id bookkeeping (`phoneDiscardedSessions`, the
/// phone/wrist end maps) would then read the new session as the discarded one
/// (plan 169 D-16905). Each read is therefore at least one millisecond after
/// the last, never behind the grid instant; the drift stays far inside
/// [kEndSkewToleranceMs], so plan 161's same-instant ties stay ties.
///
/// [TimeAdvances]: HarnessRunner.perform
///
/// A phone relaunch (plan 163's `relaunchPhone`) must build its new
/// `WorkoutState` with `clock: _gridClock(clock)` too, or the rebuilt phone
/// falls back to the wall clock and the pair loses this seam (plan 169 D-16907).
DateTime Function() _gridClock(TestClock clock) {
  var lastMs = 0;
  return () {
    final gridMs = clock.now.millisecondsSinceEpoch;
    final nextMs = max(gridMs, lastMs + 1);
    lastMs = nextMs;
    return DateTime.fromMillisecondsSinceEpoch(nextMs);
  };
}

/// One phone and one wrist, joined by a [PairRadio] and a shared [TestClock].
class WatchPairHarness {
  WatchPairHarness._({
    required this.clock,
    required this.repository,
    required this.phone,
    required this.settings,
    required this.radio,
    required this.graph,
    required this.exercise,
    required this.failures,
    required this.validator,
    this.engineFactory,
    this.recordReplay = false,
  }) : gridStartMs = clock.now.millisecondsSinceEpoch {
    clockGrid.add(gridStartMs);
  }

  /// The instant both halves read.
  final TestClock clock;
  final MockWorkoutRepository repository;
  final WorkoutState phone;
  final SettingsState settings;
  final PairRadio radio;
  final WatchSyncGraph graph;

  /// The catalog exercise a phone session holds: one with `['time','distance']`
  /// capabilities, as plan 128's pair seeds.
  final Exercise exercise;

  /// Every failure either half's `onFailure` reported, in order.
  final List<Object> failures;
  final SyncProtocolValidator validator;

  /// The seam that builds the wrist's engine; null builds the production one.
  final WristEngineFactory? engineFactory;

  /// Whether the run records the wrist's input timeline — the frames it was
  /// handed, its own actions and its kills (plan 152 D-15201…D-15203).
  ///
  /// Off by default: with the switch off nothing is captured and every existing
  /// test runs exactly as it did.
  final bool recordReplay;

  /// The raw events recorded so far, in the order the wrist saw them. The
  /// canonicalizer runs at close (`ReplayRecording.capture`).
  final List<Map<String, Object?>> replayEvents = [];

  /// The instant the run's clock started at: the corpus's `gridStartMs`.
  final int gridStartMs;

  /// Every instant the run's own clock held. A timestamp on this grid is the
  /// run's own and records verbatim; an instant off it came from the phone's
  /// real clock and is aliased (D-15204).
  final Set<int> clockGrid = {};

  /// Notes the instant the clock holds now as part of the run's grid.
  void noteClockGrid() => clockGrid.add(clock.now.millisecondsSinceEpoch);

  final InMemoryWatchSessionStore _store = InMemoryWatchSessionStore();
  late WatchSessionEngine _engine;
  late WatchSessionStartPaths _paths;
  late WatchSyncOrchestrator _orchestrator;

  /// The engine the wrist is running now. A kill replaces it with a fresh one
  /// over the same store.
  WatchSessionEngine get wristEngine => _engine;
  WatchSessionStartPaths get wristPaths => _paths;
  WatchSyncOrchestrator get wristOrchestrator => _orchestrator;
  InMemoryWatchSessionStore get wristStore => _store;

  int _wristSessionSerial = 0;
  int _wristRecordSerial = 0;
  int _wristEntrySerial = 0;
  int _messageSerial = 0;
  int _slotSerial = 0;

  late final HarnessRunner runner = HarnessRunner(this);

  /// When true, [HarnessRunner.heal] does nothing but drain the OS queues: no
  /// reconnect sync, no resume trigger, no wrist frame, no re-offer window.
  ///
  /// A seam for proving that the heal's triggers are what delivers an owed end,
  /// not an accounting of the pair as it is. Production behaviour is false.
  bool drainOnlyHeal = false;

  /// Builds both halves the way the app does (D-14501): the shipping graph over
  /// a `MockWorkoutRepository`, and a real Dart engine over an in-memory store.
  static Future<WatchPairHarness> build({
    DateTime? start,
    String exerciseId = 'ex-run',
    String exerciseName = 'Run',
    List<String> capabilities = const ['time', 'distance'],
    WristEngineFactory? engineFactory,
    bool recordReplay = false,
  }) async {
    final clock = TestClock(start ?? DateTime.utc(2026, 11, 10, 9));
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await seedExercise(
      repository,
      id: exerciseId,
      name: exerciseName,
      capabilities: capabilities,
    );
    final phone = WorkoutState(repository, clock: _gridClock(clock));
    final settings = SettingsState(repository, fakePreferencesService());
    await settings.initialize();
    final failures = <Object>[];
    final validator = loadProtocolValidator();
    final radio = PairRadio(
      clock: clock,
      onFailure: (error, stack) => failures.add(error),
    );
    final graph = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: settings,
      transport: radio,
      clock: clock.call,
      frameClock: clock.call,
      onFailure: (error, stack) => failures.add(error),
      validator: validator,
    ))!;
    graph.adoption.bindWorkoutState(phone);
    graph.autoPush.bindWorkoutState(phone);
    graph.timerPush.bindWorkoutState(phone);

    final harness = WatchPairHarness._(
      clock: clock,
      repository: repository,
      phone: phone,
      settings: settings,
      radio: radio,
      graph: graph,
      exercise: Exercise(
        id: exerciseId,
        name: exerciseName,
        capabilities: capabilities,
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
      failures: failures,
      validator: validator,
      engineFactory: engineFactory,
      recordReplay: recordReplay,
    );
    await harness._launchWrist();
    return harness;
  }

  /// Builds the wrist's engine, paths and orchestrator over the held store, and
  /// binds the phone→wrist lane to them.
  Future<void> _launchWrist() async {
    final args = WristEngineArgs(
      store: _store,
      clock: clock.call,
      validator: validator,
      idFactory: () => 'rec-${++_wristRecordSerial}',
      sessionIdFactory: () => 's-w-${++_wristSessionSerial}',
      onEmit: radio.deliverFromWrist,
    );
    _engine = engineFactory?.call(args) ?? args.buildDefault();
    _paths = WatchSessionStartPaths(
      engine: _engine,
      store: _store,
      validator: validator,
      clock: clock.call,
      idFactory: () => 'rec-${++_wristRecordSerial}',
    );
    _orchestrator = WatchSyncOrchestrator(
      transport: _WristTransport(radio, this),
      paths: _paths,
      engine: _engine,
    );
    radio.bindWristInbound(_receiveOnWrist);
  }

  /// A kill models the app dying, not the data: a fresh engine over the same
  /// store, restored (D-14505).
  Future<void> relaunchWrist() async {
    await _launchWrist();
    await _engine.restore();
  }

  /// What a phone→wrist frame reaches: a request is answered, a message goes on
  /// to the wrist's own receiver.
  Future<void> _receiveOnWrist(Map<String, Object?> frame) async {
    final request = WatchTransportRequest.nameOf(frame);
    if (request == WatchTransportRequest.snapshot) {
      await _orchestrator.answerSnapshotRequest();
      return;
    }
    if (request != null) return;
    if (recordReplay && kReplayFrameTypes.contains(frame['type'])) {
      recordReplayFrame(frame);
    }
    try {
      await _orchestrator.receive(frame);
    } on WatchEmissionRejected catch (error, stack) {
      failures.add(error);
      radio.onFailure?.call(error, stack);
    }
  }

  /// The protocol slot the wrist starts a Free workout with.
  ///
  /// A fresh id per start, as the watch makes one (A-145-23): a reused slot id
  /// made two workouts share an effort id on the phone.
  Map<String, Object?> slot() => {
    'sessionExerciseId': 'sx-$exerciseId-${++_slotSerial}',
    'exerciseId': exercise.id,
    'name': exercise.name,
    'effortKind': 'timed',
    'capabilities': exercise.capabilities,
  };

  String get exerciseId => exercise.id;

  /// The phone's current session's efforts, in segment order.
  List<SegmentEffort> get phoneEfforts => [
    for (final segment in phone.segments)
      ...phone.getEffortsForSegment(segment.id),
  ];

  /// The frames of one protocol type that crossed, in order.
  List<PairFrame> framesOfType(String type) => radio.ofType(type);

  /// Lets every queued microtask settle — engine emissions, the graph's
  /// handlers, the link listeners — without waiting on real time.
  Future<void> settle() => pumpEventQueue();

  /// The message id of a frame this harness composes itself.
  String nextMessageId() => 'm-harness-${++_messageSerial}';

  /// The entry id of a set the wrist logs.
  String nextWristEntryId() => 'w-entry-${++_wristEntrySerial}';

  /// The ids the phone itself discarded. A discard leaves no row (plan 128
  /// D-7), so this record is what lets a check read the phone's own
  /// `abandoned` (D-14514).
  final Set<String> phoneDiscardedSessions = {};

  final Map<String, String> _sessionLabels = {};
  int _sessionLabelSerial = 0;

  /// The stable name a trace and a report use for [sessionId] — "session 1",
  /// "session 2", in order of first appearance.
  ///
  /// The phone mints its id from the real clock (A-145-02), so the raw id
  /// differs between two runs of the same actions. The label is what makes
  /// those runs comparable (A-145-06).
  String labelFor(String sessionId) => _sessionLabels.putIfAbsent(
    sessionId,
    () => 'session ${++_sessionLabelSerial}',
  );

  /// The label [sessionId] already has, without minting one.
  String? labelOf(String sessionId) => _sessionLabels[sessionId];

  /// Every session id the run has named, in first-appearance order.
  List<String> get sessionIds => _sessionLabels.keys.toList();

  // ── Recording (plan 152, D-15202) ────────────────────────────────────────

  /// Appends one replay event, stamped with the instant the run's clock holds.
  ///
  /// The payload is deep-copied: an event records what the wrist was handed,
  /// not a map the engine may still mutate.
  void _recordReplayEvent(
    String t, [
    Map<String, Object?> payload = const {},
  ]) {
    if (!recordReplay) return;
    noteClockGrid();
    replayEvents.add(
      PairRadio._copy({
        't': t,
        'clockMs': clock.now.millisecondsSinceEpoch,
        ...payload,
      }),
    );
  }

  /// Records the phone→wrist frame the wrist is about to receive.
  void recordReplayFrame(Map<String, Object?> frame) =>
      _recordReplayEvent('frame', {'envelope': frame});

  /// Records one wrist action, carrying exactly the arguments the harness
  /// passed the engine.
  void recordReplayAction(
    String name, {
    Object? modality,
    List<Map<String, Object?>>? exercises,
    Map<String, Object?>? event,
    String? kind,
  }) => _recordReplayEvent('action', {
    'name': name,
    'modality': ?modality,
    'exercises': ?exercises,
    'event': ?event,
    'kind': ?kind,
  });

  /// Records the wrist's process death — the one event with no arguments.
  void recordReplayKill() => _recordReplayEvent('kill');
}

/// The phone→wrist types the wrist's session surface consumes — the seven the
/// orchestrator routes to the engine (`watch_sync_orchestrator.dart:129-160`).
///
/// A request, `routines_down` and `foods_down` change no session state and are
/// not recorded (D-15202).
const Set<String> kReplayFrameTypes = {
  'exercise_push',
  'session_snapshot',
  'structure_change',
  'session_lifecycle',
  'timer_state',
  'receipt',
  'observations_up',
};

/// The action kinds that end or restart nothing: link flaps, refused frames,
/// app kills and time. S-14515's fixture space, shared with the random run's
/// allowed-actions seam.
const Set<Type> kNoSessionActions = {
  LinkDrops,
  LinkRises,
  RefuseLiveFrame,
  WristKilled,
  TimeAdvances,
};

/// The wrist's side of the radio, in the shape its orchestrator asks for.
class _WristTransport implements WatchSyncTransport {
  _WristTransport(this.radio, this.harness);

  final PairRadio radio;
  final WatchPairHarness harness;

  @override
  bool get isPhoneReachable => radio.reachable;

  @override
  Future<void> requestRoutines({DateTime? since}) =>
      radio.deliverFromWrist(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() =>
      radio.deliverFromWrist(WatchTransportRequest.snapshotFrame());

  @override
  Future<void> send(Map<String, Object?> envelope) =>
      radio.deliverFromWrist(envelope).then((_) {});
}

/// Performs [PairAction]s on the pair: the whole action set of D-14505 plus
/// D-14513's synthetic re-assert.
///
/// A phone action is followed by `graph.autoPush.flush()` and a settle; a wrist
/// action is followed by a settle, which is where its frames reach the phone.
class HarnessRunner {
  HarnessRunner(this.harness);

  final WatchPairHarness harness;

  int _serial = 0;

  /// The serial the last minted action carries.
  int get lastSerial => _serial;

  WatchPairHarness get pair => harness;
  PairRadio get radio => harness.radio;
  WorkoutState get phone => harness.phone;
  WatchSyncGraph get graph => harness.graph;
  TestClock get clock => harness.clock;

  int _next() => ++_serial;

  PhoneStartsSession phoneStartsSession() =>
      PhoneStartsSession(serial: _next());
  PhoneLogsSet phoneLogsSet({String? effortId}) =>
      PhoneLogsSet(serial: _next(), effortId: effortId);
  PhoneFinishes phoneFinishes() => PhoneFinishes(serial: _next());
  PhoneDiscards phoneDiscards() => PhoneDiscards(serial: _next());
  PhoneStartsRest phoneStartsRest({String? effortId}) =>
      PhoneStartsRest(serial: _next(), effortId: effortId);
  PhoneReassertsLive phoneReassertsLive() =>
      PhoneReassertsLive(serial: _next());
  WristStartsFreeWorkout wristStartsFreeWorkout() =>
      WristStartsFreeWorkout(serial: _next());
  WristLogsSet wristLogsSet() => WristLogsSet(serial: _next());
  WristFinishes wristFinishes() => WristFinishes(serial: _next());
  WristDiscards wristDiscards() => WristDiscards(serial: _next());
  WristStartsRest wristStartsRest() => WristStartsRest(serial: _next());
  LinkDrops linkDrops() => LinkDrops(serial: _next());
  LinkRises linkRises() => LinkRises(serial: _next());
  RefuseLiveFrame refuseNext({required PairActor from, String? type}) =>
      RefuseLiveFrame(serial: _next(), from: from, type: type);
  WristKilled wristKilled() => WristKilled(serial: _next());
  TimeAdvances advanceTime(int seconds) =>
      TimeAdvances(serial: _next(), seconds: seconds);

  /// The trace so far: numbered actions, the frames they carried, and the
  /// heal's rounds. Every line names sessions by [WatchPairHarness.labelFor], so
  /// two runs of the same actions read identically (A-145-06).
  final List<String> _trace = [];
  List<String> get trace => List.unmodifiable(_trace);
  String traceText() => _trace.join('\n');

  /// The status each side last reported, per session id (D-14514).
  final Map<String, String?> phoneStatuses = {};
  final Map<String, String?> wristStatuses = {};

  /// The entry ids each side has ever exposed, per session id (D-14514).
  final Map<String, Set<String>> phoneEntryIds = {};
  final Map<String, Set<String>> wristEntryIds = {};

  /// Every check-2 tripwire the run stepped on, in order (D-14507).
  final List<String> absorbingViolations = [];

  /// Entry ids a side exposed twice — check 3's "none twice".
  final List<String> entryDuplicates = [];

  /// The terminal status each side first reported, per session id: check 2's
  /// memory.
  final Map<String, String> _phoneEnds = {};
  final Map<String, String> _wristEnds = {};

  HealReport? _lastHeal;

  /// What the last [heal] did, or null when the run never healed.
  HealReport? get lastHeal => _lastHeal;

  /// Runs [action] and lets the pair settle.
  Future<void> perform(PairAction action) async {
    radio.actionSerial = action.serial;
    try {
      switch (action) {
        case PhoneStartsSession():
          await _phoneStartsSession();
        case PhoneLogsSet(:final effortId):
          await _phoneLogsSet(effortId);
        case PhoneFinishes():
          await _phoneFinishes();
        case PhoneDiscards():
          await _phoneDiscards();
        case PhoneStartsRest(:final effortId):
          await _phoneStartsRest(effortId);
        case PhoneReassertsLive():
          await _phoneReassertsLive();
        case WristStartsFreeWorkout():
          await _wristStartsFreeWorkout();
        case WristLogsSet():
          await _wristLogsSet();
        case WristFinishes():
          if (harness.wristEngine.session != null) {
            harness.recordReplayAction('finish');
            await harness.wristEngine.finishSession();
          }
        case WristDiscards():
          if (harness.wristEngine.session != null) {
            harness.recordReplayAction('discard');
            await harness.wristEngine.abandonSession();
          }
        case WristStartsRest():
          if (harness.wristEngine.session != null) {
            harness.recordReplayAction(
              'restStart',
              kind: WatchTimerKind.rest,
            );
            await harness.wristEngine.startTimer(WatchTimerKind.rest);
          }
        case LinkDrops():
          radio.setReachable(false);
        case LinkRises():
          radio.setReachable(true);
          await radio.drainQueues();
        case RefuseLiveFrame(:final from, :final type):
          _refuseNext(from, type);
        case WristKilled():
          harness.recordReplayKill();
          await harness.relaunchWrist();
        case TimeAdvances(:final seconds):
          clock.advance(Duration(seconds: seconds));
          harness.noteClockGrid();
      }
    } finally {
      await harness.settle();
      radio.actionSerial = null;
    }
    _recordAction(action);
    await _sample();
  }

  void _recordAction(PairAction action) {
    _trace.add('${action.serial}. ${action.describe()}');
    for (final frame in radio.frames) {
      if (frame.actionSerial != action.serial) continue;
      _trace.add('   ${_frameLine(frame)}');
    }
  }

  String _frameLine(PairFrame frame) {
    final id = frame.sessionId;
    final label = id == null ? '' : ' (${harness.labelFor(id)})';
    final lane = frame.lane == PairLane.phoneToWrist
        ? 'phone→wrist'
        : 'wrist→phone';
    return '$lane ${frame.type}$label ${frame.outcome.name}'
        '${frame.refused ? ' (refused)' : ''}'
        '${frame.drained ? ' (drained)' : ''}';
  }

  // ── The four checks (D-14507, read per D-14514) ──────────────────────────

  /// Samples both sides: who holds what, what each side reports, and check 2's
  /// absorbing-end tripwire. Runs after every action as well as after the heal.
  Future<void> _sample() async {
    final ids = <String>{
      if (phone.currentSession?.id != null) phone.currentSession!.id,
      if (harness.wristEngine.session?.sessionId != null)
        harness.wristEngine.session!.sessionId,
      for (final frame in radio.frames)
        if (frame.sessionId != null) frame.sessionId!,
    };
    for (final id in ids) {
      harness.labelFor(id);
    }
    for (final id in ids) {
      final wrist = await _wristStatusOf(id);
      final phoneStatus = await _phoneStatusOf(id);
      if (wrist != null) wristStatuses[id] = wrist;
      if (phoneStatus != null) phoneStatuses[id] = phoneStatus;
      _noteAbsorbingEnd('phone', id, phoneStatus, _phoneEnds);
      _noteAbsorbingEnd('wrist', id, wrist, _wristEnds);
    }
    await _sampleEntries();
  }

  /// Check 2: a session that was ever `completed` or `abandoned` on one side is
  /// never `active` there again (D-14507, "absorbing end").
  void _noteAbsorbingEnd(
    String side,
    String sessionId,
    String? status,
    Map<String, String> ends,
  ) {
    if (status == null) return;
    final label = harness.labelFor(sessionId);
    if (status == WatchSessionStatus.active) {
      final ended = ends[sessionId];
      if (ended != null) {
        absorbingViolations.add(
          '$label was $ended on the $side and reports active again',
        );
      }
      return;
    }
    ends.putIfAbsent(sessionId, () => status);
  }

  /// The phone's status for [sessionId] (D-14514): `completed` when the row is
  /// ended, `abandoned` when the row is gone after a discard, `active` while an
  /// un-ended row exists — whether or not it is the session on screen.
  ///
  /// A discard is not only the phone's own: a wrist abandon deletes the phone's
  /// row through the mirror, and the phone then holds nothing at all. A session
  /// this run saw the phone hold and the phone no longer holds was ended by a
  /// discard, so it reads `abandoned` — reading `null` here left the stale
  /// `active` sample in place and reported a mismatch the pair does not have
  /// (A-145-16).
  ///
  /// An un-ended row the phone has moved on from is a session it still holds:
  /// the phone kept the wrist-started session while it started its own, or an
  /// adoption replaced the session on screen. It reads `active`, and the checks
  /// decide whether that agrees with the wrist (A-145-20). Reading `null` made
  /// the phone answer "not held" for a row it has.
  Future<String?> _phoneStatusOf(String sessionId) async {
    final row = await harness.repository.getSession(sessionId);
    if (row?.endedAtMs != null) {
      // D-16104: the phone's own row end. It is stamped by the app's wall clock,
      // which no seam reaches (A-161-05); a discard's instant is the pair clock
      // in `_phoneDiscards`, so the two ends are not comparable — the tie below
      // simply never fires across them.
      phoneEndAtMs.putIfAbsent(sessionId, () => row!.endedAtMs!);
      return WatchSessionStatus.completed;
    }
    if (row == null) {
      if (harness.phoneDiscardedSessions.contains(sessionId) ||
          _phoneHeld.contains(sessionId)) {
        return WatchSessionStatus.abandoned;
      }
      return null;
    }
    _phoneHeld.add(sessionId);
    return WatchSessionStatus.active;
  }

  /// The sessions this run saw the phone hold as its current session.
  final Set<String> _phoneHeld = {};

  /// Each side's end instant for a session, in ms (D-16104): the phone's from its
  /// discard or its ended row, the wrist's from the row the end was written on
  /// (`recordedAt`, the engine's own clock). Read only by the within-tolerance
  /// tie (D-16105); a session with no entry has an unknown instant, and a
  /// disagreement about it stays a mismatch.
  final Map<String, int> phoneEndAtMs = {};
  final Map<String, int> wristEndAtMs = {};

  /// The wrist's status for [sessionId]: the held session's own (the engine
  /// holds one at a time); for a session the wrist has moved on from, the status
  /// of its newest stored row (the wrist keeps every row, so an end applied while
  /// it held another session is still readable); null when the wrist never held
  /// it. Reading only the held session missed an owed end applied after the
  /// wrist moved on, which read as "still active" (plan 146, F-5).
  Future<String?> _wristStatusOf(String sessionId) async {
    final session = harness.wristEngine.session;
    if (session != null && session.sessionId == sessionId) {
      _noteWristEnd(sessionId, session.status, session.recordedAt);
      return session.status;
    }
    final stored = await harness.wristStore.readAll();
    WatchSessionRecord? newest;
    for (final row in stored.sessions) {
      if (row.sessionId == sessionId) newest = row;
    }
    if (newest == null) return null;
    _noteWristEnd(sessionId, newest.status, newest.recordedAt);
    return newest.status;
  }

  /// D-16104: the wrist's end instant is the `recordedAt` of the row that carried
  /// its terminal status — the engine's clock at that write, which in the harness
  /// is the pair's clock. Sampling runs after every action, so the first sample
  /// that sees a terminal status is the one the end was written on. An active row
  /// records nothing, and [Map.putIfAbsent] keeps the first end seen.
  void _noteWristEnd(String sessionId, String status, DateTime recordedAt) {
    final terminal =
        status == WatchSessionStatus.completed ||
        status == WatchSessionStatus.abandoned;
    if (!terminal) return;
    wristEndAtMs.putIfAbsent(sessionId, () => recordedAt.millisecondsSinceEpoch);
  }

  Future<void> _sampleEntries() async {
    // What the phone itself recorded of the wrist's entries: the inbox stages
    // every one under the wrist's own `entryId`, and nothing prunes it, so a
    // wrist entry the phone received counts as held even when no snapshot and
    // no mirror state still carries it (A-145-18). The wrist's `entryId` is the
    // id space of the wrist's `entries`, so the two sets compare directly.
    for (final id in harness.sessionIds) {
      final inbox = await harness.repository.getWatchInboxEntriesForSession(id);
      if (inbox.isEmpty) continue;
      _addEntries(phoneEntryIds, id, [
        for (final entry in inbox)
          // D-16101 (plan 158 §3): the phone stages its own rating, correction
          // and deletion annotations in the same inbox under
          // `phone-change-*`. They are phone records *about* a wrist entry, so
          // they can never be a wrist entry check 3 expects the wrist to hold.
          if (!WatchInboxEntry.phoneKinds.contains(entry.kind)) entry.entryId,
      ]);
    }
    final mirrorState = harness.graph.mirror.state;
    final mirrorId = mirrorState['sessionId'];
    if (mirrorId is String && mirrorId.isNotEmpty) {
      final ids = _entryIdsOf(mirrorState['entries']);
      _addEntries(phoneEntryIds, mirrorId, ids);
      _noteDuplicates('phone', mirrorId, ids);
    }
    final projected = await harness.graph.mirror.projectedSession();
    if (projected != null) {
      final id = projected['sessionId'];
      if (id is String && id.isNotEmpty) {
        final ids = _entryIdsOf(projected['entries']);
        _addEntries(phoneEntryIds, id, ids);
        _noteDuplicates('phone', id, ids);
      }
    }
    // The wrist's whole store, not only its current session's projection
    // (D-14605): an entry merged for a session the wrist has already ended is
    // held even though `entries` reads the session the wrist is on now.
    final stored = await harness.wristStore.readAll();
    for (final observation in stored.observations) {
      _addEntries(wristEntryIds, observation.sessionId, [observation.entryId]);
    }
    final wrist = harness.wristEngine.session;
    if (wrist != null) {
      final ids = [
        for (final entry in harness.wristEngine.entries) entry.entryId,
      ];
      _addEntries(wristEntryIds, wrist.sessionId, ids);
      _noteDuplicates('wrist', wrist.sessionId, ids);
    }
    for (final frame in radio.frames) {
      final id = frame.sessionId;
      if (id == null) continue;
      switch (frame.frame['type']) {
        case 'session_snapshot':
          final ids = _entryIdsOf(_payload(frame.frame)['entries']);
          if (frame.lane == PairLane.wristToPhone) {
            _addEntries(wristEntryIds, id, ids);
          } else {
            _addEntries(phoneEntryIds, id, ids);
          }
        case 'observations_up':
          final eventIds = _eventIdsOf(_payload(frame.frame)['events']);
          _addEntries(wristEntryIds, id, eventIds);
        default:
          break;
      }
    }
  }

  void _addEntries(
    Map<String, Set<String>> union,
    String sessionId,
    List<String> ids,
  ) {
    if (ids.isEmpty) return;
    union.putIfAbsent(sessionId, () => <String>{}).addAll(ids);
  }

  void _noteDuplicates(String side, String sessionId, List<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        final line =
            '${harness.labelFor(sessionId)}: the $side exposed $id twice';
        if (!entryDuplicates.contains(line)) entryDuplicates.add(line);
      }
    }
  }

  static List<String> _entryIdsOf(Object? entries) => [
    if (entries is List)
      for (final entry in entries)
        if (entry is Map && entry['entryId'] is String)
          entry['entryId'] as String,
  ];

  static List<String> _eventIdsOf(Object? events) => [
    if (events is List)
      for (final event in events)
        if (event is Map && event['entryId'] is String)
          event['entryId'] as String,
  ];

  static Map<String, Object?> _payload(Map<String, Object?> frame) {
    final payload = frame['payload'];
    return payload is Map ? payload.cast<String, Object?>() : const {};
  }

  // ── The heal (D-14506) ───────────────────────────────────────────────────

  /// The most rounds the heal runs before it calls the pair unconverged.
  static const int healRoundLimit = 10;

  /// Brings the pair together the way the app does (D-14506): link up, drain
  /// the queue, the wrist's reconnect sync, the phone's resume trigger, and one
  /// wrist `energy_live` frame — the frame that re-offers an owed end — repeated
  /// until a round carries no new state, bounded at [healRoundLimit].
  ///
  /// The clock moves 31 s before every round: the phone re-offers an owed end at
  /// most once per 30 s per session (plan 128 D-1 iv). With
  /// [WatchPairHarness.drainOnlyHeal] set, the heal only drains the queues.
  Future<HealReport> heal() async {
    radio.actionSerial = null;
    if (harness.drainOnlyHeal) {
      final before = radio.frames.length;
      await radio.drainQueues();
      await harness.settle();
      final frames = radio.frames.sublist(before);
      _trace.add('heal round 1 (drain only)');
      for (final frame in frames) {
        _trace.add('   ${_frameLine(frame)}');
      }
      final drainOnly = HealReport(
        rounds: [HealRound(round: 1, frames: frames)],
        converged: true,
      );
      _lastHeal = drainOnly;
      await _sample();
      return drainOnly;
    }
    if (!radio.reachable) radio.setReachable(true);
    await harness.settle();
    final rounds = <HealRound>[];
    var converged = false;
    var previous = '';
    for (var round = 1; round <= healRoundLimit; round++) {
      clock.advance(const Duration(seconds: 31));
      harness.noteClockGrid();
      final before = radio.frames.length;
      await radio.drainQueues();
      await harness.wristOrchestrator.sync(reconnect: true);
      await graph.sync();
      await harness.settle();
      await _injectEnergyFrame();
      await harness.settle();
      final frames = radio.frames.sublist(before);
      rounds.add(HealRound(round: round, frames: frames));
      _trace.add('heal round $round');
      for (final frame in frames) {
        _trace.add('   ${_frameLine(frame)}');
      }
      // The fixed point is a round after which both sides observe exactly what
      // they observed the round before: the same statuses, the same entry ids,
      // the same timer states (A-145-17). Counting frames instead never
      // settles, because a healthy pair re-offers the same state with a fresh
      // `messageId` for as long as the heal keeps asking.
      final state = await _observableState();
      if (round > 1 && state == previous) {
        converged = true;
        break;
      }
      previous = state;
    }
    final report = HealReport(rounds: rounds, converged: converged);
    _lastHeal = report;
    await _sample();
    return report;
  }

  /// One wrist `energy_live` frame, shaped as the wrist's live holder sends it
  /// (`test/watch_session_end_owed_test.dart`'s `_energyFrame`). The phone's
  /// router re-offers an owed end for the session it names.
  Future<void> _injectEnergyFrame() async {
    final sessionId =
        harness.wristEngine.session?.sessionId ?? phone.currentSession?.id;
    if (sessionId == null) return;
    final stamp = utcIso(clock.now);
    await radio.deliverFromWrist({
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': harness.nextMessageId(),
      'sessionId': sessionId,
      'type': 'energy_live',
      'origin': 'watch',
      'sentAt': stamp,
      'payload': <String, Object?>{'activeEnergyKcal': 12.5, 'at': stamp},
    });
  }

  /// What both sides observably hold right now: each session's status on each
  /// side, both entry-id sets, and both timer maps — the readings D-14514
  /// defines, so two rounds that compare equal leave the four checks with
  /// nothing new to say (A-14517).
  ///
  /// Frames are not part of it on purpose: a healthy pair re-offers the same
  /// state with a fresh `messageId`, and the exchange would never settle.
  Future<String> _observableState() async {
    await _sample();
    final parts = <String>[];
    for (final id in harness.sessionIds) {
      final phoneIds = (phoneEntryIds[id] ?? const <String>{}).toList()..sort();
      final wristIds = (wristEntryIds[id] ?? const <String>{}).toList()..sort();
      parts.add(
        '${harness.labelFor(id)}'
        ' phone=${phoneStatuses[id]}'
        ' wrist=${wristStatuses[id]}'
        ' phoneEntries=${phoneIds.join(',')}'
        ' wristEntries=${wristIds.join(',')}'
        ' phoneTimers=${_timerSignature('phone', id)}'
        ' wristTimers=${_timerSignature('wrist', id)}',
      );
    }
    return parts.join(' | ');
  }

  /// A side's timers for [sessionId] as `kind:state` pairs, sorted by kind: the
  /// part of a timer the checks read.
  String _timerSignature(String side, String sessionId) {
    final timers = _timersOn(side, sessionId);
    final kinds = timers.keys.toList()..sort();
    return [
      for (final kind in kinds)
        '$kind:${timers[kind] is Map ? (timers[kind] as Map)['state'] : null}',
    ].join(',');
  }

  // ── Convergence (D-14507) ────────────────────────────────────────────────

  /// The four checks after a [heal], plus the timer count that is measured and
  /// never asserted.
  Future<ConvergenceReport> checkConvergence() async {
    await _sample();
    // Sorted by label so two processes reading the same run report the same
    // order: the raw ids carry the phone's clock (A-145-02, A-145-06).
    final ids = harness.sessionIds.toList()
      ..sort((a, b) => harness.labelFor(a).compareTo(harness.labelFor(b)));
    final statusMismatches = <String>[];
    final timerViolations = <String>[];
    final entryMismatches = <String>[];
    final phoneOnlySessions = <String>[];
    final wristOnlySessions = <String>[];
    final withinSkewEndTies = <String>[];
    var timerDisagreements = 0;
    for (final id in ids) {
      final label = harness.labelFor(id);
      final phoneStatus = phoneStatuses[id];
      final wristStatus = wristStatuses[id];
      final phoneHeld = phoneStatuses.containsKey(id);
      final wristHeld = wristStatuses.containsKey(id);
      // A session only one side ever held is not a disagreement to assert: the
      // phone refused to adopt a wrist-started workout because it already had
      // one, and the workout never reached it (A-145-21). It is reported as a
      // count so the gap is visible, and left out of checks 1 and 3.
      final shared = phoneHeld && wristHeld;
      if (!shared) {
        if (phoneHeld) phoneOnlySessions.add(label);
        if (wristHeld) wristOnlySessions.add(label);
      }
      if (shared && phoneStatus != wristStatus) {
        // D-16105: the two ends are the same instant within the protocol's skew
        // tolerance — the wrist finished milliseconds before the phone's discard
        // frame landed, so neither side held a disagreeing status in the end.
        // Reported as a tie, not a failure; the owner confirms whether that is
        // convergence (A-161-04).
        if (_terminalTie(id, phoneStatus, wristStatus)) {
          withinSkewEndTies.add(label);
        } else {
          statusMismatches.add(
            '$label: phone ${phoneStatus ?? 'not held'} '
            'vs wrist ${wristStatus ?? 'not held'}',
          );
        }
      }
      final ended = _endedStatus(phoneStatus, wristStatus);
      if (ended != null) {
        for (final side in const ['phone', 'wrist']) {
          if (_runningRest(_timersOn(side, id))) {
            timerViolations.add(
              '$label: a rest timer runs on the $side although the session '
              'is $ended',
            );
          }
        }
      } else if (phoneStatus == WatchSessionStatus.active ||
          wristStatus == WatchSessionStatus.active) {
        timerDisagreements += _timerDisagreements(id);
      }
      if (!shared) continue;
      // A discarded workout is deleted with its sets (owner O-7, plan 146c
      // D-14632): nothing it held is owed to the other side, so check 3 does
      // not apply to a session either side reads `abandoned`. Seed 857's
      // phone set, logged on a workout the phone then discarded, is this case
      // (plan 151 investigation A2, reclassified).
      if (phoneStatus == WatchSessionStatus.abandoned ||
          wristStatus == WatchSessionStatus.abandoned) {
        continue;
      }
      final phoneIds = phoneEntryIds[id] ?? const <String>{};
      final wristIds = wristEntryIds[id] ?? const <String>{};
      final missingOnWrist = phoneIds.difference(wristIds).toList()..sort();
      final missingOnPhone = wristIds.difference(phoneIds).toList()..sort();
      if (missingOnWrist.isNotEmpty) {
        entryMismatches.add(
          '$label: the wrist never held ${missingOnWrist.join(', ')}',
        );
      }
      if (missingOnPhone.isNotEmpty) {
        entryMismatches.add(
          '$label: the phone never held ${missingOnPhone.join(', ')}',
        );
      }
    }
    final report = ConvergenceReport(
      sessionCount: ids.length,
      phoneStatus: {
        for (final id in ids) harness.labelFor(id): phoneStatuses[id],
      },
      wristStatus: {
        for (final id in ids) harness.labelFor(id): wristStatuses[id],
      },
      statusMismatches: statusMismatches,
      absorbingViolations: List.of(absorbingViolations),
      entryMismatches: entryMismatches,
      entryDuplicates: List.of(entryDuplicates),
      timerViolations: timerViolations,
      timerDisagreements: timerDisagreements,
      phoneOnlySessions: phoneOnlySessions,
      wristOnlySessions: wristOnlySessions,
      withinSkewEndTies: withinSkewEndTies,
      healRounds: _lastHeal?.rounds.length ?? 0,
      healConverged: _lastHeal?.converged ?? false,
    );
    _trace.add('check: ${report.converged ? 'converged' : 'DIVERGED'}');
    return report;
  }

  static String? _endedStatus(String? phone, String? wrist) {
    for (final status in [phone, wrist]) {
      if (_isTerminal(status)) return status;
    }
    return null;
  }

  static bool _isTerminal(String? status) =>
      status == WatchSessionStatus.completed ||
      status == WatchSessionStatus.abandoned;

  /// D-16105: whether a status disagreement is two ends of the same instant —
  /// one side finished, the other discarded, and the protocol's skew tolerance
  /// (D-15403) cannot tell the two orders apart. Both statuses must be terminal
  /// and both instants known (D-16104); anything else is a real mismatch.
  bool _terminalTie(String id, String? phoneStatus, String? wristStatus) {
    if (!_isTerminal(phoneStatus) || !_isTerminal(wristStatus)) return false;
    final phoneMs = phoneEndAtMs[id];
    final wristMs = wristEndAtMs[id];
    if (phoneMs == null || wristMs == null) return false;
    return endsWithinSkewToleranceMs(phoneMs, wristMs);
  }

  /// That side's timers for [sessionId], empty when the side holds another
  /// session: a timer belongs to the session it was started in.
  Map<String, Object?> _timersOn(String side, String sessionId) {
    if (side == 'phone') {
      final state = harness.graph.mirror.state;
      if (state['sessionId'] != sessionId) return const {};
      final timers = state['timers'];
      return timers is Map ? timers.cast<String, Object?>() : const {};
    }
    final session = harness.wristEngine.session;
    if (session == null || session.sessionId != sessionId) return const {};
    final snapshot = harness.wristEngine.sessionSnapshot();
    if (snapshot == null) return const {};
    final timers = _payload(snapshot)['timers'];
    return timers is Map ? timers.cast<String, Object?>() : const {};
  }

  static bool _runningRest(Map<String, Object?> timers) {
    final rest = timers[WatchTimerKind.rest];
    return rest is Map && rest['state'] == WatchTimerState.running;
  }

  /// The timer tally (D-14507): a kind both sides hold with a different state
  /// or start is a disagreement. Counted, never asserted — the owner decides
  /// timer ownership from the measurement.
  int _timerDisagreements(String sessionId) {
    final phoneTimers = _timersOn('phone', sessionId);
    final wristTimers = _timersOn('wrist', sessionId);
    var count = 0;
    for (final kind in WatchTimerKind.all) {
      final wrist = wristTimers[kind];
      final phoneTimer = phoneTimers[kind];
      if (wrist is Map && phoneTimer is Map) {
        if (wrist['state'] != phoneTimer['state'] ||
            wrist['startedAt'] != phoneTimer['startedAt']) {
          count++;
        }
      }
    }
    return count;
  }

  void _refuseNext(PairActor from, String? type) {
    final lane = from == PairActor.wrist
        ? PairLane.wristToPhone
        : PairLane.phoneToWrist;
    final previous = radio.refuseWhen;
    radio.refuseWhen = (crossedLane, frame) {
      if (previous?.call(crossedLane, frame) ?? false) return true;
      if (crossedLane != lane) return false;
      if (type != null && frame['type'] != type) return false;
      radio.refuseWhen = previous;
      return true;
    };
  }

  /// The phone's Home button, twice: a start while a session is open is a
  /// no-op, not a replacement — the shipping home screen offers Resume while a
  /// session is open, so the action must not overwrite it (A-145-19).
  Future<void> _phoneStartsSession() async {
    if (phone.currentSession != null) {
      await harness.settle();
      return;
    }
    await phone.createNewSession();
    await phone.addExerciseToSession(harness.exercise);
    await graph.autoPush.flush();
    await harness.settle();
  }

  Future<void> _phoneLogsSet(String? effortId) async {
    final effort = _resolvePhoneEffort(effortId);
    if (effort == null) return;
    // The entry the phone writes next is numbered above every number the
    // effort already holds (`EntryRows.nextNumber`), so the sets the wrist
    // logged and the phone imported are counted, not overwritten.
    final observations = await harness.repository.getEffortObservations(
      effort.id,
    );
    final index = switch (effort.effortKind) {
      'round' => (await harness.repository.getRoundInstances(effort.id)).length,
      'timed' ||
      'drill' => (await harness.repository.getTimedInstances(effort.id)).length,
      _ => EntryRows.setGroups(observations).length,
    };
    if (observations.isEmpty) {
      await phone.seedFirstEntry(effort.id);
    } else {
      await phone.addEntry(effort.id);
    }
    switch (effort.effortKind) {
      case 'round':
        await phone.setRoundDuration(effort.id, index, 30);
      case 'timed' || 'drill':
        await phone.setTimedEntryDuration(effort.id, index, 300);
      default:
        await phone.updateEntryValue(effort.id, index, 'reps', 5 + index);
    }
    // A set is logged exactly when a rest sits below it (D-1): without the
    // rest the projection reads the new group as a planned value and leaves it
    // out (`EntryRows.loggedSetNumbersOf`).
    await phone.recordRestStart(effort.id, index + 1);
    await graph.autoPush.flush();
    await harness.settle();
  }

  Future<void> _phoneFinishes() async {
    if (phone.currentSession == null) return;
    await phone.endSession(writeToHealth: false);
    await graph.autoPush.flush();
    await harness.settle();
  }

  Future<void> _phoneDiscards() async {
    final sessionId = phone.currentSession?.id;
    if (sessionId == null) return;
    // The shipping UI offers no discard for a workout that has ended — the
    // summary screen follows an end (A-145-22).
    if (phone.currentSession?.endedAtMs != null) return;
    // D-16104: the pair clock is the only instant a discarded row leaves behind —
    // the discard deletes the row rather than stamping it.
    phoneEndAtMs.putIfAbsent(
      sessionId,
      () => clock.now.millisecondsSinceEpoch,
    );
    await phone.discardCurrentSession();
    harness.phoneDiscardedSessions.add(sessionId);
    await graph.autoPush.flush();
    await harness.settle();
  }

  Future<void> _phoneStartsRest(String? effortId) async {
    final effort = _resolvePhoneEffort(effortId);
    if (effort == null) return;
    await phone.recordRestStart(effort.id, 0);
    await graph.timerPush.flush();
    await graph.autoPush.flush();
    await harness.settle();
  }

  Future<void> _phoneReassertsLive() async {
    final sessionId = phone.currentSession?.id;
    if (sessionId == null) return;
    final stamp = utcIso(clock.now);
    await radio.send({
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': harness.nextMessageId(),
      'sessionId': sessionId,
      'type': 'session_lifecycle',
      'origin': 'phone',
      'sentAt': stamp,
      'payload': {'state': WatchLifecycleState.started, 'at': stamp},
    });
    await harness.settle();
  }

  /// The wrist's Start button: while a session is running the wrist shows that
  /// session, so a second start keeps it (S-14513 — a start after an end is a
  /// new workout, and the engine's `createSession` already allows that).
  Future<void> _wristStartsFreeWorkout() async {
    final held = harness.wristEngine.session;
    if (held != null && held.status == WatchSessionStatus.active) {
      await harness.settle();
      return;
    }
    final exercises = [harness.slot()];
    harness.recordReplayAction('start', exercises: exercises);
    await harness.wristEngine.createSession(
      modality: null,
      exercises: exercises,
    );
    await harness.settle();
  }

  Future<void> _wristLogsSet() async {
    final engine = harness.wristEngine;
    final session = engine.session;
    if (session == null) return;
    final slot = session.exercises.isEmpty ? null : session.exercises.first;
    final slotId = slot?['sessionExerciseId'];
    if (slotId is! String) return;
    final entryId = harness.nextWristEntryId();
    final end = clock.now;
    final start = end.subtract(const Duration(minutes: 3));
    final kind = switch (slot?['effortKind']) {
      'timed' || 'drill' => WatchObservationKind.timed,
      'round' => WatchObservationKind.round,
      'hold' => WatchObservationKind.hold,
      _ => WatchObservationKind.set,
    };
    final event = <String, Object?>{
      'entryId': entryId,
      'eventId': entryId,
      'kind': kind,
      'loggedAt': utcIso(end),
      'sessionExerciseId': slotId,
      'exerciseId': harness.exerciseId,
      if (kind == WatchObservationKind.set) ...{
        'reps': 5,
        'loadKg': 60.0,
      } else ...{
        'startedAt': utcIso(start),
        'endedAt': utcIso(end),
        if (kind == WatchObservationKind.round) 'roundNumber': 1,
      },
    };
    harness.recordReplayAction('logSet', event: event);
    await engine.appendObservation(event);
    await harness.settle();
  }

  SegmentEffort? _resolvePhoneEffort(String? effortId) {
    final efforts = harness.phoneEfforts;
    if (efforts.isEmpty) return null;
    if (effortId == null) return efforts.first;
    for (final effort in efforts) {
      if (effort.id == effortId) return effort;
    }
    return efforts.first;
  }
}

/// One run of the pair: the actions it performed, the trace they read as, and
/// the four checks' report (D-14503, D-14509, D-14510).
///
/// It lives in the harness rather than in a test file so the random run and
/// every scripted replay share one implementation (A-145-09).
class ConvergenceRun {
  ConvergenceRun._({
    required this.seed,
    required this.actions,
    required this.pair,
    required this.heal,
    required this.report,
  });

  /// The seed the actions were generated from; -1 for a replayed action list
  /// that no seed produced.
  final int seed;

  /// The actions performed, in order. Immutable value objects, so the list can
  /// be replayed as often as a shrinker likes.
  final List<PairAction> actions;

  final WatchPairHarness pair;
  final HealReport heal;
  final ConvergenceReport report;

  HarnessRunner get runner => pair.runner;

  /// The numbered actions, the frames they carried and the heal's rounds.
  String get trace => runner.traceText();

  bool get converged => report.converged;

  List<String> get failures => report.failures;

  /// Whether any action of this run is one the shipping app cannot perform
  /// (D-14513). That action is the only one allowed to diverge by design.
  bool get usedSyntheticAction => actions.any((action) => action.synthetic);

  /// The shortest and longest trace a seeded run may be (D-14510).
  static const int minLength = 8;
  static const int maxLength = 40;

  /// Runs one seed: one [Random] drives every choice — the trace length, which
  /// action each step is, the fault a refusal fires on, the time each step
  /// advances (D-14503). Then the heal and the four checks.
  ///
  /// [allowedActions] restricts which action kinds the generator may produce;
  /// null allows all of them. An empty or unusable set throws rather than
  /// silently generating nothing (the fixture-space seam).
  ///
  /// [engineFactory] builds the wrist's engine (the mutation seam S-14508);
  /// [drainOnlyHeal] makes the heal one queue drain (the mutation seam
  /// S-14509). Both default to the production behaviour.
  static Future<ConvergenceRun> runSeed(
    int seed, {
    Set<Type>? allowedActions,
    int? length,
    WristEngineFactory? engineFactory,
    bool drainOnlyHeal = false,
    bool recordReplay = false,
  }) async {
    final random = Random(seed);
    final steps =
        length ?? (minLength + random.nextInt(maxLength - minLength + 1));
    final pair = await WatchPairHarness.build(
      engineFactory: engineFactory,
      recordReplay: recordReplay,
    );
    pair.drainOnlyHeal = drainOnlyHeal;
    final runner = pair.runner;
    final actions = <PairAction>[];
    for (var step = 0; step < steps; step++) {
      final action = _mint(random, runner, allowedActions);
      actions.add(action);
      await runner.perform(action);
    }
    return _finish(seed: seed, actions: actions, pair: pair);
  }

  /// Performs exactly [actions] on a fresh pair, then the heal and the checks.
  /// The serials stay as given, so a replayed trace numbers the same way.
  ///
  /// [engineFactory] and [drainOnlyHeal] are [runSeed]'s mutation seams, so a
  /// shrunk trace replays under the same mutation that made it fail.
  static Future<ConvergenceRun> replayActions(
    List<PairAction> actions, {
    int seed = -1,
    WristEngineFactory? engineFactory,
    bool drainOnlyHeal = false,
    bool recordReplay = false,
  }) async {
    final pair = await WatchPairHarness.build(
      engineFactory: engineFactory,
      recordReplay: recordReplay,
    );
    pair.drainOnlyHeal = drainOnlyHeal;
    final runner = pair.runner;
    for (final action in actions) {
      await runner.perform(action);
    }
    return _finish(
      seed: seed,
      actions: List<PairAction>.of(actions),
      pair: pair,
    );
  }

  static Future<ConvergenceRun> _finish({
    required int seed,
    required List<PairAction> actions,
    required WatchPairHarness pair,
  }) async {
    final heal = await pair.runner.heal();
    final report = await pair.runner.checkConvergence();
    return ConvergenceRun._(
      seed: seed,
      actions: List.unmodifiable(actions),
      pair: pair,
      heal: heal,
      report: report,
    );
  }

  /// The action kinds this generator can produce, with the weight each is
  /// drawn by: sessions happen often, endings more often than discards, and
  /// link faults often enough to matter (D-14510).
  static List<_ActionOption> _options(Random random, HarnessRunner runner) => [
    _ActionOption(PhoneStartsSession, 8, runner.phoneStartsSession),
    _ActionOption(PhoneLogsSet, 10, () => runner.phoneLogsSet()),
    _ActionOption(PhoneFinishes, 6, runner.phoneFinishes),
    _ActionOption(PhoneDiscards, 4, runner.phoneDiscards),
    _ActionOption(PhoneStartsRest, 4, () => runner.phoneStartsRest()),
    _ActionOption(PhoneReassertsLive, 2, runner.phoneReassertsLive),
    _ActionOption(WristStartsFreeWorkout, 5, runner.wristStartsFreeWorkout),
    _ActionOption(WristLogsSet, 10, runner.wristLogsSet),
    _ActionOption(WristFinishes, 5, runner.wristFinishes),
    _ActionOption(WristDiscards, 3, runner.wristDiscards),
    _ActionOption(WristStartsRest, 3, runner.wristStartsRest),
    _ActionOption(LinkDrops, 8, runner.linkDrops),
    _ActionOption(LinkRises, 5, runner.linkRises),
    _ActionOption(RefuseLiveFrame, 6, () {
      final from = random.nextBool() ? PairActor.phone : PairActor.wrist;
      // The types a lane actually carries; null refuses its next frame of any
      // type, which is what a transient radio failure looks like.
      final types = from == PairActor.phone
          ? const ['session_snapshot', 'session_lifecycle', 'timer_state']
          : const ['observations_up', 'session_lifecycle', 'session_snapshot'];
      final roll = random.nextInt(types.length + 1);
      return runner.refuseNext(
        from: from,
        type: roll == types.length ? null : types[roll],
      );
    }),
    _ActionOption(WristKilled, 3, runner.wristKilled),
    _ActionOption(
      TimeAdvances,
      6,
      () => runner.advanceTime(1 + random.nextInt(90)),
    ),
  ];

  /// Mints one action by weight, from the kinds [allowedActions] permits.
  static PairAction _mint(
    Random random,
    HarnessRunner runner,
    Set<Type>? allowedActions,
  ) {
    final options = _options(random, runner);
    final allowed = allowedActions == null
        ? options
        : [
            for (final option in options)
              if (allowedActions.contains(option.type)) option,
          ];
    if (allowed.isEmpty) {
      throw ArgumentError.value(
        allowedActions,
        'allowedActions',
        'no action kind the generator can produce is allowed',
      );
    }
    var roll = random.nextInt(allowed.fold(0, (sum, o) => sum + o.weight));
    for (final option in allowed) {
      if (roll < option.weight) return option.mint();
      roll -= option.weight;
    }
    return allowed.last.mint();
  }
}

/// One action kind the seeded generator may produce: its type (what the
/// fixture-space seam filters on), its weight, and how to mint one.
class _ActionOption {
  const _ActionOption(this.type, this.weight, this.mint);

  final Type type;
  final int weight;
  final PairAction Function() mint;
}

/// One round of the heal: the frames it carried, in order (D-14506).
class HealRound {
  const HealRound({required this.round, required this.frames});

  final int round;
  final List<PairFrame> frames;

  /// The frames this round carried in [PairLane.phoneToWrist].
  List<PairFrame> get phoneFrames => [
    for (final frame in frames)
      if (frame.lane == PairLane.phoneToWrist) frame,
  ];

  /// The frames this round carried in [PairLane.wristToPhone].
  List<PairFrame> get wristFrames => [
    for (final frame in frames)
      if (frame.lane == PairLane.wristToPhone) frame,
  ];

  @override
  String toString() => 'round $round: ${frames.length} frames';
}

/// What [HarnessRunner.heal] did: every round, and whether a round carried no
/// new state.
class HealReport {
  const HealReport({required this.rounds, required this.converged});

  final List<HealRound> rounds;
  final bool converged;

  @override
  String toString() =>
      'heal ${converged ? 'converged' : 'did not converge'} '
      'after ${rounds.length} round(s)';
}

/// D-16105: whether two end instants are the same instant for the convergence
/// checks — within [kEndSkewToleranceMs], the tolerance the reconciliation
/// rules themselves use (D-15403), so the harness and the product agree on
/// when two ends of different statuses are indistinguishable.
bool endsWithinSkewToleranceMs(int aMs, int bMs) =>
    (aMs - bMs).abs() <= kEndSkewToleranceMs;

/// The four checks of D-14507 over one healing run (read per D-14514).
///
/// [converged] is the whole verdict: no status mismatch, no absorbing end, no
/// missing or duplicated entry, no rest timer running on an ended session, and a
/// heal that reached its fixed point. [timerDisagreements] is measured and
/// deliberately **not** part of it — plan 145 leaves timer ownership to its own
/// decision.
class ConvergenceReport {
  const ConvergenceReport({
    required this.sessionCount,
    required this.phoneStatus,
    required this.wristStatus,
    required this.statusMismatches,
    required this.absorbingViolations,
    required this.entryMismatches,
    required this.entryDuplicates,
    required this.timerViolations,
    required this.timerDisagreements,
    required this.phoneOnlySessions,
    required this.wristOnlySessions,
    required this.withinSkewEndTies,
    required this.healRounds,
    required this.healConverged,
  });

  /// How many session ids the run ever mentioned — one per workout, never one
  /// per side.
  final int sessionCount;

  /// Each side's final status, by session label.
  final Map<String, String?> phoneStatus;
  final Map<String, String?> wristStatus;

  final List<String> statusMismatches;
  final List<String> absorbingViolations;
  final List<String> entryMismatches;
  final List<String> entryDuplicates;
  final List<String> timerViolations;

  /// How many timer kinds both sides held with a different state or start.
  final int timerDisagreements;

  /// Session labels only one side ever held: a workout that never reached the
  /// other side. Measured and reported, never asserted — whether a wrist
  /// workout started while the phone had its own must reach the phone is the
  /// owner's question (A-145-21).
  final List<String> phoneOnlySessions;
  final List<String> wristOnlySessions;

  /// Session labels whose status disagreement is two ends inside the protocol's
  /// skew tolerance — one side finished, the other discarded, at the same
  /// instant (D-16105). **Owner to confirm** that this is convergence: it is
  /// reported here and kept out of [failures], so the verdict is unchanged by
  /// clock skew the protocol itself cannot resolve (A-161-04).
  final List<String> withinSkewEndTies;

  /// The gap both lists describe, for a report line: "unshared 0", or the
  /// counts when a side never held a session.
  String get unsharedSummary =>
      'phone-only ${phoneOnlySessions.length}, '
      'wrist-only ${wristOnlySessions.length}';

  final int healRounds;
  final bool healConverged;

  bool get converged =>
      healConverged &&
      statusMismatches.isEmpty &&
      absorbingViolations.isEmpty &&
      entryMismatches.isEmpty &&
      entryDuplicates.isEmpty &&
      timerViolations.isEmpty;

  /// Every failure, in the order the checks run, for one readable assertion.
  List<String> get failures => [
    if (!healConverged) 'the heal did not reach its fixed point',
    ...statusMismatches,
    ...absorbingViolations,
    ...entryMismatches,
    ...entryDuplicates,
    ...timerViolations,
  ];

  @override
  String toString() => converged
      ? 'converged: $sessionCount session(s), '
            '${phoneStatus.values.toList()} on both sides '
            '($unsharedSummary'
            '${withinSkewEndTies.isEmpty ? '' : ', '
                      '${withinSkewEndTies.length} end tie(s) within skew'})'
      : 'DIVERGED ($unsharedSummary):\n  ${failures.join('\n  ')}';
}
