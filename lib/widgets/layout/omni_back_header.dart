import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Standardized back-and-title header for all secondary screens.
///
/// Implements [PreferredSizeWidget] so it can be used directly as
/// [Scaffold.appBar]. Always renders [Icons.arrow_back] in an [IconButton]
/// using [OmniTheme.textPrimary] for consistent icon color across all screens.
///
/// Title is rendered with [TextTheme.titleLarge] plus [FontWeight.w600] and
/// [OmniTheme.titleLetterSpacing] (0.4) so all screen headers share the same
/// typographic treatment regardless of the parent theme configuration.
class OmniBackHeader extends StatelessWidget implements PreferredSizeWidget {
  const OmniBackHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions,
  });

  /// Primary header text.
  final String title;

  /// Optional secondary line rendered below [title] in [TextTheme.bodySmall].
  final String? subtitle;

  /// Called when the back arrow is tapped.
  /// Defaults to [Navigator.of(context).pop()] when null.
  final VoidCallback? onBack;

  /// Optional trailing widgets placed in the AppBar actions slot.
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        color: OmniTheme.textPrimary,
        onPressed: onBack ?? () => Navigator.of(context).pop(),
      ),
      title: subtitle == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.textSecondary,
                  ),
                ),
              ],
            ),
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: OmniTheme.titleLetterSpacing,
        color: OmniTheme.textPrimary,
      ),
      actions: actions,
    );
  }
}
