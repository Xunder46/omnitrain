# Large-Screen Capped Content Column

## Overview

Introduce one app-wide behavior: on large-screen devices (tablets, iPads, large
unfolded foldables) the app's content sits in a horizontally centered column
of comfortable, readable width with empty margins on either side, instead of
stretching edge-to-edge. On phone-class widths the layout is byte-for-byte
identical to today — content fills the width, the primary bottom CTA spans
the surface minus the shared horizontal padding, no visible change. Vertical
sizes (heights, row sizes, CTA footprint) are unchanged on every device.
This is purely a horizontal-width change for one global behavior, applied
consistently to every screen with no per-screen logic, no split layouts, no
text scaling, no user-facing toggle.

## Requirements

- A single global layout behavior applied to every screen — no per-screen
  variation, no opt-in/opt-out, no user setting.
- On phone-class surface widths (including the largest phones and a foldable
  in folded state) the layout is byte-for-byte identical to today: content
  fills the surface, primary bottom CTA spans `surface.width - 2 ×
  bottomCTAHorizontalPadding`, no added side margins.
- On large-screen surface widths (tablets, iPads, large unfolded foldables)
  all content sits inside a horizontally centered column whose max width is
  on the order of a large phone. The primary bottom CTA sits inside the
  column and does not reach either screen edge. There are visible empty
  margins on both sides.
- Vertical sizing is unchanged on every device. Heights, row sizes, button
  height, vertical paddings, and the safe-area anchor are untouched.
- The cap begins only once the surface is meaningfully wider than a large
  phone. Threshold chosen so every phone is below it (largest phone ≈ 430
  dp), and any device above it (Pixel Fold unfolded ≈ 673 dp, iPad mini ≈
  744 dp, iPad Pro 11" ≈ 834 dp, iPad Pro 12.9" ≈ 1024 dp) is centered.
- No split layouts (no list/detail, no two-pane, no side-by-side). No text
  scaling changes. No orientation handling. No new orientation behavior.
- Implementation lives in a single place (`OmniGradientBackground`) so every
  screen — home, session, exercise, nutrition, profile, settings, onboarding
  — and every pushed route — receives it automatically via the existing
  gradient-wrapping contract.

## Acceptance Criteria

- [ ] On a phone-class surface width, the app is visually identical to current
      behavior: content and the bottom CTA fill the available width with
      zero added side margins.
- [ ] The largest phones, and a foldable in folded state, also show no
      margins and no change — the capped state does not activate on any
      phone-width surface.
- [ ] On a tablet/iPad-class surface width, all content sits in a
      horizontally centered column with visible empty margins on both the
      left and right.
- [ ] On a tablet/iPad-class surface width, the primary bottom action button
      (Log Set / Finish Workout / etc.) is contained within that centered
      column and does not reach either screen edge.
- [ ] The centered column's width is on the order of a large-phone width —
      it does not grow toward the screen edges as the screen gets wider.
- [ ] Every screen in the app exhibits the same framing on large screens;
      no screen stretches edge-to-edge while others are capped.
- [ ] Element heights (button height, row heights, vertical paddings) are
      unchanged on all device sizes.
- [ ] The visual result is confirmed on both a phone-class and a
      tablet-class surface, with the tablet checked in both portrait and
      landscape.
- [ ] Existing CTA-inset tests that asserted the button's left/right edges
      sit at `bottomCTAHorizontalPadding` and `surface.width -
      bottomCTAHorizontalPadding` are rewritten to measure the inset from
      the centered column's edges, so the assertion holds on both phone
      and tablet widths.
- [ ] New tests cover: (a) a phone-class width — column and CTA still fill
      available width with no margins; (b) a tablet-class width — the
      column is measurably narrower than the surface with margins on both
      sides, and the CTA is centered and capped.

## Scenarios

### S-001: Phone-class surface — content fills width, no cap
- Trigger: App rendered at a phone-class surface width (e.g. 400 × 800).
- Precondition: `OmniGradientBackground` is wrapping screen content.
- Flow: Pump a screen at a 400-wide surface.
- Expected outcome: The screen's `body` and any `Scaffold.bottomNavigationBar`
  fill the surface width minus the shared `bottomCTAHorizontalPadding`. No
  empty side margins beyond the existing 16 dp CTA inset. The centered
  column is **inert** below the activation threshold.
- Edge case of: none

