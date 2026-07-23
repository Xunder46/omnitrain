import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// Subtle "Demo" chip rendered next to built-in demo routines on the
/// My Routines list. Built on the project's typography and color
/// tokens — never hardcodes colors. The chip is purely informational
/// (the versioned refresh pipeline is the source of truth for
/// "is this a demo"); delete / edit behaviour is identical for demo
/// and user routines.
class DemoRoutineBadge extends StatelessWidget {
  const DemoRoutineBadge({super.key, this.compact = false});

  /// `true` renders the chip with reduced horizontal padding — useful
  /// when nested next to a title that already has generous spacing.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = OmniTheme.colors.textDominant;
    final background = scheme.primary.withOpacity(0.16);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        border: Border.all(color: scheme.primary.withOpacity(0.35), width: 1),
      ),
      child: Text(
        'Demo',
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          fontSize: 10,
        ),
      ),
    );
  }
}
