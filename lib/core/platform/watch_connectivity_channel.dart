/// The one file that imports the watch link package.
///
/// Plan: `docs/plans/2026-10-21-47a-watch-link-plugin-plan/2026-10-21-47a-watch-link-plugin-plan.md`
/// (D-4, D-5), extended to Android by plan 280 (D-28004). `omnitrain_watch_link`
/// is this repository's own plugin: `WCSession` on iOS, the Wear OS data layer
/// on Android, one `WatchLink` API over both. Keeping it here means a swap — a
/// different package, or another platform's watch APIs — is a change to this
/// file and nothing else (see `WatchMessageChannel`). It also exposes the OS
/// queue: listing the transfers the OS still holds and cancelling them by id
/// (`WatchQueueControl`).
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:omnitrain_watch_link/omnitrain_watch_link.dart';

import 'watch_frame_wire.dart';
import 'watch_link_info.dart';
import 'watch_queue_control.dart';
import 'watch_transport.dart';

/// [WatchMessageChannel] over the platform plugin.
class WatchConnectivityChannel
    implements WatchMessageChannel, WatchQueueControl {
  WatchConnectivityChannel({WatchLink? link}) : _link = link ?? WatchLink();

  final WatchLink _link;

  @override
  Future<bool> get isPaired async => (await _link.status()).paired;

  @override
  Future<bool> get isReachable async => (await _link.status()).reachable;

  @override
  Future<WatchLinkInfo> get info async {
    final status = await _link.status();
    return WatchLinkInfo(
      paired: status.paired,
      appInstalled: status.appInstalled,
      reachable: status.reachable,
    );
  }

  /// Both kinds of arriving frame: the live one, and the one the OS carried
  /// later. The transport dispatches them alike, so they share one stream.
  @override
  Stream<Map<String, Object?>> get messages => _link.events
      .where((event) => event is WatchLinkMessage || event is WatchLinkUserInfo)
      .map(
        (event) => switch (event) {
          WatchLinkMessage(:final frame) => frame,
          WatchLinkUserInfo(:final frame) => frame,
          _ => const <String, Object?>{},
        },
      );

  @override
  Stream<bool> get reachability => _link.events
      .where((event) => event is WatchLinkReachability)
      .map((event) => (event as WatchLinkReachability).reachable);

  /// The plugin's refusal is rethrown as the platform's own exception, so the
  /// transport can log the radio's code (`send_failed`, `not_reachable`) and
  /// never knows the plugin's type.
  @override
  Future<void> send(Map<String, Object?> frame) async {
    try {
      await _link.sendMessage(wireSafeFrame(frame));
    } on WatchLinkException catch (error) {
      throw PlatformException(code: error.code, message: error.message);
    }
  }

  /// The plugin answers `queued` or `already_queued`; both mean the OS holds
  /// the frame, which is the whole answer the transport needs.
  @override
  Future<void> queue(Map<String, Object?> frame) async {
    try {
      await _link.transferUserInfo(wireSafeFrame(frame));
    } on WatchLinkException catch (error) {
      throw PlatformException(code: error.code, message: error.message);
    }
  }

  @override
  Future<List<WatchQueuedTransfer>> outstandingTransfers() async => [
    for (final transfer in await _link.outstandingTransfers())
      WatchQueuedTransfer(
        messageId: transfer.messageId,
        type: transfer.type,
        sessionId: transfer.sessionId,
        changeId: transfer.changeId,
      ),
  ];

  @override
  Future<int> cancelTransfers(List<String> messageIds) =>
      _link.cancelTransfers(messageIds);
}
