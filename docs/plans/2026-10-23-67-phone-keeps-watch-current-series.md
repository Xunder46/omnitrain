# Series 67 — workout and food-log messages wait for the other device instead of being dropped

> Status: Index. Re-shaped 2026-10-23 after the owner's answers to Q1-Q6, before any handoff. 67a is planned; 67b will be planned when its turn comes, against the code as it is by then.
> Binding: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.
> Owner (2026-10-23): "Only active sessions need to sync perfectly from one device to another, food logging sync as well on action, other static changes can require a sync button click." The phone gets no Sync button. The watch pulls static data itself.

## The rules the owner set

- **Automatic, on action, both directions:** everything about an active workout, and food logging. When the devices are apart or the other app is closed, these are queued through the OS, not dropped.
- **Never queued:** running clocks (`timer_state`) and requests.
- **Newest only** where a message is a replaceable state (a workout snapshot, a workout's finish); edits and deletions are kept per change. No age limit.
- **Static data is pulled by the watch, never pushed by the phone.** This covers routines, theme accent, units, rest ping, effort question, food list and default portions, and the exercise list.
- No background apply on the watch, and no "Update waiting" line.

## What the watch's pull already covers (checked 2026-10-23; nothing to plan)

- **Watch app opens or the wrist is raised:** `scenePhase == .active` → `WatchAppHost.catchUpOnActivation()` → `WatchSyncOrchestrator.catchUp(reachable:)`.
- **The phone becomes reachable again:** `bridge.onReachabilityChange` → `catchUp(reachable:)` (`ios/OmniTrain Watch App/ContentView.swift`).
- **The wrist's own Sync button:** `requestSync()` → a full re-send.
- **The phone's answer:** it reloads foods from storage every time (plan 53 D-7), so a phone-side food log's new default portion reaches the watch at the next raise. It sends settings, foods and routines only when they changed (plan 62), and the exercise list only when its version differs.

Only gap found, accepted rather than planned: a static change made on the phone while the watch app stays on screen and in reach waits for the next raise. Lowering and raising the wrist pulls it.

## PRs

| Order | PR | Scope (one line) | Track | Depends on |
|---|---|---|---|---|
| 1 | 67a `docs/plans/2026-10-23-67a-phone-queues-workout-messages-plan/` | The phone's native link can list and withdraw queued transfers. When the watch can't be reached, the phone queues its workout messages instead of dropping them: newest snapshot per workout, finish/discard, set edits/deletions, exercise pushes. The food-log path (watch log → phone receipt) is pinned end to end | phone (`lib/`, `packages/omnitrain_watch_link` iOS) + phone-sender contract amendment | Phase 2: file gate G-0 |
| 2 | 67b | The wrist queues its own workout messages when the phone can't be reached: its session snapshot (newest per workout, replacing older queued copies). Timers never. The wrist's sets, food logs and finish are already queued (plan 47b) | watch (`watch/watchos`, the watch app's WCSession seam) + wrist-sender contract amendment | 67a (same rules, Swift side) |

Withdrawn from the earlier drafts (never built):
- the phone's automatic push of static data;
- Settings Sync now and its messages;
- the "Update waiting" line;
- the separate exercise-list PR;
- the optional background-apply PR.

## Gate G-0 (67a Phase 2 only)

The new scope has no functional dependency on plans 61/62. What remains is a file-collision gate: Phase 2 edits four files that the uncommitted 61/62 work also modifies. G-0 must print nothing before Phase 2 starts:
`git status --porcelain -- lib/core/platform/watch_transport.dart test/watch_transport_test.dart watch/sync_protocol/PROTOCOL.md docs/state_management/watch_surface.md`
67a Phase 1 touches none of them and may start now. 67b will touch the watch app's WCSession file and the Swift bridge; its own gate is checked when it is planned.

## Decisions every PR shares (full text in 67a's ledger)

- D-1: a queued copy is a carrier, not a delivery. Only `delivered` advances a sender's bookkeeping (plan 19b stands).
- D-3: replacement keys. `session_snapshot` and `session_lifecycle` are keyed by (type, sessionId); `structure_change` by (type, sessionId, changeId). `receipt`, `observations_up` and `exercise_push` are never withdrawn.
- D-4: `timer_state` and requests are never queued; the static types are never queued or pushed by the phone.
- D-7: the OS queue (`transferUserInfo`) is the only queue; nothing is queued in the app layer.

## Progress

- 67a: planned 2026-10-23 (re-shaped). Next handoff: @developer (Phase 1).
- 67b: not planned.
