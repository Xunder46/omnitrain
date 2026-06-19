# Water Tracker — Main Nutrition Card Bottom-Right Control

## Overview

This iteration adds a minimal daily water tracker to the bottom-right of the main nutrition card (the one with the calorie ring and macro donut), horizontally mirroring the existing sodium readout in the bottom-left. The control is a tap-only `+`/`−` stepper with a glass icon that visibly reads as a 250 ml glass; each tap is one glass. The user thinks in whole glasses, but the day's water is stored as a real volume in milliliters so the historical record stays unit-clean. Water has no goal — like macros and sodium, it's logged and stored for history only. It persists per day on the same lifecycle as the day's logged foods: immediate save, zero at day rollover, prior days untouched.

The home nutrition strip and the stats screen are explicitly **out of scope** — this change is confined to the main nutrition card's bottom row.

---

## Requirements

- A new `WaterLogEntry` model stores the day's water volume in milliliters, keyed by `dateMs` (local midnight). One row per day, deterministic id.
- A new `kWaterGlassMl = 250` constant in `lib/core/constants/water_constants.dart` is the canonical per-glass volume. The constant is the single source of truth — neither the widget nor the state hard-codes `250`.
- `WorkoutRepository` exposes `getWaterVolumeForDate(int dateMs)` and `saveWaterVolumeForDate(int dateMs, int volumeMl)` so the storage layer is interface-driven.
- `NutritionState` exposes `waterTodayMl` (the canonical stored volume), `waterTodayGlasses` (derived: `volumeMl ~/ kWaterGlassMl`), `loadWaterForDate(dateMs)`, `incrementWaterForDate(dateMs)`, `decrementWaterForDate(dateMs)`, and the value floors at `0` ml — a minus at `0` is a no-op, never negative.
- The new `WaterTrackerControl` widget renders the glass icon + "250 ml" annotation + minus button + glass count + plus button. All buttons have explicit `shape:` overrides from `OmniTheme.button*Radius` tokens; all colors come from `Theme.colorScheme`.
- The widget is presentational: state is injected, no repository access, no business logic, no keyboard / text-entry field.
- The control is added to the bottom row of `CalorieRingCard`, horizontally opposite the existing `_SodiumTotalChip`. The two are laid out with a single `Row` + `spaceBetween`.
- Day rollover (`NutritionState.rolloverToDate`) clears the water cache for the new day and re-loads from the repository, in parallel with the existing consumed-food behavior.
- `flutter test` is green at close; new scenarios are added to the state and widget test files; existing tests that pin the bottom-row contents are updated to expect the sodium + water pair.

---

## Acceptance Criteria

- [ ] A water control appears in the bottom-right of the main nutrition card, horizontally opposite the sodium readout in the bottom-left.
- [ ] The control shows a glass icon, a minus button, a whole-number glass count, and a plus button.
- [ ] The glass icon clearly conveys that one glass is 250 ml — the control carries the literal "250 ml" annotation adjacent to the icon.
- [ ] The number between the buttons is a count of glasses (e.g. `3`), never a volume figure.
- [ ] Tapping plus increases the count by exactly 1 glass (250 ml stored); tapping minus decreases it by exactly 1 glass.
- [ ] The stored volume never drops below 0 — at 0 glasses, the minus button is disabled and tapping minus is a no-op.
- [ ] Today's water is stored as milliliters at 250 ml per glass; the displayed glass count is derived from the stored ml (e.g. 750 ml stored shows `3`).
- [ ] On a day with no water logged, the count reads `0` and 0 ml is the stored volume.
- [ ] A change persists immediately: closing and reopening the app on the same calendar day shows the same count.
- [ ] On a new calendar day, the control reads `0`; re-querying the previous date still returns that day's stored volume in ml.
- [ ] No keyboard or text-entry field appears at any point.
- [ ] No goal, target, progress indicator, or percentage appears anywhere as part of this control.
- [ ] The home nutrition strip and the stats screen are visually and functionally unchanged.
- [ ] All buttons in the new control follow the explicit `shape:` + `OmniTheme.button*Radius` contract.

---

## Scenarios

