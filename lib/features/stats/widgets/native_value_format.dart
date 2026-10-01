import '../../../core/models/exercise_metric.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../state/settings/settings_state.dart';

/// One exercise's native value, as a user reads it.
///
/// The metric decides the shape: a weight in the preferred weight unit, a rep
/// count, a pace in the preferred distance unit, a clock, a round count or a
/// minute count. Records & Trends and Exercise Progress both format their
/// figures here, so the same number never reads two ways on two screens.
String formatNativeMetric(
  NativeMetric metric,
  double value,
  SettingsState settings,
) {
  switch (metric) {
    case NativeMetric.estimatedOneRepMax:
      return '${UnitFormatter.formatWeightValue(value, settings)} '
          '${UnitFormatter.weightLabel(settings)}';
    case NativeMetric.reps:
      return '${value.toInt()} reps';
    case NativeMetric.pace:
      // Stored seconds per kilometre, read as seconds per display unit —
      // `UnitFormatter.metresPerUnit`'s conversion, so no km↔mi constant is
      // repeated here.
      final secondsPerUnit =
          value *
          UnitFormatter.metresPerUnit(settings.preferredDistanceUnit) /
          1000.0;
      final clock = OmniDateUtils.formatClock((secondsPerUnit * 1000).round());
      return '$clock /${UnitFormatter.distanceLabel(settings)}';
    case NativeMetric.duration:
    case NativeMetric.hold:
      return OmniDateUtils.formatClock((value * 1000).round());
    case NativeMetric.rounds:
      return '${value.toInt()} rounds';
    case NativeMetric.roundMinutes:
      return '${value.round()} min';
  }
}

/// A whole [NativeValue]: its metric's figure, the added weight that belongs
/// to it when there is one, and the `est.` marker when the distance behind it
/// is an estimate.
String formatNativeValue(NativeValue value, SettingsState settings) {
  final base = formatNativeMetric(value.metric, value.value, settings);
  final added = value.addedWeightKg;
  final withAdded = added == null || added <= 0
      ? base
      : '$base (+${UnitFormatter.formatWeight(added, settings)})';
  return value.estimated ? '$withAdded est.' : withAdded;
}

/// The secondary figure a [NativeValue] carries, or null when it carries none.
String? formatNativeSecondary(NativeValue value, SettingsState settings) {
  final metric = value.secondaryMetric;
  final secondary = value.secondaryValue;
  if (metric == null || secondary == null) return null;
  return formatNativeMetric(metric, secondary, settings);
}

/// The number [metric] plots: [value] converted the same way
/// [formatNativeMetric] converts it, so a chart's axis and the figure above it
/// read in one unit. Only [NativeMetric.pace] is stored in a unit the user does
/// not read — seconds per kilometre against a preferred distance unit.
double nativeMetricDisplayValue(
  NativeMetric metric,
  double value,
  SettingsState settings,
) {
  switch (metric) {
    case NativeMetric.pace:
      return value *
          UnitFormatter.metresPerUnit(settings.preferredDistanceUnit) /
          1000.0;
    case NativeMetric.estimatedOneRepMax:
    case NativeMetric.reps:
    case NativeMetric.duration:
    case NativeMetric.hold:
    case NativeMetric.rounds:
    case NativeMetric.roundMinutes:
      return value;
  }
}

/// The unit a [metric]'s chart axis is read in. Empty for the metrics whose
/// numbers are unit-free counts.
String nativeMetricUnitLabel(NativeMetric metric, SettingsState settings) {
  switch (metric) {
    case NativeMetric.estimatedOneRepMax:
      return UnitFormatter.weightLabel(settings);
    case NativeMetric.reps:
      return 'reps';
    case NativeMetric.pace:
      return 's/${UnitFormatter.distanceLabel(settings)}';
    case NativeMetric.rounds:
      return 'rounds';
    case NativeMetric.roundMinutes:
      return 'min';
    case NativeMetric.duration:
    case NativeMetric.hold:
      return '';
  }
}
