// filepath: lib/core/services/health_platform_gateway_io.dart
//
// Native gateway for the platform health store, backed by the `health`
// package (13.x), which covers Apple Health (HealthKit) and Android
// Health Connect behind one API. Plugin decision per the plan
// (`2026-07-13-04-pr3-platform-health-integration-plan.md`, step 1):
// one package for both platforms rather than two SDK-specific
// integrations.
//
// Platform facts that shape this file:
//
//   * `health` imports `dart:io`, so it is only ever compiled into the
//     io variant of `health_platform_gateway.dart`.
//   * `writeWorkoutData` validates the activity type against the
//     current platform's set and throws `HealthException` on a
//     cross-over, so kinds translate per platform.
//   * Every public method swallows platform errors and reports failure
//     (false / empty list) — the contract documented on
//     [HealthPlatformService].

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../constants/health_constants.dart';
import 'health_platform_service.dart';

/// Creates the platform gateway. Desktop targets have no writable health
/// store, so they get the no-op gateway and keep the app fully usable.
HealthPlatformService createHealthPlatformService() {
  if (!Platform.isIOS && !Platform.isAndroid) {
    return const UnavailableHealthPlatformService();
  }
  return HealthPluginPlatformService();
}

/// Translates an app-owned activity kind to a platform activity type.
///
/// The per-platform split is mandatory, not cosmetic: several workout
/// types exist on exactly one platform (TRADITIONAL_STRENGTH_TRAINING
/// and FLEXIBILITY are iOS-only; STRENGTH_TRAINING is Android-only) and
/// crossing them throws. The chosen values are pinned by
/// `test/health_platform_mapper_test.dart`.
///
/// Where the app cannot be more specific than the modality (cardio and
/// sport cover many activities), the generic OTHER type is used instead
/// of guessing a discipline the session does not record.
HealthWorkoutActivityType pluginActivityTypeFor(
  HealthActivityKind kind, {
  required bool isIOS,
}) {
  switch (kind) {
    case HealthActivityKind.strength:
      return isIOS
          ? HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING
          : HealthWorkoutActivityType.STRENGTH_TRAINING;
    case HealthActivityKind.cardio:
      return HealthWorkoutActivityType.OTHER;
    case HealthActivityKind.flexibility:
      // FLEXIBILITY is iOS-only, and Health Connect has no stretching
      // type exposed by this plugin — Android falls back to the generic
      // type rather than mislabelling stretching as, say, YOGA.
      return isIOS
          ? HealthWorkoutActivityType.FLEXIBILITY
          : HealthWorkoutActivityType.OTHER;
    case HealthActivityKind.sport:
      return HealthWorkoutActivityType.OTHER;
    case HealthActivityKind.yoga:
      // HealthKit's YOGA and Health Connect's YOGA are both in the plugin's
      // platform sets (health 13.3.1: _isOnIOS/_isOnAndroid carry it).
      return HealthWorkoutActivityType.YOGA;
    case HealthActivityKind.conditioning:
      return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
    case HealthActivityKind.other:
      return HealthWorkoutActivityType.OTHER;
  }
}

/// One active-energy sample as the pure bucketing sees it: when it started and
/// its kcal, or null for a value that is not numeric.
typedef ActiveEnergyPoint = ({DateTime dateFrom, num? kcal});

/// One day's query: [start, end) and the interval length in seconds.
typedef ActiveEnergyDayQuery =
    Future<List<ActiveEnergyPoint>> Function(
      DateTime start,
      DateTime end,
      int intervalSeconds,
    );

/// The local day that begins at [dayStart]: from its local midnight to the NEXT
/// local midnight by calendar arithmetic, so a DST day is 23 h or 25 h long.
({DateTime start, DateTime end, int seconds}) activeEnergyDayBounds(
  DateTime dayStart,
) {
  final start = DateTime(dayStart.year, dayStart.month, dayStart.day);
  final end = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
  return (start: start, end: end, seconds: end.difference(start).inSeconds);
}

