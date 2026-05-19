import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

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

  Widget _buildSurface() {
    final themeColors = OmniTheme.colorsForTheme(widget.activeTheme);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        color: themeColors.surface,
        border: Border.all(
          color: themeColors.surfaceBorder,
          width: OmniTheme.surfaceBorderWidth,
        ),
        boxShadow: [
          OmniTheme.deepShadow,
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.icon,
            size: 42,
            color: themeColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: themeColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: OmniTheme.titleLetterSpacing,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
