import '../../state/settings/settings_state.dart';

class UnitFormatter {
  UnitFormatter._();

  static const double _kgToLbs = 2.20462;
  static const double _kmToMiles = 0.621371;
  static const double _cmToInches = 1.0 / 2.54;

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

  /// Converts a weight expressed in [unit] to canonical kilograms — the
  /// inverse of [convertWeight], sharing the same conversion constant.
  /// Used at input boundaries such as the health-store import.
  static double toKilograms(double value, String unit) {
    return normalizeWeightUnit(unit) == 'lbs' ? value / _kgToLbs : value;
  }

  /// Canonical kilograms as the display value for [unit] — the unit-string
  /// form of [convertWeight], for callers that hold a unit rather than a
  /// [SettingsState] (the watch client runs in its own process).
  static double fromKilograms(double kg, String? unit) {
    return normalizeWeightUnit(unit) == 'lbs' ? kg * _kgToLbs : kg;
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

  /// Metres in one display unit of distance. Canonical distance is metres —
  /// the unit `MetricIds.distance` carries — so callers working in metres use
  /// this instead of the kilometre-based helpers above; the constant is the
  /// same one, inverted once here rather than again per call site.
  static double metresPerUnit(String? unit) {
    return normalizeDistanceUnit(unit) == 'miles' ? 1000 / _kmToMiles : 1000;
  }

  // ── Height ───────────────────────────────────────────────────────────────
  //
  // Canonical storage for height is centimeters. The active
  // display unit is governed by [SettingsState.preferredHeightUnit]
  // (`cm` or `ftin`). The conversion helpers are pure functions of
  // the active unit and the canonical cm value; the profile log
  // sheet and the chart sheet both call into this single owner so
  // the display path is shared.

  /// Returns the canonical `'cm'` or `'ftin'` for any input. Unknown
  /// values normalize to `'cm'` so the rest of the code can rely on
  /// the two valid keys.
  static String normalizeHeightUnit(String? unit) {
    final normalized = unit?.toLowerCase().trim();
    if (normalized == 'ftin' ||
        normalized == 'ft_in' ||
        normalized == 'ft' ||
        normalized == 'feet_inches' ||
        normalized == 'imperial') {
      return 'ftin';
    }
    return 'cm';
  }

  /// Lowercase display label for the active height unit.
  /// - `cm`  → `'cm'`
  /// - `ftin` → `'ft in'`
  static String heightLabel(SettingsState settings) {
    return heightLabelForUnit(settings.preferredHeightUnit);
  }

  static String heightLabelForUnit(String? unit) {
    return normalizeHeightUnit(unit) == 'ftin' ? 'ft in' : 'cm';
  }

  /// Uppercase display label for the active height unit.
  static String heightLabelUpper(SettingsState settings) {
    return heightLabelUpperForUnit(settings.preferredHeightUnit);
  }

  static String heightLabelUpperForUnit(String? unit) {
    return heightLabelForUnit(unit).toUpperCase();
  }

  /// Render a canonical-cm height in the active unit, with the unit
  /// suffix. In ftin mode the result is the natural compound form
  /// (e.g. `'5 ft 11 in'`); in cm mode it is the value + ' cm'.
  static String formatHeight(double cm, SettingsState settings) {
    if (normalizeHeightUnit(settings.preferredHeightUnit) == 'ftin') {
      final compound = cmToFeetInches(cm);
      return formatFeetInches(compound.feet, compound.inches);
    }
    return '${_formatNumber(cm)} ${heightLabel(settings)}';
  }

  /// Same as [formatHeight] but without the unit suffix. In ftin
  /// mode this returns the compound form (which is self-describing),
  /// e.g. `'5 ft 11 in'`.
  static String formatHeightValue(double cm, SettingsState settings) {
    if (normalizeHeightUnit(settings.preferredHeightUnit) == 'ftin') {
      final compound = cmToFeetInches(cm);
      return formatFeetInches(compound.feet, compound.inches);
    }
    return _formatNumber(cm);
  }

  /// Convert a canonical-cm height into the display unit's primary
  /// numeric form:
  /// - cm mode → cm (passthrough)
  /// - ftin mode → total whole inches (e.g. 180 cm → 71)
  ///
  /// The chart uses this for the Y-axis plot; the label strip uses
  /// [formatHeight] for the unit-aware compound rendering.
  static double convertHeightFromCm(double cm, SettingsState settings) {
    if (normalizeHeightUnit(settings.preferredHeightUnit) == 'ftin') {
      final compound = cmToFeetInches(cm);
      return compound.feet * 12.0 + compound.inches;
    }
    return cm;
  }

  /// Convert a feet/inches pair to canonical cm. The log sheet uses
  /// this when the user saves in ftin mode; the stored value is
  /// always cm with `unitId='unit-cm'`.
  static double toCanonicalHeightFeetInches(int feet, int inches) {
    return feetInchesToCm(feet, inches);
  }

  /// Convert a canonical-cm height into a whole-foot + whole-inch
  /// pair. Inches are rounded to the nearest whole inch; the feet
  /// component is computed from the remainder.
  static ({int feet, int inches}) cmToFeetInches(double cm) {
    if (cm <= 0) return (feet: 0, inches: 0);
    final totalInches = cm * _cmToInches;
    final rounded = totalInches.round();
    return (feet: rounded ~/ 12, inches: rounded % 12);
  }

  /// Convert a feet/inches pair to canonical cm. The output is not
  /// rounded so the round-trip display exactly preserves the
  /// entered values.
  static double feetInchesToCm(int feet, int inches) {
    return (feet * 12 + inches) * 2.54;
  }

  /// Render a feet/inches pair as a natural compound string
  /// (e.g. `'5' 11"'`). Exposed for callers that already have
  /// the pair on hand.
  static String formatFeetInches(int feet, int inches) {
    return "$feet' $inches\"";
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
