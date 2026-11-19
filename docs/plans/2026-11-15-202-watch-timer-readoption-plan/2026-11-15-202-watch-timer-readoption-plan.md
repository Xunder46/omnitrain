# Feature: 202 — watch: a phone frame never restarts a timer interval the wrist already ran (ghost holds, extra rest pings)

> Status: SEEDED by the governor 2026-11-15; the architect step is skipped (see Assumption Log A-1). Defaults marked **owner to confirm**.
> Next handoff: crew-builder-watch
> Binding conventions: `docs/global_conventions.md`, `docs/state_management/watch_surface_wrist_logging.md`, `watch/sync_protocol/PROTOCOL.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 54 D-1/D-1a (a wrist-ended timer is not restarted by the phone's push), 43b/c (phone timers), 61 (rest pings), 98 (timers resend), 121a/127 (phone side: logged hold stays stopped), 80 (`senderWroteTimer`)
> Track: watch client only (`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`). No wire change, no phone change.

## Goal and acceptance

Owner report, 2026-11-15, isometric routine logged on the watch and the phone alternately:

(a) "the watch started triggering the rest ping more often … as if a second loop of the original timer started, besides the watch's own ping";
(b) "once I hit Next I saw an older active hold timer running for 3-4 minutes, but that hold is not logged in the session editor — a ghost".

Cause found in code (not yet seen on a device): the wrist adopts a phone timer frame or snapshot by storing a NEW running row whenever the row id `tms-<messageId>-<kind>` is new. Every frame has a new message id. Today's guards:
- a **work timer** (hold/elapsed/round) is ignored only when the wrist's newest timer of that kind is **not stopped**, is for the same slot and started earlier (`adoptTimer`, `WatchSessionEngine.swift` ~1107-1116). If the wrist already ran and **stopped** that very interval (the user pressed Log on the watch), a later phone frame or snapshot that still names the same interval as running stores a fresh **running** row for it: a ghost hold that nothing ever logs, and it can even pull the wrist to its exercise (`jumpTarget`).
- a **rest** is exempt from every guard. A snapshot that names the phone's still-running rest (the phone answers each wrist contact with one) stores a new rest row with the same start but a new id; the ping rule is keyed on the rest row id (`WatchRestPing.isOwed`: `pingingRestId != restId` → `lastPinged = 0`), so the boundary the wrist already tapped is tapped again. A rest the wrist already ended with Next is also reopened by the same route.

The phone's own diagnostics log of the session (19:03-19:37Z) shows the phone answering every watch contact with a snapshot and timer frames, the shape this needs.

After this change: **an interval the wrist already holds (running or stopped) is never stored again by a later frame naming the same interval**, so the extra pings and the ghost hold stop. A genuinely new interval (different start) is adopted exactly as today.

Acceptance: the scenarios below fail on the old code and pass on the new; `swift test` in `watch/watchos` green with observed counts; the sync-protocol fixtures and replay corpus unchanged and green; the watch target compiles (lead).

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20201 | **Same interval = same session, same kind, same slot, `startedAt` within 1000 ms** (the phone's own `_loggedStartToleranceMs` is 1000; ISO strings travel at millisecond precision, so equal intervals compare equal, a real new interval starts seconds later). | `WatchSessionEngine.swift` (`adoptTimer`) |
| D-20202 | **Work kinds (elapsed, hold, round): an incoming timer with `stoppedAt == nil` is ignored when the wrist's timer log already holds a STOPPED row of the same interval** (D-20201). The existing earlier-start guard (a running held row) is unchanged; an incoming row with `stoppedAt != nil` always applies (a stop). A pause/resume of a running interval is not affected (the held row is not stopped). | `adoptTimer`, new private helper `ranInterval(kind:sessionId:slotId:startedAt:)` |
| D-20203 | **Rest: an incoming rest with `stoppedAt == nil` is ignored when the wrist's timer log already holds a rest row of the same session with `startedAt` within 1000 ms that is either STOPPED, or an exact repeat (same `pausedAt` and same `accumulatedPauseMs` as the incoming).** A phone pause or resume of the same rest (different `pausedAt`/`accumulatedPauseMs`) is still adopted. A rest the phone started LATER (different start) still supersedes the wrist's own (S-336 stays). The rest has no slot: the key is session + start only. | `adoptTimer`, same helper (slot compared only for the work kinds) |
| D-20204 | **The ignore happens before the store append and before `jumpTarget`**, so no row, no revision bump, no jump and no re-ping follows. `adoptTimers`'s `changed` stays false for it. | `adoptTimer` |
| D-20205 | **Not changed:** the phone side (its resend, `_owed`, `_delivered` ledgers: failed sends are dropped by the transport, they do not arrive late); `WatchRestPing`; the Dart twin (`lib/watch`, a developer harness: its adoption keeps its behaviour); the wire; the stop path (`stopTimerFromMessage`); wrist-originated timer rows (`tms-` prefix absent): the helper only reads rows, whoever wrote them. | — |
| D-20206 | **New Swift function names avoid the append-only guard's verbs** (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set): the helper is `ranInterval`. | — |

## Input-reality checklist (answered)

1. **Writers.** The timer rows come from the wrist's own start/log (`startTimer`, `log` → `stopTimer`) and from phone frames (`timer_state`, `session_snapshot.timers`, written by `LiveSessionMirrorState.sendTimers`/`snapshotTimers`, ISO-8601 UTC at ms). Both are read through `timerLog` (the in-memory mirror of the append-only store).
2. **Lifecycle.** A session that ended: `applyTimerState` already reduces a terminal session's frame to nulls (D-14603). A relaunch: `timerLog` is rebuilt from the store, so a stopped row is still there.
3. **Settings.** Rest-ping seconds Off/changed: unaffected (the ping rule is untouched).
4. **Time.** 1000 ms tolerance; a clock-skewed phone start differing by more than 1 s from the wrist's stopped copy is a different interval by construction and is adopted as today (accepted: the wrist's own copy of a phone interval carries the phone's `startedAt`, not its own clock).
5. **Cost.** One pass over `timerLog` per adopted timer; `timerLog` holds the session's rows (tens), as `newestTimer` already scans.
6. **Words.** None on screen. Docs: the Docs delta.
7. **Competition.** A running held row vs an incoming stopped one: the stop applies (existing). A stopped held row vs an incoming running copy of the same interval: ignored (new). A held rest vs a phone rest with a later start: the phone's newer rest still wins (S-20210 pin).

## Feature invariants

- An interval the wrist has already stopped is never running again because of a frame (D-20202, S-20201, S-20202).
- A different interval is always adopted: a later start for the same slot after a stop, another slot, a later rest (D-20201..D-20203, S-20203, S-20210).
- The ignore never produces a row, a jump or a `changed` outcome (D-20204, S-20204).
- A stop frame still stops (S-20206).

## Existing-functionality impact

| Touched surface | What reads it (search to be re-run by the builder) | Effect | Guarded by |
|---|---|---|---|
| `adoptTimer` | `adoptTimers` (`applyTimerState`, the snapshot apply path `adoptTimers(... authoritative: true)`), tests `WatchLoggingTimersTests` S-6005/S-6006 (`:1000-1150`), `WatchEndedIsFinalTests` (`:492-519`), `WatchStaleSnapshotTests`, any test that adopts the same phone timer twice or a stopped copy followed by a running copy of the same start | Tests that deliberately re-run a stopped interval from a frame would change; the builder lists each and says why (the plan's rule wins) | S-20201..S-20206 |
| `senderWroteTimer` / `isTimerFromMessage` | unchanged | — | — |
| The replay/reconciliation fixtures (`watch/sync_protocol/fixtures/reconciliation/`, `replay/`) | run by `SyncProtocolFixturesTests` / the Swift replay test | Must stay green unmodified; if one encodes "a stopped interval is re-adopted", stop and report (do not edit the fixture) | S-20207 |

## Scenarios

Fixture note: the builder takes the helper blocks from `WatchLoggingTimersTests.swift` (S-6005/S-6006, `:1000-1150`: a session whose hold slot is `sx-plank`, a `timer_state` envelope builder, `engine.timerFor(WatchTimerKind.hold)`) and `WatchStaleSnapshotTests.swift` (a phone `session_snapshot` with `timers`). Every incoming frame uses a DIFFERENT message id (that is the bug's trigger).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20201 | Hold slot S. Phone `timer_state` m1: hold running, `startedAt` T. The wrist logs the hold at T+20 s (`stopTimer(kind: hold)`), so its newest hold row is stopped. A second `timer_state` m2 names the SAME hold running at T | `timerFor(hold)?.state == stopped`; the timer log holds the same number of hold rows as before m2; `adoptTimers` outcome `changed == false` | a new running hold row is stored |
| S-20202 | Same as S-20201 but the second frame is a phone `session_snapshot` (newer `sentAt`, new message id) whose `timers.hold` is the same running interval | as S-20201; no jump (`currentExerciseIndex` unchanged) | the snapshot re-adopts the stopped interval as running |
| S-20203 | After S-20201's stop, a `timer_state` m3 names the hold running at T+60 s (a real second interval) for the same slot | a new running hold row; `timerFor(hold)?.startedAt` is T+60 s | passes today — pins that a new interval is adopted |
| S-20204 | S-20201's second frame with the slot being a DIFFERENT exercise than the current one (the case that pulls the wrist) | `currentExerciseIndex` unchanged and no jump request in the outcome | the stale interval jumps the wrist to its exercise |
| S-20205 | Phone `timer_state` rest R running, `startedAt` T (m1), adopted; a phone `session_snapshot` (m2) names the same rest at T | exactly one rest row for the session at T; `restPings`: drive `WatchRestPingScheduler.step()` with a rest elapsed past one interval boundary — it taps once (before m2) and NOT again after m2 at the same boundary (count the injected haptic taps) | the snapshot stores a second rest row; its new id resets the ping memory and the boundary taps again |
| S-20209 | The wrist ended rest R (`endRest`, newest rest row stopped, `startedAt` T); a snapshot m2 still names rest R running at T | `isResting == false`, the newest rest row is stopped, no new row | the rest reopens |
| S-20210 | Held rest R at T (running); a phone rest R' at T+30 s arrives | R' is adopted as the newest rest (the wrist's rest is superseded: S-336) | passes today — pins D-20203's "later start wins" |
| S-20211 | Rest R at T running; incoming rest at T+0.4 s (ms-rounding case) | ignored (same interval, tolerance); at T+2 s adopted | exact-equality or no tolerance would store both |
| S-20206 | Held hold running at T; an incoming `timer_state` names the hold with `stoppedAt` set (a stop) | the hold is stopped (existing stop path, unchanged) | passes today — pins that a stop still applies |
| S-20212 | Held rest R at T, paused at T+10 s (`pausedAt` set); an incoming rest at T with `pausedAt` nil and `accumulatedPauseMs` 5000 (the phone's resume) | adopted: the newest rest row is running with 5000 ms accumulated | passes today — pins that a resume of the same rest is not swallowed by D-20203 |
| S-20207 | The whole `SyncProtocolFixturesTests` + the Swift replay/reconciliation tests | green, unmodified fixtures | n/a — guard against a fixture encoding the old behaviour |
| S-20208 | Source guard: `adoptTimer` calls `ranInterval(` before `store.append(` and before `jumpTarget(`, and the helper compares `abs(` of the start difference against `1.0` | exact statements incl. braces (crew rule (ao)) | the call is absent |

## Phases

**P1 — the guard (owner: crew-builder-watch; scope `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchTimerReadoptionTests.swift` (new), `.work/crew/2026-11-15-202/report-watch-p1.md`; serial after plan 201's P1 and P2).**
Items: the helper `ranInterval`; its call in `adoptTimer` for work kinds (D-20202) and rests (D-20203) before the append; the new test file with S-20201..S-20208; list and fix-or-report each existing test the guard turns red (only inside the scope: otherwise report).

**P2 — docs (owner: crew-docs-keeper; scope the two docs below; after P1).** Execute the Docs delta.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_surface_wrist_logging.md | MODIFIED | `for another slot is stored beside, and a rest keeps last-write` | `an interval the wrist already ran is never restarted by a later frame` | S-20201, S-20202 |
| docs/state_management/watch_surface_wrist_logging.md | ADDED | - | `a rest the wrist already holds is not adopted again` | S-20205, S-20209 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**No ghost hold and no extra rest ping when phone and watch share a workout — (owner, plan 202).**` | S-20201, S-20205 |

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheet 2 read, `adoptTimer` read in full, the owner's diagnostics log read).
- [x] P1 the guard
- [x] P2 docs
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols and fixtures. | lead, cost discipline | open |
| A-2 | **Not proven on a device.** The phone's log shows failed `timer_state` sends, but a failed live send is dropped by the transport (`_queueable` excludes timers), so it is NOT the cause; the cause is read from `adoptTimer`. The wrist's own diagnostics of that session are not in the log (it starts at 21:49Z). The owner checks the fix on the wrist (QA step). | lead | open |
| A-3 | The ghost needs the phone to still name the interval as running after the wrist logged it. Whether the phone stops its own timer when the wrist's hold arrives is not asserted here: the wrist is made safe either way. | lead | open |
