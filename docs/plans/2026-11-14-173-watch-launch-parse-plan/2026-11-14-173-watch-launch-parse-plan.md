# Feature: the watch launch no longer parses its whole stored history

> Status: DRAFT awaiting Q&A (owner unavailable — defaults marked "owner to confirm", see Open questions)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md (+ docs/state_management/watch_sensors.md, docs/plans/2026-11-13-156-watch-store-growth-plan/2026-11-13-156-watch-store-growth-plan.md — seeded prior decisions D-15601..D-15607 stand unless superseded here)

## Overview

Plan 156 bounded the per-reading and per-tick cost and added the launch/release prunes
(D-15601..D-15603), but the launch parse is still linear in everything stored. Measured on a
Mac, debug build, after all of plan 156 (`docs/plans/2026-11-13-156-watch-store-growth-plan/
2026-11-13-156-watch-store-growth-plan.evidence.md`, "Re-measurement at 1, 5 and 10 stored hours"):

| Stored outdoor hours | Rows | Launch |
|---|---|---|
| 1 | 5,700 | 0.25 s |
| 5 | 28,500 | 1.23 s |
| 10 | 57,000 | 2.32 s |

The owner's watch has recorded since October; its first launch of any plan-156-era build parses
that whole file once before the launch prune compacts it. And the prunes only bound the size for
acknowledged workouts: an unconfirmed workout keeps its readings up to 14 days
(`WatchSessionEngine.unacknowledgedReadingsRetention`, WatchSessionEngine.swift:1964), so a
fortnight without the phone can still hand the launch tens of thousands of rows.

### Where the time goes at launch (settled, cited)

The launch chain (Swift app target `ios/OmniTrain Watch App/ContentView.swift`, not compiled by
`swift test`):

1. `ContentView.body`'s `.task { await host.restore() }` (ContentView.swift:585-587). The first
   paint does **not** wait for `restore()` — SwiftUI renders the shell from pre-restore state:
   `host.engine.session` is nil and `host.paths` is empty, so the user sees the bare start
   surface (no routines, reachability unknown). `revision += 1` at the end of `restore()`
   (ContentView.swift:384) repaints; a workout the launch adopted is held until restore finishes
   (the D-15004/D-15005 comment at ContentView.swift:318-320), so a recovered workout's logging
   surface appears only after the whole chain below. **What the user sees with a big file: the
   stale start surface for the whole parse+restore duration, and a recovered workout late.**
2. `host.restore()` (ContentView.swift:364-385) first calls `recoverStrandedWorkout()`
   (:366, :391-393) → `engine.storedSession()` → `store.readAll()` (WatchSessionEngine.swift:201-203).
   **This is where the file is parsed**, before `engine.restore()` even runs. The store caches its
   rows (`FileWatchSessionStore.loadRows()` returns the cached array once loaded,
   FileWatchSessionStore.swift:319-321), so the later `engine.restore()` → `store.readAll()`
   (:165) and the seven family restores below re-partition the cached rows without re-reading
   the file.
3. The parse itself (`FileWatchSessionStore.loadRows()`, FileWatchSessionStore.swift:~318-345):
   `Data(contentsOf:)` of the whole file, split on `0x0A`, then per line
   `JSONSerialization.jsonObject` (`parseLine`, :~347-352) and `StoredWatchRecord.fromJson`
   (WatchRecords.swift:858-869). `JSONSerialization` per line is the dominant term; row
   construction is a cheap struct init on top. The linear extras are small by comparison: the
   id-index rebuild (`heldIds = Set(...)`, :345), the type partition in `readAllLocked`
   (:147-186) and `applyConfirmations` (WatchSessionStore.swift:~247-262, only when
   confirmations exist), and the engine's fills — `storedSensorSamples.fill(with:)` rebuilds the
   D-15605 per-session views, WatchSessionEngine.swift:189-194.
4. `engine.restore()`'s own work over the restored contents is per-session-row, not per-reading
   (WatchSessionEngine.swift:164-195). `engine.pruneSettledSensorSamples()` (ContentView.swift:373)
   runs *after* the parse, so it cannot help the launch that pays for it.

So: launch cost = one whole-file decode, and the decode is linear in stored rows. Every other
per-launch pass is over the cached rows and is small.

### What a launch actually needs (the basis for the fix)

Raw readings have exactly three readers, all about the **current** session:

- the live readout's per-kind newest and GPS pace window (`WatchLoggingState.paceWindowStart`
  and friends, WatchLoggingState.swift:548, :1276, :1301, :1351);
- `announceEnergy`'s restart-aware sum of the session's stored counts — the chain that keeps a
  recovered workout's counter from falling to zero (WatchSessionEngine.swift:1903-1911, plan 135
  S-13511);
- `sessionEndEvent`'s summary inputs at the moment the session ends
  (WatchSessionEngine.swift:2112-2114), and the on-watch end summary — which fires only in the
  process that saw the session active (`WatchWorkoutSummary.note` requires `activeSeenId`,
  WatchWorkoutSummary.swift:129-145).

