/// "Congrats! New PR" toast — the in-session personal-record celebration.
///
/// When the user logs a strength set whose estimated one-rep-max (Epley)
/// exceeds the all-time best for that exercise (per the **Stats screen**
/// definition), `WorkoutSessionScreen._logSet()` calls
/// [PRToast.buildPRSnackBar] and shows it via `ScaffoldMessenger`. The
/// toast is intentionally minimal: a trophy icon + a single line of
/// copy. It is non-blocking — no dialog, no required tap, no
/// `action:` button — and auto-dismisses in 4.0 s so it never gates
/// the rest timer or the next set.
///
/// Two axes:
///   - **Weight axis** (Epley e1RM) — the original path.
///     `buildPRSnackBar` is the SnackBar factory.
///   - **Reps axis** (bodyweight) — added with the bodyweight
///     inclusion in
///     `docs/plans/stats-summary-fix-pack-plan.md`
///     (Item 2). `buildRepPRSnackBar` is the reps-axis
///     counterpart; it shares the same trophy + minimal-copy
///     treatment as `buildPRSnackBar` so the celebration reads
///     identically regardless of which axis fired.
///
/// The contract is pinned in
/// `docs/plans/in-session-pr-toast-plan.md` (Decision Ledger
/// D-9, D-10, D-11, D-12). The PR definition itself is the source of
/// truth in `StatsProgressService.epley1RM` + `getAllTimeBestE1RM` for
/// the weight axis and `StatsProgressService.getAllTimeBestReps` for
/// the reps axis; both surfaces share the formula so the in-session
/// toast, the post-workout summary, and the Stats screen always agree.
library;

import 'package:flutter/material.dart';

/// Builder for the in-session PR toast. Extracted to its own file so the
/// factory can be unit-tested independently of the full session screen.
class PRToast {
  PRToast._();

  /// Trophy icon size and copy font size for the in-session PR toast.
  /// The toast is intentionally celebratory: 2× the default icon
  /// (18 → 36 px) and 2× the default body-medium text (14 → 28 px)
  /// make the moment feel earned without crossing into the
  /// "influencer / coaching theater" territory the "Instrument
  /// panel, not influencer" global rule warns against.
  ///
  /// The text is wrapped in `Flexible` + `TextOverflow.ellipsis` so
  /// the toast never overflows on narrow phones (the icon stays at
  /// 36 px and the gap at 8 px regardless — the truncation, when
  /// it happens, only affects the trailing characters of the copy).
  /// On typical production phone widths (360–430 px) the full
  /// `"Congrats! New PR"` copy fits; on narrower surfaces the
  /// ellipsis kicks in.
  static const double _iconSize = 36.0;
  static const double _textFontSize = 18.0;

  /// Returns a `SnackBar` configured to celebrate a new personal record.
  ///
  /// Properties (all pinned by the plan's Decision Ledger):
  /// - `duration`: 4.0 s — long enough to read at a glance, short
  ///   enough that consecutive beating sets in a session don't queue
  ///   up forever. Auto-dismisses; never blocks the rest timer or
  ///   the next set (D-9).
  /// - `behavior`: `SnackBarBehavior.floating` — does not push the
  ///   bottom controls up; the user can keep typing in the numeric
  ///   editor (D-9, D-10).
  /// - `margin`: `EdgeInsets.only(top: 100, left: 16, right: 16)` —
  ///   the 100 px top inset positions the toast in the **upper half**
  ///   of the screen (above the vertical midline on any
  ///   production-supported phone height, 568–1366 px). The side
  ///   insets match the bottom-margin version of D-10. Position is
  ///   derived from a single explicit value so future tweaks stay
  ///   localized.
  /// - `backgroundColor`: `theme.colorScheme.surface` — derived from
  ///   the active theme, never hardcoded (D-12, "Theme tokens only"
  ///   global rule).
  /// - `content`: trophy icon (36 px, 2× the default 18 px) + 8 px
  ///   gap + `"Congrats! New PR"` copy at 28 px (2× bodyMedium's
  ///   default 14 px) (D-11, D-12).
  /// - No `action:` field — the user is never asked to tap "Dismiss"
  ///   or anything similar (D-9).
  static SnackBar buildPRSnackBar(ThemeData theme) {
    return SnackBar(
      duration: const Duration(milliseconds: 4000),
      behavior: SnackBarBehavior.floating,
      backgroundColor: theme.colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 150, left: 16, right: 16),
      content: Row(
        children: [
          Icon(
            Icons.emoji_events,
            size: _iconSize,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Congrats! New PR',
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: _textFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reps-axis variant of [buildPRSnackBar] for bodyweight PRs.
  /// Visually identical to the e1RM toast — same trophy icon, same
  /// `"Congrats! New PR"` copy, same 4.0 s auto-dismiss, same
  /// floating placement — so the celebration reads the same
  /// regardless of which axis fired. The [reps] argument is the
  /// just-logged max-reps count; it is currently unused on the
  /// toast itself (the copy stays minimal per D-11, the in-session
  /// toast is intentionally value-free) but is part of the public
  /// API so a future call-site that wants to surface the value has
  /// it available without a signature change.
  static SnackBar buildRepPRSnackBar(ThemeData theme, {int? reps}) {
    return SnackBar(
      duration: const Duration(milliseconds: 4000),
      behavior: SnackBarBehavior.floating,
      backgroundColor: theme.colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 150, left: 16, right: 16),
      content: Row(
        children: [
          Icon(
            Icons.emoji_events,
            size: _iconSize,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Congrats! New PR',
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: _textFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
