import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../constants/active_energy.dart';
import '../constants/metric_ids.dart';
import '../constants/profile_measurements.dart';
import '../models/exercise_metric.dart';
import 'stats_progress_service.dart';

/// Stores the active-energy estimate of a finished session (D-13407).
///
/// One settle writes at most one `estimated` row per session: no usable body
/// weight, an unfinished session, or nothing measured writes nothing (and the
/// read-out answers null). A `measured` row is never overwritten. Every
/// failure is caught: finishing a session never fails on energy.
class ActiveEnergyService {
  ActiveEnergyService(this._repository, this._stats);
  final WorkoutRepository _repository;
  final StatsProgressService Function() _stats;

  Future<void> settle(String sessionId) async {
    try {
      final session = await _repository.getSession(sessionId);
      if (session == null || session.endedAtMs == null) return;
      final existing = await _repository.getSessionEnergy(sessionId);
      if (existing != null &&
          existing.source == SessionEnergy.sourceMeasured) {
        return;
      }
      final weightKg = existing?.bodyWeightKg ?? await latestWeightKg();
      if (weightKg == null) return;
      final kcal = await _estimate(session, weightKg);
      if (kcal == null) return;
      await _repository.putSessionEnergy(
        SessionEnergy(
          sessionId: sessionId,
          activeKcal: kcal,
          source: SessionEnergy.sourceEstimated,
          bodyWeightKg: weightKg,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // Finishing a session never fails on energy (D-13407).
    }
  }

  /// The latest bodyweight on file, in the canonical `unit-kg`, above zero
  /// (D-13406; the `value > 0` check mirrors S-13415).
  Future<double?> latestWeightKg() async {
    final entry = await _repository.getLatestMeasurement(
      ProfileMeasurements.bodyweight.type,
    );
    if (entry == null || entry.unitId != MetricIds.unitKg) return null;
    if (!entry.value.isFinite || entry.value <= 0) return null;
    return entry.value;
  }

  /// The estimate for [session] at [kg]: a known modality id takes its whole
  /// duration at that section's MET (D-13404); Free Training, an unknown id
  /// or a rolling session takes the per-section split of measured seconds
  /// (D-13413, rolling first whatever the modality value).
  Future<double?> _estimate(TrainingSession session, double kg) async {
    if (!session.isRolling && session.modality != null) {
      final section = sectionForModality(session.modality!);
      if (section != null) {
        final secs = (session.endedAtMs! - session.startedAtMs) / 1000;
        return secs <= 0 ? null : _kcal(section, secs, kg);
      }
    }
    final split = await _stats().sessionTimeBySectionFor(session.id);
    var total = 0.0;
    for (final entry in split.entries) {
      total += _kcal(entry.key, entry.value, kg);
    }
    return total <= 0 ? null : total;
  }

  /// The running estimate the open session screen shows (D-13440): the same
  /// one formula as the stored estimate, over the elapsed seconds so far at
  /// the modality's section MET (the resistance MET for Free Training, an
  /// unknown id, or a null modality). Null without a usable weight or a
  /// negative elapsed; an elapsed of 0 answers 0.0.
  static double? liveKcal({
    required String? modality,
    required int elapsedSecs,
    required double? weightKg,
  }) {
    if (weightKg == null || !weightKg.isFinite || weightKg <= 0) return null;
    if (elapsedSecs < 0) return null;
    final section =
        (modality == null ? null : sectionForModality(modality)) ??
        ExerciseSection.resistance;
    return _kcal(section, elapsedSecs.toDouble(), weightKg);
  }

  static double _kcal(ExerciseSection section, double secs, double kg) =>
      (kActiveEnergyMets[section]! - 1) * kg * secs / 3600;
}
