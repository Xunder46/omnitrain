# Plan — 131: the foods frame carries no null, so the watch sync is no longer refused

**Status**: built and verified by the lead (2026-11-07), uncommitted. Lead-written (a one-key fix the owner asked for without the crew).
**Binding conventions**: `docs/global_conventions.md`.
**Evidence**: observed counts are in the Progress section below.

## Overview

Owner report: after reinstalling the watch app, Sync spins and nothing arrives (no routines, foods or plans). The owner's phone
log: `Watch transport unavailable: WatchLinkException(send_failed: Payload contains unsupported type.)` from
`WatchSyncRequestHandler._sendRoutines`. iOS's WatchConnectivity refuses a message dictionary that holds a null. The
`foods_down` frame sent `'categoryId': null` for every food outside a category, the bundle's commit marker (the routines frame)
is only sent after the foods were carried, so one uncategorised food stopped the whole answer.

## Goal and acceptance

`foods_down` holds no null anywhere; an uncategorised food omits `categoryId` (the schema does not require it and the wrist reads
an absent key as Uncategorized, `WatchFoodCatalog.swift:67`). Acceptance: S-13040.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13040 | `WatchReferenceSync._foodJson` omits `categoryId` instead of sending null | `foods_down.schema.json` `food.required` lacks `categoryId`; `WatchFoodCatalog.swift:67` `as? String` |
| D-13041 | No transport-level null stripping: the wire's own convention is "omitted, never nulled" (`PROTOCOL.md`), and a blanket strip would hide a frame whose null is meaningful | other builders already use `'x': ?v` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13040 | `buildFoodsDown` with a food in no group and a food whose group is gone | a recursive walk finds no null; the orphan row has no `categoryId` key; the schema validator accepts the frame | the old code emitted `categoryId: null` for both foods (observed: `$.payload.foods[0].categoryId` and `[1]`) |

## Phases

Lead-written, one edit in `lib/core/utils/watch_reference_sync.dart` and one test in `test/watch_nutrition_quick_log_test.dart`.

## Progress

- [x] Fix and test. Red without the fix (mutation, file restored `cmp`-identical): `Expected: empty, Actual: ['$.payload.foods[0].categoryId', '$.payload.foods[1].categoryId']`.
- [x] `flutter test test/watch_nutrition_quick_log_test.dart` `+47: All tests passed!`; full suite `+7043 ~2: All tests passed!`; analyze 181.
- [ ] Owner device check: Sync again on the watch with an uncategorised food on the phone; foods, routines and plans arrive.

## Assumption Log

- The null in the foods frame is the only null found in the phone's reference frames (routines, preferences, plans, bests use omission). Other frames (session snapshots) were not audited for nulls here; they were working on the owner's device.
- Not proven on a device: the log shows the refusal, and the test shows the cause is removed, but no paired device run was made.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `watch/sync_protocol/PROTOCOL.md` | MODIFIED | `null` means the phone groups it under | The phone omits the key rather than sending `null` | D-13040, S-13040 |
