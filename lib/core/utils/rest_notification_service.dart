import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class RestNotificationService {
  static const int restPingBaseId = 100;
  static const int maxRestPings = 50;
  static const int effortTimerNotificationId = 200;

  static const String _title = 'Rest timer';
  static const String _effortTitle = 'Timer complete';

  final FlutterLocalNotificationsPlugin _plugin;
  final bool? _isWebOverride;
  final DateTime Function()? _nowProvider;
  final Future<void> Function({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
  })?
  _zonedScheduleOverride;
  final Future<void> Function(int id)? _cancelOverride;
  final Future<bool> Function()? _requestPermissionOverride;
  final Future<bool> Function()? _hasPermissionOverride;

  RestNotificationService()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _isWebOverride = null,
      _nowProvider = null,
      _zonedScheduleOverride = null,
      _cancelOverride = null,
      _requestPermissionOverride = null,
      _hasPermissionOverride = null;

  RestNotificationService.noop()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _isWebOverride = true,
      _nowProvider = null,
      _zonedScheduleOverride = null,
      _cancelOverride = null,
      _requestPermissionOverride = null,
      _hasPermissionOverride = null;

  @visibleForTesting
  RestNotificationService.withPlugin(
    FlutterLocalNotificationsPlugin plugin, {
    bool isWeb = false,
    DateTime Function()? nowProvider,
    Future<void> Function({
      required int id,
      required String title,
      required String body,
      required tz.TZDateTime scheduledDate,
      required NotificationDetails details,
    })?
    zonedScheduleOverride,
    Future<void> Function(int id)? cancelOverride,
    Future<bool> Function()? requestPermissionOverride,
    Future<bool> Function()? hasPermissionOverride,
  }) : _plugin = plugin,
       _isWebOverride = isWeb,
       _nowProvider = nowProvider,
       _zonedScheduleOverride = zonedScheduleOverride,
       _cancelOverride = cancelOverride,
       _requestPermissionOverride = requestPermissionOverride,
       _hasPermissionOverride = hasPermissionOverride;

  bool get _isWeb => _isWebOverride ?? kIsWeb;

  Future<void> initialize() async {
    if (_isWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _createAndroidChannels();
  }

  Future<void> _createAndroidChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    const sounds = <String>[
      'boxing_bell',
      'digital_buzzer',
      'soft_chime',
      'double_tap',
      'signal_tone',
    ];

    for (final soundId in sounds) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          _channelIdForSound(soundId),
          'Rest Pings',
          description: 'Rest period interval alerts',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound(soundId),
          playSound: true,
        ),
      );
    }
  }

  Future<bool> requestPermission() async {
    if (_isWeb) return false;
    if (_requestPermissionOverride != null) {
      return _requestPermissionOverride();
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        sound: true,
        badge: false,
      );
      return granted ?? false;
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return false;
  }

  Future<bool> hasPermission() async {
    if (_isWeb) return false;
    if (_hasPermissionOverride != null) {
      return _hasPermissionOverride();
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      return await androidPlugin.areNotificationsEnabled() ?? false;
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      // iOS does not re-prompt after a user decision, so this is safe to use
      // for reflecting granted vs denied in Settings once asked in context.
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        sound: true,
        badge: false,
      );
      return granted ?? false;
    }

    return false;
  }

  Future<void> scheduleRestPings({
    required int restStartMs,
    required int intervalSecs,
    required String soundId,
    bool playSound = true,
  }) async {
    if (_isWeb) return;

    await cancelRestNotifications();
    if (intervalSecs <= 0) return;

    final nowMs = (_nowProvider ?? DateTime.now)().millisecondsSinceEpoch;

    for (int n = 1; n <= maxRestPings; n++) {
      final fireAtMs = restStartMs + (n * intervalSecs * 1000);
      if (fireAtMs <= nowMs) continue;

      final fireAt = DateTime.fromMillisecondsSinceEpoch(fireAtMs);
      final notifId = restPingBaseId + (n - 1);

      final body = '${n * intervalSecs}s - rest time';
      final scheduledDate = tz.TZDateTime.from(fireAt, tz.local);
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdForSound(soundId),
          'Rest Pings',
          channelDescription: 'Rest period interval alerts',
          importance: Importance.high,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound(soundId),
          playSound: playSound,
        ),
        iOS: DarwinNotificationDetails(
          sound: '$soundId.caf',
          presentAlert: true,
          presentBadge: false,
          presentSound: playSound,
        ),
      );

      if (_zonedScheduleOverride != null) {
        await _zonedScheduleOverride(
          id: notifId,
          title: _title,
          body: body,
          scheduledDate: scheduledDate,
          details: details,
        );
      } else {
        await _plugin.zonedSchedule(
          notifId,
          _title,
          body,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  Future<void> scheduleEffortTimerExpiry({
    required int fireAtMs,
    required String soundId,
    bool playSound = true,
  }) async {
    if (_isWeb) return;

    await cancelEffortTimerNotification();

    final nowMs = (_nowProvider ?? DateTime.now)().millisecondsSinceEpoch;
    if (fireAtMs <= nowMs) return;

    final fireAt = DateTime.fromMillisecondsSinceEpoch(fireAtMs);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelIdForSound(soundId),
        'Rest Pings',
        channelDescription: 'Rest period interval alerts',
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(soundId),
        playSound: playSound,
      ),
      iOS: DarwinNotificationDetails(
        sound: '$soundId.caf',
        presentAlert: true,
        presentBadge: false,
        presentSound: playSound,
      ),
    );

    final scheduledDate = tz.TZDateTime.from(fireAt, tz.local);
    const body = 'Time to log your next set';

    if (_zonedScheduleOverride != null) {
      await _zonedScheduleOverride(
        id: effortTimerNotificationId,
        title: _effortTitle,
        body: body,
        scheduledDate: scheduledDate,
        details: details,
      );
      return;
    }

    await _plugin.zonedSchedule(
      effortTimerNotificationId,
      _effortTitle,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelRestNotifications() async {
    if (_isWeb) return;

    for (int i = restPingBaseId; i < restPingBaseId + maxRestPings; i++) {
      if (_cancelOverride != null) {
        await _cancelOverride(i);
      } else {
        await _plugin.cancel(i);
      }
    }
  }

  Future<void> cancelEffortTimerNotification() async {
    if (_isWeb) return;

    if (_cancelOverride != null) {
      await _cancelOverride(effortTimerNotificationId);
      return;
    }

    await _plugin.cancel(effortTimerNotificationId);
  }

  String _channelIdForSound(String soundId) => 'rest_pings_$soundId';
}
