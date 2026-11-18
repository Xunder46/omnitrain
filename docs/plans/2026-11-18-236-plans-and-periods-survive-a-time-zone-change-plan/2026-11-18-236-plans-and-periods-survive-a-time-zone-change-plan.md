# Plan 236 — Planned sessions and training periods stay on their calendar days when the time zone changes

Series: nutrition/calendar/summary pre-launch review (2026-11-16), item "days are keyed by the local-midnight instant ... shifts plans/periods by a day". Part 2 of 2 (plan 235 did food, water and targets, committed 5cfadb94). Phone only; the watch plan payload carries the phone's in-memory `scheduledDateMs` (local midnight), which does not change. One builder run, then docs. Status: COMMITTED (built, mutation-checked (5 of 5 killed), docs applied; full suite +7941 ~4 green.

## Goal and acceptance

A planned session stores `scheduledDateMs` (local midnight of its day) and a training period stores `startDateMs` (local midnight of its first day) and `endDateMs` (23:59:59.999 local of its last day), as raw instants. After a zone change those instants name a different wall-clock time: a session planned for Monday 00:00 in Auckland (UTC+13) is Sunday 05:00 in Los Angeles, so it moves to the previous day on the calendar; a period starts and ends a day early (or late) and its end can fall inside the next day. After this change the stored value is the date and time as wall-clock components read as UTC (`DateTime.utc(y, m, d, h, min, s, ms)` of the local date-time), which is the same number in every zone; the conversion happens only at the models' `toMap`/`fromMap`; everything above the repository keeps passing and reading local instants (same pattern as plan 235, which used the date-only form because food, water and target days are always midnights; the period end is 23:59:59.999, so these two models need the whole wall-clock).

Acceptance: S-23601..S-23606 green, those marked "fails without" red at the base commit when the test process runs in a non-UTC zone; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red; the lead's two-zone probe (write under Auckland, read under Los Angeles) returns the session on the same day and the period with the same dates after the change.

## What the user sees

- Plan a workout for Friday, create a period 1-14 June, then change the phone's time zone: the workout is still on Friday and the period still runs 1-14 June, today and the calendar highlight the same days. Today a zone change shifts them by a day.
- Nothing else changes. Data saved by a pre-release build is not converted (no user data before launch, owner rule): old development rows may show a day off.
- To SEE it: plan a session for tomorrow and add a period covering this week, change the phone's time zone in iOS Settings, reopen the app: both are on the same dates.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `OmniDateUtils` gains `static int wallClockKeyMs(int localMs)` (reads `fromMs(localMs)` and returns `DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond).millisecondsSinceEpoch`) and `static int localMsOfWallClockKeyMs(int key)` (reads `fromMillisecondsSinceEpoch(key, isUtc: true)` and returns `DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond).millisecondsSinceEpoch`). The lead adds them (builder-data cannot write `lib/core`). Plan 235's date-only helpers stay. | `lib/core/utils/date_utils.dart` |
| D-2 | `PlannedSession.toMap`/`fromMap` convert `scheduled_date_ms` through the pair; `TrainingPeriod.toMap`/`fromMap` do the same for `start_date_ms` and `end_date_ms`. `createdAtMs`/`updatedAtMs` and every other instant are untouched. | `models.dart:1526,1541,1619,1633` |
| D-3 | The Hive repository needs no change: both boxes are keyed by id and every range, overlap and sort runs in memory on the converted (local) values. `MockWorkoutRepository` is unchanged. | `hive_workout_repository.dart:2784-2890`, `mock_workout_repository.dart:1811-1895` |
| D-4 | A wall-clock instant that does not exist in the current zone (a DST gap) lands an hour later on read; the day never changes. A period end (23:59:59.999) and a midnight start are never inside a gap in the zones that matter, and a round trip of any value that exists is exact. | reasoning, S-23601 |
| D-5 | No migration (owner rule). The SQL comments and `docs/calendar_periods.md` field notes are updated by the lead. | memory `stats-redesign-ships-as-one-release` |

## Scenarios