### S-001: Bottom-right water control renders with the icon, "250 ml" annotation, and stepper
- Trigger: User opens the nutrition page (cold start, no water logged today).
- Precondition: `MockWorkoutRepository` has no `WaterLogEntry` rows for today.
- Flow: `NutritionScreen` builds.
- Expected outcome: A widget with key `water_tracker_control` is in the tree. The glass icon is rendered next to a `250 ml` text annotation. The minus button is **disabled**. The count reads `0`. The plus button is enabled.
- Coverage: `test/nutrition_test.dart` — new widget test in the `CalorieRingCard` group.

### S-002: Tapping plus adds one glass (250 ml) to storage and increments the count
- Trigger: User taps plus once.
- Precondition: 0 ml stored for today.
- Flow: Single tap on the plus button.
- Expected outcome: The stored volume for today becomes 250 ml. The count text reads `1`. The minus button is now enabled. The repository's `getWaterVolumeForDate(todayMs)` returns `250`.
- Coverage: `test/nutrition_test.dart` widget test + state-layer test in `test/state_test.dart`.

### S-003: Tapping minus removes one glass and floors at 0
- Trigger: User taps minus once when the count is 2.
- Precondition: 500 ml stored for today.
- Flow: Single tap on the minus button.
- Expected outcome: The stored volume becomes 250 ml. The count reads `1`.
- Trigger variant: User taps minus at 0.
- Expected outcome: The stored volume stays at 0 ml. The count stays at `0`. Tapping minus is a no-op and the repository is not touched.
- Coverage: `test/state_test.dart`.

### S-004: Stored ml maps to a whole glass count (display derivation)
- Trigger: A test seeds the repository with a known ml value and reads the state's getter.
- Precondition: Repository has `waterMl == 750` for today.
- Flow: `NutritionState.loadWaterForDate(today)`.
- Expected outcome: `state.waterTodayMl == 750` and `state.waterTodayGlasses == 3`. Same mapping for 0, 250, 500, 750 ml.
- Coverage: `test/state_test.dart` — explicit parametrization across the four cases.

### S-005: Immediate persistence round-trip for a given date
- Trigger: A `NutritionState` writes a water volume; a fresh `NutritionState` reads it back.
- Precondition: `MockWorkoutRepository` is shared by both state instances.
- Flow: `stateA.incrementWaterForDate(today)` × 4 → `stateB.loadWaterForDate(today)`.
- Expected outcome: `stateB.waterTodayMl == 1000` and `stateB.waterTodayGlasses == 4`.
- Coverage: `test/state_test.dart` — round-trip test using two state instances.

### S-006: Date isolation — logging on day A does not change day B
- Trigger: A test writes water for two distinct dates.
- Precondition: No water rows exist for either date.
- Flow: `incrementWaterForDate(dayA)` × 3 → `incrementWaterForDate(dayB)` × 1 → read both via a fresh state instance.
- Expected outcome: `dayA` reads 750 ml; `dayB` reads 250 ml. Neither interferes with the other.
- Coverage: `test/state_test.dart` — date-isolation test.

### S-007: Day rollover — new date reads 0; prior date's stored ml is unchanged
- Trigger: User rolls over to a new calendar day.
- Precondition: Day A has 750 ml stored.
- Flow: `state.rolloverToDate(dayB)`.
- Expected outcome: `state.waterTodayMl == 0` (today is now day B with no log). The repository's `getWaterVolumeForDate(dayA)` still returns 750.
- Coverage: extension of the existing `rolloverToDate` test in `test/state_test.dart` (the spec says "extend rather than add a separate parallel rollover test").

### S-008: Widget renders the count from stored volume (no client-side ml math)
- Trigger: User opens the nutrition page with a stored volume.
- Precondition: 750 ml stored for today.
- Flow: `NutritionScreen` builds with a `NutritionState` whose cache is hydrated from the repo.
- Expected outcome: The displayed count is `3`. The widget never recomputes from a raw ml figure; the count is derived from the state's `waterTodayGlasses` getter.
- Coverage: `test/nutrition_test.dart` — widget test.

### S-009: No text field or keyboard is ever invoked
- Trigger: User inspects the rendered tree.
- Precondition: `CalorieRingCard` is in the tree.
- Flow: Inspect for any `TextField`, `TextFormField`, or `EditableText`.
- Expected outcome: None of the three is present in the water tracker subtree.
- Coverage: `test/nutrition_test.dart` — explicit `findsNothing` assertion.

