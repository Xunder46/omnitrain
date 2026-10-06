# Feature: watch-session-sync PR 4 — a durable wrist store

> **Split (governor, 2026-10-06).** This plan is two PRs on two tracks (the Swift package plus the
> shell, and the Dart twin). **PR 4a** = Phases 1–3 — the append-only file store, the shell that
> builds it, F-6 (the rating surface notifies after its own mutation) and the docs for 4a. **PR 4b** =
> Phases 4–5 — G3 and F-9 on both stacks, the 4a re-review's small items, all four closed (re-review
> G1: the prune-scope test added; re-review G2: the failed-replace guard added over code that already
> behaved; re-review G3: the ledger amended; re-review G4: the positional-limit note recorded), and
> their docs. The un-scoped held-id check (D-53) with its S-56 is **dropped**: the store dedupes on
> `(recordType, recordId)` store-wide, so its fixture
> cannot be built (A-44). 4a ships the headline: a set logged on
> the wrist survives a kill. **4b does not need the file store — its cases run over the in-memory
> store** (the brief's Part C re-review G1/G2 cases are the exception: they run over `FileWatchSessionStore`,
> whose `compact` gains one line from review fix 2, H1 / A-47) — so it can land before or after 4a; it is sequenced second only because 4a is the
> owner-visible win. The governor commits per phase.

