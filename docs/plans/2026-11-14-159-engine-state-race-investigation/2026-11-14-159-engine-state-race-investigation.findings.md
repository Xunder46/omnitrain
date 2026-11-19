# 159 — Does the watch engine's un-boxed state race? Findings

**Status:** investigation complete, no product code changed.
**Scope:** `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` and the watch app
target's call sites (`ios/OmniTrain Watch App/`).
**Question:** can the engine's plain (non-boxed) state — `current`, `sessionRows`, the energy-announce
marks, the "already applied" memories — be read and written at the same time by the threads the
shipping app actually uses, and if so, what is the smallest fix?

Short answer: **yes, for the energy-announce marks — proven. Yes by construction, and crash-capable in
principle, for `current` and `sessionRows` — not proven, because Thread Sanitizer did not report them
in three instrumented attempts.** Recommendation: **Option A**, box the plain state behind the same
synchronous lock the engine already uses for its row logs.

---

## 1. What isolates what today

| Type | Isolation | Evidence |
|---|---|---|
| `WatchSessionEngine` | **none** — `public final class WatchSessionEngine: ObservableObject` at `WatchSessionEngine.swift:38`; no `@MainActor`, no `@unchecked Sendable`, not an actor | nothing in the file opts into isolation |
| `WatchAppHost` | `@MainActor` | `ios/OmniTrain Watch App/ContentView.swift:24` |
| `WatchLoggingModel`, `WatchPagerModel`, `WatchRestPingScheduler` | `@MainActor` | their own files |
| `WatchLoggingState` | **none** | no `@MainActor` in `WatchLoggingState.swift` |
| `WatchAsyncMutex` | an async FIFO mutex, **non-reentrant** | `WatchAsyncMutex.swift` header: never nest `exclusive` inside `exclusive` |
| `WatchObservationLog`, `WatchTimerLog`, `WatchSensorSampleLog`, `WatchEntryLensLog`, `WatchAcknowledgementLog` | internal `NSLock` each | `WatchEngineRowLogs.swift`, `WatchEntryLensLog.swift`, `WatchSensorSampleLog.swift` |

`WatchAppHost` being `@MainActor` isolates its *own* members. It does **not** isolate the engine it
holds: the engine is a non-`Sendable` `let`, and any `await` inside an entry point lets the
continuation resume on a different executor, so "the caller is main-actor" does not make the callee's
stored properties main-actor-only.

## 2. Lock inventory: which entry points take the engine's mutex

One `private let mutex = WatchAsyncMutex()` (`WatchSessionEngine.swift:48`), taken in exactly **six**
places. Its own doc comment states the contract it is meant to hold: it "serialises the five
session-row writers (D-2). Each runs its whole body — the read of `current`, the awaited append, the
write of `current` — inside this gate". The gated entry points below honour that for their own body;
`restore()`, which is the sixth writer of `current`, does not take the gate at all.

| Entry point | Takes `mutex`? |
|---|---|
| `createSession` | yes |
| `applySnapshot` | yes (`applySnapshotExclusive`); the jump runs *after* release — D-7 |
| `applyStructureChange` | yes |
| `applyLifecycle` | yes |
| `transitionTo` | yes (`transitionToExclusive`) |
| `pruneSettledSensorSamples` | yes |

Not under it, and not protected by anything else:

- `restore()` — **writes `current`, `sessionRows`, `appliedChangeIds` and `newestSnapshotAt` with no
  lock at all** (`WatchSessionEngine.swift:176-186`), and calls `lensLog.fill(...)`.
- `storedSession()` — read-only, but races with any writer of the store.
- `advanceExercise`, `selectExercise`, `finishSession`, `abandonSession`, `insertExercise` — they call
  `requireSession()` and read `current` *before* entering `transitionTo`'s gate, so the read is
  unprotected even though the write is not.
- `appendObservation`, `appendSensorSample`, `announceEnergy`, `startTimer`/`pauseTimer`/
  `resumeTimer`/`stopTimer`, `confirmObservations`, `applyReceipt`, `applyTimerState` — the row logs
  they write are individually locked; the `current` reads they do are not.
