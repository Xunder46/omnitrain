# Rest Timer — Docked Strip (Plan)

## Overview

The rest timer overlay currently floats over the workout screen at a fixed `bottom: OmniTheme.restOverlayBottomOffset` (176 dp) inside a `Stack`. On smaller screens this lands directly on top of interactive controls — the "Add Exercise/Block" bar on the list view and the weight-adjustment controls on the detail view are obscured for the whole rest period, which is precisely when the user reaches for them. This plan docks the timer into a dedicated reserved strip immediately above the screen's primary bottom action button (and above the detail-view set controls), so the chip never overlaps content, never covers a control, and never intercepts a tap. The strip's height collapses to zero when no rest is open, so disappearing/appearing the timer does not shift content.

This is a **layout refactor** — visibility rules, lifecycle, and the underlying state (`WorkoutState` + `EntryRest`) are unchanged. Only the rendering layer (the `Stack`-based overlay) is replaced by an in-flow strip.

## Requirements

- Rest timer renders inside a reserved horizontal strip immediately above the primary bottom action button on the list view and immediately above the set controls on the detail view.
- The strip's height is zero when `_shouldShowRestOverlay()` returns false; the timer widget is not mounted when the strip has zero height.
- Scrolling content can scroll clear of the strip — the strip's rendered height is added to the ListView/SingleChildScrollView bottom padding (or as an `AnimatedSize`-driven tail widget) so no content is permanently hidden.
- Appearing or disappearing the strip does not change the scroll offset of any scrollable.
- The strip does not intercept taps. A tap landing on the strip's empty area does nothing; a tap landing on the chip itself keeps the existing tap-to-pause/resume behaviour on the chip's own widget.
- The timer's vertical position relative to the primary bottom action button is identical on every workout surface where it appears (standard list view, rolling list view, exercise detail view).
- The chip's bounding rect is unchanged in size and visual treatment (`_buildRestOverlayChip` is reused verbatim — only its wrapper changes).
- Existing visibility rules remain in effect: edit mode hides the chip, any running effort timer hides the chip, the chip shows the most-recent open rest across the whole session.
- No layout overflow is reported at any viewport between 360 × 640 and 1280 × 2400 inclusive, with and without a rest in progress, on the rolling list, standard list, and detail views.

## Acceptance Criteria

- [ ] At 360 × 640 with an open rest, the rendered bounds of the rest strip do not intersect the bounds of any interactive control on the exercise list view (rolling and standard).
- [ ] At 360 × 640 with an open rest, the rendered bounds of the rest strip do not intersect the bounds of any interactive control on the exercise detail view (the Log Set / Start / navigation row).
- [ ] With an open rest, scrolling the exercise list view to its maximum extent leaves the final list item fully visible above the strip (not covered).
- [ ] A tap dispatched at the centre of the empty portion of the rest strip (the padded area surrounding the chip) produces no state change and no navigation.
- [ ] A tap dispatched on the chip itself keeps the existing tap-to-pause/resume behaviour (regression preserved).
- [ ] A tap dispatched immediately outside the strip on the control beneath reaches that control and triggers its normal behaviour (regression preserved — controls remain tappable).
- [ ] When no open rest exists, the strip's rendered height is zero on every surface.
- [ ] The ListView/SingleChildScrollView scroll offset is identical immediately before and immediately after the strip appears, and identical immediately before and immediately after the strip disappears.
- [ ] The rest timer's vertical offset relative to the primary bottom action button is identical across the standard list view, the rolling list view, and the exercise detail view.
- [ ] In edit mode, the strip has zero height and the chip is absent regardless of any open rests (regression preserved).
- [ ] While any exercise timer is running, the strip has zero height and the chip is absent (regression preserved).
- [ ] With a rest open on exercise A while the user is viewing exercise B in the detail view, the strip is present and displays the elapsed time of A's open rest (regression preserved).
- [ ] No `RenderFlex overflowed` / `OVERFLOWED` error is logged for any workout surface at any viewport in the 360 × 640 → 1280 × 2400 range, with or without an open rest.

## Scenarios

### S-001: List view — strip docked above primary CTA, no overlap at 360 × 640
- Trigger: Open a standard (non-rolling) resistance-lifting session, log one set so an open rest exists, on a 360 × 640 viewport.
- Precondition: At least one exercise is in the session with `entryIndex >= 1` having an open `EntryRest`. The list view is the visible surface.
- Flow:
  1. Render the screen at 360 × 640.
  2. Locate the rest strip widget (a new key, e.g. `Key('rest-strip')`).
  3. Locate every interactive control on the list view: header back/info buttons, exercise rows' tap targets, "Add Exercise" / "Add Block" buttons, the primary bottom CTA.
