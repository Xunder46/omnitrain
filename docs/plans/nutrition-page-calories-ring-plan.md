# Feature: Nutrition Page — Calorie Ring Header

## Overview

Replace the stub "Consumed Today" card at the top of `NutritionScreen` with a
ring/donut showing today's consumed calories against the user's daily calorie
target, filling as the day's foods are logged. Add a small icon button on or
beside the ring that opens the existing `NutritionTargetScreen` (the same
destination the bottom "Edit Targets" button navigates to). When no target is
set, the ring falls back to a consumed-only readout (no goal). When nothing is
logged yet, the ring renders as an empty track with an inviting "Log a food"
hint.

This is a UI change layered on top of the existing nutrition data layer. The
`ConsumedFood` model and `getConsumedFoodsForDate` repository method already
exist; `NutritionState.getTodayConsumedFoods` is currently a stub that needs a
real implementation that the ring can read from.

## Requirements

- Render a ring/donut at the top of `NutritionScreen` showing today's
  consumed calories vs the daily calorie target.
- Fill the ring proportionally as `consumed / target` (clamp to 1.0 — no
  overflow past full).
- Place a small icon button on or beside the ring that navigates to
  `NutritionTargetScreen` (replaces the existing bottom "Edit Targets"
  button — one affordance, top of page).
- When the target is unset (all four macros are 0, or `target.calories == 0`):
  show the consumed total alone in the center of the ring; do not error;
  do not draw a goal arc.
- When nothing is logged yet (consumed = 0):
  - If a target is set: render the ring as an empty track with the format
    "0 / <target> kcal" in the center, and a muted "Log a food to start
    filling" subtext.
  - If no target is set: render the ring as an empty track with "0 kcal"
    in the center and the same "Log a food to start filling" subtext.
- The ring updates as today's consumed foods change — the screen must
  re-read consumed data on init and on every `NutritionState` notification.
- No new dependencies. No data-model changes. No repository-interface
  changes. No new public state methods on `NutritionState` (extend existing
  `getTodayConsumedFoods` instead of adding a new one).

## Progress

### Phase 1 — Data layer (DBA) — Complete ✓
- [x] `NutritionState` exposes a real `consumedToday` cache, a derived
      `todayConsumedCalories` getter, and a real
      `loadConsumedToday()` / `getTodayConsumedFoods()` implementation
      backed by the repository.
- [x] Bonus: real `logConsumedFood(food, amount)` and
      `deleteConsumedFood(id)` go through the repository and keep the
      cache in sync, plus a `clearConsumedToday()` for the day-rollover
      path.
- [x] `test/state_test.dart` stub test replaced with a `consumed-food
      cache` group (4 tests) — all 192 tests in the file pass.
- [x] `test/nutrition_test.dart` — all 16 tests pass.
- [x] `flutter analyze lib/state/nutrition_state.dart` — clean.
- [x] No Flutter-import or platform-specific code added. No repository
      interface change. No schema change to `app_consumed_food` (the
      existing `IX_consumed_food_date` index supports the lookup).

### Phase 2 — `CalorieRing` widget (Developer) — Complete ✓
- [x] `lib/features/nutrition/widgets/calorie_ring.dart` created.
      `CustomPainter` paints the track + filled arc; centered `Column`
      renders the four label branches (target+consumed, target+empty,
      no-target+consumed, no-target+empty) with comma-grouped integers
      and `FontFeature.tabularFigures()` for stable alignment.
- [x] Fill fraction is `consumed / target` clamped to `0..1`; over-goal
      renders the real number in the center plus an `"over by N"`
      caption. No overflow past the track.
- [x] Colors come from `OmniTheme.colors` (track = `divider`, arc =
      `primary`). No hardcoded values. No Flutter framework imports
      beyond `material.dart`; web-safe.
- [x] `Semantics(container: true, label: ...)` announces
      `"Calories: X of Y"` (or `"X, no goal set"`) for screen readers.

