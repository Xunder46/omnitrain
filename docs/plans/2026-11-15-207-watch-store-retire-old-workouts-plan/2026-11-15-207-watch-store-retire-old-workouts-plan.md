# Feature: 207 — the watch's store retires old, fully-synced workouts

> Status: SEEDED by the governor 2026-11-15; APPROVED by the owner 2026-11-15 ("we can do item 6 now"). Architect step skipped (A-1). Defaults marked **owner to confirm**.
> Next handoff: crew-builder-watch
> Binding conventions: `docs/global_conventions.md`, `docs/state_management/watch_sensors.md` (D-15601..D-15606 readings prune), `.github/copilot/pr-scope-budget.md`
> Related plans: 156 (the readings prune), 173 (readings side files), 96 D-43 (why no blanket confirmed-row prune), 140 (recovered workout)
> Track: watch client only (Swift store, engine, one launch line in the app shell). No wire, no phone change.

## Goal and acceptance

Independent review, 2026-11-15, item 6: "The watch's other stored rows are still never trimmed. Workout records, entries and timers stay forever, about 52 KB per workout. That is slow, roughly one second of relaunch per 200 workouts on a Mac." Raw sensor readings are already released once the phone has the workout; everything else a workout leaves (session rows, entries, timers, confirmation rows, rating prompts) stays for the life of the install.

After this change, at each app launch the watch retires every workout that is **over and fully synced** except the newest 20. Nothing the user can see changes: the watch shows no workout history (the phone and Health hold it). Relaunch time stops growing with the number of workouts (about the 0.1 s the review measured at 20 workouts).

What is never retired: the session the watch is on; any workout that is not over; any workout with an entry the phone has not receipted; a wrist-started workout whose end the phone has not acknowledged; the newest 20 settled workouts; and every non-workout record (routines, planned, foods, exercise batches, preferences, bests, water frames, water and food taps). **Owner to confirm (stated behaviour):** a rating question still owed for a workout older than the newest 20 lapses with it.

Acceptance: the scenarios below fail on the old code; `swift test` whole target green with observed counts; the watch target builds (lead); the append-only source guard's allowed list names the one new store method on purpose.

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20701 | **A store-level retire, decided from the rows alone.** `WatchSessionStore` gains `pruneSettledSessions(keepingNewest: Int) async -> [String]` (returns the dropped record ids), with a default in the protocol extension that returns `[]` (the test doubles that forward to a real store answer nothing, as `archiveSensorSamples` does); `FileWatchSessionStore` and `InMemoryWatchSessionStore` implement it. It needs no engine state, so it can run BEFORE `engine.restore()` and the engine never holds stale rows. | `WatchSessionStore.swift`, `FileWatchSessionStore.swift` |
| D-20702 | **Settled = terminal AND fully synced.** A session is settled when its newest session row is `completed` or `abandoned` (`settledSensorSessionIds`), every observation row of it that the phone must receipt (kinds `set, timed, round, hold, rest, sessionEnd, effortRating`) has `confirmedAt != nil` or is named by a confirmation row, and, for a wrist-source session (`source == "watch"`), the end observation `end-<sessionId>` is confirmed (the gate `isEndAcknowledgedWhereOwed`). The "14 days unacknowledged" rule of the readings prune is NOT used: an unsynced workout is kept for as long as it is unsynced. | `FileWatchSessionStore.swift` |
| D-20703 | **Keep the newest 20.** Settled sessions are ordered by the highest `sequence` among their session rows (newest first); the first 20 are kept; every older settled session is retired. `public static let settledSessionsKept = 20` lives on the engine (`WatchSessionEngine`) and is the argument of the one call. | `WatchSessionEngine.swift` |
| D-20704 | **What a retired session drops:** all its `session` rows, its `observation` rows of the kinds in D-20702, its `timer` rows, its `ratingPrompt` rows, its `sensorSample` rows still held, its side file `watch-samples-<id>.jsonl`, and every `confirmation` row whose `observationIds` are ALL among the dropped observations. **It never drops** `waterGlass` and `nutritionQuickLog` observations (and the confirmation rows that name them): they have their own cutoff (`pruneWaterTaps`) and the water and food counts read them (plan 96 D-43). | `FileWatchSessionStore.swift` |
| D-20705 | **House pattern of every prune:** load rows, filter survivors, `guard !dropped.isEmpty` (a prune that finds nothing writes nothing: the file keeps every byte), `guard compact(survivors)` (a prune that cannot be written drops nothing), `adopt(survivors)`. | `FileWatchSessionStore.swift` |
| D-20706 | **Called once per launch, before the engine reads the store.** `WatchSessionEngine.pruneSettledSessions()` (public, async) calls the store with `settledSessionsKept`; `ContentView.restore()` awaits it immediately BEFORE `await engine.restore()`. No call after a receipt (the next launch does it). Engine in-memory logs are not touched: the call precedes their fill. | `WatchSessionEngine.swift`, `ios/OmniTrain Watch App/ContentView.swift` (~line 367) |
| D-20707 | **Append-only guard updated on purpose:** `testS004NoMutatingOperationExistsAnywhereInTheModule`'s allowed set gains `pruneSettledSessions` (its own message: "A seventh prune … has to be added here on purpose"). | `WatchSessionEngineTests.swift` (~line 342) |
| D-20708 | **Not changed:** the readings prune (`pruneSettledSensorSamples`, its D-15601 launch pin), `pruneConfirmed` (still no production caller), the wire, the phone, the Dart twin (it has no file store). | — |

