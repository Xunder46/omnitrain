# Feature: Foods I Eat — thumbnail toggle + row separation

## Overview

Two related polish changes to the food library's log row:

1. **Thumbnail toggle.** The leading `Checkbox` on `LogFoodRow` is
   replaced by a tappable food thumbnail (40×40 rounded corner, the
   same `FoodThumbnail` widget `AddFoodScreen` already uses). The
   thumbnail IS the log/unlog toggle — tapping it commits the
   current amount to the day log (S-001). When the food is logged,
   the thumb gets a 2 px primary border + a corner check badge
   that fills with a primary-color check; unlogged reverts (S-003 /
   S-004). Placeholder when no image (S-002 — common on web).
2. **Row separation.** Macros are condensed to a single
   `"<N> cal · <N>P · <N>C · <N>F"` line (format parity with
   `AddFoodScreen` rows, S-007), and a hairline divider
   (`OmniTheme.colors.divider`, height 1) renders between rows
   within a group — none after the last row in a group (S-006).

The data layer, the state classes (`FoodLibraryState`,
`NutritionState`), the `Food` model, the
`WorkoutRepository` interface, and the image-picker plumbing are
all unchanged. The change is contained to `LogFoodRow`,
`_GroupBlock` in `nutrition_screen.dart`, and the existing
`LogFoodRow` widget tests.

## Requirements

