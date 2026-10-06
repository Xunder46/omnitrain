# Feature: watch-session-sync PR 4 — a durable wrist store

> **Split (governor, 2026-10-06).** This plan is two PRs on two tracks (the Swift package plus the
> shell, and the Dart twin). **PR 4a** = Phases 1–3 — the append-only file store, the shell that
> builds it, F-6 (the rating surface notifies after its own mutation) and the docs for 4a. **PR 4b** =
> Phases 4–5 — G2, G3 and F-9 on both stacks, and their docs. 4a ships the headline: a set logged on
> the wrist survives a kill. **4b does not need the file store — its cases run over the in-memory
> store** — so it can land before or after 4a; it is sequenced second only because 4a is the
> owner-visible win. The governor commits per phase.

> Status: DRAFT (owner reads Open questions; then hand off — nothing implemented yet)
> Next handoff: **@developer (Phase 1 — the file store, PR 4a)**; every phase is `@developer` (the
> `dba` agent owns the Dart data layer, not this Swift store)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`
> Series: `docs/plans/2026-10-05-15-watch-session-sync-index.md` (its PR 4 row, split into "4a / 4b",
> and its Status line are updated with this plan; Phase 3 keeps them in step)
> Baselines at this plan's base: `flutter test` +3945 / ~1 / 0 failing · `flutter analyze` 196 issues, 0 errors · `swift test` 275 / 0 failing

## Overview

The owner's statement, verbatim: **"A set I logged on the watch must not vanish if the watch app
closes, gets killed or the watch restarts before I sync."**

Today the shell builds `InMemoryWatchSessionStore` (`ios/OmniTrain Watch App/ContentView.swift:56`), so
quitting the watch app discards the session, every row it holds and any owed rating question
(`docs/watch_session_sync.md:224`, `docs/watch-app-setup-and-qa.md:25,193`). The package is already
built for a store that outlives the process: every engine mutation is an `append`, the rest countdown
is derived from stored timestamps, the owed rating prompt is a stored row, and
`WatchEffortRatingTests.testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer` already passes —
against a second engine sharing one store object. **This PR supplies the store.**

What changes: a second Swift implementation of `WatchSessionStore` that writes the same records to a
file, and the shell builds it instead of the in-memory one (PR 4a). F-6 rides with it (PR 4a), because
the durable store is what makes the rating surface's `await` real — the shell's subscription is only
correct while the store never suspends. Three further carried defects, on both stacks, are PR 4b: the
Dart logging surface's missing status guard (F-9), the projection lens the two prunes leave behind
(G3) and the un-scoped held-id check (G2). None of those three touches the store.

What does not change: no wire format, no protocol version, no phone screen, no new sync trigger (manual
and watch-initiated, D-16/I-1 unchanged), no conflict logic, and nothing about the Dart twin's shipping
status — the Wear OS client still has no host.

## Resolved Decisions (Ledger)

| # | Decision |
|---|---|
| **D-43** | **The durable store is an append-only JSON-lines file, loaded once.** `FileWatchSessionStore` (new, `watch/watchos/Sources/WatchSessionEngine/`) is a `public final class` conforming to `WatchSessionStore`, built from one directory URL the shell names. One record per line, each line the record's own `toJson()` (`WatchRecords.swift`), written with a trailing newline by a single append. The class exposes exactly `append`, `readAll`, `pruneConfirmed`, `pruneSensorSamples` — the same four methods as its in-memory twin, so S-004's surface check stays green. No new public API, no new record type, no new protocol message. **Internals:** the file is read exactly once, lazily, on first use, into an in-memory row list; an `append` writes one line and then updates that cache — it never re-reads the file, and the cache supplies both the dedupe key and the next `sequence`. Every public method serialises access with a lock, because the engine calls it from async code. Compaction refreshes the cache from the survivors. |
| **D-44** | **Format.** The file's first line is the marker `{"format":"omnitrain-watch-store","version":1}`. Every later line is one record; `StoredWatchRecord.fromJson` reads it. A line that is not valid JSON, or whose `recordType` is unknown, is skipped and the rest of the file still reads — so a torn last line costs at most the record being written. `sequence` continues from the highest stored row, as `HiveWatchSessionStore._nextSequence` already does in the Dart twin. |
| **D-45** | **A version this binary does not know is never damaged.** If the marker names a version other than 1, `readAll()` returns empty contents and `append` is a no-op that returns the record it was handed, leaving the file byte-identical. Today v1 is unreleased so this is reachable only by a downgrade; the cost of choosing otherwise is a newer file overwritten by an older binary. |
| **D-46** | **The two prunes compact, and compaction is atomic.** `pruneConfirmed` / `pruneSensorSamples` write the marker plus every surviving line to a sibling temp file in the same directory and then move it over the original, so a crash mid-compaction leaves the original intact. The temp file lives beside the store, not in `tmp/`, because a move across volumes is not atomic. After the move the in-memory row list is refreshed from the survivors. |
| **D-47** | **Every append is durable before it returns.** No batching, no timer, no flush on suspend: `append` writes and closes before it returns, which is what makes "killed mid-set" a case with an answer, and that one write is the only file I/O an append does (the cache, D-43, holds the rest). `append` also remains the no-op-by-id it is today — a record whose `(recordType, recordId)` is already stored returns the stored row without a second line. |
| **D-48** | **Two stores, one output.** For the same append and prune sequence, `FileWatchSessionStore.readAll()` returns the same `WatchStoreContents` as `InMemoryWatchSessionStore`, all nine families included — including `preferences` and `ratingPrompts`, which a restore reads (`WatchPhonePreferences.restore`, `WatchEffortRatingState.restore`) and which a store that omitted them would silently lose. `InMemoryWatchSessionStore` stays, as the tests' and desktop runs' store. |
| **D-49** | **The Dart twin is untouched by this PR, and that is deliberate.** It already has a durable store (`lib/watch/session/hive_watch_session_store.dart`, one Hive box per record family) and no shipping host — `docs/watch-app-setup-and-qa.md` §1 records no Wear OS app, no Gradle target and no transport. Adding a second on-disk format there would be a format to keep in step for no user-visible gain. Its `canLog` guard is still corrected (D-55), because that is a rule both clients share, not a storage question. |
| **D-50** | **The projection lens stays memory-only, and the loss self-heals.** `entryCorrections` and `deletedEntryIds` are not persisted: after a relaunch the stored rows are the truth, and the next Sync re-states the phone's own entries (PR 3's D-35) and re-applies any `correct_entry`, so the wrist converges again. What a relaunch does rebuild is unchanged and sufficient: `acknowledgedObservationIds` from stored confirmations, `appliedChangeIds` from `chg-`-prefixed session rows, `current` from the newest session row. Consequence, owner-visible: between a relaunch and the next Sync an edited entry shows the phone's *un*edited payload, and a deleted entry (which no phone sender exists for yet — PR 3's D-38) can show again. Both clear on Sync. |
| **D-51** | **Pruning stays unscheduled; the file is never compacted in production.** The earlier "production pruning on a receipt" entry and its scenario (S-57) are **dropped**: nobody asked for it, and `store.readAll()` runs only at restore (`WatchEffortRating.swift:129`, `WatchPhonePreferences.swift:117`, `WatchSessionEngine.swift:106`, `WatchStartPaths.swift:290`, `WatchNutritionState.swift:116`), so an ever-growing file is not a cost on the hot path; scheduling a prune is also the one place this PR could regress the owed rating question and `WatchLoggingState.nextRoundNumber` (`:311`). **PR 2b's D-27 deferral of pruning therefore stands** — this entry supersedes only its "together with durability" half, not the deferral. A bound is a follow-up for when the file size matters. `pruneConfirmed` / `pruneSensorSamples` stay implemented and tested (S-48, S-54): the store contract requires them and the tests and the debug surface call them. |
| **D-52** | **G3: a pruned row takes its lens with it.** `pruneConfirmed` drops each dropped observation's `entryCorrections[id]` and `deletedEntryIds` marker as well as the row, in both stacks (Swift `WatchSessionEngine.swift:1508`, Dart `watch_session_engine.dart:1365`). Without it a re-carried id is appended as a fresh row and the stale correction overrides it — a correction surviving the row it corrected. With pruning unscheduled (D-51) the only callers are the tests and the Dart debug surface, so the defect is latent today; it is fixed now so the lens cannot outlive its row once a prune is scheduled later. |
| **D-53** | **G2: the re-statement check is scoped to the session.** In `storeSnapshotEntry` / `_storeSnapshotEntry` the held-id test reads the observations **of the named session** (`$0.sessionId == sessionId`), so an `entryId` that exists in two sessions cannot fold one session's correction onto the other's row. Phone ids (`entry-<sessionExerciseId>-<n>`) and wrist UUIDs cannot collide today, which is why this is a latent defect rather than a bug report — it is fixed so the identity rule stops depending on that accident. |
| **D-54** | **F-6: the rating surface notifies after its own mutation, not before.** `WatchEffortRatingState.end()` and `.confirm()` move their `objectWillChange.send()` to after the `await`s that change what the surface shows (`engine.finishSession()` / `noteOwedPrompt` / `engine.recordEffortRating`). The shell's subscription stays exactly as it is (`ContentView.swift:106-109`, the deferred bump): F-6 was flagged precisely because that subscription is only correct while the store never suspends, and this PR is what makes it suspend. The fix therefore lands in the package, where a test can drive it. |
| **D-55** | **F-9: the Dart surface refuses an ended session too.** `WatchLoggingState.canLog` (`lib/watch/logging/watch_logging_state.dart:183`) becomes `_engine.session?.status == WatchSessionStatus.active && _slot != null`, the rule the Swift surface already applies (D-23, `WatchLoggingState.swift:198`). Its only callers are debug entrypoints (`lib/watch/debug/`, `lib/state/watch/live_session_mirror_debug_main.dart`), so the user-visible effect is confined to the debug surfaces — which is the point: the twin stops disagreeing with the shipped client about when logging is possible. |
| **D-56** | **Exactly-once is unchanged by durability.** The emission path is untouched: a relaunch re-sends unconfirmed observations from storage, the phone deduplicates by `entryId`/`eventId` (S-003), a confirmed observation is never re-sent (`pendingObservations` filters on the store's `confirmedAt`), and the wrist's own `append` ignores a repeated `recordId`. The store changes where the rows live, not what is sent or how often. |
| **D-57** | **The shell owns the location, the package owns the format.** `ContentView` passes `Application Support/watch-session/` and nothing else; the directory is created on first append, it is inside the app's own container (no file sharing, no protection-class change), and the engine never names a concrete store. |

## Feature Invariants

- **The store is append-only by construction.** Four public operations per `*Store.swift` file, no
  mutating verb named anywhere in the module, and the engine reaches for nothing else. A new store file
  is picked up by `watchOS WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
  automatically (it walks `Sources/WatchSessionEngine`), so this PR's new file is covered the moment it
  exists — its private helpers must be named for what they build, not for what they replace
  (`appendLine`, `loadRows`, `parseLine`, `compact`, `nextSequence`).