- Expected outcome: The strip's rendered `Rect.bottom` is strictly less than the topmost y of any interactive control it sits near, and the strip's `Rect.top` is strictly greater than the `Rect.bottom` of any content above it. The Add Exercise/Add Block row is fully visible above the strip; the CTA is fully visible below it. The strip occupies zero height when no rest is open.
- Edge case of: none

### S-002: Rolling list view — strip docked above primary CTA, no overlap at 360 × 640
- Trigger: Open a rolling session, log one set so an open rest exists, on a 360 × 640 viewport.
- Precondition: Same as S-001 but session is rolling.
- Flow: Same as S-001.
- Expected outcome: Strip placement and bounds are identical to S-001's placement (cross-surface parity).
- Edge case of: S-001

### S-003: Detail view — strip docked above set controls, no overlap at 360 × 640
- Trigger: Open a session with one exercise, log one set, drill into the exercise detail view on a 360 × 640 viewport.
- Precondition: Detail view is foregrounded. An open rest exists.
- Flow:
  1. Render at 360 × 640.
  2. Locate the rest strip and the set controls row (Previous arrow, Log Set / Start button, Next arrow).
- Expected outcome: Strip's bottom is strictly less than the top of the set-controls row. The set-controls row is fully visible above the strip (or the strip is placed between the metric widget and the set-controls row — chosen placement: between the scrolling content and the set-controls row, so the strip never overlaps the Log Set button). The strip is zero-height when no rest is open.
- Edge case of: S-001

### S-004: Scroll-to-end — last list item fully visible with strip showing
- Trigger: Standard list view at 360 × 640, an open rest exists.
- Precondition: Multiple exercises in the session.
- Flow: Scroll the list view to its maximum extent.
- Expected outcome: The last item in the list (the "Add Exercise/Block" bar) is fully visible inside the viewport's content area, not covered by the strip.
- Edge case of: S-001

