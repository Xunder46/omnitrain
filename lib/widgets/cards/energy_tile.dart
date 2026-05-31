import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Premium training category tile with energy core visualization
/// Features biomechanical aesthetic with depth and subtle animations
class EnergyTile extends StatefulWidget {
  final String title;
  final IconData? icon;
  final Widget? iconWidget;
  final List<Color> gradientColors;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isActive;

  const EnergyTile({
    super.key,
    required this.title,
    this.icon,
    this.iconWidget,
    required this.gradientColors,
    required this.accentColor,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<EnergyTile> createState() => _EnergyTileState();
}

class _EnergyTileState extends State<EnergyTile> {
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

  Widget _buildSurface() {
    final isActive = widget.isActive;
    final baseDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
      gradient: LinearGradient(
        colors: widget.gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: OmniTheme.colors.surfaceBorder,
        width: OmniTheme.surfaceBorderWidth,
      ),
      // Keep active tile shadow behavior unchanged.
      // Inactive tiles use color-matched shadows from their own palette.
      boxShadow: isActive
          ? [
              OmniTheme.deepShadow,
              BoxShadow(
                color: widget.accentColor.withOpacity(0.35),
                blurRadius: 40,
                spreadRadius: -10,
              ),
              BoxShadow(
                color: widget.accentColor.withOpacity(0.55),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ]
          : [
              BoxShadow(
                color: widget.accentColor.withOpacity(0.32),
                blurRadius: 26,
                spreadRadius: -8,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: widget.gradientColors.last.withOpacity(0.18),
                blurRadius: 16,
                spreadRadius: -12,
                offset: const Offset(0, 6),
              ),
            ],
    );

    return Container(
      decoration: baseDecoration,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.accentColor.withOpacity(0.08),
            Colors.transparent,
            Colors.black.withOpacity(0.12),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Hide text if width is too small (less than 150 pixels)
        final shouldShowText = constraints.maxWidth > 100;
        
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.iconWidget ?? Icon(
              widget.icon!,
              size: 70,
              color: OmniTheme.colors.textDominant,
            ),
            if (shouldShowText) const SizedBox(height: 10),
            // Title text
            if (shouldShowText)
              Flexible(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: OmniTheme.colors.textDominant,
                    fontWeight: FontWeight.w500,
                    letterSpacing: OmniTheme.titleLetterSpacing,
                    height: 1,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
