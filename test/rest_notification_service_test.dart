import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // Unit tests here validate Dart-side wiring and non-fatal behavior only.
  // Release shrinker keep-rules cannot be proven in a Dart unit test because
  // the crash reproduces in optimized on-device Android builds.
  setUpAll(() {
    if (tz.timeZoneDatabase.locations.isEmpty) {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  });

  group('RestNotificationService', () {
    test('scheduleRestPings interval 0 cancels existing and does not schedule', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final canceled = <int>[];
      final scheduledIds = <int>[];

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (id) async => canceled.add(id),
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduledIds.add(id);
        },
      );

      await service.scheduleRestPings(
        restStartMs: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
        intervalSecs: 0,
        soundId: 'boxing_bell',
      );

      expect(canceled.length, RestNotificationService.maxRestPings);
      expect(scheduledIds, isEmpty);
    });

    test('scheduleRestPings skips past boundaries and schedules future IDs', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final scheduledIds = <int>[];
      final scheduledDates = <tz.TZDateTime>[];
      final now = DateTime.utc(2026, 1, 1, 12, 5, 30);
      final restStart = DateTime.utc(2026, 1, 1, 12, 0, 0);

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => now,
        cancelOverride: (_) async {},
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduledIds.add(id);
          scheduledDates.add(scheduledDate);
        },
      );

      await service.scheduleRestPings(
        restStartMs: restStart.millisecondsSinceEpoch,
        intervalSecs: 60,
        soundId: 'soft_chime',
      );

      expect(scheduledIds, isNotEmpty);
      expect(scheduledIds.first, RestNotificationService.restPingBaseId + 5);
      expect(
        scheduledDates.first,
        tz.TZDateTime.from(DateTime.utc(2026, 1, 1, 12, 6, 0), tz.local),
      );
    });

    test('cancelRestNotifications cancels IDs 100 to 149', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final canceled = <int>[];
      final service = RestNotificationService.withPlugin(
        plugin,
        cancelOverride: (id) async => canceled.add(id),
      );

      await service.cancelRestNotifications();

      expect(canceled.length, RestNotificationService.maxRestPings);
      expect(canceled.first, RestNotificationService.restPingBaseId);
      expect(canceled.last, RestNotificationService.restPingBaseId + 49);
    });

    test('cancelRestNotifications swallows PlatformException and reports error', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final canceled = <int>[];
      final reportedErrors = <Object>[];

      final service = RestNotificationService.withPlugin(
        plugin,
        cancelOverride: (id) async {
          canceled.add(id);
          throw PlatformException(code: 'cancel_failed', message: 'boom');
        },
        reportErrorOverride: (error, {stackTrace, errorContext}) async {
          reportedErrors.add(error);
        },
      );

      await service.cancelRestNotifications();

      expect(canceled.length, RestNotificationService.maxRestPings);
      expect(reportedErrors.length, RestNotificationService.maxRestPings);
      expect(reportedErrors.first, isA<PlatformException>());
    });

    test('scheduleRestPings continues scheduling when cancel throws and reports error', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final reportedErrors = <Object>[];
      final scheduledIds = <int>[];
      var didThrowOnCancel = false;

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (_) async {
          if (!didThrowOnCancel) {
            didThrowOnCancel = true;
            throw PlatformException(
              code: 'cancel_failed_once',
              message: 'cancel failed',
            );
          }
        },
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduledIds.add(id);
        },
        reportErrorOverride: (error, {stackTrace, errorContext}) async {
          reportedErrors.add(error);
        },
      );

      await service.scheduleRestPings(
        restStartMs: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
        intervalSecs: 60,
        soundId: 'boxing_bell',
      );

      expect(scheduledIds, isNotEmpty);
      expect(scheduledIds.first, RestNotificationService.restPingBaseId);
      expect(reportedErrors.whereType<PlatformException>(), isNotEmpty);
    });

    test('requestPermission and hasPermission use injected overrides', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final service = RestNotificationService.withPlugin(
        plugin,
        requestPermissionOverride: () async => true,
        hasPermissionOverride: () async => false,
      );

      expect(await service.requestPermission(), isTrue);
      expect(await service.hasPermission(), isFalse);
    });

    test('withPlugin constructor is available for tests', () {
      final plugin = FlutterLocalNotificationsPlugin();
      final service = RestNotificationService.withPlugin(plugin, isWeb: true);
      expect(service, isNotNull);
    });

    test('web mode permission methods return false', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final service = RestNotificationService.withPlugin(plugin, isWeb: true);

      expect(await service.requestPermission(), isFalse);
      expect(await service.hasPermission(), isFalse);
    });

    test('scheduleEffortTimerExpiry schedules one notification with selected sound', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      int? scheduledId;
      NotificationDetails? scheduledDetails;

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (_) async {},
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduledId = id;
          scheduledDetails = details;
        },
      );

      await service.scheduleEffortTimerExpiry(
        fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 15).millisecondsSinceEpoch,
        soundId: 'boxing_bell',
      );

      expect(scheduledId, RestNotificationService.effortTimerNotificationId);
      final androidDetails = scheduledDetails?.android as AndroidNotificationDetails;
      final iosDetails = scheduledDetails?.iOS as DarwinNotificationDetails;
      expect(androidDetails.sound?.sound, 'boxing_bell');
      expect(iosDetails.sound, 'boxing_bell.caf');
    });

    test('scheduleEffortTimerExpiry does not schedule for past time', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      var scheduleCount = 0;

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (_) async {},
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduleCount++;
        },
      );

      await service.scheduleEffortTimerExpiry(
        fireAtMs: DateTime.utc(2026, 1, 1, 11, 59, 59).millisecondsSinceEpoch,
        soundId: 'digital_buzzer',
      );

      expect(scheduleCount, 0);
    });

    test('cancelEffortTimerNotification cancels reserved effort notification ID', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final canceled = <int>[];
      final service = RestNotificationService.withPlugin(
        plugin,
        cancelOverride: (id) async => canceled.add(id),
      );

      await service.cancelEffortTimerNotification();

      expect(canceled, [RestNotificationService.effortTimerNotificationId]);
    });

    test('scheduleEffortTimerExpiry swallows PlatformException and reports error', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final reportedErrors = <Object>[];

      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (_) async {},
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          throw PlatformException(
            code: 'schedule_failed',
            message: 'schedule failed',
          );
        },
        reportErrorOverride: (error, {stackTrace, errorContext}) async {
          reportedErrors.add(error);
        },
      );

      await service.scheduleEffortTimerExpiry(
        fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 10).millisecondsSinceEpoch,
        soundId: 'boxing_bell',
      );

      expect(reportedErrors.length, 1);
      expect(reportedErrors.single, isA<PlatformException>());
    });

    test('cancelEffortTimerNotification swallows PlatformException and reports error', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final reportedErrors = <Object>[];

      final service = RestNotificationService.withPlugin(
        plugin,
        cancelOverride: (_) async {
          throw PlatformException(
            code: 'cancel_effort_failed',
            message: 'cancel effort failed',
          );
        },
        reportErrorOverride: (error, {stackTrace, errorContext}) async {
          reportedErrors.add(error);
        },
      );

      await service.cancelEffortTimerNotification();

      expect(reportedErrors.length, 1);
      expect(reportedErrors.single, isA<PlatformException>());
    });

    // These override-based tests are still valuable for wiring coverage, but
    // they bypass the real platform plugin and cannot reproduce release-only
    // shrinker/obfuscation regressions by construction.

    test('effort notification can be canceled then rescheduled', () async {
      final plugin = FlutterLocalNotificationsPlugin();
      final scheduled = <int>[];
      final canceled = <int>[];
      final service = RestNotificationService.withPlugin(
        plugin,
        nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        cancelOverride: (id) async => canceled.add(id),
        zonedScheduleOverride: ({
          required id,
          required title,
          required body,
          required scheduledDate,
          required details,
        }) async {
          scheduled.add(id);
        },
      );

      await service.scheduleEffortTimerExpiry(
        fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 5).millisecondsSinceEpoch,
        soundId: 'boxing_bell',
      );
      await service.cancelEffortTimerNotification();
      await service.scheduleEffortTimerExpiry(
        fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 8).millisecondsSinceEpoch,
        soundId: 'boxing_bell',
      );

      expect(scheduled.length, 2);
      expect(
        canceled.where(
          (id) => id == RestNotificationService.effortTimerNotificationId,
        ).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('isCacheSchemaError detects Gson Missing type parameter errors', () {
      final plugin = FlutterLocalNotificationsPlugin();
      final service = RestNotificationService.withPlugin(
        plugin,
        isWeb: true,
      );

      final gsonError = PlatformException(
        code: 'error',
        message: 'Missing type parameter.',
        stacktrace:
            'java.lang.RuntimeException: Missing type parameter.\n'
            '\tat com.google.gson.reflect.a.getSuperclassTypeParameter\n'
            '\tat com.dexterous.flutterlocalnotifications.'
            'FlutterLocalNotificationsPlugin\$1.<init>',
      );
      final unrelatedError = PlatformException(
        code: 'cancel_failed',
        message: 'boom',
      );

      expect(service.isCacheSchemaError(gsonError), isTrue);
      expect(service.isCacheSchemaError(unrelatedError), isFalse);
      expect(service.isCacheSchemaError(Exception('not a platform exc')), isFalse);
    });

    test(
      'cancelRestNotifications records cache-schema PlatformException as a '
      'low-severity info signal — NOT as an error',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final canceled = <int>[];
        final reportedErrors = <Object>[];
        final reportedSignals = <_CapturedInfoSignal>[];

        final service = RestNotificationService.withPlugin(
          plugin,
          cancelOverride: (id) async {
            canceled.add(id);
            throw PlatformException(
              code: 'error',
              message: 'Missing type parameter.',
              stacktrace:
                  'java.lang.RuntimeException: Missing type parameter.\n'
                  '\tat com.google.gson.reflect.a.getSuperclassTypeParameter',
            );
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
          reportInfoSignalOverride: ({
            required fingerprint,
            required message,
            errorContext,
          }) async {
            reportedSignals.add(
              _CapturedInfoSignal(
                fingerprint: fingerprint,
                message: message,
                errorContext: errorContext,
              ),
            );
          },
        );

        await service.cancelRestNotifications();

        // All 50 cancels ran.
        expect(canceled.length, RestNotificationService.maxRestPings);
        // The cache-schema error must NOT reach the full-severity
        // reporting channel — that is the whole point of suppression.
        expect(reportedErrors, isEmpty);
        // But it must be observable as a low-severity info signal so
        // a regression in the release-build keep-rules is detectable.
        expect(reportedSignals, isNotEmpty);
        expect(reportedSignals.first.fingerprint,
            RestNotificationService.cacheSchemaErrorFingerprint);
        expect(
          reportedSignals.first.errorContext,
          'RestNotificationService.cancelRestNotifications.cancel',
        );
      },
    );

    test(
      'scheduleRestPings records cache-schema PlatformException as a '
      'low-severity info signal — NOT as an error',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedErrors = <Object>[];
        final reportedSignals = <_CapturedInfoSignal>[];
        final scheduledIds = <int>[];
        var didThrowOnCancel = false;

        final service = RestNotificationService.withPlugin(
          plugin,
          nowProvider: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
          cancelOverride: (_) async {
            if (!didThrowOnCancel) {
              didThrowOnCancel = true;
              throw PlatformException(
                code: 'error',
                message: 'Missing type parameter.',
                stacktrace:
                    'java.lang.RuntimeException: ... '
                    'com.google.gson.reflect.TypeToken',
              );
            }
          },
          zonedScheduleOverride: ({
            required id,
            required title,
            required body,
            required scheduledDate,
            required details,
          }) async {
            scheduledIds.add(id);
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
          reportInfoSignalOverride: ({
            required fingerprint,
            required message,
            errorContext,
          }) async {
            reportedSignals.add(
              _CapturedInfoSignal(
                fingerprint: fingerprint,
                message: message,
                errorContext: errorContext,
              ),
            );
          },
        );

        await service.scheduleRestPings(
          restStartMs: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
          intervalSecs: 60,
          soundId: 'boxing_bell',
        );

        expect(scheduledIds, isNotEmpty);
        expect(reportedErrors, isEmpty);
        expect(reportedSignals, isNotEmpty);
        expect(reportedSignals.first.fingerprint,
            RestNotificationService.cacheSchemaErrorFingerprint);
      },
    );

    test(
      'non-matching notification PlatformException still reports at full '
      'severity (suppression does not widen)',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedErrors = <Object>[];
        final reportedSignals = <_CapturedInfoSignal>[];

        final service = RestNotificationService.withPlugin(
          plugin,
          cancelOverride: (_) async {
            throw PlatformException(
              // Same error category, but the message and stack do NOT
              // match the cache-schema signature — must NOT be
              // suppressed.
              code: 'security_exception',
              message: 'Notification permission denied',
            );
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
          reportInfoSignalOverride: ({
            required fingerprint,
            required message,
            errorContext,
          }) async {
            reportedSignals.add(
              _CapturedInfoSignal(
                fingerprint: fingerprint,
                message: message,
                errorContext: errorContext,
              ),
            );
          },
        );

        await service.cancelEffortTimerNotification();

        expect(reportedErrors, hasLength(1));
        expect(reportedErrors.single, isA<PlatformException>());
        expect(reportedSignals, isEmpty);
      },
    );

    test(
      'cache-schema info signal carries the stable fingerprint used for '
      'rate-threshold alerting',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedSignals = <_CapturedInfoSignal>[];

        final service = RestNotificationService.withPlugin(
          plugin,
          cancelOverride: (_) async {
            throw PlatformException(
              code: 'error',
              message: 'Missing type parameter.',
              stacktrace:
                  'java.lang.RuntimeException: Missing type parameter.\n'
                  '\tat com.google.gson.reflect.a.getSuperclassTypeParameter',
            );
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {},
          reportInfoSignalOverride: ({
            required fingerprint,
            required message,
            errorContext,
          }) async {
            reportedSignals.add(
              _CapturedInfoSignal(
                fingerprint: fingerprint,
                message: message,
                errorContext: errorContext,
              ),
            );
          },
        );

        await service.cancelEffortTimerNotification();

        // The fingerprint must be stable AND specific enough that a
        // rate-threshold alert can be attached. This guards against
        // a future refactor accidentally widening or renaming the
        // identity — alerting would silently break.
        expect(reportedSignals, hasLength(1));
        expect(reportedSignals.single.fingerprint,
            RestNotificationService.cacheSchemaErrorFingerprint);
        expect(reportedSignals.single.fingerprint, isNotEmpty);
        // Distinct from a generic notification-failure fingerprint.
        expect(
          reportedSignals.single.fingerprint,
          isNot(equals('notification.failure')),
        );
      },
    );
  });
}

/// Test-side snapshot of the low-severity info-signal payload. The
/// production path records via [CrashReportingService.recordInfoSignal];
/// tests use the override to capture the same shape.
class _CapturedInfoSignal {
  _CapturedInfoSignal({
    required this.fingerprint,
    required this.message,
    required this.errorContext,
  });

  final String fingerprint;
  final String message;
  final String? errorContext;
}
