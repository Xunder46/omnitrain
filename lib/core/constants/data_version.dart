/// Data-migration version constants + step interface.
///
/// OmniTrain used to ship data updates through ~13 independent one-time
/// steps, each gated by its own `bool` marker in the meta box. This file
/// consolidates those steps into a single ordered update sequence tracked
/// by the device's `data_version` integer.
///
/// ## Versioning rules
///
/// - The device's `data_version` is a single integer that monotonically
///   increases as migration steps complete.
/// - Steps are appended in order; the target version after the LAST step
///   runs is `currentDataVersion`. A device whose stored version equals
///   `currentDataVersion` is fully migrated; no further work runs.
/// - Each step is gated by a version check (instead of a separate bool
///   marker). Steps are still idempotent, so the version gate is the only
///   change in semantics.
/// - A failing step does NOT advance the version past the failing step;
///   the next launch retries from that step.
///
/// ## Adding a new step
///
/// To ship a new data change, append a `DataMigrationStep` to the step
/// list in `HiveWorkoutRepository._dataMigrationSteps` (and the Mock
/// mirror) and bump `currentDataVersion`. The next launch runs the new
/// step exactly once per device.
///
/// Out of scope: catalog content versioning (see
/// `lib/core/constants/catalog_version.dart`); that is a separate,
/// always-on mechanism.
library;

/// The version a device is at after the LAST consolidated step has run.
/// All existing installs that completed the legacy one-time steps land at
/// this version via the back-compat shim in `DataMigrationService`.
const int currentDataVersion = 14;

/// One consolidated data-migration step.
///
/// `targetVersion` is the version the device lands at after `run()`
/// completes. Steps are sorted by `targetVersion` ascending when the
/// `DataMigrationService` runs.
abstract class DataMigrationStep {
  const DataMigrationStep();

  /// The version the device lands at after this step completes.
  int get targetVersion;

  /// A short human-readable name for diagnostics / logging.
  String get name;

  /// The actual work the step performs. Must be safe to re-run (the
  /// service may retry after a failure).
  Future<void> run();
}