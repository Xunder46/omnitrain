# Feature: 128 — a session finished or discarded on the phone is owed to the watch until the watch has it

> Status: DRAFT, Iteration 1 ready. Owner answered the behaviour questions (2026-11-05, see Resolved Decisions D-4 to D-6). Phase 0 probes already run (evidence file).
> Next handoff: crew-builder-app (Phase 0: the real red test file; no production code)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: working tree on `claude_develop` at `ecf2d050`, shared with other sessions. **Sequencing: land AFTER 121a and 127.** 121a edits the snapshot projection in `watch_sync_wiring.dart` (about lines 267-274) and 127 may too; this plan adds a link listener in the same file and reads the same router. Re-check line numbers and file ownership of `watch_incoming_router.dart`, `watch_sync_request_handler.dart`, `live_session_mirror_state.dart` against plans 123 to 127 before briefing.
> Prior plans: `docs/plans/2026-11-02-98-phone-watch-live-sync-audit-plan/` (F-3, the open item this plan closes; S-217 pins today's behaviour; read only), `docs/plans/2026-11-05-121a-watch-hold-stuck-after-phone-log-plan/` (context only; its Noticed item 6).

## Overview

What the owner saw (plan 98, O-4): the session was finished on the phone and the watch still let the owner finish it and log the effort; none of it recorded.

What the code does today (evidence: `…-plan.evidence.md`, probes P1 to P6, run on the shipping graph with a queueing fake radio):
- The phone tells the wrist once. `_announceEnd` hands `completed` to the mirror and forgets the end whatever the radio answered (`watch_session_auto_push.dart:526-532`, pinned by `S-217`). The OS queue carries the frame only if it is alive when the watch returns.
- The phone heals the wrist only when the **wrist opens a snapshot conversation** (P1, P2 pass, also after a phone restart). The watch does that when it becomes the active app and the phone is reachable. A wrist already in front, or one that talks only in `timer_state` frames or observations, gets no answer (P3 fails). The watch coming back into reach re-offers nothing for an ended session (P4 fails).
- A **reinstalled** watch asks the phone for a snapshot, and the phone answers with the ended session, so the new watch holds an old finished session with status `completed` (P5).
- A late old end for session A cannot end a session B the wrist now holds: the wrist compares session ids (`guardSession`, P6 passes). So "the wrist ignores an end for a session it no longer holds" is already true; no age check is needed (D-6).

**Fix (phone first; the wrist only if Phase 0b says it must).** The phone keeps a bounded, memory-only "ended session X not confirmed" ledger (D-1). It re-offers the end when the wrist talks about X in any frame, and when the watch comes back into reach (D-2). After a phone restart the ledger is empty, so the phone answers from the session's stored row (D-3). A reinstalled watch is not handed an old finished session (D-5). The watch handles the end silently (D-4).

## Questions

None open. Answered by the owner (one round, recommended defaults chosen):
1. A late end on the watch: **silent, back to Start**.
2. A discarded session: **same as finished**.
3. A reinstalled watch after a finished session: **nothing, the Start screen**.

## Resolved Decisions (Ledger)

- **D-1 The ledger.** Next to `_fates` in `LiveSessionMirrorState` (the phone's memory of how it ended each session, `rememberedFateOf`), a map `_unconfirmedEnds`: `sessionId → (state: completed|abandoned, since)`. An entry is added whenever the phone announces an end (the same place `_recordFate` runs: `reportLifecycle`, `reportLifecycleFor`). Whatever the transport answers (`delivered`, `queued`, `undelivered`), the entry stays: neither is a delivery the wrist confirmed. An entry is removed when ANY of: (i) the wrist sends a `session_lifecycle` for that session with an ended state, or a `session_snapshot` for it whose status is ended (the wrist says it has it); (ii) the wrist sends a frame whose `sessionId` is a DIFFERENT session (it has moved on); (iii) it is older than 24 h; (iv) it has been re-offered 3 times. Memory-only, like `_fates`: no persistence.
- **D-2 When it is re-offered.** (a) A frame from the wrist (`origin: watch`) naming an unconfirmed session, of any type except `session_lifecycle`, `session_snapshot` (the existing snapshot path answers those) and `receipt`, is answered with `reportLifecycleFor(named, state)`, at most once per 30 s per session (a timer tick must not flood). (b) When the link changes to reachable, every unconfirmed entry is sent again (`reportLifecycleFor`, durable, so the OS queue carries it if the radio dropped meanwhile). The listener is added in `watch_sync_wiring.dart` next to the existing reachable-link flush of plan 98 D-3. Each re-offer counts toward D-1 (iv).
- **D-3 After a phone restart (empty ledger).** Rule (a) also works from the stored row: a wrist frame naming session X, X's row exists and `endedAtMs != null` → answer `completed`. The router reads the row through a narrow seam (a `getSession` function injected into the router, as `WatchSessionAutoPush` gets one), never a concrete storage class. A **discarded** session has no row, so after a phone restart its end cannot be told apart from a wrist-only session the phone has not seen yet: it is NOT answered. Accepted and documented (Notice 1). Within one app run a discard is covered by the ledger.
- **D-4 (owner) What the watch shows.** An end that arrives late, for the session the watch holds: the watch closes the session and offers Start, with **no notice and no summary**. Anything the wrist logged between the phone's end and the arrival is kept in the wrist's store and sent to the phone like any other observation; the phone's merge into an ended session is unchanged (98 F-3, `S-14`, `S-89c1-5`). Phase 0b reads the Swift and Dart engine and the wrist screens: if applying `completed` today already lands on Start with no summary or effort question for an end the phone made, this decision needs no wrist change; if it shows the summary or effort question, Phase 2 makes the phone-made end silent.
- **D-5 (owner) Reinstall.** The answer to the wrist's snapshot **request** (`_sendSnapshot` in `watch_sync_request_handler.dart`) never sends an ended session. A request means "I hold nothing"; an ended session is not something to join. The phone answers with nothing session-related (the routines and other answers are unchanged). A wrist that DOES hold the session talks in snapshots, not requests (`WatchSyncOrchestrator.sync`), and is healed by P1 and D-2. Existing tests that pin the old answer (plan 98 probe C1; grep `session_snapshot` answers to `snapshotFrame` in `test/watch_sync_request_handler_test.dart` and `test/watch_session_projection_test.dart`) are re-pinned in Phase 1 and listed in the evidence file; changing any other existing expectation is stop-and-report.
- **D-6 No age check on the wrist.** A lifecycle for a session the wrist does not hold is refused by the session id (P6, Swift `guardSession`, Dart twin). An end is monotone (a finished session stays finished), so a late copy for the held session is correct whenever it arrives. No Swift or Dart-engine change for this; P6 is kept as a guard test.
- **D-7 A discard behaves like a finish (owner).** `abandoned` goes through the same ledger and the same triggers.
- **D-8 No wire, transport or protocol change.** Existing `session_lifecycle` frame; `_queueable`/`_replaceable` unchanged. Because only the newest `session_lifecycle` per workout waits in the OS queue, the ledger sends one frame per unconfirmed session; if two ended sessions are unconfirmed (quick ends), both are sent in start order and the OS queue keeps the newest, the other is re-offered by the wrist's next frame (S-12806).
- **D-9 `S-217` stays true.** `completeSession()`'s own frame is still not an owed site in `_announceEnd`; the ledger is the new owed record. `S-217` keeps asserting that the auto push attempts the end once, and gains no change.

## Feature Invariants

- An end the phone made is re-offered only for a session the ledger or the stored row says is ended, never for a session still active (S-12809).
- No end is ever sent for a session other than the one the wrist's frame named, or the one the ledger holds (a wrist's own different session B is never ended by A's entry).
- Re-offers are bounded: 30 s apart per session, 3 at most, 24 h at most. No loop with a silent radio.
- The wrist is never told an ended session as a joinable snapshot (D-5).
- Plan 98 D-2/D-3 and 121a invariants stay green.

## Requirements and Acceptance Criteria

| # | Requirement | Scenarios |
|---|---|---|
| AC-1 | A wrist that missed the end is ended by its next frame of any type naming that session | S-12801, S-12802, S-12803 |
| AC-2 | The watch coming into reach is told an unconfirmed end | S-12804 |
| AC-3 | After a phone restart a finished session is still told on the wrist's next frame | S-12805 |
| AC-4 | Quick ends, an end then a new session, and a late old end are safe | S-12806, S-12807, S-12808 |
| AC-5 | Nothing is re-offered for a running session, a confirmed end, or beyond the bounds | S-12809, S-12810, S-12811, S-12812 |
| AC-6 | A discard is owed like a finish | S-12813 |
| AC-7 | A reinstalled watch shows no old finished session | S-12814 |
| AC-8 | The watch ends silently (D-4) | S-12815 (+ Swift test if Phase 2 runs) |
| AC-9 | Today's healing paths keep working | S-12816 (P1/P2 as guards) |

## Existing-Functionality Impact

| Touched surface | Readers | Effect | Guarded by |
|---|---|---|---|
| `LiveSessionMirrorState` `_recordFate` / `rememberedFateOf` | `watch_incoming_router.dart:130`, the mirror itself | the ledger sits beside it; `rememberedFateOf` unchanged | S-12816, `S-190` in the existing suites |
| `WatchIncomingRouter.receive` | all wrist frames | new answer for non-snapshot frames naming an ended session | S-12801 to S-12803; `test/watch_incoming_router_test.dart`, `test/watch_session_projection_test.dart` stay green |
| `watch_sync_wiring.dart` link listener | plan 98 D-3 reachable flush | one more action on `reachable` | S-12804; plan 98 `S-9929` stays green |
| `_sendSnapshot` in the request handler | wrist snapshot requests | an ended session is no longer answered | S-12814; the re-pinned tests of D-5 |
| `WatchSessionAutoPush._announceEnd` | the auto push | unchanged (D-9) | `S-217`, `S-85`, `S-201` stay green |

## UI Standards Impact

None for the phone. The watch has no new screen (D-4: silent).

## Scenarios

**Fixture F-A.** Copy the harness of `test/watch_timer_push_test.dart` (shipping graph `createWatchSync`, real Dart engine over `InMemoryWatchSessionStore`, plain `test()` only) with the queueing radio of the probe source (`…-plan.probe-source.dart.txt`): `unreachable` + durable frame → `queued` (newest per type), otherwise `undelivered`; `deliverQueued()`; `emitLink`. Clock `2026-11-05T09:00:00Z`; session `s-w-128`; one timed slot `sx-run`. The wrist creates the session, the phone adopts it, `autoPush.flush()` once. New file `test/watch_session_end_owed_test.dart`.
**Step E-away:** `unreachable = true`, `phoneState.endSession(writeToHealth: false)`, `autoPush.flush()`; fixture assert the session row has `endedAtMs`; then the queued copy is dropped (`queued.clear()`), `unreachable = false`.

| id | Fixture delta, trigger | Expected (after the fix) | Today |
|---|---|---|---|
| S-12801 | F-A; E-away; the wrist sends a `timer_state` frame naming `s-w-128`; apply the phone's answers to the engine | one `session_lifecycle` `completed` for `s-w-128`; engine status `completed` | RED (P3) |
| S-12802 | as S-12801 with an observation frame (a logged set) | same | RED |
| S-12803 | as S-12801 but the wrist sends 5 frames inside 30 s | exactly one lifecycle sent; after the clock passes 30 s, the next frame sends a second | RED |
| S-12804 | F-A; E-away; `emitLink(reachable: true)`; nothing else | the unconfirmed `completed` is sent (reaches the engine or the queue); engine `completed` | RED (P4) |
| S-12805 | F-A; E-away; the phone restarts (second `createWatchSync` over the same repository, state and radio, ledger empty); the wrist sends a `timer_state` frame | `completed` answered from the stored row; engine `completed` | RED |
| S-12806 | two sessions A then B each started on the wrist, each ended on the phone while away, queue dropped; the wrist (still on A) sends a frame naming A, then one naming B | A's end then B's end each answered once; no frame ends the wrong session | RED |
| S-12807 | F-A; E-away; the phone starts a new session B before the end is delivered; the OS delivers A's old `completed` to a wrist holding B | B stays `active` (P6); A's ledger entry is not used to end B on a frame naming B | GREEN guard |
| S-12808 | F-A; E-away; a second identical frame after the first answer, same phone run | second answer only after 30 s (rate limit); never a different state | RED |
| S-12809 | F-A, session still running; the wrist sends frames; link flaps | no `session_lifecycle` is sent | GREEN guard |
| S-12810 | F-A; E-away; the wrist confirms with its own `session_lifecycle` completed (or an ended snapshot) | entry removed; a later frame sends nothing | RED |
| S-12811 | F-A; E-away; the wrist then sends a frame naming a different session B | entry removed; nothing sent for A or B | RED |
| S-12812 | F-A; E-away; frames spaced over 31 s each, 4 times; and: clock +25 h | exactly 3 re-offers; after +25 h none | RED |
| S-12813 | F-A; the phone DISCARDS the session while away (row gone), queue dropped, link back; a frame from the wrist | `abandoned` re-offered by the ledger; engine `abandoned`; after a phone restart nothing is sent (D-3) | RED |
| S-12814 | F-A; E-away; a NEW empty wrist sends the snapshot request | the phone sends no `session_snapshot` of the ended session; the new engine holds nothing | RED (P5) |
| S-12815 | the engine applies a phone-made `completed`: assert what the wrist records and what its screen state is (summary / effort question pending or not) | Start offered, no summary, no effort question pending (D-4). Phase 0b records the actual and decides Phase 2 | Record |
| S-12816 | P1 and P2 from the evidence file as permanent guards | engine `completed` after the wrist's snapshot, with and without a phone restart | GREEN |

Adversarial set requested by the brief, mapped: end while unreachable (S-12801, S-12804), end then new session before delivery (S-12807), two quick ends (S-12806), phone restart with empty memory (S-12805, S-12813 second half), reinstall (S-12814).

## Iteration 1

### Phase 0: red tests (crew-builder-app). No production code
1. [x] Create `test/watch_session_end_owed_test.dart` per F-A and the table (S-12801 to S-12816), assertions on the Expected column; fixture asserts must pass today.
2. [x] Phase 0b (read only, Swift and Dart): what `applyLifecycle` completed does on the wrist and which wrist state follows (summary, effort question, Start). Record the answer in the evidence file; this settles S-12815 and whether Phase 2 exists.
3. [x] Run the file; paste counts and each failing line into the evidence file against the Today column. A fixture assert that fails is a harness bug.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/watch_session_end_owed_test.dart` run, counts pasted (red expected: S-12801 to S-12806, S-12808, S-12810 to S-12814); S-12807, S-12809, S-12816 green.
**Predicted Files:** the new test file, the evidence file, this plan's Progress.

### Phase 1: the ledger and its triggers (phone, crew-builder-app)
1. [x] `live_session_mirror_state.dart`: `_unconfirmedEnds` and a small method set (add on announce, `confirm(sessionId)`, `dueEnds(now)`), bounds of D-1.
2. [x] `watch_incoming_router.dart`: the D-2(a) answer, the D-3 row seam, and the D-1 (i)(ii) removals; rate limit per session.
3. [x] `watch_sync_wiring.dart`: the D-2(b) reachable listener. Inject the row seam and a clock into the router from the graph.
4. [x] `watch_sync_request_handler.dart` `_sendSnapshot`: D-5.
5. [x] Run the new file green. Then the dependents and re-pin only the D-5 tests, recording each.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/watch_session_end_owed_test.dart test/watch_session_auto_push_test.dart test/watch_incoming_router_test.dart test/watch_sync_request_handler_test.dart test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_timer_push_test.dart test/watch_transport_test.dart` green; `flutter analyze` count equal to baseline; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty.
**Predicted Files:** the four lib files above (about 70 to 110 production lines), the evidence file, this plan's Progress.

### Phase 2: the wrist ends silently (only if S-12815 shows a summary or effort question)
1. [x] Swift `WatchSessionEngine` / `WatchLoggingState` and the Dart twin: a session ended by a phone `session_lifecycle` returns to Start with no summary or effort question; a wrist-made finish is unchanged. Swift and Dart tests added.
**Done Criteria:** `swift test --package-path watch/watchos` for the touched test target, plus the Dart wrist tests, green (counts pasted).
**Predicted Files:** decided by Phase 0b; if Phase 0b needs more than about 40 lines, stop and plan it as 128b.

### Phase 3: docs (crew-docs-keeper)
1. [x] `docs/state_management/watch_surface.md` (check size against the 64 KiB ceiling first): the ledger, its triggers and bounds, the D-5 rule. `docs/watch_session_sync.md` Invariants: one bullet for "an end the phone made is owed until the wrist confirms or the bounds pass". Update the plan 98 Noticed/F-3 pointer only by a note in this plan's Progress (do not edit plan 98).
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green.

## Mutations for the governor (each turns the named test red, then restore)

| # | Mutation | Must fail |
|---|---|---|
| M1 | remove the router's D-2(a) answer | S-12801, S-12802 |
| M2 | drop the 30 s rate limit | S-12803, S-12808 |
| M3 | remove the reachable listener | S-12804 |
| M4 | drop the stored-row fallback (D-3) | S-12805 |
| M5 | remove D-1 (ii) (a different session confirms) | S-12811 |
| M6 | remove D-1 (i) confirmation | S-12810 |
| M7 | drop the 3-re-offer cap / the 24 h cap | S-12812 |
| M8 | re-offer for a running session (ignore row `endedAtMs`) | S-12809 |
| M9 | re-add the ended-session snapshot to `_sendSnapshot` | S-12814 |
| M10 | the ledger answers with the wrong session id | S-12806, S-12807 |

## Files Affected

`lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_incoming_router.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/watch_sync_request_handler.dart`, `test/watch_session_end_owed_test.dart` (new), two docs; Swift/Dart wrist files only if Phase 2.
Size: about 70 to 110 production lines, about 700 test lines. Tracks: phone, plus a possible small wrist change. One soft signal at most (two tracks, only if Phase 2 runs); within budget, no split. Phase 2 is the part to split off (128b) if Phase 0b grows it.

## Notes

- Graph: P0 → P1 → (P2 if needed) → P3 → governor. Do not run the full suite between P0 and P1.
- Why no "retry until receipt": the protocol has no acknowledgement (`watch_delivery.dart`), so "confirmed" can only mean the wrist said something that shows it holds the end or has left the session. That is why the ledger is bounded.

## Owner checks (owner)

- (owner) Start a workout on the watch, leave the watch asleep or out of reach, finish the workout on the phone, then raise your wrist: the watch is on the Start screen with no summary and no question.
- (owner) The same, but keep the watch app open in front the whole time (do not lower it): within about half a minute the watch closes the workout by itself the next time anything is logged on it.
- (owner) The same with Discard instead of Finish: the watch also returns to Start.
- (owner) Finish on the phone, then delete the watch app and reinstall it: the watch shows Start, not the old workout.
- (owner) Force-quit the phone app after finishing, then log a set on the watch: the watch closes the workout.

## Noticed, not planned

1. A discard made before a phone restart cannot be re-told after the restart (no row to tell it from a session the phone has not met). Persisting the ledger would fix it; deliberately not done (D-1).
2. Items P5 and the old probe C1 mean the request answer changed meaning; any watch build in the field that relies on being handed an ended session on request would see Start instead. That is the owner's choice (D-5).
3. The Dart engine twin has no stale-snapshot guard (121a Noticed 2); not in this plan.

## Follow-up F1 — an offer that never left does not count (2026-11-07, review minors 2 and 3 of the first review)

**D-10 An offer counts when its send returned, not when it was taken.** `takeOwedEnd` and `offerAllOwedEnds`
(`lib/state/watch/live_session_mirror_state.dart`) counted the offer, and retired the entry on the third, before the
awaited `reportLifecycleFor` ran. A send that throws (production reports it, never crashes) therefore spent a re-offer it
never delivered; the third such throw retired the end for good, and in `offerAllOwedEnds` the first throw abandoned the
remaining owed ends. New shape: `takeOwedEnd` only stamps the 30 s pacing (`lastOfferAt`); a new
`noteOfferSent(sessionId)` counts it and retires at the third, and callers invoke it after `reportLifecycleFor`
returned. `offerAllOwedEnds` tries every end, counts the ones that were sent, and rethrows the first error after the loop
(the wiring still reports it).

| Scenario | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-12890 | wrist starts, phone ends while away (radio reachable); then a wrist `timer_state` frame names the session three times, 31 s apart, with the radio throwing on every `session_lifecycle` send; then a fourth frame 31 s later with the radio healthy | the fourth frame's answer carries the end (`session_lifecycle` completed delivered) | the third throwing take retired the entry, so the fourth frame is answered with nothing |
| S-12891 | two ends owed (sessions A older, B newer), radio throws only for A's lifecycle; link flaps to reachable | B's end is delivered and the wiring's `onFailure` received A's error | the first throw left the loop, so B was never offered |
| S-12893 | one end owed, delivered; the link flaps to reachable four times | exactly three lifecycles, the fourth flap sends none | link offers were counted nowhere in a test: removing the count after the link send left every test green (lead's mutation D) |
| S-12892 | the existing S-12803/S-12812 shape (three delivered offers, the fourth none) | unchanged: exactly three, then none | guard that counting after the send still caps at three |

Docs delta: `docs/watch_session_sync.md` "re-offered 3 times" sentences gain "an offer whose send threw does not count" (lead edits).

## Progress

- [x] P0 red tests and Phase 0b
- [x] P1 ledger and triggers
- [x] P2 wrist silent end (conditional)
- [x] P3 docs
- [ ] Governor: mutations M1 to M10 (no mutation record in the evidence file; review and the full suite ran: see .review.md)
- [x] F1 (D-10, S-12890 to S-12893): done 2026-11-07 (crew-builder-app run 20261107-153217 + lead's guard test S-12893); review minors 2 and 3 closed; minor 4 was already in code; minor 5 closed by a docs sentence.

## Assumption Log

- Planning probes were run with a queueing fake radio, wrist = Dart engine; the Swift engine's `guardSession` was read, not run.
- The fake radio treats `queued` as "the OS may or may not deliver"; probes drop the queue to model a reinstall or lost queue.

## Feedback

(empty)