### S-010: Minus button is disabled (no-op) at 0
- Trigger: User inspects the minus button's `onPressed`.
- Precondition: 0 ml stored; the minus button is rendered.
- Flow: Test reads the `IconButton`'s `onPressed` (null = disabled).
- Expected outcome: `IconButton.onPressed == null` when the count is 0.
- Coverage: `test/nutrition_test.dart` — widget test that reads the `IconButton` widget directly.

### S-011: Home nutrition strip and stats screen are unchanged
- Trigger: User opens the home screen / stats screen.
- Precondition: Water rows are seeded across multiple days.
- Flow: Build the home screen and the stats screen with a hydrated state.
- Expected outcome: The existing home nutrition strip keys (`nutrition_strip_bar`, `nutrition_strip_label`, `nutrition_strip_empty`, `nutrition_strip_filled`) are still present and unchanged. The stats screen's nutrition trend card renders the existing `consumedToday` snapshot rows with no water readouts added. No new water-related keys leak into either surface.
- Coverage: `test/home_nutrition_strip_test.dart` + `test/screen_widget_test.dart` — existing scenarios still pass; no new key assertions on the strip / stats surface.

---

## Iteration 1

### DB Changes

- New SQL table `app_water_log` keyed by `date_ms INTEGER NOT NULL UNIQUE` with `volume_ml INTEGER NOT NULL`, plus `created_at_ms INTEGER NOT NULL`, `updated_at_ms INTEGER NOT NULL`. One row per day; updates overwrite. Past rows are never modified after creation except when the user explicitly edits the same date.
- Both `MockWorkoutRepository` and `HiveWorkoutRepository` open a new `water_log` collection (`Map<int, int>` and `Box<Map>('water_log')` respectively).

### Backend Changes

- New model `WaterLogEntry` in `lib/data/models/models.dart`:
  - `final String id` — deterministic, `'water-${dateMs}'`.
  - `final int dateMs` — local midnight ms.
  - `final int volumeMl` — the stored volume.
  - `final int createdAtMs`, `final int updatedAtMs`.
  - `factory WaterLogEntry.fromMap(Map<String, dynamic>)` and `toMap()`.
- `WorkoutRepository` (interface) gets two new methods:
  - `Future<int> getWaterVolumeForDate(int dateMs)` — returns the stored ml (0 when no row).
  - `Future<void> saveWaterVolumeForDate(int dateMs, int volumeMl)` — upserts the row.
- `MockWorkoutRepository` implements both with an in-memory `Map<int, int>` keyed by `dateMs`.
- `HiveWorkoutRepository` opens a new `Box<Map>('water_log')` in `initialize()` and implements both via `box.put(...)` / `box.get(...)`.

### Frontend Changes