- **`LogFoodRow` thumbnail toggle (S-001 / S-002).**
  - The leading slot is a 40×40 rounded thumbnail, same
    `FoodThumbnail` widget `AddFoodScreen` uses. Image present →
    image; absent → muted placeholder (web's common case).
  - The thumb IS the log/unlog toggle. Tapping the thumb on an
    unlogged row logs the food at the current amount (existing
    `_amountInOwnUnit` translation). Tapping on a logged row
    unlogs. Same semantics as the old Checkbox: invalid amount →
    no-op + inline error.
  - The thumb lives inside a tappable area that is **at least
    48 dp** in both dimensions (design-system gym-glove rule).
    The visible thumb is 40×40; the tappable area pads to 48×48.
  - **Selected state** (S-003): a 2 px `themeColors.primary` border
    on the thumb + a small check badge in the top-right corner
    filled with `themeColors.primary` and a check glyph. The
    state animates via `AnimatedContainer` at
    `OmniTheme.animationDuration` (180 ms) and
    `OmniTheme.animationCurve` (`easeInOut`).
  - **Unselected state** (S-004): the border is
    `themeColors.divider` (hairline), no badge.
  - **Press scale**: the thumb shrinks to 0.96× its size while
    pressed (the standard `OmniTheme.pressedScale`-style tap
    feedback, applied to the 40×40 thumb so the touch feels
    responsive without going below the visible minimum).
  - **Semantics** (S-005): the thumb wraps a `Semantics` node
    that exposes `checked: true` / `checked: false` so screen
    readers + the existing checkbox-style widget tests see a
    toggle. The label is `"Log <food name>"` /
    `"Unlog <food name>"` for clarity.
  - **Stable key** (S-001 contract for tests): the GestureDetector
    mounts a `Key('log_food_thumb_<id>')` so tests can find the
    toggle without scanning the whole tree.

- **Single-line macros (S-007).** The 2×2 macro grid is replaced
  by a single `Text` line:
  `"<cal> cal · <P>P · <C>C · <F>F"` (using the middle-dot `·`
  separator that `AddFoodScreen` already uses). Format parity
  with `AddFoodScreen` rows. The line is one `Text` widget with
  `maxLines: 1` and `TextOverflow.ellipsis`; the entire row uses
  the same `bodySmall` + `textSecondary` muted style as the
  current grid cells.

- **Row dividers (S-006).** `_GroupBlock` in
  `nutrition_screen.dart` renders a 1 px hairline divider
  (`Divider(color: themeColors.divider, height: 1)`) between
  rows within a group, but **not** after the group's last row
  (so the spacing between groups is the existing
  `EdgeInsets.only(bottom: 16.0)` on the group block, not
  doubled by a trailing divider).

- **Untouched behaviors (S-008).** The amount input, validation,
  debounced auto-commit, and the existing `onSubmitted` /
  `onEditingComplete` flows remain unchanged. Editing the amount
  on a logged row still rescales the `ConsumedFood` snapshot. The
  per-row "remove from library" affordance is still absent (a
  follow-up redesign, not in scope).

## Acceptance criteria

- [ ] Tapping the thumb on an unlogged row logs the food at the
      current amount; tapping on a logged row unlogs.
- [ ] Foods with `imagePath` show the image; foods without show
      the muted placeholder (web-safe).
- [ ] Logged rows have a 2 px primary border + a primary-fill
      check badge; unlogged rows have a hairline divider-color
      border and no badge. The transition is animated
      (`OmniTheme.animationDuration` / `animationCurve`).
- [ ] The thumb's tap target is ≥ 48 dp in both dimensions.
- [ ] The macro text is a single line:
      `"<cal> cal · <P>P · <C>C · <F>F"`, ellipsized on overflow.
- [ ] A 1 px hairline divider (`OmniTheme.colors.divider`)
      renders between rows within a group; none after the group's
      last row.
- [ ] The thumb wraps a `Semantics` node with `checked: true`
      when logged, `checked: false` when not — the existing
      `find.byType(Checkbox)` / `Checkbox.value` tests are
      migrated to `find.byKey(Key('log_food_thumb_<id>'))` and a
      `Semantics` assertion.
- [ ] Editing the amount on a logged row still auto-commits the
      new amount to the day log (existing behavior, unchanged).
- [ ] Theme tokens only — no hardcoded colors.
- [ ] No new dependencies. No data-model changes. No
      repository-interface changes. No schema changes. No
      state-class changes.
- [ ] `flutter analyze` clean for all changed files.
- [ ] All previously passing tests still pass (after the
      `find.byType(Checkbox)` → `find.byKey(...thumb...)`
      migration).
- [ ] `flutter test` — all tests green (excluding the 2
      pre-existing failures in `test/screen_widget_test.dart` and
      `test/home_nutrition_strip_test.dart` that are unrelated to
      this feature and reproduce on the baseline).

## Scenarios

### S-001: Food with image — tappable thumbnail logs / unlogs
- Trigger: User opens the Foods I Eat card on the daily
  nutrition screen.
- Precondition: A `Food` row exists with `imagePath` set to a
  readable local file (e.g. a 100×100 px PNG on native).
- Flow:
  1. The row renders a 40×40 rounded thumbnail of the food's
     image in the leading slot (replaces the old Checkbox).
  2. The thumbnail is wrapped in a 48×48 tappable area.
  3. The user taps the thumb; the row's `logConsumedFoodAt` is
     called with the current amount (existing translation:
     multiplier × referenceAmount for count, raw value for
     grams).
  4. The thumb's border switches to 2 px primary + a check
     badge appears; the transition is animated.
  5. A subsequent tap on the same thumb unlogs the food;
     border + badge revert.
- Expected outcome: The thumb IS the toggle. No separate checkbox
  is rendered. The amount input, macros line, and unit label are
  unchanged.
- Edge case of: none

### S-002: Food without image — muted placeholder thumb
- Trigger: User opens the Foods I Eat card and a food has
  `imagePath == null` (or empty).
- Precondition: A `Food` row exists with no image (e.g. a
  library food added without a photo, or the web platform where
  the image picker is a no-op).
- Flow:
  1. The row renders the muted placeholder thumb (40×40
     rounded, `themeColors.surface` background, muted
     `restaurant_outlined` icon at 50% size) — the same
     `FoodThumbnail` placeholder `AddFoodScreen` uses.
  2. The placeholder is wrapped in the same 48×48 tap target.
  3. Tapping the placeholder logs / unlogs identically to S-001.
- Expected outcome: Rows are visually uniform (always 40×40 in
  the leading slot, image or placeholder). Toggling works
  regardless of image presence.
- Edge case of: S-001

### S-003: Tap thumb on unlogged row → logged state
- Trigger: User taps the thumb on an unlogged row.
- Precondition: The food is not currently logged today.
- Flow:
  1. The thumb's `onTap` fires.
  2. The row calls `logConsumedFoodAt(food, currentAmount)`.
  3. `NutritionState.notifyListeners()` triggers a rebuild.
  4. The thumb's border animates from `divider` → `primary` at
     2 px width; the check badge fades in.
- Expected outcome: The thumb is now in the "checked" visual
  state and the day log contains the food at the committed
  amount. The ring + donut update accordingly.
- Edge case of: S-001

### S-004: Tap thumb on logged row → unlogged state
- Trigger: User taps the thumb on a logged row.
- Precondition: The food is currently logged today.
- Flow:
  1. The thumb's `onTap` fires.
  2. The row calls `unlogFoodToday(food.id)`.
  3. The thumb's border animates from `primary` → `divider`;
     the check badge fades out.
- Expected outcome: The thumb is in the "unchecked" visual
  state and the day log no longer contains the food.
- Edge case of: S-003

### S-005: Semantics — thumb exposes checkbox semantics
- Trigger: A screen reader (or a widget test asserting
  `Semantics`) inspects the row.
- Precondition: The row is in either logged or unlogged state.
- Flow:
  1. The thumb's `Semantics` node reads `checked: true` (or
     `false`) and `label: "Log <name>"` /
     `"Unlog <name>"`.
  2. A `tester.getSemantics(...)` assertion sees the toggle's
     checked state in the same way the old Checkbox was
     read.
