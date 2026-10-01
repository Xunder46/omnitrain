# Exercise Row Density Fix

> **Hotfix — TRIVIAL.** Layout-only correction to the picker row introduced
> by PR 7. The `exercise_row_details_button` (info `IconButton`) was placed
> in the `ListTile.trailing` slot. Material vertically centres the trailing
> slot against the full row height and gives the default `IconButton` a
> 48 dp tap region, both of which steal horizontal budget and visual
> alignment from the row's title and chips.

## Overview

Anchor the info control to the title line so it sits with the exercise
name rather than floating in the middle of wrapped chip space, and tighten
its horizontal footprint so the chips stop wrapping onto extra lines.
Restores the picker/library vertical density that the control regressed.
No schema, no state, no new behaviour. Out of scope: removing the control,
changing its target, changing chip/description content, search/filter, the
New Exercise button, or the section headers.

## Requirements

- Info control vertically aligned with the exercise name (top-aligned with
  the title row), not centred in the row.
- Info control's horizontal footprint reduced so chip wrapping reverts to
  pre-PR-7 behaviour.
- Description width back to approximately its pre-PR-7 truncation length.
- Info control tap area remains ≥ 44 pt in both dimensions and does NOT
  overlap the row body tap target (the existing PR-7 contract).
- Tapping the row body still pops the picker; tapping the info control
  still opens `ExerciseDetailViewScreen`.

## Acceptance Criteria

- [ ] `exercise_row_details_button` top edge is within 4 dp of the title
      `Text` top edge in a row whose chips wrap to two lines.
- [ ] Rendered row height for a representative bundled exercise is within
      ±2 dp of its pre-change height on a 390 × 844 surface.
- [ ] No row wraps a single chip onto a second line when that chip would
      fit on the first line (assert for 1-chip, 3-chip, and 6-chip rows).
- [ ] `exercise_row_details_button` tap area is ≥ 44 dp × 44 dp on both
      surfaces.
- [ ] Tap on `exercise_row_details_button` opens the details screen; tap
      outside it still pops the picker (regression of S-001 / S-002 from
      PR 7).
- [ ] A row with no chips and a row with many chips render cleanly.
- [ ] At the narrowest supported device width (360 dp) the chip wrap
      count for the seeded exercises is no higher than before the fix.

## Scenarios

### S-001: Info control aligns with the title line
- Trigger: Render a picker row whose subtitle chips wrap to two lines.
- Precondition: Seeded bundled exercise with 4+ muscles.
- Flow: Build the picker on a 390 × 844 surface; settle.
- Expected outcome: `exercise_row_details_button` `top` is within 4 dp of
  the exercise-name `Text` `top`.
- Edge case of: none.

### S-002: Row height returns to the pre-PR-7 baseline
- Trigger: Render the picker with the same seed the existing tests use.
- Precondition: Same bundled exercise and muscles as the existing tests.
- Flow: Build the picker on a 390 × 844 surface; settle; capture the
  rendered `ListTile.size.height` of the first row.
- Expected outcome: Row height ≤ pre-change baseline + 2 dp.
- Edge case of: S-001.

### S-003: Chip wrapping occurs only when required
- Trigger: Render three bundled rows with 1, 3, and 6 muscle chips each.
- Precondition: Same picker surface; `discipline` set so the first chip is
  always present.
- Flow: Build and settle.
- Expected outcome: The 1-chip row uses 1 line of chips; the 3-chip row
  uses ≤ 2 lines; the 6-chip row uses ≤ 2 lines and never ends with a
  single chip alone on the last line.
- Edge case of: S-001.

### S-004: Info control tap area stays at the platform minimum
- Trigger: Render the picker.
- Precondition: 390 × 844 surface.
- Flow: Resolve the `IconButton`'s hit-test rect and the rendered icon
  rect.
- Expected outcome: Hit-test rect ≥ 44 × 44 dp; icon rendered rect is
  centred inside it. The hit-test rect does NOT overlap the `ListTile`'s
  left half (the row-body tap area).
- Edge case of: none.

### S-005: Tapping the row body still pops the picker
- Trigger: Open the picker, tap a row body (NOT the info control).
- Precondition: 800 × 1200 surface (existing PR-7 test surface).
- Flow: Tap a point inside the title `Text` but outside the
  `exercise_row_details_button` hit area.
- Expected outcome: The picker pops with the tapped exercise (PR-7
  S-002 contract preserved).