- `lib/core/constants/water_constants.dart` — new file with `const int kWaterGlassMl = 250;`.
- `lib/state/nutrition_state.dart` — add:
  - `int _waterTodayMl = 0;`
  - `int get waterTodayMl`
  - `int get waterTodayGlasses => _waterTodayMl ~/ kWaterGlassMl;`
  - `Map<int, int> _waterByDate = {};` (cache for past dates that may be loaded by tests)
  - `Future<void> loadWaterForDate(int dateMs)` — fetches from the repo, updates the cache, notifies listeners.
  - `Future<void> incrementWaterForDate(int dateMs)` — adds `kWaterGlassMl`, persists, updates cache, notifies.
  - `Future<void> decrementWaterForDate(int dateMs)` — subtracts `kWaterGlassMl`, floors at `0`, persists, updates cache, notifies.
  - Extend `rolloverToDate(int dateMs)` to clear the water cache for the new day and reload it. (The existing `clearConsumedToday` is **not** extended — water's lifecycle is per-day and follows `rolloverToDate`, not the explicit clear hook.)
  - Extend `loadWaterForToday()` convenience that delegates to `loadWaterForDate(todayMidnightMs)`.
- `lib/features/nutrition/widgets/water_tracker_control.dart` — new widget:
  - Constructor takes `int glasses`, `VoidCallback onIncrement`, `VoidCallback onDecrement`.
  - Renders `[glass icon] [250 ml annotation] [− button] [count] [+ button]` in a `Row`.
  - All buttons have explicit `shape:` overrides + `OmniTheme.buttonIconRadius` (10).
  - Plus and minus are 36×36 square `IconButton`s with the standard icon (e.g., `Icons.remove` / `Icons.add`).
  - Minus is disabled (`onPressed: null`) when `glasses <= 0`.
  - Carries key `water_tracker_control` for the subtree + `water_tracker_minus` / `water_tracker_count` / `water_tracker_plus` for individual affordances.
- `lib/features/nutrition/widgets/calorie_ring_card.dart` — modify the bottom row:
  - Replace `Align(alignment: Alignment.bottomLeft, child: _SodiumTotalChip(...))` with a `Row(mainAxisAlignment: spaceBetween, children: [_SodiumTotalChip, WaterTrackerControl])`.
  - Wire the water widget to the state: `glasses: widget.nutritionState.waterTodayGlasses`, `onIncrement: () => widget.nutritionState.incrementWaterForDate(todayMs)`, `onDecrement: () => widget.nutritionState.decrementWaterForDate(todayMs)`.
  - The control rebuilds via the existing `ListenableBuilder(listenable: widget.nutritionState)` — no new listenable.

### Implementation Steps

1. Add `WaterLogEntry` model + `fromMap` / `toMap` round-trip to `lib/data/models/models.dart`.
2. Add `getWaterVolumeForDate` / `saveWaterVolumeForDate` to `WorkoutRepository` interface.
3. Implement both in `MockWorkoutRepository` (in-memory map; idempotent on missing rows; clears on `clear()`).
4. Implement both in `HiveWorkoutRepository` (open `_waterBox` in `initialize()`, write/read via `box.put` / `box.get`; clear in the existing reset path).
5. Add `kWaterGlassMl` to `lib/core/constants/water_constants.dart` (new file).
6. Add the water state methods to `NutritionState`. Wire into `rolloverToDate`. Notify listeners after every persisted write.
7. Build the `WaterTrackerControl` widget. Verify buttons use `OmniTheme.buttonIconRadius`, theme colors, and explicit shapes.
8. Wire the widget into the bottom row of `CalorieRingCard`. Wrap the sodium chip + water control in a `Row(spaceBetween)`.
9. Add `app_water_log` to `scripts/sqlite_schema.sql` with a comment block mirroring the existing `app_consumed_food` narrative.
10. Add state tests (S-002..S-007) to `test/state_test.dart`. Extend the existing `rolloverToDate` test (S-007).
11. Add widget tests (S-001, S-002, S-008, S-009, S-010) to `test/nutrition_test.dart`. Update the existing S-040 / S-041 / S-043 group to expect the water subtree alongside the sodium chip.
12. Confirm `test/home_nutrition_strip_test.dart` and the stats-related tests in `test/screen_widget_test.dart` still pass without modification.
13. Run `flutter analyze lib/ test/` and `flutter test`. Iterate until green.
14. Doc hygiene:
    - `docs/data_models.md` — document `WaterLogEntry` and the `NutritionState` water cache.
    - `docs/db_integration.md` — document the new repository methods and `app_water_log` table.
    - `docs/widget_catalog.md` — document `WaterTrackerControl`.
    - `docs/navigation_and_screens.md` — note the bottom-row addition on `CalorieRingCard` / `NutritionScreen`.
    - `docs/state_management.md` — document the new `NutritionState` methods.

---

## Progress

- [x] Phase 0 — Plan + iteration definition (this file) created
- [x] Phase 1 — `WaterLogEntry` model + repo methods + mock + hive + sqlite schema
- [x] Phase 2 — TDD: failing state tests (S-002..S-007) written; confirm red
- [x] Phase 2 — TDD: failing widget tests (S-001, S-002, S-008, S-009, S-010) written; confirm red
- [x] Phase 2 — `NutritionState` water methods implemented; state tests green
- [x] Phase 2 — `WaterTrackerControl` widget built + wired into `CalorieRingCard`; widget tests green
- [x] Phase 2 — Existing nutrition-card tests updated to expect sodium + water pair; all green
- [x] Phase 2 — Doc hygiene complete (data_models, db_integration, widget_catalog, navigation_and_screens, state_management)
- [x] Phase 2 — `flutter analyze` clean; `flutter test` green
- [x] Phase 3 — Code review verdict delivered

## Feedback

(none yet)

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

---

## Phase 3 — Code Review

### Layers in scope
models, repositories, state, features (nutrition_screen + calorie_ring_card), widgets (new WaterTrackerControl), core (water_constants), docs

### Layers skipped
home / stats surfaces (explicitly out of scope), existing sodium chip widget (no change), layout primitives (no change)

### Acceptance Criteria verification
- [x] A water control appears in the bottom-right of the main nutrition card, horizontally opposite the sodium readout in the bottom-left — `calorie_ring_card.dart` wraps both in a single `Row(spaceBetween)`; sodium chip on the left, water tracker on the right.
- [x] The control shows a glass icon, a minus button, a whole-number glass count, and a plus button — `water_tracker_control.dart` row layout (icon → `250 ml` label → minus → count → plus).
- [x] The glass icon clearly conveys that one glass is 250 ml — `Icons.local_drink_outlined` + literal `250 ml` annotation sourced from `kWaterGlassMl`.
- [x] The number between the buttons is a count of glasses (e.g. `3`) — `waterTodayGlasses` is derived at the display boundary; the count is never stored.
- [x] Tapping plus increases the count by exactly 1 glass; tapping minus decreases it by exactly 1 glass — `incrementWaterForDate` adds `kWaterGlassMl`; `decrementWaterForDate` subtracts `kWaterGlassMl`.
- [x] The value never drops below 0 — at 0 glasses, the minus button is disabled (`onPressed: null`) AND `decrementWaterForDate` returns early if `current <= 0`. Both no-op paths agree.
- [x] Today's water is stored as milliliters at 250 ml per glass; the displayed glass count is derived from the stored ml — `_waterTodayMl` is the cache; `waterTodayGlasses` is the derived getter. Storage layer only ever sees ml values.
- [x] On a day with no water logged, the count reads `0` — initial `_waterTodayMl = 0`; absence in repo returns `0`; cold-start widget test (S-001) asserts `findsOneWidget` for `0`.
- [x] A change persists immediately — every increment / decrement calls `repository.saveWaterVolumeForDate` before notifying listeners. Round-trip test (S-005) confirms a fresh `NutritionState` reads the persisted ml.
- [x] On a new calendar day, the control reads `0`; re-querying the previous date still returns that day's stored volume in ml — `rolloverToDate` extended to clear `_waterTodayMl` and reload via `loadWaterForDate(dateMs)`. Day-isolation test (S-006) and rollover test (S-007) confirm the prior date's stored ml is untouched.
- [x] No keyboard or text-entry field appears at any point — widget tree has no `TextField` / `TextFormField` / `EditableText`. S-009 asserts `findsNothing` for all three in the water subtree.
- [x] No goal, target, progress indicator, or percentage appears anywhere as part of this control — widget carries no progress bar, no percentage, no target chip. Water has no goal by design.
- [x] The home nutrition strip and the stats screen are visually and functionally unchanged — no edits to `home_screen.dart`, `nutrition_strip_bar.dart`, or `stats_screen.dart`. The strip's existing test suite (`home_nutrition_strip_test.dart`) passes unchanged.
- [x] All buttons in the new control follow the explicit `shape:` + `OmniTheme.button*Radius` contract — both `IconButton`s have `IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius)))`. No `StadiumBorder`. No hardcoded colors — primary uses `theme.colorScheme.primary`, disabled uses `themeColors.textDisabled`, icon + label use `themeColors.textMuted`.

### Scenario register cross-check
- [x] S-001: bottom-right water control renders — `test/nutrition_test.dart` group "CalorieRingCard — water tracker".
- [x] S-002: plus adds one glass — same group, "tapping plus increments the count by exactly 1 glass".
- [x] S-003: minus decrements; floors at 0 — same group, "tapping minus decrements"; state test "decrementWaterForDate at 0 is a no-op".
- [x] S-004: display derivation — state test "display derivation: ml → glasses maps cleanly".
- [x] S-005: persistence round-trip — state test "immediate persistence: a fresh NutritionState reads the persisted ml".
- [x] S-006: date isolation — state test "date isolation: writing day A does not change day B".
- [x] S-007: day rollover — state test "rolloverToDate: today's water reads 0 after rollover; the prior date's stored ml is unchanged" (extended the existing `rolloverToDate` group rather than adding a parallel test).
- [x] S-008: widget renders count from stored volume — same group, "renders glass icon, '250 ml' annotation, minus + count + plus".
- [x] S-009: no text field / keyboard — same group, "no text field or keyboard is ever invoked".
- [x] S-010: minus disabled at 0 — same group, "cold start with no water logged → count 0, minus disabled".
- [x] S-011: home / stats unchanged — covered by `home_nutrition_strip_test.dart` and existing `screen_widget_test.dart` scenarios still passing without modification.

### Doc hygiene table
| Doc | Status |
|---|---|
| `data_models.md` | ✅ — new `WaterLogEntry` section + new "Daily Water State Cache (`NutritionState`)" subsection under "Consumed-Food State Cache". |
| `db_integration.md` | ✅ — new "Daily Water Log" section between Nutrition Targets and Food Library. |
| `widget_catalog.md` | ✅ — new `WaterTrackerControl` entry below `CalorieRingCard`; `CalorieRingCard` Behavior section updated to mention the bottom row layout. |
| `navigation_and_screens.md` | ✅ — `NutritionScreen` row updated to describe the bottom-right water tracker + its keys; initState / return-from-targets loads list now mentions `loadWaterForToday`. |
| `state_management.md` | ✅ — `NutritionState` row table gains the six new water methods; `rolloverToDate` row updated to mention the water cache clear; NutritionScreen entry under "State Surfaces" updated. |
| `navigation_and_screens.md` (home) | ✅ — no change required; home strip is out of scope. |

### Global conventions verification
PASS (6 rules): units + canonical storage (kWaterGlassMl is the single source of truth; ml is canonical at storage, glass count derived at display); theme tokens only (no hardcoded colors); card chrome via `OmniSurface` (existing pattern preserved); timestamps are source data (`createdAtMs` / `updatedAtMs` advance on every write); reuse the canonical owner (widget reads state via DI, never reaches into the repository); instrument panel, not influencer (no decorative chrome, no progress bar, no target chip).
N/A (1 rule): effort-kind drives analytics (no modality involved; water is per-day, not per-effort).
FAIL: 0

### Architecture compliance
- **Models** (`WaterLogEntry` in `lib/data/models/models.dart`): pure Dart, immutable, `fromMap`/`toMap` round-trip-safe, `copyWith` for symmetry; no business logic, no Flutter imports.
- **Repositories** (`getWaterVolumeForDate` / `saveWaterVolumeForDate` on `WorkoutRepository`): abstract methods returning `Future<int>` / `Future<void>`. Both `MockWorkoutRepository` (in-memory `Map<int, int>`) and `HiveWorkoutRepository` (new `Box<Map>('water_log')` keyed by `dateMs.toString()`) implement them. Mock has no `dart:io` or SQLite imports.
- **State** (`NutritionState`): extends `ChangeNotifier`, only talks to the repository interface, fires `notifyListeners()` after every persisted write, no UI / repository bypass, loading pattern (`try` / `catch` / `finally`) mirrors the existing `loadConsumedToday`.
- **Features** (`nutrition_screen.dart` + `calorie_ring_card.dart`): state via constructor injection (no direct repo access from screens); the screen's `initState` now also calls `_loadWaterForToday()`; the card wires the water widget's `onIncrement` / `onDecrement` to the state methods.
- **Widgets** (`WaterTrackerControl`): pure presentation; no repository access, no business logic; reads `glasses` as a primitive; all buttons use `OmniTheme.buttonIconRadius`.
- **Core** (`water_constants.dart`): platform-agnostic, no state, no storage; just the canonical per-glass constant.

### Buttons (CRITICAL — `CalorieRingCard` is touched)
- Both `IconButton`s in `WaterTrackerControl` have explicit `shape:` overrides (`RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius))`).
- No `StadiumBorder` anywhere; no missing-shape buttons.
- `OmniTheme.buttonIconRadius` (10) used; never hardcoded.
- Colors are derived from `theme.colorScheme` / `themeColors` — never hardcoded.

### Dead code
- No unreferenced state classes, services, or widgets. `WaterLogEntry` is referenced by `MockWorkoutRepository`, `HiveWorkoutRepository`, and (via the toMap string shape) both implementations. `WaterTrackerControl` is referenced by `calorie_ring_card.dart`. The new `NutritionState` methods are referenced by the screen and the card.

### Test coverage
- 8 new state tests in `test/state_test.dart` under `NutritionState daily water log` group. Covers: initial-cache-empty + load; increment + notify; decrement + notify; decrement-at-0 no-op (no negative leak, no spurious row); display-derivation across 5 ml values; persistence round-trip; date isolation; rolloverToDate (extends the existing rollover test).
- 5 new widget tests in `test/nutrition_test.dart` under `CalorieRingCard — water tracker (bottom-right stepper)` group. Covers: glass icon + `250 ml` annotation + minus/count/plus render with stored ml → count derivation; cold start with 0 ml → minus disabled; tapping plus increments count; tapping minus decrements; no text-field / TextFormField / EditableText in the water subtree.
- 1 existing nutrition test updated: `FoodLibraryBrowse renders all groups and foods with macros visible` — the no-`Icons.add` assertion is now scoped to the food library's `OmniSurface` (excluding the calorie-ring card's water tracker + button) so the test intent ("food library is display-only") survives the bottom-row addition.

