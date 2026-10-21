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
