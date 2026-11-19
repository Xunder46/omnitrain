import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/screen_awake_port.dart';

/// Method channel implemented in AppDelegate.swift / MainActivity.kt (plan 120 D-19508).
const String screenAwakeChannelName = 'omnitrain/screen_awake';

class MethodChannelScreenAwakePort extends ScreenAwakePort {
  MethodChannelScreenAwakePort({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(screenAwakeChannelName);

  final MethodChannel _channel;

  @override
  Future<void> setKeepAwake(bool on) async {
    try {
      await _channel.invokeMethod<void>('setKeepAwake', on);
    } catch (error) {
      debugPrint('Screen awake channel unavailable: $error');
    }
  }
}

/// The channel port on iOS and Android, a no-op everywhere else.
ScreenAwakePort createScreenAwakePort() {
  if (kIsWeb) return const ScreenAwakePort.noop();
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
      return MethodChannelScreenAwakePort();
    default:
      return const ScreenAwakePort.noop();
  }
}
