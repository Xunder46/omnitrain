/// Keeps the phone screen from auto-locking (plan 120). Implementations are
/// platform specific; `ScreenAwakePort.noop()` does nothing.
abstract class ScreenAwakePort {
  const ScreenAwakePort();
  const factory ScreenAwakePort.noop() = _NoopScreenAwakePort;

  /// Turns the keep-awake hold on or off.
  Future<void> setKeepAwake(bool on);
}

class _NoopScreenAwakePort extends ScreenAwakePort {
  const _NoopScreenAwakePort();

  @override
  Future<void> setKeepAwake(bool on) async {}
}
