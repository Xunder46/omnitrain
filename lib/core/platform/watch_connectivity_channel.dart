/// The one file that imports the watch package.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-1). `watch_connectivity` wraps `WCSession` on iOS and the Wear
/// APIs on Android; keeping it here means a swap — a hand-rolled `MethodChannel`
/// layer, or a different package — is a change to this file and nothing else
/// (see `WatchMessageChannel`).
library;

import 'package:watch_connectivity/watch_connectivity.dart';

import 'watch_transport.dart';

/// [WatchMessageChannel] over the platform plugin.
class WatchConnectivityChannel implements WatchMessageChannel {
  WatchConnectivityChannel({WatchConnectivity? connectivity})
    : _connectivity = connectivity ?? WatchConnectivity();

  final WatchConnectivity _connectivity;

  @override
  Future<bool> get isPaired => _connectivity.isPaired;

  @override
  Future<bool> get isReachable => _connectivity.isReachable;

  @override
  Stream<Map<String, Object?>> get messages =>
      _connectivity.messageStream.map(_asFrame);

  @override
  Future<void> send(Map<String, Object?> frame) =>
      _connectivity.sendMessage(frame);

  /// The plugin hands back `Map<String, dynamic>`; the protocol's frames are
  /// read as `Map<String, Object?>` everywhere, and the two are the same map.
  static Map<String, Object?> _asFrame(Map<String, dynamic> message) =>
      message.cast<String, Object?>();
}
