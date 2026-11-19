import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../widgets/layout/omni_surface.dart';

/// The way into Records & Trends: a labelled row that closes the Stats list
/// (plan 219; the header no longer carries a chart icon). Presentation only;
/// the screen owns the navigation.
class RecordsLinkRow extends StatelessWidget {
  final OmniThemeColors themeColors;
  final VoidCallback onTap;

  const RecordsLinkRow({
    super.key,
    required this.themeColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Semantics(
        label: 'Records & Trends',
        button: true,
        child: InkWell(
          key: const Key('stats_records_link'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Records & Trends',
                        key: const Key('stats_records_link_title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: themeColors.textDominant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your personal records and the full history of each exercise.',
                        key: const Key('stats_records_link_hint'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: themeColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chevron_right, color: themeColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
