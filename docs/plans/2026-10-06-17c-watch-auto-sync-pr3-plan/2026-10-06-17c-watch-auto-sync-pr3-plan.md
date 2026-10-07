# Feature: watch auto-sync PR 3 — a deletion on the phone reaches the wrist

> Status: DRAFT awaiting implementer start (owner unavailable; defaults below bind, see Open questions)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` + `docs/watch_session_sync.md`,
> `docs/state_management/watch_surface.md`, `watch/sync_protocol/PROTOCOL.md`
> Series index: `docs/plans/2026-10-06-17-watch-auto-sync-index.md` (this plan is PR 3)
> Sibling plan (split out of the same owner request): `docs/plans/2026-10-07-17d-watch-auto-sync-pr4-plan/2026-10-07-17d-watch-auto-sync-pr4-plan.md`

## Overview

The owner goal for the 17-series is: **no Sync tap for any active-session action, in either
direction.** The 17a/17b PRs closed logging a set on the phone, editing it, and ending the session.
This PR closes the first of the three gaps the brief names, and only that one:

1. **A set deleted on the phone never leaves the phone.** Both engines and both validators already
   carry `structure_change` / `delete_entry`
   (`watch/sync_protocol/schemas/messages/structure_change.schema.json`,
   `lib/watch/session/watch_session_engine.dart:_applyDeletion`,
   `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:applyStructureChange`), and the
   phone's mirror can already *build* the frame
   (`lib/state/watch/live_session_mirror_state.dart:deleteEntry`, line 457) — but **nothing calls it
   during a session**: the push (`lib/state/watch/watch_session_auto_push.dart`) sends only a
   snapshot, and a snapshot cannot express an absence. So a set the user deleted on the phone keeps
   standing on the wrist until the wrist's own session is replaced (15-series D-38; the gap is
   documented as known in `docs/watch_session_sync.md:339`).
2. The phone's `timed` / `hold` / `round` entries are still not projected (15-series D-39). Out of
   scope here — planned as PR 4 (17d).
3. A skipped set and a set's added weight are not on the wire (15-series D-40). This is a **product
   default**, not a defect: it is stated plainly in D-117 and in the doc, and it stays out of scope
   as a behaviour change in both PRs.

**Scope measurement against `.github/copilot/pr-scope-budget.md`.** 17c and 17d together would be 6
phases, 2 tracks (`lib/` + `watch/watchos/` + `watch/sync_protocol/`), ~19 ledger decisions and ~15
scenarios — past the soft signals on phases, tracks and decisions. They are also two independent
user-visible outcomes (deletions travel vs. the other entry kinds travel). The split is therefore:
17c = deletions reaching the wrist; 17d = the phone's other entry kinds. 17c alone: **3 phases, 2
tracks, D-110…D-118, S-120…S-127** — inside the hard budget, and it ships a visible win at the end
of Phase 1.

## Resolved Decisions (Ledger)

Decisions are immutable once written; a change is a new superseding entry.

### D-110 — The sender is the push, and a delete is one `structure_change` frame with a changeId derived from the entry id

The phone announces a deletion from `WatchSessionAutoPush._pushOnce`
(`lib/state/watch/watch_session_auto_push.dart:100`), because that is the only component that runs on
every session change and the only one that knows what the wrist was last told (17b D-75: one seam).
The frame is the existing shape, unchanged:

```json
{"kind": "delete_entry", "entryId": "entry-<slotId>-<n>"}
```

inside one `structure_change` message with `changeId: 'del-<entryId>'`.

- **The changeId is derived, not minted.** `LiveSessionMirrorState.deleteEntry` (line 457) mints a
  fresh `_newId()` per call, which makes a re-assertion of the same deletion look like a new change.
  The push needs a stable id: `'del-' + entryId` is unique (the entry id already names its slot, and
  the slot id is a UUID) and stable across passes. Phase 1 adds a sibling
  `LiveSessionMirrorState.deleteEntryAs(String entryId, {required String changeId})` next to
  `deleteEntry`, which applies the change locally exactly as `deleteEntry` does and sends it with the
  given changeId. `deleteEntry` keeps its behaviour (its tests stay green) and both funnel into
  `applyStructureChange` (line 350).
- **Local first, wire second.** The frame is applied to the mirror's own state before it is sent, so
  the phone's converged view and the wrist's agree (`_sendOwn`'s existing order).
- **Rejected:** a new frame type (the schema already expresses a deletion, and a new type means two
  validators, a schema file and fixtures); **rejected:** carrying the deletion interval inside the
  snapshot (a snapshot cannot express an absence without a tombstone list, which is a bigger contract
  change than a frame the wrist already understands).

### D-111 — The push keeps a per-session held-id ledger, and each pass announces exactly the ids that vanished since the last pass

`WatchSessionAutoPush` gains one field per session:

- `_announced[sessionId]` — the set of entry ids the wrist was expected to hold at the end of the
  last pass for that session.

`_pushOnce()` becomes: compose the payload → `_remember(composedId)` → **`_announceDeletions(composedId,
composed)`** → baseline compare → send the snapshot. Per pass:

1. `held = payload entry ids ∪ heldWristEntryIds(composedId)` (D-112).
2. `vanished = _announced[composedId] − held`, announced one frame per id, **ascending entry id
   order** (deterministic, so a test can assert the order).
3. `_announced[composedId] = held`.

Rules that make this safe:

- **The first pass seeds silently.** With no `_announced` entry for the session, nothing is announced;
  `held` becomes the seed. (Without the seed, the first pass would "vanish" every id the wrist holds
  for another reason and delete the user's work.)
- **Announce before the snapshot of the same pass.** A delete followed by re-creating an entry under
  a reused id in the same pass must end with the entry visible (D-113); reversing the order would
  hide the re-created entry.
- **The ledger is dropped when the composed session id changes**, so a session the phone switched
  away from and back to re-seeds instead of comparing against another session's ids (D-114).
- **Memory-only, and that is stated.** A phone relaunch mid-session re-seeds the ledger from the
  current state, so a deletion made before the relaunch and not yet announced is lost — the same
  class as 17a D-83 ("dropped, never queued"); the 250 ms `_debounce` bounds the window. The wrist
  side is durable (D-113), which is what makes this acceptable: once announced, a deletion survives
  *both* devices' relaunches.

### D-112 — "The wrist is expected to hold" has exactly two producers, and the bridge answers them in one call

The known-wrist ids come from `WatchSessionAdoptionBridge` (Phase 1): the ids on the session's
`WatchInboxEntry` rows whose stamp still claims a group on their slot — i.e. the entries the wrist
itself logged and the phone still holds.

- `heldWristEntryIds(String sessionId)` returns the `entryId` of every live inbox row
  (`origin == WatchInboxEntry.originWatch`, `kind == WatchInboxEntry.kindSet`) for the session whose
  stamp still claims a group on its slot. The claim test is the **existing** one
  (`_wristRowStamps` at `watch_session_adoption_bridge.dart:271` + `PhoneEntries.claimedBy` in
  `lib/core/sync_protocol/phone_entries.dart`), reused rather than re-implemented: a row whose group
  the user deleted stops claiming, which is exactly TRAP 1's case.
- Why the bridge: it is the only place that already owns the claim rule and the inbox read behind the
  repository interface; the push takes it as an **injected seam** (like its existing `getSession`,
  passed by `createWatchSync` in `lib/state/watch/watch_sync_wiring.dart:~220`), so `lib/state/` keeps
  reading the interface and never a concrete store.
- **Scope note (17d boundary).** 17c covers `kindSet` rows only: a non-set entry has no wire entry to
  delete until 17d projects those kinds, so the phone cannot name one here. A deletion of a wrist
  `timed` entry on the phone therefore still does not reach the wrist in 17c — stated in the doc
  (Phase 3) as a known limit, and carried by 17d D-137.
- The phone's own ids are the ones the payload carries; the push reads them from the composed payload
  rather than re-deriving them, so the two can never disagree.

### D-113 — The wrist's deletion lens becomes durable, a snapshot clears it for the ids it carries, and a re-stated id with a new stamp replaces the held entry

Three rules, all in `_storeSnapshotEntry` / `applyStructureChange` / `restore` of both engines.

1. **Durability (TRAP 2).** The lens is written on the row a structure change already appends:
   `WatchSessionRecord` gains `deletedEntryIds` (default `const []`); `_applyStructureChange`
   (`watch_session_engine.dart:515`, `WatchSessionEngine.swift:applyStructureChange`) writes the
   union of the previous row's list and the change's deletions; `restore()`
   (`watch_session_engine.dart:113–145`, `WatchSessionEngine.swift:58–61`) seeds `_deletedEntryIds`
   from the newest session row it already picks by `sequence`. Without this a wrist relaunch brings
   the deleted set back, and the phone cannot re-announce it — the phone's owed set is memory-only
   (D-111), and the durable `appliedChangeIds` would swallow a repeat of the same changeId. **A
   tombstone that cannot be rebuilt from `restore()` is not a tombstone**, so re-assertion is not an
   alternative to this rule.
2. **A snapshot naming an id clears that id's tombstone (TRAP 4).** The phone is the structure
   authority (PROTOCOL authority rule 2), so an entry its snapshot carries exists. This is what makes
   a delete-then-re-create converge instead of leaving the entry invisible.
3. **A snapshot entry whose `loggedAt` differs from the held one replaces it; the same `loggedAt`
   still merges field-by-field (TRAP 4).** The phone reuses entry numbers
   (`EntryRows.numberForNewRow`, `lib/core/utils/entry_rows.dart:145`, is highest existing + 1), so
   deleting the newest set of a slot and logging another mints the *same* id for a *different* entry.
   A field merge would keep any key the new entry does not carry (a deleted set's `loadKg` showing on
   the new set), so: differing `loggedAt` → the correction **is** the whole entry; equal `loggedAt` →
   the existing merge (17b D-35, unchanged). The projection already sorts on the folded
   `payload['loggedAt']` (`_byLoggedAtThenEntryId`, `watch_session_engine.dart:1001`), so the
   re-created entry also lands in the right order.
   - **Rejected:** making the minted wire id carry the stamp — correct in principle, but it churns
     every id assertion in `test/watch_session_projection_test.dart` (~40),
     `test/watch_session_auto_push_test.dart` (~11), the cross-stack tests and four fixtures, and
     both stacks, for a case these two receiver rules close.
   - **Rejected:** adding `loggedAt` to `delete_entry` — a schema change, two validators and a fixture
     for a rule the snapshot already answers.

### D-114 — A deletion is scoped to the session both devices hold; no new scoping rule

The delete frame names the session the mirror holds, and the wrist's session guard (17a D-79,
`_guardSession` / `guardSession`) already refuses any frame naming another session — so a delete for a
session the wrist does not hold changes nothing. The phone's ledger is keyed by the composed session
id (D-111) and the ids inside it are slot-scoped UUIDs, so a stale ledger can never name the held
session's entries. The three ids in play are the ones 17b D-103 already lists: the mirror's `state`
session id, the phone's own session id, the wrist's own — plus the ledger, which is dropped when the
composed id changes.

### D-115 — The receiver hides an entry; it never rewrites its row

Unchanged from 15-series D-38: `_applyDeletion` removes the id's correction and adds the id to the
lens; the observation row stays (the store is append-only) and the projection filters on the lens.
No row rewriting, no store API change. The phone keeps the id out of every later snapshot, so nothing
re-adds it — and if a snapshot ever does carry it, rule D-113.2 applies.

### D-116 — Re-delivery is a no-op on both sides

`changeId = 'del-<entryId>'` means: a re-delivered frame is dropped by the durable
`appliedChangeIds`, and the row it wrote (`chg-del-<entryId>`) has the same record id, so the store's
duplicate-recordId no-op applies (PROTOCOL authority rule 6). This is what lets the phone re-announce
without inventing a new id.

### D-117 — A skipped set and a set's added weight stay off the wire (owner default, stated plainly)

This is decision 3 from the brief, and it is a **product** choice, so it is stated in the doc rather
than changed in code:

- **A skipped set is not a performed set.** PROTOCOL's `$defs.entry` has no `skipped` field
  (`additionalProperties: false` on the set shape), and the set the user skipped has no window, no
  reps they did and no load they moved. Sending it would show the wrist work that never happened and
  invite a second attempt at it. **Default: keep omitting it**, and say so in
  `docs/watch_session_sync.md` in plain words ("a set you skip on the phone is not sent to the
  watch").
- **A set's added weight stays omitted.** `extraLoadKg` is documented as a **hold's** added load on
  the wire, and the receiver's mapping reads it for a drill (`WatchLoggingState.swift`'s
  `windowPayload`/hold path). A set's extra load is already reported to the wrist as the set's total
  `loadKg`. **Default: keep omitting `extraLoadKg` for sets.**
- Cost if the owner overrules: a schema property, both validators, a fixture, a wrist surface that
  renders a skipped set, and a second decision about what a wrist-applied skipped set means. That is
  a PR of its own, not a clause of this one.
- The behaviour is already what the code does (`phone_entries.dart`'s `project` omits `reps < 1` and
  never writes `extraLoadKg`), so 17c changes **no code** for it — only the doc sentence, which lands
  in Phase 3.

### D-118 — The contract amendment is additive and dated; the docs are updated in the phase that ships the tested behaviour

`watch/sync_protocol/PROTOCOL.md` gains one dated paragraph (Phase 3): a phone may delete an entry on
the wrist by sending `structure_change` / `delete_entry` naming the entry's own id; a snapshot that
carries an entry clears any deletion the receiver holds for it; a snapshot entry whose `loggedAt`
differs from the held one replaces it rather than merging into it. The protocol is unreleased
(`v1`), so no version bump. Behaviour prose lands in `docs/watch_session_sync.md` (the
"A delete does not reach the wrist" bullet at line 339 is replaced by the rule, naming its tests) and
`docs/state_management/watch_surface.md` — in Phase 3, because the statement covers both engines and
is only true once the Swift twin lands. No doc file may pass the 52 KB band
(`test/docs_indexing_contract_test.dart`; both files are well under it today — the implementer
records the size it found in the evidence file).

## Feature Invariants

Only the invariants that bite in this feature. Project-wide rules live in
`docs/global_conventions.md` and are referenced, not copied.

- **I-1 Parity.** `HiveWorkoutRepository` and `MockWorkoutRepository` produce the same observable
  output for the same inputs; likewise the Dart engine (`lib/watch/session/watch_session_engine.dart`)
  and its Swift twin (`WatchSessionEngine.swift`) must hide the same entries for the same frames. The
  same delete driven through either engine must leave both `entries` lists equal.
- **I-2 Layer boundary.** `lib/state/` reads `WorkoutRepository`; no file under `lib/state/`,
  `lib/features/`, `lib/widgets/` or `lib/core/` may import a concrete store
  (`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns
  nothing). The bridge seam in D-112 exists to keep this true.
