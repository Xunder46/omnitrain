# Feature: watch-session-sync PR 3 — a set logged on the phone reaches the wrist

> **Split (governor, 2026-10-05).** This plan is two PRs. **PR 3a** = Phases 1, 2, 4 — the contract,
> the phone's projection, the docs. **PR 3b** = Phase 3 — the wrist takes a re-statement, with the
> PROTOCOL sentence and the fixture case that go with it. 3a ships the headline (a phone-logged set
> reaches the wrist and the existing merge stores it) and not the edit: after 3a an edit to such a set
> is sent and dropped, the intermediate state `## Notes` describes. The governor overruled that
> section's one-PR argument on scope grounds. Phase 1 therefore documents D-33, D-34 and D-36 and
> omits D-35's re-statement rule, and the reconciliation fixture pins the no-double-store merge rather
> than a re-statement.

> Status: DRAFT — plan complete, owner answers pending (`## Open questions` at the end)
> Next handoff: **@dba (Phase 1 — the contract)**
> Binding conventions: `docs/global_conventions.md`. Normative contract: `watch/sync_protocol/PROTOCOL.md`
> (this PR amends it, D-32). Series index: `docs/plans/2026-10-05-15-watch-session-sync-index.md`.
> Areas: `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`,
> `docs/watch-app-setup-and-qa.md`. Series decisions: D-1…D-12 (PR 1), D-13…D-20 (PR 2a),
> D-21…D-30 (PR 2b). This plan continues at **D-31** and **S-31**.

## Overview

PR 1 made the phone and the wrist converge on one session; PR 2a merged a set the **wrist** logged into
the session the phone holds; PR 2b gave the wrist a logging screen. The loop is still open in one
direction: a set logged on the **phone** never appears on the wrist, because the phone's on-demand
session answer hard-codes `'entries': const <Object?>[]`
(`lib/state/watch/watch_session_adoption_bridge.dart:177` `projectSession`). This PR closes it.

The hard decision — how phone-logged entries reach the wrist — is settled as **the existing
`session_snapshot` answer's `entries` array** (D-31), not a new message family. The wire already
supports it end to end and nothing on the wire changes: `session_snapshot.schema.json` already
*requires* `entries`; `envelope.schema.json` `$defs.entry` already carries every metric a set needs;
`MessageValidator._snapshotRejections` already validates them; both reconcilers already merge entries
by `entryId` (`SyncSessionReconciler._applySnapshot`; `WatchSessionEngine.applySnapshot` →
`storeSnapshotEntry`). The only gap is on the phone. PROTOCOL.md's "Idempotency and reconciliation"
already says entries "merge by `entryId`, so an entry one side lacks is a convergence in progress"
and that "entries come from whoever logged them" — so the amendment (D-32) is **additive
documentation**, not a wire change, and needs no schema or version bump.

Owner constraints, honoured: sync stays **manual** (the Sync action is the only trigger, D-42); no new
phone surface; no conflict logic (the phone's entries are the phone's own — nothing is arbitrated);
the wrist's store stays append-only (D-35).

Deliverable: the plan below. Out of scope and named as follow-ups in `## Open questions`: deletions,
the phone's timed/hold/round entries, the phone's rest timer, and the wrist's durable store (PR 4).

## Resolved Decisions (Ledger)

