# Plan 261 — Calendar: no spinner flash, swipe and Today, day read with its count

Review item 33 (owner list: "Calendar: spinner flash on each month change; no swipe or jump to today; screen reader hears only day numbers").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

- Changing month keeps the last loaded grid on screen while the next loads; the spinner shows only before the first load.
- Swiping the grid left shows the next month, right the previous one (ignored while a month is loading).
- A `Today` icon in the header (tooltip `Today`) shows only while another month is on screen and returns to the current month.
- A screen reader hears each day as its number, plus its session count when it has any: `16`, `16, 1 session`, `16, 2 sessions`.

Acceptance: S-26101..S-26104 green, all four red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26101 | The screen remembers the last loaded year/month (`_gridYear`, `_gridMonth`) and draws that grid while `isLoading`; the spinner only when none was ever loaded. | `calendar_screen.dart` |
| D-26102 | `GestureDetector.onHorizontalDragEnd` on the grid: velocity below -300 next, above 300 previous; ignored while loading. | same |
| D-26103 | `CalendarState.isViewingCurrentMonth` and `goToToday()`; the header icon is `Icons.today`, shown only away from the current month. | `calendar_state.dart`, header |
| D-26104 | `_DayCell` wraps in `Semantics(label: '<day>[, N session(s)]', button: tappable, excludeSemantics: true)`. Planned and completed entries both count. | `_DayCell` |

## Scenarios

S-26101 swipe left/right changes the month title. S-26102 Today button absent on this month, present after next month, returns. S-26103 a gated month load shows no spinner and the grid stays. S-26104 a day with two sessions is `1, 2 sessions`, one is `2, 1 session`.

## Input-reality checklist

1. Writers: none. 2. Lifecycle: refresh after returning from periods reloads as before. 3. Settings: week start unchanged. 4. Time: "current month" follows the state's clock. 5. Cost: none. 6. Words: `Today`, `N sessions` (owner to read). 7. Competition: a swipe during a load is ignored.

## Docs delta

`docs/calendar_periods.md`: one paragraph (no spinner flash, swipe, Today icon, spoken day label).

## Open items

1. (owner) Defaults taken: Today is a header icon shown only away from this month; a planned (not yet done) session counts in the spoken total; while a month loads the title already shows the new month over the old grid.