- **Two implementations, one output.** See D-48.
- **Nothing a user logged is dropped without a receipt.** Both prunes stay gated on the session being
  over and its numbers held by the phone; durability does not widen either gate.
- **The layer boundary holds.** `lib/state/` and `lib/features/` keep their distance from concrete
  stores; here the boundary is Swift-side — the engine depends on the protocol, only the shell names a
  store class.

## Requirements

- **R1** A set logged on the watch survives the app being closed, force-quit, or the watch restarting,
  with no Sync in between.
- **R2** What comes back is the whole surface, not just the rows: the session, its ladder and current
  position, the logged rows, a rest countdown that was running, and an owed rating question.
- **R3** The set that survived is delivered exactly once at the next Sync.
- **R4** The store keeps its append-only contract, its four operations and both prune gates.
- **R5** No new phone screens, no conflict logic, no new sync trigger — manual and watch-initiated.
- **R6** A store file this binary cannot read is left alone, not overwritten.

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| AC1 | A logged set is still in the store after the process that logged it is gone | S-44, S-51 |
| AC2 | The restored surface is complete: ladder, position, timers, owed question | S-44, S-46, S-47 |
| AC3 | The next Sync delivers it once, not twice, and not zero times | S-45, S-51 |
| AC4 | A torn last record costs that record only | S-49 |
| AC5 | A first launch and an empty store behave as today, with one marker | S-50 |
| AC6 | An ended session stays ended and stays refused | S-48, S-52 |
| AC7 | A store version this binary does not know is read as empty and never overwritten | S-53 |
| AC8 | The file store and the in-memory store answer the same for the same sequence | S-54 |
| AC9 | The rating question appears after a commit that suspends | S-55 |
| AC10 | A pruned row's correction and deletion marker go with it | S-48 |
| AC11 | One `entryId` in two sessions is never folded across | S-56 |

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `InMemoryWatchSessionStore` | 30 files: 25 Dart test files, 4 Dart debug mains, `ios/OmniTrain Watch App/ContentView.swift:56`, and `Sources/WatchSessionEngine/WatchSessionStore.swift:133` itself | The shell's single construction changes to the file store; the in-memory store stays for tests, desktop runs and the debug mains. Nothing else moves. | D-48, D-57, S-54 |
| `WatchSessionStore` implementations | Swift: protocol + `InMemoryWatchSessionStore`; Dart: `watch_session_store.dart`, `in_memory_watch_session_store.dart`, `hive_watch_session_store.dart` | A third Swift implementation joins the contract; S-004's surface check extends to it with no test edit. | S-004 (unchanged), S-54 |
| `pruneConfirmed` callers | Swift tests `WatchSensorRecordingTests.swift:519,617`, `WatchSessionEngineTests.swift:350,374,641`, `WatchNutritionQuickLogTests.swift:264`; Dart `test/watch_session_engine_test.dart:462,503`, `test/watch_sensor_recording_test.dart:706`, `test/watch_nutrition_quick_log_test.dart:422`, `lib/watch/debug/watch_session_debug_surface.dart:276`. **No production caller** (the earlier F-10); with pruning unscheduled (D-51) none is added. | G3 changes what a prune drops, so every existing prune case is extended rather than left to pass by accident. | S-48 |
| `entryCorrections` / `deletedEntryIds` | Swift `WatchSessionEngine.swift:65,66,198,200,727,821,825,826`; Dart `watch_session_engine.dart:105,106,215,216,710,871,881,882` | G2 and G3 each touch three sites per stack. The projection's meaning (PR 3's D-35 re-statement, D-38 deletion) is unchanged, and the lens staying memory-only is now a stated decision with a stated consequence (D-50). | S-48, S-56, and PR 3's S-35 / S-36 |
| `canLog` | `lib/watch/logging/watch_logging_state.dart:183`, `WatchLoggingState.swift:198`; readers `test/watch_logging_surfaces_test.dart:495,553`, `WatchLoggingSurfacesTests.swift:380,413` | Dart becomes stricter and the two clients agree. Existing Swift cases are untouched. | D-55, S-52 |
| `WatchEffortRatingState` notifications | `ios/OmniTrain Watch App/ContentView.swift:106-109` (the subscription), `WatchEffortRatingTests.swift:53,55` (the harness) | The send moves later in `end()` / `confirm()`; the shell's deferred bump re-reads settled state. The shell file is not edited. | D-54, S-55 |
| `WatchStoreContents` families | `WatchEffortRating.swift` (`ratingPrompts`), `WatchPhonePreferences.swift` (`preferences`), `WatchStartPaths.swift` (routine catalogs), `WatchNutritionState` (food catalogs) | A file store that returned fewer families would make a restore silently find nothing. The parity seed names a row of every family. | S-54 |
| Doc claims this PR invalidates | `docs/watch_session_sync.md:224`, `docs/state_management/watch_surface.md:393,663,74-92`, `docs/watch-app-setup-and-qa.md:25,193,425` | Rewritten in Phase 3 (durability, the force-quit sentences) and Phase 5 (the two guards). The two plan files that also state "the shell keeps `InMemoryWatchSessionStore`" (`docs/plans/2026-09-21-13-…:1171`, `2026-10-04-14-…:422`) are history and are not edited. | Phase 3, Phase 5 |

