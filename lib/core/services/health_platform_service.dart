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

/// Gateway to the platform health store.
///
/// Implementations never throw: a missing permission, an unavailable
/// store, or a platform error is reported as `false` / an empty list so
/// the app stays fully functional (S-005).
abstract class HealthPlatformService {
  Future<bool> requestWritePermission();

  Future<bool> requestReadPermission();

  Future<bool> writeWorkout(HealthWorkoutDraft workout);

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
