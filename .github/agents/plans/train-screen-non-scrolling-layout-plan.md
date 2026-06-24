# Train Screen — Non-Scrolling, Single-Fit Layout

## Overview

Convert the Train screen (`HomeScreen`) from a `CustomScrollView` grid with
a docked-at-the-bottom `NutritionSummaryCard` into a single, non-scrolling
layout where the six training tiles and the calorie summary card are peer
elements that all fit on screen at once. The summary becomes a peer card
sitting directly below the grid (same margins, same inter-card gap), and the
layout shrinks to fit on shorter phones — the summary reduces height first,
down to a defined minimum, before the tiles compress.

## Requirements

- The Train screen never scrolls in any state. No `Scrollable` /
  `CustomScrollView` / `ListView` governs the tiles or the summary.
- The six training tiles plus the calorie summary card are always
  simultaneously visible, fully within screen bounds, on every supported
  phone size.
- The summary card is a peer element placed directly below the two-row tile
  grid. It uses the same left/right margins as the grid (16 px) and the same
  vertical gap that separates the two tile rows (16 px). It is no longer
  pinned to the bottom and has no extra surrounding box / wrapper padding —
  the only visible chrome is the card itself.
- The summary card spans the full content width (both columns of the grid),
  not a single column or a tile-sized square.
- On phones too short for natural sizing, the whole layout shrinks to fit.
  The summary card reduces height first, down to a defined minimum that keeps
  its calorie figure and gauge legible. Only when the summary is already at
  its minimum do the tiles compress. Nothing scrolls, nothing clips, nothing
  overlaps.
- On taller phones, card-to-card spacing stays consistent — surplus space
  falls below the summary card, not stretched through the gaps.
- Internal summary card design (colors, gauge, content, tap handler) is
  untouched.
- Tile design (icons, labels, colors, two-column arrangement) is untouched.

## Acceptance Criteria

- [ ] The Train screen contains no `Scrollable` / `ScrollView` /
      `CustomScrollView` / `ListView` / `SingleChildScrollView` governing the
      tiles or the summary.
- [ ] All six training tiles plus the summary card are simultaneously
      rendered, fully within screen bounds, on small, medium, and large
      supported phone sizes.
- [ ] The summary card sits below the grid using the same horizontal
      margins as the grid (16 px) and the same vertical gap used between
      the two tile rows (16 px).
- [ ] The summary card spans the full content width (both columns), not a
      single column.
- [ ] The summary card is no longer docked to the bottom of the screen and
      has no extra surrounding background box or wrapper padding — only the
      card itself is visible.
- [ ] On a short screen, the summary card renders at a height below its
      natural size, while the tiles keep their full size (the summary is the
      first to shrink).
- [ ] On a shorter screen where the summary is already at its minimum, the
      tiles compress and the full layout still fits without scroll, without
      clipping, and without overlap.
- [ ] The summary card never renders below its defined minimum height (the
      minimum is respected).
- [ ] On a tall screen, card-to-card spacing stays consistent — any surplus
      space falls below the summary card, not through the gaps.

## Scenarios

### S-001: Train screen never scrolls
- Trigger: Render the home/Train screen at any size.
- Precondition: Default seeded state.
- Flow: Pump the home screen with the standard mock repo; let it settle.
- Expected outcome: No `Scrollable`, `ScrollView`, `CustomScrollView`,
  `ListView`, or `SingleChildScrollView` is found in the home screen widget
  tree (excluding the bottom maintenance sheet, which is out of scope).
- Edge case of: none

### S-002: Six tiles + summary visible on a small phone
- Trigger: Render the Train screen at a small-phone size (e.g. 360 × 640).
- Precondition: Default seeded state.
- Flow: Pump the home screen at small surface size; let it settle.
- Expected outcome: All six `EnergyTile` widgets are mounted and rendered
  fully within screen bounds (no overflow). The `NutritionSummaryCard` is
  also rendered fully within bounds.
- Edge case of: S-001

### S-003: Summary sits below the grid with shared margins + gap
- Trigger: Render the Train screen at a tall phone size (e.g. 390 × 844).
- Precondition: Default seeded state.
- Flow: Pump the home screen at tall surface size; let it settle.
- Expected outcome: The summary card's left edge is at the same x as the
  grid's left edge (16 px inset from screen left). The summary card's right
  edge matches the grid's right edge (16 px inset from screen right). The
  vertical gap between the bottom of the second tile row and the top of the
  summary card is exactly 16 px (the same value as the inter-row gap).
