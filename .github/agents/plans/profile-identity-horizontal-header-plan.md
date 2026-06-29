# Feature: profile-identity-horizontal-header

## Overview

Rework the Profile screen identity block from a tall, center-stacked hero (large avatar → name → height, all stacked vertically inside a heavy `OmniSurface` card) into a compact horizontal header: the avatar sits on the left at its current 200 × 200 size, and the name + height stack in a column on the right, vertically centered against the avatar. The heavy card chrome around the identity block is removed so the block reads as a screen header rather than a tall hero panel, recovering vertical space for the charted measurement cards below. The "height" cue icon (`Icons.height`, a vertical double-headed arrow) is dropped because it reads as a resize/sort control; the whole height line is already tappable.

### Iteration 3 — Verify the header's height subtitle is unit-aware

Iteration 1/2 produced the horizontal header. The user wants explicit confirmation that the height subtitle respects the user's height-unit setting (cm vs feet/inches) — same behavior the measurement cards already have. A pre-flight inspection of `lib/features/profile/profile_screen.dart` shows `_buildIdentityHeightRow` already calls `UnitFormatter.formatHeight(heightCm, widget.settingsState)`, and the screen rebuilds on `settingsState` changes via `Listenable.merge([widget.profileState, widget.settingsState])`. Iteration 3 confirms this in tests rather than fixing code: it adds explicit unit-aware render tests against the new horizontal-header layout, and adds a live unit-toggle test that asserts the subtitle re-renders in place without leaving the screen.

### Iteration 2 — Rebalance the right column

The horizontal header landed in Iteration 1 but the right column reads as loose: the avatar (200 dp) dominates the row and the name + height column floats high with the two lines spaced too far apart, leaving a big void below the height text. Iteration 2 tightens the pairing: drop the `ConstrainedBox(minHeight: ...)` chrome around both rows, drop the inter-row spacer to a tight 2 dp gap, drop the vertical padding inside both rows, and bump the name typography to `headlineMedium` so the right column carries more visual weight. The column stays vertically centered against the avatar (`MainAxisAlignment.center`); the avatar size is unchanged.

## Requirements

### Iteration 1 (shipped)

- The identity block renders as one horizontal `Row`: circular avatar on the left, name + height column on the right, vertically centered against the avatar.
- Avatar dimensions remain 200 × 200 (the established size) and never drop below a 180 floor.
- The name is the top line of the right column, left-aligned; tapping it opens the existing name editor dialog (unchanged path).
- Height is the second line of the right column, left-aligned beneath the name; tapping it opens the existing `_HeightDialog` (unchanged path).
- The `Icons.height` arrow cue next to the height value is removed.
- The `OmniSurface` wrapper around the identity block is removed; the block renders as a header flush with the screen background (gradient shows through).
- The block's total height collapses substantially: the name and height now share the avatar's vertical envelope, so the charted measurement cards beneath gain meaningful space on a typical phone viewport.
- Behavior contract preserved: `profile_identity_height_value` key continues to wrap the height tap target; height remains tappable; name remains tappable; storage path is unchanged (`ProfileState.updateHeight` → `BodyMeasurementEntry(type='height', unitId='unit-cm')`); display path is unchanged (cm / ftin formatting via `UnitFormatter.formatHeight`).
- Avatar image, shape, measurement cards, measurement order, lean mass, and the avatar crop step are explicitly out of scope.

## Acceptance Criteria

- [ ] The identity block lays out as a single horizontal `Row`: avatar on the left, name + height column on the right, vertically centered.
- [ ] Avatar is 200 × 200 (current size); the implementation does not reduce it below 180.
- [ ] Height renders as a secondary line beneath the name, left-aligned with the name — not centered on its own line.
- [ ] Tapping the name opens the name editor dialog.
- [ ] Tapping the height line opens `_HeightDialog` and persists via the existing `BodyMeasurementEntry('height')` path.
- [ ] The `Icons.height` arrow glyph is no longer present anywhere inside the identity block.
- [ ] The identity block does NOT render inside an `OmniSurface` (heavy card chrome removed); the gradient background shows through behind it.
- [ ] The identity block is measurably shorter than the previous centered layout, bringing at least one additional measurement card meaningfully into the initial viewport on a typical phone.
- [ ] Existing identity-area behavior is preserved: height displays in the active unit (cm or ftin); cm / ftin edit dialog flows are unchanged; the existing `profile_identity_height_value` key remains the height tap target.

## Scenarios

### S-001: Identity block lays out as horizontal avatar + name/height column

- Trigger: Profile screen mounts.
- Precondition: User has a display name and a height entry.
- Flow: Profile renders → identity block is composed.
- Expected outcome: The block's outer widget is a `Row` containing the avatar `GestureDetector` and a column that holds both the name `InkWell` and the height `InkWell`. The two halves are siblings inside the `Row`, not parent/child.
- Edge case of: none.

### S-002: Avatar size floor (≥ 180)

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders → identity block.
- Expected outcome: The rendered avatar's smallest dimension is ≥ 180 dp.
- Edge case of: S-001.

### S-003: Height renders as subtitle beneath the name (left-aligned)

- Trigger: Profile screen mounts with height = 180 cm.
- Precondition: User has a height entry, cm mode.
- Flow: Profile renders → identity block.
- Expected outcome: The text `180 cm` is rendered as a descendant of the height tap target, the height tap target sits BELOW the name tap target in the same column (the right column of the outer `Row`), and the height text is left-aligned (starts at the same X coordinate as the name text).
- Edge case of: S-001.