- **I-3 Append-only store.** A deletion never rewrites or removes an observation row; it is a lens
  over the projection (D-115). Any implementation that deletes a row is wrong, even if the surface
  looks right.
- **I-4 No invented data.** A frame the phone sends is derived from stored state only. A deletion is
  announced only for an id the phone previously told the wrist about (D-111's seed) — never inferred
  from a difference the phone has not observed.
- **I-5 Session scoping.** No rule may apply a change to a session other than the one the frame
  names (D-114 / 17a D-79).

## Requirements

- **R-1** Deleting a set on the phone during an active session removes it from the wrist's entry list
  without a Sync tap, within the push's normal debounce (250 ms) plus one frame.
- **R-2** A delayed or duplicated frame changes nothing on the wrist twice.
- **R-3** A deletion survives a wrist relaunch and a phone relaunch, as long as the phone held the
  session when it was deleted.
- **R-4** Deleting a set copies no entry of another session to the wrist, and does not delete another
  session's entries.
- **R-5** An entry the wrist itself logged, imported by the phone and then deleted on the phone,
  disappears on the wrist too.
- **R-6** No new sync surface: the deletion is an active-session action, so there is no Sync tap,
  no new button and no new screen.

## Acceptance Criteria

| AC | Statement | Scenarios |
|---|---|---|
| AC-1 | A set logged on the phone and deleted on the phone disappears on the wrist, and the frame that carries it is `structure_change` with one `delete_entry` naming the entry id and `changeId: 'del-<entryId>'`. | S-120 |
| AC-2 | Two deletions in one pass arrive as two frames in ascending entry-id order; a set logged and deleted inside one debounce window announces nothing. | S-121 |
| AC-3 | An entry the wrist logged, the phone imported and the user then deleted is announced and disappears (TRAP 1). | S-122 |
| AC-4 | The first pass after a binding/relaunch announces nothing, and the ledger seeds from the held set. | S-123 |
| AC-5 | A deletion survives a wrist relaunch: `restore()` rebuilds the lens and the entry is still hidden (TRAP 2). | S-124 |
| AC-6 | Delete a set, log a new one in the same slot (same minted id): the wrist shows the new set's own values, in `loggedAt` order, and not the deleted set's fields (TRAP 4). | S-125 |
| AC-7 | A delete naming another session changes nothing; a delete delivered twice changes nothing the second time. | S-126 |
| AC-8 | The doc statements — the delete rule, the durable lens and D-117's plain statement — each name an existing test, and no `docs/` file passes 64 KiB. | S-127 |

## Existing-Functionality Impact

Every row carries the read that proves it. An "unaffected" row must carry its grep.

| Touched surface | What already reads it (the read) | Effect of the change | Guarded by |
|---|---|---|---|
| `LiveSessionMirrorState.deleteEntry` (line 457) | `grep -n "deleteEntry" lib/state/watch test` → `phone_manage_bridge_test.dart:495,646,683`, `watch_session_import_test.dart:919`; no writer during a session (that is the defect) | A new sibling method takes the changeId; `deleteEntry` keeps minting its own. Both apply locally the same way | S-120, S-126 · regression: the three existing tests stay green |
| `WatchSessionAutoPush._pushOnce` | `grep -n "_pushOnce\|flush(" lib/state/watch test` — the only send path; `watch_session_auto_push_test.dart` asserts the payload and the send count | One delete frame per vanished id, before the snapshot; the payload is unchanged, so existing payload assertions stay green — but a test that counts frames per flush must be updated once | S-120, S-121 |
| `WatchSessionAdoptionBridge.projectSession` + `_wristRowStamps` | `grep -n "_wristRowStamps\|claimedBy" lib test` — the import/projection claim rule; `watch_session_projection_test.dart` S-35 case | A second public method reuses the same read; `projectSession` itself is untouched | S-122, S-123 |
| `WatchSessionRecord` (Dart) and `WatchSessionRecord` (Swift) | `grep -n "WatchSessionRecord(" lib watch/watchos` — the store's row; every existing row deserializes | One additive field with a default; an old row reads back as `[]` | S-124 |
| `_storeSnapshotEntry` / `storeSnapshotEntry` | `grep -n "_storeSnapshotEntry" lib` — every snapshot entry lands here; `test/watch_session_engine_test.dart` | Two new branches (clear the tombstone; replace when `loggedAt` differs). The merge branch is unchanged | S-125 · regression: existing re-statement/correction tests stay green |
| `docs/watch_session_sync.md:339` ("A delete does not reach the wrist", naming the S-35 test) | the doc bullet itself; the S-35 test at `test/watch_session_projection_test.dart:1158` asserts the *absence* of a delete frame | The bullet becomes the rule; the test's assertion flips (it is the red test for Phase 1) | S-120, S-127 |
| `docs/watch_session_sync.md:415–419` (the memory-only correction lens, "nothing is ever deleted from it") | the doc text; the store is append-only | One sentence is added: the *deletion lens* is persisted on the session row; the claim that no observation row is ever deleted stays true (I-3) | S-124, S-127 |
| `docs/state_management/watch_surface.md` | the state inventory for the watch surface | Two sentences: the push announces deletions; the ledger is memory-only while the lens is durable | S-127 |
| `PROTOCOL.md` | the contract; validated by `test/sync_protocol_fixtures_test.dart` and `SyncProtocolValidator.swift` | One additive dated paragraph; **no schema, validator or fixture change** (D-110/D-118) | S-127 |
| `EntryRows.numberForNewRow` (`lib/core/utils/entry_rows.dart:145`) | `grep -n "numberForNewRow" lib test` — the id mint | Not touched; it is the reason D-113.3 exists, and the plan says so | S-125 |
| Phone's `timed`/`hold`/`round` entries | `phone_entries.dart:project` filters to `set` (D-39) | **Not touched by 17c** — that is 17d; the known limit is documented | 17d D-130…D-138 |
| Per-device rest timers | `docs/watch_session_sync.md` (17a D-80) | **Untouched by 17c and by 17d**; no frame carries a timer | not applicable (no code change) |

## Scenarios

### S-120: A set deleted on the phone disappears on the wrist

- **Fixture:** one session with one exercise "Bench" (an effort with reps/sets/load capabilities) and
  two logged sets, `entry-bench-1` (60 kg × 5, `loggedAt` 1000) and `entry-bench-2` (60 kg × 5,
  `loggedAt` 2000); a Mock-backed push bound to that session, having completed one pass so the ledger
  has seeded both ids; a wrist engine (Dart twin) holding both from the previous snapshot.
- **Trigger:** delete set 2 on the phone (`LiveSessionMirrorState.deleteEntryAs('entry-bench-2',
  changeId: 'del-entry-bench-2')` via the push's next pass; the UI path is `deleteEntry` on the
  session core).
- **Flow:** the push composes → `held` = `{entry-bench-1}` → `vanished` = `{entry-bench-2}` → one
  frame → the snapshot (one entry).
- **Expected outcome:** exactly one `structure_change` frame, `changes == [{'kind': 'delete_entry',
  'entryId': 'entry-bench-2'}]`, `changeId == 'del-entry-bench-2'`; the wrist's `entries` no longer
  contains `entry-bench-2`, still contains `entry-bench-1`, and the wrist's observation store still
  has the row (I-3).
- **Edge case of:** none.

### S-121: Several deletions, and a deletion that never was

- **Fixture:** four sets on one slot — `entry-b-1` (1000), `entry-b-2` (2000), `entry-b-3` (3000),
  `entry-b-4` (4000) — after one pass that sent all four; a second copy: a set logged at t and deleted
  at t + 100 ms (inside the 250 ms debounce).
- **Trigger:** delete `entry-b-2` and `entry-b-4` before the next pass; separately flush once after
  the log+delete pair.
- **Flow:** `held` = `{entry-b-1, entry-b-3}` → `vanished` = `{entry-b-2, entry-b-4}` → frames in the
  order b-2, b-4.
- **Expected outcome:** two frames, ascending id order, one delete each; one snapshot carrying the two
  survivors; the world where the log+delete pair never left the phone sends **no** delete frame (the
  id was never announced, so it cannot vanish) and its snapshot has the set the phone kept.
- **Edge case of:** S-120.

### S-122: An entry the wrist logged, imported and then deleted on the phone (TRAP 1)

- **Fixture:** the wrist logged a set on slot "Bench" and stamped it; the phone imported it, so the
  session has a `WatchInboxEntry` row (`origin == 'watch'`, `entryId == 'entry-bench-1'`) and a group
  whose stamp equals the row's `loggedAtMs`; the phone also logged one set of its own, `entry-bench-2`.
  One pass has run (both ids in the ledger). The projection sends only its own set (the wrist's entry
  is the wrist's own row — D-34).
- **Trigger:** the user deletes the imported set on the phone (the slot's group is removed).
- **Flow:** the next pass composes one entry → `heldWristEntryIds` no longer returns `entry-bench-1`
  (its stamp claims nothing) → `vanished` = `{entry-bench-1}`.
- **Expected outcome:** one delete frame naming `entry-bench-1` — the **wrist's** id, not a phone-minted
  one; the wrist hides its own entry; the phone's group stays deleted.
- **Edge case of:** S-120.

### S-123: The first pass announces nothing (negative guard)

- **Fixture:** a fresh push bound to a session that already holds three entries the wrist has held
  since before the push existed (the wrist re-launched, so the phone re-binds).
- **Trigger:** the first pass.
- **Flow:** `_announced` has no entry → seed only.
- **Expected outcome:** zero delete frames; the snapshot is unchanged from the base behaviour. This
  scenario is green before the change as well — it is the guard that the fix does not ship the
  "delete everything the wrist holds" defect. Mutation that must turn it red: seed from an empty set
  instead of from `held`.
- **Edge case of:** S-120.

### S-124: A deletion survives a wrist relaunch (TRAP 2)

- **Fixture:** a Dart-twin engine (and a Swift-twin engine) that has applied one snapshot with two
  entries, then a `structure_change` deleting the first, then `restore()` on a **new engine instance
  over the same store** (the re-launch).
- **Trigger:** read `entries` after the restart.
- **Flow:** `restore()` reads the newest session row (the one the change appended) and rebuilds the
  lens from it.
- **Expected outcome:** the deleted entry is still absent and the survivor is still present, in both
  twins. Red without the change because today the lens is a field initialised in the constructor and
  is never read back, so the deleted entry reappears.
- **Edge case of:** S-120.

### S-125: A re-created set under a reused number is not swallowed (TRAP 4)

- **Fixture:** one slot holding `entry-bench-1` (60 kg × 5, `loggedAt` 1000) and `entry-bench-2`
  (60 kg × 5 with a load, `loggedAt` 2000), both applied by the wrist; then the phone deletes
  `entry-bench-2` and logs a new set, which `EntryRows.numberForNewRow` mints as `entry-bench-2`
  again — this time with no load and no reps (a bodyweight set) and `loggedAt` 5000.
- **Trigger:** one pass: delete frame for `entry-bench-2`, then a snapshot carrying the new
  `entry-bench-2`.
- **Flow:** the tombstone is cleared for the id the snapshot carries (D-113.2) and, because the
  `loggedAt` differs, the entry replaces the held one (D-113.3).
- **Expected outcome:** the wrist shows two entries; the new one carries exactly the phone's fields —
  no `loadKg` inherited from the deleted set — and sorts after `entry-bench-1` by `loggedAt`. Red
  without the change because today the merge keeps the held payload's keys and the tombstone wins.
- **Edge case of:** S-120.

### S-126: Another session's deletion, and a repeated frame (TRAP 3)

- **Fixture:** a wrist engine holding session A's two entries; the phone's mirror holding session B.
- **Trigger:** a `structure_change` deleting an entry id that does not exist in session A, then the
  same frame twice.
- **Flow:** the session guard refuses the first; `appliedChangeIds` refuses the second.
- **Expected outcome:** session A's `entries` is unchanged after both; no crash, no row appended for a
  foreign session. Red without the change? **No — green at the base**: it is the guard that the new
  sender must not break (17a D-79 plus D-116's dedupe), and it must stay green through all three
  phases.
- **Edge case of:** S-120.

### S-127: The docs and the contract say what the code does

- **Fixture:** the repo after Phase 3.
- **Trigger:** read `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md` and
  `watch/sync_protocol/PROTOCOL.md`.
- **Flow:** each behaviour sentence names a real test; the delete bullet no longer claims a delete
  cannot reach the wrist; D-117's plain statement is present; the PROTOCOL amendment is dated.
- **Expected outcome:** the named tests exist and are green; no `docs/` file passes 64 KiB. Verified
  by the reviewer (a doc statement without a test is a finding), not by a new test.
- **Edge case of:** none.

## Iteration 1

### Phase 1: The phone announces its deletions (@developer)

1. [ ] Add `heldWristEntryIds(String sessionId)` to `WatchSessionAdoptionBridge`
   (`lib/state/watch/watch_session_adoption_bridge.dart`): read the session's inbox rows via
   `_repository.getWatchInboxEntriesForSession`, keep `origin == WatchInboxEntry.originWatch` **and**
   `kind == WatchInboxEntry.kindSet`, group by `sessionExerciseId`, read each slot's groups via
   `EntryRows.setGroups(await _repository.getEffortObservations(effortId))` and return the `entryId`
   of every row whose stamp still claims a group (`PhoneEntries.claimedBy`). Doc comment cites D-112
   and the 17d boundary. · `WatchSessionAdoptionBridge:heldWristEntryIds`
2. [ ] Add `deleteEntryAs(String entryId, {required String changeId})` beside
   `LiveSessionMirrorState.deleteEntry` (`lib/state/watch/live_session_mirror_state.dart:457`): build
   the same `structure_change` envelope with the given `changeId`, apply it locally (the same call
   `deleteEntry` makes) and send it. `deleteEntry` keeps minting its own id. · `LiveSessionMirrorState:deleteEntryAs`
3. [ ] Add the ledger and the diff to `WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`):
   a `Map<String, Set<String>> _announced` field; in `_pushOnce` compose → `_remember` →
   `await _announceDeletions(composedId, composed)` → baseline compare → `_mirror.sendState`. ·
   `WatchSessionAutoPush:_pushOnce`, `WatchSessionAutoPush:_announced`
4. [ ] Implement `_announceDeletions(String sessionId, Map<String, Object?> composed)` in the same
   file: `held = payload entry ids ∪ await _heldWristEntryIds!(sessionId)`; if `_announced` has no
   entry for the session, store `held` and return; otherwise send one
   `deleteEntryAs(id, changeId: 'del-$id')` per id in `_announced[sessionId] − held`, ascending, then
   store `held`. Drop the entry for any other session id (D-111). ·
   `WatchSessionAutoPush:_announceDeletions`
5. [ ] Add the `heldWristEntryIds` seam to the constructor and its call site:
   `WatchSessionAutoPush(...)` takes `Future<Set<String>> Function(String sessionId) heldWristEntryIds`
   and `createWatchSync` (`lib/state/watch/watch_sync_wiring.dart:~220`) passes
   `adoption.heldWristEntryIds`. · `WatchSessionAutoPush`, `createWatchSync`
6. [ ] Flip the S-35 case in `test/watch_session_projection_test.dart` (the "an edit reaches the wrist
   and a delete is not sent" test, ~line 1158) to assert the delete frame **is** sent, with
   `changeId == 'del-entry-…'` and the entry id from the fixture. · `test/watch_session_projection_test.dart`
7. [ ] Add S-120, S-121, S-122, S-123 and S-126's first half to
   `test/watch_session_auto_push_test.dart` as plain `test()` cases (Mock-first; no `testWidgets`, no
   real delay). · `test/watch_session_auto_push_test.dart`
8. [ ] Record the phase's baseline counts and the red→green table in
   `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md`
   under "Phase 1", and append Progress + any Assumption Log entries to this plan. ·
   `2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart test/phone_manage_bridge_test.dart test/watch_session_import_test.dart`;
a `prove-red` demonstration on the S-120 case (S-120 must fail with the push's delete call reverted);
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns
nothing (I-2). The full `flutter test` suite runs at the end of Phase 3.

**Predicted Files**: `lib/state/watch/watch_session_auto_push.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`,
`lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_sync_wiring.dart`,
`test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart`,
`test/watch_session_adoption_bridge_test.dart`, this plan, its
evidence file. Nothing else.

### Phase 2: The Dart twin keeps the deletion, and a snapshot answers for the ids it carries (@developer)

1. [ ] Add `deletedEntryIds` (a `List<String>`/`Set<String>` with a `const []` default) to
   `WatchSessionRecord` in `lib/watch/session/watch_records.dart`, carried through its `copyWith`,
   `toMap` and `fromMap` like the other fields. · `WatchSessionRecord`
2. [ ] Make `_applyStructureChange` (`lib/watch/session/watch_session_engine.dart:515`) write the union
   of the previous row's `deletedEntryIds` and the change's `delete_entry` ids onto the session row it
   appends, and keep `_deletedEntryIds` in memory in step. · `WatchSessionEngine:_applyStructureChange`
3. [ ] Make `restore()` (`lib/watch/session/watch_session_engine.dart:113`) seed `_deletedEntryIds`
   from the newest session row it already selects — the durable half of TRAP 2. · `WatchSessionEngine:restore`
4. [ ] In `_storeSnapshotEntry` (`lib/watch/session/watch_session_engine.dart:753`): clear
   `_deletedEntryIds` for the `entryId` the snapshot carries (D-113.2) and, when the incoming
   `loggedAt` differs from the held entry's `payload['loggedAt']`, record the entry as a **whole
   replacement** instead of the field merge; the `entries` getter (`:209`) must fold the two
   differently. · `WatchSessionEngine:_storeSnapshotEntry`, `WatchSessionEngine:entries`
5. [ ] Add S-124, S-125 and S-126's second half to `test/watch_session_engine_test.dart` as plain
   `test()` cases (a restart over the same store; a reused id; a foreign-session delete). ·
   `test/watch_session_engine_test.dart`
6. [ ] Run the existing delete/late-entry suites as regression guards and record the counts
   (`test/watch_session_edit_restore_late_entry_test.dart`,
   `test/watch_session_engine_test.dart`), plus Progress/Assumption Log back to this plan. ·
   `2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_edit_restore_late_entry_test.dart test/watch_session_import_test.dart`;
a `prove-red` demonstration on S-124 (the test must fail with the `restore()` seeding reverted) and on
S-125 (fail with the replacement branch reverted).

**Predicted Files**: `lib/watch/session/watch_records.dart`,
`lib/watch/session/watch_session_engine.dart`, `test/watch_session_engine_test.dart`, this plan, its
evidence file — **and, if the store's `toMap`/`fromMap` for the record lives beside it,
`lib/watch/session/watch_session_store.dart` / `in_memory_watch_session_store.dart` /
`hive_watch_session_store.dart` only to round-trip the new field**. The bridge's own doc sentence lands
in Phase 3.

**Interphase note.** Phase 2 is Dart-only on purpose: the doc sentence about the durable lens covers
both engines, so it lands with the Swift twin in Phase 3 (17b shipped a phase this way for the same
reason).

### Phase 3: The Swift twin, the contract and the docs (@developer)

1. [x] Add `deletedEntryIds` to `WatchSessionRecord`
   (`watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`), defaulted, carried through its
   `Codable`/map round trip and the file store
   (`watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift`). ·
   `WatchSessionRecord`, `FileWatchSessionStore`
2. [x] Mirror Phase 2's three rules in `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`:
   `applyStructureChange` writes the union onto the appended session row; `restore()` seeds
   `deletedEntryIds` from the newest row; `storeSnapshotEntry` clears the tombstone for a carried id
   and replaces (rather than merges) when `loggedAt` differs. ·
   `WatchSessionEngine:applyStructureChange`, `WatchSessionEngine:restore`,
   `WatchSessionEngine:storeSnapshotEntry`
3. [x] Add the Swift halves of S-124, S-125 and S-126 to
   `watch/watchos/Tests/WatchSessionEngineTests/` (the engine suite and the file-store suite): a
   restart over the same store keeps the deletion, a reused id shows the new entry's own fields, and a
   foreign session's delete is refused. · `WatchSessionEngineTests`, `WatchFileStoreTests`
4. [x] Add one dated paragraph to `watch/sync_protocol/PROTOCOL.md` (D-118): the phone may delete an
   entry by `delete_entry` naming the entry's own id; a snapshot clears a deletion for any entry it
   carries; a snapshot entry whose `loggedAt` differs replaces the held one. · `watch/sync_protocol/PROTOCOL.md`
5. [x] Rewrite `docs/watch_session_sync.md`'s "A delete does not reach the wrist" bullet (line 339)
   as the rule, naming the tests of S-120/S-124/S-125; add the one sentence that the **deletion lens**
   is persisted on the session row (keeping the "no observation row is ever deleted" sentence true);
   add D-117's plain statements ("a set you skip on the phone is not sent to the watch"; "a set's
   added weight is reported as the set's total, not separately"). Record the file's size. ·
   `docs/watch_session_sync.md`
6. [x] Add the two sentences of D-118 to `docs/state_management/watch_surface.md` (the push announces
   deletions; the ledger is memory-only while the lens is durable), add S-127's doc conformance note
   to `test/docs_indexing_contract_test.dart`'s area if that test enumerates doc claims (read it
   first), and write Progress + the evidence table for this phase. ·
   `docs/state_management/watch_surface.md`, the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh swift-test`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/docs_indexing_contract_test.dart`;
then the **full** `.github/copilot/scripts/macos/gateway.sh test` (900 s — compare the count against the
baseline in the evidence file; do not assume it).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
`watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/*`, `watch/sync_protocol/PROTOCOL.md`,
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, this plan, its evidence file.

## Files Affected

- `lib/state/watch/watch_session_auto_push.dart` — the ledger, the diff, the seam (Phase 1; whole feature)
- `lib/state/watch/watch_session_adoption_bridge.dart` — `heldWristEntryIds` (Phase 1)
- `lib/state/watch/live_session_mirror_state.dart` — `deleteEntryAs` (Phase 1)
- `lib/state/watch/watch_sync_wiring.dart` — the seam's wiring (Phase 1)
- `lib/watch/session/watch_records.dart` — `deletedEntryIds` (Phase 2)
- `lib/watch/session/watch_session_engine.dart` — write/restore/clear/replace (Phase 2)
- `lib/watch/session/watch_session_store.dart`, `in_memory_watch_session_store.dart`,
  `hive_watch_session_store.dart` — only if the record's map round trip lives there (Phase 2)
- `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift` (Phase 3)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (Phase 3)
- `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` (Phase 3)
- `watch/sync_protocol/PROTOCOL.md` (Phase 3)
- `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md` (Phase 3)
- Tests (as listed per phase). Readers only: `test/phone_manage_bridge_test.dart`,
  `test/watch_session_import_test.dart`, `test/watch_session_edit_restore_late_entry_test.dart`,
  `test/docs_indexing_contract_test.dart`, `lib/core/utils/entry_rows.dart`,
  `lib/core/sync_protocol/phone_entries.dart`.

## Notes

**Dependency graph.** Phase 1 is independent and visibly useful on its own: the wrist's receiver
already applies `delete_entry` (15-series D-38), so after Phase 1 a phone deletion reaches the wrist
as long as the wrist stays running. Phases 2 and 3 are the robustness half — a wrist relaunch would
otherwise resurrect the deleted set (Phase 2/3) and a re-created id would be swallowed (Phase 2/3).
Thus: "Phase 1 → Phase 2 → Phase 3" is the safe order; running Phase 1 alone ships a real win, and it
is legitimate to stop after Phase 1 and plan the rest later if the run budget bites.

**Predicted intermediate states.** After Phase 1, the S-35 projection test asserts a delete frame and
the durable lens does not exist yet — the wrist hides the entry in memory only. After Phase 2, the
Dart twin survives a restart while the Swift twin still does not, so a Swift-side restart test does
not exist yet (do not add it before Phase 3). After Phase 3, the two twins agree value-for-value
(I-1).

**Baselines and counts.** Use the numbers the run itself produces; the counts quoted in the brief for
the base are `flutter test` ≈4030 passed / ~1 skipped, `flutter analyze` 196 issues / 0 errors, and
`swift test` 325/0 — the 17b evidence quotes `flutter test` 4020 and `swift test` 315, so the two
sources disagree and the honest move is to record what the first run of this PR prints in the evidence
file and compare against that. Do not treat any of these as a promise.

**Test traps (from AGENTS.md).** `testWidgets` runs in FakeAsync: a real `await Future.delayed` or a
Hive write inside it hangs forever. All of 17c's new cases are plain `test()`; the push's debounce is
driven by an injected clock/timer in `watch_session_auto_push_test.dart`'s existing harness — reuse
it, do not `pump` a real duration. A red Mock group can leave the file's Hive group hanging behind
it: fix the Mock group first.

**Known limits stated, not fixed.** (a) A deletion the phone has not yet announced is lost if the
phone dies inside the 250 ms debounce window (D-111). (b) A wrist `timed`/`hold`/`round` entry deleted
on the phone still does not reach the wrist — 17d's boundary (D-112). (c) A deletion on the wrist is
never sent to the phone (the wrist has no delete sender, and no rule here adds one).

## Progress

- [x] Phase 1 — the phone announces its deletions — **Complete** (developer, 2026-10-07; base
  `8d00fab`)
  - [x] 1 `WatchSessionAdoptionBridge:heldWristEntryIds` — `kindSet` rows whose stamp still claims a group
  - [x] 2 `LiveSessionMirrorState:deleteEntryAs` + `applyStructureChange(..., {changeId})`
  - [x] 3 `WatchSessionAutoPush:_announced`, `_pushOnce`: compose → remember → announce end → announce deletions → baseline → send
  - [x] 4 `WatchSessionAutoPush:_announceDeletions` — `previous − held`, ascending, `del-$id`
  - [x] 5 optional `heldWristEntryIds` seam, wired in `createWatchSync`
  - [x] 6 S-35 flipped in `test/watch_session_projection_test.dart`
  - [x] 7 S-120, S-121 (×2), S-122, S-123, S-126 (first half) added; `watch_session_auto_push_test.dart` 31 passed / 0 failed
  - [x] 8 evidence + Progress — counts, prove-red verdicts and the mutation table in the evidence file
- [x] Phase 2 — the Dart twin keeps the deletion; a snapshot clears and replaces — **Complete**
  (developer, 2026-10-07; base `0413112`)
  - [x] 1 `WatchSessionRecord.deletedEntryIds`, defaulted, carried through `withSequence`/`withDeletedEntryIds`/JSON
  - [x] 2 the union is written in `_appendSessionRow` (every session row, not the structure-change row only — see the Assumption Log); `_applyDeletion` keeps the in-memory set in step
  - [x] 3 `restore()` seeds `_deletedEntryIds` from the newest session row
  - [x] 4 `_storeSnapshotEntry` clears the tombstone for a carried id (scoped — see the Assumption Log) and replaces the whole entry when `loggedAt` differs; `entries` folds the two arms differently
  - [x] 5 S-124 ×2, S-125 ×2, S-126 (second half) added; `watch_session_engine_test.dart` 36 passed / 0 failed
  - [x] 6 regression: four suites 141 passed / 0 failed, engine + projection 68 passed / 0 failed, full suite `+4042 ~1`, lint 196/0, I-2 clean; evidence + Progress below
- [x] Phase 3 — the Swift twin, PROTOCOL, docs — **Complete** (developer, 2026-10-07; base `c4e29e5`)
  - [x] 1 `WatchSessionRecord.deletedEntryIds` — field, init default, `withSequence`, `withDeletedEntryIds`, `toJson`/`fromJson`; the file store round-trips it unchanged
  - [x] 2 the three rules in `WatchSessionEngine` — union written in `storeSessionRow` (the row funnel), `restore()` seeds, `unhideTheIdTheSnapshotNames` + `sameStamp` clear/merge/replace, `delete_entry` and `pruneConfirmed` drop the replaced id
  - [x] 3 the Swift halves of S-124 (×2 engine, ×2 file store), S-125 (×2), S-126 and S-35's stale re-statement; `swift test` 333 / 0 (baseline 325 / 0)
  - [x] 4 `PROTOCOL.md` — one dated `1 (amended) | 2026-10-07` version-history row; no schema, validator or fixture change
  - [x] 5 `docs/watch_session_sync.md` — the delete bullet is the rule, the lens is durable, D-117's two statements; four mutation proofs in the evidence file (`prove-red` cannot compile the new API at the base commit)
  - [x] 6 `docs/state_management/watch_surface.md` — the two D-118 invariants and the stale S-35 pointer; the docs contract test enumerates no claims, so S-127 stays the reviewer's; evidence + this Progress
  - [x] checks — four suites `+109`, full `test` `+4042 ~1`, `lint` 196 issues / 0 errors, invariant clean; the two unscheduled Swift suites (`WatchPhoneEntriesTests`, `WatchFileStoreTests`) are covered by the full `swift-test` run

## Assumption Log

Phase 1 (developer, 2026-10-07). Each entry: decision / options considered / why.

1. **The `heldWristEntryIds` seam is optional with a default, not required (`_heldWristEntryIds!`).**
   Options: a required constructor parameter (item 5's text), or an optional named one defaulting to a
   `const {}` no-op. Chose optional: every existing construction site — the tests and any future
   mirror-only host — keeps compiling, and "the phone holds no wrist entries" is a truthful default.
   The wiring still passes the real function, so no runtime path uses the default.
2. **The ledger is seeded by writing `held` on every pass, not by an early return.** Options: an
   explicit `if (!_announced.containsKey(sessionId)) { _announced[sessionId] = held; return; }`, or
   the one-line `..[sessionId] = held`. Same observable behaviour (S-123, S-120), one branch fewer;
   the phase's mutation record shows the seed is load-bearing either way.
3. **S-123's mutation, as the plan words it, is not reachable on its own.** "Seed from an empty set
   instead of from `held`" only changes behaviour once the difference direction is inverted too
   (evidence, mutation b′). Recorded honestly instead of claiming the plan's exact mutation.
4. **The per-session keying of `_announced` is not observable.** Flattening the lookup leaves every
   test green, S-85 included, because the ids are slot-scoped. Kept as a cheap invariant; the
   reviewer can drop it or ask for a fixture.
5. **Fixture ids follow the harness, not the plan's prose.** The plan's scenario text says
   `entry-bench-*`; `test/watch_session_auto_push_test.dart` numbers sets `entry-sx-1-*` /
   `entry-slot-bench-*`. The scenario's *outcome* is asserted unchanged; only the ids differ.
6. **The plan's S-35 pointer (~line 1158) is stale** — the test is at ~1780 in
   `test/watch_session_projection_test.dart`. The named test was found by name, not by line.
7. **A full `flutter test` run was made at the end of Phase 1** although the plan schedules it for the
   end of Phase 3: `+4036 ~1: All tests passed!`. The evidence Baseline test row is post-change, since
   no base-commit full-suite run exists for this PR.
8. **No Swift file changed in this phase**, so no `swift-test` run and no Swift prove-red: S-126's
   second half and TRAP 2's durable half are Phase 2/3 work.

Phase 2 (developer, 2026-10-07). Each entry: decision / options considered / why.

1. **The union is written in `_appendSessionRow`, not in `_applyStructureChange`.** Options: item 2's
   literal "the change writes the union onto the session row it appends", or writing it in the single
   funnel every row passes through. Chose the funnel (`watch_session_engine.dart:1148`): `restore()`
   reads the *newest* row, so the lifecycle row S-124's second case appends after an ordinary frame
   would otherwise answer with an empty lens. A superset of item 2's text; nothing else changes.
2. **The snapshot's tombstone state is settled before its own row is appended.** `_applySnapshot`
   appends the session row *before* `_storeSnapshotEntry` runs, and that row is what `restore()` reads
   the lens from — so the D-113.2 clear is applied in `_applySnapshot`'s entry loop as well as at the
   entry-store site item 4 names. One helper (`_unhideTheIdTheSnapshotNames`), two call sites.
3. **D-113.2 is scoped: the clear applies only to a statement the wrist is not already holding.**
   Options: the literal rule (clear for every carried id), or clearing only when the snapshot outranks
   what the wrist holds — no held row, or a differing `loggedAt`. Chose the scoped rule: the literal
   one turns Phase 1's `S-35 a re-statement of a deleted id stays deleted`
   (`test/watch_session_projection_test.dart`) red, while this plan's own impact row for
   `_storeSnapshotEntry` requires that family to stay green. D-115 says the phone stops sending a
   deleted id, so a same-stamp repeat is a stale answer and the newer deletion wins. Convergence
   (TRAP 4) is untouched: a differing stamp is D-113.3's replacement, and an id the wrist never held is
   shown. Evidence mutation b is the literal reading, red on S-35; Open question 5 asks for the ruling.
4. **The replacement/correction lens stays memory-only, like 17b's corrections.** Only the *deletion*
   lens is durable (that is the field D-113.1 asks for), so after a wrist relaunch a re-created id
   shows the dead set's stored fields again. Outside Phase 2 — Open question 5's neighbour, not
   absorbed here.
5. **The brief's extra item needs the delete and the session switch inside one window.** A phone-side
   delete only reaches the *composed* session (the ledger is keyed by composed id, and a pass
   composing nothing returns before it announces), so a mirror-level delete alone cannot shrink the
   held set. Recorded because it is the only fixture that discriminates the ledger drop.

Phase 3 (developer, 2026-10-07). Each entry: decision / options considered / why.

1. **The union is written in `storeSessionRow`, not on the structure-change row alone.** Options: item
   2's literal "the structure-change row", or the one funnel every session row passes through. Chose
   the funnel, matching Phase 2's Assumption 1 and for the same reason: `restore()` seeds from the
   *newest* row, so a lifecycle row appended after an ordinary frame would otherwise answer an empty
   lens. Mutation c isolates that case.
2. **D-113.2's scoped reading was carried into Swift unchanged.** Options: the literal rule (clear for
   every carried id) or Phase 2's scoped one (clear only when the wrist holds no row for the id or the
   `loggedAt` differs). Chose scoped: the literal reading turns the pre-existing
   `WatchPhoneEntriesTests.testS35AReStatementOfADeletedIdStaysDeleted` red as well as this phase's
   twin (mutation d), and Open question 5's default is the scoped rule. Reversible in one predicate
   across both twins if the owner rules the other way.
3. **A third doc was implicated by Phase 1's rename.** `docs/watch-app-setup-and-qa.md:384` still read
   "Deleting a set on the phone is **not** carried" — false since Phase 1 — and named the pre-rename
   test. Fixed in two lines (the pointer plus the outcome). Outside the phase's Predicted Files;
   `docs/state_management/watch_surface.md:88` and `docs/watch_session_sync.md:91` carried the same
   stale pointer and were fixed while those files were already open.
4. **D-117's "added weight" sentence is written as structure, not as an unverified behaviour claim.**
   No test pins the absence of `extraLoadKg` on a set's entry (the field is the hold/drill path's, and
   the closest assertions only *show* it on a hold/drill), and the doc standard forbids a behaviour
   sentence with no test behind it. The bullet therefore names the file that owns the field, and points
   the one assertion it does make — a set's total rides `loadKg` verbatim and a rep-less row is left
   out — at `S-59 …omits only the row without reps`.
5. **`prove-red` is unusable this phase; four mutations are the proof.** The new tests exercise API
   that does not exist at the base commit, so they cannot compile at `HEAD` and a red would mean
   nothing. Each of the four guards was mutated alone, run, restored exactly (`git-diff --stat` back to
   the phase's own 4 Swift files), and re-run green; the verdicts are in the evidence file.

## Feedback

- **D-113.2's literal wording contradicts this plan's own impact table** (developer, Phase 2,
  2026-10-07). Clearing the tombstone for *every* id a snapshot carries turns Phase 1's
  `S-35 a re-statement of a deleted id stays deleted` red, yet the `_storeSnapshotEntry` row in
  Existing-Functionality Impact requires that family to stay green. Phase 2 shipped the scoped reading
  (Assumption Log 3) and is **Complete**; the planner should ratify that wording — or say the S-35
  guard is meant to flip, which is a one-predicate change (evidence mutation b).
- Otherwise empty.

## Open questions

Every question carries the default this plan proceeded on. The owner was unavailable; each default is
implementable and reversible.

1. **Should a deletion still be visible as deleted after the watch is restarted or the app re-opened
   hours later, inside the same session?** Default: **yes** — the deletion is written to the wrist's
   own session record, so a relaunch does not bring the set back (D-113.1). The alternative (accept
   that a wrist relaunch resurrects the deleted set until the session is replaced) would save a field
   on a stored record and two engines' write/restore paths, and is the current behaviour — say the
   word and Phase 2/3 collapse into receiver-only rules.
2. **Should the phone also tell the wrist about a set the user *skipped*, or a set's added weight?**
   Default: **no** — a skipped set is not a performed set and a set's added weight already travels as
   the set's total load (D-117). The alternative is a schema field, both validators, a fixture and a
   wrist surface that shows skipped work; that is a PR of its own.
3. **Should a deletion made on the watch travel back to the phone?** Default: **no, not in this PR** —
   the wrist has no delete sender today and the owner's goal for this PR is the phone→wrist
   direction. If the owner wants it, it is a new PR with its own ledger (and it interacts with the
   import claim rule in D-112).
4. **How fast must a deletion appear on the wrist?** Default: **the existing push cadence** — 250 ms
   debounce plus one frame (D-110), no new timer. Making it immediate would mean sending outside the
   debounce, which weakens the coalescing the push does for every other change.
5. **May a snapshot resurrect an id whose deletion the wrist already knows?** Default: **only when the
   snapshot's statement is new to the wrist** — the tombstone is cleared for a carried id when this
   watch holds no row for that id, or when the snapshot's `loggedAt` differs from the held row's
   (Phase 2, Assumption Log 3). The literal D-113.2 is one predicate simpler, but it turns a stale
   repeat of a deleted id back into a visible set, which is the behaviour the existing S-35 test
   guards against. Reversible in one predicate; the owner's answer decides Phase 3's Swift twin too.
6. **Does the wrist need the re-created set to survive a relaunch as the *new* set, not the dead
   one's fields?** Default: **not in this PR** — the replacement lens is memory-only, so after a
   relaunch a re-created id shows the deleted set's stored fields (a re-created set is rare, and the
   next snapshot's differing `loggedAt` re-replaces it). Persisting it means a second durable map on
   the session row in both twins; say the word and it is a follow-up.