## Input-reality checklist (answered)

1. **Writers.** Rows are written by `FileWatchSessionStore.append` from the engine (sessions, observations, timers, confirmations, rating prompts) and the other states (routines, foods, bests, water). Confirmations come from the phone's `receipt` and from snapshots that carry entries.
2. **Lifecycle.** An install updated from an older build opens a large file once: the first launch compacts it (one rewrite); a relaunch with nothing to retire writes nothing (D-20705). A recovered workout (plan 140) is the newest, not settled: untouched. A torn last line is handled by `loadRows` as today.
3. **Settings.** None.
4. **Time.** No clock: order is by `sequence`, so a clock change cannot retire the wrong workout.
5. **Cost.** One pass over the rows at launch plus at most one rewrite; the launch then decodes fewer rows.
6. **Words.** Docs: the Docs delta. No on-screen words.
7. **Competition.** Retire vs a late phone frame for a retired session: a frame for an unknown session is refused by the engine unless it is a snapshot that creates the session (a queued snapshot older than the newest 20 settled workouts naming an ACTIVE session would recreate it: accepted, the phone's snapshots follow its live session).

## Feature invariants

- Nothing unsynced, active or recent is ever dropped (D-20702, D-20703, S-20702..S-20705).
- Non-workout records and water/food taps are untouched (D-20704, S-20706).
- A retire that finds nothing, or cannot write, changes no byte of the file (D-20705, S-20707, S-20708).
- It runs before the engine restores (D-20706, S-20709).

## Existing-functionality impact

| Touched surface | What reads it (scout sheet 7) | Effect | Guarded by |
|---|---|---|---|
| `WatchSessionStore` protocol | `InMemoryWatchSessionStore`, `FileWatchSessionStore`, test doubles that forward to a real store (the extension default covers them) | New requirement with a default | S-20701 |
| The append-only guard | `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` allowed set (10 names) | One name added | S-20710 |
| `ContentView.restore()` and its pin | `WatchStoreGrowthTests.testS15601TheLaunchRestoreAsksForThePrunes` asserts the readings prune comes AFTER `await engine.restore()`; it must stay true | The new call goes before `engine.restore()`; the pin gains a second assertion | S-20709 |
| Stored files of existing installs | `WatchLaunchParseTests` (S-17301/S-17307 launch cost over many old rows) | Their fixtures keep many old rows in one store; they call the store directly and never the new prune, so they are unaffected | S-20711 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20701 | A file store with 25 settled workouts (each: 2 session rows, 3 effort observations all confirmed, a rest, a `session_end` confirmed, 2 timers, 1 confirmation row, 1 rating prompt, a side file), plus routines, foods, preferences, bests, water frame, a `waterGlass` and a `nutritionQuickLog` tap that belong to the oldest session; `pruneSettledSessions(keepingNewest: 20)` | the 5 oldest workouts have NO rows of any retired kind and no side file; the 20 newest are byte-for-byte intact; the water and food taps and every non-workout row survive | no such prune |
| S-20702 | The oldest workout has one effort observation with no confirmation | that workout is kept whole | an unsynced workout would be lost |
| S-20703 | The oldest workout is wrist-source and its `end-<id>` observation is unconfirmed | kept whole | its end would never reach the phone |
| S-20704 | The oldest session's newest row is `active` (never ended) | kept; and the held current session is never retired whatever its age | an unfinished workout would be lost |
| S-20705 | A settled workout inside the newest 20 | kept | the cut-off is wrong |
| S-20706 | Only non-workout rows plus 3 settled workouts | nothing dropped, the file is not rewritten (same bytes) | n/a — pin |
| S-20707 | A prune that drops nothing | the file's bytes (marker, torn tail included) are identical | a rewrite on every launch |
| S-20708 | A store whose directory cannot be written (the existing F2/G1 fixture style) | returns `[]`, in-memory rows unchanged | a failed write would drop rows in memory |
| S-20709 | Source guard on `ContentView.swift`: `restore()` contains the exact statement `await engine.pruneSettledSessions()` BEFORE `await engine.restore()`, and the readings prune still comes after | exact statements | the call is absent |
| S-20710 | The append-only guard test with the new name allowed | green | the guard refuses the new method |
| S-20711 | An engine over a store with 40 settled workouts: `pruneSettledSessions()` then `restore()` | `engine.session` is the newest workout, `sessionRowCount` etc. equal the 20 kept, the main file's row count is below a fixed bound derived from the fixture | relaunch keeps all 40 |

## Phases

**P1a — production (owner: crew-builder-watch; scope `WatchSessionStore.swift`, `FileWatchSessionStore.swift`, `WatchSessionEngine.swift`, `ios/OmniTrain Watch App/ContentView.swift`, the allowed list in `WatchSessionEngineTests.swift` (one line), the existing launch pin in `WatchStoreGrowthTests.swift`, report).** D-20701..D-20707.

**P1b — tests (owner: crew-builder-watch; new `WatchSettledSessionPruneTests.swift`, report; serial after P1a).** S-20701..S-20708, S-20711 (S-20709 and S-20710 ride in P1a).

**P2 — docs (owner: crew-docs-keeper).** The Docs delta.

## Docs delta

The readings retention is described in `docs/state_management/watch_sensors.md` (the `unacknowledgedReadingsRetention` paragraph near line 612) and `docs/watch_session_sync/what_does_not_sync.md:247`; the keeper reads both before placing the sentence.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_sensors.md | ADDED | - | `the watch retires every settled workout beyond the newest 20 at launch` | S-20701, S-20702 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**Old workouts leave the watch's store — (owner, plan 207).**` | S-20701 |

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheet 7 read).
- [ ] P1a production
- [ ] P1b tests
- [ ] P2 docs
- [ ] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols, fixtures. | lead | open |
| A-2 | **Owner to confirm:** keep the newest 20 settled workouts; a still-owed rating question for an older workout lapses. | lead | open |
| A-3 | The ~52 KB per workout is not measured by a test; the saving is stated by row counts, not bytes. | scout sheet 7 Q6 | open |
