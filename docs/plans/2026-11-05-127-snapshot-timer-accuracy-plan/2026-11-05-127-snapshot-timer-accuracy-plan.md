# Feature: 127 — a snapshot tells the watch what the phone's timers are doing now

> Status: DRAFT, Iteration 1 ready. No blocking owner question (see Questions).
> Next handoff: crew-builder-app (Phase 0: red tests; it writes no production code)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> **Lands AFTER plan 121a.** 127 builds on 121a's D-1 (a snapshot names a delivered timer only while the phone still runs that same timer) and edits the code 121a adds (`snapshotTimers()` in `lib/state/watch/watch_timer_push.dart`, its use in `lib/state/watch/watch_sync_wiring.dart`). On the tree at `ecf2d050` neither exists yet (`deliveredTimers()` is still there). **Phase 0 starts with the prerequisite check:** `grep -n "snapshotTimers" lib/state/watch/watch_timer_push.dart` must find it, and `grep -rn "deliveredTimers" lib test` must be empty. If not, stop: 121a has not landed.
> Base: shared working tree on `claude_develop`. Sibling sessions edit it (plans 121a, 121b, 128). Before Phase 1 read `git diff --stat` on the files below; only 121a's changes are expected there.
> Prior plans: 121a (above), `2026-11-02-98-phone-watch-live-sync-audit-plan` (D-2 owed starts, D-3 reachability flush), 54 (D-1a never restart a timer the wrist ended), 63 (D-1/D-6 stale snapshot rule).
> Scenario ids: the folder number is 127, but `S-127xx` is taken by plan 77a (`S-12701`..`S-12713`, in `docs/nutrition.md`, `docs/data_models.md` and `test/food_library_copy_edit_test.dart`). Ids are never reused, so this plan uses **`S-127-NN`** (hyphen, two digits). Decisions are `D-n`.

## Overview

Four gaps were noticed while planning 121a. Each was checked against the code. Result:

| Item | Verdict | What the owner would see |
|---|---|---|
| (a) a pause the radio refused is sent in later snapshots as RUNNING | **Real** → fixed (D-1) | Phone paused, wrist (out of reach, or freshly installed) shows the timer counting |
| (b) a timer START the radio refused never rides a snapshot | **Real, narrow** → fixed (D-2..D-5), with one new guard | Phone running a hold, wrist app opened after a while shows nothing until the wrist reports to the phone |
| (c) a clear refused by a wrist with no session is counted as delivered | **Not real after 121a** → no code (D-7); a probe proves it | Nothing: a wrist with no session holds no timer to clear |
| (d) the Dart wrist engine lacks Swift's "drop an older snapshot" check | **Real test-fidelity gap** → closed in the last phase (D-8) | Nothing in the app; tests of reordered snapshots could pass or fail differently from the real watch |

Why (a) and (b) are real, from code:
- `snapshotTimers()` (121a D-1 (D-3 there: "the value stays the delivered JSON")) returns the copy stored when a frame was last DELIVERED. `_pushOnce` records a refused frame in `_owed` (`watch_timer_push.dart:362-381`, `_owe` at 395) and leaves `_delivered` as it was. So after a refused pause the snapshot names the old running copy. Because the auto push compares the whole composed payload with its baseline (`watch_session_auto_push.dart:305`), and the payload did not change, **no new snapshot is queued at all**: the durable path says nothing about the pause.
- A refused START is only in `_owed`. `snapshotTimers()` reads `_delivered` only, so the start is not on any snapshot. It reaches the wrist only through a live frame: a reachability event (98 D-3) or a frame from the wrist (`flushClears`). The snapshot is the one frame the OS queues when the wrist is out of reach.

Why (c) is not real: `guardSession` (Swift `WatchSessionEngine.swift:1948`, Dart `_guardSession`) refuses a `timer_state` only when the wrist holds NO session or another one. A wrist with no session holds no timers (timers belong to a session). The clear has nothing to clear. Its first session arrives as a snapshot, which after 121a is composed from the phone's state, so it names no logged timer. A START refused for the same reason and counted delivered is also right: the ledger entry makes the next snapshot name it. Probes S-127-20..22 prove this; if S-127-20 or -21 turns red, (c) is real and the plan stops at the gate (D-9).