An **ended** session's readings are read by nothing: the summaries went into the `session_end`
observation the first time the session ended (`captureSessionEnd`, WatchSessionEngine.swift:2082,
"no end is ever re-emitted with different values"), the entries and timers are their own rows,
and the phone's acknowledgement state lives in confirmation rows. This is the same conclusion
plan 156's lead review reached for the 14-day valve ("the readings are therefore redundant for
the phone once that row exists").

### Options considered for the smallest change that makes launch independent of OLD data

- **(a) Split readings into per-session side files** — **recommended.** The main file keeps
  every row except ended sessions' raw readings; each ended session's readings live in their own
  JSONL file, written once at the move and deleted by the existing release gates. A launch reads
  the main file only — small rows plus (when one exists) the current active session's readings,
  which the launch genuinely needs. Old data never re-enters the launch path.
- **(b) A size/age cap on unconfirmed workouts' readings** — rejected as the main fix. A row cap
  corrupts the rebuild path (partial readings would recompute *wrong* summaries from
  `sessionEndEvent`'s inputs); an age cap is a shortened D-15602 valve, which bounds the
  unconfirmed accumulation but still makes the launch cost depend on *those* rows — it does not
  give a launch bound independent of old rows, and shortening the 14-day window narrows the
  safety margin D-15602 chose for the end-entry-not-persisted case (owner's call, not ours).
  Not adopted; D-15602 stands unchanged.
- **(c) A compacted snapshot** — rejected: it is what the launch prune's `compact` already does
  (FileWatchSessionStore.swift:~483-513), it bounds nothing for unconfirmed workouts, and it
  cannot keep the current session's readings out of the parse (they are needed).
- **(d) Async/background parse with a placeholder UI** — rejected: the UI already paints before
  `restore()` (`.task`, ContentView.swift:585-587); the symptom is the *stale* surface and the
  late recovered-workout surface, and deferring the parse delays exactly the restore the
  D-15004/D-15005 adoption rules hold a workout for. It hides the cost without removing it.

## Resolved Decisions (Ledger)

- **D-17301 The launch read set is the main file only.** The launch must decode the format
  marker, every session/observation/timer/confirmation/catalog/preference/rating/bests/water
  row, and the readings of a session that is **not** ended — nothing else. A session's readings
  leave the launch set when the session's newest row is terminal (`completed` or `abandoned`,
  WatchSessionEngine.swift:117-121); a session with no session row keeps its readings in the
  launch set (conservative: it cannot be classified, and unclassified readings are the recovery
  case).
- **D-17302 Side files.** Readings of a terminal session move to one JSONL file per session —
  `watch-samples-<sessionId>.jsonl` beside `watch-session.jsonl` (exact name pinned: tests and
  migration read the directory) — with the rows verbatim (ids and sequences unchanged). Side
  files are write-once (a full temp+replace write, the same pattern as `compact`) and are never
  appended to afterwards: the session is over. The main-file row format and the marker version
  are unchanged; no `StoredWatchRecord` change (WatchRecords.swift untouched).
- **D-17303 The move is kill-safe and idempotent.** Order: write the side file (temp + replace)
  first, then rewrite the main file without that session's inline readings via `compact`
  (atomic: temp file + `replaceItemAt`/`moveItem`, FileWatchSessionStore.swift:~483-513 — "a kill
  mid-rewrite leaves either the old file or the new one — never half of each"). A kill between
  the two writes leaves both copies on disk; the next load re-runs the move, rewriting the side
  file wholesale from the inline rows — so no reader ever sees two copies, live or across a kill
  (all under the store's `NSLock`; the both-copies state exists only on disk after a kill).
- **D-17304 The migration is the load-time move.** On every first load, after parsing the main
  file, the store moves any inline readings of terminal sessions (D-17301's rule) and compacts.
  The owner's October file is therefore fully processed at the new build's first launch — one
  full parse (unavoidable: it must be read to be split) plus one atomic compaction — and every
  launch after is a small parse. A load that finds nothing to move writes nothing (D-15603's
  rule). No format-version bump (D-17306's second half): an older binary keeps working exactly
  as today against the main file, and whatever it re-inlines is re-moved at the next new-build
  load.
- **D-17305 The engine moves at the end.** After `storeSessionRow` (WatchSessionEngine.swift:1346)
  appends a session row whose status is terminal — the single writer every end path funnels
  through (:691 phone-snapshot end, :848, :958 lifecycle end; the wrist's own `finishSession`
  :440 reaches the same writer) — the engine asks the store to move that session's readings
  (awaited; session ends are rare, off the per-second path). Aggressive on purpose: a terminal
  session's readings have no reader (Overview), so the move does not wait for the phone's
  receipt; the receipt still gates the *drop* (D-15601's release in `applyReceipt`,
  :988-999, stands unchanged). **Owner to confirm** (Open question 1).
- **D-17306 No format bump, no app-target change.** `ContentView.swift` gains no code: the
  launch chain already reaches the store through `engine.storedSession()` and the family
  restores, and the migration runs inside the store's first load, ahead of everything. The file
  is source-scanned only (Phase 5's sweep).
- **D-17307 Read sets, pinned as a protocol change.** `WatchSessionStore` gains
  `readLaunch() -> WatchStoreContents` — everything except the raw readings of terminal
  sessions. The file store answers from the main file only; `InMemoryWatchSessionStore` answers
  through **one shared free function** beside the rows (precedent: `confirmedWaterTapIds`,
  WatchSessionStore.swift:~176-190), so the twin cannot drift from the store it stands in for.
  `readAll()` keeps its meaning — *everything stored*, including side files — so every existing
  pin keeps holding: S-15601's "what stays on disk" set, S-15603's valve rows and S-15605's
  20,000-row count are all `readAll()` assertions and stay true. Every launch-path reader
  switches to `readLaunch()` (the 10 sites in Existing-Functionality Impact). `pruneSensorSamples`
  loads the named sessions' side files so it still returns *every* dropped record id — the
  engine's in-memory release (`storedSensorSamples.prune { dropped.contains($0.recordId) }`,
  WatchSessionEngine.swift:2021) keeps working across the boundary.
- **D-17308 The settle gate loses its memory-visibility precondition.** With readings outside
  the main file and outside the engine's restored log, `storedSensorSamples.contains(sessionId:)`
  (WatchSessionEngine.swift:2006) would hide terminal sessions from the gate forever (a relaunch
  empties the in-memory log of ended sessions' rows). The precondition is removed: the gate asks
  the store, which answers cheaply from its side-file registry without decoding anything, and a
  session with nothing stored drops nothing and writes nothing (D-15603). The acknowledgement
  gates and the 14-day valve are untouched (D-15601, D-15602 stand).

## Feature Invariants

- **Twin parity, extended:** `InMemoryWatchSessionStore` and `FileWatchSessionStore` answer
  `readLaunch()`, `readAll()`, `archiveSensorSamples` and `pruneSensorSamples` value-for-value
  for the same history — by construction through the shared helper and identical id sets
  (guarded by S-17306).
- **A reading is one row wherever copies of it live:** the move neither loses nor duplicates a
  reading; ids and sequences cross verbatim (guarded by S-17302, S-17303).
- **The active session's readings are never moved and never dropped by anything in this
  feature** — they are the recovery contract (D-17306, guarded by S-17304).
- **A store write that would change nothing does not run** (D-15603, extended to the move: a
  load that finds no movers writes nothing, guarded by S-17302's inode assertion).
- **No app-target code for this feature** (D-17306): `ContentView.swift` is read-only here.

## Requirements

1. A launch decodes a number of rows that does not depend on how many readings old workouts
   stored — counted, not timed (S-17301).
2. An existing October-shaped store is migrated at the new build's first launch, atomically and
   re-runnably (S-17302, S-17303).
3. A workout recovered after a kill keeps its live readout and its energy/step chain; when it
   ends, its readings leave the launch path for every launch after (S-17304).
4. The existing release gates (receipt release, launch prune, 14-day valve) now delete side
   files, with no behaviour change to what they drop (S-17305).
5. No wire, protocol or phone change; no `StoredWatchRecord` change; no behaviour the user sees
   changes except launch latency (D-15607's rule restated).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- Launch decode count is fixture-exact and independent of side-file size → S-17301, S-17307.
- First-launch migration of a large legacy file, idempotent re-run → S-17302, S-17303.
- Recovery after a kill unaffected; post-end launches skip the ended readings → S-17304.
- Release gates delete side files; nothing-to-drop stays a no-op → S-17305.
- Twin parity on the new members → S-17306.
- Replay corpus and every existing store/sensor/race suite green → S-17308.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `store.readAll()` — the launch-path readers | `grep -n "\.readAll()" watch/watchos/Sources` → WatchSessionEngine.swift:165 (`restore`), :202 (`storedSession`), WatchNutritionState.swift:144, WatchWater.swift:132, WatchStartPaths.swift:392, :584, :598, WatchPhonePreferences.swift:197, WatchPersonalBests.swift:86, WatchEffortRating.swift:148 (`WatchPlatformWorkout.swift:627` reaches `storedSession`, so it is covered) | All ten switch to `readLaunch()`; behaviour-neutral until side files exist (a store without them answers identically) | S-17301, S-17308 |
| `readAll()`'s contract | 144 call sites in 29 test files (grep over `watch/watchos/Tests`) — none change | Contract unchanged ("everything stored", now including side files); the twin gains no state change | S-17306 |
| The settled prune gate | WatchSessionEngine.swift:1997-2022; the S-15601/15602/15603 pins in `WatchSensorRecordingTests` (S-237 family) and `WatchStoreGrowthTests` | Loses only the `contains` precondition (:2006); what it drops is unchanged — receipts, acknowledgement and the 14-day valve as today | S-17305, S-17308 |
| `FileWatchSessionStore` prunes/compact | `WatchFileStoreTests` (29 `readAll` sites), G1/G2 pins ("a prune that cannot be written prunes nothing", "a failed replace leaves no temporary file") | `pruneSensorSamples` additionally deletes side files and loads named ones to echo ids; every other prune is untouched; `compact` reused, not modified | S-17305, S-17308 |
| The version gate and old builds | FileWatchSessionStore.swift:~29-31, :~322-327 (an unknown version is read as empty and never written) | No version bump (D-17306); an old build sees the same marker-version-1 file; its re-inlined readings are re-moved at the next new-build load | S-17302 (re-run), Notes |
| `WatchSensorSampleLog` / per-session views (D-15605) | readers: WatchLoggingState.swift:548/:1276/:1301/:1351, WatchWorkoutSummary.swift:145, engine :227-262 | Untouched; after a relaunch the in-memory log holds only the active session's rows, which is all its readers show | S-17304 |
| `WatchReplayTests` (replay corpus) | WatchReplayTests.swift:634 asserts the corpus is non-empty; 4/4 inside the full suite in plan 162 | No store-contract change reaches it: replay drives the engine, whose appends and reads are unchanged | S-17308 |
| Phone side (`lib/`), watch app target | n/a | No Dart file and no `ContentView.swift` code in the diff (D-17306) | Phase 5 footprint sweep |

**Unaffected, with the grep that proves it:** `WatchRecords.swift` (no model change — grep
`enum StoredWatchRecord` has one definition, untouched), `WatchSensorSampleLog.swift` (its
per-session views are in-memory only, no store contract), `lib/` (no Dart file in any phase's
Predicted Files), `watch/contract/` and `watch/sync_protocol/` (no wire change).

## UI Standards Impact

None — no screen, widget or navigation change. `docs/design_system.md` untouched.

## Scenarios

### S-17301: the launch decodes the small rows, not the old readings
- Fixture: one directory, `watch-session.jsonl` written by hand (JSONL, marker
  `{"format":"omnitrain-watch-store","version":1}` first) holding exactly: 11 session rows
  (10 terminal `completed`, 1 `active`), 10 `session_end` observation rows, nothing else; and
  ten side files `watch-samples-s-old-1..10.jsonl`, each holding exactly 5,700 sample rows of
  its session (ids `sen-s-old-<i>-hr-<n>` and friends, sequences 1..5,700) — the steady-state
  shape after migration. Total stored readings: 57,000.
- Trigger: a launch — a new `FileWatchSessionStore` and engine over the directory,
  `engine.restore()`.
- Flow: `storedSession()`/`restore()` read through `readLaunch()`.
- Expected outcome: the store's rows-decoded counter reads exactly `1 (marker) + 11 (sessions)
  + 10 (observations) = 22`; `engine.sensorSamples` is empty (no active session's readings are
  inline); the 57,000 side-file rows are decoded zero times. The number does not change when
  the side files grow to 5× their size.
- Edge case of: none (root scenario).

### S-17302: the October file is migrated at the first launch
- Fixture: one directory, `watch-session.jsonl` written by hand: marker, 11 session rows (10
  terminal, 1 active), 10 `session_end` observation rows, **inline** 10 × 5,700 sample rows of
  the terminal sessions and 100 sample rows of the active session — the October shape, 57,100
  readings in one file. No side files.
- Trigger: the first launch of the new build (new store, `engine.restore()`).
- Flow: the load-time move (D-17304): side files written first, then the main file compacted.
- Expected outcome: after the launch, `watch-session.jsonl` holds the marker, the 11 session
  rows, the 10 observations and the active session's 100 inline rows — **no** terminal
  session's sample; each of the ten side files holds exactly its session's 5,700 rows with
  ids and sequences verbatim; a fresh store's `readAll()` returns every row exactly once
  (57,100 samples); a second launch moves nothing — the main file's inode is unchanged
  (the S-15604 identity guard's method).
- Edge case of: none.

### S-17303: a kill between the side-file write and the main-file swap
- Fixture: the both-copies state on disk — `watch-session.jsonl` still holding terminal
  sessions' sample rows inline **and** their side files already present with identical rows.
- Trigger: a launch.
- Flow: the load-time move re-runs (D-17303).
- Expected outcome: each side file is rewritten wholesale from the inline rows (same ids), the
  main file is compacted without them, and `readAll()` yields every reading exactly once — no
  duplicate record id anywhere.
- Edge case of: S-17302.

### S-17304: a recovered workout needs only the active session's readings — and gives them up at the end
- Fixture: continue from S-17302's directory after its launch (the active session `s-live`
  with 100 inline readings).
- Trigger: a relaunch (kill mid-workout recovery), one more reading appended, then
  `finishSession()`, then another relaunch.
- Flow: the recovery read is the active session's inline rows (D-17306); the end-time move
  runs at `storeSessionRow`'s terminal row (D-17305).
- Expected outcome: the relaunch restores all 100 readings into `engine.sensorSamples` (the
  live readout and the `announceEnergy` chain survive the kill); after `finishSession` the 101
  readings sit in `watch-samples-s-live.jsonl` and are out of the main file; the next launch's
  decode count contains none of them (counter exactness as in S-17301) and `readAll()` still
  returns all 101 until their release gate fires.
- Edge case of: S-17302.

### S-17305: the release gates delete side files
- Fixture: the `GrowthWrist` harness (`WatchStoreGrowthTests`), three ended workouts, each with
  its readings already in its side file: workout A with every entry and its `session_end`
  acknowledged (a receipt frame), workout B ended and unacknowledged with its newest session
  row 13 days old, workout C ended and unacknowledged 15 days old.
- Trigger: `engine.pruneSettledSensorSamples()` at a launch.
- Flow: the gate without its memory-visibility precondition (D-17308); the store deletes the
  named sessions' side files.
- Expected outcome: A's and C's side files are gone and `readAll()` shows no rows for them
  (memory and disk); B's side file stays with every reading; the in-memory log releases A's and
  C's ids; a second call drops nothing and rewrites/deletes nothing (D-15603).
- Edge case of: S-15601/S-15603 (extends their disk assertions to side files; both seeded pins
  keep passing — their `readAll()` assertions are unchanged).

### S-17306: the twin answers the new members value-for-value
- Fixture: the same workout history driven through both stores — one session created, two
  readings appended, ended, readings archived — mirrored row for row.
- Trigger: `readLaunch()`, `readAll()`, `archiveSensorSamples`, `pruneSensorSamples` on both.
- Expected outcome: identical id|kind|value|sequence signatures on every family, including
  `sensorSamples` (the twin's `readLaunch` excludes the terminal session's readings through the
  shared helper, exactly as the file store's main file does); `pruneSensorSamples` returns the
  same record ids from both.
- Edge case of: none.

### S-17307: a launch over 57,000 stored old readings costs at most 3× a launch over none
- Fixture: directory A = S-17301's steady state (57,000 side-file rows); directory B = the same
  main file with no side files.
- Trigger: one launch over each, in the same run, same machine.
- Expected outcome: `launch(A) ≤ 3 × launch(B)` — the S-15605-rewrite ratio style (A-156-05):
  wall time only as a ratio of the same machine's timings, never an absolute bound, so the
  guard is not flaky across machines. The count guard (S-17301) is the real assertion; this is
  the regression tripwire for a regression the counter cannot see (e.g. accidentally opening a
  side file).
- Edge case of: S-17301.

### S-17308: everything already green stays green
- Fixture: the existing suites, unchanged.
- Trigger: the full `swift test --package-path watch/watchos`, the replay corpus
  (`WatchReplayTests`) inside it, and the thread-sanitizer filter.
- Expected outcome: 0 failures everywhere; `WatchReplayTests` green; no new TSan report naming
  the store, the engine's end path or the settle gate.
- Edge case of: none.

## Iteration 1

### Phase 1: the launch read set (`readLaunch`) (@developer)
1. [ ] Add the shared free helper beside the row types — decides which sample rows are out of
   the launch set (newest session row per id, terminal ⇒ out; a session with no row stays in) —
   `watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift` · new free function
   `launchSensorSampleRows(_ rows: [StoredWatchRecord]) -> [StoredWatchRecord]` (name a
   mechanic; mirror `confirmedWaterTapIds`'s "one rule for both stores" doc comment)
2. [ ] Add `readLaunch() -> WatchSessionStore`'s protocol member with its contract doc comment
   ("everything except the raw readings of terminal sessions; those live in their own files") —
   `WatchSessionStore.swift` · `protocol WatchSessionStore`
3. [ ] Implement it on the twin through the helper; `readAll()` untouched —
   `WatchSessionStore.swift` · `InMemoryWatchSessionStore.readLaunch()`
4. [ ] Implement it on the file store as the main file's rows only (side files never opened) —
   `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` ·
   `FileWatchSessionStore.readLaunch()`
5. [ ] Switch the engine's two launch reads — `WatchSessionEngine.swift` · `restore()` (:165)
   and `storedSession()` (:202) — from `readAll()` to `readLaunch()`
6. [ ] Switch the six family restores, one call each (StartPaths has three) —
   `WatchNutritionState.swift:144`, `WatchWater.swift:132`, `WatchStartPaths.swift:392/584/598`,
   `WatchPhonePreferences.swift:197`, `WatchPersonalBests.swift:86`, `WatchEffortRating.swift:148`
7. [ ] Run: `.github/copilot/scripts/macos/gateway.sh swift-test` — full suite green,
   behaviour-neutral at this point (a store without side files answers `readLaunch()`
   identically to `readAll()`); paste the count into the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` full
green (record the actual baseline count — the last known is 1435/0 from plan 162, plus whatever
the working tree carries); `.github/copilot/scripts/macos/gateway.sh git-diff --name-only`
against the Predicted Files.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift`,
`FileWatchSessionStore.swift`, `WatchSessionEngine.swift`, `WatchNutritionState.swift`,
`WatchWater.swift`, `WatchStartPaths.swift`, `WatchPhonePreferences.swift`,
`WatchPersonalBests.swift`, `WatchEffortRating.swift`.
**Phase 1 verification notes (Conductor, date):** *(added at verification)*

### Phase 2: side files, the move, and the migration in the file store (@developer)
1. [ ] Side-file naming and registry: at first load, list the directory for
   `watch-samples-*.jsonl` and hold `[sessionId: URL]` under the existing `NSLock` (existence
   only, never decoded for the gate) — `FileWatchSessionStore.swift` · new private
   `sampleSideFiles` registry beside `heldIds`
2. [ ] The move: `archiveSensorSamples(_ sessionId: String) async -> [String]` (protocol member;
   returns the moved record ids) — write the side file wholesale (temp + replace, `compact`'s
   pattern), then `compact` the main file without that session's inline sample rows, then
   `adopt(_:)`; a call for a session with nothing inline and no side file writes nothing —
   `FileWatchSessionStore.swift` · `archiveSensorSamples` + `FileWatchSessionStore`
   protocol conformance in `WatchSessionStore.swift`
3. [ ] The twin's member: a no-op that returns the session's in-memory row ids (memory keeps
   them; the helper already excludes terminal sessions from `readLaunch()`) —
   `WatchSessionStore.swift` · `InMemoryWatchSessionStore.archiveSensorSamples`
4. [ ] The load-time move (D-17304): in `loadRows()`, after parsing, group inline sample rows by
   the helper's terminal-session rule; if any, write each side file (temp + replace), then
   `compact` + `adopt`; if none, no write at all — `FileWatchSessionStore.swift` ·
   `loadRows()` (the mover is a new private `migrateInlineSamples()` called from it)
5. [ ] `pruneSensorSamplesLocked`: named sessions ⇒ drop their inline rows (compact only if any
   were dropped), delete their side files, and load each named side file so the returned ids
   cover the rows the engine holds in memory — `FileWatchSessionStore.swift` ·
   `pruneSensorSamplesLocked` (:223)
6. [ ] The rows-decoded counter for the tests: increment on every line `parseLine` decodes
   (marker included), exposed as `rowsDecodedForTesting` (the `sensorRowsVisitedForTesting`
   precedent, WatchSessionEngine.swift:241) — `FileWatchSessionStore.swift` · `parseLine`
   (:~347) + the new counter property
7. [ ] Focused store runs: `swift test --filter
   "WatchFileStoreTests|WatchStoreGrowthTests|WatchSensorRecordingTests"` — every existing pin
   green with `readAll()` semantics unchanged; paste counts

**Done Criteria** (run until green): the focused run above green; full
`.github/copilot/scripts/macos/gateway.sh swift-test` green; the no-op guarantees of items 2
and 4 asserted by the new tests of Phase 4 (they may land red-on-HEAD first here, per the
mutation precedent of plan 156's Phase B part 2: if the tests cannot compile at HEAD, prove the
guards by mutation and record the table in the evidence file).
**Predicted Files**: `FileWatchSessionStore.swift`, `WatchSessionStore.swift`.
**Phase 2 verification notes (Conductor, date):** *(added at verification)*

### Phase 3: the engine moves at the end and asks the store instead of its memory (@developer)
1. [ ] In `storeSessionRow` (WatchSessionEngine.swift:1346), after the append, when the row's
   status is terminal, ask the store to move that session's readings (awaited; not on the
   per-second path) — `WatchSessionEngine.swift` · `storeSessionRow`
2. [ ] Re-verify the single-writer claim by grep and paste it in the evidence file:
   `captureSessionEnd`'s three callers (:683, :956, :1568) and `finishSession` (:440) all reach
   `storeSessionRow`; no other site appends a terminal session row
3. [ ] Remove the `storedSensorSamples.contains(sessionId:)` precondition from the settle gate
   (WatchSessionEngine.swift:2004-2013) — the store now owns "is anything stored"; keep
   everything else (awaiting-receipt, end-acknowledged, 14-day valve) exactly as it is —
   `WatchSessionEngine.swift` · `pruneSettledSensorSamplesLocked`
4. [ ] Run: `.github/copilot/scripts/macos/gateway.sh swift-test` full green;
   `.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread --filter
   "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests"`
   green with zero reports naming the store or the end path (plan 162's command form)

**Done Criteria** (run until green): full suite green; TSan filter green (paste counts); the
grep of item 2 pasted into the evidence file; Progress + Assumption Log updated.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`.
**Phase 3 verification notes (Conductor, date):** *(added at verification)*

### Phase 4: the launch-bound tests (S-17301..S-17307) (@developer)
1. [ ] New test file with a hand-written-JSONL seeder (the `growthWriteStore` pattern, extended
   to session/observation rows and to side files) and the launch helper reusing `GrowthWrist` —
   `watch/watchos/Tests/WatchSessionEngineTests/WatchLaunchParseTests.swift` · new
   `WatchLaunchParseTests`
2. [ ] `testS17301TheLaunchDecodesTheSmallRowsOnly` — S-17301's exact counter bound; prove red
   at HEAD: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter
   WatchLaunchParseTests` (expected: does not compile at HEAD — no `readLaunch`, no counter —
   so record the mutation proof instead, plan-156 Phase B part 2 style)
3. [ ] `testS17302TheOctoberFileIsMigratedAtTheFirstLaunch` — S-17302: inline readings moved
   exactly, active session's stay, `readAll()` complete, second launch moves nothing (inode)
4. [ ] `testS17303AKillBetweenTheTwoWritesIsHealedByTheNextLoad` — S-17303's both-copies state,
   seeded by writing main and side files by hand
5. [ ] `testS17304ARecoveredWorkoutKeepsItsChainAndGivesItsReadingsUpAtTheEnd` — S-17304:
   relaunch restores the active session's readings, end moves them out, next launch decodes none
6. [ ] `testS17305TheReleaseGatesDeleteSideFiles` — S-17305 over `GrowthWrist`: receipt-released
   and 15-day side files deleted, 13-day stays, second call a no-op
7. [ ] `testS17306TheTwinAnswersTheNewMembersValueForValue` — S-17306 signatures over both
   stores (the `growthSignatures` method)
8. [ ] `testS17307ALaunchOverFiftySevenThousandOldRowsCostsAtMostThreeTimesALaunchOverNone` —
   S-17307's ratio, measured in one run; then full `.github/copilot/scripts/macos/gateway.sh
   swift-test` (replay corpus green inside it) and the plan-162 TSan filter extended with
   `WatchLaunchParseTests` — zero reports naming the new code; paste every count into the
   evidence file

**Done Criteria** (run until green): the prove-red/mutation record for items 2-8 in
`docs/plans/2026-11-14-173-watch-launch-parse-plan/2026-11-14-173-watch-launch-parse-plan.evidence.md`;
full `swift-test` green; TSan filter green; Progress + Assumption Log updated.
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchLaunchParseTests.swift`
(+ `WatchStoreGrowthTests.swift` only if a seeded pin needs a one-line comment update — no
assertion of the S-156 family changes).
**Phase 4 verification notes (Conductor, date):** *(added at verification)*

### Phase 5: doc delta, re-measurement, consolidated verification (@developer)
1. [ ] `docs/state_management/watch_sensors.md`: extend the bounded-readings bullet (:595) and
   the Structure section (:21) with the side-file sentences — where readings live, when they
   move, when their files are deleted, and that a launch reads the main file only — naming the
   new tests (`testS17301…`, `testS17302…`, `testS17304…`, `testS17305…`). Doc is ~43 KB, under
   the 52 KB band; no split needed
2. [ ] Re-measurement table in the evidence file at 1, 5 and 10 stored outdoor hours, same
   method as plan 156's tables (5,700 readings per hour, throwaway test, debug build) — launch
   before/after; the throwaway file is reported to the governor for deletion
   (`delete-scratch` refuses non-`test/zz_*` paths)
3. [ ] Residue sweep, recorded in the evidence file: `grep -n "\.readAll()" watch/watchos/Sources`
   shows zero launch-path readers left (only the store's internal uses, if any), and
   `grep -rn "watch-session.jsonl" watch/watchos/Sources` shows the side-file naming beside it
4. [ ] Consolidated verification: full `.github/copilot/scripts/macos/gateway.sh swift-test`,
   the Phase 4 TSan filter, `.github/copilot/scripts/macos/gateway.sh lint` (no Dart file
   changed — the count must equal the pre-existing baseline, 181 at plan 156's run), and
   `.github/copilot/scripts/macos/gateway.sh git-diff --name-only` against the whole feature's
   Predicted Files — paste all counts; source-scan of the app target: `grep -n "restore()"
   "ios/OmniTrain Watch App/ContentView.swift"` confirms the launch chain (:364-393, :585-587)
   is untouched (D-17306)

**Done Criteria** (run until green): all of item 4's commands green/unchanged and pasted; the
doc updated; the evidence file complete; handoff to `@code-reviewer`.
**Predicted Files**: `docs/state_management/watch_sensors.md`,
`docs/plans/2026-11-14-173-watch-launch-parse-plan/2026-11-14-173-watch-launch-parse-plan.evidence.md`.
**Phase 5 verification notes (Conductor, date):** *(added at verification)*

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift` — protocol members
  (`readLaunch`, `archiveSensorSamples`), shared helper, twin (writes)
- `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` — side files, move,
  load-time migration, prune, counter (writes)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` — `restore()`,
  `storedSession()`, `storeSessionRow`, `pruneSettledSensorSamplesLocked` (writes)
- `watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`, `WatchWater.swift`,
  `WatchStartPaths.swift`, `WatchPhonePreferences.swift`, `WatchPersonalBests.swift`,
  `WatchEffortRating.swift` — one-line `readAll()` → `readLaunch()` switches (writes)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchLaunchParseTests.swift` — new (writes)
- `docs/state_management/watch_sensors.md`, the plan's `.evidence.md` (writes)
- `ios/OmniTrain Watch App/ContentView.swift` — **not touched** (source-scanned only, D-17306)
- `WatchRecords.swift`, `WatchSensorSampleLog.swift`, `lib/`, `watch/contract/`,
  `watch/sync_protocol/` — not touched

## Notes

- **Phase dependency graph:** Phase 1 (read set) → Phase 2 (side files; needs the helper and
  `readLaunch`) → Phase 3 (engine wiring; needs `archiveSensorSamples`) → Phase 4 (tests) →
  Phase 5 (docs + sweep). Phase 1 alone changes no behaviour; Phase 2 alone is inert until
  Phase 3 wires the end-time move (the load-time move already works, which is what S-17302
  tests). Re-ordering: none recommended — Phase 4's guards need all three.
- **Predicted intermediate states:** after Phase 1 the full suite is green with `readLaunch`
  answering `readAll`'s contents; after Phase 2 a store that never ended a workout behaves
  exactly as today; after Phase 3 a workout's readings leave the main file at its end.
- **Legacy handling:** the October file (S-17302); an older binary's interleave — it reads the
  same marker-version-1 main file, may append new inline readings for its active session, and
  the next new-build load re-moves whatever terminal-session rows it re-inlined (no version
  bump, D-17306); orphan readings whose session has no row stay inline (D-17301); a duplicate
  append for an already-moved reading would re-inline one copy and be re-moved at the next
  load — the engine never does this (it appends only for the active session), noted as a
  defensive edge, not a guard.
- **Durability unchanged:** the per-append fsync stays (plan 156 A-156-05 recorded it as out of
  scope); side files are written whole, so they never carry a torn tail.
- **Known repo notes for the implementer:** `flutter test`/`lint` are irrelevant here (no Dart
  file changes); `swift test` full runs ~25-35 s; the TSan filter ~30 s; `TempS156MeasureTests.swift`
  is plan 156's leftover residue awaiting governor deletion — it is +1 in the suite count, not
  this feature's.

## Progress

- [ ] Phase 1 — read set (`readLaunch`, helper, twin, 8 call-site switches)
- [ ] Phase 2 — side files, move, migration, prune, counter
- [ ] Phase 3 — engine end-time move + settle-gate precondition removal
- [ ] Phase 4 — S-17301..S-17307 guards, full suite, TSan
- [ ] Phase 5 — doc delta, re-measurement, residue sweep, consolidated verification

## Assumption Log

- **A-17301** The store, not the engine, derives "terminal session" for the move and for
  `readLaunch`. Options: engine passes the rule vs store derives it from the newest session
  row. Chose store-derived because the load-time migration (D-17304) runs before any engine
  exists. Derived from D-17301/D-17304/D-17305 — vetoable before Phase 2.
- **A-17302** `storeSessionRow` (WatchSessionEngine.swift:1346) is the single writer of
  terminal session rows; verified for the three `captureSessionEnd` callers (:683, :956, :1568)
  and `finishSession` (:440) by reading the call sites, and re-verified by the Phase 3 item 2
  grep. If the grep finds a fourth writer, it joins item 1's hook.
- **A-17303** The twin's `archiveSensorSamples` is a no-op returning the session's in-memory
  row ids: memory keeps the rows (the on-watch end summary reads them in the same process),
  while the shared helper already excludes them from `readLaunch()`. Chosen over deleting twin
  rows so the twin keeps mirroring the file store's *answers*, not its disk.
- **A-17304** `WatchStartPaths`' three `readAll` sites (:392, :584, :598) switch together; the
  two `exerciseBatches` reads (:584, :598) run in one flow, so a local pass-down could avoid the
  second call, but that is a refactor this plan does not own — both become `readLaunch()`.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

## Open questions (owner to confirm; defaults proceed)

1. **D-17305's move-at-end timing.** Default: move a terminal session's readings to their side
   file when the session's row lands, without waiting for the phone's receipt (they have no
   reader after the end). The conservative alternative is to move only when the settle gate
   would drop them (receipt or 14 days), which keeps the main file carrying one unacknowledged
   workout's readings for up to 14 days.
2. **Side-file naming** `watch-samples-<sessionId>.jsonl`. Default: as written (pinned so
   tests and migration are stable); any rename is a one-line change plus the tests.
3. **The active session's readings stay inline** and are therefore part of every launch parse
   (bounded by one workout, ~0.25 s per stored hour on the Mac). Default: keep (recovery
   requires them). The alternative — side files for the active session too, loaded lazily by
   the launch — is a strictly larger change deferred unless the owner asks.
4. **Suite-count baseline.** The last recorded full `swift test` count is 1435/0 (plan 162) plus
   working-tree drift and plan 156's leftover `TempS156MeasureTests.swift`. Default: the
   implementer records the actual baseline before Phase 1 and compares against that.
