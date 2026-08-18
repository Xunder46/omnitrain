import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/tile_artwork_metrics.dart';

/// Premium training category tile with energy core visualization
/// Features biomechanical aesthetic with depth and subtle animations
class EnergyTile extends StatefulWidget {
  final String title;
  final IconData? icon;

  /// Custom-drawn artwork, supplied as a builder so this tile — not the
  /// caller — decides how large it renders. See [TileArtworkMetrics].
  final TileArtworkBuilder? artworkBuilder;
  final Color accentColor;
  final VoidCallback onTap;

  /// Whether this tile belongs to the visually secondary tier.
  ///
  /// Secondary tiles (Free, Routines) render with:
  ///   - 8% own-accent fill (instead of 18%)
  ///   - smaller icon (56 vs 70), dimmed to white @ 75%
  ///   - label weight Medium (w500) and color white @ 70%
  ///   - no 1px top rim highlight, no 1px bottom inner shadow
  final bool isSecondary;
  final bool isActive;

  const EnergyTile({
    super.key,
    required this.title,
    this.icon,
    this.artworkBuilder,
    required this.accentColor,
    required this.onTap,
    this.isSecondary = false,
    this.isActive = false,
  });

  @override
  State<EnergyTile> createState() => _EnergyTileState();
}

class _EnergyTileState extends State<EnergyTile>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  // Single controller drives the active-state dot pulse. 1.8s cycle, well
  // under the 3Hz epilepsy threshold. Owned here so the dot is rebuilt only
  // on `isActive` transitions.
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.1,
          end: 1.00,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.00,
          end: 0.1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_pulseController);
    if (widget.isActive) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant EnergyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.isActive && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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

  Widget _buildSurface() {
    final isActive = widget.isActive;
    final isSecondary = widget.isSecondary;
    final fillOpacity = isSecondary ? 0.20 : 0.40;

    final baseDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
      color: widget.accentColor.withOpacity(fillOpacity),
      border: Border.all(
        color: OmniTheme.colors.surfaceBorder,
        width: OmniTheme.surfaceBorderWidth,
      ),
      // No resting drop shadow — both tiers.
      // The isActive branch is preserved as a functional in-progress
      // indicator (accent glow + deep shadow) and is intentionally exempt
      // from the "no drop shadow" rule for the resting state. Blur radii
      // and inner-glow alpha were nudged up slightly (40→48, 24→28,
      // 0.55→0.65) so the active tile stays visibly the brightest card
      // now that all four primary tiles carry a defined rim treatment.
      boxShadow: isActive
          ? [
              OmniTheme.deepShadow,
              BoxShadow(
                color: widget.accentColor.withOpacity(0.40),
                blurRadius: 48,
                spreadRadius: -10,
              ),
              BoxShadow(
                color: widget.accentColor.withOpacity(0.65),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ]
          : null,
    );

    return Semantics(
      label: isActive ? '${widget.title}, Workout in progress' : null,
      excludeSemantics: false,
      child: Container(
        decoration: baseDecoration,
        // No gradient overlay. Primary tiles get crisp 1px top-rim + 1px
        // bottom-inner-shadow strips inside the content (see _buildContent),
        // clipped to the rounded surface via Clip.hardEdge on the Stack.
        // Secondary tiles render with the base decoration only.
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final isSecondary = widget.isSecondary;
    // The per-tier artwork ceiling — the size on a tile with room to spare.
    // The shared rule shrinks below it; nothing may exceed it.
    final maxArtworkSize = isSecondary ? 56.0 : 70.0;
    final iconColor = isSecondary
        ? Colors.white.withOpacity(0.75)
        : OmniTheme.colors.textDominant;
    final labelColor = isSecondary
        ? Colors.white.withOpacity(0.70)
        : OmniTheme.colors.textDominant;
    final labelWeight = isSecondary ? FontWeight.w500 : FontWeight.w600;

    final artworkRegionKey = ValueKey(
      'energy_tile_artwork_region_${widget.title}',
    );
    final artworkKey = ValueKey('energy_tile_artwork_${widget.title}');
    final labelKey = ValueKey('energy_tile_label_${widget.title}');
    final statusKey = ValueKey('energy_tile_status_${widget.title}');

    return LayoutBuilder(
      builder: (context, constraints) {
        // Every dimension below comes from the one shared sizing rule.
        // This tile states its label style and its per-tier artwork
        // ceiling; it does not restate the rule. See
        // `lib/core/constants/tile_artwork_metrics.dart`.
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final metrics = TileArtworkMetrics.resolve(
          tileHeight: constraints.maxHeight,
          maxArtworkSize: maxArtworkSize,
          // 16pt from titleSmall, at the active text scale.
          labelLineHeight: 16.0 * textScale,
        );

        final outerPadding = metrics.outerPadding;
        final showArtwork = metrics.showArtwork;
        final artworkHeight = metrics.artworkSize;
        const artworkTopInset = TileArtworkMetrics.artworkTopInset;

        // The label widget is shared between the two layouts.
        final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: labelColor,
          fontWeight: labelWeight,
          letterSpacing: OmniTheme.titleLetterSpacing,
          height: 1,
        );
        final label = Text(
          widget.title,
          key: labelKey,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: labelStyle,
        );

        // The artwork, wrapped with the artwork key so the test can locate
        // its bounding box. Custom-drawn artwork is built at the resolved
        // size exactly like a standard icon — the builder indirection is
        // what keeps a caller from pinning a fixed size past the rule.
        final artwork = widget.artworkBuilder != null
            ? widget.artworkBuilder!(artworkHeight, iconColor)
            : Icon(widget.icon, size: artworkHeight, color: iconColor);
        final iconChild = KeyedSubtree(
          key: artworkKey,
          child: IconTheme(
            data: IconThemeData(color: iconColor, size: artworkHeight),
            child: artwork,
          ),
        );

        // The artwork region has breathing room above the icon so it
        // never collides with the active dot.
        final artworkRegion = KeyedSubtree(
          key: artworkRegionKey,
          child: Padding(
            padding: const EdgeInsets.only(top: artworkTopInset),
            child: Center(child: iconChild),
          ),
        );

        // The label padding keeps the 12/8 ratio (12 bottom, 8 top) so
        // tall tiles render with the original spacing; cramped tiles
        // shrink both sides proportionally. The split is owned by the
        // shared rule.
        final labelInLayout = Padding(
          padding: EdgeInsets.only(
            bottom: metrics.labelGapBottom,
            top: metrics.labelGapTop,
          ),
          child: label,
        );

        final content = showArtwork
            ? Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(child: artworkRegion),
                  labelInLayout,
                ],
              )
            : Center(child: label);

        return Padding(
          padding: EdgeInsets.all(outerPadding),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 1px top rim highlight — drawn first so content sits above.
              if (!isSecondary)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
              // 1px bottom inner shadow — sits at the very bottom edge, full
              // width. Clipped to the rounded corners by Stack's Clip.hardEdge.
              if (!isSecondary)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.20),
                    ),
                  ),
                ),
              // Pulsing "live" dot — only on active tiles. ~8pt diameter,
              // top-right ~10pt inset. Dot only animates; the glow itself
              // remains static. The dot is decorative (ExcludeSemantics) so
              // it is not announced separately from the tile.
              if (widget.isActive)
                Positioned(
                  top: 0,
                  right: 0,
                  child: KeyedSubtree(
                    key: statusKey,
                    child: ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          return Opacity(opacity: _pulse.value, child: child);
                        },
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x4D000000), // black @ 30%
                                blurRadius: 1,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Content group: when the artwork fits the budget, render
              // the artwork at the top and the label at the bottom (the
              // original anchored layout).  When the budget is too tight,
              // omit the artwork and centre the label — the label is the
              // identifying content, the artwork is decorative.
              Positioned.fill(child: content),
            ],
          ),
        );
      },
    );
  }
}