### Phase 3 — `CalorieRingCard` wrapper (Developer) — Complete ✓
- [x] `lib/features/nutrition/widgets/calorie_ring_card.dart` created.
      `Card` + `Padding` + section title "Today" + `Center(CalorieRing)`.
- [x] Edit icon: `IconButton(Icons.tune)` with explicit
      `shape: RoundedRectangleBorder(borderRadius:
      BorderRadius.circular(OmniTheme.buttonIconRadius))` (avoids
      Material 3 `StadiumBorder` default per the design spec).
      `Key('edit_targets_icon')`, tooltip `"Edit targets"`.
- [x] `ListenableBuilder` over `nutritionState` so target load/save and
      consumed-food load/log/delete all rebuild the ring.
- [x] Treats `nutritionTarget.calories == 0` or `null` target as
      "no goal" (consumed-only mode).
- [x] Pure presentation — no repository access, no business logic.

### Phase 4 — Wire into `NutritionScreen` (Developer) — Complete ✓
- [x] Stub "Consumed Today" `Card` replaced with `CalorieRingCard`.
- [x] Bottom "Edit Targets" `FilledButton` removed.
- [x] `initState` now fires `_loadTodayTarget`, `_loadConsumedToday`,
      and `_loadLibrary` in parallel (all independent).
- [x] Returning from `NutritionTargetScreen` re-fires both target and
      consumed-food loads (symmetric path).
- [x] The screen still imports `OmniTheme` for the food-library rows
      and "no foods" muted text (used by existing helpers).

### Phase 5 — Widget tests for the card (Developer) — Complete ✓
- [x] `test/nutrition_test.dart` — new `CalorieRingCard` group with 7
      tests covering every scenario from the plan:
      1. renders consumed vs target when both present (S-001)
      2. updates ring as the day log changes (S-003, S-006)
      3. consumed-only when no target is set (S-002)
      4. empty ring invites setup when nothing logged (S-001/S-002
         empty branch)
      5. tapping the edit icon pushes `NutritionTargetScreen` (S-005)
      6. over-target: ring fills to 100% and shows "over by N"
         caption (S-004) — added in the post-review follow-up
      7. day rollover: `clearConsumedToday` drops ring to empty
         (S-007) — added in the post-review follow-up
- [x] Stale `NutritionScreen shows the Edit Targets button` test
      updated to assert the new icon affordance
      (`Key('edit_targets_icon')` present, `Edit Targets` text absent).
- [x] `flutter test test/nutrition_test.dart` — 23 / 23 pass.
- [x] `flutter test test/state_test.dart` — 192 / 192 pass (unchanged).
- [x] `flutter analyze lib/features/nutrition/
       lib/state/nutrition_state.dart` — `No issues found!`.

### Phase 6 — Visual polish + theme parity (Developer) — Complete ✓
- [x] All colors from `OmniTheme.colors`; no hardcoded values
      anywhere in the new widgets.
- [x] Buttons (the edit `IconButton`) use the explicit
      `RoundedRectangleBorder(radius: OmniTheme.buttonIconRadius)`
      override; never relies on Material 3 `StadiumBorder` default.
- [x] Typography matches the existing nutrition cards: `titleLarge`
      for the section title, `headlineSmall` w700 for the center
      value, `bodySmall` in `textMuted` for the subtext.
- [x] `Semantics` node wraps the painter+label so screen readers
      announce meaningful calorie state.