## Questions

None blocking. One derived reading of the owner's expectation, D-6 (what the wrist shows when a start arrives late), follows what a live start already does, so the owner may veto it.

## Resolved Decisions (Ledger)

- **D-1 (a) A snapshot carries the phone's CURRENT timer, not the stored delivered copy.** In `snapshotTimers()`, the value written for a kind is `wanted[kind]` (composed now, the helper 121a adds). The kind is still chosen by 121a's rules (i) to (v), matched against the ledger record (`_delivered[kind]`, or `_owed[kind]`, D-2). Leaving the value unchanged would only be right while the wrist had everything. A paused timer therefore rides as `paused` with its `pausedAt` and `accumulatedPauseMs`. Effect on the auto push: the payload changes when the phone pauses, so a snapshot is composed, and the OS queues it when the wrist is away. 121a's D-3 ("the value stays the delivered JSON") is replaced by this decision.
- **D-2 (b) A refused start rides snapshots.** Candidates for `snapshotTimers()` are `_delivered` ∪ `_owed`. For a kind, the matching ledger record is `_owed[kind]` first, then `_delivered[kind]`; 121a's (i) to (iv) are checked against it. **Replacement rule (work kinds only):** when `_delivered[kind]` holds a different slot or a different start than `wanted[kind]`, the kind is OMITTED even if owed. Reason: the wrist may still hold the old phone-written row, and `adoptTimer` ignores a later start for the same slot while an earlier one runs (Swift D-4); a snapshot has no safe way to clear (D-2 of 121a: never an explicit null). Omission stops the old phone-written row, which is right, and the new start follows live (clear then start, D-2b, on reachability). A rest is exempt from this rule (the phone's newer rest supersedes the wrist's, Swift D-4 second half).
- **D-3 (b) 54 D-1a still holds.** 121a's (v) `_wristEnded` applies to owed kinds too. A start is never named in a snapshot when the mirror holds that very timer as stopped.
- **D-4 (b) Owed live starts check the mirror at send time.** A snapshot can now deliver a start, so the wrist may then have paused or ended it before the owed LIVE start is sent (reachability or wrist frame). In the clears-only pass, an owed start is dropped, and its `_owed` entry removed, when the mirror already holds the SAME slot and start (a rest within `_restStartToleranceMs`) in ANY state, running, paused or stopped. Today `_owe` checks `_wristEnded` only when the frame is refused, not when the owed start is sent (`watch_timer_push.dart:362`). This also closes the case where a frame reached the wrist but the radio reported failure and the wrist then ended the timer.
- **D-5 (b) A refused start asks for a snapshot.** `WatchTimerPush` gets an optional `onOwed` callback, called at the end of `_owe` when it recorded at least one entry. `createWatchSync` passes `() => unawaited(push.flush().catchError(report))`, where `push` is the `WatchSessionAutoPush` already built before the timer push. Without it, a snapshot composed before the timer push ran (the debounce windows race) lacks the start and nothing triggers a new one. A delivered frame never calls it, so a reachable wrist gets no extra snapshot per timer event (S-127-16).
- **D-6 (derived, owner may veto) What the wrist shows when a start arrives late.** The same as a live start: the timer counts from its ORIGINAL start (so a hold the phone started two minutes ago shows two minutes), and the wrist moves to that exercise as it does for a live start (Swift `jumpTarget`, D-2). No notice. A start for an interval the phone has already logged is never sent (D-2 rule (ii), `_owed.removeWhere`).
- **D-7 (c) No code.** The phone's accounting (a frame the radio delivered is delivered) stays. Probes S-127-20 to -22 are the proof. The wrist's receipt is not needed: 121a D-1 and D-1 here make the snapshot the truth for a wrist that just got its session.
- **D-8 (d) Close the Dart twin, last, separable.** In `lib/watch/session/watch_session_engine.dart`: `DateTime? _newestSnapshotAt`; seeded in `restore()` from the stored session rows whose `recordId` starts with `snap-` (their `recordedAt` is the snapshot's `sentAt`); in `_applySnapshot`, right after `sentAt` is read, `if (_newestSnapshotAt != null && sentAt.isBefore(_newestSnapshotAt!)) return false;` (refused whole: no entry, tombstone or timer), and `_newestSnapshotAt` is raised after the session row is appended. Equal applies. Same rule as Swift (plan 63 D-1, D-6). Worth doing because: the twin runs the real wrist logic in `test/` and in `lib/watch` debug mains, and this plan's own fixtures deliver queued snapshots late and out of order; without the guard they could pass on the twin and fail on the watch. It protects the tests listed under Existing-Functionality Impact. **Stop rule:** if more than 5 existing test files need a stamp fix because they apply snapshots with decreasing stamps, stop and split this phase to a plan 127b (plan 63 told its builders to fix the TEST, never loosen the rule).
- **D-9 Phase 0 gate.** On the unchanged code (with 121a landed): S-127-01, -02, -10, -11, -12, -13, -30, -31, -32 and -34 must be RED, and the probes S-127-20, -21 and the guards must be GREEN. A probe that is red where it was expected green (S-127-20, -21) re-opens (c): Phase 0 ends with its evidence, Status becomes `BLOCKED: (c) is real`, and the governor re-plans. An item expected red that is green is dropped, with its evidence, and the plan loses that item (never forced).
- **D-10 No wire, transport or Swift change.** `timer_state` stays live-only; `session_snapshot` stays durable. Swift already has the stale check.

## Feature Invariants

- A snapshot names a phone timer only while the phone runs it, and with the phone's current state (121a D-1, D-1 here).
- A timer the wrist ended, or holds in any state the phone did not send, is not overwritten by an owed start (54 D-1a, D-3, D-4).
- A wrist-started timer is never stopped by a snapshot's omission (Swift D-80); a snapshot never carries `kind: null` (121a D-2).
- Reachable wrist: the number of snapshots sent per timer event does not grow (D-5).
- Plan 98 D-2 and D-3 hold: an owed start is sent on a wrist frame or on reachability, unless D-4 drops it.

## Requirements and Acceptance Criteria

| # | Requirement | Scenarios |
|---|---|---|
| AC-1 | A pause or resume the wrist did not get reaches it through the durable snapshot, and a freshly installed wrist shows the paused timer | S-127-01..05 |
| AC-2 | A phone-started timer the wrist did not get rides the snapshot, once, and only while the phone runs it | S-127-10, -11, -14, -15 |
| AC-3 | A timer the wrist ended, paused or already holds is never restarted or overwritten by an owed start | S-127-12, -13 |
| AC-4 | A replacement interval is never named while the old one may still be on the wrist | S-127-17 |
| AC-5 | A reachable wrist gets no extra snapshots | S-127-16 |
| AC-6 | A wrist with no session gets the right timers from its first snapshot | S-127-20..22 |
| AC-7 | The Dart wrist engine drops an older snapshot arriving late, like the watch | S-127-30..34 |

## Existing-Functionality Impact

| Touched surface | Readers / guards (grep) | Effect | Guarded by |
|---|---|---|---|
| `snapshotTimers()` (121a) | `watch_sync_wiring.dart` projection; six snapshot paths listed in 121a | Value becomes the current state; owed kinds added | 121a's file `test/watch_logged_hold_stays_stopped_test.dart` stays green; S-127-01..17 |
| `_pushOnce` clears-only branch (D-4) | tests `S-9925`..`S-9934` (98), `S-8406`..`S-8408`, `S-6321`..`S-6330` in `test/watch_timer_push_test.dart` | An owed start is dropped when the mirror holds the slot and start | The whole file re-runs; S-127-12, -13 |
| `_owe` callback `onOwed` | `createWatchSync` only (one construction site: `grep -n "WatchTimerPush(" lib test`) | Extra auto-push pass after a refused start | S-127-11, -16 |
| Snapshot `timers` asserted by tests | `grep -rln "\['timers'\]" test`: `watch_session_auto_push_test.dart`, `watch_session_projection_test.dart`, `live_mirroring_test.dart`, `watch_reconciliation_cross_stack_test.dart`, `watch_timer_adoption_test.dart` | Must stay green | Done Criteria of Phase 1 |
| Dart wrist engine `_applySnapshot` (D-8) | test files that apply snapshots to `WatchSessionEngine`: `grep -rln "engine.applyMessage\|WatchSessionEngine(" test` (at least `live_mirroring_test`, `watch_session_projection_test`, `watch_session_finish_test`, `watch_reconciliation_cross_stack_test`, `watch_transport_test`, `phone_manage_bridge_test`, `watch_session_queue_test`) | A snapshot with a stamp older than a previous one is now refused | Phase 2 re-runs each; stamp fixes are test-side (D-8 stop rule) |

## UI Standards Impact

None: no screen change.

## Scenarios

**Fixture F-A.** The harness of 121a's F-A, copied (121a's test file is not edited, and it extracts nothing shared): shipping graph `createWatchSync` over a fake radio, real Dart `WatchSessionEngine` over `InMemoryWatchSessionStore`, `_QueueingPhoneRadio` (`unreachable`, `sent`, `queued` with newest-wins replacement for `session_snapshot`, `attempted`, `deliverQueued()`, `emitLink`), `adoption`, `timerPush`, `timerAdoption`, `autoPush` bound to the phone `WorkoutState`. Two extras: the radio can be set `lostAnswer` (the frame is applied to the engine but the answer is `undelivered`), and the wrist can be set `refuseNoSession` (engine empty: `applyMessage` returns false for session-scoped frames, the answer stays `delivered`). Clock `2026-11-05T09:00:00Z`; session `s-w-127`; `sx-plank` (drill, `ex-plank`, ONE interval) then `sx-run` (timed, `ex-run`, ONE interval); the wrist creates the session and the phone adopts it, as in 121a. Fixture asserts: one `notStarted` interval per slot. File: `test/watch_snapshot_timer_accuracy_test.dart`, plain `test()` only.

