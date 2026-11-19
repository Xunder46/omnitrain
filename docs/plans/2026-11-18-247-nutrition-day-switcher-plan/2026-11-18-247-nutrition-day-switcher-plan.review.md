# Review: 2026-11-18-247-nutrition-day-switcher-plan · P1-P5 · 9cf691e9..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 4 · minor 4 · tests: not run (per brief — the governor ran the full suite: no failing test outside the Windows base set, analyze at baseline 178 issues / 0 errors)
Diff vs Predicted Files: conforms, plus `test/food_catalog_load_test.dart` (2 lines: a `!` dropped before `.fat`) — outside the predicted list but declared in the plan's Assumption Log as an unrelated uncommitted file; no finding. `macos/Flutter/GeneratedPluginRegistrant.swift` appears only as a line-ending warning, not in the stat.

## Findings

1. [Major] lib/state/nutrition_state.dart:221-224 — `applyWatchWaterTap` assigns the viewed water with a single `_pastViewMs == dateMs` check before the await and no re-check after it, so day A's water can land while the view is on day B. Interleaving: viewing yesterday, a wrist tap on yesterday passes the check and awaits `getWaterVolumeForDate(yesterday)`; the user taps `nutrition_day_next` to D-2, whose `viewDay` applies its own reads (the tap does not change `_viewSeq`); the tap's read then completes and `_viewedWaterMl` is set to yesterday's total with `notifyListeners` — the screen shows yesterday's water under D-2, violating D-24704 ("a day never shows under another day's numbers"). Repo data is correct; the display is wrong until the next switch or write. Fix: re-check `_pastViewMs == dateMs` after the await before assigning (mirror `_reloadViewedRows` / `_stepViewedWater`). Guard: a Mock-only gated test where the tap's read is held across a `viewDay` to another day.
2. [Major] lib/state/nutrition_state.dart:770-801 — `viewDay`'s apply (`if (seq != _viewSeq) return;` at :797) only guards against a newer viewDay; a write to the same viewed day landing between the reads and the apply is overwritten. Interleaving: `viewDay(yesterday)` starts and its water read returns the pre-tap 750; a wrist tap (`applyWatchWaterTap`) then saves 1000 and refreshes `_viewedWaterMl` to 1000; `viewDay`'s seq check passes (writes do not bump `_viewSeq`) and it applies 750 — the tap is lost from the view until the next action. Same shape for `logConsumedFoodOnDay`'s wrist log racing the rows read (the egg vanishes from the view though the repo holds it). Fix: capture a write epoch (bumped by every viewed-day write) before the reads and re-run the reads once if it changed at apply time. Guard: Mock-only gated test writing to the gated day between the read and the apply.
3. [Major] docs/state_management/nutrition_state.md:190 — the row the Docs delta MODIFIED still says the card "reads `nutritionState.nutritionTarget`, `nutritionState.todayConsumedCalories`, and `nutritionState.waterTodayMl`" and that "The water tracker's increment / decrement buttons are wired to `nutritionState.incrementWaterForDate(todayMs)` / `.decrementWaterForDate(todayMs)`". calorie_ring_card.dart now reads `viewedTarget`, `viewedTotals`, `viewedWaterMl` and calls `incrementWaterViewed()` / `decrementWaterViewed()`; the named members are no longer read and the named methods are no longer called. A maintainer wiring a button from this doc hits methods that bypass the viewed cache. Fix: rewrite both sentences to the viewed members/methods (with the on-today delegation note). Guard: none (docs).
4. [Major] docs/design_system.md:184 — "with `nutrition_target_button` labelled `OutlinedButton.icon` in actions between the `nutrition_day_prev` and `nutrition_day_next` arrows" reads as the button sitting between the arrows; on screen the row is `‹ TITLE ›  [Change target]` — the trailing arrow is between the title and the button, and the button is right of `nutrition_day_next` (nutrition_screen.dart:224-268). A user reading the doc expects the button between the arrows. Fix: drop "between the `nutrition_day_prev` and `nutrition_day_next` arrows" or say the button sits right of them. Guard: none (docs).
5. [Minor] docs/state_management/nutrition_state.md:190 — "renders the day header (`Today`, `Yesterday` or the date) via `CalorieRingCard`": the header is built by `NutritionScreen`'s `OmniCardHeader` (nutrition_screen.dart:224-238); `CalorieRingCard` renders no header (its own comments place the title in NutritionScreen). False at base already; the delta's edit preserved it. Fix: name `NutritionScreen` / `OmniCardHeader`.
6. [Minor] lib/features/nutrition/nutrition_screen.dart:111-119 — `dayTitle`'s `, <year>` branch (a date in another year) has no scenario and no test; a regression there (`formatShort` without the year) fails nothing. Fix: one screen-test case seeding a row on a date in a previous year with the clock in the current year.
7. [Minor] lib/features/nutrition/nutrition_screen.dart:429-434 — a `ConsumedFood` row with `sourceFoodId == null` whose food name matches a food that IS in the library renders twice: once in its group (the group row's toggle works by `sourceFoodId`, so it cannot see the old row) and once under `No longer in Foods I Eat`. Legacy rows pre-`sourceFoodId` can do this. Display-only; no test covers sourceFoodId null with the food present. Fix: prefer the library match when a library food with the same id exists, or accept and document.
8. [Minor] lib/state/nutrition_state.dart:817-830 — `_reloadViewedRows`'s catch silently keeps the previous viewed rows with no error surface, so a failed re-read after a successful write shows a total that omits that write until the next switch. Consistent with `viewDay`'s per-read catches; noted for the owner, no change required.

## Q1 — Today unchanged: YES (two clock notes, no user-visible change)
- Six `todayConsumed*` getters (nutrition_state.dart:105-107, 989-1026) delegate to `NutritionDayTotals.of` with identical arithmetic: calories `sum + c.caloriesConsumed` int fold; macros `(x * amountConsumed / referenceAmount)` double fold, `?? 0` on fiber/sodium, rounded once at the end. Same order, same rounding. S-24716 pins the 0.45 g case.
- `CalorieRingCard` on today: `viewedTarget`→`_nutritionTarget`, `viewedTotals` on `_consumedToday` (same values), sodium chip condition unchanged (`totals.sodium > 0`, pinned by the changed `first_run_path_test.dart:262` literal), `viewedWaterMl`→`_waterTodayMl`.
- Water wiring: base called `incrementWaterForDate(OmniDateUtils.todayMidnightMs())` (`DateTime.now()`); the viewed methods call `incrementWaterForDate(_todayMs())` (the state's `_clock ?? DateTime.now`). Identical on a device; under an injected test clock the state's clock is the intended one. Not a behaviour change.
- `applyWatchWaterTap`: the new `_pastViewMs == dateMs` branch is unreachable on today (null), the `_waterDayMs` branch is untouched.
- `LogFoodRow`'s five call sites (:188 initState pre-fill, :307 auto-commit guard, :319/:356 toggle/recommit guards, :381 build): `_loggedRow` delegates to `findLoggedTodayForFood` on today, `_commitAmount`→`logConsumedFoodViewed`→`logConsumedFoodAt`, untick→`unlogFoodToday`. Same methods, same guards as base.

## Q2 — Stale or lost writes: two races found (findings 1, 2); all guarded paths check out
- `_reloadViewedRows` (:817-830) re-checks `_pastViewMs == dayMs` before and after the read — a day switch between them is dropped correctly.
- `_stepViewedWater` (:930-944) writes only the viewed cache and re-checks after the save; a minus at 0 writes nothing and notifies nobody (S-24719).
- `resetDayView` bumps `_viewSeq` (:836-843), so a pending viewDay is dropped (S-24705, S-24704).
- `setLoggedAmountViewed` / `deleteConsumedFoodViewed` capture `past` once and let `_reloadViewedRows` re-check — a mid-await day switch cannot put A's rows into B's cache.
- `logConsumedFoodViewed` routes past days through `logConsumedFoodOnDay`, which itself re-clamps `dayMs >= _todayMs()` to the today path.

## Q3 — Removed-food rows: no library write, no duplicate-row path found
- A removed row is never routed to `logConsumedFoodViewed`: `_commitAmount` (log_food_row.dart:142-153) uses `setLoggedAmountViewed` only; `_toggle` untick uses `deleteConsumedFoodViewed(removed.id)`; `_autoCommitIfLogged`/`_recommitIfLogged`/`_toggle(log-on)` all no-op through the null `_loggedRow` check before anything writes. `setLoggedAmountViewed` calls `updateConsumedFood` only — it never touches `_writeThroughLastAmount`/`updateFood`, so no ghost food (S-24709 asserts `repo.getFoods()` stays without `f-rice`).
- `foodFromConsumedSnapshot` (food_helpers.dart:116-134) gives the row id as the Food id, so even a mistaken library write could not collide with a real food id.
- After unticking one: the row and the section vanish, the repo row is deleted for good, and it cannot be ticked back (no library entry; open item 3). Tapping the thumb of an unlogged removed row (transient state) is a silent no-op.
- One-row-per-food-per-day holds for library foods via `logConsumedFoodOnDay`'s same-day sourceFoodId lookup (S-24707, S-24726).

## Q4 — UI standards
- `_DayArrow` (nutrition_screen.dart:356-391): `IconButton` with `tooltip` (`Previous day` / `Next day`), explicit `shape` (`RoundedRectangleBorder`, `OmniTheme.buttonIconRadius`), default 48 dp target (no global or inline `visualDensity` override found), disabled next via `onPressed: null` with `OmniTheme.colors.textDisabled`. No hex colours. Conforms.
- `OmniCardHeader` new params: with neither flank set the else-branch is `Expanded(child: titleText)` — same Row, same spaceBetween, same key `omniCardHeader_title`, same style, same actions cap. Tree identical to base. S-24731 asserts flanking order and the key.
- New copy listed for the owner: `TODAY` / `YESTERDAY` / uppercased short date (+`, <year>`), `Previous day`, `Next day`, `No longer in Foods I Eat`, spoken `Water on Nov 17: ...` (today's `Water today: ...` unchanged).
- No allowlist entry added, no ratchet raised, no raw `Card`/`SnackBar`/bare `IconButton`/colour literal in the changed files. Copy changes are all part of the owner direction, listed above for the owner.

## Docs delta
- docs/design_system.md Daily-Nutrition row rewrite -> applied (test citations exist; sentence accuracy = finding 4)
- docs/navigation_and_screens.md day-title card header -> applied (S-24721 exists)
- docs/navigation_and_screens.md "with arrows to look back at and edit earlier days" -> applied (S-24722 exists)
- docs/nutrition.md "Today's view by default, with arrows to any earlier day" -> applied (S-24722 exists)
- docs/nutrition.md ADDED `### Earlier days` -> applied (cites S-24721/22/24/26/23/28/27/09 — all exist, sentences true)
- docs/state_management/nutrition_state.md ADDED `viewDay(DateTime day)` row -> applied (S-24715, S-24718, S-24704, S-24701 exist; sentence true)
- docs/state_management/nutrition_state.md day-header sentence -> applied but partially false (findings 3, 5)
- docs/state_management/nutrition_state.md "viewed day's log" -> applied (S-24706 exists)
- docs/widget_catalog/nutrition_widgets.md "for the viewed day" -> applied (S-24724 exists)
- docs/widget_catalog/home_screen.md ADDED `No longer in Foods I Eat` -> applied (S-24727, S-24730 exist; sentence true)
- docs/widget_catalog/home_screen.md ADDED `dayLabel` -> applied (S-24725 exists)
- docs/widget_catalog/layout_and_inputs.md ADDED `leading` and `trailing` -> applied (S-24731 exists)

Doc edits the table does not name (all true and cited, but the table should own them): the `applyWatchWaterTap` row's plan-247 sentence (state doc :64), and the added state-doc rows for `shiftViewedDay`, `resetDayView`, viewed reads (×2), viewed edits (×3), viewed water.

## Assumption Log rulings
- base commit 9cf691e9 / branch, unrelated uncommitted files: ratify (matches the diff read this run; `test/food_catalog_load_test.dart`'s 2-line change is unrelated and compiles at the analyze baseline).
- ids S-247xx / D-247xx unique: ratify (test names and docs use them consistently; S-24718/S-24719/S-24732 are additions beyond the plan's scenario list).
- no architect run / plan-lint pending: ratify (governor reported plan-lint could not be run).
- scope guard soft signal: ratify (diff ~1,780 lines incl. two new test files, within the predicted shape).

## Scenario coverage
S-24701..S-24703, S-24705..S-24716 -> test/nutrition_day_view_state_test.dart · `Mock: viewed day` (and Hive twin), same-named tests | S-24704, S-24717 -> same file · group `Mock: gated reads` | S-24718, S-24719 -> same file · group `Mock: viewed day` (beyond plan) | S-24721..S-24731 -> test/nutrition_day_switcher_screen_test.dart · group `plan 247: nutrition day switcher screen`, same-named tests | S-24732 -> same file (beyond plan). No MISSING scenario. Year-suffix title rule: no test (finding 6).
