# Review: 2026-11-03-101-streak-accuracy-plan · P1, P2a, P2b, P3 · 27172ae5..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: touched files 19/19 passed (run this session: `test/calendar_streak_state_test.dart` + `test/calendar_streak_screen_test.dart` → `+19: All tests passed!`); full suite `+6174 ~2 -1` per the governor (the one failure red at the base)
Diff vs Predicted Files: conforms (plus `lib/core/services/stats_progress_service.dart` and `test/stats_dst_day_arithmetic_test.dart`, the brief's unrelated dirty files, ignored)

## Answers to the five questions

**1. Production behaviour outside the plan — none.** The three lib diffs are exactly the plan's "Exact
production code (P1)": the injected `_now` (constructor, `init`, `isHistoricalMonth`, `isActiveStreak`,
`_computeStreak`; `createPlannedSession`/`completePlannedSession` keep `DateTime.now()` — verified in the
file), `_streakIsLive` reset at the top of `_computeStreak` and set only after an anchor was found, the
`liveStreakDays` getter, the calendar-day `apart` comparison in `_longestRunInMonth`, the strip condition
`completedSessions == 0 && !isActiveStreak`, and R&T's `clock` parameter reading `liveStreakDays`. No other
hunk in `lib/`.

**2. Staleness walk — no sequence leaves `_streakIsLive` true for a month it was not computed for.**
Current month: compute anchors today/yesterday, sets live only in that branch. Past month (`goToPreviousMonth`)
and future month (`goToNextMonth`): `isCurrentMonth` false → historical branch, live stays false. Back to the
current month: `_loadMonth` → `_computeStreak` recomputes from scratch. `catch` branch: live was reset to
false at the top, stays false. The only path where the new month's compute never runs is `_loadMonth`'s own
`catch` (e.g. `_loadPeriods` throws before `Future.wait` completes) — there `_streakIsLive` keeps the previous
month's value, but `isActiveStreak` also requires `_year/_month == now` at read time, so a stale true is
invisible unless the user re-enters the current month after a failed load, where the retained value is from
the last successful compute of that same month. No user-visible wrongness found.

**3. Wrong-reason audit of the two test files — one weak assertion (Minor 2 below), otherwise sound.**
S-17401 passes under the old code too, as the plan declares (guard, not a killer). S-17402's three clocks and
the twin are exactly the plan's fixtures; the walk breaks at streak 1 under M2 because the 23 h day makes
`subtract(Duration(days: 1))` land at 01:00 local, which is not the seeded midnight key. S-17406 kills M5 via
`find.text('2d')` (under the old condition the slot read `—`), not via the dash assertion, which is the weak
one. S-17407a/b and S-17408a/b each fail under M3/M4/M7 on the label or the `0 d`/`2 d` texts. The
clock-change loops ran for real in this zone (2026-03-08 and 2026-11-01, both found as non-24 h days); the
zone guard test exists and skips with a message in a no-DST zone. S-17408 scopes texts to the first
`OmniSurface`, which is the aggregate card (`_buildContent` puts `_buildAggregateCard` first; the Streak pill
is the only `… d` text there — the Sessions pill renders a bare count).

**4. Docs — all sentences true, all cited names exist (checked against the files this run).**
`calendar_periods.md`: "local start-of-day timestamps" is true (`OmniDateUtils.startOfDayMs` is local
midnight, `lib/core/utils/date_utils.dart:8`); "walks backwards one calendar day at a time" and the step-5
error/anchor wording match `_computeStreak`; the cited group names `S-17401 two sessions on one day count as
one day`, `S-17402 the streak across a clock change`, `S-17403 to S-17405 a live streak, a lapsed one, none`,
`S-17406 a live streak before the first session of the month`, `S-17406 and S-17407 the Calendar strip` all
exist verbatim. `records_and_trends.md`: group `S-17408 the Records and Trends Streak figure` and both test
names exist verbatim; the sentence matches `liveStreakDays` + `'$_streakDays d'`. `app_state.md`: the `now`
clock row matches the code; the `streakDays`/`liveStreakDays` rows match the getters. `README.md:69`: the
Mix, Signals, Instruments and Fuel blocks all exist in `lib/features/stats/stats_screen.dart`. One imprecision
→ Minor 1.

**5. Unlisted user-visible changes — none.** The only rendered-string change is the streak slot's value
condition (in the plan, goals 1–2). Records & Trends: label `Streak`, value `'$_streakDays d'`, flame icon
rule and everything else in the screen are untouched by the diff; the lapsed default reads `0 d`
(`liveStreakDays` → 0), as the plan's default states.

