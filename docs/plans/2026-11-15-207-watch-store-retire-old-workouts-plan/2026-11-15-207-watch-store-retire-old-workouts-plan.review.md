# Review: 2026-11-15-207-watch-store-retire-old-workouts · P1a+P1b · 7664f126..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: 1575 passed / 0 failed (the brief's observed whole-package Swift run; not re-run — the brief marks it do-not-re-verify)
Diff vs Predicted Files: conforms for plan 207 (the seven in-scope files); the working tree also carries plans 201-206 and other sessions' files per the brief — not reviewed.

## Q1 Data loss (can the retire drop rows the phone has not acknowledged?)
Verdict: OK
Evidence:
- Snapshot-carried entries: `applySnapshotExclusive` stores each entry (`storeSnapshotEntry`, WatchSessionEngine.swift:1290) and then appends a confirmation row for them (`confirmObservations(entryMaps.compactMap { $0["entryId"] })`, same path) — so a snapshot entry is marked confirmed by a row the store gate reads (`retiredSessionIds` folds confirmations via `applyConfirmations`, WatchSessionStore.swift:315). It cannot be dropped while unconfirmed.
- Corrections and deletions: they arrive as session `changes` (`correct_entry` → `lensLog.merge`, `delete_entry` → `lensLog.hide`, WatchSessionEngine.swift:1489-1493); they never un-confirm the underlying observation row. An unconfirmed row keeps the session from retiring (owed gate). A confirmed row of a retired session is dropped only together with the tombstone-carrying session rows of the same session — the phone is the structure authority and holds the correction/deletion, so nothing the phone lacks is dropped.
- Late entries into an ended session: `mergeLateEntries` (WatchSessionEngine.swift:749) appends observations with NO confirmation by design (D-14605) → they are owed and unsynced → `retiredSessionIds` excludes that session until a receipt names them. Conservative: a retention leak, never a loss.
- Wrist `session_end`: the wrist-source gate demands the `end-<sessionId>` row exist AND be synced (WatchSessionStore.swift:333-341); a joined session's end is held by the generic owed gate (`sessionEnd` is in `receiptKinds`, plan 71 D-1/D-3). Both shapes pinned (S-20703, S-20703B).
- A session row appended after the prune decision: the prune runs once at launch before `engine.restore()`; appends after it (late snapshots, receipts) are survivors. A queued snapshot that recreates a retired session is the plan's documented, accepted competition answer.
- Note (not a finding — the rule is D-20704's own wording and S-20712 pins it): a confirmation row that names a kept tap keeps its retired-session ids too, so a receipt batch that mixed taps and entries leaves one small permanent confirmation row after `pruneWaterTaps` cuts the taps.
Findings: none.

## Q2 Order and ties
Verdict: OK
Evidence: Candidates are ordered by the newest session-row `sequence` (WatchSessionStore.swift:344-347; unique per row, so no ties). A late session row for an OLD session can only appear via the recreate-after-prune path: while the engine still holds the session's terminal row, a late snapshot merges entries only and never writes a session row (`holdsTerminalRow` → `mergeLateEntries`, WatchSessionEngine.swift:633, 652). Recreation ranks the old session as newest — it can retire a genuinely newer (already synced) workout: wrong retention, never data loss, and the plan accepts recreation explicitly (seed competition answer).
`keepingNewest` counts only retire-eligible sessions: `candidates` is built after all three gates, then `dropFirst(keepingNewest)` (WatchSessionStore.swift:345-347). That matches D-20702/D-20703 ("settled" = terminal AND fully synced; the first 20 kept). An unsynced older workout does not count toward the 20 and is harmless: it is kept regardless of the count, and once synced it retires on a later launch if it is then beyond the newest 20 — the plan's stated behaviour.
Findings: none.

## Q3 Water and food
Verdict: OK
Evidence: The readers join nothing on session rows. `WatchWaterState` reads `engine.waterLog` (WatchWater.swift:98, :275) and `WatchNutritionState` reads `engine.nutritionLog` (WatchNutritionState.swift:102, :211) — both filter the in-memory observation log by kind only. A water tap's sessionId is always the day's nutrition id, never a workout's (WatchSessionEngine.swift:1846-1855); a nutrition quick-log CAN carry a workout's sessionId (WatchSessionEngine.swift:1806) and the retire keeps every `nutritionQuickLog` and `waterGlass` row (WatchSessionStore.swift:397-399), pinned by S-20701 and S-20713 (a confirmation naming a kept tap stays whole). A retired session's session rows are not needed to read its kept taps.
Findings: none.

## Q4 Launch order
Verdict: OK
Evidence: Between app start and `await engine.pruneSettledSessions()` (ContentView.swift:370): the engine's `init` stores dependencies and reads nothing (WatchSessionEngine.swift:136-151); the `$revision` subscription's first emission sees an empty session (lifecycle `.none`; `summary.note`, `restPings.arm()` — the rest row it re-reads is the in-memory timer log, WatchRestPingScheduler.swift:52), and `workout.refresh`/`sensors.refresh` read HealthKit, not the store. `recoverStrandedWorkout()` (ContentView.swift:366; also the system recovery relaunch, OmniTrainApp.swift:39) reads only `engine.storedSession()` = `readLaunch().sessions.max` (WatchSessionEngine.swift:201) — one read whose keep-or-discard decision depends only on whether the newest row is terminal, is complete before the prune runs, and cannot be invalidated by it (a kept stranded session is active → never retired). `workout.restoreFinished` runs after prune+restore (D-15005). Cost note, consistent with the plan's lifecycle answer: the first full parse happens in `recoverStrandedWorkout` before the prune, but `loadRows` caches (FileWatchSessionStore.swift:598), so the prune's own load is free and the compaction shrinks every launch from the next one on.
Findings: none.

## Q5 Tests
Verdict: Minor
Evidence: 16 tests in `WatchSettledSessionPruneTests.swift`. The core shape is real: `PruneWrist.settledWorkout` builds each workout through the engine over a fresh `FileWatchSessionStore` (createSession, sensor sample, set entry, `finishSession`, receipt stand-in via `confirmObservations`) — engine-built session rows, the archive's side file, and the engine's own end capture are all exercised. The owed-kind arm is per-kind (S-20714), the confirmation arms are S-20712/S-20713, the write arms are S-20706/S-20706B/S-20708, the twin is S-20701B/S-20716B.
Real-engine shapes no test covers (named as asked):
1. An effort rating answered through the engine's own flow (`recordEffortRating`, recordId `rating-<sessionId>`, WatchSessionEngine.swift:2271-2289) — covered only by hand-built `effort_rating` rows (S-20713/S-20714). Kind and id match the gate's list, so the residual risk is flow-level only.
2. A recovered-then-continued workout (plan 140: session rows written across two launches, the recovered continuation row).
3. Engine-logged timers and rests (real `startTimer`/`pauseTimer` rows with `stoppedAt`, work kinds) — timers appear only as hand-built rest rows; the drop arm is `.timer where sessions.contains(id)` and shape-independent.
4. A late snapshot merging entries into an ended, retire-eligible session (`mergeLateEntries`) — the resulting unconfirmed entries would hold the workout from retirement; the gate shape is covered (S-20702) but not that flow.
Findings:
1. [Minor] WatchSettledSessionPruneTests.swift:707 — the four real-engine shapes above are unexercised; a regression that misreads a real flow (for example a rating row written under an unexpected id or sessionId) would pass every test. Fix: one engine-flow test — a settled workout whose rating is answered with `recordEffortRating` and left unconfirmed must be held from retirement, and one `mergeLateEntries` follow-up whose workout must be kept. Guard: the same tests.
2. [Minor] WatchSettledSessionPruneTests.swift:730 — S-20711's Expect says "the main file's row count is below a fixed bound derived from the fixture"; the test asserts `storeLines() < beforeLines` (relative). It still fails without the change, but a fixture that grows its rows without dropping any would not be caught. Fix: assert `storeLines()` against a constant derived from the 20-kept fixture.

## Assumption Log rulings
- A-1 (architect step skipped) — ratify. The seed named files, symbols and fixtures; the implementation matches them.
- A-2 (newest 20; a still-owed rating lapses) — remains open, owner to confirm. The code implements it and the docs state it (`watch_sensors.md` "a rating question still owed for it lapses with it", `watch-app-qa-wrist-logging.md` item 52); the owner's confirmation is still owed, not a code finding.
- A-3 (~52 KB not measured; the saving stated by row counts) — ratify. S-20711 bounds the file by line count; bytes are not asserted anywhere.

## Scenario coverage
S-20701 -> WatchSettledSessionPruneTests · testS20701TheOldestSettledWorkoutsLeaveAndTheNewestTwentyStayWhole
S-20702 -> WatchSettledSessionPruneTests · testS20702AnUnsyncedWorkoutIsKeptWhateverItsAge
S-20703 -> WatchSettledSessionPruneTests · testS20703AWristWorkoutWhoseEndIsUnacknowledgedIsKept (+ testS20703B…NoEndRowAtAllIsKept)
S-20704 -> WatchSettledSessionPruneTests · testS20704AnUnfinishedOldSessionIsNeverRetired (+ testS20704B…WithNothingUnsyncedIsStillKept)
S-20705 -> WatchSettledSessionPruneTests · testS20701 (the newest-20 row-equality assertions) | covered
S-20706 -> WatchSettledSessionPruneTests · testS20706ANothingToRetirePruneWritesNothing
S-20707 -> WatchSettledSessionPruneTests · testS20706BANothingToRetirePruneKeepsATornTailAndTheMarker (bytes + inode)
S-20708 -> WatchSettledSessionPruneTests · testS20708APruneThatCannotBeWrittenDropsNothing
S-20709 -> WatchStoreGrowthTests · testS15601TheLaunchRestoreAsksForThePrunes (second pin: the retire precedes `engine.restore()`)
S-20710 -> WatchSessionEngineTests · testS004NoMutatingOperationExistsAnywhereInTheModule (allowed list gains `pruneSettledSessions`)
S-20711 -> WatchSettledSessionPruneTests · testS20711AnEngineOverFortySettledWorkoutsKeepsTwentyAfterRelaunch | covered, weaker assertion (finding 2)
S-20712/S-20713/S-20714/S-20716/S-20716B -> present as named (guard-arm tests beyond the plan's table)

## Docs delta
docs/state_management/watch_sensors.md ADDED -> applied (line 625; every named test exists in WatchSettledSessionPruneTests.swift / WatchStoreGrowthTests.swift; sentences true)
docs/watch-app-qa-wrist-logging.md ADDED -> applied (line 697, item 52; named tests exist)
Doc edit the table does not name: docs/watch_session_sync/what_does_not_sync.md:240-242 — a plan-207 sentence ("only a workout that is over and fully synced, beyond the newest 20, leaves the file at launch") tied to `WatchSettledSessionPruneTests`; true, listed per the rules.
