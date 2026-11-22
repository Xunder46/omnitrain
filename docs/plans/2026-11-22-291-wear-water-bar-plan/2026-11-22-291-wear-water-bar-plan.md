# Plan 291 — The Wear wrist shows the water bar (plan 280 open item 5, part 2)

Part 2 of the water item. Plan 290 made the wrist hold the day's water and log taps; this part draws the bar. The owner's decisions are series 94-96's (`docs/plans/2026-11-01-95-watch-water-bar-plan/`, D-31..D-34) and the Apple wrist is the model: a water bar pinned at the bottom of the Nutrition screen (the Foods list), shown also when the list is empty and never on a single-food screen, a minus on the left, a drop with the glass count in the middle, a plus on the right; each press is one glass added or removed, stored on the wrist first and sent as a `water_glass` event; the count is the phone's count plus the wrist's own taps the phone has not counted yet (0 before the first sync); a click after a press that stored a tap; names a screen reader can say; the count follows local midnight within a minute. No water from inside a workout (the bar is on the Nutrition screen only). Wrist only (`lib/watch/`); no wire, phone, schema or Swift change. Base commit: `.work/2026-11-22-291-wear-water-bar/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch, opening Log food from the start screen shows the foods list (or the "No foods yet" message) with a one-row bar under it: `-`, a drop and the count, `+`. Pressing `+` shows one more glass at once, before the phone answers; pressing `-` one fewer; the minus is greyed at 0 and both buttons are greyed at 500 taps for the day. A press that stored a tap gives one click. A `water_down` frame that arrives while the screen is open changes the count; local midnight with the screen open shows the new day's count within a minute. The bar fits 192 and 227 dp with the portion row and the Log button above it. A screen reader says `Remove one glass`, `Add one glass` and, for the middle, `Water` with `3 glasses` (`1 glass`).

Acceptance: S-29101..S-29112 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the existing Wear files and `test/watch_nutrition_quick_log_test.dart`'s screen tests no new red; Docs delta applied.

## Feature invariants

- The bar draws what `WatchWaterState.snapshot` says, read once per build (the count, `canAdd`, `canRemove` and the spoken count come from the same instant and the same taps). It computes nothing.
- A screen built without a water owner (the debug harness, the phone-free tests) shows no bar and behaves exactly as before.
- The bar is the water owner's only listener: it sets `onWaterChanged` when it appears and clears it when it goes, and re-reads once a minute.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29101 | New widget `WatchWaterBar(state:)` (`lib/watch/nutrition/watch_water_bar.dart`): one row, a `WatchStepButton` minus (`Icons.remove`, label `Remove one glass`, `onPressed` null when `!canRemove`), the middle (`Icons.water_drop` and the count in one `Semantics` element labelled `Water` with the spoken count as its value, children excluded) and a `WatchStepButton` plus (`Icons.add`, `Add one glass`, null when `!canAdd`). Compact look under the wrist's compact rule. Keys `WatchWaterBar.removeKey`, `addKey`, `countKey`. | plan 95 D-31, D-33; `watch_controls.dart` `WatchStepButton` |
| D-29102 | A press calls `state.press(change)`; when it returns true the bar plays `HapticFeedback.selectionClick()` (the Apple `.click`); nothing otherwise. The rebuild comes from the owner's `onWaterChanged`, not from the press. | plan 95 D-32 |
| D-29103 | The bar sets `state.onWaterChanged` in `initState` and clears it in `dispose` only if it is still its own; a `Timer.periodic` of one minute rebuilds it, so midnight changes the count within a minute; both are cancelled on dispose. | plan 95 D-34, D-35 |
| D-29104 | `WatchNutritionScreen` takes an optional `WatchWaterState? water`. With it the screen's body is a `Column`: the existing foods list or "No foods yet" message in an `Expanded`, then the bar once, outside the list's scroll view, so it sits at the bottom in both branches. Without it the screen is unchanged. | plan 95 D-31 |
| D-29105 | `WearApp._openNutrition` passes its `water` owner (plan 290) to the screen. The debug harness is left as is (no owner, no bar). | `wear_app.dart` `_openNutrition` |
| D-29106 | Wear deviation, stated: the Apple wrist draws the drop as an SF Symbol; here it is `Icons.water_drop`. The Apple wrist re-reads through `TimelineView(.everyMinute)`; here a one-minute timer. | `WatchWater.swift`; plan 95 D-34 |
| D-29107 | Not in scope: the launch prune of old confirmed taps; the Apple VoiceOver "magic tap"; any water control outside the Nutrition screen. | plan 96 |

## Input-reality checklist

