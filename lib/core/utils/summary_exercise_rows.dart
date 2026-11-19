import 'date_utils.dart';

/// One exercise of a finished session and the work logged in it, as the
/// Session Summary's EXERCISES card shows it (plan 245).
class SummaryExerciseRow {
  final String effortId;
  final String name;

  /// The logged work, one short text per entry: `10×60 kg`, `12 reps`,
  /// `01:00`. Never empty.
  final List<String> items;

  const SummaryExerciseRow({
    required this.effortId,
    required this.name,
    required this.items,
  });
}

/// Builds the rows of the Summary's EXERCISES card from
/// `WorkoutState.getExercisesWithEntries()`.
///
/// Reads no state and no settings: the caller passes the weight unit label and
/// a formatter from kilograms. An entry that holds no work (a skipped set, a set
/// with no reps, an interval or round that never ran) gives no item, and an
/// exercise with no item gives no row. Order is the input order.
List<SummaryExerciseRow> buildSummaryExerciseRows(
  List<Map<String, dynamic>> exercisesWithEntries, {
  required String weightUnitLabel,
  required String Function(double kg) formatWeight,
}) {
  final rows = <SummaryExerciseRow>[];
  for (final exercise in exercisesWithEntries) {
    final kind = exercise['effortKind'] as String?;
    final entries =
        (exercise['entries'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final items = <String>[];
    for (final entry in entries) {
      final item = _itemFor(kind, entry, weightUnitLabel, formatWeight);
      if (item != null) items.add(item);
    }
    if (items.isEmpty) continue;
    rows.add(
      SummaryExerciseRow(
        effortId: exercise['id'] as String,
        name: exercise['name'] as String,
        items: items,
      ),
    );
  }
  return rows;
}

String? _itemFor(
  String? kind,
  Map<String, dynamic> entry,
  String unit,
  String Function(double kg) formatWeight,
) {
  switch (kind) {
    case 'set':
      if (entry['skipped'] == true) return null;
      final reps = (entry['reps'] as num?)?.toInt() ?? 0;
      if (reps <= 0) return null;
      final weight = (entry['weight'] as num?)?.toDouble() ?? 0.0;
      final extra = (entry['extra-weight'] as num?)?.toDouble() ?? 0.0;
      if (weight > 0) return '$reps×${formatWeight(weight)} $unit';
      if (extra > 0) return '$reps reps +${formatWeight(extra)} $unit';
      return '$reps reps';
    case 'timed':
    case 'drill':
      final secs = (entry['elapsedSecs'] as num?)?.toInt() ?? 0;
      return secs > 0 ? OmniDateUtils.formatTimerDigits(secs) : null;
    case 'round':
      final secs = (entry['actualDuration'] as num?)?.toInt() ?? 0;
      return secs > 0 ? OmniDateUtils.formatTimerDigits(secs) : null;
  }
  return null;
}
