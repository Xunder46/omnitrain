# Plan 270 — Move an exercise up or down on the live list

Review item 38, second part (owner list: "Live session: no reorder ... add drag-to-reorder"). Owner 2026-11-19: do it as Move up / Move down in the tile menu for now; he will test it in his next workout. Drag between blocks in the routine editor is plan 271.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

The `⋮` menu on each exercise tile (plan 269) gains `Move up` and `Move down`, greyed at the ends. A loose exercise swaps places with the item beside it; a block counts as one item, so a loose exercise can pass a block. Inside a block an exercise swaps with its neighbour. The list redraws at once, in the live workout and in Edit Session. A rolling list moves only inside a block.

Acceptance: S-27001..S-27005 green (the file does not compile without the change); `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27001 | `WorkoutState.moveExercise(effortId, delta)` (SessionCore): sorts the group the way the list does, swaps one place, then renumbers positions 0..n-1 (which also settles legacy ties). Inside a block it writes `blockOrderIndex`/`orderIndex`; at top level it writes `topLevelOrderIndex` for loose exercises and blocks, and gives a block's exercises their block's new place. | `workout_session_screen.dart` order helpers |
| D-27002 | A block's own `orderIndex` (the rolling-session block order and `reorderSessionBlocks`) is never changed here. | `session_block_manager.dart` |
| D-27003 | Move availability is computed from the same ordered lists the screen shows (`_sortExercisesForBlock`, `_buildNonRollingTopLevelItems`). | list view |
| D-27004 | Edit Session marks the screen as structurally changed. Known gap: the edit snapshot holds efforts but not blocks, so leaving Edit Session without saving restores the exercises' positions but not a block's top-level position moved by passing it. Display order only, no data is lost. | `session_edit_snapshot.dart` |

## Scenarios

S-27001 a loose exercise moves up and down among others. S-27002 the first cannot move up, the last cannot move down, an unknown id returns false. S-27003 inside a block two exercises swap. S-27004 a loose exercise passes a block. S-27005 the tile menu: Move up greyed on the first, Move down moves it below the second.

## Input-reality checklist

1. Writers: `updateEffort`, `updateSessionBlock`. 2. Lifecycle: reload after each move; a finished-workout edit follows the existing structural-change guard. 3. Settings: none. 4. Time: none. 5. Cost: a few writes per move. 6. Words: `Move up`, `Move down`. 7. Competition: the watch's slot order is not changed by this plan; whether the wrist list follows the new order is for the owner's workout test.

## Docs delta

`docs/modality_based_exercise_ui.md`: one bullet in the List View section.

## Open items

1. (owner) Test in a real workout, including with the watch paired: does the wrist list follow the new order?
2. (owner) D-27004 gap in Edit Session with blocks.
3. Plan 271: drag between blocks in the routine editor.
