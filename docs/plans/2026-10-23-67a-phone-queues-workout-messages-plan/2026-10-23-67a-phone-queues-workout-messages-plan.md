# Feature: 67a — the phone's workout messages wait for the watch instead of being dropped

> Status: Iteration 1 active. Re-shaped 2026-10-23 after the owner's answers, before any handoff. It replaces the drafts `…67a-phone-pushes-reference-data-plan` and `…67a-phone-queues-session-and-sync-now-plan`; neither was built, both folders were removed, and none of their decisions bind.
> Next handoff: @developer (Phase 1 may start now; Phase 2 waits for gate G-0 in the series index)
> Series: `docs/plans/2026-10-23-67-phone-keeps-watch-current-series.md`
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; docs/state_management/watch_surface.md ("The phone's link"); watch/sync_protocol/PROTOCOL.md ("Idempotency and reconciliation", the 2026-10-08 "Honest delivery" row).
> Working branch: the one checked out (`claude_develop`). Never create or switch branches. Evidence goes in `2026-10-23-67a-phone-queues-workout-messages-plan.evidence.md`, review findings in `…review.md`, both beside this file.

## Overview

| What you do on the phone while the watch app is closed or out of reach | Today | After 67a |
|---|---|---|
| Log sets, edit or delete a set, add an exercise to the workout | the message is dropped; the phone offers it again only at its next trigger (another change, a resume, a frame from the watch) | the phone hands it to watchOS, which delivers it when the watch app next opens. Only the newest workout state waits, and older waiting copies are withdrawn; each edit/deletion and each added exercise is kept |
| Finish or discard the workout | dropped until the next trigger | queued; one finish per workout waits |
| Log 100 sets | n/a | one waiting workout state, not 100 |
| A timer or rest changes | dropped | still dropped (it would be wrong on arrival); re-sent fresh when the devices meet |
| Log a food on the watch | the watch already queues its log (plan 47b) and the phone's receipt is already queued (plan 47a) | unchanged; now pinned end to end |
| Change a routine, theme, units, rest ping, effort question or a food | the watch pulls it when its app opens or is raised near the phone (plans 55, 62) | unchanged; the phone never pushes static data |

No screen changes, and no watch code changes. The wrist already applies late or repeated messages safely: a `session_snapshot` older than the newest it applied is ignored (plan 63 D-6), and a repeated `session_lifecycle` or `structure_change` is a no-op (PROTOCOL authority rule 6, `changeId`). The wrist's own messages are 67b.

## Facts from source (read 2026-10-23)

- `WatchConnectivityTransport.send` (`lib/core/platform/watch_transport.dart`): when the watch is unreachable or the radio refuses, it queues only `isDurable` frames (`type == 'receipt'`) and answers `queued`; everything else answers `undelivered` with nothing queued. `test/watch_transport_test.dart` S-6811 and S-6812 pin `session_snapshot` as not queued; S-6811 pins `timer_state` and requests as not queued; S-6810 pins the receipt as queued.
- The phone's workout frames all come from `LiveSessionMirrorState` (`lib/state/watch/live_session_mirror_state.dart`):
  - `session_snapshot`, with a fresh `messageId` per send;
  - `exercise_push`;
  - `structure_change`, with `changeId` in the payload; `deleteEntryAs` re-offers an owed deletion under the same `changeId` and a fresh `messageId`;
  - `session_lifecycle`, with a fresh `messageId` per call;
  - `timer_state`.
  All go through `WatchInboxStagingTransport(inner: resolved)` (`lib/state/watch/watch_sync_wiring.dart`) into the transport's `send`.
