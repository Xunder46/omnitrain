import '../../state/settings/settings_state.dart';

class UnitFormatter {
  UnitFormatter._();

  static const double _kgToLbs = 2.20462;
  static const double _kmToMiles = 0.621371;

  static String normalizeWeightUnit(String? unit) {
    return unit?.toLowerCase().trim() == 'lbs' ? 'lbs' : 'kg';
  }

  static String normalizeDistanceUnit(String? unit) {
    final normalized = unit?.toLowerCase().trim();
    if (normalized == 'miles' || normalized == 'mile' || normalized == 'mi') {
      return 'miles';
    }
    return 'km';
  }

  // ── Weight ────────────────────────────────────────────────────────────────

  static double convertWeight(double kg, SettingsState settings) {
    if (normalizeWeightUnit(settings.preferredWeightUnit) == 'lbs') {
      return kg * _kgToLbs;
    }
    return kg;
  }

  static String weightLabel(SettingsState settings) {
    return weightLabelForUnit(settings.preferredWeightUnit);
  }

  static String weightLabelForUnit(String? unit) {
    return normalizeWeightUnit(unit) == 'lbs' ? 'lbs' : 'kg';
  }

  static String weightLabelUpper(SettingsState settings) {
    return weightLabelUpperForUnit(settings.preferredWeightUnit);
  }

  static String weightLabelUpperForUnit(String? unit) {
    return weightLabelForUnit(unit).toUpperCase();
  }

  static String formatWeight(
    double kg,
    SettingsState settings, {
    int decimals = 1,
  }) {
    return '${formatWeightValue(kg, settings, decimals: decimals)} ${weightLabel(settings)}';
  }

  static String formatWeightValue(
    double kg,
    SettingsState settings, {
    int decimals = 1,
  }) {
    final converted = convertWeight(kg, settings);
    return _formatNumber(converted, decimals: decimals);
  }

  static double toCanonicalWeight(double displayValue, SettingsState settings) {
    if (normalizeWeightUnit(settings.preferredWeightUnit) == 'lbs') {
      return displayValue / _kgToLbs;
    }
    return displayValue;
  }

  // ── Distance ──────────────────────────────────────────────────────────────

  static double convertDistance(double km, SettingsState settings) {
    if (normalizeDistanceUnit(settings.preferredDistanceUnit) == 'miles') {
      return km * _kmToMiles;
    }
    return km;
  }

  static String distanceLabel(SettingsState settings) {
    return distanceLabelForUnit(settings.preferredDistanceUnit);
  }

  static String distanceLabelForUnit(String? unit) {
    return normalizeDistanceUnit(unit) == 'miles' ? 'mi' : 'km';
  }

  static String distanceLabelUpper(SettingsState settings) {
    return distanceLabelUpperForUnit(settings.preferredDistanceUnit);
  }

  static String distanceLabelUpperForUnit(String? unit) {
    return distanceLabelForUnit(unit).toUpperCase();
  }

  static String formatDistance(
    double km,
    SettingsState settings, {
    int decimals = 1,
  }) {
    return '${formatDistanceValue(km, settings, decimals: decimals)} ${distanceLabel(settings)}';
  }

  static String formatDistanceValue(
    double km,
    SettingsState settings, {
    int decimals = 1,
  }) {
    final converted = convertDistance(km, settings);
    return _formatNumber(converted, decimals: decimals);
  }

  static double toCanonicalDistance(
    double displayValue,
    SettingsState settings,
  ) {
    if (normalizeDistanceUnit(settings.preferredDistanceUnit) == 'miles') {
      return displayValue / _kmToMiles;
    }
    return displayValue;
  }

  static String _formatNumber(double value, {int decimals = 1}) {
    if (decimals != 1) {
      return value.toStringAsFixed(decimals);
    }

    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    if (value.abs() < 1) {
      return value.toStringAsFixed(1);
    }

    return value.toStringAsFixed(1);
  }
}
