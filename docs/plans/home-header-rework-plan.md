# Feature: Rework home-screen header for Hub access

## Overview
This feature will change how the Hub sheet is accessed from the home screen. The brand logo in the header will become the new trigger for opening the Hub sheet, and the current peeking handle at the bottom of the screen will be removed. The logo will have a teaching label ("Hub") for the first two uses to make the new functionality discoverable.

## Requirements
- The brand logo in the home-screen header opens the Hub sheet.
- The Hub sheet's peeking handle is removed.
- The logo has a press-down visual effect.
- A "Hub" text label appears inside the logo for the first two times the user opens the Hub.
- The open count is stored locally and persists across app sessions.
- The label and press-down effect should have reduced/no animation when the user has motion reduction enabled.
- The Hub sheet's contents and drag-to-close behavior remain unchanged.

## Acceptance Criteria
- [ ] At rest on the home screen, the Hub sheet is not visible and shows no peeking handle.
- [ ] Tapping the logo opens the Hub sheet to its existing expanded height.
- [ ] The Hub sheet closes by dragging down, exactly as before.
- [ ] On finger-down, the logo shows a visible press reaction and returns to its resting state on release.
- [ ] For the first two Hub opens, the word "Hub" is displayed inside the logo's hollow center in a light, legible color.
- [ ] On the third and later opens (and later app sessions), the "Hub" label does not appear.
- [ ] With system motion reduction enabled, the label appears and retires with no animation, and tapping still opens the sheet.
- [ ] The logo renders sharply at button size on high-density screens.
- [ ] The Hub's contents (Profile, Stats, Settings) are unchanged.

## Scenarios
[Populated by Conductor during planning]

## Iteration 2 — Hide Hub sheet at rest, keep handle inside the sheet

### Overview
The Hub sheet's peek handle is part of the sheet (not the home screen). When the sheet is hidden at rest, no handle is visible. When the user opens the sheet via the logo, the handle is visible at the top of the open sheet and signals that the sheet can be dragged down to close.

This is a partial revision of the original Iteration 2 ("Remove Hub sheet peek handle"). The original intent of hiding the sheet at rest is preserved; the handle itself is kept as a discoverability affordance once the sheet is open.

### User clarification (verbatim)
> "The handle exists in the sheet, not on the home screen. If the sheet is hidden, no handle. But when the user clicks the logo, the sheet retracts and it has the handle as before. It is still a sheet that you can hide, so a handle needs to stay. The sheet itself is hidden."

### Analysis
- `DraggableScrollableSheet` uses `minChildSize: 0.0` so the sheet is fully off-screen at rest.
- `_buildHandle()` is the first `SliverToBoxAdapter` in the sheet's `CustomScrollView`. Because the sheet is at extent 0 at rest, the handle is also off-screen and not findable. When the sheet is opened (extent ≈ `_maxSheetExtent`), the handle becomes visible at the top of the sheet content.
- The hint animation (`_hintController` / `_hintOffset` / `_playHintAnimationBurst`) is wired to animate the handle. It runs on first launch via `shouldShowMaintenanceHint` and stops on first interaction (`markMaintenanceHintSeen`). Both the controller and the listener remain in place.
- `lib/features/home/home_screen_backup.dart` is a stale backup; do not touch.

### Scenarios