- Every read accessor: `session`, `currentExercise`, `observations`, `sensorSamples`,
  `newestSensorSample`, `newestSensorSamples`, `timerRows`, `timerFor`, `entries`, `sessionSnapshot`,
  `newestSessionRows`, `holdsTerminalRow`, `creationRow`, `jumpTarget`, `pendingObservations`.

So the mutex serialises **the row-building writers against each other**. It does not serialise readers
against writers, and it does not cover `restore()` at all.

## 3. Who calls what, on which thread

| Entry point | Caller | Thread it actually runs on |
|---|---|---|
| `createSession`, `advanceExercise`, `selectExercise`, `appendObservation`, `startTimer`/`pauseTimer`/`resumeTimer`, `finishSession`, `abandonSession`, `confirmObservations`, `logNutrition` | SwiftUI views through `WatchAppHost` (`@MainActor`) | starts on the main actor; **resumes elsewhere after every `await`** |
| `restore()`, `storedSession()` | `WatchAppHost.restore()` / `recoverStrandedWorkout()` | main actor at entry, off it after the first `await store…` |
| `applyMessage` (snapshots, structure changes, lifecycle, receipts, timer state) | `WatchConnectivityBridge.onIncoming`, whose handler is **`@concurrent`** (`ContentView.swift:~253`), through `WatchInboundLane` | **off the main actor** — the lane serialises frames against each other, nothing else |
| `appendSensorSample`, `announceEnergy` | `WatchSensorRecording`'s per-stream `Task { for await … }`; `WatchSensorWrites` chains sensor writes on a plain `Task` | **off the main actor** |
| `applyReceipt`, `applyTimerState` | `WatchSyncOrchestrator` receive / catch-up | off the main actor |
| reads (all accessors) | SwiftUI `body`, `WatchLoggingModel`, `WatchPagerModel`, `RestPingScheduler` | main actor |

The three writers the wrist really has — **SwiftUI taps, the radio's `@concurrent` handler, and the
sensor recorder tasks** — are on three different threads by design. `CoreLocationRawSource`'s delegate
is `nonisolated` and calls back off the main actor as well.

## 4. Every un-boxed stored property

| Property (declaration) | Writers | Readers | Guarded by |
|---|---|---|---|
| `current: WatchSessionRecord?` (`:146`) | `restore():176`, `mirrored(_:)` (`current = row`) via `storeSessionRow` / `transitionToExclusive` / `applySnapshotExclusive` / `applyStructureChangeExclusive` / `applyLifecycleExclusive` | every accessor above, plus `requireSession()` | only when written from a gated path; **`restore()` writes it unlocked** |
| `sessionRows: [WatchSessionRecord]` (`:76`) | `restore():176` (whole-array assignment), `mirrored(_:)` (`sessionRows.append(row)`) | `holdsTerminalRow`, `newestSessionRows`, `creationRow`, `sessionRows` accessor, `sessionSnapshot()` | same split: append is gated, restore is not |
| `appliedChangeIds: Set<String>` (`:95`) | `restore():177-182` (whole set), `applyStructureChangeExclusive` (`insert`) | `applyStructureChangeExclusive` only | gated path vs unlocked restore |
| `newestSnapshotAt: Date?` (`:101`) | `restore():183-186` (whole value), `applySnapshotExclusive` (`max`) | `applySnapshotExclusive` only | ditto |
| `energyAnnouncedSession: String?` (`:1857`) | `announceEnergy` (`:1903`) | `announceEnergy` (`:1879` guard) | **nothing** |
| `energyAnnouncedKcal: Double?` (`:1858`) | `announceEnergy:1901` | `announceEnergy:1879` | **nothing** |
| `energyAnnouncedAt: Date?` (`:1859`) | `announceEnergy:1902` | `announceEnergy` | **nothing** |

Constant `let`s (`store`, `onEmit`, `validator`, `clock`, `idFactory`, `sessionIdFactory`, `mutex`) are
immutable after `init` and are not part of the question.

## 5. Thread Sanitizer attempt

