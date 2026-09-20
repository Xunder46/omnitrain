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
    case HealthActivityKind.conditioning:
      return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
    case HealthActivityKind.other:
      return HealthWorkoutActivityType.OTHER;
  }
}

/// `health`-package-backed gateway. Constructed only on iOS/Android —
/// see [createHealthPlatformService].
class HealthPluginPlatformService implements HealthPlatformService {
  final Health _health = Health();

  @override
  Future<bool> requestWritePermission() async {
    return _requestPermission([HealthDataType.WORKOUT], write: true);
  }

  @override
  Future<bool> requestReadPermission() async {
    return _requestPermission([HealthDataType.WEIGHT], write: false);
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async {
    try {
      return await _health.writeWorkoutData(
        activityType: pluginActivityTypeFor(
          workout.activityKind,
          isIOS: Platform.isIOS,
        ),
        start: workout.start,
        end: workout.end,
        title: workout.title,
      );
    } catch (e) {
      debugPrint('Health write skipped (${workout.activityKind.name}): $e');
      return false;
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
        permissions: [write ? HealthDataAccess.WRITE : HealthDataAccess.READ],
      );
    } catch (e) {
      debugPrint('Health permission request failed: $e');
      return false;
    }
  }
}