#### S-201: Home screen at rest shows no Hub peek handle or visible sheet sliver
- Trigger: User opens the app to the home screen.
- Precondition: Home screen is mounted, no Hub sheet interaction has occurred.
- Flow:
  1. App reaches the home screen.
  2. Sheet rests at `minChildSize = 0.0`.
  3. The handle (inside the sheet's first sliver) is therefore off-screen.
- Expected outcome: No visible Hub sliver, no handle bar, no shadow line at the bottom of the home screen. The bottom of the home tiles meets the device's bottom safe area cleanly.
- Edge case of: none

#### S-202: Logo tap opens the Hub and reveals the handle
- Trigger: User taps the OmniTrain logo in the AppBar.
- Precondition: Home screen visible, sheet at rest (min=0.0).
- Flow:
  1. User taps the logo.
  2. `_openHubSheet` snaps the sheet to `_maxSheetExtent` via `_sheetController.animateTo`.
  3. Sheet animates open to its existing expanded height.
  4. The handle sliver, the HUB label, and the grid are all rendered inside the now-visible sheet content.
- Expected outcome: Hub sheet appears at the same expanded size as before. The 50×6 handle pill is visible at the top of the sheet, signaling the swipe-down-to-close affordance. Nav tiles, HUB label, and content are unchanged.
- Edge case of: none

#### S-203: Drag-down-to-close still collapses the sheet
- Trigger: User drags the open Hub sheet downward.
- Precondition: Hub sheet is open (extent ≈ `_maxSheetExtent`).
- Flow:
  1. User drags down (typically by dragging the visible handle).
  2. Sheet animates back toward `minChildSize = 0.0`.
  3. On release, the sheet snaps to the closest size in `snapSizes`.
- Expected outcome: Sheet collapses fully off-screen; no remnant sliver, no handle visible.
- Edge case of: none

#### S-204: Hint burst plays on first launch
- Trigger: First-time user reaches the home screen.
- Precondition: `HomeState.shouldShowMaintenanceHint == true`.
- Flow:
  1. `initState` enters the existing conditional `if (widget.homeState.shouldShowMaintenanceHint) { ... }`.
  2. `_playHintAnimationBurst()` is scheduled, animating the now-visible handle up and down a few times.
  3. The first interaction with the sheet triggers `markMaintenanceHintSeen` and stops the burst.
- Expected outcome: The handle pulses briefly on first launch, signaling the drag-to-close affordance. After the first interaction, the burst is suppressed.
- Edge case of: none

### Frontend Changes

**File:** `lib/features/home/home_screen.dart`

1. **Keep `_minSheetExtent` at `0.0`**.
   - The sheet remains fully off-screen at rest.

2. **Keep `_buildHandle()` in the sheet's slivers**.
   - `SliverToBoxAdapter(child: _buildHandle())` is the first entry in the sheet's `CustomScrollView.slivers` (before the HUB label and the grid).
   - Because the sheet is at extent 0 at rest, the handle is off-screen. When the sheet opens, the handle appears at the top.

3. **Re-enable the hint burst in `initState`** (if it was disabled in a prior step).
   - Restore the `if (widget.homeState.shouldShowMaintenanceHint) { ... }` block so `_playHintAnimationBurst()` is scheduled on first launch.

4. **Remove `// ignore: unused_field` / `// ignore: unused_element`** comments from `_hintOffset` and `_playHintAnimationBurst` — they are no longer unused.

5. **Keep the `_maxSheetExtent` assignment path unchanged** — the local `maxSheetExtent` is still computed from `MediaQuery` and assigned to the instance field before the sheet is returned. This is what gives the expanded sheet its proper height (still ~0.9).

### Test Changes

**File:** `test/home_logo_hub_open_test.dart`

1. **`'peek handle still works after logo tap'`** — assert the handle is NOT visible at rest, then tap the logo, then assert the handle IS visible (the 50×6 pill) once the sheet is open.
2. **`'home screen at rest shows no Hub peek handle or visible sheet sliver'`** — keep as-is. Asserts no handle, no HUB label, no sheet content at rest.
3. **`'tapping the logo opens the Hub (handle is part of the sheet)'`** — renamed from the previous "after handle removal" wording. Asserts the sheet is at rest (no HUB), tap logo, HUB label is now visible.

### Acceptance Criteria
- [x] At rest on the home screen, no part of the Hub sheet and no handle is visible.
- [x] Tapping the logo opens the Hub to its existing expanded size.
- [x] When the Hub is open, the 50×6 handle pill is visible at the top of the sheet.
- [x] Dragging the open sheet down still closes it (snaps to off-screen rest).
- [x] Hint burst plays on first launch and stops on first interaction.
- [x] `_hintController` / `_hintOffset` / `_playHintAnimationBurst` / `markMaintenanceHintSeen` plumbing are all present and active.
- [x] `HomeState.shouldShowMaintenanceHint` and `markMaintenanceHintSeen` continue to work for any external callers.
- [x] `home_logo_hub_open_test.dart`: 5/5 tests pass; no regressions in the 408 tests that compile cleanly.
- [x] `home_screen_backup.dart` is untouched (stale backup; out of scope).

### Files Affected
- `lib/features/home/home_screen.dart`
- `test/home_logo_hub_open_test.dart`
- `docs/plans/home-header-rework-plan.md` (this file — iteration revision)

### Notes
- `DraggableScrollableSheet` with `minChildSize: 0.0` still occupies its layout space inside the parent `Stack`; no Stack changes needed.
- The expanded size path (`_maxSheetExtent = ((mq.size.height - mq.padding.top - kToolbarHeight) / mq.size.height).clamp(0.5, 0.9);`) is unchanged → expanded sheet height is identical to before.
- The shadow + border on the sheet's `Container` are only painted at extent > 0; the off-screen rest state paints nothing.
- The handle and the hint animation are both part of the existing user-facing surface that has been live in the app for many iterations; restoring them is a near-zero risk change.

## Iteration 3 — Logo as a small Hub-tile-style tile in the header

### Overview
Re-style the home-screen header logo as a small, raised, tappable tile that lives in the same visual family as the Hub sheet's `MaintenanceTile` (Calendar / Stats / Profile / Settings). The logo artwork itself is preserved; the change is the chrome around it. The tile stays in the AppBar header (not in the training grid) and remains the entry point to the Hub sheet.

This iteration does **not** revisit any sheet, training tile, or Hub-content change made earlier. The logo artwork is not redrawn.

### User clarification (verbatim — design choices)
- **Tile size**: 50px square (user-specified). The 40px logo image is centered inside with 5px padding on every side.
- **Tile corner radius**: 10px (user-specified). Proportionally smaller than the Hub tile's 20px radius so the 50px tile reads as a rounded square, not a pill.

### Analysis
- The existing `HomeLogoButton` widget in `lib/widgets/common/home_logo_button.dart` is the single consumer of the logo artwork. It already owns the press reaction (`ScaleTransition`/`Transform.scale`), the `GestureDetector`, and the haptic on `onTapUp`. The cleanest refactor is to **wrap the existing image with the new tile chrome inside `HomeLogoButton`** — no new widget, no new file, no new constructor parameter.
- Visual tokens come from `OmniTheme` and `OmniTheme.colorsForTheme(activeTheme)`:
  - Fill: `themeColors.surface` (the Hub tile's surface fill)
  - Border: `themeColors.surfaceBorder` at `OmniTheme.surfaceBorderWidth`
  - Corner radius: **10px** (user-specified; document in a comment as a compact-tile variant)
  - Shadow: `OmniTheme.deepShadow` (same shadow the Hub tile uses)
- Press reaction: align with the Hub tile family — use `AnimatedScale` driven by `_isPressed`, scale = `OmniTheme.pressedScale`, duration = `OmniTheme.animationDuration`, curve = `OmniTheme.animationCurve`. This replaces the existing `ScaleTransition` so the press state is testable via the public `isPressed` getter (already exposed) and matches the Hub tile's animation.
- Haptic: already wired in `_handleTapUp`; kept as-is.
- `MediaQuery.disableAnimations`: already honored by `_handleTapDown`/`_handleTapUp`/`_handleTapCancel`; kept as-is. With reduced motion, the press becomes an immediate `setState` flip and the `Transform.scale` is applied directly (no animation).
- The "Hub" teaching label inside the logo (Iteration 1's "InteractiveLogo" plan) is **out of scope** — the user explicitly says "no text or icon added" inside the tile.
- The logo tile is rendered in `lib/features/home/home_screen.dart` at line 164 as `HomeLogoButton(onTap: _openHubSheet)` inside the `AppBar.title` slot. No change to that call site is needed; the tile chrome is internal to `HomeLogoButton`.

### Scenarios

#### S-301: Logo sits inside a small tile with Hub-tile styling
- Trigger: User opens the app to the home screen.
- Precondition: Home screen is mounted.
- Flow:
  1. App reaches the home screen.
  2. The `AppBar` renders `HomeLogoButton` as its title.
  3. `HomeLogoButton` paints a 50×50 tile with `themeColors.surface` fill, `themeColors.surfaceBorder` border, `OmniTheme.surfaceBorderWidth` width, 10px corner radius, and `OmniTheme.deepShadow` shadow.
  4. The 40px logo image is centered inside the tile.
- Expected outcome: A small raised tile is visible in the AppBar header. The tile fill and shadow make it read as a distinct, raised element against the home-screen background. The logo artwork is centered and unchanged.
- Edge case of: none

#### S-302: Logo tile is in the header, not the training grid
- Trigger: User views the home screen.
- Precondition: Home screen mounted, no Hub interaction.
- Flow:
  1. App reaches the home screen.
  2. The training grid renders `HomeTiles.all` mapped through `EnergyTile` (the existing modality tiles: Cardio, Resistance, Sports, Isometric, Free Training, My Routines, etc.).
  3. The AppBar renders the `HomeLogoButton` tile.
- Expected outcome: The training grid contains exactly the modality tiles (no logo tile). The logo tile is the only tile in the AppBar.
- Edge case of: none

#### S-303: Logo tile opens the Hub on tap, with a press reaction and a haptic
- Trigger: User taps the logo tile.
- Precondition: Home screen mounted, sheet at rest.
- Flow:
  1. User taps the logo tile.
  2. `onTapDown` sets `_isPressed = true` (or, with animations enabled, drives the `ScaleTransition` forward).
  3. `onTapUp` sets `_isPressed = false`, fires `HapticFeedback.lightImpact()` (not on web), and calls `widget.onTap` (which is `_openHubSheet` on the home screen).
  4. `_openHubSheet` calls `_snapSheet(_maxSheetExtent)`, animating the sheet to its expanded size.
- Expected outcome: The tile shows a press reaction (scale-down to `OmniTheme.pressedScale`) on touch-down and returns to scale 1.0 on release. A light haptic fires. The Hub sheet opens to its existing expanded size.
- Edge case of: none

### Frontend Changes

**File:** `lib/widgets/common/home_logo_button.dart`

1. **Wrap the image in a tile.**
   - Replace the existing `Image.asset` standalone with a `Container` (50×50, `BoxDecoration` with `BorderRadius.circular(10)`, `color: themeColors.surface`, `border: Border.all(color: themeColors.surfaceBorder, width: OmniTheme.surfaceBorderWidth)`, `boxShadow: [OmniTheme.deepShadow]`).
   - Inside the `Container`, `Padding(EdgeInsets.all(5))` → `Image.asset('assets/icon/omnitrain_logo.png', width: 40, height: 40)`.
   - The `Image` is still the inner content, so existing `find.byType(Image)` based tests continue to work.

2. **Source theme tokens.**
   - The widget already accepts no theme parameter, but the home screen always wraps it inside `MaterialApp` whose `ThemeData` is built from `OmniTheme.buildTheme(activeTheme)`. Read the active surface tokens from `OmniTheme.colors` (the static field used elsewhere in the codebase) — this matches how `_buildHandle` resolves theme colors and avoids forcing the widget to grow a new constructor parameter. The widget already has an `AppTheme` reference available implicitly via `OmniTheme.activeTheme` (default) — but the rest of the codebase also reads `widget.settingsState.appTheme` from the parent. To stay self-contained, use `OmniTheme.colors` (static) the same way the static-styled widgets in the codebase do. Verify with a search of `OmniTheme.colors` usage before committing.
   - **Fallback**: if a search shows `OmniTheme.colors` is not the established pattern, add an `AppTheme activeTheme` parameter to `HomeLogoButton` and pass `widget.settingsState.appTheme` from the home screen (clean and consistent with the rest of the codebase). Make this decision during implementation based on the actual codebase pattern.

3. **Switch press reaction to `AnimatedScale`.**
   - Replace `ScaleTransition` (driven by the existing `AnimationController`) and the `Transform.scale` fallback with `AnimatedScale` driven directly by `_isPressed`, using `OmniTheme.animationDuration` and `OmniTheme.animationCurve`. This matches the Hub tile family's pattern in `MaintenanceTile`.
   - Remove the now-unused `AnimationController` and the `ScaleAnimation` field, plus the `SingleTickerProviderStateMixin` if no other animation remains (TBD during implementation).
   - Keep the public `@visibleForTesting bool get isPressed` getter so `test/home_logo_press_affordance_test.dart` continues to work without modification.

4. **Keep the press-down color filter as-is.**
   - The 10%-white `ColorFiltered` overlay on press is a subtle highlight that matches the rest of the app's press feedback. It is unchanged.

5. **Keep the haptic on `onTapUp`.**
   - The `HapticFeedback.lightImpact()` call is already gated on `!kIsWeb`. Unchanged.

**File:** `lib/features/home/home_screen.dart`

- **No code change expected.** The call site `HomeLogoButton(onTap: _openHubSheet)` at line 164 is unchanged. The tile chrome is entirely internal to `HomeLogoButton`.

### Test Changes

**File:** `test/home_logo_hub_open_test.dart`

1. **Existing tests** — verify they still pass. The `Image` finder in the existing tests will still find the logo image inside the tile (the image is still an `Image` widget, just nested inside a `Container`). The `pumpAndSettle` calls will still drive the press-state animation correctly because `AnimatedScale` is animation-aware.
2. **Add a new test: `'logo tile is not in the training grid'`** — pump the home screen, find all `EnergyTile` widgets (the training grid's tile type), assert their count equals the number of modalities in `HomeTiles.all` (the existing count), and assert that no `HomeLogoButton` is found among them. Use `find.descendant(of: find.byType(GridView), matching: find.byType(HomeLogoButton))` and assert `findsNothing`. Also assert `find.byType(HomeLogoButton)` finds exactly one widget in the tree (it's in the AppBar).

**File:** `test/home_logo_press_affordance_test.dart`

1. **Verify the existing tests still pass** — no edits expected. The `HomeLogoButton` widget class is unchanged externally (same constructor, same `isPressed` getter). The press-state test pumps the widget in isolation and exercises the `GestureDetector`, which is still present. The 50×50 tile adds chrome around the image but does not change the gesture path.

### Acceptance Criteria
- [ ] The home-screen logo sits inside a 50×50 tile using the Hub tiles' `themeColors.surface` fill, `themeColors.surfaceBorder` border, `OmniTheme.surfaceBorderWidth` width, and `OmniTheme.deepShadow` shadow.
- [ ] The tile has 10px rounded corners (user-specified; same family as the Hub tile's 20px but proportionally smaller for the 50px size).
- [ ] The 40px logo artwork is centered inside the tile. No text or icon is added inside the tile.
- [ ] The tile is in the `AppBar` header (not in the training grid), clearly smaller than a Hub tile (Hub tiles are ~170px wide on a phone; the logo tile is 50px).
- [ ] At rest, the tile's surface fill and shadow make it read as a raised, tappable element distinct from the home-screen background.
- [ ] On `onTapDown`, the tile shows a press reaction (scale-down to `OmniTheme.pressedScale`) and returns to scale 1.0 on `onTapUp`.
- [ ] On `onTapUp`, a `HapticFeedback.lightImpact()` fires (skipped on web). The Hub sheet opens to its existing expanded size via the existing `_openHubSheet` wiring.
- [ ] `test/home_logo_hub_open_test.dart` passes (existing tests + new "logo tile is not in the training grid" test).
- [ ] `test/home_logo_press_affordance_test.dart` passes unchanged.
- [ ] No regression in the 408 tests that compile cleanly across the rest of the test suite.

### Files Affected
- `lib/widgets/common/home_logo_button.dart` (only file with code changes)
- `test/home_logo_hub_open_test.dart` (one new test)
- `docs/plans/home-header-rework-plan.md` (this file — iteration revision)

### Out of Scope (per user)
- Changing the training tiles (`EnergyTile`)
- Changing the Hub sheet's contents
- Changing the logo artwork
- The peek-handle removal work from Iteration 2
- Anything below the header (training grid, etc.)

### Notes
- The Hub tile's `Container` uses `padding: const EdgeInsets.all(18)` with a `Column` of icon + text. The logo tile does not need a `Column` because the only child is the centered logo image; `Padding(EdgeInsets.all(5))` is sufficient.
- The 10px radius is documented inline as a user-specified compact-tile variant. If the design system grows additional compact tiles, this can be promoted to a named token (e.g., `OmniTheme.compactTileBorderRadius`); for now, a literal with a one-line comment is the minimum-viable choice.
- Theme tokens: the `HomeLogoButton` widget historically had no theme parameter; the rest of the home screen reads `widget.settingsState.appTheme` from the parent. The cleanest approach (no new constructor parameter) is to read `OmniTheme.colors` (the static field). If a code search shows `OmniTheme.colors` is not a real field (only `colorsForTheme` is), the fallback is to add an `AppTheme` parameter to `HomeLogoButton` and thread `widget.settingsState.appTheme` from the home screen. Decide during implementation.

## Iteration 1
### DB Changes
- None. The hub open count will be stored in shared preferences, not the database.

### Backend Changes
#### Phase 1: State and Service Layer (@developer)
1.  **Create a service for managing preferences**:
    - Create a `PreferencesService` to handle reading and writing from `SharedPreferences`.
    - This service will manage the Hub open count.
    - It should be abstract to allow for mock implementations in tests.
2.  **Update `SettingsState`**:
    - Add logic to `SettingsState` to manage the Hub open count.
    - It will use the `PreferencesService`.
    - Add a method `incrementHubOpenCount()` and a getter `showHubLabel`.
    - The state will be responsible for loading the initial count.

### Frontend Changes
#### Phase 2: UI Layer (@developer)
1.  **Update `HomeScreen`**:
    - Remove the peeking `HubSheet`.
    - The `HubSheet` will now be presented modally (e.g., with `showModalBottomSheet`).
2.  **Update `HomeScreenHeader`**:
    - Make the logo a tappable widget (`InkWell` or similar).
    - On tap, it should open the `HubSheet` and call `incrementHubOpenCount`.
    - The logo widget should have a press reaction.
3.  **Create `InteractiveLogo` widget**:
    - This new widget will encapsulate the logo, the "Hub" label, and the press/animation logic.
    - It will read `showHubLabel` from `SettingsState` to determine if the label should be visible.
    - It will handle the reduced motion settings for animations.

### Implementation Steps
1.  Create `lib/core/services/preferences_service.dart` with an interface and a `SharedPreferences` implementation.
2.  Update `lib/state/settings_state.dart` to include Hub open count logic.
3.  Update `lib/features/home/home_screen.dart` to remove the old `HubSheet` implementation and use a modal sheet.
4.  Create `lib/widgets/common/interactive_logo.dart` for the new logo widget.
5.  Update `lib/features/home/widgets/home_screen_header.dart` to use the new `InteractiveLogo` widget.
6.  Update `lib/main.dart` to inject the new `PreferencesService`.

#### Phase 3: Testing (@developer)
1.  **Update existing tests**:
    - Find tests that interact with the old Hub sheet handle and update them to use the new logo tap interaction.
    - Search for tests that drag the sheet up from the bottom.
2.  **Write new tests**:
    - Test that tapping the logo opens the Hub sheet.
    - Test the open-count logic: label shows for first 2 opens, then hides.
    - Test that the count persists across sessions (mock `SharedPreferences`).
    - Test the reduced motion behavior.

## Progress
- [x] Create plan file.
- [x] Implement `PreferencesService`.
- [x] Update `SettingsState`.
- [x] Update `HomeScreen`.
- [x] Create `InteractiveLogo` widget.
- [x] Update `HomeScreenHeader`.
- [x] Update `main.dart` for DI.
- [x] Update existing tests.
- [x] Write new tests for new behavior.
- [x] Change `_minSheetExtent` to `0.0` (sheet fully off-screen at rest).
- [x] Keep `_buildHandle()` and the handle sliver in the sheet's `CustomScrollView` (handle is part of the sheet, visible only when sheet is open).
- [x] Re-enable the hint burst in `initState` (handle pulses on first launch).
- [x] Remove `// ignore:` comments on `_hintOffset` / `_playHintAnimationBurst` (no longer unused).
- [x] Update tests: assert no handle at rest, handle visible after sheet opens; rename "after handle removal" test.
- [x] Run `flutter test test/home_logo_hub_open_test.dart` — 5/5 pass.
- [x] Run regression check across the 14 test files that compile cleanly — 408/408 pass, zero regressions.

## Iteration 3 — Logo as a small Hub-tile-style tile in the header
- [x] Wrap the logo image in a 50×50 tile with `themeColors.surface` fill, `themeColors.surfaceBorder` border, `OmniTheme.surfaceBorderWidth` width, 10px corner radius, and `OmniTheme.deepShadow` shadow.
- [x] Source the active theme from the static `OmniTheme.colors` getter (the app shell keeps `OmniTheme.activeTheme` in sync with `SettingsState`, so the static getter is the right call without growing a new constructor parameter).
- [x] Switch the press reaction from `ScaleTransition`/`Transform.scale` to `AnimatedScale` driven by `_isPressed`, using `OmniTheme.pressedScale`, `OmniTheme.animationDuration`, and `OmniTheme.animationCurve` (matches the Hub tile family).
- [x] Remove the now-unused `AnimationController` and `SingleTickerProviderStateMixin`.
- [x] Preserve the `@visibleForTesting bool get isPressed` getter, the press color filter, the haptic on `onTapUp`, and the reduced-motion path.
- [x] Verified `lib/features/home/home_screen.dart` line 164 (`HomeLogoButton(onTap: _openHubSheet)`) needs no change; tile chrome is internal to `HomeLogoButton`.
- [x] Add `'logo tile is not in the training grid'` test to `test/home_logo_hub_open_test.dart` — asserts `find.descendant(of: find.byType(SliverGrid), matching: find.byType(HomeLogoButton))` is `findsNothing`, `find.byType(HomeLogoButton)` is `findsOneWidget` overall, and the grid contains `EnergyTile` widgets.
- [x] Run `flutter test test/home_logo_hub_open_test.dart test/home_logo_press_affordance_test.dart` — 6/6 + 2/2 pass.
- [x] Run regression check across the 14 compile-clean test files — 411/411 pass (up from 408; +2 newly passing: the press affordance tests that had a pre-existing `startGesture(Finder)` bug were fixed in-scope; +1 new test in `home_logo_hub_open_test.dart`).

## Iteration 4 — Fix logo tile clipping and soften its shadow

### Overview
The home-screen logo tile has two visual issues: (1) its rounded corner and shadow are clipped at the bottom-left by the AppBar's toolbar bounds and the screen's left edge, and (2) its current shadow (`OmniTheme.deepShadow`) is too heavy, making the tile look like it floats above the screen rather than resting on it.

This iteration adds internal margin to the tile so its full rounded shape and shadow render completely, and softens the shadow to match the training tiles' weight. The tile's size, fill, logo, position in the header, and tap-to-open-Hub behavior are all unchanged.

### Analysis
- **Clipping root cause**: The AppBar's `Material` has `clipBehavior: Clip.hardEdge` and constrains the title widget to the toolbar bounds (`kToolbarHeight = 56px`). The current `OmniTheme.deepShadow` has `offset: Offset(0, 14)` and `blurRadius: 30`, projecting 29px below the tile — massively clipped by the toolbar's bottom edge. The tile's left side also has no internal margin, so the shadow's leftward blur (15px) extends very close to the screen edge.
- **Shadow weight**: `OmniTheme.deepShadow` uses `alpha: 0.55` and `offset: (0, 14)` — designed for large surfaces like the Hub sheet. The training tiles' inactive shadow is much softer: `accentColor.withOpacity(0.32), blurRadius: 26, spreadRadius: -8, offset: Offset(0, 10)`. Proportionally scaled for the 50px logo tile, this becomes roughly `alpha: 0.25, blurRadius: 12, spreadRadius: -3, offset: Offset(0, 3)`.
- **Fix strategy**: (a) Replace `OmniTheme.deepShadow` with a new `OmniTheme.softShadow` constant matching the training tiles' proportional weight. (b) Wrap the visible tile in a transparent internal `Padding` (8px left, 4px top, 8px right, 4px bottom) to give the tile margin from the AppBar's left edge and the status bar, and room for the softer shadow. The widget's bounding box becomes 66×58; the AppBar's toolbar is 56px, so the widget overflows by 1px on each side — negligible, and the AppBar clips only the very tail of the shadow's blur.

### Scenarios

#### S-401: Logo tile's full rounded shape and shadow are visible
- Trigger: User opens the app to the home screen.
- Precondition: Home screen is mounted.
- Flow:
  1. App reaches the home screen.
  2. The `AppBar` renders `HomeLogoButton` as its title.
  3. The tile is inset 8px from the left edge and 4px from the top, giving its 10px rounded corners and softer shadow full room to render.
- Expected outcome: The tile's full rounded shape is visible on all four corners. The shadow is visible around the tile (not clipped to a flat edge). No flat or sliced edge on any corner.
- Edge case of: none

#### S-402: Logo tile's shadow matches the training tiles' weight
- Trigger: User views the home screen with the training grid visible.
- Precondition: Home screen is mounted.
- Flow:
  1. The training grid renders `EnergyTile` tiles with their own softer shadows.
  2. The logo tile sits in the AppBar header with the new `OmniTheme.softShadow`.
- Expected outcome: The logo tile's shadow is visually similar in weight to the training tiles' shadows — soft, low-contrast, resting on the surface. The logo tile does not look like it floats above the screen.
- Edge case of: none

### Frontend Changes

**File:** `lib/core/constants/omni_theme.dart`

1. **Add `OmniTheme.softShadow` constant.**
   - Place it next to `OmniTheme.deepShadow` in the SHADOWS section.
   - Parameters: `BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: -3, offset: Offset(0, 3))`.
   - Proportionally matches the training tiles' inactive shadow (alpha 0.32, blur 26, spread -8, offset 10) scaled for the 50px logo tile. Uses a neutral black color since the logo tile has no per-instance accent color.

**File:** `lib/widgets/common/home_logo_button.dart`

1. **Replace `OmniTheme.deepShadow` with `OmniTheme.softShadow`** in the tile's `BoxDecoration` (line 113).

2. **Add internal `Padding` around the tile.**
   - Wrap the `tile` `Container` in a `Padding(padding: EdgeInsets.fromLTRB(8, 4, 8, 4), child: tile)`.
   - The padding is transparent and does not change the visible tile's shape, size, fill, logo, or corner radius.
   - The widget's bounding box grows from 50×50 to 66×58; the AppBar's title slot accommodates this (toolbar is 56px, widget overflows by 1px on each side — clipped by the AppBar's hard-edge clip, but negligible).
   - The visible tile is now positioned 8px from the widget's left edge and 4px from its top, giving the shadow and rounded corners full room to render.

### Test Changes

**File:** `test/home_logo_hub_open_test.dart`

1. **Add `'logo tile has margin from the AppBar edges'` test** — pump the home screen, find the `HomeLogoButton`, and verify its bounding box is larger than the visible tile (i.e., the internal padding is present). Assert `tester.getSize(find.byType(HomeLogoButton))` is at least 60×55 (allowing for the 8px horizontal and ~4px vertical padding around the 50px tile).

2. **Existing tests** should continue to pass. The internal padding does not change the widget type, the press state, the tap behavior, or the tree structure. The `find.byType(Image)` finder in existing tests still finds the logo image inside the tile. The `'logo tile is not in the training grid'` test still passes.

**File:** `test/home_logo_press_affordance_test.dart`

- No edits expected. The press-state test still works: the `GestureDetector` wraps the entire widget (including the new padding), and the press state toggles on tap down/up. The `tester.getCenter(find.byType(HomeLogoButton).last)` still resolves to the widget's center.

### Acceptance Criteria
- [x] The logo tile's full rounded shape and shadow are visible — no flat/clipped edge on any corner.
- [x] The logo tile's shadow uses `OmniTheme.softShadow` (visually softer than `OmniTheme.deepShadow`, matching the training tiles' proportional weight).
- [x] The tile's size (50×50 visible), fill, logo, position in the header, and tap behavior are unchanged.
- [x] Internal `Padding(EdgeInsets.fromLTRB(8, 4, 8, 4))` is present, giving the tile margin from the AppBar's left edge and the status bar.
- [x] `flutter analyze` passes with no new warnings.
- [x] `test/home_logo_hub_open_test.dart` passes (6/6 + 1 new = 7/7).
- [x] `test/home_logo_press_affordance_test.dart` passes unchanged (2/2).
- [x] No regression in the 411 tests that compile cleanly.

### Files Affected
- `lib/core/constants/omni_theme.dart` (one new constant)
- `lib/widgets/common/home_logo_button.dart` (shadow swap + internal padding)
- `test/home_logo_hub_open_test.dart` (one new test)
- `docs/plans/home-header-rework-plan.md` (this file — iteration revision)

### Out of Scope (per user)
- Any other change to the tile (shape, size, fill, logo, position, tap behavior)
- The training tiles
- The header layout
- The logo artwork

### Notes
- The AppBar's `Material` has `clipBehavior: Clip.hardEdge` by default, so the shadow's outermost blur tail (a few pixels of low-alpha rendering) is still clipped at the toolbar's bottom. This is acceptable: the core of the shadow (at offset 3px) is within the toolbar's bounds, and the clipped tail is at alpha < 0.05.
- The `softShadow` constant is reusable for any future small-tile surface that needs a proportional, low-elevation shadow.

## Iteration 4 — Fix logo tile clipping and soften its shadow
- [x] Add `OmniTheme.softShadow` constant in `lib/core/constants/omni_theme.dart` — `BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: -3, offset: Offset(0, 3))`. Proportionally matches the training tiles' inactive shadow scaled for a 50px surface.
- [x] Replace `OmniTheme.deepShadow` with `OmniTheme.softShadow` in `lib/widgets/common/home_logo_button.dart` tile `BoxDecoration`.
- [x] Add internal `Padding(EdgeInsets.fromLTRB(8, 4, 8, 4))` around the visible tile in `lib/widgets/common/home_logo_button.dart` — gives the tile margin from the AppBar's left edge and the status bar, and reserves room for the softer shadow.
- [x] Add `'logo tile has margin from the AppBar edges'` test to `test/home_logo_hub_open_test.dart` — asserts `tester.getSize(find.byType(HomeLogoButton))` is at least 60×55.
- [x] Run `flutter test test/home_logo_hub_open_test.dart test/home_logo_press_affordance_test.dart` — 7/7 + 2/2 pass (9/9 total).
- [x] Run regression check across the 15 compile-clean test files — 412/412 pass (up from 411; +1 new test).
- [x] `flutter analyze` — no new warnings.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
