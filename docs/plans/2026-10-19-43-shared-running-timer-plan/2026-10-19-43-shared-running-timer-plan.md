# Feature: 43 — one running timer shared by phone and watch (timed, hold, round and interval sets)

> Status: 43a BUILT (2026-10-19, `docs/plans/2026-10-19-43a-timed-fill-plan/`, reviewed); 43b BUILT as three plans (2026-10-20: 43b1 wire + wrist, 43b2 phone receives, 43b3 phone sends — see the split below); 43c BUILT (2026-10-20, `docs/plans/2026-10-20-43c-finish-once-plan/`, review pending). All uncommitted on `claude_develop`. Written from the owner's QA of 2026-10-19; re-validate every pointer against the tree before seeding.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> This is a protocol-touching series; it is split into three PRs (43a, 43b, 43c) by the scope guard rule "more than one track". Do not merge them into one plan.

## What the owner saw (2026-10-19, real devices, flutter run on the phone)

In a cardio session with an exercise added, both devices showed the running session. Starting a set on the watch left the phone's set untouched, and the phone's set could be started too. Logging on the phone and then on the watch crashed the phone app (not reproduced, no log: see "Crash" below). Logging on the watch added a set and left the phone's set intact. This was true for every modality except resistance, where plan 36a already makes a watch-logged set fill the phone's next planned set.

## Owner decision (2026-10-19)

Starting a set on one device starts the same running timer on the other; finishing it on either device logs it once.

## Facts (verified 2026-10-19; line numbers drift, re-grep)

- Resistance sets: a watch set fills the phone's first unlogged row (`lib/core/services/watch_session_importer.dart` `_placeAroundUserRows`, `fills = fillPlanned && entry.wireKind == WatchInboxEntry.kindSet`). Timed, hold and round entries NEVER fill: they append at `next++` (`final index = unfinished ?? fill?.number ?? next++`). That is why a watch interval lands beside the phone's own.
- The phone sends only logged entries to the wrist (`PhoneEntries`), and in-progress timed/hold/round entries appear on the other device only once finished (known limit from the auto-sync series; `docs/watch_session_sync.md`).
- The wire already carries timers: `timer_state` (either direction) and the `timers` map of `session_snapshot`, kinds `rest`, `round`, `hold`, `elapsed`, as wall-clock `startedAt`, `pausedAt`, `stoppedAt`, `accumulatedPauseMs` and an optional plan (PROTOCOL.md "Timer state"; Swift `WatchTimerKind`; wrist side `WatchSessionEngine` emits `timer_state` ~:1818 and `WatchLoggingState.startWork`). The phone's `LiveSessionMirrorState` holds them (`state['timers']`, `timerEnd`), but the phone's SESSION SCREEN does not read them: its timers live in `workout_session_timer_mixin.dart` keyed `'$effortId-$entryIndex'`, persisted as `TimedInstance`/`RoundInstance` (`startedAtMs`, `state`, `pausedAtMs`, `totalPausedDurationMs`), which already match the wire's fields one to one.
- The wrist's own timed flow is Start then Log (plan 21; `WatchLoggingModel.primaryAction`), and it logs a `timed`/`hold`/`round` entry with `startedAt`, `endedAt`, `loggedAt` (`PhoneEntries` mirrors that shape).

## Proposed series (each its own plan; decisions below are proposals for the seed)

