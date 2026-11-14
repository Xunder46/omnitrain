# Series 157 — what counts in Stats (group A of the 2026-11-12 pre-launch review)

Source: items 1, 3 and 10 of the Stats pre-launch review (memory `stats-prelaunch-review-2026-11-12`). The owner accepted the recommendations on 2026-11-13 ("A: what counts"). Split by the scope budget (`.github/copilot/pr-scope-budget.md`): three PRs, planned one at a time against the code as it is by then.

| PR | Order | Scope | Tracks | Depends on |
|---|---|---|---|---|
| 157a | 1 (built, uncommitted) | Finish drops every `set` entry never logged and any set exercise left empty (review item 1). Plan: `2026-11-13-157a-stats-unlogged-sets-plan/`. | phone state | none |
| 157b | 2 (built, uncommitted) | Est. 1RM accuracy: the rep count in the estimate is capped at 12 everywhere the formula lives (phone `StatsProgressService.epley1RM`, and the wrist's Swift twin `WatchPersonalBests.estimateOneRepMax`, `watch/watchos/Sources/WatchSessionEngine/WatchPersonalBests.swift:216`, which must give the same number bit for bit); and an exercise sits on the reps axis only when zero-weight entries strictly outnumber weighted ones over its whole history, never because of one set (review items 3 and 10, first half). One decision function shared by `computeProgressData` (`repsDayMap.isNotEmpty`, line ~342) and `_repsAxisExercises` (+ `_hasBodyweightEntry`, line ~1473). | phone `lib/core`, wrist Swift twin | 157a (placeholders stop flipping the axis for new data) |
| 157c | 3 (built, uncommitted) | Sustained High Load: a week that holds sessions but no rated one is left out of the twelve-week baseline instead of counting as zero load (a truly empty week still counts as zero, D-1705). Needs `WeeklyLoad` to say whether the week held sessions (`lib/core/models/training_load.dart:76`, built in `StatsProgressService.weeklyLoads`, line ~603; baseline in `lib/core/models/sustained_high_load.dart:106`). Review item 10, second half. | phone `lib/core` | none (can run beside 157b only if scopes are disjoint: both touch `stats_progress_service.dart`, so serial) |
| 157d | after 157a (order open) | Prune planned sets of workouts the watch took part in, once the watch's rows have settled (the importer's side; D-11 of 157a skips them today). Needs a rule for "settled" and the late-entry path (`_placeAroundUserRows`, plan 03d). | phone state + importer | 157a |

## Shared decisions

- No migration: nothing stored before these changes is repaired (D-8 of 157a).
- Rep cap is 12 (the owner accepted "about 12"); the cap changes the displayed Est. 1RM and the in-session New PR toast together because they call one function.
- Axis rule on a tie goes to the weight axis (the example that motivated it: a lift with one stray zero-weight set).
- 157b changes a number the wrist compares for its own PR check: phone and wrist must change in the same PR, and the bests frame's fixtures and the Swift replay traces are readers to list in its seed.

## Owner decisions still open (none blocks 157a)

The Finish dialog's exercise count and a warning for a typed-but-unlogged set (157a Open items).
