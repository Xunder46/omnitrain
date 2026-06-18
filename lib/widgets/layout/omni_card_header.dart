import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Standardized card-level header rendered above an outlined card.
///
/// Wraps a title on the left and an optional `actions` cluster on the
/// right in a `Row(MainAxisAlignment.spaceBetween)`. The default bottom
/// padding is 8 dp — the gap that callers historically hand-rolled
/// with a `SizedBox(height: 8)` between the header and the card below.
///
/// Title typography follows the canonical section/card-header style
/// (`labelSmall` + `w600` + `letterSpacing: 2.0` + `textMuted`) so every
/// card in the app reads as a member of the same hierarchy. See the
/// "Section / Card Headers" section of `docs/design_system.md` for the
/// design contract.
///
/// The widget is presentation-only. It has no state, no repository
/// access, and no business logic. Cards below the header are owned by
/// the caller — typically an `OmniSurface`.
class OmniCardHeader extends StatelessWidget {
  const OmniCardHeader({
    super.key,
    required this.title,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, 8),
  });

  /// Title text rendered on the left side of the row.
  final String title;

  /// Optional trailing widgets (icon buttons, controls) rendered in a
  /// right-aligned cluster. When `null` or empty, no cluster is rendered
  /// and the title takes the full width.
  final List<Widget>? actions;

  /// Padding around the row. Default leaves an 8 dp gap below the row
  /// so the header sits cleanly above the card beneath it. Callers can
  /// override to add horizontal padding or change the gap.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Local non-null list so the analyzer can promote across the
    // `if (hasActions)` branch without a `!` inside the `Row`
    // constructor's `children:` argument.
    final effectiveActions = actions ?? const <Widget>[];
    final hasActions = effectiveActions.isNotEmpty;

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              key: const Key('omniCardHeader_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: OmniTheme.colors.textMuted,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (hasActions)
            Row(
              key: const Key('omniCardHeader_actions'),
              mainAxisSize: MainAxisSize.min,
              children: effectiveActions,
            ),
        ],
      ),
    );
  }
}
