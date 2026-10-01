import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// Shared full-width bottom call-to-action used by screens with a
/// single persistent footer action.
///
/// **Single source of truth for primary bottom CTA placement and
/// width.** Every screen that exposes a primary bottom action must
/// use this widget — see
/// `docs/plans/primary-bottom-cta-anchor-width-plan.md`.
///
/// The widget enforces a shared contract:
///
/// * **Height** — `OmniTheme.buttonPrimaryHeight` (56 dp).
/// * **Width** — `double.infinity`, inset by
///   `OmniTheme.bottomCTAHorizontalPadding` on each side, so the
///   button's left/right edges sit at exactly the same horizontal
///   margin on every screen.
/// * **Corner radius** — `OmniTheme.buttonBorderRadius` (12 dp).
/// * **Vertical anchor** — `SafeArea(top: false)` (bottom on by
///   default) plus `OmniTheme.bottomCTAVerticalBottomPadding`. The
///   button clears the device home indicator on iOS and the
///   navigation bar on Android uniformly.
/// * **Footer treatment** — theme-reactive fade gradient using
///   `colorScheme.surface` so the CTA lifts above scrollable content.
///
/// Call sites must not override padding, radius, height, or color.
/// Do not embed a `Spacer() + SizedBox + FilledButton` at the
/// bottom of a screen — that pattern bypasses this contract and
/// has been removed in favour of `Scaffold.bottomNavigationBar:
/// OmniBottomCTA(...)`.
class OmniBottomCTA extends StatelessWidget {
  /// Button text. A leading `+` triggers the shared add affordance.
  final String label;

  /// Tap handler. `null` disables the CTA.
  final VoidCallback? onPressed;

  /// When true, the CTA uses the active theme's destructive /
  /// error colors instead of the primary accent. Same shape and
  /// placement as the standard variant.
  final bool isDestructive;

  /// Optional `Key` forwarded to the rendered `FilledButton`. Used
  /// by callers that want to expose the CTA as a stable test
  /// target (e.g. the `food_form_save` key on the food library
  /// host screens, which preserves the existing test contract).
  final Key? buttonKey;

  const OmniBottomCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final backgroundColor = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final foregroundColor = isDestructive
        ? theme.colorScheme.onError
        : theme.colorScheme.onPrimary;

    return Material(
      type: MaterialType.transparency,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              surface.withOpacity(0.0),
              surface.withOpacity(0.92),
              surface,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        // SafeArea(top: false) — bottom on by default — keeps the
        // button above the device's home indicator (iOS) and
        // gesture / 3-button nav bar (Android). Combined with
        // `bottomCTAVerticalBottomPadding` this is the shared
        // vertical anchor.
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniTheme.bottomCTAHorizontalPadding,
              OmniTheme.bottomCTAVerticalTopPadding,
              OmniTheme.bottomCTAHorizontalPadding,
              OmniTheme.bottomCTAVerticalBottomPadding,
            ),
            child: SizedBox(
              width: double.infinity,
              height: OmniTheme.buttonPrimaryHeight,
              child: FilledButton(
                key: buttonKey,
                onPressed: onPressed,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return theme.colorScheme.onSurface.withOpacity(0.12);
                    }
                    return backgroundColor;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return theme.colorScheme.onSurface.withOpacity(0.38);
                    }
                    return foregroundColor;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                  ),
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
