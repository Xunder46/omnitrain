# Series: watch-session-sync — "a session in progress is the same session on the phone and the watch"

> Status: DRAFT (index + full PR 1 + full PR 2a + full PR 2b; PR 1 and PR 2a implemented, base `612b356`)
> Next handoff: @developer (PR 2b, Phase 1 — the package's outgoing sink and the active-session guard)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`
> Builds on: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md` (UNCOMMITTED verified unit, base commit 373c39b)

## Goal

One shared in-progress session. A wrist-started session is the phone's normal in-progress
session (regular Free Session screen, picker, finish, home affordance), and a phone session is
the wrist's in-progress session. Both devices eventually log sets into the one session.

## Owner decisions (binding)

1. **True two-way logging** — both devices log sets into the one session.
2. **No conflict-resolution UI or merge logic.** When both devices already hold different
   sessions, each keeps its own until one is finished — nothing lost, no prompt — via R1's
   phone-policy guard above the protocol's replace-wholesale rule. A later series adds auto-sync.
3. **Remove all three phone-side watch surfaces**: the Watch Session screen, the home
   entry-point card (+ layout budget), and the picker "Send to watch session" icon.
4. **Sync stays manual / watch-initiated.**

## Decomposition

| PR | Scope | Track(s) | Notes |
|---|---|---|---|
| **1** | Phone-side convergence: remove the three surfaces; wrist session → phone's normal in-progress session; phone session → wrist's in-progress ladder. No set logging. | `lib/` (+ docs) | Full plan in this series. Its A33 deferred the merge of a held session's wrist rows to "the merge PR" (G3). |
| **2a** | **Merge a set the wrist logged into the session the phone holds** — the G3 gap PR 1 left. No wrist surface, no protocol change; inert until 2b ships. | `lib/` (+ docs) | Full plan in this series (replaces the old PR 2 outline). |
| **2b** | Host the wrist logging surface (set logging, End, rating prompt) over the in-memory store, and **wire the outgoing sink the engine already has** — `onEmit` exists and every emission point calls it, but `ios/OmniTrain Watch App/ContentView.swift` built the engine with no sink, so every frame was dropped until this PR wired it. | `watch/watchos/` (+ `ios/` shell) | Full plan in this series. Split out of PR 2 for the scope budget. Manual QA steps 15–18 of `docs/watch-app-setup-and-qa.md` become runnable here; step 17 additionally needs PR 4's durable store, and steps 19–20 stay Phase 8. |
| **3** | Phone → wrist set logging: a set logged on the phone appears on the wrist. The one contract decision. | `lib/` + `watch/watchos/` + `watch/sync_protocol/` | **Full plan in this series** (D-31…D-42, S-31…S-43; four phases), **split by scope into two PRs: 3a = Phases 1, 2, 4** (PROTOCOL amendment + fixtures, the phone's projection, the docs) and **3b = Phase 3** (the wrist takes a re-statement of an edited entry, with its PROTOCOL sentence and fixture case). 3a ships the headline — a phone-logged set reaches the wrist and the existing merge stores it — and leaves an edit to such a set sent-and-dropped until 3b. The contract decision landed as **(b)**: the phone's entries ride the existing `session_snapshot` answer — see the section below, which supersedes the `entries_down` proposal. |
| **4** | Durable wrist store (if still needed after PR 2/3). | `watch/watchos/` | Conditional. |
| **5** | What PR 3 left open: a deletion reaching the wrist (`structure_change` `delete_entry`, no phone sender yet), the phone's `timed`/`hold`/`round` entries, and the phone's rest timer. | `lib/` + `watch/sync_protocol/` | Named by PR 3's scope boundaries (D-38, D-39, D-42). Not planned yet. |

## Order and rationale

PR 1 must land first: the three surfaces are dead once the mirror is demoted to a transport
projection, and the removal is the visible, low-risk half. **PR 2a comes next**: PR 1's G3 leaves a
session the phone adopted missing every set the wrist logged in it, and that is the defect the
wrist's logging surface would otherwise ship into — 2a closes it while the code is still inert.
PR 2b then gives the wrist its logging screen. PR 3 closes the loop (phone-logged sets reach the
wrist) and is the only PR that touches the protocol. PR 4 is deferred and may be cancelled; PR 5
collects what PR 3 leaves open and is not yet planned.

## Dependency graph

- PR 1 → PR 2a (the merge resolves wrist rows onto the session identity and effort-row ids PR 1
  establishes, D-3).
- PR 1 → PR 2b (the wrist logging surface targets the same session identity PR 1 establishes).
- PR 2a → PR 2b (the wrist can log the day its screen arrives only if what it logs lands).
- PR 2a → PR 3 (PR 3's phone→wrist entries meet the merge on the same effort rows).
- PR 1 → PR 3 (PR 3 sends phone entries to the wrist's live session; needs PR 1's session identity).
- PR 2b → PR 3 (two-way set sync is testable only once the wrist can log at all).
- PR 3 → PR 4 (a durable store matters only once the wrist holds a session worth persisting).
- PR 2b and PR 3 are otherwise independent and could swap order; 2a may not move after 2b.

## The one hard-to-reverse contract decision (decided in PR 3)

**Decided: option (b).** The proposal below was `entries_down`, a new phone→wrist message family
mirroring `observations_up`. PR 3 supersedes it: a phone-logged entry travels in the **existing
`session_snapshot` answer's `entries` array**, and nothing on the wire changes shape.

Why the supersedure. The snapshot already is the carrier, end to end: `session_snapshot.schema.json`
already *requires* `entries`; `envelope.schema.json` `$defs.entry` already carries every metric a set
needs; `MessageValidator._snapshotRejections` already validates snapshot entries; both engines already
merge them by `entryId` (`WatchSessionEngine.applySnapshot` → `storeSnapshotEntry`) and already
confirm them; and `SyncSessionReconciler._applySnapshot` already merges and clears them on a session
switch. PROTOCOL.md already says entries "merge by `entryId`" and "come from whoever logged them".
The only gap was the phone's own answer, which hard-coded an empty `entries` list. `entries_down`
would have added a message type, two schemas, a validator profile, a receipt variant and per-entry
plumbing in both stacks to deliver the same merge — and PR 3's trigger is a manual Sync, which is a
snapshot exchange by definition. Alternative (c) — `structure_change` `correct_entry`/`delete_entry` —
cannot add an entry at all, and stays the mechanism for corrections and deletions.

What PR 3 therefore had to decide instead: **identity** (the phone mints `entry-<sessionExerciseId>-<n>`;
the wrist mints UUIDs, so the spaces cannot collide), **provenance** (the phone projects only the
entries it logged itself, claimed against the wrist's inbox stamps one-to-one, so a wrist-logged set is
never echoed back and doubled), and **re-statement** (the snapshot is authoritative for the entries it
carries, which is how an edit to a phone-logged set reaches the wrist while the wrist's store stays
append-only). PROTOCOL.md is amended additively for these, with no version bump. The full reasoning,
the alternatives and the rejections are D-31…D-42 of the PR 3 plan.

Owner-visible consequences are listed in the PR 3 plan's **Open questions**: deletions, the phone's
`timed`/`hold`/`round` entries, a phone set's added weight, a skipped set, and the phone's rest timer
(the last is the index's PR 5 row).

## See also

- Full PR 1 plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.md`
- Full PR 2a plan (the held-session merge, G3): `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan/2026-10-05-15b-watch-session-sync-pr2-plan.md`
- Full PR 2b plan (the wrist logging surface): `docs/plans/2026-10-05-15c-watch-session-sync-pr2b-plan/2026-10-05-15c-watch-session-sync-pr2b-plan.md`
  — its Overview corrects this index's PR 2b row and PR 2a's "What PR 2b carries": the engine's
  outgoing sink exists and was never wired.
- Full PR 3 plan (phone → wrist entries): `docs/plans/2026-10-05-15d-watch-session-sync-pr3-plan/2026-10-05-15d-watch-session-sync-pr3-plan.md`
  — its Overview and D-31 supersede this index's `entries_down` proposal; its Open questions list what
  PR 3 leaves open (the PR 5 row above).