**H-start:** `startTimedEntry('sx-plank',0)` (start S_H), `timerPush.flush()`, `autoPush.flush()`, apply every `sent` frame to the engine. **H-away:** `radio.unreachable = true`.

| id | Flow | Expected after the fix | Today (121a landed) |
|---|---|---|---|
| S-127-01 | (a) F-A; H-start (delivered, running); H-away; `pauseTimedEntry('sx-plank',0)`; `timerPush.flush()`; `autoPush.flush()`; read `queued` | exactly one queued `session_snapshot`; its `timers.hold` is `paused`, start S_H, `pausedAt` = the phone's; applied to the engine, `timerFor('hold')` is paused | RED: no snapshot queued (payload unchanged) |
| S-127-02 | S-127-01, then the wrist is REINSTALLED: a second engine over a NEW empty store applies `deliverQueued()` | the new engine holds the session and `hold` is paused, not running | RED |
| S-127-03 | (a) resume: pause delivered while reachable, wrist applies it; H-away; `resumeTimedEntry`; flushes; apply the queued snapshot | `hold` running again with the new `accumulatedPauseMs` | RED |
| S-127-04 | the refused pause later goes live: S-127-01, then reachable + `emitLink(true)`: the owed pause is sent and applied; then the OS delivers the (older) queued snapshot | `hold` paused after each step, never running again | GREEN after fix (guard against a regression in the order) |
| S-127-05 | in sync: reachable pause, delivered | the projected `timers.hold` equals the delivered frame's JSON exactly | GREEN guard |
| S-127-10 | (b) F-A; H-away from the start; `startTimedEntry('sx-plank',0)`; `timerPush.flush()` (refused, owed); `autoPush.flush()`; fresh second engine applies `deliverQueued()` | one queued snapshot names `hold` (running, start S_H, slot `sx-plank`); the engine runs `hold` from S_H and shows `sx-plank` as current | RED |
| S-127-11 | (b) the race: `autoPush.flush()` BEFORE `timerPush.flush()`, then `timerPush.flush()` | after the second step the queue (newest wins) holds a snapshot that names `hold` (D-5 `onOwed`) | RED |
| S-127-12 | (b) 54 D-1a, adversarial: radio `lostAnswer` for the start (the wrist got it, the phone thinks not); the wrist stops it (`engine.stopTimer(kind:'hold')`) and that stopped `timer_state` reaches the phone (`mirror.receive`); then reachable, `emitLink(true)`; apply all frames; then `autoPush` after a phone change | no live `hold` start is attempted after the stopped frame; no snapshot names `hold`; the engine's `hold` stays stopped | RED: the owed start is sent (clears-only branch) |
| S-127-13 | (b) the wrist paused its copy: the snapshot delivered the start (S-127-10 engine), the user pauses on the wrist, the wrist's `timer_state` (paused) reaches the phone; reachable, `flushClears` | the owed start is not sent; the wrist stays paused | RED |
| S-127-14 | (b) the phone ends first: S-127-10 up to before applying; `finishTimedEntry`; flushes; the newest queued snapshot is applied | no `hold` on the snapshot; the engine shows no running hold; no live start attempted on `emitLink(true)` | snapshot part RED; live part GREEN |
| S-127-15 | (b) late arrival: S-127-10 applied by the engine, then reachable `emitLink(true)`: the owed live start also arrives | one running `hold`, start S_H unchanged (the second row has the same values); `timerFor('hold').startedAt == S_H` | GREEN after fix |
| S-127-16 | reachable wrist: start, pause, resume, finish of the hold, all delivered | the count of `session_snapshot` frames in `sent`+`queued` equals the count Phase 0 records on the unchanged code; `onOwed` was never called | GREEN guard (baseline recorded) |
| S-127-17 | (b)/(a) replacement while away: H-start delivered; H-away; `finishTimedEntry('sx-plank',0)`; the SAME slot gets a second interval started (`sx-plank` has two intervals in this fixture; S_H2 > S_H); flushes; apply the snapshot | no `hold` named (old one stopped by omission, new one withheld, D-2); then reachable: clear then start go live; the engine's `hold` runs from S_H2 | RED (121a S-12114 plus owed) |
| S-127-20 | (c) probe: wrist engine EMPTY, `refuseNoSession`; the phone starts the hold (counted delivered), logs it (the clear counted delivered); the wrist sends `WatchTransportRequest.snapshotFrame()`; apply the phone's answer | the engine holds `s-w-127`; `hold` is null or stopped | GREEN expected (gate) |
| S-127-21 | same without the log | the answer names `hold` running from S_H; the engine runs it | GREEN expected (gate) |
| S-127-22 | same with a pause instead of the log (start and pause both refused, both counted) | the answer names `hold` PAUSED | RED (needs D-1) |
| S-127-30 | (d) Dart engine alone: a snapshot A (stamp t1, names `hold`), a snapshot B (t2 > t1, no `hold`); apply A, B, then A again by message id `a2` (a re-send stamped t1) | the re-sent older snapshot returns false and changes nothing: no timer row, no entry, no tombstone cleared | RED |
| S-127-31 | equal stamp applies (t2 then another with t2) | applies | GREEN guard |
| S-127-32 | restart: `restore()` over the same store, then the older snapshot | still refused (seeded from `snap-` rows) | RED |
| S-127-33 | a stale snapshot does not bring back an entry the newer one deleted (D-113.2 / plan 63 D-6) | the entry stays gone | RED |
| S-127-34 | end to end: H-start delivered; H-away; log away (121a flow) so two snapshots exist (A names `hold`, B does not); the OS delivers B then A | the engine's `hold` is stopped after both | RED |

