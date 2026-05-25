import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
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
  });
}
