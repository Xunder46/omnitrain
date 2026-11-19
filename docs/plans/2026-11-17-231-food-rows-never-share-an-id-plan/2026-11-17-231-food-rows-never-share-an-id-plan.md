# Plan 231 — Foods logged back to back never overwrite each other

Series: nutrition/calendar/summary pre-launch review (2026-11-16), proven item "food-log row ids are built from the millisecond clock". Phone only (`lib/state/nutrition_state.dart`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (4 of 4 killed; S-23105 added by the lead), docs applied; full suite pending.

## Goal and acceptance

A logged food row's id is `consumed-<ms>-<ms/1000>` (`NutritionState._snapshotFor`, `nutrition_state.dart:434`). Two foods logged in the same millisecond get the same id, and both stores (Mock and Hive) replace a row with an equal id, so the second food silently overwrites the first (proof 2026-11-16: six foods logged back to back on the mock store left two rows). The wrist's quick-log bridge logs every food of one message in a loop (`watch_nutrition_log_bridge.dart:143-171`), so a message with several foods is the real exposure. After this change every new row gets an id no other row has.

Acceptance: S-23101..S-23105 green, those marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Log several foods quickly, or send several foods from the watch in one go: every food appears in the day, each with its own amount. Today some can vanish.
- Nothing else changes: the same row shape, the same one-row-per-food-per-day rule.
- To SEE it: from the watch, tick three foods in the quick-log and send them together; all three appear on the phone's day.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `NutritionState` keeps `int _lastIdStamp = 0` and a private `int _nextIdStamp()`: `final now = DateTime.now().millisecondsSinceEpoch; _lastIdStamp = now > _lastIdStamp ? now : _lastIdStamp + 1; return _lastIdStamp;`. | `nutrition_state.dart:434` |
| D-2 | `_snapshotFor` builds the id from `_nextIdStamp()` instead of `nowMs` (`'consumed-$stamp-${stamp ~/ 1000}'`); `createdAtMs` / `updatedAtMs` keep `nowMs`. Both fresh-log paths (`logConsumedFood`, `logConsumedFoodOnDay`) go through `_snapshotFor`, so one change covers today's log, a past-day log and the wrist bridge. | `nutrition_state.dart:402,623`, `watch_nutrition_log_bridge.dart:158-166` |
| D-3 | The id format `consumed-<n>-<n/1000>` is kept (nothing parses it; seeds use `seed-consumed-...`). | grep `consumed-` |
| D-4 | No migration: rows already overwritten cannot be recovered (no user data before launch). | owner rule |
| D-5 | Other tables' ids are not touched in this plan (the review proved only the food log); a scan found no other clock-built id on a repeated-write path. | grep |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23101 | State test, both harnesses. Six different foods, logged one after another with `await nutritionState.logConsumedFoodAt(food, amount)` and no delay. | six rows for today in the store; six distinct ids; each amount kept. | equal-millisecond ids overwrite (proof: 2 rows of 6) |
| S-23102 | Same six foods through `Future.wait` of six `logConsumedFoodAt` calls. | six rows. | same |
| S-23103 | The same food logged twice. | one row, the second amount (the day-uniqueness rule is intact). | passes both ways on purpose (mutation: every call makes a new row) |
| S-23105 | Six foods on a past day through `Future.wait` of `logConsumedFoodOnDay` (all take their clock before any await). | six rows. | the base shares the id (lead mutation: the past-day path on the plain clock survived S-23104 alone) |
| S-23104 | Two foods on a past day back to back through `logConsumedFoodOnDay`. | two rows. | the base shares the id when both land in one millisecond |

## Input-reality checklist

1. Writers and units: the phone UI, the wrist bridge and the save-as-own-food flow all reach `logConsumedFoodAt`; one id source covers them. Amounts are in the food's own unit, untouched.
2. Lifecycle: `_lastIdStamp` lives with the `NutritionState` (one per app); a restart starts at the clock, which is later than any earlier stamp (up to a clock set backwards, accepted).
3. Settings changing while open: none.
4. Time: a clock that steps back does not matter inside one run (the stamp only goes up); across a restart a row from the future could share an id only if the clock moved back by the exact stamp: accepted.
5. Cost: none.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/state/nutrition_state.dart`, `test/food_rows_never_share_an_id_test.dart` (new). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "consumed-\|createConsumedFood\|logConsumedFood" test`. A reader that pins the id as `consumed-<now>-...` is reported, not edited.

## Mutation list (lead)

(a) `_nextIdStamp` returns the plain clock (S-23101/02 die); (b) the stamp does not go up on an equal clock (`now >= _lastIdStamp`); (c) `logConsumedFoodOnDay` bypasses the stamp; (d) every call makes a new row (S-23103).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/nutrition_state.md` | ADDED | - | No two logged rows share an id | S-23101 |

Stale-term sweep: `grep -rIn "consumed-" docs` outside plans/history/releases; each hit is a row.

## Open items

1. (owner) Send several foods from the watch at once: all appear on the phone.
2. Other writers keyed by clock (water logs, measurements) were not proven and are not touched.

## Predicted files

`nutrition_state.dart` (+14), one new test file, one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7902 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-231/base.txt`; other sessions' files are outside this plan.
- 2026-11-17: ids S-231xx: none found.

## Feedback

(none yet)