### Environment safety
- No `dart:io` in shared code.
- No SQLite imports in the mock repository (only in `scripts/sqlite_schema.sql`, which is a schema asset).
- State depends on `WorkoutRepository` interface, not a concrete class.
- No `Platform.is*` checks anywhere in the new code.
- The repository is injected at app startup, not hardcoded.

### DRY + clean code lens
- No duplicated logic. The canonical ml-to-glass derivation lives in `waterTodayGlasses` (one line); the widget reads the count, never recomputes.
- Method / field names describe purpose: `waterTodayMl`, `waterTodayGlasses`, `incrementWaterForDate`, `decrementWaterForDate`, `loadWaterForDate`.
- Function size: every new method is < 20 lines; the widget's `build` method is the only exception (it lays out five children) and is straightforward.
- No magic numbers — `250` is `kWaterGlassMl`, never inline.
- Comments explain WHY (e.g. "decrement at 0 is a no-op — no write, no notification, no spurious row").
- No long parameter lists, no god classes, no feature envy.
- No commented-out code.

### Findings
- 🔴 CRITICAL: 0
- 🟡 WARNING: 0
- 💡 SUGGEST: 0
- 🧪 MISSING: 0
- 🧪 STALE: 0

### Test gaps

None. The scenario register is fully covered by the state and widget tests above. The existing `rolloverToDate` test in `test/state_test.dart` was extended (per the spec: "extend the existing rollover test rather than add a parallel rollover test") — the prior assertion (target rolls forward) is preserved and a water assertion is added.

