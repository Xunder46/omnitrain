/// The real transport between the phone and the wrist: one object that satisfies
/// both sides' interfaces and hands arriving frames to whoever owns them.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-1). Scenarios S-001, S-002, S-006.
///
/// Two rules shape this file:
///
/// 1. **No watch package type escapes.** [WatchSyncTransport] and
///    [WatchMirrorTransport] are what callers depend on, and [WatchMessageChannel]
///    is the seam the platform plugin plugs into — so a hand-rolled
///    `MethodChannel` + `WCSession` implementation, or a Wear data-layer one,
///    replaces the channel without touching a caller.
/// 2. **A send answers, with the protocol doing the recovering.** A receipt and
///    the four workout messages (`session_snapshot`, `session_lifecycle`,
///    `structure_change`, `exercise_push`) are queued for the OS when the peer
///    cannot be reached, or when the radio refuses them; only the newest copy
///    per workout waits, and a queued copy is a carrier, not a delivery — the
///    caller's bookkeeping moves only on [WatchDelivery.delivered]. Every
///    other frame is live-only: it answers [WatchDelivery.undelivered] and is
///    re-offered at its next trigger. What the peer still owes is re-sent from
///    storage on the next sync (PROTOCOL.md, "Idempotency and reconciliation").
library;

import 'dart:async';

import '../sync_protocol/wire_timestamps.dart';
import '../../watch/start/watch_sync_orchestrator.dart';
import '../../state/watch/live_session_mirror_state.dart';
import 'watch_delivery.dart';
import 'watch_link_info.dart';
import 'watch_link_source.dart';
import 'watch_queue_control.dart';

/// What a transport needs from the platform's watch API — the package's
/// `WCSession` wrapper on iOS, the Wear data layer on Android, a fake in tests.
///
/// Seven members, each one the platform can answer and nothing the transport
/// could compute for itself:
///
/// - [isPaired] and [isReachable] are the two questions a caller asks before
///   deciding whether there is anything to do.
/// - [messages] is the one inbound stream, both kinds of frame merged.
/// - [send] is the live radio, [queue] the OS queue for a frame owed for good.
/// - [reachability] reports every change, so the flag stops being read once.
/// - [info] is the pairing, the app and reachability as one value.
abstract interface class WatchMessageChannel {
  /// Whether a counterpart device is paired at all.
  Future<bool> get isPaired;

  /// Whether the counterpart can be reached right now.
  Future<bool> get isReachable;

  /// Every frame the peer sent, in arrival order.
  Stream<Map<String, Object?>> get messages;

  /// Hands the peer one frame. Completes when the platform has taken it.
  Future<void> send(Map<String, Object?> frame);

  /// Hands the peer one frame the OS delivers later, when the devices meet.
  Future<void> queue(Map<String, Object?> frame);

  /// Every change of reachability, as the platform reports it.
  Stream<bool> get reachability;

  /// The state of the pairing right now.
  Future<WatchLinkInfo> get info;
}

/// A frame that arrived from the peer: a protocol message, or a request.
typedef WatchInboundHandler = Future<void> Function(Map<String, Object?> frame);

/// The requests the transport carries that are not protocol messages.
///
/// PROTOCOL.md is explicit that a request is a transport concern: "The request
/// is a transport concern and carries no message of its own; the answer MUST be
/// a `session_snapshot`." Asking for the routines the same way keeps one
/// vocabulary for both.
abstract final class WatchTransportRequest {
  /// Watch → phone: send the routines, optionally only what changed since.
  static const String routines = 'routines';

  /// Either direction: send your session state.
  static const String snapshot = 'snapshot';

  /// The request [frame] is, or null when it is a protocol message instead.
  ///
  /// One test decides which: a protocol envelope always carries `type`, and a
  /// request never does.
  static String? nameOf(Map<String, Object?> frame) {
    if (frame['type'] is String) return null;
    final request = frame['request'];
    return request is String ? request : null;
  }