> Status: **PR 4a built (Phases 1–3 complete, review fix 1 applied); PR 4b built (Phases 4–5 complete,
> review fix 2 applied)** — outstanding: the owner's walkthrough of QA steps 11 and 17 on hardware,
> the governor's `xcodebuild` of the watch shell, and the reviews of 4a and of 4b.
> Next handoff: **@code-reviewer (PR 4b)**; 4a's review fix 1 is applied and the re-review's G1–G4 are
> closed here
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
correct while the store never suspends. Two further carried defects, on both stacks, are PR 4b: the
Dart logging surface's missing status guard (F-9) and the projection lens the two prunes leave behind
(G3). Neither touches the store: the third, the un-scoped held-id check (D-53), is dropped with its
S-56 (A-44).

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
| **D-47** | **Every append is durable before it returns.** No batching, no timer, no flush on suspend: `append` writes and closes before it returns, which is what makes "killed mid-set" a case with an answer, and that one write is the only file I/O an append does (the cache, D-43, holds the rest). `append` also remains the no-op-by-id it is today — a record whose `(recordType, recordId)` is already stored returns the stored row without a second line. **Amended after review fix 1:** a write that fails is *reported to the caller as not stored* — the row stays out of the cache (so `readAll` never returns it) while still carrying the sequence it was assigned and being returned, so the engine's newest-row pick still sees it. "Durable before it returns" describes the successful path, not a claim that a failed write landed. |
| **D-48** | **Two stores, one output.** For the same append and prune sequence, `FileWatchSessionStore.readAll()` returns the same `WatchStoreContents` as `InMemoryWatchSessionStore`, all nine families included — including `preferences` and `ratingPrompts`, which a restore reads (`WatchPhonePreferences.restore`, `WatchEffortRatingState.restore`) and which a store that omitted them would silently lose. `InMemoryWatchSessionStore` stays, as the tests' and desktop runs' store. |
| **D-49** | **The Dart twin is untouched by this PR, and that is deliberate.** It already has a durable store (`lib/watch/session/hive_watch_session_store.dart`, one Hive box per record family) and no shipping host — `docs/watch-app-setup-and-qa.md` §1 records no Wear OS app, no Gradle target and no transport. Adding a second on-disk format there would be a format to keep in step for no user-visible gain. Its `canLog` guard is still corrected (D-55), because that is a rule both clients share, not a storage question. |
| **D-50** | **The projection lens stays memory-only, and the loss self-heals.** `entryCorrections` and `deletedEntryIds` are not persisted: after a relaunch the stored rows are the truth, and the next Sync re-states the phone's own entries (PR 3's D-35) and re-applies any `correct_entry`, so the wrist converges again. What a relaunch does rebuild is unchanged and sufficient: `acknowledgedObservationIds` from stored confirmations, `appliedChangeIds` from `chg-`-prefixed session rows, `current` from the newest session row. Consequence, owner-visible: between a relaunch and the next Sync an edited entry shows the phone's *un*edited payload, and a deleted entry (which no phone sender exists for yet — PR 3's D-38) can show again. Both clear on Sync. |
| **D-51** | **Pruning stays unscheduled; the file is never compacted in production.** The earlier "production pruning on a receipt" entry and its scenario (S-57) are **dropped**: nobody asked for it, and `store.readAll()` runs only at restore (`WatchEffortRating.swift:129`, `WatchPhonePreferences.swift:117`, `WatchSessionEngine.swift:106`, `WatchStartPaths.swift:290`, `WatchNutritionState.swift:116`), so an ever-growing file is not a cost on the hot path; scheduling a prune is also the one place this PR could regress the owed rating question and `WatchLoggingState.nextRoundNumber` (`:311`). **PR 2b's D-27 deferral of pruning therefore stands** — this entry supersedes only its "together with durability" half, not the deferral. A bound is a follow-up for when the file size matters. `pruneConfirmed` / `pruneSensorSamples` stay implemented and tested (S-48, S-54): the store contract requires them and the tests and the debug surface call them. **Amended after review fix 1:** unchanged in meaning — pruning is still unscheduled; what the fix adds is that a prune which cannot be written reports it and drops nothing (F2, re-review G1), and the lens half of S-48 is implemented in PR 4b (D-52). |
| **D-52** | **G3: a pruned row takes its lens with it.** `pruneConfirmed` drops each dropped observation's `entryCorrections[id]` and `deletedEntryIds` marker as well as the row, in both stacks (Swift `WatchSessionEngine.swift:1508`, Dart `watch_session_engine.dart:1365`). Without it a re-carried id is appended as a fresh row and the stale correction overrides it — a correction surviving the row it corrected. With pruning unscheduled (D-51) the only callers are the tests and the Dart debug surface, so the defect is latent today; it is fixed now so the lens cannot outlive its row once a prune is scheduled later. |
| **D-53** | **Dropped (the un-scoped held-id check): the re-statement check is not scoped to the session.** The store dedupes on `(recordType, recordId)` store-wide (`InMemoryWatchSessionStore.append`, `FileWatchSessionStore.appendLocked`), so one `entryId` can never be held for two sessions: S-56's fixture cannot be built through the engine, and scoping the check would make `storeSnapshotEntry` call `store.append`, get the *other* session's row back and append a duplicate of it to the engine's own list. `storeSnapshotEntry` / `_storeSnapshotEntry` stay exactly as they are (A-44). |
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
| AC11 | ~~One `entryId` in two sessions is never folded across~~ — **dropped (the un-scoped held-id check, D-53)**: the store's store-wide dedupe makes the two-session fixture unbuildable, so nothing is folded across | — |

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `InMemoryWatchSessionStore` | 30 files: 25 Dart test files, 4 Dart debug mains, `ios/OmniTrain Watch App/ContentView.swift:56`, and `Sources/WatchSessionEngine/WatchSessionStore.swift:133` itself | The shell's single construction changes to the file store; the in-memory store stays for tests, desktop runs and the debug mains. Nothing else moves. | D-48, D-57, S-54 |
| `WatchSessionStore` implementations | Swift: protocol + `InMemoryWatchSessionStore`; Dart: `watch_session_store.dart`, `in_memory_watch_session_store.dart`, `hive_watch_session_store.dart` | A third Swift implementation joins the contract; S-004's surface check extends to it with no test edit. | S-004 (unchanged), S-54 |
| `pruneConfirmed` callers | Swift tests `WatchSensorRecordingTests.swift:519,617`, `WatchSessionEngineTests.swift:350,374,641`, `WatchNutritionQuickLogTests.swift:264`; Dart `test/watch_session_engine_test.dart:462,503`, `test/watch_sensor_recording_test.dart:706`, `test/watch_nutrition_quick_log_test.dart:422`, `lib/watch/debug/watch_session_debug_surface.dart:276`. **No production caller** (the earlier F-10); with pruning unscheduled (D-51) none is added. | G3 changes what a prune drops, so every existing prune case is extended rather than left to pass by accident. | S-48 |
| `entryCorrections` / `deletedEntryIds` | Swift `WatchSessionEngine.swift:65,66,198,200,727,821,825,826`; Dart `watch_session_engine.dart:105,106,215,216,710,871,881,882` | G3 touches two sites per stack (the prune path); the un-scoped held-id check's third site is dropped (D-53). The projection's meaning (PR 3's D-35 re-statement, D-38 deletion) is unchanged, and the lens staying memory-only is now a stated decision with a stated consequence (D-50). | S-48 and PR 3's S-35 / S-36 |
| `canLog` | `lib/watch/logging/watch_logging_state.dart:183`, `WatchLoggingState.swift:198`; readers `test/watch_logging_surfaces_test.dart:511,539,576,643`, `WatchLoggingSurfacesTests.swift:380,413` | Dart becomes stricter and the two clients agree. Existing Swift cases are untouched. | D-55, S-52 |
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

### S-56: one `entryId` in two sessions — **dropped (the un-scoped held-id check, D-53).** The store dedupes on `(recordType, recordId)` store-wide, so two sessions cannot both hold one `entryId` and the fixture cannot be built through the engine (A-44).

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
1. [x] `ios/OmniTrain Watch App/ContentView.swift` `init()` (`:56`): build `FileWatchSessionStore(directory:)` from `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-session", isDirectory: true)` in place of `InMemoryWatchSessionStore()`, leaving the D-21 build-order comment and every other line as they are.
2. [x] `WatchEffortRating.swift`: move `objectWillChange.send()` in `end()` to after `finishSession()` and `noteOwedPrompt` (D-54) — symbol: `WatchEffortRatingState.end`.
3. [x] `WatchEffortRating.swift`: the same move in `confirm()`, after `engine.recordEffortRating` — symbol: `WatchEffortRatingState.confirm`.
4. [x] Add S-55 to `WatchEffortRatingTests.swift` with a suspending store stub (a `WatchSessionStore` whose `append` waits on a continuation), asserting every notification sees a settled state — red before step 2.
5. [x] No store-level S-47 half here — **DROPPED** by the Phase 2 brief; Phase 1's `testS47TheOwedRatingQuestionSurvivesTheKill` proves S-47 over the file store already (see A-35).
6. [x] Read the whole diff for a shell line that assumes a non-suspending store; the only two are the two fixed here (the bump after End and the bump after an answer).
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (275 + Phase 1's cases, 0 failing), `.github/copilot/scripts/macos/gateway.sh lint` (196 issues, 0 errors), `.github/copilot/scripts/macos/gateway.sh test` (3945 passing / 1 skipped / 0 failing)
**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`
**Governor/owner steps (not agent-runnable):** the governor builds the watch scheme (`xcodebuild`, the shell file is outside the Swift package, so `swift-test` cannot compile it); the owner then runs `docs/watch-app-setup-and-qa.md` step 17 and the two kill steps (11 and the wrist-logging walkthrough's force-quit), which is the only check that observes the shipped shell.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: Docs, walkthrough and the residue sweep for 4a (@developer)
1. [x] `docs/watch_session_sync.md:224`: replace "Nothing logged on the wrist survives a relaunch" with what does survive (the session, its rows, its timers, an owed rating question) and what does not (the projection lens, D-50) — symbol: the bullet list under "What this cannot do today" / "What the wrist cannot do yet". — the bullet now reads "A relaunch keeps what the wrist logged, with two gaps", citing the file-store cases.
2. [x] `docs/state_management/watch_surface.md:393`: the store is durable; keep the sentence about what a relaunch loses to D-50, and keep the two "smaller gaps" intact. — the paragraph now says the shell builds `FileWatchSessionStore` over Application Support and the engine is restored at launch; both gaps kept verbatim.
3. [x] `docs/watch-app-setup-and-qa.md:25`: the store row reads "append-only file store; survives a relaunch" instead of "in-memory only". — done, as "**append-only file store** — survives a relaunch".
4. [x] `docs/watch-app-setup-and-qa.md:193,425`: the two force-quit sentences stop promising loss, and step 17 drops "(needs the durable store — PR 4)"; mark the kill steps and step 17 **(owner — runs on hardware/simulator)**. — done; a third force-quit-loss sentence (`:479`, "A force-quit loses the session and any owed question") was deleted too, and steps 11/17 are marked **(owner)** (A-37).
5. [x] `docs/plans/2026-10-05-15-watch-session-sync-index.md`: PR 4's row loses "Conditional", reads **4a / 4b** with its track and its full-plan link, and §"See also" gains the PR 4 entry; the Status and Next handoff lines move to PR 4; the "See also" sentence about D-51 becomes "its D-51 keeps pruning unscheduled — PR 2b's D-27 deferral stands". — already in place at this base (the governor's split); verified and left untouched, per the brief.
6. [x] Residue sweep, pasted into the evidence file: `grep -rn "InMemoryWatchSessionStore" ios/` returns only the file store's replacement in `ContentView.swift` — no in-memory construction left in the shell; `grep -rn "in-memory only\|Nothing logged on the wrist survives" docs/` returns nothing outside `docs/history/` and the dated release notes; `grep -rn "durable store" docs/` returns no "not runnable yet". — all three clean over the live docs; see the evidence file's Phase 3 section (the one live-doc hit is `nutrition_state.md`'s unrelated maintenance hint).
7. [x] State the two touched docs' sizes against the 52 KB band in the evidence file, and run `test/docs_indexing_contract_test.dart` (part of `flutter test`) as the 64 KiB guard. — sizes not measurable (`wc` denied): the guard passed all nine cases, including the band check; recorded in the evidence file.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh test` (3945 / ~1 / 0), `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing), plus the three sweep greps with their output pasted into `<plan>.evidence.md`
**Predicted Files**: `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-05-15-watch-session-sync-index.md`, `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/2026-10-06-15e-watch-session-sync-pr4-plan.evidence.md`
**Phase 3 verification notes (Conductor, date):** —

### Phase 4: The engine's own bookkeeping, both stacks (@developer) — PR 4b
No file store is needed: every case here runs over `InMemoryWatchSessionStore` (or a test double), so this phase can run before or after PR 4a.
1. [x] Swift `WatchSessionEngine.pruneConfirmed()` (`WatchSessionEngine.swift:1508`): drop each dropped id from `entryCorrections` and `deletedEntryIds` — symbol: `pruneConfirmed`. — done (+7 lines, D-52); `testS48APrunedRowTakesItsCorrectionWithIt` / `…TakesItsDeletionMarkerWithIt` green, both red under the mutation that removes the loop.
2. [x] Dart `WatchSessionEngine.pruneConfirmed()` (`watch_session_engine.dart:1365`): the same, on `_entryCorrections` and `_deletedEntryIds`. — done (+7 lines, D-52); the two `S-48 a pruned row takes its lens with it (G3)` cases green, both red under the same mutation.
3. [ ] **Dropped (the un-scoped held-id check, D-53, A-44):** Swift `storeSnapshotEntry`'s held-id check stays store-scoped; scoping it per session would hand back the other session's row.
4. [ ] **Dropped (the un-scoped held-id check, D-53, A-44):** the Dart `_storeSnapshotEntry` twin of step 3.
5. [x] Dart `WatchLoggingState.canLog` (`lib/watch/logging/watch_logging_state.dart:183`): require an active session (D-55) — symbol: `canLog`. — done (6 changed lines); both S-52 cases green, both red with the old rule.
6. [x] Extend the existing prune cases with S-48's second half — a re-carried id after a prune — in `WatchSessionEngineTests.swift` (the `S-005` retention cases around `:350,374`) and `test/watch_session_engine_test.dart` (`:462,503`). — done: two cases per stack, one for the phone's correction and one for its deletion marker.
7. [ ] **Dropped (the un-scoped held-id check, D-53, A-44):** S-56's cases in `WatchPhoneEntriesTests.swift` and `test/watch_session_projection_test.dart` — no fixture can be built through the engine.
8. [x] Add S-52's Dart half to `test/watch_logging_surfaces_test.dart` next to `no session means nothing to log` (`:486`), over a session ended by `finishSession()` and over one the phone completed — the mirror of `WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto` / `…testS029aAPhoneCompletionClosesTheLoggingSurface`. — done: `S-52 the wrist's own End closes the logging surface` and `S-52 a session the phone ended is not a surface to log into`.
9. [x] Prove each of steps 1–5 by running its case before the fix: the new Swift and Dart cases are red first (the PR 3 review measured exactly this for G3: the re-carried id comes back with the stale value). — the three fixes landed before their cases in this run, so the red evidence is a mutation round instead: removing each fix turns exactly its cases red (Swift 6 failures, Dart 4), originals restored and green after (evidence §PR 4b).
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing; 275 plus any phases already landed), `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_projection_test.dart test/watch_logging_surfaces_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh lint` (196 issues, 0 errors)
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `lib/watch/session/watch_session_engine.dart`, `lib/watch/logging/watch_logging_state.dart`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`, `test/watch_session_engine_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_logging_surfaces_test.dart` — **as run:** `WatchPhoneEntriesTests.swift` and `test/watch_session_projection_test.dart` are untouched (step 7 dropped), `WatchFileStoreTests.swift` joins them for the brief's Part C cases re-review G1/G2 (A-47), and the store itself changes by one line for review fix 2 (H1, A-48).
**Phase 4 verification notes (Conductor, date):** `swift-test` **294 passing / 0 failing** (290 baseline + 4: two S-48 cases, re-review G1, re-review G2); `test` **3949 passing / 1 skipped / 0 failing** (3945 baseline + 4); the brief's targeted Dart run (`test/watch_session_engine_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_logging_surfaces_test.dart`) 71 passing / 0 failing; `lint` **196 issues / 0 errors** (no issue in a touched file); the hive-import invariant grep empty; the mutation round 6 red (Swift) and 4 red (Dart), all restored. See `.evidence.md` §PR 4b and A-43.
**Phase 4b verification notes (review fix 2, H1–H3):** `FileWatchSessionStore.compact`'s staging-write failure path now removes the partial `.tmp` (A-48); `swift-test` **294 passing / 0 failing** after the change.

### Phase 5: Docs for 4b (@developer)
1. [x] `docs/state_management/watch_surface.md:663` (the "Two prunes" bullet): a pruned row takes its correction and deletion marker with it (D-52), and the held-id check is scoped to the session the snapshot names (D-53). — the D-52 half is a new bullet under §Invariants (opening **A prune that cannot be written replaces nothing…**, next to the bullet the plan names), naming the two watchOS S-48 cases and the Dart `S-48 a pruned row takes its lens with it (G3)` group; the D-53 half is dropped with D-53.
1b. Also cite the Dart twin's S-52 cases on the existing "An ended session is no longer a logging surface" sentence (`:389`), which until F-9 was only true of the Swift shell. — done; no sentence deleted, three lines appended.
2. [ ] **Dropped (D-53, A-44):** the re-statement paragraph's per-session sentence — nothing in `docs/` claims the check is per session, and no fixture can show it.
3. [x] Record in the evidence file that no feature doc claims the Dart twin's `canLog` rule (F-9); the two surfaces now agree and each has its own test (S-52). — recorded: no live doc stated the Dart twin's rule at all, so there was no false claim to correct; the one sentence that states the rule for the Swift shell gained the Dart citations under 1b.
4. [x] Residue sweep in the evidence file: `grep -rn "canLog" docs/` returns no sentence claiming the Dart twin refuses nothing, and nothing in `docs/` still describes a prune as keeping the corrected row's lens. — clean; both sweeps pasted in the evidence file.
5. [x] The brief's Part C items (re-review G1–G4): re-review G1 and re-review G2 are new watchOS cases over code that already behaved (`WatchFileStoreTests.swift`, A-47), re-review G3 is the ledger amendments D-47/D-51 (A-43), re-review G4 is A-45, and the new invariant bullet names all three file-store cases.
**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (0 failing), `.github/copilot/scripts/macos/gateway.sh test` (3945 / ~1 / 0), `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failing), plus the sweep grep pasted into `<plan>.evidence.md`
**Predicted Files**: `docs/state_management/watch_surface.md`, `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/2026-10-06-15e-watch-session-sync-pr4-plan.evidence.md`
**Phase 5 verification notes (Conductor, date):** `test test/docs_indexing_contract_test.dart` 9 passing / 0 failing (inside the whole-suite run, and alone both before and after the last doc edit); `test` 3949 passing / 1 skipped / 0 failing, run after the doc bullet and again over the finished tree; `swift-test` 294 passing / 0 failing; `lint` 196 issues / 0 errors, none in a touched file; both residue sweeps clean over the live docs; the edits are in `docs/state_management/watch_surface.md` only (one new bullet, no sentence deleted, plus three added lines after the ended-session sentence at `:389` citing the Dart twin's S-52 tests — F-9 makes that sentence true of both stacks and the doc rule wants a test per platform). See `.evidence.md` §PR 4b.

## Files Affected

**PR 4a**
- `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` — new (Phase 1)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift` — new (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift` — F-6 (Phase 2)
- `ios/OmniTrain Watch App/ContentView.swift` — the durable store (Phase 2)
- Tests: `WatchEffortRatingTests.swift` (Phase 2)
- Docs: `watch_session_sync.md`, `state_management/watch_surface.md`, `watch-app-setup-and-qa.md`, and the series index (Phase 3)

**PR 4b**
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` — G3 (Phase 4)
- `lib/watch/session/watch_session_engine.dart` — G3 (Phase 4)
- `lib/watch/logging/watch_logging_state.dart` — F-9 (Phase 4)
- `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` — review fix 2 (H1): `compact`'s staging-write failure path now removes the partial `.tmp` before returning; otherwise the 4a file, whose Part C cases re-review G1/G2 pin the behaviour it already had (A-47)
- Tests: `WatchSessionEngineTests.swift`, `WatchFileStoreTests.swift` (re-review G1/G2), `test/watch_session_engine_test.dart`, `test/watch_logging_surfaces_test.dart` (Phase 4)
- Docs: `state_management/watch_surface.md` (Phase 5)

Dependents that only read a touched surface (no edit): `WatchSessionStartPaths.swift`, `WatchPhonePreferences.swift`, `WatchNutritionState.swift`, the Rust-free `lib/watch/debug/` entrypoints, and every Dart test that builds `InMemoryWatchSessionStore`.

## Notes

- **PR 4a's order is a dependency chain**: Phase 2's shell swap needs Phase 1's class, and Phase 3
  documents both. Phases 1 and 2 could be merged at the cost of one long run.
- **PR 4b is independent of 4a.** Phases 4 and 5 touch no store file; every Phase 4 case runs over
  `InMemoryWatchSessionStore` or a test double — the brief's Part C cases re-review G1 and G2 are the
  exception: they run over `FileWatchSessionStore`, and review fix 2 changes one line of it (H1, A-47).
  4b may land before 4a; if
  it does, 4a's `swift-test` baseline is 275 plus Phase 4's cases.
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
| 2 — the shell and the rating surface (4a) | **complete** — `swift-test` 286 passing / 0 failing (284 baseline + 2 new S-55 cases), `lint` 196 issues / 0 errors (unchanged; no Dart file touched); S-55 red before the fix and red under both mutations (a: 3 failures, b: 2); the shell's store swap and `engine.restore()` are written but compiled only by the governor's `xcodebuild`; evidence in `.evidence.md` |
| 3 — docs, walkthrough and the sweep for 4a | **complete** — `swift-test` 287 passing / 0 failing (286 baseline + 1: D-50's `testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`), `docs_indexing_contract_test.dart` 9 passing / 0 failing, `test` 3945 passing / 1 skipped / 0 failing (baseline exactly), `lint` 196 issues / 0 errors (unchanged; no Dart file touched), three residue sweeps clean over the live docs, the shell invariant grep empty; the D-50 case proven non-vacuous by mutation (expected 60→65 red, restored, green); evidence in `.evidence.md` |
| 4 — the engine's bookkeeping, both stacks (4b) | **complete** — `swift-test` 294 passing / 0 failing (290 baseline + 4: two S-48 cases, re-review G1, re-review G2), `test` 3949 passing / 1 skipped / 0 failing (3945 baseline + 4), `lint` 196 issues / 0 errors (none in a touched file), the hive-import invariant grep empty; every new guard proven by mutation (Swift 6 red, Dart 4 red), originals restored and green after; the un-scoped held-id check's step and S-56 collapsed as dropped (D-53, A-44); review fix 2 applied (H1–H3) — `swift-test` 294 passing / 0 failing again; evidence in `.evidence.md` §PR 4b |
| 5 — docs for 4b | **complete** — one new §Invariants bullet in `docs/state_management/watch_surface.md` (the D-52 lens rule plus the re-review G1/G2 store guards, each naming its tests), plus the Dart twin's S-52 cases cited on the existing "an ended session is no longer a logging surface" sentence (F-9); both residue sweeps clean; `docs_indexing_contract_test.dart` 9 passing / 0 failing; evidence in `.evidence.md` §PR 4b |

### Review fixes (PR 4a and PR 4b)

| Item | State |
|---|---|
| Fix 1 — a failed write must not look durable (review F1–F4) | **complete** — `swift-test` 290 passing / 0 failing (287 baseline + the three guards `testF1AnAppendThatCannotBeWrittenIsNotStoredAndKeepsItsSequence`, `testF2APruneThatCannotBeWrittenPrunesNothing`, `testF3AFileWithoutAMarkerGetsOneAtTheTop`), `docs_indexing_contract_test.dart` 9 passing / 0 failing, `lint` 196 issues / 0 errors (unchanged; no Dart file touched), the hive-import invariant grep empty; all three guards red before the fix (6 failures, with each guard asserting up front that its path is really unwritable) and each red under its own mutation (a: 1, b: 3, c: 2, d: 1), restored and green after each; evidence in `.evidence.md` §Fix 1 |
| Re-review items G1–G4 (PR 4a, closed in 4b) | **complete** — re-review G1 and re-review G2 are two new watchOS cases over code that already behaved (`testG1APruneOfSensorSamplesThatCannotBeWrittenPrunesNothing`, `testG2AFailedReplaceLeavesNoTemporaryFile`) plus the `.tmp`-absent assertions inside F2/G1; re-review G3 is D-47's and D-51's amendment (A-43); re-review G4 is A-45; `swift-test` 294 passing / 0 failing, `lint` 196 issues / 0 errors; both guards proven by mutation; evidence in `.evidence.md` §PR 4b |
| Fix 2 — a partial staging file must not survive a failed write (review H1), and the dropped item's name (H2) and the `canLog` reader lines (H3) | **complete** — `FileWatchSessionStore.compact`'s staging-write `catch` now removes `tempURL` before returning false, mirroring `replaceItemAt`'s failure path; `swift-test` **294 passing / 0 failing** after the change (same counts as before it — the state is unchanged on both sides). No new test: on a read-only directory the staging write fails before creating the file, so the partial-write path the line cleans up is unreachable from a test (`FileManager` offers no way to fail a write after it opened it) — A-48. H2 renames the dropped item from bare "G2" to "the un-scoped held-id check (D-53)" everywhere it names that item and prefixes the 4a re-review's items "re-review G1–G4"; H3 refreshes the `canLog` readers to `test/watch_logging_surfaces_test.dart:511,539,576,643`. |

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
| A-34 | 2 | Governor finding the plan missed: `WatchAppHost.restore()` restored `paths`, `preferences` and `rating` but never `engine`, while every harness calls `engine.restore()` first. Chosen: call `await engine.restore()` first in `restore()`, matching the harnesses, so a relaunch over the file store shows the rows it already holds. |
| A-35 | 2 | The brief drops the plan's Phase 2 step 5 (a store-level S-47 half over `FileWatchSessionStore`): Phase 1's `testS47TheOwedRatingQuestionSurvivesTheKill` already proves S-47 over the file store. Chosen: drop it, and mark the step so the plan and the run agree. |
| A-36 | 2 | In S-55 the armed `append` is the first one after `arm()`, so End suspends inside `engine.finishSession()` rather than at the prompt's own append. Chosen: keep it — the scenario asserts the notification's position relative to the whole commit, and both mutations still turn the cases red. |
| A-37 | 3 | The brief and the plan name two force-quit-loss sentences (`docs/watch-app-setup-and-qa.md:193,425`), but the walkthrough's "known gaps" paragraph carried a third at `:479` — "A force-quit loses the session and any owed question (step 17)." Chosen: delete it, per the brief's log-and-continue rule, because a false loss claim left standing is the exact drift Phase 3 exists to remove. |
| A-38 | 3 | The plan's step 4 says to mark the kill steps and step 17 "**(owner — runs on hardware/simulator)**"; the file's own convention for an owner-run step is a bare bold **(owner)** (step 11 was the only one). Chosen: **(owner)** in both headings, one tag style in the file, with the shell-only reason stated in the step body and in §"What QA passed means". |
| A-39 | 3 | The plan's step 7 asks for each touched doc's size against the 52 KB band; `wc -c` is denied by policy and the docs-guard test reports no size. Chosen: record "not measured" in the evidence file and cite the guard's own band case (`no documentation file is within the warning band of the ceiling`) as the check that would have failed. |
| A-40 | fix 1 | The guards must make a write fail for real, and the host may run as root, where `chmod` does not block writes (`docs/docs-audit-2026-07-26.md:273`). Chosen: the brief's `chmod 0o500` plus `UF_IMMUTABLE` — the file for F1, the directory for F2 — with each guard asserting up front that its path is really unwritable and restoring both in a teardown block. |
| A-41 | fix 1 | Review F4 offers two directions (move the in-memory store to max-of-rows + 1, or move the file store to a counter); the brief fixes the counter (item 1). Chosen: the file store keeps a monotonic `lastSequence` like `InMemoryWatchSessionStore.sequence`, because max-of-cache + 1 can hand out a sequence a row on disk already holds (F2's own consequence) and would reuse a failed write's sequence. The brief also overrides F1's "returned unchanged with sequence 0": the failed row comes back with its fresh sequence, so the engine's newest-row pick still sees it. |
| A-42 | fix 1 | The brief's doc sentence cites F1 only; a first draft also stated the prune behaviour. Chosen: F1 only — the prune paths still have no production caller (D-51), so their failure mode is not yet user-visible behaviour to document. |
| A-43 | 4b | The brief's re-review G3 asks D-47's and D-51's text to describe what exists. Chosen: D-47 gains the failed-write sentence (the row stays out of the cache, still gets a sequence, is returned) and D-51 gains one line saying its meaning is unchanged. This row is the superseding note: review fix 1 changed the code without re-planning the decision text. |
| A-44 | 4b | The plan scoped the held-id check per session (D-53, S-56, AC11, Phase 4 steps 3/4/7). **Dropped by the governor:** the store dedupes on `(recordType, recordId)` store-wide, so one `entryId` can never be held for two sessions — S-56's fixture cannot be built, and scoping the check would make `append` hand back the *other* session's row. Chosen: leave `storeSnapshotEntry` / `_storeSnapshotEntry` as they are and mark all four dropped, numbering kept. |
| A-45 | 4b | The store's version gate reads only the file's **first** line. Chosen: record it, change nothing — a marker-less file is rewritten with a fresh marker at the top (F3), and a newer-version marker that is not on the first line is not recognised. v1 is unreleased and the shell writes the marker itself. |
| A-46 | 4b | S-48's plan fixture says "an ended session" and its outcome repeats the ended-session refusal. Chosen: the S-48 cases run over the session the prune is exercised on — the lens mechanism is status-independent — and the refusal half is S-52's, the scenario the plan already names for it (AC6 lists both). |
| A-47 | 4b | The brief's Part C re-review G1/G2 name `WatchFileStoreTests.swift`, which the plan's Predicted Files omit, and re-review G2's `.tmp` assertion passes vacuously where the *staging write* fails (an unwritable directory). Chosen: add both guards there, add `testG2AFailedReplaceLeavesNoTemporaryFile` (writable directory, immutable file, so the write succeeds and the replace fails) as the one shape that exercises `compact`'s cleanup, and record the file as an addition to the phase's set. |
| A-48 | fix 2 | Review H1's partial-staging cleanup line has no failing test to show red, because the case it covers is unreachable: `compact` writes the `.tmp` first and `FileManager` offers no way to fail a write *after* it created the file (a read-only directory fails before the file exists, which the existing F2/G1 guards already pin). Options: inject a failing writer into the store, or drop the line. Chosen: keep the line with no test — it mirrors `replaceItemAt`'s existing failure path, and the two failure paths must not differ in what they leave behind. Converting the store's `FileManager` calls to an injected seam is unplanned work (a phase-Blocked item), so it is recorded here instead. |

## Feedback

**Review 1 (PR 4a) — `CHANGES_REQUESTED`.** Findings: `<plan>.review.md` §Findings. Fix checklist for
one bounded round, each item with its guard test:

- **F1** (`FileWatchSessionStore.swift:262-270`) — make the write report failure and stop treating a
  failed append as durable (D-47). Guard: an unwritable directory → `append` returns the record
  unchanged with sequence 0 and `readAll()` does not contain it.
- **F2** (`:160-161`, `:183-184`, `:276-300`) — same code path: `compact` must report failure and the
  cache must stay un-pruned when it fails. Guard: failed temp write → pre-prune rows still readable,
  next sequence unchanged.
- F3-F7 are optional; do not extend this PR to take them. F6 is an owner-visible observation for QA
  step 17, not a defect.

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
