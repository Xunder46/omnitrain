# Plan 162 — evidence

Plan: `2026-11-14-162-engine-state-lock-box-plan.md`. Phase 1 = slice 1 (commit 1 / PR 1);
Phases 2-5 = slice 2 (commit 2). All commands are the gateway form; the logs named are under
`.work/gateway/`.

## Phase 1 — slice 1: the energy marks get one critical section

### 1. Red at HEAD (prove-red, TSan)

```
.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --sanitize=thread \
  --filter WatchEngineStateBoxRaceTests -- \
  watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift
```

Verdict line:

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the
reason the test guards; a compile or load error means the test could not run there (use a mutation
instead).
```

Log: `.work/gateway/swift-test-20261114-161517-17057.log` (1129 lines).
**10 TSan warnings, every one naming `WatchSessionEngine.swift` `announceEnergy` (1901 / 1902);
none named anything else.**

The first report (the guard's read racing the mark writes — `:1879` is the read, `:1901` the write):

```
==================
WARNING: ThreadSanitizer: data race (pid=17715)
  Write of size 8 at 0x00010e407328 by thread T4:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1901
    #1 closure #1 in announcingCaller #1 () in WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers() WatchEngineStateBoxRaceTests.swift:149

  Previous read of size 8 at 0x00010e407328 by thread T6:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1879
    #1 closure #1 in announcingCaller #1 () in WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers() WatchEngineStateBoxRaceTests.swift:149

  Location is heap block of size 401 at 0x00010e4071c0 allocated by thread T1

  Thread T4 (tid=28402782, running) is a GCD worker thread
  Thread T6 (tid=28402784, running) is a GCD worker thread

SUMMARY: ThreadSanitizer: data race WatchSessionEngine.swift:1901 in WatchSessionEngine.announceEnergy(kilocalories:at:)
==================
```

The remaining nine, all between the two announcing callers and all on the marks:

| # | Access A | Access B |
|---|---|---|
| 2 | write size 8, `:1901` (T6) | read size 8, `:1901` (T4) |
| 3 | write size 8, `:1901` (T4) | write size 8, `:1901` (T6) |
| 4 | write size 8, `:1902` (T6) | write size 8, `:1902` (T4) |
| 5 | write size 1, `:1902` (T6) | write size 1, `:1902` (T4) |
| 6 | write size 8, `:1901` (T6) | write size 8, `:1901` (T4) |
| 7-10 | same pairs, `:1901` / `:1902`, failing test names one per pair | |

TSan's own tally, from the end of the log:

```
ThreadSanitizer: reported 10 warnings
```

S-16202 was also observably red at HEAD without TSan — its one-shot pin is worth recording:

```
WatchEngineStateBoxRaceTests.swift:221: error: … testS16202TwoSimultaneousAnnouncementsEmitOneFrame
  : XCTAssertEqual failed: ("2") is not equal to ("1") - S-16202 two simultaneous announcements of
  one total emit one frame
```

(That makes A-16204's "red not guaranteed" stronger than planned: this run did catch the two-caller
window. It stays a pin — the TSan run is the deterministic red.)

### 2. Green after slice 1

Focused, no sanitizer (`.work/gateway/swift-test-20261114-161634-18356.log`):

```
Test Case …testS16201EnergyMarksSurviveTwoAnnouncingCallers passed (1.550 seconds).
Test Case …testS16202TwoSimultaneousAnnouncementsEmitOneFrame passed (0.002 seconds).
Executed 2 tests, with 0 failures (0 unexpected) in 1.552 (1.553) seconds
```

**Before the fix**, the same file reported `Executed 2 tests, with 1 failure` — S-16202 produced two
frames (`.work/gateway/swift-test-20261114-161435-16733.log`).

### 3. TSan filter, three runs

Command (the plan's item 6):

```
.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread \
  --filter "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests"
