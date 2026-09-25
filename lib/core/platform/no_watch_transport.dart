/// The transport for a platform with no watch: it carries nothing, and says so.
///
/// Plan: `.github/agents/plans/2026-09-21-13-watch-integration-shipping.md`,
/// Phase 1 (D-2). This is what keeps the environment contract in CLAUDE.md
/// intact — the app builds and tests on web, desktop, and Android without a
/// watch, and a send that has nowhere to go resolves instead of throwing.
///
/// A null-object rather than a null: callers that hold a `WatchTransport` never
/// branch on whether one exists, and the one place that has to know the
/// difference — production DI, which decides whether to build the live mirror at
/// all — asks the factory for null instead.
library;

import 'watch_transport.dart';

class NoWatchTransport implements WatchTransport {
  const NoWatchTransport();

  /// Nothing to reach, ever.
  @override
  bool get isPhoneReachable => false;

  /// No device, so no frames: a bound handler is never called.
  @override
  void onIncoming(WatchInboundHandler handler) {}

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async {}
}