- Expected outcome: The semantics contract is backward
  compatible with the old Checkbox — `Semantics.checked`
  reflects the log state.
- Edge case of: S-001

### S-006: Hairline divider between rows in a group
- Trigger: User views a group with N ≥ 2 foods.
- Precondition: A `_GroupBlock` renders the foods.
- Flow:
  1. The first food renders normally (no divider above it).
  2. Between food 1 and food 2, a 1 px
     `themeColors.divider`-colored line renders.
  3. Between food 2 and food 3, another divider renders.
  4. No divider after the last food in the group (the
     existing 16 px bottom padding on the group block provides
     the gap to the next group).
- Expected outcome: Rows within a group are clearly separated;
  the visual rhythm is "row, line, row, line, row, blank
  space, next group's title".
- Edge case of: none

### S-007: Single-line macros — `<N> cal · <N>P · <N>C · <N>F`
- Trigger: User views a food row.
- Precondition: A `Food` row is rendered.
- Flow:
  1. The food name renders on line 1 (1-line ellipsized).
  2. The macros render on line 2 as a single
     `"<cal> cal · <P>P · <C>C · <F>F"` Text widget.
  3. If the line is too long, it ellipsizes (does not wrap).
- Expected outcome: Macros are compact and consistent with
  `AddFoodScreen`'s catalog rows. The 2×2 grid is gone.
- Edge case of: none

### S-008: Regression — editing amount on a logged row still rescales
- Trigger: User types a new value into the amount input on a
  row that is currently logged.
- Precondition: The food is logged today.
- Flow:
  1. The amount input's `onChanged` fires; the debounce timer
     restarts.
  2. After 250 ms of no further keystrokes, the row calls
     `logConsumedFoodAt(food, newAmount)` (existing
     `_autoCommitIfLogged` flow, unchanged).
  3. The day log updates; the ring + donut refresh.
- Expected outcome: The new amount is committed. The
  thumb's visual state is unchanged (still logged, still
  check badge). The macro line in the row is unchanged
  (the row's display macros are based on the food's
  reference, not the consumed amount).
