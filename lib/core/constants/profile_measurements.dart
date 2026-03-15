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
        label: 'Body Fat',
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