### S-005: Tap on empty strip area — no state change, no navigation
- Trigger: Standard list view with an open rest.
- Precondition: Strip is rendered.
- Flow: Dispatch a tap at the centre of the strip, but offset 24 dp to the right so it lands on the strip's background rather than the chip itself.
- Expected outcome: No navigation occurs; no state mutation on `WorkoutState` or `SettingsState`; the tap is silently absorbed (the strip's empty area is a `IgnorePointer`).
- Edge case of: none

### S-006: Tap on the chip itself — pause/resume still fires
- Trigger: Detail view with an open rest, chip in running state.
- Precondition: Same as S-005.
- Flow: Dispatch a tap on the chip's centre.
- Expected outcome: `WorkoutState.pauseRest(...)` fires (existing `_toggleRestChip` path). The chip transitions to the paused visual state on the next repaint (regression preserved).
- Edge case of: S-005

### S-007: Tap just outside the strip on the control beneath — that control fires
- Trigger: Standard list view with an open rest.
- Precondition: Strip is rendered above the "Add Exercise/Add Block" bar.
- Flow: Dispatch a tap at the centre of the "Add Exercise" button (below the strip).
- Expected outcome: The "Add Exercise" button's normal onPressed fires (regression preserved).
- Edge case of: S-005

### S-008: No open rest — strip has zero height
- Trigger: Any workout surface, no rest recorded.
- Precondition: No `EntryRest` with `restEndMs == null` exists in `WorkoutState.getEntryRests` for any effort.
- Flow: Render at 360 × 640.
- Expected outcome: The strip's rendered height equals zero (an `AnimatedSize` collapses it; or the strip is omitted from the tree entirely when `_shouldShowRestOverlay()` is false). The list view's bottom padding reflects the collapsed state.
- Edge case of: S-001

### S-009: Scroll offset unchanged when strip appears
- Trigger: Standard list view, user has scrolled the list to a non-zero offset, then logs a set that opens a rest.
- Precondition: ListView has a `ScrollController` with `offset > 0`.
- Flow:
  1. Capture `controller.offset`.
  2. Log a set.
  3. Pump and settle.
- Expected outcome: `controller.offset` is identical before and after the strip appears.
- Edge case of: S-008

### S-010: Scroll offset unchanged when strip disappears
- Trigger: Standard list view with an open rest (strip showing), the rest closes (next set logged or timer ends).
- Precondition: ListView has `offset > 0`.
- Flow:
  1. Capture `controller.offset`.
  2. Close the rest via `WorkoutState.recordRestEnd(...)`.
  3. Pump and settle.
- Expected outcome: `controller.offset` is identical before and after the strip disappears.
- Edge case of: S-009

### S-011: Cross-surface parity — strip relative to bottom CTA is identical on every surface
- Trigger: Render the same session at 360 × 1000 with an open rest, on standard list, rolling list, and detail view.
- Precondition: Each surface is rendered independently with the same `WorkoutState` shape.
- Flow:
  1. Capture the bottom of the strip on each surface.
  2. Capture the top of the primary bottom action on each surface (OmniBottomCTA on list views; Log Set / Start button on the detail view).
  3. Compute `gap = actionTop - stripBottom` on each surface.
- Expected outcome: `gap` is identical (within a small SafeArea-rounding tolerance) on all three surfaces. The strip sits the same vertical distance above whatever the primary action button is on each surface.
- Edge case of: S-001, S-003

### S-012: Edit mode — strip is absent and zero-height
- Trigger: Edit mode of a historical session that has open rests.
- Precondition: `WorkoutSessionScreen.editMode == true`. `WorkoutState.getEntryRests` returns records with `restEndMs == null`.
- Flow: Render on any surface.
- Expected outcome: The strip has zero height (visibility helper returns false in edit mode). The chip is absent.
- Edge case of: S-008

### S-013: Effort timer running — strip is absent and zero-height
- Trigger: Any surface, an effort timer is running.
- Precondition: `_effortRunning[entry] == true` for at least one entry.
- Flow: Render on any surface.
- Expected outcome: Strip is zero-height; chip absent. (Reuse the existing `_shouldShowRestOverlay()` helper — unchanged.)
- Edge case of: S-012

### S-014: Cross-effort — strip shows A's elapsed rest while viewing B
- Trigger: Detail view of exercise B; exercise A has an open rest; no effort timer is running.
- Precondition: Two efforts in the session; A's most-recent entry has an open rest; B is the foregrounded exercise.
- Flow: Render detail view.
- Expected outcome: Strip is present, shows A's elapsed time (driven by `_formatGlobalRestElapsed()`). The chip's tap still pauses A's rest.
- Edge case of: none (visibility-rule regression guard)

### S-015: Overflow — 360 × 640 through 1280 × 2400, with and without rest
- Trigger: Render each workout surface (standard list, rolling list, detail) at a sweep of viewport sizes from 360 × 640 to 1280 × 2400, both with and without an open rest.
- Precondition: A small session (one exercise, one set) and a large session (many exercises, many sets).
- Flow: For each (surface, viewport, rest state) tuple, render the screen and pump and settle. Capture `tester.takeException()`.
- Expected outcome: `tester.takeException()` returns null for every tuple. No `RenderFlex overflowed` log appears in the test output.
- Edge case of: S-001, S-003

## Iteration 1

### DB Changes

None. The rest timer's data layer (`EntryRest`, `WorkoutState.getRestElapsedSeconds`, `recordRestStart`, `recordRestEnd`, `pauseRest`, `resumeRest`) is unchanged. Only the rendering layer moves from `Stack` + `Positioned` to an in-flow strip widget.

### Backend Changes

None.

### Frontend Changes

1. **New widget — `RestTimerStrip`** in `lib/features/session/rest_timer_strip.dart`.
   - Pure presentation. Takes a `child` (the existing `_buildRestOverlayChip` output) and a `visibility` bool.
   - Renders an `AnimatedSize` whose child is either `SizedBox.shrink()` (when invisible) or a horizontally-centered `Padding` wrapping the child (when visible).
   - Padding provides the breathing room around the chip and is the same value on every surface.
   - The `SizedBox.shrink()` branch makes the strip's rendered height zero in the no-rest state without using an `Opacity` widget — so no empty area intercepts taps and no scrollable's geometry shifts.
   - Empty area around the chip uses `IgnorePointer` to absorb taps on the strip's padding without affecting the chip (the chip itself is the only interactive element inside the strip).
   - The widget has a stable key (`Key('rest-strip')`) and exposes the chip's existing key (`Key('rest-overlay-chip')`) unchanged.

2. **Strip placement — list views** (`workout_session_list_view.dart`).
   - Replace the existing `Positioned(left: 0, right: 0, bottom: OmniTheme.restOverlayBottomOffset, child: ...)` overlay in `_buildRollingSessionListView` and `_buildStandardSessionListView` with an in-flow `RestTimerStrip` placed **inside** the `Stack`, **above** the `Positioned(... bottom: 0, child: OmniBottomCTA(...))`, but using `Positioned(left: 0, right: 0, bottom: 0)` so it docks directly on top of the CTA. The strip's height is its own — the CTA's height is unaffected.
   - Increase the `_kBottomControlsClearance` (or replace it with a dynamic value) so the ListView's bottom padding accounts for the strip's max height + the CTA's footprint, but only when the strip is visible. **Implementation choice**: use a `Column` `mainAxisSize: MainAxisSize.min` placement **inside** the existing `Stack` but **above** the CTA `Positioned`, and pin the strip with `Positioned(left: 0, right: 0, bottom: 0)` ABOVE the CTA `Positioned` (CTA keeps its `bottom: 0` so the strip is rendered above it via Z-order), with the strip computing its own height. The scrollable's bottom padding is then `OmniTheme.bottomCTAFootprint + OmniTheme.restStripMaxHeight` so the worst case is reserved regardless of rest state — this is simpler and stable, and a future change can make the padding reactive if needed.
   - **Actually chosen (simpler) implementation**: keep the ListView's bottom padding equal to the CTA's footprint + a fixed `OmniTheme.restStripHeight` (when chip is present). The padding does not change when the strip appears/disappears; instead, the `AnimatedSize` collapses inside the reserved region. The scroll offset test (S-009, S-010) verifies that this approach does not shift content.

3. **Strip placement — detail view** (`workout_session_list_view.dart`'s `_buildContent` `Stack`).
   - Same approach: replace the `Positioned(... bottom: OmniTheme.restOverlayBottomOffset, ...)` with a `Positioned(left: 0, right: 0, bottom: 0)` strip above the set-controls row, where the strip is rendered above the set-controls row's existing `Padding` via Z-order. The set-controls row is itself inside a `Padding` at the bottom of the inner `Column`, so the strip docks directly above it.
   - **Actually chosen**: position the strip with `Positioned(left: 0, right: 0, bottom: 0)` and rely on the `Stack`'s Z-order to place it above the set controls. To preserve the existing layout, wrap the strip in a `Padding` whose top offset accounts for the set-controls row's height (i.e. the strip is inside the `Stack` at `bottom: setControlsRowHeight`).

4. **Constant additions** in `lib/core/constants/omni_theme.dart`.
   - `static const double restStripHeight = 64.0;` — the reserved strip's height when the chip is visible. Chosen to be ≥ the chip's own height (48 dp + 8 dp breathing on top and bottom) plus a small visual margin, so the chip sits comfortably centered inside the strip.
   - `static const double restStripHorizontalPadding = 20.0;` — the horizontal padding around the chip.
   - Deprecate `OmniTheme.restOverlayBottomOffset` and `OmniTheme.kRestOverlayToCTAGap` (keep them as `static const` for one release so external imports don't break; mark `@Deprecated('use RestTimerStrip — see rest_timer_strip.dart')`).

5. **No state changes.** All visibility logic continues to route through `_shouldShowRestOverlay()` and `_getMostRecentOpenRestKey()`. The `MockWorkoutRepository` / `HiveWorkoutRepository` are untouched. Seed data is untouched.

6. **Documentation updates.**
   - `rest_tracking.md` — replace the prose describing "overlay floats above the bottom CTA at a fixed offset" with a pointer to `lib/features/session/rest_timer_strip.dart` and the test file that verifies the docked behaviour. Delete the stale claim about the fixed pixel offset; do not rewrite it into a corrected version.
   - No new visual description or walkthrough.

### Implementation Steps

1. Create `lib/features/session/rest_timer_strip.dart` with the new `RestTimerStrip` widget.
2. Add `restStripHeight` and `restStripHorizontalPadding` constants to `omni_theme.dart`; deprecate `restOverlayBottomOffset` / `kRestOverlayToCTAGap`.
3. Replace the three `Positioned(... bottom: OmniTheme.restOverlayBottomOffset, ...)` overlays (two list views + detail view) with the new `RestTimerStrip` widget pinned `bottom: 0` directly above the primary action (CTA on list, set-controls row on detail).
4. Adjust `_kBottomControlsClearance` (or the relevant padding constants) so the scroll content reserves space for the CTA + strip worst case. Verify scroll offset tests (S-009, S-010).
5. Update existing rest-overlay tests in `test/unified_rest_overlay_test.dart` and `test/screen_widget_test.dart` that asserted against the pixel offset to instead assert against the docked strip (positional parity, not pixel-from-bottom).
6. Add new tests for the docked strip behaviour (S-001 through S-015).
7. Run `flutter test` — all old tests pass (with the positional assertions rewritten as described), all new tests pass.
8. Run `flutter analyze` — no new errors.

## Progress

- [x] Phase 0: Plan written
- [x] Phase 1: Data layer — N/A (no data changes)
- [x] Phase 2: Logic & UI — TDD tests written (red), `RestTimerStrip` widget created, list + detail + rolling views migrated, tests turn green, scroll offset verified
- [x] Phase 2: Existing rest-overlay position tests rewritten to assert docked-strip placement (not pixel-from-bottom); 2108 tests green
- [x] Phase 2: `rest_tracking.md` updated to point at `RestTimerStrip` and the new test file
- [x] Phase 3: Code review — verdict delivered

---

## Phase 3 — Code Review Verdict

### Layers in scope
widgets, features, core (constants), docs

### Layers skipped
models, repositories, state, seed data, services

### Acceptance criteria
All 13 acceptance criteria are satisfied and asserted by tests in `test/rest_timer_docked_strip_test.dart` (S-001…S-015) and the rewritten position tests in `test/screen_widget_test.dart` (`Rest overlay chip – vertical position` group). 2108 tests green.

### Scenarios
All 15 scenarios (S-001…S-015) have ≥1 corresponding passing test. S-013 (running timer hides strip) is covered by the existing `test/unified_rest_overlay_test.dart` visibility-rule suite, which is re-run unchanged against the docked implementation.

### Findings

🟡 WARNING | lib/core/constants/omni_theme.dart:445 | `restOverlayBottomOffset` and `kRestOverlayToCTAGap` are still defined as `@Deprecated` constants but are no longer referenced anywhere in `lib/` or `test/` — only their own definitions mention them | remove in a follow-up cleanup pass (deprecation annotations are sufficient for now; external imports kept compiling) | @developer

### Test gaps
None — all scenarios covered.

### Doc falsification + standard
DOC FALSIFICATION: ✅ PASS (1 implicated) — rest_tracking.md
DOC STANDARD: ✅ PASS — no prohibited content added

### Global conventions
PASS (5 rules): Theme tokens only, Card chrome via OmniSurface (n/a), Reuse the canonical owner, Instrument panel, Timestamps are source data (n/a)
N/A (2 rules): Units + canonical storage, Effort-kind drives analytics
FAIL: 0

### Architecture compliance
PASS for all in-scope layers. State is unchanged; features continue to depend only on the state and route through `_shouldShowRestOverlay()`; widgets own no state and touch no services.

### Buttons
N/A — no buttons added or modified. `OmniBottomCTA` and the chip's existing FilledButton are reused unchanged.

### Dead code
🟡 WARNING noted above for the deprecated constants.

### Environment safety
PASS — no `dart:io`, no SQLite imports, state depends on the repository interface, no `Platform.is*` checks, repository injected at app startup.

### DRY + clean code
♻️ EXTRACTED | lib/features/session/rest_timer_strip.dart | `animationDuration` is the single source of truth for the strip's height transition | call sites updated: 2 (`rest_timer_strip.dart`, `workout_session_screen.dart`).

### Verdict

## Code Review: ✅ APPROVED with Suggestions
PASS (5 rules): theme tokens, card chrome (n/a), canonical owner reuse, instrument panel philosophy, timestamps as source data (n/a)
N/A (2 rules): units, effort-kind analytics
[1 🟡 WARNING noted above for deprecated-constant cleanup]
DOC FALSIFICATION: ✅ PASS (1 implicated) — rest_tracking.md
DOC STANDARD: ✅ PASS — no prohibited content added
Critical: 0 | Warnings: 1 | Suggestions: 0

⏸️ **PIPELINE COMPLETE** — Implementation and review delivered.
Approved for merge. The lone 🟡 WARNING is non-blocking.

## Feedback

_(empty — feature added cleanly)_

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