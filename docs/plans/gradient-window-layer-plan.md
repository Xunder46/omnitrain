# Feature: Gradient Background — App-Level Window Layer

## Overview
Promote `OmniGradientBackground` from a per-screen `body` wrapper to a true app-level layer that paints the entire device window. Every visible region — status bar inset, bottom gesture inset, area behind the home maintenance sheet, route transition surfaces — will show the gradient instead of the solid `scaffoldBackgroundColor` fallback. Remove the redundant per-screen wrappers after the app-level layer is in place.

## Requirements
- The gradient fills the entire window at all times: status bar, content area, bottom system inset, safe-area gutters.
- No screen introduces its own opaque background that blocks the gradient (unless explicitly opting in).
- The maintenance sheet's minimum extent no longer reveals a flat-color band below or above the sheet.
- Dragging / overscrolling the home tile grid in any direction shows a continuous gradient with no seam.
- Theme switches update the entire window gradient instantly.
- The radial highlight and noise overlay remain functional.
- Existing tests still pass; any test asserting on the old per-screen wrapper is updated.

## Acceptance Criteria
- [ ] Home screen: aggressive overscroll (up and down) shows continuous gradient, no color band at top or bottom.
- [ ] Home screen: maintenance sheet at minimum extent — area above/below sheet shows gradient, not a flat color.
- [ ] Every screen (session, exercise editor, picker, calendar, day-session list, stats, profile, settings, routines, onboarding, splash, periods) verified visually — gradient fills the window.
- [ ] No screen transition produces a flash of mismatched background during the route animation.
- [ ] Theme switching updates the full window gradient with no residual regions retaining the old color.
- [ ] Verified on: one notched iPhone (Dynamic Island or notch), one non-notched device, one Android gesture-nav device.
- [ ] No screen that previously had a deliberate opaque region has unintentionally become transparent.
- [ ] Radial highlight overlay and noise overlay still render correctly on top of the gradient.
- [ ] All existing widget tests pass; updated tests assert on the new app-level gradient structure.

## Screens Inventory (27 `OmniGradientBackground` usages)

| Screen / file | Usages | Notes |
|---|---|---|
| `home/home_screen.dart` L152 | 1 | `Scaffold(backgroundColor: Colors.transparent)` — good start; missing `extendBody: true` |
| `session/workout_session_list_view.dart` L344, 435, 519, 638, 647, 705, 748 | 7 | Multiple conditional Scaffold branches |
| `session/session_summary_screen.dart` L537 | 1 | |
| `routine/my_routines_screen.dart` L63 | 1 | |
| `routine/routine_setup_screen.dart` L110, 185, 596 | 3 | Three Scaffold branches |
| `onboarding/onboarding_screen.dart` L99 | 1 | `Scaffold(backgroundColor: Colors.transparent)` |
| `splash/omni_splash_screen.dart` L111 | 1 | Scaffold has no explicit `backgroundColor` |
| `calendar/calendar_screen.dart` L97 | 1 | |
| `calendar/day_session_list_screen.dart` L81 | 1 | |
| `stats/stats_screen.dart` L168 | 1 | Inside conditional branch |
| `exercise/exercise_editor_screen.dart` L252, 265 | 2 | Two Scaffold branches |
| `profile/profile_screen.dart` L57 | 1 | |
| `settings/settings_screen.dart` L34 | 1 | |
| `period/create_period_screen.dart` L97 | 1 | |
| `period/period_list_screen.dart` L39 | 1 | |
| `home/maintenance_placeholder_screen.dart` L29 | 1 | |

## Scenarios
- User idles on home screen → full gradient visible including status bar and bottom gesture area.
- User drags maintenance sheet from min to max → no color band at any point during drag.
- User aggressively overscrolls tile grid → gradient continues, no brown/flat region revealed.
- User navigates home → session → back → gradient consistent throughout transition.
- User switches theme in settings → entire window updates immediately.
- User with older iPhone (no Dynamic Island) sees gradient flush at top.
- Android user with gesture nav bar sees gradient continue behind nav bar.

---

## Iteration 1

### Analysis

**Root causes:**
1. `scaffoldBackgroundColor` in `buildTheme()` (`app.dart` L149) is set to `tokens.backgroundBottom` (the solid warm brown/dark stop of the gradient). Any area not covered by `OmniGradientBackground`'s `body` widget shows this flat color.
2. Home screen `Scaffold` has `extendBodyBehindAppBar: true` but **not** `extendBody: true`, so the system bottom inset is not painted by the body gradient.
3. `OmniSplashScreen` Scaffold has no explicit `backgroundColor`, so it also inherits the solid fallback.
4. `OnboardingScreen` Scaffold sets `backgroundColor: Colors.transparent` — correct approach, but depends on a parent surface that currently is the solid scaffold color from `MaterialApp`.