- Edge case of: none

### S-004: Summary spans full content width
- Trigger: Render the Train screen at any size.
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The summary card width equals the grid content width
  (screen width minus 32 px for the two 16 px side margins). The summary
  card is wider than a single tile column.
- Edge case of: S-003

### S-005: Summary is a peer card, not a docked bar
- Trigger: Render the Train screen.
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The summary card is NOT positioned inside
  `Scaffold.bottomNavigationBar`, `Scaffold.persistentFooterButtons`, a
  `BottomAppBar`, or any container anchored to the bottom of the screen.
  It appears as the last child of the main body `Column`.
- Edge case of: none

### S-006: Short screen — summary shrinks, tiles stay full
- Trigger: Render the Train screen at a height slightly below natural
  fitting size (e.g. 390 × 700).
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The tiles render at their full natural size. The
  summary card height is below its natural content height but above the
  defined minimum. Nothing overflows.
- Edge case of: S-001

### S-007: Shorter screen — summary at minimum, tiles compress
- Trigger: Render the Train screen at a much shorter height (e.g. 390 ×
  550).
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The summary card renders at exactly its defined
  minimum height. The tiles compress (their height is below the natural
  square size) and the full layout still fits without scroll, without
  clipping, and without overflow.
- Edge case of: S-006

### S-008: Summary never below minimum
- Trigger: Render the Train screen at an extremely short height (e.g. 390
  × 400).
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The summary card height equals the defined minimum
  (not below). Tiles compress to whatever remaining space exists.
- Edge case of: S-007

