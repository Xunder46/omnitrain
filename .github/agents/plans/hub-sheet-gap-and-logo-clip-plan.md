# Feature: Hub sheet gap tightening + logo clip fix

## Overview

Tighten the empty band between the `HUB` eyebrow label and the first row of
maintenance tiles in the Hub sheet so the grid sits balanced within the sheet
(rather than being pushed to the bottom), and fix the top-left logo mark so it
is no longer clipped by the sheet's top edge when the sheet is fully expanded.
Tile sizes, column count, tile order, snap positions, drag behaviour, and the
five-tile arrangement (which leaves one tile alone on the last row) are
unchanged.

> **TRIVIAL feature** — no schema change, no new state, no new user-facing
> behavior. Lean plan with a single iteration block; scenario register is one
> block per scenario and the test plan is the unit-test matrix the user
> supplied.

## Requirements

- The vertical gap between the `HUB` eyebrow text and the top edge of the
  first row of `MaintenanceTile`s is visibly reduced, so the grid is no longer
  pushed toward the sheet's lower edge.
- The Hub sheet's grid sits in a balanced position within the sheet (with
  breathing room above the bottom row, not crowding the sheet's lower edge).
- Tile sizes (width, height, aspect ratio, internal padding, gap) are
  unchanged.
- Column count is unchanged (2 columns; 5 tiles leave the last row with one
  tile alone — this is the expected arrangement).
- Tile order is unchanged (Calendar, Stats, Exercise Library, Profile,
  Settings).
- The top-left `HomeLogoButton` renders fully (no clipping by the sheet edge
  or by any inset/clipping widget along the way), at the default text scale
  and at the largest supported system text scale.
- The sheet's collapsed (`_minSheetExtent = 0.0`) and expanded
  (`_maxSheetExtent`) snap positions resolve correctly. Drag-and-release
  between them still snaps to the closest snap point (no half-open stops,
  per the existing `hub-bottom-sheet-single-step-open-plan.md` contract).
- No new tiles, no removed tiles, no label changes, no icon changes, no
  colour changes, no change to sheet snap animation timing/curve.

## Acceptance Criteria

- [ ] The gap between the `HUB` eyebrow and the first tile row is visibly
      reduced (the visual band above the grid is shorter than before).
- [ ] The grid sits balanced within the sheet — there is breathing room
      between the bottom row and the sheet's lower edge (the bottom tile no
      longer crowds the bottom edge).
- [ ] Tile dimensions (`MaintenanceTile` width × height, internal padding,
      aspect ratio) are unchanged from before this iteration.
- [ ] Column count is unchanged (2 columns, 5 tiles, last row has 1).
- [ ] Tile order is unchanged (Calendar → Stats → Exercise Library → Profile
      → Settings).
- [ ] The `HomeLogoButton` logo mark renders fully at the default text scale
      (no clip by the sheet edge or any other inset).
- [ ] The `HomeLogoButton` logo mark still renders fully at the largest
      supported system text scale (`textScaler = 1.6` per `MyApp` clamp).
- [ ] The sheet's `minChildSize` / `maxChildSize` snap positions still
      resolve correctly: collapsing snaps to `_minSheetExtent` (0.0),
      expanding snaps to `_maxSheetExtent` (≤ 0.86), and there is no
      half-open intermediate snap.
- [ ] No previously passing test fails (`flutter test`).

## Scenarios

### S-001: Hub sheet grid sits balanced (gap tightened)
- Trigger: User taps the top-left `HomeLogoButton` (or the handle) to open
  the Hub sheet.
- Precondition: Home screen is mounted with `extendBodyBehindAppBar: true`,
  `toolbarHeight: 60`, AppBar title = `HomeLogoButton`; Hub sheet is
  closed (at `_minSheetExtent` = 0.0).
