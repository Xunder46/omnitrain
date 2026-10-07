# Series: watch-auto-sync — "anything about the running session syncs by itself"

> Status: DRAFT (index + full PR 1, which the governor split into PR 1a = Phases 1–2 and PR 1b =
> Phase 3; PR 2 and PR 3 outlined)
> Next handoff: @developer (PR 1a, Phase 1)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`
> Supersedes: `docs/plans/2026-10-05-15-watch-session-sync-index.md` decision 4 ("Sync stays manual /
> watch-initiated") and the tail of its decision 2 ("A later series adds auto-sync") — this is that series.
> Numbering: **D-70…** / **S-70…** (D-58…D-69 = the parallel negative-load plan;
> D-43…D-57 = watch-session-sync PR 4). PR 1 uses D-75…D-86 and S-70…S-88; PR 2 uses **D-90…D-102 and
> S-100…S-115**; PR 3 therefore starts at **D-110… and S-130…** (its old D-95…/S-100… reservation is
> now occupied by PR 2).

## Goal

Nobody should ever have to press Sync while a session is running. Whatever either device does to the
running session — start it, add or change an exercise, log, edit or delete a set, move the current
exercise, finish or discard it — is on the other device by itself. The Sync button stays, is labelled
just **Sync**, and is left for the two things that are not active-session work: a device that was out
of reach, and the routine list.

The owner's words (2026-10-06):

> "Auto Sync should work essentially for any action, starting / editing / finishing a session /
> exercise / set. If a user is adding something on the phone or the watch they shouldn't ever need to
> click the Sync button. The button should just say 'Sync' from now on, it should only Sync in case a
> device was out of reach or if the routine list was modified in any way; anything active-session
> related should autosync."

Read as: **both directions**; **every active-session action**; the Sync button stays as the manual
fallback (out-of-reach, routines); **no new phone screens, modals or buttons**; and a session conflict
stays silent — each device keeps its own session when both hold one with exercises (15-series D-10).

## Owner decisions, and what this series does with each

| # | The owner's decision | What the series does |
|---|---|---|
| a | Both directions | PR 1 makes phone → watch automatic. Watch → phone is **already automatic** for every action the wrist can take today (see the baseline table): the wrist's frames are emitted as the user acts. PR 2 closes the two gaps the baseline shows: the wrist's own picker add is silent, and nothing is retried when a device was out of reach. |
| b | Every active-session action | PR 1: start, add an exercise, log/edit a set, move the current exercise, finish, discard. PR 2: the wrist's silent add, the catch-up. PR 3: what the wire cannot carry yet — deletions, the phone's `timed`/`hold`/`round` entries, a `skipped` set, the phone's rest timer (the 15-index's PR 5 row). |
| c | The button reads "Sync"; "No automatic sync" goes | PR 1a (Phase 1). The button's action does not change: it stays the manual fallback and the routine refresh. |
| d | No new phone screens, modals or buttons | Every PR. Nothing in this series adds a surface; the push is a state-layer listener. |
| e | A conflict stays silent — each keeps its own | PR 1 (D-78): the wrist refuses a snapshot naming another session while it holds an active session with a ladder, and says nothing at all. |

## Baseline — what is automatic today, per direction

This table is the series' starting point. It comes from the emission sites, read in code:
`WatchEmitForwarder` (`watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift:65`) forwards
every `onEmit` call, and `WatchSessionEngine.emit` (`…WatchSessionEngine.swift:1584`) is called by
`emitLifecycle` (`:977`, reached from `createSession` `:273` and `transitionTo` `:951`) and by the
observation and timer builders (`:1534` `observations_up`, `:1551` `timer_state`).

| The action | Wrist → phone today | Phone → wrist today |
|---|---|---|
| Start a session | **Only the frame** — `createSession` → `session_lifecycle started` is emitted by itself, but the phone adopts a session only from a `session_snapshot`, and the wrist sends its snapshot at its own Sync, so a wrist-started session becomes the phone's only then (**PR 2**) | Not at all (the wrist hears it at its next Sync) |
| Add an exercise | **Only locally**: a picker add emits nothing (`WatchStartPaths.addExerciseToSession:375` → `insertExercise` → `transitionTo(…, lifecycle: nil)` at `:359`), so the phone learns of it only from the snapshot the wrist sends at its own Sync (**PR 2**) | Silent; the phone's own structure changes wait for a Sync, and an add sent deliberately is a manual "send to watch session" (`exercise_push`) — **PR 1** (D-75) pushes the phone's own adds by itself |
| Change the current exercise | **Automatic** — `advanceExercise`/`selectExercise` → `session_lifecycle exercise_advanced` | Not at all (a Sync answer carries the phone's own projection, which today means slot 0 — see PR 1 D-77) — **PR 1** (D-75, D-77) pushes it, keeping the wrist's own place |
| Log a set | **Automatic** — `appendObservation` → `observations_up`; the phone confirms with a `receipt` | Not at all until a Sync — **PR 1** (D-75) pushes it by itself |
| Edit a set | Not carried (an observation is asserted once) | **PR 3** (15-series D-38/D-39) |
| Delete a set | Not carried (the wrist cannot delete) | Not carried; **PR 3** (15-series D-38) |
| Rest timer | **Automatic** — `appendTimer` → `timer_state` | Not carried (15-series D-26); **PR 3** |
| Finish the session | **Automatic** — `finishSession` → `session_lifecycle completed` | Not at all (the phone's finish is silent — 15-series D-16/"G2"); **PR 1** (D-81) |
| Discard the session | **Automatic** — `abandonSession` → `session_lifecycle abandoned` | Not at all; **PR 1** (D-81) |
| End-of-session rating | Automatic — captured at the session's end (`captureSessionEnd` + the rating rows; verified by `WatchCaptureContractTests`) | Not applicable (the rating is the wrist's) |
| Nutrition quick-log | Automatic (its own message type) | Not applicable |
| Routines / preferences / food catalog | The phone answers a `routines` request with `preferences_down` + `routines_down` (`WatchSyncRequestHandler._sendRoutines`) | **Stays manual** (D-72) |

The phone never sent its own session unasked before this series; `docs/watch_session_sync.md:145`
records it ("The phone's finish is silent") and the 15-series PR 1 evidence keeps a mutation check
whose whole point is that the phone's finish must *not* be announced. PR 1 reverses exactly that, and
names the two test files that pin it.

## The contract decisions (series level)

- **D-70 — A conflict stays silent; each device keeps its own session.** When both devices hold their
  own active session with a ladder, neither adopts the other's; the refusal is silent to the user (no
  prompt, no card, no error). The phone's half already exists (15-series D-10, `consider` →
  `refusedConflict`); PR 1 adds the wrist's half (D-78). Elaborated by D-78.
- **D-71 — Transport: live frames are fire-and-forget over the existing radio; nothing is queued.**
  A frame the radio cannot carry is dropped (the transport already catches and reports it —
  `WatchConnectivityTransport.send`, `lib/core/platform/watch_transport.dart`), the protocol's
  idempotency absorbs a frame that arrives late or twice, and what a peer missed is re-sent from
  storage by that peer's own catch-up (PR 2). **Amended 2026-10-06 (rev 1):** the transport's
  newest-state channel is verified available — `watch_connectivity` 0.2.8 exposes `isSupported`,
  `isPaired`, `isReachable`, `messageStream`, `sendMessage(Map)`, `updateApplicationContext(Map)`,
  `applicationContext`, `receivedApplicationContexts` and `contextStream` (it does **not** expose
  `transferUserInfo`) — so PR 2 must evaluate publishing each device's latest `session_snapshot` as an
  application context **first**, against the wrist-side catch-up it outlines today. PR 1 keeps
  `sendMessage` for its push. Elaborated by PR 1's D-83. **Amended 2026-10-06 (rev 2, PR 2):** the
  evaluation was made and the answer is **no, not in PR 2** (PR 2's D-97) — the watch shell implements
  `didReceiveMessage` only (no `didReceiveApplicationContext`, `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`),
  a context is latest-wins, so it cannot carry the
  ordered set of unacknowledged observations the protocol requires ("On sync, a wrist MUST re-send every
  observation the phone has not acknowledged … in the order it stored them") — the newest replaces, it
  does not extend, the backlog — and an entry-heavy session
  risks the undocumented context size limit; both receiving halves would also be new platform surface
  (the phone has no `contextStream` listener in `lib/core/platform/watch_connectivity_channel.dart`).
  (WatchConnectivity does deliver the newest context to the peer when its app next runs — that is not
  the reason.) PR 2 catches up over `sendMessage`, driven by the wrist's
  existing storage replay and its reachability edge. The channel stays available for a later PR: a
  latest-state context for the phone → watch direction alone is a viable later optimisation.
- **D-72 — Routines, preferences and the food catalog stay watch-requested.** Automatic sync never
  carries reference data; the Sync button and the app's existing request paths own it.
- **D-73 — Each device keeps its own rest countdown.** Incoming session state never stops a timer the
  receiver started itself. Elaborated by PR 1's D-80.
- **D-74 — The button is labelled "Sync"; no new surface is added for any of this.** The start
  surface stops claiming that sync is not automatic. Elaborated by PR 1's D-84.

## Decomposition

| PR | Scope | Track(s) | User-visible result, in plain words |
|---|---|---|---|
| **17a (PR 1a)** | The contract amendment (PROTOCOL, 2026-10-06), the start-surface copy ("Sync"; "No automatic sync" deleted), the wrist's acceptance rules — D-78 refuses a foreign snapshot silently, D-79 guards every session-scoped apply, D-80 gives each device its own rest countdown — and the wrist's own rest countdown surviving a snapshot. | `watch/sync_protocol/` + `watch/contract/` + `watch/watchos/` + `lib/watch/` | *(nothing visible on its own: the wrist is made safe before the phone starts pushing. 1a ships with 1b; a release carrying the push without these rules is not shippable.)* |
| **17a (PR 1b)** | The phone's push — one seam (D-75), the coalescing trigger (D-76), the place-keeping projection (D-77), the end pushed (D-81, keyed on the mirrored session's repository row), the re-baseline (D-82), dropped-never-queued (D-83) — and the behaviour docs. | `lib/` + `docs/` | **Work you do on the phone about the running session — add an exercise, log or correct a set, finish, discard — appears on the watch by itself.** The watch's own session is never taken away by the phone, and each device keeps its own rest countdown. Nothing needs tapping. |
| **17b (PR 2)** — **planned 2026-10-06**: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md` (D-90…D-103, S-100…S-115) | The wrist announces its own session: the engine emits its own `session_snapshot` on start and on a ladder change the **wrist's user** made (D-90/D-91), and a wrist-originated structure change now moves `revision` (D-101) — so a wrist-started session and a wrist add become the phone's without the button. The phone reconciles a wrist snapshot naming the session it already holds: **add-only**, in the snapshot's order, never a delete or a reorder, never re-adding a slot the phone removed, never clearing a timer (D-92/D-93/D-94/D-95 — 17a's `consider` returns `alreadyHeld` and drops the frame today). Catch-up by itself in both directions: the wrist on the reachability edge, gated on holding a session, one sync at a time via a tested `WatchSyncOrchestrator.catchUp(reachable:)` (D-96), and the phone on resume through a `WatchResumeSync` observer. **The application-context evaluation (D-71's amendment) is done and its outcome is D-97: not in PR 2** — the receiving halves would be new platform surface (no `didReceiveApplicationContext` in the shell, no `contextStream` listener on the phone), a context is latest-wins and so cannot carry the ordered owed observations the protocol requires, and the size limit is undocumented; a latest-state context for the phone → watch direction alone stays a viable later optimisation. Carried out of 17a's review: the push's drain bounded against a hung send (G6 → D-98) and the timer path's unhandled error (H5 → D-99); the Dart `captureSessionEnd` question closed as a recorded rule, not built (A-8 → D-100); the late-adoption push window closed by the phone-side resume trigger (F3/A-17 → D-96). Routines stay manual. Phases 1–4 are agent-built; Phase 5 (one call site in the watch shell) is governor-built. | `watch/watchos/` + `ios/` shell + `lib/` + `docs/` | **A watch that was out of range for a while catches up on its own when it is back** — nothing is lost and nothing needs tapping. **A session started on the watch, and an exercise added on the watch, reach the phone by themselves instead of at a Sync.** The Sync button remains the manual fallback. |
| **17c (PR 3)** | What "any action" still cannot carry: a deletion reaching the wrist (`structure_change` `delete_entry`, no phone sender yet), the phone's `timed` / `hold` / `round` entries, a set the wire omits today (`skipped`, `extraLoadKg`), and the phone's rest timer (the 15-index's PR 5 row). | `lib/` + `watch/sync_protocol/` (+ `watch/watchos/` if a receiver rule is needed) | **Deleting a set on the phone removes it on the watch, and the other kinds of work the phone can log — holds, timed sets, rounds — show up there too.** |

Each row's budget: 17a/1a = 2 phases (the contract + the `watch/` tracks), 17a/1b = 1 phase (`lib/` +
docs) — one plan file, one set of ids (the governor's split note in the PR 1 plan). The governor split
1a/1b on 2026-10-06 on three soft signals: the plan runs over 500 lines, it touches three tracks, and
it amends the contract. PR 2 = 5 phases (Phases 3 and 4 are the Dart and Swift halves of one workstream), 2 tracks; PR 3 = 3 phases, 2 tracks. All within
`.github/copilot/pr-scope-budget.md`; the hard limits are 800 lines / 5 phases / 1500 production
lines.

## Order and dependency graph

```
17a (PR 1: the phone pushes, the wrist accepts)
 ├── 1a (Phases 1–2: the contract amendment, the copy, the wrist's acceptance rules)   [ships with 1b]
 ├── 1b (Phase 3: the phone's push + the behaviour docs)   [needs 1a: the wrist must accept a push before a push reaches it]
 ├── 17b (PR 2: automatic catch-up, the wrist's silent adds)   [needs 17a]
 └── 17c (PR 3: deletions + the other entry kinds)             [needs 17a: entries travel in the push]
```

- **1a must land with or before 1b.** A phone that pushes while the wrist still applies a foreign
  snapshot wholesale would take a session away from a wrist that has its own — a data-loss defect,
  not a cosmetic one. A release that carried the push without the wrist's rules is not shippable;
  the plan marks this explicitly.
- **17b and 17c are independent of each other** and can land in either order. 17b is worth more
  (a device out of reach is the case the owner named), so it is planned next.
- Re-ordering with its trade-off: running 17c's entries-and-deletions first would make an edit of a
  phone set reach the wrist sooner, but it leaves the owner's most visible complaint — the button
  and the manual step — in place for one more PR. Not recommended.

## Transport: how a frame gets there when the other device is not reachable (D-71)

**Decision: fire-and-forget `sendMessage` for live frames, and a self-driven catch-up by the peer that
was behind.** PR 1's push goes by `sendMessage`; PR 2 must evaluate `updateApplicationContext`
(latest-state delivery) as its first option (below).

Evidence, from this repository:

- `lib/core/platform/watch_transport.dart` header, rule 2: *"Fire-and-forget, with the protocol doing
  the recovering. There is no queue here by design: a frame the radio cannot carry right now is
  reported and dropped, and what the peer still owes is re-sent from storage on the next sync"* — the
  transport's own contract already says a send failure is reported, not queued.
- `WatchConnectivityTransport.send` catches the failure and passes it to `onFailure`; it never throws
  into a caller. So an automatic push while the watch is unreachable is safe by construction.
- `sendMessage` is only delivered while both apps are up and the watch is reachable
  (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`, the `sendMessage`-only path with
  `phoneNotReachable`). That is exactly the case in which a user is acting on both devices.
- Idempotency is already the protocol's rule: a `changeId` applies at most once, an observation
  carries its own id, a snapshot merges entries by `entryId`, and a snapshot is never answered with an
  equal one. A late or duplicated frame is therefore a no-op, not a corruption.

Rejected alternatives:

1. **`updateApplicationContext` (latest-state delivery) — rejected for PR 1's live frames, but PR 2's
   first candidate.** The governor read `~/.pub-cache/hosted/pub.dev/watch_connectivity-0.2.8` and its
   platform interface 0.4.0: the plugin exposes `isSupported`, `isPaired`, `isReachable`,
   `messageStream`, `sendMessage(Map)`, `updateApplicationContext(Map)`, `applicationContext`,
   `receivedApplicationContexts` and `contextStream`, and does **not** expose `transferUserInfo`.
   WatchConnectivity hands the newest context to the peer when the peer app next runs, even if it was
   out of reach when it was sent, and a newer context replaces an older one — a per-device *latest
   state*, not a queue, so it does not violate the rule this section pins. PR 2 must evaluate it
   **first**, against the wrist-side catch-up (on launch and on reachability) it outlines today,
   publishing each device's latest `session_snapshot` — the phone's push, and the wrist's own
   snapshot, which carries its entries. Trade-offs verifiable today: the protocol's merge is
   idempotent, so a duplicate context is harmless; a context has no documented hard size limit but
   should stay small (a ladder and its `set` entries, no timers) and the projection is already a
   compact map; the watch would need a `didReceiveApplicationContext` implementation in
   `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift` (a governor-built shell — agents may not
   add target code there) and the phone a `contextStream` listener in
   `lib/core/platform/watch_connectivity_channel.dart`. Not used in PR 1: its push stays
   `sendMessage` (low latency, dropped when unreachable — D-83).
2. **A bounded retry on the phone.** Retrying needs a clock, a queue and a drop policy — the state
   layer re-invented — and the peer's own catch-up delivers the same outcome for less.
3. **A reachability-driven push from the phone.** The phone's transport tracks reachability
   (`refreshReachability`, `isPhoneReachable`) but exposes no change stream; polling it to drive
   pushes is more machinery than the wrist asking once when it comes back.

What that means for frames that arrive late or twice: nothing special — the protocol is idempotent by
design (a push carries the same `messageId`-derived row ids, and the entry ids the phone minted).
What that means for battery: the watch does not poll; it sends when the user acts and (PR 2) once when
reachability returns.

## Rest timers: each device keeps its own (D-73, elaborated as PR 1's D-80)

Today a Sync stops a running wrist rest countdown: the phone's answer carries `'timers': const {}`
(`WatchSessionAdoptionBridge.projectSession`) and a snapshot is authoritative for timers as a whole
(`WatchSessionEngine.adoptTimers(…, authoritative: true)` at `:619` stops every kind the message does
not name). With a push after every set that would kill the countdown constantly, so it must change.

- **(A) Each device keeps its own rest timer** — recommended, and what PR 1 does. An authoritative
  snapshot (and a `timer_state`) stops only the kinds whose newest row the *sender* wrote (row-id
  prefix `tms-`, `WatchSessionEngine.swift:49`); a kind the wrist started itself is never stopped or
  replaced by incoming state. The wrist's countdown survives every push.
- **(B) The rest timer is shared and carried both ways** — rejected for PR 1: the phone's rest timer
  is not carried at all today (15-series D-26), the two devices can hold different rest lengths, and
  making one device's countdown the other's authority is a contract change of its own (PR 3).

## Deletions and the phone's other entry kinds (PR 3)

`structure_change` already has `delete_entry` and `correct_entry`; the phone has no sender for a
deletion (15-series D-38), and the phone's projection carries only `set` entries (D-39). The wire has
no `skipped`. All of it is "an action the user took on the running session that the other device
never hears about", so it belongs in this series, in its own PR, after the push exists.

## Out of reach: what the user sees

- **Nothing new on the phone.** No banner, no retry indicator, no queue: a frame the radio could not
  carry is dropped (D-71). This is the owner's explicit exemption ("it should only Sync in case a
  device was out of reach").
- **On the watch, the existing Sync button and the existing "Phone not reachable" line**
  (`WatchStartSurfaceCopy.unreachableLabel`, `WatchStartPaths.swift:52`). Neither changes in this
  series.
- **When reachability returns: the device catches up by itself** (PR 2 — the wrist re-sends what it
  owes and asks for the phone's state; `updateApplicationContext` is PR 2's first candidate, D-71's
  amendment). The button stays as the manual fallback. This is an owner question with that default
  (below).

## How many frames one action costs, and why nothing ping-pongs

- One set logged on the phone = one `session_snapshot` (the push). The next set is another one. A
  burst of changes (adding three exercises in a second) is coalesced into one frame by a short
  trailing window (PR 1's D-75/D-76).
- A wrist frame that the phone applies is never pushed straight back: the phone re-baselines what it
  composed (PR 1's D-82), and a set the wrist logged is not in the phone's own projection to begin
  with (15-series D-34 — the phone projects only the entries it logged itself).
- A snapshot is never answered with an equal one (`LiveSessionMirrorState._shapeDiffers`: an
  entry-only difference is no difference) — that rule is kept as it is.
- A timer tick on the phone changes nothing in the composed payload, so the push compares payloads
  and sends nothing (a rest countdown on the phone costs zero frames).

## Documentation debt this series creates

| Doc | What is stale after this series | PR |
|---|---|---|
| `docs/watch_session_sync.md` | "Starting a session, changing exercises and converging two sessions still need a manual Sync"; "The phone's finish is silent" (`:145`); the D-26 rest-timer bullet ("a Sync stops a running wrist rest countdown" — 1a's D-80); "a delete does not reach the wrist" and "only sets are carried" (PR 3) | 17a/1b, 17c |
| `docs/state_management/watch_surface.md` | the "no automatic sync" claim (`:336`) and the D-11 sentence about `projectedSession` (`:81`) | 17a/1b |
| `docs/watch-app-setup-and-qa.md` | walkthrough step 1 ("The watch says it does not auto-sync") and every step that says "tap Sync" as a *logging* step (`:345-380`); the recovery and routine steps stay but must say what they are for | 17a/1a |
| `watch/sync_protocol/PROTOCOL.md` | the amendment of 2026-10-06 (a peer may send a session frame unasked; a frame applies only to the session it names; a receiver keeps its own session; timer ownership). v1 is unreleased, so it is additive with no version bump and no migration | 17a/1a, 17c |
| `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md` | after 17b: "Starting a session, changing exercises and converging two sessions still need a manual Sync"; the walkthrough's "the wrist's session reaches the phone at a Sync" step (`:342-345`) and its "catches up at the next Sync" note (`:500-503`); the wrist's own announcements and the add-only reconcile rule are stated where the adoption rules are. Also records 17b's D-102 heads-up (an unended wrist session keeps blocking a new phone session on the watch) | 17b |

## Folders and numbering

- `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/` — **used** (this series' PR 1: plan, evidence,
  review).
- `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/` — **used** by PR 2 when it is planned.
- `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/` — **used** by PR 3 when it is planned.
- None of the three is unused; nothing needs removing.
- Decision and scenario numbers: series contract D-70…D-74; PR 1 D-75…D-86, S-70…S-88 (its iteration 2
  consumed the old "PR 2 reserved D-85…/S-90…" range); PR 2 **D-90…D-103, S-100…S-115**; PR 3 must
  therefore start at **D-110… and S-130…** — its old reservation (D-95…, S-100…) now collides with
  PR 2 on both, so a PR 3 planner must not reuse those ids.

## Open questions (owner)

1. **A rest countdown, when the other device sends news.** Recommended (and planned as PR 1's D-80):
   each device keeps its own countdown, so a set logged elsewhere never stops the "X left" line on
   the wrist. The alternative is one shared countdown over both devices.
2. **A device that was out of reach.** Recommended: it catches up by itself (PR 2) — launching the
   watch app, or the connection coming back, is enough; the Sync button stays for forcing it. The
   alternative is the button staying the only way back.
3. **The end of the session.** Recommended: finishing or discarding on the phone reaches the watch by
   itself (PR 1's D-81), so the watch stops showing a live session the phone already closed. Today
   the watch only learns it at its next Sync.
4. **What the Sync button still does.** Recommended: exactly two things — recover a device that was
   out of reach, and refresh the routine list. Everything else is automatic.
5. **The button's words.** "Sync" (the owner's decision); the watch's "No automatic sync" line goes
   **and is not replaced** — the button needs no subtitle, and "Phone not reachable" already covers the
   one case it is still for. "No routines yet. Sync with your phone to get them." stays. (PR 1's D-84.)
6. **PR 2 — a device that was out of reach.** **Answered 2026-10-06 (PR 2 planned):** a device that was
   out of reach receives the latest state **by itself** when it is back — the wrist on the reachability
   edge (gated on the wrist holding a session, one sync at a time), the phone on resume, both over the
   existing radio (PR 2's D-96) — and the Sync button stays for forcing it. The application-context
   route was evaluated and deferred (D-71 rev 2, PR 2's D-97). Alternative: it only catches up when you
   tap **Sync**.
7. **PR 2 — a wrist session left active.** Recommended: leave it (PR 2's D-102). While the wrist holds
   its own active session it still refuses a phone session for a different id (D-78), so a session
   started on the phone afterwards does not appear on the watch until the wrist's own session ends. The
   alternative silently discards work done on the wrist. **Heads-up, not a defect** — no change planned.
8. **PR 2 — what the wrist's automatic catch-up fetches.** Recommended: the whole Sync call (the session
   *and* routines/settings), gated on the wrist holding a session, so a fresh wrist still fetches nothing
   until asked. Alternative: a session-only sync, which would be a new request kind in the contract.
9. **PR 2 — where a wrist-added exercise lands on the phone.** Recommended: appended after the phone's
   known slots, in the wrist's order, never reordering the phone's own (the phone is the structure
   authority). Alternative: inserted at the wrist's own index.

## Open questions (technical — not owner-visible)

1. **`watch_connectivity` 0.2.8's API — verified 2026-10-06.** The governor read
   `~/.pub-cache/hosted/pub.dev/watch_connectivity-0.2.8` and its platform interface 0.4.0: the plugin
   exposes `isSupported`, `isPaired`, `isReachable`, `messageStream`, `sendMessage(Map)`,
   `updateApplicationContext(Map)`, `applicationContext`, `receivedApplicationContexts` and
   `contextStream`; it does **not** expose `transferUserInfo`. PR 1 needs none of the new members — its
   push goes by `sendMessage` (D-71/D-83) — and PR 2's first evaluation is `updateApplicationContext`
   (D-71's amendment and "Transport" above). The app's own use today is `isPaired`, `isReachable`,
   `messageStream`, `sendMessage` (`lib/core/platform/watch_connectivity_channel.dart`), pinned at
   0.2.8 by `pubspec.lock`.
2. **The Dart twins must move with the Swift.** `lib/watch/session/watch_session_engine.dart` mirrors
   the Swift engine's apply rules and `lib/watch/start/watch_start_screen.dart` mirrors its copy. PR 1
   changes both stacks in one phase; a reviewer should treat a Swift-only rule as a finding.
3. **The end-of-session rating's exact frame** on the wrist → phone path was not read line by line for
   this series (it is automatic today and this series does not change it). PR 2 should confirm it
   while it is in `WatchSessionEngine.captureSessionEnd`.

## See also

- Full PR 1 plan: `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/2026-10-06-17a-watch-auto-sync-pr1-plan.md`
- Superseded series: `docs/plans/2026-10-05-15-watch-session-sync-index.md` (its decision 4 and the tail
  of decision 2 now point here)
- Current behaviour: `docs/watch_session_sync.md`, `watch/sync_protocol/PROTOCOL.md`
- Parallel plan that lands first: `docs/plans/2026-10-06-16-watch-negative-load-plan/` (band assist)