Run in a test process whose zone is not UTC (the lead runs the new file under `TZ=Pacific/Auckland` and `TZ=America/Los_Angeles`; under UTC the key and the local instant coincide and the base would pass).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23601 | Helpers: local `DateTime(2026, 6, 15)`, `DateTime(2026, 6, 15, 23, 59, 59, 999)`, `DateTime(2026, 6, 15, 13, 45, 10, 250)`. | `wallClockKeyMs` is `1781481600000`, `1781567999999`, `1781531110250`; `localMsOfWallClockKeyMs(key)` returns the original local instant for each. | the helpers do not exist |
| S-23602 | `PlannedSession` with `scheduledDateMs: DateTime(2026, 6, 15).millisecondsSinceEpoch`. | `toMap()['scheduled_date_ms'] == 1781481600000`; `fromMap(toMap()).scheduledDateMs` equals the original; every other field round-trips. | the base writes the local instant |
| S-23603 | `TrainingPeriod` from local 15 June 00:00 to local 17 June 23:59:59.999. | `toMap()` has `start_date_ms == 1781481600000` and `end_date_ms == 1781740799999` (17 June 23:59:59.999 as UTC: `1781481600000 + 2*86400000 + 86399999`); `fromMap(toMap())` returns the original local start and end. | the base writes the local instants |
| S-23604 | Both stores. Planned sessions for 14, 15 and 16 June (local midnights); `getPlannedSessionsForDateRange(local 15 June 00:00, local 15 June 23:59:59.999)`; `getPlannedSessionsForDateRange(14 June, 16 June)`; `getPlannedSessions()`; Hive only, the raw `planned_sessions` row of the 15 June one. | 1 session on 15 June; 3 in the wide range, ascending; each `scheduledDateMs` the fixture's local midnight; Hive's raw row has `scheduled_date_ms == 1781481600000`. | the base stores the local instant |
| S-23605 | Both stores. A period 15-17 June (start local midnight, end local 23:59:59.999). `hasPeriodOverlap(17 June 00:00, 17 June 23:59:59.999)`, `hasPeriodOverlap(18 June 00:00, 18 June 23:59:59.999)`, `hasPeriodOverlap` of the same period with `excludeId`, `getPeriodById`, `getPeriods`; Hive only, the raw `training_periods` row. | true, false, false (excluded); the read-back period has the fixture's local start and end; Hive's raw row has the two keys of S-23603. | the base stores the local instants |
| S-23606 | Hive (and Mock, which has no restart): after S-23604's and S-23605's writes `harness.restart()`, read them again. | the same sessions and the same period, same local values. | passes both ways in one zone on purpose; the cross-zone proof is the lead's two-process probe, which no in-process test can run |

## Input-reality checklist

1. Writers and units: `CalendarState.createPlannedSession` (`startOfDayMs(date)`), `PeriodState.createPeriod`/`updatePeriod` (the period screen builds midnight / 23:59:59.999), the routine template flow (`day_session_list_screen.dart:381`, `calendar_state.dart:283` copy a plan's own `scheduledDateMs`). All go through the models' maps. The watch payload `scheduledDateMs` (`watch_reference_sync.dart:264`) is the in-memory local value, unchanged.
2. Lifecycle: write and read in one zone is unchanged; a zone change between them is the case fixed. In-memory lists (`CalendarState`, `PeriodState`) were built in the old zone and rebuild on the next `load()`, which the screens call on open; a zone change while the app is open is outside this plan.
3. Settings changing while open: none.
4. Time: DST (D-4); the period end keeps its millisecond so `endDateMs >= startOfDay(today)` comparisons (`stats_progress_service.dart:2615`) behave as before.
5. Cost: none.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-data**, scope `lib/data/models/models.dart`, `test/day_keys_survive_zone_change_test.dart` is plan 235's file and stays untouched; new `test/plans_and_periods_survive_zone_change_test.dart`, the reader tests listed below (raw-column expectations only). No full suite.
2. **P2 lead**: the `date_utils.dart` helpers (before P1), schema comments, docs, mutation pass, two-zone probe, full suite.

## Readers

`grep -rln "scheduled_date_ms\|start_date_ms\|end_date_ms" test` (`test/models_test.dart` ~416-520 holds raw maps with `1000` and `5000`, `test/db_seed_test.dart` is SQL only) and `grep -rln "PlannedSession(\|TrainingPeriod(\|createPeriod\|createPlannedSession" test` (about 30 files, all through the repository or the state, so values round-trip). A reader that pins the raw stored value as the local instant is updated to the key (`OmniDateUtils.wallClockKeyMs(<fixture>)`); one that fails for another reason is reported, never edited.

## Mutation list (lead)

(a) `wallClockKeyMs` returns its input (S-23601..S-23605); (b) `PlannedSession.fromMap` returns the raw key (S-23604); (c) `TrainingPeriod.toMap` writes only the date-only key for the end, losing 23:59:59.999 (S-23603, S-23605); (d) `TrainingPeriod.fromMap` converts the start but not the end (S-23603/05); (e) `localMsOfWallClockKeyMs` drops the milliseconds (S-23601/03).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/calendar_periods.md` | MODIFIED | - `scheduledDateMs` (start-of-day local) | - `scheduledDateMs` (start-of-day local in memory; stored as that wall-clock time read as UTC, so a time-zone change keeps the day) | S-23602, S-23604 |
| `docs/calendar_periods.md` | ADDED | - | `startDateMs` and `endDateMs` are stored the same way | S-23603, S-23605 |
| `scripts/sqlite_schema.sql` | MODIFIED | (midnight local) | (midnight local, stored as that wall-clock time read as UTC) | S-23603 |

Stale-term sweep: `grep -rIn "start-of-day local\|midnight local\|end-of-day local" docs scripts` outside plans/history/releases: `docs/calendar_periods.md:159`, `scripts/sqlite_schema.sql` lines 937, 1009, 1010 (the lead edits all of them).

## Open items

1. (owner) Plan a session and add a period, change the phone's time zone, reopen: same dates.
2. A zone change while the app is open does not refresh the in-memory calendar and period lists until the screens reload (rare, not in this plan).

## Predicted files

`date_utils.dart` (+16, lead), `models.dart` (+16), one new test file (~170), up to two reader tests, one doc, one schema comment block.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass, two-zone probe (found under Los Angeles, Auckland, Tokyo)
- [x] Full suite (+7941 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-236/base.txt` (5cfadb94); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-236xx: none found (checked before seeding).

## Feedback

(none yet)