- Flow:
  1. User taps the logo (or handle) to open the Hub sheet.
  2. `DraggableScrollableSheet` snaps to `_maxSheetExtent`.
  3. Sheet renders the handle, the `HUB` eyebrow text, and the 2-column
     grid of 5 `MaintenanceTile`s.
- Expected outcome: The vertical gap between the bottom of the `HUB` text
  and the top edge of the first tile row is shorter than before this
  iteration (the "empty band" the user reported is tightened). The grid is
  not pushed toward the bottom of the sheet — the bottom tile has visible
  breathing room below it. Tile sizes, columns, order, and arrangement are
  unchanged.
- Edge case of: none.

### S-002: Hub sheet does not clip the top-left logo
- Trigger: User opens the Hub sheet to `_maxSheetExtent`.
- Precondition: Home screen mounted as in S-001.
- Flow:
  1. User opens the Hub sheet.
  2. Sheet animates to its fully expanded position.
- Expected outcome: The `HomeLogoButton` logo mark in the AppBar renders
  fully — no part of the visible circle or its shadow is clipped by the
  sheet's top edge at the default text scale or at `textScaler = 1.6`.
- Edge case of: S-001.

## Iteration 1

> **TRIVIAL** — two surgical edits in `home_screen.dart` plus a small
> adjustment to `home_logo_button.dart`'s internal padding so the visible
> circle has even breathing room above the sheet's top edge. No model,
> repository, state, schema, navigation, theme-token, or service changes.

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

**File 1: `lib/features/home/home_screen.dart`** — `_buildMaintenanceSheet`

Two surgical changes inside the `SliverToBoxAdapter` that hosts the `HUB`
column and the surrounding padding (lines ~945–977):

1. **Reduce the gap between the `HUB` eyebrow and the grid.** Replace the
   current 16-px combined gap (8-px `Padding.bottom` on the HUB Column +
   8-px `SizedBox(height: 8)` inside the Column) with a tighter combined
   gap. The simplest equivalent is to keep the `Padding` 8/0/8/0 (drop the
   `SizedBox(height: 8)` and the bottom padding) so the grid sits ~16 px
   closer to the `HUB` text than before. The exact value is owned by this
   iteration; we will measure against the visual balance criterion in
   acceptance criteria, not a hard number.
2. **Use the actual `toolbarHeight` (60), not `kToolbarHeight` (56), in
   the `_maxSheetExtent` calculation** so the sheet's top edge lands at
   exactly the bottom of the AppBar on every screen size. Current code:
   ```dart
   _maxSheetExtent =
       ((mq.size.height - mq.padding.top - kToolbarHeight) / mq.size.height)
           .clamp(0.5, 0.86);
   ```
   Replace with:
   ```dart
   _maxSheetExtent =
       ((mq.size.height - mq.padding.top - kToolbarHeight) / mq.size.height)
           .clamp(0.5, 0.86);
   ```
   Wait — that line is unchanged. The real fix here is the *home logo
   button* bounding box (see file 2 below) so the visible circle does not
   extend below the AppBar's bottom edge.

**File 2: `lib/widgets/common/home_logo_button.dart`** — `HomeLogoButton`

Adjust the internal `Padding` around the tile so the visible 55×55 circle
sits with even, deliberate breathing room on all four sides instead of
1 px on the left and 4 px on the bottom. Specifically:

- Change `Padding(EdgeInsets.fromLTRB(1, 8, 8, 4))` to
  `Padding(EdgeInsets.all(8))` so the bounding box becomes 71×71 (8 px
  padding on every side) — this keeps the soft shadow fully off-screen
  edges and ensures the visible circle sits inside the AppBar's
  `toolbarHeight: 60` slot with equal margin on top and bottom.
- Drop the inner `Padding(EdgeInsets.only(right: 1))` since the
  symmetrical outer padding already centres the logo inside the circle.
  Keep the `Center(child: artwork)` wrapper.