  /// The wrist's sync request frame.
  ///
  /// [exercisesVersion] is the version of the exercise list the wrist holds, and
  /// is added only when it says one — a wrist holding nothing omits the key
  /// rather than naming an empty version, the same way a first sync omits
  /// `since` (D-3833).
  static Map<String, Object?> routinesFrame({
    DateTime? since,
    String? exercisesVersion,
  }) {
    final stamp = since == null ? null : utcIso(since);
    final version = exercisesVersion == null || exercisesVersion.isEmpty
        ? null
        : exercisesVersion;
    return {'request': routines, 'since': ?stamp, 'exercisesVersion': ?version};
  }

  /// The exercise-list version [frame] names, or null when it names none.
  ///
  /// A request from a wrist that holds no list — or one whose key is not a
  /// non-empty string — names no version, and the phone answers with the whole
  /// list (D-3833, D-3834).
  static String? exercisesVersionOf(Map<String, Object?> frame) {
    final version = frame['exercisesVersion'];
    return version is String && version.isNotEmpty ? version : null;
  }

  /// The held-routines stamp [frame] names, or null when it names none.
  ///
  /// The wrist names the `generatedAt` of the routines copy it holds as
  /// `since`; anything unreadable — absent, empty, not a string, not a date —
  /// is "names none", and the phone answers with everything.
  static DateTime? sinceOf(Map<String, Object?> frame) {
    final since = frame['since'];
    if (since is! String || since.isEmpty) return null;
    return DateTime.tryParse(since)?.toUtc();
  }

  static Map<String, Object?> snapshotFrame() => const {'request': snapshot};
}

/// The transport both devices talk to: the watch's `WatchSyncTransport` and the
/// phone's `WatchMirrorTransport` in one object, because they are one radio.
abstract interface class WatchTransport
    implements WatchSyncTransport, WatchMirrorTransport {
  /// Hands every frame the peer sends to [handler], for as long as the
  /// transport lives. Set once, before the app starts receiving.
  void onIncoming(WatchInboundHandler handler);

  /// Re-reads whether the peer is reachable. Cheap, and never throws.
  Future<void> refreshReachability();
}

/// The one implementation that talks to a device. Its channel is the only thing
/// that knows which platform it is on.
class WatchConnectivityTransport implements WatchTransport, WatchLinkSource {
  /// Builds the transport without listening to the channel.
  ///
  /// Listening starts at [onIncoming], not here: the platform's `messages` and
  /// `reachability` are one event stream, it withholds that stream until the
  /// first listener attaches, and then flushes what it buffered. A listener
  /// attached here could take that flush before there is a message listener to
  /// give it to.
  WatchConnectivityTransport({
    required WatchMessageChannel channel,
    void Function(Object error, StackTrace stack)? onFailure,
    DateTime Function()? clock,
    Duration handlerTimeout = const Duration(seconds: 30),
  }) : _channel = channel,
       _onFailure = onFailure,
       _clock = clock ?? DateTime.now,
       _handlerTimeout = handlerTimeout;

  /// A frame the radio refuses does not take the session down with it: it is
  /// reported here, its caller learns it was not delivered, and the next sync
  /// re-sends what is owed.
  final void Function(Object error, StackTrace stack)? _onFailure;

  final WatchMessageChannel _channel;

  /// The clock [heard] stamps an arriving frame with. Injectable so a test
  /// never reads the real clock.
  final DateTime Function() _clock;

  StreamSubscription<Map<String, Object?>>? _incoming;
  StreamSubscription<bool>? _reachability;
  final StreamController<WatchLinkInfo> _linkChanges =
      StreamController<WatchLinkInfo>.broadcast();
  final StreamController<DateTime> _heard =
      StreamController<DateTime>.broadcast();
  WatchInboundHandler? _handler;

  /// Frames are handled one at a time: this is the turn of the frame being
  /// handled, and the next frame's turn chains after it.
  Future<void> _lane = Future<void>.value();

  /// Queue work (withdraw, then queue) runs one call at a time, in call order, so two
  /// sends never read the OS list between each other's read and cancel.
  Future<void> _queueLane = Future<void>.value();

