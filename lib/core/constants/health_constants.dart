// filepath: lib/core/constants/health_constants.dart
//
// Platform health integration vocabulary (Apple Health / Health Connect).
//
// Phone-only feature: the platform gateway is a no-op everywhere a
// writable health store does not exist (web, desktop). The toggles live
// in the same preference store as every other setting, so a reinstall
// wipes them — there is deliberately no second source of truth (S-006).

/// Preference keys and tunables for the health integration.
class HealthPrefs {
  HealthPrefs._();

  /// `off` | `on` | `denied` — see [HealthToggleState].
  static const String writeWorkoutsKey = 'health.writeWorkouts';
  static const String readBodyWeightKey = 'health.readBodyWeight';

  /// JSON list of session ids already written to the platform store:
  /// the idempotency ledger for the write pipeline (S-008).
  static const String writtenSessionIdsKey = 'health.writtenSessionIds';

  /// Ledger cap; oldest entries are dropped once exceeded. A session id
  /// falling off the ledger cannot cause a duplicate write because the
  /// sessions themselves are never re-completed.
  static const int writtenSessionIdLimit = 200;

  /// How far back the body-weight read queries the platform store.
  static const int bodyWeightLookbackDays = 90;
}

/// Persisted state of one health-sync toggle.
enum HealthToggleState { off, on, permissionDenied }

/// App-owned workout vocabulary. Kept free of plugin types so the
/// mapping logic is testable on every platform; the native gateway
/// translates a kind to a platform activity type per platform.
enum HealthActivityKind {
  strength,
  cardio,
  flexibility,
  sport,
  conditioning,
  other,
}

/// Parses a persisted toggle value; unknown values resolve to [off].
HealthToggleState parseHealthToggleState(String? raw) {
  switch (raw) {
    case 'on':
      return HealthToggleState.on;
    case 'denied':
      return HealthToggleState.permissionDenied;
    default:
      return HealthToggleState.off;
  }
}

/// Serializes a toggle state for persistence.
String healthToggleStateValue(HealthToggleState state) {
  switch (state) {
    case HealthToggleState.on:
      return 'on';
    case HealthToggleState.permissionDenied:
      return 'denied';
    case HealthToggleState.off:
      return 'off';
  }
}