Scratch test (plan 159 only; now parked as a skipped test because the gateway's `delete-scratch`
refuses paths outside `test/zz_*`, so the Governor deletes the file — see the handoff report):
`watch/watchos/Tests/WatchSessionEngineTests/ZzScratchStateRaceTests.swift`. Four scenarios, each a
5-second window with **eight GCD reader threads** and one detached writer task per axis:

| Scenario | Writers | Readers |
|---|---|---|
| S-zz1 | phone snapshots (`applyMessage`), `restore()`, structure changes, taps (`advanceExercise` + `appendObservation`), sensor (`appendSensorSample` + `announceEnergy`) | all 13 read accessors, in a loop |
| S-zz2 | two concurrent `announceEnergy` callers | all read accessors |
| S-zz3 | snapshots, `restore()`, structure changes | `session`, `entries` |
| S-zz4 | `restore()` + `advanceExercise` only — the narrowest `current` probe | `session`, `currentExercise`, `entries`, `sessionSnapshot()` |

Plan 150's strongest attempt (S-15031) was three reader threads and 80 writes for 1.5 s. This is
roughly 40× the accesses.

Command: `.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread --filter ZzScratchStateRaceTests`.

### Result: 3 attempts, 20 race reports, all on the energy-announce marks

| Attempt | Exit | Race reports | Where |
|---|---|---|---|
| 1 | `swift test` exited 1 (TSan's own abort) | **7** | `announceEnergy` only: `1901` (read/write pairs on `energyAnnouncedKcal`), `1902` (`energyAnnouncedAt`, plus `:1879` read vs `:1902` write), 1-byte write at `1902` |
| 2 | same | **6** | identical: `1901` ×4, `1902` ×2 |
| 3 | `swift test` exited 1 on two scratch assertions (see below) | **7** | `announceEnergy` `1902` only |

Logs: `.work/gateway/swift-test-20261114-154027-2298.log` (1),
`swift-test-20261114-154206-3342.log` (2), `swift-test-20261114-154437-4494.log` (3).

Representative report (attempt 1):

```
WARNING: ThreadSanitizer: data race (pid=2577)
  Write of size 8 at 0x00010cc074f8 by thread T3:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1902
  Previous write of size 8 at 0x00010cc074f8 by thread T13:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1902
  Location is heap block of size 401 at 0x00010cc07380        <- the engine object
SUMMARY: ThreadSanitizer: data race WatchSessionEngine.swift:1902 in WatchSessionEngine.announceEnergy(kilocalories:at:)
```

Two honest caveats about these runs:

- Attempts 1 and 2 reported every scratch test as passed (`Executed 3 tests, with 0 failures`) and the
  process then exited through Thread Sanitizer's own abort path (`unexpected signal code 6`, no engine
  frame on it). That exit code is the sanitizer reporting races, not the engine crashing. Attempt 3
  failed two of my own scratch assertions (the refusal count below) and reported no signal.
- Attempt 2 also produced a `SEGV` during teardown (`==3422==ERROR: ThreadSanitizer: SEGV on unknown
  address 0x000000000000`), with a Swift over-release stack ending in `LockedFrameSink.deinit` →
  `_ContiguousArrayStorage.__deallocating_deinit` → `_swift_release_dealloc`. The sink's own array is
  `NSLock`-protected, so that stack does not attribute the over-release to a named engine access; treat
  it as a symptom of the same class (refcount damage under concurrent use) whose owner is not pinned
  down, not as proof against a specific property.

### What it did **not** report, and how to read that

No report ever named `current`, `sessionRows`, `appliedChangeIds` or `newestSnapshotAt`, including in
S-zz4, where the only two writers were `restore()` (unlocked) and `advanceExercise` (gated), both
looping thousands of times while eight threads copied `current` for the full 5 s. S-zz4 passed with no
report in attempt 3, and the emitted-frame histogram proves those writers really wrote
(`zz frame types: ["observations_up": 250, "session_snapshot": 1, "session_lifecycle": 251,
"energy_live": 1]` — the lifecycle frames are the taps' transitions, each of which republishes
`current`).

