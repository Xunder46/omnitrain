import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Premium training category tile with energy core visualization
/// Features biomechanical aesthetic with depth and subtle animations
class EnergyTile extends StatefulWidget {
  final String title;
  final IconData? icon;
  final Widget? iconWidget;
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
    this.iconWidget,
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
        tween: Tween(begin: 0.1, end: 1.00)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.00, end: 0.1)
            .chain(CurveTween(curve: Curves.easeInOut)),
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
    final fillOpacity = isSecondary ? 0.08 : 0.18;

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
        padding: const EdgeInsets.all(20),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final isSecondary = widget.isSecondary;
    final iconSize = isSecondary ? 56.0 : 70.0;
    final iconColor = isSecondary
        ? Colors.white.withOpacity(0.75)
        : OmniTheme.colors.textDominant;
    final labelColor = isSecondary
        ? Colors.white.withOpacity(0.70)
        : OmniTheme.colors.textDominant;
    final labelWeight = isSecondary ? FontWeight.w500 : FontWeight.w600;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Hide text if width is too small (less than 150 pixels)
        final shouldShowText = constraints.maxWidth > 100;

        return Stack(
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
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _pulse.value,
                        child: child,
                      );
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
            // Content group: pin the icon in the upper third and the label
            // baseline to a fixed offset from the bottom edge, so the
            // label position does not float when the icon size changes
            // (e.g. across primary vs. secondary tiers or with the active
            // state). Uses `Positioned` inside the outer Stack instead of
            // `Column + spaceBetween` so the bottom anchor is deterministic
            // and independent of the icon's vertical extent.
            Positioned.fill(
              child: Column(
                children: [
                  // Upper region: pushes the icon into the upper third.
                  // On active tiles, the dot occupies the top ~18pt, so
                  // the upper region shrinks proportionally. `Expanded` is
                  // used so the icon stays centered within the upper band
                  // without leaking into the lower band.
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 15,
                      ),
                      child: Center(
                        child: IconTheme(
                          data: IconThemeData(
                              color: iconColor, size: iconSize),
                          child: widget.iconWidget ??
                              Icon(widget.icon,
                                  size: iconSize, color: iconColor),
                        ),
                      ),
                    ),
                  ),
                  if (shouldShowText) ...[
                    //const SizedBox(height: 8),
                    Padding(
                      // Reserve room at the bottom for the 1px shadow
                      // strip on primary tiles and consistent label
                      // position across tiers.
                      padding: const EdgeInsets.only(bottom: 12, top: 8),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: labelColor,
                              fontWeight: labelWeight,
                              letterSpacing: OmniTheme.titleLetterSpacing,
                              height: 1,
                            ),
                      ),
                    ),
                  ] else
                    const Spacer(flex: 1),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