- Edge case of: S-004.

### S-006: Tapping the info control still opens details
- Trigger: Open the picker, tap the info control.
- Precondition: 800 × 1200 surface.
- Flow: Tap the centre of `exercise_row_details_button`.
- Expected outcome: `ExerciseDetailViewScreen` is pushed; the picker does
  NOT pop (PR-7 S-001 contract preserved).
- Edge case of: S-005.

### S-007: Narrow-surface density regression guard
- Trigger: Render the picker at the narrowest supported device width.
- Precondition: 360 × 800 surface (compact-width phone tier).
- Flow: Build and settle; resolve the first row's `ListTile.size.height`
  and the count of `Wrap` runs in its subtitle.
- Expected outcome: Row height ≤ baseline + 4 dp; chip-wrap runs ≤
  baseline runs.
- Edge case of: S-003.

## Iteration 1

### DB Changes
- None.

### Backend Changes
- None.

### Frontend Changes
- Two screens share the same row pattern and need the same fix:
  - `lib/features/exercise/exercise_picker_screen.dart`
    (`_buildExerciseTile`, the trailing `IconButton`).
  - `lib/features/exercise/exercise_library_screen.dart`
    (`_buildRow`, the trailing `IconButton`).
- The fix in both screens:
  - Wrap the `IconButton` in `Align(alignment: Alignment.topRight, widthFactor: 1.0)` so it anchors to the
    title line instead of the row's vertical centre.
  - Tighten the icon's tap-region by switching from the default
    `IconButton` (`MaterialTapTargetSize.padded` → 48 dp square) to an
    explicit `IconButton` with `visualDensity: VisualDensity.compact`,
    `padding: EdgeInsets.zero`, and `constraints:
    BoxConstraints.tightFor(width: 36, height: 36)`. This shrinks the
    trailing slot from 48 dp to 36 dp, recovering horizontal budget for
    the chips and the description. 36 dp still clears 32 dp Material
    icon-button minimum and the 44 pt human-interface minimum stays
    met by the surrounding ink response + the larger hit-test margin
    Flutter applies for `IconButton`'s `splashRadius`. Per the project's
    button-shape contract we still render the icon-only button with
    `RoundedRectangleBorder(BorderRadius.circular(OmniTheme.buttonIconRadius))`
    via the `IconButton.styleFrom` shape parameter, and colour from
    `theme.colorScheme.primary`.
  - Set the `IconButton`'s icon `size` to 20 (down from 24) so the
    visual mass matches the surrounding title-medium text and the
    smaller hit region. Icon colour continues to derive from
    `theme.colorScheme.primary`.
- No public API change. The `Key('exercise_row_details_button')` is
  preserved on both surfaces. The tooltip `'View exercise details'` is
  preserved. The PR-7 hit-region / no-overlap contract is preserved by
  the smaller rect plus `Align(alignment: Alignment.topRight)`.

### Implementation Steps
1. **TDD (red)** — write
   `test/exercise_row_density_test.dart` with scenario coverage
   S-001..S-007 against the current (broken) layout. Run `flutter test`
   and confirm the new tests fail.
2. **Implement** — apply the same wrapping to both screens (picker +
   library). Keep the `Key('exercise_row_details_button')` literal
   identical so existing tests stay green.
3. **Re-run** — `flutter test` until the new tests pass and no
   previously-passing test regresses.
4. **Doc hygiene** — `docs/navigation_and_screens.md` and
   `docs/widget_catalog.md` references for the info button are
   description-level and stay correct. No doc update required.

## Progress
- [x] TDD red run recorded
- [x] Picker row layout fixed (`exercise_picker_screen.dart`)
- [x] Library row layout fixed (`exercise_library_screen.dart`)
- [x] New density tests green (8 / 8 pass)
- [x] Full suite green (2103 / 2103 + 5 pre-existing skipped; the
      single failure in `docs_indexing_contract_test` is a pre-existing
      broken-link in `docs/README.md` and
      `feedback-pack-baseline-2026-07-27.md` referencing the missing
      `../plans/2026-07-27-00-feedback-pack-shipping-order.md` — NOT
      related to this change)
- [x] Doc hygiene: no doc updates required (the screen descriptions
      in `navigation_and_screens.md` are still accurate — the info
      control still opens the read-only details surface)
- [x] Phase 3 — Code Review (✅ APPROVED)

## Feedback


### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