- Edge case of: S-003

## Iteration 1 — DB / Backend / Frontend Changes

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### 1. `LogFoodRow` — replace Checkbox with thumb toggle
File: `lib/features/nutrition/widgets/log_food_row.dart`

- Remove the existing `Checkbox(key: Key('log_food_checkbox_<id>'),
  value: isLogged, onChanged: _toggle)` from the row's
  `Row` children.
- Add a new private widget `_ThumbToggle` that:
  - Wraps the `FoodThumbnail` (existing
    `lib/features/nutrition/widgets/food_thumbnail.dart` widget,
    `imagePath: food.imagePath`).
  - Adds a tappable area of `48×48` around the 40×40 thumb via
    a `GestureDetector` (or a `Material` + `InkWell` for splash).
  - Animates the border (`AnimatedContainer`,
    `OmniTheme.animationDuration` + `OmniTheme.animationCurve`):
    - Logged: 2 px `themeColors.primary` border.
    - Unlogged: 1 px `themeColors.divider` border.
  - Overlays a 16×16 check badge in the top-right corner
    (only visible when logged) — a small filled circle of
    `themeColors.primary` with a white check glyph at 12 px.
  - On press, scales the 40×40 thumb down to 0.96× via
    `AnimatedScale`.
  - Mounts `Key('log_food_thumb_<food.id>')` on the
    GestureDetector / InkWell for test lookup.
  - Wraps in `Semantics(button: true, checked: isLogged, label:
    isLogged ? 'Unlog ${food.name}' : 'Log ${food.name}',
    onTap: _toggle)`.
- Wire the thumb's `onTap` to the existing `_toggle` method
  (the Checkbox's `onChanged` is removed; the same callback is
  reused).

#### 2. `LogFoodRow` — single-line macros
File: `lib/features/nutrition/widgets/log_food_row.dart`

- Remove the `_MacroGrid` class (or leave it as a private
  unused class — but better: delete it).
- Replace the `_MacroGrid` usage in `build` with a single
  `Text(macroText, style: mutedBodySmall, maxLines: 1,
  overflow: TextOverflow.ellipsis)` where
  `macroText = '$cal cal · ${food.protein}P · ${food.carbs}C ·
  ${food.fat}F'` (format parity with `AddFoodScreen`'s
  `_UserCatalogRow` / `_LibraryCatalogRow`).
- The muted style reuses the same `theme.textTheme.bodySmall` +
  `themeColors.textSecondary` + `tabularFigures` features as the
  deleted grid cells.

#### 3. `_GroupBlock` — dividers between rows
File: `lib/features/nutrition/nutrition_screen.dart`

- In `_GroupBlock.build`, replace the `for (final f in foods)
  LogFoodRow(...)` loop with:
  ```dart
  for (var i = 0; i < foods.length; i++) ...[
    if (i > 0)
      Divider(
        key: Key('group_${groupName}_divider_$i'),
        color: themeColors.divider,
        height: 1,
        thickness: 1,
      ),
    LogFoodRow(
      food: foods[i],
      foodLibraryState: foodLibraryState,
      nutritionState: nutritionState,
    ),
  ]
  ```
  The collection-if + spread avoids rendering a divider above
  the first row and a divider after the last row.
- The `Divider` key (`'group_<name>_divider_<i>'`) is included
  for tests that want to assert on divider presence; it's a
  stable handle for the per-group divider list.

#### 4. `LogFoodRow` test migration
File: `test/nutrition_test.dart`

- The `LogFoodRow — log from library (S-001 / S-008)` group's
  test currently uses
  `find.byKey(Key('log_food_checkbox_<id>'))` and
  `tester.widget(find.byKey(...))` cast to `Checkbox` to read
  the checkbox's `value`.