```

| Run | Result | Log |
|---|---|---|
| 1 | `Executed 21 tests, with 0 failures (0 unexpected) in 29.853 (29.872) seconds`; grep for `ThreadSanitizer\|data race` over the log → **no matches** | `.work/gateway/swift-test-20261114-161702-19413.log` |
| 2 | `Executed 21 tests, with 0 failures (0 unexpected) in 27.767 (27.787) seconds`; no TSan line in the output at all | printed in full, no log file |
| 3 | `Executed 21 tests, with 0 failures (0 unexpected) in 29.623 (29.640) seconds`; no TSan line in the output at all | printed in full, no log file |

All three runs included `WatchEngineStateBoxRaceTests` (2 tests, green) — the class the red run's 10
warnings named. Baseline before the change: the same filter at HEAD produced the warnings in §1.

### 4. Full suite

```
.github/copilot/scripts/macos/gateway.sh swift-test
```

```
Test Suite 'All tests' passed at 2026-11-14 16:20:12.916.
	 Executed 1432 tests, with 0 failures (0 unexpected) in 29.436 (29.610) seconds
```

Log: `.work/gateway/swift-test-20261114-161925-20643.log`. Re-run after the final whitespace
tidy-up of the engine diff: **1432 tests, 0 failures** in 23.350 s
(`.work/gateway/swift-test-20261114-162131-23481.log`).

**1432, not the plan's 1431**: baseline 1430 + 2 new tests = 1432 (the plan's item 7 arithmetic
added two to 1430 but wrote 1431; D-16207's baseline is 1430). `WatchReplayTests` 4/4 passed within
it, including `testS15208EveryRecordingReplaysWithNamedOutcome`, which replays the whole corpus.

### 5. Files

Modified: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (+43/−5);
`docs/state_management/watch_sensors.md` (+8/−1).
Created: `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift`;
this plan and this evidence file.
Nothing under `lib/`, `test/`, `watch/contract/`, `watch/sync_protocol/` or `ios/` was touched
(`git-diff --stat` shows only the two tracked files above; the rest of the tree is the parallel
Dart run's work, already modified before this phase started).

## Phase 2 — slice 2a: `current` and `sessionRows` move into the box

### 6. The box and the migration

`watch/watchos/Sources/WatchSessionEngine/WatchEngineSessionState.swift` (new, ~150 lines) owns the
four values behind one `NSLock`: `record()`, `mirror(_:)`, `rows()`, `rowCount`,
`fill(rows:current:)` in this phase (widened in Phase 3), `firstApply(changeId:)`,
`snapshotWatermark()`, `advanceSnapshot(sentAt:)`. Header states the lock order (`mutex → state
lock`) and that no section awaits; fields are private and every method is a single acquisition, so a
caller cannot hold the value.

`WatchSessionEngine.swift`: `private var sessionRows` and `private var current` deleted,
`private let state = WatchEngineSessionState()` added, ~35 call sites routed. `restore()` computes
its locals from the store snapshot and then writes once through `state.fill(rows:current:)`,
including `lensLog.fill(hidden:)` from the local it just filled (not a second read). `mirrored(_:)`
survives as a thin wrapper around `state.mirror(row)` so `createSessionExclusive`,
`transitionToExclusive`, `applySnapshotExclusive` and `applyStructureChangeExclusive` keep their call
shapes; `storeSessionRow` calls `mirrored(...)` without assigning the result (the box sets the
mirror itself).

Two mechanical side-effects, both logged: the `mutex` doc comment's stale "five session-row writers"
sentence was corrected in the same edit (the plan's Notes invited it), and the local
`let state = payload["state"]` inside `applyLifecycleExclusive` collided with the new `state`
property and was renamed `lifecycleState` (three sites, A-16212).

The migration was compiler-driven rather than sampled: `swift-test --filter
WatchEngineStateBoxRaceTests` printed every remaining `current`/`sessionRows` use with its line, and
each was routed in turn.

### 7. Focused run after the migration

`.work/gateway/swift-test-20261114-170955-52191.log`:

```
Test Suite 'Selected tests' passed at 2026-11-14 17:10:06.564.
	 Executed 4 tests, with 0 failures (0 unexpected) in 4.605 (4.607) seconds