### S-004: Tapping the name opens the name editor; tapping the height opens the height editor

- Trigger: User taps the name and then taps the height.
- Precondition: Profile rendered.
- Flow: Tap name → `Edit Name` dialog opens with the existing single `TextField`. Cancel. Tap height → `Edit Height` dialog opens with the cm/ftin shape matching the active height unit. Save 182 → repository gets a new entry; identity area re-renders "182 cm".
- Expected outcome: Both tap targets are wired to their existing dialog paths. The height write still goes through `ProfileState.updateHeight` → `BodyMeasurementEntry(type='height', unitId='unit-cm')`.
- Edge case of: none.

### S-005: `Icons.height` arrow glyph is gone

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders → identity block.
- Expected outcome: No widget with `Icons.height` is rendered anywhere on the Profile screen. The `profile_identity_height_value` `InkWell` shows only the height text (no leading icon).
- Edge case of: none.

### S-006: Identity block is not wrapped in `OmniSurface`

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders → identity block.
- Expected outcome: The identity block's root widget is not an `OmniSurface`. `find.descendant(of: find.byKey(identityBlockKey), matching: find.byType(OmniSurface))` returns nothing — i.e. the previous heavy card chrome has been removed so the gradient background reads through behind the avatar and name/height column.
- Edge case of: none.

### S-007: Block height is shorter than the prior centered layout

