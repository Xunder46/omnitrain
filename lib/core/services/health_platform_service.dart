// filepath: lib/core/services/health_platform_service.dart
//
// Platform-neutral contract for the phone health-store integration
// (Apple Health / Health Connect).
//
// Deliberately free of plugin types: the concrete gateway
// (`health_platform_gateway_io.dart`) owns the `health` package, and
// everything above it — sync service, state, UI — sees only this
// contract. That keeps the whole pipeline testable on the host and
// keeps the plugin out of the web/desktop compilation path.

import '../constants/health_constants.dart';
import '../utils/unit_formatter.dart';

/// One completed workout to write to the platform store.
class HealthWorkoutDraft {
  final HealthActivityKind activityKind;
  final DateTime start;
  final DateTime end;
  final String? title;

  const HealthWorkoutDraft({
    required this.activityKind,
    required this.start,
    required this.end,
    this.title,
  });
}

/// One body-weight reading read back from the platform store.
class HealthWeightSample {
  /// Stable platform identifier (HealthKit / Health Connect UUID), used
  /// as the import dedupe key when present.
  final String? sourceId;

  final DateTime sampledAt;

  /// Canonical kilograms — the app stores weight in kg only.
  final double kilograms;

  const HealthWeightSample({
    this.sourceId,
    required this.sampledAt,
    required this.kilograms,
  });
}

/// What a Workout Effort write did (plan 90 D-1).
///
/// [leftAlone]: the workout already carries an effort another source saved
/// (the owner's own value in Fitness), which this app never replaces (OQ-2).
/// [noWorkout]: no own-source workout starts inside the span yet; a watch
/// workout reaches the phone's store a little after the finish.
/// [unavailable]: no effort support here (Android, web, iOS before 18, no
/// permission) or a platform error.
enum HealthEffortOutcome { written, leftAlone, noWorkout, unavailable }

/// Gateway to the platform health store.
///
/// Implementations never throw: a missing permission, an unavailable
/// store, or a platform error is reported as `false` / an empty list so
/// the app stays fully functional (S-005).
abstract class HealthPlatformService {
  Future<bool> requestWritePermission();

  Future<bool> requestReadPermission();

  Future<bool> writeWorkout(HealthWorkoutDraft workout);

  /// Removes this app's own workouts that start inside `[start, end)`
  /// (plan 89 D-5: the plugin matches by start time and by this app's
  /// source only). True when the store accepted the request.
  Future<bool> deleteWorkouts(DateTime start, DateTime end);

  /// Sets the Workout Effort (Apple's 1 to 10 score) of this app's own
  /// workout that starts inside `[start, end)`, replacing only an effort this
  /// app wrote before (plan 90 D-1, D-6).
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  );

  /// Removes the effort this app wrote for its workout that starts inside
  /// `[start, end)`. True when the store accepted the request.
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end);

  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since);
}

/// No-op gateway for platforms without a writable health store (web,
/// desktop) and for tests.
class UnavailableHealthPlatformService implements HealthPlatformService {
  const UnavailableHealthPlatformService();

  @override
  Future<bool> requestWritePermission() async => false;

  @override
  Future<bool> requestReadPermission() async => false;

  @override
  Future<bool> writeWorkout(HealthWorkoutDraft workout) async => false;

  @override
  Future<bool> deleteWorkouts(DateTime start, DateTime end) async => false;

  @override
  Future<HealthEffortOutcome> setWorkoutEffort(
    DateTime start,
    DateTime end,
    int score,
  ) async => HealthEffortOutcome.unavailable;

  @override
  Future<bool> clearWorkoutEffort(DateTime start, DateTime end) async => false;

  @override
  Future<List<HealthWeightSample>> readBodyWeightSince(DateTime since) async =>
      const [];
}

/// Converts a platform weight reading to canonical kilograms.
///
/// Pound-style labels go through [UnitFormatter] so the conversion
/// constant is shared with display conversion; every other label is
/// treated as already-kilograms.
double weightToKilograms({required double value, required String unitLabel}) {
  final normalized = unitLabel.toLowerCase().trim();
  final isPound = normalized.startsWith('lb') || normalized.startsWith('pound');
  return isPound ? UnitFormatter.toKilograms(value, 'lbs') : value;
}