## Scenarios

### S-44: a logged set survives the process
- Fixture: a file store in a fresh temp directory; a `WatchSessionEngine` over it; a free session with two slots (`sx-bench` reps/sets/load, `sx-run` time/distance); three logged sets on `sx-bench` (`entry-1`, `entry-2`, `entry-3`, loads 60/60/62.5 kg), the phone's confirmations for `entry-1` and `entry-2`, one `set_rest` timer started 30 s ago, and `currentExerciseIndex` moved to 1.
- Trigger: build a *second* engine over the same directory — nothing else, no sync.
- Flow: `restore()`.
- Expected outcome: the session exists with status active, both slots in order, `currentExerciseIndex == 1`, all three entries present with their payloads, `entry-1`/`entry-2` carrying their confirmation timestamps, the rest timer present with its `startedAt`.
- Edge case of: none.
- Turns red: a store that keeps rows in memory only, or a `readAll` that drops the `timers` family.

### S-45: exactly one delivery after a relaunch
- Fixture: S-44's store after the relaunch, with `entry-3` unconfirmed; a transport that records the envelopes it is handed.
- Trigger: `WatchSyncOrchestrator.sync()`.
- Flow: the relaunched engine re-sends what the phone has not acknowledged.
- Expected outcome: the envelopes carry `entry-3` exactly once and never `entry-1`/`entry-2`; the phone's `entryId`s are unchanged from before the kill, so its own dedupe has nothing to do.
- Edge case of: S-44.
- Turns red: an `append` that assigns a new `recordId` on the way out, or a `readAll` that drops the confirmation fold.

