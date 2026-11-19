# 101 — The training streak says what is true on the Calendar and on Records & Trends

Status: SEEDED by the lead 2026-11-03 (no architect run: the seed carries exact production code; exact test text sits in the
builder briefs). Base commit: `.work/2026-11-03-101-streak-accuracy/base.txt` (27172ae5).
Track: phone only (`lib/`, `test/`, `docs/`). Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`,
`test/stats_dst_day_arithmetic_test.dart` (another session's DST work).
Owner request 2026-11-03: the Calendar showed a streak of 1 on 2026-11-02 when two sessions the day before and one the day
before that made 2. Owner said "proceed" (commits pre-approved, take defaults, report at the end).

## Goal and acceptance

What a user sees after this PR:

1. **A lapsed streak is not called a streak on the Calendar.** With no session today or yesterday, the strip's slot reads
   `BEST RUN` (the displayed month's longest run) in the current month too. Before, only past months did: in the current month
   the best-run figure carried the label `STREAK`.
2. **A live streak shows from the first day of a month.** Trained Oct 30 and 31, now Nov 1 before any session: the slot reads
   `STREAK 2d`. Before it read `—` because the month had no session yet.
3. **Records & Trends shows the live streak only.** Its Streak figure reads `0 d` when neither today nor yesterday has a
   session. Before it showed the month's best run under the label Streak. (Default: `0 d`, not "Best run": this screen is the
   all-time one, and a month's best run would read like a lifetime record.)
4. **The streak survives a clock change.** The day after the clocks change no day is skipped, in the live streak and in the best
   run of a past month (a spring-forward day is 23 h long; the best-run walk dropped it).
5. Two sessions on one day count as one day (already true; now guarded).

Not in this PR: the 90-day lookback (a streak over about 91 days reads 91); the streak on Home (owner decided against it);
the other Calendar strip figures.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17401 | `CalendarState` takes an optional clock: `CalendarState(repo, {DateTime Function()? now})`, default `DateTime.now`. Used by the constructor, `init`, `isHistoricalMonth`, `isActiveStreak`, `_computeStreak`. The two `DateTime.now()` that stamp a created or updated row stay | `calendar_state.dart:60,96,321,328,341` |
| D-17402 | `_computeStreak` records whether an anchor (today or yesterday) was found: `bool _streakIsLive`, reset to false at each compute. `isActiveStreak` is `_streakIsLive` and the displayed month is the current month. `streakDays` is unchanged (live streak, else the month's longest run) | `calendar_state.dart` `_computeStreak`, `isActiveStreak` |
| D-17403 | New getter `liveStreakDays` = `isActiveStreak ? _streakDays : 0` | `calendar_state.dart` |
| D-17404 | `_longestRunInMonth` compares calendar days (`DateTime.utc(y, m, d)` difference), not `Duration.inDays` of local midnights (23 h on a spring-forward day rounds to 0) | `calendar_state.dart:414` |
| D-17405 | The strip shows `—` only when the month has no completed session AND the streak is not live: `completedSessions == 0 && !isActiveStreak` | `calendar_screen.dart:710` |
| D-17406 | `RecordsAndTrendsScreen` gets an optional `clock` (`DateTime Function()?`), passed to its `CalendarState`, and reads `liveStreakDays` | `records_and_trends_screen.dart:31,78,80` |
| D-17407 | Tests never depend on today's date: fixed 2026 dates with injected clock; DST cases find the day whose length is not 24 h by scanning 2026 (the pattern of `test/nutrition_target_dst_walk_test.dart`) and skip in a zone without DST | tests |
| D-17408 | Proof: `prove-red` at the base fails by compile (no `now` parameter), which proves nothing about behaviour; the lead's mutation pass M1-M7 is the proof | Assumption Log |
| D-17409 | The README's Stats Screen row still describes the ALL TIME card that plan 100 removed; fixed here because the stale-term sweep for "streak" finds it | `docs/README.md:69` |

## Exact production code (P1)

`lib/state/calendar/calendar_state.dart`:

```dart
  CalendarState(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    final today = _now();
    _year = today.year;
    _month = today.month;
  }

  /// The clock. Injected so a test can stand on any date (the day after a
  /// clock change, the first of a month); production reads the device clock.
  final DateTime Function() _now;