**Correct architectural fix:**
Wrap `MaterialApp` (or its immediate child) in `OmniGradientBackground` so the gradient paints the entire window surface. Then:
- Set `scaffoldBackgroundColor: Colors.transparent` in `buildTheme()` so every Scaffold is transparent by default.
- Remove per-screen `OmniGradientBackground` wrappers from every `body:` — they are redundant once the app-level layer exists.
- Repurpose `OmniGradientBackground` so it can still be used explicitly on overlays/sheets that need their own gradient surface (e.g. full-screen modal routes that cover the app layer).

**Hero / route-transition risk:**
Because `MaterialApp` manages the navigator, wrapping it with a gradient widget is straightforward — the gradient is behind the navigator stack, so route animations (fades, slides) all composit over a stable gradient background. There is no Hero interaction risk with this placement.

**`OmniGradientBackground` repurposing:**
The widget itself stays. Its `showRadialHighlight` and noise overlay logic are preserved. It gains a mode:
- **`isAppLayer: true`** (new, default `false`): renders the full gradient + overlays.
- When used as app-level, the existing usages inside `body:` simply get removed; the widget continues to serve any screens that push a full-screen opaque surface (currently none, but keeps the door open).

Alternatively — simpler — just leave `OmniGradientBackground` unchanged and wrap it around the `MaterialApp` builder result. Per-screen usages become `child:` pass-throughs only (no-op gradient-less containers). See Step 4 below for the cleanest approach.

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### Step 1 — Make `scaffoldBackgroundColor` transparent globally
**File:** `lib/app.dart`

In `buildTheme()`, change:
```dart
scaffoldBackgroundColor: background,
```
to:
```dart
scaffoldBackgroundColor: Colors.transparent,
```

This makes every Scaffold transparent by default. Screens that need an opaque surface must opt in explicitly (none currently do).

**Risk:** Verify `background` (= `tokens.backgroundBottom`) is no longer needed in `ThemeData`. It should still be reachable via `OmniTheme.colorsForTheme(activeTheme).backgroundBottom` for direct use.

#### Step 2 — Promote gradient to app-level layer
**File:** `lib/app.dart`

In `MyApp.build()`, wrap the `MaterialApp` widget with `OmniGradientBackground`. Because `ListenableBuilder` rebuilds on theme changes, the gradient also rebuilds, which is correct.

```dart
return OmniGradientBackground(
  child: MaterialApp(
    title: 'Omnitrain',
    ...
  ),
);
```

This makes the gradient paint behind everything in the app window.

**Important:** `OmniGradientBackground` currently reads `OmniTheme.activeTheme` internally to resolve gradient colors. It will update correctly on theme switch because `ListenableBuilder` (wrapping both the gradient and the MaterialApp) will rebuild the whole tree.

#### Step 3 — Remove redundant `OmniGradientBackground` from every screen `body:`
For each of the 27 usage sites listed in the Screens Inventory:
- Replace `body: OmniGradientBackground(child: X)` with `body: X`.
- Do NOT change any other Scaffold properties (appBar, backgroundColor, extendBody, etc.) at this step — those are handled per-screen in Step 4.

Files to update:
- `lib/features/home/home_screen.dart`
- `lib/features/session/workout_session_list_view.dart` (7 usages)
- `lib/features/session/session_summary_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `lib/features/routine/routine_setup_screen.dart` (3 usages)
- `lib/features/onboarding/onboarding_screen.dart`
- `lib/features/splash/omni_splash_screen.dart`
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/stats/stats_screen.dart`
- `lib/features/exercise/exercise_editor_screen.dart` (2 usages)
- `lib/features/profile/profile_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/period/create_period_screen.dart`
- `lib/features/period/period_list_screen.dart`
- `lib/features/home/maintenance_placeholder_screen.dart`

#### Step 4 — Audit Scaffold flags per screen
After Step 3, the gradient shows through every transparent Scaffold. Walk each screen and confirm or fix:

| Screen | `backgroundColor` | `extendBodyBehindAppBar` | `extendBody` | Action needed |
|---|---|---|---|---|
| `home_screen.dart` | `Colors.transparent` ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `workout_session_list_view.dart` (all branches) | unset → now transparent ✓ | check each branch | check each branch | Audit each of the 7 Scaffold builds |
| `session_summary_screen.dart` | unset → now transparent ✓ | check | check | Audit |
| `my_routines_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `routine_setup_screen.dart` (all 3) | unset → now transparent ✓ | check | check | Audit each |
| `onboarding_screen.dart` | `Colors.transparent` ✓ | check | check | Audit |
| `omni_splash_screen.dart` | unset → now transparent ✓ | check | check | Audit |
| `calendar_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `day_session_list_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `stats_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `exercise_editor_screen.dart` (both) | unset → now transparent ✓ | `true` ✓ | present on one, missing on other | Align both branches |
| `profile_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `settings_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |
| `create_period_screen.dart` | unset → now transparent ✓ | `true` ✓ | `true` ✓ | No change |
| `period_list_screen.dart` | unset → now transparent ✓ | `true` ✓ | `true` ✓ | No change |
| `maintenance_placeholder_screen.dart` | unset → now transparent ✓ | `true` ✓ | **missing** | Add `extendBody: true` |

#### Step 5 — Verify modal and overlay surfaces
These surfaces introduce their own paint layer on top of the app gradient. Each must explicitly manage its background:

| Surface | File | Status | Verify |
|---|---|---|---|
| Routine picker sheet | `home_screen.dart` L461 | `backgroundColor: Colors.transparent` ✓ | Sheet widget paints its own card surface; no opaque system default |
| Session summary "save as routine" sheet | `session_summary_screen.dart` L197 | `backgroundColor: Colors.transparent`, `barrierColor: Colors.black54` ✓ | Sheet surface and barrier tint correct |
| Session summary exercise-picker sheet | `session_summary_screen.dart` L347 | `backgroundColor: Colors.transparent` ✓ | Same |
| Exercise picker dialog container rows | `exercise_picker_dialog.dart` L257, 603, 620 | `backgroundColor: Colors.transparent` ✓ | Chips render on gradient; confirm no unexpected bleed |
| Modality picker dialog | `modality_picker_dialog.dart` L47 | `backgroundColor: Colors.transparent` ✓ | Picker surface correct |
| Unsaved-changes / delete dialogs | `home_screen.dart`, `workout_session_edit_mode.dart`, `workout_session_finish.dart`, `session_summary_screen.dart` | No explicit backgroundColor — Material Dialog default | Dialogs should use `colorScheme.surface`; no white flash in dark themes. Confirm visually. |

#### Step 6 — Verify splash and onboarding
- **Splash (`omni_splash_screen.dart`):** Scaffold now transparent, gradient comes from app level. Temporarily re-enable `OmniSplashScreen` in `app.dart` (comment in line 88, comment out the direct home). Verify logo and text render correctly with no color seam. Re-disable after verification (or leave enabled if product wants it).
- **Onboarding (`onboarding_screen.dart`):** `backgroundColor: Colors.transparent` ✓ — already correct. Verify all three pages and transitions show gradient with no inset color leak.

#### Step 7 — Update widget tests
Files to audit:
- Any test that constructs a widget tree containing `OmniGradientBackground` as a `body:` wrapper and asserts on it directly.
- Key test files to check: `screen_widget_test.dart`, `widget_test.dart`, `state_test.dart`, `interaction_flow_test.dart`, `session_toolbar_rework_test.dart`, `unsaved_changes_dialog_test.dart`.
- For each failing test: if it was pumping a screen widget in isolation (without the full `MyApp` wrapper), it may now need a wrapping `OmniGradientBackground` or a plain `MaterialApp` with transparent scaffold to avoid a black background in tests.
- Update assertions: any test that found `OmniGradientBackground` as a descendant of a screen's `body:` will now find it as an ancestor wrapping the navigator. Update the finder accordingly.

### Implementation Steps
1. [ ] Change `scaffoldBackgroundColor` from `background` to `Colors.transparent` in `buildTheme()` (`app.dart`)
2. [ ] Wrap `MaterialApp` with `OmniGradientBackground` in `MyApp.build()` (`app.dart`)
3. [ ] Remove `OmniGradientBackground` wrapper from all 27 `body:` sites (16 files)
4. [ ] Add `extendBody: true` to every Scaffold that is missing it (home, routines, calendar, day-session, stats, profile, settings, maintenance-placeholder; audit all session branches)
5. [ ] Verify each `showModalBottomSheet` / `showDialog` still has correct `backgroundColor` handling (Step 5 table)
6. [ ] Temporarily re-enable splash screen, verify, re-disable
7. [ ] Verify onboarding on device
8. [ ] Run full widget test suite; fix any failing tests
9. [ ] Manual device walkthrough: every screen listed in Screens Inventory
10. [ ] Manual device walkthrough: theme switching from settings