## Iteration 1

### Phase 0: red tests and the gate (crew-builder-app). No production code
1. [ ] Prerequisite check (top of this plan). Record the baseline snapshot counts for S-127-16 in the evidence file.
2. [ ] Create `test/watch_snapshot_timer_accuracy_test.dart`: header listing D-ids and S-ids, the F-A harness with the two extras.
3. [ ] Write every scenario above asserting the Expected column; fixture asserts must pass today (a failing fixture assert is a harness bug).
4. [ ] Run the file; write the red/green table against the Today column in the evidence file; apply D-9.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/watch_snapshot_timer_accuracy_test.dart` run, counts pasted (red is expected; the intermediate state is red by design); `flutter analyze test/watch_snapshot_timer_accuracy_test.dart` shows 0 new issues.
**Predicted Files:** the new test file, the evidence file, this plan's Progress and Assumption Log.

### Phase 1: snapshots carry the current timers; owed starts are safe (crew-builder-app). Only after the gate
1. [ ] `watch_timer_push.dart`: `snapshotTimers()` per D-1, D-2, D-3 (candidates `_delivered ∪ _owed`, value `wanted[kind]`, the replacement rule).
2. [ ] `watch_timer_push.dart`: D-4 in the clears-only branch, via one helper `_mirrorKnowsStart(sessionId, kind, timer)` (same slot, same start, any state; rest tolerance).
3. [ ] `watch_timer_push.dart`: `onOwed` constructor parameter, called at the end of `_owe` (D-5). `watch_sync_wiring.dart`: pass it, using the existing `push`; update the projection comment.
4. [ ] Update the class and field doc comments of `_owed` and `snapshotTimers()` (plan 127).
5. [ ] Run the new file: S-127-01..22 green (S-127-30..34 stay red until Phase 2). Paste red→green per id.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/watch_snapshot_timer_accuracy_test.dart test/watch_logged_hold_stays_stopped_test.dart test/watch_timer_push_test.dart test/watch_timer_adoption_test.dart test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_transport_test.dart`: green except S-127-30..34; `flutter analyze` count equal to the baseline; the Invariant checks of `AGENTS.md` clean.
**Predicted Files:** `lib/state/watch/watch_timer_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, evidence, this plan (Progress, Assumption Log). About 60 production lines.

### Phase 2: the Dart wrist engine drops an older snapshot (crew-builder-app). Separable
1. [ ] Grep the test files that apply snapshots to the Dart engine (Existing-Functionality table) and read their stamps first.
2. [ ] `lib/watch/session/watch_session_engine.dart`: D-8 (field, `restore()` seed, `_applySnapshot` guard and raise).
3. [ ] Fix any existing TEST whose stamps go backwards, with the reason in the evidence file; stop under the D-8 rule if more than 5 files.
**Done Criteria:** the Phase 1 command plus `test/watch_session_finish_test.dart test/phone_manage_bridge_test.dart test/watch_session_queue_test.dart test/watch_session_engine_test.dart`: all green, S-127-30..34 included.
**Predicted Files:** `lib/watch/session/watch_session_engine.dart` (about 12 lines), the test files that needed a stamp fix, evidence.

### Phase 3: docs (crew-docs-keeper)
1. [ ] `docs/state_management/watch_surface.md` (46,979 bytes before 121a's edit; 121a adds about 1 KB; 127 adds about 0.8 KB, band 52 KB): in the `WatchTimerPush` paragraph, state D-1/D-2 (snapshot value is the phone's current state; owed starts ride it), D-4 and D-5.
2. [ ] `docs/watch_session_sync.md` (32,745 bytes) `## Invariants`: a snapshot names a phone timer only with its current state; the Dart wrist twin refuses an older snapshot like the watch. Verified by `test/watch_snapshot_timer_accuracy_test.dart`.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green.

