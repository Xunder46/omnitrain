# Evidence — watch-auto-sync PR 2 (`17b`)

Plan: `2026-10-06-17b-watch-auto-sync-pr2-plan.md`. Implementers and the reviewer paste real command
output here; the plan holds no evidence.

## Baselines (before this PR, at the branch point `a45dd49`)

| Command | Result | Date |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | 4013 passing, ~1 skipped, 0 failures | 2026-10-06 (17a's evidence) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 315 passing, 0 failures | 2026-10-06 |

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| 1 | gateway `test test/watch_session_adoption_bridge_test.dart test/watch_session_adoption_build_notify_test.dart test/watch_session_rest_timer_append_test.dart` | `+23: All tests passed!` (0 failed) | the first run of the same three files was `+14 -4` — see below |
| 1 | gateway `test test/watch_session_adoption_bridge_test.dart test/watch_session_adoption_build_notify_test.dart test/watch_session_rest_timer_append_test.dart test/watch_session_start_test.dart test/docs_indexing_contract_test.dart` | 64 passed, 0 failed | the plan's Done-Criteria set, after the docs paragraph landed |
| 1 | gateway `test` (full) | 4020 passed, ~1 skipped, 0 failed | baseline 4013 (~1 skipped) + 7 new Dart tests |
| 1 | gateway `lint` | 196 issues, 0 errors | same count as the baseline; `grep` over the log finds none in a touched file |
| 1 | gateway `swift-test` | not run — no Swift file changed | `git diff --stat`: 3 `lib/` files, 3 test files, 1 doc |

## Phase 1 — the phone accepts the wrist's additions (S-102…S-106, S-110, S-111)

Steps 1–10 done, plus the docs sentence in `docs/watch_session_sync.md`. `appendSessionSlots`
(`lib/state/workout/session_core_entry.dart:77`, exposed by `lib/state/workout/workout_state.dart`)
writes through `WorkoutRepository` and takes no reload path, so no timer is touched; `_reconcile` and
`_everSeen` live in `lib/state/watch/watch_session_adoption_bridge.dart`, and `consider`'s
`alreadyHeld` branch calls them only for a non-empty result.

One decision the plan left to the implementation (D-92's "never reorder"): an addition takes the
phone's **next free** `orderIndex` — its own highest + 1, incremented per addition — not the snapshot's
index. Taking the snapshot's index made a mid-ladder addition tie with an existing one and sort into
the middle of the ladder (`importedEfforts` read `['sl-1','sl-9','sl-2']`, which D-92 forbids).

### Red first — the first targeted run, before the last three defects were fixed

`+14 -4: Some tests failed.` The four failures, each with its cause:

| Red | Cause | Fix |
|---|---|---|
| `a second snapshot of the session the phone holds does not rewrite it` saw `['sl-1','sl-9','sl-2']` with order `[0,1,2]` | `_reconcile` took the snapshot's `orderIndex`, so the mid-ladder addition tied with an existing slot and sorted into the middle | additions take the phone's next free index (`nextOrderIndex`) |
| `test/watch_session_adoption_build_notify_test.dart` did not compile: `'SessionSegment' isn't a type` | the new S-103/S-111 helpers name `SegmentEffort` and the file did not import `package:omnitrain/data/models/models.dart` | the import was added |
| S-105 and S-106 hit a null-check on `(await phone.bridge.projectSession(null))!` | the fixture's capabilities were empty, so `_slotFor` returned `null` for every effort and `projectSession` found no slots. `test/helpers/repository_harness.dart:168 seedExercise` passes `capabilities` to the `Exercise` constructor, which `MockWorkoutRepository.createExercise` drops — capabilities live in the separate `_exerciseCapabilities` store that `getExerciseById` reads back | the bridge test's `_repository()` now calls `setExerciseCapabilities` for both seeded exercises, the way `test/helpers/watch_capture_import_harness.dart:85` does |

This is a harness defect in an existing helper, not a behaviour of the change under test; the helper
was **not** edited (the harness is shared with other files, and fixing it there would change them).

### Which new tests are red against the code before Phase 1, and which need a mutation

Before this change, `consider`'s `alreadyHeld` branch returned without touching anything, so every
scenario whose outcome is "the ladder grows, once, and something is notified" is red on the old code:
S-102, S-110 and S-111 — mutation (a) reproduces exactly that state, and all three go red under it.
The other four assert that something does *not* happen — a converged ladder changes nothing (S-104), a
renamed slot survives (S-105), a foreign session is refused (S-106), a removed slot does not come back
(S-103) — and each passes trivially on code that never appends. Their red is the mutation the brief
names for each: (e′) for S-104, (d) for S-105, (f) for S-106, and (b) for S-103.

### Mutations — every new guard, shown red, then restored exactly

Each mutation was applied alone against the three Phase 1 test files (`+23` green otherwise), and the
exact original line was restored and the files re-run green after each. No mutation was left applied.

| # | Mutation (original → mutant) | What went red | Observed |
|---|---|---|---|
| a | the `_reconcile` call site: `if (additions.isNotEmpty) {` → `if (false && additions.isNotEmpty) {` | S-110, S-102, `a second snapshot …`, S-103, S-111 | `+18 -5: Some tests failed.` |
| b | the ever-seen half: `if (held.contains(slotId) \|\| !seen.add(slotId)) continue;` → `if (held.contains(slotId)) continue;` | S-103 (its stale-copy half) | 1 red |
| c | `appendSessionSlots` reloads: `_notify();` → `await loadSessionData();` | S-110, S-102 | `+15 -2`, `notifications 3 != 1` |
| d | the match key: `final slotId = slot['sessionExerciseId'];` → `final slotId = slot['name'];` | S-105 and three more | `+12 -4` |
| e | the ladder half: `if (held.contains(slotId) \|\| !seen.add(slotId)) continue;` → `if (!seen.add(slotId)) continue;` | **nothing** — S-104 stays green | the `held.contains(slotId)` half is redundant: `seen.addAll(held)` runs before the loop, so `seen` already holds the phone's own ids |
| e′ | the whole guard line deleted (`-      if (held.contains(slotId) \|\| !seen.add(slotId)) continue;`) | S-104 — the phone's own efforts were re-ordered to 2/3 | 1 red |
| f | S-106 needs two lines at once: `_reconcile`/`appendSessionSlots` called **before** the `refusedConflict` guard, **and** `appendSessionSlots`'s `if (efforts.isEmpty \|\| _currentSession?.id != sessionId) return;` reduced to `if (efforts.isEmpty) return;` | S-106 | 1 red, `Expected: <0> Actual: <2>` |

Reading (e) and (e′) together: the guard as a whole is what S-104 proves, and either single half
still covers the case (the other half plus `_adopt`'s `_everSeen` seeding). (b) shows the ever-seen
half alone is what keeps a removed slot from coming back; the `held.contains` half adds no
independently observable behaviour — it is kept because it states the rule directly and the pair is
cheaper than the reasoning that they are equivalent. Mutation (f) is two lines because the single-line
variant is green: `appendSessionSlots` refuses a foreign session id on its own.

### The test the plan predicted

`test/watch_session_adoption_bridge_test.dart` — `a second snapshot of the session the phone holds
does not rewrite it` — was the file the impact table (row `WatchSessionAdoptionBridge.consider`
`alreadyHeld`) and Predicted Files both name. Its ladder assertions now read `['sl-1','sl-2','sl-9']`
with order `[0,1,2]`: the frame it sends carries a slot the phone has never seen, which D-92 appends,
and every assertion about the phone's own two slots is unchanged. No other existing test in the repo
changed, and none went red for an unpredicted reason.

### Residue sweeps

`grep` for each mutant spelling under `lib/` and `test/` finds no residue: `additionsM`, `false &&`,
`slot\['name'\] ??`, and no deleted guard line. `git diff --stat` on the phase shows the 3 production
files, the 3 test files and `docs/watch_session_sync.md`, and nothing else.

## Phase 2A — the wrist announces its own session (Swift half: steps 1–5, 7, 8, 9)

Base `0bd8c15`. Baseline for this run: `swift-test` **315 passed / 0 failed**, `lint` **196 issues /
0 errors** (both 2026-10-06). Steps 6, 10 and 11 — the Dart twin, `test/watch_session_engine_test.dart`
and the two docs — are part B and were **not started**: no `lib/` file and no doc changed here.

`WatchSessionEngine.swift` (the only production file, +55 lines): a private `emitSnapshot()` beside
`emitLifecycle`; `createSession` emits the snapshot right after `emitLifecycle(live, state: .started)`;
`insertExercise(_:atIndex:moveTo:announce:)` gained `announce: Bool = true`, moves `session.revision`
by 1 on a wrist add, and emits when announcing; `applyExercisePush` passes `announce: false`;
`transitionTo` gained `revision: Int? = nil` and writes `revision ?? session.revision` (preserve).
`applySnapshot`, `applyStructureChange` and `applyLifecycle` were not touched — they write their rows
through `storeSessionRow` and never call `transitionTo`, which is why step 4 needed no edit. Step 5 was
verified and left alone: `startFromRoutine` (`WatchStartPaths.swift:344`) and `startFreeWorkout`
(`:356`) both return `engine.createSession(…)`, and `addExerciseToSession` (`:366`) calls
`insertExercise` (`:370`) with the default `announce`.

### Red first, before implementation

| Command | Result | Log |
|---|---|---|
| gateway `swift-test --filter 'S10[014]'` (main checkout, before the change) | `Executed 6 tests, with 7 failures` — S-100 6 failures, S-101 1, S-104 3 tests green (they assert silence, which is true at base); the 6th test is the pre-existing `testS104SyncWithNoSessionAsksForASnapshot` | `swift-test-20261007-003922-56579.log` |
| gateway `prove-red 0bd8c15 swift-test --filter testS100 -- <engine test file>` | `gateway: prove-red: RED AT 0bd8c15` — 1 test, 6 failures at `WatchSessionEngineTests.swift:1267/:1277/:1282–:1285` | `swift-test-20261007-003932-56921.log` |
| gateway `prove-red 0bd8c15 swift-test --filter testS101 -- <engine test file>` | `gateway: prove-red: RED AT 0bd8c15` — 1 test, 1 failure, `:1298 XCTUnwrap failed: expected non-nil value of type "Dictionary<String, Any>"` | `swift-test-20261007-003932-56922.log` |
| gateway `prove-red 0bd8c15 swift-test --filter testS100A -- <start-path test file>` | `gateway: prove-red: RED AT 0bd8c15` — 2 tests, 4 failures: `:518/:520` and `:542/:543`, `("[session_lifecycle"]") is not equal to ("["session_lifecycle", "session_snapshot"]")` | `swift-test-20261007-005754-64859.log` |

The first `prove-red` attempt for S-100 was **not** a valid red: `error: call can throw but is not
marked with 'try'` at the test's own `await engine.applyMessage(…)` (log
`swift-test-20261007-003759-56164.log`). That is a test defect, fixed in the test only by adding `try`;
the re-run above is the red that counts.

At base the S-100 failures are the whole snapshot: the frame list is missing it (`:1267`), both
messages carry the same `messageId` (`:1277`, `msg-rec-1`), and the payload reads empty — ladder `[]`
vs `["sx-a","sx-b"]`, status `nil`, `currentIndex`/`currentExerciseIndex` `nil` (`:1282–:1285`).

### Mutations — each guard shown red, then restored exactly

The four the brief names, plus two for the phone-originated paths it does not (S-104's other halves).
Every mutation was applied alone, then reverted to the exact original; no mutation was left applied.

| # | Mutation (original → mutant) | Observed | Log |
|---|---|---|---|
| a | `createSession`: the added `emitSnapshot()` call removed | S-100, 1 test / 6 failures at `:1267–:1285`, frame list back to `["session_lifecycle"]` | `swift-test-20261007-004251-60392.log` |
| b | `applyExercisePush`: `announce: false` → `announce: true` | S-104 push, `:1369 XCTAssertTrue failed - D-91 an \`exercise_push\` applies with \`announce: false\`` | `swift-test-20261007-004730-61825.log` |
| c | `insertExercise`: `revision: announce ? session.revision + 1 : nil` → `revision: nil` | S-101, `:1313 XCTAssertGreaterThan failed: ("0") is not greater than ("0") - D-101 a wrist-originated structural change moves the revision` | `swift-test-20261007-004834-62193.log` |
| d | `createSession`: the snapshot emitted **before** the lifecycle | S-100, 1 test / 5 failures, `:1267 ("[Optional("session_snapshot"), Optional("session_lifecycle")]") is not equal to (…)` | `swift-test-20261007-004427-60992.log` |
| e | `applyStructureChange`: an `emitSnapshot()` added | S-104 structure change, `:1348 XCTAssertTrue failed - D-91 the phone is the structure authority` | `swift-test-20261007-004908-62430.log` |
| f | `applySnapshot`: an `emitSnapshot()` added | S-104 snapshot, `:1394 XCTAssertTrue failed - D-91 a snapshot is answered with silence` | `swift-test-20261007-004948-62668.log` |

Restore checks: the targeted re-runs saved at `swift-test-20261007-004341-60730.log` (after a),
`…-004827-62080.log` (after b) and `…-004859-62319.log` (after c) are green, and the final full suite
below is green with all six mutants absent — `git-diff` carries only the five intended files. (d) is
the mutation that pins the order D-91 states, and it is the only one that leaves the snapshot in place
and still turns S-100 red; (e) and (f) are the two phone-originated paths S-104's other two tests own.

### Green

| Command | Result | Log |
|---|---|---|
| gateway `swift-test` (targeted, after implementing) | `Executed 320 tests, with 0 failures` (5 new engine tests) | `swift-test-20261007-004241-57899.log` |
| gateway `swift-test` (full, final) | `Executed 322 tests, with 0 failures (0 unexpected)` — baseline 315 + 5 engine + 2 start-path tests | `swift-test-20261007-005812-65129.log` |
| gateway `lint` | `196 issues found. (ran in 2.4s)`, 0 errors — the baseline count; no issue names a touched file (only `.swift` files changed, which `flutter analyze` does not read) | `lint-20261007-005834-65364.log` |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

### Footprint and residue

`gateway git-diff --stat`: `WatchSessionEngine.swift` +55, `WatchEmitForwarderTests.swift` ±5,
`WatchSensorRecordingTests.swift` ±6, `WatchSessionEngineTests.swift` +172,
`WatchSessionStartPathsTests.swift` +44 — 5 files, 268 insertions, 14 deletions, nothing else.

Three pre-existing assertions were updated because D-91 changes the frames a start emits, and each was
checked to be a frame-list or frame-count assertion rather than a behaviour one:
`WatchSessionEngineTests.swift:225` (the S-003 type list now reads
`["session_lifecycle","session_snapshot","observations_up"×3]`), `WatchEmitForwarderTests.expectedFrames`
and `WatchSensorRecordingTests.swift:852/:858` (emitted count 1 → 2). Every other pre-existing test is
type-filtered, calls `clearEmitted()`, or counts the orchestrator's own sends, which the new frame does
not join — the full suite is the proof: no test outside these three changed or went red.
