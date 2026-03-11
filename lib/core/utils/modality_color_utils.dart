import 'package:flutter/material.dart';

/// Resolves display color and label for a modality key.
/// Colors mirror the accent colors defined in HomeTiles so the calendar
/// indicators remain visually consistent with the home screen tiles.
class ModalityColorUtils {
  /// Returns the accent color for [modality].
  /// Falls back to grey for unknown/null modalities (Free Training).
  static Color colorForModality(String? modality) {
    switch (modality) {
      case 'cardio_endurance':
        return const Color(0xFF43A047); // grass green
      case 'resistance_lifting':
        return const Color(0xFF5B9BD5); // steel blue
      case 'sports':
      case 'martial_arts':
        return const Color(0xFFE63946); // ember red
      case 'isometric_stretching':
        return const Color(0xFFFFA726); // amber
      case 'free_training':
      default:
        return const Color(0xFF7E57C2); // violet (Free Training / fallback)
    }
  }

  /// Short display name for a modality.
  static String labelForModality(String? modality) {
    switch (modality) {
      case 'cardio_endurance':
        return 'Cardio / Endurance';
      case 'resistance_lifting':
        return 'Resistance / Lifting';
      case 'sports':
        return 'Sports';
      case 'martial_arts':
        return 'Martial Arts';
      case 'isometric_stretching':
        return 'Isometric / Stretching';
      default:
        return 'Free Training';
    }
  }
}
