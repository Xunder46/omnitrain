import 'package:flutter/material.dart';
import 'modality.dart';
import 'modality_colors.dart';
import 'tile_artwork_metrics.dart';
import '../../widgets/icons/overhead_press_icon.dart';

/// Configuration for home screen modality tiles with cosmic aesthetic
/// Defines the 5 primary entry points for workout sessions + My Routines
/// Layout: 3 rows × 2 columns (grid with bottom row special)
class HomeTileConfig {
  final String key;
  final String label;
  final IconData? iconData;

  /// Custom-drawn artwork for tiles a standard [IconData] cannot express.
  ///
  /// A builder, not a widget: the tile owns artwork size, so a definition
  /// states *which* artwork to draw and never how large. Custom artwork and
  /// standard icons therefore shrink and drop out at the same points.
  final TileArtworkBuilder? artworkBuilder;
  final Color accentColor;
  final String? modality; // null = special tile (Free Training, My Routines)

  /// Whether this tile belongs to the visually secondary tier.
  ///
  /// Secondary tiles render with an 8% own-accent fill, a smaller dimmed
  /// icon, a lighter Medium label, and no rim highlight / inner shadow.
  /// They share the same surface radius, padding, and grid placement as
  /// primary tiles — only the resting decoration differs.
  final bool isSecondary;

  const HomeTileConfig({
    required this.key,
    required this.label,
    this.iconData,
    this.artworkBuilder,
    required this.accentColor,
    this.modality,
    this.isSecondary = false,
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
      accentColor: ModalityColors.cardioEndurance,
      modality: Modality.cardioEndurance,
    ),
    // Resistance / Lifting — steel blue (strength/weight)
    HomeTileConfig(
      key: 'resistance',
      label: 'Resistance',
      artworkBuilder: OverheadPressIcon.artwork,
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
      accentColor: ModalityColors.sports,
      modality: Modality.sports,
    ),
    // Isometric / Stretching — amber (warm/hold)
    HomeTileConfig(
      key: 'isometric',
      label: 'Isometric',
      iconData: Icons.accessibility,
      accentColor: ModalityColors.isometricStretching,
      modality: Modality.isometricStretching,
    ),

    // Row 3 — secondary tier (8% own-accent fill, dimmed/smaller icon, lighter
    // Medium label, no rim, no inner shadow). Free keeps its purple tint at
    // lower opacity; Routines uses its neutral gray at lower opacity.
    // Free Training — violet (open/flexible, user chooses metrics per exercise)
    HomeTileConfig(
      key: 'free_training',
      label: 'Free',
      iconData: Icons.play_arrow,
      accentColor: ModalityColors.freeTraining,
      modality: null, // No modality preset
      isSecondary: true,
    ),
    // My Routines — neutral grey
    HomeTileConfig(
      key: 'my_routines',
      label: 'Routines',
      iconData: Icons.folder_open,
      accentColor: Color(0xFF9E9E9E),
      modality: null, // Special tile, not a workout modality
      isSecondary: true,
    ),
  ];
}
