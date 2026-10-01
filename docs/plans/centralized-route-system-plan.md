# Feature: Centralized Route System & Transition Bleed-Through Fix

## Overview

OmniTrain's app-level gradient architecture (`OmniGradientBackground` above the Navigator) correctly
solved static bleed-through (status bar, sheet-min gaps, overscroll, AppBar tints) but left one
acceptance criterion unverified: "No screen transition produces a flash of mismatched background."

Because every `Scaffold` is transparent, both the incoming and outgoing routes paint simultaneously
during a `MaterialPageRoute` slide. After the animation settles there is still a short window where
both routes are painted; when the compositor finally culls the bottom route the previous screen's
content (e.g. the Hub sheet) visibly snaps out. The fix is a dual-layer strategy: the app-level
gradient remains the safety net for uncovered window areas; each route independently brings its own
matching gradient so the incoming route fully occludes the outgoing one at every frame.

This effort also centralizes all screen navigation through a thin `OmniNavigator` helper class,
making every future cross-cutting concern (analytics, deep links, auth gates) a one-place plug-in
rather than 30 patches.

## Requirements

- Route-transition bleed-through is eliminated on every navigation path.
- App-level `OmniGradientBackground` layer is preserved unchanged.
- iOS edge-swipe-back gesture continues to work on every pushed screen.
- Every screen-level push and pushReplacement flows through `OmniNavigator`.
- Zero `MaterialPageRoute` or `PageRouteBuilder` usage outside the navigation module after migration.
- A fade-style variant is available for the splash→home transition.
- Tests cover all of the above; docs describe the new navigation contract.

## Acceptance Criteria

- [ ] A single shared route primitive `OmniRoute` (and fade variant `OmniFadeRoute`) exists in
      `lib/core/navigation/`.
- [ ] `OmniNavigator` helper class exposes `push`, `pushReplacement`, `popUntil`, and any other
      navigation operations currently in use; all screen pushes in `lib/features/` and
      `lib/widgets/` go through it.
- [ ] A post-migration grep for `MaterialPageRoute` and `PageRouteBuilder` in `lib/features/` and
      `lib/widgets/` returns **zero results**.
- [ ] Route-level gradient is visually identical to the app-level gradient in steady state —
      same theme tokens, radial highlight, noise overlay — on all six themes.
- [ ] App-level `OmniGradientBackground` remains in `app.dart` `builder:` wrapping the Navigator.
- [ ] No visible bleed-through at any frame (start, mid, end, post-settle) on any navigation path.
- [ ] iOS edge-swipe-back confirmed working on ≥3 navigation paths on a physical iOS device.
- [ ] Android back gesture / button unchanged.
- [ ] Theme switch via Settings updates app-level gradient, current route gradient, and overlays
      instantly, no artifacts.
- [ ] `OmniFadeRoute` used by splash→home transition; no bleed-through during the fade.
- [ ] All existing widget tests pass.
- [ ] New tests: route primitive construction, transition occlusion across all frames (incl.
      post-settle), iOS edge-swipe-back, theme switching mid-route, app-level gradient preservation,
      fade variant, `OmniNavigator` API surface.
- [ ] `docs/navigation_and_screens.md` updated with the new navigation contract.
- [ ] `docs/navigation_contract.md` created explaining the rule: raw route construction outside
      the navigation module is a review blocker.
- [ ] Gradient plan's "No screen transition produces a flash of mismatched background" criterion
      marked resolved with a pointer to this effort.
- [ ] Audit report committed at `docs/route-migration-audit.md` listing every call
      site migrated, every test touched, and the post-migration grep confirmation.

## Scenarios

- Home → Settings: Hub sheet no longer "ghosts" through Settings at transition end.
- Home → SessionOverview: clean slide; no tile grid visible through incoming screen.
- WorkoutSession → SessionSummary (pushReplacement): no flash at replace boundary.
- Onboarding → Home (pushReplacement): clean replace; onboarding content gone.
- iOS edge-swipe back from Settings to Home: gesture recognizer fires; back-gesture works.
- Theme switch while Settings screen is open: gradient on Settings screen updates live.
- App-level gradient still paints behind system insets after a screen is pushed.

