import 'package:flutter/material.dart';
import 'modality.dart';

/// Configuration for home screen modality tiles
/// Defines the 6 primary entry points for workout sessions
class HomeTileConfig {
  final String key;
  final String label;
  final IconData iconData;
  final Color color;
  final String? modality; // null = Free Training (no modality preset)

  const HomeTileConfig({
    required this.key,
    required this.label,
    required this.iconData,
    required this.color,
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
      color: Color(0xFF4e8ea7), // Teal blue
      modality: Modality.cardioEndurance,
    ),
    HomeTileConfig(
      key: 'resistance',
      label: 'Resistance / Lifting',
      iconData: Icons.fitness_center,
      color: Color(0xFF0f324c), // dark blue
      modality: Modality.resistanceLifting,
    ),
    
    // Row 2
    HomeTileConfig(
      key: 'martial_arts',
      label: 'Martial Arts',
      iconData: Icons.sports_mma,
      color: Color(0xFFD32F2F), // Red 700
      modality: Modality.martialArts,
    ),
    HomeTileConfig(
      key: 'isometric',
      label: 'Isometric / Stretching',
      iconData: Icons.accessibility,
      color: Color(0xFFFFC434), // Amber/gold
      modality: Modality.isometricStretching,
    ),
    
    // Row 3
    HomeTileConfig(
      key: 'sports',
      label: 'Sports',
      iconData: Icons.sports_soccer,
      color: Color(0xFF388E3C), // Green 700
      modality: Modality.sports,
    ),
    HomeTileConfig(
      key: 'free_training',
      label: 'Free Training',
      iconData: Icons.play_arrow,
      color: Color(0xFF424242), // Neutral grey 800 (theme-friendly)
      modality: null, // No modality preset
    ),
  ];
}