- **43a — a watch interval fills the phone's interval (no duplicates).** In the importer's live merge, let `timed`, `hold` and `round` entries fill the first interval the phone reads as unlogged, the way sets do (plan 36a D-4: "unlogged" for a timed instance is `state != finished`/no `finishedAtMs`; the filled instance takes the wrist's window and stamps the wrist's time so it is never echoed back). Also close the phone's running timer for that interval (stop its ticker and drop the in-progress marker in the session screen) when the wrist's entry fills it. No wire change. Smallest, fixes "logging on the watch adds a set and leaves the phone's set intact". Includes the governor repro of the crash (below).
- **43b — a timer started on one device runs on the other.** Phone Start/Pause/Stop sends `timer_state` for the work kind of the current exercise (`elapsed` for count-up timed, `hold`, `round`), and the wrist's `timer_state`/snapshot timers drive the phone's `TimedInstance`/`RoundInstance` (create or resume the instance at the current interval with the wrist's `startedAt`), so both show the same clock. Wire change expected only if the current entry index must be named (a `timer_state` today names the kind, not the interval): decide whether the interval is implied (the focused interval of the current exercise on both devices) or an optional `entryIndex`/`entryId` is added (additive, validator and fixture updates on both stacks).
- **43c — finishing on either logs once.** A log on one device stops the other's timer and fills the same interval (43a's fill rule plus a clearing `timer_state` with `null`); a simultaneous finish on both is resolved with one winner by wall-clock `loggedAt` (like the rating rule of plan 42: the phone's value stands if both land inside the radio window, stated as a limit).

## Owner answers (2026-10-19, in chat)

1. Which interval a timer started on one device belongs to: **where it started**: the interval (and exercise) the starting device was on, even when the other device is somewhere else. Consequence (differs from the outline's recommendation): the wire must NAME the exercise slot and interval. Today a `timer_state` names only the kind (`rest`, `round`, `hold`, `elapsed`), so 43b needs an additive field (an optional `sessionExerciseId` and `entryIndex` on the timer, validators and fixtures on both stacks) or a new timer-state shape; decide in the 43b seed, and split 43b if the contract change is its own PR. The other device must show that interval's running clock without moving the user's focus (open question for the seed: how the phone shows a timer running on an interval it is not looking at, with no new screen or modal unless the owner approves one).
2. Pause on one device: **pauses both** (one shared clock; resume and stop likewise).
3. Both devices start the same interval at nearly the same moment: **the earlier start wins**; the later device adopts the earlier `startedAt`. This replaces 43a's stated assumption A-1 only in the case where the phone had started first: 43a lets the wrist's logged entry fill (and stop) a running phone interval, which is the "finish logs once" half; the start-race rule belongs to 43b.

## Crash (not diagnosed)

The phone crashed after logging an interval on the phone and then on the watch (flutter run on a physical device, no log kept). Do not guess a cause: 43a's first step is a governor-written repro test (a phone timed instance at entry index 0 finished on the phone, then a wrist `timed` entry merged live, then the session screen reloading) and, in parallel, ask the owner for `flutter run 2>&1 | tee ~/omnitrain-run.log` on the next attempt. If the crash is an index/range error in the session screen after an extra interval lands, 43a's fill rule removes the trigger.

## Size (outline, to re-estimate when seeded)

43a about 80 production lines (importer + session screen cleanup), 2 phases, one track. 43b about 200 lines, phone + wrist + contract, 4 phases: split again if the interval must be named on the wire. 43c about 80 lines, 2 phases.

## 43b split by the scope guard (2026-10-20, seeded)

43b1 and 43b3 are BUILT (2026-10-20, reviewed, uncommitted); 43b2 is next. 43b is three plans, built in this order: `docs/plans/2026-10-20-43b1-shared-timer-wire-and-wrist-plan/` (the timer names its exercise on the wire; the wrist honours it and the earlier start wins), `.../2026-10-20-43b2-shared-timer-phone-receives-plan/` (a timer started on the watch runs on the phone), `.../2026-10-20-43b3-shared-timer-phone-sends-plan/` (a timer started or paused on the phone runs and pauses on the watch). 43c (finishing on either logs once, matching the phone's interval by the shared start) follows. Only `sessionExerciseId` is added to the wire (no interval index): a wrist-started timer lands on the phone's in-progress or first unfinished interval of that exercise.

## Next handoff (superseded by the split above)

Seed 43b: first a scout on `timer_state` (what the wrist emits for Start/Pause/Stop, kinds, the reconciler `session_reconciler.dart:67`, and what the phone's `LiveSessionMirrorState` does with `timers`), then decide the wire shape for slot + interval, then split 43b into contract / wrist / phone as the scope guard requires.
