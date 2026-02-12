import 'package:flutter/material.dart';
import 'modality.dart';

/// Configuration for home screen modality tiles with cosmic aesthetic
/// Defines the 6 primary entry points for workout sessions
class HomeTileConfig {
  final String key;
  final String label;
  final IconData iconData;
  final List<Color> gradientColors;
  final String? modality; // null = Free Training (no modality preset)

  const HomeTileConfig({
    required this.key,
    required this.label,
    required this.iconData,
    required this.gradientColors,
    this.modality,
  });
}

/// The 6 primary home screen tiles in display order (3 rows × 2 columns)
class HomeTiles {
  static const List<HomeTileConfig> all = [
    // Row 1
    HomeTileConfig(
      key: 'cardio',
      label: 'Cardio / Endurance',
      iconData: Icons.directions_run,
      gradientColors: [Color(0xFF1ED7C6), Color(0xFF0E5E6F)],
      modality: Modality.cardioEndurance,
    ),
    HomeTileConfig(
      key: 'resistance',
      label: 'Resistance / Lifting',
      iconData: Icons.fitness_center,
      gradientColors: [Color(0xFF4FC3F7), Color(0xFF1A3A5F)],
      modality: Modality.resistanceLifting,
    ),
    
    // Row 2
    HomeTileConfig(
      key: 'martial_arts',
      label: 'Martial Arts',
      iconData: Icons.sports_mma,
      gradientColors: [Color(0xFFE53935), Color(0xFF5C1A1A)],
      modality: Modality.martialArts,
    ),
    HomeTileConfig(
      key: 'isometric',
      label: 'Isometric / Stretching',
      iconData: Icons.accessibility,
      gradientColors: [Color(0xFFFFC107), Color(0xFF5C4A1A)],
      modality: Modality.isometricStretching,
    ),
    
    // Row 3
    HomeTileConfig(
      key: 'sports',
      label: 'Sports',
      iconData: Icons.sports_soccer,
      gradientColors: [Color(0xFF43A047), Color(0xFF1B3A22)],
      modality: Modality.sports,
    ),
    HomeTileConfig(
      key: 'free_training',
      label: 'Free Training',
      iconData: Icons.play_arrow,
      gradientColors: [Color(0xFF3F51B5), Color(0xFF1A1F4A)],
      modality: null, // No modality preset
    ),
  ];
}
