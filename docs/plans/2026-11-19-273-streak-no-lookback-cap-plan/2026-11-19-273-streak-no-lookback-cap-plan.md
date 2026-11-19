# Plan 273 — streak-no-lookback-cap

Review item 31 (owner 2026-11-19.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

 remove the 90-day cap; the streak stays consecutive days, rest days break it — a streak is rest-less by definition)

Acceptance: The streak counts every consecutive day with a completed session back as far as they go; it used to stop looking after 90 days. green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27301 | S-27203 (130 consecutive days count as 130; 91 with the old cap) | owner decision above |

## Docs delta

`CalendarState._computeStreak` reads sessions from the start (no 90-day lower bound):`docs/calendar_periods.md`.

## Open items

None.
