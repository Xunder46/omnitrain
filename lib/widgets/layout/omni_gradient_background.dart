import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Reusable cosmic gradient background with optional radial highlight
/// Used throughout OMNITRAIN for consistent atmosphere
class OmniGradientBackground extends StatelessWidget {
  final Widget child;
  final bool showRadialHighlight;

  const OmniGradientBackground({
    super.key,
    required this.child,
    this.showRadialHighlight = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            OmniTheme.backgroundGradientTop,
            OmniTheme.backgroundGradientBottom,
          ],
        ),
      ),
      child: showRadialHighlight
          ? Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.5,
                  colors: [
                    Colors.white.withOpacity(0.03),
                    Colors.transparent,
                  ],
                ),
              ),
              child: child,
            )
          : child,
    );
  }
}