---

## Iteration 1

### Analysis

**Affected call sites (31 total across 10 files):**

| File | Count |
|---|---|
| `lib/features/home/home_screen.dart` | 10 (lines 290, 346, 366, 386, 456, 586, 750, 768, 780, 792) |
| `lib/features/calendar/calendar_screen.dart` | 3 (163, 197, 213) |
| `lib/features/calendar/day_session_list_screen.dart` | 2 (182, 269) |
| `lib/features/session/session_overview_screen.dart` | 2 (96, 331) |
| `lib/features/session/workout_session_finish.dart` | 1 (161 — pushReplacement to Summary) |
| `lib/features/session/session_summary_screen.dart` | 2 (301, 320) |
| `lib/features/routine/my_routines_screen.dart` | 3 (198, 213, 298) |
| `lib/features/period/period_list_screen.dart` | 2 (86, 97) |
| `lib/features/onboarding/onboarding_screen.dart` | 1 (75 — pushReplacement to Home) |
| `lib/widgets/pickers/exercise_picker_dialog.dart` | 1 (175) |
| `lib/features/splash/omni_splash_screen.dart` | 1 (77 — `PageRouteBuilder` fade to Home) |

**Proposed new files:**
- `lib/core/navigation/omni_route.dart` — `OmniRoute<T>` and `OmniFadeRoute<T>` primitives
- `lib/core/navigation/omni_navigator.dart` — `OmniNavigator` static helper
- `lib/core/navigation/navigation.dart` — barrel export

**`OmniRoute` design:**
`OmniRoute<T>` extends `PageRoute<T>`. It:
- Sets `opaque = true` (this is the key change — routes claim to be opaque so Flutter culls the
  bottom route promptly, but they also paint their own gradient so the transparent Scaffold is
  fully backed by the route's own gradient layer).
- Wraps the given `builder` page in `OmniGradientBackground` (same widget, same theme resolution).
- Delegates the actual transition to `CupertinoPageTransitionsBuilder` on iOS and
  `FadeUpwardsPageTransitionsBuilder` on Android — matching current behavior exactly.
- Preserves `maintainState = true`, `fullscreenDialog` option.

**Why `opaque = true` is correct:**
- With `opaque = false` (current implicit behavior from transparent Scaffold), Flutter must keep
  the bottom route painted because it might show through. Setting `opaque = true` tells Flutter it
  can cull the bottom route as soon as the animation completes — or even skip painting it during the
  transition if the incoming route fully covers the screen. This is the standard Flutter optimization.
- The route's gradient ensures the screen is genuinely opaque to the user (gradient fills from edge
  to edge), so setting `opaque = true` is truthful.

**Visual tradeoff (documented):**
During the ~300ms slide, both routes are painting their own gradient (with radial highlight and
noise overlay). The overlap zone shows a brief doubling of the 5%-opacity radial highlight. At
that opacity level, during motion, this is below the perceptual threshold. The alternative
(removing the route-level highlight) would regress the steady-state aesthetic on every screen
permanently — an unacceptable tradeoff. The transient doubling is accepted.