### S-46: a countdown that was running is still right
- Fixture: as S-44, with the rest timer started 30 s before the kill (rest length 90 s) and the clock advanced 30 s past the kill.
- Trigger: relaunch and read the countdown.
- Flow: the remaining time is derived from the stored `startedAt`, not from a counter.
- Expected outcome: the countdown shows 30 s left, and the timer row is unchanged.
- Edge case of: S-44.
- Turns red: a store that persists a "remaining" value, or a restore that treats a stale `startedAt` as finished.

### S-47: the owed rating question survives the kill (QA step 17)
- Fixture: an ended session with two effort entries, `preferences.asksForEffortRating == true`, the phone having confirmed both entries; `end()` called, so a `prompt-<sessionId>` row exists; then the process dies.
- Trigger: a second engine and a second `WatchEffortRatingState` over the same directory, `restore()`.
- Flow: the prompt is read back from `store.readAll().ratingPrompts`.
- Expected outcome: the question is asked again, an answer of 4 records exactly one rating for that session, and a further relaunch asks nothing.
- Edge case of: S-44.
- Turns red: a file store that omits `ratingPrompts` from `readAll`, or a duplicate-keyed second prompt row for the same session.

### S-48: a pruned row takes its lens with it (G3)
- Fixture: an ended session; `entry-1` carrying a phone correction (`load` 70) and confirmed; `entry-2` confirmed; `entry-3` unconfirmed.
- Trigger: `pruneConfirmed()`, then a snapshot that carries `entry-1` again with the same payload.
- Flow: the row is dropped, the correction and any deletion marker are dropped with it, and the re-carried id is appended as a fresh row with nothing overriding it.
- Expected outcome: `entries` shows the re-carried `entry-1` exactly as delivered; `entry-2` is gone; `entry-3` is untouched; the ended session is still ended and the surface still refuses to log into it.
- Edge case of: S-44.
- Turns red: the current code — the stale correction overrides the fresh row (Swift `WatchSessionEngine.swift:1508`, Dart `watch_session_engine.dart:1365`).

### S-49: a torn last record
- Fixture: a store file written by S-44, with its last line truncated mid-JSON (the shape a kill during an append leaves).
- Trigger: `readAll()`, then one more `append`.
- Flow: the unparsable line is skipped; the new append lands as a new final line.
- Expected outcome: every intact row reads; the truncated record is simply absent; the new record is readable by a third engine.
- Edge case of: S-44.
- Turns red: a reader that abandons the whole file on one bad line.

### S-50: a first launch on an empty store
- Fixture: an empty temp directory, no file.
- Trigger: `readAll()`, then `append` of one session row, then `readAll()` again.
- Flow: an empty read, the directory and file created on the append, the marker written once.
- Expected outcome: the first `readAll` is empty; after the append the row reads with `sequence == 1`; the file has exactly one marker line and one record line.
- Edge case of: none.
- Turns red: a store that fails to create its directory, or one that appends a second marker line.