- Update the existing widget doc comment to reflect the new bounding box
  (was 72×64 — the docs already claim 72×64, the actual code computes
  64×67; new code makes both 71×71 with consistent 8 px insets).

No changes to `tileSize`, `size`, `ColorFiltered` theme tint, press
reaction, accessibility (`Semantics`), or `ConstrainedBox` minimum hit
target.

### Implementation Steps

1. [x] Verify the gap-reduction math: at default text scale, current
      gap = 16 px (8 `SizedBox` + 8 bottom Padding); new target = ~0–4 px
      combined. `_buildMaintenanceSheet`'s `Padding(EdgeInsets.fromLTRB(20, 8, 20, 8))`
      around the `HUB` Column drops to `Padding(EdgeInsets.fromLTRB(20, 8, 20, 0))`
      and the inner `SizedBox(height: 8)` drops to `SizedBox(height: 0)`
      so the total gap becomes 0 (instead of 16). Implementation
      records the chosen values in the handoff so the reviewer can verify.
2. [x] Adjust `HomeLogoButton` `Padding` to `EdgeInsets.all(8)` and drop
      the inner `Padding(EdgeInsets.only(right: 1))`. Update the widget
      doc comment.
3. [x] Update the existing `home_logo_hub_open_test.dart` "logo tile has
      margin from the AppBar edges" test to assert the new bounding box
      (≥ 70×70 since 8 px all around a 55×55 tile = 71×71).
4. [x] Add new coverage in `home_logo_hub_open_test.dart`:
      - Hub sheet grid tile count + order at default text scale.
      - Hub sheet grid tile dimensions (width × height) at default text
        scale (regression — assert no change vs the pre-iteration
        baseline).
      - Hub sheet grid render at `textScaler = 1.6` (largest supported):
        each `MaintenanceTile` is found, no two tiles overlap, no tile
        is clipped by the sheet's bottom edge (measured against the
        sheet's `RenderBox` bounds).
      - Hub sheet snap positions: tapping the logo animates to
        `_maxSheetExtent`; the sheet's `minChildSize` / `maxChildSize`
        resolve to the documented 0.0 / ≤ 0.86 values; there is no
        half-open intermediate snap (the `_midSheetExtent` constant is
        no longer used — assert `snapSizes.length == 2`).
5. [x] Update widget docs: `widget_catalog/feature_primitives.md`
      `HomeLogoButton` section reflects the new 8-px padding and 71×71
      bounding box.
6. [x] Update widget docs: `widget_catalog/home_screen.md` notes the
      Hub sheet's tightened HUB-to-grid gap.
7. [x] Run `flutter test` and confirm all green.

## Progress
- [x] Phase 0: Plan written.
- [x] Phase 1: Data layer — N/A (no model/repo/schema changes).
- [x] Phase 2.1: Failing tests written (`home_logo_hub_open_test.dart`
      additions) and confirmed red against the pre-iteration source.
- [x] Phase 2.2: `_buildMaintenanceSheet` gap reduced
      (`Padding(fromLTRB(20, 8, 20, 8))` → `Padding(fromLTRB(20, 8, 20, 0))`,
      inner `SizedBox(height: 8)` → `SizedBox(height: 0)`).
- [x] Phase 2.3: `HomeLogoButton` `Padding(EdgeInsets.fromLTRB(1, 8, 8, 4))`
      → `Padding(EdgeInsets.all(8))`; inner `Padding(EdgeInsets.only(right: 1))`
      dropped; widget doc comment updated.
- [x] Phase 2.4: Tests green (`flutter test`).
- [x] Phase 2.5: Docs updated (`widget_catalog/feature_primitives.md`,
      `widget_catalog/home_screen.md`).