## Findings

1. [Minor] `docs/calendar_periods.md:31` — the label sentence dropped the current-month half of
   `isActiveStreak` (`lib/state/calendar/calendar_state.dart:334`): it now reads "reads STREAK when the
   streak is live (a session today or yesterday)" where the old text said "when the displayed month is the
   current month with a live streak". A reader could conclude a past month shows STREAK while a live streak
   exists; it shows BEST RUN (the past month's compute clears `_streakIsLive`). Fix: restore the qualifier,
   e.g. "when the displayed month is the current month and the streak is live (a session today or
   yesterday)". Guard: none needed (doc-only).
2. [Minor] `test/calendar_streak_screen_test.dart:91` — S-17406's "the SESSIONS figure is `—`" is asserted as
   `find.text('—'), findsWidgets`, which matches the TIME slot's dash alone; the SESSIONS slot could show any
   value and the assertion would still pass. The scenario is still guarded (M5 dies on `find.text('2d')`).
   Fix: `findsNWidgets(2)` (SESSIONS and TIME both read the dash in this fixture) or scope the finder to the
   SESSIONS `_CompactStat`. Guard: the same test.

## Assumption Log rulings

- Baseline analyze 181 / 0 errors — ratify (governor-measured; not re-run).
- Correction: the Calendar did not flip to BEST RUN for a lapsed streak in the current month — ratify; the
  old code I read (`isActiveStreak` = current month && `_streakDays > 0`, strip value gated only on
  `completedSessions == 0`) matches it.
- Old DST step already fixed in 36c1fe50 without a streak test — ratify as stated (history not checked; the
  current code carries the calendar-arithmetic step and this unit adds the test).
- R&T keeps the label Streak and reads `0 d` when lapsed — ratify; matches the code and S-17408b.

## Docs delta

- docs/calendar_periods.md MODIFIED (STREAK when live, otherwise BEST RUN) -> applied (see Minor 1)
- docs/calendar_periods.md ADDED (live streak before the month's first session) -> applied
- docs/calendar_periods.md MODIFIED (local start-of-day timestamps) -> applied
- docs/calendar_periods.md MODIFIED (walks one calendar day, never 24 h) -> applied
- docs/state_management/app_state.md MODIFIED (streakDays = live streak, else month's longest run) -> applied
- docs/state_management/app_state.md ADDED (liveStreakDays, 0 once lapsed) -> applied
- docs/state_management/app_state.md ADDED (optional `now` clock) -> applied
- docs/records_and_trends.md ADDED (Streak figure is the live streak, 0 d when lapsed) -> applied
- docs/README.md MODIFIED (Mix/Signals/Instruments/Fuel blocks) -> applied
- Doc edits the table does not name: none (the docs diff contains only these hunks).

## Scenario coverage

S-17401 -> test/calendar_streak_state_test.dart · 'a streak over three sessions on two days is 2'
S-17402 -> test/calendar_streak_state_test.dart · group 'S-17402 the streak across a clock change' (3 tests × 2026-03-08 and 2026-11-01, plus the zone guard)
S-17403 -> test/calendar_streak_state_test.dart · 'S-17403 a session yesterday and the day before is a live streak'
S-17404 -> test/calendar_streak_state_test.dart · 'S-17404 none today or yesterday: the best run is not a streak'
S-17405 -> test/calendar_streak_state_test.dart · 'S-17405 no sessions at all'
S-17406 -> test/calendar_streak_state_test.dart · 'trained the last two days of May, now the morning of June 1' + test/calendar_streak_screen_test.dart · 'S-17406 a live streak shows before the month first session'
S-17407 -> test/calendar_streak_screen_test.dart · 'S-17407 a lapsed streak reads BEST RUN' + 'S-17407 a live streak reads STREAK'
S-17408 -> test/calendar_streak_screen_test.dart · 'S-17408 a live streak reads 2 d' + 'S-17408 a lapsed streak reads 0 d, not the month best run'
S-17409 -> test/calendar_streak_state_test.dart · group 'S-17409 the best run of a past month across a clock change' (2026-03-08 and 2026-11-01)
S-17410 -> existing `calendar_state_month_init_test.dart`, `state_test.dart`, `edge_case_test.dart` untouched; green in the governor's full-suite run (not re-read this run)
