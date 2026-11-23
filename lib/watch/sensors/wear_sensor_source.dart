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

class WearSensorSource
    implements WatchSensorSource, WatchEnergySource, WatchNotificationSource {
  WearSensorSource({
    MethodChannel? methods,
    EventChannel? heartRateEvents,
    EventChannel? locationEvents,
    EventChannel? energyEvents,
  }) : _methods = methods ?? const MethodChannel(methodsName),
       _heartRateEvents = heartRateEvents ?? const EventChannel(heartRateName),
       _locationEvents = locationEvents ?? const EventChannel(locationName),
       _energyEvents = energyEvents ?? const EventChannel(energyName);

  static const String methodsName = 'omnitrain/wear_sensors/methods';
  static const String heartRateName = 'omnitrain/wear_sensors/heart_rate';
  static const String locationName = 'omnitrain/wear_sensors/location';

  /// Cumulative kilocalories of the platform workout (plan 305, D-30507): the
  /// native half answers `activeEnergyPermission` on the methods channel and
  /// streams the numbers here.
  static const String energyName = 'omnitrain/wear_sensors/energy';

  final MethodChannel _methods;
  final EventChannel _heartRateEvents;
  final EventChannel _locationEvents;
  final EventChannel _energyEvents;

  @override
  Future<WatchSensorPermission> heartRatePermission() =>
      _permission('heartRatePermission');

  @override
  Future<WatchSensorPermission> locationPermission() =>
      _permission('locationPermission');

  /// A refusal is remembered for the life of the process (plan 306, D-30608):
  /// the workout asks before it starts and the recorder asks again, and Android
  /// shows the prompt a second time after a first "Don't allow".
  bool _energyRefused = false;

  @override
  Future<WatchSensorPermission> activeEnergyPermission() async {
    if (_energyRefused) return WatchSensorPermission.denied;
    final answer = await _permission('activeEnergyPermission');
    if (answer == WatchSensorPermission.denied) _energyRefused = true;
    return answer;
  }

  @override
  Stream<double> activeEnergy() => _numbers(_energyEvents);

  /// A refusal is remembered for the life of the process, like the calories one
  /// (plan 309): the question is asked once per run.
  bool _notificationRefused = false;

  @override
  Future<WatchSensorPermission> notificationPermission() async {
    if (_notificationRefused) return WatchSensorPermission.denied;
    final answer = await _permission('notificationPermission');
    if (answer == WatchSensorPermission.denied) _notificationRefused = true;
    return answer;
  }

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

/// The Wear wrist's platform workout (plan 300, D-30001): a Health Services
/// exercise, over `MethodChannel('omnitrain/wear_workout/methods')` with
/// `begin(<Health Connect type name>)`, `end()` and `inProgress()` (a list of
/// names). The Kotlin half is `WearWorkout`.
///
/// Logging never depends on a platform workout: `begin` does nothing unless the
/// heart-rate permission is held (the exercise needs the body-sensor permission,
/// and the shell starts the workout before the recorder asks), and every
/// platform failure reads as "nothing happened".
class WearPlatformWorkoutStore implements WatchPlatformWorkoutStore {
  WearPlatformWorkoutStore({
    required WatchSensorSource source,
    MethodChannel? methods,
  }) : _source = source,
       _methods = methods ?? const MethodChannel(methodsName);

  static const String methodsName = 'omnitrain/wear_workout/methods';

  final WatchSensorSource _source;
  final MethodChannel _methods;

  @override
  Future<void> begin(String activityType) async {
    try {
      if (await _source.heartRatePermission() !=
          WatchSensorPermission.granted) {
        return;
      }
      await _askEnergy();
      await _askNotifications();
      await _methods.invokeMethod<void>(
        'begin',
        WatchActivityTypes.wearFor(activityType),
      );
    } on Object {
      return;
    }
  }

  /// The notification permission, asked after the calories one and before the
  /// workout starts (plan 309): the chip on the watch face needs the notification
  /// the workout's service posts. The answer is not needed here; a source without
  /// the question asks nothing, and a workout without the chip is still a workout.
  Future<void> _askNotifications() async {
    final Object source = _source;
    if (source is! WatchNotificationSource) return;
    try {
      await source.notificationPermission();
    } on Object {
      // No chip, no failure.
    }
  }

  /// The calorie permission, asked before the workout starts (plan 306,
  /// D-30606): the native half fixes the exercise's data types at start and
  /// reads the held permission itself, so the answer is not needed here. The
  /// shell starts the workout before the recorder asks, which is why this
  /// cannot wait for it. A source without energy asks nothing.
  Future<void> _askEnergy() async {
    // Tested as an Object: the two interfaces are unrelated.
    final Object source = _source;
    if (source is! WatchEnergySource) return;
    try {
      await source.activeEnergyPermission();
    } on Object {
      // A workout without calories is still a workout.
    }
  }

  @override
  Future<void> end() async {
    try {
      await _methods.invokeMethod<void>('end');
    } on Object {
      return;
    }
  }

  @override
  Future<List<String>> inProgressActivityTypes() async {
    try {
      final answer = await _methods.invokeListMethod<Object?>('inProgress');
      return [
        for (final name in answer ?? const <Object?>[])
          if (name is String) name,
      ];
    } on Object {
      return const [];
    }
  }
}