```

## Phase 3 — slice 2b: the two apply gates

### 8. The members, the guard, the watermark

The box gains `firstApply(changeId:)`, `snapshotWatermark()`, `advanceSnapshot(sentAt:)`, and `fill`
now takes all four values, so `restore()` writes the whole state in one acquisition. In the engine
`private var appliedChangeIds` and `private var newestSnapshotAt` are gone; the structure guard's
`insert(...).inserted` becomes `state.firstApply(changeId)` (the same atomic test-and-insert, now
race-free against `restore()`'s fill); `applySnapshotExclusive` reads `state.snapshotWatermark()` at
the gate and calls `state.advanceSnapshot(sentAt:)` at the write, keeping the read→write gap inside
the one `mutex` body with no state-lock span across the awaited store writes (D-16204).

The gate keeps the literal line `if let newest = newestSnapshotAt, sentAt < newest { return nil }`
because `WatchInboundLaneWiringSourceTests.testS9315TheEngineRefusesASnapshotOlderThanTheNewestApplied`
scans the source for exactly that text; the box value is bound to a local named `newestSnapshotAt`
immediately above it (A-16213). Behaviour is unchanged.

### 9. Two red runs, both the test's fault, both fixed

- `.work/gateway/swift-test-20261114-171126-52635.log`: `Executed 5 tests, with 1 failure` —
  `WatchEngineStateBoxSourceTests.swift:55` reported the allowed set as `["energyAnnouncedSession"]`
  against the four expected names. Cause: the scan's two patterns were not line-bounded
  (`[^{=]*` ran across newlines), so only the shortest declaration matched. Rewrote both patterns
  (`[^{=\n]*`, explicit modifier list, optional initialiser).
- `.work/gateway/swift-test-20261114-171312-53238.log`: full suite `Executed 1435 tests, with 1
  failure` — `WatchInboundLaneWiringSourceTests.swift:192` (`testS9315…`) red because the migration
  had rewritten the literal it scans. Fixed by §8's local binding, which keeps the scanned text
  verbatim; no existing test was edited.

### 10. Focused source-scan run after the fix

`.work/gateway/swift-test-20261114-171230-52937.log`:

```
Test Case '-[…testS16205EngineDeclaresNoUnboxedMutableState]' passed (0.006 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 0.006 (0.007) seconds
```

## Phase 4 — the race, the mix, the source scan

### 11. What the three tests assert

- `testS16203MirrorSurvivesRestoreAndTaps` (S-16203): one `restore()` writer and one
  `advanceExercise()` writer for the window, 8 GCD readers copying `session`, `currentExercise`,
  `entries` and `sessionSnapshot()`; coherence notes must stay empty (session id `s-race`, exercise
  index in range while active, never zero rows while a session is held), and the window must end with
  the session active and named.
- `testS16204FullWriterMixSurvivesAllAccessors` (S-16204): taps, conformant `structure_change` phone
  frames, `restore()` and the sensor pair all live at once, 8 readers over all 13 accessors; same
  coherence notes, no "every logged set survived" assertion (restore legitimately replaces the log).
- `testS16205EngineDeclaresNoUnboxedMutableState` (S-16205): the drift guard over
  `WatchSessionEngine.swift` with comments stripped; allowed set
  `{announcedCountdownKeys, energyAnnouncedSession, energyAnnouncedKcal, energyAnnouncedAt}` — the
  three energy marks stayed plain in slice 1 behind `energyMarksLock`, so the allowed set is four
  names rather than D-16206's one (A-16210).

### 12. Mutation proofs

| Guard | Mutation | Verdict | Log |
|---|---|---|---|
| S-16205 | `private var probe: Int = 0` beside `state` | **RED** — `Executed 1 test, with 1 failure`; allowed set became `["energyAnnouncedSession", "energyAnnouncedKcal", "probe", "announcedCountdownKeys", "energyAnnouncedAt"]` | `.work/gateway/swift-test-20261114-171239-53029.log` |
| S-16203 | `fill` sets the held rows to `[]` | **RED** — `Executed 4 tests, with 1 failure`; S-16203 failed on `not equal to ("[]") - S-16203 no reader saw a torn or shrinking mirror`, S-16204 stayed green | `.work/gateway/swift-test-20261114-171552-53964.log` |

Both mutations were reverted to the exact original lines and the files re-run green (§15).

**Recorded limit of the proof (the plan's Phase 4 item 4 wording):** TSan cannot see the
refcount/`memcpy` damage these races cause, so S-16203/S-16204 were also green at HEAD before the
box; the tests prove no regression and exercise the lock; the by-construction argument (159 §6) is
the justification.

### 13. S-16203's first assertion was wrong, and the replacement is honest

S-16203's first run was red for a real reason — "row count fell from 267 to 266". `restore()`'s
`readAll` snapshot can predate a tap's append, so its `fill` legitimately replaces a superset with a
subset (D-16203 keeps that clobber). A non-shrinking assertion therefore contradicted the plan's own
decision; it was replaced with the property that must actually hold — the mirror never held zero rows
while a session was held (A-16211).

## Phase 5 — docs, residue sweep, consolidated verification

### 14. Docs

`docs/state_management/watch_sensors.md`, "One writer." section (+15/−1 lines): names
`WatchEngineSessionState`, `restore()`'s one-acquisition write, the lock order `mutex → state lock`,
that no state-lock section awaits, that the clobber semantics are unchanged, and the three tests
(`WatchEngineStateBoxRaceTests.testS16203MirrorSurvivesRestoreAndTaps`,
`…testS16204FullWriterMixSurvivesAllAccessors`,
`WatchEngineStateBoxSourceTests.testS16205EngineDeclaresNoUnboxedMutableState`). File ~39 KB, under
the 52 KB split band.

### 15. Full suite (final)

```
.github/copilot/scripts/macos/gateway.sh swift-test
```

```
Test Suite 'All tests' passed at 2026-11-14 17:19:16.801.
	 Executed 1435 tests, with 0 failures (0 unexpected) in 25.703 (25.807) seconds
```

Log: `.work/gateway/swift-test-20261114-171848-54976.log`. Inside it `WatchEngineStateBoxRaceTests`
4/4 (4.589 s) and `WatchReplayTests` 4/4; every other suite green. An earlier all-suite run right
after the S-9315 fix (`…-171400-53475.log`) also reported `Executed 1435 tests, with 0 failures`.

**1435, not the plan's 1434**: 1432 after Phase 1 (A-16209) + 3 new tests = 1435.

### 16. TSan filter (final)

```
.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread \
  --filter "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests|WatchReplayTests"
```

```
Test Suite 'Selected tests' passed at 2026-11-14 17:19:57.712.
	 Executed 27 tests, with 0 failures (0 unexpected) in 25.692 (25.707) seconds
```

Log: `.work/gateway/swift-test-20261114-171919-55113.log`; grep for
`WARNING: ThreadSanitizer|ThreadSanitizer:|data race` over that log → **no matches**. The box's own
suite is green under TSan (S-16203 1.510 s, S-16204 1.545 s).

### 17. Residue sweep

- `sessionRows|appliedChangeIds|newestSnapshotAt` over `watch/watchos/Sources/WatchSessionEngine/`:
  hits only in `WatchEngineSessionState.swift`'s own fields and, in the engine, (a) the argument
  labels of `state.fill(rows:current:appliedChangeIds:newestSnapshotAt:)`, (b) the two locals
  `restore()` binds from its store snapshot before that fill, (c) the local
  `let newestSnapshotAt = state.snapshotWatermark()` at the snapshot gate, and (d) that local's
  scanned guard line. No engine reader of a plain stored property remains.
- `\bcurrent\b` over `WatchSessionEngine.swift`: 14 hits — 12 doc comments, `current: restored` (the
  fill argument), and `guard let current = state.record() else … return current` in
  `requireSession()` (the read-once shape D-16205 asks for).
- `grep -rln "import .*workout_repository" …` not re-run: this slice changed no Dart file (§19).

### 18. Footprint

```
$ … gateway.sh git-diff --stat -- watch/watchos docs/state_management/watch_sensors.md docs/plans/2026-11-14-162-…
docs/state_management/watch_sensors.md             |  15 +-
 .../WatchSessionEngine/WatchSessionEngine.swift    | 158 ++++++-----
 .../WatchEngineStateBoxRaceTests.swift             | 293 +++++++++++++++++++++
 3 files changed, 396 insertions(+), 70 deletions(-)
```

plus two new untracked files (`WatchEngineSessionState.swift`, `WatchEngineStateBoxSourceTests.swift`)
and this plan/evidence pair. Nothing under `lib/`, `test/`, `watch/contract/`, `watch/sync_protocol/`
or `ios/` came from this run — the `lib/watch/...`, `test/watch_session_engine_test.dart` and
`test/watch_session_import_test.dart` entries in `git-status` belong to a parallel Dart run.

### 19. Dart suites not run (deliberate)

This slice is Swift-only, so `lint`, full `test`, `ui_standards_contract_test.dart` and the SQLite/seed
contract gained no new input from it. The Dart checks to run are those of the parallel Dart run that
owns the modified `lib/watch/` files.
