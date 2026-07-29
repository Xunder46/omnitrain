# PR 6: Routine and Session Entry Navigation

> **Priority 6 of 8 — Tier 3 intent correction.** Includes Item 9 (routine list opens routines) and Item 10 (new workout lands on session); ship together after PR 5.

## Overview

Stop guessing user intent: routine-card bodies open routine details rather than starting, and new workouts land on a neutral empty session rather than auto-opening the picker. Explicit one-tap routine start and equally weighted add-exercise/add-block choices preserve speed without hijacking navigation.

## Requirements

- Card body opens existing routine editor and creates no session.
- Separate non-overlapping start control retains existing start flow/warning.
- Remove card overflow; move confirmed named destructive delete to routine header.
- Delete routine only; preserve completed sessions/history/stats/PRs.
- All modality and Free Training starts land on session screen.
- Empty session shows equally weighted add exercise/add block.
- Existing block-header add remains direct to picker; routine-populated sessions bypass empty state.
- Preserve bottom Cancel/Save controls.

## Acceptance Criteria

- [x] Card opens routine with no session creation.
- [x] Distinct start control starts in one tap with non-overlapping hit area.
- [x] Overflow is absent; header delete names routine and states permanence.
- [x] Delete/cancel behave correctly and prior training analytics remain unchanged.
- [x] Bottom Cancel/Save and active-session warning remain unchanged.
- [x] Every modality/Free Training start lands on session, not picker.
- [x] Empty session renders equally weighted add-exercise/add-block actions.
- [x] Add exercise opens picker; add block uses existing creation behavior.
- [x] Block-header add stays direct; routine session never shows empty state.
- [x] Non-empty session/leave behavior is unchanged.
- [x] Add Exercise and Add Block are always-secondary OutlinedButtons
      regardless of session contents (S-005 follow-up).
- [x] Start control is a bare play glyph with no text label
        (S-006 follow-up).
- [x] Play glyph uses the theme accent colour, with no fill or border
        (S-006 follow-up).
- [x] Play glyph is vertically centred in the row, not stretched
        to the row's full height (S-006 follow-up).
- [x] Play glyph touch target is at least the platform minimum
        (S-006 follow-up).
- [x] Play glyph is no longer the largest touch target on the
        screen — the row body covers more area (S-006 follow-up).
- [x] "Demo" marker sits on the metadata line, not the title line
        (S-006 follow-up).
- [x] Routine names of typical length render in full on the
        narrowest supported device width (S-006 follow-up).
- [x] Start control tap region measures at least 44 pt in both
      dimensions (S-007 follow-up).
- [x] Play glyph visual size and appearance are unchanged from S-006
      (S-007 follow-up).
- [x] Start control tap region does not overlap the row body tap
      region (S-007 follow-up).
- [x] No point in a row is unresponsive — every tap either starts or
      opens (S-007 follow-up).
- [x] Demo badge occupies the same horizontal position on every row
      regardless of date text length (S-007 follow-up).
- [x] Rows without a Demo badge leave no visible gap or misalignment
      in the date line (S-007 follow-up).
- [x] Row height and spacing are unchanged (S-007 follow-up).
- [x] New Routine button is unchanged (S-007 follow-up).
- [x] Demo badge sits on the title row next to the routine name, not
      on the date line (S-008 follow-up).
- [x] Demo badge is vertically centred with the title text (S-008
      follow-up).
- [x] Demo badge text is vertically centred within its pill (S-008
      follow-up).
- [x] Metadata line returns to a simple `Row` layout (date text
      only, no Stack and no reserved space) (S-008 follow-up).
- [x] Demo badge horizontal position is still stable across rows
      regardless of name length (S-008 follow-up).
- [x] User rows render the title line + date line with no gap and no
      misalignment (S-008 follow-up).

## Scenarios

### S-001: Card opens; explicit control starts
- Trigger: Tap card body or start control.
- Precondition: Routine exists.
- Flow: Body→editor; control→existing start flow.
- Expected outcome: Only explicit start creates a session.
- Edge case of: none

### S-002: Delete preserves history
- Trigger: Confirm routine header delete.
- Precondition: Completed sessions reference routine.
- Flow: Delete routine hierarchy and refresh queries.
- Expected outcome: Routine disappears; sessions/values/stats/PRs are unchanged.
- Edge case of: none

### S-003: Empty workout asks rather than guesses
- Trigger: Start modality or Free Training.
- Precondition: Empty new session.
- Flow: Session screen → choose add exercise or block.
- Expected outcome: Both equal choices are available; picker opens only explicitly.
- Edge case of: none

### S-004: Explicit context stays direct
- Trigger: Block-header add or routine start.
- Precondition: Intent/content already exists.
- Flow: Block add→picker; routine→populated session.
- Expected outcome: No neutral empty choice interrupts.
- Edge case of: S-003

### S-005: Add Exercise and Add Block are always secondary
- Trigger: Add a block or an exercise to a fresh session.
- Precondition: Empty (or populated) session, both Add Exercise and Add Block are visible.
- Flow: Add content, observe button visual weight.
- Expected outcome: Neither button ever becomes a FilledButton (primary); both stay OutlinedButtons.
- Edge case of: none

### S-006: Start control shrinks to a bare play glyph; Demo marker moves
- Trigger: Render `MyRoutinesScreen` with multiple routines (typical and long names, mixed demo + user).
- Precondition: At least one user routine and one built-in demo routine exist; the screen fits a narrow phone width (320 dp).
- Flow: Inspect card chrome, locate the start control, tap the glyph, tap the card body.
- Expected outcome: Start control is a small play triangle (no text label, no fill, no border) using the theme accent colour, vertically centred in the row, with a touch target ≥ 48 dp; the "Demo" pill sits next to the creation date, not next to the title; routine names of typical length render in full on a 320-dp surface; tapping the glyph starts a session while tapping the row body opens the editor.
- Edge case of: S-001

### S-007: Tap region + Demo badge stability refinements
- Trigger: Render `MyRoutinesScreen` with three demo routines (short, medium, long date text) plus one user routine (no Demo badge) on a narrow phone width.
- Precondition: The list contains heterogeneous date strings; mixed demo + user routines.
- Flow: Measure the start control tap region, tap near its edges, tap into the row body, sample rows for badge horizontal alignment.
- Expected outcome: Start control tap region ≥ 44 dp in both dimensions (and comfortably larger than the visible glyph); no point in the row is unresponsive (every tap either starts or opens); the Demo badge sits at the same horizontal position on every row regardless of the date text length; user rows render the date line with no visible gap.
- Edge case of: S-006

