import 'package:flutter/material.dart';
import '../../core/constants/home_tiles.dart';

/// Reusable tile widget for home screen modality selection
/// Pure presentation component - no state mutation or business logic
class ModalityTile extends StatelessWidget {
  final HomeTileConfig config;
  final VoidCallback onTap;

  const ModalityTile({
    super.key,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Determine if this is the neutral "Free Training" tile
    final isNeutralTile = config.modality == null;
    
    // Hide text on very small screens (< 350px width)
    final showLabel = screenWidth >= 350;
    
    return Card(
      elevation: 2,
      color: isNeutralTile 
        ? theme.colorScheme.surfaceContainerHigh 
        : config.color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                config.iconData,
                size: 48,
                color: isNeutralTile 
                  ? theme.colorScheme.onSurface 
                  : Colors.white,
              ),
              if (showLabel) ...[
                const SizedBox(height: 12),
                Text(
                  config.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isNeutralTile 
                      ? theme.colorScheme.onSurface 
                      : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
