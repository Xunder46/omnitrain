# Evidence — plan 218

- P1 builder (state + queue + wiring, `test/wrist_linked_finish_drops_planned_sets_test.dart` 6 tests, three 157a tests rewritten): green.
- P2 builder (`test/wrist_linked_end_late_sets_test.dart`, 3 tests): S-21804, S-21805 green, S-21806 red at first (a late wrist set replaced a typed set), cause traced to the importer's planned-row fill.
- Fix 1 (importer `fillPlannedSets`, `opensRest` split), fix 2 (S-14 fixture through the app's `endSession`): readers green: merge 78, import 96, finish 22, end_owed 31, edit_restore 25, finish_drops 33, screen 1.
- Lead mutation pass (7): ended workout still fills, effort removed anyway, queue ignored, wrist-linked drop skipped again, phone-only keeps efforts, rest gate follows the fill gate, chain not used: all KILLED, sources restored and compared.
- Full suite found two more readers (clock-seam fixture, replay corpus), both fixed (Open items 7). `swift test` in `watch/watchos`: 1580 tests, 0 failures.
- Review: APPROVE WITH FIXES (0 blocker, 1 major: a stale sentence in `docs/watch_session_sync.md`, 2 minor); all three fixed.