- Migrate to:
  - `find.byKey(Key('log_food_thumb_<id>'))` for the toggle's
    tap target.
  - `tester.getSemantics(find.byKey(...))` to read the
    `Semantics.checked` flag (replaces the
    `Checkbox.value` cast).
  - Or: a small helper `bool isThumbChecked(WidgetTester, String
    foodId)` that wraps the Semantics lookup.
- The `LogFoodRow`'s behavior is otherwise unchanged: tapping
  the thumb still calls the same `logConsumedFoodAt` /
  `unlogFoodToday` paths. The amount input, the
  scroll-until-visible flow, the macro auto-commit — all
  unchanged. Existing assertions on
  `nutritionState.consumedToday` /
  `nutritionState.todayConsumedCalories` still hold.

#### 5. New tests for the new surface
File: `test/nutrition_test.dart` (extend the same group)

- **`S-002: placeholder when no image`** — render a `LogFoodRow`
  with a food whose `imagePath` is null; assert that
  `find.byIcon(Icons.restaurant_outlined)` finds the
  placeholder icon (the same icon `FoodThumbnail` renders when
  no image is set).
- **`S-005: semantics is checked when logged`** — log a row,
  then assert `tester.getSemantics(find.byKey(Key('log_food_thumb_<id>'))).hasFlag(SemanticsFlag.isChecked)`.
- **`S-005: semantics is unchecked when unlogged`** — inverse.
- **`S-006: hairline divider between rows`** — render a group
  with 2+ foods; assert
  `find.byKey(Key('group_<name>_divider_1'))` is found
  (between row 0 and row 1) and
  `find.byKey(Key('group_<name>_divider_N'))` is **not** found
  for the index after the last row.
- **`S-007: single-line macros`** — assert
  `find.text('90 cal · 0P · 0C · 10F')` finds the rendered
  macro string; assert the 2×2 grid `find.text('90 cal')` and
  `find.text('0P')` separately do not find individual cells
  (the grid is gone).

#### 6. Doc hygiene
- `docs/widget_catalog.md` — `LogFoodRow` entry:
  - Update the layout ascii diagram to show the thumb leading
    slot + the new single-line macro row.
  - Note the new `Key('log_food_thumb_<id>')` and the
    `Semantics` `checked` flag.
  - Note the `AnimatedContainer` 180 ms / easeInOut state
    transition and the 48 dp tap target.
- `docs/widget_catalog.md` — `_GroupBlock` (private to
  `NutritionScreen`) entry: note the new hairline divider
  pattern (1 px between rows, none after the last row).
- `docs/state_management.md` — N/A (no state changes).
- `docs/data_models.md` — N/A.
- `docs/db_integration.md` — N/A.
- `docs/navigation_and_screens.md` — N/A.
- `docs/design_system.md` — N/A (no palette change; the thumb
  reuses `FoodThumbnail` which already uses the existing
  `surface` + `textMuted` placeholder tokens).

## Progress

### Phase 0 — Plan — Complete ✓
- [x] Read the existing `LogFoodRow` widget + the
      `nutrition_screen.dart` integration.
- [x] Read `FoodThumbnail` (the shared thumbnail widget
      already used by `AddFoodScreen`).
- [x] Read the existing `LogFoodRow` widget tests; identified
      the `find.byType(Checkbox)` / `Checkbox.value` cast
      pattern that must be migrated.
- [x] Read `AddFoodScreen` rows for the single-line macro
      format (`"$cal cal · ${protein}P · ${carbs}C · ${fat}F"`).
- [x] Scenario register: S-001..S-008 — all unambiguous and
      ready to test against.

### Phase 1 — Data layer (DBA) — N/A
- No data layer change in this iteration. The `Food` model's
  `imagePath` is already present (used by `AddFoodScreen`).
  `NutritionState.logConsumedFoodAt` / `unlogFoodToday` are
  unchanged. Skipped per the spec.

