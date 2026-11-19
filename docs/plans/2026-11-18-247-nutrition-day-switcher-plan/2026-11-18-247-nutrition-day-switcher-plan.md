# Plan 247 — Daily Nutrition looks back and edits earlier days with side arrows

Review item 8 (owner direction 2026-11-18: "TODAY for today with side arrows that switch to YESTERDAY or previous dates. They should allow edits too. A food that no longer exists in the library only shows again if keeping it is nearly free").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

Today the Daily Nutrition screen shows only today: the ring, macro donut, sodium, water and the "Foods I Eat" ticks all read the today-caches of `NutritionState`. After this change:

- The first card header reads `‹  TODAY  ›`. The left arrow steps one day back, the right arrow one day forward; the right arrow is disabled on today (no future days). The title reads `TODAY`, `YESTERDAY`, then the date in the app's short form uppercased (`NOV 16`, with the year, `NOV 16, 2025`, when it is not this year).
- Any earlier day shows its own ring, macro donut, sodium chip, water total and ticked foods, with that day's saved target (rolled forward as the app does today).
- Edits work on an earlier day: tick or untick a food, change an amount, water + and -. They write to that day only. Today, the Home strip and the watch never see them.
- A food logged on that day that is no longer in "Foods I Eat" shows in a section `No longer in Foods I Eat` with its own name and numbers and can be edited or removed. Every logged row carries its own name and numbers, so the "hide it and say so" arm of the owner's rule never fires (reported to the owner).
- The `Change target` button shows on today only (a past day's target is not edited here).
- Leaving the screen and opening it again starts on today.

Acceptance: S-24701..S-24717 (state) and S-24721..S-24731 (screen) green; the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set (`.work/windows-base-failing-tests.txt`); Docs delta applied.

## What the user sees

- Open Daily Nutrition: `‹ TODAY ›`, right arrow greyed. Tap `‹`: `YESTERDAY`, yesterday's ring, water and ticks; `Change target` gone. Tap `‹` again: the date. Tap `›` back to today.
- On YESTERDAY tick an egg: yesterday's calories go up and today's Home strip does not move.
- A food deleted from "Foods I Eat" but logged yesterday appears under `No longer in Foods I Eat`; unticking removes it from that day for good.
- To SEE it: log a food today, delete it from Foods I Eat, step back a day after logging it yesterday (or seed via the Mock repository).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24701 | `NutritionState` gets a separate viewed-day cache (`_viewedConsumed`, `_viewedWaterMl`, `_viewedTarget`). The today caches (`_consumedToday`, `_waterTodayMl`, `_nutritionTarget`) are never written for a past day, so `home_screen.dart:552-566`, `watch_nutrition_log_bridge.dart` and `rolloverIfDayChanged` stay today-only and unchanged. `_viewDayMs` holds a past local midnight or null (today); a value at or after today counts as today (`_pastViewMs`). | `nutrition_state.dart:98,126,59`; grep of readers |
| D-24702 | New pure class `NutritionDayTotals` (`lib/state/nutrition/nutrition_day_totals.dart`): `calories, protein, carbs, fiber, fat, sodium` from a `List<ConsumedFood>`, same math as today's getters (doubles summed, rounded once). The six `todayConsumed*` getters delegate to it (one source). | `nutrition_state.dart:106,752-812` |
| D-24703 | Viewed API on `NutritionState` (exact code in the P1 brief): `isViewingToday`, `viewedDayMs`, `viewedConsumed`, `viewedTotals`, `viewedWaterMl`, `viewedTarget`, `isViewedDayLoaded`, `canViewNextDay`, `viewDay(DateTime)`, `shiftViewedDay(int)`, `resetDayView()`, `findLoggedViewedForFood`, `isFoodLoggedViewed`, `logConsumedFoodViewed`, `unlogFoodViewed`, `deleteConsumedFoodViewed`, `setLoggedAmountViewed`, `incrementWaterViewed`, `decrementWaterViewed`. Viewing today, every viewed method delegates to the existing today method. | — |
| D-24704 | Day arithmetic is calendar arithmetic (`DateTime(y, m, d + delta)`), never `ms - 86400000` (a clock-change day is 23 or 25 h). `viewDay` on a day at or after today means today. A later `viewDay` wins: a load whose request number is no longer the latest is dropped (`_viewSeq`). At a switch the viewed caches are cleared at once so a day never shows under another day's numbers; `isViewedDayLoaded` is false until the three reads land. `resetDayView()` sets today without notifying (it runs from `initState`). | `date_utils.dart:startOfDayMs` |
| D-24705 | Past-day writes: a library food ticked, or its amount changed, goes through `logConsumedFoodOnDay(food, amount, loggedAt: <that day>)` (one row per food per day, the row freezes THAT day's saved target; it also stamps `lastAmountConsumed` like a late wrist log: owner check). A removed-food row is changed by `setLoggedAmountViewed(row, amount)`, which updates that row only and never touches a library food (`updateFood` is a plain put on both stores and would create a ghost food). Unlogging deletes the row by id. After every past write the viewed rows are re-read, only if that day is still the viewed one. `logConsumedFoodOnDay` and `applyWatchWaterTap` refresh the viewed cache when their day is the viewed day. | `nutrition_state.dart:629-691,205-221`; `hive_workout_repository.dart:2379` (`updateFood` = put) |
| D-24706 | Water on a past day: `incrementWaterViewed`/`decrementWaterViewed` do the same read-modify-write as the today methods on the viewed day inside `_serialiseWater`, and set only `_viewedWaterMl`. The existing `incrementWaterForDate` must not be used for a past day (it sets `_waterTodayMl` whatever the date). Minus at 0 is a no-op. | `nutrition_state.dart:168-193` |
| D-24707 | `OmniCardHeader` gains optional `leading` and `trailing` widgets that flank the title text, and `titleMinWidth` (so the next arrow keeps its place as the title changes length: 120 dp here, measured at 390x844 where `YESTERDAY` is 117 dp wide; on today the `Change target` button takes half the row, so the title box is 83 dp there and the arrow sits about 37 dp left of its place on an earlier day: accepted). With neither flank set its widget tree is exactly as before. `NutritionState.todayDayMs` (today's local midnight by the state's clock) is added for the title rule. The screen's first header is `OmniCardHeader(leading: prev arrow, title: dayTitle, trailing: next arrow, actions: [target button on today only])`. Keys: `nutrition_day_prev`, `nutrition_day_next`, `nutrition_day_title` (on the title via the existing `omniCardHeader_title`). Arrows are `IconButton` with tooltip (`Previous day`, `Next day`), explicit shape, 48 dp target; next is `onPressed: null` on today. | `omni_card_header.dart` |
| D-24708 | Title rule `dayTitle(day, today)`: same date as today `TODAY`; the day before `YESTERDAY`; otherwise `OmniDateUtils.formatShort(day).toUpperCase()` plus `, <year>` when the year differs from today's. | `date_utils.dart:formatShort` |
| D-24709 | `CalorieRingCard` reads `viewedTotals`, `viewedTarget` and `viewedWaterMl` instead of the `today*` getters (identical on today). The water control calls `incrementWaterViewed`/`decrementWaterViewed` and gets a new optional `dayLabel` (default `today`): its semantics label reads `Water <dayLabel>: <total>` (`Water today: ...` unchanged; past day `Water on Nov 17: ...`). | `calorie_ring_card.dart:99-115,297-315`, `water_tracker_control.dart:68` |
| D-24710 | `LogFoodRow` calls the viewed methods (`isFoodLoggedViewed`, `findLoggedViewedForFood`, `logConsumedFoodViewed`, `unlogFoodViewed`) at its five call sites; a new optional `ConsumedFood? removedRow` makes it a removed-food row: logged means the row id is in `viewedConsumed`, an amount change calls `setLoggedAmountViewed(removedRow, amount)`, the toggle calls `deleteConsumedFoodViewed(removedRow.id)`. `foodFromConsumedSnapshot(ConsumedFood)` in `lib/core/utils/food_helpers.dart` builds the display `Food` (id = the row id). | `log_food_row.dart:154,275,287,299,319,344` |
| D-24711 | `NutritionScreen`: `initState` calls `resetDayView()` before its loads. Below the ring the "Foods I Eat" block shows a spinner while `!isViewedDayLoaded`, otherwise the sections inside a `KeyedSubtree(ValueKey(viewedDayMs))` so each day's rows start from that day's amounts. `_FoodLibraryBrowseSection` listens to the library AND `NutritionState`; after the library sections it adds the section `No longer in Foods I Eat` for `viewedConsumed` rows whose `sourceFoodId` is null or not in `foodLibraryState.foods`; the empty-library state shows only when there are no such rows either. | `nutrition_screen.dart:36-55,168-294,305-379` |
| D-24712 | No earliest day, no future day, no swipe. | — |
| D-24713 | Accepted limit: an amount typed on a row and an arrow tapped within the row's 250 ms auto-commit delay loses that edit, as leaving the screen already does. Open item. | `log_food_row.dart:118,181` |

## Scenarios

Fixtures. Clock `DateTime(2026, 11, 18, 10)`: today = Nov 18, yesterday = Nov 17, D-2 = Nov 16, all local midnights. Library foods: **Rice** `f-rice` grams, ref 100 g, label `g`, 10P/10C/10F (170 kcal per 100 g); **Egg** `f-egg` count, ref 1, label `1 egg`, 6P/1C/5F (73 kcal). Rows (built with `ConsumedFood`, written with `repo.createConsumedFood`, snapshot macros as the food): `c-y1` Rice 200 g on yesterday (340 kcal, 20P/20C/20F), `c-t1` Egg 2 on today (146 kcal). Water: yesterday 750 ml, today 250 ml (`saveWaterVolumeForDate`). Targets: `saveNutritionTargetForDate(today, calories 2200)`, `(yesterday, calories 2000)`; D-2 has none and nothing earlier, so its target is null. Mock repo: call `clearConsumedFoodsForTest()` after `initialize()` (the seed pre-loads today rows). Every state scenario runs through `harnessFactories` (Mock and Hive) unless marked Mock only; `NutritionState(repo, clock: () => DateTime(2026, 11, 18, 10))`.

Level A (new `test/nutrition_day_view_state_test.dart`, plain `test()`):

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24701 | `await state.loadConsumedToday(); loadWaterForToday(); loadNutritionTarget();` then `await state.viewDay(DateTime(2026,11,17))` | `isViewingToday` false; `viewedDayMs == DateTime(2026,11,17).millisecondsSinceEpoch`; `viewedConsumed` ids `[c-y1]`; `viewedTotals.calories 340, protein 20, carbs 20, fat 20, fiber 0, sodium 0`; `viewedWaterMl 750`; `viewedTarget.calories 2000`; AND the today caches untouched: `consumedToday` ids `[c-t1]`, `todayConsumedCalories 146`, `waterTodayMl 250`, `nutritionTarget.calories 2200`. | the viewed API does not exist (compile); the today-untouched half guards a design that would reuse the today caches |
| S-24702 | from today: `shiftViewedDay(-1)`, `shiftViewedDay(-1)`, then `+1`, `+1`, `+1` | after the 2nd call `viewedDayMs` is Nov 16, `viewedConsumed` empty, `viewedWaterMl 0`, `viewedTarget` null; after the 4th `isViewingToday` true; the 5th stays on today (`canViewNextDay` false). | no API |
| S-24703 | clock `DateTime(2026, 3, 9, 10)`: `shiftViewedDay(-1)` twice | `viewedDayMs` equals `DateTime(2026,3,7).millisecondsSinceEpoch` | mutation: `viewedDayMs - 86400000` lands on 23:00 of Mar 7... only in a zone with a clock change on Mar 8 (the lead's EST machine); in UTC it passes both ways (stated) |
| S-24704 | Mock only: repo subclass whose `getConsumedFoodsForDate(yesterday)` waits on a `Completer`; call `viewDay(yesterday)` (not awaited) then `await viewDay(D-2)`, then complete the first | `viewedDayMs` Nov 16, `viewedConsumed` empty (the late yesterday result is dropped) | mutation: the `_viewSeq` check removed |
| S-24705 | view yesterday, then add a listener counting calls, then `resetDayView()` | `isViewingToday` true, `viewedConsumed` ids `[c-t1]`, listener count 0 | mutation: reset leaves `_viewDayMs` |
| S-24706 | view yesterday; `logConsumedFoodViewed(egg, 2)` | returns an id; repo `getConsumedFoodsForDate(yesterday)` holds `c-y1` and an egg row with `targetCalories 2000`; `viewedConsumed` length 2; `consumedToday` ids still `[c-t1]` | a today-path write puts the egg in today |
| S-24707 | view yesterday; `logConsumedFoodViewed(rice, 300)` | still ONE rice row on yesterday with id `c-y1` and `amountConsumed 300`; `viewedTotals.calories 510` | a create-always path adds a second rice row |
| S-24708 | view yesterday; `unlogFoodViewed('f-rice')` | true; repo yesterday empty; `viewedConsumed` empty; `consumedToday` ids `[c-t1]`; a second call returns false | the today path finds no row |
| S-24709 | library has NO `f-rice` (do not create it); view yesterday; `setLoggedAmountViewed(c-y1 row, 100)` | repo row amount 100; `viewedTotals.calories 170`; `repo.getFoods()` still has no `f-rice` | routing it through `logConsumedFoodViewed` stamps `lastAmountConsumed` with `updateFood`, a put that creates a ghost food |
| S-24710 | `deleteConsumedFoodViewed('c-y1')` while viewing yesterday, then with an unknown id | true then false; repo yesterday empty | no API |
| S-24711 | view yesterday; `incrementWaterViewed()`; then view D-2 and `decrementWaterViewed()` | repo yesterday 1000, `viewedWaterMl` was 1000, `waterTodayMl` still 250; on D-2 the minus is a no-op: repo D-2 0, no row written | `incrementWaterForDate` on a past day overwrites `_waterTodayMl` (would read 1000) |
| S-24712 | on TODAY: `logConsumedFoodViewed(egg, 3)`; `incrementWaterViewed()`; `unlogFoodViewed('f-egg')` | the egg row `c-t1` becomes amount 3 (`todayConsumedCalories 219`); `waterTodayMl` 500 and `viewedWaterMl` 500; after the unlog `consumedToday` empty | guards the delegation to the today methods |
| S-24713 | view yesterday; `logConsumedFoodOnDay(egg, 1, loggedAt: DateTime(2026,11,17,20))` | `viewedConsumed` now holds the egg row (2 rows) | the viewed cache would stay stale after a late wrist log |
| S-24714 | view yesterday; `applyWatchWaterTap(dateMs: yesterday, tapId: 't1', add: true)` | returns true; `viewedWaterMl 1000`; `waterTodayMl` still 250 | the viewed cache would stay stale |
| S-24715 | `viewDay(DateTime(2026,11,18))` after viewing yesterday, and `viewDay(DateTime(2026,11,19))` | both: `isViewingToday` true, `viewedConsumed` ids `[c-t1]` | a future day would show an empty future |
| S-24716 | two Egg-like rows `protein 30 per 100 g`, amount 1.5 g... i.e. each contributes 0.45 g protein (`protein 30, referenceAmount 100, amountConsumed 1.5`) | `NutritionDayTotals.of(rows).protein == 1` (0.9 rounded once; per-row rounding would give 0); `state.todayConsumedProtein` equals it with the same rows in the today cache | per-row rounding |
| S-24717 | view yesterday with a Completer-delayed repo (Mock only, as S-24704) | `isViewedDayLoaded` false until the reads land, true after; on today it is always true | no API |

Level B (new `test/nutrition_day_switcher_screen_test.dart`, Mock only): copy `_freshRepo`, `_buildState` and the `_egg` helper from `test/nutrition_log_from_library_test.dart` (change the egg to 6/1/5 labelled `1 egg`, add `_rice`), pump `NutritionScreen` with `NutritionState` (clock injected), `FoodLibraryState`, `test_nutrition_primer_state.dart`'s primer state; `tester.binding.setSurfaceSize(const Size(600, 1200))`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24721 | open the screen on the Level A data | header title `TODAY`; `nutrition_day_prev` enabled, `nutrition_day_next` disabled | no arrows |
| S-24722 | tap prev | title `YESTERDAY`; ring shows `340`; Rice thumb semantics checked, Rice amount field `200`; Egg unchecked. Tap prev again: title `NOV 16`, nothing checked. Tap next twice: `TODAY`, Egg checked, amount `2`. | no switching |
| S-24723 | on yesterday | `nutrition_target_button` absent; back on today present | the button would stay |
| S-24724 | on yesterday tap the Egg thumb | repo yesterday holds an egg row; repo today still only `c-t1`; ring `413` (340 + 73) | a today-path write |
| S-24725 | on yesterday tap `water_tracker_plus` | `viewedWaterMl 1000`, `waterTodayMl 250`; the control's semantics label starts `Water on Nov 17` (today: `Water today`) | no day label |
| S-24726 | on yesterday change the Rice amount to `300` and wait 300 ms (`tester.pump(const Duration(milliseconds: 300))`) | repo rice row amount 300, still one row; today untouched | a today-path auto-commit |
| S-24727 | library holds Egg only; yesterday has `c-y1` Rice | section title `No longer in Foods I Eat` with `Rice`, its thumb checked, amount `200`, ring `340`; change amount to `300`: row 300, `repo.getFoods()` has no Rice; untick: the row and the section vanish, repo yesterday empty. On today the section is absent. | no section; or a ghost food |
| S-24728 | go to yesterday, dispose the screen, pump a new `NutritionScreen` on the same state | title `TODAY` | no reset |
| S-24729 | today Egg amount `2`; go to yesterday: Egg amount shows the default `1` unchecked; back to today: `2` | each day's rows start from that day's amounts | stale controllers |
| S-24730 | library empty and yesterday has a row | no empty state; the removed-food section shows | the empty state would hide the row |
| S-24731 | `OmniCardHeader(leading: A, trailing: B, title: 'X')` pumps both flanking the title; `OmniCardHeader(title: 'X')` unchanged | `leading` left of the title, `trailing` right of it, title key kept | no params |

## Input-reality checklist

1. Writers: `ConsumedFood` rows are written by `logConsumedFood`/`logConsumedFoodAt`/`logConsumedFoodOnDay` (`nutrition_state.dart`), called by `LogFoodRow`, `watch_nutrition_log_bridge.dart:160` and the Add-food flows (`add_food_screen.dart`, `save_default_as_own_food.dart`); water by `incrementWaterForDate`, `decrementWaterForDate` and `applyWatchWaterTap`; targets by `saveNutritionTargetForDate` (Targets screen). Units: grams or count multiplier, ml, kcal.
2. Lifecycle: a food deleted or archived after it was logged leaves its rows with the frozen name and numbers (`models.dart:ConsumedFood`: name and macros are non-null) and `sourceFoodId` possibly null: they appear under `No longer in Foods I Eat` (S-24727). Rows from before the sodium freeze read sodium null = 0.
3. Settings: the volume unit follows the weight unit; the viewed water is stored ml and the control formats it (existing `_onSettingsChanged` notifies). Nothing else read.
4. Time: a clock-change day (S-24703); a future day clamps to today (S-24715); the title is computed from the clock at build, so `YESTERDAY` becomes the date after midnight on the next rebuild; one row per food per day holds; a zone change moves "today" but a viewed past local midnight keeps its instant (accepted).
5. Cost: switching a day = 3 repository reads (rows, water, target); an edit = one write and one rows read; viewing today = no extra read.
6. Words: the `TODAY` header is named in `design_system.md`, `navigation_and_screens.md`; see Docs delta. New copy: `YESTERDAY`, `No longer in Foods I Eat`, `Previous day`, `Next day`, `Water on <date>` (owner to read).
7. Competition: the title block and the `Change target` button share one header row (the actions cluster is capped at half the width, the title ellipsizes); a wrist log or tap for the viewed past day and a phone edit on it both land (S-24713, S-24714).

## Phases

1. **P1 builder-app**, scope `lib/state/nutrition_state.dart`, `lib/state/nutrition/nutrition_day_totals.dart` (new), `lib/core/utils/food_helpers.dart`: D-24701..D-24706 and `foodFromConsumedSnapshot` (exact code in the brief). No full suite.
2. **P2b builder-app** (after P1; runs beside P3, disjoint scopes), scope `lib/features/nutrition/widgets/log_food_row.dart` (D-24710). Then **P2a builder-app** (after P2b, so no builder tests against a half-edited row), scope `lib/state/nutrition_state.dart` (one getter, `todayDayMs`), `lib/widgets/layout/omni_card_header.dart`, `lib/features/nutrition/nutrition_screen.dart`, `lib/features/nutrition/widgets/calorie_ring_card.dart`, `lib/features/nutrition/widgets/water_tracker_control.dart` (D-24707..D-24709, D-24711). Exact code in the briefs.
3. **P3 builder-app**, scope `test/nutrition_day_view_state_test.dart` (new): S-24701..S-24717. After P1, beside P2b. No full suite.
4. **P4 builder-app** (after P2a), scope `test/nutrition_day_switcher_screen_test.dart` (new): S-24721..S-24731. No full suite.
5. **P5 lead**: readers set, full suite compared with the base failing set, analyze, mutation pass, `crew-docs-keeper`, reviewer.

## Readers

Tests that build the changed widgets or call the methods whose bodies change (all must stay green untouched): `nutrition_log_from_library_test`, `nutrition_test`, `picker_polish_test`, `row_caption_and_primer_test`, `daily_targets_display_test`, `decimal_comma_input_test`, `first_run_path_test`, `header_standardization_test`, `screen_widget_test` (group on the nutrition screen), `nutrition_target_button_test`, `food_group_membership_test`, `watch_nutrition_quick_log_test`, `state_test` (groups `daily water log`, `NutritionState volume unit`), `watch_nutrition_empty_copy_test`, `screen_overflow_contract_test`, `ui_standards_contract_test`, `docs_indexing_contract_test` (red here at base). The Home strip reads `todayConsumed*` (delegated getters): `home_*` tests that show the strip.

## Mutation list (lead)

(a) `_viewSeq` check removed (S-24704); (b) reset leaves `_viewDayMs` (S-24705); (c) shift by `- 86400000` (S-24703); (d) future day not clamped (S-24715); (e) past write uses the today path (S-24706, S-24707); (f) removed-row amount through `logConsumedFoodViewed` (S-24709); (g) `incrementWaterViewed` sets `_waterTodayMl` (S-24711); (h) `logConsumedFoodOnDay` skips the viewed refresh (S-24713); (i) `applyWatchWaterTap` skips the viewed refresh (S-24714); (j) per-row rounding in totals (S-24716); (k) next arrow enabled on today (S-24721); (l) target button shown on a past day (S-24723); (m) removed-section filter ignores the library (S-24727); (n) `resetDayView` call removed from `initState` (S-24728); (o) rows not keyed by day / spinner removed (S-24729).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/design_system.md` | MODIFIED | `TODAY` (with `nutrition_target_button` labelled | between the `nutrition_day_prev` and `nutrition_day_next` arrows | S-24721, S-24723 |
| `docs/navigation_and_screens.md` | MODIFIED | `TODAY` card header at the top of that screen | day-title card header (`TODAY`, `YESTERDAY` or the date) at the top of that screen | S-24721 |
| `docs/navigation_and_screens.md` | MODIFIED | and the grouped "Foods I Eat" browse card. | and the grouped "Foods I Eat" browse card, with arrows to look back at and edit earlier days. | S-24722 |
| `docs/nutrition.md` | MODIFIED | Today's view, and the only screen that fires the feature's loads. | Today's view by default, with arrows to any earlier day, and the only screen that fires the feature's loads. | S-24722 |
| `docs/nutrition.md` | ADDED | - | ### Earlier days | S-24722, S-24724, S-24727, S-24728 |
| `docs/state_management/nutrition_state.md` | ADDED | - | `viewDay(DateTime day)` | S-24701 |
| `docs/state_management/nutrition_state.md` | MODIFIED | renders the `Today` header via `CalorieRingCard` | renders the day header (`Today`, `Yesterday` or the date) with `OmniCardHeader` above `CalorieRingCard` | S-24701 |
| `docs/state_management/nutrition_state.md` | MODIFIED | whose checkbox toggles the food in/out of today's log via `NutritionState` | whose checkbox toggles the food in/out of the viewed day's log via `NutritionState` | S-24706 |
| `docs/widget_catalog/nutrition_widgets.md` | MODIFIED | toggle that logs or unlogs the food for today | toggle that logs or unlogs the food for the viewed day | S-24724 |
| `docs/widget_catalog/home_screen.md` | ADDED | - | `No longer in Foods I Eat` | S-24727 |
| `docs/widget_catalog/home_screen.md` | ADDED | - | `dayLabel` | S-24725 |
| `docs/widget_catalog/layout_and_inputs.md` | ADDED | - | `leading` and `trailing` | S-24731 |

The keeper adds `### Earlier days` to `docs/nutrition.md` after the `NutritionScreen` section (file is at 45,714 bytes: at most 12 lines): the arrows and titles (S-24721, S-24722), edits write to that day only (S-24724, S-24726), the target button is today-only (S-24723), reopening starts on today (S-24728), a removed food's row and why no ghost food (S-24727, S-24709), each sentence citing its test. Rows for the new API go in `docs/state_management/nutrition_state.md` (34 KB) in the method table, one row per method group (navigation; viewed reads; viewed edits; viewed water). Stale-term sweep (lead): `grep -rIn "TODAY\|today's log\|logs or unlogs the food for today" docs` outside plans, history, releases: hits covered above; `docs/data_models.md` 542-543 name methods that stay; it is at the size band and is NOT touched.

## Open items

1. (owner) A tick or amount change on an earlier day also remembers that amount as the food's "last amount" (it pre-fills the next day's row), as a late wrist log already does.
2. (owner) Every logged row carries its own name and numbers, so a food missing from the library always shows (under `No longer in Foods I Eat`); nothing is ever hidden with a note.
3. (owner) Unticking a removed food deletes that day's row for good; it cannot be ticked back because the food is not in the list.
4. D-24713: an edit typed within a quarter second of tapping an arrow is lost.
5. (owner) No earliest day: the left arrow always works.
6. A logged row with no `sourceFoodId` (older rows) whose food is still in the library shows twice: in its group and under `No longer in Foods I Eat` (review finding 7, display only).
7. After a failed re-read following a successful earlier-day write, the screen keeps the previous rows until the next switch (review finding 8, same pattern as `viewDay`).

## Predicted files

`nutrition_state.dart` (+200), `nutrition_day_totals.dart` (+45), `food_helpers.dart` (+25), `omni_card_header.dart` (+35), `nutrition_screen.dart` (+130), `calorie_ring_card.dart` (+12), `water_tracker_control.dart` (+10), `log_food_row.dart` (+45), two new test files (~450 + ~420), docs (~60 lines across six).

## Progress

- [x] Seeded
- [x] P1 state (4 min), P2b row, P2a screen/header/card/water (7 min)
- [x] P3 state tests (32 at first, now 38 with S-24733/S-24734), P4 screen tests (11, now 12 with S-24735)
- [x] P5 verify: full suite +7093 passed, 1072 failed, no failing name outside the Windows base set; analyze 178, 0 errors; mutation pass 29 of 29 killed after 3 tests-only additions (S-24718, S-24719, S-24732) and 3 more for the review fixes (S-24733..S-24735); docs (keeper, 12 of 12 rows); review (0 blocker, 4 major, 4 minor)
- [x] Review fixes: findings 1 and 2 (code, tests S-24733, S-24734), 3, 4, 5 (docs), 6 (test S-24735); finding 7 recorded (Open item 6), 8 accepted
- [ ] (owner) look at it on a device, Open items 1, 2, 3, 5, 6

## Assumption Log

- 2026-11-18: base commit in `.work/item8/base.txt` (9cf691e9), branch `claude_develop`. Unrelated uncommitted files (`test/food_catalog_load_test.dart`, `macos/Flutter/GeneratedPluginRegistrant.swift`) are never staged.
- 2026-11-18: ids S-247xx and D-247xx: none found in `test/`, `docs/`, `watch/`.
- 2026-11-18: no architect run (seed has phases, plan-lint to be clean), as plans 244-246.
- 2026-11-18: scope guard at seeding: 5 phases, one track (phone), 13 decisions, 28 scenarios, production ~520 lines: one soft signal (phases), within budget, one PR.
- 2026-11-18: `plan-lint.ps1` (before and after) was denied by the permission classifier and not retried; the 7 Old markers were checked with `grep -F` before the build and all 12 Docs delta rows (Old gone, New on one line) after it.
- 2026-11-18: one existing test line changed by the lead: `test/first_run_path_test.dart` S-12914 looked for the literal `todayConsumedSodium > 0` in the ring card, which now reads `totals.sodium > 0` (same premise: the sodium chip is hidden at 0).
- 2026-11-18: two Docs delta New markers were corrected after review: the day header is built by `OmniCardHeader` above `CalorieRingCard` (not by the card), and the Daily Nutrition row says the title sits between the arrows with the target button in actions.
- 2026-11-18: layout measured with a throwaway probe at 390x844, 1.0x and 1.3x text: no overflow, `Change target` fits (195 to 374 dp); at 2.0x text the page overflows 289 dp at the bottom (not the header; 2.0x is outside the repo's overflow contract). `titleMinWidth` 96 raised to 120 dp (YESTERDAY is 117 dp). Probe deleted.
- 2026-11-18: the crew built it in 6 builder runs of 3 to 7 minutes each (P1, P2b, P2a, P3, P4, P5, P6) plus a docs keeper (4.8 min) and a reviewer (6.9 min); the lead wrote no production code.

## Feedback

Review: `2026-11-18-247-nutrition-day-switcher-plan.review.md` (APPROVE WITH FIXES: 0 blocker, 4 major, 4 minor).
- [x] 1 wrist water tap landing under another day's view: re-check after the await (S-24733)
- [x] 2 a write landing while a day's reads are in flight: write epoch, reads rerun once (S-24734)
- [x] 3, 4, 5 stale doc sentences rewritten (nutrition_state.md consumers row, design_system.md Daily Nutrition row)
- [x] 6 year title test (S-24735)
- [ ] 7 legacy rows without a source id shown twice: Open item 6
- [ ] 8 failed re-read keeps old rows: Open item 7