1. **Writers.** Only `WatchWaterState` writes (frames, taps); the bar reads and presses. One listener slot: the bar owns it while mounted.
2. **Units.** Glasses only; no volume anywhere on the wrist.
3. **Lifecycle.** Opened before the first sync (0); opened with a held frame (restored by the shell at launch); a frame arriving while open (callback); the screen popped while a press is in flight (the press completes in the owner; `mounted` checks guard the rebuild); reopened (a fresh bar re-takes the callback).
4. **Settings changing while open.** None reach the bar.
5. **Time.** Midnight while open: the minute timer rebuilds and the snapshot reads the clock.
6. **Load.** One snapshot per build (at most a few hundred taps read once); a build happens per press, per frame and once a minute.
7. **Wording.** `Add one glass`, `Remove one glass`, `Water`, `1 glass`/`N glasses` are `WatchWaterCopy`'s (plan 290). Stale wording: `docs/wear_os_app.md` lists the water bar among the Apple-only items and says "Nothing on the screen uses it yet" in the water section (the Docs delta).
8. **Slot competition.** The bar takes a row under the portion row and the Log button; at 192 dp the foods list gives up that height (it scrolls). Measured with the new fit tests (S-29109) and the existing nutrition screen tests.

## Scenarios

Widgets (`test/wear_water_bar_test.dart`, new; in-memory store, Mock-first, explicit pumps; the water state on a clock the test moves):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29101 | the screen with a water owner and two foods; and the same with no foods synced; and with no owner | the bar (`+`, `-`, the count) is below the list in the first two, once; absent in the third and the screen is as before | the bar is missing, in the scroll view, or drawn without an owner |
| S-29102 | a held frame of 3; tap `+` | the count shows 4 in the same pump after the press; one `water_glass` tap is stored under the nutrition id; one `HapticFeedback.vibrate`-family call `selectionClick` | the press does not store, the rebuild does not come, or no click |
| S-29103 | tap `-` from 4 | 3; a remove tap stored; one click | minus does nothing |
| S-29104 | count 0 | the minus button is disabled (`onPressed` null); a tap stores nothing and gives no click | minus below zero stores a tap |
| S-29105 | 499 taps stored for today, then one `+` | the 500th is stored; then both buttons are disabled | the cap is not drawn |
| S-29106 | the bar's semantics | the minus is `Remove one glass`, the plus `Add one glass`; the middle is one node labelled `Water` with value `3 glasses` (and `1 glass` at one); the drop and the digits are not separate nodes | the names are missing or the middle is two elements |
| S-29107 | a `water_down` frame applied while the screen is open (count 3 then a frame of 6) | the count shows 6 without a press | no callback hookup |
| S-29108 | the clock passes local midnight with the screen open, then one minute is pumped | the count is the new day's (0, or its own taps) | no minute refresh |
| S-29109 | 192x192 and 227x227 dp, three foods, one selected (portion row and Log button up) | no overflow exception; the bar inside the screen | the bar overflows |
| S-29110 | the screen popped | `onWaterChanged` is cleared and the minute timer is cancelled (no pending timer at teardown) | the callback leaks |
| S-29111 | the shell: open Log food from the start screen | the screen shows the bar bound to the shell's owner: tapping `+` stores one tap in the engine's `waterLog` | `_openNutrition` does not pass the owner |
| S-29112 | a press whose write fails (a store that throws on an observation write) | no click, the count unchanged, no exception | a failed press clicks or throws |

Guard families the lead proves by mutation: the bar's placement, the disabled rules (both), the click and its condition, the labels and the semantics merge, the callback hookup and its clean-up, the minute refresh, the no-owner case, the shell's wiring.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the bar, the screen, the shell** (`crew-builder-watch`; scope `lib/watch/nutrition/watch_water_bar.dart` (new), `lib/watch/nutrition/watch_nutrition_screen.dart`, `lib/watch/app/wear_app.dart`). Exact code in the brief. About 130 lines.
2. **P2 — tests** (lead, as in plans 287-290).
3. **P3 — docs** (lead).
4. **Lead:** analyze, readers, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | Nothing on the screen uses it yet: the bar is the next change. | The water bar sits at the bottom of the Log food screen | S-29102 |
| docs/wear_os_app.md | ADDED | - | `test/wear_water_bar_test.dart` | S-29102 |
| docs/wear_os_app.md | ADDED | - | 11. (owner) on a Wear watch with a paired phone | S-29111 |

The Apple-only list loses "the water bar," (hand edit). Plan 280's open item 5 is a plan record ("part 2, the bar, built by plan 291").

## Assumption Log

- `WatchStepButton` accepts a null `onPressed` and a `compact` flag (`watch_controls.dart`).
- `Icons.water_drop` is a Material icon.
- The nutrition screen's body is a `Padding` over `foods.isEmpty ? _nothingSynced() : _quickLog(foods)`; `_quickLog` is a `Column` with an `Expanded` list, so nesting it in another `Expanded` is sound.

## Progress

- [x] P1 production (crew builder)
- [x] P2 tests (lead; S-29101..S-29112)
- [x] P3 docs (lead)
- [x] Verify and prove (analyze 174; 218 Wear tests green; every non-equivalent mutant killed)
- [ ] (owner) check 11 in `docs/wear_os_app.md` on a watch
