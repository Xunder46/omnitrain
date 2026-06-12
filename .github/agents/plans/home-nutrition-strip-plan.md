# Feature: Home-screen nutrition strip (placeholder)

## Overview
Add a full-width strip button along the bottom of the home screen, in the space freed by removing the Hub sheet's peek handle. It is a zero-state placeholder for the nutrition entry point — text is hard-coded to "0 calories today" and tapping opens a placeholder destination. Live calorie totals and the real day-log arrive in Phase 3.

The strip must sit above the device's bottom system-gesture/safe area, must not be a FAB, and must not displace or compete with the training tiles.

This is a UI-only change. No repository, schema, or state methods are added.

## Requirements
- A new full-width strip sits along the bottom of the home screen, above the safe area.
- Strip text: "0 calories today".
- Tapping the strip opens a placeholder destination (use the existing `MaintenancePlaceholderScreen` with title "Nutrition" and a short description).
- Strip must not be a `FloatingActionButton`.
- Strip must not displace or compete with the six training tiles.
- Strip must sit above the home-indicator / system gesture safe area (`SafeArea(top: false)` or equivalent MediaQuery padding).
- Style matches the app's dark theme (use `OmniTheme.colorsForTheme(activeTheme)` tokens — surface fill, surface border, text tokens). No hardcoded colors.
- No new repository methods, no schema changes, no new state.

## Acceptance Criteria
- [ ] A full-width strip sits along the bottom of the home screen, above the safe area, reading "0 calories today".
- [ ] Tapping the strip opens the placeholder nutrition destination.
- [ ] The strip does not trigger or block the home-indicator gesture (it lives above the safe-area inset and is not a FAB).
- [ ] No training tile was added, removed, or resized; no FAB was added.
- [ ] The strip's colors come from `OmniTheme` tokens, not hardcoded values.

## Scenarios

### S-001: Cold-start home screen shows nutrition strip
- Trigger: User opens the app to the home screen (no active session).
- Precondition: Home screen mounted, no Hub sheet interaction.
- Flow:
  1. App reaches the home screen.
  2. The home body renders the existing TRAIN heading + 2×2 + 2×1 training tile grid.
  3. A new full-width strip is rendered along the bottom of the Scaffold body, above the device's bottom safe-area inset.
  4. The strip displays "0 calories today".
- Expected outcome: The strip is visible at the bottom of the home screen. The six training tiles are still visible and in their existing positions. The Hub sheet is at rest (off-screen). Tapping inside the strip's tappable area does not open the Hub.
- Edge case of: none

### S-002: Tapping the strip opens the placeholder nutrition destination
- Trigger: User taps the nutrition strip on the home screen.
- Precondition: Home screen mounted, strip visible.
- Flow:
  1. User taps anywhere on the strip.
  2. The strip's `onTap` callback runs `OmniNavigator.push` to a placeholder screen.
  3. The placeholder screen renders with the existing `MaintenancePlaceholderScreen` (title "Nutrition", description "Coming soon — daily nutrition tracking arrives in a future update.").
- Expected outcome: The user sees a "Coming Soon" placeholder screen titled "Nutrition" with the placeholder copy. Back button (or system back) returns to the home screen with the strip still visible.
- Edge case of: none

### S-003: Strip lives above the home-indicator safe area
- Trigger: User views the home screen on a device with a bottom home-indicator (e.g., iPhone X+, modern Android).
- Precondition: Home screen mounted, device has a non-zero `MediaQuery.padding.bottom`.
- Flow:
  1. The strip renders inside a `SafeArea(top: false)` wrapper (or uses `MediaQuery.viewPadding.bottom`) so its bottom edge is above the system gesture inset.
  2. The user performs a home-indicator swipe up from the very bottom of the screen.
- Expected outcome: The system recognizes the home-indicator swipe and the app does not intercept it. Tapping the strip body opens the placeholder; swiping from the system gesture area triggers the system home gesture, not the strip's tap.
- Edge case of: S-001

### S-004: No FAB or training-tile displacement
- Trigger: User views the home screen.
- Precondition: Home screen mounted.
- Flow:
  1. The home body still contains the six training tiles (Cardio, Resistance, Sports, Isometric, Free Training, My Routines) in the existing 2×2 + 2×1 layout.
  2. No `FloatingActionButton` exists anywhere on the home screen.
- Expected outcome: Tile count, layout, and behavior are unchanged. The strip is a separate element, not inside the training grid.
- Edge case of: S-001

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### 1. Create the strip widget
Add `lib/features/home/widgets/nutrition_strip_button.dart` (new widget, scoped to the home feature folder to keep it close to its only call site).

API:
- `class NutritionStripButton extends StatelessWidget`
- `const NutritionStripButton({super.key, required this.onTap, this.label = '0 calories today'})`
- `final VoidCallback onTap;`
- `final String label;`

