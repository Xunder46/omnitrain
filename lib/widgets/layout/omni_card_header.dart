import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// Standardized card-level header rendered above an outlined card.
///
/// Wraps a title on the left and an optional `actions` cluster on the
/// right in a `Row(MainAxisAlignment.spaceBetween)`. The cluster takes
/// at most half the header's width, so a long action ellipsizes rather
/// than pushing the title below half. The default bottom padding is
/// 8 dp — the gap that callers historically hand-rolled with a
/// `SizedBox(height: 8)` between the header and the card below.
/// Optionally, a [leading] widget sits directly left of the title and
/// a [trailing] widget directly right of it (a flanked title row).
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
    this.leading,
    this.trailing,
    this.titleMinWidth,
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

  /// Optional widget directly left of the title (a day-step arrow). With
  /// [leading] or [trailing] the title sits between them, left-aligned; with
  /// neither the row is exactly the plain header.
  final Widget? leading;

  /// Optional widget directly right of the title.
  final Widget? trailing;

  /// Minimum width of the title text when it is flanked, so a [trailing]
  /// control keeps its place as the title text changes length. Ignored without
  /// [leading] or [trailing].
  final double? titleMinWidth;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The cluster takes at most half the header; the title stays
          // `Expanded` and keeps the rest, so a long action ellipsizes at
          // the cap instead of squeezing the title below half the header.
          // Under an unbounded parent there is no cap to apply.
          final maxActionsWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth * 0.5
              : double.infinity;
          final titleText = Text(
            title,
            key: const Key('omniCardHeader_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: OmniTheme.colors.textMuted,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w600,
            ),
          );
          final flanked = leading != null || trailing != null;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (flanked)
                Expanded(
                  child: Row(
                    children: [
                      ?leading,
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: titleMinWidth ?? 0,
                          ),
                          child: Align(widthFactor: 1.0, child: titleText),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                )
              else
                Expanded(child: titleText),
              if (hasActions)
                // The cap bounds the cluster; the loose `Flexible`s pass that
                // bound down to each action so a long label (the window chip)
                // ellipsizes instead of overflowing the row at narrow widths
                // and large text scales.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxActionsWidth),
                  child: Row(
                    key: const Key('omniCardHeader_actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final action in effectiveActions)
                        Flexible(fit: FlexFit.loose, child: action),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
