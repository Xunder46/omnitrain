# Evidence — plan 149 PR 2 (the wrist rule and rest labels)

Companion to `2026-11-12-149b-planned-amount-wrist-rule-plan.md`. Implementers fill the red→green tables per phase; the reviewer re-runs every grep row below.

## Baselines

- `swift test` in `watch/watchos`: compiles the whole package; run the focused filters first (`--filter WatchRestLabelsTests`, `--filter WatchRestNextHoldTests`, `--filter WatchPlannedSetsTests`), then the full package once per phase. The watch app target itself needs `xcodebuild`, which only the governor runs.
- `flutter analyze`: **181 issues** at the PR 1 baseline — PR 2 predicts **no Dart change**; record "not run, no Dart change" per phase unless a Dart file actually changed.
- `flutter test`: not in this PR's loop for the same reason.
- Uncommitted neighbours: plans 144/145/146 and their suites may be red for reasons outside this plan; a failure there is compared against their own state, never "fixed" here.
- PR 1's committed state at planning time: `03e2433c` (the wire: `plannedEfforts` schema-declared, phone-projected, adoption-seeded; Dart fixtures 182 passed; full suite 7452 passed — see the parent plan's evidence file).

## Planner research table (settled with file:line, this run 2026-11-12)

| Question | Answer | Evidence |
|---|---|---|
| Where the wrist reads `plannedSets` today (the layer PR 2 extends) | `deriveRestLabels`'s slot loop reads the count off the slot map | `WatchRestLabels.swift:98` (`planned:`), done rule `:62` (`isDone`), move line `:63-66` (`nextLabel`), stay branches `:104-124` |
| The state layer's set-only gates | `plannedSets` getter kind-gated; `setCaption`, `setsHeld`, planned `initialValue` all set-only | `WatchLoggingState.swift:334` (`setCaption`), `:642-650` (`effortKind`), `:698-707` (`plannedSets`), `:709-715` (`setsHeld`), `:857` (initialValue) |
| The round stay-line's construction | `restLabels` builds `nextRound` unconditionally for a round effort from `roundsLabel`/`nextRoundNumber` | `WatchLoggingState.swift:533-548` (`restLabels`, `singular` at :541-543), `:652-658` (`roundsLabel`), `:661-669` (`nextRoundNumber`) |
| Every other effort/done counter (unchanged) | Kind-agnostic counts of `WatchObservationKind.efforts` | `grep "WatchObservationKind.efforts"` → `WatchMenu.swift:263-267`, `WatchWorkoutSummary.swift:76,142`, `WatchSessionEngine.swift:2238`, `WatchEffortRating.swift:181`, `WatchSensorSummaries.swift:316` |
| Rest ping / Health | Neither reads labels or plans | `WatchRestPing.swift:42-55`, `WatchRestPingScheduler.swift`; `WatchPlatformWorkout.swift`, `WatchWorkoutSummary.heartRateNote :94` |
| Dart twin | None — PR 2 is Swift-only | grep `deriveRestLabels\|WatchRestLabelCopy\|nextSlotId` over `lib/` and `test/` → **zero matches** (re-checked this run) |
| PR 1's committed wire the wrist will read | `plannedEfforts` (integer ≥ 1) on non-set slots only, schema-declared, never beside `plannedSets` | parent plan D-14901..D-14906; `envelope.schema.json` `$defs.sessionExercise`; commit `03e2433c` |

## Red→green tables (implementers fill in)

### Phase 1 (the pure rule)

