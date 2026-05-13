# Feature: Hub Bottom Sheet — Single-Step Open

## Overview
Remove the mid (half-open) snap point from the Hub screen's always-visible bottom sheet so that a single upward gesture opens it fully and a single downward gesture collapses it to peek.

## Requirements
- Sheet has exactly two snap positions: collapsed peek (`_minSheetExtent`) and fully open (`maxSheetExtent`)
- Single upward flick from peek → fully open
- Single downward flick from fully open → peek
- Drag-and-release snaps to whichever of the two positions is closer
- Snap animation timing and curve unchanged
- No changes to peek height, fully-open height, sheet content, nav tiles, or visual styling

## Acceptance Criteria
- [ ] Sheet never stops at a half-open height under any drag or flick input
- [ ] A single upward swipe from peek opens the sheet fully
- [ ] A single downward swipe from fully open collapses to peek
- [ ] Handle tap opens the sheet fully (not to mid)
- [ ] All four navigation tiles remain accessible and functional in the fully-open state
- [ ] No visual regressions on the sheet or home screen
- [ ] `OmniSplashScreen` still renders its full top-to-bottom gradient (painted by `OmniGradientBackground`); the Scaffold behind it does not bleed through as a flat color
- [ ] `OnboardingScreen` (`backgroundColor: Colors.transparent` Scaffold) still renders its full gradient; no white/flat-color flash between onboarding pages
- [ ] All `showModalBottomSheet` calls that pass `backgroundColor: Colors.transparent` still display the sheet widget's own painted surface — no unintended opaque system-default overlay

## Scenarios
N/A — pure interaction change, no new screens or state.

## Iteration 1

### Analysis
All the work is in `lib/features/home/home_screen.dart`. Two surgical changes required:

1. **`snapSizes`** (line 606): Change from `[_minSheetExtent, _midSheetExtent, maxSheetExtent]` to `[_minSheetExtent, maxSheetExtent]`.  
   This removes the intermediate snap point that causes the two-step behavior.

2. **Handle tap `onTap`** (line 704): Currently calls `_snapSheet(_midSheetExtent)`. The tap is the programmatic equivalent of an upward gesture from peek, so it should snap to `maxSheetExtent`.  
   `maxSheetExtent` is a local variable computed in the build method. The cleanest approach is to cache it as a field `_maxSheetExtent` that is set during build, then reference it in the handle tap and in `_snapSheet`. Alternatively, compute it inline from `MediaQuery` inside `_snapSheet`.

   **Recommended approach**: Add a `double _maxSheetExtent = 0.9;` instance field (initialized to the clamp max as a safe default) and update it at the top of the `_buildSheet` / `_buildHub` method before it's used in `snapSizes` and the handle tap. This avoids any MediaQuery call duplication.

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

**File:** `lib/features/home/home_screen.dart`

#### Step 1 — Add `_maxSheetExtent` instance field
- Add `double _maxSheetExtent = 0.9;` to `_HomeScreenState` alongside `_minSheetExtent` and `_midSheetExtent`.

#### Step 2 — Remove `_midSheetExtent` constant (optional cleanup)
- `_midSheetExtent` is no longer used after these changes. Remove the constant to avoid dead code.

#### Step 3 — Assign `_maxSheetExtent` before the sheet widget builds
- In the method that computes `maxSheetExtent` (the local variable), assign it to `_maxSheetExtent` at the same time:
  ```dart
  _maxSheetExtent = ((mq.size.height - mq.padding.top - kToolbarHeight) / mq.size.height)
      .clamp(0.5, 0.9);
  ```
- Then replace the local `maxSheetExtent` references with `_maxSheetExtent`.

#### Step 4 — Remove mid snap point from `snapSizes`
- Change: `snapSizes: [_minSheetExtent, _midSheetExtent, maxSheetExtent]`
- To: `snapSizes: [_minSheetExtent, _maxSheetExtent]`

#### Step 5 — Fix handle tap target
- Change: `onTap: () => _snapSheet(_midSheetExtent)`
- To: `onTap: () => _snapSheet(_maxSheetExtent)`

