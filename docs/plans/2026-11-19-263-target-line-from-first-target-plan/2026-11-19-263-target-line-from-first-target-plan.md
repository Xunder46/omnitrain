# Plan 263 — The dashed target lines start on the first target day

Owner report 2026-11-19: the Nutrition trend charts show no dashed target lines, calories or macros, although targets are set.
Phone only. No wire, watch, storage or schema change.

## Cause

`computeNutritionAdherence` read the target on the EARLIEST logged day. When that day was older than the first saved target (a target set up after the first foods were logged, e.g. after a reinstall), the whole line was dropped, even for the later days that have a target.

## Goal and acceptance

The target line starts on the first day that has a saved target and runs from there; the charts draw nothing before it. No target up to the latest logged day: still no line.

Acceptance: S-26301..S-26306 green, S-26301, S-26304, S-26305, S-26306 red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26301 | When the earliest logged day has no target, binary-search the calendar days up to the latest logged day for the first one that has a target (a day with a target is always followed by days with one); the step list starts there. No target on the latest logged day: empty line as before. Binary search because a lookup on a day with no ancestor walks to 1970. | `stats_progress_service.dart` `computeNutritionAdherence` |
| D-26302 | The Calories and Macros target series skip logged days before the first step instead of padding back with the first target. | `nutrition_trend_card.dart` |
| D-26303 | The Daily Nutrition ring is unchanged: a day before the first saved target has no target (no back-fill). | owner 2026-11-19 |

## Scenarios

S-26301 food older than the first target: the line starts on the target day. S-26302 a target before the first logged day anchors on it (control). S-26303 a target saved only after the latest logged day: no line (control). S-26304 40 days of food, target 13 days ago: found. S-26305/S-26306 the calories and macro series start at the target day's index.

## Input-reality checklist

1. Writers: none. 2. Lifecycle: a new target later adds a step as before. 3. Settings: none. 4. Time: calendar-day arithmetic, no 24 h steps. 5. Cost: log2(days) lookups. 6. Words: none. 7. Competition: none.

## Docs delta

`docs/nutrition.md`: the target line starts on the first target day; the ring has no back-fill.

## Open items

1. (owner) Targets saved by builds before plan 235 (2026-11-18) are stored under the old day key and are invisible now (no migration, plan 235 D-7). A one-time repair is possible if the old entries are still on the device.
