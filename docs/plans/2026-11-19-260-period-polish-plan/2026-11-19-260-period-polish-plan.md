# Plan 260 — Periods: name on the calendar, one name, dates like the rest of the app

Review item 32 (owner list: "Periods: name not shown on the calendar; 'Training periods' versus 'Periodization'; dates as dd/mm/yyyy").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

- The Calendar shows the name of the training period you are in today in a small line under the month title, while the month on screen overlaps that period. No period today, or a month the period does not reach: no line.
- The Training periods list screen is titled `Training periods`, the same as the Calendar's button (was `Periodization`).
- The period form's Start and End dates read `Nov 16` (`Nov 16, 2025` when not this year) instead of `16/11/2025`.

Acceptance: S-26001..S-26006 green, the "fails without" ones (S-26001, S-26004, S-26006) red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26001 | `_MonthHeader` takes `periodName`; the calendar passes the first period that covers today and overlaps the viewed month. | `calendar_screen.dart` `_currentPeriodName` |
| D-26002 | `PeriodListScreen` title is `Training periods` (the calendar button's name wins: plain words, and the docs already call them training periods). | `period_list_screen.dart` |
| D-26003 | `OmniDateUtils.formatDay(date, today)`: `Nov 16`, `Nov 16, 2025` off-year. The period form's date field uses it. | `date_utils.dart`, `create_period_screen.dart` |

## Scenarios

S-26001 period covers today: its name shows (fails without: no line). S-26002 only an old period: no line (control). S-26003 two months ahead: no line (control). S-26004 button tooltip and list title are both `Training periods`, no `Periodization` (fails without). S-26005 `formatDay`. S-26006 the form shows `Mar 8, 2020` / `Apr 5, 2020` and no dd/mm/yyyy (fails without).

## Input-reality checklist

1. Writers: none. 2. Lifecycle: a period edited or deleted refreshes the calendar as before. 3. Settings: none. 4. Time: "today" is read at build; the line follows a month change. 5. Cost: one pass over the loaded periods. 6. Words: `Training periods` title (owner to read). 7. Competition: none.

## Docs delta

`docs/calendar_periods.md` (name line, one name, date style); `docs/design_system.md` (`Periodization` -> `Training periods`).

## Open items

1. (owner) Defaults taken: the line shows the period covering today, only when the viewed month overlaps it (not "the period of the month you browse"); date form drops the year in the current year.
