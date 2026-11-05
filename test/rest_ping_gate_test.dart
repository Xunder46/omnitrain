import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // Harness copied from test/rest_notification_service_test.dart:27:
  // pinned nowProvider, capture overrides, isWeb: false.
  setUpAll(() {
    if (tz.timeZoneDatabase.locations.isEmpty) {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  });

  final now = DateTime.utc(2026, 10, 26, 12);
  final nowMs = now.millisecondsSinceEpoch;

  RestNotificationService buildService({
    required List<int> scheduledIds,
    required List<int> canceledIds,
    Completer<void>? blockFirstSchedule,
  }) {
    var blockedUsed = false;
    return RestNotificationService.withPlugin(
      FlutterLocalNotificationsPlugin(),
      isWeb: false,
      nowProvider: () => now,
      cancelOverride: (id) async => canceledIds.add(id),
      zonedScheduleOverride: ({
        required id,
        required title,
        required body,
        required scheduledDate,
        required details,
      }) async {
        if (blockFirstSchedule != null && !blockedUsed) {
          blockedUsed = true;
          await blockFirstSchedule.future;
        }
        scheduledIds.add(id);
      },
    );
  }

  group('S-15602 gate true', () {
    test('scheduleRestPings schedules nothing and cancels the 50 ping ids', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
      );
      service.wristOwnsPings = () => true;

      await service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 30,
        soundId: 'soft_chime',
      );

      expect(scheduledIds, isEmpty);
      expect(canceledIds.length, RestNotificationService.maxRestPings);
      expect(canceledIds.first, RestNotificationService.restPingBaseId);
      expect(canceledIds.last, RestNotificationService.restPingBaseId + 49);
    });
  });

  group('S-15603 gate null', () {
    test('scheduleRestPings schedules the future boundaries exactly as today', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
      );

      await service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 30,
        soundId: 'soft_chime',
      );

      expect(scheduledIds.length, RestNotificationService.maxRestPings);
      expect(scheduledIds.first, RestNotificationService.restPingBaseId);
      expect(
        scheduledIds,
        List.generate(RestNotificationService.maxRestPings,
            (i) => RestNotificationService.restPingBaseId + i),
      );
    });
  });

  group('S-15604 reevaluate after the gate flips', () {
    test('gate true->false schedules the 48 future boundaries; false->true cancels', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
      );
      var gate = true;
      service.wristOwnsPings = () => gate;

      // Remembered under a true gate: nothing scheduled, 50 cancels.
      await service.scheduleRestPings(
        restStartMs: nowMs - 70000,
        intervalSecs: 30,
        soundId: 'soft_chime',
      );
      expect(scheduledIds, isEmpty);
      expect(canceledIds.length, 50);

      // Gate flips true -> false: the remaining boundaries from the
      // rest's own start; 30 s and 60 s are in the past at the pinned
      // now, so 48 schedules, ids 102..149.
      gate = false;
      await service.reevaluate();
      expect(scheduledIds.length, 48);
      expect(
        scheduledIds,
        List.generate(48, (i) => RestNotificationService.restPingBaseId + 2 + i),
      );

      // Gate flips false -> true: withdraw what was scheduled.
      gate = true;
      await service.reevaluate();
      expect(scheduledIds.length, 48);
      expect(canceledIds.length, 150);
      expect(
        canceledIds.sublist(100),
        List.generate(RestNotificationService.maxRestPings,
            (i) => RestNotificationService.restPingBaseId + i),
      );
    });
  });

  group('S-15605 reevaluate with nothing remembered', () {
    test('does nothing before a request and after cancelRestNotifications', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
      );
      service.wristOwnsPings = () => false;

      await service.reevaluate();
      expect(scheduledIds, isEmpty);
      expect(canceledIds, isEmpty);

      await service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 30,
        soundId: 'soft_chime',
      );
      expect(scheduledIds.length, 50);

      await service.cancelRestNotifications();
      expect(canceledIds.length, 100);

      // The request was forgotten: reevaluate schedules nothing and
      // issues no extra cancels.
      await service.reevaluate();
      expect(scheduledIds.length, 50);
      expect(canceledIds.length, 100);
    });
  });

  group('S-15606 interval 0', () {
    test('nothing scheduled at either gate and reevaluate keeps it so', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
      );

      await service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 0,
        soundId: 'soft_chime',
      );
      expect(scheduledIds, isEmpty);
      expect(canceledIds.length, 50);

      await service.reevaluate();
      expect(scheduledIds, isEmpty);

      service.wristOwnsPings = () => true;
      await service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 0,
        soundId: 'soft_chime',
      );
      await service.reevaluate();
      expect(scheduledIds, isEmpty);
    });
  });

  group('rest ping queue', () {
    test('overlapping scheduleRestPings and reevaluate finish in order with no interleaved ids', () async {
      final scheduledIds = <int>[];
      final canceledIds = <int>[];
      final firstScheduleBlocked = Completer<void>();
      final service = buildService(
        scheduledIds: scheduledIds,
        canceledIds: canceledIds,
        blockFirstSchedule: firstScheduleBlocked,
      );

      final first = service.scheduleRestPings(
        restStartMs: nowMs - 5000,
        intervalSecs: 30,
        soundId: 'soft_chime',
      );
      // Let pass 1 run until it blocks inside its first schedule.
      await pumpEventQueue();
      final second = service.reevaluate();
      firstScheduleBlocked.complete();
      await first;
      await second;

      // Pass 1 scheduled ids 100..149, then pass 2 re-ran the same
      // remembered request: no interleaving.
      final onePass = List.generate(
          RestNotificationService.maxRestPings,
          (i) => RestNotificationService.restPingBaseId + i);
      expect(scheduledIds, [...onePass, ...onePass]);
    });
  });
}
