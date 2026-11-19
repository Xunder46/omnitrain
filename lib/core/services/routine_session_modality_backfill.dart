import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

/// ONE-OFF (plan 122) — retire after launch.
///
/// Stamps past routine sessions with their routine's Focus as it is today:
/// for every stored `TrainingSession` with `intent == 'routine'`, a null
/// `modality` and a non-empty `routineTemplateId`, the referenced template's
/// `focusModality` (non-null and non-empty) is copied verbatim into
/// `modality`; every other field, including `updated_at_ms` and
/// `ended_at_ms`, is unchanged. Deleted routines and routines with no Focus
/// are skipped silently; planned rows are never read or written. Rows are
/// written one at a time and awaited, with no try/catch: a throw propagates
/// so `DataMigrationService` does not advance `data_version` and the next
/// launch re-runs the step. Already-stamped rows no longer match the
/// selection rule, so a second run performs zero updates — idempotent and
/// resumable.
///
/// Runs as data-migration step 18 (`backfillRoutineSessionModality`).
///
/// Retirement procedure: replace the step's `run` body with a no-op keeping
/// its version and name, delete this service and its test file, and update
/// `docs/db_integration.md`; never renumber or remove a version (a device
/// below it would stop short of `currentDataVersion`).
class RoutineSessionModalityBackfill {
  RoutineSessionModalityBackfill(this._repository);

  final WorkoutRepository _repository;

  Future<void> run() async {
    for (final session in await _repository.getAllSessions()) {
      if (session.intent != 'routine') continue;
      if (session.modality != null) continue;
      final routineId = session.routineTemplateId;
      if (routineId == null || routineId.isEmpty) continue;
      final template = await _repository.getTemplateById(routineId);
      if (template == null) continue;
      final focus = template.focusModality;
      if (focus == null || focus.isEmpty) continue;
      await _repository.updateSession(
        TrainingSession.fromMap({...session.toMap(), 'modality': focus}),
      );
    }
  }
}