Attempts 1 and 2 also showed that the phone frames were **refused** rather than applied
(`XCTAssertGreaterThan failed: ("0") is not greater than ("0")` — zero applied), and attempt 3's
histogram shows the refusals emit no frame at all, so in all three runs the radio path did not write
`current`; S-zz4 was added to cover that axis with writers that provably write.

This absence is **not** evidence of safety. Swift's retain/release and `isUniquelyReferenced` are
compiler intrinsics that Thread Sanitizer does not instrument, and a ~400-byte `WatchSessionRecord`
assignment is a `memcpy` of a struct full of reference-counted fields; a torn or raced copy damages
refcounts rather than tripping a shadow-memory check. `WatchEngineRowLogs` was introduced in plan 150
for exactly this reason — the reports from that plan and this one cover the boxed things, not the
un-boxed ones.

## 6. Classification

**Crash-capable (a damaged refcount or a torn reference is a hard crash, not a wrong number):**

| Property | Why |
|---|---|
| `energyAnnouncedKcal: Double?` and `energyAnnouncedAt: Date?` (`:1858`, `:1859`) | plain stored properties written on one thread while another reads them at `:1879` and writes them at `:1901`/`:1902`; a torn optional gives a nonsense total or timestamp — **proven by TSan** (a 1-byte tag write at `:1902` was reported too) |
| `energyAnnouncedSession: String?` (`:1857`) | a refcounted pointer written on the same unlocked path; a double write of two different `String`s is the over-release shape — reported for its neighbours, not itself |
| `sessionRows: [WatchSessionRecord]` | `sessionRows.append(row)` from the gated mirror vs `sessionRows = contents.sessions` in the unlocked `restore()`: concurrent `append` on a shared CoW buffer is the classic over-release, and readers copy the buffer while it is being replaced |
| `appliedChangeIds: Set<String>` | same shape (refcounted dictionary/set storage), written from the gated change path and from `restore()` |
| `current: WatchSessionRecord?` | structurally the same (multi-field struct of `String`s and arrays): a read that copies while a write is in flight can retain a buffer the writer is releasing. In practice it also produces the stale-read classes below |

**Stale-read only (wrong or empty projections, no crash):**

| Property | Symptom |
|---|---|
| `energyAnnouncedKcal`, `energyAnnouncedAt` | a torn `Double`/`Date` makes the "already announced" comparison (`:1879`) admit or suppress an announcement — at worst a duplicate or missing spoken energy update |
| `newestSnapshotAt` | a stale value makes the mirror refuse a newer snapshot as older, or accept an older one — a stuck-looking mirror |
| `current` (read side) | `entries`, `observations`, `sensorSamples`, `timerRows` filter locked logs against `current?.sessionId` read separately, so an interleaved read yields the previous session's rows for a frame or an empty list |
| `requireSession()` | `preconditionFailure` if `current` ever reads as `nil`; nothing assigns `nil` today, so this stays theoretical unless `restore()` is changed to clear it |

## 7. Smallest fix

### Option A — box the plain state, following `WatchEngineRowLogs` (recommended)

Add one small holder with an `NSLock` and synchronous accessors — the pattern plan 150 already
established for `WatchObservationLog`, `WatchTimerLog`, `WatchSensorSampleLog`, `WatchEntryLensLog`
and `WatchAcknowledgementLog` — and route the seven un-boxed properties through it.

- **Files:** one new `WatchSessionEngine/Sources/WatchSessionEngine/WatchEngineSessionState.swift`
  (≈70 lines: `current`, `sessionRows`, `appliedChangeIds`, `newestSnapshotAt`, the three energy marks,
  plus `read`/`write`/`mutate` accessors), and `WatchSessionEngine.swift` (~45 call sites changed,
  all mechanical: `current` → `state.current`, `sessionRows.append` → `state.appendRow`).
- **Lock discipline:** the new lock is synchronous and is **never** held across an `await`, so it
  cannot interleave with `WatchAsyncMutex`'s FIFO waiters. Where both are involved the order is
  `mutex → state lock` on every path (the gated bodies take the state lock inside; `restore()` takes
  only the state lock). No path takes them in the opposite order, so no deadlock.
