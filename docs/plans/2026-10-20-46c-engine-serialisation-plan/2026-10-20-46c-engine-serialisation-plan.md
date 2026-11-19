# Feature: 46c — the wrist's session changes happen one at a time, and the screen is told on the main thread

> Status: BUILT, PROVED AND REVIEWED 2026-10-20 (review APPROVE, one minor fixed: the plan's wait bound). Swift 657/0, mutation pass 8/8 red, watch target builds with xcodebuild. Base commit: `.work/2026-10-20-46c/base.txt`. Team: the crew (lead-seeded from the scout sheet `.work/crew/2026-10-20-46a/scout-engine-writers.md`).
> Series: `docs/plans/2026-10-20-46-wrist-logging-series.md`. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md

## Goal and acceptance

| Situation on the watch | Now | After 46c |
|---|---|---|
| The phone adds an exercise (a snapshot or structure change) while you pick another exercise from the menu | the pick can undo the phone's addition: the list reverts to the old one until the phone's next snapshot | both land: the list has the phone's addition and your pick is the current exercise |
| The phone and you change position at the same moment | whichever write finishes last silently decides, built from an out-of-date copy | the changes apply one after the other, each built from the latest session; the later one wins cleanly |
| Two taps start a workout twice | two sessions can be created | the second tap finds the first one |
| An incoming phone message reaches the screen | the screen refresh counter is bumped off the main thread | bumped on the main thread |

## Decision Ledger

- D-1 One mutex for the engine's session-row writers (new file `watch/watchos/Sources/WatchSessionEngine/WatchAsyncMutex.swift`, final class `WatchAsyncMutex`): FIFO, non-reentrant, `func exclusive<T>(_ body: () async -> T) async -> T`. Built on `NSLock` and `CheckedContinuation`: registration under the lock decides "held or not" so a release between the check and the registration cannot lose the waiter; release hands the lock to the first waiter (stays held) or frees it. New names avoid the append-only source guard's verbs (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set): use `acquire`, `release`, `exclusive`; take the first waiter with `let next = waiters[0]; waiters = Array(waiters[1...])`, not `removeFirst`/`dropFirst`.
- D-2 Wrap the whole body (read of `current`, every await, the write of `current`) of the five writers, no other function: `createSession` (:273), `transitionTo` (:1095), `applySnapshot` (:481), `applyStructureChange` (:560), `applyLifecycle` (:597). Pattern: rename the existing body to a private `...Exclusive` function and make the original name `await mutex.exclusive { await ...Exclusive(args) }` (same signature, same visibility, same documentation). Deadlock check done (scout sheet Q2): none of the five calls another of the five or any function that reaches one, so a non-reentrant lock cannot deadlock on today's call graph; the five are reached from `applyMessage`, `advanceExercise`, `selectExercise`, `finishSession`, `abandonSession`, `insertExercise` and `applyExercisePush`, none of which may take the mutex (D-5).
- D-3 `emit`/`emitLifecycle`/`emitSnapshot` run inside the lock: the sink only enqueues (`WatchEmitForwarder.sink`, non-awaiting), and test harness sinks append to arrays, so a sink cannot call back into the engine. The builder verifies by reading `WatchEmitForwarder.sink` and says so.
- D-4 The host bumps its refresh counter on the main actor: `ios/OmniTrain Watch App/ContentView.swift` `bridge.onIncoming { ... _ = try await self.orchestrator.receive(frame); self.revision += 1 }` becomes `... await MainActor.run { self.revision += 1 }`. The `@concurrent` receive path stays (the engine work stays off the main actor); only the host's own state moves.
- D-5 Out of scope, stated limits: the engine's timers and observations (`storedTimers`, `storedObservations` read-modify-write across awaits, scout sheet Q4) are not serialised here; making the whole engine main-actor isolated is a larger design change; the pager (46b) commits an exercise only on settle, which keeps the user-visible exposure small.

## Scenarios (ids S-6501.. checked free)

New `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineSerialisationTests.swift`, `@MainActor`-free async XCTest, using `SuspendingStore` (`WatchEffortRatingTests.swift:160`: `arm()`, `suspended`, `resume()`) and the harness/snapshot-envelope helpers already used by `WatchLiveMirroringTests.swift` / `WatchSessionEngineTests.swift` (the builder finds the snapshot, structure-change and lifecycle envelope builders there). Fixture: a wrist session with exercises [A, B], current index 0; phone message adds exercise C. Bounded waits only (`Task.yield` loop, bounded yield loops (the tests use limits of 500 to 100,000 iterations)); no real-clock thresholds.
- S-6501 snapshot first: arm the store; start `applyMessage(snapshot [A,B,C], same session, higher revision)`; wait until `store.suspended`; start `selectExercise(slotId: B)`; yield 50 times (the select must be blocked, assert `engine.session.currentExerciseIndex == 0` still); `resume()`; await both: the session has 3 exercises AND the current index is B's. Fails without the gate: select built its row from the 2-exercise copy and wins last (2 exercises).
- S-6502 select first: arm; start `selectExercise(B)`, wait until suspended; start the snapshot message; yield 50 times; `resume()`; await both: 3 exercises (the snapshot applied after the select, built from the select's row).
- S-6503 structure change vs select, both orders, same shape as S-6501/S-6502 with a `structure_change` that appends C (see how `WatchSessionEngineTests` builds `structure_change`).
- S-6504 lifecycle vs select, both orders, with an `exercise_advanced` lifecycle naming index 2 vs a select of B: whichever applies last wins and the other's row is its base: assert the final index is the one applied last in arrival order for each order (not the one that finished its append last).
- S-6505 `createSession` twice concurrently with the first suspended in its append: the second returns the first's session (same session id), exactly one session row exists.
- S-6506 `WatchAsyncMutex` alone: three tasks entering `exclusive` in a known order run strictly one at a time (a shared counter never exceeds 1) and in FIFO order; a body that suspends does not let the next start; the lock is free again after the last (a fourth call runs at once).
- S-6507 source scan (same helper style as `WatchSensorSourceSourceTests.swift:57` `viewSource()`): `ContentView.swift` contains `await MainActor.run { self.revision += 1 }` inside the `bridge.onIncoming` closure and no bare `self.revision += 1` there.
Mutation list for the lead: remove each of the five `exclusive` wraps one at a time (S-6501..6505 must each fail for its own wrap), make `release` free the lock without waking a waiter, make acquire non-FIFO, remove the main-actor hop.

## Phases

| Phase | Agent | Items | Write scope |
|---|---|---|---|
| P1 mutex + tests S-6506 | crew-builder-watch | 3 | `WatchAsyncMutex.swift`, `watch/watchos/Tests/**` |
| P2 five wraps + S-6501..6505 | crew-builder-watch | 6 | `WatchSessionEngine.swift`, `watch/watchos/Tests/**` (serial after P1) |
| P3 host hop + S-6507 | crew-builder-watch | 2 | `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Tests/**` |
| P4 docs | crew-docs-keeper | 2 | `docs/**` |
Builder Done lists include `swift-test --filter WatchSessionEngineTests` (append-only guard) and the sibling files `WatchLiveMirroringTests`, `WatchSessionStartPathsTests`, `WatchEffortRatingTests`, `WatchMenuTests`, then the full `swift-test`. Never run the full `flutter test`.

## Owner checks (owner)

- (owner) With the phone running a session: add an exercise on the phone and pick another on the watch within the same second; both should show afterwards (hard to time by hand; the unit tests are the proof).
