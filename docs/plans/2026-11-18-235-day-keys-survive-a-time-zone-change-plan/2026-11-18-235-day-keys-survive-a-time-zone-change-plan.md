# Plan 235 — Food, water and daily targets stay on their calendar day when the time zone changes

Series: nutrition/calendar/summary pre-launch review (2026-11-16), item "days are keyed by the local-midnight instant, so a time-zone change hides today's food, water and target". Part 1 of 2: the nutrition store (food log, water log, daily targets). Part 2 (plan 236, not seeded): planned sessions and training periods. Phone only; the watch wire already names days as `YYYY-MM-DD` text (`watch_reference_sync.dart` `_isoDay`), so nothing on the watch changes. One builder run, then docs. Status: COMMITTED (built, mutation-checked (6 mutants: 5 killed, 1 equivalent), docs applied; full suite +7932 ~4 green.

## Goal and acceptance

A food row, a water day and a daily target are stored under `dateMs`, the instant of local midnight (`OmniDateUtils.startOfDayMs`). The same calendar date is a different number in a different zone, so after the phone changes zone (travel, a manual change) every row written before is filed under a day that is no longer "today" and no longer matches the day list. Proof 2026-11-18 (throwaway two-process probe on the Hive store, committed nowhere): written under `TZ=Pacific/Auckland` for 15 June 2026 (one food, 750 ml water, one target), read back under `TZ=America/Los_Angeles` for 15 June 2026 it found 0 foods, 0 ml and no target; read back under Auckland it found 1, 750 and 2200.

After this change the stored day key is the calendar date itself, independent of any zone: the UTC midnight of the local year-month-day (`DateTime.utc(y, m, d)`). The conversion happens at the persistence boundary only (the models' `toMap`/`fromMap` and the Hive repository's box keys); everything above the repository keeps passing local-midnight instants exactly as today.

Acceptance: S-23501..S-23509 green, those marked "fails without" red at the base commit when the test process runs in a non-UTC zone; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red; the lead's two-zone probe (write under Auckland, read under Los Angeles) finds the row after the change.

## What the user sees

- Fly to another time zone, or change the phone's zone: the food list, the water total, the calorie ring and the daily target for a given date are still there. Today they vanish (all zero) and the target falls back to an older day.
- Nothing else changes: same rows, same totals, same days. A day is the calendar date on the phone's clock.
- Data saved by a pre-release build is not converted (no user data before launch, owner rule): a development phone's old rows may show one day off until deleted.
- To SEE it: log a food and 500 ml of water, change the phone's time zone in iOS Settings, reopen the app: the food and water are still on today's date.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `OmniDateUtils` gains two helpers: `static int dayKeyMs(DateTime date) => DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;` and `static int localMidnightOfDayKeyMs(int key) { final d = DateTime.fromMillisecondsSinceEpoch(key, isUtc: true); return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch; }`. `startOfDayMs` and `todayMidnightMs` are unchanged (they stay the in-app currency and are still right for instants). | `lib/core/utils/date_utils.dart:8` |
| D-2 | The models convert at their own map boundary: `ConsumedFood.toMap` writes `'date_ms': OmniDateUtils.dayKeyMs(OmniDateUtils.fromMs(dateMs))`, `ConsumedFood.fromMap` reads `dateMs: OmniDateUtils.localMidnightOfDayKeyMs(m['date_ms'] as int)`. `NutritionTarget` does the same for a non-null `date_ms`; a null stays null both ways. `models.dart` already imports from `core/utils`. | `models.dart:1860,1868,2285,2313` |
| D-3 | `HiveWorkoutRepository` keys its two per-day boxes by the day key: target box key and water box key become `dayKeyMs(fromMs(dateMs)).toString()`; the water row's `date_ms` and `id` (`WaterLogEntry.idForDate(key)`) use the key. Rows never written through the models (water) store the key directly. `WaterLogEntry.fromMap/toMap` convert like D-2 so the model stays consistent. | `hive_workout_repository.dart:1133-1210,2545-2625` |
| D-4 | The target ancestor walk in `getNutritionTargetForDate` (Hive) steps by calendar day over day keys: `DateTime.utc(y, m, d - 1)` from the requested date's components, looking up `.millisecondsSinceEpoch.toString()`. The forward propagation compares keys with keys and writes the future row with `copyWith(dateMs: OmniDateUtils.localMidnightOfDayKeyMs(futureKey))` (the model converts back to a key when it writes). | `hive_workout_repository.dart:1145-1160,1187-1203` |
| D-5 | `getConsumedFoodsForDate` and `getConsumedFoodsInRange` (Hive) need no code change: they filter the already converted rows on local-midnight instants. | `hive_workout_repository.dart:2494,2519` |
| D-6 | `MockWorkoutRepository` is unchanged (in-memory objects, no storage format, no zone to survive); the two stores must still end identical on every scenario. | `mock_workout_repository.dart:2007` |
| D-7 | No migration, no legacy read: rows written before this change are off by the zone offset (owner rule: no user data). | memory `stats-redesign-ships-as-one-release` |
| D-8 | Planned sessions and training periods are plan 236, not this one (they are also stored as local-midnight instants and are read by range). Session days need nothing: they are derived from `startedAtMs` at read time, in the current zone. | review |

## Scenarios

Run every one in a test process whose zone is not UTC (the lead runs the new file under `TZ=Pacific/Auckland` and `TZ=America/Los_Angeles`; on a UTC machine the key and the local midnight coincide and the base would pass).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23501 | Pure test of the two helpers: for `DateTime(2026, 6, 15, 0, 0)`, `DateTime(2026, 6, 15, 13, 45)` and `DateTime(2026, 6, 15, 23, 59, 59)`. | `dayKeyMs` is `1781481600000` for all three (the UTC midnight of 15 June 2026); `localMidnightOfDayKeyMs(1781481600000)` equals `DateTime(2026, 6, 15).millisecondsSinceEpoch`; the round trip `localMidnightOfDayKeyMs(dayKeyMs(d)) == OmniDateUtils.startOfDayMs(d)` holds. | the helpers do not exist |
| S-23502 | Model round trip: a `ConsumedFood` with `dateMs: DateTime(2026, 6, 15).millisecondsSinceEpoch`; a `NutritionTarget` with the same `dateMs`; a `NutritionTarget` with `dateMs: null`. | `toMap()['date_ms'] == 1781481600000` for the first two; `fromMap(toMap()).dateMs` equals the original local midnight; the null target keeps `date_ms` null both ways and `isNull` after `fromMap`. | the base writes the local-midnight instant, which is 1781481600000 only in UTC |
| S-23503 | Both stores. `saveWaterVolumeForDate(localMidnight(2026-06-15), 750)`; read it back with `getWaterVolumeForDate(localMidnight(2026-06-15))`; then, Hive only, read the raw water box (`Hive.box`) and check its single key and row. | 750 ml back; Hive's raw key is `'1781481600000'` and the row's `date_ms` is `1781481600000`, its `id` `'water-1781481600000'`. | the base's raw key is the local-midnight instant |
| S-23504 | Both stores. `createConsumedFood` for 14, 15 and 16 June (local midnights); `getConsumedFoodsForDate(15 June)`, `getConsumedFoodsInRange(15 June, 15 June)` and `getConsumedFoodsInRange(14 June, 16 June)`; Hive only, the raw box row for the 15 June food. | 1 row, 1 row, 3 rows, each row's `dateMs` the local midnight of its day; Hive's raw row `date_ms` is the 15 June key. | the base stores the local-midnight instant |
| S-23505 | Both stores. A target saved for 10 June (A) and read for 15 June. | the 15 June read returns A's macros with `dateMs` equal to the local midnight of 15 June (the walk crosses the five days between, over a boundary month-free span). | passes both ways on purpose (guards the ancestor walk; mutation: the walk steps in local instants against key boxes) |
| S-23506 | Both stores. Targets A saved for 10 June and an identical copy of A saved for 20 June; then B saved for 10 June (different macros). | the 20 June read returns B (forward propagation kept the identical future row in step); a 5 June read returns null; the 10 June read returns B with `dateMs` the local midnight of 10 June. | passes both ways on purpose (mutation: propagation compares keys with local instants) |
| S-23507 | Hive only: `applyWaterTap` for 15 June with tap id `t1`, then `harness.restart()`, then `applyWaterTap` again with `t1`, then `getAppliedWaterTapIds(15 June)` and `getWaterVolumeForDate(15 June)`. | the second tap returns false; the ledger is `['t1']`; the volume is one step. | passes both ways on purpose (mutation: `applyWaterTap` keeps keying by the local instant while the reads use the key) |
| S-23508 | Both stores, through `NutritionState`: log a food for today with `logConsumedFoodAt`, add water for today, save a target for today, then build a fresh `NutritionState` over the same repository (Hive: `harness.restart()`). | the fresh state, after `loadConsumedToday()`/`loadWaterForDate(todayMidnightMs())`/`loadNutritionTargetForDate(todayMidnightMs())` (use the names the existing nutrition tests use), shows the food, the water and the target. | passes both ways in one zone; the cross-zone proof is the lead's two-process probe (below), which no in-process test can run |
| S-23509 | Both stores. A target saved for 14 June, read for 15 June. | the 15 June read returns it with `dateMs` the local midnight of 15 June. | the lead's mutation (the walk's first step a local instant against key boxes) skipped exactly the day before; S-23505 alone (5 days apart) did not see it |

