# Feature: a rest done on the watch reaches the phone's rest history (18c)

> Status: Iteration 1 — **split by the governor's scope check (2026-10-08)**: this plan ships Phase 1A (the wire) and
> Phase 2 (the phone writes it). The wrist emission and the totals/views/docs work moved to plan 18d —
> `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`.
> Every seeded Ledger entry, scenario and phase outline line is kept (additions are marked "planner, Iteration 1";
> entries that moved stay below as one-line markers, so their ids are never reused).
> Next handoff: @developer (Phase 1A — the wire: `$defs.event` branch, both validators, fixtures, `PROTOCOL.md` row)
> Binding conventions: `docs/global_conventions.md` ("Rest rule: rest is a count-up"), `docs/rest_tracking.md`,
> `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/documentation_standard.md`
> Part of the 18 series — index: `docs/plans/2026-10-08-18-watch-qa-index.md`. The design is pinned in plan 18b:
> `docs/plans/2026-10-08-18b-watch-rest-count-up-plan/2026-10-08-18b-watch-rest-count-up-plan.md`
> (D-166, D-167, D-169, `## Remainder planned as 18c`). This plan implements it; it re-decides nothing there.
> Evidence: `….evidence.md` · Review: `….review.md` (beside this file)

## Split (governor, 2026-10-08)

- **Stays here (18c):** Phase 1A — the wire (schemas, both validators, the four fixtures, `PROTOCOL.md` row) — and
  Phase 2 — the phone stages and writes a rest (`WatchInboxEntry.kindRest`, the inbox field contract, `_applyRests` in
  all three flows, first-write-wins, drop-and-consume), proven by fixtures and importer tests while no client sends one.
- **Moved to plan 18d:** part B of the seeded Phase 1 (the wrist emits — Swift, the Dart twin, the finish-path stop) and
  the seeded Phase 3 (S-329 totals, the phone's rest rows, the docs "what travels" lists, the 17a annotation, the 18
  index row): `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`.
- **Order:** receiver first — 18c ships before 18d; 18d is built on 18c's merge commit, and a wrist built from 18d must
  not send a rest to a phone without 18c. Moved entries keep their ids and stay below as one-line markers.

## Overview

18b made the watch's rest a count-up with its own screen and Next. The owner asked whether the watch's rest should reach
the phone, and answered:

> "yes"

Until now a rest done on the watch stays on the watch: the phone's session summary and history know nothing about it.

**What this plan (18c) ships.** The phone can receive, stage and write a rest observation: the wire accepts the kind
(Phase 1A), and the importer writes one `EntryRest` per rest in all three of its flows (Phase 2) — proven by fixtures
and importer tests, while **no client sends one yet**. Nothing changes on either device's screens.

**What plan 18d adds.** The wrist emits the observation (Swift and the Dart twin, including the finish path), and then
the totals, the phone's rest rows and the docs follow there, because a doc must not describe behaviour that has not
shipped. The user-visible outcome below is plan 18d's; 18c makes the phone able to receive it.

What the user sees after **plan 18d**: a set logged on the watch followed by a rest that ends at Next (or at the next set, or
when the workout ends) shows up in the phone's session afterwards **as a rest between those two sets**, with the same
start and end the watch showed, and it counts toward the session's rest time in the summary and history exactly like a
rest the phone itself counted. Nothing changes on the watch screen. A rest that has no length (zero seconds) is never
sent. A rest the phone already has for that spot (the phone logged the set itself) is left exactly as it is. Deleting a
set on the phone does not delete the rest after it.

### Acceptance criteria

1. **(ships in plan 18d)** The wrist emits one `rest` observation per completed rest, in the Swift client and in the
   Dart twin, carrying the fields of D-166; never for a window of no length; a rest still running when the workout ends
   is emitted with the workout's end instant.
2. The wire accepts the new kind in the schema and in both validators, with a valid fixture and invalid fixtures, and a
   dated `1 (amended)` row in `watch/sync_protocol/PROTOCOL.md` (D-169).
3. The phone stages the row, and its importer writes an `EntryRest` by D-167's rules (a)–(d), in all three import flows
   the importer has (a new session, a session the phone already holds, a late top-up of an imported session); an
   unresolvable or duplicate rest is acknowledged and dropped, never retried forever.
4. **(ships in plan 18d)** `SessionSummaryService.computeSessionRestTimeMs` totals an imported wrist rest, and the
   phone's session views show it where they show any rest (no new screen).
5. The rest rule is untouched: the event carries a start and an end and no planned length; the rest-rule contract test
   stays green; the ping is unaffected (an imported rest is closed, so it never pings: plan 22 D-249).
6. **(ships in plan 18d)** Docs are true: the sync doc's and watch-surface doc's "what travels" lists; 17a D-80/S-79
   annotated per 18b D-165; the 18 index gains its row.
7. Baselines hold or rise: flutter +4181 ~1, swift 376 / 0, analyze 196 / 0. The governor's `xcodebuild "OmniTrain
   Watch App"` run belongs to plan 18d. 18c touches Swift only through Phase 1A's mirror validator
   (`SyncProtocolValidator.swift`) — no Swift client change — so the watch baseline holds: `swift-test` 376 / 0.

## Requirements (planner, Iteration 1)

- **R-1 (→ plan 18d)** The wrist emits one `rest` observation per completed rest, from the one place every wrist-side
  ending goes through, with the fields of D-166/D-220, identically in the Swift client and the Dart twin (S-320, S-332,
  S-335).
- **R-2** The wire accepts the kind and refuses a rest that is not a window, with fixtures both suites walk (S-330).
- **R-3** The phone stages the row and its importer writes one `EntryRest` per rest in all three flows, first write wins
  (S-320, S-324, S-325, S-326, S-327, S-328).
