# Plan 239 — The summary's rest-day count stops at today

Series: nutrition/calendar/summary pre-launch review (2026-11-16), item "rest days count future days". Phone only (`lib/features/session/session_summary_screen.dart`, `lib/core/utils/date_utils.dart`). The production fix is small and exact (lead applies it), one builder run writes the tests, then docs. Status: COMMITTED (built, mutation-checked (4 of 4 killed), docs applied; full suite +7965 ~4 green.

## Goal and acceptance

The calendar card on the session summary prints "N workout days / M rest days" for the month it shows. `M` is computed as the month's length minus the workout days (`session_summary_screen.dart:1371`), so on 18 November with one workout it says "1 workout days / 29 rest days": 12 of those "rest days" have not happened yet. After this change a day counts as a rest day only once it has started: for the current month the count runs up to and including today, for a past month (a workout opened from the calendar) it covers every day of that month.

Behaviour call (stated, not asked): a day that has not started cannot be a rest day, and today counts (it may still end with a workout; the card already counts today's workout in `N`). Nothing else on the card changes.

Acceptance: S-23901..S-23903 green, S-23901 and S-23902 red at the base commit or killed by the lead's mutation; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- After finishing a workout on 18 November the card says "1 workout days / 17 rest days" (18 days elapsed, 1 with a workout), not "29 rest days". The number grows by one each new day without a workout.
- Opening a workout from a past month shows that whole month's rest days, as today.
- To SEE it: finish a workout today and read the line under the month grid on the summary.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `OmniDateUtils.daysElapsedInMonth(DateTime month, DateTime today)`: compares `year * 12 + month` of the two; a past month returns its full length (`DateTime(month.year, month.month + 1, 0).day`), the same month returns `today.day`, a later month returns 0. | `date_utils.dart` |
| D-2 | `_buildCalendarCard`: `final elapsed = OmniDateUtils.daysElapsedInMonth(_viewMonth, DateTime.now()); final restDays = (elapsed - workoutDays).clamp(0, elapsed);`. `_daysInMonth` stays for its other users. | `session_summary_screen.dart:1369-1371` |
| D-3 | Wording, the workout-day set and the grid are unchanged ("1 workout days" keeps its grammar: out of scope). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23901 | Pure test of `daysElapsedInMonth`: (Oct 2026, today 18 Nov 2026) = 31; (Nov 2026, today 18 Nov 2026) = 18; (Nov 2026, today 1 Nov 2026) = 1; (Feb 2028, today 5 Mar 2028) = 29; (Dec 2026, today 5 Jan 2027) = 31; (Jan 2027, today 31 Dec 2026) = 0. | the listed values. | the helper does not exist |
| S-23902 | Screen test, Mock (the harness of `test/summary_note_survives_quick_done_test.dart`): a rolling session started today, shown as the post-workout summary. Read `DateTime.now()` after pumping for the expected text. | the card text is `1 workout days / ${now.day - 1} rest days`. | the base shows `${daysInMonth - 1}` |
| S-23903 | Screen test, Mock: a finished session started on the 10th of the PREVIOUS month, opened with `openedFromCalendar: true` after `viewHistoricalSession`. | the card text is `1 workout days / ${daysInThatMonth - 1} rest days`. | passes both ways on purpose (mutation: a past month counted up to today's day number) |

## Input-reality checklist

1. Writers and units: no stored data; the count is derived at paint time from the session rows of the shown month; units are days.
2. Lifecycle: computed on every build of the card; `DateTime.now()` at paint, so a summary left open across midnight shows the new day on its next rebuild.
3. Settings changing while open: none.
4. Time: month boundaries and years (S-23901 covers December/January and a leap February). A time-zone change moves `DateTime.now()` with the phone, which is the intended "today".
5. Cost: none.
6. Words: none changed.
7. Slot competition: none.

## Phases

1. **P1 lead**: the two production edits (exact text above).
2. **P2 builder-app**, scope `test/summary_rest_days_elapsed_test.dart` (new): S-23901..S-23903, copying the harness of `test/summary_note_survives_quick_done_test.dart`.
3. **P3 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "rest days\|_daysInMonth" test lib` and every `session_summary_*_test.dart`, `test/screen_widget_test.dart` (summary groups): reported if red, not edited.

## Mutation list (lead)

(a) `daysElapsedInMonth` returns the full month length for the same month (S-23901, S-23902); (b) returns `today.day` for a past month (S-23901, S-23903); (c) the card keeps `_daysInMonth` (S-23902).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/calendar_periods.md` | ADDED | - | Rest days are counted only for days that have started | S-23902, S-23903 |

Stale-term sweep: `grep -rIn "rest days" docs` outside plans/history/releases: `docs/calendar_periods.md:96` (the card), `docs/stats_screen.md:459` (Fuel's training/rest split, unrelated and unchanged).

## Open items

1. (owner) Finish a workout and read the line under the month grid: rest days stop at today.

## Predicted files

`date_utils.dart` (+14), `session_summary_screen.dart` (+3 -1), one new test file (~150), one doc.

## Progress

- [x] Seeded
- [x] Production edit (lead)
- [x] P2 tests
- [x] Docs, mutation pass
- [x] Full suite (+7965 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-239/base.txt` (76c02ccc); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-239xx: none found.

## Feedback

(none yet)
