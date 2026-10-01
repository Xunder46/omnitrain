import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../state/watch/live_session_mirror_state.dart';
import '../layout/omni_surface.dart';

/// The way into a session that is running on the wrist, shown on the home
/// panel while one is live.
///
/// Plan: `docs/plans/2026-07-13-10-c2-phone-manage-bridge-live-sessions-plan.md`.
///
/// One line: which exercise the wrist is on, and how much has been logged. It
/// reads the session rather than a copy of it, so what it says is what the
/// wrist is doing at that moment. Presentation only — the caller decides where
/// it goes.
class LiveSessionEntryPoint extends StatelessWidget {
  const LiveSessionEntryPoint({
    super.key,
    required this.liveSession,
    required this.onTap,
  });

  /// Vertical padding (24) plus the surface's border (2).
  static const double _chrome = 26.0;

  /// One text line at `textScaler = 1.0`. The text scales; the chrome does
  /// not, and the 18pt icons never exceed the scaled line.
  static const double _textLine = 20.0;

  /// The vertical space this widget occupies at [textScale].
  ///
  /// The panel that hosts it does not scroll and has to budget for it, so the
  /// budget lives with the geometry it describes rather than being restated by
  /// the caller. `test/home_short_viewport_test.dart` asserts the rendered
  /// height against this at both supported text scales.
  static double budgetHeight(double textScale) =>
      _textLine * textScale + _chrome;

  final LiveSessionMirrorState liveSession;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = liveSession.currentExercise?['name'] as String? ?? 'Session';

    // `Material(type: transparency) + InkWell` wrapping the `OmniSurface`, the
    // same pairing the home nutrition card uses: the splash paints on the
    // Material's surface — the card's own body — rather than behind the opaque
    // card, where it would not be visible at all.
    return Material(
      key: const Key('live_session_entry_point'),
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        child: OmniSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.watch, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: OmniTheme.colors.textDominant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${liveSession.entries.length} logged',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: OmniTheme.colors.textSecondary,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: OmniTheme.colors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