### S-51: two relaunches in a row
- Fixture: S-44's store, relaunched twice with one more set logged before each relaunch (`entry-4`, then `entry-5`).
- Trigger: two full kill/relaunch cycles.
- Flow: nothing is lost and nothing is duplicated; sequences keep climbing.
- Expected outcome: after the second relaunch all five entries read in append order with strictly increasing `sequence`, and `append` of an already-stored record adds no line.
- Edge case of: S-44.
- Turns red: a store that rebuilds `sequence` from zero, so a later row sorts before an earlier one.

### S-52: an ended session stays ended and stays refused
- Fixture: S-47's store, whose session ended before the kill; two surfaces over it (Swift `WatchLoggingState`, Dart `WatchLoggingState`).
- Trigger: `restore()` on each, then `canLog` and a log attempt.
- Flow: the status comes back `completed` from the stored session row, and both surfaces refuse.
- Expected outcome: both report `canLog == false`, both refuse the log with their own error, both leave the store's row count unchanged — the same answer from the same fixture.
- Edge case of: S-47.
- Turns red: today's Dart rule (`session != null && slot != null`) accepts it.

### S-53: a version this binary does not know
- Fixture: a store file whose marker reads `"version": 2`, followed by one well-formed record line.
- Trigger: `readAll()` on a v1 store, then `append`, then read the bytes.
- Flow: the unknown version is read as empty and the append is a no-op.
- Expected outcome: `readAll` is empty, the append returns the record it was handed, and the file is byte-identical to before.
- Edge case of: S-50.
- Turns red: a store that parses the lines anyway, or that truncates on append.

