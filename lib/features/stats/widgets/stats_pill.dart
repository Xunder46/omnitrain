import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// One labelled figure in the ALL TIME row.
///
/// Owned here so the Stats screen and Records & Trends render the same
/// three figures the same way rather than each drawing its own column.
class StatsPill extends StatelessWidget {
  final String label;
  final String value;
  final OmniThemeColors themeColors;
  final ThemeData theme;
  final Widget? trailingIcon;

  const StatsPill({
    super.key,
    required this.label,
    required this.value,
    required this.themeColors,
    required this.theme,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.5,
            color: themeColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: themeColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              trailingIcon!,
            ],
          ],
        ),
      ],
    );
  }
}
