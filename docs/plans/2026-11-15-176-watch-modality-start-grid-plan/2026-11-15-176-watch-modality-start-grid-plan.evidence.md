# Plan 176 — the watchOS modality start grid: execution evidence

Plan: `2026-11-15-176-watch-modality-start-grid-plan.md`.
Phase 1 complete (run 1); Phase 2 first landed empty-session-shaped (run 1, Blocked at item 2) and
was reworked to D-17608/D-17609 in run 2; Phases 3 and 4 complete in run 2. One unpredicted
dependent is red and needs a re-plan (see "Run 2 — the unpredicted dependent").

## Baseline (before this run)

| Check | Baseline |
|---|---|
| `swift test` (watch package) | 1477 tests, 0 failures (brief/plan baseline). Observed after this run: 1495 — this run's 13 new tests plus whatever plan 177's uncommitted `WatchDiagnosticsSourceTests` edits add in the same working tree |
| `flutter test` (full) | green at HEAD `62480d1`; re-run below after this run's one new test file |
| `flutter analyze` | 181 issues (all pre-existing); re-run below |

## Phase 1 — contract, constants, parity tests

Files: `watch/contract/watch_modality_start_contract.json`,
`watch/watchos/Sources/WatchSessionEngine/WatchModalityStart.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift`,
`test/watch_modality_start_contract_test.dart`.

| Run | Command | Result |
|---|---|---|
| Swift parity | `gateway.sh swift-test --filter WatchModalityStartContractTests` | **Executed 5 tests, with 0 failures** |
| Dart parity | `gateway.sh test test/watch_modality_start_contract_test.dart` | **+4: All tests passed!** |

### Phase 1 mutation (the red these tests would catch)

Every symbol is new, so HEAD cannot compile the new files: a red run would prove only a
build failure. Proved instead by mutating the shared contract, which is what both suites read:

Original line, `watch/contract/watch_modality_start_contract.json` (cardio_endurance row):

```json
      "hex": "#43A047"
```

Mutation: `"hex": "#43A048"`.

- Swift: `testS17602TheCellsAreTheContractsRowsInOrder` **failed** —
  `XCTAssertEqual failed: ("["#43A047", "#5B9BD5", "#E63946", …`) — *Executed 5 tests, with 1 failure*.
- Dart: `S-17602 every row wears the phone's own ModalityColors hex` **failed** —
  `Expected: '#43A048' / Actual: '#43A047'` — *+3 -1: Some tests failed*.

Restored the exact original line; both suites green again (counts above). The Dart half also
fails if a phone `ModalityColors` token moves without the contract following, which is the
parity the plan asks for.

## Phase 2 — start path, workout-open rule, behaviour tests

### Landed and green

| Item | Files | Run |
|---|---|---|
| 1 — `startModalityWorkout(_:)` | `WatchStartPaths.swift` (+15 lines, one method) | compiled by every run below |
| 3 — S-17604/5/6 behaviour tests | `WatchModalityStartTests.swift` (new, 6 tests) | `--filter WatchModalityStartTests`: **Executed 6 tests, with 0 failures** |
| 5 — S-17610 pin | `WatchSessionStartPathsTests.swift` (+2 tests) | `--filter testS17610`: **Executed 2 tests, with 0 failures** |

Full package after the rollback below: **Executed 1495 tests, with 0 failures (0 unexpected) in
41.984 s**.

### Phase 2 mutation 1 — the modality is what the start passes on

Original, `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`:

```swift
        await engine.createSession(modality: modality)
```

Mutation: `await engine.createSession(modality: nil)`.

`--filter WatchModalityStartTests`: **Executed 6 tests, with 8 failures** — S-17604's modality
assertion (`("nil") is not equal to ("Optional("cardio_endurance")")`), its per-cell arm (four
failures, one per cell), S-17605's kept-modality assertion, and S-17606's next-start arm.
Restored the exact original; green again (6/6).

### Phase 2 mutation 2 — the S-17610 pin (fill-in-place)

