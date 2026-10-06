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
| **2b** | Host the wrist logging surface (set logging, End, rating prompt) over the in-memory store, and **wire the outgoing sink the engine already has** — `onEmit` exists and every emission point calls it, but `ios/OmniTrain Watch App/ContentView.swift` builds the engine with no sink, so every frame is dropped today. | `watch/watchos/` (+ `ios/` shell) | Full plan in this series. Split out of PR 2 for the scope budget. Manual QA steps 15–18 of `docs/watch-app-setup-and-qa.md` become runnable here; step 17 additionally needs PR 4's durable store, and steps 19–20 stay Phase 8. |
| **3** | Phone → wrist set logging: a set logged on the phone appears on the wrist. The one contract decision. | `lib/` + `watch/watchos/` + `watch/sync_protocol/` | Skeleton only; plan next. |
| **4** | Durable wrist store (if still needed after PR 2/3). | `watch/watchos/` | Conditional. |

## Order and rationale

PR 1 must land first: the three surfaces are dead once the mirror is demoted to a transport
projection, and the removal is the visible, low-risk half. **PR 2a comes next**: PR 1's G3 leaves a
session the phone adopted missing every set the wrist logged in it, and that is the defect the
wrist's logging surface would otherwise ship into — 2a closes it while the code is still inert.
PR 2b then gives the wrist its logging screen. PR 3 closes the loop (phone-logged sets reach the
wrist) and is the only PR that touches the protocol. PR 4 is deferred and may be cancelled.

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

## The one hard-to-reverse contract decision (lands in PR 3, proposed here)

Today PROTOCOL.md's authority rule is "phone owns structure; **entries are the wrist's to log**;
the phone corrects/deletes rather than adds." True two-way logging breaks the entries half. The
lowest-risk fix is a **new phone→wrist message family `entries_down`** that mirrors `observations_up`
(add/update/delete of one entry) and reuses the same idempotency keying and receipt ack. Alternatives:
(b) re-assert the whole session via `session_snapshot` (coarse, clobbers wrist's in-flight edits);
(c) relax the "phone never adds entries" rule in place (muddies the authority contract). Recommend (a).
Owner-visible consequence in **Open questions** (PR 1 file).

## See also

- Full PR 1 plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.md`
- Full PR 2a plan (the held-session merge, G3): `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan/2026-10-05-15b-watch-session-sync-pr2-plan.md`
- Full PR 2b plan (the wrist logging surface): `docs/plans/2026-10-05-15c-watch-session-sync-pr2b-plan/2026-10-05-15c-watch-session-sync-pr2b-plan.md`
  — its Overview corrects this index's PR 2b row and PR 2a's "What PR 2b carries": the engine's
  outgoing sink exists and was never wired.
