import 'package:flutter/material.dart';

/// The two fills the logger's progress indicators share, so the countdown
/// ring and the set bar can never drift apart.
///
/// "Dim primary" is the focused, not-yet-logged segment of `SetSegmentBar`
/// and the countdown ring before Start. "Track grey" is an unlogged segment
/// and the ring's track. Both derive from the theme's `ColorScheme`.
///
/// Plan: `docs/plans/2026-10-19-44-logger-feedback-round-plan/2026-10-19-44-logger-feedback-round-plan.md` (D-3).
class SessionProgressColors {
  const SessionProgressColors._();

  /// Primary at 115/255 opacity: "this is next, not done".
  static Color dimPrimary(ColorScheme scheme) => scheme.primary.withAlpha(115);

  /// On-surface at 51/255 opacity: "not reached yet".
  static Color trackGrey(ColorScheme scheme) => scheme.onSurface.withAlpha(51);
}
