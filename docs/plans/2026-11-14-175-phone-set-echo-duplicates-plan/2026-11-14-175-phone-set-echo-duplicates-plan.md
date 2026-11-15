# Feature: Phone set echo duplicates — a set the phone logged is no longer re-imported as a new set every time the wrist reports it back

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
>
> **BUILD ASAP: user-visible duplicate sets.** A real shipping bug, found by plan 172's
> heal-class investigation and confirmed by the governor's scratch probe
> (`docs/plans/2026-11-14-172-heal-class-investigation/2026-11-14-172-heal-class-investigation.findings.md`,
> §4–§6): in a session where BOTH devices logged a set, every sync exchange
> (`WatchSyncOrchestrator.sync(reconnect: true)` → `WatchSyncGraph.sync()` — every
> connect/reconnect and every wrist wake) makes the phone write ONE EXTRA SET into its own
> session. The phone's set count grows without bound; the two devices never settle
> (the sweep's `heal` class: 13 of 2000 seeds, a stable core of five, 4-action shrunk trace).

## Overview

The loop, step by step (all citations verified in this run):

1. The phone holds a set the wrist has not been told about; its projection carries it as
   `entry-<sessionExerciseId>-<n>` (`lib/core/sync_protocol/phone_entries.dart:377`,
   `:457` — D-33's id space). Entries the wrist's staged rows already claim are dropped
   from the projection (D-34, `PhoneEntries.project` `phone_entries.dart:64-88`), so the
   phone's answer carries only the newest unclaimed one.
2. The wrist keeps it and reports it back: both engines' `sessionSnapshot` send `entries`
   = the wrist's own log PLUS the entries the phone sent
   (`lib/watch/session/watch_session_engine.dart:239-296`, the Dart twin; the real Swift
   `WatchSessionEngine.sessionSnapshot`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:281-338`).
   Nothing marks a phone-composed entry as not-the-wrist's.
3. The phone stages the wrist's snapshot entries as wrist news:
   `lib/state/watch/watch_session_inbox.dart`, `_stageable` case
   `'session_snapshot' when envelope['origin'] == 'watch'` (:577-579), `_isStageable`
   (:594-605, only a non-empty id and the kind's required fields), `_entryFor` stamps
   `origin: WatchInboxEntry.originWatch` (:607-621).
4. `WatchSessionImporter` writes it as a new phone set: `_createEntry` →
   `LoggedEntryRows.setObservations` (`lib/core/services/watch_session_importer.dart:1539-1573`,
   called from `_placeEntries` :919 and the user-rows placement :1056). The claim rule
   suppresses only what the projection names; it does nothing to the import. The new
   group's number is one higher; the echoed inbox row claims the *original* group (the
   first unclaimed one with that stamp, `PhoneEntries.resolveClaims`,
   `phone_entries.dart:266-290`), so the duplicate is the one entry left unclaimed — the
   projection mints `entry-<sessionExerciseId>-<n+1>` for it.
5. Back to step 1: one new unclaimed entry exists after every exchange, so the exchange is
   self-sustaining — rows +1 set, inbox +1 row, entry id +1, for ever. The harness's
   `_observableState()` (`test/helpers/watch_pair_harness.dart:1638-1656`) compares each
   session's phone and wrist entry-id sets, so the pair never reaches the fixed point
   `heal()` waits for (`HarnessRunner.heal`, `watch_pair_harness.dart:1554-1615`,
   `healRoundLimit = 10` :1544).

The fix is at the phone's receiver, with no wire change: the phone's inbox refuses to
stage an entry the phone itself minted, and the importer is idempotent for the rows that
were staged before the fix. The wrist's echo is the protocol's own behaviour
(D-17502): the receiverside rule it violates is already written in
`watch/sync_protocol/PROTOCOL.md:539-544` — "a receiver MUST NOT add them back under a
second `entryId`" — and the phone now enforces it.

## Resolved Decisions (Ledger)

**D-17501 — the invariant.** A set logged on the phone appears exactly once on the phone
and once on the wrist; a set logged on the wrist likewise; repeated sync exchanges change
nothing (idempotence), whatever order the devices logged in, and in both directions. The
wrist side already holds: the phone's projection drops claimed groups (D-34,
`phone_entries.dart:64-88`) and the wrist re-states a held id without storing a second row
(D-14606, `WatchSessionEngine.swift:1233-1251` `storeSnapshotEntry` —
`if heldRecord(entryId) != nil` → re-state, not store; twin
`lib/watch/session/watch_session_engine.dart:646-670` `_mergeLateEntries` "union by
`entryId` … keeps a re-stated set from doubling"). The one asymmetry is the documented
same-millisecond benign under-projection (`phone_entries.dart:264-275`) — unchanged by
this plan.

**D-17502 — no wire change; the wrist keeps echoing.** `session_snapshot.entries` keeps
the meaning `watch/sync_protocol/PROTOCOL.md:539-544` gives it: the entries its sender
logged/holds; a receiver MUST NOT add them back under a second `entryId`, and a snapshot
naming an `entryId` the receiver already holds MUST NOT store a second row (PROTOCOL.md
:545-556). Both engines keep producing snapshots that carry phone-composed entries —
Swift `sessionSnapshot` (`WatchSessionEngine.swift:322-338`, `entries` getter :288) and
the twin (:246-296) — and both engines keep matching the reconciliation fixtures and the
replay corpus. PROTOCOL.md is NOT edited: the rule is already correct; the phone simply
did not implement it. (Derived interpretation, vetoable: the wrist's `entries` getter is
also what its UI reads — `WatchEffortRating.swift:181`, `WatchMenu.swift:303` — so
filtering there would change what the wrist shows; not done.)

**D-17503 — the discriminator is the D-33 id space, grammar-only.** A wrist-sent entry
whose `entryId` is in the phone's minting shape is the phone's own, by construction: the
phone mints `entry-<sessionExerciseId>-<n>` (`phone_entries.dart:377`, `:457`), and the
wrist never mints that shape — Swift ids come from `UUID().uuidString`
(`WatchSessionEngine.swift:146` `idFactory`, used at :1726, :1766; also
`WatchLoggingState.swift:294`), the production Dart twin from its uuid factory
(`lib/watch/session/watch_session_engine.dart:61-65`), and the harness twin from
`w-entry-<n>` (`test/helpers/watch_pair_harness.dart:1011` `nextWristEntryId`). The
predicate lives ONCE, on `PhoneEntries` (`isPhoneEntryId`), mirroring the parse
`WatchSessionImporter._phoneEntry` already does (`watch_session_importer.dart:1343-1373`):
`entry-` prefix, a non-empty body, a `-<digits>` tail. Both call sites (inbox, importer)
read the one predicate — implementations of one rule can never diverge (parity invariant).
Rejected alternative — resolving the id against existing phone rows (`_phoneEntry`-style
existence check): it resurrects a deleted group. The phone re-mints ids after a delete
(D-113.3's comment, `WatchSessionEngine.swift:1222-1227`: "deleting the newest set of a
slot and logging another reuses its id"); a phone that deleted group n and logged nothing
new still gets the old id echoed — an existence check would find no group and import the
echo as a resurrection; grammar-only refuses it. Rejected alternative (a) — the wrist
stops echoing: a wire-semantics change touching both engines, the reconciliation fixtures
and the replay corpus (`watch/sync_protocol/fixtures/`), violating the owner's no-wire-
change rule, and not protecting pairs where an already-installed watch keeps echoing.

**D-17504 — the inbox refuses to stage a phone-minted id.** `WatchSessionInbox._isStageable`
(`watch_session_inbox.dart:594-605`) gains `PhoneEntries.isPhoneEntryId(entryId)` as its
first refusal, so it covers BOTH stageable sources: watch `session_snapshot` entries
(:577-579) and `observations_up` events (:574-575). A refused entry is not staged, not
imported, not receipted. Safe because the wrist stores phone-snapshot entries as
confirmed at apply time — Swift `_ = await confirmObservations(entryMaps.compactMap …)`
(`WatchSessionEngine.swift:712-713`), twin
`await confirmObservations([for (final entry in entryMaps) …])`
(`watch_session_engine.dart:637-639`) — so there is no receipt debt and no re-send for
the live path. `stagePhoneChanges` (:352-380) is untouched: the phone's own corrections
and deletions are built there directly with `originPhone` and never pass `_isStageable`.
Known wart (bounded, no growth): the D-14605 late-merge path
(`WatchSessionEngine.swift:733-746`, twin `:646-670`) stores phone entries into an ended
wrist session WITHOUT confirmation, and after the fix the phone never receipts them, so
the wrist may re-send those few `observations_up` events for ever — refused each time,
nothing written. Owner to confirm (A-175-4).

**D-17505 — the importer is idempotent for durable rows staged before the fix.** A staged
effort-kind row (`set`/`timed`/`round`/`hold`, `originWatch`) whose `entryId` is
phone-minted is materialised as nothing, marked applied, and receipted (`_wristIds`
already receipts every row the pass marks applied, `watch_session_importer.dart:485-488`).
Filter point: the `entries` parse filter in `WatchSessionImporter.apply` (:193-197) and in
`_mergeHeld` (:382-386). Rationale: a phone killed between staging and settle leaves
unapplied echo rows; `WatchSessionInbox.resume` (`watch_session_inbox.dart:292-302`)
would otherwise write one last duplicate on upgrade. Rows the pre-fix loop already
applied are tombstones and never re-materialise (module doc :13-15).

**D-17506 — existing damage stays; the growth stops.** No migration, no dedup. Sets the
phone already duplicated remain in history — identical extra sets (same reps, same load,
same stamp) in the session screen, the Session Summary and Stats — and, where the pair
exchanged after them, they were already pushed to and confirmed on the wrist. After the
fix a later sync duplicates them no further: the echo is refused at staging (D-17504) and
durable leftovers are skipped at import (D-17505). Owner to confirm (A-175-3).

**D-17507 — the Swift wrist needs no echo protection.** It already dedupes by entryId
(D-14606, `WatchSessionEngine.swift:1241-1251`) and confirms snapshot entries at apply
(:712). The Swift-side deliverable is a pinning test: the wrist's snapshot after the
phone logged a set carries the phone-minted ids (the echo is intended wire behaviour),
and applying the phone's snapshot twice stores no second row. Guarded by S-17510.

**D-17508 — the sweep register and ratchets move only as measured.** The contract test's
`knownClasses['heal']` text (`test/watch_convergence_random_test.dart:240-243`) is
rewritten with the re-measured standing heal count after the fix — expected 0 of 2000 in
both sweeps and the kill sweep, with the stable five `[209, 270, 316, 899, 1662]`
converging on isolated replay. The entry STAYS in `knownClasses` (the test asserts
`knownClasses.keys.toSet() == kKnownKinds`, :276-280) with the new standing count as its
text; it is removed only if `_kindsOf`'s vocabulary changes, which it does not. The
ratchets — `shippingRatchet = (kSeedCount * 6 / 200).ceil()` (:232-235) and
`phoneKillRatchetPer200 = 10` (:341-344) — already exclude `heal` from their counts
(:285-289, :395-399): they move DOWN only if a re-measure shows a non-heal class shrank,
and are never raised.

**D-17509 — the replay corpus gains one echo source; existing recordings are untouched.**
No checked-in recording is regenerated (the fix changes no engine output; both engines
already echo identically). One new source `trace-echo` is added to `kCorpusSources`
(`test/watch_replay_corpus_test.dart:142`), whose steps guarantee a wrist snapshot AFTER
the phone logged a set, so the corpus pins that both engines produce identical
echo-carrying snapshots — a future wrist-side "fix" that filters them breaks the corpus
loudly instead of diverging silently. The new source's recording is written once by the
governor with `--dart-define=REPLAY_CORPUS_WRITE=true` (D-15209), never by an implementer.

## Feature Invariants

- A set logged on the phone appears exactly once on the phone and once on the wrist;
  repeated sync exchanges change nothing (D-17501, guarded by S-17501, S-17505…S-17507).
- The phone never materialises an entry whose id it minted (D-17503/D-17504/D-17505;
  guarded by S-17502, S-17503, S-17504, S-17511).
- The id-space rule lives once, on `PhoneEntries`; the inbox and the importer read the
  same predicate (parity; guarded by S-17502/S-17504 both passing against the one
  symbol).
- The wire is unchanged: both engines' snapshots, the reconciliation fixtures and the
  replay corpus keep matching (D-17502/D-17509; guarded by S-17509, S-17510).
- Everything the import marks applied is receipted (existing rule,
  `watch_session_importer.dart:244`, `:439`; unchanged by the filter — the filtered rows
  stay in `unapplied` and are named).

## Requirements

1. A wrist `session_snapshot` or `observations_up` entry whose `entryId` is phone-minted
   is never staged by `WatchSessionInbox` (D-17504).
2. A staged effort-kind row whose `entryId` is phone-minted is never materialised by
   `WatchSessionImporter`, is marked applied and is receipted (D-17505).
3. The four-action echo trace converges: bounded heal, phone set rows constant across
   exchanges, both logging orders, each device killed and relaunched in between, and a
   wrist-two/phone-one variant (S-17501, S-17505…S-17507).
4. The sweep's `heal` class falls to zero at 2000 seeds in all three sweeps, or its
   standing count is recorded and never raised (D-17508, S-17508).
5. Existing suites stay green; no checked-in replay recording is regenerated; the new
   corpus source is recorded by the governor (D-17509, S-17509, S-17510).
6. Docs name the new rule where they name the old behaviour (docs delta, Phase 5).

## Acceptance Criteria

- S-17501 passes (was red at HEAD — proven with the gateway's `prove-red` before Phase 2).
- S-17502…S-17504, S-17511 pass (new unit rules).
- S-17505…S-17507 pass (harness loop variants).
- S-17508's replay of `[209, 270, 316, 899, 1662]` converges; the 2000-seed sweeps'
  heal bucket is re-measured and recorded.
- S-17509: `test/watch_session_projection_test.dart`, `test/watch_session_import_test.dart`,
  `test/watch_session_merge_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`,
  `test/watch_replay_corpus_test.dart`, and the three convergence suites all pass
  unchanged (except the new tests).
- S-17510: the Swift pin passes (`swift test` in `watch/watchos`), and the corpus's
  `trace-echo` re-records identically on the Dart twin.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect of the change | Guarded by |
|---|---|---|---|
| `PhoneEntries`' id space (D-33, `phone_entries.dart:377`, `:457`) | Readers: `WatchSessionImporter._phoneEntry` (`watch_session_importer.dart:1343`, grep `_phoneEntry`), `WatchSessionAdoptionBridge`'s claim read (grep `PhoneEntries.` → `lib/state/watch/watch_session_adoption_bridge.dart`), the inbox (new) | One static predicate added; projection untouched | S-17502, S-17509 |
| `WatchSessionInbox._isStageable` / `_stageable` (`watch_session_inbox.dart:565-605`) | Sole caller `WatchSessionInbox.receive` (:254, grep `_stageable`); `_settle` consumes what was staged | Refuses phone-minted ids from both stageable sources; `stagePhoneChanges` (:352-380, grep `stagePhoneChanges`) is a separate path with `originPhone` and is untouched | S-17502, S-17503 |
| `WatchSessionImporter.apply` / `_mergeHeld` entry filters (`watch_session_importer.dart:193-197`, `:382-386`) | Callers: `WatchSessionInbox._settleNow` (grep `apply(` → `watch_session_inbox.dart:503` area), `resume` (:292-302); tests `test/watch_session_import_test.dart`, `test/watch_session_merge_test.dart` | Phone-minted staged rows are filtered from `entries`/`live` before placement; still marked applied and receipted | S-17504 |
| Nutrition quick-logs | `watch_session_inbox.dart:563-565` ("Nutrition quick-logs are the nutrition bridge's alone"); `WatchNutritionLogBridge` builds its own ids (`watch_nutrition_log_bridge.dart:104-111`) and its own receipts | Unaffected — nutrition never passes `_stageable` | S-17509 |
| Phone corrections/deletions of wrist entries | `stagePhoneChanges` maps `correct_entry`/`delete_entry` to `kindPhoneCorrection`/`kindPhoneDeletion` with `originPhone` (:368-380) | Unaffected — does not pass `_isStageable`; ids are `phone-change-*` (`models.dart:2946`) | S-17509 |
| Phone-minted ids whose group the phone deleted | D-113.3's reuse rule (`WatchSessionEngine.swift:1222-1227`) | Grammar-only refusal: no resurrection (an existence check would resurrect) | S-17511 |
| The harness's `_sampleEntries` (`watch_pair_harness.dart:1429-1497`) | Reads inbox ids, mirror/projected entries, wrist store, snapshot frames | After the fix the phone's inbox holds no echo rows; phone and wrist id sets match and `heal()` reaches its fixed point | S-17501, S-17505 |
| The replay corpus and reconciliation fixtures | `test/watch_replay_corpus_test.dart` (D-15208/D-15209), `fixtures/reconciliation/phone_entries_merge.json` | Existing recordings unchanged (no engine output change); one new source added | S-17509, S-17510 |
| The sweep register and ratchets | `test/watch_convergence_random_test.dart:240-243` (heal entry), `:232-235` (shippingRatchet), `:341-344` (phoneKillRatchetPer200) | Heal text rewritten with the re-measured count; ratchets only ever down | S-17508 |
| `WatchLateEntryRecovery.recoverEntriesAppliedSince` (`watch_session_inbox.dart:536-548` doc, D-802/D-804) | `SessionCore.restoreSessionSnapshot` | Unaffected — it un-marks rows the inbox already staged; a refused id was never staged | S-17509 |

## UI Standards Impact

None. No screen, widget or design-system piece changes; the user-visible effect is that
phantom duplicate sets stop appearing (D-17506). Docs/design_system.md is not consulted
for a behaviour-only change with no UI.

## Scenarios

### S-17501: the four-action echo trace adds no set (both orders)
- Fixture: a fresh pair. Phone-first order: `PhoneStartsSession`, `TimeAdvances(5)`,
  `PhoneLogsSet`, `WristLogsSet` (`test/helpers/watch_pair_harness.dart:500`, `:644`,
  `:508`, `:562`). Wrist-first order: the same with `WristLogsSet` before
  `PhoneLogsSet`. Exactly one set per device; no other entries; no kills.
- Trigger: `HarnessRunner.heal()` (the app's own connect path:
  `clock.advance(31 s)`, `noteClockGrid()`, `drainQueues()`,
  `wristOrchestrator.sync(reconnect: true)`, `graph.sync()`, `settle()`, one wrist
  `energy_live` — `watch_pair_harness.dart:1554-1615`), repeated; then three more
  explicit exchanges of `sync(reconnect: true)` + `graph.sync()` + `settle()`.
- Flow: after the trace, read the phone's set rows for the logged effort
  (`EntryRows.setGroups(await repository.getEffortObservations(<slot id>))`,
  `lib/core/utils/entry_rows.dart`); run the exchanges; read again.
- Expected outcome: `heal.converged` true within `healRoundLimit` (10); the phone's set
  group count for the effort is 2 (one phone set + one wrist set) before and after every
  exchange — constant; the phone's inbox holds no row whose `entryId` starts `entry-`.
  Red at HEAD (today: +1 group per exchange, `healConverged=false`).
- Edge case of: none (the class's own root scenario).

### S-17502: a wrist snapshot carrying a phone-minted id stages only the wrist's own
- Fixture: the inbox's repository with nothing staged; a watch `session_snapshot`
  envelope whose `payload.entries` = one watch-minted `set` entry (`entryId:
  'w-entry-1'`, all required fields per `WatchSessionInbox._requiredFields`) and one
  phone-minted `set` entry (`entryId: 'entry-<sessionExerciseId>-1'`, same shape); a
  near-twin of the phone-minted one with a DIFFERENT id tail (`entry-…-2`) as a second
  copy.
- Trigger: `WatchSessionInbox.receive(envelope)` (`watch_session_inbox.dart:249-289`).
- Flow: `_stageable` → `_isStageable` → `_entryFor` → `stageWatchInboxEntry`.
- Expected outcome: only `w-entry-1` is staged (`WatchInboxResult.stagedEntryIds ==
  ['w-entry-1']`); the two `entry-…` rows exist nowhere in the inbox; outcome `staged`.
- Edge case of: S-17501.

### S-17503: an `observations_up` event with a phone-minted id is refused too
- Fixture: a watch `observations_up` envelope whose `payload.events` carry one
  watch-minted set and one phone-minted set (same shapes as S-17502).
- Trigger: `WatchSessionInbox.receive(envelope)`.
- Expected outcome: only the watch-minted event is staged; the phone-minted one is
  neither staged nor receipted.
- Edge case of: S-17502.

### S-17504: a durable pre-fix staged row is marked applied and materialises nothing
- Fixture: the inbox's repository holding an unapplied `originWatch` `set` row whose
  `entryId` is `entry-<sessionExerciseId>-1` for a session the phone holds as its own
  (adoption: `phoneOwnsSession: true`), the session's efforts already holding a group
  numbered 1, plus a `session_end` row (completed).
- Trigger: `WatchSessionImporter.apply(sessionId, phoneOwnsSession: true)` →
  `_mergeHeld` (`watch_session_importer.dart:288-445`).
- Expected outcome: no new observation row is written (the effort's observation count and
  `EntryRows.setGroups` are unchanged); the row's `appliedAtMs` is set; the returned
  `WatchSessionImport.appliedEntryIds` names it (receipted, D-17505). Same assertion for
  the history-import path (`phoneOwnsSession: false`, `apply` :167-254) with a
  wrist-origin session whose `entries` filter would otherwise materialise the id.
- Edge case of: S-17502.

### S-17505: the echo loop converges — the five shrunk seeds
- Fixture: `ConvergenceRun.replayActions` of the shrunk traces, or plain
  `ConvergenceRun.runSeed(seed)` for seeds 209, 270, 316, 899, 1662 (the stable core,
  findings §2).
- Trigger: the run's heal, bounded at 10 rounds.
- Expected outcome: `healConverged=true` for every seed; the phone's set-row count for
  each session's efforts equals the logged sets (one per device) after the heal.
- Edge case of: S-17501.

### S-17506: the loop stays converged across a kill of each device
- Fixture: S-17501's phone-first trace, then `PhoneKilledAndRelaunched`
  (`watch_pair_harness.dart:636`) before the exchanges; a second run with `WristKilled`
  (:621) instead.
- Trigger: the same exchanges as S-17501 after the kill.
- Expected outcome: set-row count constant across the exchanges in both runs; heal
  converges; no phone-shaped inbox row.
- Edge case of: S-17501.

### S-17507: wrist logs two, phone logs one — three-entry variant
- Fixture: `PhoneStartsSession`, `TimeAdvances(5)`, `WristLogsSet`, `WristLogsSet`,
  `PhoneLogsSet`.
- Trigger: heal + three exchanges.
- Expected outcome: the phone's effort holds 3 set groups (two imported once from the
  wrist, one the phone's own) before and after every exchange; the wrist holds 3; heal
  converges.
- Edge case of: S-17501.

### S-17508: the sweep's heal class is re-measured after the fix
- Fixture: the sweep itself at `CONVERGENCE_SEEDS=2000`, three runs (random traces,
  contract, kill), exactly the commands of findings §8.
- Trigger: the re-measure.
- Expected outcome: the heal-only lists are empty in all three (record whatever is
  measured in the evidence file); the register's `heal` entry states the new standing
  count; the ratchets are untouched unless a non-heal class shrank. The five stable
  seeds converge on isolated replay (S-17505's assertion covers them).
- Edge case of: S-17505.

### S-17509: the existing suites stay green
- Fixture: the repo as Phase 2 left it.
- Trigger: the focused suites named in Acceptance Criteria plus `gateway.sh lint` and the
  full `gateway.sh test`.
- Expected outcome: all green; no checked-in replay recording regenerated; the
  projection tests (S-31…S-143) unchanged and passing.
- Edge case of: none.

### S-17510: the echo is pinned as intended wire behaviour on both engines
- Fixture: a Swift test session where the phone's snapshot delivered a set to the wrist;
  the corpus source `trace-echo` (steps: `phoneStart`, `advance 3`, `phoneLog`,
  `wristLog`, `drop`, `rise`, `advance 31`, `wristFinish` — every step name exists in
  `_Step.run`, `test/watch_replay_corpus_test.dart:61-104`).
- Trigger: the Swift engine's `sessionSnapshot` after the phone's snapshot applied; the
  corpus test's fresh re-recording of `trace-echo` on the Dart twin.
- Expected outcome: the Swift snapshot's `entries` carry the phone-minted id (echo,
  D-17502), and applying the phone's snapshot a second time stores no second
  observation row (D-14606 already, now pinned); the corpus file re-records byte-equal.
- Edge case of: S-17509.

### S-17511: a phone-minted id whose group the phone deleted is never resurrected
- Fixture: the phone's session whose effort held group 1 (id `entry-<slot>-1`) and the
  group was deleted (no group numbered 1 remains); a staged `originWatch` `set` row with
  that id, unapplied.
- Trigger: `apply`/`_mergeHeld` as in S-17504.
- Expected outcome: nothing written, row marked applied and receipted — the
  grammar-only rule refuses it where an existence check would have re-created the set
  (D-17503's rejected alternative).
- Edge case of: S-17504.

## Iteration 1

### Phase 1: the red tests (@developer)
1. [ ] Add the scripted echo-loop test — `test/watch_convergence_harness_test.dart` ·
  new `test('S-17501 the echo loop adds no set (phone first)')` and its sibling
  `(wrist first)`: the S-17501 fixture/trigger/outcome verbatim, reading set rows with
  `EntryRows.setGroups(await repository.getEffortObservations(...))`
  (`lib/core/utils/entry_rows.dart`)
2. [ ] Add the kill variants — same file · `test('S-17506 the echo loop survives a phone
  kill')`, `test('S-17506 the echo loop survives a wrist kill')` using
  `runner.phoneKilledAndRelaunched()` / `runner.wristKilled()`
3. [ ] Add the three-entry variant — same file · `test('S-17507 wrist logs two, phone
  one')`
4. [ ] Add the inbox/importer unit tests — `test/watch_session_import_test.dart` ·
  `S-17502`, `S-17503` (one group "the echo is not staged"), `S-17504` and `S-17511`
  (one group "a phone-minted staged row is not materialised") — construct
  `WatchSessionInbox`/`WatchSessionImporter` as the file's existing groups do
5. [ ] Add the seed replay — `test/watch_convergence_random_test.dart` ·
  `test('S-17505 the healed seeds converge')`: for seed in [209, 270, 316, 899, 1662],
  `ConvergenceRun.replayActions` of the four-action trace and `runSeed(seed)` both
  report `healConverged=true`
6. [ ] Prove red at HEAD — gateway ·
  `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test --plain-name "S-17501"`
  (and the S-17502/S-17504 plain-names): S-17501 and the unit tests FAIL at HEAD with
  the test files carried over; paste the failing counts into the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`
(compare with the plan baseline's issue count); the new tests red at HEAD via `prove-red`;
Progress and Assumption Log updated.
**Predicted Files**: `test/watch_convergence_harness_test.dart`,
`test/watch_session_import_test.dart`, `test/watch_convergence_random_test.dart`,
`docs/plans/2026-11-14-175-phone-set-echo-duplicates-plan/2026-11-14-175-phone-set-echo-duplicates-plan.evidence.md`.
**Phase 1 verification notes (Conductor, date):** —
### Phase 1.Y: remediation — BLOCKS Phase 1 closure (opened only if `prove-red` cannot run the named plain-names; record the exact denial under Assumption Log instead of re-running)

### Phase 2: the fix (@developer)
1. [ ] Add the one predicate — `lib/core/sync_protocol/phone_entries.dart` ·
  `PhoneEntries.isPhoneEntryId(String entryId)`: `entry-` prefix, non-empty body,
  `-<digits>` tail (the parse `_phoneEntry` uses, `watch_session_importer.dart:1343-1373`),
  doc comment citing D-33, D-17503 and S-17511's deleted-group rationale
2. [ ] Refuse at staging — `lib/state/watch/watch_session_inbox.dart` ·
  `_isStageable` (:594): return false when `PhoneEntries.isPhoneEntryId(entryId)`; import
  `../../core/sync_protocol/phone_entries.dart`
3. [ ] Filter the merge path — `lib/core/services/watch_session_importer.dart` ·
  `_mergeHeld`'s `entries` list build (:382-386): drop rows whose
  `PhoneEntries.isPhoneEntryId(entryId)`; they stay in `unapplied` (marked applied,
  receipted by `_wristIds`)
4. [ ] Filter the import path — same file · `apply`'s `entries` list build (:193-197):
  the same drop, same receipt behaviour
5. [ ] Turn the red tests green — run Phase 1's suites; S-17501…S-17504, S-17511,
  S-17505 all green; paste pass/fail counts into the evidence file

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test --plain-name "Mock"`-led focused runs of
`test/watch_session_import_test.dart`, `test/watch_session_projection_test.dart`,
`test/watch_session_merge_test.dart` (Mock-first; Hive groups seeded in `setUp`);
`test/watch_convergence_harness_test.dart`; Phase 1's seed test. Mock-first, persisting
taps Mock-only (docs/global_conventions.md).
**Predicted Files**: `lib/core/sync_protocol/phone_entries.dart`,
`lib/state/watch/watch_session_inbox.dart`,
`lib/core/services/watch_session_importer.dart` (test files only via green runs).
**Phase 2 verification notes (Conductor, date):** —
### Phase 2.Y: remediation — BLOCKS Phase 2 closure

### Phase 3: the sweep re-measure and the register (@developer)
1. [ ] Re-measure at 2000 — gateway · the three commands of findings §8
   (`S-14509 the random seeds`, `S-14509 every random seed converges`, `S-16310`) with
   `--dart-define=CONVERGENCE_SEEDS=2000`; paste the heal-only lists and class counts
   into the evidence file (exit 124 = timed out: report, never re-run unchanged)
2. [ ] Rewrite the register's heal entry — `test/watch_convergence_random_test.dart` ·
   `knownClasses['heal']` (:240-243): the measured standing count (expected: 0 of 2000 in
   all three sweeps; the stable five converge), keeping the key (the
   `knownClasses.keys.toSet() == kKnownKinds` assert :276-280 must keep passing)
3. [ ] Leave the ratchets unless measured lower — same file · `shippingRatchet` (:232-235)
   and `phoneKillRatchetPer200` (:341-344) change only if a non-heal class's re-measured
   count is lower; never raise; record the decision in the evidence file
4. [ ] Full convergence suites green — gateway · `test` over
   `test/watch_convergence_harness_test.dart`, `test/watch_convergence_kill_test.dart`,
   `test/watch_convergence_random_test.dart` at their default 200 seeds, plus
   `test/watch_reconciliation_cross_stack_test.dart` and
   `test/watch_replay_corpus_test.dart`

**Done Criteria** (run until green): the three 2000-seed runs recorded (governor-scale;
the sweep's own `timeout: 20 minutes` exceeds the gateway's 900 s `test` check — if a
2000-seed run times out, record the 200-seed result and list the 2000-seed re-measure
under Governor actions); lint; the suites above green.
**Predicted Files**: `test/watch_convergence_random_test.dart` (register text only),
evidence file.
**Phase 3 verification notes (Conductor, date):** —
### Phase 3.Y: remediation — BLOCKS Phase 3 closure

### Phase 4: the Swift pin and the corpus source (@developer; watch track)
1. [ ] Pin the echo on the Swift engine —
   `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` · new
   `testS17510TheWristSnapshotCarriesThePhoneComposedEntries`: phone snapshot with a
   `entry-…` set applied twice; assert the wrist's `entries` hold it once under its id
   (no second row — D-14606) and `sessionSnapshot`'s `entries` carry the phone-minted id
   (D-17502, S-17510)
2. [ ] Add the corpus source — `test/watch_replay_corpus_test.dart` · `kCorpusSources`
   (:142): `_Source('trace-echo', kind: 'trace', steps: [phoneStart, advance 3,
   phoneLog, wristLog, drop, rise, advance 31, wristFinish], tags: ['entry',
   'frame-prefix'])`
3. [ ] Verify the Swift pin — gateway · `.github/copilot/scripts/macos/gateway.sh
   swift-test`

**Done Criteria**: `swift-test` green; the corpus test green for every EXISTING source
(the new source is red until the governor records it — see Governor actions; do not run
`REPLAY_CORPUS_WRITE=true` yourself).
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
`test/watch_replay_corpus_test.dart`,
`watch/sync_protocol/fixtures/replay/trace-echo.json` (governor),
`watch/sync_protocol/fixtures/replay/manifest.json` (governor, if the manifest lists
sources explicitly).
**Phase 4 verification notes (Conductor, date):** —
### Phase 4.Y: remediation — BLOCKS Phase 4 closure

### Phase 5: docs delta and residue sweep (@developer)
1. [ ] Update the capture doc — `docs/watch_session_capture.md` · the Structure row
   "Staging what a wrist sends" plus one Rationale paragraph: what is staged now
   excludes entries the phone itself minted (D-17503/D-17504), with the S-17502/S-17504
   test names. Current size 40.3 KB (measured 2026-11-14) — the delta is a few hundred
   bytes; state the new size in the evidence file
2. [ ] Update the sync doc — `docs/watch_session_sync.md` · the Structure row "Merging a
   wrist's set into the session the phone holds" gains the receiver rule (PROTOCOL.md
   :539-544 enforced at the phone; no wire change, D-17502). Current size 45.1 KB — same
   band note
3. [ ] Check the surface doc — `docs/state_management/watch_surface.md` · grep it for a
   description of `_isStageable`/staging semantics; update ONLY if it describes the old
   behaviour (it names the inbox as a graph component at :547 — likely no change)
4. [ ] Residue sweep — grep proving zero readers treat a phone-minted snapshot id as
   wrist news: `grep -n "isPhoneEntryId" lib/ test/` (the one predicate, its two
   readers, its tests) and `grep -n "originWatch" lib/state/watch/` (no new consumer of
   the old staging behaviour); paste both into the evidence file
5. [ ] Final gate — gateway · `lint`, full `test` (900 s), `swift-test`; docs index
   green (`test/docs_indexing_contract_test.dart`)

**Done Criteria**: lint (issue count at or under the baseline), full `test` green,
`swift-test` green, residue greps pasted, Progress complete.
**Predicted Files**: `docs/watch_session_capture.md`, `docs/watch_session_sync.md`,
possibly `docs/state_management/watch_surface.md`, evidence file.
**Phase 5 verification notes (Conductor, date):** —
### Phase 5.Y: remediation — BLOCKS Phase 5 closure

## Files Affected (whole feature)

- `lib/core/sync_protocol/phone_entries.dart` — adds `PhoneEntries.isPhoneEntryId` (Phase 2)
- `lib/state/watch/watch_session_inbox.dart` — `_isStageable` refusal (Phase 2; readers only otherwise)
- `lib/core/services/watch_session_importer.dart` — `apply`/`_mergeHeld` filters (Phase 2)
- `test/watch_convergence_harness_test.dart`, `test/watch_session_import_test.dart`,
  `test/watch_convergence_random_test.dart` — new tests (Phases 1, 3)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` — the pin (Phase 4)
- `test/watch_replay_corpus_test.dart` — the new source (Phase 4)
- `watch/sync_protocol/fixtures/replay/trace-echo.json` (+ manifest if explicit) — governor
- `docs/watch_session_capture.md`, `docs/watch_session_sync.md`,
  possibly `docs/state_management/watch_surface.md` — Phase 5
- Read-only dependents: `lib/state/watch/watch_session_adoption_bridge.dart` (claim read),
  `lib/core/utils/entry_rows.dart`, the projection tests — untouched, verified green.

## Notes

- **Phase dependency graph.** 1 → 2 → {3, 4} → 5. Phase 4 needs only Phase 2 (the pin
  asserts behaviour the fix does not change, but its red twin would be meaningless
  before the harness exists); it can run beside Phase 3. Phase 5 last.
- **Red at HEAD.** Phase 1's tests are red at HEAD by construction (the bug is live);
  `prove-red` makes that permanent evidence. If the gateway's `test` check cannot carry
  the plain-name filters, record the denial; the falling-back path is the full suite on
  HEAD failing at the new tests.
- **Upgrade path.** An installing phone: staged-but-unapplied echo rows → Phase 2's
  filter materialises nothing and receipts them (D-17505). Applied tombstones are
  already inert. At most one residual duplicate can exist from a kill between staging
  and settle before the upgrade — accepted (D-17506).
- **The wrist's late-merge debt.** D-14605's path stores phone entries unconfirmed into
  an ended wrist session; post-fix they are re-sent for ever and refused for ever.
  Bounded (the entries pushed while the wrist held the ended session), no growth, no
  duplicates — the accepted wart of refusing at staging (D-17504, owner to confirm).
- **Intermediate states.** After Phase 2 but before Phase 3 the register's heal text
  still describes 13/19 stalls — a stale claim, not a failure; Phase 3 rewrites it from
  the re-measure. After Phase 4's source is added but before the governor records it,
  the corpus test is red on the new source only.
- **Legacy handling.** No migration, no dedup, no wire change, no PROTOCOL.md edit.
- **Doc sizes.** `watch_session_capture.md` 40.3 KB, `watch_session_sync.md` 45.1 KB,
  both inside the 52 KB band (rule: `docs/documentation_standard.md`); the deltas are
  small; re-measure at update time and record in the evidence file.

## Progress

- [x] Phase 1 — the red tests (@developer) — 10 tests in 3 files, all proved RED at HEAD
  (S-17502/S-17503/S-17504 history path in `watch_session_import_test`, 5 harness
  cases, 2 seed cases); evidence file §Phase 1.
- [x] Phase 2 — the fix (@developer) — `PhoneEntries.isPhoneEntryId` + three refusals;
  35 changed lines in `lib/`; all 12 plan-175 tests green; mutation B (staging refusal)
  and C (`apply` filter) each turn a witness red, A (`_mergeHeld`) does not — A-175-8.
- [x] Phase 3 — the sweep re-measure and the register (@developer) — 2000 seeds: contract
  1949 converge / 31 shipping divergers / **0 heal stalls**, kill 1906 / 76 / **0 heal
  stalls**; `heal` class retired in the register; ratchets unchanged (A-175-10);
  evidence file §Phase 3.
- [ ] Phase 4 — the Swift pin and the corpus source (@developer) — **Blocked (scope)**:
  the `trace-echo` source is added (`test/watch_replay_corpus_test.dart`) but the corpus
  cannot be re-recorded from this run (`REPLAY_CORPUS_WRITE=true` is denied), and the
  fix leaves 5 existing recordings stale (`trace-s14501`, `trace-f7`, `trace-a2`,
  `seed-408`, `seed-857`), so `S-15202/S-15204/S-15207` are red until then. The Swift
  pin was not written: `WatchSessionEngineTests.swift` is owned by the parallel plan-173
  run (its working-tree diff) and the standing rule forbids touching it. Both are
  governor actions — see the handoff.
- [x] Phase 5 — docs delta and residue sweep (@developer) — capture and sync docs
  updated (`watch_surface.md` checked, no change required: it names the inbox as a graph
  component, never the staged ids); both residue greps clean; lint 181 = baseline; docs
  index and UI-standards contract tests green in the final full run except the corpus
  failures above.

## Open Items (added by the developer, plan 175)

1. Governor: re-record the corpus — `flutter test --dart-define=REPLAY_CORPUS_WRITE=true test/watch_replay_corpus_test.dart`
   (6 files: the 5 the fix leaves stale plus the new `trace-echo`).
2. Governor: the Swift pin `testS17510…` in `WatchSessionEngineTests.swift`, after plan 173's diff lands (A-175-11).
3. Governor: confirm `trace-echo`'s recorded tags include what it declares, after the re-record.
4. Pre-existing flake, not plan 175: `logger_feedback_controls_test.dart` `S-5115 … rolling list view`
   fails under load (green alone and at HEAD); leave it to its owner.

## Assumption Log

- A-175-1 Unit-test home: the inbox/importer tests go to
  `test/watch_session_import_test.dart` (options: a new file, the merge test file;
  choice: the file the existing staging groups live in per plan 42a's caller grep).
  Implementer may re-home to an existing closer group — record here if so.
- A-175-2 PROTOCOL.md is not edited (D-17502): the receiver rule at :539-544 is already
  exact; the plan treats the phone's old behaviour as a bug, not an underspecification.
  Owner to confirm.
- A-175-3 No migration for duplicated history (D-17506). Owner to confirm.
- A-175-4 The late-merge receipt debt is accepted as a bounded wart (D-17504). Owner to
  confirm.
- A-175-5 `trace-echo`'s steps chosen by the planner; the governor records it. Owner to
  confirm the step list.
- A-175-6 The harness tests read phone set rows via
  `repository.getEffortObservations` + `EntryRows.setGroups` (mechanic; any equivalent
  read is fine).
- A-175-7 The gateway's `test` check accepts `--plain-name`/`--dart-define` args (the
  findings' §8 runs show exactly such commands through the gateway). If refused, the
  2000-seed re-measures become Governor actions. — **Confirmed:** all three re-measure
  commands ran through the gateway inside the 900 s `test` check.
- A-175-8 The `_mergeHeld` filter is defence in depth, not a red witness: with the
  staging refusal in place nothing phone-minted reaches the held merge, and forcing the
  filter true leaves all 12 tests green. Kept because a durable pre-fix staged row can
  still arrive that way (D-17505); no test distinguishes it, and none pretends to.
- A-175-9 S-17511 reshaped: group 1 is retained and the echo asks for a deleted group 2.
  The original wording (a phone-minted id whose whole group the phone deleted) could not
  fail at HEAD — with no group 1 the snapshot was already empty — so it proved nothing.
- A-175-10 The register's `heal` class is retired in place (text rewritten to the
  measured 0) rather than removed from `knownClasses`, because the suite asserts
  `knownClasses.keys == kKnownKinds`; deleting the key would redden an unrelated assert.
- A-175-11 Phase 4 split: the Swift pin is left to the governor because
  `WatchSessionEngineTests.swift` carries the parallel plan-173 run's diff, and the
  corpus re-recording needs `REPLAY_CORPUS_WRITE=true`, which this run's policy denies.
  The `trace-echo` source itself is added now so one re-record covers all six files.

## Feedback

- **Phase 4 cannot close in this run.** The `trace-echo` source is added, but the corpus
  needs re-recording (`REPLAY_CORPUS_WRITE=true` is denied to this run's shell — a
  governor action), and the fix additionally leaves five existing recordings stale
  (`trace-s14501`, `trace-f7`, `trace-a2`, `seed-408`, `seed-857`), which the plan did not
  foresee: they encode the bug (one extra phone set minted from the wrist's echo per
  exchange). The Swift pin was not written because `WatchSessionEngineTests.swift` carries
  the parallel plan-173 diff. Both are in Open Items; re-plan or hand to the governor.

