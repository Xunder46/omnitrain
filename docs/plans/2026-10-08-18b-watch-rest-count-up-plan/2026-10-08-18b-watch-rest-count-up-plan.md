# Feature: the watch's rest is a count-up — and the rule becomes impossible to regress (18b)

> Status: DRAFT — defaults applied, owner may veto any Open question before Phase 1 starts
> Next handoff: @developer (Phase 1) — the wrist's rest stops having a length, in both stacks
> Binding conventions: `docs/global_conventions.md` (+ `docs/rest_tracking.md`,
> `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`,
> `docs/documentation_standard.md`, by path)
> Part of the 18 series — index: `docs/plans/2026-10-08-18-watch-qa-index.md`

## Overview

The owner, after the first real-device QA of the watch app:

> "OmniTrain doesn't have such a thing as a rest timer with a preset value, rest always starts from
> zero and ticks up until you start the next set, check out how it works and make sure it is similar
> on the watch and it is well documented and surfaced for agents. The rest timer can appear in its
> own screen with the next button to stop it and go to the next set."

and, asked whether the watch's rest should reach the phone:

> "yes"

The rule, stated once, for every device:

> **Rest in OmniTrain is a count-up from the moment a set is logged to the moment the next set
> starts. There is no preset rest length, no rest countdown and no rest alarm anywhere, on any
> device.**

The phone already works this way (`EntryRest`, `docs/rest_tracking.md`). The wrist does not: it
starts a `WatchTimerKind.rest` timer with a 90-second plan (`WatchLoggingDefaults.restSeconds = 90`,
`WatchLoggingState.swift:25`) and renders a countdown with an alarm at zero
(`WatchLoggingView.swift:88` shows `"\(clock(countdown)) left"`; `WatchTimerHaptics.poll` fires at
`remainingMs == 0`, `WatchTimerHaptics.swift:50`). The owner reports this has surfaced "multiple
times in the past, for some reason it is a hard pill to swallow for any language model" — so 18b
treats the *rule* as the deliverable: the behaviour change is small, the durable part is the
conventions row, the contract test and the doc sweep that stop it coming back.

**What 18b ships** (2 tracks: the watch client, and the sync contract):

1. The wrist's rest becomes a count-up: no `restSeconds`, no `plannedDurationMs` on the rest timer,
   no "left", no alarm — in the Swift package *and* the Dart twin, with cross-stack tests.
2. A rest screen of its own on the wrist: elapsed since the set was logged, from 0:00, and a single
   **Next** control that ends the rest and returns to logging.
3. The wire refuses a rest length: a `rest` timer carrying `plannedDurationMs` is rejected by both
   validators, and the envelope schema forbids the property for that kind.
4. The rule, where agents will hit it: `docs/global_conventions.md`, the rest/sync/watch docs, and
   `test/rest_is_count_up_contract_test.dart` (+ its Swift twin), whose failure message names why.

**What 18b deliberately does not ship — planned as 18c** (`## Remainder planned as 18c`): the wrist's
rest *reaching* the phone (the new `observations_up` `rest` entry kind, the importer writing an
`EntryRest`, the history surfaces). The brief's budget rule fires here: 18b already spans 4 phases
(soft signal: >3 phases) and 2 tracks (soft signal: >1 track), and adding the phone-history work
would make a third track and a fifth phase — two soft signals, which the brief says to resolve by
planning the remainder as 18c. 18b therefore pins 18c's design in the Ledger (D-166, D-167) so 18c's
phases can be written without re-deciding anything, and ships no wire kind.

## Resolved Decisions (Ledger)

