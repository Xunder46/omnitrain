# Plan 274 — home-rollover-at-midnight

Review item 13, second half (owner 2026-11-19.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

 yes if not an overhead)

Acceptance:  the app left open on Home while midnight passes shows the new day green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27401 | Home sleeps one timer until just after the next local midnight (it does not poll), then asks `NutritionState.rolloverIfDayChanged` and sets the next timer; a resume also re-sets it. Cancelled on dispose. | owner decision above |

## Docs delta

S-27204 (open Home at 21:00, an hour later nothing changes, after midnight the strip reads 0 / target):`NutritionState.untilNextDay()`; `_HomeScreenState._scheduleMidnightRollover`:`docs/navigation_and_screens.md`.

## Open items

None.