### S-008: Demo badge moves back to the title row, vertically centred
- Trigger: Render `MyRoutinesScreen` with mixed demo + user routines.
- Precondition: The S-007 Stack-pinned metadata-line layout is in place.
- Flow: Inspect card chrome, locate the Demo badge, measure its vertical alignment with the title text.
- Expected outcome: The Demo badge sits on the title line next to the routine name (not on the date line). The badge's text is vertically centred within its pill, and the pill is vertically centred with the title text. The metadata line returns to its pre-S-007 simple `Row` layout (date text only, no reserved space).
- Edge case of: S-007

## Iteration 1

### DB Changes
None expected; verify routine delete cannot cascade into sessions.

### Backend Changes
- Reuse existing routine start/warning from explicit control.
- Ensure template-only deletion and historical resolution.

### Frontend Changes
- Separate card/open/start hit regions; remove overflow; add header delete.
- Redirect session creation to session screen and render balanced empty state.

### Implementation Steps
1. TDD card/open/start/delete/history.
2. TDD all session-entry and empty-state paths.
3. Implement routine navigation changes and session landing.
4. Rewrite stale card-start/picker-auto-open tests.
5. Run full suite.

## Unit Tests Required
- Card opens/no session; start control creates session.
- Delete/cancel and historical analytics invariants.
- Active-session warning remains.
- All creation paths land on session.
- Empty actions, block direct add, and routine bypass.
- List every rewritten stale expectation in review.

## Progress
- [x] TDD red run recorded (12 failing — all new tests red; no existing tests touched yet)
- [x] Phase 1 — Data Layer (N/A — verified template-only deletion; planned sessions cascade is intentional, completed sessions keep routineTemplateId by design)
- [x] Routine intent changes implemented (card open/start split, header delete)
- [x] Session landing/empty state implemented (no auto-open, balanced buttons)
- [x] Full suite green (2054 passing, 5 skipped, 0 failing — 12 PR 6 + 3 S-005 + 6 S-006 + 6 S-007 + 5 S-008 tests)
- [x] Phase 3 — Code Review
- [ ] Release-ready

## Feedback


### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 0.5 — TDD Red Run ✓

`test/pr6_routine_session_entry_navigation_test.dart` records 12 tests
that pin the contract. As of the red run before Phase 2 implementation:

- **0 passing, 12 failing** — every new test fails as expected because the
  PR 6 changes are not yet wired:
  - 4× S-001 — routine card intent split (body opens, start button
    distinct, overflow removed, header delete action present).
  - 2× S-002 — delete dialog names the routine and states permanence;
    confirmed delete removes template only and keeps completed-session
    history and routineTemplateId intact.
  - 4× S-003 — modality start lands on session screen with no picker
    pushed; Free Training start lands on session screen with no picker
    pushed; empty state renders equally weighted Add Exercise / Add
    Block; empty-state Add Exercise opens the picker only on tap.
  - 2× S-004 — block-header add routes straight to picker; routine-
    populated session bypasses the empty state and never shows the
    balanced buttons.

  Each failure points to a concrete code change in the next phase:
  routine card hit regions, picker auto-open gate, empty-state widget
  contract.

### Phase 2 ✓

Implementation landed in three files plus three test files:

- `lib/features/routine/my_routines_screen.dart` — replaced the
  `Card`+`ListTile`+`PopupMenuButton` layout with a new private
  `_RoutineCard` widget that exposes two non-overlapping hit regions:
  - `Key('routine-card-body')` — opens `RoutineSetupScreen` for the
    existing routine; no session is created.
  - `Key('routine-card-start')` — 96-dp `TextButton`, primary-tinted,
    utility-radius corners; creates the session in one tap using the
    existing `RoutineSessionService.buildSessionFromTemplate` +
    active-session warning flow.

  Extracted the destructive delete confirmation into a public
  `showDeleteRoutineDialog` helper so the wording is identical
  regardless of where it is invoked from. The dialog title is
  `Delete "<routine name>"?`, the body warns about permanence and
  planned-session cleanup, and the destructive Delete button uses
  `theme.colorScheme.error` / `onError` with the `routine-delete-confirm`
  key for tests.

- `lib/features/routine/routine_setup_screen.dart` — added a
  `_deleteCurrentRoutine` action that gates on `widget.templateId != null`
  (so new unsaved drafts never expose a destructive control) and pops
  without re-prompting after a successful delete. The header action
  uses `Icons.delete_outline` + `colorScheme.error`, keyed
  `routine-delete-action`. The destructive action is wired through
  the shared `showDeleteRoutineDialog` so its copy / layout matches
  the rest of the app.

- `lib/features/session/workout_session_screen.dart` — the picker
  auto-open gate (`_shouldAutoOpenPicker`) now always returns `false`
  per PR 6 / S-003; `_scheduleAutoOpenPicker` is a no-op that still
  flips the `_autoOpenAttempted` flag for any future re-introduction
  behind a flag.

- `lib/features/session/workout_session_list_view.dart` — added a
  `balanced` flag to `_buildAddExerciseAndBlockBar`. When `balanced`
  is true, the bar renders two equally weighted `OutlinedButton`s
  (Add Exercise + Add Block) with identical shape tokens, keyed
  `empty-add-exercise` / `empty-add-block` so tests can locate them.
  When `balanced` is false, the original primary-CTA layout is
  preserved for non-empty sessions (the bottom-of-list add bar).
  The standard-session empty-state branch also falls through to the
  populated path when `currentSession.routineTemplateId != null`, so
  routine-populated sessions never show the balanced empty state per
  PR 6 / S-004.

- `test/exercise_notes_sheet_test.dart`, `test/widget_test.dart`,
  `test/interaction_flow_test.dart`, `test/screen_widget_test.dart` —
  updated the four tests that explicitly tapped `Icons.arrow_back`
  to dismiss the auto-opened picker; those now assert that the
  picker is not in the tree on first load and tap the
  `OutlinedButton` "Add Exercise" to open it explicitly. The
  `MyRoutinesScreen interactions` delete test now opens the editor
  via the card body and uses the `routine-delete-action` /
  `routine-delete-confirm` keys instead of the removed overflow menu.

Green run: **2034 tests pass, 5 skipped, 0 failing.**

### S-005 follow-up (2026-07-28) ✓

User feedback: "the Add Exercise button turns primary" after adding a
block or an exercise. Removed the `balanced` flag from
`_buildAddExerciseAndBlockBar` — Add Exercise and Add Block are now
*always* secondary `OutlinedButton`s regardless of session contents.
The bottom Finish Workout CTA remains the only `FilledButton` in the
session screen.

- `lib/features/session/workout_session_list_view.dart` — collapsed the
  bar into a single branch with two `OutlinedButton`s keyed
  `add-exercise` / `add-block` (renamed from `empty-add-*` since the
  empty vs populated distinction no longer applies to the widget
  itself).
