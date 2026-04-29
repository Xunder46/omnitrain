import 'package:omnitrain/core/utils/timer_alert_service.dart';

/// Test double for [TimerAlertService].
/// All methods are no-ops so tests can run without real audio.
class FakeTimerAlertService extends TimerAlertService {
  final List<String> effortAlertSoundIds = [];
  final List<String> restPingSoundIds = [];
  final List<String> previewSoundIds = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> fireEffortTimerAlert(String soundId) async {
    effortAlertSoundIds.add(soundId);
  }

  @override
  Future<void> fireRestPingAlert(String soundId) async {
    restPingSoundIds.add(soundId);
  }

  @override
  Future<void> playPreview(String soundId) async {
    previewSoundIds.add(soundId);
  }

  @override
  Future<void> dispose() async {}
}