Then the governor: mutations, crew-reviewer, the full `flutter test` once, and `swift test --package-path watch/watchos --filter WatchTimedWorkTests` only if a Swift file changed (none is expected).

## Mutations for the governor (each must turn the named test red, then be restored)

| # | Mutation | Must fail |
|---|---|---|
| M1 | `snapshotTimers()` writes the ledger copy instead of `wanted[kind]` | S-127-01, -02, -03, -22 |
| M2 | `_owed` removed from the candidates | S-127-10, -11 |
| M3 | `onOwed` not called | S-127-11 |
| M4 | drop (v) `_wristEnded` for owed kinds | S-127-12 |
| M5 | drop D-4 (`_mirrorKnowsStart`) | S-127-12, -13 |
| M6 | `_mirrorKnowsStart` checks `state == stopped` only | S-127-13 |
| M7 | drop the replacement rule (D-2) | S-127-17 |
| M8 | owed kinds named without (ii) "the phone still wants it" | S-127-14 |
| M9 | `onOwed` also called after a delivered frame | S-127-16 |
| M10 | Dart guard `isBefore` → `!isAfter` (equal refused) | S-127-31 |
| M11 | Dart guard not seeded in `restore()` | S-127-32 |
| M12 | Dart guard removed | S-127-30, -33, -34 |

