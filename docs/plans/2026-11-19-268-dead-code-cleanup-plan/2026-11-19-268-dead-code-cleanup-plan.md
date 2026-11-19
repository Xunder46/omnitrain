# Plan 268 — Remove three pieces of dead UI

Review item 39 (owner list: "Cleanup, not user-visible: unused Session Overview screen, a never-shown 'In progress' section, a rest label the routine editor cannot set. Suggested: delete all three, or add a rest setting to the editor if planned rest is wanted."). Default taken: delete all three (rest is a count-up, `docs/global_conventions.md`: no preset rest length).
Phone only. No behaviour change anyone can see. No wire, watch, storage or schema change.

## Goal and acceptance

- `lib/features/session/session_overview_screen.dart` and the tests that exist only for it are gone; no other file imports it; docs stop naming it as a live screen.
- The Day Session list no longer builds an `IN PROGRESS` section or the `In Progress` row subtitle: the calendar only lists finished sessions (`CalendarState` keeps `endedAtMs != null`), so neither can appear.
- The routine editor no longer shows a `Rest ...` line under an exercise (`_formatRestLabel` is removed). Stored rest values are not touched.

Acceptance: `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set (`.work/windows-base-failing-tests.txt`); `grep -rn SessionOverviewScreen lib` returns nothing; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26801 | Delete the Session Overview screen (nothing in `lib/` pushes it). Tests that only drive it are deleted; tests that merely mention it lose that part. | grep of `lib/` |
| D-26802 | Remove the `IN PROGRESS` section, its list and the `In Progress` subtitle branch from `day_session_list_screen.dart`. | `calendar_state.dart` loads completed sessions only |
| D-26803 | Remove `_formatRestLabel` and the line that shows it from `routine_setup_screen.dart`. | the editor has no rest control; rest is a count-up |

## Scenarios

S-26801 `grep -rn "SessionOverviewScreen\|session_overview_screen" lib test` returns nothing. S-26802 the Day Session list still shows COMPLETED and PLANNED sections unchanged (existing tests stay green). S-26803 the routine editor still shows an exercise's name and sets without a `Rest` line (existing routine tests stay green).

## Docs delta

`docs/navigation_and_screens.md`, `docs/modality_tracking.md`: drop the Session Overview screen from the live screen lists (history files under `docs/history/` and `docs/plans/` stay as written).

## Open items

None.