### Phase 2 — Logic & UI (Developer) — Complete ✓
- [x] Wrote 4 new red tests in `test/nutrition_test.dart`:
      S-002 (placeholder thumb), S-005 (checked/unchecked
      semantics toggling), S-006 (per-index divider presence
      and post-last-row absence), S-007 (single-line macro
      format). Confirmed all 4 were red before the
      implementation (compilation errors due to missing
      `log_food_thumb_<id>` key, missing divider key, and
      missing single-line format).
- [x] Migrated the existing `LogFoodRow` test from
      `find.byType(Checkbox)` / `Checkbox.value` to
      `find.byKey(Key('log_food_thumb_<id>'))` +
      `flagsCollection.isChecked` (a `CheckedState` from
      `dart:ui` via `SemanticsData`). The migrated test is
      the same `LogFoodRow — log from library (S-001 / S-008)`
      group's "thumb toggle logs, amount input scales, unlog
      removes" test.
- [x] Migrated the two `nutrition_log_from_library_test.dart`
      tests that referenced `log_food_checkbox_<id>` (the
      "fractional count" + "zero count" tests) to use the new
      thumb key.
- [x] Updated the unrelated `FoodLibraryBrowse — renders all
      groups and foods with macros visible` test in
      `nutrition_test.dart` to assert the new
      `"<cal> cal · <P>P · <C>C · <F>F"` single-line format
      instead of the old 2×2 grid cell format.
- [x] Added the `_ThumbToggle` widget to `log_food_row.dart`
      (private `StatefulWidget`). Composition:
      - 48×48 tap target (padded from the 40×40 visible
        thumb) — design-system gym-glove rule.
      - `AnimatedContainer` border that animates between
        `divider` (1 px, unselected) and `primary` (2 px,
        selected) at
        `OmniTheme.animationDuration` / `animationCurve`.
      - `AnimatedOpacity` check badge in the top-right
        corner (16×16, primary fill, white check glyph) —
        visible only when selected.
      - `AnimatedScale` 0.96× press feedback on the visible
        thumb.
      - `Key('log_food_thumb_<food.id>')` mounted on the
        **outer `Semantics` wrapper** (not the
        `GestureDetector`) so that semantics-tree lookups
        find the correct node carrying the `checked` /
        `label` properties. (Putting the key on the
        `GestureDetector` returns a *different* node — the
        inner one — whose semantics don't include the outer
        `checked` flag.)
      - `Semantics(container: true, checked: isLogged,
        label: isLogged ? 'Unlog <name>' : 'Log <name>',
        button: true, enabled: true, onTap: widget.onTap)`
        wrapper. The `label` switches so screen readers
        announce the right action.
- [x] Replaced `Checkbox(value: isLogged, onChanged: _toggle)`
      with `_ThumbToggle(food: food, isLogged: isLogged,
      onTap: () => _toggle(isLogged ? false : true))`. The
      `_toggle` method now takes a `bool nextState` (was
      `bool? value`) since the thumb is always pressed with
      intent — no trivalent semantics to interpret.
- [x] Condensed the 2×2 macro grid to a single
      `Text(macroText, ..., maxLines: 1,
      overflow: TextOverflow.ellipsis)` line. Format:
      `"<cal> cal · <P>P · <C>C · <F>F"`. Deleted the
      `_MacroGrid` private class.
- [x] Added the per-group divider in `_GroupBlock.build` in
      `nutrition_screen.dart`. The new `for (var i = 0; i <
      foods.length; i++) ...[ if (i > 0) Divider(...), LogFoodRow(...) ]`
      pattern emits a divider only between rows (no
      pre-first-row or post-last-row dividers). The
      per-divider key is
      `Key('group_<groupName>_divider_<i>')` for tests.