## Files Affected

`lib/state/watch/watch_timer_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/watch/session/watch_session_engine.dart`, `test/watch_snapshot_timer_accuracy_test.dart` (new), test files fixed for stamps if any, `docs/state_management/watch_surface.md`, `docs/watch_session_sync.md`.
Read only: `watch_session_auto_push.dart`, `live_session_mirror_state.dart`, Swift `WatchSessionEngine.swift`.
Size: about 75 production lines and about 700 test lines, 4 phases, two tracks (phone sync; the Dart wrist twin, which is separable). One soft signal only. Within budget; no split. Phase 2 is the cut line if the D-8 stop rule fires.

## Owner checks (owner)

- (owner) Start a hold on the phone and see it on the watch. Lower your wrist. Pause it on the phone. Raise your wrist: the watch shows it paused (not counting).
- (owner) The same, then delete the watch app and reinstall it while the session runs: the new watch shows the hold paused.
- (owner) Put the watch away (or turn off its Bluetooth/Wi-Fi link), start a hold on the phone, wait a minute, bring the watch back and open its app: it shows the hold counting from when you started it on the phone (about a minute in) and is on that exercise. Nothing else pops up.
- (owner) The same, but log the hold on the phone before bringing the watch back: the watch shows no hold counting.
- (owner) Unchanged: with the watch on your wrist, pause, resume and log on the phone; the watch follows at once.

