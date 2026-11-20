import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// Screen shown after a backup restore (plan 278b, D-27824).
///
/// `StartupRoot` swaps the running app for this screen through
/// `AppRestart.maybeOf(context)?.showRestartRequired()`: the restored
/// data is only read at the next launch, so the old in-memory state
/// must not stay usable. The screen deliberately touches no repository
/// or state object and offers no way back — the only way forward is to
/// close and reopen the app.
///
/// See `docs/plans/2026-11-19-278b-settings-export-import-plan.md`
/// scenario S-27828 for the contract.
class RestoreCompleteScreen extends StatelessWidget {
  const RestoreCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mounted inside `StartupRoot`'s MaterialApp, which adopts the
    // saved theme on the next launch; listen so a theme change while
    // this screen is up still reaches the gradient below.
    return ValueListenableBuilder<AppTheme>(
      valueListenable: OmniTheme.activeThemeListenable,
      builder: (context, activeTheme, _) => _build(context, activeTheme),
    );
  }

  Widget _build(BuildContext context, AppTheme activeTheme) {
    return PopScope(
      // There is no route to go back to and nothing to resume; system
      // back must do nothing (S-27828).
      canPop: false,
      child: Scaffold(
        body: OmniGradientBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Restore complete',
                    key: const Key('restore-complete-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Close OmniTrain and open it again to finish. '
                      'Your data is restored.',
                      key: const Key('restore-complete-body'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
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
