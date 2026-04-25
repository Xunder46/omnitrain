import 'package:flutter/material.dart';

import '../constants/modality.dart';
import '../constants/modality_colors.dart';

/// Resolves display color and label for a modality key.
/// Colors mirror the accent colors defined in HomeTiles so the calendar
/// indicators remain visually consistent with the home screen tiles.
class ModalityColorUtils {
  /// Returns the accent color for [modality].
  /// Falls back to the Free Training accent for unknown/null modalities.
  static Color colorForModality(String? modality) {
    return ModalityColors.forModality(modality);
  }

  /// Short display name for a modality.
  static String labelForModality(String? modality) {
    switch (modality) {
      case Modality.cardioEndurance:
        return 'Cardio / Endurance';
      case Modality.resistanceLifting:
        return 'Resistance / Lifting';
      case Modality.sports:
        return 'Sports';
      case Modality.isometricStretching:
        return 'Isometric / Stretching';
      default:
        return 'Free Training';
    }
  }
}
