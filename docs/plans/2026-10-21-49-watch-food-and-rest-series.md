# Series 49/50: food logging reachable on the watch, and rest travelling between the two devices

> Status: 49a, 49b, 50a, 50b BUILT 2026-10-21; owner device checks pending. Seeded 2026-10-21 (owner, in chat: "food logging should be reachable; rest should propagate from one device to another"; the exercise list's letter jump is its search). Scout sheets: `.work/crew/2026-10-21-49/scout-{food,rest-phone,rest-wrist}.md`.
> Binding conventions: docs/global_conventions.md; docs/rest_tracking.md; .github/copilot/pr-scope-budget.md

## What the user sees after the series

- Food: the watch's start screen has a Log food button, and the session menu has a Log food row, so food can be logged with or without a workout. The list is the phone's Foods-I-Eat list (the foods you eat, A to Z inside your categories, the foods you logged on the watch first), the Crown sets the portion in half servings, and Log lands in the phone's day log (existing behaviour). The phone sends the list whenever the watch syncs.
- Rest: logging a set on either device starts the rest on both, counting from the moment you logged it. Next on the watch (or logging the next set on either device) ends the rest on both. Pausing the rest chip on the phone freezes it on the watch. Both devices ping as the Rest Ping setting says. The rest screen on the watch keeps replacing the logging screen, and you end the rest by hand before the next set.

## Today (scout facts)

- Food: the wrist side is built (`WatchNutritionView/State`, `foods_down` handling, quick-log observations, the phone's `WatchNutritionLogBridge` writing the day log and receipting) but the watch app never builds the nutrition state, never passes `onOpenNutrition`, and the phone's request handler never sends `foods_down` (no production caller of `buildFoodsDown`).
- Rest: the wrist already accepts, times, pings and clears a phone rest (`adoptTimer` exempts rest from the earlier-start rule; S-336 tests) and its shell swaps to the rest screen on any arrival. The phone never sends one (`WatchTimerPush` is work timers only, D-4). A wrist rest reaches the phone as an open rest when its set arrives and as a closed window when the wrist ends it, but a wrist Next on a rest the PHONE started names a phone-logged entry (`entry-<slot>-<n>`) that the importer's per-pass `_placed` map does not know, so the phone's rest stays open.

## Split

- 49a phone sends `foods_down` with every routines sync. 49b the watch app mounts the nutrition surface (start screen button, menu row).
- 50a the phone pushes its open rest (running, paused, ended) to the wrist as a `rest` timer. 50b the importer closes the phone's rest when the wrist's `rest` event names a phone-logged entry.
- 49a || 49b, then 50a || 50b (disjoint files), then docs, then the lead's simulator checks.
