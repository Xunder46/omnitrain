# Feature: Plan 160 — the watch's own finished workout reaches the phone (O-6)

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md · docs/watch_session_sync.md · docs/watch_session_capture.md · watch/sync_protocol/PROTOCOL.md
> Supersedes: plan 152's A-152a (D-15211) — see D-16006

## Overview

O-6 (the owner's story, decided 2026-11-14): two workouts open at once, one per device —
the link was down when each side started its own. Both finish independently. The
phone's own workout stays open and is never touched; the watch's workout is saved on
the phone as its OWN finished workout, with its calendar entry, its sets and its time
span. The watch keeps its own Apple Health workout. Nothing is deleted. No new phone
notice, dialog or choice.

The phone side is already built and green: `WatchSessionImporter.apply` turns a staged
wrist-origin `session_end` plus the staged sets into the wrist's own finished
`TrainingSession` row (`test/watch_session_import_test.dart`, group `O-6 the wrist's
own workout is its own finished row` :985-1091 — RED-proof exists as a passing test).
The real wrist (Swift) already produces the end: `captureSessionEnd` /
`sessionEndEvent` (`WatchSessionEngine.swift:2029-2115`), called from all three paths
that end a held session (:664 snapshot, :934 lifecycle, :1553 the wrist's own
finish/discard).

The gap is the Dart twin — the reference engine the convergence harness runs. It
never stores or emits a `session_end` observation: `WatchObservationKind`
(`lib/watch/session/watch_records.dart:58-96`) has no `sessionEnd` constant, no
capture hook exists anywhere under `lib/watch/` (grep
`captureSessionEnd|WatchObservationKind.sessionEnd|sessionEndId` → nothing), and plan
152 recorded exactly this as known asymmetry A-152a. So
`test/watch_convergence_harness_test.dart` S-14660 (:837-975, currently `skip:`) — the
harness trace of the owner's story — is red-and-skipped: the wrist's terminal
lifecycle supersedes its queued snapshot, the inbox stages no `session_end` row, and
the importer has nothing to import (plan 146c's Open Items, :588-594).

The answer to the brief's "smallest wire change" question is **option (c): the
existing `session_end` observation carries everything** — the change is Dart-twin
parity, not a wire change. No schema, no fixture, no version, no phone code. Phase
order: twin → replay parity → the harness proof → docs.

## Resolved Decisions (Ledger)

| ID | Decision | Backing |
|---|---|---|
| D-16001 | **No wire change.** The smallest change is option (c): the existing `session_end` event kind — added to `observations_up` by the 2026-09-25 protocol amendment (`PROTOCOL.md:893`) — already carries everything O-6 needs (`startedAt`, `endedAt`, `status` required; `modality`, `followed`, the summary fields optional, `watch/sync_protocol/schemas/messages/observations_up.schema.json:83-84`, `envelope.schema.json:302-340`). The defect is that the Dart twin never produces one (A-152a). The phone needs nothing: the O-6 importer test is green at HEAD. No schema, no fixture, no protocol version, no `PROTOCOL.md` edit — only what is accepted stays exactly as it is; a client that never produced a described frame starts producing it | plan 146c Open Items :588-594; O-6 test green; A-152a (plan 152 D-15211) |
| D-16002 | **Twin capture contract — three sites, before the terminal row, Swift's guards.** The twin captures a `session_end` observation exactly where Swift does, and always BEFORE the row that records the new status (`docs/watch_session_capture.md:493`): (1) the wrist's own finish/abandon in `_transitionTo` — only when `status != null`, after the rest stop (`WatchSessionEngine.swift:1552-1555`); (2) a phone snapshot that ends the held session, with the row's status and `recordedAt` (:655) — only on the row-writing path, never on the `_mergeLateEntries` path; (3) a phone lifecycle `completed`/`abandoned`, with the payload's `at` (:934). Guards, in order, exactly Swift's `captureSessionEnd` (:2029-2033): the status is terminal; a **creation row already exists** for the session — the first row stored before this write (`creationRow`, :2152-2159: a first-hearing snapshot that arrives already finished captures nothing, because the phone already holds the whole session); no end is held yet | `WatchSessionEngine.swift:2029-2045, 655, 934, 1552-1555, 2152-2159`; `watch_session_engine.dart` `_transitionTo` :1431-1466, `_applySnapshot` :596-609, `_applyLifecycle` :837-853; `docs/watch_session_capture.md:493` |
| D-16003 | **Event shape.** `entryId` = `eventId` = `end-<sessionId>` (Swift `WatchSessionCapture.sessionEndId`, `WatchRecords.swift:100`); `kind` `session_end`; `loggedAt` = the twin's clock now; `startedAt` = the creation row's `startedAt`, `endedAt` = the end instant, both written through the wire instant (the `utcIso` of the parsed instant — Swift's `wireInstant`, `WatchSensorSummaries.swift:298`); `status` = the terminal status; `followed: true` when the creation row's source is not `watch` (Swift :2073 — a session the phone started and the wrist followed); `modality` when the creation row carries a non-empty one. **No summary fields**: the twin computes no heart-rate/energy summaries (Swift's `WatchSensorSummaries` has no Dart counterpart); every summary field is optional on the wire ("absent means not measured, never zero", `envelope.schema.json:315-340`) and the importer treats each as optional | `WatchSessionEngine.swift:2051-2115`; `envelope.schema.json:302-340`; `watch_session_importer.dart` summary attach (S-261 family) |
| D-16004 | **Idempotence (brief Q2).** The end's id is the session's, so no end is ever re-emitted with different values: the capture guard refuses a second one (Swift's `knowsObservation` :2160-2163; the twin's `_heldRecord('end-'+sessionId)`, `watch_session_engine.dart:1167`). Delivery side: the phone stages put-if-absent by `entryId` (`watch_session_inbox.dart` `_stageable`), the importer tombstones applied entry ids, and a redelivered end is consumed with no second row — pinned today by `test/watch_session_import_test.dart` group `S-263 redelivery` :609 | `WatchSessionEngine.swift:2029-2033, 2160-2163`; plan 156 evidence :106 ("stored once, never re-emitted with different values") |
| D-16005 | **Catch-up re-offer covers every session (brief Q2).** The twin's `pendingObservations()` re-offers every unconfirmed observation of every session it stores, in storage order — the Swift rule (D-128, `WatchSessionEngine.swift:1989-1997`) — not only the current session's (`watch_session_engine.dart:1683-1701` filters to `_session`). This is what delivers a wrist workout that ended while the link was down even after another session started; the wrist's reconnect sync sends it (`watch_sync_orchestrator.dart:108-117`) | `WatchSessionEngine.swift:1989-1997`; `watch_sync_orchestrator.dart:90-117` |
| D-16006 | **Replay parity closes A-152a.** The replay summary stops excluding session-end ids on both sides: lift the skip in `test/helpers/watch_replay_recorder.dart:288` (and its :240/:266-268 comments), and remove the A-152a allowlist entry from the manifest generator (`test/watch_replay_corpus_test.dart:446-451`) and from the checked-in `watch/sync_protocol/fixtures/replay/manifest.json` via regeneration (D-15209's define). All 16 sources must stay green on both engines — this is the structural proof that the twin and Swift produce the same ends for the same stories. Regenerating rewrites the recordings' `expected` blocks (each ended session's `entries` gains `end-<sessionId>`); no recording's event timeline changes (D-15202 records only wrist-inbound frames) | plan 152 D-15205/D-15211/A-152a; `watch_replay_recorder.dart:266-288`; `watch_replay_corpus_test.dart:446-451`; D-15209's regeneration define |
| D-16007 | **The successor asymmetry: the twin's end carries no summaries.** Swift's end computes `avgHeartRateBpm`/`maxHeartRateBpm`, `activeEnergyKcal` and `setBlockHeartRates` from its stored sensor samples; the twin stores samples but has no summary helper, and no consumer needs one from it: the importer attaches each summary field only when present, and the replay summary compares entry ids only (D-15205). Porting `WatchSensorSummaries` to Dart is a later owner decision (Open question Q2), not part of O-6 | `WatchSensorSummaries.swift:86-300`; `envelope.schema.json:315-340`; D-15205 |
| D-16008 | **What the phone saves (brief Q3) — unchanged, asserted.** The importer creates the session as its own finished row: id = the watch's session id, `startedAtMs`/`endedAtMs` from the end, the wrist's sets materialised as efforts, the calendar refreshed (S-271), **no Apple Health workout written for it** (S-270 — the watch's own Health workout stands alone, nothing duplicated), and the phone's own open session untouched (the O-6 importer test asserts `phoneRow.endedAtMs` stays null and both rows exist). The "kept session-…, did not adopt" line in the adoption bridge (D-10) is the rule working, not a defect — adoption and import are different paths | `test/watch_session_import_test.dart` :985-1091 (O-6), S-270 :1785, S-271 :1829; `watch_session_adoption_bridge.dart:123` (D-10); `watch_session_importer.dart` `_createSession` |
| D-16009 | **Prune interplay (brief Q4) — no new rule.** The acknowledgement that releases the wrist's hold on a finished workout is the phone's `receipt` naming the end's entryId: the importer's applied ids include the end row, the receipt reaches `confirmObservations`, and the settled prune releases the readings (Swift: `isEndAcknowledgedWhereOwed` :2170-2173 + D-15601's receipt-time release, :976; the 14-day valve D-15602 :1905 ends the hold when the phone never comes). On the twin the same hold is already expressed without an end-specific gate: an unconfirmed end puts the session in `_awaitsReceipt` (`watch_session_engine.dart:2020-2026`), so its samples stay. The twin gains no prune change; the gate is exercised by a new test (S-16001's fixture asserts the end is still owed after the finish) | `WatchSessionEngine.swift:1900-1976, 2165-2173`; `watch_session_engine.dart:2004-2026`; plan 156 D-15601/D-15602 |

## Feature Invariants

- One `session_end` per session, id `end-<sessionId>`, stored before the row that
  records the terminal status (D-16002). No end is ever re-emitted with different
  values (D-16004).
- For the same story, the twin and Swift hold the same end ids — proved by the replay
  corpus with the exclusion lifted (D-16006).
- The phone keeps its own open workout through an import of another session: nothing
  adopted, nothing ended, nothing deleted (D-16008, O-6).
- `pendingObservations()` on the twin covers every session's unconfirmed rows, as
  Swift's does (D-16005).
- No `PROTOCOL.md`, schema or fixture change (D-16001). The sync contract track is
  touched only by the corpus regeneration, which is data, not contract text.

## Requirements

R1. The Dart twin stores and emits a conformant `session_end` observation at every
    path that ends a held session, before the terminal row, with Swift's guards and
    shape (D-16002, D-16003).
R2. Exactly one end per session (D-16004); a re-offer after a later session started
    still happens (D-16005).
R3. The replay corpus compares session-end ids on both engines and stays 16/16 (D-16006).
R4. S-14660 is un-skipped and green: the owner's trace converges with the phone's own
    workout untouched (D-16008).
R5. Docs name the twin's new parity and the closed A-152a; plan 146c's Open Items gets
    a closing pointer (Phase 4).

## Acceptance Criteria

- AC-1 → S-16001, S-16002, S-16003, S-16004, S-16005, S-16006 (capture sites, shape,
  guards).
- AC-2 → S-16007, S-16008 (catch-up re-offer, delivered twice).
- AC-3 → S-16009 (the owner's story in the harness; S-14660 un-skipped and green).
- AC-4 → S-16010 (replay corpus 16/16, both engines, end ids compared).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect | Guarded by |
|---|---|---|---|
| `WatchObservationKind` (`lib/watch/session/watch_records.dart:58`) | Append-only const table; readers = the twin's emitters and the phone's inbox gate (`_requiredFields`, `watch_session_inbox.dart`) | Gains `sessionEnd = 'session_end'`; no existing kind changes; `all` gains it (it is now emitted, unlike `waterGlass`) | S-16001 |
| `_transitionTo` (`watch_session_engine.dart:1431`) | `finishSession` :399, `abandonSession` :406, `advanceExercise` :378, `insertExercise` :419 | Gains the capture hook on the `status != null` path only (finish/abandon); advance/insert unchanged (status null → no capture) | S-16001, S-16002, S-16003 |
| `_applySnapshot` / `_applyLifecycle` (`watch_session_engine.dart:596, 837`) | The router's phone frames; `test/live_mirroring_test.dart` replays the register | Gains the capture before the terminal `_appendSessionRow`; non-ending frames unchanged (status not terminal → guard refuses) | S-16004, S-16005, S-16006 |
| `pendingObservations` (`watch_session_engine.dart:1683`) | `watch_sync_orchestrator.dart:113-117` (reconnect sync); `test/watch_session_end_owed_test.dart` | Widens from current-session-only to all sessions — mirrors Swift; the phone deduplicates re-offers by `entryId` (put-if-absent staging) | S-16007, S-16008 |
| Replay summary (`test/helpers/watch_replay_recorder.dart:229-288`) | Only `test/watch_replay_corpus_test.dart` | Gains `end-<id>` in every ended session's `entries`, both sides; the checked-in recordings' `expected` blocks change → regeneration | S-16010 |
| Phone inbox/importer/Health/calendar | Unaffected by code; exercised by the new end frames. Greps proving no phone change is needed: the inbox already stages `session_end` (`_stageable`/`_requiredFields`, `watch_session_inbox.dart`), the importer already builds the row (O-6 test green at HEAD), Health is already skipped for imports (S-270 test :1785), the calendar already refreshes (S-271 :1829) | None | S-16009 |
| Stats / plan 157a | `docs/plans/2026-11-13-157a-stats-unlogged-sets-plan/` owns what counts as logged (its D-1/D-2: a set is logged when a rest sits at position + 1) and keeps planned sets for wrist-part sessions (its D-11). An imported wrist-only workout carries no unlogged placeholders (the importer writes only logged sets), so the 157a drop does not interact. **This plan edits no stats file and no 157a file** | None — interface named, not touched | D-16008 |
| Plan 146c's Open Items | Names S-14660 as red-and-deferred, "a protocol change, outside Phase 4" | Phase 4 adds one closing pointer line (the diagnosis was right about the inbox staging nothing; the fix turned out to be twin parity, not a protocol change — D-16001) | R5 |

## UI Standards Impact

None. No screen, widget, notice, dialog or choice changes (the owner decision: no new
phone notice). The adoption bridge's existing debug line is untouched.

## Scenarios

Fixtures for the twin tests: an `InMemoryWatchSessionStore` engine built the way
`test/watch_session_engine_test.dart` builds them (TestClock, counter id factories,
the real `SyncProtocolValidator`); sessions started with `createSession(modality:
null, source: ...)`; sets logged with `appendObservation` of a conformant `set` event
(copy the event map from `test/watch_session_engine_test.dart`'s existing set tests).

### S-16001: the wrist's own finish captures its end
- Fixture: engine with one wrist-created session (`source: 'watch'`, `modality: null`),
  one `set` logged at T+60 s.
- Trigger: `finishSession()` at T+600 s.
- Flow: the capture runs before the terminal row is appended.
- Expected outcome: the store holds a `session_end` observation with
  `entryId`/`eventId` `end-<sessionId>`, `startedAt` = the session's start, `endedAt`
  = T+600 s, `status` `completed`, no `followed`, no `modality`, no summary fields;
  the envelope emitted is `observations_up` and the real validator accepts it; the
  observation row's sequence is lower than the terminal session row's (stored before).
  The end is among `pendingObservations()` while unconfirmed.
- Edge case of: none.

### S-16002: the wrist's own discard captures its end
- Fixture: as S-16001.
- Trigger: `abandonSession()` at T+600 s.
- Flow: as S-16001.
- Expected outcome: same shape with `status` `abandoned`.
- Edge case of: S-16001.

### S-16003: one end per session, whatever ends it twice
- Fixture: S-16001's fixture, then a second `finishSession()` call after the end, and
  (separately, second engine) a finish on a session the phone's lifecycle already
  ended.
- Trigger: the second terminal transition.
- Flow: D-14602 keeps the session ended; the capture guard finds the held end.
- Expected outcome: no second end row, no second emission, no row appended; the
  store holds exactly one `session_end` with the FIRST end's values (idempotence,
  D-16004).
- Edge case of: S-16001, S-16004.

### S-16004: a phone snapshot that ends the session captures its end
- Fixture: the wrist holds a session created by a phone snapshot (`source: 'phone'`,
  so it is a followed session) with one set; the phone then sends a `session_snapshot`
  with `status: completed` and `sentAt` at T+600 s.
- Trigger: `_applySnapshot`.
- Flow: the capture runs with the row's status and `recordedAt`, before the row.
- Expected outcome: one `session_end`, `endedAt` = the snapshot's instant,
  `status` `completed`, `followed: true` (creation source is `phone`), stored before
  the snapshot's terminal row.
- Edge case of: S-16001.

### S-16005: a phone lifecycle end captures its end with the payload's instant
- Fixture: as S-16004 but the end arrives as `session_lifecycle` `completed` with
  `at` = T+540 s.
- Trigger: `_applyLifecycle`.
- Flow: the capture runs with `endedAt` = the payload's `at`.
- Expected outcome: one `session_end`, `endedAt` = T+540 s, `status` `completed`,
  `followed: true`, stored before the lifecycle row.
- Edge case of: S-16004.

### S-16006: a first-hearing already-finished snapshot captures nothing
- Fixture: an engine with no session; a `session_snapshot` arrives for a session id
  the wrist never held, with `status: completed` and one entry.
- Trigger: `_applySnapshot` (first hearing; the phone already holds the whole session).
- Flow: at capture time no creation row exists for the id (Swift `creationRow`
  :2152-2159).
- Expected outcome: no `session_end` observation is stored or emitted; the snapshot's
  terminal row and entry are stored exactly as today.
- Edge case of: S-16004.

### S-16007: the end is still owed after another session started
- Fixture: S-16001's engine; the session finished at T+600 s; `createSession()` called
  again at T+900 s (a second wrist session, so the first is no longer the current one).
- Trigger: `pendingObservations()`.
- Flow: D-16005 — the re-offer covers every session's unconfirmed rows.
- Expected outcome: the first session's `end-<id>` observation is still re-offered
  (and its set), alongside the new session's rows. Red at HEAD (the twin offers only
  the current session's observations), green after Phase 1.
- Edge case of: S-16001.

### S-16008: the end delivered twice is one import
- Fixture: the phone-side repository with the end's `observations_up` staged twice
  under two message ids (same `entryId`), plus the O-6 set.
- Trigger: two `WatchSessionImporter.apply` passes (the shape of
  `test/watch_session_import_test.dart` group `S-263 redelivery` :609, applied to the
  end).
- Expected outcome: one imported session row, one effort, every staged row consumed,
  the receipt names `end-<id>` once; the second pass imports nothing. Red at HEAD is
  not expected — this pins D-16004 against the twin's new emitter, and runs green
  with the existing code (it fails only if a Phase 1 change broke idempotence).
- Edge case of: S-16001.

### S-16009: the owner's story in the harness (un-skips S-14660)
- Fixture: the exact trace of
  `test/watch_convergence_harness_test.dart:837-966` — `linkDrops`; `phoneStartsSession`
  (p1) + `phoneLogsSet`; `wristStartsFreeWorkout` (w2) + `wristLogsSet` (`w-entry-1`);
  `wristFinishes`; `linkRises`; then `heal()` and `checkConvergence()`. The wrist lane
  drains second, so the queued `observations_up` frames (the set, then the end
  captured by Phase 1) reach the phone after p1's frames; the terminal lifecycle has
  already withdrawn the queued w2 snapshot (the radio's `_withdrawOnWristQueue`), and
  the end does not need it.
- Trigger: the un-skipped S-14660 test.
- Flow: inbox stages the set and the end (origin watch); the importer applies w2 with
  `phoneOwnsSession: false` (the adoption bridge holds nothing for w2 — adoption was
  refused by D-10 because the phone holds its own p1).
- Expected outcome: exactly the assertions already written in the test — p1 stays the
  phone's current session, `active`, `endedAtMs` null; w2 saved as its own
  `completed` row with `w-entry-1` present on both sides; no status, entry or
  absorbing mismatches; the heal converges. Nothing deleted, nothing adopted.
- Edge case of: none (the plan's headline scenario).

### S-16010: the replay corpus stays 16/16 with end ids compared
- Fixture: the checked-in corpus at
  `watch/sync_protocol/fixtures/replay/` (16 sources) regenerated after Phase 1 —
  each ended session's `expected.entries` now also holds `end-<sessionId>`.
- Trigger: `test/watch_replay_corpus_test.dart` (Dart replay, byte-fresh) and the
  Swift replay suite (`gateway.sh swift-test`) against the regenerated manifest.
- Flow: D-15206's recorder-fidelity and parity rules, with the D-16006 exclusion
  lifted.
- Expected outcome: 16/16 on both engines; a mismatch is a real finding, never
  normalized (D-15206).
- Edge case of: none.

## Iteration 1

### Phase 1: the twin captures the session end (@developer)

1. [ ] Write the red twin tests first: a new group `plan 160 the twin's session_end`
       in `test/watch_session_engine_test.dart` covering S-16001, S-16002, S-16003,
       S-16004, S-16005, S-16006, S-16007 — symbol: the new test group (fixture
       recipe in each scenario). — `test/watch_session_engine_test.dart`
2. [ ] Add `WatchObservationKind.sessionEnd = 'session_end'` to the kind table and a
       `WatchSessionCapture` helper class with `static String sessionEndId(String
       sessionId) => 'end-$sessionId'`, mirroring Swift `WatchRecords.swift:99-102`;
       `sessionEnd` joins `WatchObservationKind.all` (it is now emitted, unlike
       `waterGlass`). — `lib/watch/session/watch_records.dart` ·
       `WatchObservationKind`, new `WatchSessionCapture`
3. [ ] Add the capture internals to the twin: private `_creationRow(sessionId)`
       (the first stored row for the id, lowest sequence — Swift :2152),
       `_sessionEndEvent(origin, status, endedAt)` building the D-16003 payload, and
       `_captureSessionEnd(sessionId, status, endedAt)` with the three guards of
       D-16002 (terminal status; a creation row exists; `_heldRecord('end-'+id)`
       is null), storing through `_appendObservation(event, sessionId:)` so the
       envelope is validated and emitted like every observation. —
       `lib/watch/session/watch_session_engine.dart` · `_captureSessionEnd`,
       `_sessionEndEvent`, `_creationRow`
4. [ ] Hook site 1: in `_transitionTo`, on the `status != null` path, call
       `_captureSessionEnd(session.sessionId, status, now)` after the rest stop and
       before the row append (Swift :1552-1555). —
       `lib/watch/session/watch_session_engine.dart` · `_transitionTo`
5. [ ] Hook site 2: in `_applySnapshot`, call `_captureSessionEnd(sessionId,
       row.status, row.recordedAt)` immediately before `_appendSessionRow(row,
       lifecycle: null)` (:608), only on the row-writing path — `_mergeLateEntries`
       stays capture-free. — `lib/watch/session/watch_session_engine.dart` ·
       `_applySnapshot`
6. [ ] Hook site 3: in `_applyLifecycle`, call `_captureSessionEnd(session.sessionId,
       status, at)` immediately before `_appendSessionRow` (:845), after the
       terminal/tie-break early returns (Swift :934). —
       `lib/watch/session/watch_session_engine.dart` · `_applyLifecycle`
7. [ ] Widen `pendingObservations()` to every session's unconfirmed observations in
       storage order, keeping the nutrition quick-logs under their stored session ids
       (D-16005; Swift :1989-1997). — `lib/watch/session/watch_session_engine.dart` ·
       `pendingObservations`
8. [ ] Add S-16008 to `test/watch_session_import_test.dart` (group `O-6`, the
       redelivery shape) and run the phase suites.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`
(baseline 181 pre-existing issues — none new), `.github/copilot/scripts/macos/
gateway.sh test test/watch_session_engine_test.dart`, `.github/copilot/scripts/macos/
gateway.sh test test/watch_session_import_test.dart --plain-name "O-6"`, and
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart
--plain-name "S-263"`. Expect the corpus staleness test to now be red (the recordings'
`expected` blocks lack the new end ids) — that is Phase 2's first item, not a Phase 1
failure; record it in the evidence file.
**Predicted Files**: `lib/watch/session/watch_records.dart`,
`lib/watch/session/watch_session_engine.dart`, `test/watch_session_engine_test.dart`,
`test/watch_session_import_test.dart`. Nothing else.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: replay parity — close A-152a (@developer)

BLOCKS on Phase 1 (the twin must capture ends before the corpus can compare them).

1. [ ] Lift the summary exclusion: remove the `if (entryId == sessionEndId(id))
       continue;` line and rewrite the :240/:266-268 comments to name D-16006 (the
       exclusion existed only because the twin stored no end). —
       `test/helpers/watch_replay_recorder.dart` · `WristSummary.fromContents`,
       `sessionEndId` (keep the helper; the corpus test's staleness guard still uses
       the id shape nowhere else)
2. [ ] Remove the A-152a allowlist entry from the manifest generator (the
       `'allowlist'` list's first entry). — `test/watch_replay_corpus_test.dart` ·
       `_manifest`
3. [ ] Regenerate the corpus (this rewrites the 16 recordings' `expected` blocks and
       the checked-in manifest — the D-15209 define): `.github/copilot/scripts/macos/
       gateway.sh test test/watch_replay_corpus_test.dart
       --dart-define=REPLAY_CORPUS_WRITE=true`. If the gateway refuses the
       file-writing run, list it under Governor actions and stop Phase 2 there. —
       `watch/sync_protocol/fixtures/replay/*.json`, `…/manifest.json`
4. [ ] Run the corpus test fresh: `.github/copilot/scripts/macos/gateway.sh test
       test/watch_replay_corpus_test.dart` — 16/16 Dart, byte-identical re-record.
5. [ ] Run the Swift replay: `.github/copilot/scripts/macos/gateway.sh swift-test` —
       16/16 Swift against the same manifest with the end ids now compared.

**Done Criteria**: the two test runs above green with the regenerated corpus;
`.github/copilot/scripts/macos/gateway.sh lint` unchanged (test-only files).
**Predicted Files**: `test/helpers/watch_replay_recorder.dart`,
`test/watch_replay_corpus_test.dart`, `watch/sync_protocol/fixtures/replay/
manifest.json`, the 16 `watch/sync_protocol/fixtures/replay/trace-*.json`/
`seed-*.json` recordings. Nothing else.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: the harness proof — un-skip S-14660 (@developer)

BLOCKS on Phase 1 (S-16009 needs the twin's end); independent of Phase 2.

1. [ ] Remove the `skip:` argument from S-14660 and its blocking comment
       (:968-975), keeping the test body byte-for-byte as written — the assertion is
       the spec. — `test/watch_convergence_harness_test.dart` · S-14660
2. [ ] Run it: `.github/copilot/scripts/macos/gateway.sh test
       test/watch_convergence_harness_test.dart --plain-name "S-14660"`. If red,
       trace with `runner.traceText()` and fix only what the trace names (a twin
       Phase 1 defect, or an inbox/router gap — neither is expected; the O-6 importer
       test pins the phone half). A second red run without a named fix → stop and
       report.
3. [ ] Run the convergence sweep: `.github/copilot/scripts/macos/gateway.sh test
       test/watch_convergence_random_test.dart` — record the mismatch count against
       the baseline (12 per 200, ratchet 14); a lower number is the expected
      improvement, a higher one is a finding. — evidence file
4. [ ] Full suite: `.github/copilot/scripts/macos/gateway.sh test` (900 s) — compare
       with the baseline (7465 passed, 4 skipped, 1 pre-existing failure
       `delete_focused_timer_test.dart` S-4905); S-14660's skip must leave the skipped
       count. Also re-run `.github/copilot/scripts/macos/gateway.sh test
       test/watch_session_end_owed_test.dart` (the owed-end surface D-16005 widens).

**Done Criteria**: all four runs green (full suite within baseline + S-14660 passing
+ one fewer skip); the sweep number recorded in the evidence file.
**Predicted Files**: `test/watch_convergence_harness_test.dart` (un-skip only) — and,
only if step 2 finds a defect, the file the trace names. Nothing else.
**Phase 3 verification notes (Conductor, date):** —

### Phase 4: docs — the twin's parity is now the record (@developer)

BLOCKS on Phases 1-3 (the docs describe what landed).

1. [ ] `docs/watch_session_capture.md`: in the capture table (:228-243) and the
       end-rules list (:493-558), state that the Dart twin captures the same
       `session_end` at the same three sites with Swift's guards (D-16002/D-16003),
       and record the standing asymmetry: the twin's end carries no summary fields
       (D-16007). State the doc's current size against the 52 KB band in the evidence
       file (`test/docs_indexing_contract_test.dart` enforces the 64 KB cap). —
       `docs/watch_session_capture.md`
2. [ ] `docs/watch_session_sync.md`: the offline-import paragraph (:60-78) gains one
       sentence — the wrist's end observation now reaches the inbox from the Dart
       twin too (plan 160), with the S-14660 test as the witness. —
       `docs/watch_session_sync.md`
3. [ ] Plan 146c's Open Items (:588-594): append one closing pointer — "Closed by
       plan 160 (D-16001): no protocol change was needed; the fix was Dart-twin
       parity (`docs/plans/2026-11-14-160-watch-own-workout-reaches-phone-plan/`),
       S-14660 un-skipped and green." —
       `docs/plans/2026-11-12-146c-earlier-discard-wins-plan/
       2026-11-12-146c-earlier-discard-wins-plan.md`
4. [ ] `PROTOCOL.md`: explicitly NO change (D-16001) — verify no amendment row or
       fixture was touched by Phases 1-3; if one was, that is a finding, not work.
5. [ ] Run the docs contract: `.github/copilot/scripts/macos/gateway.sh test
       test/docs_indexing_contract_test.dart`.

**Done Criteria**: the docs test green; lint unchanged; steps 1-3 present in the
diff; step 4's verification (no PROTOCOL.md/schema/fixture diff) recorded in the
evidence file.
**Predicted Files**: `docs/watch_session_capture.md`, `docs/watch_session_sync.md`,
`docs/plans/2026-11-12-146c-earlier-discard-wins-plan/
2026-11-12-146c-earlier-discard-wins-plan.md`,
`…/2026-11-14-160-watch-own-workout-reaches-phone-plan.evidence.md`. Nothing else.
**Phase 4 verification notes (Conductor, date):** —

## Files Affected (whole feature)

| File | Change | Phase |
|---|---|---|
| `lib/watch/session/watch_records.dart` | `WatchObservationKind.sessionEnd`, `WatchSessionCapture.sessionEndId` | 1 |
| `lib/watch/session/watch_session_engine.dart` | capture internals, three hooks, `pendingObservations` widening | 1 |
| `test/watch_session_engine_test.dart` | new twin group (S-16001..S-16007) | 1 |
| `test/watch_session_import_test.dart` | S-16008 redelivery-of-the-end pin | 1 |
| `test/helpers/watch_replay_recorder.dart` | lift the end-id exclusion | 2 |
| `test/watch_replay_corpus_test.dart` | drop the A-152a allowlist entry | 2 |
| `watch/sync_protocol/fixtures/replay/*` (16 recordings + `manifest.json`) | regenerated `expected` blocks | 2 |
| `test/watch_convergence_harness_test.dart` | un-skip S-14660 | 3 |
| `docs/watch_session_capture.md`, `docs/watch_session_sync.md` | parity notes | 4 |
| plan 146c's plan file | one closing pointer line | 4 |
| `…/2026-11-14-160-…-plan.evidence.md` | implementers' baselines, red→green tables, sweep numbers | all |

Readers that need nothing: the phone inbox/importer/router/adoption bridge (existing
tests pin them), plan 157a's stats surfaces (D-16008), `PROTOCOL.md` and the schemas
(D-16001).

## Notes

- Phase dependency graph: Phase 1 → {Phase 2, Phase 3} → Phase 4. Phases 2 and 3 are
  independent of each other; either may run first. Running Phase 2 first gives the
  parity proof before the user story; running Phase 3 first gives the visible win at
  the cost of the corpus staleness test staying red until Phase 2 lands.
- Intermediate state after Phase 1: the corpus staleness test is red by design (the
  recordings' `expected` blocks predate the twin's ends). That red is Phase 2's
  starting signal, not a regression — say so in the evidence file.
- The harness trace's mechanics, for the implementer: the wrist lane queue holds the
  w2 `started` lifecycle, the set's `observations_up` and (new) the end's
  `observations_up`; the terminal lifecycle withdraws the queued w2 snapshot only;
  `observations_up` frames are never withdrawn. The phone lane drains first (p1's
  frames; the wrist refuses to adopt p1 because w2 is terminal — D-78's guard — and
  the phone refuses to adopt w2 because it holds p1 — D-10), then the wrist lane.
- Legacy handling: plan 146c's Open Items text is kept verbatim; Phase 4 appends the
  pointer. The 146c evidence's root-cause sentence ("the wrist re-offering a
  completed session's entries… a protocol change") is superseded by D-16001 but not
  edited — plans are immutable records.
- Watch-out: the twin's `confirmedAt` is in-memory only (`toJson` drops it,
  `watch_records.dart:397-403`), so after a relaunch the twin re-offers confirmed
  rows where Swift's acknowledgement log would not. The phone deduplicates by
  `entryId`, so this stays benign; it is pre-existing, untouched here, and recorded
  as an open question (Q3) in case the owner wants it closed.

## Progress

- [x] Phase 1 — **Complete** (@developer): implemented as planned and green in the
      plan's own files (8 twin tests + `S-16008`; 9 exact-frame assertions in
      `test/watch_session_engine_test.dart` reconciled). The 19 tests the new
      `session_end` frame broke in 7 files are reconciled in the same pass — full suite
      `+7586 -2`, the two reds being Phase 2's stale corpus. Evidence `Phase 1`.
- [ ] Phase 2 — **Edits applied; regeneration pending (Governor action)** (@developer):
      the A-152a lift, the `A-152a` allowlist removal, the derived-end canonicalizer
      rule (`end-<sessionId>` → `end-<the session id's alias>`), the manifest tags the
      recorded runs now cover, the Swift reader (`excludingSessionEnd` gone) and its
      rewritten S-15210/S-15211 guards are in the tree. The recorded `expected` blocks
      are stale until the D-15209 writing run runs, so `S-15202` and `S-15207` are red
      by design. Evidence `Phase 2` and `Phase 2 follow-up 2`.
- [x] Phase 3 — **Complete** (@developer): S-14660 un-skipped and green — the phone
      now imports the wrist's own workout as its own finished workout.
- [x] Phase 4 — **Complete** (@developer): `docs/watch_session_capture.md` and plan
      146c's Open Item updated, each naming the test; `docs/watch_session_sync.md`
      needed nothing.

## Assumption Log

- AL-1 (Phase 1, D-16007): the twin's end carries no HR/energy/block summaries — the
  owner's O-6 sentence lists calendar entry, sets, time span only; every summary
  field is optional on the wire and the corpus compares ids only. Options: omit (chosen) /
  port `WatchSensorSummaries` (~300 lines). Conductor pre-ratification offered (Q2).
- AL-2 (Phase 2): the corpus regeneration rewrites 16 fixture files via the
  D-15209 define — sanctioned by that decision as the `--update-goldens` analogue;
  flagged because the standing rule forbids checks that write files (Q4).
- AL-3 (Phase 1): the twin's end is emitted on every ending path, so it is a wire
  frame even where no `onEmit` is wired. Nine existing assertions in
  `test/watch_session_engine_test.dart` pinned an exact frame/row list and counted
  one item too few; each was reconciled there, none weakened. Not predicted by the
  plan; no test outside that file went red.
- AL-4 (Phase 2): the A-152a lift and the corpus regeneration are one atomic
  change — applying the lift alone leaves the staleness tests red — so the two edits
  are in the tree and the writing run stays a Governor action (Q4).
- AL-5 (Phase 1): mutation M2 (the creation-row guard) cannot be told apart from the
  held-record dedupe by S-16006's real fixture, so no stub was written and the
  mutation is recorded as inconclusive rather than passed.
- AL-6 (Phase 1 follow-up): the 19 unpredicted reds were reconciled in their own test
  files, following whichever side already states the invariant — the Dart
  reconciliation runner now filters `session_end` exactly as the Swift
  `assertConverged` does, and the frame/kind/count assertions gained the end rather
  than dropping an assertion.
- AL-7 (Phase 1 follow-up, S-14514): the pacing fixture now starts the session while
  the link is down, so the wrist never holds it. With the wrist holding the session,
  its answer to the owed end produced a second re-offer inside one window and the
  test measured the wrist's echo, not the ledger's pacing. Fixture change, no
  assertion weakened.
- AL-8 (Phase 2): `S-15201`'s F-2 assertion expected `entries` to be empty; it now
  expects exactly `end-<sessionId>`, the id derived from `WatchSessionCapture`, so the
  claim it makes ("F-2 logs no set") is unchanged.
- AL-9 (Phase 2 follow-up 2): the derived-end rule keys off
  `WatchSessionCapture.endPrefix`, never a literal, and reuses the session id's alias
  through the same table, so meeting the end first mints no second alias. The Swift
  side needs no canonicalizer change: it reads the stored aliases and derives its end
  id from the session id it applied, which is already `x-<n>`.

## Open Items

- **Closed (this pass): the twin's new `session_end` frame broke 19 tests in 7 files
  the plan did not predict.** All 19 are reconciled: the Dart reconciliation runner
  filters `session_end` like the Swift `assertConverged`, and the frame, kind and
  count assertions gained the end. Full suite `+7586 -2`, both reds the stale corpus.
- `S-15202` and `S-15207` are red until Phase 2's regeneration runs — the recorded
  `expected` blocks predate the captured end.
- **Closed (Phase 2 follow-up 2): the stale `watch_surface_transport.md` paragraph.**
  The A-152a sentence now records the closure and names
  `testS15210TheSessionEndIsHeldOnBothSides` and
  `testS15211DroppingAnEndFromEitherSideIsReportedAsAnEntriesDiff`; the
  canonicalization sentence states the derived-end rule and names the `S-15203` test.
- **Open (Governor action): the regeneration.** After it, `S-15202`, `S-15207` and the
  five Swift replay tests go green together; the prediction is in evidence
  `Phase 2 follow-up 2`. Nothing else in Phase 2 is outstanding.

## Feedback

Phase 2 stops one step short of done: the A-152a lift and the allowlist removal are
applied in `test/helpers/watch_replay_recorder.dart` and
`test/watch_replay_corpus_test.dart`, but every recorded `expected` block predates the
captured end, and refreshing them is a writing run
(`--dart-define=REPLAY_CORPUS_WRITE=true`) that the standing rules forbid a check to
perform. The Governor needs to run the regeneration, then re-run
`test/watch_replay_corpus_test.dart` and the full suite; `S-15202` and `S-15207` go
green together. Nothing else in the plan is outstanding.

One deliberate deviation from a plan note: Phase 4's "append the pointer" for plan
146c became a rewrite of that Open Item (it now records the closure and names the
un-skipped test) rather than text appended after it, because the item's own
sentence was what plan 160 made false.
