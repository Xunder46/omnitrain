import '../constants/data_version.dart';
import '../../data/repositories/workout_repository.dart';

/// Outcome of a single `run()` invocation of [DataMigrationService].
class DataMigrationResult {
  DataMigrationResult({
    required this.from,
    required this.to,
    required this.appliedSteps,
  });

  /// The version the device was at before the run.
  final int from;

  /// The version the device is at after the run (may equal `from` when
  /// the device was already at or beyond `targetVersion`).
  final int to;

  /// The steps that ran during this invocation, in execution order.
  /// Empty when the device was already at `targetVersion` (no-op).
  final List<DataMigrationStep> appliedSteps;
}

/// Drives the consolidated data-migration sequence.
///
/// On launch, the host (typically `HiveWorkoutRepository.initialize()`)
/// constructs a `DataMigrationService` with the ordered list of steps
/// and calls `run()`. The service:
///
/// 1. Reads the device's `data_version` (default `1`).
/// 2. If `data_version == 1` AND any legacy one-shot markers are present
///    on the device, the back-compat shim maps the legacy markers to
///    a starting version and writes it back so the shim runs only once.
/// 3. Runs every pending step in ascending `targetVersion` order. After
///    each step succeeds, `data_version` is advanced to the step's
///    `targetVersion`. If a step throws, the exception is re-raised
///    without advancing `data_version` past the failing step; the next
///    launch retries from that step.
/// 4. Records `(from, to)` in the meta box for diagnostics.
///
/// Steps must be idempotent so the version gate is sufficient and so
/// accidental retries cannot corrupt data.
class DataMigrationService {
  DataMigrationService({
    required WorkoutRepository repository,
    required int targetVersion,
    required List<DataMigrationStep> steps,
  }) : _repository = repository,
       _targetVersion = targetVersion,
       _steps = List.unmodifiable(steps);

  final WorkoutRepository _repository;
  final int _targetVersion;
  final List<DataMigrationStep> _steps;

  /// Read-only view of the ordered step list this service was constructed
  /// with. The list is normalized to ascending `targetVersion` at
  /// construction time.
  List<DataMigrationStep> get steps => _steps;

  /// The list of steps that ran during the most recent `run()` invocation,
  /// in execution order. Empty before the first call, or after a call that
  /// was a no-op.
  List<DataMigrationStep> appliedSteps = const [];

  /// Run the migration sequence.
  Future<DataMigrationResult> run() async {
    final storedVersion = await _repository.getDataVersion();

    // Back-compat shim: only when the device has never recorded a
    // data_version AND at least one legacy one-shot marker is present.
    // Devices that started fresh never hit the legacy markers, so the
    // shim is a no-op for them.
    var effectiveFrom = storedVersion;
    if (storedVersion == 1) {
      final legacyApplied = await _repository.getLegacyAppliedDataVersion();
      if (legacyApplied > 1) {
        effectiveFrom = legacyApplied;
        await _repository.setDataVersion(legacyApplied);
      }
    }

    if (effectiveFrom >= _targetVersion) {
      // No-op: record the (no-op) transition so the diagnostic record
      // reflects that the migration ran this launch.
      await _repository.setLastDataVersionTransition(
        effectiveFrom,
        effectiveFrom,
      );
      appliedSteps = const [];
      return DataMigrationResult(
        from: effectiveFrom,
        to: effectiveFrom,
        appliedSteps: const [],
      );
    }

    // Sort the steps by targetVersion ascending. Defensive — callers are
    // expected to pass them in order, but this guards against future
    // ordering mistakes.
    final ordered = List<DataMigrationStep>.from(_steps)
      ..sort((a, b) => a.targetVersion.compareTo(b.targetVersion));

    final ran = <DataMigrationStep>[];
    for (final step in ordered) {
      if (step.targetVersion <= effectiveFrom) {
        // Already past this step (could happen when a step's
        // targetVersion is < the shim-detected starting version).
        continue;
      }
      await step.run();
      await _repository.setDataVersion(step.targetVersion);
      ran.add(step);
    }

    appliedSteps = List.unmodifiable(ran);
    await _repository.setLastDataVersionTransition(
      effectiveFrom,
      _targetVersion,
    );
    return DataMigrationResult(
      from: effectiveFrom,
      to: _targetVersion,
      appliedSteps: appliedSteps,
    );
  }
}
