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
| 2B | gateway `prove-red e88a491 test test/watch_session_engine_test.dart` | `RED AT e88a491` — 31 executed, 28 passed / 3 failed | S-003, S-100, S-101; S-104 is proven by mutation instead (it asserts silence) |
| 2B | gateway `test test/watch_session_engine_test.dart` (final state) | `+31: All tests passed!` (0 failed) | 28 pre-existing + 3 new tests |
| 2B | gateway `test` (full, final) | 4023 passed, ~1 skipped, 0 failed | part A's 4020 + the 3 new Dart tests |
| 2B | gateway `lint` | 196 issues, 0 errors | baseline count; `grep` over the log finds none in a touched file |
| 2B | gateway `swift-test` | not run — no `.swift` file changed | `git diff --stat` below |

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

## Phase 2B — the Dart twin announces its own session (S-100, S-101, S-104; steps 6, 10, 11)

Base for this part: `e88a491`, which already carries part A's Swift half. This run's baselines are
part A's: full `test` 4020 passed / ~1 skipped / 0 failed, `lint` 196 issues / 0 errors.

`lib/watch/session/watch_session_engine.dart` is the only production file (+39/−4). `createSession`
now returns `_appendSessionRow`'s live row and calls the new `_emitSnapshotIfConformant()` (which sits
beside `_emitLifecycleIfConformant` and catches `on Exception` — `WatchEmissionRejected implements
Exception`, so a bare catch was neither needed nor allowed; an `Error` still escapes).
`insertExercise` gained `announce: bool = true` after `moveTo` and routes its update through
`_transitionTo`, passing `revision: announce ? session.revision + 1 : null` and emitting only when
announcing; `applyExercisePush` passes `announce: false`; `_transitionTo` gained `int? revision` and
writes `revision ?? session.revision`, which preserves on a phone-originated change and moves the
number by 1 on a wrist add (D-101).

Step 11 turned out to need no diff, and that is not an omission: the only caller of
`_emitLifecycleIfConformant` is `_appendSessionRow`, which is already the wrist-authorship path;
`_applySnapshot` and `_applyStructureChange` write their rows without it and never call the new
snapshot helper, which is exactly what keeps the phone's frames silent.

### Red first, before implementation

| Command | Result | Log |
|---|---|---|
| gateway `prove-red e88a491 test test/watch_session_engine_test.dart` | `gateway: prove-red: RED AT e88a491` (exit 1) — 31 executed, 28 passed / 3 failed: S-003 `:452`, S-100 `:1337`, S-101 `:1364` | `test-20261007-013706-83645.log` |