### Implementation Steps
1. [ ] Add `double _maxSheetExtent = 0.9;` field to `_HomeScreenState`
2. [ ] Remove unused `_midSheetExtent` constant
3. [ ] Assign `_maxSheetExtent` from the computed value before the sheet is returned
4. [ ] Update `snapSizes` to `[_minSheetExtent, _maxSheetExtent]`
5. [ ] Update handle `onTap` to `_snapSheet(_maxSheetExtent)`
6. [ ] Hot-reload and verify single-gesture open and close
7. [ ] Verify no half-open stop under fast flick and slow drag-release

### Surface Verification Steps (new)

These checks guard against regressions on gradient-painted surfaces and transparent overlay contracts.

#### Splash screen (`lib/features/splash/omni_splash_screen.dart`)
- `OmniSplashScreen` is currently disabled in `app.dart` (line 87–88) but should be re-enabled for verification.
- The Scaffold has **no explicit `backgroundColor`**, so it inherits `scaffoldBackgroundColor` from `buildTheme()` (set to `tokens.backgroundBottom` — the darker gradient stop).
- `OmniGradientBackground` in `body` paints the full top-to-bottom gradient **on top of** that scaffold color; the two must remain visually consistent.
- **Risk**: if `scaffoldBackgroundColor` is changed to a contrasting color (e.g., pure black or white), a 1-frame flash or safe-area bleed could be visible before the gradient paints.
- **Verify**: Temporarily re-enable `OmniSplashScreen` in `app.dart`, launch on device, and confirm no visible scaffold color shows through at top/bottom safe-area insets.

#### Onboarding screen (`lib/features/onboarding/onboarding_screen.dart`)
- Uses `Scaffold(backgroundColor: Colors.transparent)` — relies on the **parent Material widget** (from `MaterialApp`) to supply the background.
- `OmniGradientBackground` in `body` paints the gradient; `Colors.transparent` scaffold lets any ancestor surface show through the safe-area gutters.
- **Risk**: if the `MaterialApp` theme's `scaffoldBackgroundColor` changes to a non-matching color, the transparent edges of the scaffold will reveal it instead of the gradient.
- **Verify**: Run onboarding flow on device (trigger via `showOnboarding = true` in `main.dart`), swipe through all three pages, and confirm full gradient coverage with no color bleed in safe-area insets or between page transitions.

#### Modal bottom sheets and dialogs

| Call site | File | Transparent? | Verify |
|---|---|---|---|
| Routine picker sheet | `home_screen.dart` L461 | `backgroundColor: Colors.transparent` | Sheet widget paints its own surface; no white/grey system card behind it |
| Session summary "save as routine" sheet | `session_summary_screen.dart` L197 | `backgroundColor: Colors.transparent`, `barrierColor: Colors.black54` | Sheet surface correct; barrier tint correct |
| Session summary routine exercise picker sheet | `session_summary_screen.dart` L347 | `backgroundColor: Colors.transparent` | Same as above |
| Unsaved-changes and delete dialogs | `home_screen.dart` L290, L387; `workout_session_edit_mode.dart` L30, L237, L339; `workout_session_finish.dart` L10, L66; `session_summary_screen.dart` L212, L258, L275 | No `backgroundColor` (Material Dialog default) | Dialog surface uses theme `colorScheme.surface`; confirm no white flash in dark themes |
| Exercise picker `showDialog` | `exercise_picker_dialog.dart` | `backgroundColor: Colors.transparent` rows L257, L603, L620 | Transparent container rows; confirm chips render correctly |
| Modality picker | `modality_picker_dialog.dart` L47 | `backgroundColor: Colors.transparent` | Picker surface paints correctly |

- **Verify each call site** by triggering the flow on device and confirming the modal surface matches the design intent (themed surface, no unexpected opaque white/grey backdrop).

## Progress
- [x] Add `_maxSheetExtent` instance field
- [x] Remove `_midSheetExtent` constant
- [x] Assign `_maxSheetExtent` in build/sheet method
- [x] Update `snapSizes` to two snap points
- [x] Update handle tap to fully-open target
- [ ] Smoke-test snap behavior on device/simulator
- [ ] Verify splash screen gradient renders without scaffold color bleed
- [ ] Verify onboarding gradient renders through all three pages with no color leak at safe-area insets
- [ ] Verify all `showModalBottomSheet` call sites retain correct transparent surface treatment
- [ ] Verify dialog call sites use themed surface color (no white flash in dark themes)

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