## Noticed, not planned

1. **After a PHONE restart the phone's own running timers are stopped on the wrist.** The ledger (`_delivered`, `_owed`) is memory-only. After a restart the first snapshot omits a hold the phone still runs (it is not in the ledger), and omission stops a phone-written row on the wrist (Swift D-80). 121a S-12113 records which frame stops a timer in that case. A state-based `snapshotTimers()` (name every wanted kind the wrist does not already own) would fix it, but it widens the "wrist ended it?" risk (54 D-1a), because after a restart the mirror may not know. Needs its own plan and a device check.
2. A snapshot queued by the OS can name a timer the wrist then ended while out of reach, and revives it when delivered (the stop row is older in append order than the late adoption). The mirror cannot see it because the wrist's stop frame is live-only. Left as it is: it needs a wrist-side rule (a stopped row for the same slot and start is not revived), which is a Swift plan.
3. 121b and 128 (session end) touch the same sync area: check their diffs before Phase 1.

## Progress

- [x] Prerequisite: 121a landed (87de583c)
- [x] P0 red tests and gate D-9
- [x] P1 D-1..D-5
- [x] P2 D-8 (separable)
- [x] P3 docs (lead-written, small exact edits: shared files)
- [x] Governor: mutations (M6 unobservable, see log), review (1 Major fixed), full suite left to the main session

## Assumption Log

- Phase 0: S-127-14, -17, -22 were already GREEN on 121a code (kept as guards; no red item dropped from the fixes). S-127-04, -15 were red.
- D-4 narrowed after review: the helper `_mirrorKnowsStart` (any state) was removed; an owed start is dropped only when the mirror holds it as stopped (`_wristEnded`), because any-state dropped a refused pause (new S-127-18, red before, green after).
- Tests edited: 121a S-12105/S-12105b flipped to "owed kinds ARE named" (127 D-2 reverses 121a; the plan's impact table wrongly said that file stays green). S-127-12/-14/-16 assertions tightened by the lead after mutation survivors M8/M9.
- M6 (stopped-only vs any-state) was unobservable; moot after the D-4 narrowing. Test files: the Dart-engine scenarios S-127-30..33 live in `test/watch_engine_stale_snapshot_test.dart`.

## Feedback

(empty)