| Scenario | Test | Red | Green |
|---|---|---|---|
| S-14920..S-14928 (pure halves) | `WatchRestLabelsTests.swift`, group `S-14920 the wrist counts each kind against its own plan` — `testS14920APlannedHoldStaysUntilItsPlanThenNamesTheNext`, `testS14921APlannedRoundStaysWithItsCountAndMovesWhenMet`, `testS14922APlannedTimedEffortStaysWithItsIntervalCount`, `testS14923ASetSlotIgnoresPlannedEfforts`, `testS14923ADrillSlotIgnoresPlannedSets`, `testS14924AFourthHoldIsAcceptedAndNeverReadsPastItsPlan`, `testS14925OutOfOrderCountingKeysOnTheSlotId`, `testS14926NoPlannedAmountKeepsTodaysRule`, `testS14928APlanOfOneBehavesAsTheOneEffortRule` | `prove-red HEAD swift-test --filter WatchRestLabelsTests` → **RED AT HEAD (exit 1)** but only as a compile error (`extra argument 'roundNoun' in call`), which proves nothing. Mutation instead: `plannedEfforts:` read `: 0  // MUTATION` → **Executed 28 tests, with 20 failures** (S-14920, S-14921, S-14922, S-14924, S-14925 red at their plan-count assertions; S-14923's pair, S-14926 and S-14928 green by design). Original line restored exactly. | `Executed 28 tests, with 0 failures` |

### Phase 2 (the state layer and the round gate)

| Scenario | Test | Red | Green |
|---|---|---|---|
| S-14921 (state half) | `WatchRestNextHoldTests.a planned round moves on when its plan is met` (`testS14921APlannedRoundMovesOnWhenItsPlanIsMet`) | prove-red HEAD: `("Next: Period 2") is not equal to ("Next: Period 2 of 3")`, then `("Next: Period 4") is not equal to ("Next: Bench · Set 1 of 2")` | green |
| S-14924 (state half) | same file, `a fourth hold is accepted` (`testS14924AFourthPlannedHoldIsAccepted`) | prove-red HEAD: `("Next: Wall Sit") is not equal to ("Next: Wall Sit · Hold 1 of 2")` | green |
| S-14925 (state half) | same file, `a planned ladder counts out of order per slot` (`testS14925APlannedLadderCountsOutOfOrderPerSlot`) | prove-red HEAD: `("Next: Plank") is not equal to ("Next: Hold 2 of 2")`, `XCTAssertNil failed: "B"` | green |
| S-14926 | same file, `no plan keeps today's rule` (`testS14926NoPlanKeepsTodaysRule`) | green at HEAD **by design** (preserved behaviour; the file's existing cases are its world) | green |
| S-14927 | same file, `the same frame twice changes nothing` (`testS14927TheSameFrameAppliedTwiceChangesNothing`) | prove-red HEAD: `("Next: Wall Sit") is not equal to ("Next: Hold 2 of 3")` | green |
| S-14923 (both gates, state level) | `WatchPlannedSetsTests.testS14923ASetSlotIgnoresPlannedEfforts`, `testS14923ADrillSlotIgnoresPlannedSets` | green at HEAD by design; proven by mutation: both plan reads ungated + the stay branch admitting a planned non-set (`me.planned > 0 && me.kind != set`, inner `max(...)`) → **Executed 14 tests, with 3 failures**: `testS14923ASetSlotIgnoresPlannedEfforts` (`("Nothing planned next") is not equal to ("Next: Set 2 of 2")`) and `testS14923ADrillSlotIgnoresPlannedSets` (`("Next: Hold 2 of 2") is not equal to ("Next: Wall Sit")`, `XCTAssertNil failed: "sx-wall"`). All four mutation lines restored exactly. | `Executed 14 tests, with 0 failures` |

Prove-red verdict line (state half):

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```

### Phase 3 (docs)

| Check | Command / grep | Result |
|---|---|---|
| Pager doc's stale sentence dead | `grep "does not read it yet" docs/` → zero live matches (plan files are historical artefacts) | only `docs/plans/2026-11-12-149b-…-plan.md` and its `.evidence.md` mention the phrase; `docs/state_management/watch_surface_wrist_pager.md` rewritten |
| Consumer pages name the wrist half | `grep "plannedEfforts" docs/` → `watch_session_sync.md`, `what_does_not_sync.md`, `watch_surface_wrist_pager.md` each carry the wrist-reading clause | all four live pages (incl. `state_management/watch_surface_wrist_logging.md`) state the kind-aware rule with the guarding test names |

### PR 2 — final run log

- `swift-test --filter WatchRest` (the three rest suites plus the ping/surface neighbours): **93 tests, 0 failures**.
- `swift-test --filter WatchRestNextHoldTests`: **13 tests, 0 failures**; `--filter WatchPlannedSetsTests`: **14 tests, 0 failures**; `--filter WatchRestLabelsTests`: **28 tests, 0 failures**.
- Full package: **Executed 1381 tests, with 0 failures (0 unexpected)** (`swift-test` over `watch/watchos`, 2026-11-12 16:02).
- `flutter analyze`: **not run, no Dart change** (PR 2 is Swift and docs only). `flutter test test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart` (the docs ceiling and the untouched contract): **195 tests, all passed**.
- Invariant grep: `import .*hive_workout_repository` over `lib/` → `lib/main.dart` only (the composition root); nothing under `lib/state`, `lib/features`, `lib/widgets`, `lib/core`.
- Diff footprint: 2 Swift sources (+128), 3 Swift test files (+631), 4 docs, the plan and this evidence file (864 insertions / 71 deletions in total). `.claude/crew.md` shows 2 uncommitted lines that this run did not touch.

