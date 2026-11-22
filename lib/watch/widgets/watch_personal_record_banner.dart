/// The "New PR" banner both Wear surfaces overlay.
///
/// Plan: `docs/plans/2026-11-22-289-wear-new-pr-banner-plan/2026-11-22-289-wear-new-pr-banner-plan.md`
/// (D-28902, D-28903). The Dart twin of the Apple client's
/// `WatchPersonalRecordBanner` (series 87, plan 88): a trophy and two words over
/// the top of a surface while the logging state's window is open. The logging
/// surface shows it while the wrist stays there, and the rest surface the shell
/// swaps in the instant a log starts a rest shows the same widget, so a record
/// logged as the rest begins is not torn down with the logging screen.
///
/// Opacity is the only thing that can change it: no movement, no animation, so
/// reduced motion needs nothing extra. It takes no touch, so the button under it
/// stays the surface's own, and it wears the phone's accent through the theme's
/// `primary` (plan 286).
library;

import 'package:flutter/material.dart';

import '../logging/watch_logging_state.dart';

/// The banner's fixed copy and window, named like the Apple `WatchPersonalRecordCopy`.
abstract final class WatchPersonalRecordCopy {
  /// About four seconds: long enough to read on a wrist, short enough not to
  /// cover the next set's rows. A second record restarts the window.
  static const Duration bannerDuration = WatchLoggingState.personalRecordWindow;

  static const String label = 'New PR';

  /// What a screen reader says (the Apple `WatchSpokenText.personalRecord`).
  static const String spoken = 'New personal record';
}

class WatchPersonalRecordBanner extends StatelessWidget {
  const WatchPersonalRecordBanner({super.key, required this.state});

  final WatchLoggingState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isPersonalRecordBannerVisible(state.now())) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: WatchPersonalRecordCopy.spoken,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events, size: 14, color: scheme.onPrimary),
                const SizedBox(width: 4),
                Text(
                  WatchPersonalRecordCopy.label,
                  style: styles.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
