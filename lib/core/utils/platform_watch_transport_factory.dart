/// Where the app asks for the thing that carries watch messages.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-2), scenario S-006. Plan 280 brings Android in (D-28004).
///
/// One place decides, and it decides on the platform rather than on what is
/// installed: iOS and Android get the real transport, and every other platform
/// gets nothing — a null that production DI reads as "this build has no wrist".
/// The two platforms' links come from one package (`omnitrain_watch_link`):
/// `WCSession` on iOS, the Wear OS data layer on Android, behind the same
/// `WatchLink` API, so nothing above this file knows which wrist it has.
///
/// The check is `defaultTargetPlatform`, not `dart:io`'s `Platform`: this file
/// is compiled for web too, where `dart:io` does not exist.
library;

import 'package:flutter/foundation.dart';

import '../platform/watch_connectivity_channel.dart';
import '../platform/watch_transport.dart';
import '../services/diagnostics_log.dart';

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
  DiagnosticsLog? diagnostics,
}) async {
  final target = platform ?? defaultTargetPlatform;
  if (kIsWeb) return null;
  if (target != TargetPlatform.iOS && target != TargetPlatform.android) {
    return null;
  }

  try {
    final transport = WatchConnectivityTransport(
      channel: (channelFactory ?? _watchConnectivityChannel)(),
      onFailure: onFailure,
      diagnostics: diagnostics,
    );
    await transport.refreshReachability();
    return transport;
  } catch (error, stack) {
    onFailure?.call(error, stack);
    return null;
  }
}

WatchMessageChannel _watchConnectivityChannel() => WatchConnectivityChannel();
