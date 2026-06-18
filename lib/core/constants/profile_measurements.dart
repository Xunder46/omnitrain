import '../utils/unit_formatter.dart';

// Validation range record used by log-entry save logic.
// min/max are expressed in the unit the user is currently typing in.
typedef _Range = ({double min, double max});

class ProfileMeasurementDefinition {
  final String type;
  final String label;
  final String unitId;
  final String unitLabel;

  const ProfileMeasurementDefinition({
    required this.type,
    required this.label,
    required this.unitId,
    required this.unitLabel,
  });
}

class ProfileMeasurements {
  static const ProfileMeasurementDefinition bodyweight =
      ProfileMeasurementDefinition(
        type: 'bodyweight',
        label: 'Body Weight',
        unitId: 'unit-kg',
        unitLabel: 'kg',
      );

  static const ProfileMeasurementDefinition height =
      ProfileMeasurementDefinition(
        type: 'height',
        label: 'Height',
        unitId: 'unit-cm',
        unitLabel: 'cm',
      );

  static const ProfileMeasurementDefinition bodyFatPct =
      ProfileMeasurementDefinition(
        type: 'body_fat_pct',
        label: 'BODY FAT',
        unitId: 'unit-pct',
        unitLabel: '%',
      );

  static const ProfileMeasurementDefinition leanMass =
      ProfileMeasurementDefinition(
        type: 'lean_mass',
        label: 'Lean Mass',
        unitId: 'unit-kg',
        unitLabel: 'kg',
      );

  static const ProfileMeasurementDefinition waist =
      ProfileMeasurementDefinition(
        type: 'waist_cm',
        label: 'Waist',
        unitId: 'unit-cm',
        unitLabel: 'cm',
      );

  static const ProfileMeasurementDefinition chest =
      ProfileMeasurementDefinition(
        type: 'chest_cm',
        label: 'Chest',
        unitId: 'unit-cm',
        unitLabel: 'cm',
      );

  static const ProfileMeasurementDefinition hips = ProfileMeasurementDefinition(
    type: 'hips_cm',
    label: 'Hips',
    unitId: 'unit-cm',
    unitLabel: 'cm',
  );

  static const ProfileMeasurementDefinition thigh =
      ProfileMeasurementDefinition(
        type: 'thigh_cm',
        label: 'Thigh',
        unitId: 'unit-cm',
        unitLabel: 'cm',
      );

  static const ProfileMeasurementDefinition arm = ProfileMeasurementDefinition(
    type: 'arm_cm',
    label: 'Arm',
    unitId: 'unit-cm',
    unitLabel: 'cm',
  );

  static const List<ProfileMeasurementDefinition> primary = [
    bodyweight,
    height,
  ];

  static const List<ProfileMeasurementDefinition> additional = [
    bodyFatPct,
    leanMass,
    waist,
    chest,
    hips,
    thigh,
    arm,
  ];

  static const List<ProfileMeasurementDefinition> all = [
    bodyweight,
    height,
    bodyFatPct,
    leanMass,
    waist,
    chest,
    hips,
    thigh,
    arm,
  ];

  // ── Validation ranges ────────────────────────────────────────────────────

  // Ranges for non-weight types and for kg weight types.
  static const Map<String, _Range> _kgRanges = {
    'bodyweight': (min: 20, max: 300),
    'height': (min: 50, max: 250),
    'body_fat_pct': (min: 1, max: 100),
    'lean_mass': (min: 20, max: 200),
    'waist_cm': (min: 30, max: 200),
    'chest_cm': (min: 30, max: 200),
    'hips_cm': (min: 30, max: 200),
    'thigh_cm': (min: 20, max: 100),
    'arm_cm': (min: 15, max: 80),
  };

  // Display-unit lbs ranges for weight types.
  static const Map<String, _Range> _lbsRanges = {
    'bodyweight': (min: 40, max: 600),
    'lean_mass': (min: 40, max: 440),
  };

  /// Returns the valid [min, max] range for [type] in the unit the user is
  /// currently typing in. [weightUnit] should be
  /// [SettingsState.preferredWeightUnit] (e.g. `'kg'` or `'lbs'`).
  static _Range validationRangeFor(String type, String weightUnit) {
    final isLbs = UnitFormatter.normalizeWeightUnit(weightUnit) == 'lbs';
    if (isLbs && _lbsRanges.containsKey(type)) {
      return _lbsRanges[type]!;
    }
    return _kgRanges[type] ?? (min: 0, max: double.infinity);
  }

  /// Returns the display unit label used in validation error messages for
  /// [type]. For weight types, respects the user's [weightUnit] preference.
  static String validationUnitLabel(String type, String weightUnit) {
    final def = definitionFor(type);
    if (def.unitId == 'unit-kg') {
      return UnitFormatter.weightLabelForUnit(weightUnit);
    }
    return def.unitLabel;
  }

  // ── Other helpers ─────────────────────────────────────────────────────────

  static ProfileMeasurementDefinition definitionFor(String type) {
    for (final definition in all) {
      if (definition.type == type) return definition;
    }
    return ProfileMeasurementDefinition(
      type: type,
      label: type,
      unitId: '',
      unitLabel: '',
    );
  }

  static String unitLabelFor(String unitId) {
    switch (unitId) {
      case 'unit-kg':
        return 'kg';
      case 'unit-cm':
        return 'cm';
      case 'unit-pct':
        return '%';
      default:
        return '';
    }
  }

  static String formatValue(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final oneDecimal = value.toStringAsFixed(1);
    return oneDecimal.endsWith('.0') ? value.toStringAsFixed(0) : oneDecimal;
  }
}
