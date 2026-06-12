# Feature: Home-screen logo press affordance

## Overview
The home-screen logo opens the Hub but reads as static artwork rather than a control. Add a behavioral affordance — a visible press reaction (subtle scale + brightness lift) on finger-down that settles back on release, and a light haptic on tap. No borders, outlines, or drop-shadows. The resting look stays identical.

## Requirements
- On finger-down the logo visibly reacts (subtle press/scale + brightness lift).
- On finger-up / cancel the logo settles back to its resting state.
- A light haptic fires on tap (web is a no-op, matching existing pattern in `workout_session_screen.dart`).
- No border, outline, or drop-shadow is added to the logo.
- The existing `Image.asset('assets/icon/omnitrain_logo.png', height: 40, width: 40)` artwork is reused as-is.
- Tapping still opens the Hub (existing `_openHubSheet` flow is preserved).
- Nothing else on the home screen or Hub changes.

## Acceptance Criteria
- [ ] On finger-down the logo shows a visible press reaction and returns to rest on release.
- [ ] A light haptic fires on tap (no-op on web).
- [ ] No border, outline, or drop-shadow is added to the logo (verified by inspection of the widget — no `Border`, no `boxShadow`, no `Outline` on the logo subtree).
- [ ] Tapping the logo still opens the Hub.
- [ ] New unit test asserts the logo exposes a press interaction (press state toggles on down/up).
- [ ] Existing `home_logo_hub_open_test.dart` still passes (tap-opens-Hub).

## Scenarios

### S-001: Press-and-release the logo on home screen
- Trigger: User puts finger on the logo in the home AppBar, then releases.
- Precondition: Home screen visible, Hub sheet closed.
- Flow:
  1. User presses the logo.
  2. Logo visually scales to `OmniTheme.pressedScale` (0.96) and brightens (ColorFilter overlay at low opacity) within `OmniTheme.animationDuration` (180ms).
  3. User releases the finger.
  4. Logo animates back to scale 1.0, no brightness overlay.
  5. `onTap` callback fires, calling `_openHubSheet()` → Hub sheet opens.
  6. `HapticFeedback.lightImpact()` fires (no-op on web).
- Expected outcome: Visible press reaction matches existing tile behavior, Hub opens, no chrome added.
- Edge case of: none

### S-002: Press is cancelled (drag away / interrupt)
- Trigger: User puts finger on the logo, then drags off before releasing.
- Precondition: Home screen visible.
- Flow:
  1. Press detected → logo enters pressed visual state.
  2. `onTapCancel` fires (drag-off or system interrupt).
  3. Logo animates back to rest. `onTap` does NOT fire, so no Hub open, no haptic.
- Expected outcome: Logo returns to rest cleanly, Hub does not open.
- Edge case of: S-001

### S-003: Tap logo when Hub is already open
- Trigger: User taps the logo while the Hub sheet is at max extent.
- Precondition: Hub sheet open.
- Flow: Same as S-001 but `_openHubSheet()` snaps to max (no-op visually).
- Expected outcome: No crash, no adverse effects.
- Edge case of: S-001

## Implementation Plan

### Phase 1: Logic/UI (@developer)
1. [x] Create `lib/widgets/common/home_logo_button.dart` — a small `StatefulWidget` that wraps the logo asset and exposes:
   - `final VoidCallback onTap;`
   - `final double size;` (defaults to 40)
   - `bool isPressed;` (public getter, `@visibleForTesting` for the test)
   - `onTapDown` / `onTapUp` / `onTapCancel` handlers that flip `isPressed` and drive an `AnimatedScale` to `OmniTheme.pressedScale`.
   - A `ColorFiltered` brightness lift on press: white at low opacity (e.g. `Color.fromRGBO(255, 255, 255, 0.10)`) using `BlendMode.modulate` (or `BlendMode.lighten`/`plus` — pick the one that reads as a clean lift against the existing logo).
   - On `onTap`, fire `HapticFeedback.lightImpact()` guarded by `if (!kIsWeb)` to match the existing pattern in `lib/features/session/workout_session_screen.dart:725` and `lib/core/utils/timer_alert_service.dart`.
   - No `Border`, no `boxShadow`, no `Outline`, no `Ink`/`InkWell` (which would paint a splash). Use plain `GestureDetector`.
   - Respect `MediaQuery.of(context).disableAnimations` by snapping the visual state without animation (consistent with the existing `InteractiveLogo` pattern in `lib/widgets/common/interactive_logo.dart`).
