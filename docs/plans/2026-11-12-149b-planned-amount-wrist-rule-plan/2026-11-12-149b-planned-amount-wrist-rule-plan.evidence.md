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
| S-14920..S-14928 (pure halves) | `WatchRestLabelsTests.swift`, group `S-14920 the wrist counts each kind against its own plan` | | |

### Phase 2 (the state layer and the round gate)

| Scenario | Test | Red | Green |
|---|---|---|---|
| S-14921 (state half) | `WatchRestNextHoldTests.swift`, `a planned round moves on when its plan is met` | | |
| S-14924 (state half) | same file, `a fourth hold is accepted` | | |
| S-14925 (state half) | same file, `a planned ladder counts out of order per slot` | | |
| S-14927 | same file, `the same frame twice changes nothing` | | |
| S-14923 (both gates, state level) | `WatchPlannedSetsTests.swift`, two new methods in the S-3631/S-3632 group | | |

### Phase 3 (docs)

| Check | Command / grep | Result |
|---|---|---|
| Pager doc's stale sentence dead | `grep "does not read it yet" docs/` → zero live matches (plan files are historical artefacts) | |
| Consumer pages name the wrist half | `grep "plannedEfforts" docs/` → `watch_session_sync.md`, `what_does_not_sync.md`, `watch_surface_wrist_pager.md` each carry the wrist-reading clause | |

### PR 2 — final run log

- (implementer: paste the focused-filter counts, the full-package count, and any `flutter analyze` run with its issue count vs the 181 baseline)
