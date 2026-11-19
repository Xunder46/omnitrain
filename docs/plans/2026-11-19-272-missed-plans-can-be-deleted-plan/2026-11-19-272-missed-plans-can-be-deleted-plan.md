# Plan 272 — missed-plans-can-be-deleted

Review item 9 (owner decision 2026-11-19.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

 agreed — keep missed plans visible, allow Delete only; no move, no mark done)

Acceptance: A planned session on a past day shows its bin; Delete asks first (Cancel keeps it) and removes it. The play button, the edit tap and any move stay off for past days. green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27201 | S-27201 (bin asks, Cancel keeps, Delete removes) and S-24804 (yesterday | owner decision above |

## Docs delta

 only the bin; tap does nothing):`day_session_list_screen.dart` `onDelete` no longer gated on today-or-future:`docs/calendar_periods.md`.

## Open items

None.
