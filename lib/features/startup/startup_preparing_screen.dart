import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// Neutral preparation surface rendered by [StartupRoot] while the
/// startup runner is in flight.
///
/// Deliberately minimal:
///
///  - No brand content (no logo, no wordmark, no tag line).
///  - No copy that could be mistaken for a failure message.
///  - No motion that finishes in a way that could be confused for
///    a transition into the app.
///
/// The widget is a single `CircularProgressIndicator` centred on
/// the gradient background. The role is the same as the launch
/// image on a native app: a blank-ish surface that conveys
/// "working" without putting anything on screen that the user
/// could read as a state of the running app.
///
/// See `.github/agents/plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md`
/// scenario S-001 for the contract.
class StartupPreparingScreen extends StatelessWidget {
  const StartupPreparingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = OmniTheme.colorsForTheme(OmniTheme.activeTheme).primary;

    return Scaffold(
      // The gradient covers the status bar and any safe-area insets,
      // matching the rest of the app's atmosphere so the eventual
      // transition into the running app stays visually calm.
      body: OmniGradientBackground(
        child: SafeArea(
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