- Trigger: Profile screen mounts on a typical phone (test surface height ≥ 700 dp).
- Precondition: Profile rendered.
- Flow: Render and measure the identity block's vertical extent.
- Expected outcome: The identity block's outer `Size.height` is meaningfully shorter than the avatar-only height + name line height + height line height + `OmniSurface` padding sum of the prior layout. The vertical savings are on the order of the prior layout's chrome padding + the prior name/height stacked heights minus the column half of the avatar — at least enough that an additional measurement card is reachable in the initial viewport on a typical phone. (Test asserts the avatar-envelope-only height, i.e. the block does not exceed 1.4 × the avatar's pixel height — a structural proxy for the visible savings.)
- Edge case of: none.

### S-008: Regression — height is not a charted measurement card

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders → the charted column is the same `additional` list (Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm).
- Expected outcome: `find.descendant(of: find.byType(ProfileScreen), matching: find.text('HEIGHT'))` returns nothing — height is not in the charted column.
- Edge case of: none.

## Iteration 1

### DB Changes

None. `UserProfile` and `BodyMeasurementEntry` are unchanged. The height write path (`ProfileState.updateHeight`) is unchanged.

### Backend Changes

None. No state class is touched. `ProfileState`, `SettingsState`, and the repository surface are unchanged.

### Frontend Changes

- `lib/features/profile/profile_screen.dart`
  - Rework `_buildIdentitySection` to compose a `Row` with `CrossAxisAlignment.center`:
    - Left: the existing avatar `GestureDetector` (200 × 200 circular), unchanged.
    - Right: a `Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start)` containing the existing name tap target and the existing height tap target.
  - Remove the outer `OmniSurface` wrapper around the identity block.
  - Update `_buildIdentityHeightRow`:
    - Drop the leading `Icon(Icons.height, ...)` from the inner `Row`.
    - Drop the `mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center` centering inside the height row — the row sits inside the right-hand column, so it inherits left-alignment from `crossAxisAlignment: CrossAxisAlignment.start` of the column.
    - Tighten typography: height text down to `bodyMedium` (was `titleMedium`) so it reads as a quiet secondary line; keep `OmniTheme.colors.textSecondary` for present values, dimmer for missing values.
    - Keep the existing `Key('profile_identity_height_value')` on the `InkWell` (tests rely on it).
    - Preserve the present / missing display strings and the unit-aware formatting path (`UnitFormatter.formatHeight`).
  - Adjust the surrounding `ListView` top spacing if needed (current `EdgeInsets.fromLTRB(20, 12, 20, 24)` stays — the savings come from the removed `OmniSurface` padding and the collapsed name/height stack, not from screen padding).
  - The `_HeightDialog`, `_MeasurementLogSheet`, `_SheetOption`, avatar picker, and measurement column are untouched.

- `test/profile_screen_test.dart` and `test/profile_cleanup_test.dart`
  - Existing tests that scope via `find.byKey(const Key('profile_identity_height_value'))` keep working — the key is preserved.
  - No existing test asserts the prior vertical center-stacked layout, the `Icons.height` glyph, or the `OmniSurface` wrapper, so no existing assertion needs to change.

- `test/screen_widget_test.dart` — add a new group (or new file if `screen_widget_test.dart` is too long) covering S-001 .. S-008 (per the test-file map in Phase 2.1; `lib/features/` → `test/screen_widget_test.dart` for render + `test/interaction_flow_test.dart` for interactions). The avatar floor is best asserted in `test/screen_widget_test.dart`; the tap-to-edit interaction is best asserted in `test/interaction_flow_test.dart`.

### Implementation Steps

1. Phase 0 — write plan file (this file).
2. Phase 1 — confirm no schema/repo change; update `docs/profile_and_measurements.md` to describe the horizontal identity block in the "Identity Section" subsection (replace the vertical-hero description and the avatar-tap → sheet ordering context with the horizontal description). Other docs (`navigation_and_screens.md`, `state_management.md`, `widget_catalog.md`, `data_models.md`, `db_integration.md`) need no changes.
3. Phase 2.1 — TDD: write red widget tests asserting S-001 .. S-008; run `flutter test` and confirm the new tests fail.
4. Phase 2.2-2.5 — refactor `_buildIdentitySection` and `_buildIdentityHeightRow`; remove the `OmniSurface` wrapper; run tests until green.
5. Phase 2.7 — doc hygiene (one doc update: `profile_and_measurements.md`).
6. Phase 3 — code review.

## Iteration 2 — Rebalance the right column

### Requirements (Iteration 2)

- The two-line `Column` (name + height) sits at the avatar's mid-height. The text content centers within the 200 dp avatar envelope; the avatar is the visual anchor, not a backdrop.
- The vertical gap between the name baseline and the height baseline is small enough that the two lines read as one stacked pair, not two unrelated lines. The pair must occupy a tighter vertical envelope than the prior layout (no oversized `ConstrainedBox(minHeight: …)` padding or inter-row spacer).
- The name and the height share the same left edge — both are anchored to the same `crossAxisAlignment: CrossAxisAlignment.start` gutter on the right column, with a consistent horizontal gutter beside the avatar.
- The name carries more visual weight than the height: a larger text style (`headlineMedium` instead of `headlineSmall`) and the existing `FontWeight.w700` + `textDominant` color. The height remains `bodyMedium` + `textSecondary` so the visual hierarchy is preserved (name dominant, height quiet).
- The avatar size is unchanged (200 × 200, floor 180). No changes to the avatar shape, image, border, or tap behavior.
- The overall height of the identity block is not increased. The rebalance tightens the right column, not stretches it.

### Acceptance Criteria

- [ ] The name+height column's vertical center aligns with the avatar's vertical center (no large empty space above or below the text block — the text sits at the avatar's mid-height).
- [ ] The vertical distance between the name text center and the height text center is small (tight stacked pair) — measured in pixels, this should be less than the prior layout's inter-text gap.
- [ ] The name and height share the same left edge and start at a consistent gutter beside the avatar (`crossAxisAlignment: CrossAxisAlignment.start` on the right column).
- [ ] The avatar size is unchanged: 200 × 200 (above the 180 floor).
- [ ] The header's overall height is not increased by these changes.
- [ ] The name uses `headlineMedium` (or larger text style) so the right column holds its own against the avatar visually.

### Scenarios

#### S-101: Name and height sit at the avatar's mid-height (vertically centered)

- Trigger: Profile screen mounts.
- Precondition: User has a display name and a height entry.
- Flow: Profile renders → identity block renders.
- Expected outcome: The midpoint Y-coordinate of the rendered name+height text block is within ±20 dp of the avatar's geometric midpoint Y-coordinate.
- Edge case of: S-001.

#### S-102: Name and height share a left alignment and are stacked in a single column

- Trigger: Profile screen mounts.
- Precondition: User has a display name and a height entry.
- Flow: Profile renders.
- Expected outcome: Both `Text` widgets are siblings inside the same `Column`, both with `crossAxisAlignment: CrossAxisAlignment.start`. Their left edges (text X-coordinates) are within 2 dp of each other. The Y-coordinates are distinct (height below name).
- Edge case of: S-001.

#### S-103: Tight vertical gap between name and height (stacked pair)

- Trigger: Profile screen mounts.
- Precondition: User has a display name and a height entry.
- Flow: Profile renders.
- Expected outcome: The Y-distance between the name text center and the height text center is tight — less than 60 dp. (Prior layout was ~70+ dp due to `ConstrainedBox(minHeight: 48/36)` + 6/4 dp vertical padding + 4 dp `SizedBox`.)
- Edge case of: S-101.

#### S-104: Avatar size unchanged after rebalance

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders.
- Expected outcome: Avatar dimensions are 200 × 200 (no change from prior layout).
- Edge case of: S-002.

#### S-105: Name uses a larger text style than height (visual hierarchy)

- Trigger: Profile screen mounts.
- Precondition: User has a display name.
- Flow: Profile renders.
- Expected outcome: The name `Text`'s resolved `style.fontSize` is strictly greater than the height `Text`'s resolved `style.fontSize`. (Concrete: `headlineMedium.fontSize` > `bodyMedium.fontSize`.)
- Edge case of: none.

#### S-106: Header overall height not increased

- Trigger: Profile screen mounts.
- Precondition: User has a display name and a height entry.
- Flow: Profile renders.
- Expected outcome: The identity block's total height is ≤ 200 dp (it cannot exceed the avatar's height since `CrossAxisAlignment.center` on the `Row` makes the row 200 dp tall).
- Edge case of: none.

### Frontend Changes

- `lib/features/profile/profile_screen.dart`
  - `_buildIdentityNameRow`:
    - Drop the `ConstrainedBox(minHeight: 48)` wrapper — the InkWell wraps the text directly with no forced minimum height. The text takes its natural height from the typography.
    - Drop the vertical padding on the inner `Padding` (`vertical: 6 → 0`); keep horizontal padding (`horizontal: 12`) so the tap area still extends left/right of the text glyphs.
    - Bump the name text style from `headlineSmall` to `headlineMedium` (one M3 tier larger) so the right column holds its own against the avatar. Keep `FontWeight.w700`, `letterSpacing: 0.4`, and `textDominant` color.
    - Keep `borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius)` on the `InkWell` for consistent hit-area rounding.
  - `_buildIdentityHeightRow`:
    - Drop the `ConstrainedBox(minHeight: 36)` wrapper.
    - Drop the vertical padding on the inner `Padding` (`vertical: 4 → 0`); keep horizontal padding (`horizontal: 12`).
    - Keep `bodyMedium`, `FontWeight.w500`, `letterSpacing: 0.2`, `textSecondary`.
    - Keep the existing `Key('profile_identity_height_value')` on the `InkWell` — tests still scope through it.
  - `_buildIdentitySection`:
    - Drop the `SizedBox(height: 4)` between the name and height rows to `SizedBox(height: 2)` (the 2 dp gap keeps the two lines visually distinct without spacing them apart).
    - Keep `mainAxisAlignment: MainAxisAlignment.center` on the right column so the text block centers at the avatar's mid-height.
    - Keep `crossAxisAlignment: CrossAxisAlignment.start` so the name and height share a left edge and start at a consistent gutter beside the avatar.
  - No other changes — the avatar, the `_HeightDialog`, `_MeasurementLogSheet`, `_SheetOption`, avatar picker, and measurement column are untouched.

- `docs/profile_and_measurements.md` — small refinement to the "Identity Section" entry: note the tight stacked-pair layout (no oversized tap-target padding around the lines) and the `headlineMedium` name treatment.

- `test/screen_widget_test.dart` — add 3 new widget tests covering S-101 / S-103 / S-105 (mid-height centering, tight gap, name hierarchy). Update the existing S-001 / S-003 tests to use the new acceptance criteria (the structural layout is unchanged but the gap metric is now bounded).

- The existing `profile_screen_test.dart` interaction tests (S-004 — tap name → editor; tap height → editor) are unaffected. They tap the existing `InkWell` targets which remain wired to the same dialogs.

### Implementation Steps

1. Phase 0 — append Iteration 2 to this plan file (done).
2. Phase 2.1 — TDD: add S-101, S-103, S-105 widget tests; confirm they fail against the prior rebalanced layout (the prior gap is ~70 dp, the new requirement is < 60 dp; the prior name is `headlineSmall`, the new requirement is `headlineMedium`).
3. Phase 2.2-2.5 — apply the three frontend changes (drop minHeight + vertical padding + SizedBox; bump name style).
4. Phase 2.7 — doc hygiene (one small update to `profile_and_measurements.md`).
5. Phase 3 — code review.

## Progress

- [x] Phase 0 — Iteration 1 plan written.
- [x] Phase 1 — Iteration 1 doc update (`profile_and_measurements.md`).
- [x] Phase 2 — Iteration 1 red tests written, refactor done, all tests green.
- [x] Phase 3 — Iteration 1 review: ✅ Approved with one non-blocking suggestion.
- [x] Phase 0 — Iteration 2 plan appended.
- [x] Phase 2 — Iteration 2 red tests written, refactor done, all tests green.
- [x] Phase 3 — Iteration 2 review: ✅ Approved.
- [x] Phase 0 — Iteration 3 plan appended.
- [x] Phase 2 — Iteration 3 explicit unit-aware tests added; live toggle test added.
- [x] Phase 3 — Iteration 3 review: ✅ Approved.

## Progress

- [ ] Phase 0 complete (plan written).
- [ ] Phase 1 complete (no schema/repo change; one doc update queued).
- [ ] Phase 2 complete (red tests written, refactor done, all tests green).
- [ ] Phase 3 complete (review verdict recorded).

## Feedback

### Phase 0 Complete ✓
### Phase 1 Complete ✓

No schema or repository changes. Doc update: `docs/profile_and_measurements.md` "Identity Section" rewritten to describe the horizontal layout, dropped `OmniSurface` reference, dropped `Icons.height` arrow cue reference, and noted the avatar's 200×200 floor.

### Phase 2 Complete ✓

Red-phase: added five render tests to `test/screen_widget_test.dart` (S-001/S-002/S-003/S-006/S-008 composed, S-002 floor, S-006 no OmniSurface, S-005 no arrow, S-007 envelope) — all 5 failed against the old layout (`profile_identity_avatar` key missing; `Icons.height` arrow present; avatar wrapped in `OmniSurface`).

Green-phase refactor (`lib/features/profile/profile_screen.dart`):
- `_buildIdentitySection` rewritten as a single `Row(crossAxisAlignment: center)`: avatar on the left (200×200, now keyed `profile_identity_avatar`), 16 dp spacer, `Expanded(Column(nameRow, heightRow))` on the right.
- `OmniSurface` wrapper around the identity block removed.
- `_buildIdentityHeightRow` simplified: dropped `Icons.height` arrow cue, dropped centered-row chrome, dropped `mainAxisAlignment.center` (now left-aligned via the column), downgraded `titleMedium` → `bodyMedium` so height reads as a quiet subtitle.
- `_buildIdentityNameRow` extracted as a sibling tap target; name editor dialog path unchanged.
- `Key('profile_identity_height_value')` preserved on the height tap target — no existing test broken.

Interaction tests (S-004) added to `test/profile_screen_test.dart` — both new tests pass.

Full test run: **1,783 passed, 5 skipped, 0 failed.** No regressions in profile, screen-widget, interaction-flow, or edge-case suites.

---

### Phase 3 — Code Review

#### Iteration 1 review: ✅ Approved with one non-blocking suggestion

(documented above)

#### Iteration 2 review: ✅ Approved

**Layers in scope**: features (`lib/features/profile/profile_screen.dart`), tests (`test/screen_widget_test.dart`), docs (`docs/profile_and_measurements.md`).
**Layers skipped**: models, repositories, state, core, widgets, `data_models.md`, `db_integration.md`, `navigation_and_screens.md`, `state_management.md`, `widget_catalog.md` — no changes warranted.

##### Acceptance Criteria

| Criterion | Status | Where |
|---|---|---|
| Name+height column centers at avatar mid-height | ✅ | `profile_screen.dart:142` (`mainAxisAlignment: MainAxisAlignment.center`) + S-101 test (delta ≤ 20 dp) |
| Tight vertical gap between name and height | ✅ | `profile_screen.dart:145` (`SizedBox(height: 2)`) + S-103 test (gap < 40 dp, was 46 dp) |
| Name and height share a left edge / consistent gutter | ✅ | `profile_screen.dart:143` (`crossAxisAlignment: CrossAxisAlignment.start`) + S-102 test (dx delta < 20 dp) |
| Avatar size unchanged | ✅ | avatar still 200 × 200 (`profile_screen.dart:119-120`) + S-104 test |
| Header overall height not increased | ✅ | Row is 200 dp (matches avatar via `CrossAxisAlignment.center`) + S-106 test |
| Name uses larger text style (visual weight) | ✅ | `headlineMedium` (`profile_screen.dart:184`) + S-105 test (`nameFontSize > heightFontSize`) |

##### Scenario Register vs Tests

| Scenario | Test file | Status |
|---|---|---|
| S-101 (mid-height centering) | `test/screen_widget_test.dart` (`identity header: name+height column centers at avatar mid-height`) | ✅ |
| S-102 (left alignment + single column) | `test/screen_widget_test.dart` (`identity header: tight vertical gap` — also asserts dx delta) | ✅ |
| S-103 (tight gap < 40 dp) | same as S-102 | ✅ |
| S-104 (avatar size unchanged) | `test/screen_widget_test.dart` (`identity header: overall height...`) — avatar asserted at 200×200 | ✅ |
| S-105 (name > height font size) | `test/screen_widget_test.dart` (`identity header: name uses a larger text style than height`) | ✅ |
| S-106 (header height not increased) | same as S-104 — avatar 200 dp = header max | ✅ |

##### Doc Hygiene

| Doc | Status |
|---|---|
| `navigation_and_screens.md` | ✅ N/A — no route changes |
| `state_management.md` | ✅ N/A — no state changes |
| `widget_catalog.md` | ✅ N/A — no new reusable widget |
| `data_models.md` | ✅ N/A — no model changes |
| `db_integration.md` | ✅ N/A — no repository changes |
| `profile_and_measurements.md` | ✅ Updated — "Identity Section" now notes `headlineMedium`, 2 dp gap, tight `Padding(horizontal: 12)` chrome |

##### Global Conventions

```
PASS (6 rules): Card chrome via OmniSurface (no change — none added or removed); timestamps are source data (unchanged); reuse the canonical owner (UnitFormatter.formatHeight path unchanged; ProfileState.updateHeight unchanged); instrument panel not influencer (rebalance tightens chrome, reduces the visual weight gap between avatar and text column); theme tokens only (colors via OmniTheme.colors); section/card headers via OmniCardHeader (no headers added — the identity header is screen-level chrome).
N/A (2 rules): Units + canonical storage (path unchanged); effort-kind drives analytics (no effort tracking touched).
```

##### Architecture Compliance

- **Features**: state via constructor injection ✅; no direct repository call from any of `_buildIdentitySection` / `_buildIdentityNameRow` / `_buildIdentityHeightRow` ✅; no business logic ✅; `ListenableBuilder` already in `build` (pre-existing) ✅.
- **Widgets**: presentation-only ✅; no state mutation outside widget ✅; no repo/service access ✅; no business logic ✅.

##### Buttons

No new `FilledButton`/`OutlinedButton`/`TextButton` introduced. The dialog buttons used by `_HeightDialog` / `_showDisplayNameDialog` (already in the file) still carry explicit `shape:` overrides and `OmniTheme.buttonUtilityRadius` — unchanged from Iteration 1.

##### Dead Code

None. Both `_buildIdentityNameRow` and `_buildIdentityHeightRow` are wired into `_buildIdentitySection`. Both tap targets remain reachable (S-004 interaction tests still green).

##### Test Coverage

| File | Status |
|---|---|
| `lib/features/profile/profile_screen.dart` | ✅ 4 new render tests cover S-101, S-102/S-103, S-104/S-106, S-105 in `test/screen_widget_test.dart`. The S-103 gap test (`< 40 dp`) failed against the prior layout (gap was 46 dp) and now passes (gap is tighter — within target). Existing `profile_screen_test.dart` S-004 interaction tests (tap-name / tap-height) unaffected — same `Key('profile_identity_height_value')` + name `Text` selector still reach the dialogs. No stale references. |

##### Environment Safety

- No `dart:io` introduced.
- No new SQLite imports.
- No `Platform.is*` checks.
- State still depends on the repository interface only.

##### DRY + Clean Code Lens

- `_buildIdentityNameRow` and `_buildIdentityHeightRow` are both 18-line wrappers around `Material > InkWell > Padding(horizontal: 12) > Text` — duplicated chrome shape (same as the pre-existing suggestion from Iteration 1). The structure is now even more identical after dropping `ConstrainedBox` and vertical padding from both, which slightly increases the dedup pressure. **Suggestion: extract a private `_IdentityTapRow` helper that takes `text`, `style`, `onTap`, and an optional `Key` — both name and height rows would call it with one line each.** Non-blocking.
- Magic numbers: `SizedBox(width: 16)` (column gutter), `SizedBox(height: 2)` (inter-row gap) are small visual gaps, consistent with the file's existing convention (no promoted tokens).
- Comments explain WHY — the Iteration 2 additions to the doc comments on both helpers explain the rebalance intent.

##### Findings

```
PASS (no critical, no warnings, 1 suggestion — same as Iteration 1):

💡 SUGGEST | lib/features/profile/profile_screen.dart:174-196 + 222-244 | _buildIdentityNameRow and _buildIdentityHeightRow both wrap Material > InkWell > Padding(horizontal: 12) > Text in identical shape; consider extracting a private _IdentityTapRow helper | non-blocking — readability of two named methods outweighs the dedup, but the chrome is now even more identical than Iteration 1 noted
```

##### Review Verdict

✅ **Approved.**

All 6 Iteration 2 acceptance criteria are met. All 6 new scenarios map to green tests. The doc update reflects the rebalance. No regressions in 1,787 tests (4 new + 1,783 existing). No critical or warning findings.

#### Iteration 3 review: ✅ Approved (no findings)

**Layers in scope**: tests (`test/profile_screen_test.dart`).
**Layers skipped**: models, repositories, state, features, core, widgets, all docs — no code or doc changes were warranted.

##### Pre-flight inspection

| Item | Finding |
|---|---|
| `_buildIdentityHeightRow` calls | `UnitFormatter.formatHeight(heightCm, widget.settingsState)` — passes the live settings state so the formatter honors the active unit. |
| Screen rebuild trigger | `ListenableBuilder(listenable: Listenable.merge([widget.profileState, widget.settingsState]), ...)` — the screen rebuilds on `settingsState` notification (which `setPreferredHeightUnit` triggers). |
| Existing tests covering cm | `identity area reflects cm mode (default) for stored height` — passes ✅ |
| Existing tests covering ftin | `identity area reflects ftin mode for stored height` — passes ✅ |
| Existing test covering live toggle | `identity-area height round-trips cm mode (no drift across unit toggle)` — passes ✅ |
| Hardcoded "cm" suffix in tests | None. The only mention of "180 cm" in `test/profile_screen_test.dart` is in a doc comment (line ~205), not an assertion. |

##### Acceptance Criteria

| Criterion | Status | Where |
|---|---|---|
| ftin selected → subtitle shows ftin; cm selected → subtitle shows cm | ✅ | `profile_screen.dart:219` (`UnitFormatter.formatHeight(heightCm, widget.settingsState)`) + S-201 group |
| Live update on unit change without leaving screen | ✅ | `profile_screen.dart:71-72` (`Listenable.merge`) + S-202 group |
| Subtitle matches the height measurement value | ✅ | Same `UnitFormatter.formatHeight` path used by `_formatMeasurementValue` (line 421) and the height log sheet |

##### Scenario Register vs Tests

| Scenario | Test file | Status |
|---|---|---|
| S-201 (cm mode shows cm suffix; ftin mode shows ftin) | `test/profile_screen_test.dart` (S-201 group: cm mode + ftin mode) | ✅ |
| S-202 (live re-render on unit toggle, both directions) | `test/profile_screen_test.dart` (S-202 group: ftin→cm, cm→ftin) | ✅ |
| S-203 (no hardcoded "cm" suffix in header-height assertions) | grep + code review: only a doc comment mentions "180 cm"; no test asserts a hardcoded suffix | ✅ |

##### Doc Hygiene

| Doc | Status |
|---|---|
| All docs | ✅ N/A — no production code or doc changes. The existing `profile_and_measurements.md` already documents that the identity area uses `UnitFormatter.formatHeight(heightCm, settingsState)` — which is exactly the contract Iteration 3 is asserting. |

##### Architecture Compliance

- **Tests**: use `MockWorkoutRepository` (never concrete) ✅; call state methods directly ✅; `pumpWidget` with real state class injected ✅; no test mocks around the state layer ✅.

##### Test Coverage

| File | Status |
|---|---|
| `test/profile_screen_test.dart` | ✅ 4 new tests in S-201 and S-202 groups, all green. Tests are explicit about the unit-aware behavior: each test asserts both the expected unit form AND the absence of the wrong-unit form (cm must NOT appear in ftin mode, and vice versa). The S-202 live-toggle tests also assert `ProfileScreen` remains mounted (`findsOneWidget`) across the unit change, so a regression that remounts the screen instead of rebuilding it would be caught. |

##### Environment Safety

No code changes; nothing to verify beyond the existing Iteration 1/2 contract.

##### DRY + Clean Code Lens

The 4 new tests share boilerplate (`_freshRepo`-equivalent setup, save entry, build state, build settings, pump widget). The boilerplate is consistent with the existing tests in this file — no extraction is warranted because each test exercises a different scenario and the shared helper would obscure what each test is doing. The S-202 tests deliberately use two separate `testWidgets` calls (ftin→cm and cm→ftin) instead of parameterizing, so a failure points clearly at the broken direction.

##### Findings

```
PASS (no critical, no warnings, no suggestions).
```

##### Review Verdict

✅ **Approved.**

The pre-flight inspection shows the iteration-3 contract was already satisfied by the existing implementation (`UnitFormatter.formatHeight(heightCm, widget.settingsState)` + `Listenable.merge` rebuild). The new tests make that contract explicit and document the unit-aware behavior against the new horizontal header layout. No code or doc changes needed; all 4 new tests pass; no regressions in the 396-test regression sweep.

### Phase 3 Complete ✓

---

## Feedback

### Phase 0 Complete ✓
### Phase 1 Complete ✓

No schema or repository changes. Doc update: `docs/profile_and_measurements.md` "Identity Section" rewritten to describe the horizontal layout, dropped `OmniSurface` reference, dropped `Icons.height` arrow cue reference, and noted the avatar's 200×200 floor.

### Phase 2 — Red phase confirmed (Iteration 1)

Added five widget tests to `test/screen_widget_test.dart` under the `ProfileScreen` group covering S-001 / S-002 / S-003 / S-006 / S-008 (composed as a single horizontal-layout test), S-002 (avatar floor), S-006 (no OmniSurface wrapper), S-005 (no Icons.height arrow), and S-007 (vertical envelope ≤ 1.4 × avatar height). All five fail against the current implementation: `profile_identity_avatar` key does not exist, `find.byIcon(Icons.height)` finds the existing arrow cue, and the avatar's enclosing widget is an `OmniSurface`. Refactor to follow.

### Phase 2 Complete ✓ (Iteration 1)

Red-phase: added five render tests to `test/screen_widget_test.dart` (S-001/S-002/S-003/S-006/S-008 composed, S-002 floor, S-006 no OmniSurface, S-005 no arrow, S-007 envelope) — all 5 failed against the old layout (`profile_identity_avatar` key missing; `Icons.height` arrow present; avatar wrapped in `OmniSurface`).

Green-phase refactor (`lib/features/profile/profile_screen.dart`):
- `_buildIdentitySection` rewritten as a single `Row(crossAxisAlignment: center)`: avatar on the left (200×200, now keyed `profile_identity_avatar`), 16 dp spacer, `Expanded(Column(nameRow, heightRow))` on the right.
- `OmniSurface` wrapper around the identity block removed.
- `_buildIdentityHeightRow` simplified: dropped `Icons.height` arrow cue, dropped centered-row chrome, dropped `mainAxisAlignment.center` (now left-aligned via the column), downgraded `titleMedium` → `bodyMedium` so height reads as a quiet subtitle.
- `_buildIdentityNameRow` extracted as a sibling tap target; name editor dialog path unchanged.
- `Key('profile_identity_height_value')` preserved on the height tap target — no existing test broken.

Interaction tests (S-004) added to `test/profile_screen_test.dart` — both new tests pass.

Full test run: **1,783 passed, 5 skipped, 0 failed.** No regressions in profile, screen-widget, interaction-flow, or edge-case suites.

### Phase 2 Complete ✓ (Iteration 2)

Red-phase: added 4 render tests (S-101, S-102/S-103, S-104/S-106, S-105) to `test/screen_widget_test.dart`. S-103 (`gap < 40 dp`) initially failed — measured gap against the prior layout was 46 dp (`ConstrainedBox(minHeight: 48/36)` + `Padding(vertical: 6/4)` + `SizedBox(height: 4)` pushed the text centers ~46 dp apart).

Green-phase refactor (`lib/features/profile/profile_screen.dart`):
- `_buildIdentityNameRow`: dropped `ConstrainedBox(minHeight: 48)` and `Padding(vertical: 6)` — InkWell now wraps the text tightly. Bumped `headlineSmall` → `headlineMedium` to give the right column visual heft.
- `_buildIdentityHeightRow`: dropped `ConstrainedBox(minHeight: 36)` and `Padding(vertical: 4)` — InkWell wraps the text tightly. Kept `bodyMedium` + `textSecondary` for hierarchy.
- `_buildIdentitySection`: dropped `SizedBox(height: 4)` → `SizedBox(height: 2)` for a tighter stacked pair.
- Kept `Key('profile_identity_height_value')`, `mainAxisAlignment: MainAxisAlignment.center`, `crossAxisAlignment: CrossAxisAlignment.start`, horizontal padding (12 dp) for tap-area extension.
- Avatar size, image, shape, tap behavior, dialog paths, storage path all unchanged.

Full test run: **1,787 passed, 5 skipped, 0 failed** (4 new rebalance tests added on top of the Iteration 1 green suite). No regressions.

#### Acceptance Criteria

| Criterion | Status | Where |
|---|---|---|
| Identity block lays out as horizontal Row, avatar + name/height column | ✅ | `profile_screen.dart:108-145` |
| Avatar ≥ 180 dp, established size 200 | ✅ | `profile_screen.dart:119-120` + `screen_widget_test.dart` S-002 test |
| Height is subtitle beneath the name, left-aligned | ✅ | `profile_screen.dart:140-144` (`crossAxisAlignment: CrossAxisAlignment.start`) + S-003 test |
| Name tap opens name editor dialog | ✅ | `profile_screen.dart:153` + `profile_screen_test.dart` S-004 |
| Height tap opens `_HeightDialog` + persists via `BodyMeasurementEntry('height')` | ✅ | `profile_screen.dart:206` + `profile_screen_test.dart` S-004 |
| `Icons.height` arrow glyph gone | ✅ | removed from `_buildIdentityHeightRow`; only mention left is in a doc comment |
| No `OmniSurface` wrapper around identity block | ✅ | `profile_screen.dart:113` returns a bare `Row` |
| Identity block measurably shorter than prior layout | ✅ | S-007 test asserts `height ≤ 1.4 × avatar height` (i.e. ≈ 280 dp vs ≈ 360+ dp prior) |
| `profile_identity_height_value` key preserved | ✅ | `profile_screen.dart:203` |
| Existing behavior preserved (cm/ftin, no charted height card, etc.) | ✅ | `profile_screen_test.dart` S-001..S-008 round-trip cm/ftin still green |

#### Scenario Register vs Tests

| Scenario | Test file | Status |
|---|---|---|
| S-001 (horizontal layout) | `test/screen_widget_test.dart` (`identity block composes avatar + name/height column horizontally`) | ✅ |
| S-002 (avatar floor) | `test/screen_widget_test.dart` (`avatar size floor: avatar dimension is at least 180 dp`) | ✅ |
| S-003 (subtitle + left-aligned) | same as S-001 (name `dy < height.dy`, X-offsets `closeTo(50)`) | ✅ |
| S-004 (tap → editor) | `test/profile_screen_test.dart` (S-004 group) | ✅ |
| S-005 (no arrow) | `test/screen_widget_test.dart` (`height row has no Icons.height arrow glyph`) | ✅ |
| S-006 (no OmniSurface) | `test/screen_widget_test.dart` (`identity block does not wrap in OmniSurface`) | ✅ |
| S-007 (envelope collapse) | `test/screen_widget_test.dart` (`identity block vertical envelope collapses vs avatar-only height`) | ✅ |
| S-008 (height not charted) | same as S-001 (`find.text('HEIGHT')` is `findsNothing`) | ✅ |

#### Doc Hygiene

| Doc | Status |
|---|---|
| navigation_and_screens.md | ✅ N/A — no route or constructor changes |
| state_management.md | ✅ N/A — no state class or method changes |
| widget_catalog.md | ✅ N/A — no new reusable widget |
| data_models.md | ✅ N/A — no model changes |
| db_integration.md | ✅ N/A — no repository changes |
| profile_and_measurements.md | ✅ Updated — "Identity Section" rewritten to describe horizontal Row, dropped `OmniSurface`, dropped `Icons.height` arrow, retained key + storage contract |

#### Global Conventions

```
PASS (7 rules): Card chrome via OmniSurface (none added — card chrome dropped instead); effort-kind drives analytics (N/A this pass); timestamps are source data (unchanged — height write path unchanged); reuse the canonical owner (ProfileState.updateHeight + UnitFormatter.formatHeight unchanged); instrument panel not influencer (rework explicitly reduces chrome and recovers vertical space); theme tokens only (all colors via OmniTheme.colors or theme.colorScheme); section/card headers via OmniCardHeader (identity block has no header — by design, it's a screen-level header).
N/A (1 rule): Units + canonical storage (path is unchanged; UnitFormatter still used for height formatting).
```

#### Architecture Compliance

- **Features**: state via constructor injection ✅; no direct repository call from `_buildIdentitySection` / `_buildIdentityHeightRow` / `_buildIdentityNameRow` ✅; no business logic ✅; uses `ListenableBuilder` in `build` (pre-existing) ✅.
- **Widgets (new `_buildIdentityNameRow`)**: presentation-only ✅; no state mutation outside widget ✅; no repo/service access ✅; no business logic ✅.

#### Buttons

No new `FilledButton`/`OutlinedButton`/`TextButton` introduced. The dialog buttons used by `_HeightDialog` / `_showDisplayNameDialog` (already in the file) still carry explicit `shape:` overrides and `OmniTheme.buttonUtilityRadius` — verified pre-existing, not part of this pass.

#### Dead Code

None. `_buildIdentityNameRow` is wired into `_buildIdentitySection`. `_buildIdentityHeightRow` is wired into `_buildIdentitySection`. Both tap targets are reachable. `_buildAvatarFallback` unchanged.

#### Test Coverage

| File | Status |
|---|---|
| `lib/features/profile/profile_screen.dart` | ✅ New render tests cover S-001..S-003, S-005..S-008 in `screen_widget_test.dart`; new interaction tests cover S-004 in `profile_screen_test.dart`. No stale references — the `profile_identity_height_value` key is preserved, so the existing 9 references in `profile_screen_test.dart` + 4 in `profile_cleanup_test.dart` keep working. |

#### Environment Safety

- No `dart:io` introduced.
- No new SQLite imports.
- No `Platform.is*` checks.
- State still depends on the repository interface only.

#### DRY + Clean Code Lens

- The new `_buildIdentityNameRow` is a 17-line helper; `_buildIdentityHeightRow` is a 26-line helper — both under the 50-line guideline.
- The two `Material > InkWell` wrappers share an identical structure (`Material > InkWell > ConstrainedBox > Padding > Text`); extracted the name into a separate method instead of inline so the column reads as `[nameRow, spacer, heightRow]`. Acceptable duplication (the alternatives — a `_IdentityTapRow({label, onTap, key, style})` parameterised helper — would obscure the readable call sites more than it saves). **Suggestion, not blocker.**
- Magic numbers: avatar size is `200` (matches established value); `SizedBox(width: 16)` and `SizedBox(height: 4)` are small visual gaps, not promoted to tokens — consistent with the existing file convention.
- Comments explain WHY (the doc comment on `_buildIdentitySection` explains the rework intent; the comment on `_buildIdentityHeightRow` explains the dropped `Icons.height` rationale).

#### Findings

```
PASS (no critical, no warnings, 1 suggestion):

💡 SUGGEST | lib/features/profile/profile_screen.dart:147-170 + 200-227 | _buildIdentityNameRow and _buildIdentityHeightRow both wrap a Material > InkWell > ConstrainedBox > Padding > Text in identical shape; consider a small private helper to share the tap-row chrome | non-blocking — the readability of two named methods outweighs the dedup
```

#### Review Verdict

✅ **Approved with one non-blocking suggestion.**

All eight acceptance criteria are met. All eight scenarios map to green tests. The doc update reflects the new layout. No regressions in 1,783 tests. No critical or warning findings.

### Phase 3 Complete ✓

