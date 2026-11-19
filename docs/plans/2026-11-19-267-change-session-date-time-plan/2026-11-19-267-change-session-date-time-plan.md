# Plan 267 — Change a finished workout's date and start time

Review item 37, first half (owner list: "Edit finished session: no date or start-time change; added or removed sets are written before Save. Suggested: let the date and start time be edited, and hold added or removed sets until Save like the other edits.").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

The workout summary's overflow menu gets `Change date & time`. It opens a date picker (earliest 2020, latest today), then a time picker opening on the current start time. Confirming moves the workout's start to the chosen date and time; a finished workout keeps its length (its end moves by the same amount); the summary shows the new date, with a `Date and time changed` message. A start in the future is refused (`That time is in the future.`), and a failed write says `Could not change the date. Try again.`. Cancelling either picker, or confirming the same time, changes nothing.

Acceptance: S-26701..S-26703 green, S-26703 red without the screen change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26701 | `WorkoutState.updateSessionStart(ms)` (in `SessionCore`): refuses a future start, keeps the length of a finished session, writes through `updateSession`, updates the held current session. | `session_core_lifecycle.dart` |
| D-26702 | Only the session's own `startedAtMs`/`endedAtMs` move; moments recorded inside it (set times, rests) keep their original times. Everything that groups by day reads the session start. | owner list wording; stats read `startedAtMs` |
| D-26703 | NOT built: holding added or removed sets until Save. Edit Session already holds metric edits until Save and undoes added/removed sets when you leave without saving (snapshot restore, with a discard confirmation); moving those writes behind a Save buffer is a rewrite of that tested path for a difference only visible if the app is killed mid-edit. Reported to the owner. | `session_edit_snapshot.dart` |

## Scenarios

S-26701 the start moves, a 40-minute finished session stays 40 minutes. S-26702 a start tomorrow is refused, nothing changes. S-26703 menu -> pick another day -> confirm the time: the stored start is that day at the same time and the message shows.

## Input-reality checklist

1. Writers: `updateSession` only. 2. Lifecycle: a planned-session link and calendar day follow the new start the next time the calendar loads. 3. Settings: the time picker follows the phone's 12/24-hour setting. 4. Time: local calendar date and clock time, minute precision (seconds drop to zero). 5. Cost: none. 6. Words: `Change date & time`, `Date and time changed`, `That time is in the future.`, `Could not change the date. Try again.` (owner to read). 7. Competition: a wrist set arriving for this session keeps its own time.

## Docs delta

`docs/session_summary.md`: a `Change date and time` section.

## Open items

1. (owner) D-26703: held structural edits not built; say if you still want them.
2. (owner) A workout moved onto a day that has a planned session for the same routine is not auto-linked.
