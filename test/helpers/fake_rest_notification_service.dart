import 'package:omnitrain/core/utils/rest_notification_service.dart';

/// Test double for [RestNotificationService].
class FakeRestNotificationService extends RestNotificationService {
  final List<
    ({int restStartMs, int intervalSecs, String soundId, bool playSound})
  >
  scheduled = [];
  final List<({int fireAtMs, String soundId, bool playSound})> effortSchedules =
      [];
  int cancelCallCount = 0;
  int effortCancelCallCount = 0;
  bool permissionGranted = true;
  int requestPermissionCallCount = 0;
  int hasPermissionCallCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    requestPermissionCallCount++;
    return permissionGranted;
  }

  @override
  Future<bool> hasPermission() async {
    hasPermissionCallCount++;
    return permissionGranted;
  }

  @override
  Future<void> scheduleRestPings({
    required int restStartMs,
    required int intervalSecs,
    required String soundId,
    bool playSound = true,
  }) async {
    scheduled.add((
      restStartMs: restStartMs,
      intervalSecs: intervalSecs,
      soundId: soundId,
      playSound: playSound,
    ));
  }

  @override
  Future<void> cancelRestNotifications() async {
    cancelCallCount++;
  }

  @override
  Future<void> scheduleEffortTimerExpiry({
    required int fireAtMs,
    required String soundId,
    bool playSound = true,
  }) async {
    effortSchedules.add((
      fireAtMs: fireAtMs,
      soundId: soundId,
      playSound: playSound,
    ));
  }

  @override
  Future<void> cancelEffortTimerNotification() async {
    effortCancelCallCount++;
  }
}