**D-160 — Rest is a count-up, everywhere, forever.** A rest runs from the instant a set is logged to
the instant the next set starts (or the session ends). No device holds a preset rest length, renders
a rest as a remaining time, or alarms at the end of a rest. On the wrist this means a
`WatchTimerKind.rest` record carries **no** `plannedDurationMs`; `WatchLoggingDefaults.restSeconds`
and `WatchLoggingState.restSeconds` are deleted in both stacks (Swift
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:25,135,179,186`, Dart twin
`lib/watch/logging/watch_logging_state.dart:36,134,176`). The rest timer *record* stays — it is the
wall-clock window the screen derives its elapsed from — only its length goes. The authoritative
statement lives in `docs/global_conventions.md` (Phase 4) and is enforced by
`test/rest_is_count_up_contract_test.dart`.

**D-161 — The wrist's rest surface.** When a `rest` timer is running and not stopped, the wrist shows
a rest screen instead of the logging surface: the exercise's name, the elapsed rest counting up from
`0:00` (derived at render time from the rest row's `startedAt`, `WatchTimerMath.activeElapsedMs`,
`WatchTimerMath.swift:17`), and **exactly one control: Next**. Next stops the rest timer
(`WatchSessionEngine.stopTimer(kind: .rest)`, `WatchSessionEngine.swift:1552`) and returns to the
logging surface. No End, no exercise picker, no dial, no pause, no preset — the wrist's rest is never
paused (D-166 records the consequence for imported rows). Because the elapsed is derived from the
persisted row, the rest survives the screen turning off and a relaunch: timer rows are written
through the store (`WatchSessionEngine.appendTimer` → `store.append(.timer(row))`,
`WatchSessionEngine.swift:1584`) and restored by `WatchSessionEngine.restore()` (`:111`).
Shell placement: `ios/OmniTrain Watch App/ContentView.swift`'s `body` gains a branch *after*
`host.rating.isPromptOwed` and *before* the active-session branch, so an owed rating still wins.
The app target is not covered by `swift-test` (it needs `xcodebuild`): the governor builds it.

**D-162 — Logging anything ends a running rest.** `WatchLoggingState.log()` stops a running rest
timer before it starts the follow-on timer, in both stacks, so a rest can never outlive the entry
that follows it — whichever path logs (Log button, debug surface, a future auto-log). The rest's end
instant is that log's instant. This is the wrist's twin of the phone's
`TimerManager.recordRestStart` behaviour, which closes every open rest for the effort before it
creates the next one (`lib/state/workout/timer_manager.dart:714,728`).

**D-163 — No rest alert, and no replacement.** The milestone haptic fires only for a timer that has a
`plannedDurationMs` (`WatchTimerHaptics.poll` reads `remainingMs(timer, now) == 0`,
`WatchTimerHaptics.swift:50`; `WatchTimerMath.remainingMs` is nil without a plan, `:26`) — with the
rest's plan gone, no haptic is ever owed for a rest, and nothing is added in its place. The phone's
**rest ping** (`restPingInterval` / `restPingSound`, `_checkRestPings`,
`lib/features/session/workout_session_global_timer.dart:36-63`) is unchanged: it is a count-up nudge
for the phone's own *open* rest and already skips a closed one (`:50`), so it never fires for an
imported wrist rest (D-167 makes imported rests closed). The phone's round/hold "timer alerts" are
untouched. `docs/theme_and_settings.md` gains one sentence saying exactly this (Phase 4).

**D-164 — The wire carries no rest length.** `plannedDurationMs` on a timer whose `kind` is `"rest"`
is refused, in both validators, with a message naming the rule:
`SyncProtocolValidator.swift`'s `timerKindRejections` (`:176-206`) and
`lib/core/sync_protocol/message_validator.dart`'s `_timerKindRejections` (`:294`). The envelope
schema forbids the property for that kind (`watch/sync_protocol/schemas/envelope.schema.json`,
`$defs.timer:321-350`; `$defs.timers:356-365` is referenced by both
`messages/timer_state.schema.json:17` and `messages/session_snapshot.schema.json:36`, so there is one
edit). Round, hold and elapsed timers keep their `plannedDurationMs` exactly as they are. Existing
fixtures are updated additively — the valid `rest` fixture loses the property, a new invalid fixture
carries it (Phase 3). `"rest"` stays in `timerKinds` (`SyncProtocolValidator.swift:63`,
`message_validator.dart:118`) and in `WatchTimerKind.all`: the kind is not being removed, only its
length.

**D-165 — 17a D-80 superseded for the display; its ownership half stands.**
`docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/2026-10-06-17a-watch-auto-sync-pr1-plan.md:83`
("Each device keeps its own rest countdown") is superseded: *neither* device counts down — both count
up (D-160) — and the wrist's rest now travels to the phone (D-166/D-167, shipped in 18c). The rest of
D-80 is untouched and must stay true: a rest is device-local, a snapshot stops only the timer kinds
its sender wrote, and a `rest` timer that the phone cleared stays cleared (guarded by S-167). 17a's
S-79 (`:348`) and its Open question 1 (`:855`), where that default was taken, are annotated by the
18c doc phase, not re-opened.

**D-166 — The wrist's rest travels as a `rest` observation (implemented in 18c, pinned here).** The
wrist emits one `observations_up` `event` per completed rest, `kind: "rest"`, carrying `eventId`,
`sessionExerciseId`, `exerciseId`, `startedAt`, `endedAt` and `afterEntryId` (the `entryId` of the set
the rest follows). No new message type, no new envelope `$defs` — `$defs.event`'s oneOf gains the
value, which is the smallest additive shape available. A rest is emitted when it ends (Next, the next
set's log, or the session's end, where `endedAt` is the session's end instant); a rest whose
`endedAt <= startedAt` is not emitted at all; a rest still running when the session ends is emitted
with the session's end instant. The amendment is a dated `1 (amended)` row in
`watch/sync_protocol/PROTOCOL.md`'s Version history (`:551`), written in the phase that ships it, with
no version bump (v1 is unreleased).

**D-167 — The phone turns an imported rest into an `EntryRest`, keyed on `entryIndex` (18c).** The
importer resolves `afterEntryId` to the placed index of that entry in the effort and writes
`EntryRest` with `entryIndex = that index + 1` (the rest *precedes* the entry at that index — the
phone's own convention, `TimerManager.recordRestStart`, `timer_manager.dart:693-736`), `id =
'rest-<effortId>-<entryIndex>'` (the same id shape the phone builds, `timer_manager.dart:718`),
`restStartMs = startedAt`, `restEndMs = endedAt`, never paused (`restIsPaused = false`,
`restPausedAtMs = null`, `restPausedDurationMs = 0` — the wrist has no pause, D-161), and
`createdAtMs`/`updatedAtMs` from the importer's existing write convention (`_createEntry`,
`lib/core/services/watch_session_importer.dart:855`). Rules:
**(a)** first write wins — if the effort already holds a rest at that `entryIndex` (the phone logged
that set, or the event arrived twice), the row is left exactly as it is and the event is
acknowledged and dropped; **(b)** a rest is not an entry — it is never placed, never re-stated by
`_applyCorrections` (`:1000`), never re-indexed by `_reindexInstance` (`:823`) and never deleted by
`_deleteInstance` (`:801`), so deleting the set a rest follows deletes the set and leaves the rest
row alone; **(c)** a rest whose `afterEntryId` resolves to no placed entry is dropped (a rest cannot
exist without its set); **(d)** the only writer is the repository method the phone's own rest path
uses — `WorkoutRepository.createEntryRest` (`lib/data/repositories/workout_repository.dart:253`),
never `TimerManager`, so an imported rest never notifies the live phone session.

**D-168 — A routine's Rest duration is a prescription, not a timer.** `TemplateEffort.restSeconds`
(the routine editor's rest field, `rest_seconds` in `scripts/sqlite_schema.sql`) and every reader of
it are out of scope and must not be renamed, deleted or rewritten: it describes how long the athlete
*intends* to rest between sets, and the app has never turned it into a timer. D-160 forbids a *timer*
with a preset length, not a plan field. The contract test's scope (Phase 4) therefore excludes
`lib/data/models/models.dart`, `lib/features/routine/**`, `lib/state/routine/**`,
`scripts/sqlite_schema.sql` and `docs/my_routines.md` for the `restSeconds` token, and S-168 pins
that the routine field still round-trips.

**D-169 — One version-history row per wire change, in the phase that ships it.** The refusal (D-164)
gets its own dated `1 (amended)` row in `watch/sync_protocol/PROTOCOL.md:551+` in Phase 3, and the
`rest` entry kind (D-166) gets its own row in 18c's wire phase. Both are additive and both name the
pinning tests and fixtures, like the six existing amendment rows (`:556-565`).

## Feature Invariants

- **No rest length exists anywhere.** After 18b, no source file, schema or doc states a rest length
  as behaviour: not `restSeconds` on the wrist, not `plannedDurationMs` on a rest timer, not a
  "remaining" rest. The one exception is the routine prescription (D-168).
- **Both watch stacks agree.** The Swift package and the Dart twin must produce the same observable
  behaviour for the same inputs — the same absence of a rest plan, the same count-up, the same Next
  semantics. Divergence makes the twin lie.
- **The phone's rest behaviour is unchanged by 18b.** 18b writes no `EntryRest`; the phone's rest
  records, pings and summary arithmetic are exactly as 18a leaves them.
- **A rest is device-local.** D-80's ownership half: a snapshot stops only the kinds its sender wrote,
  and a cleared rest stays cleared (S-167).
- **Docs trail code by zero phases.** Every phase that changes behaviour updates the doc it
  invalidated in the same phase; `docs/state_management/watch_surface.md` must stay under its 51.2 KB
  ceiling (it is ~50.1 KB) by *removing* countdown prose, not adding.

## Requirements

- R-10 The wrist's rest is a count-up from 0:00 with no preset length and no "remaining"; both stacks.
- R-11 The wrist shows a rest screen of its own with a single **Next** control that ends the rest and
  returns to logging.
- R-12 The rest's elapsed survives the screen turning off and a relaunch (wall clock from the
  persisted timer row).
- R-13 No alert is ever owed for a rest; no alert wiring is added in its place.
- R-14 Logging any set ends a running rest first, whatever path logs it.
- R-15 A `rest` timer carrying `plannedDurationMs` is refused by both validators and by the schema;
  round/hold/elapsed timers are unaffected.
- R-16 The rule is authoritative in `docs/global_conventions.md` and the rest/sync/watch docs, and a
  contract test fails — naming why — if the regression returns.
- R-17 The wrist's rest reaching the phone is designed in the Ledger (D-166/D-167) and implemented as
  18c; 18b ships no wire kind.

## Acceptance Criteria

- AC-10 The wrist's rest timer row has no `plannedDurationMs` and the surface shows no "left" line
  (S-160).
- AC-11 A rest that started four minutes before the app is relaunched still shows four minutes of
  elapsed (S-161).
- AC-12 Next ends the rest at the tap instant and returns to logging; the next set's log does not move
  that instant (S-162).
- AC-13 Logging a set while a rest is running ends the rest at that log's instant (S-163).
- AC-14 No timer milestone is owed for a rest at any point; a round countdown still fires one (S-164).
- AC-15 Both validators reject a `rest` timer with a plan, accept a `rest` timer without one, and still
  accept a round timer with one (S-165).
- AC-16 The contract test and its Swift twin are red at the base and green after (S-166).
- AC-17 A phone-cleared rest stays cleared on the wrist, and the routine's Rest duration still
  round-trips (S-167, S-168).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchLoggingDefaults.restSeconds` / `WatchLoggingState.restSeconds` | Only `startFollowOnTimer` in each stack, plus the test helper default (`WatchLoggingTimersTests.swift:25,30`) — `grep -rn restSeconds watch/watchos/Sources lib/watch lib/state` returns those five Swift sites and four Dart sites, nothing else | Deleted; the rest timer is started with no plan | S-160, D-160 |
| `WatchTimerKind.rest` | `SyncProtocolValidator.swift:63`, `message_validator.dart:118` (kind lists); `WatchLoggingModel.countdown:71`; `WatchTimerHaptics` (`WatchTimerKind.all`); `WatchTimerMath.remainingMs`; the projection's timer map (`lib/state/watch/live_session_mirror_state.dart`, the `timers`/`timerEnd` projection); 17a D-80 | The kind stays; only its `plannedDurationMs` goes, so every reader keeps compiling and the timer record keeps travelling | S-167, S-164 |
| `WatchLoggingModel.countdown` / `_countdown()` | `WatchLoggingView.swift:88`, `lib/watch/logging/watch_logging_screen.dart:172` (the "left" line) — the only two call sites | The rest fallback goes; the function returns the round timer's remaining only | S-160, S-161 |
| `plannedDurationMs` on the timer shape | `envelope.schema.json:$defs.timer:345`; `timer_state.schema.json:17`; `session_snapshot.schema.json:36`; both validators' timer rejections; `TimerInstants.remainingMs`; `completionInstant`; the fixtures under `watch/sync_protocol/fixtures/` | Forbidden for `kind == "rest"` only; every other kind unchanged; fixtures updated additively | S-165, D-164 |
| `WatchLoggingState.log()` | The logging surface's Log button, the debug surfaces, `test/watch_logging_timers_test.dart`, `WatchLoggingTimersTests.swift` | Ends a running rest before it starts the follow-on timer | S-163, D-162 |
| `ios/OmniTrain Watch App/ContentView.swift`'s branch chain | The app target only — not built by `swift-test` (`grep -rn loggingSurface "ios/OmniTrain Watch App"` returns only this file) | A third branch, after the owed rating | S-161, S-162 + the governor's simulator build |
| Countdown prose in `docs/watch_session_sync.md:416,460,498`, `docs/state_management/watch_surface.md:425,455,466,791`, `docs/watch-app-setup-and-qa.md:195,452,511,546`, `docs/rest_tracking.md`, `docs/README.md:92` | The owner's QA walkthrough (`watch-app-setup-and-qa.md:511` walks the countdown), agents reading the conventions | Replaced by the count-up statement; `watch_surface.md` shrinks rather than grows | S-166, Phase 4 |
| `TemplateEffort.restSeconds` (routine prescription) | `routine_setup_screen.dart:938-941`, `routine_session_service.dart:75`, `routine_state.dart:509,687,1187,1257`, `catalog_refresh_service.dart:271`, `scripts/sqlite_schema.sql:498`, `docs/my_routines.md:160` | Untouched — the contract test excludes it by scope | D-168, S-168 |
| The phone's `EntryRest` write path | `timer_manager.dart:714,728` (`updateEntryRest`/`createEntryRest`), `session_core_io.dart:104,175,247`, `workout_state.dart:90`, `workout_session_screen.dart:272,618,710`, `session_summary_service.dart:29`, both repositories (`hive_workout_repository.dart:1520`, `mock_workout_repository.dart:809`) | No writer, reader or schema changes in 18b; 18c adds an importer-side writer through the same method | 18b writes no rest row — stated in Notes; S-168 |

## Scenarios

### S-160: the wrist's rest has no length
- Fixture: a restored wrist session on a set-kind effort (`sessionExerciseId sl-1`, `exerciseId e-1`,
  0 entries logged), `WatchLoggingDefaults` as shipped; `now = 2026-10-08T10:00:00Z`.
- Trigger: `log()` a set at `10:00:00`; read the engine's timers at `10:00:00` and `10:00:07`.
- Flow: `log()` → the follow-on rest starts → the surface renders the rest branch → seven seconds
  later the surface renders again.
- Expected outcome: the rest row exists with `plannedDurationMs == nil` and `startedAt == 10:00:00`;
  `activeElapsedMs(rest, 10:00:00) == 0` and `activeElapsedMs(rest, 10:00:07) == 7_000`; the surface
  shows `0:00` then `0:07` and **no** "left" line; `remainingMs(rest, anyNow)` is nil.
- Red without the change because: `WatchLoggingTimersTests.swift:55` asserts
  `rest.plannedDurationMs == 90_000` on today's code, and `WatchLoggingView.swift:88` renders
  `"\(clock(countdown)) left"` — both assertions fail at the base.
- Edge case of: none

### S-161: a rest survives the screen turning off
- Fixture: a stored session on `sl-1` whose rest row has `startedAt = 10:00:00` and no stop, written
  through the store; the app is launched at `10:04:00` (four minutes later, after the screen was off
  or the app relaunched).
- Trigger: `WatchSessionEngine.restore()` (`:111`), then render the rest branch at `10:04:00`.
- Flow: restore → the rest row is in `timers` → the surface renders the rest branch.
- Expected outcome: `activeElapsedMs(rest, 10:04:00) == 240_000` and the surface shows `4:00` — the
  elapsed is derived from the row, not from a ticker that stopped; the row is unchanged by the
  restore.
- Red without the change because: **negative guard.** `activeElapsedMs` is already wall-clock at the
  base, so this assertion passes today; its mutation is restoring `plannedDurationMs: restSeconds *
  1000` on the rest timer (S-160's mutation), which turns the surface's own value into a remaining —
  the guard is that the *rendered* value is an elapsed, asserted here through the surface, not just
  through the engine. The scenario also pins that `restore()` keeps the row (the brief's
  screen-off requirement).
- Edge case of: S-160

### S-162: Next ends the rest and returns to logging
- Fixture: as S-160, one set logged at `10:00:00`, the rest running; `now = 10:00:30`.
- Trigger: tap **Next** at `10:00:30`; then `log()` the next set at `10:01:10`.
- Flow: Next → `endRest()` → `stopTimer(kind: .rest)` → the shell's branch flips back to the logging
  surface; the next log starts a *new* rest.
- Expected outcome: at the tap, the rest row's `stoppedAt == 10:00:30` and
  `activeElapsedMs(rest, 10:01:10) == 30_000` (a stopped timer keeps the time it had reached,
  `WatchSessionEngine.stopTimer:1552`); the surface shows the logging surface again; after the second
  log there are two rest rows and the *newest* is running.
- Red without the change because: today the rest surface does not exist — the logging surface stays up
  and there is no Next control at all, so the assertions that the shell renders the rest branch and
  that Next stops it fail at the base (the row's `stoppedAt` is nil at the base).
- Edge case of: S-160

### S-163: logging ends a running rest whichever path logs
- Fixture: as S-162 after Next: no rest running; then a second set logged at `10:01:10` starting rest
  #2; the athlete logs the third set at `10:02:00` **without** tapping Next.
- Trigger: `log()` at `10:02:00`.
- Flow: `log()` → a running rest is stopped first → the follow-on rest starts.
- Expected outcome: rest #2's `stoppedAt == 10:02:00` (not the instant of some later tick, and not
  left running); rest #3 exists and is running; the entry count is 3 and the rest count is 3.
- Red without the change because: at the base the running rest is never stopped by `log()` — the
  engine replaces the timer of the same kind (`startTimer`, `:1497`), which discards the old row
  rather than recording an end, so an assertion that the previous rest's `stoppedAt` is that log's
  instant fails.
- Edge case of: S-162

### S-164: no alert is ever owed for a rest
- Fixture: as S-160, a rest running from `10:00:00`; a round countdown started at `10:00:00` with
  `plannedDurationMs = 60_000`.
- Trigger: `WatchTimerHaptics.poll(now:)` at every second from `10:00:00` to `10:05:00`.
- Flow: each poll walks the timers; a rest yields nothing, the round yields one milestone at
  `10:01:00`.
- Expected outcome: the milestones are exactly
  `[WatchTimerMilestone(kind: .round, at: 10:01:00)]` — nothing with `kind == .rest` at any instant,
  including the instants where the old code fired (90 s, 180 s, …).
- Red without the change because: `WatchTimerHaptics.poll` fires when
  `remainingMs(timer, now) == 0` (`WatchTimerHaptics.swift:50`) and today's rest timer has a 90 s
  plan, so the poll at `10:01:30` yields `WatchTimerMilestone(kind: .rest, at: 10:01:30)` —
  `WatchLoggingTimersTests.swift:73,147,325` assert exactly that on today's code.
- Edge case of: S-160

### S-165: the wire refuses a rest length
- Fixture: three timer-state fixtures — `rest` with no `plannedDurationMs` (the updated
  `fixtures/valid/timer_state.json`), `rest` with `plannedDurationMs: 90000` (the new
  `fixtures/invalid/timer_state_rest_with_planned_duration.json`), and a `round` timer with
  `plannedDurationMs: 60000` (unchanged).
- Trigger: both validators (`SyncProtocolValidator`, `MessageValidator`) on each fixture.
- Flow: the envelope's `$defs.timer` is checked, then the kind's own rejections.
- Expected outcome: fixture 1 accepted, fixture 2 rejected with the code the kind's rejections use and
  a message naming the count-up rule, fixture 3 accepted; both validators agree fixture for fixture.
- Red without the change because: today `plannedDurationMs` is optional and unconstrained for every
  kind (`envelope.schema.json:345`) and `timerKindRejections` has no rest clause, so fixture 2 is
  accepted — the rejection assertion fails at the base.
- Edge case of: none

### S-166: the contract test fails if the regression returns
- Fixture: the repository at the base ref (the code as it is today) and after Phase 4.
- Trigger: `test/rest_is_count_up_contract_test.dart` and its Swift twin
  `WatchRestIsCountUpTests.swift`.
- Flow: the scanner walks the named roots for the forbidden tokens and fails with a message naming why.
- Expected outcome: at the base the Dart scanner finds `restSeconds` in
  `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:25` (via the Swift-source scan),
  the rest `plannedDurationMs` at `:717`, the Dart twin's `:36`/`:708`, and the "countdown" rest
  wording in the docs — and fails, naming the rule and `docs/global_conventions.md`; after Phase 4 it
  passes; restoring any single one of those tokens fails it again.
- Red without the change because: **negative guard with a named mutation** — the test itself is new,
  so its red is proven by running it against the base tree with the Swift sources untouched
  (`prove-red`), and its mutation is re-introducing any one token. Both halves are named in Phase 4's
  Done Criteria.
- Edge case of: none

### S-167: a rest is still a device-local timer
- Fixture: a wrist session with a rest running from `10:00:00`; a phone snapshot whose `timers.rest`
  is `null` and whose `timers.round` is a running 60 s countdown.
- Trigger: apply the snapshot; then poll the haptics at `10:01:00`.
- Flow: the snapshot stops the kinds it names; the rest is not named, so it stays as it is.
- Expected outcome: the rest row survives the snapshot unchanged; the round countdown is replaced and
  still fires its milestone at `10:01:00` — D-80's ownership half intact.
- Red without the change because: **negative guard.** It passes today; its mutation is deleting the
  rest kind from `WatchTimerKind.all` or from the projection's timer map, which makes the surviving
  rest row disappear.
- Edge case of: none

### S-168: the routine's Rest duration is not a timer
- Fixture: a routine whose effort has `restSeconds = 120`, seeded through
  `scripts/sqlite_seed.sql`'s path and read by `routine_setup_screen.dart`.
- Trigger: open the routine editor, read the field, save unchanged.
- Flow: the field round-trips.
- Expected outcome: `restSeconds == 120` before and after; the contract test does not fail on
  `models.dart`, `lib/features/routine/**` or `docs/my_routines.md` for that token.
- Red without the change because: **negative guard.** It passes today and must keep passing; its
  mutation is widening the contract test's scope to all of `lib/`, which fails on the routine field —
  that is why D-168 names the exclusions.
- Edge case of: none

## Iteration 1

Dependency graph: Phase 1 → Phase 2 (the screen needs `isResting`/`endRest`) → Phase 4 (the contract
test asserts Phase 1/2's shape and the docs Phase 4 edits). Phase 3 is independent of 1 and 2 (it is
the schema and the two validators) and can run first or in parallel if a second agent is available;
running it first would make the wrist emit/accept nothing until Phase 1 lands, so the default order
keeps 1 → 2 → 3 → 4.

### Phase 1: the wrist's rest stops having a length (@developer)

1. [ ] Delete `WatchLoggingDefaults.restSeconds` (`:25`), the `restSeconds` field (`:135`), the init
   parameter (`:179`) and the assignment (`:186`); make the rest branch of `startFollowOnTimer`
   (`:714-718`) call `engine.startTimer(WatchTimerKind.rest)` with no `plannedDurationMs` (the
   parameter is already optional); state the count-up rule and cite D-160 in the doc comment —
   `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` ·
   `WatchLoggingDefaults.restSeconds`, `WatchLoggingState.restSeconds`, `startFollowOnTimer`.
2. [ ] The same four edits in the Dart twin (`:36`, `:134`, `:176`, `:705-712`), same comment —
   `lib/watch/logging/watch_logging_state.dart` · `WatchLoggingState.restSeconds`,
   `_startFollowOnTimer`.
3. [ ] Read only the round timer; delete the rest fallback and the `restSeconds` reference; the doc
   comment says why (a rest is a count-up, D-160) —
   `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` · `countdown` (`:69-75`).
4. [ ] The same in the twin screen — `lib/watch/logging/watch_logging_screen.dart` · `_countdown()`
   (`:203-215`), `_header` (`:161-179`).
5. [ ] Drop the helper's `restSeconds` parameter (`:25,30`), replace the `90_000` rest assertions
   (`:55`, `:73`, `:97`, `:114-126`, `:147`, `:325`, `:347`, `:564-620` — `:361` stays, it is a
   round) with the count-up ones, and add S-160, S-161 and S-164 as Swift tests —
   `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` ·
   `makeEngine(restSeconds:)`, the rest-timer tests.
6. [ ] The same three scenarios as plain Dart tests, and remove every rest-plan assertion from the
   existing cases — `test/watch_logging_timers_test.dart` (17a S-79's rest rows) ·
   `test/watch_logging_surfaces_test.dart:81-85`.
7. [ ] New: a source scan over `Sources/**` and `lib/watch/**` for `restSeconds` and a rest
   `plannedDurationMs`, failing with a message that names D-160 and the conventions row — the Swift
   twin of the Dart contract test, cheap because it reads the same trees —
   `watch/watchos/Tests/WatchSessionEngineTests/WatchRestIsCountUpTests.swift` · new `test`.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (expect the
335-test baseline plus the new cases, 0 failures);
`.github/copilot/scripts/macos/gateway.sh test test/watch_logging_timers_test.dart test/watch_logging_surfaces_test.dart`;
`.github/copilot/scripts/macos/gateway.sh lint` (baseline 196 issues / 0 errors — compare the count);
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/watch_logging_timers_test.dart -- lib/watch/logging/watch_logging_state.dart lib/watch/logging/watch_logging_screen.dart`

**Predicted Files**: the four source files above; the three test files above; the new Swift test file.
Nothing else — in particular no phone file, no schema, no doc.

### Phase 2: the rest screen, with one control (@developer)

1. [ ] Add `isResting` (a `rest` timer exists and is not stopped) and `endRest()` (stop that timer)
   and make `log()` stop a running rest first (D-162) —
   `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `isResting`, `endRest()`,
   `log()` (`:556-568`).
2. [ ] The same three members in the twin — `lib/watch/logging/watch_logging_state.dart` ·
   `isResting`, `endRest()`, `log()`.
3. [ ] New view: the exercise's name, the elapsed rest counting up (`activeElapsedMs`, re-read on a
   1 s timeline so it ticks) and one **Next** button calling `endRest()`; no other control; the doc
   comment states the rule and cites D-160/D-161 —
   `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` · new `WatchRestView`.
4. [ ] After a successful `log()` or `endRest()`, call the shell's change callback so the branch
   re-evaluates (mirroring `WatchStartView`'s callback/revision pattern) —
   `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` · `WatchLoggingView.body`,
   `WatchLoggingModel`.
5. [ ] Add the branch: `host.rating.isPromptOwed` → `owedRating`; else `host.logging.isResting` →
   `WatchRestView(state: host.logging)`; else the active session → `loggingSurface`; else
   `WatchStartView`; wire the callback from item 4 —
   `ios/OmniTrain Watch App/ContentView.swift` · `body` (the branch chain).
6. [ ] The Dart twin surface, same layout and the same single Next control —
   `lib/watch/logging/watch_rest_screen.dart` · new `WatchRestScreen`.
7. [ ] New Swift tests for S-161 (0:00 at the log instant, 0:07 seven seconds later, 4:00 after a
   relaunch mid-rest), S-162 (Next sets `stoppedAt` at the tap and the surface returns to logging) and
   S-163 (a log without Next ends the running rest) —
   `watch/watchos/Tests/WatchSessionEngineTests/WatchRestSurfaceTests.swift` · new `test`s.
8. [ ] The same three scenarios on the twin surface —
   `test/watch_rest_surface_test.dart` · new `test`s (plain `test()`; the surface is built and pumped
   with `tester.pump`, never a real delay — FakeAsync hangs).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test`;
`.github/copilot/scripts/macos/gateway.sh test test/watch_rest_surface_test.dart test/watch_logging_timers_test.dart test/watch_logging_surfaces_test.dart`;
`.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/watch_rest_surface_test.dart -- lib/watch/logging/watch_logging_state.dart lib/watch/logging/watch_rest_screen.dart`

**Predicted Files**: the five source files above; the two new test files; `WatchLoggingView.swift`
(item 4). The governor builds the watch app scheme for `ContentView.swift` — the package's tests do
not cover the app target, so the implementer says so in its evidence row instead of claiming a green
simulator run.

### Phase 3: the wire refuses a rest length (@dba)

1. [ ] Add the rest clause to the kind rejections — a `rest` timer carrying `plannedDurationMs` is
   refused, with a message naming the count-up rule and citing `docs/global_conventions.md` —
   `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` · `timerKindRejections`
   (`:176-206`).
2. [ ] The same clause, same message, in the Dart validator —
   `lib/core/sync_protocol/message_validator.dart` · `_timerKindRejections` (`:294`).
3. [ ] Forbid `plannedDurationMs` when `kind == "rest"` (a conditional in `$defs.timer`; keep it
   optional and unchanged for every other kind) — `watch/sync_protocol/schemas/envelope.schema.json` ·
   `$defs.timer` (`:321-350`). `messages/timer_state.schema.json:17` and
   `messages/session_snapshot.schema.json:36` `$ref` it, so they need no edit.
4. [ ] Update the fixtures additively: drop the rest's `plannedDurationMs` from
   `fixtures/valid/timer_state.json`; add
   `fixtures/invalid/timer_state_rest_with_planned_duration.json`; register it in
   `fixtures/manifest.json`; check `fixtures/reconciliation/timer_cleared.json`,
   `lifecycle_completed.json` and `snapshot_then_events.json` for a rest with a plan and drop it if
   present — `watch/sync_protocol/fixtures/` · the three fixture files + the manifest.
5. [ ] State the rule in the normative timer-state section and add a dated
   `1 (amended) | 2026-10-08` version-history row naming the tests and fixtures (D-169, D-164) —
   `watch/sync_protocol/PROTOCOL.md` · the timer-state section (`:209`), the version history
   (`:551+`).
6. [ ] S-165 both halves: the updated valid fixture and the round fixture are accepted, the new
   invalid fixture is rejected by the Dart validator — `test/sync_protocol_fixtures_test.dart` · new
   `test`; and the same three fixtures through the Swift validator —
   `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolValidatorTests.swift` · new `test`.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart`;
`.github/copilot/scripts/macos/gateway.sh swift-test`;
`.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/sync_protocol_fixtures_test.dart -- lib/core/sync_protocol/message_validator.dart watch/sync_protocol/schemas/envelope.schema.json`

**Predicted Files**: the two validators; `envelope.schema.json`; the three fixtures + `manifest.json`;
`PROTOCOL.md`; the two test files.

### Phase 4: the rule where agents will hit it (@developer)

1. [ ] Append the Rules-table row (the table is at `:5-15`): bold, verbatim — **"Rest is a count-up
   from the moment a set is logged to the moment the next set starts. There is no preset rest length,
   no rest countdown and no rest alarm anywhere, on any device."** — with one line naming the
   contract test and the routine-prescription exception (D-168) —
   `docs/global_conventions.md` · the Rules table.
2. [ ] State the rule and the wrist's rest screen (D-161) in the rest doc, and fix its `docs/README.md`
   index line (`:92`, which currently says the rest is "DB-backed" — it is Hive-backed and now also
   wrist-fed) — `docs/rest_tracking.md` · the rest-lifecycle section; `docs/README.md` · the Rest
   Tracking index line.
3. [ ] Replace the countdown statements with the count-up rule: the rest is device-local, has no
   length, and the timer records carry none — `docs/watch_session_sync.md` · `:416-418`, `:460`,
   `:498-503` (the "each device keeps its own countdown" paragraph).
4. [ ] Remove the rest-countdown prose (the file must get *smaller*, ceiling 51.2 KB against ~50.1 KB)
   and state the count-up, the rest screen and its single Next control —
   `docs/state_management/watch_surface.md` · `:425`, `:455`, `:466-469`, `:791`.
5. [ ] Update the owner-facing QA walkthrough so a walkthrough cannot teach the old behaviour —
   `:195-198` ("each device keeps only the countdown it started"), `:452` ("both sets and the rest
   countdown are back"), `:511` ("the rest countdown starts") and `:546-548` (the known-gaps list)
   become the count-up and the rest screen; keep and strengthen `:446-449`, which already says a
   restored rest showing a fresh full duration "means someone reintroduced remaining-time, which the
   protocol forbids" — that sentence is the rule, and it stays —
   `docs/watch-app-setup-and-qa.md` · `:195-198`, `:446-449`, `:452`, `:511`, `:546-548`.
6. [ ] Answer the alert question in one sentence (D-163): the rest ping is a count-up nudge for the
   phone's own open rest and is not a rest timer or a rest alarm; the wrist has no rest alert; the
   round/hold timer alerts are unchanged — `docs/theme_and_settings.md` · `:9-11`, `:82-88`.
7. [ ] New contract test: scan `lib/watch/**`, `lib/state/watch/**`, `lib/core/sync_protocol/**`, the
   Swift package's `Sources/**` and `watch/sync_protocol/schemas/**` (plus the rest wording in the
   docs named above) for `restSeconds`, a rest `plannedDurationMs`, a rest planned-duration schema
   property, and "rest countdown"/"remaining" rest wording; the failure message states WHY and points
   at `docs/global_conventions.md`'s rule; the scope excludes the routine prescription (D-168) —
   `test/rest_is_count_up_contract_test.dart` · new `test` (pattern:
   `test/palette_legibility_contract_test.dart`, `test/docs_indexing_contract_test.dart`).
8. [ ] Residue sweep: grep `restSeconds`, a rest `plannedDurationMs`, and "rest countdown"/"rest
   remaining" across `lib/`, `watch/`, `test/` and `docs/`, record the grep and its output in the
   evidence file, fix the one confirmed survivor it finds — the stale "read their countdown from"
   comment in `test/watch_session_rest_timer_append_test.dart:130-133`, about the phone's own rest,
   which is a count-up — and list, in the evidence file, the hits that are legitimately about a
   **round** countdown and must not be "fixed": `lib/watch/logging/watch_logging_screen.dart`'s round
   timer, `docs/constants_reference.md:69` (`round` — "Round counter + countdown"),
   `docs/modality_tracking.md:148,267`, `docs/state_management/workout_state.md:201` and
   `docs/README.md:174`. The sweep is green when no hit remains outside those and D-168's exclusions.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart test/watch_session_rest_timer_append_test.dart`;
`.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/rest_is_count_up_contract_test.dart -- lib/watch watch/watchos/Sources watch/sync_protocol/schemas`;
the residue grep (no hit outside the D-168 exclusions).

**Predicted Files**: the seven docs above; the new contract test; the two residue files.

## Remainder planned as 18c (the wrist's rest reaches the phone)

18b ends with the rule enforced and the wrist counting up; the phone still learns nothing about a rest
that happened on the wrist. 18c implements D-166/D-167 and the history surfaces, as three phases:

- **18c Phase 1 (@developer)** — the wrist emits it: `WatchLoggingState.endRest()`/`log()` records a
  completed rest and emits an `observations_up` `event` with `kind: "rest"` and `afterEntryId`
  (D-166), in the Swift package and the Dart twin, with cross-stack tests; `WatchObservationKind`
  (`WatchRecords.swift:50-54`) gains the value and `WatchObservationRecord` (`:341-343`) carries the
  window; no rest is emitted for a window of no length.
- **18c Phase 2 (@dba)** — the phone writes it: the new kind in `WatchInboxEntry`'s kinds
  (`lib/data/models/models.dart:2618-2633`), in the inbox's `_requiredFields`
  (`lib/state/watch/watch_session_inbox.dart:165-193`) and in the importer's `_effortKinds`
  (`watch_session_importer.dart:103`); a `_createRest` beside `_createEntry` (`:855`) writing through
  `WorkoutRepository.createEntryRest` (`workout_repository.dart:253`) with D-167's rules (index from
  `afterEntryId`, first-write-wins, not an entry, unresolved `afterEntryId` → dropped); the
  `PROTOCOL.md` row for the kind (D-169) and the fixture pair.
- **18c Phase 3 (@developer)** — the history surfaces and the docs: `computeSessionRestTimeMs`
  (`session_summary_service.dart:15-57`) already totals whatever rests exist, so this is a test that an
  imported wrist rest lands in the total; the summary/history screens' rest rows; 17a D-80's and S-79's
  text annotated with D-165's supersedure; the session-sync and watch-surface docs' "what travels"
  lists; the `docs/README.md` index lines.

18c's phases get their own plan file and evidence/review pair when it is written; this section exists
so that 18c's planner re-decides nothing. 18c's numbering continues this series: scenarios from
**S-169**, Ledger entries from **D-170** (D-166/D-167 stay 18b's, marked "implemented in 18c"), and
the plan path `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/`.

## Files Affected

Production: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`WatchLoggingModel.swift`, `WatchLoggingView.swift`, `WatchRestView.swift` (new),
`SyncProtocolValidator.swift`, `ios/OmniTrain Watch App/ContentView.swift`,
`lib/watch/logging/watch_logging_state.dart`, `lib/watch/logging/watch_logging_screen.dart`,
`lib/watch/logging/watch_rest_screen.dart` (new), `lib/core/sync_protocol/message_validator.dart`,
`watch/sync_protocol/schemas/envelope.schema.json`, `watch/sync_protocol/PROTOCOL.md`,
`watch/sync_protocol/fixtures/**`.

Tests: `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`,
`WatchRestSurfaceTests.swift` (new), `WatchRestIsCountUpTests.swift` (new),
`SyncProtocolValidatorTests.swift`, `test/watch_logging_timers_test.dart`,
`test/watch_logging_surfaces_test.dart`, `test/watch_rest_surface_test.dart` (new),
`test/sync_protocol_fixtures_test.dart`, `test/rest_is_count_up_contract_test.dart` (new),
`test/watch_session_rest_timer_append_test.dart` (one comment line).

Docs: `docs/global_conventions.md`, `docs/rest_tracking.md`, `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`,
`docs/theme_and_settings.md`, `docs/README.md`, `docs/constants_reference.md`.

Dependents that only *read* a touched surface (no edits, tests must stay green):
`lib/state/watch/live_session_mirror_state.dart`, `lib/watch/session/watch_timer_math.dart`,
`lib/core/sync_protocol/timer_derivation.dart`, `lib/watch/logging/watch_timer_haptics.dart`,
`test/watch_session_rest_timer_append_test.dart`, `WatchConnectivityBridgeTests.swift`,
`WatchLoggingSurfacesTests.swift`.

## Notes

- **Intermediate state after Phase 1**: the wrist's rest has no length, so the wrist's own rest timer
  no longer fires an alert and the countdown line is gone, but there is no rest screen yet (the
  logging surface simply stays up). That state is shippable and is exactly the owner's first ask
  minus the screen; Phase 2 closes the gap. No migration, no stored-data shape change: the removed
  field was never persisted (timer rows store `plannedDurationMs` as an optional column, and rows
  written before this change may still carry `90_000` — a rest row with a stale plan renders as a
  count-up anyway because the surface no longer reads it; the projection may carry it until that row
  is replaced, which is harmless and needs no migration).
- **Phase 3's refusal and Phase 1's absence interact**: after Phase 1 no wrist emits a rest with a
  plan, and after Phase 3 neither validator would accept one — the two changes are safe in either
  order, which is why Phase 3 can run in parallel.
- **`swift-test` does not build the app target**: `ContentView.swift` (Phase 2, item 5) is only
  compiled by `xcodebuild` against a watchOS simulator, which the governor runs. The plan asks the
  implementer to state that in its evidence row rather than claim it.
- **FakeAsync**: `test/watch_rest_surface_test.dart` builds and pumps the surface with `tester.pump`;
  it never awaits a real delay or opens the Hive harness inside `testWidgets`.
- **The phone is untouched in 18b**: no writer, reader, repository, schema or migration changes, so
  the 18a work and the phone's rest behaviour cannot be affected by this PR. The importer is 18c's.
- **18a overlap**: 18a touches `session_summary_service.dart` and `session_core*` for an unrelated
  crash fix. 18b touches neither, so the two PRs can land in either order; if both are open, the
  second one rebases and re-runs the phone suites.

## Progress

- [x] Phase 1 — the wrist's rest stops having a length (@developer) — complete: `restSeconds`
  deleted in both stacks, `countdown`/`_countdown()` read the round timer only, `startFollowOnTimer`
  starts a rest with no plan, the new `WatchRestIsCountUpTests` scan in place; Swift 349/0, Dart
  `+4133 ~1` all passed, analyze 196/0, `prove-red HEAD` RED for the four count-up cases. Evidence:
  `2026-10-08-18b-watch-rest-count-up-plan.evidence.md`
- [x] Phase 2 — the rest screen, with one control (@developer) — complete: `isResting`/`endRest()`/
  `restElapsedSeconds()` in both stacks, `log()` ends a running rest first, `WatchRestView.swift` +
  the `WatchRestScreen` twin, the `ContentView` branch second in the chain with `WatchLoggingView`'s
  `onLogged` nudge; Dart `+4138 ~1` all passed (5 new cases), Swift 353/0 (4 new cases), analyze 196/0,
  three mutations RED and restored, the `ContentView` branch order stated as governor-verified only.
  Evidence: `2026-10-08-18b-watch-rest-count-up-plan.evidence.md`
- [x] Phase 3 — the wire refuses a rest length (@dba) — complete: the rest clause in both validators
  (`message_validator.dart`, `SyncProtocolValidator.swift`), the schema conditional, the `PROTOCOL.md`
  row, and the FIX run that repaired the rest-with-plan fixtures this clause turned red
  (`test/watch_session_engine_test.dart`, `test/live_mirroring_test.dart`, `test/watch_session_auto_push_test.dart`,
  the two Swift test files); Swift 357/0, Dart `+4141 ~1` all passed, analyze 196/0. Evidence:
  `2026-10-08-18b-watch-rest-count-up-plan.evidence.md` (`## Phase 3 FIX — the rest-with-plan fixtures`)
- [ ] Phase 4 — the rule where agents will hit it (@developer)
- [ ] 18c planned — the wrist's rest reaches the phone

## Assumption Log

[empty — executors append: decision made, options considered, choice + why. The Conductor marks each
RATIFIED (promote to a D-x) or REVERT (remediation).]

### Phase 1 (@developer)

1. **Base ref for `prove-red` = `HEAD` (`d79dd8c`).** The brief's `git log -1 --format=%h` is denied by
   policy (`shell(git log)`), so the base could not be read that way; `gateway.sh git-status`/`git-log`
   showed a clean tree at `d79dd8c`, so that is the base.
2. **The Dart twin's `WatchLoggingDefaults` class was deleted, not emptied.** Its only member was
   `restSeconds`, so deleting the member would have left an empty holder; nothing else referenced it
   (lint 196/0). Options: keep an empty class for symmetry with Swift's `WatchLoggingDefaults` (which
   still holds `roundDurationSeconds`) or delete it — deleted, because Dart has no second member.
3. **No doc edited (plan's Predicted Files: "Nothing else — in particular no … doc").** The wrist
   rest-countdown prose that Phase 1 makes false (`docs/state_management/watch_surface.md:467`,
   `docs/watch_session_sync.md:550`, `docs/watch-app-setup-and-qa.md:486,553`) stays until Phase 4
   items 3–5, which own it.
4. **Survivors outside Phase 1's Predicted Files, left untouched.** `lib/watch/debug/watch_session_debug_surface.dart:243`
   still starts a rest with `plannedDurationMs: _debugRestMs`, and `test/watch_debug_surface_test.dart:80`
   still asserts a `left` line (it passes, because the debug surface writes its own plan); several test
   files still build a 90 s *rest* row directly (`test/watch_session_engine_test.dart`,
   `WatchFileStoreTests.swift`, `WatchLiveMirroringTests.swift`, `WatchSessionEngineTests.swift`). The
   plan predicted none of them; Phase 4's contract scan and residue sweep must decide them.
5. **Two base tests changed subject rather than being deleted.** `WatchTimerHaptics derivation a
   countdown the user ended early never fires`, in both stacks, moved from rest+90 s to a round (60 s,
   stopped at 30 s), because a rest can no longer be owed a haptic at all; and the S-79 group's wrist
   rest is now started with no plan, since S-79 is about ownership, not length.

### Phase 2 (@developer)

1. **The Dart debug harness is not wired (item 5's "only if there is an obvious place" is not met).**
   `lib/watch/debug/watch_logging_debug_main.dart` renders `WatchLoggingScreen` directly inside a
   `Column` with a slot picker and no surface switch, so a rest branch would be a new behaviour in an
   unpredicted file. Options: add a `ListenableBuilder` branch on `isResting` there, or leave it — left
   it, because the Swift shell is the runtime and the plan's Predicted Files do not name the harness.
2. **`prove-red` is not applicable to this phase; mutation proofs stand in its place.** The three
   members and `watch_rest_screen.dart` do not exist at `3cab789`, so the test file cannot compile
   there, and a prove-red over `watch_rest_screen.dart` would have to remove an untracked new file.
   The brief directs the mutation form, so (a) stopped-state, (b) the `log()` guard and (c) the
   count-up were each mutated, seen RED on both stacks, and restored exactly.
3. **The two stacks tick differently, deliberately.** `WatchRestView` uses `TimelineView(.periodic(…,
   by: 1))` (the brief's prescription, no state to own); `WatchRestScreen` uses a 1 s `Timer.periodic`
   + `setState`, mirroring `watch_logging_screen.dart` and cancelling in `dispose`. Both re-read the
   elapsed from the persisted row, so neither ticker is the source of the time.
4. **`ContentView`'s branch order is stated, not proved.** `swift-test` compiles the package only, so
   no package test can reach the app target's `body`; the evidence row records the claim and leaves the
   watchOS-simulator `xcodebuild` to the governor, which is what the plan asks for.

### Phase 3 FIX (@developer)

1. **S-005's reference moved from a rest to a round timer, and the test was renamed.** A rest is a
   count-up, so "the phone's end moment reaches the wrist's rest" has no premise left (D-160); the
   guard — the wrist's own row adopts the phone's end for the *same* kind — survives on
   `WatchTimerKind.round` (`test/live_mirroring_test.dart`, `'a round timer started on the wrist ends
   when the phone says it does'`). Options: delete the case, or move it to a kind that has an end —
   moved, because the cross-stack agreement it pins is still worth a test.
2. **Every rest-with-plan fixture whose plan is *incidental* lost it; the rest were listed, not
   converted.** Fixed: the `_runningRest` helper, the S-77/S-78 setUps and S-004's start
   (`watch_session_engine_test.dart`, `live_mirroring_test.dart`), `autoPush`'s S-71 rest, the Swift
   `timerJson` helper and `wristMidWorkout()` (`WatchSessionEngineTests.swift`), S-002
   (`WatchLiveMirroringTests.swift`), and S-006's false premise on both stacks (its rest now has no end
   and the countdown half moved to a `round` timer). Left, because their assertion *is* a rest's
   remaining/end: `watch_session_engine_test.dart:309,352,1454,1562`, `phone_manage_bridge_test.dart:361`,
   `WatchSessionEngineTests.swift:194,224,952,1412`, `WatchFileStoreTests.swift:151,419` — Phase 1's
   Assumption Log 4 already assigns these to Phase 4's residue sweep, and converting them would change
   what they exercise (`advanceExercise` disposes a rest, not a round).
3. **A production gap found by the sweep, recorded and not fixed.** Neither hand-written validator
   enforces `envelope.schema.json`'s `$defs.timer` `if kind == rest then not: plannedDurationMs`, so a
   rest + plan inside a `session_snapshot` is accepted (only `timer_state` refuses it); the Dart
   validator supports `maximum/pattern/allOf/oneOf/$ref` only. Fixing it is a production change, and
   this brief is tests and fixtures only, so it goes to Phase 4/the owner.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

## Open questions

Owner-visible choices, each with the default this plan proceeds on. Answers are not blocking: the
plan is written on the defaults.

1. **Does the rest screen take over the wrist while resting?** Default: **yes** — the owner asked for
   "its own screen", so while a rest runs the logging surface is replaced (no dial, no End, no picker;
   Next is the only control). Alternative: an overlay strip on top of the logging surface, the way the
   phone shows its rest chip.
2. **Does the rest screen appear after the *last* set of an exercise too?** Default: **yes** — every
   logged set starts a rest, so the athlete sees the rest screen and Next returns them to logging,
   where End/the picker are waiting. Alternative: skip it after the last set (then the athlete must
   use End directly).
3. **Can the wrist's rest be paused?** Default: **no** — one control only (the phone's rest tile can
   be paused, but the wrist's rest screen is deliberately Next-only). Alternative: add a pause later.
4. **Should the wrist's rest land in the phone's history in *this* PR?** Default: **no** — 18b ships
   the count-up, the rest screen, the wire refusal and the rule; the wrist's rest reaching the phone's
   history is 18c (design pinned in D-166/D-167). Reason: 18b already spans two tracks and four
   phases, and the brief's budget rule says to plan the remainder separately when two soft signals
   fire. Alternative: one larger PR (five phases, three tracks).
5. **Should `CLAUDE.md` and `.github/copilot/agent-rules.md` carry a one-line pointer to the rule?**
   These two files are the **owner's** — this plan recommends, and does not make, the edit:
   `Rest is a count-up — never a countdown, never a preset. See docs/global_conventions.md (Rules).`
   Default: **yes, add both lines.** Reason: the owner's own words say the rule has been missed
   repeatedly; the conventions row plus the contract test catch a regression, but a pointer in the
   agent instruction files catches it *before* the code is written. Alternative: rely on the
   conventions row and the contract test alone.
6. **Should the rest screen also show which exercise just ended?** Default: **yes, the name only** —
   the exercise's name is already on the logging surface, so the rest screen shows it for orientation
   and nothing else. Alternative: a bare timer with no name.
