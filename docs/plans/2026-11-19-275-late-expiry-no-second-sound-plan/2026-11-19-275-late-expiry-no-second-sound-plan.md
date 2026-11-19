# Plan 275 — late-expiry-no-second-sound

Review item 40, second half (owner 2026-11-19.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

 agreed)

Acceptance:  an interval, hold or round that ended while the phone was locked plays its scheduled notification, and noticing it late does not play the in-app alert again green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27501 | The in-app expiry alert is skipped when the expiry is noticed more than 3 seconds after the target; on-time expiries still play it. The rest-from-real-end part was plan 241. | owner decision above |

## Docs delta

S-27301 (started 60 s behind: finished, no alert) and S-27302 (on time: one alert):`_noticedOnTime` and a `playAlert` flag on `_handleEffortTimerExpired` in the timer mixin:`docs/theme_and_settings.md`.

## Open items

None.
