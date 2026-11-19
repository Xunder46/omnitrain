# Evidence — plan 138 (routine editor: arrows cross exercises), P2

Lead-observed facts, copied per the brief. Not measured by P2.

- Base commit `b78112ef2f99d2bdaf450c889cbe4b7c53d7d80d`; branch `claude_develop`.
- Production change: one file, `lib/features/routine/routine_setup_screen.dart`, methods `_buildSetControls`, `_previousSet`, `_nextSet` (+38/-8).
- `flutter analyze` on that file: 24 issues before and after (all pre-existing info notices); no new issue.
- `flutter test test/routine_detail_screen_test.dart`: `+25: All tests passed!` (17 existing, 8 new: S-4514 x1, S-4515 x1, S-4516 x2, S-4517 x1, S-4518 x3).
- Mutation pass by the lead (10 mutants of the arrow code, original restored byte-identical):
  - Killed by the first 7 tests: M1 Next does not cross, M2 Previous lands on set 1, M3 Previous enabled only by set, M4 Previous never dims, M5 Next enabled only by set, M6 Next never dims, M7 Next adds a set when it crosses, M10 Next jumps to the last exercise.
  - M8 Previous goes to the first exercise and M9 Previous uses the wrong set count SURVIVED the first 7 tests (the two-exercise fixture cannot tell) and were killed after the lead added the test `Previous walks back block by block, landing on last sets` (group `S-4518 the walk follows the list order`).
- Not claimed: the app was not run on a simulator or device; (owner) device check is in the plan's Assumption Log.

## Docs delta (P2)

| Row | Status |
|---|---|
| `docs/my_routines.md` MODIFIED (old marker "the Previous Set / Next Set arrow row is unchanged" removed; new marker "Next on the last set opens the next exercise" present) -> done |
| `docs/my_routines.md` ADDED "Previous on the first set opens the previous exercise on its last set" -> done |
| `docs/my_routines.md` ADDED "dimmed on the last set of the last exercise" -> done |
| `docs/my_routines.md` ADDED "never adds a set" -> done |
| `docs/my_routines.md` ADDED "same order as the list" -> done |

Test citations in `docs/my_routines.md` (groups and test names verified this run in `test/routine_detail_screen_test.dart`): groups `S-4514 Next crosses to the next exercise`, `S-4515 Previous crosses to the previous exercise`, `S-4516 the arrows dim at the ends of the routine`, `S-4517 Next never adds a set`, `S-4518 the walk follows the list order`, plus the one-exercise case named by the older group `S-4512 set arrows (A8)` · `Previous and Next Set walk the sets and stop at the ends`.

Stale-term sweep for `arrow row is unchanged`, `Previous Set`, `Next Set`, `stop at the ends` (docs/ excluding `docs/plans`, `docs/history`, `docs/releases`, this run): only `docs/my_routines.md:383-403` (the rewritten paragraph itself). The remaining hits elsewhere are inside `docs/plans/*` and no other exclusion-listed or non-plan doc carries the old claims.
