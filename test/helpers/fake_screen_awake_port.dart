import 'package:omnitrain/core/services/screen_awake_port.dart';

/// Records every `setKeepAwake` value in order, synchronously.
class FakeScreenAwakePort extends ScreenAwakePort {
  final List<bool> calls = <bool>[];

  @override
  Future<void> setKeepAwake(bool on) async {
    calls.add(on);
  }
}

/// Throws synchronously on every call (plan 120 S-19517).
class ThrowingScreenAwakePort extends ScreenAwakePort {
  @override
  Future<void> setKeepAwake(bool on) {
    throw StateError('screen awake port unavailable');
  }
}