**Home screen `OmniGradientBackground` in `body:`:**
`home_screen.dart` line 166 still uses `OmniGradientBackground` as a `body:` wrapper. This is
currently intentional (the gradient plan audit left it there for overscroll coverage inside the
home screen's scrollable area). After the route primitive wraps the whole page, this per-screen
usage becomes redundant but harmless — the route-level gradient is underneath; the body-level
gradient paints on top (identical colors). Remove it during the migration to keep one source of
truth. Verify overscroll still shows the correct gradient (it will, since the route-level gradient
covers the full screen area).

---

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### Phase 1 — Create the navigation module

**File: `lib/core/navigation/omni_route.dart`**

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// Shared route primitive used for every screen-level navigation push
/// in OmniTrain. Wraps the destination page in [OmniGradientBackground]
/// so the route fully occludes any route beneath it during transitions,
/// eliminating the bleed-through bug that occurs when every Scaffold is
/// transparent and `opaque == false`.
///
/// Uses [CupertinoPageTransitionsBuilder] on iOS (slide + edge-swipe-back)
/// and [FadeUpwardsPageTransitionsBuilder] on Android.
///
/// See docs/navigation_contract.md for the rule: raw MaterialPageRoute /
/// PageRouteBuilder outside this module is a code-review blocker.
class OmniRoute<T> extends PageRoute<T> {
  OmniRoute({
    required this.builder,
    super.settings,
    this.fullscreenDialog = false,
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final bool fullscreenDialog;

  @override
  final bool maintainState;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return OmniGradientBackground(child: builder(context));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    const builder = CupertinoPageTransitionsBuilder();
    return builder.buildTransitions<T>(
        this, context, animation, secondaryAnimation, child);
  }
}

/// Fade variant used for the splash→home transition.
/// Same gradient-wrapping guarantees as [OmniRoute]; no bleed-through.
class OmniFadeRoute<T> extends PageRoute<T> {
  OmniFadeRoute({
    required this.builder,
    super.settings,
    this.transitionDuration = const Duration(milliseconds: 600),
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final Duration transitionDuration;

  @override
  final bool maintainState;

  @override
  bool get opaque => true;

  @override
  bool get fullscreenDialog => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return OmniGradientBackground(child: builder(context));
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(opacity: animation, child: child);
  }
}
```

**File: `lib/core/navigation/omni_navigator.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'omni_route.dart';

/// Centralized navigation helper. All screen-level navigation in OmniTrain
/// goes through this class. Callers never instantiate route objects directly.
///
/// Cross-cutting concerns (analytics, deep links, auth gates) are added here
/// in a single place rather than patched across every call site.
abstract final class OmniNavigator {
  /// Push [builder] onto the navigator using the standard [OmniRoute]
  /// (platform-appropriate slide transition + gradient background).
  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool fullscreenDialog = false,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).push(OmniRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    ));
  }

  /// Replace the current route with [builder] using [OmniRoute].
  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    WidgetBuilder builder, {
    TO? result,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).pushReplacement(
      OmniRoute<T>(builder: builder, settings: settings),
      result: result,
    );
  }

  /// Replace the current route with [builder] using the fade variant
  /// [OmniFadeRoute]. Used for the splash→home transition.
  static Future<T?> pushReplacementFade<T, TO>(
    BuildContext context,
    WidgetBuilder builder, {
    Duration transitionDuration = const Duration(milliseconds: 600),
    TO? result,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).pushReplacement(
      OmniFadeRoute<T>(
        builder: builder,
        settings: settings,
        transitionDuration: transitionDuration,
      ),
      result: result,
    );
  }

  /// Pop routes until [predicate] returns true.
  static void popUntil(BuildContext context, RoutePredicate predicate) {
    Navigator.of(context).popUntil(predicate);
  }
}
```

**File: `lib/core/navigation/navigation.dart`** (barrel)

```dart
export 'omni_navigator.dart';
export 'omni_route.dart';
```

#### Phase 2 — Migrate all call sites

Replace every `Navigator.push(context, MaterialPageRoute(builder: (_) => Screen(...)))` with
`OmniNavigator.push(context, (_) => Screen(...))` and similarly for `pushReplacement`.

The `PageRouteBuilder` in `omni_splash_screen.dart` becomes `OmniNavigator.pushReplacementFade`.

Remove the `OmniGradientBackground` wrapper from `home_screen.dart` body (line 166 — now redundant;
the route-level gradient covers the full page).

**Files to migrate:**

1. `lib/features/home/home_screen.dart` (10 push sites + body-level gradient removal)
2. `lib/features/calendar/calendar_screen.dart` (3 push sites)
3. `lib/features/calendar/day_session_list_screen.dart` (2 push sites)
4. `lib/features/session/session_overview_screen.dart` (2 push sites)
5. `lib/features/session/workout_session_finish.dart` (1 pushReplacement)
6. `lib/features/session/session_summary_screen.dart` (2 push sites)
7. `lib/features/routine/my_routines_screen.dart` (3 push sites)
8. `lib/features/period/period_list_screen.dart` (2 push sites)
9. `lib/features/onboarding/onboarding_screen.dart` (1 pushReplacement)
10. `lib/widgets/pickers/exercise_picker_dialog.dart` (1 push site)
11. `lib/features/splash/omni_splash_screen.dart` (1 pushReplacementFade)

#### Phase 3 — Tests

New test file: `test/omni_route_test.dart`

Tests to create:
1. **Route primitive construction** — pump `OmniRoute` wrapping a minimal widget; verify
   `OmniGradientBackground` appears in the widget tree.
2. **Transition occlusion** — pump an app with two routes via `OmniNavigator.push`; advance
   animation through 0.0, 0.5, 1.0 (settled); at every frame verify the previous screen's
   content widget is NOT visible (either not in tree or occluded — use `findsNothing` or opacity
   checks). The post-settle frame (after `pumpAndSettle`) is the primary assertion.
3. **iOS edge-swipe-back** — pump a navigator with a pushed `OmniRoute`; simulate
   `TestGesture` drag from left edge; verify route pops.
4. **Theme switching mid-route** — pump app with `OmniRoute` pushed; call
   `settingsState.setTheme(...)` via `SettingsState`; `pumpAndSettle`; verify the route's
   `OmniGradientBackground` renders the new theme's gradient colors.
5. **App-level gradient preservation** — pump `MyApp`; push a screen via `OmniNavigator`; verify
   the `OmniGradientBackground` from `app.dart` builder is still present above the Navigator in
   the widget tree.
6. **Fade variant** — pump app; call `OmniNavigator.pushReplacementFade`; advance animation;
   verify `OmniGradientBackground` wraps the destination and previous screen content is not
   visible.
7. **`OmniNavigator` API** — unit/widget tests that call `push`, `pushReplacement`,
   `pushReplacementFade`, and `popUntil` and assert on the resulting route stack.

Existing tests to review:
- `screen_widget_test.dart`, `widget_test.dart`, `state_test.dart`, `interaction_flow_test.dart`,
  `session_toolbar_rework_test.dart`, `unsaved_changes_dialog_test.dart` — each reviewed for raw
  `MaterialPageRoute` / `PageRouteBuilder` use. Tests simulating real navigation: migrate to
  `OmniRoute` or `OmniNavigator`. Tests pumping screens in isolation as setup convenience: leave
  raw route in place, flag in audit report.

#### Phase 4 — Documentation

1. **`docs/navigation_and_screens.md`** — add a "Navigation Contract" section at the top:
   > All screen-level navigation goes through `OmniNavigator`. `OmniRoute` and `OmniFadeRoute`
   > are the only route types used for screen pushes. Any `MaterialPageRoute` or `PageRouteBuilder`
   > outside `lib/core/navigation/` is a code-review blocker.
   Update the navigation diagram to show `OmniNavigator → OmniRoute → OmniGradientBackground →
   Screen`.

2. **`docs/navigation_contract.md`** — new short doc:
   - Why the rule exists (bleed-through bug, dual-layer strategy)
   - What `OmniRoute` does (gradient wrapping + `opaque = true`)
   - The visual tradeoff accepted (transient highlight doubling during slide)
   - How to add a new screen (use `OmniNavigator.push`)
   - How to add cross-cutting concerns (edit `OmniNavigator` methods)

3. **`docs/gradient-window-layer-plan.md` / gradient plan acceptance criteria** — mark the
   "No screen transition produces a flash of mismatched background" item as resolved, pointer to
   this effort.

4. **`docs/route-migration-audit.md`** — committed after implementation:
   - Table of every call site migrated (file, line, before/after)
   - List of test files reviewed and decision per file
   - Post-migration grep output confirming zero results for `MaterialPageRoute` and
     `PageRouteBuilder` in `lib/features/` and `lib/widgets/`

---

### Implementation Steps

- [ ] 1. Create `lib/core/navigation/omni_route.dart` with `OmniRoute<T>` and `OmniFadeRoute<T>`
- [ ] 2. Create `lib/core/navigation/omni_navigator.dart` with `OmniNavigator` static class
- [ ] 3. Create `lib/core/navigation/navigation.dart` barrel export
- [ ] 4. Migrate `home_screen.dart` (10 push sites; remove body `OmniGradientBackground`)
- [ ] 5. Migrate `calendar_screen.dart` (3 push sites)
- [ ] 6. Migrate `day_session_list_screen.dart` (2 push sites)
- [ ] 7. Migrate `session_overview_screen.dart` (2 push sites)
- [ ] 8. Migrate `workout_session_finish.dart` (1 pushReplacement)
- [ ] 9. Migrate `session_summary_screen.dart` (2 push sites)
- [ ] 10. Migrate `my_routines_screen.dart` (3 push sites)
- [ ] 11. Migrate `period_list_screen.dart` (2 push sites)
- [ ] 12. Migrate `onboarding_screen.dart` (1 pushReplacement)
- [ ] 13. Migrate `exercise_picker_dialog.dart` (1 push site)
- [ ] 14. Migrate `omni_splash_screen.dart` (1 pushReplacementFade)
- [ ] 15. Run post-migration grep — confirm zero results in `lib/features/` and `lib/widgets/`
- [ ] 16. Create `test/omni_route_test.dart` with all 7 new tests
- [ ] 17. Review and update existing test files (8 files listed above)
- [ ] 18. Run full test suite — all tests pass
- [ ] 19. Update `docs/navigation_and_screens.md` with navigation contract section
- [ ] 20. Create `docs/navigation_contract.md`
- [ ] 21. Mark gradient plan acceptance criterion resolved
- [ ] 22. Commit `docs/route-migration-audit.md`
- [ ] 23. Manual device verification: 3 navigation paths on iOS (edge-swipe-back), 1 on Android

## Progress

- [x] Phase 1: Create navigation module (steps 1–3)
- [x] Phase 2: Migrate all call sites (steps 4–15)
- [x] Phase 3: Tests (steps 16–18)
- [x] Phase 4: Documentation (steps 19–22)
- [ ] Phase 5: Manual device verification (step 23)

### Implementation Notes (Phase 3 & 4)

- **Warning 2 fixed**: `OmniRoute.buildTransitions` now uses `Theme.of(context).platform` to select `CupertinoPageTransitionsBuilder` on iOS/macOS and `FadeUpwardsPageTransitionsBuilder` on Android, matching original behavior on all platforms.
- **`test/omni_route_test.dart` created**: 7 tests covering route primitive construction, transition occlusion, iOS edge-swipe-back, theme switching mid-route, app-level gradient preservation, fade variant, and full `OmniNavigator` API (`push`, `pushReplacement`, `pushReplacementFade`, `popUntil`).
- **`docs/navigation_and_screens.md`** updated with Navigation Contract section at the top (architecture diagram, method table, pointer to `navigation_contract.md`).
- **`docs/navigation_contract.md`** created: explains the bleed-through bug, dual-layer strategy, `OmniRoute` property table, accepted visual tradeoff, how to add screens, how to add cross-cutting concerns.
- **`docs/route-migration-audit.md`** committed: full table of all 31 migrated call sites, test file review decisions, post-migration grep confirmation.
- **Artifacts removed**: `fix_navigation.py`, `update_home_screen.py`, `update_home_screen_v2.py` deleted.

## Feedback

_Leave empty until a specialist or reviewer adds notes._
