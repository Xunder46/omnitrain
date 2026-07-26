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

      // The audible attempt reports one error, the silent retry reports
      // a second one. The original swallowing contract still holds: the
      // exception never propagates to the caller.
      expect(reportedErrors.length, 2);
      expect(reportedErrors.every((e) => e is PlatformException), isTrue);
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

    // -------------------------------------------------------------------------
    // Silent-fallback tests.
    //
    // These cover the production Sentry error
    //   "PlatformException(invalid_sound, The resource boxing_bell could not
    //   be found. Please make sure it has been added as a raw resource to
    //   your Android head project.)"
    //
    // The contract under test: an audible schedule failure must NEVER
    // interrupt a workout. The method swallows the failure, falls back to a
    // silent schedule for the SAME notification ID, and only if the silent
    // retry also fails does it report and move on. Verifying the five files
    // exist in res/raw/ is a build / on-device concern; the fallback is
    // what guarantees the workout keeps going even when they do not.
    // -------------------------------------------------------------------------

    test(
      'scheduleRestPings silent-fallback: when the audible schedule throws '
      'invalid_sound, the same notification ID is retried silently and the '
      'method never propagates the exception',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedErrors = <Object>[];
        final scheduledCalls = <_CapturedScheduleCall>[];
        var firstAttemptForId = <int>{};

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
            scheduledCalls.add(
              _CapturedScheduleCall(
                id: id,
                title: title,
                body: body,
                playSound:
                    (details.android as AndroidNotificationDetails).playSound,
                androidSound:
                    (details.android as AndroidNotificationDetails).sound?.sound,
              ),
            );
            if (firstAttemptForId.add(id)) {
              throw PlatformException(
                code: 'invalid_sound',
                message:
                    'The resource boxing_bell could not be found. '
                    'Please make sure it has been added as a raw resource '
                    'to your Android head project.',
              );
            }
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
        );

        // The call must complete without propagating the PlatformException
        // out to the caller — that is the whole point of the fallback.
        await service.scheduleRestPings(
          restStartMs: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
          intervalSecs: 60,
          soundId: 'boxing_bell',
        );

        // For every scheduled notification ID, the audible attempt throws
        // and the silent attempt must succeed. So we expect exactly two
        // calls per id, and the second must be silent with no sound.
        final ids = scheduledCalls.map((c) => c.id).toSet();
        expect(ids, isNotEmpty);
        for (final id in ids) {
          final calls = scheduledCalls.where((c) => c.id == id).toList();
          expect(
            calls,
            hasLength(2),
            reason: 'expected one audible + one silent attempt for id=$id',
          );
          expect(calls.first.playSound, isTrue);
          expect(calls.first.androidSound, 'boxing_bell');
          expect(calls.last.playSound, isFalse);
          expect(calls.last.androidSound, isNull);
        }
        // The audible failure surfaces as a non-fatal error — one per id.
        expect(reportedErrors.whereType<PlatformException>(), hasLength(ids.length));
      },
    );

    test(
      'scheduleRestPings silent-fallback: silent retry preserves the same '
      'title, body, and scheduled time as the audible attempt',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final scheduledCalls = <_CapturedScheduleCall>[];
        var firstAttemptForId = <int>{};

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
            scheduledCalls.add(
              _CapturedScheduleCall(
                id: id,
                title: title,
                body: body,
                playSound:
                    (details.android as AndroidNotificationDetails).playSound,
                androidSound:
                    (details.android as AndroidNotificationDetails).sound?.sound,
                scheduledDate: scheduledDate,
              ),
            );
            if (firstAttemptForId.add(id)) {
              throw PlatformException(
                code: 'invalid_sound',
                message: 'The resource soft_chime could not be found.',
              );
            }
          },
        );

        await service.scheduleRestPings(
          restStartMs: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
          intervalSecs: 60,
          soundId: 'soft_chime',
        );

        // Group by id; the two attempts must agree on every field except
        // the sound attachment and playSound flag.
        final byId = <int, List<_CapturedScheduleCall>>{};
        for (final c in scheduledCalls) {
          byId.putIfAbsent(c.id, () => []).add(c);
        }
        expect(byId, isNotEmpty);
        byId.forEach((id, calls) {
          expect(calls, hasLength(2), reason: 'id=$id');
          final audible = calls.first;
          final silent = calls.last;
          expect(silent.title, audible.title, reason: 'title must match for id=$id');
          expect(silent.body, audible.body, reason: 'body must match for id=$id');
          expect(
            silent.scheduledDate,
            audible.scheduledDate,
            reason: 'scheduledDate must match for id=$id',
          );
        });
      },
    );

    test(
      'scheduleEffortTimerExpiry silent-fallback: when the audible schedule '
      'throws invalid_sound, the SAME notification ID is retried silently '
      'and the method does not propagate',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedErrors = <Object>[];
        final scheduledCalls = <_CapturedScheduleCall>[];

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
            scheduledCalls.add(
              _CapturedScheduleCall(
                id: id,
                title: title,
                body: body,
                playSound:
                    (details.android as AndroidNotificationDetails).playSound,
                androidSound:
                    (details.android as AndroidNotificationDetails).sound?.sound,
              ),
            );
            if (scheduledCalls.length == 1) {
              throw PlatformException(
                code: 'invalid_sound',
                message: 'The resource boxing_bell could not be found.',
              );
            }
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
        );

        // The call must complete — no rethrow, no PlatformException
        // surfaces to the caller.
        await service.scheduleEffortTimerExpiry(
          fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 15).millisecondsSinceEpoch,
          soundId: 'boxing_bell',
        );

        // The same notification ID is used for both attempts; the second
        // must be silent with no sound attached.
        expect(scheduledCalls, hasLength(2));
        expect(
          scheduledCalls.every(
            (c) => c.id == RestNotificationService.effortTimerNotificationId,
          ),
          isTrue,
        );
        expect(scheduledCalls.first.playSound, isTrue);
        expect(scheduledCalls.first.androidSound, 'boxing_bell');
        expect(scheduledCalls.last.playSound, isFalse);
        expect(scheduledCalls.last.androidSound, isNull);
        // The audible failure is reported; the silent success is not.
        expect(reportedErrors.whereType<PlatformException>(), hasLength(1));
      },
    );

    test(
      'scheduleEffortTimerExpiry silent-fallback: when playSound is already '
      'false, a failure is reported but no silent retry is made (the user '
      'already asked for silent)',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final reportedErrors = <Object>[];
        final scheduledCalls = <_CapturedScheduleCall>[];

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
            scheduledCalls.add(
              _CapturedScheduleCall(
                id: id,
                title: title,
                body: body,
                playSound:
                    (details.android as AndroidNotificationDetails).playSound,
                androidSound:
                    (details.android as AndroidNotificationDetails).sound?.sound,
              ),
            );
            throw PlatformException(
              code: 'invalid_sound',
              message: 'noop sound cannot play',
            );
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
        );

        await service.scheduleEffortTimerExpiry(
          fireAtMs: DateTime.utc(2026, 1, 1, 12, 0, 15).millisecondsSinceEpoch,
          soundId: 'boxing_bell',
          playSound: false,
        );

        // Only one call should have been made — the user already asked
        // for a silent alert, so there is nothing to retry against. The
        // call still carries the `soundId` attachment (the platform uses
        // `playSound: false` to suppress playback), but the device will
        // not play it.
        expect(scheduledCalls, hasLength(1));
        expect(scheduledCalls.single.playSound, isFalse);
        expect(scheduledCalls.single.androidSound, 'boxing_bell');
        expect(reportedErrors.whereType<PlatformException>(), hasLength(1));
      },
    );

    test(
      'initialize / _createAndroidChannels: a per-sound channel-creation '
      'failure does not abort the remaining channels or rethrow',
      () async {
        final plugin = FlutterLocalNotificationsPlugin();
        final createdChannels = <String>[];
        final reportedErrors = <Object>[];

        // Boxing bell fails; the other four must still get created. The
        // `androidChannelCreateOverride` stands in for
        // `AndroidFlutterLocalNotificationsPlugin.createNotificationChannel`
        // because that method is only reachable through
        // `resolvePlatformSpecificImplementation`, which returns null in
        // the unit-test environment. The `pluginInitializeOverride`
        // short-circuits the real platform-channel call that would
        // otherwise throw `MissingPluginException` here.
        final service = RestNotificationService.withPlugin(
          plugin,
          pluginInitializeOverride: (
            settings, {
            onDidReceiveNotificationResponse,
            onDidReceiveBackgroundNotificationResponse,
          }) async {},
          androidChannelCreateOverride: (channel) async {
            if (channel.id == 'rest_pings_boxing_bell') {
              throw PlatformException(
                code: 'channel_creation_failed',
                message: 'channel ${channel.id} could not be created',
              );
            }
            createdChannels.add(channel.id);
          },
          reportErrorOverride: (error, {stackTrace, errorContext}) async {
            reportedErrors.add(error);
          },
        );

        // initialize() must complete normally even when a channel fails.
        await service.initialize();

        // Every sound got an attempt; the four that did not fail must
        // appear in the recorded set, the one that did must not.
        expect(createdChannels, isNotEmpty);
        expect(createdChannels, contains('rest_pings_digital_buzzer'));
        expect(createdChannels, contains('rest_pings_soft_chime'));
        expect(createdChannels, contains('rest_pings_double_tap'));
        expect(createdChannels, contains('rest_pings_signal_tone'));
        expect(createdChannels, isNot(contains('rest_pings_boxing_bell')));
        // The failure is observable as a non-fatal error so a regression
        // is detectable, but the app keeps running.
        expect(reportedErrors, hasLength(1));
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

/// Test-side snapshot of a single [FlutterLocalNotificationsPlugin.zonedSchedule]
/// invocation. Captures everything the silent-fallback tests need to
/// compare the audible attempt against the silent retry.
class _CapturedScheduleCall {
  _CapturedScheduleCall({
    required this.id,
    required this.title,
    required this.body,
    required this.playSound,
    required this.androidSound,
    this.scheduledDate,
  });

  final int id;
  final String title;
  final String body;
  final bool playSound;
  final String? androidSound;
  final tz.TZDateTime? scheduledDate;
}