- `test/pr6_routine_session_entry_navigation_test.dart` — added a new
  S-005 group with three regression-guard tests (empty session, after
  adding a block, after adding an exercise) asserting Add Exercise and
  Add Block are `OutlinedButton`s and never `FilledButton`s. Updated
  S-003 / S-004 keys from `empty-add-*` to `add-*`.
- `docs/navigation_and_screens.md`, `docs/my_routines.md`,
  `docs/feedback-pack-baseline-2026-07-27.md` — added S-005 contract
  documentation.

Green run after S-005 follow-up: **2037 tests pass, 5 skipped, 0 failing.**

### S-006 follow-up (2026-07-28) ✓

User feedback: the card's start control was a 96-dp filled `TextButton`
with a "Start" label that ate ~25% of every row's width, eight routines
stacked read as a column of buttons, routine names were truncated to
"Bodyweight \u2026" / "Easy Run \u2014 3\u2026", and the start control was the
largest touch target on the screen — backwards for a control whose
purpose is to be deliberate.

Implementation changes in
`lib/features/routine/my_routines_screen.dart`:

- Replaced the 96-dp `TextButton("Start")` with a bare
  `SizedBox(width: 48, height: 48)` wrapping an `IconButton` whose
  `icon: Icon(Icons.play_arrow, color: theme.colorScheme.primary,
  size: 28)`. No text label, no fill, no border. Vertically centred
  in the row, touch target ≥ 48 dp (platform minimum).
- `IconButton.padding: EdgeInsets.zero` so the visual stays small
  inside the 48-dp box.
- Tooltip `'Start routine'` — semantic locator for accessibility and
  the S-006 tests.
- `Key('routine-card-start')` preserved so existing tests that locate
  the start control by key still work.
- Moved the `DemoRoutineBadge(compact: true)` off the title line onto
  the metadata line, alongside the creation-date text. The compact
  variant keeps the pill from crowding the date.
- Title line now hosts the routine name alone (no Row sibling), so
  the `Flexible`+`Text` pair renders the name in full on a 320-dp
  surface.

New tests in `test/pr6_routine_session_entry_navigation_test.dart`
(S-006 group, 6 tests, all green):

- `start control renders as a play triangle with no text label` —
  asserts `find.byIcon(Icons.play_arrow)` finds three glyphs (one per
  seeded routine) and `find.text('Start')` finds nothing.
- `play glyph uses the theme accent colour with no fill and no
  border` — inspects the `Icon` widget's colour and shadows.
- `play glyph touch target meets the platform accessibility minimum` —
  uses the new `tooltip: 'Start routine'` as the semantic locator and
  asserts the rect ≥ 48 dp on both axes.
- `play glyph is smaller than the row body touch region` — locks the
  "body covers more area than the glyph" regression guard from the
  user feedback.
- `Demo marker renders on the metadata line, not the title line` —
  asserts (a) the badge's `y` is below the title's bottom, (b) the
  badge's parent Row does NOT contain the title, (c) the badge's
  parent Row DOES contain the `Created \u2026` text.
- `routine names of typical length render in full on a 320-dp
  surface` — renders "Bodyweight Conditioning" on a 320-dp surface and
  asserts the rendered text is untruncated, with the very long name
  still truncated as a regression guard against overflow.

The `routine-card-body` `Key('routine-card-body')` and the
`routine-card-start` `Key('routine-card-start')` are preserved so
existing tests in `test/pr6_routine_session_entry_navigation_test.dart`
and `test/interaction_flow_test.dart` continue to work without
locator updates.

Docs updated:

- `docs/my_routines.md` — current-state boundary note flags the S-006
  contract (bare play glyph + Demo on metadata line + typical names
  render in full on 320-dp viewports).
- `docs/widget_catalog/feature_primitives.md` — `_RoutineCard` section
  rewritten for the S-006 layout (play glyph hit target, Demo on
  metadata line, compact badge variant, name-line restored).
- `docs/navigation_and_screens.md` — full screen-flow diagram's
  My Routines branch references the S-006 play glyph.
- `docs/feedback-pack-baseline-2026-07-27.md` — new "Routine card
  start control dominates the row" row + cross-reference to the
  S-005 row for the session-screen add buttons.

No golden or snapshot tests exist for the routines list (grep
`matchesGoldenFile` finds none), so no regeneration is required.

Green run after S-006 follow-up: **2043 tests pass, 5 skipped, 0 failing.**

### S-007 follow-up (2026-07-28) ✓

Two refinements to the S-006 layout: a larger tap region for the start
control, and a Stack-pinned Demo badge so its horizontal position is
identical across rows regardless of date text length.

Code changes:

- `lib/core/constants/omni_theme.dart` — added
  `OmniTheme.demoBadgeReservedWidth = 64.0` token. Documents the
  measured width of the compact `DemoRoutineBadge` plus the 8-dp
  inner gap so the date text can reserve exactly the right amount
  of horizontal space when the badge is present.
- `lib/features/routine/my_routines_screen.dart` — two edits in
  `_RoutineCard`:
  - `SizedBox(width: 48, height: 48)` → `SizedBox(width: 56, height: 56)`
    around the play `IconButton`. The visible glyph is unchanged
    (`Icons.play_arrow` `size: 28`); only the tap region grows so a
    hurried or off-centre tap still hits the start control reliably.
  - Metadata line rebuilt as `SizedBox(height: 18, child: Stack(...))`
    so the `DemoRoutineBadge` is `Positioned` at the right edge of
    the line. The date text uses
    `Padding(right: OmniTheme.demoBadgeReservedWidth)` only when the
    routine carries the demo badge — user rows render the date
    full-width with no reserved gap. The `Stack` is clipped to
    `Clip.none` so the badge can render slightly outside the line
    bounds if needed.

Tests added in `test/pr6_routine_session_entry_navigation_test.dart`
(S-007 group, 6 tests, all green):

- `start control tap region is at least 44 dp in both dimensions and
  visibly larger than the glyph it represents` — measures
  `Key('routine-card-start')` rect (≥ 44 dp both axes) AND asserts
  the tap rect strictly contains the visible glyph rect.
- `tap near the edge of the start control region hits the start
  control (does not fall through to the row body)` — taps 2 dp from
  the trailing edge of the tap region; asserts the routine editor
  did NOT open (the tap landed on the start control, not the body).
- `tap just outside the start control region opens the routine` —
  taps 2 dp to the LEFT of the start control's left edge; asserts
  the routine editor opened (the tap landed on the body).
- `no point in a row is unresponsive — taps at sampled positions
  either hit the start control or the row body` — five x-positions
  across the full row width; for each, fresh-pump, classify inside
  vs outside the start control region, assert the matching
  destination fired. Locks the no-dead-zone contract.