### S-009: Tall screen — gaps stay consistent
- Trigger: Render the Train screen at a tall phone size (e.g. 430 × 932).
- Precondition: Default seeded state.
- Flow: Pump the home screen; let it settle.
- Expected outcome: The vertical gap between the first and second tile
  rows is exactly 16 px (the grid's `mainAxisSpacing`). The vertical gap
  between the second tile row and the summary card is exactly 16 px.
  Surplus space falls below the summary card.
- Edge case of: S-003

### S-010: Update — no docked / scroll contract left
- Trigger: Run the existing home / hub / nutrition summary test suites.
- Precondition: Existing tests reference the old docked/scroll contract.
- Flow: Tests are updated to assert the new peer, non-scrolling
  contract. Specifically: the S-106 group in
  `home_nutrition_summary_card_test.dart` no longer asserts a 32 px gap
  (it asserts the new 16 px peer gap), and no test asserts that the grid
  is a `SliverGrid` inside a `CustomScrollView`.
- Expected outcome: All updated and new tests pass.
- Edge case of: S-001, S-003

## Iteration 1

### DB Changes

None. This is a layout-only change. No models, no repository, no seed data.

### Backend Changes

None. No state, no service, no business logic changes. The
`NutritionState` getters used to feed the summary card are unchanged.

### Frontend Changes

The change lives in `lib/features/home/home_screen.dart`. The widget tree
in `build()` is restructured so that:

1. The main column body is a `Column` whose children are, in order:
   - The `TRAIN` title (unchanged).
   - A 20 px gap (unchanged).
   - The two-row tile grid (now rendered via `Column` + `Row` + `Expanded`,
     not `CustomScrollView` / `SliverGrid`).
   - A 16 px gap (the same value as the inter-row gap — peer placement).
   - The `NutritionSummaryCard`.
   - A trailing `Spacer` / `Expanded` for tall-phone surplus space.
2. The grid is rendered as a `Column` of two `Row`s (each row is a 2-column
   grid of `Expanded` `EnergyTile`s). The first row has 4 tiles, the second
   row has 2 tiles.
3. The tile rows and the summary card participate in a `Flexible` /
   `Expanded` arrangement that lets the layout shrink to fit on shorter
   phones. The summary card uses a flex of 0 at natural size and shrinks
   first under pressure, down to a defined minimum
   (`NutritionSummaryCard.minHeight = 96.0` px — a new constant on the
   card that keeps the calorie figure and gauge legible). The tile rows
   use `Flexible` with flex that increases under pressure only after the
   summary is at minimum.
4. The summary card's outer `Padding(EdgeInsets.symmetric(horizontal:
   16))` is preserved (peer margins). The previous
   `Padding(EdgeInsets.only(bottom: 12))` wrapper is removed because the
   summary is no longer pinned to the bottom.
5. `Scaffold.bottomNavigationBar`, `Scaffold.persistentFooterButtons`,
   `BottomAppBar`, and any "bottom strip" wrappers are not used for the
   summary card.

A new constant `NutritionSummaryCard.minHeight = 96.0` is introduced on
the card. This is the only change to the card itself — internal design
is untouched.

### Implementation Steps

1. Add `NutritionSummaryCard.minHeight` constant and wrap the card's
   content in a `ConstrainedBox(constraints: BoxConstraints(minHeight:
   NutritionSummaryCard.minHeight))` with a `Flexible` parent at the
   home-screen level so the card can be flex-compressed between its
   content height and `minHeight`.
2. Restructure the `build()` method in `home_screen.dart`:
   - Replace the `Expanded(child: ListenableBuilder(... CustomScrollView(
     slivers: [SliverGrid, SliverToBoxAdapter, SliverGrid]))...)` block
     with a non-scrolling grid that uses `Column` + two `Row`s of
     `Expanded` tiles, with a fixed 16 px inter-row gap.
   - Replace the bottom-of-screen `Column(children: [SizedBox(32),
     Padding(bottom:12, ListenableBuilder(... NutritionSummaryCard
     ...))])` block with a peer-positioned summary: `SizedBox(height:
     standardGridSpacing)` + `NutritionSummaryCard` inside the same
     body `Column` as the grid (no extra wrapper Padding). The summary
     is wrapped in a `Flexible(child: ConstrainedBox(...))` that allows
     it to shrink under vertical pressure.
   - Wrap the grid + summary block in a `Column` with a trailing
     `Spacer()` so tall screens absorb surplus space below the summary
     (gaps stay consistent).
3. Confirm the home screen `Scaffold` no longer contains
   `bottomNavigationBar`, `persistentFooterButtons`, or any pinned
   bottom slot. The maintenance sheet (out of scope) is unchanged.
4. Run the full existing test suite to surface any contract assertions
   tied to the old docked/scroll structure (S-106 in
   `home_nutrition_summary_card_test.dart`, and the
   `home_logo_hub_open_test.dart` assertions about `SliverGrid` / logo
   tile placement).
5. Update affected existing tests to the new peer / non-scrolling
   contract (replace 32 px SizedBox gap assertion with 16 px peer gap
   assertion; remove `SliverGrid` expectations from logo-tile-placement
   tests, replacing with assertions about the grid being a plain
   `Row`-based 2-column grid).
6. Write new widget tests covering S-001 through S-009 in
   `test/home_train_layout_test.dart` (the feature-area test file
   already exists per the test mapping — `test/screen_widget_test.dart`
   for renders + `test/interaction_flow_test.dart` for interactions;
   since this is a layout/render concern, the new tests go in
   `test/screen_widget_test.dart` and reference the home screen by
   key, reusing the `_buildHomeScreen` helper pattern from
   `home_nutrition_summary_card_test.dart`).
7. Run `flutter test test/screen_widget_test.dart` and
   `flutter test test/home_nutrition_summary_card_test.dart` and
   `flutter test test/home_logo_hub_open_test.dart` to confirm new and
   updated tests pass.
8. Run `flutter analyze lib/ test/` to confirm no new lints.

## Progress

- [x] Phase 0 — Plan (this file)
- [ ] Phase 1 — Data Layer (N/A — no model / repo / schema changes)
- [ ] Phase 2 — Logic & UI
  - [ ] Add `NutritionSummaryCard.minHeight` constant
  - [ ] Restructure `home_screen.dart` grid + summary layout
  - [ ] Update existing tests with old docked/scroll contracts
  - [ ] Write new layout tests S-001 through S-009
  - [ ] Run `flutter test` for affected files
  - [ ] Run `flutter analyze`
- [ ] Phase 3 — Code Review

### Phase 0 Complete ✓

## Feedback