- Callers advance bookkeeping only on `WatchDelivery.delivered`: `watch_session_auto_push.dart` l.292, 299, 311, 387, 520, 538, 576; `watch_timer_push.dart` l.448. `watch_sync_wiring.dart` l.150 (`WatchSyncGraph.sync`) forgets the push baseline only on `undelivered`.
- Native link (`packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift`): `status`, `sendMessage` (answers on the watch's reply), `transferUserInfo` (dedups by `messageId` against `outstandingUserInfoTransfers`). It has no way to list or cancel. Only `lib/core/platform/watch_connectivity_channel.dart` imports the package (47a D-4).
- Food logging: the wrist's `observations_up` (which carries food quick-logs) is durable on the wrist (`WatchConnectivityBridge.isDurable`). The phone logs it through `WatchNutritionLogBridge` and answers with a `receipt`, which is durable on the phone. A food logged on the phone sends nothing; it only changes the next `foods_down` the watch pulls.

## Owner decisions applied (2026-10-23)

- Q1: active workouts and food logging sync on action; static data needs no push.
- Q2: no phone Sync button; the watch pulls static data.
- Q3: no "Update waiting" line. Static data no longer queues on the phone. A waiting workout message is replaced within the workout and matters mid-workout, not in Settings. Waiting receipts would make a line noisy. The Settings card stays read-only (S-6912 keeps its meaning).
- Q4: newest copy only, no age limit.
- Q5: running timers are never queued.
- Q6: no background apply on the watch.

## Resolved Decisions (Ledger)

- **D-1 A queued copy is a carrier, not a delivery.** `queued` does not advance any sender's bookkeeping; the plan 19b rule stands (only `delivered` does). A frame still owed is offered again at its next trigger, queued again, and its older copy replaced (D-3). No caller in `lib/state/watch/` changes how it reads a `WatchDelivery`.
- **D-2 Queued types.** When the watch is unreachable, or the radio refuses the live send, these are queued and answer `queued`: `receipt` (unchanged), `session_snapshot`, `session_lifecycle`, `structure_change` and `exercise_push`. Everything else answers `undelivered` as today, with nothing queued.
- **D-3 Replacement.** Before queuing a frame, and after a frame is delivered live, withdraw the outstanding OS transfers it replaces:
  - `session_snapshot`: every outstanding `session_snapshot` with the same `sessionId`.
  - `session_lifecycle`: every outstanding `session_lifecycle` with the same `sessionId`.
  - `structure_change`: every outstanding `structure_change` with the same `sessionId` and the same payload `changeId`.
  - `exercise_push`, `receipt` and anything else: none (dedup by `messageId` only, the existing native rule).
  A transfer whose `messageId` equals the frame's own is never withdrawn. The OS's own outstanding list is read each time, so transfers left from a previous app run are matched too.
- **D-4 Never queued.** `timer_state`; every request (a frame without `type`); and `preferences_down`, `foods_down`, `routines_down`, `exercises_down`. Static data travels only as the answer to the watch's pull.
- **D-5 Failures.** If reading the outstanding list fails, the frame is still queued (at worst one extra copy, which the wrist ignores as stale or repeated) and the failure is reported once. If a cancel fails, it is reported once and the queue call still runs. If queuing fails, the result is `undelivered` and the failure is reported once (unchanged).
- **D-6 Order.** Queued frames keep their queue order (`transferUserInfo` is first in, first out). D-3 only removes copies, so a deletion queued before a snapshot still arrives before it (S-120's rule).
- **D-7 OS queue only.** Queuing uses the existing `transferUserInfo` path. Nothing is queued or retried in the app layer; the watch_surface.md rule stands.
- **D-8 Native link additions.** Two new methods:
  - `outstandingTransfers` returns a list of `{messageId, type, sessionId?, changeId?}`, read from each outstanding transfer's `userInfo` (`changeId` from `userInfo.payload.changeId`). An entry without a string `messageId` is skipped.
  - `cancelTransfers(messageIds: [String])` returns the number cancelled; an empty list is answered 0 without touching the session.
  Both are decoded by `WatchLink`. No new event.
- **D-9 Plugin types stay in the channel.** The list/withdraw capability is a core interface in a new file under `lib/core/platform/`. `WatchConnectivityChannel` implements it; a channel without it answers an empty list and 0. `WatchMessageChannel` and `WatchMirrorTransport` gain no members, so their test fakes stay untouched.
- **D-10 Contract.** `watch/sync_protocol/PROTOCOL.md` gets one amendment row and a matching note under "Idempotency and reconciliation". It covers:
  - the phone MAY queue `session_snapshot`, `session_lifecycle`, `structure_change` and `exercise_push` through the OS when the watch cannot be reached;
  - it MAY withdraw a queued copy it has superseded (D-3 keys);
  - `timer_state`, requests and static frames are never queued by the phone;
  - a queued copy advances no bookkeeping.
  This supersedes the 2026-10-08 "Honest delivery" row's "Nothing is queued then or now" for these four phone-sent types. No shape, schema, fixture or version change.

## Feature Invariants

- Only `delivered` advances bookkeeping (D-1).
- After any send completes, the OS queue holds at most one `session_snapshot` and one `session_lifecycle` per `sessionId`, and at most one `structure_change` per (`sessionId`, `changeId`).
- `receipt`, `observations_up` and `exercise_push` transfers are never withdrawn. `timer_state` and the static types are never queued.
- Layer rule: `lib/state/` reaches the link only through `lib/core/platform/` interfaces. No repository change, so implementation parity is untouched.

## Acceptance Criteria

- AC-1 Workout messages are queued when the watch can't be reached: newest only, edits and the finish kept, timers never (S-9710…S-9719).
- AC-2 Bookkeeping stays honest, and a real graph converges when the devices meet (S-9720, S-9721).
- AC-3 Food logging stays queued (S-9722). Static data is never pushed (S-9723).
- AC-4 The native link lists and withdraws transfers (S-9701…S-9703).

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `WatchConnectivityTransport.send` queue policy | `grep -rln "WatchConnectivityTransport(" lib test` → `lib/core/utils/platform_watch_transport_factory.dart`, `test/watch_transport_test.dart`, `test/watch_message_order_test.dart` | the D-2 types answer `queued` instead of `undelivered` when apart | S-6811 snapshot arm → S-9710 and S-6812 snapshot arm → S-9713 (supersedures: bodies edited, ids renamed); S-6810, the S-6811 timer/request arms, S-206 and S-218 unchanged |
| Callers of `WatchDelivery` | `grep -rn "WatchDelivery\.\(delivered\|undelivered\|queued\)" lib` (sites listed in Facts) | none: they compare to `delivered`, or to `undelivered` only to forget a baseline | `test/watch_session_auto_push_test.dart`, `test/watch_timer_push_test.dart`, `test/live_mirroring_test.dart` (S-215, S-216), `test/watch_session_projection_test.dart` green unchanged (their fakes return their own deliveries) |
| `WatchSyncGraph.sync()` l.150 | wiring | a resume snapshot that is queued keeps the push baseline, so the push re-offers it only at the next change | S-9721 asserts the queued copy reaches the watch when the devices meet and a later change is re-offered |
| Plugin and channel | `test/watch_link_package_test.dart`, `test/watch_connectivity_channel_test.dart` | additive | S-6801…S-6805, S-6816 unchanged |
| Settings APPLE WATCH card | `test/settings_watch_status_test.dart` | untouched | S-6910…S-6914 unchanged |
| Wrist apply of late or repeated frames | `WatchSessionEngine.applySnapshotExclusive` stale rule (plan 63 D-6), `changeId` dedup | receives queued copies | existing Swift suites; owner device checks 1-2 |
| Standing invariants | docs/global_conventions.md | no UI | N/A |

## UI Standards Impact

None: no UI change.

## Scenarios

Shared link fixture **L**: a fake channel with the D-9 capability, holding:
- the flags `paired`, `appInstalled`, `reachable`;
- an outstanding list of `{messageId,type,sessionId?,changeId?}` that a queue call appends to and a cancel removes from;
- recorded live sends, queue calls and cancels;
- scripted throws by frame `type`.
Clock T0 = 2026-10-23T10:00:00.000Z, advanced only explicitly. Shorthand: snap(s, m) is a `session_snapshot` for session `s` with `messageId m`; sc(s, c, m) a `structure_change` with `changeId c`; lc(s, state, m) a `session_lifecycle`.

### Phase 1 (native link, Dart side)
### S-9701: the outstanding list decodes
- Fixture: native answers `[{messageId:'m1', type:'session_snapshot', sessionId:'s-1'}, {messageId:'m2', type:'structure_change', sessionId:'s-1', changeId:'c1'}, {messageId:'r1', type:'receipt'}, {type:'foods_down'}, 42]`.
- Expected: three entries in order, with their optional fields; the entry without `messageId` and the non-map are skipped.
- Edge case of: none
### S-9702: cancelling by id
- Fixture: A ids `['a','b']`, native answers 1; B ids `[]` (empty queue); C native throws `PlatformException('not_activated')`.
- Expected: A sends exactly `['a','b']` and returns 1. B returns 0 and invokes nothing. C throws `WatchLinkException('not_activated')`.
- Edge case of: none
### S-9703: the channel exposes it without plugin types
- Fixture: `WatchConnectivityChannel` over a fake `WatchLink` answering S-9701's list.
- Expected: a core-typed list of three; cancel forwards the ids. Guard: `grep -rln "package:omnitrain_watch_link" lib` prints only `lib/core/platform/watch_connectivity_channel.dart`.
- Edge case of: S-6816

### Phase 2 (the phone's workout messages)
### S-9710 (supersedes S-6811's snapshot arm): a snapshot while apart is queued
- Fixture: L; reachable false; outstanding empty.
- Trigger: send snap(s-1, m1).
- Expected: result `queued`; live sends 0; queued `[m1]`; cancels 0; nothing reported.
- Edge case of: S-6811
### S-9711: only the newest snapshot of a workout waits
- Fixture: L apart; outstanding `[snap(s-1,m1), snap(s-2,m9), receipt r1, sc(s-1,c1,mX)]`.
- Trigger: send snap(s-1, m2).
- Expected: cancels exactly `[m1]`; outstanding afterwards `[m9, r1, mX, m2]`.
- Edge case of: S-9710
### S-9712: 100 sets while apart (overflow)
- Fixture: L apart; outstanding empty.
- Trigger: send snap(s-1, m1) … snap(s-1, m100) in sequence.
- Expected: after every send exactly one s-1 snapshot is outstanding; 99 cancels in total; final outstanding `[m100]`.
- Edge case of: S-9711
### S-9713 (supersedes S-6812's snapshot arm): a refused live snapshot is queued
- Fixture: L reachable; the live send of `session_snapshot` throws `send_failed`.
- Trigger: send snap(s-1, m1).
- Expected: one failure report; result `queued`; queued `[m1]`.
- Edge case of: S-6812
### S-9714: a live delivery clears older copies
- Fixture: L reachable; outstanding `[snap(s-1,m1), lc(s-1,'completed',mL), snap(s-2,m9)]`.
- Trigger: send snap(s-1, m2), delivered live.
- Expected: result `delivered`; cancels exactly `[m1]`.
- Edge case of: S-9711
### S-9715: clocks, requests and static frames are never queued
- Fixture: L apart.
- Trigger: send a `timer_state` for s-1; `WatchTransportRequest.snapshotFrame()`; a `routines_down`; an `exercises_down` batch.
- Expected: all four `undelivered`; queued 0; cancels 0 (the S-6811 timer/request arms and S-206 unchanged).
- Edge case of: S-6811
### S-9716: one finish per workout, repeats harmless
- Fixture: L apart; outstanding `[lc(s-1,'completed',mA), lc(s-2,'abandoned',mB)]`.
- Trigger: A: send lc(s-1,'completed',mC). B: send the same mC again.
- Expected: A cancels `[mA]` and queues mC. B: native answers `already_queued`, result `queued`, cancels 0, mC outstanding once. mB is never touched.
- Edge case of: none
### S-9717: edits are kept per change, in order
- Fixture: L apart; outstanding `[sc(s-1,c1,mX), sc(s-1,c2,mY)]`.
- Trigger: send sc(s-1, c1, mZ) (an owed deletion re-offered), then snap(s-1, mS).
- Expected: cancels exactly `[mX]`; queued order afterwards `[mY, mZ, mS]`, with the deletion ahead of the snapshot.
- Edge case of: S-120
### S-9718: never withdrawn
- Fixture: L apart; outstanding `[receipt r1, exercise_push(s-1, mP1)]`.
- Trigger: send exercise_push(s-1, mP2), snap(s-1, m1), lc(s-1, 'completed', mL).
- Expected: r1 and mP1 remain; mP2 queued; no cancel names r1, mP1 or mP2.
- Edge case of: S-6810
### S-9719: failures
- Fixture: L apart; outstanding `[snap(s-1,m1)]`. A: the outstanding read throws. B: the cancel throws. C: the queue throws.
- Trigger: send snap(s-1, m2).
- Expected: A one report, m2 queued, result `queued`. B one report, m2 queued. C one report, result `undelivered`.
- Edge case of: S-9711
### S-9720: a queued copy keeps the debt
- Fixture: a graph from `createWatchSync` over L (apart); `MockWorkoutRepository` with an active phone session s-1 holding one logged set; `WorkoutState` bound to the auto push.
- Trigger: log a second set; let the push window close; log a third set; let it close.
- Expected: two snapshot sends, both `queued`; `autoPush.hasUnsentChange()` stays true after each; exactly one s-1 snapshot outstanding (the newest, carrying three sets).
- Edge case of: S-200 (plan 19b)
### S-9721: the devices meet
- Fixture: S-9720 after its trigger; then `reachable = true`.
- Trigger: a wrist `routines` request frame arrives (the wrist opened its app).
- Expected: the owed snapshot is delivered live; the outstanding s-1 snapshot is withdrawn; `hasUnsentChange()` is false; no second live snapshot follows.
- Edge case of: S-9720
### S-9722: a watch food log while apart
- Fixture: a graph over L (apart); `MockWorkoutRepository` holding food "Apple" (`food-apple`, reference 100 g); no session.
- Trigger: an `observations_up` from the wrist with one nutrition quick-log of `food-apple`, 2 servings. The same frame is delivered a second time (duplicate).
- Expected: the day log holds one Apple row of 200 g (the duplicate updates the same row); the `receipt` naming that entry is queued, result `queued`, and the duplicate's receipt dedups or replaces nothing else; no `foods_down` is sent or queued.
- Edge case of: S-6810
### S-9723: static data is never pushed
- Fixture: a graph over L, reachable; settings rest ping 30; routine `tpl-1` "Push A"; foods Apple, Oats.
- Trigger: rest ping 30 → 45, add food "Rice", rename `tpl-1`; advance the injected clock 10 s.
- Expected: 0 static frames (`*_down`) sent or queued.
- Edge case of: none

## Iteration 1

### Phase 1: the native link lists and withdraws transfers (@developer) — may start now
1. [ ] Add `outstandingTransfers` and `cancelTransfers` (D-8) — `packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift` · `handle`
2. [ ] Dart API for both, plus a value type in the package — `packages/omnitrain_watch_link/lib/watch_link.dart` · `WatchLink`
3. [ ] Core capability interface and value type (D-9) — new file under `lib/core/platform/` (suggested `watch_queue_control.dart`)
4. [ ] `WatchConnectivityChannel` implements it — `lib/core/platform/watch_connectivity_channel.dart`
5. [ ] Tests S-9701, S-9702 — `test/watch_link_package_test.dart`; S-9703 — `test/watch_connectivity_channel_test.dart`
6. [ ] README: the two methods — `packages/omnitrain_watch_link/README.md`

**Done Criteria**:
- `flutter analyze`: issue count ≤ the baseline recorded in evidence.
- `flutter test test/watch_link_package_test.dart test/watch_connectivity_channel_test.dart`.
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter build ios --simulator --no-codesign` succeeds (Copilot: the gateway's `build`).
- The S-9703 grep prints one path.

**Predicted Files**: the paths above plus the new interface file.

### Phase 2: the phone queues its workout messages (@developer) — only when G-0 prints nothing
1. [ ] Run G-0 (series index) and paste its empty output into evidence.
2. [ ] Queue policy D-2…D-6 in `WatchConnectivityTransport.send` / `_queue` / `isDurable`, using the D-9 capability when the channel has it — `lib/core/platform/watch_transport.dart`
3. [ ] Supersede the S-6811/S-6812 snapshot arms with S-9710/S-9713; add S-9711, S-9712, S-9714…S-9719 — `test/watch_transport_test.dart`
4. [ ] S-9720…S-9723 over a real graph — new `test/watch_session_queue_test.dart` (plain `test()`; inject the clock; no real `Future.delayed`)
5. [ ] PROTOCOL amendment row and note (D-10) — `watch/sync_protocol/PROTOCOL.md`
6. [ ] Docs: in "The phone's link" (45.8 KB, stays < 52 KB), rewrite "A frame owed for good can be queued" to the D-2/D-3 rules and add the two native methods — `docs/state_management/watch_surface.md`; the plugin README if semantics changed
7. [ ] Residue sweep. Each must be empty:
   - `grep -rn "is true exactly for .receipt." docs/state_management`;
   - `grep -rn "=> *frame\['type'\] == 'receipt';" lib/core/platform/watch_transport.dart`.
8. [ ] Re-run the Impact suites unchanged.

**Done Criteria**:
- `flutter analyze` ≤ baseline.
- `flutter test test/watch_transport_test.dart test/watch_session_queue_test.dart test/watch_message_order_test.dart test/watch_session_auto_push_test.dart test/watch_timer_push_test.dart test/live_mirroring_test.dart test/watch_session_projection_test.dart test/settings_watch_status_test.dart`.
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter test` full suite (paste the counts).
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`.
- The invariant grep (AGENTS.md) is empty.
- Each new S-97xx is shown red once with its rule removed (stash/restore; table in evidence).

**Predicted Files**: `lib/core/platform/watch_transport.dart`, `test/watch_transport_test.dart`, `test/watch_session_queue_test.dart`, `watch/sync_protocol/PROTOCOL.md`, `docs/state_management/watch_surface.md`; `packages/omnitrain_watch_link/README.md` only if needed.

## Verification (Code Reviewer)

- Diff vs Predicted Files per phase; per-S test conformance to the fixtures; Impact greps re-run.
- Each of these mutations must turn a test red:

| Mutation | Test that must fail |
|---|---|
| withdraw ignores `sessionId` | S-9711 |
| withdraw ignores `changeId` | S-9717 |
| `receipt` or `exercise_push` withdrawn | S-9718 |
| `timer_state` or a static frame queued | S-9715 |
| `queued` treated as delivered by the push | S-9720 |
| no withdraw after a live delivery | S-9714 / S-9721 |
| a list-read failure skips the queue | S-9719 A |

## Owner device checks (owner, after Phase 2)

1. Start a workout on the phone, close the watch app, log three sets on the phone, open the watch app: it shows the three sets.
2. Watch out of reach (another room, or Bluetooth off on the watch): delete a set, then finish the workout on the phone. Bring the watch back and open the app: the set is gone and the workout has ended.
3. Log a food on the watch with the phone out of reach. Bring them together and open the phone app: the food is in today's log once. (Plan 47a left the OS delivering to a closed phone app unverified; this is that check.)

## Files Affected

Phase lists above. Dependents that only read a touched surface: the auto-push, timer-push, live-mirroring and projection suites; `lib/state/watch/watch_sync_wiring.dart` (reads `WatchDelivery`, unchanged).

## Notes

- Dependency graph: Phase 1 → Phase 2. G-0 gates Phase 2 only, and only as a file-collision gate: the new scope has no functional dependency on plans 61/62.
- Intermediate state: after Phase 1 nothing calls the new methods, so the app's behaviour is unchanged.
- Known and left:
  - The wrist's own workout messages are 67b.
  - A static change made on the phone while the watch app stays on screen and in reach waits for the next raise.
  - A phone with no foods sends no `foods_down`, so the wrist keeps foods the phone deleted (plan 62 rule).
- iOS only: Android has no watch transport.

## Progress

- Phase 1: built 2026-10-23, uncommitted (two crew runs, evidence in `…evidence.md`); the Phase 1 Done Criteria are all observed green. Owner device check: none for this phase.
- Phase 2: not started (gated by G-0).

## Assumption Log

## Feedback