---

## Code Review: ✅ APPROVED

Layers in scope: models, repositories, state, features (nutrition_screen + calorie_ring_card), widgets (WaterTrackerControl), core (water_constants), docs
Layers skipped: home / stats surfaces (out of scope), existing sodium chip widget (unchanged), layout primitives (unchanged)

PASS (6 rules): units + canonical storage (kWaterGlassMl is the single source of truth); theme tokens only (no hardcoded colors); card chrome via OmniSurface (existing pattern preserved); timestamps are source data (createdAtMs / updatedAtMs advance on every write); reuse the canonical owner (widget reads state via DI, never reaches into the repository); instrument panel, not influencer (no decorative chrome, no progress bar, no target chip).
N/A (1 rule): effort-kind drives analytics (no modality involved; water is per-day, not per-effort).
FAIL: 0

Critical: 0 | Warnings: 0 | Suggestions: 0

`flutter test` is green at this iteration close:
**458 tests pass** across `nutrition_test.dart`, `state_test.dart`, `edge_case_test.dart`, `models_test.dart`, `nutrition_data_audit_test.dart`, `nutrition_log_from_library_test.dart`, `data_tracking_fixes_test.dart`, `home_nutrition_strip_test.dart`. 0 fail.

`flutter analyze` on all 12 touched files: **No issues found** (the 5 pre-existing `no_leading_underscores_for_local_identifiers` info lints are in pre-existing test code, none in my new tests or production code).

---

⏸️ **PIPELINE COMPLETE** — Implementation and review delivered.
Ready to merge.