/// Sums [points] per local day. A point belongs to the day in [dayStarts]
/// whose bounds contain its `dateFrom` (`start <= dateFrom < end`); points of
/// one day are summed; a non-numeric point (kcal null) is skipped and never
/// creates a day. A day with at least one numeric point is in the result, even
/// when the sum is 0.0. Keys are the day-start epoch milliseconds.
Map<int, double> activeEnergyTotalsByDay({
  required List<DateTime> dayStarts,
  required Iterable<ActiveEnergyPoint> points,
}) {
  final totals = <int, double>{};
  for (final day in dayStarts) {
    final bounds = activeEnergyDayBounds(day);
    for (final p in points) {
      final kcal = p.kcal;
      if (kcal == null) continue;
      if (p.dateFrom.isBefore(bounds.start) ||
          !p.dateFrom.isBefore(bounds.end)) {
        continue;
      }
      final key = bounds.start.millisecondsSinceEpoch;
      totals[key] = (totals[key] ?? 0.0) + kcal.toDouble();
    }
  }
  return totals;
}

/// The Runner's own Workout Effort channel (plan 90 D-6,
/// `ios/Runner/HealthEffortChannel.swift`). iOS only.
const String healthEffortChannelName = 'omnitrain/health_effort';

/// `health`-package-backed gateway. Constructed only on iOS/Android —
/// see [createHealthPlatformService]. [isIOS] and [effortChannel] are
/// injectable so the iOS-only channel use is testable off device.
/// [dayQuery] overrides the plugin's per-day interval query, so the
/// active-energy read (plan 208 D-18) is testable on the host.
class HealthPluginPlatformService
    implements HealthPlatformService, HealthActiveEnergySource {
  HealthPluginPlatformService({
    bool? isIOS,
    MethodChannel? effortChannel,
    ActiveEnergyDayQuery? dayQuery,
  }) : _isIOS = isIOS ?? Platform.isIOS,
       _effortChannel =
           effortChannel ?? const MethodChannel(healthEffortChannelName),
       _dayQueryOverride = dayQuery;

  final Health _health = Health();
  final bool _isIOS;
  final MethodChannel _effortChannel;
  final ActiveEnergyDayQuery? _dayQueryOverride;

  /// Switching "Write workouts" on also asks for Workout Effort (plan 90
  /// OQ-4). The effort request goes first and includes the workout type, so
  /// the owner sees one Health sheet; its answer never decides the result.
  @override
  Future<bool> requestWritePermission() async {
    await _invokeEffort('requestAuthorization');
    // Health Connect inserts the exercise session and its calories in one call
    // (plan 307 D-30705), so the calories permission is asked with the
    // workout's; iOS has no such type here.
    return _requestPermission([
      HealthDataType.WORKOUT,
      if (!_isIOS) HealthDataType.TOTAL_CALORIES_BURNED,
    ], write: true);
  }

  @override
  Future<bool> requestReadPermission() async {
    return _requestPermission([HealthDataType.WEIGHT], write: false);
  }

  @override
  Future<bool> requestActiveEnergyReadPermission() =>
      _requestPermission([HealthDataType.ACTIVE_ENERGY_BURNED], write: false);

  @override
  Future<Map<int, double>> readDailyActiveEnergy(
    List<DateTime> dayStarts,
  ) async {
    final query = _dayQueryOverride ?? _pluginDayQuery;
    final totals = <int, double>{};
    for (final day in dayStarts) {
      final bounds = activeEnergyDayBounds(day);
      try {
        final points = await query(bounds.start, bounds.end, bounds.seconds);
        totals.addAll(
          activeEnergyTotalsByDay(dayStarts: [bounds.start], points: points),
        );
      } catch (e) {
        // A day whose query fails (Health Connect missing, a plugin error) is
        // left out; the other days stand. Never throws (D-18).
        debugPrint('Health active energy read skipped (${bounds.start}): $e');
      }
    }
    return totals;
  }

  /// The plugin call behind the seam: iOS runs HealthKit's statistics sum,
  /// Android Health Connect's `aggregateGroupByDuration`, one query per local
  /// day.
  Future<List<ActiveEnergyPoint>> _pluginDayQuery(
    DateTime start,
    DateTime end,
    int intervalSeconds,
  ) async {
    final points = await _health.getHealthIntervalDataFromTypes(
      startDate: start,
      endDate: end,
      types: [HealthDataType.ACTIVE_ENERGY_BURNED],
      interval: intervalSeconds,
    );
    return [
      for (final p in points)
        (
          dateFrom: p.dateFrom,
          kcal: p.value is NumericHealthValue
              ? (p.value as NumericHealthValue).numericValue
              : null,
        ),
    ];
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    final energy = workout.energyKcal;
    final kcal = energy == null || !energy.isFinite || energy <= 0
        ? null
        : energy.round();
    // Health Connect writes the session and its calories in one all-or-nothing
    // call, so a missing calories permission fails the whole write; the
    // workout is then written without them (plan 307 D-30705).
    if (kcal != null && kcal > 0) {
      if (await _writeWorkoutOnce(workout, kcal)) return true;
    }
    return _writeWorkoutOnce(workout, null);
  }

  Future<bool> _writeWorkoutOnce(HealthWorkoutDraft workout, int? kcal) async {
    try {
      return await _health.writeWorkoutData(
        activityType: pluginActivityTypeFor(
          workout.activityKind,
          isIOS: Platform.isIOS,
        ),
        start: workout.start,
        end: workout.end,
        totalEnergyBurned: kcal,
        title: workout.title,
      );
    } catch (e) {
      debugPrint('Health write skipped (${workout.activityKind.name}): $e');
      return false;
    }
  }

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async {
    try {
      // iOS: the plugin deletes only this app's own workouts whose start
      // lies in [start, end) (`.strictStartDate` + `HKSource.default()`),
      // so a back-to-back neighbour or another app's workout is never hit.
      return await _health.delete(
        type: HealthDataType.WORKOUT,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      debugPrint('Health workout delete skipped: $e');
      return false;
    }
  }

  // Plan 90 D-1, D-6, D-7: the `health` plugin has no Workout Effort
  // support, so these go through the Runner's own channel on iOS only;
  // Android answers "unavailable" without any work.
  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async {
    final answer = await _invokeEffort('set', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'score': score,
    });
    return HealthEffortOutcome.values.firstWhere(
      (outcome) => outcome.name == answer,
      orElse: () => HealthEffortOutcome.unavailable,
    );
  }

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async {
    final answer = await _invokeEffort('clear', {
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return answer == 'cleared';
  }

  /// The channel's string answer, or null off iOS or on any error.
  Future<String?> _invokeEffort(String method, [Object? arguments]) async {
    if (!_isIOS) return null;
    try {
      final answer = await _effortChannel.invokeMethod<Object?>(
        method,
        arguments,
      );
      return answer is String ? answer : null;
    } catch (e) {
      debugPrint('Health effort $method skipped: $e');
      return null;
    }
  }

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async {
    try {
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: since,
        endTime: DateTime.now(),
      );

      final samples = <HealthWeightSample>[];
      for (final point in points) {
        final value = point.value;
        if (value is! NumericHealthValue) continue;
        samples.add(
          HealthWeightSample(
            sourceId: point.uuid,
            sampledAt: point.dateFrom,
            kilograms: weightToKilograms(
              value: value.numericValue.toDouble(),
              unitLabel: point.unit.name,
            ),
          ),
        );
      }
      return samples;
    } catch (e) {
      debugPrint('Health body weight read skipped: $e');
      return const [];
    }
  }

  Future<bool> _requestPermission(
    List<HealthDataType> types, {
    required bool write,
  }) async {
    try {
      return await _health.requestAuthorization(
        types,
        // One access entry per type: the plugin refuses a list of another
        // length (plan 307: the workout and its calories are asked together).
        permissions: List.filled(
          types.length,
          write ? HealthDataAccess.WRITE : HealthDataAccess.READ,
        ),
      );
    } catch (e) {
      debugPrint('Health permission request failed: $e');
      return false;
    }
  }
}
