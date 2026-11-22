/// The Wear wrist's sensors: `WatchSensorSource` over the platform channels the
/// native half answers.
///
/// Plan: `docs/plans/2026-11-22-297-wear-sensor-seam-plan/2026-11-22-297-wear-sensor-seam-plan.md`
/// (D-29701..D-29703). This file fixes the contract the Kotlin half implements
/// (plans 298 heart rate, 299 distance):
///
/// - `MethodChannel('omnitrain/wear_sensors/methods')`: `heartRatePermission`
///   and `locationPermission`, each answering `'granted'`, `'denied'` or
///   `'unavailable'`. A call asks the user first when the state is
///   undetermined; the native half owns the prompt.
/// - `EventChannel('omnitrain/wear_sensors/heart_rate')`: numbers, beats per
///   minute.
/// - `EventChannel('omnitrain/wear_sensors/location')`: numbers, cumulative
///   metres since the session started.
///
/// Until the native half exists every call fails with a `MissingPluginException`
/// and reads as `unavailable`, so the wrist behaves as it did before sensors.
/// Logging never depends on a sensor: nothing here throws to its caller.
library;

import 'package:flutter/services.dart';

import 'watch_platform_workout.dart';
import 'watch_sensor_recording.dart';

class WearSensorSource implements WatchSensorSource {
  WearSensorSource({
    MethodChannel? methods,
    EventChannel? heartRateEvents,
    EventChannel? locationEvents,
  }) : _methods = methods ?? const MethodChannel(methodsName),
       _heartRateEvents = heartRateEvents ?? const EventChannel(heartRateName),
       _locationEvents = locationEvents ?? const EventChannel(locationName);

  static const String methodsName = 'omnitrain/wear_sensors/methods';
  static const String heartRateName = 'omnitrain/wear_sensors/heart_rate';
  static const String locationName = 'omnitrain/wear_sensors/location';

  final MethodChannel _methods;
  final EventChannel _heartRateEvents;
  final EventChannel _locationEvents;

  @override
  Future<WatchSensorPermission> heartRatePermission() =>
      _permission('heartRatePermission');

  @override
  Future<WatchSensorPermission> locationPermission() =>
      _permission('locationPermission');

  @override
  Stream<double> heartRate() => _numbers(_heartRateEvents);

  @override
  Stream<WatchLocationFix> location() => _numbers(
    _locationEvents,
  ).map((metres) => WatchLocationFix(distanceMeters: metres));

  /// The platform's answer, with every failure read as "nothing to ask".
  Future<WatchSensorPermission> _permission(String method) async {
    try {
      final answer = await _methods.invokeMethod<String>(method);
      return switch (answer) {
        'granted' => WatchSensorPermission.granted,
        'denied' => WatchSensorPermission.denied,
        _ => WatchSensorPermission.unavailable,
      };
    } on Object {
      return WatchSensorPermission.unavailable;
    }
  }

  /// The channel's numbers as doubles: an error ends nothing and reaches no
  /// listener, and anything that is not a number is dropped (D-29702).
  static Stream<double> _numbers(EventChannel channel) => channel
      .receiveBroadcastStream()
      .handleError((Object _) {})
      .where((event) => event is num)
      .map((event) => (event as num).toDouble());
}

/// The Wear wrist's platform workout store: opens nothing and closes nothing.
/// The Health Services exercise session is plan 300 (D-29703); until then the
/// wrist registers no workout with the platform and there is nothing stranded to
/// recover.
class WearPlatformWorkoutStore implements WatchPlatformWorkoutStore {
  const WearPlatformWorkoutStore();

  @override
  Future<void> begin(String activityType) async {}

  @override
  Future<void> end() async {}

  @override
  Future<List<String>> inProgressActivityTypes() async => const [];
}
