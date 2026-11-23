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

  /// The energy the workout burned, in kilocalories, when a watch measured it
  /// (plan 307). Null when nothing was measured: an estimate is never written.
  final double? energyKcal;

  /// The Health Connect exercise name the wrist's own rule gives this session
  /// (`exercise_type_running`), set only for a session a Wear wrist ran (plan
  /// 308). The Android gateway prefers it to the coarse [activityKind]; any
  /// platform or name it does not map falls back to the kind.
  final String? activityTypeName;

  const HealthWorkoutDraft({
    required this.activityKind,
    required this.start,
    required this.end,
    this.title,
    this.energyKcal,
    this.activityTypeName,
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

/// Reads the user's daily ACTIVE energy from the platform health store
/// (Apple Health on iOS, Health Connect on Android). A separate interface so
/// the existing `HealthPlatformService` fakes stay untouched (plan 208 D-12).
abstract class HealthActiveEnergySource {
  /// Asks for READ access to active energy; false when refused or unavailable.
  Future<bool> requestActiveEnergyReadPermission();

  /// Active kcal per local day. [dayStarts] are local midnights; the result is
  /// keyed by the day-start epoch milliseconds. A day the store cannot answer
  /// is absent. Never throws.
  Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts);
}

/// No-op gateway for platforms without a writable health store (web,
/// desktop) and for tests.
class UnavailableHealthPlatformService
    implements HealthPlatformService, HealthActiveEnergySource {
  const UnavailableHealthPlatformService();

  @override
  Future<bool> requestWritePermission() async => false;

  @override
  Future<bool> requestReadPermission() async => false;

  @override
  Future<bool> requestActiveEnergyReadPermission() async => false;

  @override
  Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts) =>
      Future.value(const {});

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
