# Review: 46c engine serialisation plan · P1–P4 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: governor-run (Swift 657/0; mutants 8/8 red) — not re-run per brief
Diff vs Predicted Files: conforms — exactly the 7 predicted paths (`--stat`: 921 insertions, 1 deletion); nothing outside

## Brief questions

1. **Waiter loss / double wake — no.** `WatchAsyncMutex.swift:38-47`: `acquire`'s `held` check and
   `waiters.append(continuation)` are both inside one `lock.lock()`…`unlock()` critical section, so a
   `release` running between them is impossible. `release` (`:51-61`): with waiters it takes
   `waiters[0]`, slices with `Array(waiters[1...])` (D-1's prescribed form), leaves `held == true`
   (the lock stays held through the hand-off) and resumes exactly one continuation. With no waiters
   it sets `held = false`. Each continuation is resumed from exactly one site; `exclusive` (`:30-35`)
   always reaches `release` because `body` is non-throwing. No lost waiter, no double wake, no
   orphaned `held`.
2. **Deadlock — none.** Exhaustive call-site grep of the five writer names and the seven entry
   points in `WatchSessionEngine.swift`: the only call sites are the unwrapped entry points →
   `transitionTo` (`:329, :350, :359, :368, :404`), `applyExercisePush` → `insertExercise` (`:434`),
   and `applyMessage` → the three appliers + `applyExercisePush` (`:461-473`). `createSession` has no
   internal call site. None of these callers holds the mutex. The awaited helpers reachable from
   inside the lock — `stopTimer` (`:1156`), `captureSessionEnd` (`:537, :648, :1159`),
   `storeSessionRow` (`:539, :599, :654`), `storeSnapshotEntry` (`:559`), `confirmObservations`
   (`:561, :685`), `adoptTimers` (`:562, :699` → `stopTimerFromMessage` `:728`), `appendObservation`
   (`:1465, :1697`), `appendTimer` (`:1602-1659`), `emitRestEnded` (`:1661`) — have zero call sites
   of the five writers or the entry points. A non-reentrant lock cannot deadlock on this call graph.
3. **Sink re-entry — no.** `emit` (`WatchSessionEngine.swift:1929-1931`) calls `onEmit?(envelope)`
   synchronously; `WatchEmitForwarder.sink` (`WatchEmitForwarder.swift:125-127`) is
   `{ [weak self] envelope in self?.enqueue(envelope) }`, and `enqueue` (`:129-149`) only chains a
   `Task` behind `tail` and returns — the send never runs inside the caller. Host wiring
   (`ContentView.swift:82-90`): the engine's `onEmit` is `forwarder.sink`; the transport is the radio
   bridge, which cannot reach back into the engine. Test harness sinks append to arrays. The
   `onIncoming` handler does call `orchestrator.receive` → the engine, but that is the *acquire* side
   (it waits, never holds), so no re-entrancy.
4. **S-6502/S-6504 outcomes and distinguishing power — correct and distinguishing.** Serialised
   semantics: S-6502 pick-then-snapshot ⇒ 3 exercises, index 0 (the snapshot's own position);
   S-6504 lifecycle-first ⇒ index 1 (the pick, applied last, on the lifecycle's row); pick-first ⇒
   index 2. All asserted outcomes match. Distinguishing power rests on two facts I verified:
   `SuspendingStore` (`WatchEffortRatingTests.swift:160-248`) suspends exactly **one** append (the
   arm is consumed by `beginAppend`), and `current` is written only **after** the append completes
   (`storeSessionRow` `:939-943`, `mirrored` `:1190-1197`, `createSessionExclusive` `:313-316`).
   Without the wrap, in every pick-first case the parked writer's row lands last and overwrites:
   S-6502/S-6503-pick-first end at 2 exercises (count assert fails), S-6504-pick-first at index 1
   (index assert fails), S-6504-lifecycle-first at index 2 (index assert fails); S-6501/S-6503-first
   end at index 0 with the stale 2-exercise base (slotId assert fails); S-6505's second start sees
   `current == nil` and mints a second row (rows.count assert fails). No assertion found that passes
   without the lock. The builder's "two cases passing before the fix" is consistent with the
   S-6506 mutex tests, which do not depend on the five wraps; no current S-6501..6505 case does.
5. **Docs names — all exist.** Verified this run: `WatchAsyncMutex.swift`, `WatchSessionEngine.swift`,
   `ContentView.swift`, the five writer names, the five private `...Exclusive` bodies, `exclusive`,
   `applyMessage`, `advanceExercise`, `selectExercise`, `finishSession`, `abandonSession`,
   `insertExercise`, `applyExercisePush`, `stopTimer` (`:1654`), `appendTimer` (`:1747`),
   `WatchEngineSerialisationTests.swift` (S-6501..S-6505), `WatchAsyncMutexTests.swift` (S-6506),
   `WatchHostHopSourceTests.swift` (S-6507). The claim "`WatchAsyncMutex.swift` says so at the top"
   is true (`:10-11`). The new source test's claim that the bridge delivers reachability on the main
   actor is true (`OmniTrainWatchConnectivity.swift:135-139` `Task { @MainActor in … }`, handler not
   `@concurrent`), and the arrival handler really does hop off (`receiveHandler` is `@concurrent`,
   `:42, :98`), so D-4's premise holds.

## Findings

1. [Minor] `WatchEngineSerialisationTests.swift:31-37` — the plan bounds bounded waits at "at most
   200 iterations"; the implemented bounds are 500 (`WatchAsyncMutexTests.waitUntil`), 1_000 and
   100_000 (`spin`). Still yield-bounded and clock-free, so the intent holds, but a maintainer
   reading the plan sees a different number. Fix: one-line amendment of the plan's bound (or cap
   `spin`'s default), nothing else.

## Assumption Log rulings

No separate Assumption Log entries; the Decision Ledger's stated limits (D-5: timers/observations
unserialised, no main-actor isolation) are ratified as documented in the new docs subsection's
"Known limits" paragraph, which matches the code.

## Scenario coverage

- S-6501 → `WatchEngineSerialisationTests.testS6501ASnapshotFirstAndAPickInFlightBothLand` ✓
- S-6502 → `…testS6502APickFirstAndASnapshotInFlightBothLand` ✓
- S-6503 → `…testS6503AStructureChangeFirstAndAPickInFlightBothLand` + `…APickFirstAndAStructureChangeInFlightBothLand` ✓ (both orders)
- S-6504 → `…testS6504ALifecycleFirstLosesToThePickThatArrivesSecond` + `…APickFirstLosesToTheLifecycleThatArrivesSecond` ✓ (both orders)
- S-6505 → `…testS6505TwoStartsAtOnceProduceOneSession` ✓
- S-6506 → `WatchAsyncMutexTests` cases A/B/C (order, exclusion, free-after-last, suspension holds) ✓
- S-6507 → `WatchHostHopSourceTests` both guards (hop present, bare bump absent, reachability untouched) ✓

No scenario missing a test that would fail without the change; the governor's 8/8 mutant-red pass
matches the per-wrap failure paths reasoned above.