- [x] Phase 3: Code review complete.
- [x] Phase 3 follow-ups applied (review suggestions resolved):
      1. **`kToolbarHeight` → named `appBarToolbarHeight = 60.0` local**
         in `_buildMaintenanceSheet` (was review WARNING #1). The AppBar
         sets `toolbarHeight: 60`; the calculation previously used
         `kToolbarHeight = 56`, leaving a 4 px drift that made the sheet
         clip the bottom edge of the AppBar on some screen sizes.
      2. **`symmetryTolerancePx` named constant** replacing the bare
         `0.5` magic number in the "logo tile has even margin from the
         AppBar edges" test (was review WARNING #2). The constant has
         a comment explaining the sub-pixel-rounding rationale.
      3. **`LayoutBuilder` dropped from `MaintenanceTile._buildSurface`**
         (was review SUGGEST #1). The wrapper didn't read `constraints`,
         so it added an unnecessary layer of nesting; the `Flexible` +
         `maxLines: 2` + `overflow: TextOverflow.ellipsis` on the title
         `Text` handle overflow regardless of constraint size.
      4. **`_HubGridDelegateSpec`** value-object replacing the hard-coded
         baseline (`192 × 174.545`) in the "tile dimensions unchanged"
         test (was review SUGGEST #2). The expected tile dimensions are
         now derived from the surface size and the grid delegate config
         (crossAxisCount, crossAxisSpacing, childAspectRatio,
         horizontalPadding) — changing any of these inputs updates the
         assertion automatically instead of silently breaking the
         regression guard.
- [x] Phase 4 follow-up (user feedback "tiles still pushed down"):
      The first iteration only killed the HUB→grid side of the gap
      (16 px: SizedBox + bottom Padding). The handle→HUB side was left
      alone, so the user still saw ~20 px of empty space between the
      handle bar and the HUB label. The second pass cut that side too:
      - `_buildHandle` `EdgeInsets.only(bottom: 12 → 4)` — saves 8 px
      - HUB Column `EdgeInsets.fromLTRB(20, 8, 20, 0) → fromLTRB(20, 0, 20, 0)` — saves 8 px
      Total additional pull-up: **16 px**. The empty space between the
      handle bar and the first tile row is now ~18 px (down from
      ~34 px before this iteration).
- [x] Phase 5 follow-up (user feedback "tiles still low + handle too high"):
      The HUB→grid gap was already ≤ 4 px, but the screenshot showed an
      oversized sheet with the grid sitting in the upper-middle and a
      massive empty band below the last row. Root cause was the sheet's
      `maxChildSize` (`0.86`) leaving the sheet much taller than the
      5-tile grid needed. Three coupled changes address this:
      1. **Sheet extent clamp `0.86 → 0.76`** via new
         `const hubSheetMaxExtent = 0.76` in
         `_buildMaintenanceSheet`. The sheet stops growing past
         76% of screen height, which moves the grid from
         upper-middle-of-an-oversized-sheet to visually centred in
         a compact sheet. The snap-mechanism (drag, snap-to-extents)
         is unchanged; only the upper extent changes. The Phase 0
         "Hub sheet snap positions resolve correctly" test was
         tightened from `<= 0.86` to `<= 0.76`.
      2. **Handle top padding `4 → 20`** so the handle has
         breathing room below the AppBar instead of hugging the
         sheet's rounded top edge (the user reported "handle is now
         too high"). The visible circle still sits inside the
         AppBar's `toolbarHeight: 60` slot via the symmetric 8 px
         `Padding` inside `HomeLogoButton`.
      3. **Grid `SliverPadding` bottom `24 → 4`** so the bottom row
         (Settings) stops floating 24 px above the sheet's rounded
         bottom edge.
      Net effect: the grid is the dominant visual element of a
      compact sheet, the handle sits comfortably below the AppBar, and
      the bottom row has a small breathing gap above the sheet edge
      instead of a 24 px one.

## Feedback
(empty — adjust here if a phase is blocked)

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (N/A — no model/repo/schema changes)
### Phase 2 Complete ✓
### Phase 3 Complete ✓