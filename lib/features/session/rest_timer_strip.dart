// filepath: lib/features/session/rest_timer_strip.dart
//
// Docked strip that hosts the rest-timer chip on every workout surface.
//
// The strip is the single source of truth for the rest timer's vertical
// placement. The previous floating overlay lived at a fixed pixel offset
// above the screen bottom and landed on top of interactive controls on
// small screens — covering the Add Exercise / Add Block bar on the list
// view and the weight-adjustment section on the detail view for the
// entire rest period.
//
// The docked strip replaces that with an in-flow reserved strip that
// sits directly above the primary bottom action button on each surface
// (the `OmniBottomCTA` on the list views; the set controls row on the
// detail view). The chip's bounding rect never overlaps any interactive
// control; the strip's empty area uses a transparent `GestureDetector`
// with `HitTestBehavior.opaque` so taps on the padding around the chip
// do not interfere with the screen underneath; and the strip collapses
// to zero height when no rest is in progress so the screen does not
// reserve vertical space it is not using.
//
// Behaviour that this widget intentionally does not own:
//   * Visibility — `_shouldShowRestOverlay()` in
//     `workout_session_global_timer.dart` is the single helper that
//     decides whether the strip is visible (edit-mode, running
//     effort, cross-effort rest, and "no rest open" cases). The
//     caller passes a `visible` flag.
//   * The chip's tap-to-pause / resume behaviour — owned by
//     `_toggleRestChip` on the session state; the chip is built and
//     passed in by the caller.
//
// Verified by `test/rest_timer_docked_strip_test.dart`.

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// Docked strip hosting the rest-timer chip.
///
/// The strip's reserved height is [OmniTheme.restStripHeight] when
/// [visible] is true and zero otherwise. The height transition is
/// animated so appearing and disappearing the chip does not jolt
/// neighbouring content, but the underlying scroll offset is left
/// untouched (the strip lives in a `Stack` layer above the
/// scrollable, so the scrollable's geometry does not depend on the
/// strip's presence — see the test suite for the scroll-offset
/// invariants).
///
/// The strip's empty area (the padding around the chip) absorbs
/// taps via a transparent `GestureDetector` with
/// `HitTestBehavior.opaque`; the chip itself is layered on top of
/// that detector in a `Stack` and receives its own taps because
/// Flutter's hit test resolves deepest-child-first. The result is
/// that a tap on the padding around the chip does nothing, while
/// a tap on the chip itself fires its tap-to-pause / resume
/// handler.
class RestTimerStrip extends StatelessWidget {
  /// Whether the strip should be visible. Driven by
  /// `_shouldShowRestOverlay()` on the session state. When false,
  /// the strip is collapsed to zero height and the chip is not
  /// mounted.
  final bool visible;

  /// The chip widget to host inside the strip. Typically the
  /// `_buildRestOverlayChip(...)` output. The chip's tap behaviour
  /// is owned by the caller; this widget does not intercept it.
  final Widget child;

  /// Animation duration for the strip's height transition. Kept
  /// short so appearing or disappearing the rest timer feels
  /// immediate. Reused by callers that need to coordinate the
  /// scrollable's bottom padding animation with the strip's
  /// appearance / disappearance so the content does not jolt.
  static const Duration animationDuration = Duration(milliseconds: 200);

  const RestTimerStrip({super.key, required this.visible, required this.child});

  /// Stable key for the strip widget, used by tests to locate the
  /// strip regardless of which surface is foregrounded. Callers
  /// may override it via the `key:` parameter of the constructor.
  static const Key widgetKey = Key('rest-strip');

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      key: widgetKey,
      duration: animationDuration,
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: visible
          ? SizedBox(
              height: OmniTheme.restStripHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background tap-absorber. A transparent
                  // GestureDetector with HitTestBehavior.opaque
                  // catches taps that land on the strip's padding
                  // (anywhere not covered by the chip). The onTap
                  // is a no-op so the tap is silently consumed
                  // and does not bubble to the scrollable beneath.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  // The chip on top. Flutter's hit test resolves
                  // deepest-child-first, so the chip's own
                  // Material + InkWell handles taps that land on
                  // the chip itself; the GestureDetector above
                  // only handles taps on the surrounding padding.
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OmniTheme.restStripHorizontalPadding,
                      ),
                      child: child,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}
