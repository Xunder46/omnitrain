import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Premium dark navy surface container with engineered depth
/// Base component for cards, panels, and elevated surfaces
class OmniSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool showShadow;

  const OmniSurface({
    super.key,
    required this.child,
    this.padding,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: themeColors.surface,
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        border: Border.all(
          color: themeColors.surfaceBorder,
          width: OmniTheme.surfaceBorderWidth,
        ),
        boxShadow: showShadow ? [OmniTheme.deepShadow] : null,
      ),
      child: child,
    );
  }
}