- **Replay corpus / protocol:** unchanged. Nothing about frame shape, ordering or emitted acks moves;
  the state lock only replaces unsynchronised reads and writes of the same values.
- **Risk to the Swift suite (≈1,430 tests):** mechanical and compile-checked. The engine's own tests
  read through the same accessors, so a missed call site is a compile error, not a silent behaviour
  change.
- **Cost:** a real but bounded refactor of the hottest class in the package (~1.5-2 h with its tests).

A cheaper first slice, if the full refactor must be split: box **only** the three energy marks, which
is the part TSan proves (~15 changed lines, no reader changes). That closes the proven crash path and
leaves `current`/`sessionRows` for the follow-up.

### Option B — make the engine `@MainActor`

- **Files:** `WatchSessionEngine.swift` (one attribute), plus every off-main call site: the
  `@concurrent` radio handler in `ContentView.swift`, `WatchSyncOrchestrator.receive`/`catchUp`,
  `WatchSensorRecording`'s stream tasks, `WatchSensorWrites`, `CoreLocationRawSource`'s delegate, and
  `WatchInboundLane`'s handler — each gains a `MainActor.run`/`await` hop (≈15 call sites).
- **Deadlock risk:** low in the app, but real in tests — `XCTestExpectation` waits and the existing
  GCD reader threads would have to become `MainActor` hops, and plan 150's stress tests would need
  rewriting.
- **Replay corpus:** unaffected, but every sensor sample and every radio frame would cross an actor
  hop, which changes timing enough to be a behavioural risk on watchOS.
- **Cost:** larger than A, and it hides the same problem rather than fixing it if any hop is missed.

### Option C — convert the engine to an `actor` / custom serial executor

Largest: every entry point becomes `async` and `Sendable`, the `ObservableObject` conformance has to
go (SwiftUI needs a main-actor view model), and all ~1,430 tests' call sites change. Only worth doing
alongside a wider rework; not a crash fix.

### Recommendation

**Option A**, in two commits: the energy marks first (proven, tiny), then `current`/`sessionRows`/
`appliedChangeIds`/`newestSnapshotAt`. Option A is the only one that closes the proven race without
introducing new hops into the sensor or radio paths.

## 8. What this investigation could not determine

- Whether `current` and `sessionRows` race **in the field**, because Thread Sanitizer cannot see
  refcount/`memcpy` damage on them. They are unsynchronised by construction (section 2), which is the
  standard to fix to, but no report exists to point at.
- Which access produced the attempt-2 `SEGV`. The stack names the test's frame sink, not the engine.
- Whether the phone's refusal of the scratch test's frames (`applied == 0`, and no refusal frame
  emitted) is a validator rule the scratch fixtures got wrong — one run with a fixture copied verbatim
  from `WatchStaleSnapshotTests.snapshot(...)` would say whether the radio axis can be exercised under
  TSan at all.

## 9. Tests a fix would add

- `WatchEngineStateRaceTests.testCurrentAndSessionRowsUnderRestoreAndFrames` — S-zz4's shape, asserting
  the mirror answers coherently (`session?.sessionId` never changes mid-copy, `sessionRows` never
  shrinks).
- `WatchEngineStateRaceTests.testEnergyMarksUnderTwoAnnouncingCallers` — S-zz2's shape, asserting the
  last announced pair is a pair from one caller, never a mixture.

## 10. Footprint of this investigation

- Product code: **unchanged**. `git diff --stat` is empty; no Dart, no `.swift` source, no SQL, no doc
  outside `docs/plans/2026-11-14-159-engine-state-race-investigation/` was touched.
- Package suite after the runs: `swift test --package-path watch/watchos` →
  `Executed 1434 tests, with 4 tests skipped and 0 failures (0 unexpected)`. The four skipped ones are
  the parked scratch probe, which the Governor deletes.
- Docs contract: `flutter test test/docs_indexing_contract_test.dart` → `All tests passed!` (14 tests).