## Progress
- [x] `scaffoldBackgroundColor` → `Colors.transparent` in `buildTheme()`
- [x] `OmniGradientBackground` applied app-wide via `MaterialApp.builder` in `MyApp.build()`
- [x] All 27 per-screen `OmniGradientBackground` body wrappers removed
- [x] `extendBody: true` added to all applicable Scaffolds
- [x] Modal / overlay backgroundColor audit complete
- [ ] Splash verified
- [ ] Onboarding verified
- [x] Widget tests updated and passing
- [ ] Manual walkthrough: all screens
- [ ] Manual walkthrough: theme switching

## Iteration 2

### Analysis — Post-implementation visual regression

**From:** User screenshot after Iteration 1 was deployed. App reports "still moving inside a hidden box and weird color changes on top."

**Root causes:**

**1. `appBarTheme` missing from `buildTheme()` → `scrolledUnderElevation` issue**
`buildTheme()` in `lib/app.dart` sets no `appBarTheme`. Material 3 defaults to `scrolledUnderElevation: 3.0`. When the `CustomScrollView` in `home_screen` scrolls content under the transparent AppBar, Flutter applies a surface tint to the AppBar's internal Material widget. This tint is computed as `Color.alphaBlend(surfaceTint.withOpacity(elevationOpacity(3.0)), Colors.transparent)`, which produces a visible semi-opaque colored layer. This is:
- The "weird color changes on top" (AppBar changes shade during scroll)
- The "moving inside a hidden box" (tinted AppBar area = opaque box at top when scrolling)

Individual AppBars already have `backgroundColor: Colors.transparent` and `elevation: 0`, but these do NOT suppress `scrolledUnderElevation`.

**2. Radial highlight and noise overlays are 0×0 (invisible)**
`OmniGradientBackground`'s inner `Stack` uses `StackFit.loose` (default). Children without an explicit size and no child widget receive loose constraints and collapse to 0×0:
- `Container(decoration: RadialGradient)` → 0×0 → NOT painted
- `CustomPaint(painter: noise, child: Container())` → 0×0 → NOT painted

The overlay children need `Positioned.fill()` or `StackFit.expand` to render at full stack size.

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### Fix 1 — Add `appBarTheme` to `buildTheme()` in `lib/app.dart`
Add the following inside the `ThemeData(...)` call in `buildTheme()`:
```dart
appBarTheme: const AppBarTheme(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  shadowColor: Colors.transparent,
),
```
This prevents Material 3 from applying surface tints to AppBars when content scrolls under them, making the gradient visible and stable behind all AppBars at all times.

#### Fix 2 — Wrap overlay Stack children with `Positioned.fill()` in `OmniGradientBackground`
In `lib/widgets/layout/omni_gradient_background.dart`, the radial gradient Container and the noise CustomPaint inside the Stack need to fill the available space. Change:
- `Container(decoration: RadialGradient)` → `Positioned.fill(child: Container(decoration: RadialGradient))`
- `CustomPaint(painter: noise, child: Container())` → `Positioned.fill(child: CustomPaint(painter: noise))`

This makes both overlays render at the full Stack size (= full window), restoring the intended visual effect.

### Implementation Steps
1. [x] In `lib/app.dart` `buildTheme()`: add `appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, shadowColor: Colors.transparent)`
2. [x] In `lib/widgets/layout/omni_gradient_background.dart`: wrap radial-gradient Container with `Positioned.fill()` in BOTH Stack branches (showRadialHighlight = true and = false)
3. [x] In `lib/widgets/layout/omni_gradient_background.dart`: wrap noise CustomPaint with `Positioned.fill()` in BOTH Stack branches; remove `child: Container()` from CustomPaint (size is now handled by Positioned)
4. [x] Run `flutter test` — all tests must pass (746/746 ✓)
5. [x] App launched on device for visual verification

### Acceptance Criteria
- [x] All existing widget tests pass (746/746)
- [ ] Scrolling the tile grid does not change the AppBar's color — **MANUAL VERIFICATION NEEDED**
- [ ] The radial highlight is visible at the top-center of the gradient — **MANUAL VERIFICATION NEEDED**
- [ ] The noise overlay renders at full window size (if `OmniTheme.enableBackgroundNoise` is true) — **MANUAL VERIFICATION NEEDED**

## Feedback
App successfully deployed to device. Tests: 746/746 passing. Visual verification in progress on device. User should observe:
- Gradient seamless from top to bottom (no brown box at status bar)
- Radial highlight glow visible at top-center
- When scrolling home tile grid: AppBar remains transparent with no color tinting
- When dragging maintenance sheet: no flat-color band above or below sheet

### Phase 2 Complete ✓
Iteration 2 implementation done. All code changes applied. All tests green. App on device for visual validation.