- [x] No animation in v1 (matches the plan's out-of-scope note).

### Doc Updates (mandatory)
- [x] `docs/state_management.md` — `NutritionState` section updated to
      document the new `consumedToday` / `todayConsumedCalories` /
      `loadConsumedToday()` / `getTodayConsumedFoods()` /
      `logConsumedFood` / `deleteConsumedFood` / `clearConsumedToday`
      surface. The `Stub Methods for Future Integration` note was
      replaced with a `Consumed-Food Cache` section pointing readers
      to the `Data Models` doc. `FoodLibraryState` consumer list now
      also lists the calorie ring.
- [x] `docs/navigation_and_screens.md` — `NutritionScreen` inventory
      row updated to describe the new ring-card header and the icon
      edit affordance. The flow diagram now shows
      `ring-card edit icon → NutritionTargetScreen` (instead of the
      removed "Edit Targets" button) in both the home-strip and hub
      branches.
- [x] `docs/widget_catalog.md` — new `CalorieRing` and
      `CalorieRingCard` sections with props, behavior, and theme
      token notes. Both are documented as presentation-only.

### Global Conventions (final, post-review)
- [x] `docs/global_conventions.md` re-read against the final
      implementation. Every applicable rule explicitly verified:
  - **Units + canonical storage** — N/A. Ring renders only `kcal`;
    no `WeightUnit` / `DistanceUnit` involvement; no persisted
    display-unit value.
  - **Theme tokens only** — PASS. Every color in the new widgets
    traces to `OmniTheme.colors` (grep verified; no hardcoded
    `Color(0x…)` or stray `Colors.x`).
  - **Effort-kind drives analytics** — N/A. Nutrition feature; no
    `SegmentEffort` / `effortKind` involvement.
  - **Timestamps are source data** — PASS. Ring reads pre-computed
    sums; the state itself uses `DateTime.now().millisecondsSinceEpoch`
    (wall-clock) when creating new `ConsumedFood` rows and
    `OmniDateUtils.todayMidnightMs()` for the day key. No local
    counters; no "elapsed since open" logic in the ring.
  - **Reuse the canonical owner** — PASS. Calorie math lives on
    `ConsumedFood.caloriesConsumed` and is summed by
    `NutritionState.todayConsumedCalories`; the ring just renders
    the pre-computed value. Theme selection is read once at the top
    of `build()` via `OmniTheme.colors`.
  - **Instrument panel, not influencer** — PASS. No animation in v1
    (per the plan's out-of-scope note). The "Log a food to start
    filling" subtext is functional (instructs the next action), not
    motivational. The ring is status-only.
- [x] Post-review follow-up added two new widget tests (S-004
      over-target, S-007 day-rollover visual) to close the
      coverage gaps flagged in the code review. No new
      implementation changes were required — the branches were
      already reachable in code; the tests just pin the contract.

## Acceptance Criteria

- [x] The top of `NutritionScreen` shows a calorie ring (consumed / target).
- [x] The ring fills as `consumed / target` (clamped to 0..1, no overflow).
- [x] A small icon button is visible on or beside the ring; tapping it
      pushes `NutritionTargetScreen` and reloads the target on return.
- [x] With no target set (calories target == 0), the ring area shows the
      consumed total only (no goal arc, no `/ <target>` text), with no
      error.
- [x] With nothing logged today, the ring renders as an empty track with
      an inviting subtext (no exceptions, no NaN, no division by zero).
- [x] The bottom "Edit Targets" button is removed; the icon on/near the
      ring is the only edit affordance.
- [x] The ring re-renders when a `ConsumedFood` is added or removed for
      today (i.e. on `notifyListeners` from the consumed-foods source of
      truth).
- [x] Ring colors come from the active theme (`OmniTheme.colors`) — no
      hardcoded colors.
- [x] No new dependencies added to `pubspec.yaml`.

## Scenarios

### S-001: Default state — target set, no foods logged
- Trigger: User opens `NutritionScreen` for the first time today
- Precondition: A daily target exists (e.g. 2000 kcal); no `ConsumedFood`
  rows exist for today's date
- Flow:
  1. `NutritionScreen.initState` calls `_loadTodayTarget()` and
     `_loadConsumedToday()` in parallel
  2. Both resolve; ring builds with `consumed = 0`, `target = 2000`
  3. Ring renders as an empty track (0% fill) with "0 / 2,000 kcal" in the
     center and "Log a food to start filling" subtext
  4. The edit icon is visible on/near the ring
- Expected outcome: Empty ring with inviting copy. No error. No `NaN`.
- Edge case of: none

### S-002: Default state — no target set, no foods logged
- Trigger: User opens `NutritionScreen` for the first time
- Precondition: No daily target exists (all four macros are 0); no
  consumed-food rows exist for today
- Flow:
  1. Both loads resolve; ring builds with `consumed = 0`,
     `target = null` (or `target.calories == 0`)
  2. Ring renders as an empty track with "0 kcal" in the center and the
     same "Log a food to start filling" subtext
  3. No goal arc is drawn (consumed-only mode)
- Expected outcome: Empty consumed-only ring, no error, no division by
  zero in the fill calculation.
- Edge case of: S-001

### S-003: Partially logged — target set, 1 food logged
- Trigger: User logs a food (e.g. 350 kcal) for today
- Precondition: Target is 2000 kcal; one `ConsumedFood` exists for today
  with `caloriesConsumed == 350`
- Flow:
  1. `NutritionState` notifies (consumed-foods cache mutated)
  2. The screen rebuilds; the ring shows `consumed = 350`,
     `target = 2000`
  3. Ring fills to 350 / 2000 = 17.5%; center reads "350 / 2,000 kcal"
- Expected outcome: Ring shows partial fill (17.5%); consumed value comes
  from summing `ConsumedFood.caloriesConsumed` for today.
- Edge case of: S-001

### S-004: Fully logged / over-target
- Trigger: User has logged more than the daily target today
- Precondition: Target is 2000 kcal; consumed total is 2350 kcal
- Flow:
  1. Ring builds with `consumed = 2350`, `target = 2000`
  2. Fill fraction is clamped to 1.0 — ring renders fully filled (100%)
  3. Center reads "2,350 / 2,000 kcal" (shows the real number, not the
     clamped one); a small "over by 350" or "✓ goal met" caption is
     shown
- Expected outcome: Ring is fully filled, the center shows the real
  total vs the target so the user can see they exceeded. No overflow
  painting past the track.
- Edge case of: S-003

### S-005: Tap the edit icon → targets screen
- Trigger: User taps the small edit icon on/near the ring
- Precondition: User is on `NutritionScreen`
- Flow:
  1. `OmniNavigator.push` to `NutritionTargetScreen` (same call as the
     existing bottom button)
  2. User edits, saves, and pops back
  3. `NutritionScreen._loadTodayTarget` re-fires in the `.then((_) …)`
     callback; the ring rebuilds with the new target
- Expected outcome: Targets screen opens; saving updates the ring on
  return. The bottom "Edit Targets" button is gone.
- Edge case of: none

### S-006: Consumed-food removed — ring decreases
- Trigger: User deletes a logged food for today
- Precondition: Consumed was 350 kcal; user deletes the entry; consumed
  is now 0
- Flow:
  1. `NutritionState` notifies (cache mutated)
  2. The screen rebuilds; ring shows `consumed = 0`, `target = 2000`
  3. Ring returns to empty-track state (S-001)
- Expected outcome: Ring shrinks back to empty. Update path is symmetric
  with S-003.
- Edge case of: S-003

### S-007: Day rollover — ring starts empty for the new day
- Trigger: Device clock crosses midnight
- Precondition: App re-detects the date change and re-runs
  `_loadConsumedToday()` and `_loadTodayTarget()` for the new day
- Flow:
  1. Both loads resolve with the new day's data (likely empty + rolled-
     over target)
  2. Ring shows 0 / <target> for the new day
- Expected outcome: Ring reflects the new day's data, not yesterday's.
  Existing day-rollover plumbing in `NutritionState` is reused; no new
  code path is required here beyond the re-load.
- Edge case of: S-001

## Architecture & Data Model

- No new data-model fields, no new tables, no repository-interface
  changes. `ConsumedFood` and `getConsumedFoodsForDate` already exist.
- One state method gets a real implementation:
  `NutritionState.getTodayConsumedFoods()` (currently a stub returning
  `[]`). It must return a `Future<List<ConsumedFood>>` for today and
  notify listeners on success, so the ring rebuilds when consumed data
  changes. The state must also expose a synchronous
  `List<ConsumedFood> get consumedToday` cache (loaded by the
  implementation) for the ring widget to read during `build`.
- One new widget:
  `lib/features/nutrition/widgets/calorie_ring.dart` — a small
  `CustomPainter` (or `CircularProgressIndicator`-based) donut plus a
  centered label column. Takes `consumed`, `target` (nullable
  `double?`), and an optional `onEditTap` callback.
- One new widget:
  `lib/features/nutrition/widgets/calorie_ring_card.dart` — wraps the
  ring in a `Card` and lays out the edit icon in a `Stack` overlaid on
  the ring's top-right corner (or beside it, on a wide layout). Reads
  from `NutritionState` via `ListenableBuilder`. Handles all three
  branches (logged + target, logged + no target, empty) and dispatches
  the edit-tap to the same `_navigateToTargets` callback used by the
  removed bottom button.
- One new private helper on `NutritionState`:
  `Future<void> _loadConsumedToday()` (called from
  `NutritionScreen.initState`) that delegates to the implemented
  `getTodayConsumedFoods`.
- The bottom "Edit Targets" full-width `FilledButton` in
  `NutritionScreen` is removed; the ring card's icon button is the only
  edit affordance.

## Implementation Phases

### Phase 1: Data layer wiring — `NutritionState` (no new repo methods) — Complete ✓
1. [x] In `lib/state/nutrition_state.dart`, replaced the stub
       `getTodayConsumedFoods` with a real implementation that:
       - Resolves today's midnight ms via `OmniDateUtils.todayMidnightMs()`.
       - Calls `_repository.getConsumedFoodsForDate(todayMs)`.
       - Caches the result in a new `List<ConsumedFood> _consumedToday`
         field and exposes it as `List<ConsumedFood> get consumedToday`.
       - Calls `notifyListeners()` on success.
       - On error, leaves `_consumedToday` as `[]` and does not throw
         upward (matches the existing `try/catch` pattern in
         `loadNutritionTargetForDate`).
2. [x] Added a public `Future<void> loadConsumedToday()`.
3. [x] Bonus: also implemented a real `logConsumedFood(food, amount)` and
       `deleteConsumedFood(id)` that go through the repository and keep
       the cache in sync, so the ring can update without a separate
       load. Added `clearConsumedToday()` for the day-rollover path.
       Added a derived `todayConsumedCalories` getter that sums
       `ConsumedFood.caloriesConsumed` (pure / derived, no repo call).
4. [x] Updated `test/state_test.dart` — the legacy stub test is replaced
       with a `consumed-food cache` group (4 tests): initial empty state,
       empty-when-repo-empty, populates from repo with a real
       `todayConsumedCalories` sum, idempotent refresh, and
       `clearConsumedToday` no-op semantics.
5. [x] No Flutter imports added to the state; only `package:flutter/foundation.dart`
       (already present) and the project's own `date_utils.dart`,
       `models.dart`, `workout_repository.dart` (all web-safe).
6. [x] `flutter test test/state_test.dart` — 192 / 192 pass.
       `flutter test test/nutrition_test.dart` — 16 / 16 pass.
       `flutter analyze lib/state/nutrition_state.dart` — clean.

### Phase 2: New ring widget — `CalorieRing`
1. [ ] Create `lib/features/nutrition/widgets/calorie_ring.dart` with
       a `CalorieRing` `StatelessWidget`:
       - Props: `double consumed` (calories, non-negative, rounded to
         int for display), `double? target` (nullable — null OR `<= 0`
         means consumed-only), `String? emptyHint` (defaults to
         "Log a food to start filling"), `String? overCaption`
         (optional).
       - Uses a `CustomPaint` for the donut track + filled arc, sized
         ~160×160 with stroke width ~14. The fill fraction is
         `target != null && target > 0 ? (consumed / target).clamp(0, 1) : 0`
         (consumed-only mode draws the track only, no arc).
       - Colors come from `OmniTheme.colors`: track uses
         `themeColors.surface` or `themeColors.divider`; arc uses
         `themeColors.primary`. Center text uses
         `themeColors.textDominant`; subtext uses
         `themeColors.textMuted`. No hardcoded `Color(0x…)` values.
       - Renders three label branches in the center:
         - Target set + consumed > 0: `"<consumed> / <target> kcal"`
           (comma-grouped ints); over-target appends
           `" · over by <diff>"` (only when `consumed > target`).
         - Target set + consumed == 0: `"0 / <target> kcal"` with the
           subtext hint beneath.
         - Target null + consumed > 0: `"<consumed> kcal"` with a
           smaller `"no goal set"` subtext.
         - Target null + consumed == 0: `"0 kcal"` with the subtext
           hint beneath.
       - Includes `Semantics` so screen readers announce
           "Calories: <consumed> of <target>" or "Calories: <consumed>,
           no goal set".

### Phase 3: New ring card — `CalorieRingCard`
1. [ ] Create
       `lib/features/nutrition/widgets/calorie_ring_card.dart` with a
       `CalorieRingCard` `StatelessWidget`:
       - Props: `NutritionState nutritionState`, `VoidCallback onEditTap`.
       - Wraps `CalorieRing` in a `Card` and places a small
         `IconButton` (`Icons.tune` or `Icons.edit_outlined`) in a
         `Stack` overlaid on the top-right of the ring (or beside it on
         wider layouts — use a `Row` with the ring as a `Flexible`
         child and a trailing `IconButton` for simplicity; pick the
         approach that fits the existing 16-px-padded `Card` style best
         in code).
       - Uses `ListenableBuilder(listenable: nutritionState)` so it
         rebuilds on every `notifyListeners()` (covers both target
         changes and consumed-food changes).
       - Reads `nutritionState.nutritionTarget` for the target and
         `nutritionState.consumedToday` for the consumed list; sums
         `e.caloriesConsumed` over the list.
       - The edit icon must have a `tooltip: 'Edit targets'` and a
         `key: const Key('edit_targets_icon')` so tests can find it.

### Phase 4: Wire into `NutritionScreen`
1. [ ] In `lib/features/nutrition/nutrition_screen.dart`:
       - Add a `_loadConsumedToday()` call in `initState` next to
         `_loadTodayTarget()` so both run in parallel via
         `Future.wait` (or as separate unawaited `Future`s — match the
         existing pattern).
       - Reload consumed foods on return from
         `NutritionTargetScreen` in the same `.then((_) …)` callback
         that already reloads the target, so the ring reflects any
         target changes (consumed data is unaffected by target edits,
         but loading both keeps the code symmetric).
       - Replace the stub "Consumed Today" `Card` at the top of the
         `Column` with a `CalorieRingCard`.
       - Remove the bottom "Edit Targets" `FilledButton` (`SizedBox`
         wrapper + button) — the icon on the ring is the only edit
         affordance.
       - Keep the existing "Food Library" card and
         `NutritionSummaryCard` below the ring.
2. [ ] Pass `_navigateToTargets` to `CalorieRingCard.onEditTap`.

### Phase 5: Tests (new + updated)
1. [ ] Update `test/state_test.dart`'s
       `getTodayConsumedFoods returns empty list (stub)` test to assert
       the real behaviour: with no rows in the repo, the returned
       list is empty AND `state.consumedToday` is empty; with two
       `ConsumedFood` rows created for today, both appear in
       `state.consumedToday` (in insertion order); and `notifyListeners`
       is invoked once after the load.
2. [ ] New widget test in `test/nutrition_test.dart` —
       `CalorieRingCard` group:
       - `renders consumed vs target when both present`: seed a
         `NutritionTarget(calories: 2000, …)` and a
         `ConsumedFood` with `caloriesConsumed == 700`. Pump the card
         inside a `Scaffold` + `MaterialApp`. Assert the center text
         contains `"700"` and `"2,000"`; assert the `edit_targets_icon`
         key is present.
       - `updates ring as consumed log changes`: start with one
         `ConsumedFood` (350 kcal); pump the card; assert the center
         shows `"350 / 2,000"`. Then call
         `repo.createConsumedFood(...)` to add a second entry
         (200 kcal), call `state.loadConsumedToday()`, pump again;
         assert the center shows `"550 / 2,000"`. (i.e. ring updates
         as the day's log changes.)
       - `consumed-only when no target is set`: leave the target
         unset; add a 300-kcal `ConsumedFood`. Pump the card. Assert
         the center shows `"300 kcal"` and that the text does NOT
         contain `"/ 0"` or `"/ 2,000"`. Pump must not throw.
       - `empty ring invites setup when nothing logged`: no target,
         no consumed foods. Pump. Assert the center shows
         `"0 kcal"` and that the subtext contains
         `"Log a food"` (case-insensitive). Pump must not throw.
       - `tapping edit icon pushes NutritionTargetScreen`: pump the
         screen; tap the icon by key. After `pumpAndSettle`, the
         `NutritionTargetScreen`'s AppBar title (`"Daily Nutrition
         Targets"`) should be present.

### Phase 6: Visual polish + theme parity
1. [ ] Use `OmniTheme.colorsForTheme` (or `OmniTheme.colors` static
       getter) — do not hardcode colors.
2. [ ] Match the visual language of the existing nutrition cards:
       `Card` + 16-px padding, `titleLarge` for the section title
       ("Today"), `titleMedium` for the consumed total, `bodySmall` in
       `textMuted` for the subtext and the "over by N" caption.
3. [ ] The ring itself should not animate fill changes in this
       iteration (no `TweenAnimationBuilder`) — keep it static for
       v1. A future iteration can add animation.

## Files Affected

- `lib/state/nutrition_state.dart` — implement `getTodayConsumedFoods`,
  add `consumedToday` cache + `loadConsumedToday`.
- `lib/features/nutrition/widgets/calorie_ring.dart` — NEW. Donut
  painter + centered label.
- `lib/features/nutrition/widgets/calorie_ring_card.dart` — NEW. Card
  wrapper with edit icon, listens to `NutritionState`.
- `lib/features/nutrition/nutrition_screen.dart` — replace the
  top stub `Card` with `CalorieRingCard`; add `_loadConsumedToday`;
  remove the bottom "Edit Targets" button.
- `test/state_test.dart` — update the `getTodayConsumedFoods` test to
  assert real behaviour.
- `test/nutrition_test.dart` — new `CalorieRingCard` test group
  (5 tests).

## Out of Scope

- Animating the ring fill (no `TweenAnimationBuilder` for v1).
- Logging UI for foods (the user can already create foods in the
  library; this feature only displays the totals).
- Macro breakdown (protein/carbs/fat) inside the ring — the ring is
  calories only. A future iteration can add stacked arcs per macro.
- Changing the bottom "Edit Targets" button's behavior beyond
  removing it. No replacement CTA at the bottom.

## Notes

- `NutritionState.getTodayConsumedFoods` is currently called by no
  other widget in the app. After this change, it is the single
  source of truth for the ring's consumed total. If a future
  "logged foods" list is added, it can read from the same
  `consumedToday` cache.
- The `ConsumedFood` snapshot freezes calories at log time, so
  re-editing a food in the library does NOT change yesterday's
  totals. This is the intended behavior.
- The repository already supports `getConsumedFoodsForDate` in
  both `HiveWorkoutRepository` and `MockWorkoutRepository` — no
  repository changes are required.