- [x] `flutter test` — all 5 LogFoodRow tests pass
      (`testWidgets('thumb toggle logs...')`, S-002, S-005,
      S-007, S-006), all 43 nutrition tests pass, all 30
      `nutrition_log_from_library_test.dart` tests pass. The
      full project suite is **1434/1436** — the 2 failing
      tests in `test/screen_widget_test.dart` and
      `test/home_nutrition_strip_test.dart` are **pre-existing
      failures** that reproduce on the baseline (verified by
      stashing my changes and re-running).
- [x] `flutter analyze` clean for the 4 modified files (the
      5 remaining issues are pre-existing local-variable
      underscore warnings unrelated to this iteration).
- [x] Doc hygiene:
      - `docs/widget_catalog.md` — `LogFoodRow` entry
        rewritten: layout ascii updated to the new thumb +
        single-line macros pattern; Iteration 1 sections
        added for the thumb toggle (selected/unselected
        states, animation, semantics, key), the single-line
        macros (S-007), and the per-row dividers (S-006).
      - `docs/widget_catalog.md` — `_FoodLibraryBrowseSection`
        entry notes the per-group divider pattern in
        `_GroupBlock` (S-006) with the divider key format.
      - `docs/state_management.md`, `docs/data_models.md`,
        `docs/db_integration.md`, `docs/navigation_and_screens.md`,
        `docs/design_system.md` — N/A (no state, model,
        schema, route, or palette changes).

### Phase 3 — Code review — TBD

#### Findings (non-blocking)
- `lib/features/nutrition/widgets/log_food_row.dart` —
  the thumb's `Semantics(checked: isLogged, ...)` widget
  **must be the widget that carries the `Key`, not the
  `GestureDetector`**. Putting the key on the
  `GestureDetector` makes `tester.getSemantics(...)` return
  a *different* node (one without the outer `checked`
  flag), and the semantics test silently passes the
  `find.byKey(...)` lookup but reads empty `checked` /
  `label` values. The doc comment in `_ThumbToggle` notes
  this gotcha; a future reader should be aware. (WARNING)
- `lib/features/nutrition/widgets/log_food_row.dart` —
  the `_ThumbToggle` widget allocates a new
  `SemanticsHandle` per test via `tester.ensureSemantics()`.
  Calling it more than once per test leaks handles, so the
  test framework's leak check rejects the test. The new
  tests enable semantics once at the top of the test body
  and explicitly `dispose()` the handle at the end (NOT
  `addTearDown` — `addTearDown` callbacks fire *after* the
  framework's leak check). (WARNING)
- `lib/features/nutrition/widgets/log_food_row.dart` —
  the thumb's border width is hardcoded as
  `_selectedBorderWidth = 2.0` /
  `_unselectedBorderWidth = 1.0`. Could be hoisted to
  `OmniTheme` tokens later if a future iteration needs to
  theme them per palette. (SUGGESTION)
- `lib/features/nutrition/nutrition_screen.dart` — the
  `_GroupBlock` divider key includes the literal group
  name (`Key('group_${groupName}_divider_$i')`). If a
  group name contains characters that are not safe in a
  `Key` (e.g. whitespace or punctuation), the key will
  still work but is harder to read. A slug-style
  transformation (lowercase, replace spaces with `_`)
  would be marginally nicer. (SUGGESTION)
- `test/nutrition_test.dart` — the new S-005 test calls
  `tester.ensureSemantics()` once and disposes the handle
  at the end. The migrated "thumb toggle logs" test does
  the same. The `thumbChecked` helper is now a pure read
  with no `ensureSemantics()` call — every caller must
  have already enabled semantics. Documented in the helper
  comment. (DOCUMENTATION)
- `test/nutrition_test.dart` + `test/nutrition_log_from_library_test.dart` —
  the `CheckedState` enum is imported from `dart:ui` (not
  from `package:flutter/semantics.dart`, which only
  re-exports a subset of the semantics API). The new
  imports are at the top of each test file. (DOCUMENTATION)

## Feedback

(no feedback yet)