## Input-reality checklist

1. Writers and units: every writer of a day goes through `ConsumedFood.toMap`, `NutritionTarget.toMap`, `saveWaterVolumeForDate`, `applyWaterTap` (all in the Hive repository). Everything above passes local-midnight instants built by `startOfDayMs`/`todayMidnightMs`; the wire (watch) carries `YYYY-MM-DD`, converted to a local-midnight instant by the phone as today (`watch_water_log_bridge.dart:126`, `watch_reference_sync.dart:850`). Units untouched.
2. Lifecycle: a store written before and read after a zone change is the case being fixed; a store written and read in one zone is unchanged. The in-memory caches (`_consumedToday`, `_targetsByDate`, `_waterDayMs`) are keyed by local-midnight instants of the zone they were loaded in; after a zone change `rolloverToDate` rebuilds them on the next day rollover, and the app restarts the caches at launch (a zone change while the app runs is outside this plan: the next load re-derives today).
3. Settings changing while open: none.
4. Time: DST is already handled by calendar-day stepping and stays so (D-4 keeps calendar arithmetic, now in UTC where there is no DST). A zone whose midnight does not exist on a day (some zones skip 00:00): `DateTime(y, m, d)` normalises to 01:00 of the same date, so `dayKeyMs` of it still names that date.
5. Cost: the ancestor walk is as long as before (one lookup per day back to 1970 on a miss, today's cost).
6. Words: none on screen.
7. Slot competition: none; `applyWaterTap` keeps its read-then-put with no await between (D-5 of plan 94).

## Phases

1. **P1 builder-app**, scope `lib/core/utils/date_utils.dart`, `lib/data/models/models.dart`, `lib/data/repositories/hive_workout_repository.dart`, `test/day_keys_survive_zone_change_test.dart` (new), and the readers listed below (key-format expectations only). No full suite.
2. **P2 lead**: schema comments + docs, mutation pass, the two-zone probe, full suite.

## Readers

`grep -rln "date_ms" test`: `test/models_test.dart:1293` (`expect(map['date_ms'], 1749312000000)` for a `ConsumedFood`), `test/water_tap_ledger_test.dart` (raw rows with `'date_ms': 1` and `dMs`), `test/food_form_decimals_and_autofocus_test.dart` (`'date_ms': 0`), `test/db_seed_test.dart` (SQL only, unaffected). A reader that pins the stored value as the local-midnight instant is updated to the key (its premise is the storage format); a reader that fails for another reason is reported, never edited. Also `grep -rln "getNutritionTargetForDate\|saveNutritionTargetForDate\|getWaterVolumeForDate\|saveWaterVolumeForDate\|getConsumedFoodsInRange" test` run under both stores.

## Mutation list (lead)

(a) `dayKeyMs` returns the local midnight (S-23501/02/03/04); (b) `ConsumedFood.fromMap` returns the raw key (S-23504); (c) target ancestor walk steps `DateTime(...)` local instants against key boxes (S-23505); (d) propagation compares a key with `dateMs` (S-23506); (e) `applyWaterTap` skips the conversion (S-23507); (f) `NutritionTarget.fromMap` converts a null (crash, S-23502).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/data_models.md` | MODIFIED | keyed by `dateMs` (local midnight). | keyed by `dateMs` (the calendar date as the phone's local midnight; stored as that date's UTC midnight so a time-zone change keeps the day). | S-23503 |
| `docs/data_models.md` | ADDED | - | A day is stored as its calendar date's UTC midnight | S-23502 |
| `scripts/sqlite_schema.sql` | MODIFIED | (local midnight ms) | (the date's UTC midnight, the zone-independent day key) | S-23501 |

Stale-term sweep: `grep -rIn "local midnight\|midnight local" docs scripts` outside plans/history/releases gave `docs/signals.md:67` and `docs/training_load.md:146` (Mix week tiling, instants, stay true), `docs/state_management/services_and_utils.md:596` (`proteinTargetsByDay` keys its map by local-midnight `DateTime`, stays true), the two data-model lines above.

## Open items

1. (owner) Log a food and water, change the phone's time zone, reopen: still there.
2. Plan 236: planned sessions and training periods (same key problem, range-read).
3. A zone change while the app is open does not refresh the in-memory day caches until the next launch or rollover (rare; not in this plan).

## Predicted files

`date_utils.dart` (+14), `models.dart` (+12), `hive_workout_repository.dart` (+30), one new test file (~230), up to three reader tests, one doc, one schema comment.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass, two-zone probe (found under Los Angeles, Auckland, Tokyo)
- [x] Full suite (+7932 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-235/base.txt` (621c1018); other sessions' files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-235xx: none found. Proof probe kept at `scratchpad/zz_probe_zone_change_test.dart`, never committed.
- 2026-11-18: decision for the owner's scope question (all of time-zone in one go, or split): split into 235 (nutrition) and 236 (plans, periods); no behaviour question, stated in one line.

## Feedback

(none yet)