### S-002: Phone-class surface — bottom CTA still spans the width
- Trigger: App rendered at a phone-class surface width.
- Precondition: A screen using `Scaffold.bottomNavigationBar:
  OmniBottomCTA(...)` is on screen.
- Flow: Get the `FilledButton` rect inside the CTA at a 400-wide surface.
- Expected outcome: The button's left edge sits at
  `OmniTheme.bottomCTAHorizontalPadding` and the right edge sits at
  `surface.width - OmniTheme.bottomCTAHorizontalPadding`. The button width
  is `surface.width - 2 × bottomCTAHorizontalPadding`.
- Edge case of: S-001

### S-003: Tablet-class surface — content sits in centered column
- Trigger: App rendered at a tablet-class surface width (e.g. 1024 × 1366).
- Precondition: `OmniGradientBackground` is wrapping screen content.
- Flow: Pump a screen at a 1024-wide surface.
- Expected outcome: The content column has a `width` of
  `OmniTheme.kColumnMaxWidth` (≈ 480 dp), is horizontally centered in the
  surface (equal empty margins on the left and right), and the margins are
  non-zero. Vertical sizes are unchanged.
- Edge case of: none

### S-004: Tablet-class surface — bottom CTA is centered and capped
- Trigger: App rendered at a tablet-class surface width.
- Precondition: A screen using `Scaffold.bottomNavigationBar:
  OmniBottomCTA(...)` is on screen.
- Flow: Get the `FilledButton` rect inside the CTA at a 1024-wide surface.
- Expected outcome: The button's left edge sits at
  `(surface.width - OmniTheme.kColumnMaxWidth) / 2 + bottomCTAHorizontalPadding`
  and the right edge sits at
  `(surface.width + kColumnMaxWidth) / 2 - bottomCTAHorizontalPadding`.
  The button does not reach either screen edge; both side margins are
  non-zero and equal.
- Edge case of: S-003

### S-005: Tablet-class surface — column does not grow with the surface
- Trigger: App rendered at successively larger tablet-class surface widths.
- Precondition: `OmniGradientBackground` is wrapping screen content.
- Flow: Render the same screen at 1024 and at 1366 surface widths. Get the
  content column rect in each case.
- Expected outcome: The content column's width is identical (equal to
  `kColumnMaxWidth`) at both surface widths; only the side margins grow.
- Edge case of: S-003

### S-006: Every screen frames consistently on tablet
- Trigger: Tablet-class surface, multiple screens.
- Precondition: Two or more distinct screens (e.g. `PeriodListScreen`,
  `DaySessionListScreen`, `NutritionTargetScreen`, `AddFoodScreen`) on
  tablet.
- Flow: For each, get the content column rect.
- Expected outcome: All screens have the same content column width
  (`kColumnMaxWidth`) and the same horizontal centering. No screen
  stretches edge-to-edge while others are capped.
- Edge case of: S-003, S-004

## Iteration 1

### DB Changes

None. This is a pure layout/UI change. No model, repository, schema, or
data-layer touch.

### Backend Changes

None. OmniTrain has no server backend.

### Frontend Changes

1. **New design tokens** in `lib/core/constants/omni_theme.dart` under a new
   `LARGE-SCREEN CONTENT COLUMN` section:
   - `kColumnMaxWidth = 480.0` — max width of the centered content column.
   - `kColumnMinActivationWidth = 500.0` — surface width at which the cap
     activates. Just above the largest phone width (430 dp) so every phone
     passes through unchanged.

2. **Wrap child in a centered column inside `OmniGradientBackground`**
   (`lib/widgets/layout/omni_gradient_background.dart`): add a
   `LayoutBuilder` that, when `constraints.maxWidth >=
   OmniTheme.kColumnMinActivationWidth`, wraps the `child` in
   `Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth:
   OmniTheme.kColumnMaxWidth), child: child))`. Below the threshold the
   child passes through unchanged. The gradient `Container` and the
   `Stack` overlays (radial highlight, noise) continue to fill the full
   surface so the app's atmosphere is unchanged — only the `child`'s
   horizontal extent is capped.

   Because every screen-level navigation goes through `OmniRoute` /
   `OmniFadeRoute` (per the navigation contract) and both wrap their
   pages in `OmniGradientBackground`, and the home and onboarding
   screens are wrapped in the gradient inside `MaterialApp.builder` in
   `app.dart`, the cap reaches every screen automatically — no per-screen
   edits, no per-route edits, no per-feature edits.

