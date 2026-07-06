import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// End-user startup-failure surface.
///
/// Replaces the old developer-oriented dead-end ("Error initializing
/// app. Check console for details.") with a plain-language message
/// and a Retry control. The widget is intentionally pure presentation:
/// it never holds business state, never talks to a repository, and
/// never observes a `ChangeNotifier`. The owning root passes a
/// retry callback in via [onRetry] and the widget just renders it.
///
/// Copy is deliberately free of developer terminology — no "console",
/// no "log", no "error", no raw exception text. See
/// `.github/agents/plans/startup-failure-screen-plan.md` (S-001) for
/// the full copy contract and the test that enforces it.
class StartupFailureScreen extends StatelessWidget {
  /// Called when the user taps Retry. The owning root uses this to
  /// re-invoke the entire `main()` startup sequence from scratch.
  final VoidCallback onRetry;

  /// While `true` the Retry button is disabled. The owning root
  /// flips this during an in-flight retry attempt so a fast double
  /// tap cannot trigger two concurrent startups.
  final bool isRetrying;

  const StartupFailureScreen({
    super.key,
    required this.onRetry,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = OmniTheme.colorsForTheme(OmniTheme.activeTheme);
    final theme = Theme.of(context);

    return Scaffold(
      // The gradient lives behind the Scaffold so it covers the
      // status bar and any safe-area insets, matching the rest of
      // the app's atmosphere.
      body: OmniGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Primary headline — short, plain-language, no
                  // developer verbiage. Reads as "something went
                  // wrong" without naming the failure category.
                  Text(
                    'Something went wrong while starting OmniTrain.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: tokens.textDominant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Secondary line — invites the user to try again
                  // without naming internal mechanisms.
                  Text(
                    'Tap Retry to try starting it again.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: tokens.textSecondary,
                      letterSpacing: 0.2,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Full-width primary CTA. Explicit `shape:`
                  // override per the global button convention;
                  // colours come from the active colorScheme —
                  // never hardcoded.
                  SizedBox(
                    height: OmniTheme.buttonPrimaryHeight,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isRetrying ? null : onRetry,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}