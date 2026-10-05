# Series: watch-session-sync — "a session in progress is the same session on the phone and the watch"

> Status: DRAFT awaiting Q&A (index + full PR 1 + PR 2 outline)
> Next handoff: @developer (PR 1, Phase 1)
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
| **1** | Phone-side convergence: remove the three surfaces; wrist session → phone's normal in-progress session; phone session → wrist's in-progress ladder. No set logging. | `lib/` (+ docs) | Full plan in this series. |
| **2** | Host the wrist logging surface (set logging, End, rating prompt) over the in-memory store. | `watch/watchos/` | Outline in this series. Wrist-logged sets already reach the phone via existing `observations_up` → inbox → import-on-end. |
| **3** | Phone → wrist set logging: a set logged on the phone appears on the wrist. The one contract decision. | `lib/` + `watch/watchos/` + `watch/sync_protocol/` | Skeleton only; plan next. |
| **4** | Durable wrist store (if still needed after PR 2/3). | `watch/watchos/` | Conditional. |

## Order and rationale

PR 1 must land first: the three surfaces are dead once the mirror is demoted to a transport
projection, and the removal is the visible, low-risk half. PR 2 gives the wrist a logging surface
so the shared session has two endpoints. PR 3 closes the loop (phone-logged sets reach the wrist)
and is the only PR that touches the protocol. PR 4 is deferred and may be cancelled.

## Dependency graph

- PR 1 → PR 2 (the wrist logging surface targets the same session identity PR 1 establishes).
- PR 1 → PR 3 (PR 3 sends phone entries to the wrist's live session; needs PR 1's session identity).
- PR 2 → PR 3 (two-way set sync is testable only once the wrist can log at all).
- PR 3 → PR 4 (a durable store matters only once the wrist holds a session worth persisting).
- PR 1 and PR 2 are otherwise independent and could swap order.

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
- PR 2 outline: `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan/2026-10-05-15b-watch-session-sync-pr2-plan.md`
