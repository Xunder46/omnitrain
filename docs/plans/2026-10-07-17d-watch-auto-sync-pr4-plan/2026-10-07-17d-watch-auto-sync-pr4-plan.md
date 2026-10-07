# Feature: watch auto-sync PR 4 — the phone's other entry kinds reach the wrist

> Status: DRAFT awaiting implementer start (owner unavailable; defaults below bind, see Open questions)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` + `docs/watch_session_sync.md`,
> `docs/modality_tracking.md`, `docs/modality_based_exercise_ui.md`,
> `watch/sync_protocol/PROTOCOL.md`
> Series index: `docs/plans/2026-10-06-17-watch-auto-sync-index.md` (this plan is PR 4)
> Predecessor: `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/2026-10-06-17c-watch-auto-sync-pr3-plan.md`
> (deletions reaching the wrist — its D-112 held-id read and D-113 receiver rules are assumed in place)

## Overview

17a/17b/17c carry a phone session to the wrist: sets, edits of sets, a session end, and (17c) a
deletion. This PR closes the remaining projection gap named in the brief:

- **The phone's `timed`, `hold` and `round` entries never reach the wrist** (15-series D-39):
  `PhoneEntries.project` builds `set` entries only, and `WatchSessionAdoptionBridge._entriesFor`
  (`lib/state/watch/watch_session_adoption_bridge.dart:243`) returns `const []` for every effort whose
  `effortKind != BlockTypes.set`. The wire is ready for them — `$defs.entry` in
  `watch/sync_protocol/schemas/messages/envelope.schema.json` already has the `timed`, `hold` and
  `round` shapes, and both validators already accept them (`message_validator.dart:133–137`,
  `SyncProtocolValidator.swift:78–82`) — so this is a **sender** gap, exactly like 17c's.
- The two omissions the owner asked to be decided are **decided and out of code scope** (D-135,
  D-136): a skipped set and a set's added weight stay off the wire, stated plainly in the doc. 17c
  already ships the doc sentences; this plan carries the decisions and the residue sweep that proves
  no other code path reintroduces them.

**Where the data comes from.** The phone already stores everything the wire needs, behind the
repository interface it may read: `getTimedInstances(effortId)` /
`getTimedInstancesByEffort()` (`lib/data/repositories/workout_repository.dart:224`, `:106`) and
`getRoundInstances(effortId)` / `getRoundInstancesByEffort()` (`:192`, `:198`), plus the effort's
observation rows. `TimedInstance` (`lib/data/models/models.dart:1241`) carries
`entryIndex`, `startedAtMs`, `finishedAtMs`, `totalPausedDurationMs`; `RoundInstance` (`:1041`)
carries `roundIndex` (0-based), `startedAtMs`, `finishedAtMs`, `totalPausedDurationMs`, `completed`.
No new repository method and no model change is expected — Phase 1's first item confirms that by
reading, and the plan says what to do if it does not hold.

Spec magnitude: **3 phases, 1 track** (`lib/` + the watch tests; the Swift side needs tests only, not
new production rules), D-130…D-138, S-140…S-146 — inside the budget.

## Resolved Decisions (Ledger)

Decisions are immutable once written; a change is a new superseding entry.

### D-130 — The phone projects a non-set entry from the instance the session already stores, with the wire's own kind and field names

`PhoneEntries` (`lib/core/sync_protocol/phone_entries.dart`) gains one projection per kind, beside
`project` (which keeps its `set`-only contract so every existing caller and test is unchanged):

| Phone record | Wire kind | Fields the phone writes |
|---|---|---|
| `TimedInstance` | `timed` | `entryId`, `eventId` (= `entryId`), `sessionExerciseId`, `exerciseId`, `kind`, `loggedAt` = `finishedAtMs` (or `startedAtMs` while in progress), `startedAt`, `endedAt`, and `distanceMeters`/`distanceSource` only from the effort's distance observation for that entry index |
| `TimedInstance` on a hold effort | `hold` | as above, plus `extraLoadKg` from the effort's added weight for that entry |
| `RoundInstance` | `round` | `entryId`, `eventId`, `sessionExerciseId`, `exerciseId`, `kind`, `roundNumber` = `roundIndex + 1`, `loggedAt`, `startedAt`, `endedAt`, `pausedMs` = `totalPausedDurationMs` when non-zero, `distanceMeters`/`distanceSource` when the effort carries a distance observation for that round |

- **The kind is the effort's kind on the wire, not the phone's effort kind.** A `timed`-capability
  effort is `timed`; an effort carrying the `hold` capability is `hold`; a rounds effort is `round`,
  decided by the same capability precedence the wrist's own logger uses
  (`WatchLoggingState.kindPrecedence = ["hold","rounds","reps","sets","load","time","distance"]`) so
  that a phone-logged entry and a wrist-logged entry of the same effort arrive with the same kind. If
  the precedence is not reachable from `lib/core/constants/modality_config.dart` without new code,
  mirror the wrist's order in one private function beside the projection and cite this decision — do
  not invent a second precedence.
- **Unit and field agreement with the wrist's own spelling.** Whatever the wrist's own logger writes
  for an entry of a kind (`WatchLoggingState.swift:600–700`: `windowPayload(coversDistance:)` →
  `{startedAt, endedAt, distanceMeters?}`, `extraLoadKg?` for a hold, the round window for a round),
  the phone writes byte-compatible values for the same kind. Phase 1 item 3 pins this by reading that
  function, and any disagreement is a bug in the phone's projection, not a reason to change the wire.
- **A hold with no instance.** When an effort has the `hold` capability but the phone stored no
  `TimedInstance` for it (a hold logged as a duration observation alone), the phone reconstructs the
  window the same way the wrist's own logger does — `[loggedAt − duration, loggedAt]` from the
  observation's `recordedAtMs` and its stored duration — **only when the row carries a duration**;
  otherwise the entry is omitted (D-132). This is the wrist's convention, not an invention.

### D-131 — A non-set entry's id is `entry-<sessionExerciseId>-<n>`, with `n` the record's own index

`TimedInstance.entryIndex` (0-based) and `RoundInstance.roundIndex` (0-based) are the numbers the
phone's own row ids already carry (`EntryRows.parseId`/`numberInId`,
`lib/core/utils/entry_rows.dart:91,100`), so the minted wire id is the same shape as a set's
(`entry-<sessionExerciseId>-<n>`), with a `0`-based number for these kinds rather than a set's
1-based group number. The id is a stable handle: it does not change when the entry is edited, and it
is what 17c's delete frame names.

- The id is **not** required to be numerically consecutive and is **not** a position: deleting entry 1
  of three leaves the other two ids untouched (the wrist sorts the projection by `loggedAt`, then id —
  `_byLoggedAtThenEntryId`, `watch_session_engine.dart:1001`).

### D-132 — Omit, never placeholder

An instance or observation that cannot be expressed as a valid wire entry is **omitted**, because one
invalid entry fails the whole snapshot on both receivers (both validators reject the frame):

- an instance that never started (`startedAtMs == 0` and no `finishedAtMs`) — nothing happened;
- a window whose `endedAt` is not after its `startedAt` (the schema/minimum rule);
- a distance that is not `> 0` (never `distanceMeters: 0`);
- a `hold`'s `extraLoadKg` of exactly 0 (the schema's exclusive minimum);
- a round whose `roundIndex + 1 < 1` — impossible by construction, listed so the guard is explicit;
- a `loggedAt` below the wire minimum (the same floor a set already respects).

No `null` placeholder, no `0`, no fabricated duration. A phone entry that is omitted is a known limit
and is stated in the doc (Phase 3), not a silent loss: the wrist's own entry list already shows what
the wrist itself logged.

### D-133 — Provenance extends to every kind: a wrist entry of any kind still claims its phone record

15-series D-34 (a wrist `WatchInboxEntry` row claims the phone group whose stamp matches) is extended
from `kindSet` to `timed`, `hold` and `round` rows: the phone must not send back an entry the wrist
itself logged, under a phone-minted id (that is the doubling defect of the 15-series F3 evidence).

- The claim read is `WatchSessionAdoptionBridge._wristRowStamps`
  (`lib/state/watch/watch_session_adoption_bridge.dart:271`), which today **skips** every row whose
  `kind != WatchInboxEntry.kindSet`; Phase 1 removes that filter and matches per kind
  (`WatchInboxEntry.kindTimed` / `kindHold` / `kindRound` — add the constants beside `kindSet` at
  `lib/data/models/models.dart:2618` if they do not exist, in the same PR and in the `@dba`-routed
  layer).
- The claim's stamp for a non-set entry is the stamp the importer wrote on the phone's record for it.
  **Phase 1 item 1 reads `lib/state/watch/watch_session_importer.dart`'s write path for a non-set entry
  and cites the `createdAtMs`/stamp it writes.** Pinned fallback if the importer does not stamp a
  non-set entry with the wrist's `loggedAtMs`: the claim compares the row's `loggedAtMs` to the phone
  record's own stamp — `TimedInstance.finishedAtMs ?? startedAtMs`, `RoundInstance.finishedAtMs ??
  startedAtMs` — and the phase records which rule it used and why in the evidence file. Either way the
  observable rule is: **one wrist entry produces at most one phone entry, and never a duplicate pair.**
- `heldWristEntryIds` (17c D-112) drops its `kindSet` filter in the same phase, so a non-set entry the
  wrist logged and the user deleted on the phone is announced like any other (17c D-110…D-116 do the
  rest; this PR adds no sender).

### D-134 — The wrist renders a phone-sent non-set entry exactly like its own kind

No new wrist rule and no new wrist surface: a `timed`/`hold`/`round` entry from the phone flows into
the same `entries` projection the wrist's own logger feeds, and the logging surface's derived counts
(`WatchLoggingState`'s per-kind tallies) therefore include it. The Dart twin does the same. Phase 2
proves this by test in both twins rather than by adding code; if a test fails, the finding is a
receiver defect and becomes a remediation sub-phase, not a plan change.

### D-135 — A set the user skipped stays off the wire (owner default, restated)

Carried from 17c D-117, and binding here: **a skipped set is not a performed set** — it has no window,
no reps the user did and no load they moved, so sending it would show the wrist work that never
happened. PROTOCOL's set shape has no `skipped` property (`additionalProperties: false`), and this PR
adds none. The phone's existing behaviour (`project` omits `reps < 1`) already implements it; Phase 3's
residue sweep proves no other sender re-introduces a skipped set, and the doc sentence (shipped in
17c) names its test.

### D-136 — A set's added weight stays off the wire (owner default, restated)

Carried from 17c D-117. The wire's `extraLoadKg` is documented as a **hold's** added load and the
receiver reads it on the hold path; a set's added weight reaches the wrist as part of the set's total
`loadKg`, which is what the wrist's set row needs. A set's `extraLoadKg` is therefore never written,
and `phone_entries.dart`'s doc comment (which says exactly this today) stays true. Adding it later
means a schema property, both validators, a fixture and a wrist surface that renders a distinct
"added weight" value — a PR of its own.

### D-137 — Nothing else about an entry travels

- The phone's **rest timer** does not travel, for any kind (17a D-80 holds; rest stays per-device).
- An entry's **sensor values** (heart rate, steps, `sensorSummary`) are the wrist's own logging
  output; the phone does not send them.
- `pausedMs` is written for a `round` only (both validators accept it there and nowhere else), so a
  paused `timed` entry travels with its wall-clock window and no pause field.
- No new frame type, no schema change, no validator change: every shape this PR sends already exists
  and is already validated (D-130's table is a sender-side contract).

### D-138 — Verification uses the existing gates; docs land with the tested behaviour

`gateway.sh lint`, `gateway.sh test <suites>`, `gateway.sh swift-test`, `prove-red` where a new
assertion is the fix. No simulator and no `xcodebuild` — this PR changes no Swift production code
(D-134), so the Swift side is test-only and `swift-test` is sufficient. Doc prose lands in Phase 3
(with its tests), every behaviour sentence names a real test, and no `docs/` file passes the 52 KB
band (`test/docs_indexing_contract_test.dart`).

## Feature Invariants

- **I-1 Parity.** `HiveWorkoutRepository` and `MockWorkoutRepository` produce the same observable
  output for the same inputs — so the projection reads instances through the interface and produces
  the same payload for both. The Dart twin and the Swift twin hide and show the same entries for the
  same frames.
- **I-2 Layer boundary.** `lib/state/` reads `WorkoutRepository` only; the bridge keeps reading the
  interface (`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
  must stay empty).
- **I-3 Omit, never placeholder.** An unrepresentable entry is left out; a fabricated `0` or a
  placeholder window is a defect (D-132).
- **I-4 One entry per real record.** A wrist-logged entry of any kind appears exactly once in the
  projection, and never doubled under a phone-minted id (D-133).
- **I-5 No invented data.** Every field the projection writes comes from a stored instance or
  observation; a duration is never estimated.

## Requirements

- **R-1** A `timed` entry logged on the phone during an active session appears on the wrist with the
  same kind and window, without a Sync tap.
- **R-2** A `round` entry appears with its round number, and a `hold` entry with its window and its
  added load.
- **R-3** An entry the wrist logged is not sent back to it under a phone id (no doubling), for any of
  the four kinds.
- **R-4** An entry that cannot be expressed validly is omitted, and the rest of the snapshot still
  arrives (one bad instance never fails the whole frame).
- **R-5** Deleting a phone `timed`/`hold`/`round` entry reaches the wrist using 17c's sender — no new
  frame, no new button.
- **R-6** No new sync surface: these are active-session actions, so there is no Sync tap, no new
  screen and no new control.

## Acceptance Criteria

| AC | Statement | Scenarios |
|---|---|---|
| AC-1 | A phone `timed` entry reaches the wrist with the wire's `timed` shape: `kind`, `entryId`, `loggedAt`, `startedAt`, `endedAt`, optional `distanceMeters`/`distanceSource`. | S-140 |
| AC-2 | A phone `round` entry carries `roundNumber` (= `roundIndex + 1`) and a `hold` carries `extraLoadKg` — each in the shape both validators accept. | S-141 |
| AC-3 | A wrist-logged `timed`/`hold`/`round` entry is claimed by stamp and is not sent back to the wrist (one entry, not two). | S-142 |
| AC-4 | An instance that cannot be expressed (never started, zero-length window, zero distance) is omitted while the rest of the snapshot arrives. | S-143 |
| AC-5 | A phone `timed` entry deleted on the phone disappears on the wrist through 17c's deletion sender. | S-144 |
| AC-6 | The wrist's logging surface counts a phone-sent non-set entry like one of its own; the Dart twin shows the same list. | S-145 |
| AC-7 | The docs state which kinds travel, name their tests, and the residue sweep shows no `set`-only assumption left; no `docs/` file passes 64 KiB. | S-146 |

## Existing-Functionality Impact

| Touched surface | What already reads it (the read) | Effect of the change | Guarded by |
|---|---|---|---|
| `PhoneEntries.project` | `grep -n "PhoneEntries.project\|PhoneEntries.ordered" lib test` — the bridge at `:243` and `test/watch_session_projection_test.dart` / `test/sync_protocol_fixtures_test.dart` | **Unchanged signature and behaviour**; siblings are added beside it, so all existing assertions stay green | S-140 · regression: the two suites |
| `WatchSessionAdoptionBridge._entriesFor` (`:243`) | `grep -n "_entriesFor" lib test` — one caller, `projectSession` | The `effortKind != set → const []` early return is replaced by a per-kind dispatch; `projectSession`'s shape and the `timers: {}` field are untouched | S-140, S-141 |
| `WatchSessionAdoptionBridge._wristRowStamps` (`:271`) | `grep -n "_wristRowStamps" lib test` — the claim rule for sets (the 15-series F3 fix) | The `kindSet` filter is replaced by a per-kind match; the set behaviour must not change | S-142 · regression: `test/watch_session_import_test.dart` |
| `WatchInboxEntry.kindSet` (`lib/data/models/models.dart:2618`) | `grep -n "kindSet\|kindTimed\|kindHold\|kindRound" lib test` | New sibling constants only if absent; existing rows' stored `kind` strings are never renamed | S-142 |
| `heldWristEntryIds` (17c D-112) | `grep -n "heldWristEntryIds" lib test` | Its `kindSet` filter drops to the four kinds the wire carries; the set behaviour is unchanged | S-144 |
| `$defs.entry` in `envelope.schema.json` + both validators | `test/sync_protocol_fixtures_test.dart`, `SyncProtocolValidator.swift:78–82` | **Not touched** — the shapes already exist; they are the conformance target | S-140, S-141, S-143 |
| `WatchLoggingState`'s kind precedence and `windowPayload` (`WatchLoggingState.swift:600–700`) | the wrist's own encoder; the Swift tests | **Not touched**; it is the agreement reference for D-130's field spelling | S-140, S-145 |
| `docs/watch_session_sync.md:328–338` ("Only sets are carried") | the doc bullet; the 17c plan touches the neighbouring delete bullet | Lists the four kinds, names the tests, and states D-135/D-136 plainly | S-146 |
| `EntryRows.parseId`/`numberInId`/`setGroups` | `grep -n "numberInId\|setGroups" lib test` | **Not touched**; it is the id-number reference for D-131 | S-140 |
| Per-device rest timers | 17a D-80 | **Untouched** (D-137) | not applicable |
| Skipped sets / a set's added weight | `phone_entries.dart`'s doc comment + `project`'s `reps < 1` omission | **No code change** — decision carried, doc states it (D-135/D-136) | S-146 |

## Scenarios

### S-140: A phone `timed` entry reaches the wrist

- **Fixture:** one session, one effort "Plank" with the time capability and one `TimedInstance`
  (`entryIndex` 1, `startedAtMs` 1000, `finishedAtMs` 61000, `state` finished) plus a distance
  observation of 0 for that index; a Mock-backed push bound to the session; one pass already run.
- **Trigger:** the entry is logged (or the pass re-runs).
- **Flow:** `projectSession` → `_entriesFor` → the `timed` projection → the snapshot.
- **Expected outcome:** exactly one entry with `kind == 'timed'`, `entryId == 'entry-<slot>-1'`,
  `loggedAt == 61000`, `startedAt == 1000`, `endedAt == 61000`, and **no** `distanceMeters`
  (0 is omitted, D-132); `SyncProtocolValidator`/`MessageValidator` accept the frame; the wrist shows
  the entry. Red without the change because `_entriesFor` returns `const []` for a non-set effort.
- **Edge case of:** none.

### S-141: A round and a hold carry their own fields

- **Fixture:** one rounds effort with two `RoundInstance` rows (`roundIndex` 0 and 1, both finished,
  the first with `totalPausedDurationMs` 5000) and one hold effort with an `extraWeight` of 12 kg and
  one held instance.
- **Trigger:** one pass.
- **Flow:** the per-kind dispatch.
- **Expected outcome:** two `round` entries with `roundNumber` 1 and 2, the first carrying
  `pausedMs == 5000` and the second carrying none; one `hold` entry carrying `extraLoadKg == 12`.
  Both frames validate. Red without the change for the same reason as S-140.
- **Edge case of:** S-140.

### S-142: A wrist-logged entry of any kind is not doubled (D-133)

- **Fixture:** the wrist logged a `timed` entry (`loggedAtMs` 61000) and a `round` entry; the phone
  imported both (one `WatchInboxEntry` row each, `origin == 'watch'`, `kind` `timed`/`round`) and holds
  the record the importer wrote (stamp as D-133 pins).
- **Trigger:** one pass.
- **Flow:** `_wristRowStamps` matches each row to its record by stamp per kind → the entry is claimed →
  `_entriesFor` sends only the unclaimed ones.
- **Expected outcome:** the snapshot carries neither wrist entry; the wrist's own two entries are the
  only ones present (no duplicate pair, no phone-minted twin). Red without the change because the
  claim rule today skips every non-set row.
- **Edge case of:** S-140.

### S-143: An unrepresentable instance is omitted, not faked (D-132)

- **Fixture:** one effort with three instances: one that never started (`startedAtMs == 0`,
  `finishedAtMs == null`), one with `finishedAtMs == startedAtMs`, and one good one.
- **Trigger:** one pass.
- **Flow:** the projection omits the first two.
- **Expected outcome:** the frame carries exactly one entry (the good one) and both validators accept
  it; nothing is sent with `startedAt == endedAt` or a zero distance. Red without the change because
  today the effort contributes no entries at all — the guard is that the fix does not add invalid ones
  (mutation: drop the zero-length guard → the validator rejects the snapshot and the test fails).
- **Edge case of:** S-140.

### S-144: A phone `timed` entry deleted on the phone reaches the wrist (17c's sender)

- **Fixture:** after S-140's pass, the ledger has seeded `entry-<slot>-1`.
- **Trigger:** delete the timed entry on the phone.
- **Flow:** 17c's `_announceDeletions` diffs the held set — with the `kindSet` filter dropped, the id is
  in the seed, so it vanishes.
- **Expected outcome:** one `delete_entry` frame naming the timed entry's id, and the wrist no longer
  shows it. Red without the change because the filter keeps the id out of the seed.
- **Edge case of:** S-140.

### S-145: The wrist's surface treats a phone entry like its own (D-134)

- **Fixture:** a wrist engine that has applied a snapshot with one phone `timed` entry, and the Dart
  twin with the same snapshot.
- **Trigger:** read the surface's derived counts and the twin's `entries`.
- **Flow:** the existing per-kind tallies.
- **Expected outcome:** the phone entry is counted in the kind's tally and appears in the twin's list
  exactly once, with the same fields. If either fails, it is a receiver defect → remediation sub-phase.
  Green at the base for the wrist's **own** entries; red for a phone-sent one only because the phone
  sends none today.
- **Edge case of:** S-140.

### S-146: Docs and the residue sweep (S-146)

- **Fixture:** the repo after Phase 3.
- **Trigger:** read `docs/watch_session_sync.md`, `PROTOCOL.md`; run the sweep grep.
- **Flow:** the "Only sets are carried" bullet is replaced by the four kinds and the two omissions,
  each naming a test; the sweep (`grep -rn "BlockTypes.set" lib/state/watch lib/core/sync_protocol`
  and `grep -rn "kindSet" lib/state/watch`) shows no remaining `set`-only assumption outside the
  documented boundaries.
- **Expected outcome:** every named test exists and is green; the sweep output is pasted in the
  evidence file; no `docs/` file passes 64 KiB. Verified by the reviewer.
- **Edge case of:** none.

## Iteration 1

### Phase 1: The phone projects its other kinds (@developer)

1. [ ] Read and record two facts in the evidence file, then proceed on the pinned fallbacks if they do
   not hold: (a) the `createdAtMs`/stamp `lib/state/watch/watch_session_importer.dart` writes for an
   imported non-set entry (D-133's first rule); (b) whether a hold effort's window is derivable from
   its observation row alone (D-130's "a hold with no instance"). · `2026-10-06-17d-…-plan.evidence.md`
2. [ ] Add the per-kind projections beside `PhoneEntries.project` in
   `lib/core/sync_protocol/phone_entries.dart` — one shared `_window` helper plus
   `projectTimed`/`projectHold`/`projectRound` (or one `projectInstance` with a kind switch),
   each documented as D-130's table and D-131's id rule. `project` keeps its `set`-only contract. ·
   `PhoneEntries:projectTimed`, `PhoneEntries:projectHold`, `PhoneEntries:projectRound`
3. [ ] Read `WatchLoggingState.windowPayload(coversDistance:)` and the hold/round spellings
   (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:600–700`) and make the phone's
   field names, signs and units agree for each kind; cite the function and the line in a doc comment. ·
   `PhoneEntries:_window`
4. [ ] Add the kind constants (`kindTimed`, `kindHold`, `kindRound`) beside `WatchInboxEntry.kindSet`
   in `lib/data/models/models.dart:2618` if they are absent — additive, no rename, no migration. ·
   `WatchInboxEntry:kindTimed`
5. [ ] Replace `_entriesFor`'s `effortKind != BlockTypes.set → const []` early return
   (`lib/state/watch/watch_session_adoption_bridge.dart:243`) with the per-kind dispatch: sets keep
   today's path, and the wires' other kinds read `getTimedInstances`/`getRoundInstances` through the
   repository and project them. · `WatchSessionAdoptionBridge:_entriesFor`
6. [ ] Drop `_wristRowStamps`'s `kind != kindSet` skip (`:271`) and match a row to its record per kind
   (D-133). · `WatchSessionAdoptionBridge:_wristRowStamps`
7. [ ] Add S-140, S-141, S-142, S-143 to `test/watch_session_projection_test.dart` and the payload
   shapes to `test/sync_protocol_fixtures_test.dart`'s conformance area if a fixture is the natural
   home; plain `test()`, Mock-first. · `test/watch_session_projection_test.dart`,
   `test/sync_protocol_fixtures_test.dart`
8. [ ] Write Progress + the two recorded facts + the red→green table for this phase. · the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart test/sync_protocol_fixtures_test.dart test/watch_session_import_test.dart test/phone_manage_bridge_test.dart`;
a `prove-red` demonstration on S-140 (red with the `_entriesFor` change reverted).
**Predicted Files**: `lib/core/sync_protocol/phone_entries.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `lib/data/models/models.dart` (constants only),
`test/watch_session_projection_test.dart`, `test/watch_session_adoption_bridge_test.dart`,
`test/sync_protocol_fixtures_test.dart`, this plan, the evidence file.

### Phase 2: The wrist shows them, and 17c's deletion covers them (@developer)

1. [ ] Add S-145 to `test/watch_session_engine_test.dart` (the Dart twin shows a phone `timed` entry
   once, with the phone's fields). · `test/watch_session_engine_test.dart`
2. [ ] Add the Swift half of S-145 to `watch/watchos/Tests/WatchSessionEngineTests/`: the logging
   surface's per-kind tally includes a phone-sent `timed` entry, and the engine's `entries` carries it
   once. No Swift production change is expected (D-134) — if one is required, stop and report it. ·
   `WatchSessionEngineTests`, `WatchLoggingStateTests`
3. [ ] Drop `heldWristEntryIds`'s `kindSet` filter
   (`lib/state/watch/watch_session_adoption_bridge.dart`, 17c Phase 1) so the ids of wrist-logged
   `timed`/`hold`/`round` entries join the held set, and add S-144 to
   `test/watch_session_auto_push_test.dart`. · `WatchSessionAdoptionBridge:heldWristEntryIds`,
   `test/watch_session_auto_push_test.dart`
4. [ ] Run the cross-stack and import suites as regression guards and record the counts
   (`test/watch_reconciliation_cross_stack_test.dart`, `test/watch_session_import_test.dart`,
   `test/watch_session_edit_restore_late_entry_test.dart`). · the evidence file
5. [ ] Write Progress + the red→green table for this phase. · the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_auto_push_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_session_import_test.dart`;
`.github/copilot/scripts/macos/gateway.sh swift-test`; a `prove-red` on S-144 (red with the filter
restored).
**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`,
`test/watch_session_engine_test.dart`, `test/watch_session_auto_push_test.dart`,
`watch/watchos/Tests/WatchSessionEngineTests/*`, this plan, the evidence file. No Swift production file.

### Phase 3: Docs, the contract sentence, and the residue sweep (@developer)

1. [ ] Rewrite `docs/watch_session_sync.md`'s "Only sets are carried" bullet (lines 328–338) to list the
   four kinds and what each carries, naming the tests of S-140/S-141, and restate D-135/D-136 in plain
   words (one sentence each) with the test that proves each. Record the file's size. ·
   `docs/watch_session_sync.md`
2. [ ] Add one dated sentence to `watch/sync_protocol/PROTOCOL.md`: which entry kinds the phone
   projects and from which record, with the id rule of D-131 (no schema change — the shapes already
   exist). · `watch/sync_protocol/PROTOCOL.md`
3. [ ] If `docs/modality_tracking.md` or `docs/modality_based_exercise_ui.md` claims the wrist only
   receives sets, correct that sentence in the same pass; otherwise record the read that proves no
   such claim exists. · `docs/modality_tracking.md`, `docs/modality_based_exercise_ui.md`
4. [ ] Residue sweep: run
   `grep -rn "BlockTypes.set" lib/state/watch lib/core/sync_protocol` and
   `grep -rn "kindSet" lib/state/watch lib/data/models` and paste both outputs in the evidence file;
   every remaining hit must be either a set-specific rule or documented as a boundary. ·
   the evidence file
5. [ ] Full-suite gate: `.github/copilot/scripts/macos/gateway.sh test` (900 s) and
   `.github/copilot/scripts/macos/gateway.sh swift-test`; compare both counts against the baseline
   recorded in the evidence file (do not assume the brief's numbers). · the evidence file
6. [ ] Write Progress + the final evidence table and hand the plan to the reviewer. · the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test` (full, 900 s);
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`;
`.github/copilot/scripts/macos/gateway.sh swift-test`.
**Predicted Files**: `docs/watch_session_sync.md`, `watch/sync_protocol/PROTOCOL.md`,
`docs/modality_tracking.md` / `docs/modality_based_exercise_ui.md` (only if a claim needs correcting),
this plan, the evidence file.

## Files Affected

- `lib/core/sync_protocol/phone_entries.dart` — the three projections (Phase 1)
- `lib/state/watch/watch_session_adoption_bridge.dart` — dispatch, claim per kind, held ids (Phases 1–2)
- `lib/data/models/models.dart` — the kind constants, if absent (Phase 1)
- `test/watch_session_projection_test.dart`, `test/sync_protocol_fixtures_test.dart` (Phase 1)
- `test/watch_session_engine_test.dart`, `test/watch_session_auto_push_test.dart` (Phase 2)
- `watch/watchos/Tests/WatchSessionEngineTests/*` — Swift tests only (Phase 2)
- `docs/watch_session_sync.md`, `watch/sync_protocol/PROTOCOL.md`, `docs/modality_tracking.md` /
  `docs/modality_based_exercise_ui.md` (Phase 3)
- Readers only: `lib/data/repositories/workout_repository.dart`, `lib/data/models/models.dart`
  (`TimedInstance`, `RoundInstance`, `WatchInboxEntry`), `lib/core/utils/entry_rows.dart`,
  `lib/state/workout/timer_manager.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
  `test/watch_session_import_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`.

## Notes

**Dependency graph.** Phase 1 is the whole feature's usable half. Phase 2 depends on Phase 1 (there is
nothing for the wrist to show or delete before it) and on 17c's Phase 1 (`heldWristEntryIds`); Phase 3
depends on both. 17d can be planned and run after 17c lands; it does not need 17c's Phase 2/3 (the
durable lens is orthogonal), so running 17d's Phase 1 before 17c's Phases 2–3 is legitimate if the
budget forces a choice — with the known cost that a wrist relaunch would then resurrect a deleted
non-set entry.

**Predicted intermediate states.** After Phase 1 the phone sends `timed`/`hold`/`round` entries and
`_wristRowStamps` matches them, but `heldWristEntryIds` still filters to sets, so a deleted non-set
entry is not announced yet (S-144 is red). After Phase 2 both directions are covered. Phase 3 is docs
only.

**Baselines.** Record what this PR's first run prints; the brief quotes `flutter test` ≈4030/~1
skipped, `flutter analyze` 196/0 and `swift test` 325/0, while the 17b evidence quotes 4020 and 315 —
they disagree, so the evidence file is the authority, not any of these.

**Test traps.** Plain `test()` throughout; `testWidgets` hangs on a real `await` inside FakeAsync. The
Swift side is `swift-test` only — no simulator, no `xcodebuild` (D-138). A red Mock group can leave the
Hive group behind it hanging: fix the Mock group first.

**Known limits stated, not fixed.** (a) A phone entry that cannot be expressed is omitted (D-132).
(b) The wrist's own rest timer and sensor values never travel (D-137). (c) A skipped set and a set's
added weight stay off the wire by decision (D-135/D-136).

## Progress

- [ ] Phase 1 — the phone projects its other kinds
- [ ] Phase 2 — the wrist shows them; 17c's deletion covers them
- [ ] Phase 3 — docs, contract sentence, residue sweep

## Assumption Log

[empty — executors append decision / options / rationale here; the Conductor marks each RATIFIED or
REVERT]

## Feedback

[empty — fill this and re-invoke the planner when a D-x contradicts itself or the scope changes]

## Open questions

Each carries the default this plan proceeded on; the owner was unavailable and every default is
implementable and reversible.

1. **Should a set the user skipped on the phone appear on the watch?** Default: **no** — a skipped set
   is not a performed set (D-135). Overruling means a schema field, both validators, a fixture and a
   watch surface that renders skipped work; that is its own PR.
2. **Should a set's added weight reach the watch separately from its total load?** Default: **no** —
   the total load is what the watch row shows (D-136). Overruling is a schema field plus a wrist
   surface change.
3. **Should a phone `timed` entry that is still running appear on the watch, or only once it
   finishes?** Default: **only once it has a window** — a running instance with no `finishedAtMs`
   travels with `endedAt = now` only if the phone re-sends on every pass; this plan sends the entry only
   when it has a valid window (D-132), so the watch sees a timed entry when it ends, not while it runs.
   If the owner wants live mirroring of a running timer, that is a different decision (it needs a
   re-send cadence) and a separate PR.
4. **Should the phone's rest timer reach the watch?** Default: **no** — rest stays per-device (17a
   D-80, D-137). The owner asked explicitly that the rest timer not be carried.