### S-54: the two stores agree
- Fixture: one scripted sequence — a session row, two observation rows, a timer, a confirmation, a sensor sample, a routine catalog, a food catalog, a preferences row, a rating prompt, then `pruneConfirmed` — replayed into `FileWatchSessionStore` (temp directory) and into `InMemoryWatchSessionStore`.
- Trigger: `readAll()` on both after the sequence.
- Flow: family by family, record by record.
- Expected outcome: the two `WatchStoreContents` are equal on all nine families, equal in append order, and equal in each row's `sequence`; both prunes return the same dropped ids.
- Edge case of: none.
- Turns red: a file store missing the `preferences` or `ratingPrompts` family (a real gap in the Dart twin's own Hive store, which is why the seed names them), or one that orders rows by write time instead of sequence.

### S-55: a slow commit still shows the owed question (F-6)
- Fixture: a store stub whose `append` suspends until the test resumes it, over an engine whose session has one effort entry and a preference asking for ratings.
- Trigger: `await rating.end()`.
- Flow: the surface's notification is delivered only after the end has been written and the prompt noted.
- Expected outcome: every notification the rating state sends observes a state already mutated — the prompt is owed by the time the shell's bump runs, and the shell's read of the surface is never mid-commit.
- Edge case of: S-47.
- Turns red: the current code, whose `objectWillChange.send()` precedes the `await`.

### S-56: one `entryId` in two sessions (G2)
- Fixture: the wrist holding observations for two sessions — `s-watch-1` and `s-watch-2` — that share the `entryId` `e-shared`, plus a snapshot naming `e-shared` in `s-watch-2`.
- Trigger: the snapshot is applied.
- Flow: the held-id check is scoped to the session the snapshot names.
- Expected outcome: `s-watch-2`'s row folds the re-statement, and `s-watch-1`'s row is untouched.
- Edge case of: none.
- Turns red: today's unscoped check folds the payload onto the other session's row.

## Iteration 1

### Phase 1: The file store (@developer) — PR 4a
1. [x] Add `FileWatchSessionStore.swift` in `watch/watchos/Sources/WatchSessionEngine/`: a `public final class FileWatchSessionStore: WatchSessionStore` with `public init(directory: URL)`, exactly the four protocol methods public, and private helpers (`loadRows`, `parseLine`, `markerLine`, `appendLine`, `compact`, `ensureDirectory`, `nextSequence`) — symbol: `FileWatchSessionStore`. No public member beyond those four, so S-004's surface assertion holds unchanged. — done; S-004 green with no edit to it.
2. [x] Marker and version gate (D-44, D-45) — `FileWatchSessionStore.markerLine` / `loadRows`: the marker line, the unknown-version short circuit, and line tolerance for unparsable JSON and unknown `recordType`. — done; S-50, S-53 green.
3. [x] Load-once and lock (D-43): `loadRows` reads the file exactly once on first use into one private row list; every public method takes that lock; the dedupe key and the next `sequence` come from the list, never from a re-read — symbol: `FileWatchSessionStore.loadRows`. — done; the lock is taken in a synchronous helper so no lock spans a suspension point.
4. [x] `append` (D-47): dedupe on `(recordType, recordId)` by returning the stored row, assign the next `sequence` from the cache, `appendLine` one JSON line with its trailing newline, update the cache, and return the record with its assigned sequence. — done; S-51 green.
5. [x] `readAll` (D-48): every family into one `WatchStoreContents`, observations folded through `applyConfirmations`, rows in sequence order. — done; S-44, S-54 green.
6. [x] `pruneConfirmed` and `pruneSensorSamples` (D-46): find the rows, `compact` the file to marker + survivors through a sibling temp file and a move, refresh the cache from the survivors, return the dropped ids. — done; S-54's parity of both return arrays green.
7. [x] Add `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift` with the store cases of S-49, S-50, S-51, S-53 and S-54 — most of them red before step 1's file is complete, which is the order to write them in. — done; written first.
8. [x] Add the two-engine cases of S-44, S-45, S-46, S-47 and S-48 to the same file (a helper that builds a second `WatchSessionEngine` over one directory), keeping the existing in-memory harnesses where they are. — S-44…S-47 done; **S-48 not added** — the brief scopes it to PR 4b (it is AC10, the G3 lens case Phase 4 owns). See A-30.
9. [x] Confirm S-004 stays green over the new file with no edit to that test — it walks the sources directory itself. — green, unchanged.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (baseline 275 passing / 0 failing, and the count rises by this phase's cases), `.github/copilot/scripts/macos/gateway.sh lint` (baseline 196 issues / 0 errors — unchanged; no Dart file is touched in this phase)
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` (new), `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift` (new)
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: The shell and the rating surface (@developer) — PR 4a
1. [ ] `ios/OmniTrain Watch App/ContentView.swift` `init()` (`:56`): build `FileWatchSessionStore(directory:)` from `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-session", isDirectory: true)` in place of `InMemoryWatchSessionStore()`, leaving the D-21 build-order comment and every other line as they are.
2. [ ] `WatchEffortRating.swift`: move `objectWillChange.send()` in `end()` to after `finishSession()` and `noteOwedPrompt` (D-54) — symbol: `WatchEffortRatingState.end`.
3. [ ] `WatchEffortRating.swift`: the same move in `confirm()`, after `engine.recordEffortRating` — symbol: `WatchEffortRatingState.confirm`.
4. [ ] Add S-55 to `WatchEffortRatingTests.swift` with a suspending store stub (a `WatchSessionStore` whose `append` waits on a continuation), asserting every notification sees a settled state — red before step 2.
5. [ ] Add S-47's store-level half to `WatchEffortRatingTests.swift` alongside `testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer`, over `FileWatchSessionStore` rather than a shared object.
6. [ ] Read the whole diff for a shell line that assumes a non-suspending store; the only two are the two fixed here (the bump after End and the bump after an answer).
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (275 + Phase 1's cases, 0 failing), `.github/copilot/scripts/macos/gateway.sh lint` (196 issues, 0 errors), `.github/copilot/scripts/macos/gateway.sh test` (3945 passing / 1 skipped / 0 failing)
**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`
**Governor/owner steps (not agent-runnable):** the governor builds the watch scheme (`xcodebuild`, the shell file is outside the Swift package, so `swift-test` cannot compile it); the owner then runs `docs/watch-app-setup-and-qa.md` step 17 and the two kill steps (11 and the wrist-logging walkthrough's force-quit), which is the only check that observes the shipped shell.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: Docs, walkthrough and the residue sweep for 4a (@developer)
1. [ ] `docs/watch_session_sync.md:224`: replace "Nothing logged on the wrist survives a relaunch" with what does survive (the session, its rows, its timers, an owed rating question) and what does not (the projection lens, D-50) — symbol: the bullet list under "What this cannot do today" / "What the wrist cannot do yet".
2. [ ] `docs/state_management/watch_surface.md:393`: the store is durable; keep the sentence about what a relaunch loses to D-50, and keep the two "smaller gaps" intact.
3. [ ] `docs/watch-app-setup-and-qa.md:25`: the store row reads "append-only file store; survives a relaunch" instead of "in-memory only".
4. [ ] `docs/watch-app-setup-and-qa.md:193,425`: the two force-quit sentences stop promising loss, and step 17 drops "(needs the durable store — PR 4)"; mark the kill steps and step 17 **(owner — runs on hardware/simulator)**.
5. [ ] `docs/plans/2026-10-05-15-watch-session-sync-index.md`: PR 4's row loses "Conditional", reads **4a / 4b** with its track and its full-plan link, and §"See also" gains the PR 4 entry; the Status and Next handoff lines move to PR 4; the "See also" sentence about D-51 becomes "its D-51 keeps pruning unscheduled — PR 2b's D-27 deferral stands".
6. [ ] Residue sweep, pasted into the evidence file: `grep -rn "InMemoryWatchSessionStore" ios/` returns only the file store's replacement in `ContentView.swift` — no in-memory construction left in the shell; `grep -rn "in-memory only\|Nothing logged on the wrist survives" docs/` returns nothing outside `docs/history/` and the dated release notes; `grep -rn "durable store" docs/` returns no "not runnable yet".
7. [ ] State the two touched docs' sizes against the 52 KB band in the evidence file, and run `test/docs_indexing_contract_test.dart` (part of `flutter test`) as the 64 KiB guard.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh test` (3945 / ~1 / 0), `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing), plus the three sweep greps with their output pasted into `<plan>.evidence.md`
**Predicted Files**: `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-05-15-watch-session-sync-index.md`, `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/2026-10-06-15e-watch-session-sync-pr4-plan.evidence.md`
**Phase 3 verification notes (Conductor, date):** —

### Phase 4: The engine's own bookkeeping, both stacks (@developer) — PR 4b
No file store is needed: every case here runs over `InMemoryWatchSessionStore` (or a test double), so this phase can run before or after PR 4a.
1. [ ] Swift `WatchSessionEngine.pruneConfirmed()` (`WatchSessionEngine.swift:1508`): drop each dropped id from `entryCorrections` and `deletedEntryIds` — symbol: `pruneConfirmed`.
2. [ ] Dart `WatchSessionEngine.pruneConfirmed()` (`watch_session_engine.dart:1365`): the same, on `_entryCorrections` and `_deletedEntryIds`.
3. [ ] Swift `storeSnapshotEntry` (`WatchSessionEngine.swift:724`): scope the held-id test to the snapshot's session — symbol: `storeSnapshotEntry`.
4. [ ] Dart `_storeSnapshotEntry` (`watch_session_engine.dart:704`): the same.
5. [ ] Dart `WatchLoggingState.canLog` (`lib/watch/logging/watch_logging_state.dart:183`): require an active session (D-55) — symbol: `canLog`.
6. [ ] Extend the existing prune cases with S-48's second half — a re-carried id after a prune — in `WatchSessionEngineTests.swift` (the `S-005` retention cases around `:350,374`) and `test/watch_session_engine_test.dart` (`:462,503`).
7. [ ] Add S-56 in `WatchPhoneEntriesTests.swift` (the re-statement cases, `:137,247`) and `test/watch_session_projection_test.dart` (`S-35`'s cases; name the second-session case after S-56).
8. [ ] Add S-52's Dart half to `test/watch_logging_surfaces_test.dart` next to `no session means nothing to log` (`:486`), over a session ended by `finishSession()` and over one the phone completed — the mirror of `WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto` / `…testS029aAPhoneCompletionClosesTheLoggingSurface`.
9. [ ] Prove each of steps 1–5 by running its case before the fix: the new Swift and Dart cases are red first (the PR 3 review measured exactly this for G3: the re-carried id comes back with the stale value).
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing; 275 plus any phases already landed), `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_projection_test.dart test/watch_logging_surfaces_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh lint` (196 issues, 0 errors)
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `lib/watch/session/watch_session_engine.dart`, `lib/watch/logging/watch_logging_state.dart`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`, `test/watch_session_engine_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_logging_surfaces_test.dart`
**Phase 4 verification notes (Conductor, date):** —

### Phase 5: Docs for 4b (@developer)
1. [ ] `docs/state_management/watch_surface.md:663` (the "Two prunes" bullet): a pruned row takes its correction and deletion marker with it (D-52), and the held-id check is scoped to the session the snapshot names (D-53).
2. [ ] `docs/state_management/watch_surface.md:74-92` (the re-statement paragraph under "What this phone asserts is its own session"): the re-statement is per session — an `entryId` held in two sessions folds only onto the row of the session named (D-53).
3. [ ] Record in the evidence file that no feature doc claims the Dart twin's `canLog` rule (F-9); the two surfaces now agree and each has its own test (S-52).
4. [ ] Residue sweep in the evidence file: `grep -rn "canLog" docs/` returns no sentence claiming the Dart twin refuses nothing, and nothing in `docs/` still describes a prune as keeping the corrected row's lens.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh test` (3945 / ~1 / 0), `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing), plus the sweep grep pasted into `<plan>.evidence.md`
**Predicted Files**: `docs/state_management/watch_surface.md`, `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/2026-10-06-15e-watch-session-sync-pr4-plan.evidence.md`
**Phase 5 verification notes (Conductor, date):** —

## Files Affected

**PR 4a**
- `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` — new (Phase 1)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift` — new (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift` — F-6 (Phase 2)
- `ios/OmniTrain Watch App/ContentView.swift` — the durable store (Phase 2)
- Tests: `WatchEffortRatingTests.swift` (Phase 2)
- Docs: `watch_session_sync.md`, `state_management/watch_surface.md`, `watch-app-setup-and-qa.md`, and the series index (Phase 3)

**PR 4b**
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` — G2, G3 (Phase 4)
- `lib/watch/session/watch_session_engine.dart` — G2, G3 (Phase 4)
- `lib/watch/logging/watch_logging_state.dart` — F-9 (Phase 4)
- Tests: `WatchSessionEngineTests.swift`, `WatchPhoneEntriesTests.swift`, `WatchLoggingSurfacesTests.swift`, `test/watch_session_engine_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_logging_surfaces_test.dart` (Phase 4)
- Docs: `state_management/watch_surface.md` (Phase 5)

Dependents that only read a touched surface (no edit): `WatchSessionStartPaths.swift`, `WatchPhonePreferences.swift`, `WatchNutritionState.swift`, the Rust-free `lib/watch/debug/` entrypoints, and every Dart test that builds `InMemoryWatchSessionStore`.

## Notes

- **PR 4a's order is a dependency chain**: Phase 2's shell swap needs Phase 1's class, and Phase 3
  documents both. Phases 1 and 2 could be merged at the cost of one long run.
- **PR 4b is independent of 4a.** Phases 4 and 5 touch no store file; every Phase 4 case runs over
  `InMemoryWatchSessionStore` or a test double. 4b may land before 4a; if it does, 4a's `swift-test`
  baseline is 275 plus Phase 4's cases.
- Intermediate state after Phase 1: two Swift stores, one shell, no behaviour change. The package is
  green and the app is exactly as it was.
- Intermediate state after Phase 2: the durable store is live; 4b's guards are not yet in, so a prune
  (tests and the Dart debug surface only, D-51) can still leave the lens behind, and the Dart twin's
  `canLog` is looser than the shipped Swift one.
- The registry/ordering trap noted in this project does not apply here: this PR registers no stats
  signal and adds no `buildSignalRegistry` entry.
- The file grows by one line per record and is never compacted in production (D-51): the two prunes
  exist, are tested, and are called only by the tests and the Dart debug surface, so a bound on the
  file is a follow-up for when its size matters.
- `swift test` cannot compile `ios/OmniTrain Watch App/`, so the shell's one-line change is verified by
  the governor's build and the owner's walkthrough — recorded as such, not claimed by an agent.

## Progress

| Phase | State |
|---|---|
| 1 — the file store (4a) | **complete** — `swift-test` 284 passing / 0 failing (275 baseline + 9 new), `test` 3945 passing / 0 failing, `lint` 196 issues / 0 errors (unchanged); S-44…S-47, S-49…S-51, S-53, S-54 green; S-004 green unedited; S-48 deferred to 4b (A-30); evidence in `.evidence.md` |
| 2 — the shell and the rating surface (4a) | not started |
| 3 — docs, walkthrough and the sweep for 4a | not started |
| 4 — the engine's bookkeeping, both stacks (4b) | not started |
| 5 — docs for 4b | not started |

## Assumption Log

| A | Phase | Decision, options considered, choice |
|---|---|---|
| A-25 | plan | Wire format: a JSON-lines file vs one JSON document rewritten per append vs SwiftData vs a raw SQLite dependency. Chosen: JSON-lines, because `WatchRecords.swift` already has `toJson`/`fromJson` per record, a torn line costs one record rather than the file, and no new dependency or schema is introduced. |
| A-26 | plan | Where the rating prompt's durability comes from: nothing new. `WatchEffortRatingState.restore()` already reads `store.readAll().ratingPrompts` and `end()` already stores the prompt row before returning — the in-memory store was the only reason a kill lost it. |
| A-28 | plan | The lens (`entryCorrections`, `deletedEntryIds`): persist it, or accept the loss. Chosen: accept it (D-50), because persisting a projection makes a second representation to keep in step, and PR 3's re-statement makes the next Sync rebuild it exactly. |
| A-29 | plan | A session left in progress resumes and never expires (D-57's store keeps it): accept it, because the resume is the point of a durable store and the phone's Sync-ends-wrist rule clears the session when the phone finished it. The owner-visible question is recorded under `## Open questions`. |
| A-30 | 1 | Phase 1 step 8 lists S-48 among the two-engine cases, but S-48 is AC10 — the G3 prune-takes-the-lens case, which is Phase 4's bookkeeping (4b). Chosen: implement S-44…S-47 only and leave S-48 to Phase 4, following the brief that scoped this run. |
| A-31 | 1 | S-45's plan fixture drives `WatchSyncOrchestrator.sync()`; the brief names the relaunched engine's `pendingObservations()`. Chosen: the brief's observable — the same "what does the relaunched engine re-send" one layer below the transport, and the transport layer is already covered elsewhere. |
| A-32 | 1 | S-44's plan fixture names loads 60/60/62.5 kg; the brief prescribes the suite's shared `setEvent` helper. Chosen: the shared helper (reps 5, 80 kg), because the scenario's outcome is that the payload survives the process, not what the payload says. |
| A-33 | 1 | S-51's plan fixture is S-44's store with two more sets; the brief prescribes five rows plus a re-append of a stored id. Chosen: the brief's fixture, and a prune-then-append stage was added, because the brief's five mutations cannot tell "highest stored sequence + 1" from "row count + 1" and a prune is the only thing that separates them (mutation f). |

## Feedback

[empty]

## Open questions (owner-visible)

1. **An edit that arrived just before the watch app was killed is not remembered until the next Sync.**
   If the phone corrected a set the wrist holds, and the wrist is killed before it syncs again, the
   wrist shows the phone's *uncorrected* value until the next Sync, when it converges again.
   *Recommended: accept it — you cannot see the difference except by looking at the wrist between the
   kill and the Sync, and nothing is lost.*
2. **A deleted set can reappear on the wrist after a kill, until the next Sync.** The phone sends no
   deletions today (PR 3), so this is only reachable from the wrist's End.
   *Recommended: accept it, and revisit with the deletion work in PR 5.*
3. **A session left in progress on the wrist now stays there until someone ends it.** With a durable
   store the wrist resumes the session that was in progress when the app was killed — that is the
   point of this PR — so a session someone forgot to End sits on the wrist, with its rest countdown
   derived from wall-clock, until the user ends it on the wrist or the phone's Sync ends it. There is
   no automatic expiry.
   *Recommended: accept it — auto-expiry is a separate product decision, and the phone's
   Sync-ends-wrist rule already clears it when the phone finished that session.*
4. **This PR does not fix the Dart client's own store.** The Wear OS client has no app to run it in
   (`docs/watch-app-setup-and-qa.md` §1), and its store omits two families (preferences and rating
   prompts) that the Swift store now keeps.
   *Recommended: leave Wear OS as it is — it is deferred to its own cloning job — and note the gap.*
5. **Kill-testing step 17 needs you, on hardware or a simulator.** No agent can run the shell: the
   watch app target is outside the Swift package and building it is the governor's step.
   *Recommended: run `docs/watch-app-setup-and-qa.md` steps 11, 17 and the wrist-logging walkthrough's
   force-quit once the governor's build is up.*
