# Plan 237 — The nutrition day follows the clock: no yesterday's food, water or target after midnight

Series: nutrition/calendar/summary pre-launch review (2026-11-16, second pass), item "day change is checked once, at Home's first load (Home food strip stale next morning if the app stayed alive)". Phone only (`lib/state/nutrition_state.dart`, `lib/features/home/home_screen.dart`). Two builder runs (state + Home code and state tests, then the Home screen test), then docs. Status: COMMITTED (built, mutation-checked (7 of 7 killed after three tests were added), docs applied; full suite +7957 ~4 green.

## Goal and acceptance

`HomeScreen._checkAndHandleDateRollover` runs once, right after Home's first load (`home_screen.dart:257`). An app left in the background overnight resumes with Home still mounted: nothing re-checks the day, so the Home food strip, the calorie ring, the water total and today's target keep showing YESTERDAY's values as "today". Worse, the first food logged after midnight is built for the new day (`logConsumedFood` takes `todayMs` fresh) but is APPENDED to the stale list (`nutrition_state.dart:415`), so the ring shows yesterday's foods plus the new one. After this change the nutrition state notices the day change itself, on app resume and before every log that touches today's list, and rolls over to the new day (empty day, new day's target and water).

Acceptance: S-23701..S-23708 green, those marked "fails without" red at the base commit or killed by the lead's mutation; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Leave the app in the background overnight, open it in the morning: Home's food strip, the calorie ring and the water total show an empty new day (and the new day's target), not yesterday's numbers.
- Log a food as the first thing in the morning from any screen: the ring shows only that food.
- Nothing else changes. A user who keeps the screen on across midnight without leaving the app is not covered until the next resume or log (open item 1).
- To SEE it: log a food, send the app to the background, set the phone's clock past midnight, reopen the app: the strip is empty for the new day.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `NutritionState` takes an optional `DateTime Function()? clock` (named, default `DateTime.now`), kept as `_clock`; a private `DateTime _now() => (_clock ?? DateTime.now)();` and `int _todayMs() => OmniDateUtils.startOfDayMs(_now());`. Every `OmniDateUtils.todayMidnightMs()` call in the file (lines 145, 268, 310, 314, 330, 350, 385, 521, 594) becomes `_todayMs()`; `logConsumedFood`'s `final now = DateTime.now().millisecondsSinceEpoch;` (line 384) becomes `_now().millisecondsSinceEpoch` so a faked clock names the row's day; `_nextIdStamp` keeps the real clock. | `nutrition_state.dart:15,384-385` |
| D-2 | A private `int? _cacheDayMs` records the day the today-caches (`_consumedToday`, `_nutritionTarget`, `_waterTodayMl`) belong to. It is set to `todayMs` in `loadConsumedToday`, `getTodayConsumedFoods` and `rolloverToDate(dateMs)` (to `dateMs`). | `nutrition_state.dart:287,330,350` |
| D-3 | New public `Future<bool> rolloverIfDayChanged()`: returns `false` at once when `_cacheDayMs` is null (nothing loaded yet) or equals `_todayMs()`; otherwise `await rolloverToDate(today)` then `await loadConsumedToday()` and returns `true`. A rollover already in flight is shared: a `Future<void>? _rolling` holds it, a second concurrent call awaits the same future and returns `false`. | new |
| D-4 | `logConsumedFood` starts with `await rolloverIfDayChanged();` (after the amount validation, before the cache or `_todayMs()` is read) so a log never appends to yesterday's list. `logConsumedFoodAt` needs no call of its own: its cache lookup is by today's key, so it finds nothing on a stale cache and falls through to `logConsumedFood` (the lead removed the builder's redundant second call after a mutant showed it dead). `unlogFoodToday` and the water increments need no call: the first filters by today's key, the second takes its day from the caller. | `nutrition_state.dart:376,546,652` |
| D-5 | Home becomes a `WidgetsBindingObserver`: `initState` adds it, `dispose` removes it, `didChangeAppLifecycleState(resumed)` calls `unawaited(widget.nutritionState.rolloverIfDayChanged())` when `mounted`. `_lastSeenDate`, `_initializeLastSeenDate` and `_checkAndHandleDateRollover` are removed; the one check after the initial loads becomes `unawaited(widget.nutritionState.rolloverIfDayChanged())` (it is a no-op unless the day changed during the load). The old post-frame wrapper is not needed: a lifecycle callback and a post-load continuation both run outside a build. | `home_screen.dart:148,257-310` |
| D-6 | No Timer to midnight and no change to water or target semantics (open item 1). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23701 | State test, both harnesses. A `NutritionState` with a fake clock at 15 June 2026 10:00. Save a target for 15 June (calories 2200), log a food, add water for 15 June, `loadConsumedToday()`. Move the clock to 16 June 08:00 and call `rolloverIfDayChanged()`. | returns `true`; `consumedToday` is empty and `todayConsumedCalories` is 0; `waterTodayMl` is 0; `nutritionTarget` is the 16 June read (inherits 2200); the 15 June row is still in the store (`getConsumedFoodsForDate` of 15 June has 1 row). | the base has no such method and never re-checks |
| S-23702 | The same state, clock still on 15 June (later in the day), `rolloverIfDayChanged()`. | returns `false`; `consumedToday` still holds the food; no extra notification (count listener calls around the call). | passes both ways on purpose (mutation: the check always rolls over) |
| S-23703 | The same state. Clock moves to 16 June 08:00 and `logConsumedFoodAt(otherFood, 50)` is called WITHOUT calling `rolloverIfDayChanged()` first. | `consumedToday` holds only `otherFood`'s row, whose `dateMs` is the 16 June local midnight; the store has one row on 15 June and one on 16 June. | the base appends the new row to yesterday's cached list (the cache holds two rows, one of them yesterday's) |
| S-23704 | Two concurrent calls after the clock moves: `final r = await Future.wait([state.rolloverIfDayChanged(), state.rolloverIfDayChanged()])`. | one is `true` and one `false`; the state ends empty for 16 June; a following `rolloverIfDayChanged()` is `false`. | passes both ways on purpose (mutation: the in-flight future is not shared, which double-clears; observable only by the listener count, so the test counts notifications and expects the same count as one rollover) |
| S-23705 | A fresh `NutritionState` (nothing loaded), clock on any day; `rolloverIfDayChanged()`. | returns `false`; `consumedToday` empty; no exception; no repository read (a Mock repo subclass or a counter is not needed: assert `nutritionTarget` is still null). | passes both ways on purpose (mutation: a null `_cacheDayMs` is treated as "changed", which would load a target) |
| S-23707 | State test, both harnesses. The rollover is started and, before it finishes, `logConsumedFood` is called (`final r = state.rolloverIfDayChanged(); await state.logConsumedFood(f, 100); await r;`). | the row's `targetCalories` is 2200 (the new day's inherited target), its `dateMs` the 16 June midnight, and it is the only row. | without the in-flight sharing the log reads the just-cleared (null, all-zero) target |
| S-23708 | A direct `rolloverToDate(d16)` after the clock moved, then `rolloverIfDayChanged()`. | returns `false` (the caches already belong to 16 June). | passes both ways only if `rolloverToDate` marks the day (the lead's mutation g) |
| S-23706 | Screen test, Mock only, plain copy of the harness of `test/home_nutrition_summary_card_test.dart` with a `NutritionState` built with the fake clock: pump Home, settle, a food logged on 15 June shown in the strip; move the clock to 16 June 08:00; `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed)`; pump. | the strip shows the empty state (no calories) and `state.consumedToday` is empty. | the base never re-checks on resume |

## Input-reality checklist

1. Writers and units: the only writers of the today-caches are the loads, `rolloverToDate`, the log and unlog paths (all in `NutritionState`); days are local-midnight instants (plan 235 keeps stored keys zone-safe). The wrist's quick-log keeps its own day logic (`logConsumedFoodOnDay`, unchanged).
2. Lifecycle: `_cacheDayMs` starts null (nothing loaded), set by the loads, so a fresh app with no Home yet never rolls. The Home observer is removed in `dispose`; a rollover finishing after dispose only notifies the state's listeners (the state outlives Home). A load racing a rollover: the rollover's own `loadConsumedToday` replaces the list last.
3. Settings changing while open: none. A time-zone change while the app is open is also caught: `_todayMs()` differs from `_cacheDayMs` after a resume.
4. Time: DST and zone changes only move `_todayMs()`; the clock jumping backwards (a manual change to yesterday) rolls over to yesterday the same way, which is correct ("the day it is").
5. Cost: a resume does two integer compares unless the day changed.
6. Words: none.
7. Slot competition: concurrent `rolloverIfDayChanged` calls share one rollover (D-3); a log racing a rollover awaits it first (D-4).

## Phases

1. **P1 builder-app**, scope `lib/state/nutrition_state.dart`, `lib/features/home/home_screen.dart`, `test/nutrition_day_follows_the_clock_test.dart` (new, S-23701..S-23705). No full suite.
2. **P2 builder-app**, scope `test/home_day_rollover_on_resume_test.dart` (new, S-23706), starts by copying the harness helper of `test/home_nutrition_summary_card_test.dart`.
3. **P3 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "rolloverToDate\|NutritionState(\|_checkAndHandleDateRollover\|todayMidnightMs" test`: `test/state_test.dart` (~4151, ~4501), `test/nutrition_test.dart` (~3911), every Home screen test (`home_*_test.dart`, `app_theme_reactive_test.dart`). A reader that depends on `_lastSeenDate` or on the post-frame rollover is reported, not edited.

## Mutation list (lead)

(a) `rolloverIfDayChanged` returns false always (S-23701/03/06); (b) it rolls over on equal days (S-23702); (c) the call in `logConsumedFood` removed (S-23703); (d) null `_cacheDayMs` treated as changed (S-23705); (e) the in-flight future not shared (S-23704); (f) the Home resume handler removed (S-23706); (g) `rolloverToDate` does not set `_cacheDayMs` (S-23701 second call).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/nutrition_state.md` | ADDED | - | `rolloverIfDayChanged()` | S-23701, S-23703 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `Day-rollover safety net.` | `Day-rollover safety net (also run by `rolloverIfDayChanged` on resume and before a log).` | S-23701 |
| `docs/navigation_and_screens.md` | MODIFIED | `whenever `_lastSeenDate` differs from today.` | `resumes and once after its first load` | S-23706 |

Stale-term sweep: `grep -rIn "_lastSeenDate\|checkAndHandleDateRollover\|S-054\|rolloverToDate" docs` outside plans/history/releases: the lead lists each hit as a row.

## Open items

1. A user who keeps the app in the foreground across midnight sees the old day until the next resume or log (no Timer to midnight): small follow-up if the owner wants it.
2. (owner) Log a food, background the app, set the clock past midnight, reopen: empty strip.

## Predicted files

`nutrition_state.dart` (+40), `home_screen.dart` (-35 +14), two new test files (~220 and ~120), one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] P2 Home screen test (S-23706, S-23706b)
- [x] Docs, mutation pass
- [x] Full suite (+7957 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-237/base.txt` (84b9cc83); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-237xx: none found. The base cannot run S-23701..S-23705 (no clock parameter, no method), so "fails without" is shown by the lead's mutations, not a base run.

## Feedback

(none yet)
