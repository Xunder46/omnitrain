import '../../data/repositories/workout_repository.dart';
import '../models/weight_trend.dart';

/// Reads the body-weight history and applies [weightTrend] (D-17703).
class WeightTrendService {
  WeightTrendService(this._repository);

  final WorkoutRepository _repository;

  /// The trend at [now], or null with too little history. A history that cannot
  /// be read is also null: the block is absent rather than breaking Stats.
  Future<WeightTrend?> compute({required DateTime now}) async {
    try {
      final entries = await _repository.getMeasurementHistory('bodyweight');
      return weightTrend(entries: entries, now: now);
    } catch (_) {
      return null;
    }
  }
}
