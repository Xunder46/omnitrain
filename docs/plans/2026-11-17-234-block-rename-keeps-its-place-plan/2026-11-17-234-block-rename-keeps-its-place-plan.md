# Plan 234 — Renaming a session block keeps it where it is

Series: nutrition/calendar/summary pre-launch review (2026-11-16, second pass), proven at data level: "renaming a session block rewrites it without its top-level position, so a block that sits after standalone exercises moves up". Phone only (`lib/features/session`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (4 of 4 killed), docs applied; full suite +7917 ~4 green).

## Goal and acceptance

The Rename Block dialog (`workout_session_screen.dart:1799-1853`) builds a replacement `SessionBlock` with `id`, `sessionId`, the new `name`, `orderIndex`, `createdAtMs`, but NOT `topLevelOrderIndex`. The constructor leaves it null, which `toMap` stores as `orderIndex` (`models.dart:303`), so a block that had been placed after standalone exercises (top-level position above its block order) jumps back up to its block-order slot. After this change a rename keeps the block's top-level position.

Acceptance: S-23401..S-23403 green, the one marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- In a rolling session with standalone exercises and a block that sits below them, rename the block: it stays below the exercises. Today it jumps to the top.
- Nothing else changes: the new name, the block's contents and its other fields are as before.
- To SEE it: in a rolling session add an exercise, add a block below it, rename the block.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | In `_showBlockRenameDialog` the replacement block carries `topLevelOrderIndex: block.topLevelOrderIndex`. Nothing else changes in the replacement. | `workout_session_screen.dart:1843-1850`, `models.dart:268-306` |
| D-2 | `SessionBlockManager.updateSessionBlock` is unchanged: it stores what it is given (other callers, e.g. a reorder, pass the index they mean). | `session_block_manager.dart:97-112` |
| D-3 | Other `SessionBlock(` constructions in `lib/` (add, clone) set the index themselves and are not touched. | grep |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23401 | Screen test, Mock only (the fixture of the existing rename test in `test/screen_widget_test.dart` near line 8677: a rolling session with one block, open the block menu, Edit, Rename Block dialog). Before the rename the block is stored with `orderIndex` 0 and `topLevelOrderIndex` 3 (written through `workoutState.updateSessionBlock`). Rename to `Warm-Up`, Save. | `workoutState.getSessionBlocks().single.topLevelOrderIndex` is 3 and the store row (`repo.getSessionBlocks(sessionId)`) reads 3. | the base writes null (stored as `orderIndex`, 0) |
| S-23402 | The same rename. | the name is `Warm-Up`, `orderIndex` 0, `createdAtMs` unchanged. | passes both ways on purpose (mutation: the rename drops the new name or changes the order) |
| S-23403 | A block that was never reordered (`topLevelOrderIndex` null, `orderIndex` 0) renamed. | stored `topLevelOrderIndex` equals `orderIndex` (0), unchanged. | passes both ways on purpose |

## Input-reality checklist

1. Writers and units: only this call site renames. `toMap` already maps null to `orderIndex` for a block never reordered, so D-1 changes nothing for it.
2. Lifecycle: none.
3. Settings: none.
4. Time: `updatedAtMs` still takes the current clock.
5. Cost: none.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/features/session/workout_session_screen.dart`, `test/block_rename_keeps_its_place_test.dart` (new). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`test/screen_widget_test.dart` (the rename test, ~8677), `grep -rln "updateSessionBlock\|SessionBlock(" test`. A reader that pins the rename dropping the position is reported, not edited.

## Mutation list (lead)

(a) the `topLevelOrderIndex` line removed; (b) it is set to `block.orderIndex` (S-23401 must die: 0 vs 3); (c) `orderIndex` dropped from the replacement (S-23402).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/data_models.md` | ADDED | - | Renaming a block keeps its top-level position | S-23401 |

Stale-term sweep: `grep -rIn "topLevelOrderIndex\|Rename Block" docs` outside plans/history/releases: the hits describe the ordering keys and stay true.

## Open items

1. (owner) In a rolling session put a block below an exercise and rename it: it stays below.

## Predicted files

`workout_session_screen.dart` (+1), one new test file, one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7917 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-234/base.txt`; other sessions' files are outside this plan.
- 2026-11-17: ids S-234xx: none found.

## Feedback

(none yet)