Implementation:
- `Material` → `InkWell` for splash + tap.
- Outer `SafeArea(top: false)` so it clears the bottom system-gesture inset without affecting the top.
- Container with `width: double.infinity`, padding `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`.
- Background: `themeColors.surface`.
- Border: top-only `BorderSide(color: themeColors.surfaceBorder, width: OmniTheme.surfaceBorderWidth)` to give a subtle separator from the home body above.
- Corner radius: small (e.g. `BorderRadius.circular(8)`) — does not need to match the larger 20px tile radius; the strip is a thin footer element.
- Subtle shadow: `[BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: Offset(0, -2))]` to lift the strip off the body.
- Text: `Text(label, style: ...copyWith(color: themeColors.textDominant, fontWeight: FontWeight.w600, letterSpacing: 0.5))`.
- Optional leading icon: `Icons.local_fire_outline` (or similar neutral placeholder) tinted with `themeColors.primary` at 0.7 opacity, for a hint of the eventual calorie metric.

#### 2. Placeholder destination
Reuse the existing `lib/features/home/maintenance_placeholder_screen.dart` (`MaintenancePlaceholderScreen`). No new screen file is required.

#### 3. Wire the strip into `HomeScreen.build`
File: `lib/features/home/home_screen.dart`

- In the `Scaffold.body` `Stack`, the top-level child currently is `SafeArea(... Column(...))` and the second child is `_buildMaintenanceSheet(context)`.
- Wrap the existing `SafeArea` body in a `Column` (or use `Stack` positioning) so the strip sits *below* the existing body and above the bottom edge of the Stack. Concretely, the cleanest approach:
  - Replace the outer `Stack` body with a `Column` whose children are:
    1. `Expanded(child: SafeArea(bottom: false, child: <existing Column body>))` — the body fills the available space above the strip. Set `bottom: false` on the body `SafeArea` so the strip below owns the safe-area inset.
    2. `NutritionStripButton(onTap: () => _openNutritionPlaceholder())` — full-width, sits below the body.
  - Add a private method `_openNutritionPlaceholder()`:
    ```dart
    void _openNutritionPlaceholder() {
      OmniNavigator.push(
        context,
        (_) => const MaintenancePlaceholderScreen(
          title: 'Nutrition',
          description:
              'Coming soon — daily nutrition tracking arrives in a future update.',
        ),
      );
    }
    ```
  - Update the existing `body:` import to include `maintenance_placeholder_screen.dart` (already imported? — verify in the file; if not, add it).

Notes:
- The Hub sheet (`_buildMaintenanceSheet`) is *not* part of this Column. It is still rendered in the Scaffold as a `bottomSheet` parameter (or kept in the Stack). To avoid disturbing the existing sheet contract, the **safest minimal change** is: keep the existing `Stack` body, change its first child to the `Column(body, strip)` and leave the second child (the sheet) untouched. The strip lives inside the body's Column, not the sheet.
- To keep the strip above the safe area and the body's existing padding behavior intact, structure the body's child like this:
  ```dart
  Column(
    children: [
      Expanded(
        child: SafeArea(
          bottom: false, // body no longer pads the bottom
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 5.0, 16.0, 0.0),
            child: <existing Column content (TRAIN heading + grid)>,
          ),
        ),
      ),
      NutritionStripButton(onTap: _openNutritionPlaceholder),
    ],
  )
  ```
- The `bottom: false` on the body's SafeArea is required so the body does not double-pad with the strip's own SafeArea.

#### 4. Keep the existing `_buildMaintenanceSheet` untouched.
- The Hub sheet is a `DraggableScrollableSheet` rendered in the `Stack`. Its `minChildSize: 0.0` keeps it off-screen at rest, so the strip is the only visible bottom element until the user opens the Hub.

#### 5. Tests
Add `test/home_nutrition_strip_test.dart` with two groups:

**Group A — `NutritionStripButton`**
- `'renders the placeholder label'` — pump widget, expect `find.text('0 calories today')` to find one widget.
- `'invokes onTap when tapped'` — pump with a flag, tap, expect flag to be set.

**Group B — `HomeScreen` integration**
- `'shows the nutrition strip and routes on tap'` — build a `HomeScreen` with the standard fake dependencies (mirror the helper in `test/home_logo_hub_open_test.dart`), pump, expect `find.text('0 calories today')` to find one widget. Then `tester.tap(find.text('0 calories today'))`, pump, and expect `MaintenancePlaceholderScreen` to be in the tree (or `find.text('Coming Soon')` to be findable).
- `'no nutrition heading or text block is rendered above the strip'` — guard test. Build the home screen, assert the body **does not** contain any of: `'Nutrition'`, `'0 calories today'` (in the body, outside the strip), `'calories'`, or any free-standing `Text` widget reading those strings above the strip. Use `find.descendant(of: find.byType(NutritionStripButton), matching: find.text('0 calories today'))` for the strip's text, and assert the same text is not present elsewhere. This guard prevents the earlier premature nutrition heading/text block from returning.