- `Demo badge sits at the same horizontal position on every row
  regardless of date text length` — seeds three demo routines with
  `today` / `5 days ago` / `3 weeks ago` dates (different text
  lengths); asserts every badge's centre x and left x match within
  0.5 dp tolerance.
- `user row (no Demo badge) renders the date line with no visible
  gap` — asserts the user row's date text reaches as far right as
  any demo row's badge left edge, proving no reserved gap on user
  rows.

The S-006 "Demo marker renders on the metadata line, not the title
line" test was updated to look for the badge's parent `Stack` (which
contains the date) instead of the badge's parent `Row`. The badge is
now a `Positioned` child of the metadata-line `Stack`, not a Row
sibling.

Docs updated:

- `docs/widget_catalog/feature_primitives.md` — `_RoutineCard`
  section rewritten for the S-006 + S-007 layout (56-dp tap region,
  `Stack`-pinned badge, `OmniTheme.demoBadgeReservedWidth`).
- `docs/my_routines.md` — current-state boundary note flags the
  S-007 contract; `Editing a Routine` section mentions the 56 dp
  tap region around the 28 dp visible glyph and the Stack-pinned
  Demo badge.
- `docs/feedback-pack-baseline-2026-07-27.md` — added an "Start
  control tap region too tight / Demo badge ragged" row pinned to
  the routine-cards row, summarising the S-007 refinement.

No golden or snapshot tests exist for the routines list, so no
regeneration is required.

Green run after S-007 follow-up: **2049 tests pass, 5 skipped, 0 failing.**

### S-008 follow-up (2026-07-28) ✓

User feedback (pivot): the Demo badge should sit on the TITLE row
next to the routine name, vertically centred with the title text, not
on the metadata line. The metadata line returns to a simple `Text`
widget — no Stack, no Positioned, no reserved space. The S-008 design
reverts the metadata-line placement because the start control is now
small enough (56-dp tap region around a 28-dp glyph) for the title row
to host the badge without crowding the routine name.

Code changes in `lib/features/routine/my_routines_screen.dart`:

- The metadata line is reduced from a `SizedBox(height: 18, child:
  Stack(...))` (PR 6 / S-007) back to a single `Text` widget (the
  pre-S-006 form). The Demo badge is no longer pinned to the
  metadata line.
- The title line is now `Row(crossAxisAlignment: CrossAxisAlignment.center,
  children: [Expanded(child: Text(name, ellipsis)), if (demo)
  SizedBox(width: 8), DemoRoutineBadge(compact: true)])`. The title
  text sits in an `Expanded` (FlexFit.tight) so the badge's right
  edge is pinned to the title row's right edge regardless of how
  long the routine name happens to be. Using `Flexible` (loose)
  would shrink-fit the row to the Text's natural width and pull the
  badge inwards on short names — this is locked in by an explicit
  comment and exercised by the S-007 horizontal-stability test which
  now seeds heterogeneous TITLE lengths instead of date lengths.
- `lib/core/constants/omni_theme.dart` — removed the
  `OmniTheme.demoBadgeReservedWidth = 64.0` token that the S-007
  Stack-based layout needed. The metadata line is back to a simple
  `Text` widget, so the reserved-width constant has no caller.

Tests added / updated in
`test/pr6_routine_session_entry_navigation_test.dart`:

- **S-006 "Demo marker" test inverted:** was asserting the badge
  sits on the metadata line; now asserts (a) the badge sits on the
  title row (badge.top ≤ title.bottom and badge.bottom ≥
  title.top), (b) the badge is vertically centred with the title
  text (badge centre y within the title height band), (c) the badge
  shares an IMMEDIATE Row parent with the title text, (d) the
  badge does NOT share a Row parent with the date text.
- **S-007 "Demo badge sits at the same horizontal position" test
  retargeted:** now seeds heterogeneous TITLE lengths (`Push` /
  `Bodyweight Conditioning` / `Full Body Hypertrophy Push Pull Legs
  with accessories`) instead of heterogeneous date lengths, and
  asserts every badge's `center.dx` and `left` match within 0.5 dp
  tolerance — i.e. the badge is pinned to the title row's right
  edge via the `Expanded` wrapper.
- **S-007 "user row no gap" test retargeted:** the user row's date
  line is now a plain `Text` widget with no Stack / Positioned /
  reserved padding. The test verifies (a) the user row's title
  parent Row does not contain a Demo badge, (b) the user row's date
  line's parent Row does not contain a Stack.
- **New S-008 group (5 tests, all green):**
  1. `Demo badge sits on the title row next to the routine name`
     — walks the title text's parent Row, asserts it contains a
     Demo badge.
  2. `Demo badge is vertically centred with the title text` —
     asserts badge.top ≤ title.bottom, badge.bottom ≥ title.top,
     and `(badge centre y − title centre y).abs ≤ title.height / 2 + 4`.
  3. `Demo badge text is vertically centred within the pill` —
     asserts the badge's vertical padding is symmetric (top ==
     bottom) and the text is centred within the pill (topGap ==
     bottomGap within ±2 dp).
  4. `metadata line uses a simple Row (no Stack, no reserved
     space)` — asserts the date text's parent Column contains no
     Stack, no Positioned, and no `DemoRoutineBadge` as a DIRECT
     child (the badge is on the title Row, not a sibling of the date
     in the column).
  5. `user row title line is clean (no Demo badge, no reserved
     space)` — asserts the user row's title parent Row contains no
     Demo badge and the user row's date line's parent Row contains
     no Stack.

Docs updated:

- `docs/widget_catalog/feature_primitives.md` — `_RoutineCard`
  section rewritten for the S-008 layout (Demo badge on title row,
  `Expanded` for tight-fit title text, vertical-centring guarantee).
- `docs/my_routines.md` — current-state boundary note mentions the
  S-008 contract; `Editing a Routine` section describes the title-row
  badge placement and the `Expanded` tight-fit pattern.
- `docs/feedback-pack-baseline-2026-07-27.md` — routine-cards row
  extended with the S-008 design-pivot paragraph.

No golden or snapshot tests exist for the routines list, so no
regeneration is required.

Green run after S-008 follow-up: **2054 tests pass, 5 skipped, 0 failing.**

### S-008 Phase 3 — Code Review ✓

Layers in scope: features (routine), widgets (card), core (constants).
Layers skipped: models, repositories, state, docs.

Acceptance criteria verification:

| AC | Status | Evidence |
|---|---|---|
| Demo badge on title row next to routine name | ✅ | `test/pr6...test.dart` S-008 #1 — title text's parent Row contains a `DemoRoutineBadge`. S-006 Demo marker test also asserts (a)-(d) on the badge's Row parent. |
| Badge vertically centred with title text | ✅ | `test/pr6...test.dart` S-008 #2 — badge.top ≤ title.bottom, badge.bottom ≥ title.top, badge centre y within title height band. |
| Badge text vertically centred within pill | ✅ | `test/pr6...test.dart` S-008 #3 — padding top == bottom, topGap == bottomGap within ±2 dp. |
| Metadata line is simple `Row` (no Stack, no reserved space) | ✅ | `test/pr6...test.dart` S-008 #4 — date's parent Column contains no Stack, no Positioned, and no `DemoRoutineBadge` direct child. |
| Demo badge horizontal position stable across rows regardless of name length | ✅ | `test/pr6...test.dart` S-007 (retargeted to seed heterogeneous TITLE lengths) — every badge's `center.dx` and `left` match within 0.5 dp. The `Expanded` (FlexFit.tight) wrapper around the title text pins the badge to the row's right edge. |
| User rows render title + date lines with no gap / misalignment | ✅ | `test/pr6...test.dart` S-008 #5 — user row's title parent Row has no Demo badge; user row's date parent Row has no Stack. |

Scenario register cross-check:

| Scenario | Test | Result |
|---|---|---|
| S-008 #1 | `test/pr6_routine_session_entry_navigation_test.dart` S-008 group, first test | ✅ |
| S-008 #2 | S-008 group, second test | ✅ |
| S-008 #3 | S-008 group, third test | ✅ |
| S-008 #4 | S-008 group, fourth test | ✅ |
| S-008 #5 | S-008 group, fifth test | ✅ |

Doc hygiene:

| Doc | Status |
|---|---|
| my_routines.md | ✅ Updated — current-state boundary note flags the S-008 contract; `Editing a Routine` section describes the title-row badge and `Expanded` tight-fit pattern. |
| navigation_and_screens.md | ✅ N/A — no nav-flow change; My Routines branch is at the S-006 level. |
| widget_catalog/feature_primitives.md | ✅ Updated — `_RoutineCard` section rewritten for the S-008 layout. |
| feedback-pack-baseline-2026-07-27.md | ✅ Updated — S-008 design-pivot paragraph appended to the routine-cards row. |
| state_management.md | ✅ N/A — no state class changes. |
| data_models.md | ✅ N/A — no model changes. |
| db_integration.md | ✅ N/A — no repository / schema changes. |

Global conventions:

- PASS (7 rules): repository-only dependency from state (no change to
  RoutineState in S-008); environment portability (no `dart:io`, no
  `Platform.is*`); theme tokens (removed `demoBadgeReservedWidth`
  rather than leaving it dead — the S-008 layout doesn't need it);
  reuse of canonical owner (`Expanded` + the existing
  `buttonPrimaryHeight` / `buttonIconSize` tokens); effort-kind
  analytics (no changes); timestamps as source data (no changes);
  no business logic in widgets (the badge is just a Row sibling).
- N/A (2 rules): units (no unit-edited values flow through this PR);
  effort-kind classification (no analytics rekeying).
- FAIL: none.

Architecture compliance:

- Features: changes confined to `MyRoutinesScreen`'s private
  `_RoutineCard` widget. Constructor signature unchanged. ✅
- Widgets: `_RoutineCard` is a private widget with local theme +
  callbacks; no state mutation outside the widget, no repository
  access, pure presentation. ✅
- Core: `OmniTheme.demoBadgeReservedWidth` removed (no callers).
  The constant was added in S-007 and is now obsolete. ✅
- Models / Repositories / State: untouched. ✅

Buttons (every screen touched):

- The play glyph remains `IconButton` (no `FilledButton` /
  `OutlinedButton` / `TextButton`); no button-shape regressions.
- No new button introduced.
- `MyRoutinesScreen`'s `+ New Routine` `OmniBottomCTA` is unchanged.

Dead code: no new dead code introduced. The S-007 Stack-pinned
metadata-line structure was removed in the same edit that moved the
badge back to the title row. The `OmniTheme.demoBadgeReservedWidth`
constant was removed.

Test coverage: 5 new S-008 tests cover every AC. The
horizontal-stability test was retargeted to seed heterogeneous TITLE
lengths (not date lengths) since the badge is now on the title
row. The S-006 Demo marker test was inverted to assert the badge is
on the title row instead of the metadata line. The S-007
user-row-no-gap test was retargeted to verify the user row's date
line has no Stack / Positioned structure.

🟢 APPROVED — Pipeline complete. Ready to merge.

### S-007 Phase 3 — Code Review ✓

Layers in scope: features (routine), widgets (card), core (constants).
Layers skipped: models, repositories, state, docs.

Acceptance criteria verification:

| AC | Status | Evidence |
|---|---|---|
| Tap region ≥ 44 pt in both dimensions | ✅ | `test/pr6...test.dart` S-007 #1 — `startRegion.width/height >= 44.0` against the `SizedBox(56, 56)` `Key('routine-card-start')`. |
| Visible play glyph unchanged | ✅ | `Icon(Icons.play_arrow, size: 28)` is identical to S-006; only the wrapper `SizedBox` was bumped from 48 to 56. No test or doc references the visual glyph size. |
| Tap region does not overlap the row body | ✅ | `SizedBox(56, 56)` is a sibling of `Expanded(InkWell)` in the outer `Row`. Hit regions are non-overlapping columns by construction; re-asserted by S-007 #4 (no point in a row is unresponsive). |
| Every point triggers either start or open | ✅ | `test/pr6...test.dart` S-007 #4 samples 5 x-positions across the row at the centre y and asserts each tap fires either `onStart` (no editor) or `onOpen` (editor opens). |
| Demo badge stable horizontal position across rows | ✅ | `test/pr6...test.dart` S-007 #5 seeds heterogeneous date lengths (`today`, `5 days ago`, `3 weeks ago`) and asserts every badge's `center.dx` and `left` match within 0.5 dp. The Stack's `Positioned(right: 0, ...)` pins the badge to the line's right edge. |
| User row renders date line without visible gap | ✅ | `test/pr6...test.dart` S-007 #6 asserts the user row's date reaches as far right as any demo row's badge left edge. The conditional `Padding(right: isBuiltInDemo ? OmniTheme.demoBadgeReservedWidth : 0)` reserves space only when the badge is present. |
| Row height and spacing unchanged | ✅ | `IntrinsicHeight` still sizes the row by the body's intrinsic height; the S-007 `SizedBox(56, 56)` for the start control is inside the row's existing cross-axis, and the metadata line's `SizedBox(height: 18)` matches the `labelMedium` line height used before. No `Padding` additions that would inflate row height. |
| New Routine button unchanged | ✅ | `lib/features/routine/my_routines_screen.dart` `_MyRoutinesScreenState.build` still wraps `OmniBottomCTA(label: '+ New Routine', …)`. No change. |

Scenario register cross-check:

| Scenario | Test | Result |
|---|---|---|
| S-007 #1 | `test/pr6_routine_session_entry_navigation_test.dart` S-007 group, first test | ✅ |
| S-007 #2 | S-007 group, second test | ✅ |
| S-007 #3 | S-007 group, third test | ✅ |
| S-007 #4 | S-007 group, fourth test | ✅ |
| S-007 #5 | S-007 group, fifth test | ✅ |
| S-007 #6 | S-007 group, sixth test | ✅ |

Doc hygiene:

| Doc | Status |
|---|---|
| my_routines.md | ✅ Updated — current-state boundary note mentions the 56 dp tap region and Stack-pinned badge. |
| navigation_and_screens.md | ✅ N/A — no nav-flow change; My Routines branch is already at the S-006 level. |
| widget_catalog/feature_primitives.md | ✅ Updated — `_RoutineCard` section rewritten with the S-007 hit-region contract. |
| feedback-pack-baseline-2026-07-27.md | ✅ Updated — S-007 row added to the routine-cards cell. |
| state_management.md | ✅ N/A — no state class changes. |
| data_models.md | ✅ N/A — no model changes. |
| db_integration.md | ✅ N/A — no repository / schema changes. |

Global conventions:

- PASS (7 rules): repository-only dependency from state (no change to
  RoutineState in S-007); environment portability (no `dart:io`, no
  `Platform.is*`); theme tokens (`OmniTheme.demoBadgeReservedWidth`
  is the single source of truth for the reserved width); reuse of
  canonical owner (`OmniTheme.buttonPrimaryHeight` + the new
  `demoBadgeReservedWidth` token alongside the existing button-size
  tokens); effort-kind analytics (no changes); timestamps as source
  data (no changes); no business logic in widgets (the Stack is pure
  layout).
- N/A (2 rules): units (no unit-edited values flow through this PR);
  effort-kind classification (no analytics rekeying).
- FAIL: none.

Architecture compliance:

- Features: changes confined to `MyRoutinesScreen`'s private
  `_RoutineCard` widget. Constructor signature unchanged. ✅
- Widgets: `_RoutineCard` is a private widget with local theme +
  callbacks; no state mutation outside the widget, no repository
  access, pure presentation. ✅
- Core: `OmniTheme.demoBadgeReservedWidth` added as a single new
  constant alongside the existing button-size tokens. ✅
- Models / Repositories / State: untouched. ✅

Buttons (every screen touched):

- The play glyph remains `IconButton` (not `FilledButton` /
  `OutlinedButton` / `TextButton`); no button-shape regressions.
- No new button introduced.
- `MyRoutinesScreen`'s `+ New Routine` `OmniBottomCTA` is unchanged.

Dead code: no new dead code introduced. The previous `Flexible`
+ `if (demo) SizedBox + Badge` metadata-line structure was removed in
the same edit that introduced the `Stack`-pinned layout. The
`Row`-based badge assertion in the S-006 Demo marker test was
updated to walk to the new `Stack` parent.

Test coverage: 6 new S-007 tests cover every AC. The tap-edge /
tap-just-outside pair (S-007 #2 and #3) explicitly verify the
two-region hit-area contract — the regression the user called out
("tap either starts or opens, never lands somewhere ambiguous"). The
no-dead-zone test (S-007 #4) samples the full row width and locks the
regression guard. The badge horizontal-stability test (S-007 #5)
seeds heterogeneous date strings and asserts pixel-level alignment.

🟢 APPROVED — Pipeline complete. Ready to merge.

### Phase 3 — Code Review ✓

Layers in scope: features (routine + session), widgets (card), docs.
Layers skipped: models, repositories, core, state.

Acceptance criteria verification:

| AC | Status | Evidence |
|---|---|---|
| Card opens routine with no session creation | ✅ | `test/pr6..._test.dart:130` (S-001 #1) — taps body, expects `RoutineSetupScreen` and asserts no `ExercisePickerScreen`. |
| Distinct start control with non-overlapping hit area | ✅ | `test/pr6..._test.dart:160` (S-001 #2) — asserts `startRect.overlaps(cardRect) == false`. |
| Overflow is absent; header delete names routine and states permanence | ✅ | `test/pr6..._test.dart:190` (S-001 #3) — no `PopupMenuButton`. `test/pr6..._test.dart:240` (S-002 #1) — `find.text('Delete "PR6 Routine"?')` + `cannot be undone`. |
| Delete preserves completed-session history / stats / PRs | ✅ | `test/pr6..._test.dart:280` (S-002 #2) — template gone, session intact with `routineTemplateId` + non-null `endedAtMs`. |
| Bottom Cancel/Save and active-session warning remain unchanged | ✅ | `_showFinishSessionDialog`, `_attemptExit`, and the active-session "Start New Session?" dialog are untouched. |
| Every modality / Free Training start lands on session, not picker | ✅ | `test/pr6..._test.dart:340, 380` (S-003 #1, #2) — no `ExercisePickerScreen` on first load. |
| Empty session renders equally weighted add-exercise / add-block actions | ✅ | `test/pr6..._test.dart:415` (S-003 #3) — both buttons are `OutlinedButton`, Add Exercise above Add Block, both above Finish Workout. |
| Add exercise opens picker; add block uses existing creation behavior | ✅ | `test/pr6..._test.dart:465` (S-003 #4) — tapping Add Exercise opens the picker. Add Block still calls `workoutState.addSessionBlock`. |
| Block-header add stays direct; routine session never shows empty state | ✅ | `test/pr6..._test.dart:500` (S-004 #1) — block-header `Icons.add` `IconButton` (tooltip "Add exercise to block") opens the picker. `test/pr6..._test.dart:530` (S-004 #2) — routine session with empty exercises still has no `empty-add-exercise` / `empty-add-block` keys. |
| Non-empty session / leave behavior is unchanged | ✅ | All previously passing session tests (`test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/widget_test.dart`) still pass. |

Scenario register cross-check:

| Scenario | Test | Result |
|---|---|---|
| S-001 #1 | `test/pr6_routine_session_entry_navigation_test.dart` S-001 group, first test | ✅ |
| S-001 #2 | S-001 group, second test | ✅ |
| S-001 #3 | S-001 group, third test | ✅ |
| S-001 #4 | S-001 group, fourth test | ✅ |
| S-002 #1 | S-002 group, first test | ✅ |
| S-002 #2 | S-002 group, second test | ✅ |
| S-003 #1 | S-003 group, first test | ✅ |
| S-003 #2 | S-003 group, second test | ✅ |
| S-003 #3 | S-003 group, third test | ✅ |
| S-003 #4 | S-003 group, fourth test | ✅ |
| S-004 #1 | S-004 group, first test | ✅ |
| S-004 #2 | S-004 group, second test | ✅ |

Doc hygiene:

| Doc | Status |
|---|---|
| my_routines.md | ✅ Updated — current-state boundary note flipped to "shipped"; `Editing a Routine` and `Deleting a Routine` rewritten to reflect the PR 6 contract. |
| navigation_and_screens.md | ✅ Updated — full screen-flow diagram patched (modality tile branch, My Routines branch, Free Training branch) plus the previous "Scheduled, not current" callout flipped to "PR 6 (shipped 2026-07-27)". |
| widget_catalog/feature_primitives.md | ✅ Updated — new section documents the private `_RoutineCard` widget with the two hit-region keys. |
| widget_catalog/layout_and_inputs.md | ✅ Updated — `OmniBackHeader` usage notes now mention the routine-editor delete icon. |
| state_management.md | ✅ N/A — no state class added; existing `RoutineState` extended with PR 5 baseline hooks that this PR reuses. |
| data_models.md | ✅ N/A — no model changes. |
| db_integration.md | ✅ N/A — no repository / schema changes. |

Global conventions:

- PASS (7 rules): repository-only dependency from state (no change to
  RoutineState / WorkoutState in PR 6); environment portability (no
  `dart:io`, no `Platform.is*`); theme tokens (all new buttons derive
  shape from `OmniTheme.buttonUtilityRadius` / `buttonBorderRadius`
  and colors from `theme.colorScheme`); reuse of canonical owner
  (`showDeleteRoutineDialog` lives in `my_routines_screen.dart` next
  to the dialog pattern it mirrors); effort-kind analytics (no
  changes — PR 6 is a navigation/UI pass); timestamps as source
  data (no time-derived fields changed); no business logic in widgets
  (delete confirmation is in the dialog helper, not in the card).
- N/A (2 rules): units (no unit-edited values flow through this PR);
  effort-kind classification (no analytics rekeying).
- FAIL: none.

Architecture compliance:

- Models: untouched. ✅
- Repositories: untouched. PR 6 does not change any
  `WorkoutRepository` interface method; the existing template-only
  delete + planned-session cascade is reused. ✅
- State: untouched. `RoutineState.deleteRoutine` is reused; no new
  state class added. ✅
- Features: changes are constrained to `MyRoutinesScreen`,
  `RoutineSetupScreen`, and the session-screen list view. Both
  consume state via constructor injection. `ListenableBuilder`
  still drives reactivity in `MyRoutinesScreen`. ✅
- Widgets: `_RoutineCard` is a private widget with local `theme` /
  `onOpen` / `onStart` callbacks; no state mutation outside the
  widget, no repository access, pure presentation. ✅
- Core: untouched. ✅

Buttons (every screen touched):

- `my_routines_screen.dart`: Start `TextButton` has explicit
  `RoundedRectangleBorder` with `buttonUtilityRadius` corners.
  Cancel / Delete `TextButton` + `FilledButton` in
  `showDeleteRoutineDialog` both have explicit
  `OmniTheme.buttonUtilityRadius` shapes.
- `routine_setup_screen.dart`: header delete `IconButton` (icon
  only — not a button).
- `workout_session_list_view.dart`: `balanced: true` branch uses
  two `OutlinedButton`s with explicit `RoundedRectangleBorder` +
  `buttonBorderRadius` shape; `balanced: false` branch keeps the
  existing primary-CTA `FilledButton` + `OutlinedButton` pattern.

Dead code: no new dead code introduced. The old
`_confirmDelete(BuildContext, String)` method on
`MyRoutinesScreen` was removed in the same edit that introduced
`_RoutineCard`. `RoutineState.countPlannedSessionsForTemplate`
remains used by `showDeleteRoutineDialog`.

Test coverage: 12 new tests (S-001 × 4, S-002 × 2, S-003 × 4, S-004 ×
2) cover every scenario in the register. The two round-trip
checks (template removed + session intact) cover the S-002
historical-analytics invariant. No public method added without a
happy-path test.

🟡 SUGGEST 1: `lib/features/session/workout_session_list_view.dart:454`
— the routine-populated fall-through to the populated path leaves an
empty `ListView` between the header and the bottom CTA. Consider
showing the routine's name in the header subtitle in that fallback so
the user has context. Non-blocking — the routine name already appears
in the page chrome via `currentSession.title` and the Session Time
chip.

🟡 SUGGEST 2: `test/pr6_routine_session_entry_navigation_test.dart:280`
— the S-002 historical-analytics invariant could also assert that the
session's `efforts` / `observations` / `rests` are intact (not just
the session row). Current coverage is sufficient because
`MockWorkoutRepository.deleteTemplate` only touches template rows,
but adding a session-effort-presence assertion would lock that
invariant at the test boundary. Non-blocking.

🟢 APPROVED WITH SUGGESTIONS — Pipeline complete.

### Phase 2 ✓

### S-006 Phase 3 — Code Review ✓

Layers in scope: features (routine), widgets (card).
Layers skipped: models, repositories, core, state, docs.

Acceptance criteria verification:

| AC | Status | Evidence |
|---|---|---|
| Start control renders as a play triangle with no accompanying text label | ✅ | `test/pr6...test.dart` S-006 #1 — `find.byIcon(Icons.play_arrow)` finds 3 glyphs, `find.text('Start')` finds nothing. |
| Play triangle uses the theme's accent colour | ✅ | `test/pr6...test.dart` S-006 #2 — `glyph.color` is non-null and derived from `theme.colorScheme.primary`. |
| No filled background and no visible border | ✅ | `Icon` has no `shadows` and no `decoration`; the surrounding `Material` (clipBehavior + borderRadius) does not extend to the glyph because the glyph is a sibling of the card body, not a child of it. |
| Vertically centred within the row | ✅ | `IconButton` inside `SizedBox(48, 48)` inside `IntrinsicHeight` `Row` (stretch axis) — the SizedBox doesn't expand, so the glyph sits at its natural position centred vertically. |
| Touch target ≥ platform accessibility minimum | ✅ | `SizedBox(width: 48, height: 48)` wrapper guarantees the layout size, even when `MaterialTapTargetSize.padded` would otherwise produce 44 dp. Asserted by S-006 #3. |
| Touch target smaller than the row body | ✅ | Asserted by S-006 #4 — `glyphRect.width * glyphRect.height < bodyRect.width * bodyRect.height`. |
| Demo marker on the metadata line, not the title line | ✅ | Asserted by S-006 #5 — badge `y` > title bottom, badge's parent Row contains the date and not the title. |
| Routine names of typical length render in full | ✅ | Asserted by S-006 #6 — "Bodyweight Conditioning" renders untruncated on a 320-dp surface; the very long name still truncates (regression guard). |
| Tapping play triangle starts a workout | ✅ | Preserved by `IconButton.onPressed: onStart` — the same closure that previously powered the 96-dp `TextButton`. |
| Tapping row body opens the routine screen | ✅ | `routine-card-body` `InkWell.onTap: onOpen` is untouched; all S-001 tests for this behaviour still pass. |
| Play triangle hit area does not overlap the row body | ✅ | The `SizedBox(width: 48, height: 48)` is a sibling of the `Expanded` body in the outer `Row`. The two hit regions are non-overlapping columns by construction (re-asserted by the S-006 #4 body-wins area check). |
| New Routine button unchanged | ✅ | `lib/features/routine/my_routines_screen.dart` `_MyRoutinesScreenState.build` still wraps an `OmniBottomCTA(label: '+ New Routine', …)`. No change to that block. |

Scenario register cross-check:

| Scenario | Test | Result |
|---|---|---|
| S-006 #1 | `test/pr6_routine_session_entry_navigation_test.dart` S-006 group, first test | ✅ |
| S-006 #2 | S-006 group, second test | ✅ |
| S-006 #3 | S-006 group, third test | ✅ |
| S-006 #4 | S-006 group, fourth test | ✅ |
| S-006 #5 | S-006 group, fifth test | ✅ |
| S-006 #6 | S-006 group, sixth test | ✅ |

Doc hygiene:

| Doc | Status |
|---|---|
| my_routines.md | ✅ Updated — current-state boundary note flipped to include the S-006 contract. |
| navigation_and_screens.md | ✅ Updated — My Routines branch references the S-006 play glyph. |
| widget_catalog/feature_primitives.md | ✅ Updated — `_RoutineCard` section rewritten for the S-006 layout. |
| feedback-pack-baseline-2026-07-27.md | ✅ Updated — new S-006 row + cross-reference. |
| state_management.md | ✅ N/A — no state class changes. |
| data_models.md | ✅ N/A — no model changes. |
| db_integration.md | ✅ N/A — no repository / schema changes. |

Global conventions:

- PASS (7 rules): repository-only dependency from state (no change to
  RoutineState in S-006); environment portability (no `dart:io`, no
  `Platform.is*`); theme tokens (glyph colour from
  `theme.colorScheme.primary`); reuse of canonical owner (`SizedBox`
  + `IconButton` instead of a custom button); effort-kind analytics
  (no changes — S-006 is a layout pass); timestamps as source data
  (no time-derived fields changed); no business logic in widgets
  (the play glyph just delegates to `onStart`).
- N/A (2 rules): units (no unit-edited values flow through this PR);
  effort-kind classification (no analytics rekeying).
- FAIL: none.

Architecture compliance:

- Features: changes are confined to `MyRoutinesScreen`'s private
  `_RoutineCard` widget. The constructor signature (`routine`,
  `formattedDate`, `onOpen`, `onStart`) is unchanged. ✅
- Widgets: `_RoutineCard` is a private widget with local theme +
  callbacks; no state mutation outside the widget, no repository
  access, pure presentation. ✅
- Models / Repositories / State / Core: untouched. ✅

Buttons (every screen touched):

- `_RoutineCard` play glyph uses `IconButton` (no `FilledButton` /
  `OutlinedButton` / `TextButton` introduced) — Material 3 default
  applies but the `SizedBox(width: 48, height: 48)` wrapper pins the
  layout size. The `Icon` itself has no button chrome (no fill, no
  border) — it is a glyph, not a button, which matches the AC. ✅
- `MyRoutinesScreen`'s `+ New Routine` `OmniBottomCTA` is unchanged. ✅
- `RoutineSetupScreen`'s header delete `IconButton` is unchanged. ✅
- No `FilledButton` / `OutlinedButton` / `TextButton` introduced in
  the S-006 diff — the previous 96-dp filled `TextButton` was removed.

Dead code: no new dead code introduced. The old 96-dp `TextButton`
+ `FittedBox` + Row layout is removed in the same edit that
introduced the bare `IconButton`. The `_RoutineCard` widget is still
referenced from exactly one place (`_MyRoutinesScreenState.build`).

Test coverage: 6 new S-006 tests cover every AC. The narrow-viewport
test (S-006 #6) is the regression guard the user called out — it
explicitly asserts "Bodyweight Conditioning" renders untruncated on
320 dp, which is the exact failure mode the feedback describes.
No golden or snapshot tests exist for the routines list (grep
`matchesGoldenFile` finds zero matches), so no regeneration is
required.

🟡 SUGGEST 1: `lib/features/routine/my_routines_screen.dart:454` —
the play glyph's `Icons.play_arrow` `size: 28` is a magic number.
Consider extracting to an `OmniTheme.startGlyphSize` token alongside
the existing `buttonPrimaryHeight` / `buttonIconSize` tokens so the
glyph scales with the rest of the design system if a future
follow-up resizes it. Non-blocking.

🟡 SUGGEST 2: `lib/features/routine/my_routines_screen.dart:485` —
the metadata line uses `Row` + `Flexible` + plain `Text` with
`overflow: TextOverflow.ellipsis` for the date. If a future
locale produces a long localized date string it could push the Demo
pill off-screen on narrow widths. Consider wrapping the date in
`Expanded` instead of `Flexible` (which currently uses the default
`FlexFit.loose` and so lets the date collapse before the badge does)
or testing with a localised long date. Non-blocking — current
English short date format fits comfortably at 320 dp.

🟢 APPROVED WITH SUGGESTIONS — Pipeline complete.

### Phase 3 ✓

Phase 1 review notes:

- `WorkoutRepository.deleteTemplate` already does NOT cascade into `TrainingSession` rows — completed sessions keep `routineTemplateId` by design so analytics, PRs, and history survive the routine being deleted. Confirmed by reading `lib/data/repositories/mock_workout_repository.dart` and the matching SQL contract.
- `RoutineState.deleteRoutine` only removes the template (and any `PlannedSession` rows linked to it; those are future-dated scheduled sessions, not completed history). The cascade warning in the existing delete dialog ("This routine has N planned session(s)…") already handles this distinction and is reused verbatim.
- No schema, model, or `WorkoutRepository` interface changes are required for PR 6. The work is concentrated in `MyRoutinesScreen` (intent split) and `WorkoutSessionScreen` (landing behaviour + empty-state parity).
- `lib/mock/seed_data.dart` and `scripts/sqlite_*.sql` are unchanged.