3. **Update the 6 existing CTA-inset tests** in
   `test/screen_widget_test.dart` (lines 64–180, the `OmniBottomCTA`
   group, plus the `PeriodListScreen` and `DaySessionListScreen` CTA
   anchor tests) and `test/nutrition_test.dart` (the `NutritionTarget`,
   `AddFoodScreen` My Foods, and `AddFoodScreen` Categories CTA anchor
   tests) so the assertion measures the inset from the centered column's
   edges, not the surface's. Wrap the `pumpWidget` body in a
   `MaterialApp.builder` that applies the same cap as production (a
   small test helper), so the test exercises the production centering
   path. The expected left/right become
   `columnLeft + bottomCTAHorizontalPadding` and
   `columnLeft + columnWidth - bottomCTAHorizontalPadding`, where
   `columnLeft = (surface.width - columnWidth) / 2` and
   `columnWidth = surface.width >= kColumnMinActivationWidth ?
   kColumnMaxWidth : surface.width`.

4. **Add a new `Large-screen content column` test group** in
   `test/screen_widget_test.dart` covering:
   - S-001 / S-002: at a phone width (e.g. 400 × 800), content and the
     CTA still fill the width, the column is inert, the button's edges
     touch the surface-minus-padding.
   - S-003 / S-004: at a tablet width (e.g. 1024 × 1366), the content
     column is centered, `kColumnMaxWidth` wide, with non-zero equal
     side margins; the CTA's button is centered within the column and
     does not reach either surface edge.
   - S-005: at two different tablet widths (1024 and 1366), the content
     column width is the same — it does not grow with the surface.

5. **Doc hygiene:**
   - `docs/widget_catalog.md`: document the large-screen cap on the
     `OmniGradientBackground` entry — the centered column is a built-in
     behavior of the gradient wrapper.
   - `docs/design_system.md`: note the app-wide centered-column rule
     under the layout section.
   - `docs/constants_reference.md`: list the new tokens
     `kColumnMaxWidth` and `kColumnMinActivationWidth`.

### Implementation Steps

1. Phase 0 (this file): plan, scenarios, acceptance criteria — done.
2. Phase 1: add the two tokens to `OmniTheme` (no data-layer change).
3. Phase 2:
   1. Write the new `Large-screen content column` test group in
      `test/screen_widget_test.dart` and the new shared test helper
      (TDD — confirm red).
   2. Implement the centered column inside `OmniGradientBackground`.
   3. Update the 6 existing CTA-inset tests to measure against the
      column's edges and use the shared helper.
   4. Run the full test suite to green.
   5. Update `widget_catalog.md`, `design_system.md`,
      `constants_reference.md`.
4. Phase 3: code review.

## Progress

- [x] Phase 0 — plan file authored
- [x] Phase 1 — tokens added to `OmniTheme`
- [x] Phase 2.1 — new column-cap tests written (red)
  - S-001/S-002 pass (phone = no-op, current behavior matches)
  - S-003/S-004/S-005/S-006 fail (tablet cap missing)
- [x] Phase 2.2 — centered column implemented in `OmniGradientBackground`
- [x] Phase 2.3 — existing 6 CTA-inset tests rewritten against column edges
- [x] Phase 2.4 — full test suite green (1685 pass, 5 skipped, 0 fail)
- [x] Phase 2.5 — `widget_catalog.md`, `design_system.md`,
      `constants_reference.md` updated
- [x] Phase 3 — code review complete
  - All 10 acceptance criteria verified against the implementation
  - All 6 scenarios mapped to passing tests
  - Doc hygiene table: navigation/state/widget_catalog/design_system/data_models/db_integration/constants_reference all ✅
  - Global conventions: PASS (Reuse the canonical owner, Instrument panel), N/A (units, theme colors, card chrome, effort kind, timestamps, decorative chrome)
  - Architecture compliance: widgets/core/test in-scope layers all clean
  - Buttons: no new buttons; existing OmniBottomCTA unchanged with explicit shape
  - Dead code: removed `TestContentColumn` class (the production-helper widget); kept `contentColumnRectFor` geometry helper
  - Test coverage: 6 new tests + 6 rewritten tests cover phone/tablet/threshold/orientation
  - Environment safety: no `dart:io`, no SQLite, no Platform.is*, no hardcoded repo
  - DRY: single cap implementation, single geometry helper
  - Final: 1685 pass, 5 skipped, 0 fail (no regressions)
  - Findings: 1 resolved (test_content_column dead code → removed), 1 resolved (S-005 tearDown inside loop → consolidated outside loop)

## Feedback

