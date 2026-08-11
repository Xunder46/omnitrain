import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/tile_artwork_metrics.dart';

/// Hub-sheet destination tile.
///
/// Visually a different component from the Home screen's `EnergyTile` — its
/// own surface, shadow, colours and label style — but it sizes its artwork
/// from the same [TileArtworkMetrics] rule, so both grids shrink and drop
/// their artwork at exactly the same points. The two widgets share sizing
/// behaviour, not appearance; they are deliberately not merged.
class MaintenanceTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final AppTheme activeTheme;

  const MaintenanceTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.activeTheme = AppTheme.abyssalNeon,
  });

  @override
  State<MaintenanceTile> createState() => _MaintenanceTileState();
}

class _MaintenanceTileState extends State<MaintenanceTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? OmniTheme.pressedScale : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: scale,
        duration: OmniTheme.animationDuration,
        curve: OmniTheme.animationCurve,
        child: _buildSurface(),
      ),
    );
  }

  /// Artwork ceiling on a tile with room to spare. Not a fixed dimension —
  /// [TileArtworkMetrics] shrinks below it and drops the icon entirely on a
  /// short tile, in step with the Home grid.
  static const double _maxIconSize = 42.0;

  /// `bodyLarge` (15pt) at the label's 1.1 line-height multiplier.
  static const double _labelLineHeight = 15.0 * 1.1;

  Widget _buildSurface() {
    final themeColors = OmniTheme.colorsForTheme(widget.activeTheme);
    final labelStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: themeColors.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: OmniTheme.titleLetterSpacing,
      height: 1.1,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        color: themeColors.surface,
        border: Border.all(
          color: themeColors.surfaceBorder,
          width: OmniTheme.surfaceBorderWidth,
        ),
        boxShadow: [OmniTheme.deepShadow],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Padding, icon size and the icon-to-label gap all come from the
          // shared rule rather than fixed values of this tile's own, so the
          // hub grid cannot drift away from the Home grid. Appearance —
          // surface, shadow, colours, label style — stays this tile's.
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final metrics = TileArtworkMetrics.resolve(
            tileHeight: constraints.maxHeight,
            maxArtworkSize: _maxIconSize,
            labelLineHeight: _labelLineHeight * textScale,
          );

          // `Flexible` lets the title `Text` shrink to fit when the system
          // text scale is large enough that the natural Column height would
          // overflow the grid cell. `maxLines: 2` + ellipsis is the
          // visible-fallback for any remaining overflow. See
          // `hub-sheet-gap-and-logo-clip-plan.md` for the layout test that
          // depends on this resilience.
          final label = Flexible(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          );

          return Padding(
            padding: EdgeInsets.all(metrics.outerPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Artwork is decoration: below the shared drop threshold it
                // is omitted and the label centres on its own, exactly as
                // the Home tile does.
                if (metrics.showArtwork) ...[
                  Icon(
                    widget.icon,
                    size: metrics.artworkSize,
                    color: themeColors.textMuted,
                  ),
                  SizedBox(height: metrics.labelGap),
                ],
                label,
              ],
            ),
          );
        },
      ),
    );
  }
}
