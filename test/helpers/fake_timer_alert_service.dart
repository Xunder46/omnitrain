import 'package:omnitrain/core/utils/timer_alert_service.dart';

/// Test double for [TimerAlertService].
/// All methods are no-ops so tests can run without real audio.
class FakeTimerAlertService extends TimerAlertService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> fireEffortTimerAlert(String soundId) async {}

  @override
  Future<void> fireRestPingAlert(String soundId) async {}

  @override
  Future<void> playPreview(String soundId) async {}

  @override
  Future<void> dispose() async {}
}