Original, `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, in `startFromRoutine`:

```swift
            held.exercises.isEmpty
        {
            var filled = held
```

Mutation: `held.exercises.isEmpty, held.modality == nil`.

`--filter testS17610`: `testS17610ARoutineFillingAModalitySessionKeepsItsModality` **failed** —
`XCTAssertEqual failed: ("0") is not equal to ("3") - S-17610 and the ladder is the routine's own`
(the routine no longer fills the live session, so no slots land). The no-session arm stayed green,
as it must. Restored the exact original; both green again (2/2).

### Blocked item 2 — the D-17603 workout-open guard

The plan's guard, as written, in `WatchWorkoutLifecycle.action`:

```swift
        if session.source == "watch", session.exercises.isEmpty { return .none }
```

Full `swift test` with it in place: **14 pre-existing tests failed** — `WatchWorkoutCoordinatorTests`
(18 assertion failures), `WatchFitnessFollowsSessionTests`, `WatchContinueRecoveredWorkoutTests`,
`WatchWorkoutAdoptBeforeRestoreTests`, `WatchOpenFailureTests`, `WatchMenuTests`. Cause:
`engine.createSession(modality:)` defaults `source: "watch"` with `exercises: []`, so the guard is
true of every session the existing open-tests build (`testS1500OpensForAnActiveSession`,
`testS89_1*`, `testS14005*`, `testS15005*`, `testS15006*`, `testS15102`, `testS15110`,
`testS17109AnEmptyEndBehavesAsADiscard`, …).

Those six files are outside the phase's Predicted Files, so the guard (and the one doc-comment
sentence it added) was reverted exactly: `gateway.sh git-diff --stat -- …/WatchPlatformWorkout.swift`
now lists nothing, and the full package is green (1495/0) as quoted above. Item 4 (S-17607/8/11)
was not written: it pins the missing rule.

## Final suites (run 1, before the amendment)

| Check | Command | Result |
|---|---|---|
| Swift package | `gateway.sh swift-test` | **Executed 1495 tests, with 0 failures (0 unexpected) in 41.984 s** |
| Dart, full | `gateway.sh test` | **+7673 ~4: All tests passed!** (4 pre-existing skips) |
| Dart, parity file | `gateway.sh test test/watch_modality_start_contract_test.dart` | **+4: All tests passed!** |
| UI standards | `gateway.sh test test/ui_standards_contract_test.dart` | **+41: All tests passed!** |
| Analyzer | `gateway.sh lint` | **181 issues found** — the plan's baseline, unchanged; none in the files this run touched |

## Invariants and standards

- No `import … hive_workout_repository` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core`:
  this run touched no Dart source under `lib/` at all (one new test file under `test/`).
- `test/ui_standards_contract_test.dart`: **41 passed** (above); no UI file in `lib/` changed this run.
- No model, seed, `scripts/sqlite_*.sql` or contract-schema change, so `test/db_seed_test.dart`
  and the sync-protocol schema tests are untouched by this run.

## Run 2 — Phase 2 reworked to D-17608/D-17609 (pick first, then create)

Files: `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` (Path 3 replaced),
`watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartTests.swift` (rewritten),
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` (two call sites).

| Run | Command | Result |
|---|---|---|
| Red first (S-17604/5/6/8, amended shapes) | `gateway.sh swift-test --filter WatchModalityStartTests` | **compile failure** — no `beginModalityStart`, `pendingModalityStart`, `cancelModalityStart`, `startModalityWorkout(_:with:)`; every symbol is new, so the red could only be a build error |
| Green | same | **Executed 11 tests, with 0 failures (0 unexpected)** |
| S-17610 call sites | `gateway.sh swift-test --filter testS17610` | **Executed 2 tests, with 0 failures** (`await harness.engine.createSession(modality: "cardio_endurance")` replaces the removed empty-session method) |

