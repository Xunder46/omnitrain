import 'package:flutter/material.dart';

import 'modality.dart';

/// Single source of truth for modality accent colors.
///
/// All modality-specific UI (home tiles, calendar dots, chips, headers, badges)
/// must import and use this file instead of redefining modality color values.
/// Keep these values exactly aligned with home screen tile accents.
class ModalityColors {
  static const Color cardioEndurance = Color(0xFF43A047);
  static const Color resistanceLifting = Color(0xFF5B9BD5);
  static const Color sports = Color(0xFFE63946);
  static const Color isometricStretching = Color(0xFFFFA726);
  static const Color freeTraining = Color(0xFF7E57C2);

  static const Map<String, Color> byModality = {
    Modality.cardioEndurance: cardioEndurance,
    Modality.resistanceLifting: resistanceLifting,
    Modality.sports: sports,
    Modality.martialArts: sports,
    Modality.isometricStretching: isometricStretching,
    'free_training': freeTraining,
  };

  static const Map<String, Color> summaryGroupLabelColors = {
    'strength': resistanceLifting,
    'cardio': cardioEndurance,
    'rounds': sports,
    'sports': sports,
    'isometric': isometricStretching,
  };

  static Color forModality(String? modality) {
    if (modality == null) return freeTraining;
    return byModality[modality] ?? freeTraining;
  }

  static Color forSummaryGroupLabel(String groupKey) {
    return summaryGroupLabelColors[groupKey] ?? freeTraining;
  }
}
