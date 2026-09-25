/// The real transport between the phone and the wrist: one object that satisfies
/// both sides' interfaces and hands arriving frames to whoever owns them.
///
/// Plan: `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-1). Scenarios S-001, S-002, S-006.
///
/// Two rules shape this file:
///
/// 1. **No watch package type escapes.** [WatchSyncTransport] and
///    [WatchMirrorTransport] are what callers depend on, and [WatchMessageChannel]
///    is the seam the platform plugin plugs into — so a hand-rolled
///    `MethodChannel` + `WCSession` implementation, or a Wear data-layer one,
///    replaces the channel without touching a caller.
/// 2. **Fire-and-forget, with the protocol doing the recovering.** There is no
///    queue here by design: a frame the radio cannot carry right now is reported
///    and dropped, and what the peer still owes is re-sent from storage on the
///    next sync (PROTOCOL.md, "Idempotency and reconciliation").
library;

import 'dart:async';

import '../sync_protocol/wire_timestamps.dart';
import '../../watch/start/watch_sync_orchestrator.dart';
import '../../state/watch/live_session_mirror_state.dart';

/// What a transport needs from the platform's watch API — the package's
/// `WCSession` wrapper on iOS, the Wear data layer on Android, a fake in tests.
///
/// Deliberately four members and no more: everything else the transport does
/// (classifying frames, dispatching, remembering reachability) is logic that
/// would otherwise be written once per platform.
abstract interface class WatchMessageChannel {
  /// Whether a counterpart device is paired at all.
  Future<bool> get isPaired;

  /// Whether the counterpart can be reached right now.
  Future<bool> get isReachable;

  /// Every frame the peer sent, in arrival order.
  Stream<Map<String, Object?>> get messages;

  /// Hands the peer one frame. Completes when the platform has taken it.
  Future<void> send(Map<String, Object?> frame);
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

  static Map<String, Object?> routinesFrame({DateTime? since}) {
    final stamp = since == null ? null : utcIso(since);
    return {'request': routines, 'since': ?stamp};
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
class WatchConnectivityTransport implements WatchTransport {
  WatchConnectivityTransport({
    required WatchMessageChannel channel,
    void Function(Object error, StackTrace stack)? onFailure,
  }) : _channel = channel,
       _onFailure = onFailure;

  /// A frame that could not be carried does not take the session down with it:
  /// the caller reports it and the next sync re-sends what is owed.
  final void Function(Object error, StackTrace stack)? _onFailure;

  final WatchMessageChannel _channel;

  StreamSubscription<Map<String, Object?>>? _incoming;
  WatchInboundHandler? _handler;
  bool _phoneReachable = false;

  /// Whether the counterpart can be reached right now — the phone, from the
  /// wrist's side; the wrist, from the phone's. The platform reports one flag
  /// for both, and the interface names it from the watch's side.
  @override
  bool get isPhoneReachable => _phoneReachable;

  @override
  void onIncoming(WatchInboundHandler handler) {
    _handler = handler;
    _incoming ??= _channel.messages.listen(_dispatch);
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

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    try {
      await _channel.send(envelope);
      _phoneReachable = true;
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Hands one arriving frame to the handler, if there is one.
  ///
  /// A frame that arrives before the handler is bound is dropped rather than
  /// buffered: it names a session the receiver has not built yet, and the next
  /// sync is what brings the receiver up to date.
  Future<void> _dispatch(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler(frame);
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
  }
}
