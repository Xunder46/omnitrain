import 'package:flutter/material.dart';
import 'modality.dart';
import 'modality_colors.dart';
import '../../widgets/icons/overhead_press_icon.dart';

/// Configuration for home screen modality tiles with cosmic aesthetic
/// Defines the 5 primary entry points for workout sessions + My Routines
/// Layout: 3 rows × 2 columns (grid with bottom row special)
class HomeTileConfig {
  final String key;
  final String label;
  final IconData? iconData;
  final Widget? iconWidget;
  final List<Color> gradientColors;
  final Color accentColor;
  final String? modality; // null = special tile (Free Training, My Routines)

  const HomeTileConfig({
    required this.key,
    required this.label,
    this.iconData,
    this.iconWidget,
    required this.gradientColors,
    required this.accentColor,
    this.modality,
  });
}

/// The 6 home screen tiles in display order (3 rows × 2 columns)
/// Changed Feb 2026: Combined martial arts & sports → unified Sports tile
/// Unified Sports supports both martial arts and sports exercises with time+rounds tracking
class HomeTiles {
  static const List<HomeTileConfig> all = [
    // Row 1
    // Cardio / Endurance — grass green (Feb 2026: changed from cyan to green)
    HomeTileConfig(
      key: 'cardio',
      label: 'Cardio',
      iconData: Icons.directions_run,
      gradientColors: [Color(0xFF1A2F47), Color(0xFF0D2818)],
      accentColor: ModalityColors.cardioEndurance,
      modality: Modality.cardioEndurance,
    ),
    // Resistance / Lifting — steel blue (strength/weight)
    HomeTileConfig(
      key: 'resistance',
      label: 'Resistance',
      iconWidget: OverheadPressIcon(size: 70),
      gradientColors: [Color(0xFF1A2F47), Color(0xFF152F42)],
      accentColor: ModalityColors.resistanceLifting,
      modality: Modality.resistanceLifting,
    ),

    // Row 2
    // Sports — unified martial arts + sports (Feb 2026: combined with martial arts icon and color)
    // Icon: martial arts, Color: ember red, Modality: sports (includes both categories)
    HomeTileConfig(
      key: 'sports',
      label: 'Sports',
      iconData: Icons.sports_martial_arts,
      gradientColors: [Color(0xFF2A1E24), Color(0xFF3A1F2A)],
      accentColor: ModalityColors.sports,
      modality: Modality.sports,
    ),
    // Isometric / Stretching — amber (warm/hold)
    HomeTileConfig(
      key: 'isometric',
      label: 'Isometric',
      iconData: Icons.accessibility,
      gradientColors: [Color(0xFF2F2A1E), Color(0xFF3D3424)],
      accentColor: ModalityColors.isometricStretching,
      modality: Modality.isometricStretching,
    ),

    // Row 3
    // Free Training — violet (open/flexible, user chooses metrics per exercise)
    HomeTileConfig(
      key: 'free_training',
      label: 'Free',
      iconData: Icons.play_arrow,
      gradientColors: [Color(0xFF24222A), Color(0xFF2A2433)],
      accentColor: ModalityColors.freeTraining,
      modality: null, // No modality preset
    ),
    // My Routines — neutral grey (placeholder for routine management feature)
    HomeTileConfig(
      key: 'my_routines',
      label: 'Routines',
      iconData: Icons.folder_open,
      gradientColors: [Color(0xFF252525), Color(0xFF1C1C1C)],
      accentColor: Color(0xFF9E9E9E),
      modality: null, // Special tile, not a workout modality
    ),
  ];
}