- **R-4 (→ plan 18d)** An imported rest renders and totals exactly like a phone-counted rest of the same window (S-329).
- **R-5** The rest rule is untouched: a start, an end, no planned length; no screen changes on either device; no new
  message type; protocol version stays 1; the watch shows nothing new. (The watch's half of this ships in 18d; 18c
  keeps the wire and the phone inside it.)
- **R-6 (→ plan 18d)** Docs are true where they claim what travels, 17a D-80/S-79 is annotated, and the 18 index gains
  its row.

## Verification of the seed's questions (planner, read at the base commit)

The seed asks five things be verified before the phases are written. All five are answered; each names the symbol and the
line that decides it. **V-1 is a divergence**: the plan keeps the seeded text and does what D-211 pre-authorises.

**V-1 — does the finish path stop a running rest? No.** `WatchSessionEngine.transitionTo` (`WatchSessionEngine.swift:1071`)
only captures the session end (`captureSessionEnd`, `:1381`), so a rest still running at End keeps running and nothing is
emitted; the Dart twin is the same (`_transitionTo`, `lib/watch/session/watch_session_engine.dart:1148`, from
`finishSession` `:341` / `abandonSession` `:347`). D-211 sanctions the addition, so **plan 18d's Phase 1 adds the stop at
the session's end instant and the emission it produces** (its items 4 and 5).

**V-2 — what is the `afterEntryId` lookup?** Positional, against the store's own row order, because the rest timer row
carries no slot: the `recordId` of the newest effort observation (`set`/`timed`/`round`/`hold`) of the session whose row
position precedes the **pre-stop** rest timer row's, skipping timer rows and non-effort records. Pinned as D-221.

**V-3 — the importer has exactly three flows and two hook sites.** (a) a new import and (b) a late top-up both run
`_Pass.run` (`watch_session_importer.dart:429`, its ranked `_placeEffort`/`_placeEntries` loop then the orphan-effort
loop) and finish with `_markApplied` (`:214`); (c) a merge into a phone-held session runs `_mergeHeld` (`:224`) and
finishes with `_consume` (`:367`) / `_markApplied` (`:369`) before its `return`. Calling `_applyRests` at those two sites
therefore reaches all three flows, and the rows it writes or drops are consumed in the same pass.

**V-4 — repository changes: none.** `getEntryRests`/`createEntryRest` already exist in both implementations
(`hive_workout_repository.dart:1550`/`:1560`, `mock_workout_repository.dart:859`/`:866`). The Mock appends (no dedupe by
id or index) while Hive puts by id, so the importer's "a rest already exists at that `entryIndex`" guard is what keeps
the two observably equal (invariant 1, S-325). D-215's expectation is confirmed: no repository change.

**V-5 — the wire.** `envelope.schema.json`: `$defs.entry.properties.kind.enum` (`:175`) gains `"rest"`, and
`$defs.entry.properties` has no `afterEntryId` while the object is `additionalProperties: false` (`:161`), so the field
must be declared there too. `observations_up.schema.json`: `$defs.event.oneOf` (7 branches) gains an eighth, mirroring
`timed` plus `afterEntryId`. Both validators gain one semantic rule (D-222). No new rejection code, so
`test/sync_protocol_fixtures_test.dart`'s "documents every rejection code" list is unaffected.

## Decision Ledger (seeded)

**D-210 — Pinned designs stand.** 18b's D-166 (the `rest` observation: `eventId`, `sessionExerciseId`, `exerciseId`,
`startedAt`, `endedAt`, `afterEntryId`; emitted when the rest ends; `endedAt <= startedAt` not emitted; a rest running at
the workout's end is emitted with that end instant; no new message type, `$defs.event` oneOf gains the value, no version
bump) and D-167 (`EntryRest` with `entryIndex = index of afterEntryId's entry + 1`, `id = 'rest-<effortId>-<entryIndex>'`,
`restStartMs = startedAt`, `restEndMs = endedAt`, never paused, first write wins, a rest is never placed, re-stated,
re-indexed or deleted with its set, an `afterEntryId` that resolves to nothing is dropped) are implemented as written.
Do not restate them here; cite them.

**D-211 — Where the wrist records the rest.** → moved to plan 18d (same id, full text there; it governs the wrist's emission).

**D-212 — Idempotency.** → moved to plan 18d (same id, full text there; it governs the wrist's emission).

**D-213 — `afterEntryId` is the set the rest follows.** → moved to plan 18d (same id, full text there; it governs the
wrist's emission).

**D-214 — The phone stages it as a wire kind that is not an effort entry.** `WatchInboxEntry` gains `kindRest = 'rest'`
(`lib/data/models/models.dart:2621`) in `watchKinds`; `WatchSessionInbox._requiredFields`
(`lib/state/watch/watch_session_inbox.dart:~183`) gains `rest: [sessionExerciseId, exerciseId, startedAt, endedAt,
afterEntryId]`. It is deliberately NOT added to the importer's `_effortKinds` (`watch_session_importer.dart:103`), because
that set is what turns a row into a placed entry (`_Entry.parse`, the `live`/`materialised` lists and the empty-session
test at `:174-190`, `:299-305`). A session whose only staged rows are rests is still empty (D-133): a rest alone never
imports a session.

**D-215 — The importer applies rests after the entries are placed, in every flow.** In each of the importer's flows (new
import, merge into a phone-held session, top-up) a separate `_applyRests` step runs after the entries are placed and
indexes are final, resolves `afterEntryId` through the placed entry's index, and writes through
`WorkoutRepository.createEntryRest` (`workout_repository.dart:253`) unless `getEntryRests(effortId)` already holds a rest at
that `entryIndex` (first write wins). A rest row is marked applied (consumed) when written or dropped, so it is never
retried. Both repository implementations (Hive, Mock) already implement `createEntryRest`; no repository change is
expected — the planner confirms.

**D-216 — The phone's own rest wins and the phone is the authority.** For a session the phone already holds (19a), a rest
for a slot where the phone logged that set itself is dropped by D-167(a); the wrist's rest never overwrites or merges
into the phone's. No rest is ever written for a set the phone does not hold.

**D-217 — No wire version bump, one amendment row.** `PROTOCOL.md`'s Version history gains one dated `1 (amended)` row
for the kind (D-169), written in the phase that ships the wire change, naming the fixtures and tests. `PROTOCOL.md` is
≈63 KB and not covered by the docs size test: add a short row, do not expand the file.

**D-218 — Out of scope, stated so it stays out.** Editing, pausing or deleting a rest on either device; showing wrist
rests on the watch; any rest length; rests in a routine; the phone sending its rests to the watch.

## Decision Ledger additions (planner, Iteration 1)

**D-219 — exactly one emission site, and only a wrist-side ending fires it.** → moved to plan 18d (same id, full text
there; it governs the wrist's emission).

**D-220 — what the emitted event carries, and how it travels.** → moved to plan 18d (same id, full text there; it
governs the wrist's emission).

**D-221 — the `afterEntryId` lookup, stated exactly.** → moved to plan 18d (same id, full text there; it governs the
wrist's emission).

**D-222 — the wire's rest event is a window, and the entry shape is shared.** `envelope.schema.json`:
`$defs.entry.properties.kind.enum` gains `"rest"`, and `$defs.entry.properties` gains `afterEntryId`
(`type: string`, `minLength: 1`) — required, because the entry object is `additionalProperties: false`.
`observations_up.schema.json`: `$defs.event.oneOf` gains an eighth branch requiring
`kind, sessionExerciseId, exerciseId, startedAt, endedAt, afterEntryId`, mirroring `timed`. Both validators gain one
semantic rule: a `rest` whose `endedAt` is **not after** its `startedAt` is refused as `semantic_violation`
(`endedAt == startedAt` included — a rest of no length cannot travel, and the wrist never builds one, D-166); the phone
additionally drops such a row if an older peer staged it (S-323). A stray `afterEntryId` on another kind is accepted and
inert: the shared entry shape cannot say "only on a rest", no reader reads the field on another kind, and gating it would
need a new kind map in both validators — rejected as unnecessary (vetoable, see Open questions). Protocol version stays 1.

## Feature Invariants (planner, Iteration 1)

Only the invariants this feature can plausibly break; project-wide rules stay in `docs/global_conventions.md`.

- **Implementation parity.** For the same import, `HiveWorkoutRepository` and `MockWorkoutRepository` must show one
  `EntryRest` with the same `entryIndex`, `id` and window. Mock's `createEntryRest` appends
  (`mock_workout_repository.dart:866`) while Hive's puts by id (`hive_workout_repository.dart:1560`), so the importer's
  "a rest already exists at that `entryIndex`" guard is what keeps them equal; no test may lean on Mock's append.
- **Layer boundaries.** `lib/state/` and `lib/core/services/` reach rests only through `WorkoutRepository`
  (`getEntryRests`/`createEntryRest`), never a Hive box.
- **The rest rule.** The event carries a start and an end and no planned length: no `restSeconds`, `restDurationMs`,
  `restLengthMs`, `defaultRest*` or `kRest*` identifier, no "rest countdown"/"rest remaining" wording, no
  `startTimer(WatchTimerKind.rest, plannedDurationMs:)`. `test/rest_is_count_up_contract_test.dart` scans
  `watch/sync_protocol/schemas` too, so new schema text is inside its reach.
- **History is never rewritten.** An imported rest edits no set; deleting a set never deletes its rest (D-167(b), S-327).

## Existing-Functionality Impact (planner, Iteration 1)

Each row: the surface this feature touches → what already reads it (the grep that found it) → what the change does to it
→ the guard. `grep -n stopTimer|appendObservation|_effortKinds|_requiredFields|getEntryRests|WatchObservationKind` over
`lib/`, `watch/watchos/Sources/` and `test/` produced these readers.

| Touched surface | What already reads it | Effect | Guarded by |
|---|---|---|---|
| `_effortKinds` (`watch_session_importer.dart:103`) | `_Entry.parse`, the empty-session test (`:174-190`, `:299-305`) | unchanged on purpose: adding `rest` would let a rest alone create a session | S-326 |
| `WatchInboxEntry._checkInvariants` allow-list (`models.dart:2725`), whose `ArgumentError` `_entryFor` (`watch_session_inbox.dart:514`) swallows | the staging path | a `rest` row absent from `watchKinds` is never staged **and never receipted**, so the wrist re-sends it forever — the kind must be added | S-320, S-324 |
| `_requiredFields` (`watch_session_inbox.dart:171`) → `_isStageable` (`:501`) → `_settleNow` (`:420`) | staging and receipting | a kind absent from the map is never settled (D-214) | S-320 |
| `computeSessionRestTimeMs` (`session_summary_service.dart:17`) | `session_summary_screen.dart:808` (`_restTimeMs`), the summary tests | no code change: an imported rest is a closed `EntryRest` inside the session window — asserted, never edited | plan 18d Phase 2 (S-329) |
| `getEntryRests` readers (`workout_session_screen.dart:331,678,770`; `lib/features/session/workout_session_global_timer.dart:45,81`; `lib/state/workout/session_core_io.dart:104,175,247`; `lib/state/workout/timer_manager.dart:49`; `lib/state/workout/workout_state.dart:90`; the history view reads it through `_getMostRecentOpenRestKey`, not the `workout_session_list_view.dart:607` doc comment) | the session and history rest rows, the rest ping and the global rest chip | the timer and notification readers null-check `restEndMs` before use, so a closed imported rest never enters the global rest chip or fires a ping; the rest are passthrough accessors and loaders; they show an imported rest with no change (no new screen, no new widget) | plan 18d Phase 2 |
| `WorkoutRepository.createEntryRest` (`workout_repository.dart:253`) in both implementations | `TimerManager.recordRestStart` (`timer_manager.dart:693`); from Phase 2, `_applyRests` reads `getEntryRests` for first-write-wins | no change needed (V-4); the phone's own rest keeps winning (D-216) | S-325, Phase 2 parity row |
| `watch/sync_protocol/PROTOCOL.md` message table + Version history | `test/sync_protocol_fixtures_test.dart` (spec text, rejection codes, and "links only to paths that exist", `:764`) | one kind in the `observations_up` row, one dated amendment row, no new rejection code | S-330 |
| `scripts/sqlite_schema.sql` (`app_entry_rest`, `:756`) | `test/db_seed_test.dart` | no change: no model field and no table; `entry_index`/`rest_start_ms`/`rest_end_ms` already match D-167 | `db_seed_test.dart` |

The wrist rows — `WatchObservationKind`, `WatchSessionEngine.stopTimer(kind:)`, `stopTimerFromMessage`,
`finishSession`/`abandonSession` and `appendObservation` — moved to plan 18d with their phases, and carry their S-ids
there (S-320, S-322, S-331…S-336, S-339). The two rows whose *effect* is 18c's write but whose *assertion* is 18d's
(`computeSessionRestTimeMs`, the `getEntryRests` readers) stay here with the 18d phase named in their guard column, so
no dependent surface is dropped from this plan's Impact Check.

## Core scenarios (seeded)

"Red without the change" = the thing named does not exist or does not do this at the base commit.

- **S-320 — the happy path.** Wrist logs set A, rests 70 s, Next. The phone receives set A and a `rest` event
  (`afterEntryId` = A, `startedAt`/`endedAt` 70 s apart) then the session end. History holds the session with set A and one
  `EntryRest` at `entryIndex` 1, `restStartMs`/`restEndMs` as sent, `id 'rest-<effort>-1'`. Red: no kind, no writer.
  **18c proves the phone half** — a staged `rest` event and set A (the wire's valid fixture stands in for the wrist)
  imported through all three flows, Phase 2. **Plan 18d re-proves the wrist half** on the real engine, Swift and Dart.
- **S-321 — a rest ended by the next set.** → moved to plan 18d (same id, full text there; the ending instant is the
  wrist's).
- **S-322 — a rest running when the workout ends.** → moved to plan 18d (same id, full text there; the finish path is
  the wrist's).
- **S-323 — zero length.** `endedAt <= startedAt`: not emitted on the wrist; if one arrives anyway the phone drops it
  (acknowledged, not written). **18c proves the phone half** (the drop, Phase 2, items 3 and 4); **plan 18d re-proves
  the wrist half** (nothing is emitted).
- **S-324 — duplicate delivery.** The same `rest` event delivered twice: one `EntryRest`, second acknowledged and dropped.
  **18c proves the phone half** (first write wins, Phase 2); **plan 18d re-proves the wrist half** (one emission per
  rest, D-212).
- **S-325 — the phone already holds that spot.** The phone logged set A itself and has an `EntryRest` at index 1: the
  wrist's rest changes nothing (the row compares equal before and after).
- **S-326 — a rest does not import a session.** Staged rows are a `rest` and a `session_end` only: no session is created.
- **S-327 — deleting a set leaves its rest.** Rest imported after set A; the user deletes set A on the phone: the
  `EntryRest` row is unchanged (D-167(b)).
- **S-328 — unresolvable.** `afterEntryId` names no placed entry: dropped and consumed; the next pass does not retry it.
- **S-329 — the totals.** → moved to plan 18d (same id, full text there; the total is asserted against the phone's
  surfaces there).
- **S-330 — the wire.** Valid `rest` fixture passes both validators; missing `afterEntryId`, a `plannedDurationMs` field
  and `endedAt` before `startedAt` are refused (messages named in the fixtures). Red: kind not in the enum.

## Edge scenarios (planner, Iteration 1)

Every fixture below names the exact population that must exist; "red" = red at the base commit.

- **S-331 — the finish path ends a rest.** → moved to plan 18d (same id, full text there; the finish path is the wrist's).
- **S-332 — Next emits once; a second stop is silent.** → moved to plan 18d (same id, full text there; the emission is
  the wrist's).
- **S-333 — a phone-sent stop emits nothing.** → moved to plan 18d (same id, full text there; the emission is the
  wrist's).
- **S-334 — nothing to hang the rest on.** → moved to plan 18d (same id, full text there; it is the wrist's lookup).
- **S-335 — the two stacks agree.** → moved to plan 18d (same id, full text there; both engines are the wrist's).
- **S-336 — an adopted rest the wrist ends still emits.** → moved to plan 18d (same id, full text there; the emission is
  the wrist's).
- **S-337 — the after-entry is gone.** Fixture: staged rows = set A, a rest with `afterEntryId` = A, then the user
  deletes A on the phone before the next import pass (and, separately, a rest whose `afterEntryId` names an entry the
  phone never held). Trigger: the pass runs. Expected: the rest is dropped and consumed, the session keeps the sets it
  has, the row is not retried and not receipted for a second attempt. Edge case of: S-328.
- **S-338 — a rest after the last set.** Fixture: set A, set B, then a rest with `afterEntryId` = B. Trigger: import.
  Expected: one rest at `entryIndex` = 2 = `entries.length` (the phone's own `recordRestStart` does the same for a rest
  after the last set), not clamped and not dropped. Edge case of: S-320.
- **S-339 — the lookup survives a relaunch.** → moved to plan 18d (same id, full text there; it is the wrist's lookup).

## Phase outline (seeded; each phase ≤ 8 items; one run each)

1. **Phase 1A — the wire (@developer).** Part A of the seeded Phase 1 (the planner split it at the 8-item rule): schema
   `$defs.event` oneOf + both validators + fixtures + `PROTOCOL.md` row (D-217, D-222). Scenario S-330. Track: sync
   contract.
2. **Phase 2 — the phone writes it (@dba).** The seeded Phase 2, unchanged: `WatchInboxEntry.kindRest`, inbox
   `_requiredFields`, importer `_applyRests` in the three flows, the empty-session rule, first-write-wins,
   dropped-and-consumed (D-214…D-216). Scenarios S-320 (phone half), S-323 (phone half), S-324 (phone half), S-325,
   S-326, S-327, S-328, S-337, S-338. Track: phone data/importer.

**Moved to plan 18d** (governor's scope split, 2026-10-08): part B of the seeded Phase 1 — the wrist emits it (Swift, the
Dart twin, the finish-path stop; D-211…D-213, D-219…D-221; S-320 wrist half, S-321, S-322, S-331…S-336, S-339) — and the
seeded Phase 3 (S-329 totals, the phone's rest rows, the docs "what travels" lists, the 17a annotation, the 18 index row)
— `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`.

Scope check (`.github/copilot/pr-scope-budget.md`): after the split, 18c is 2 phases, 10 scenarios and 7 decisions over
two tracks (phone + sync contract); plan 18d carries the watch-client track. The order is fixed — receiver first: 18c
ships before 18d.

## Code pointers (seeded)

| What | File : symbol (≈ line) |
|---|---|
| Wrist rest start / end | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` `isResting` (264), `endRest` (271), `log` (589 `if isResting { await endRest() }`), `startFollowOnTimer`; `WatchSessionEngine.swift` `stopTimer` (1569), `finishSession` (340), `abandonSession` (348), `appendObservation` (1225) |
| Wrist kinds / record | `WatchRecords.swift` `WatchObservationKind` (50), `WatchObservationRecord` (314) |
| Dart twin | `lib/watch/session/watch_records.dart` kinds (62), `watch_session_engine.dart` (`stopTimer`, `finishSession` 341), `lib/watch/logging/watch_logging_state.dart` `endRest` (197) |
| Wire | `watch/sync_protocol/schemas/envelope.schema.json` event kind enum (~179) and `$defs.event`; `schemas/messages/observations_up.schema.json`; `lib/core/sync_protocol/message_validator.dart` (kinds ~123); `SyncProtocolValidator.swift` (kinds ~68); `fixtures/manifest.json`; `PROTOCOL.md` message table and Version history |
| Phone staging | `lib/data/models/models.dart` `WatchInboxEntry` kinds (2621), `watchKinds`; `lib/state/watch/watch_session_inbox.dart` `_requiredFields` (~183) |
| Phone import | `lib/core/services/watch_session_importer.dart` `_effortKinds` (103), flows around 160-310, `_createEntry` (855), `_applyCorrections` (996), `_reindexInstance`, `_deleteInstance` |
| Rest storage / total | `EntryRest` `models.dart:1600`; `WorkoutRepository.createEntryRest` (253) / `getEntryRests` (250); `session_summary_service.dart` `computeSessionRestTimeMs` |
| Phone's own convention | `lib/state/workout/timer_manager.dart` `recordRestStart` (~693-736) |

The wrist rows (rest start/end, `WatchRecords`, the Dart twin) describe plan 18d's work; they are kept here because the
seeded table is not edited, and plan 18d carries its own copy for its executor.

## Iteration 1 (planner, Iteration 1)

Phase 1A is part A of the seeded Phase 1; part B (the wrist emits) and the seeded Phase 3 moved to plan 18d under the
governor's scope split of 2026-10-08. Phase 1A must still land before the phone's Phase 2 (the staging path needs the
wire's field contract), and both land before 18d begins.

### Phase 1A: the wire (@developer) — part A of the seeded Phase 1

1. [x] Add `"rest"` to `$defs.entry.properties.kind.enum` and declare
       `$defs.entry.properties.afterEntryId` (`type: string`, `minLength: 1`, a one-line description: the id of the set
       this rest follows) — `watch/sync_protocol/schemas/envelope.schema.json` · `$defs.entry` (D-222).
2. [x] Add the eighth `$defs.event.oneOf` branch, requiring
       `kind, sessionExerciseId, exerciseId, startedAt, endedAt, afterEntryId` with `properties.kind.const = "rest"`
       (mirror the `timed` branch verbatim) — `watch/sync_protocol/schemas/messages/observations_up.schema.json` ·
       `$defs.event` (D-222).
3. [x] Add the window rule: a `rest` event whose `endedAt` is not after its `startedAt` is refused as
       `semantic_violation` at path `$.payload.events[i].endedAt`, reason naming both instants; call it from
       `_semanticRejections` beside `_restLengthRejections`, and parse both instants as UTC (`DateTime.tryParse`; an
       unparseable instant stays the schema's `type` rejection) — `lib/core/sync_protocol/message_validator.dart` ·
       `_semanticRejections` (`:268`), new `_restWindowRejections`.
4. [x] The same rule, same code, same path and same reason text, in the mirror validator — the fixtures pin both to one
       answer — `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` · its semantic layer (the mirror of
       `_semanticRejections`).
5. [x] Add the fixtures: `watch/sync_protocol/fixtures/valid/observations_up_rest.json` (one set `entry-a1`, then one
       70 s `rest` with `afterEntryId: "entry-a1"`), `…/invalid/observations_up_rest_missing_after_entry_id.json`
       (`missing_required_field`, reason contains `afterEntryId`),
       `…/invalid/observations_up_rest_planned_duration.json` (`unexpected_field`, reason contains `plannedDurationMs`),
       `…/invalid/observations_up_rest_not_after.json` (`semantic_violation`, reason contains `endedAt`).
6. [x] Register all four in `watch/sync_protocol/fixtures/manifest.json` — one `valid` row (`type: "observations_up"`,
       `"scenario": "S-330"`) and three `invalid` rows with `expectedCode`/`expectedReasonContains`. The on-disk test
       (`test/sync_protocol_fixtures_test.dart:158`) fails unless each file is listed exactly once.
7. [x] `watch/sync_protocol/PROTOCOL.md`: add the kind to the `observations_up` row of the message-families table, and
       one dated `1 (amended)` row in `## Version history` naming the kind, its fields, the four fixtures and S-330.
       A short row only (D-217), and every `schemas/`/`fixtures/` path the row names must exist
       (`test/sync_protocol_fixtures_test.dart:764`).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart`,
`.github/copilot/scripts/macos/gateway.sh swift-test` (the Swift conformance suite walks the same manifest, so a
validator divergence fails here). **Red first**: with items 5–6 done and items 1–4 not, the Dart suite must fail on the
new fixtures — paste that failure into `….evidence.md` before making them pass. Baselines: analyze 196 / 0.
**Predicted Files**: the two schema files, `lib/core/sync_protocol/message_validator.dart`,
`watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`, the four fixtures, `fixtures/manifest.json`,
`watch/sync_protocol/PROTOCOL.md`.

### Phase 2: the phone writes it (@dba) — the seeded Phase 2

1. [x] Add the wire kind: `static const kindRest = 'rest'` next to `kindSessionEnd` and `kindRest` in `watchKinds` —
       `lib/data/models/models.dart` · `WatchInboxEntry` (`:2621`), so `_checkInvariants`' kind allow-list (`:2725`)
       accepts the row instead of throwing into `_entryFor`'s swallow (D-214).
2. [x] Add the field contract `kindRest: [sessionExerciseId, exerciseId, startedAt, endedAt, afterEntryId]` to the map,
       which `_isStageable` (`:501`) consults before `_settleNow` (`:420`) receipts the row —
       `lib/state/watch/watch_session_inbox.dart` · `_requiredFields` (`:171`) (D-214).
3. [x] Add `_applyRests(rows, placedEffort, sessionExerciseId)`: in arrival order resolve `afterEntryId` through the
       placed entries' `entryId` → `entryIndex` = that entry's index + 1; drop (and report as consumed) a row with no
       match or with `endedAt <= startedAt`; skip when `getEntryRests(effortId)` already holds a rest at that
       `entryIndex`; otherwise `createEntryRest` with D-167's id (`'rest-<effortId>-<entryIndex>'`), window
       (`restStartMs`/`restEndMs`) and `entryIndex`; return the written/dropped split —
       `lib/core/services/watch_session_importer.dart` · new `_applyRests` (D-215, D-216, D-222).
4. [x] Call it where entries are final and rows are about to be consumed, for a new import **and** a top-up:
       after the placement loops of `_Pass.run` (`:429`) and before `_markApplied` (`:214`) — `…_importer.dart` ·
       `_Pass.run` / `apply` (`:127`). A pass that creates no session writes no rest (D-214, S-326).
5. [x] The merge flow: call `_applyRests` for the phone-held effort before `_consume` (`:367`) / `_markApplied`
       (`:369`), so the phone's own rest at that `entryIndex` wins and the row is consumed either way —
       `…_importer.dart` · `_mergeHeld` (`:224`) (D-216).
6. [x] Count a written rest as a write: include the effort in the pass's changed set (the same value that feeds
       `historyChanged`, and `_mergeHeld`'s `changedEffortIds`) so the summary recomputes; a dropped row must not —
       `…_importer.dart` · `apply` (`:127`) and `_mergeHeld` (`:224`).
7. [x] Tests for S-320 (phone side), S-323, S-324, S-326, S-327 and S-328: a staged rest becomes one `EntryRest`;
       a duplicate delivery and a re-run pass write once; a zero-length row is dropped; a rest plus a `session_end`
       alone creates no session; deleting the set leaves the rest; an unresolvable rest is consumed and not retried —
       `test/watch_session_import_test.dart` and `test/watch_session_rest_timer_append_test.dart` (Mock-first).
8. [x] Tests for the merge and top-up flows (S-320's second and third flow, S-325, S-328, S-337, S-338) and the parity
       row: one fixture asserted through `MockWorkoutRepository` and through `HiveWorkoutRepository` yields one row with
       the same `entryIndex`, `id`, `restStartMs`, `restEndMs` — `test/watch_session_merge_test.dart` (Hive seeded in
       `setUp`), with `test/db_seed_test.dart` still green (no model, no SQL change).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart test/watch_session_merge_test.dart test/watch_session_rest_timer_append_test.dart test/db_seed_test.dart`;
guard proof: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_import_test.dart` must
**fail** at the base commit. Baselines: analyze 196 / 0. The only Swift 18c touches are Phase 1A's mirror validator
(`SyncProtocolValidator.swift`); no Swift client change, and `swift-test` ran 376 / 0 (plan 18d's final phase runs it
again, with the full suite and the governor's watch-app build).
**Predicted Files**: `lib/data/models/models.dart`, `lib/state/watch/watch_session_inbox.dart`,
`lib/core/services/watch_session_importer.dart`, the three test files named above.

### Phase 3: totals, views, docs (@developer) — → moved to plan 18d (its Phases 2 and 3, split there)

## Files Affected (whole feature)

Production: `watch/sync_protocol/schemas/envelope.schema.json`,
`watch/sync_protocol/schemas/messages/observations_up.schema.json`, `lib/core/sync_protocol/message_validator.dart`,
`watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`, `lib/data/models/models.dart`,
`lib/state/watch/watch_session_inbox.dart`, `lib/core/services/watch_session_importer.dart`.
Contract data: `watch/sync_protocol/fixtures/valid/observations_up_rest.json`, three `…/invalid/…rest…json` fixtures,
`watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`.
Tests: `test/sync_protocol_fixtures_test.dart` (no edit), `test/watch_session_rest_timer_append_test.dart`,
`test/watch_session_import_test.dart`, `test/watch_session_merge_test.dart`, `SyncProtocolFixturesTests.swift` (no edit).
Dependents that only read a touched surface (no edit, but their tests must stay green):
`lib/data/repositories/{hive,mock}_workout_repository.dart`, `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`,
`lib/state/workout/timer_manager.dart`.

**Moved to plan 18d** (not touched by this plan): `WatchRecords.swift`, `WatchSessionEngine.swift`,
`lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_engine.dart`,
`WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift`, `WatchSessionEngineTests.swift`,
`WatchFileStoreTests.swift`, `test/watch_session_engine_test.dart`,
`test/watch_session_summary_integration_test.dart`, `test/watch_rest_to_phone_view_test.dart`,
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/rest_tracking.md`, the 17a plan file,
`docs/plans/2026-10-08-18-watch-qa-index.md`.

## Notes (planner, Iteration 1)

- **Dependency graph.** 1A → 2 (staging needs the schema's field contract) and both → plan 18d (the wrist emits in 18d's
  Phase 1; totals, views and docs follow in 18d's Phases 2–3). Nothing in this plan depends on 18d: every scenario here
  is provable with the wire fixtures standing in for the wrist.
- **Intermediate states.** After 1A the wire accepts a kind nobody sends. Nothing on the phone's screens changes until
  Phase 2's importer runs, and no client emits a rest at all until plan 18d ships.
- **Fixture stand-in.** S-320's end-to-end proof here is the hand-written `observations_up` fixture (a `rest` after
  `entry-a1`) standing in for the wrist; 18d re-proves the same scenario from the engine on both stacks.
- **Emission site, twin parity, adopted timers.** Those notes moved with the work to plan 18d's `## Notes` (a second
  emission site would double the rest; the twin has no `session_end` gap either; an adopted rest still emits, a
  phone-sent stop does not).
- **No model, no SQL, no repository change.** `EntryRest` and both repository rest methods already exist (V-4);
  `app_entry_rest` in `scripts/sqlite_schema.sql:756` already matches D-167's `entry_index`/`rest_start_ms`/`rest_end_ms`.

## Progress (planner, Iteration 1)

- Plan expanded from the seed; all five seed questions verified against the base commit (V-1 is a divergence: the finish
  path stops nothing today — D-211 pre-authorises the addition, now plan 18d's Phase 1 item 4). No phase has started.
- Split (governor, 2026-10-08): the seeded Phase 1B and Phase 3 moved to plan 18d; this plan is the receiver-first half
  (1A the wire, 2 the phone writes it). Moved Ledger entries and scenarios stay here as one-line markers.
- Phase 1A: **Complete** (developer, 2026-10-08, base cd1830f). All 7 items done; fixtures + manifest + schemas +
  both validators + PROTOCOL.md. `test/sync_protocol_fixtures_test.dart` `+95`, `swift-test` 376 / 0,
  `rest_is_count_up_contract_test.dart` + `watch_capture_contract_conformance_test.dart` `+27`, `lint` 196 (baseline).
  Red evidence (fixtures present, schemas unchanged: `+66 -3`) and the `prove-red` not-applicable note are in
  `.evidence.md`. Phase 2: complete (below).
- Phase 2: **Complete** (dba, 2026-10-08, base dc69aa3). All 8 items done; `kindRest` in `WatchInboxEntry.watchKinds`
  and its field contract in `_requiredFields`; `_applyRests` called at the end of `_Pass.run` and in `_mergeHeld`.
  Done Criteria (`test/watch_session_import_test.dart test/watch_session_merge_test.dart
  test/watch_session_rest_timer_append_test.dart test/db_seed_test.dart`) → `+105`; full suite `+4204 ~1`; `lint` 196
  (baseline, none in the touched files). `prove-red dc69aa3` → **RED AT** on the merge file (`+28 -12`) and the
  rest-timer file (`+1 -1`); the import file cannot load at the base (the constant is new), so its group is proved by
  two mutations, both pasted in `.evidence.md`. No repository, model or SQL change; the only Swift change is Phase 1A's
  mirror validator.
- Fix round 1 (developer, 2026-10-08, base dc69aa3): review F-1/F-2/F-3/F-4 and A-10 addressed — two new import
  tests (S-328 the same-instant rest pin, the A-3 rest missing `afterEntryId` negative), the Impact table's reader
  set, the three Swift sentences, and A-10. Counts and both mutation proofs in `.evidence.md` "Fix round 1".
- Baselines to beat at the base commit: flutter +4181 ~1, swift 376 / 0, analyze 196 / 0, `xcodebuild "OmniTrain Watch
  App"` (governor-run).

## Assumption Log (planner, Iteration 1)

- **A-1** Kept the seeded D-211 text although its premise ("the one place every ending goes through") is false at the
  base commit: `stopTimerFromMessage` (`WatchSessionEngine.swift:752`) bypasses `stopTimer` and `transitionTo` (`:1071`)
  stops no timer. Chose to keep the seed and implement the addition D-211 itself sanctions, rather than rewrite a seeded
  entry. Raised in Open questions; the implementation is now plan 18d's Phase 1 item 4.
- **A-2** Read D-213's "the last observation the wrist logged on that exercise" positionally (D-221), because a timer row
  carries no slot and any log ends a running rest first, so the positional and per-exercise answers coincide. Vetoable.
- **A-3** Decided a phone-initiated stop emits nothing (D-219), so the phone cannot count a rest twice. Vetoable.
- **A-4** Made the wire refuse `endedAt == startedAt` as well as "before" (D-222); the seed's S-330 names only "before".
  Refusing equality keeps a zero-length rest off the wire entirely. Vetoable.
- **A-5** Split the seeded Phase 1 into two runs (1A/1B) at the 8-item boundary rather than adding a fourth phase. The
  governor then moved 1B (and Phase 3) into plan 18d, so this plan holds two phases (1A, 2) with 7 and 8 items.
- **A-6** The moved Ledger entries and scenarios are reproduced verbatim in plan 18d under their original ids, with a
  transpose note naming this plan — chosen over bare cross-references because 18d must be self-contained for its
  executor, and this file's markers must not need editing later. Vetoable.
- **A-7 (dba, Phase 2)** Item 3's sketched signature `_applyRests(rows, placedEffort, sessionExerciseId)` is not
  buildable as written: resolving `afterEntryId` needs the entry's *final* index, which only the placement loops know.
  Built `_applyRests(rows)` over a `_placed` map (`entryId → effortId + final index`) that `_placeEntries` and
  `_placeAroundUserRows` fill. Same behaviour, one map, one pass.
- **A-8 (dba, Phase 2)** A written rest sets the pass's `changed`, so it counts as a write (item 6) and a merge names
  the effort; a dropped row sets nothing. `test/watch_session_merge_test.dart` pins both (the receipt and the refresh
  count). Vetoable.
- **A-9 (dba, Phase 2)** `kindRest` is in `watchKinds` only, never in `_effortKinds`: a rest is not an entry, so it is
  never placed, re-stated by a correction, re-indexed or deleted. S-327 pins the delete case. Vetoable.
- **A-10 (dba, Phase 2)** Docs: `docs/watch_session_capture.md` was corrected (the staging list and the "only … are
  staged" invariant). `docs/rest_tracking.md` was left as committed — the governor restored it because its wording
  claims a wrist rest reaches the phone, untrue until plan 18d — and is plan 18d's.
- **A-11 (dba, Phase 2)** S-323 stages its zero-length row with `repository.stageWatchInboxEntry`, because 1A's wire
  rule (A-4) refuses `endedAt == startedAt` — the older-peer row cannot arrive as a message. The test asserts the
  refusal first, then the drop. Vetoable.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

## Open questions

(The planner appends here. Governor's defaults, none needing the owner: the wrist shows nothing new; a rest with no
resolvable set is dropped silently; the phone's own rest at a spot always wins.)

Planner, Iteration 1 — each with the default taken. None blocks Phase 1A.

1. **Seeded D-211 is factually wrong about the base commit** (kept, not edited, per the brief). It says the rest stop is
   "the one place every ending goes through", but `stopTimerFromMessage` (`WatchSessionEngine.swift:752`, reachable from
   `applyTimerState` `:658`/`adoptTimers` `:665`) does not call `stopTimer` (`:1569`), and `transitionTo` (`:1071`, from
   `finishSession` `:340`/`abandonSession` `:348`) neither calls it nor stops any timer. *Default taken*: keep the text,
   add the finish-path stop D-211    pre-authorises (plan 18d's Phase 1 item 4) and pin the phone-sent stop in D-219. *Needed*: a
   governor decision only if the seeded wording itself is the contract.
2. **A phone-initiated stop emits nothing** (D-219). The alternative — emitting there too — would hand the phone a rest it
   just ended itself and double the row. *Default taken*: no emission; S-333 asserts it.
3. **D-213's lookup is positional** (D-221), because a timer row carries no slot and `log()` ends a rest before appending
   the entry that follows it. *Alternative*: index entries by exercise and pick the newest by `loggedAt`. *Default taken*:
   positional, in both stacks.
4. **The wire refuses `endedAt == startedAt` too** (D-222), stricter than S-330's "before". *Default taken*: refuse both,
   and let the phone drop a legacy row (S-323).
5. **A stray `afterEntryId` on another kind is accepted** (inert) rather than gated by a new kind map in both validators.
   *Default taken*: accept; nothing reads the field on another kind. Vetoable — a kind-gated rule plus one invalid fixture
   would close it.
6. **Scope — answered by the governor (split decided).** The governor split this plan on 2026-10-08: 18c keeps 1A (the
   wire) and 2 (the phone writes it), and the seeded Phase 1B and Phase 3 moved to plan 18d (the wrist emits it, then
   totals/views/docs). The "three soft signals" reading is resolved by the split; nothing further is needed from the
   owner here.
7. **Governance.** Nothing was denied that the plan needs: no file had to be created, moved or deleted under this plan
   folder, and no new directory was needed (the plan folder exists). Two early shell probes (`wc -l`, `ls`) were denied by
   policy and were replaced by `glob`/`view`/`grep`; the plan's Done Criteria use only gateway checks, so no governor
   action is required. Plan 18d's `…-plan.evidence.md` is a new file inside a plan folder, created with the file tools.