2. [x] In `lib/features/home/home_screen.dart`, replace the existing `GestureDetector(onTap: _openHubSheet, child: Image.asset(...))` in the AppBar `title:` with the new `HomeLogoButton(onTap: _openHubSheet)`.
3. [x] Add the `home_logo_button.dart` import to `home_screen.dart` and add the `flutter/services.dart` import if not already present.
4. [x] Add a new test `test/home_logo_press_affordance_test.dart`:
   - Build a minimal `MaterialApp(home: Scaffold(appBar: AppBar(title: HomeLogoButton(onTap: () {}))))`.
   - Pump and settle.
   - Find the `HomeLogoButton` state via `tester.state<HomeLogoButtonState>(find.byType(HomeLogoButton))` (expose the state class publicly, e.g. `class HomeLogoButtonState extends State<HomeLogoButton>`).
   - Assert `state.isPressed == false` initially.
   - Use `tester.startGesture(...)` (or `tester.tapDown` if available) → pump one frame → assert `state.isPressed == true`.
   - Release → pump and settle → assert `state.isPressed == false`.
5. [x] Verify `test/home_logo_hub_open_test.dart` still passes (no behavior changes to the tap→Hub path).
6. [x] Run `flutter test` to confirm no regressions.

### Acceptance Criteria
- [ ] `HomeLogoButton` widget created at `lib/widgets/common/home_logo_button.dart`
- [ ] `HomeLogoButton` exposes `isPressed` for testing
- [ ] `HomeLogoButton` uses `OmniTheme.pressedScale`, `OmniTheme.animationDuration`, `OmniTheme.animationCurve`
- [ ] `HomeLogoButton` fires `HapticFeedback.lightImpact()` on tap, guarded by `!kIsWeb`
- [ ] `HomeLogoButton` adds no border, outline, or drop-shadow to the logo
- [ ] `home_screen.dart` AppBar uses `HomeLogoButton` instead of the existing `GestureDetector + Image.asset`
- [ ] `test/home_logo_press_affordance_test.dart` asserts press state toggles on down/up
- [ ] `test/home_logo_hub_open_test.dart` still passes

### Files Affected
- `lib/widgets/common/home_logo_button.dart` (new)
- `lib/features/home/home_screen.dart` (replace inline `GestureDetector + Image.asset` with `HomeLogoButton`)
- `test/home_logo_press_affordance_test.dart` (new)

### Notes
- The existing `lib/widgets/common/interactive_logo.dart` is unused and is NOT a drop-in fit: it hardcodes 48x48, adds a "Hub" text label overlay gated by `SettingsState.showHubLabel`, and lacks haptic feedback. Do not reuse it; create a focused `HomeLogoButton` per the acceptance criteria.
- Use `ColorFilter.mode` with a low-alpha white to lift brightness — this is the cleanest way to add a "pressed" tint without any chrome (no border, no shadow). Verify visually on the actual logo asset.
- Keep the `Image.asset('assets/icon/omnitrain_logo.png', height: 40, width: 40)` size unchanged so the resting look is pixel-identical.
- Follow the dual-environment contract: web + native both work; haptic is a no-op on web (matches existing pattern in `workout_session_screen.dart:725` and `timer_alert_service.dart:67,76`).
- Reference docs: `docs/design_system.md` for animation tokens; `docs/app_philosophy.md` for "fast logging, clear status, restrained motion, and functional controls."

### Phase 1 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.
