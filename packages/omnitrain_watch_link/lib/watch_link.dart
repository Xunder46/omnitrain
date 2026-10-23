import 'dart:async';

import 'package:flutter/services.dart';

import 'watch_link_event.dart';

/// A failure the native link reported; [code] is one of `not_supported`,
/// `not_activated`, `not_reachable`, `send_failed` or `timeout`.
class WatchLinkException implements Exception {
  const WatchLinkException(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() =>
      'WatchLinkException($code${message == null ? '' : ': $message'})';
}

/// One transfer the OS still holds, read from its `userInfo` frame.
class WatchLinkTransfer {
  const WatchLinkTransfer({
    required this.messageId,
    required this.type,
    this.sessionId,
    this.changeId,
  });

  /// The frame's `messageId`.
  final String messageId;

  /// The frame's `type`, or `''` when it has none.
  final String type;

  /// The frame's `sessionId`, when it carries one.
  final String? sessionId;

  /// The `changeId` inside the frame's `payload`, when it carries one.
  final String? changeId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchLinkTransfer &&
          other.messageId == messageId &&
          other.type == type &&
          other.sessionId == sessionId &&
          other.changeId == changeId;

  @override
  int get hashCode => Object.hash(messageId, type, sessionId, changeId);

  @override
  String toString() => 'WatchLinkTransfer(messageId: $messageId, type: $type, '
      'sessionId: $sessionId, changeId: $changeId)';
}

/// The phone's link to the watch.
class WatchLink {
  WatchLink({MethodChannel? methods, EventChannel? events})
      : _methods =
            methods ?? const MethodChannel('omnitrain/watch_link/methods'),
        _events = events ?? const EventChannel('omnitrain/watch_link/events');

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<WatchLinkEvent>? _stream;

  Future<WatchLinkStatus> status() async {
    final map = await _methods.invokeMapMethod<Object?, Object?>('status');
    return WatchLinkStatus.fromMap(map ?? const {});
  }

  /// Completes when the watch has answered the message; throws
  /// [WatchLinkException] when the radio refuses it, or `timeout` when no
  /// answer comes within [timeout].
  Future<void> sendMessage(
    Map<String, Object?> frame, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await _methods.invokeMethod<void>('sendMessage', frame).timeout(timeout);
    } on TimeoutException {
      throw const WatchLinkException('timeout');
    } on PlatformException catch (error) {
      throw WatchLinkException(error.code, error.message);
    }
  }

  /// Hands the OS one frame to deliver later. `queued`, or `already_queued`
  /// when a transfer with the same `messageId` is still outstanding.
  Future<String> transferUserInfo(Map<String, Object?> frame) async {
    try {
      final result = await _methods.invokeMethod<String>(
        'transferUserInfo',
        frame,
      );
      return result ?? 'queued';
    } on PlatformException catch (error) {
      throw WatchLinkException(error.code, error.message);
    }
  }

  /// The transfers the OS still holds, in native order, read from each one's
  /// `userInfo` frame. An entry without a string `messageId` is skipped.
  Future<List<WatchLinkTransfer>> outstandingTransfers() async {
    try {
      final raw = await _methods.invokeListMethod<Object?>(
        'outstandingTransfers',
      );
      final transfers = <WatchLinkTransfer>[];
      for (final entry in raw ?? const <Object?>[]) {
        if (entry is! Map) continue;
        final messageId = entry['messageId'];
        if (messageId is! String) continue;
        transfers.add(
          WatchLinkTransfer(
            messageId: messageId,
            type: entry['type'] is String ? entry['type'] as String : '',
            sessionId: entry['sessionId'] is String
                ? entry['sessionId'] as String
                : null,
            changeId: entry['changeId'] is String
                ? entry['changeId'] as String
                : null,
          ),
        );
      }
      return transfers;
    } on PlatformException catch (error) {
      throw WatchLinkException(error.code, error.message);
    }
  }

  /// Cancels the outstanding transfers whose `messageId` is in [messageIds]
  /// and answers how many were cancelled. An empty list answers 0 without
  /// touching the native side.
  Future<int> cancelTransfers(List<String> messageIds) async {
    if (messageIds.isEmpty) return 0;
    try {
      final result = await _methods.invokeMethod<int>(
          'cancelTransfers', <String, Object?>{'messageIds': messageIds});
      return result ?? 0;
    } on PlatformException catch (error) {
      throw WatchLinkException(error.code, error.message);
    }
  }

  /// Everything the native link reports, in arrival order. One broadcast
  /// stream: the native side starts reporting (and flushes what it buffered)
  /// when the first listener attaches.
  Stream<WatchLinkEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map(_decode)
      .where((event) => event != null)
      .cast<WatchLinkEvent>()
      .asBroadcastStream();

  static WatchLinkEvent? _decode(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['kind']) {
      case 'message':
        return WatchLinkMessage(_frame(raw['frame']));
      case 'userInfo':
        return WatchLinkUserInfo(_frame(raw['frame']));
      case 'reachability':
        return WatchLinkReachability(raw['reachable'] == true);
      case 'state':
        return WatchLinkStateChanged(WatchLinkStatus.fromMap(raw));
    }
    return null;
  }

  static Map<String, Object?> _frame(Object? raw) =>
      raw is Map ? raw.cast<String, Object?>() : const {};
}
