import 'package:flutter/material.dart';

/// The shared "nothing here yet" composition: a muted icon, a short title and
/// one line saying what to do next.
///
/// Every screen or list with nothing to show routes through this widget, so
/// the same message reads the same everywhere (plan 28, D-28.1). All colours
/// come from `Theme.of(context).colorScheme` — `onSurface` at three alphas —
/// so the composition follows the active theme without per-screen tokens.
///
/// The default (non-`compact`) variant centres itself in the space it is given
/// and scrolls when that space is shorter than the content, so it never
/// overflows on a small phone (320x568). `compact: true` drops the scroll
/// wrapper and shrinks the icon, for use inside a card that already supplies
/// its own padding and sits in a scrolling body.
class OmniEmptyState extends StatelessWidget {
  /// The headline. Kept verbatim per screen (D-28.2).
  final String title;

  /// One line saying what to do next. Omitted when `null`.
  final String? hint;

  /// The muted glyph above the title.
  final IconData icon;

  /// Optional content below the hint — a CTA, or a short explanation.
  final Widget? action;

  /// Shrinks the icon and drops the scroll wrapper, for use inside a card.
  final bool compact;

  /// The icon size of the full-screen variant.
  static const double iconSize = 64;

  /// The icon size of the [compact] variant.
  static const double compactIconSize = 40;

  const OmniEmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(
          icon,
          size: compact ? compactIconSize : iconSize,
          color: onSurface.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    );

    if (compact) return column;

    return LayoutBuilder(
      builder: (context, constraints) {
        // A scrolling body or a card gives this widget an unbounded height,
        // and the scroll wrapper below needs a bounded one to fill. With no
        // bounded height to fill, the centred column IS the empty state.
        if (!constraints.hasBoundedHeight) return column;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: column),
          ),
        );
      },
    );
  }
}