### Implementation Steps
1. [ ] Create `lib/features/home/widgets/nutrition_strip_button.dart` with `NutritionStripButton`.
2. [ ] Add `_openNutritionPlaceholder` to `_HomeScreenState`.
3. [ ] Restructure the `Stack`'s first child to a `Column` with `Expanded(body)` + `NutritionStripButton`.
4. [ ] Ensure `MaintenancePlaceholderScreen` is imported in `home_screen.dart`.
5. [ ] Add `test/home_nutrition_strip_test.dart` covering the two groups above.
6. [ ] Run `flutter test test/home_nutrition_strip_test.dart test/home_logo_hub_open_test.dart test/interaction_flow_test.dart test/screen_widget_test.dart` to confirm green.
7. [ ] Smoke test on web with `flutter run -d chrome` and confirm the strip is visible above the home indicator, tap opens the placeholder, and the six training tiles are unchanged.

## Progress
- [x] Create `NutritionStripButton` widget
- [x] Wire strip into `HomeScreen.build`
- [x] Add `_openNutritionPlaceholder`
- [x] Add `test/home_nutrition_strip_test.dart`
- [x] Run targeted tests and web smoke check

## Feedback
- Phase 0 red gate: tests failed to compile because `NutritionStripButton` did not exist (correct kind of red — missing implementation, not test-config error).
- Phase 2 green: all 6 new tests pass; full home-related test set (`home_nutrition_strip_test`, `home_logo_hub_open_test`, `home_logo_press_affordance_test`) passes 15/15.
- Pre-existing failures in the working tree (26 occurrences of `SettingsState(repo)` 1-arg call sites in `test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/exercise_notes_sheet_test.dart`, `test/crown_control_tap_to_edit_test.dart`) are unrelated to this feature — they were broken on the working tree before this iteration by an in-progress `SettingsState` constructor change. Out of scope for the home-screen nutrition strip.
- Web smoke: `flutter build web` succeeded; the built bundle serves and contains the app entry. The 6 `withOpacity` deprecation warnings in `home_screen.dart` are pre-existing (not in code this iteration added).
- Plan said `Icons.local_fire_outline` — replaced with `Icons.local_dining_outlined` because `local_fire_outline` is not a member of the project's Material icon set under the current Flutter version.

---

## Iteration 4.1 — Strip Redesign per D-8

### Phase 4.1 — Strip Redesign per D-8 (@developer) — Complete

The Phase 4 (D-5) two-row layout exhibited three presentational
defects (SafeArea nesting, upward drop shadow, track
shrink-wrap → "floating pills"). D-8 supersedes the layout
and structurally removes all three defect classes.

### Frontend Changes
- [x] **1.** Rebuild `NutritionStripBar` per D-8: full-height bar; surface = track; fill with chevron leading edge (`CustomPaint`); straight interior segment boundaries; overlay calorie label with shadowed-text contrast treatment; hairline top border, no shadow; decoration OUTSIDE `SafeArea(top:false)`, content inside.
- [x] **2.** `HomeScreen`: strip claims fixed content height (`NutritionStripBarMetrics.contentHeight`, default 64 px) + bottom inset extending to screen edge; remove the `isCurrent` route gate (S-057); keep gap = 2 × `standardGridSpacing`.
- [x] **3.** Delete `nutrition_strip_button.dart` (carried over from Phase 4 item 5) and the `dispose()` no-op `whenComplete` (Phase 4's microtask-deferred load obviates the drain pattern).
- [x] **4.** Tests: S-050b, S-056, S-057 + re-point S-051..S-054 at the new geometry. S-050b's fixture is the 45 / 11 / 44 split as written; S-053 is preserved with the in-segment label as a `Text` widget so widget tests can probe it via `find.textContaining('P 25%')`. All 17 strip tests pass.
- [x] **5.** Update docs: `widget_catalog.md` (`NutritionStripBar` entry — D-8 geometry, design tokens, chevron behaviour, removed D-5 two-row description) and `navigation_and_screens.md` (`HomeScreen` row — D-8 layout summary, removed isCurrent gate, removed placeholder reference).

### Predicted Files
- [x] `lib/features/home/widgets/nutrition_strip_bar.dart` — rewritten per D-8.
- [x] `lib/features/home/home_screen.dart` — isCurrent gate removed, dispose no-op removed, `NutritionStripBar` geometry comments updated.
- [x] `lib/features/home/widgets/nutrition_strip_button.dart` — deleted (Phase 4 placeholder removed).
- [x] `test/home_nutrition_strip_test.dart` — rewritten with S-050b, S-056, S-057 + re-pointed S-051..S-054. 17 tests pass.
- [x] `.github/agents/docs/widget_catalog.md` — `NutritionStripBar` entry updated.
- [x] `.github/agents/docs/navigation_and_screens.md` — `HomeScreen` row updated.

### Phase 4.1 Complete ✓
Implementation done. All Phase 4.1 strip tests green. Ready for Code Reviewer.
