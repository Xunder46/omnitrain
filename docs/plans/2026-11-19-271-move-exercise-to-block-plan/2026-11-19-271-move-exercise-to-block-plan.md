# Plan 271 — Move an exercise to another block in the routine editor

Review item 38, third part (owner list: "... Routine editor: drag works only inside a block. Suggested: ... allow dragging between blocks in the editor."). Owner 2026-11-19 chose menus over drag for the live list; the same is done here: each block is its own reorderable list, which cannot take a drag from another, so the editor gets `Move to <block name>` menu items instead (a bottom sheet was tried first and refused by the hand-built-sheet ratchet; no shared sheet piece exists).
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

In the routine editor, the `⋮` menu of an exercise has one `Move to <block name>` item for each other block (none when the routine has a single block). Choosing one moves the exercise to the END of that block with its sets and targets, and renumbers both blocks. The change is an ordinary routine edit (unsaved-changes guard, autosave, Save). Dragging inside a block works as before.

Acceptance: S-27101..S-27104 green (crew-written test file, verified by the lead); `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27101 | `RoutineState.moveExerciseToSegment(effortId, targetSegmentId)`: removes the effort from its block, appends a copy with the target `templateSegmentId`, renumbers both lists, schedules autosave, notifies; false for an unknown effort or block or the same block. Targets are keyed by effort id so they travel unchanged. | `routine_state.dart` |
| D-27102 | Persistence needs no change: `_syncRowsToRepository` re-creates the effort under its new block (delete under the old, put under the new, targets re-created). | `_syncRowsToRepository` |
| D-27103 | UI: `ExerciseCard.moveTargets` / `onMoveTo` add one menu item per other block (keys `move_to_block_<blockId>`). | `routine_setup_screen.dart` |

## Scenarios

S-27101 move X from A to B: B is [Z, X], A is [Y], both renumbered. S-27102 X's targets are unchanged. S-27103 same block, unknown block and unknown effort return false and change nothing; after Save the repository holds X under B only. S-27104 the editor: menu -> `Move to Block B` shows X under B and offers no item for its own block; one block shows no item.

## Input-reality checklist

1. Writers: routine save only. 2. Lifecycle: a routine started earlier is unaffected (sessions copy a routine when they start). 3. Settings: none. 4. Time: none. 5. Cost: none. 6. Words: `Move to <block name>` (owner to read). 7. Competition: autosave debounces as for other edits.

## Docs delta

`docs/my_routines.md`: one sentence in the editor section.

## Open items

1. (owner) Drag handles still reorder inside a block only; a drag across blocks is not built (menu instead).
2. The new exercise lands at the END of the chosen block; say if you want a choice of place.