  Future<T> _inQueueLane<T>(Future<T> Function() work) {
    final turn = _queueLane.then((_) => work());
    _queueLane = turn.then<void>((_) {}, onError: (Object _) {});
    return turn;
  }

  /// How long a handler may hold its turn before it is reported and given up
  /// on, so later frames are not stuck behind a hung one.
  final Duration _handlerTimeout;
  bool _phoneReachable = false;

  /// The frames the sender may hand the OS to carry when the peer cannot be
  /// reached (plan 67a D-2): a receipt, owed for good, and the four workout
  /// messages the phone sends. A timer, a request or a static frame is never
  /// queued (D-4): it would be wrong on arrival, and is re-sent fresh.
  static const Set<String> _queueable = {
    'receipt',
    'session_snapshot',
    'session_lifecycle',
    'structure_change',
    'exercise_push',
  };

  /// The queued types a newer copy replaces (D-3). A receipt and an
  /// `exercise_push` are never withdrawn.
  static const Set<String> _replaceable = {
    'session_snapshot',
    'session_lifecycle',
    'structure_change',
  };

  /// Whether the OS may carry the frame later when the radio cannot (D-2).
  static bool isDurable(Map<String, Object?> frame) =>
      _queueable.contains(frame['type']);

  /// Every change of the link: reachability, as the platform reports it, with
  /// the pairing and the app read alongside it.
  ///
  /// Events start once [onIncoming] has been called, because that is what
  /// attaches the reachability listener; before it, [isPhoneReachable] holds
  /// what [refreshReachability] read.
  @override
  Stream<WatchLinkInfo> get linkChanges => _linkChanges.stream;

  /// One event per frame handed to the inbound handler, stamped by [clock].
  @override
  Stream<DateTime> get heard => _heard.stream;

  /// The state of the link right now.
  @override
  Future<WatchLinkInfo> linkInfo() => _channel.info;

  /// Whether the counterpart can be reached right now — the phone, from the
  /// wrist's side; the wrist, from the phone's. The platform reports one flag
  /// for both, and the interface names it from the watch's side.
  ///
  /// The flag follows the platform's reachability events from the moment
  /// [onIncoming] is called, plus every send; until then it is what
  /// [refreshReachability] read.
  @override
  bool get isPhoneReachable => _phoneReachable;