The ended-session arm of the old S-17606 suite was dropped with the empty-session design: nothing
exists to cancel before a pick, so "cancel leaves no row and no frame"
(`testS17606CancelLeavesNoSessionRowAndNoFrame`) is the whole of it.

### Run 2 mutation — the pick is what creates the session

Original, `WatchStartPaths.swift`, `startModalityWorkout(_:with:)`:

```swift
        return await engine.createSession(modality: modality, exercises: [exercise.toSlot(...)])
```

Mutation: an early `return await engine.createSession(modality: modality)` (the old empty-session
behaviour) inserted before it, with `pendingModalityStart = nil` ahead of it; Swift warned only
"code after 'return' will never be executed".

`--filter WatchModalityStartTests`: **Executed 11 tests, with 12 failures** — the pick's exercise
missing (S-17605), the Health kind falling back to the modality default (S-17607's two arms), the
activity type walking→running, and the abandoned-session arm (S-17606). Restored the exact
original; green again (11/0).

## Run 2 — Phase 3: the grid view and its source guards

Files: `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` (+9 guards).

| Run | Command | Result |
|---|---|---|
| Green after the grid | `gateway.sh swift-test --filter WatchPlannedSurfaceSourceTests` | **Executed 15 tests, with 0 failures** |
| Prove red | `gateway.sh prove-red HEAD swift-test --filter WatchPlannedSurfaceSourceTests -- <test file>` | **RED AT HEAD (exit 1), 10 failures** — every guard failed for its own reason (no grid in the source, no `startModality`, no start-mode parameter, the `Free workout` button still present); green at the working tree |

`prove-red` first crashed the runner instead: a guard force-unwrapped a missing symbol
("Fatal error: Unexpectedly found nil"), which kills the xctest process and proves nothing. Rewritten
with `try XCTUnwrap` so each guard fails cleanly, then re-run: the verdict above.

## Run 2 — Phase 4: docs

`docs/state_management/watch_surface_wrist.md`: a new grid paragraph at the top of "The wrist's start
surface" (order, contract, tap creates nothing, the pick creates the session, the Health typing, what
the surface lost, the test names), "Today's planned workout is the first control **below the grid**",
and the cancel paragraph now covers the start mode.

`docs/watch-app-qa-wrist-logging.md`: step 45 added (grid on the wrist, VoiceOver, tap-then-dismiss,
the pick's session, Fitness typing per cell); steps 1, 14, 20, 29, 38 and 43 reworded off the button
that no longer exists. Every behavioural sentence names an existing test.

## Run 2 — the unpredicted dependent

`WatchNutritionWiringSourceTests.testS7205NutritionSitsRightUnderFreeWorkout` (plan 72) pins
`Button("Free workout")` in `WatchStartView.swift` as the anchor the Nutrition button sits under. The
plan's D-17608 and S-17612 remove that button, so the anchor is `nil`:

```
WatchNutritionWiringSourceTests.swift:219: error: … testS7205NutritionSitsRightUnderFreeWorkout :
XCTUnwrap failed: expected non-nil value of type "Int" - S-7205 the start screen carries the Free
workout button
```

That file is outside this phase's Predicted Files and belongs to another plan, so it was not edited.
`WatchPhoneProblemWiringSourceTests.testS9004TheStartSurfaceSaysWhenARoutineVanished` (S-9004's
three-site count) went red for the same reason and was fixed inside this plan's file by dropping the
extra `routineNotice = nil` from `startModality(_:)`, not by touching the test.

## Run 2 — final suites

| Check | Command | Result |
|---|---|---|
| Swift package | `gateway.sh swift-test` | **Executed 1509 tests, with 1 failure (0 unexpected) in 38.321 s** — the S-7205 pin above, nothing else |
| Dart, full | `gateway.sh test` | **+7673 ~4: All tests passed!** |
| Analyzer | `gateway.sh lint` | **181 issues found** — the plan's baseline, unchanged |
| Invariant grep | `import .*hive_workout_repository` under `lib/` | only `lib/main.dart` (the composition root); nothing in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` |
