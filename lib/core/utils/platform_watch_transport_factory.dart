/// Where the app asks for the thing that carries watch messages.
///
/// Plan: `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-2), scenario S-006.
///
/// One place decides, and it decides on the platform rather than on what is
/// installed: iOS gets the real transport, and every other platform gets
/// nothing — a null that production DI reads as "this build has no wrist".
/// Android is deliberately in that group until the Wear OS client is built; the
/// transport interfaces carry no iOS type, so the Wear implementation slots in
/// here without reopening the contract.
///
/// The check is `defaultTargetPlatform`, not `dart:io`'s `Platform`: this file
/// is compiled for web too, where `dart:io` does not exist.
library;

import 'package:flutter/foundation.dart';

import '../platform/watch_connectivity_channel.dart';
import '../platform/watch_transport.dart';

/// Builds the channel to use. Overridden by a test that wants a fake.
typedef WatchMessageChannelFactory = WatchMessageChannel Function();

/// The transport this build should use, or null when it has no wrist to talk
/// to.
///
/// Construction trouble — a platform channel that is not registered, a plugin
/// that throws on a simulator without a paired watch — is reported through
/// [onFailure] and answered with null, because a watch that cannot be set up is
/// not a reason to refuse to start the app.
Future<WatchTransport?> createPlatformWatchTransport({
  TargetPlatform? platform,
  WatchMessageChannelFactory? channelFactory,
  void Function(Object error, StackTrace stack)? onFailure,
}) async {
  final target = platform ?? defaultTargetPlatform;
  if (kIsWeb || target != TargetPlatform.iOS) return null;

  try {
    final transport = WatchConnectivityTransport(
      channel: (channelFactory ?? _watchConnectivityChannel)(),
      onFailure: onFailure,
    );
    await transport.refreshReachability();
    return transport;
  } catch (error, stack) {
    onFailure?.call(error, stack);
    return null;
  }
}

WatchMessageChannel _watchConnectivityChannel() => WatchConnectivityChannel();