  Future<void> _reachabilityChanged(bool reachable) async {
    _phoneReachable = reachable;
    try {
      final info = await _channel.info;
      // A close during the read has closed the stream on purpose: the change is
      // simply not reported, rather than as a transport failure.
      if (_linkChanges.isClosed) return;
      _linkChanges.add(info);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Binds the handler and starts listening.
  ///
  /// The message listener is attached first and the reachability listener in
  /// the same synchronous block: the platform delivers nothing until the first
  /// listener attaches and then flushes its buffer, so a frame that arrived
  /// before the app was ready is waiting for the message listener, never for
  /// reachability alone.
  @override
  void onIncoming(WatchInboundHandler handler) {
    _handler = handler;
    _incoming ??= _channel.messages.listen(_dispatch);
    _reachability ??= _channel.reachability.listen(_reachabilityChanged);
  }

  @override
  Future<void> refreshReachability() async {
    try {
      _phoneReachable = await _channel.isReachable;
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  @override
  Future<void> requestRoutines({DateTime? since}) =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() =>
      send(WatchTransportRequest.snapshotFrame());

  /// Hands the peer one frame, and answers whether the radio took it.
  ///
  /// Reachability is read per send, never from the cached [isPhoneReachable]
  /// hint, which is the UI's (D-190). An unreachable counterpart is
  /// [WatchDelivery.undelivered] without calling the channel and without a
  /// report — the caller re-offers the frame at its next trigger (D-201) —
  /// unless the frame is [isDurable]: a receipt or one of the four workout
  /// messages, which is handed to the OS queue and answers
  /// [WatchDelivery.queued]. A radio that refuses a durable frame falls back
  /// to the same queue; a refused live frame is undelivered. A queued copy is
  /// a carrier, not a delivery: only the newest copy per workout waits, and
  /// the caller's bookkeeping moves only on [WatchDelivery.delivered].
  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    final bool reachable;
    try {
      reachable = await _channel.isReachable;
    } catch (error, stack) {
      _report(error, stack);
      return WatchDelivery.undelivered;
    }
    if (!reachable) {
      return isDurable(envelope)
          ? _queue(envelope)
          : WatchDelivery.undelivered;
    }
    try {
      await _channel.send(envelope);
      _phoneReachable = true;
    } catch (error, stack) {
      _report(error, stack);
      _phoneReachable = false;
      return isDurable(envelope)
          ? _queue(envelope)
          : WatchDelivery.undelivered;
    }
    await _inQueueLane(() => _withdrawSuperseded(envelope));
    return WatchDelivery.delivered;
  }

  /// Hands a frame the OS may carry to the OS queue, after withdrawing the
  /// copies it replaces (D-3). A failing withdraw is reported and the queue
  /// call still runs (D-5).
  Future<WatchDelivery> _queue(Map<String, Object?> envelope) =>
      _inQueueLane(() async {
        await _withdrawSuperseded(envelope);
        try {
          await _channel.queue(envelope);
          return WatchDelivery.queued;
        } catch (error, stack) {
          _report(error, stack);
          return WatchDelivery.undelivered;
        }
      });

  /// Cancels the outstanding transfers [envelope] replaces (D-3): same type
  /// and `sessionId` and, for a `structure_change`, the same payload
  /// `changeId`. A transfer with the frame's own `messageId` is never
  /// cancelled. A channel that cannot list and cancel withdraws nothing.
  Future<void> _withdrawSuperseded(Map<String, Object?> envelope) async {
    // The declared type is [WatchMessageChannel], which is not a supertype of
    // [WatchQueueControl], so the capability check goes through an `Object`
    // local to let the type promote.
    final Object channel = _channel;
    final control = channel is WatchQueueControl ? channel : null;
    if (control == null) return;
    final type = envelope['type'];
    final sessionId = envelope['sessionId'];
    if (type is! String || !_replaceable.contains(type)) return;
    if (sessionId is! String) return;
    String? changeId;
    if (type == 'structure_change') {
      final payload = envelope['payload'];
      final raw = payload is Map ? payload['changeId'] : null;
      if (raw is! String) return;
      changeId = raw;
    }
    final ownId = envelope['messageId'];
    try {
      final held = await control.outstandingTransfers();
      final replaced = <String>[
        for (final transfer in held)
          if (transfer.type == type &&
              transfer.sessionId == sessionId &&
              (changeId == null || transfer.changeId == changeId) &&
              transfer.messageId != ownId)
            transfer.messageId,
      ];
      if (replaced.isEmpty) return;
      await control.cancelTransfers(replaced);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Hands one arriving frame to the handler, if there is one.
  ///
  /// A frame that arrives before the handler is bound is dropped rather than
  /// buffered: it names a session the receiver has not built yet, and the next
  /// sync is what brings the receiver up to date. Only a frame the handler
  /// takes counts as heard.
  ///
  /// Frames are handled one at a time, in arrival order; a handler that does
  /// not finish within the timeout is reported and given up on.
  Future<void> _dispatch(Map<String, Object?> frame) {
    final handler = _handler;
    if (handler == null) return Future<void>.value();
    _heard.add(_clock());
    final turn = _lane.then((_) => _handle(handler, frame));
    _lane = turn;
    return turn;
  }

  Future<void> _handle(
    WatchInboundHandler handler,
    Map<String, Object?> frame,
  ) async {
    try {
      await handler(frame).timeout(_handlerTimeout);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _report(Object error, StackTrace stack) {
    if (_onFailure == null) return;
    _onFailure(error, stack);
  }

  /// Stops listening. The app owns this transport for its lifetime; a test owns
  /// it for a case.
  Future<void> close() async {
    await _incoming?.cancel();
    _incoming = null;
    await _reachability?.cancel();
    _reachability = null;
    await _linkChanges.close();
    await _heard.close();
  }
}