The three base failures, each for the reason the test guards and not a compile or config problem:
S-003's frame list is `['session_lifecycle','observations_up'×3]` with no snapshot;
S-100 reads the same at `:1337` (`Expected: ['session_lifecycle','session_snapshot'] Actual:
['session_lifecycle']`); S-101's `firstWhere` finds no `session_snapshot` at all — `Bad state: No
element` at `:1364`.

**S-104 is green at the base commit, and that is not a broken test:** it asserts *silence* on the
phone's three frame kinds, which is already true at `e88a491`. `prove-red` therefore proves nothing
for it, and it is proven by mutation (b) below instead. Recorded rather than papered over — see A-13.

### Mutations — each guard shown red, then restored exactly

Every mutation was applied alone and then reverted to the exact original; none was left applied, and
the final full suite below is green with all three absent.

| # | Mutation (original → mutant) | Observed | Log |
|---|---|---|---|
| a | `createSession`: the `_emitSnapshotIfConformant()` call removed | S-100, 1 test / 1 failure at `:1337`: `Expected: ['session_lifecycle','session_snapshot'] Actual: ['session_lifecycle']` | `test-20261007-013732-83942.log` |
| b | `applyExercisePush`: `announce: false` → `announce: true` | S-104, 1 test / 1 failure: `Expected: empty` but one `session_snapshot` (`messageId 'msg-snapshot-rec-2'`, `revision: 1`, ladder `['sx-bench','sx-row']`) — the phone's own push echoed back | `test-20261007-013754-84195.log` |
| c | `insertExercise`: `revision: announce ? session.revision + 1 : null` → `revision: null` | S-101, 1 test / 1 failure at `:1387`: `Expected: a value greater than <0> Actual: <0>` | `test-20261007-013808-84396.log` |

(b) is the only proof S-104 has, and it is the one that matters: it shows the second snapshot's
existence, not merely its count, and pins `revision: 1` as the value a wrist *add* moves.

### Green

| Command | Result | Log |
|---|---|---|
| gateway `test test/watch_session_engine_test.dart` (final state) | `+31: All tests passed!` — 28 pre-existing + 3 new | inline (under the 200-line summary threshold) |
| gateway `test` (full, final) | `+4023 ~1: All tests passed!` — 4023 passed, ~1 skipped, 0 failed; part A's 4020 + the 3 new Dart tests | `test-20261007-015346-99046.log` |
| gateway `test` (full, first attempt, before the pinned counts moved) | `+4022 ~1 -1: Some tests failed.` — the one failure is `test/watch_sensor_recording_test.dart`, "Sensor wiring a reading is stored without being sent anywhere", expecting `hasLength(1)` twice | `test-20261007-013822-84597.log` |
| gateway `lint` | `196 issues found. (ran in 3.0s)`, 0 errors — the baseline count; a `grep` over the log for `watch_session_engine` / `watch_sensor_recording` finds nothing | `lint-20261007-014907-97566.log` |
| gateway `swift-test` | not run — no `.swift` file changed | `git diff --stat` below |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

### Blast radius: one pre-existing frame-count assertion

`test/watch_sensor_recording_test.dart` carries two assertions that count the frames a wrist start
emits and pinned `hasLength(1)`; with D-91 the start emits two, so both moved to `hasLength(2)` with
their reasons renamed to D-91. Both are frame-count assertions, no behaviour assertion was touched,
and this mirrors part A's `WatchSensorRecordingTests.swift` (A-11). The brief did not name the file,
so it is logged as A-14.

### Footprint and residue

`gateway git-diff --stat`: `lib/watch/session/watch_session_engine.dart` +39, `test/watch_session_engine_test.dart` +118,
`test/watch_sensor_recording_test.dart` ±8, `docs/watch_session_sync.md` 26, `docs/state_management/watch_surface.md` +15,
the plan +35 and its evidence +83 — 7 files, 305 insertions, 19 deletions, nothing else, and no
untracked file (`git-status` lists the 7 modified files and no scratch). (Those are the whole-tree
numbers at the end of Phase 2B; the Phase 3 section below adds its own files and its own counts.) The test file's diff is
additions only apart from
the S-003 comment and frame-list line, which is how the accidental mid-edit loss of the "Stopping a
timer" group is shown to have left no residue: the file holds exactly its 28 pre-existing tests plus
the 3 new ones, and `+31` is that file's whole run.

## Phase 3 — the push's bounds and the phone's resume trigger (S-112, S-113, S-109; steps 1–8)

Baseline carried into this phase: full `test` `+4023 ~1: All tests passed!` and `lint`
`196 issues found. (ran in 3.0s)`, 0 errors. Five tests are new — S-112, S-113 (two), S-109 (two) —
and the full suite's `+4028` is that baseline plus them.

### No `prove-red` is possible here, so every guard was proven by mutation

`.github/copilot/scripts/macos/gateway.sh prove-red HEAD test …` needs the tests to compile against the code without
the change; at `HEAD` the new `sendTimeout` / `onFailure` constructor parameters, the `WatchResumeSync`
class and `WatchSyncGraph.sync()` do not exist, so the three touched test files fail to compile rather
than fail an assertion — a compile error is not the red the brief asks for. All four guards were
therefore proven by mutation: each was applied alone, the failure observed, the line restored to its
exact original, and the file re-run green. None is left applied, and the full suite below is green
with all four absent.

| # | Mutation (original → mutant) | Observed | Log |
|---|---|---|---|
| a | `flush()`: the `.timeout(_sendTimeout, onTimeout: …)` wrapper removed | S-112 red — "a send that never completes is abandoned and reported, and the change made while it hung still leaves the phone": the joined second flush never returned and the assertion on the single reported `TimeoutException` failed | inline (under the summary threshold) |
| b | `_onChanged` timer callback: `unawaited(flush().catchError(…))` → `unawaited(flush())` | S-113 timer-path red — "an Error from the debounce timer path is reported, not unhandled, and a direct flush still throws it": `Expected: an object with length of <1> / Actual: []` on `reported` | inline (under the summary threshold) |
| c | `WatchResumeSync.didChangeAppLifecycleState`: the `== AppLifecycleState.resumed` guard removed (call for every state) | both S-109 observer tests red — the down-transition half records calls for `inactive`/`hidden`/`paused` | inline (under the summary threshold) |
| d | `WatchSyncGraph.sync()`: `await requestSnapshot(); await sendSnapshot();` (ask before handing over) | S-109 graph red — `Expected: 'session_snapshot' / Actual: <null>`: the wrist is asked first, so the phone's own snapshot is no longer the first frame | inline (under the summary threshold) |

(b) needed the test strengthened first, and that is worth recording: against the mutant the test's
original wait — `_until(reported.isNotEmpty)` — never resolved, because the escaped error goes to the
`runZonedGuarded` handler and never reaches the failure hook, so the suite hung for 30 s instead of
failing. The wait is now `reported.isNotEmpty || unhandled.isNotEmpty` and the `reported` length is
asserted *after* the zone body, which turns the same regression into a fast, meaningful red. The
bounded poll itself (`_until`: 500 × 2 ms, then `fail(reason)`) has no wall-clock threshold — it polls
to a deadline.

### Red first, and the fixture defect that hid it

The two new auto-push tests were red on their first run, but for the wrong reason: the second phone
set was built with `weight: 65`, an `int`, and `session_core_entry.dart:207` casts it with
`as double?`. `addEntry` catches that itself, sets
`WorkoutState.error = "Failed to add entry: type 'int' is not a subtype of type 'double?'"` and writes
no row, so the second change never happened and the tests read as a push defect. Both fixtures now use
`65.0` (A-18). A second, related trap: the pushed frame carries *every* entry the session holds, so
after a wrist set and a phone set `payload['entries']` has two objects — `.single` throws
`Bad state: Too many elements`, and the assertions map the list and use `contains(65.0)` instead.

### Green

| Command | Result | Log |
|---|---|---|
| gateway `test test/watch_session_auto_push_test.dart` | `+25: All tests passed!` — 22 pre-existing + 3 new | inline (under the summary threshold) |
| gateway `test` (the three touched files together, final state) | `+57: All tests passed!` — 57 passed, 0 failed | inline (under the summary threshold) |
| gateway `test` (full, final) | `+4028 ~1: All tests passed!` — 4028 passed, ~1 skipped, 0 failed; the 4023 baseline + the 5 new tests | `test-20261007-021922-20223.log` |
| gateway `lint` | `196 issues found. (ran in 3.0s)`, 0 errors — the baseline count; a `grep` over the log for `watch_session_auto_push`, `watch_sync_wiring`, `watch_resume_sync`, `app.dart` and the three test files finds nothing | `lint-20261007-021856-20030.log` |
| gateway `swift-test` | not run — no `.swift` file changed | `git diff --stat` below |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

### Footprint and residue

`gateway git-diff --stat`: `lib/state/watch/watch_session_auto_push.dart` +60, `lib/state/watch/watch_sync_wiring.dart` +10,
`lib/app.dart` ±15, `lib/main.dart` +3, `test/watch_session_auto_push_test.dart` +226,
`test/watch_session_projection_test.dart` +64, the plan +39 — 7 files, 398 insertions, 19 deletions.
`git-status` additionally lists exactly two untracked files, both intended and both new:
`lib/state/watch/watch_resume_sync.dart` (59 lines) and `test/watch_resume_sync_test.dart`. No scratch
file was created, so none had to be deleted, and every changed file is inside the phase's Predicted
Files. No formatter was run: the edits are hand-written and the diff is the size of the edits.

## Phase 3 fix 1 — the resume sync sends the phone's own session, or nothing (closed fix, 2026-10-07)

Defect (found by the governor behind the green Phase 3 suite): `WatchSyncGraph.sync()` was
`mirror.sync()`, i.e. `sendSnapshot()` = `sendState(state)` — the MIRROR's converged copy. On an idle
resume that copy is `watchSessionPlaceholder` (`s-phone-unjoined`, status `abandoned`), a junk session
a wrist holding nothing would store; and a phone holding its own P while the mirror had converged on a
wrist session X sent X's stale copy. 15-series D-11: every ladder the phone asserts is composed from
the phone's own session via `mirror.projectedSession()`, never the mirror's copy.

Fix (one method, `lib/state/watch/watch_sync_wiring.dart`): `sync()` composes
`mirror.projectedSession()` and sends it only when it is non-null, then always `requestSnapshot()`.
`LiveSessionMirrorState.sync()` is untouched — the debug mains use it. The doc comment now says what
the method sends and why, and names its three tests.

### Red first, before the fix

`gateway test test/watch_session_projection_test.dart --plain-name "S-109"` — 0 passed / 3 failed, each
for its own reason:

| Case | The assertion that failed |
|---|---|
| A | `Expected: 'sess-1' / Actual: 's-phone-unjoined'` — the frame was the placeholder, not the phone's own session |
| B | `Expected: empty / Actual: [ one session_snapshot for 's-phone-unjoined', status 'abandoned' ]` — the junk frame a wrist holding nothing would store |
| C | `Expected: 'sess-1' / Actual: 'bd67cc5b-81b3-4f4e-b56e-0ff081b99585'` (the wrist's session X) — the mirror's converged copy |

### Mutation — restore exactly

`sync()` → `await mirror.sync();` alone. No `prove-red` is possible here: the tests are new to a call
site that does not exist at HEAD. Observed: all three S-109 cases red (`+0 -3`) — A
`s-phone-unjoined`, B the junk snapshot, C the wrist's id. Restored to the exact three-line body and
re-ran green (`+3`); nothing is left applied.

### Green

| Command | Result | Log |
|---|---|---|
| gateway `test test/watch_session_projection_test.dart --plain-name "S-109"` | `+3: All tests passed!` | inline (under the summary threshold) |
| gateway `test` (the three Done-criteria files) | `+59: All tests passed!` — 59 passed, 0 failed | inline (under the summary threshold) |
| gateway `test` (full, final) | `+4030 ~1: All tests passed!` — 4030 passed, ~1 skipped, 0 failed; Phase 3's 4028 + the 2 added S-109 cases | `test-20261007-022843-33000.log` |
| gateway `lint` | `196 issues found. (ran in 1.6s)`, 0 errors — the baseline count; the log has no line for `watch_sync_wiring` or `watch_session_projection` | `lint-20261007-022829-32858.log` |
| gateway `swift-test` | not run — no `.swift` file changed | — |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

Footprint: `lib/state/watch/watch_sync_wiring.dart` +19 and `test/watch_session_projection_test.dart`
(replacing the one S-109 graph test with its three cases) — 2 files. No scratch file was created, so
none had to be deleted, and no formatter was run.

## Phase 4 — the Swift half and the contract (S-107, S-108, S-112; steps 1–5)

Brief: `.work/watch-autosync/brief-17b-dev-4.md`. Base commit `8ed0a96` (swift 322 / 0; flutter
+4030 ~1; analyze 196 / 0).

### No `prove-red` at the base — the new API does not compile there

`catchUp(reachable:)` and the `sendTimeout` init parameter do not exist at `8ed0a96`, so
`prove-red HEAD swift-test …` cannot compile the new tests. Every guard is therefore proven by
mutation: record the original line, apply the mutation, run the guard's test, restore the EXACT
original, re-run green. All four mutations are below with their verdict lines.

### Mutations — every new guard, shown red, then restored exactly

| Guard | Mutation applied | Test | Verdict |
|---|---|---|---|
| S-107 in-flight guard | `catchUp`'s test-and-set replaced with `catchUpLock.withLock { catchUpInFlight = true }` (the guard removed) | `testS107TheWristCatchesUpOnAReachabilityEdgeOnce` | RED AT: `XCTAssertEqual failed: ("2") is not equal to ("1") - exactly one sync ran`; also `and no send overlapped it`, `the owed entries left exactly once` (`["e-1", "e-2", "e-1", "e-2"]`), `the wrist holding a session offers its own snapshot` (2 vs 1), `a later trigger is not dropped` (3 vs 2) |
| S-108 session gate | `guard reachable, engine.session != nil else { return }` → `guard reachable else { return }` | `testS108AWristWithNoSessionDoesNotSyncOnItsOwn` | RED AT: `XCTAssertTrue failed - no session means no catch-up`; `XCTAssertEqual failed: ("1") is not equal to ("0")` (a snapshot request left) |
| S-107 unreachable case | the gate's `reachable` clause dropped: `guard engine.session != nil else { return }` | `testS107TheWristCatchesUpOnAReachabilityEdgeOnce` | RED AT: `XCTAssertEqual failed: ("3") is not equal to ("2") - an unreachable phone starts no sync` — the only assertion that fails |
| S-112 send bound | `enqueue`'s `try await WatchEmitForwarder.bounded(envelope, via: send, within: timeout)` → `try await send(envelope)` (the bound removed) | `testS112AHungSendCannotWedgeTheQueue` | RED AT: `XCTAssertEqual failed: ("0") is not equal to ("1") - the wedged send is reported exactly once`; the run took 5.17 s — the hung send's own delay, i.e. no bound fired |

After each mutation the exact original line was restored and the test re-run green (below).

### Green

| Command | Result | Log |
|---|---|---|
| gateway `swift-test --filter WatchEmitForwarderTests` | `Executed 6 tests, with 0 failures` — includes `testS112AHungSendCannotWedgeTheQueue` | `swift-test-20261007-024226-47452.log` |
| gateway `swift-test --filter WatchConnectivityBridgeTests` | `Executed 21 tests, with 0 failures` — includes `testS107TheWristCatchesUpOnAReachabilityEdgeOnce` and `testS108AWristWithNoSessionDoesNotSyncOnItsOwn` | `swift-test-20261007-024245-…` (inline) |
| gateway `swift-test` (full, final) | `Executed 325 tests, with 0 failures` — 325 passed, 0 failed; baseline 322 / 0, **+3** (S-107, S-108, S-112) | `swift-test-20261007-024536-48671.log` |
| gateway `test` (full, final) | `+4030 ~1: All tests passed!` — 4030 passed, ~1 skipped, 0 failed; the baseline count (docs-only change; the docs/fixtures guard is green) | `test-20261007-024546-48829.log` |
| gateway `lint` | `196 issues found.` — 0 errors, the baseline count; no line for a touched file | `lint-20261007-024541-48733.log` |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

### What the change is

- `WatchEmitForwarder.swift`: `sendTimeout: TimeInterval = 10` on both inits; `enqueue` routes each
  frame through a new `static func bounded(_:via:within:)` that races the send against a `Task.sleep`
  and fails with `WatchSendTimeout` when the bound expires, guarded by a once-only `SendRace` (NSLock).
  The loser is abandoned, never awaited, so a hung send cannot hold the serial chain; nothing is
  retried or queued (D-98).
- `WatchSyncOrchestrator.swift`: `public func catchUp(reachable: Bool) async` — the gate
  (`reachable && engine.session != nil`) and an `NSLock`-guarded test-and-set in-flight flag (no
  suspension between check and set; cleared in a `defer`), then `await sync(reconnect: paths.syncedAt
  != nil)` (D-96).
- `PROTOCOL.md`: one additive 2026-10-06 version-history row and one snapshot-rules bullet for the
  wrist's own announcement (D-101), naming the six tests; nothing about catch-up.
- `docs/watch_session_sync.md`: a new "Catching up by itself" section (both directions, the bounded
  send, the remaining Sync uses, D-102), every sentence naming an exact test.
- `docs/watch-app-setup-and-qa.md`: the wrist walkthrough step and the out-of-reach note became
  automatic, marked *(owner)*.
- `ios/OmniTrain Watch App/ContentView.swift`: the reachability handler forwards the value to
  `orchestrator.catchUp(reachable:)` in a detached `Task`; `requestSync()`'s comment corrected. This
  file is the governor's to build (`xcodebuild`); the agent edit is one line plus the comment.

Footprint: 8 files — 2 Swift sources, 2 Swift test files, `PROTOCOL.md`, 2 docs, 1 shell file
(`git-diff --stat`: 359 insertions, 15 deletions). No scratch file was created, so none had to be
deleted, and no formatter was run.

## Fix round 1 — the eight review findings (F1…F8), 2026-10-07

Brief: `.work/watch-autosync/brief-17b-fix-1.md`. Base commit `54d2470` (swift 325 / 0; flutter
+4030 ~1; analyze 196 / 0).

Docs, comments and one Swift guard; no behaviour change and no new test. `prove-red` therefore cannot
apply to the prose (deleting prose is not a guard), so the findings are verified by reading and by the
existing suites; the one guard that is code — F5's sleeper cancellation — is proven by the same S-112
mutation Phase 4 used, re-run here.

### The one guard that changed (F5)

| Test | Mutation applied | Verdict |
|---|---|---|
| `WatchEmitForwarderTests.testS112AHungSendCannotWedgeTheQueue` | `enqueue`: `try await WatchEmitForwarder.bounded(envelope, via: send, within: timeout)` → `try await send(envelope)` (the bound removed) | RED AT: `XCTAssertEqual failed: ("0") is not equal to ("1") - the wedged send is reported exactly once`; 1 executed / 1 failed in 5.19 s — the hung send's own delay, i.e. no bound fired |

The exact original line was restored before the full run below.

### Green

| Command | Result | Log |
|---|---|---|
| gateway `swift-test --filter WatchEmitForwarderTests` | `Executed 6 tests, with 0 failures` — includes `testS112AHungSendCannotWedgeTheQueue`, which passes with the cancellation in place | inline |
| gateway `swift-test --filter testS112AHungSendCannotWedgeTheQueue` (mutation applied) | `Executed 1 test, with 1 failure` | inline |
| gateway `swift-test` (full, after the restore) | `Executed 325 tests, with 0 failures` — 325 passed, 0 failed; the Phase 4 count unchanged | `swift-test-20261007-031456-75524.log` |
| gateway `test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — the ceiling, links and reachability clauses | inline |
| gateway `test` (full) | `+4030 ~1: All tests passed!` — 4030 passed, ~1 skipped, 0 failed; unchanged (no Dart behaviour changed) | `test-20261007-031502-75633.log` |
| gateway `lint` | `196 issues found.` — 0 errors, the baseline count; `grep` over the log finds no line for `session_core_entry.dart` or `watch_session_auto_push.dart` and none carrying `error •` | `lint-20261007-031724-80474.log` |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches | — |

### What each finding changed

| Finding | File | The edit |
|---|---|---|
| F2 (blocking) | `docs/watch_session_sync.md` | "it re-sends what the phone has not acknowledged and asks for the phone's state" deleted; the catch-up sentence now says the wrist hands the phone the session it holds. The S-107/S-108 pointers are unchanged |
| F1 | plan, the S-104 note | "Red without the change because …" replaced: it passes vacuously at the base and is proven by mutation (e′) / (b) |
| F3 | plan AC-5, D-93 and Notes; `docs/watch_session_sync.md` | the ever-seen set's memory-only, per-held-session boundary stated in all three; the add-only paragraph marks it a known limit and claims no test; the durable ledger is a follow-up in Notes |
| F4 | `lib/state/workout/session_core_entry.dart` | doc comment only: a failed append surfaces on the state's error channel, not the watch graph's failure hook, and the slot is not retried this run |
| F5 | `WatchEmitForwarder.swift` | `bounded` keeps its sleeper in a `SleeperHandle` and whichever task wins the race cancels it, so a settled send leaves no task waiting out the timeout; the sleeper's timeout path is unchanged |
| F6 | `PROTOCOL.md` (the snapshot-rules bullet and the 2026-10-06 amendment row), `docs/watch_session_sync.md` | all three S-104 tests named: `…AnExercisePushFromThePhoneIsNeverAnnouncedBack`, `…AStructureChangeFromThePhoneIsNeverAnnouncedBack`, `…ASnapshotFromThePhoneIsNeverAnsweredWithTheWristsOwn` |
| F7 | `docs/watch_session_sync.md` | the D-102 paragraph states the non-empty-ladder condition and names the counter-case `testS77AWristWithAnEmptyLadderReservesNothing` |
| F8 | `lib/state/watch/watch_session_auto_push.dart` | comment only: a timed-out pass may report again on its own later failure — a second report for one pass, no state effect |

Footprint: 6 files (`git-diff --stat`: 111 insertions, 27 deletions) — the two docs and `PROTOCOL.md`,
two source comments, one Swift source, and the plan. No scratch file was created and no formatter was
run.
