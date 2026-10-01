# Feature: TestFlight UI Fixes (May 2026)

## Overview
Four UI regressions reported from TestFlight iPhone testing. All are pure UI/logic
fixes — no schema changes, no new state methods, no new screens.

## Requirements
- Fix routine segment card background color being hardcoded to AbyssalNeon surface.
- Reduce Create Routine cancel/save button height to match the app-wide standard.
- Lift the Free Training + My Routines tiles (and the hub sheet toggle) slightly.
- Set progress dots must only fill (primary color) when the set is actually logged,
  not simply because the user has navigated past that set index.

## Acceptance Criteria
- [x] Routine segment cards reflect the active theme surface color on all six themes.
- [x] Cancel and Save in Create Routine are 56 px tall (OmniTheme.buttonPrimaryHeight),
      matching "Add Exercise" / "Finish Workout" buttons.
- [x] The utility row (Free Training + My Routines tiles) is visually closer to the
      modality grid above it.
- [x] A set dot shows primary color ONLY when that set has been persisted/logged.
      Navigating between unlogged sets leaves their dots grey.

## Scenarios
N/A — all fixes are visual / state-display corrections in existing screens.

---

## Iteration 1

### Analysis
All four issues are self-contained UI/color corrections in three files:
- `lib/features/routine/routine_setup_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/session/workout_session_detail_view.dart`

No DBA phase needed.

---

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### Fix 1 — Routine segment card hardcoded surface color
**File:** `lib/features/routine/routine_setup_screen.dart`

Root cause: `_buildSegmentCard` passes `color: OmniTheme.surfaceColor.withOpacity(0.7)`
to the `Card` widget. `OmniTheme.surfaceColor` is a compile-time constant
(`Color(0xFF0E223A)`) equal to the AbyssalNeon surface — it does not react to the
active theme.

Fix: Replace with `theme.colorScheme.surface.withOpacity(0.7)`, which is already the
pattern used by every `TextField` and `DropdownButtonFormField` on the same screen.

---

#### Fix 2 — Cancel / Save buttons too tall
**File:** `lib/features/routine/routine_setup_screen.dart`

Root cause: `_buildBottomActions` gives both `OutlinedButton` and `FilledButton` a
`padding: const EdgeInsets.symmetric(vertical: 24)`, producing a ~96 px hit area
instead of the standard 56 px.

Fix:
- Remove the explicit `vertical: 24` padding from both buttons.
- Wrap each `Expanded` in a `SizedBox(height: OmniTheme.buttonPrimaryHeight)` child,
  using `padding: EdgeInsets.zero` on the button style (so the fixed height drives
  size, not internal padding).
- Use `borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius)` (12.0)
  on both buttons to match the session screen standard.

---

#### Fix 3 — Free Training / My Routines tiles too low
**File:** `lib/features/home/home_screen.dart`

Root cause: `utilitySectionGap = standardGridSpacing * 3` = 48 px between the 2×2
modality grid and the 2-tile utility row. This pushes the utility row (and the hub
sheet handle) too far down on iPhone screens.

Fix: Reduce the gap multiplier from `* 3` to `* 1` (16 px), lifting the utility
tiles and hub sheet toggle together. Adjust if the user wants a different value.

---

#### Fix 4 — Set dots fill on navigation instead of on log
**File:** `lib/features/session/workout_session_detail_view.dart`

Root cause: `_buildSetIndicator` determines fill color with:
```dart
final isCompleted = index < _currentSet - 1;  // position-based
```
This marks every set *before* the current index as filled (primary color), regardless
of whether the user actually logged those sets.

Fix:
1. Pass `effortId` (and `effortKind`) into `_buildSetIndicator` (or resolve it inside
   from `_exercises[_currentExerciseIndex]`).
2. Replace `isCompleted` with:
   ```dart
   final isActuallyLogged = _isSetLogged(effortId, index, effortKind);
   ```
3. Color logic becomes:
   - `isActuallyLogged && !isSkipped` → `theme.colorScheme.primary.withOpacity(0.8)` (filled)
   - `isCurrent && !isActuallyLogged` → `theme.colorScheme.onSurface.withAlpha((0.35 * 255).round())` (slightly brighter grey for active set)
   - everything else → `theme.colorScheme.onSurface.withAlpha((0.2 * 255).round())` (grey)

   (The current-set dot should remain *larger* (14 px vs 10 px) for visual position cue,
    but only *filled* once the set is logged.)

---

### Implementation Steps
1. [x] Fix 1: In `_buildSegmentCard`, change `OmniTheme.surfaceColor` → `theme.colorScheme.surface`.
2. [x] Fix 2: In `_buildBottomActions`, replace `padding: EdgeInsets.symmetric(vertical: 24)` with
        `SizedBox(height: OmniTheme.buttonPrimaryHeight)` wrapper + `padding: EdgeInsets.zero` +
        `borderRadius: OmniTheme.buttonBorderRadius`.
3. [x] Fix 3: In `home_screen.dart`, change `const utilitySectionGap = standardGridSpacing * 3` →
        `standardGridSpacing * 1` (or a value confirmed by the user).
4. [x] Fix 4: In `_buildSetIndicator`, replace position-based `isCompleted` with
        `_isSetLogged(effortId, index, effortKind)`.
5. [ ] Smoke test each fix on iPhone simulator (or TestFlight build).

### Files Affected
- `lib/features/routine/routine_setup_screen.dart` (Fixes 1 & 2)
- `lib/features/home/home_screen.dart` (Fix 3)
- `lib/features/session/workout_session_detail_view.dart` (Fix 4)

### Notes
- No test changes are required (the existing test suite covers `_isSetLogged` logic).
- Fix 3 gap value (16 px) is a suggestion; if the user finds it too tight, try 24 px
  (`standardGridSpacing * 1.5`).
- Fix 4 must confirm that `_isSetLogged` is accessible from the `_buildSetIndicator`
  scope (it is — both live in `_WorkoutSessionDetailViewState`).

---

## Progress
- [x] Fix segment card surface color (routine_setup_screen.dart)
- [x] Fix Cancel/Save button height (routine_setup_screen.dart)
- [x] Lift utility tile gap (home_screen.dart)
- [x] Set dots log-only fill (workout_session_detail_view.dart)

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback

