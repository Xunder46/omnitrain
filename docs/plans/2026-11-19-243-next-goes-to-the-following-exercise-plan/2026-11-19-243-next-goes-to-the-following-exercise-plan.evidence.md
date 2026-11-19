# Evidence — plan 243 (Next goes to the following exercise in the list)

Base commit b94a549a (branch `claude_develop`).

## Production change (lead)

`WatchRestLabels.swift`, end of `deriveRestLabels`: the first-not-done search and the plan 201 cycle block are one block (D-24301). Before the builder started, four tests failed for exactly the old premise (run by the lead): `testS20104AnUndoneExerciseWinsOverTheCycle`, `testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped`, `WatchRestNextHoldTests.testLoggingOutOfOrderCountsPerSlotAndNextGoesForwardFromTheLoggedOne` and `testNextWrapsToTheTopWhenNothingIsLeftAfterTheLoggedExercise`.

## Builder run (crew-builder-watch, P2)

Rewrote those four (new names in the plan's Docs delta) and added `testS24301`..`testS24305` (`WatchRestLabelsTests`) and `testS24306TheRestsNextOpensTheFollowingExerciseNotTheUnloggedOne` (`WatchRestAdvanceTests`). 3 files, +203 -26.

## Verification (lead, observed)

| Check | Result |
|---|---|
| `swift test` in `watch/watchos`, whole package | Executed 1600 tests, with 0 failures |
| `swift test --filter` of the three rest files (run again after the mutation pass, source restored byte-identical) | green |
| `flutter analyze` | no Dart file changed by this plan |
| `python3 -I .claude/scripts/macos/plan-lint.py after <plan>` | clean (6 scenarios, 12 docs-delta rows) |
| stale-term sweep `grep -rIn "not-done\|searched forward\|first exercise after it\|unfinished exercise\|testS20104AnUndone\|testS7603cAnExercise" docs` outside plans/history/releases | no hits |

## Mutation pass (lead; script keeps its backup outside the tree, source restored and `cmp`-identical)

Filter: `WatchRestLabelsTests|WatchRestNextHoldTests|WatchRestAdvanceTests`.

| Mutant | Result | Killed by (among others) |
|---|---|---|
| M1 wrap removed (`min(here + 1, count - 1)`) | killed | S-24302, S-20101, S-9106 |
| M2 following always by name alone | killed | S-24303, S-24305 |
| M3 following always with its count | killed | S-24301, S-24302, S-9104 |
| M4 planned-set stay rule removed | killed | S-24304 |
| M5 one-slot guard widened | killed | S-20103 |
| M6 done means past the plan (`sets > planned`) | killed | S-24301, S-24302 |
| M7 skips one exercise (`here + 2`) | killed | S-24306, S-24301, S-24302 |

## Docs delta (lead wrote the sentences; the keeper was not run: seven short replacements, and a writer slot was held by another session)

`docs/state_management/watch_surface_wrist_logging.md` (the rest-line paragraph, the done-slot paragraph, three test names), `docs/watch_session_sync.md` (one phrase), `docs/watch-app-setup-and-qa.md` (QA step 41 rewritten: owner check), `docs/watch-app-qa-wrist-logging.md` (two test names). Every New marker is on one line and every Old marker is gone (plan-lint).