```

`init()`, `isHistoricalMonth`, `isActiveStreak` and `_computeStreak` use `final now = _now();` instead of `DateTime.now()`.
`createPlannedSession` and `completePlannedSession` keep `DateTime.now()` (they stamp rows).

```dart
  int _streakDays = 0;
  int get streakDays => _streakDays;

  /// True when the last compute found a session today or yesterday (a live streak).
  bool _streakIsLive = false;
```

```dart
  /// True when [streakDays] is a live streak: the displayed month is the current
  /// month and the last compute anchored on today or yesterday. With no live
  /// streak [streakDays] holds the month's longest run, which is not a streak.
  bool get isActiveStreak {
    final now = _now();
    return _streakIsLive && _year == now.year && _month == now.month;
  }

  /// The live streak, or 0 once it has lapsed. [streakDays] alone cannot tell
  /// the two apart.
  int get liveStreakDays => isActiveStreak ? _streakDays : 0;
```

In `_computeStreak`: first line inside the method `_streakIsLive = false;` (before the `try`); after `_streakDays = streak;` in the
current-month branch add `_streakIsLive = true;`; the `catch` also leaves it false (it is reset at the top).

In `_longestRunInMonth` replace `if (curr.difference(prev).inDays == 1) {` with:

```dart
      // Calendar days apart, not 24 h blocks: the day after a spring-forward
      // change is 23 h later, which Duration.inDays rounds down to 0.
      final apart = DateTime.utc(curr.year, curr.month, curr.day)
          .difference(DateTime.utc(prev.year, prev.month, prev.day))
          .inDays;
      if (apart == 1) {
```

`lib/features/calendar/calendar_screen.dart`, in `_MonthlyStatsStrip`, the streak `_CompactStat` value:

```dart
                    value: completedSessions == 0 && !isActiveStreak
                        ? '—'
                        : (streakDays >= 3
                              ? '🔥 ${streakDays}d'
                              : (streakDays == 0 ? '0' : '${streakDays}d')),
```

`lib/features/stats/records_and_trends_screen.dart`:

```dart
  final WorkoutState workoutState;
  final SettingsState settingsState;

  /// The clock the streak is read against; null reads the device clock. A test
  /// passes a fixed one.
  final DateTime Function()? clock;

  const RecordsAndTrendsScreen({
    super.key,
    required this.workoutState,
    required this.settingsState,
    this.clock,
  });
```

and in `_loadData`:

```dart
      // Reuse CalendarState streak logic — the calendar keeps owning that
      // rule; this screen only displays it. Only a live streak counts: with
      // none, CalendarState holds the month's best run, which is not a streak.
      final calendarState = CalendarState(
        widget.workoutState.repository,
        now: widget.clock,
      );
      await calendarState.init();
      final streak = calendarState.liveStreakDays;
```

## Scenarios

Fixed dates in 2026 with an injected clock; sessions at noon; Mock repository. `Fails without the change` is proven by the
lead's mutations (D-17408).

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17401 | Sessions Jun 1 12:00, Jun 2 09:00 and Jun 2 18:00; clock Jun 3 09:00 | `streakDays` 2, `liveStreakDays` 2, `isActiveStreak` true, `completedSessionCount` 3: two sessions on one day are one day | twin: no simple mutation separates it; it records the owner's two-sessions question as a guard |
| S-17402 | For each day D of 2026 whose length is not 24 h: sessions at noon on D-1, D, D+1, D+2; clocks D+2 18:00 (today has a session), D+3 09:00 (yesterday does); twin: sessions D-1, D only, clock D+1 09:00 | `streakDays` 4, 4 and 2, all live | a 24 h step from the day after the change lands an hour off midnight and finds no session (mutations M1, M2) |
| S-17403 | Clock Jun 5 09:00, sessions Jun 3 and Jun 4 | live: `isActiveStreak` true, `liveStreakDays` 2 | twin of S-17404 |
| S-17404 | Clock Jun 5 09:00, sessions Jun 1 and Jun 2 (none today or yesterday) | `streakDays` 2 (best run), `isActiveStreak` false, `liveStreakDays` 0 | `isActiveStreak` was `_streakDays > 0`, so the best run read as live (mutation M3) |
| S-17405 | Clock Jun 5 09:00, no sessions | `streakDays` 0, `isActiveStreak` false, `liveStreakDays` 0 | twin: guards a streak invented from no history (no mutation expected to differ) |
| S-17406 | Calendar screen, clock Jun 1 09:00, sessions May 30 and May 31 | the strip shows label `STREAK` and `2d`; the SESSIONS figure is `—` | the slot read `—` while the month had no session (mutation M5) |
| S-17407 | Calendar screen, clock Jun 5 09:00; (a) sessions Jun 1, 2; (b) sessions Jun 4, 5 | (a) label `BEST RUN` and `2d`, no `STREAK`; (b) label `STREAK` and `2d` | the lapsed figure carried `STREAK` (mutation M3) |
| S-17408 | Records & Trends with `clock` fixed to Jun 5 09:00; (a) sessions Jun 3, 4; (b) sessions Jun 1, 2 | the Streak pill reads `2 d` in (a) and `0 d` in (b) | (b) read `2 d` (mutations M4, M7) |
| S-17409 | For each day D of 2026 that is 23 h long (spring forward): sessions at noon on D, D+1, D+2; clock the 5th of the next month, then `goToPreviousMonth()` | `streakDays` 3, `isActiveStreak` false | the best-run walk broke the run at the 23 h day (mutation M6) |
| S-17410 | The existing `calendar_state_month_init_test.dart`, `state_test.dart` streak test and `edge_case_test.dart` streak test | stay green untouched | guards the default clock |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/state/calendar/calendar_state.dart`, `lib/features/calendar/calendar_screen.dart`, `lib/features/stats/records_and_trends_screen.dart` | the six edits above | first |
| P2a | crew-builder-app | new `test/calendar_streak_state_test.dart` | S-17401 to S-17405, S-17409 (exact text in the brief) | after P1; parallel with P2b |
| P2b | crew-builder-app | new `test/calendar_streak_screen_test.dart` | S-17406, S-17407, S-17408; helpers copied from `calendar_layout_responsive_test.dart` and `records_and_trends_screen_test.dart` | after P1; parallel |
| P3 | crew-docs-keeper | `docs/calendar_periods.md`, `docs/state_management/app_state.md`, `docs/records_and_trends.md`, `docs/README.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts (Mock only; no Hive harness is involved); `flutter analyze` issue
count not above 181 (0 errors); full `flutter test` green apart from the known reds (5 in `instrument_list_service_test.dart` and
`routine_save_removes_deleted_rows_test.dart`, and `records_and_trends_screen_test.dart` S-915, all red at the base); invariant grep
clean; `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations M1
`yesterday` back to `today.subtract(Duration(days: 1))`; M2 the walk step back to `day.subtract(Duration(days: 1))`; M3
`isActiveStreak` back to `_year == now.year && _month == now.month && _streakDays > 0`; M4 `liveStreakDays` returns `_streakDays`;
M5 the strip condition back to `completedSessions == 0`; M6 `apart` back to `curr.difference(prev).inDays`; M7 R&T reads
`streakDays`.

## Docs delta

Markers are exact one-line phrases. `-` = none. Docs not listed are checked by the keeper's search for `streak`, `BEST RUN`,
`STREAK` outside `docs/plans`, `docs/history`, `docs/releases`.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/calendar_periods.md | MODIFIED | when the displayed month is the current month with a live streak, otherwise BEST RUN (the longest | the streak is live (a session today or yesterday), otherwise BEST RUN | S-17404 |
| docs/calendar_periods.md | ADDED | - | A live streak shows even before the month's first session. | S-17406 |
| docs/calendar_periods.md | MODIFIED | 2. Builds a `Set<int>` of UTC-midnight timestamps for days that have a completed session. | 2. Builds a `Set<int>` of local start-of-day timestamps, so two sessions on one day count once. | S-17401 |
| docs/calendar_periods.md | MODIFIED | 4. Walks backwards day-by-day counting consecutive days present in the set. | 4. Walks backwards one calendar day at a time, never 24 h, so a clock change cannot hide a day. | S-17402 |
| docs/state_management/app_state.md | MODIFIED | Current consecutive-day streak (computed independently of displayed month) | The live streak, else the displayed month's longest run | S-17404 |
| docs/state_management/app_state.md | ADDED | - | The live streak, or 0 once it has lapsed | S-17405 |
| docs/state_management/app_state.md | ADDED | - | `CalendarState` takes an optional `now` clock | D-17401 |
| docs/records_and_trends.md | ADDED | - | The Streak figure is the live streak and reads 0 d once it has lapsed. | S-17408 |
| docs/README.md | MODIFIED | The all-time aggregate card (Sessions / Time / Streak), the Instruments list | The Mix, Signals, Instruments and Fuel blocks: the Instruments list | D-17409 |

## Progress

- [x] P1 production
- [x] P2a state tests (14 tests, 2 clock-change days in this zone)
- [x] P2b screen tests (5 tests)
- [x] Lead mutation pass M1-M7 (all 7 killed)
- [x] P3 docs
- [x] `plan-lint after` (clean, 9 of 9 rows)
- [x] P4 review (APPROVE, 0 blocker, 0 major, 2 minor, both fixed by the lead)
- [x] Full suite, analyze, invariants
- [x] Commit (own files only)

## Assumption Log

- Baseline `flutter analyze`: 181 issues, 0 errors (plan 100's final count; re-measured before P1 by the lead).
- Correction of the lead's earlier statement to the owner: the Calendar did NOT flip to `BEST RUN` for a lapsed streak in the
  current month (only for past months). Found by reading `isActiveStreak` when planning this unit; fixed here (goal 1).
- The old DST step in `_computeStreak` was already fixed in 36c1fe50 without a streak test; this unit adds the test.
- Verification (observed): full suite `+6174 ~2 -1` (the one red, `routine_save_removes_deleted_rows_test.dart` S-R3, is red at the
  base too); the four `instrument_list_service_test.dart` reds and `records_and_trends_screen_test.dart` S-915 that were red at 27172ae5
  were green in this tree, which carries the other session's uncommitted `stats_progress_service.dart`: not this unit's doing, not
  claimed as fixed. `flutter analyze` 181 issues (baseline). Invariant grep clean. `ui_standards_contract_test.dart` and
  `docs_indexing_contract_test.dart` green. Mutations M1-M7 all killed (M1 and M2 by S-17402, M3 by S-17404 and S-17407, M4 by S-17404 and
  S-17408, M5 by S-17406, M6 by S-17409, M7 by S-17408). No `prove-red` run: at the base the new tests fail to compile (D-17408).
- Review minors fixed by the lead: the calendar doc sentence regained "in the current month"; the S-17406 dash check is pinned to the
  SESSIONS slot.
- Not fixed, by decision: the 90-day lookback and the doc sentence "caps the displayed streak at 90" (it is 91 days counting today).
- Records & Trends keeps the label Streak and shows `0 d` when lapsed (default; the owner's earlier "or Best run" wording would
  show a month's best run on an all-time screen).
