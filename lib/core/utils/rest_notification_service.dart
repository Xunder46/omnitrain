import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omnitrain/core/services/crash_reporting_service.dart';
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
  final Future<void> Function(
    Object error, {
    StackTrace? stackTrace,
    String? errorContext,
  })?
  _reportErrorOverride;
  final Future<void> Function({
    required String fingerprint,
    required String message,
    String? errorContext,
  })?
  _reportInfoSignalOverride;
  final Future<void> Function(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  })?
  _pluginInitializeOverride;
  final Future<void> Function(AndroidNotificationChannel channel)?
  _androidChannelCreateOverride;

  /// Stable identity for the flutter_local_notifications Android
  /// cache-schema error. Used as the Sentry fingerprint so every
  /// emission groups together in the dashboard and a single
  /// rate-threshold alert can be attached. The value is part of the
  /// observability contract — changing it requires coordinated
  /// alerting updates.
  static const String cacheSchemaErrorFingerprint =
      'flutter_local_notifications.cache_schema';

  RestNotificationService()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _isWebOverride = null,
      _nowProvider = null,
      _zonedScheduleOverride = null,
      _cancelOverride = null,
      _requestPermissionOverride = null,
      _hasPermissionOverride = null,
      _reportErrorOverride = null,
      _reportInfoSignalOverride = null,
      _pluginInitializeOverride = null,
      _androidChannelCreateOverride = null;

  RestNotificationService.noop()
    : _plugin = FlutterLocalNotificationsPlugin(),
      _isWebOverride = true,
      _nowProvider = null,
      _zonedScheduleOverride = null,
      _cancelOverride = null,
      _requestPermissionOverride = null,
      _hasPermissionOverride = null,
      _reportErrorOverride = null,
      _reportInfoSignalOverride = null,
      _pluginInitializeOverride = null,
      _androidChannelCreateOverride = null;

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
    Future<void> Function(
      Object error, {
      StackTrace? stackTrace,
      String? errorContext,
    })?
    reportErrorOverride,
    Future<void> Function({
      required String fingerprint,
      required String message,
      String? errorContext,
    })?
    reportInfoSignalOverride,
    Future<void> Function(
      InitializationSettings initializationSettings, {
      DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
      DidReceiveBackgroundNotificationResponseCallback?
      onDidReceiveBackgroundNotificationResponse,
    })?
    pluginInitializeOverride,
    Future<void> Function(AndroidNotificationChannel channel)?
    androidChannelCreateOverride,
  }) : _plugin = plugin,
       _isWebOverride = isWeb,
       _nowProvider = nowProvider,
       _zonedScheduleOverride = zonedScheduleOverride,
       _cancelOverride = cancelOverride,
       _requestPermissionOverride = requestPermissionOverride,
       _hasPermissionOverride = hasPermissionOverride,
       _reportErrorOverride = reportErrorOverride,
       _reportInfoSignalOverride = reportInfoSignalOverride,
       _pluginInitializeOverride = pluginInitializeOverride,
       _androidChannelCreateOverride = androidChannelCreateOverride;

  bool get _isWeb => _isWebOverride ?? kIsWeb;

  Future<void> initialize() async {
    if (_isWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final initSettings = const InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    if (_pluginInitializeOverride != null) {
      await _pluginInitializeOverride(initSettings);
    } else {
      await _plugin.initialize(initSettings);
    }

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
      final channel = AndroidNotificationChannel(
        _channelIdForSound(soundId),
        'Rest Pings',
        description: 'Rest period interval alerts',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound(soundId),
        playSound: true,
      );
      try {
        if (_androidChannelCreateOverride != null) {
          await _androidChannelCreateOverride(channel);
        } else {
          await androidPlugin.createNotificationChannel(channel);
        }
      } catch (error, stackTrace) {
        // One channel failing must not abort the rest, and must not
        // bubble out of `initialize` (which would block the app shell
        // from rendering on a misconfigured device). The failure is
        // observable as a non-fatal error so a regression is
        // detectable in Sentry without disrupting the workout.
        await _reportNonFatal(
          error,
          stackTrace: stackTrace,
          errorContext: 'RestNotificationService._createAndroidChannels.create',
        );
      }
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

    // Resolve exact-alarm capability once per batch, not per ping.
    await _refreshExactAlarmCapability();

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
        await _scheduleWithSilentFallback(
          notifId: notifId,
          title: _title,
          body: body,
          scheduledDate: scheduledDate,
          audibleDetails: details,
          scheduleOverride: _zonedScheduleOverride,
          overrideErrorContext:
              'RestNotificationService.scheduleRestPings.scheduleOverride',
          realErrorContext:
              'RestNotificationService.scheduleRestPings.schedule',
        );
      } else {
        await _scheduleWithSilentFallback(
          notifId: notifId,
          title: _title,
          body: body,
          scheduledDate: scheduledDate,
          audibleDetails: details,
          scheduleOverride: null,
          overrideErrorContext:
              'RestNotificationService.scheduleRestPings.scheduleOverride',
          realErrorContext:
              'RestNotificationService.scheduleRestPings.schedule',
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

    await _refreshExactAlarmCapability();

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

    await _scheduleWithSilentFallback(
      notifId: effortTimerNotificationId,
      title: _effortTitle,
      body: body,
      scheduledDate: scheduledDate,
      audibleDetails: details,
      scheduleOverride: _zonedScheduleOverride,
      overrideErrorContext:
          'RestNotificationService.scheduleEffortTimerExpiry.scheduleOverride',
      realErrorContext:
          'RestNotificationService.scheduleEffortTimerExpiry.schedule',
    );
  }

  /// Schedule a single notification, falling back to a guaranteed-silent
  /// schedule if the audible attempt throws.
  ///
  /// Contract:
  /// 1. The method never propagates a [PlatformException] to the caller.
  ///    A failing schedule mid-workout is the exact pathology the silent
  ///    fallback exists to prevent — it must never surface as a thrown
  ///    error to user code.
  /// 2. If the audible attempt throws AND `audibleDetails.android.playSound`
  ///    is `true`, exactly one silent retry is attempted for the same
  ///    notification ID, title, body, and scheduled time. The silent
  ///    retry uses `playSound: false` and a `NotificationDetails` with
  ///    no `android.sound` and no iOS sound — so the timer alert still
  ///    fires visually, but the device default tone is never used as a
  ///    substitute.
  /// 3. If the audible attempt was already silent (`playSound == false`)
  ///    or the silent retry itself throws, the error is reported through
  ///    the existing non-fatal channel and the method returns normally.
  /// 4. The `audible` error is always reported with the supplied
  ///    [audibleErrorContext] so the original failure is still observable
  ///    in telemetry.
  ///
  /// This is the production safety net for
  /// `PlatformException(invalid_sound, ...)` and the catch-all for any
  /// other transient schedule failure: lose the sound, never lose the
  /// workout.
  Future<void> _scheduleWithSilentFallback({
    required int notifId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails audibleDetails,
    required Future<void> Function({
      required int id,
      required String title,
      required String body,
      required tz.TZDateTime scheduledDate,
      required NotificationDetails details,
    })?
    scheduleOverride,
    required String overrideErrorContext,
    required String realErrorContext,
  }) async {
    // Production callers always supply Android details (the schedule
    // methods construct the `NotificationDetails` with `android:
    // AndroidNotificationDetails(...)`). If a future caller passes
    // something else, the `!` throws and the failure is reported —
    // still better than silently dropping a timer alert.
    final androidAudible = audibleDetails.android!;
    final audiblePlaySound = androidAudible.playSound;

    // Try the audible schedule first.
    try {
      await _invokeSchedule(
        notifId: notifId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        details: audibleDetails,
        scheduleOverride: scheduleOverride,
      );
      return;
    } catch (error, stackTrace) {
      // The audible attempt failed. Report it so a regression is
      // observable in Sentry, then fall through to the silent retry.
      await _reportNonFatal(
        error,
        stackTrace: stackTrace,
        errorContext: scheduleOverride != null
            ? overrideErrorContext
            : realErrorContext,
      );
    }

    // If the user already asked for a silent notification, there is
    // nothing to fall back to — the silent attempt itself failed and
    // reporting it is the right outcome. Re-throwing here would defeat
    // the "never interrupt a workout" contract.
    if (!audiblePlaySound) {
      return;
    }

    // Silent retry: same id, title, body, scheduledDate, channelId; the
    // only difference is `playSound: false` and no `android.sound` (so
    // the device default tone is never substituted).
    final silentDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        androidAudible.channelId,
        'Rest Pings',
        channelDescription: 'Rest period interval alerts',
        importance: Importance.high,
        priority: Priority.high,
        // No `sound` — we explicitly do not want the device default
        // tone, and the previous audible attempt already proved the
        // selected sound is unresolvable.
        playSound: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );

    try {
      await _invokeSchedule(
        notifId: notifId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        details: silentDetails,
        scheduleOverride: scheduleOverride,
      );
    } catch (error, stackTrace) {
      // Even the silent retry failed (extremely unusual — likely a
      // deeper plugin issue). Report and move on; do not propagate.
      await _reportNonFatal(
        error,
        stackTrace: stackTrace,
        errorContext: scheduleOverride != null
            ? '$overrideErrorContext.silentRetry'
            : '$realErrorContext.silentRetry',
      );
    }
  }

  Future<void> _invokeSchedule({
    required int notifId,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required Future<void> Function({
      required int id,
      required String title,
      required String body,
      required tz.TZDateTime scheduledDate,
      required NotificationDetails details,
    })?
    scheduleOverride,
  }) {
    if (scheduleOverride != null) {
      return scheduleOverride(
        id: notifId,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        details: details,
      );
    }
    return _plugin.zonedSchedule(
      notifId,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: _androidScheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cached result of the exact-alarm capability probe. `null` until the
  /// first schedule call resolves it.
  bool? _canScheduleExactAlarms;

  /// The schedule mode to use for this device.
  ///
  /// `exactAllowWhileIdle` requires `SCHEDULE_EXACT_ALARM`, which
  /// Android 14+ denies by default to any app that is not an alarm
  /// clock or calendar. Asking for it anyway throws
  /// `PlatformException(exact_alarms_not_permitted)` and the ping is
  /// simply never delivered — the previous silent-sound retry could not
  /// recover from that, because it re-issued the same exact-mode
  /// request.
  ///
  /// A rest ping that lands a few seconds late is far better than one
  /// that never lands, so we fall back to `inexactAllowWhileIdle` when
  /// the permission is absent. Devices that DO grant it keep precise
  /// timing.
  AndroidScheduleMode get _androidScheduleMode =>
      (_canScheduleExactAlarms ?? false)
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Probe the platform for exact-alarm permission and cache it.
  ///
  /// Called once per schedule batch rather than per notification. A
  /// probe failure is treated as "not permitted" — the inexact path
  /// always works, so an unknown state must not cost the user their
  /// ping.
  Future<void> _refreshExactAlarmCapability() async {
    if (_isWeb) return;
    // A schedule override means the real plugin is never invoked (the
    // test harness and `RestNotificationService.noop()` both use one).
    // Probing the platform there would reach for a binding that may not
    // exist and tell us nothing about any real device.
    if (_zonedScheduleOverride != null) return;

    try {
      // `resolvePlatformSpecificImplementation` itself can throw when no
      // ServicesBinding is initialised, so it belongs inside the guard —
      // not just the probe call.
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) {
        // Non-Android (iOS): the Android schedule mode is ignored, so
        // the cached value is irrelevant. Leave it false.
        return;
      }
      _canScheduleExactAlarms =
          await androidPlugin.canScheduleExactNotifications() ?? false;
    } catch (_) {
      // Deliberately NOT reported. This probe runs once per schedule
      // batch, so a reporting path here would emit a non-fatal on every
      // rest period for any device where the probe is unavailable —
      // enough volume to crowd out real crashes. The failure is also
      // self-correcting: an unknown capability falls back to inexact
      // scheduling, which always works.
      _canScheduleExactAlarms = false;
    }
  }

  Future<void> cancelRestNotifications() async {
    if (_isWeb) return;

    for (int i = restPingBaseId; i < restPingBaseId + maxRestPings; i++) {
      try {
        if (_cancelOverride != null) {
          await _cancelOverride(i);
        } else {
          await _plugin.cancel(i);
        }
      } catch (error, stackTrace) {
        await _reportNonFatal(
          error,
          stackTrace: stackTrace,
          errorContext:
              'RestNotificationService.cancelRestNotifications.cancel',
        );
      }
    }
  }

  Future<void> cancelEffortTimerNotification() async {
    if (_isWeb) return;

    try {
      if (_cancelOverride != null) {
        await _cancelOverride(effortTimerNotificationId);
        return;
      }

      await _plugin.cancel(effortTimerNotificationId);
    } catch (error, stackTrace) {
      await _reportNonFatal(
        error,
        stackTrace: stackTrace,
        errorContext:
            'RestNotificationService.cancelEffortTimerNotification.cancel',
      );
    }
  }

  String _channelIdForSound(String soundId) => 'rest_pings_$soundId';

  Future<void> _reportNonFatal(
    Object error, {
    StackTrace? stackTrace,
    required String errorContext,
  }) async {
    // flutter_local_notifications on Android release builds can throw
    // `Missing type parameter.` from Gson reflection when reading its
    // SharedPreferences cache (see flutter_local_notifications #2014).
    // The platform-side notification cancel/schedule already succeeded
    // before this cache reload, so the failure is purely cosmetic and
    // cannot be cleared by the user short of reinstalling.
    //
    // We do NOT report this at error/crash level — that would drown
    // genuine issues and risk paging on a known benign signal. We also
    // do NOT drop it entirely: a silent regression (build setting
    // change, dependency update) would be undetectable. Instead, emit
    // a low-severity, informational signal under a stable fingerprint
    // so its rate is observable in telemetry and a regression can be
    // caught by a rate-threshold alert.
    if (_isCacheSchemaError(error)) {
      await _reportCacheSchemaSignal(errorContext: errorContext);
      return;
    }

    if (_reportErrorOverride != null) {
      await _reportErrorOverride(
        error,
        stackTrace: stackTrace,
        errorContext: errorContext,
      );
      return;
    }

    await CrashReportingService.recordError(
      error,
      stackTrace: stackTrace,
      errorContext: errorContext,
    );
  }

  Future<void> _reportCacheSchemaSignal({required String errorContext}) async {
    const message =
        'flutter_local_notifications Android cache-schema error '
        '(known benign; release build keep-rule regression marker)';
    if (_reportInfoSignalOverride != null) {
      await _reportInfoSignalOverride(
        fingerprint: cacheSchemaErrorFingerprint,
        message: message,
        errorContext: errorContext,
      );
      return;
    }

    await CrashReportingService.recordInfoSignal(
      fingerprint: cacheSchemaErrorFingerprint,
      message: message,
      errorContext: errorContext,
    );
  }

  @visibleForTesting
  bool isCacheSchemaError(Object error) => _isCacheSchemaError(error);

  bool _isCacheSchemaError(Object error) {
    if (error is! PlatformException) return false;
    final message = error.message ?? '';
    final stack = error.stacktrace?.toString() ?? '';
    return message.contains('Missing type parameter') ||
        stack.contains('com.google.gson.reflect') ||
        stack.contains('TypeToken');
  }
}