- **D-31 — The wire contract: phone-logged entries ride the existing `session_snapshot` answer.**
  A `session_snapshot` from the phone carries, in `payload.entries`, the entries the phone logged
  itself; the receiver merges them by `entryId`. Alternatives evaluated and rejected:
  - **(a) a new phone→wrist family `entries_down`** (the index's proposal). Rejected: it duplicates
    surface the snapshot already has — the schema requires `entries`, both validators validate them,
    both engines already merge them by `entryId` and already confirm them, and the receipt path
    already exists. (a) would add a message type, two schema files, a validator profile, a receipt
    variant, and per-entry plumbing in both stacks, and would still need the same identity and
    ordering decisions below. It buys exactly one thing — entries that can arrive without a snapshot
    — and PR 3's trigger is a manual Sync, which is a snapshot exchange by definition (D-42).
  - **(c) `structure_change` `correct_entry`/`delete_entry`.** Rejected as the *carrier*: those
    changes correct and delete entries that exist, and by construction cannot add one
    (`WatchSessionEngine._applyStructureChange` has no add case). They stay the mechanism for
    corrections and deletions (D-38).
- **D-32 — PROTOCOL.md is amended additively; the wire version does not move.** The new normative
  sentences: a `session_snapshot`'s `entries` are **the sender's own entries**, and a receiver MUST
  re-state an `entryId` it already holds from the snapshot's values rather than storing a second row
  (D-35); authority rule 1's second sentence gains "and the phone MAY add entries it logged, which
  arrive in its `session_snapshot`"; the entry-identity, provenance and ordering rules of D-33, D-34
  and D-36 are stated. A conforming receiver already handles this shape, so the change is compatible:
  `## Version history` gains `| 1 (amended) | 2026-10-05 | <the sentences added> |`, after the two
  existing `1 (amended)` entries (2026-09-25, 2026-09-27).
- **D-33 — Entry identity: the phone mints `entry-<sessionExerciseId>-<n>`.** `n` is the row group's
  number in the slot (`EntryRows.numberInId`); `sessionExerciseId` is the slot id, which is already
  the protocol id (PR 1 D-3). `eventId` equals `entryId`. The wrist mints UUIDs
  (`WatchSessionEngine`'s `idFactory` → `UUID().uuidString`), so the two id spaces are disjoint by
  construction and a phone entry can never collide with a wrist entry. Precedent for
  phone-minted deterministic ids: `phoneRatingId`, `phoneChangeId`.
- **D-34 — Provenance: the phone projects only the entries it logged itself.** For a slot, a row group
  is the wrist's iff a **live** watch-inbox row for the same session, `origin == originWatch`,
  `appliedAtMs != null`, claims it by stamp — `group.createdAtMs == row.loggedAtMs` — claimed
  **one-to-one in ascending group order** (a second group with the same stamp is the phone's own).
  The stamp is the importer's own identity rule for an imported entry's rows
  (`WatchSessionImporter.unfinishedPlaceOf`: "every row there holds exactly what the entry would
  write"); the one-to-one claim is what makes a same-millisecond coincidence a benign
  under-projection instead of a lost entry. Every unclaimed group is the phone's own and is
  projected. Consequence: the phone never echoes the wrist's entries back, so nothing is doubled,
  and the wrist's own rows keep being confirmed by the phone's existing `receipt`
  (`WatchSessionInbox._settle` → `WatchNutritionLogBridge.receiptFor`).
- **D-35 — The snapshot is authoritative for the entries it carries.** An `entryId` the wrist already
  holds is **re-stated**: the snapshot's payload folds into `_entryCorrections` (the projection lens
  `entries` already reads) and the stored observation is never rewritten. An id it does not hold is
  stored, exactly as `storeSnapshotEntry` does today. This is what makes an **edit to a set the phone
  logged** reach the wrist without a new message, and it is why "sent but silently dropped" cannot
  happen. No arbitration: by D-34 the phone only ever names its own entries, and the wrist never
  names them back.
- **D-36 — Ordering and `loggedAt`.** A projected entry's `loggedAt` is its row group's
  `createdAtMs` (all rows of one entry share it: `addEntry` captures one `now`), written as UTC
  ISO-8601 (`utcIso`). The wrist orders entries by `loggedAt` then `entryId` (existing rule,
  `WatchSessionEngine._byLoggedAtThenEntryId`), so a phone entry sits in the same order the phone
  shows it.
- **D-37 — Units: nothing converts.** The wire is canonical kg, the phone stores canonical kg, and
  `loadKg` is passed through. A user displaying lb sees lb on both screens.
- **D-38 — Corrections and deletions: this PR carries adds only.** A `correct_entry` is carried by the
  snapshot's re-statement (D-35) for an entry the phone logged. A **deletion** does not reach the
  wrist: the phone's projection simply stops naming the entry, and the wrist keeps the row it holds.
  The mechanism for a deletion is `structure_change` `delete_entry` — already implemented in both
  engines and both validators — and the phone has no sender for it. Named follow-up (PR 5 row in the
  index). Stated in `docs/watch_session_sync.md` in the user's words.
- **D-39 — Kinds: sets only.** `set` entries are projected. The phone's `timed`, `hold` and `round`
  entries are not projected yet — each needs its window/distance/round fields mapped from its
  instance row and its own scenarios. Named follow-up (PR 5 row).
- **D-40 — The projection emits only entries the schema and the validator accept; anything it cannot
  render is omitted, never placeheld.** Concretely: a **skipped** set is omitted (the wire has no
  `skipped` field, `additionalProperties: false`), a set whose stored reps are `< 1` is omitted
  (`reps` has `minimum: 1`), and a set's added weight is not sent (`extraLoadKg` is documented as a
  hold's load). This is a safety rule, not a nicety: a rejected entry rejects the **whole** snapshot,
  so a placeholder would cost the wrist the entire answer. Derived from the schema — offered for veto.
- **D-41 — The projection is read-only and deterministic.** It never writes to the repository, and
  the same rows always produce byte-identical `entries` (same ids, same order, same values) — which
  is what keeps the mirror's echo guard (PR 1 D-11, `_shapeDiffers`) from re-asserting.
- **D-42 — Manual sync stays the only trigger; no new phone surface.** The projection is composed
  when the phone answers (`watch_sync_request_handler.dart:102`) or re-asserts
  (`live_session_mirror_state.dart:308`), both of which are Sync-driven. No new button, screen,
  banner, or background timer. The projection's `timers` stays `{}` (PR 2b D-26 stands: a Sync still
  clears a wrist countdown) — carrying the phone's rest timer is a follow-up (PR 5 row).

## Feature Invariants

Only the ones that bite here:

- **Implementation parity.** `HiveWorkoutRepository` and `MockWorkoutRepository` produce the same
  observable output for the same inputs. The projection reads through `WorkoutRepository` only.
- **Layer boundary.** `lib/state/` and `lib/features/` depend on `WorkoutRepository`, never on
  `HiveWorkoutRepository` — the standing invariant check must stay clean.
- **Append-only wrist store.** A correction is a lens over a stored row; `storeSnapshotEntry` and the
  re-statement of D-35 never rewrite one.
- **Determinism.** D-41 — re-projecting unchanged rows yields identical bytes.
- **One entry, one row.** An entry that both sides hold has exactly one row on the wrist, whichever
  side logged it (D-33, D-34).
- **Cross-stack agreement.** The Dart wrist twin and the Swift engine stay contract-tested against
  the same fixtures; a contract change must leave both suites agreeing.

## Requirements

1. A set logged on the phone while the phone holds the session reaches the wrist on Sync, shown as a
   set with the phone's reps and load, in the phone's order.
2. Redelivery of the same answer never doubles a wrist row.
3. A set the wrist logged is never sent back to it under a second id.
4. An edit to a set the phone logged reaches the wrist, and the wrist's stored row is not rewritten.
5. A phone entry shows on the wrist exactly like one the wrist logged: same counts, same "last set".
6. Nothing on the wire changes shape; the existing fixtures, validators and reconciliation fixtures
   stay valid.
7. A rejected snapshot is impossible by construction (D-40).
8. No new phone surface; Sync remains manual (D-42).

## Acceptance Criteria

Each maps to ≥ 1 scenario.

- **AC-1** — A held phone session's logged sets appear on the wrist after Sync (S-31, S-38).
- **AC-2** — Neither a redelivered answer nor a wrist-logged set doubles a row (S-32, S-33, S-41).
- **AC-3** — The wrist's order and derived counts match the phone's (S-34, S-37).
- **AC-4** — An edit to a phone-logged set reaches the wrist with the store still append-only (S-35).
- **AC-5** — A session with no phone entries answers with none; a session the wrist lacks is adopted
  with its entries (S-36, S-38, S-40).
- **AC-6** — The projection is deterministic and never emits an entry the validator would reject
  (S-39, S-42, S-43).

## Existing-Functionality Impact

| Touched surface | What already reads it (how found) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchSessionAdoptionBridge.projectSession` | `lib/state/watch/watch_sync_wiring.dart:149` (injected as the mirror's `projection`), `lib/state/watch/watch_sync_request_handler.dart:102` (`projectedSession`), `test/watch_session_merge_test.dart:168`, `test/watch_session_finish_test.dart:132` (both inject it), `test/watch_session_projection_test.dart`, `test/live_mirroring_test.dart` — found by grep `projectSession\|projectedSession\|snapshotEnvelope\(` | The answer gains a non-empty `entries` array where it was always empty. The two injecting tests must stay green: they are regression targets for Phase 2. | S-31…S-43; Phase 2 Done Criteria |
| `session_snapshot` `entries` on the receiving side | `SyncSessionReconciler._applySnapshot` (merges by `entryId`, clears on session switch), `MessageValidator._snapshotRejections` → `_entryIdentityRejections`/`_captureRejections`, `WatchSessionEngine._applySnapshot:438` → `_storeSnapshotEntry:697`, Swift `applySnapshot:439` → `storeSnapshotEntry:718` — read directly | Entries that were always empty now carry data. No signature or schema change. | S-31, S-32, S-38, S-40 |
| The wrist's entry projection (`entries`, `_entryCorrections`) | `lib/watch/session/watch_session_engine.dart:212` and Swift `projectedEntries:196`; `confirmObservations` (both stacks) | A snapshot naming a held id now folds into `_entryCorrections` instead of returning early. Display order and confirmation semantics unchanged. | S-32, S-35, S-41 |
| The phone's watch inbox as a provenance source | `WatchSessionImporter._createEntry` (`atMs = entry.loggedAtMs` on every row it writes), `unfinishedPlaceOf:1323`, `WatchSessionInbox._settle:405` (the receipt) — read directly | Read-only: the projection claims row groups by inbox stamp. No write, no schema change. | S-33, S-34 |
| `WatchInboxEntry.appliedAtMs` semantics | `watch_session_inbox.dart:442` (a redelivered entry is receipted only when `appliedAtMs != null`) | Read-only, and now also the D-34 liveness test. | S-33 |
| `docs/watch_session_sync.md` "What does not sync" | Cites `test/watch_session_projection_test.dart` for "sets logged on the phone are not carried to the wrist" | That claim becomes false; the bullet and its citation are replaced (Phase 4). | Phase 4 Done Criteria |
| `test/watch_session_projection_test.dart:318` | `expect(payload['entries'], isEmpty)` inside S-2 | The pin flips to a non-empty expectation (Phase 2). | S-31 |
| The wrist's derived counts ("last set") | `lib/watch/logging/watch_logging_state.dart`, Swift logging state — read directly | A phone entry is a row like any other; counts rise, and no code changes. | S-37 |
| Timers | PR 2b D-26 (`projectSession` answers `'timers': const {}`) | **Unchanged** — the projection still answers `{}`. | D-42; S-43 |
| `scripts/sqlite_schema.sql` / `models.dart` | `test/db_seed_test.dart` executes the schema | **Unaffected** — no model, table or column changes. Verified by the absence of any model edit in Predicted Files, and by `gateway.sh test`. | Phase 1/2 Done Criteria |

## Scenarios

Numbering continues after PR 2b's S-30. Comments and tests cite these ids.

### S-31: a set logged on the phone reaches the wrist at Sync
- Fixture: the phone holds `sess-1` (`status: started`) with one exercise `ex-bench` (capabilities
  `reps`,`load`) in slot `slot-bench`, and exactly two row groups in that slot — `entry-slot-bench-0`
  (reps 8, loadKg 60.0, `createdAtMs` T1) and `entry-slot-bench-1` (reps 8, loadKg 62.5, T2 > T1).
  The wrist holds `sess-1` with the same ladder and **zero** observations of its own. No watch-inbox
  rows for `sess-1`.
- Trigger: the wrist sends its `session_snapshot`; the phone answers.
- Flow: the projection reads the slot's rows, mints both ids, the answer carries both entries; the
  wrist `applySnapshot` → `storeSnapshotEntry` twice → `confirmObservations`.
- Expected outcome: the wrist's `entries` holds exactly two rows, ids `entry-slot-bench-0` and
  `entry-slot-bench-1`, `kind: set`, reps 8/8 and loadKg 60.0/62.5, in that order; the slot's set
  count is 2; both rows are confirmed (the phone has them) and are not owed.
- Edge case of: none.

### S-32: the same answer twice does not double a row
- Fixture: as S-31 after the answer landed (the wrist holds both rows, confirmed); the phone's rows
  unchanged.
- Trigger: the identical envelope arrives again (same `messageId`), then a fresh one with a new
  `messageId`.
- Flow: `storeSnapshotEntry` finds `recordId == entryId` and returns early.
- Expected outcome: still exactly two rows with those values; no duplicate; no emission from the
  wrist.
- Edge case of: S-31.

### S-33: the wrist's own set is not sent back
- Fixture: `sess-1` on the phone holds one slot with three row groups: the phone's own
  `entry-slot-bench-0` (reps 8, 60.0, T1); a wrist entry `9F2C…-UUID` (reps 5, 55.0, T2) imported
  earlier — a live inbox row for `sess-1`, `originWatch`, kind `set`, `loggedAtMs == T2`,
  `appliedAtMs != null`, whose rows carry `createdAtMs == T2`; and the phone's own
  `entry-slot-bench-2` (reps 10, 65.0, T3).
- Trigger: the phone answers a snapshot.
- Flow: the inbox row claims the group stamped T2; the other two are unclaimed and projected.
- Expected outcome: `entries` carries exactly two entries — `entry-slot-bench-0` and
  `entry-slot-bench-2` — and never the UUID; the wrist's own row is untouched and not doubled.
- Edge case of: S-31.

### S-34: a same-millisecond coincidence loses nothing
- Fixture: as S-33, but the phone's own `entry-slot-bench-2` has `createdAtMs == T2` (the same
  millisecond as the wrist entry), and no other group in the slot shares T2.
- Trigger: the phone answers a snapshot.
- Flow: the live inbox row claims exactly one group stamped T2 — the first in ascending order, which
  is the imported one (the import wrote it at that stamp before the phone's row existed); the second
  stays unclaimed.
- Expected outcome: both the wrist's entry and the phone's `entry-slot-bench-2` are represented on
  the wrist exactly once each — the wrist's own row keeps its UUID, and the phone's row arrives under
  its minted id. Nothing is dropped.
- Edge case of: S-33.

### S-35: an edit to a set the phone logged reaches the wrist
- Fixture: as S-31 after the answer landed (the wrist holds `entry-slot-bench-0` at 60.0 kg, stored
  and confirmed). The phone then edits that set's load to 62.5 kg, keeping the same row group and
  `createdAtMs`.
- Trigger: Sync again — a new snapshot names `entry-slot-bench-0` with 62.5 kg.
- Flow: the wrist holds the id, so the payload folds into `_entryCorrections`; the stored row is
  untouched.
- Expected outcome: the wrist's `entries` shows 62.5 kg for that id; the stored observation row still
  holds 60.0 kg; one row, not two; the id is still confirmed.
- Edge case of: S-31.

### S-36: a session with no entries answers with none
- Fixture: the phone holds `sess-1` with a ladder and zero logged entries, no inbox rows.
- Trigger: the phone answers a snapshot.
- Expected outcome: `payload['entries']` is an empty list — the existing S-2 expectation holds
  unchanged.
- Edge case of: S-31 (empty state).

### S-37: a phone entry counts like the wrist's own
- Fixture: `sess-1` with one slot; the phone logged two sets (T1, T3); the wrist logged one of its own
  (T2) which the phone has imported.
- Trigger: the wrist's logging state derives the slot's set count and the "last set" line.
- Expected outcome: the count is 3, and the last set is the newest by `loggedAt` (the phone's T3);
  nothing in the derived display distinguishes a phone entry from a wrist one.
- Edge case of: S-31.

### S-38: the wrist adopts a session it does not hold
- Fixture: the wrist holds no session (empty store); the phone holds `sess-1` with the S-31 ladder and
  two logged sets.
- Trigger: the phone's snapshot arrives.
- Flow: `applySnapshot` stores the session row, the ladder, then the entries.
- Expected outcome: the wrist holds `sess-1` with the ladder and both entries; the phone's sets are
  shown with the wrist having logged nothing.
- Edge case of: S-31.

### S-39: the projection is deterministic
- Fixture: as S-31.
- Trigger: the phone projects twice with no write between, then the wrist re-asserts with an
  identical snapshot.
- Flow: `_shapeDiffers` (PR 1 D-11) compares the received snapshot with the phone's own state.
- Expected outcome: byte-identical `entries` both times; the phone does not re-assert, so no echo
  loop.
- Edge case of: S-31.

### S-40: two sessions do not share entries
- Fixture: the phone holds `sess-1` (two sets) and `sess-2` (one set); the wrist holds `sess-1` with
  the two entries and no session `sess-2`.
- Trigger: the phone's held session becomes `sess-2` and Sync runs.
- Expected outcome: the wrist holds `sess-2`'s ladder and its one entry **under `sess-2`**; `sess-1`'s
  rows are still `sess-1`'s and are not merged into `sess-2`.
- Edge case of: S-31.

### S-41: the wrist's own set survives an answer with no phone entries
- Fixture: the wrist logged one set (UUID) in `sess-1`; the phone holds `sess-1` with that entry
  imported and no phone-logged entries.
- Trigger: the phone answers.
- Expected outcome: `entries` is empty; the wrist's row survives the merge and is confirmed through
  the existing `receipt` path.
- Edge case of: S-33.

### S-42: an entry the wire cannot carry is omitted, not placeheld
- Fixture: `sess-1` with one slot holding a skipped set (stored reps 0) and a normal set (reps 8,
  60.0), no inbox rows.
- Trigger: the phone answers; the answer is validated.
- Expected outcome: the answer carries only the normal set; `validateEnvelope` reports no rejection
  (a `reps: 0` entry would be a `constraintViolation` and would cost the whole snapshot); the wrist's
  rows are the normal set alone.
- Edge case of: S-31.

### S-43: the phone is unreachable at Sync
- Fixture: the wrist holds its own set; the phone holds two sets it logged and does not answer.
- Trigger: the Sync action runs with no reply.
- Expected outcome: nothing changes on either side — the wrist keeps its own row and its "owed to
  phone" line, the phone's sets do not appear — and a later Sync that is answered converges exactly
  as S-31.
- Edge case of: S-31 (transport failure).

## Iteration 1

Phase graph: **1 → 2 → 3 → 4.** Phase 2 is the visible win (the wrist already stores snapshot entries
today, so the headline works as soon as the phone sends them); Phase 3 makes an edit to a phone-logged
set reach the wrist; Phase 4 closes the docs. Phases 2 and 3 could swap, at the cost of shipping the
"sent but silently dropped" edit in between — which is why they do not.

### Phase 1: The contract (@dba)

1. [ ] Amend `watch/sync_protocol/PROTOCOL.md`: authority rule 1's second sentence gains "and the
       phone MAY add entries it logged, which arrive in its `session_snapshot`" (D-32).
2. [ ] Add to the same file, under "Idempotency and reconciliation" (beside the existing
       "entries merge by `entryId`" bullet at ~302) and "Session capture", the normative sentences for
       D-33 (identity, `eventId` = `entryId`), D-34 (provenance: a snapshot carries the sender's own
       entries), D-35 (a re-stated id is the sender's current values; the stored row is not rewritten)
       and D-36 (ordering by `loggedAt` then `entryId`).
3. [ ] Add the `## Version history` row `| 1 (amended) | 2026-10-05 | <what was added> |`, following
       the two existing amended entries.
4. [ ] Add `watch/sync_protocol/fixtures/valid/session_snapshot_with_entries.json`: a phone
       `session_snapshot` for `sess-1` carrying two `set` entries in the D-33 shape (ids
       `entry-slot-bench-0`/`-1`, reps, loadKg, `sessionExerciseId`, `exerciseId`, `loggedAt`).
5. [ ] Add `watch/sync_protocol/fixtures/reconciliation/phone_entries_merge.json`: a session with a
       ladder, a wrist observation, and a snapshot naming one held id (re-stated) plus one new id, so
       both stacks must land on the same structure.
6. [ ] Extend `test/sync_protocol_fixtures_test.dart` to replay the new valid fixture (conformance
       profile, no rejection) and to assert the shape of one entry field-by-field.
7. [ ] Extend `test/watch_reconciliation_cross_stack_test.dart` to replay the new reconciliation
       fixture, asserting both stacks agree (entries excluded from the structural comparison, as the
       file's header already explains) and that the snapshot's entries are absorbed.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test` (900 s; whole suite — the `test` check runs `flutter test` and appends any args), `.github/copilot/scripts/macos/gateway.sh swift-test` (900 s).
**Predicted Files**: `watch/sync_protocol/PROTOCOL.md`, `watch/sync_protocol/fixtures/valid/session_snapshot_with_entries.json` (new), `watch/sync_protocol/fixtures/reconciliation/phone_entries_merge.json` (new), `test/sync_protocol_fixtures_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift` (only if the Swift fixture replay needs the new file listed).

### Phase 2: The phone's projection (@developer)

1. [ ] Add the pure row → wire-entry mapping (predicted `lib/core/sync_protocol/phone_entries.dart`):
       given a slot id, the slot's row groups, and the claiming inbox stamps, return the projected
       entries — ids per D-33, `eventId` = `entryId`, `kind: set`, `loggedAt` per D-36, `reps`,
       `loadKg`, `sessionExerciseId`, `exerciseId`; omit per D-40.
2. [ ] Implement the D-34 claim: read the session's live watch-inbox rows (`originWatch`,
       `appliedAtMs != null`) and claim row groups one-to-one in ascending order by
       `group.createdAtMs == row.loggedAtMs`.
3. [ ] Fill `'entries'` in `WatchSessionAdoptionBridge.projectSession`
       (`lib/state/watch/watch_session_adoption_bridge.dart:177`), iterating the ladder's slots and
       reading the phone's rows for each effort through the repository (observations, plus
       `EntryRows`/`SetRows` readers); no writes (D-41).
4. [ ] Leave `'timers': const {}` untouched (D-42) and add no new phone surface.
5. [ ] Flip `test/watch_session_projection_test.dart:318` (S-36's pin) and add the projection tests
       for S-31, S-33, S-34, S-36, S-37, S-39, S-40, S-42 — plain `test()` where the fixture is state,
       Mock-first where it needs a repository, Hive seeded in `setUp` if a Hive group is used.
6. [ ] Add the mirror-level test for S-32 (redelivery) and keep S-39's echo guard green in
       `test/live_mirroring_test.dart`; re-run `test/watch_session_merge_test.dart` and
       `test/watch_session_finish_test.dart` as regressions (both inject `projectSession`).
7. [ ] Update `docs/watch_session_sync.md`'s ladder table row for the phone's answer and the "What
       does not sync" bullet this PR invalidates — docs trail code by zero phases.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`.
**Predicted Files**: `lib/core/sync_protocol/phone_entries.dart` (new), `lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_session_projection_test.dart`, `test/live_mirroring_test.dart`, `test/watch_session_merge_test.dart` (regression only), `test/watch_session_finish_test.dart` (regression only), `docs/watch_session_sync.md`.

### Phase 3: The wrist takes a re-statement (@dba)

1. [ ] Dart twin: in `lib/watch/session/watch_session_engine.dart` `_storeSnapshotEntry` (697), an id
       the engine already holds folds the snapshot payload into `_entryCorrections` instead of
       returning early (D-35); a new id is stored as today.
2. [ ] Swift: the same in
       `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` `storeSnapshotEntry` (718).
3. [ ] Assert the store stays append-only: the stored row's payload is unchanged after a
       re-statement (both stacks).
4. [ ] Tests: S-32, S-35, S-41 on both stacks — Dart `test/watch_session_projection_test.dart` (or the
       engine's own file) and Swift
       `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` (or a new
       `WatchPhoneEntriesTests.swift` beside it, which SwiftPM picks up automatically).
5. [ ] S-38 (adopt a session the wrist does not hold) on both stacks: the entries land under the
       adopted session id.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`, `.github/copilot/scripts/macos/gateway.sh swift-test`.
**Predicted Files**: `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `test/watch_session_projection_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`.

### Phase 4: Docs, walkthrough, residue sweep (@developer)

1. [ ] `docs/watch_session_sync.md`: replace the "sets logged on the phone are not carried to the
       wrist" bullet with what now syncs, what does not (D-38 deletions, D-39 kinds, D-42 timers), and
       a citation naming the real tests for each sentence (S-31…S-43).
2. [ ] `docs/state_management/watch_surface.md`: state that the phone's answer now carries the entries
       it logged, and that the wrist merges them by id (D-31, D-35).
3. [ ] `docs/watch-app-setup-and-qa.md`: extend the manual walkthrough with the phone→wrist step —
       log two sets on the phone, Sync, see them on the wrist, then edit one and Sync again.
       **Mark it (owner)** — a wrist simulator walkthrough is the owner's, not an agent's.
4. [ ] Residue sweep: `grep -rn "entries': const <Object?>" lib/` and
       `grep -rn "not carried to the wrist" docs/` return nothing; the standing invariant check
       `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
       returns nothing.
5. [ ] Check each touched doc's size stays inside the band (guard:
       `test/docs_indexing_contract_test.dart`; split before ~52 KB). Measured line counts at planning
       time: `watch_session_sync.md` 189, `watch-app-setup-and-qa.md` 499, `watch_surface.md` 686 —
       all well inside.
6. [ ] Write the evidence file (`<feature>-plan.evidence.md`): baselines, per-phase suite counts, the
       red→green table for S-35's re-statement (the test must be shown to fail before Phase 3's
       change), and the two fixture runs.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`, `.github/copilot/scripts/macos/gateway.sh swift-test`; the four greps in item 4.
**Predicted Files**: `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-05-15d-watch-session-sync-pr3-plan/2026-10-05-15d-watch-session-sync-pr3-plan.evidence.md` (new).

### Governor and owner steps (not agent-runnable)

- **(governor)** build the watch app to confirm the Swift change compiles for the device target:
  `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build`.
- **(owner)** run Phase 4's walkthrough on a paired phone + wrist simulator, and confirm the
  boundaries in D-38/D-39/D-42 are acceptable as the shipped behaviour.

## Files Affected

- `watch/sync_protocol/PROTOCOL.md` — the amendment and its version-history row (D-32).
- `watch/sync_protocol/fixtures/valid/session_snapshot_with_entries.json` — new (Phase 1).
- `watch/sync_protocol/fixtures/reconciliation/phone_entries_merge.json` — new (Phase 1).
- `lib/core/sync_protocol/phone_entries.dart` — new: the pure mapping (Phase 2).
- `lib/state/watch/watch_session_adoption_bridge.dart` — `projectSession` composes `entries`
  (Phase 2). *Dependents that only read it:* `watch_sync_wiring.dart`, `watch_sync_request_handler.dart`.
- `lib/watch/session/watch_session_engine.dart` — the Dart twin's re-statement (Phase 3).
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` — the Swift re-statement
  (Phase 3).
- `test/watch_session_projection_test.dart`, `test/live_mirroring_test.dart`,
  `test/watch_session_merge_test.dart`, `test/watch_session_finish_test.dart`,
  `test/sync_protocol_fixtures_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
  `.../SyncProtocolFixturesTests.swift`.
- `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`,
  `docs/watch-app-setup-and-qa.md`.
- Not touched: `lib/data/`, `lib/main.dart`, `scripts/sqlite_schema.sql`, any screen or widget.

## Notes

- **Intermediate states.** After Phase 2 the phone sends entries and the wrist already stores them
  (`storeSnapshotEntry` exists today), so the headline works — but an edit to a phone-logged set is
  sent and dropped, because a held id returns early. Phase 3 removes that state; it must not ship
  without it. After Phase 1 alone nothing user-visible changes.
- **Why one PR, not 3a/3b.** *(Governor, 2026-10-05: **overruled** — the series was split into 3a =
  Phases 1, 2, 4 and 3b = Phase 3; see the Split note at the top of this plan.)* The split was
  considered: 3a = contract + phone projection, 3b = the re-statement. Rejected because 3a's own
  intermediate state is the defect above (an edit that is silently dropped), and the whole feature is
  4 phases / one contract change / no schema change — inside the scope budget
  (`.github/copilot/pr-scope-budget.md`): under 800 lines and 5 phases, under 1,500 lines of predicted
  production code, and the contract change rides with its first consumer.
- **No schema, no model, no migration.** Nothing in `scripts/sqlite_schema.sql`, `lib/data/models/`
  or the Hive boxes changes; `test/db_seed_test.dart` is unaffected.
- **The watch shell is untouched.** All wrist behaviour lands in the Swift package
  (`watch/watchos/Sources/WatchSessionEngine/`) and the Dart twin, both covered by `swift-test`.
- **Test shape.** Prefer plain `test()` for the state-layer projection; widget tests Mock-first; seed
  Hive in `setUp`. A `testWidgets` that awaits a real delay or a Hive write hangs (see AGENTS.md).

## Progress

- [x] Phase 1 — the contract (@developer, PR 3a) — **Complete.** PROTOCOL.md amended (authority rule 1;
      the snapshot-entries merge, provenance and ordering bullets; the phone's id scheme; a dated
      version-history row), the two fixtures added and registered, the two test files extended. Red
      first by mutation, 3 of 3 caught; green `+91` in the two files; whole suite `+3920 ~1`, 0
      failures; `swift-test` 268 / 0; `lint` 196 / 0. Evidence: `<plan>.evidence.md`.
- [ ] Phase 2 — the phone's projection (@developer)
- [ ] Phase 3 — the wrist takes a re-statement (@dba)
- [ ] Phase 4 — docs, walkthrough, residue sweep (@developer)

## Assumption Log

*(Executors append: decision, options considered, choice and why. The Conductor marks each RATIFIED —
promote to a D-x — or REVERT, opening a remediation item.)*

- **A-1 (Conductor, planning).** D-40's omission rule is derived from the schema
  (`additionalProperties: false`, `reps` `minimum: 1`), not from an owner answer. Options: omit, or
  send a placeholder. Chosen: omit, because a rejected entry costs the whole snapshot. Offered for
  veto in `## Open questions`.
- **A-2 (Conductor, planning).** D-34's one-to-one claim rule is a technical call, not a product one:
  options were stamp-only (a same-millisecond coincidence could drop a phone set) or stamp plus a
  one-to-one claim (benign under-projection, never a lost row). Chosen: one-to-one.
- **A-3 (Developer, Phase 1).** Scope is PR 3a only: the governor split this plan into 3a (Phases 1,
  2, 4) and 3b (Phase 3, the re-statement). Options: document D-35 now, or leave it to 3b. Chosen:
  leave it — Phase 1 documents D-33, D-34 and D-36, the fixture pins the no-double-store merge, and
  no sentence claims re-statement, so 3b amends PROTOCOL.md rather than 3a being contradicted by it.
- **A-4 (Developer, Phase 1).** `watch/sync_protocol/fixtures/manifest.json` is not in the Phase 1
  Predicted Files but is mandatory: the manifest test requires every fixture on disk to be listed
  exactly once, and both stacks' register loops read it. Options: stop and report, or register the two
  fixtures. Chosen: register them, as every prior fixture-adding phase did; flagged in the handoff.
- **A-5 (Developer, Phase 1).** The plan names Phase 1's owner as @dba; the governor's brief assigns
  it to @developer. Chosen: follow the brief — Phase 1 changes no model, repository or seed, so no
  data-layer work is involved.

## Feedback

[empty]

## Open questions

Each has a recommended default; the plan proceeds on the defaults.

1. **Sets only in this PR?** The phone's `timed`, `hold` and `round` entries are not projected yet
   (D-39), so a treadmill set logged on the phone still will not show on the wrist. *Default: yes,
   sets only; the rest is a named follow-up (index PR 5 row).* Alternative: carry all four kinds now,
   which roughly doubles the mapping and the fixtures.
2. **A deletion does not reach the wrist?** Deleting a set on the phone leaves the wrist still showing
   it until the wrist's own session is replaced (D-38). *Default: accepted for this PR; the mechanism
   (`structure_change` `delete_entry`, already implemented both sides) is a follow-up.*
3. **A skipped set does not reach the wrist** (D-40) — the wire cannot say "skipped". *Default: omit.*
   Alternative: send it as a performed set, which would be a false record.
4. **A phone-logged set's added weight does not reach the wrist** — `extraLoadKg` is documented as a
   hold's load, so a weighted set travels as its `loadKg` alone. *Default: accepted.*
5. **A Sync still clears a running wrist rest countdown** (PR 2b D-26 stands, D-42): carrying the
   phone's rest timer is not in this PR. *Default: accepted; follow-up (index PR 5 row).*
6. **PROTOCOL.md is amended, not version-bumped** (D-32), dated 2026-10-05, and the wire stays v1.
   *Default: yes — a conforming receiver already handles a snapshot carrying entries.*
7. **The phone mints `entry-<sessionExerciseId>-<n>`** (D-33). *Default: yes; the scheme is
   internal to the phone and never leaves the wire contract's shape.*

### Raised by @developer in Phase 1 (Copilot run, non-interactive — proceeded on the defaults)

8. **`manifest.json` is required but not a Predicted File.** The manifest test requires every fixture
   on disk to be listed exactly once and both stacks' register loops read it, so a new fixture without
   a manifest row fails the suite. *Default: register the fixtures and flag it (A-4).* Alternative:
   stop the phase and re-plan for a Predicted-Files update.
9. **The reconciliation fixture re-carries a held id with identical values.** It pins the
   no-double-store merge; it deliberately does **not** pin a re-statement with changed values, because
   that is D-35 / Phase 3 (PR 3b). *Default: keep it identical — a changed value would document
   behaviour 3a does not ship.*
10. **One `S-31` label covers both new fixtures and both test files.** The register's `S-31` is the
    scenario id; the second fixture is registered under the `scenarios` register with a property
    description rather than a second S-id. *Default: keep one S-id; the property text distinguishes
    them.*
11. **The plan assigns Phase 1 to @dba; the brief assigned it to @developer.** *Default: follow the
    brief (A-5) — no model, repository or seed changes here.*
8. **The snapshot is authoritative for the entries it carries** (D-35), which is how a phone edit
   reaches the wrist without a new message. *Default: yes.*
9. **One plan, four phases, no 3a/3b split** — the governor does not need to create a second plan
   folder. *Default: one plan.*
