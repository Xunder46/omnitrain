# Plan 21 — timed work on the watch: one Start button that turns into Log

> Status: SEEDED — governor seed written; the planner expands the phases. Seeded Ledger D-1300…D-1313, scenarios S-1300…S-1309.
> **Expanded 2026-10-09 by the planner.** Every seeded entry is kept verbatim; D-1314…D-1316 and S-1310…S-1312 are appended after
> them, and `## Iteration 1` below specifies phases 1A, 1B-i, 1B-ii, 2 and 3 (1B is split so no run exceeds 8 items — the by-name
> list is 20 tests over 6 files; it is in the evidence file). **Next handoff: @developer (Phase 1A).**
> Series: `docs/plans/2026-10-08-18-watch-qa-index.md` row 21. Base: `.work/watch-21/base.txt`.
> Evidence: `2026-10-09-21-watch-timed-work-plan.evidence.md` · Review: `2026-10-09-21-watch-timed-work-plan.review.md` (both beside this file).
> Track: Apple Watch client only (`watch/watchos/`, `ios/OmniTrain Watch App/`) + docs. No wire, phone or Dart change. Delivering the phone's period length to the watch is plan 21b (a contract change), not this plan.

## Goal (owner, 2026-10-08 QA item 5 and 2026-10-09 answers)

Cardio (timed), isometric holds (drill) and sports / martial-arts rounds (round) are logged with a clock, not with steppers.
The wrist shows one big button. **Start** begins the effort; the same button then reads **Log** and saves it. Nothing about
duration or distance is dialled. A sports or martial-arts period is always a **countdown** from the length the phone has
(the wrist cannot change it); **Log** saves that period and does *not* behave as a "+round" button.

## Owner answers that fix the behaviour (2026-10-09)

1. Rounds / periods: always a countdown, preset length comes from the phone's numbers; the wrist does not let the user set it.
2. Cardio distance: **no distance entry** on the wrist. A distance is saved only when the watch itself measured it.
3. No Discard: once Start is pressed the effort ends with Log. (Finish ends the whole workout as before.)

## Acceptance criteria

1. For a timed, drill or round exercise the logging screen shows **Start** before the effort runs and **Log** while it runs. There is
   no duration, distance, rounds or round-length stepper and the crown does nothing on those rows. A drill keeps its **Extra load** row.
2. Timed and drill count **up** from Start; the readout is derived from stored timer timestamps (survives screen-off and relaunch).
3. A round / period counts **down** from its preset length (this plan: the existing 3:00 default until 21b delivers the phone's number);
   the existing end-of-countdown haptic still fires once. **Log** is only live while the period runs; it saves one period with its own
   window; the period number is the count already logged + 1; there is no stepper and no automatic next countdown (the user presses Start again).
4. Log saves exactly what happened: window = Start instant → Log instant (a round that ran past zero ends at zero, as today). Distance only when
   the watch measured it. Heart-rate and step summaries are unchanged.
5. Starting an effort ends a running rest at the Start instant (the rest is saved to the phone as today).
6. A set exercise (reps/load) is unchanged: steppers, **Log**, rest after the set.
7. While a timed effort runs, the menu does not jump to another exercise (a running effort belongs to its exercise); **Finish** still works.
8. `swift test` and the watch scheme build stay green; the flutter suite is unchanged.

### Acceptance criteria → scenarios

| # | Scenarios | # | Scenarios |
|---|---|---|---|
| 1 | S-1300, S-1302, S-1303, S-1308 | 5 | S-1305 |
| 2 | S-1306, S-1312 | 6 | S-1308 |
| 3 | S-1303, S-1304 | 7 | S-1307 |
| 4 | S-1300, S-1304, S-1309 | 8 | S-1309, plus every phase's Done Criteria |

## Decision Ledger (seeded; do not edit, renumber or delete — append only)

- **D-1300** "Timed work" = effort kind `timed`, `drill` or `round` (`WatchEffortKind`, `WatchLoggingState.swift:29`). `set` is untouched. The Dart Wear client
  (`lib/watch/logging/`) is not changed (plans 18b–20 precedent: Swift only); the docs say so.
- **D-1301** The work clock is a stored engine timer, one kind per effort kind: `timed` → `WatchTimerKind.elapsed`, `drill` → `.hold`, `round` → `.round`
  (`WatchRecords.swift:23`). Start = `engine.startTimer(kind, plannedDurationMs:)` (`WatchSessionEngine.swift:1524`); Log ends it with `engine.stopTimer(kind:at:)`.
  Only `round` carries `plannedDurationMs`; `elapsed`/`hold` carry none (count-up). No pause / resume on the wrist.
- **D-1302** `WatchLoggingState` gains: `isTimedWork` (effort kind ≠ set), `workTimerKind`, `workTimer` (newest timer of that kind whose state ≠ stopped, only while `canLog`),
  `isWorkRunning`, `workElapsedSeconds(now:)` (`activeElapsedMs`, `WatchTimerMath.swift`), `workRemainingSeconds(now:)` (round only, `remainingMs`), and
  `startWork() async` (one clock read; ends a running rest at that instant via `endRest(at:)`, then starts the timer; a no-op for `set` or when one already runs).
- **D-1303** Round preset: `private var plannedRoundMs: Int` = `WatchLoggingDefaults.roundDurationSeconds * 1000` (`:24`). It is the single seam plan 21b replaces with the
  phone's number; nothing else reads the default.
- **D-1304** `log()` for a timed kind requires a running work timer, else throws `WatchRecordError.malformed`, stores nothing. The payload: `timed` → `startedAt` =
  timer start, `endedAt` = log instant, `distanceMeters` only when `isMeasuringDistance` and the reading is > 0; `drill` → the same window plus `extraLoadKg` when dialled ≠ 0;
  `round` → the existing `roundWindow` (`:662`, completion instant when the countdown reached zero), `roundNumber = nextRoundNumber` (`:325`), `pausedMs` as today. After the append the
  work timer is stopped at the log instant.
- **D-1305** `fields` (`:337`) for a timed kind returns `[]`; for a drill, `[extraWeight]` only; for a round, `[]`. The duration / distance / rounds / round-length entries leave
  `metricKeysByKind` and `targetsByKind` (`:149-165`) for those kinds. `WatchMetricStepping` and its shared stepping contract are untouched (`testSteppingMatchesTheSharedContract`).
- **D-1306** The round follow-on countdown is removed: `startFollowOnTimer` (`:731`) keeps only the `set` → rest case. A logged period leaves the screen on **Start**.
- **D-1307** The screen (`WatchLoggingView.swift`): for a timed kind, the value rows are replaced by one large readout (count-up `m:ss`, or the round's remaining `m:ss`; before Start a
  round shows its preset and the others `0:00`) and one button, **Start** or **Log** (`model.state.isWorkRunning`). The header keeps the name, the countdown line, the sensor line.
  A round's header also names the period ("Period 2" / "Interval 2" / "Round 2", `roundsLabel`). A set exercise renders exactly as today.
- **D-1308** `WatchLoggingModel` (`WatchLoggingModel.swift:76-84`) gains `startWork()`; `log()` is unchanged in shape. The 1 s ticker already republishes the readout.
- **D-1309** Menu lock: `WatchMenuState` (`WatchMenu.swift:109-140`) exposes `isLocked` (a work timer is running); `jump(to:)` returns false and does nothing while locked;
  the view shows the rows inert with a short caption. **Finish** is never locked. What Finish does to a running work timer is unchanged by this plan (record it in the evidence).
- **D-1310** `WatchTimerHaptics.poll` is untouched: only timers with a plan can reach zero, so count-ups owe no haptic and the round countdown's single haptic is unchanged.
- **D-1311** The rest rule is unchanged: Log still ends a running rest (D-162); Start now does the same. No new timer kind, no wire field, no schema change.
- **D-1312** Docs (remove words before adding; `docs/state_management/watch_surface.md` is ~50.6 KB of its 51.2 KB ceiling): `watch_surface.md` (logging-surface paragraph),
  `docs/watch-app-setup-and-qa.md` (QA steps), QA index row 21. Plan 20/20b records are not rewritten.
- **D-1313** Out of scope: the phone's period length on the wire (21b), pause/resume, a Discard, distance entry, rest changes, the start screen picker, the Dart Wear client, 19c.
- **D-1314** (appended; **supersedes D-1303's initialisation only**, not its name or its default) The round preset is an **injectable seam**: the stored
  property stays `private var plannedRoundMs: Int` (D-1303) and `WatchLoggingState.init` (`WatchLoggingState.swift:167`) gains `roundPresetMs: Int? = nil`,
  which initialises it to the argument `?? WatchLoggingDefaults.roundDurationSeconds * 1000` (`:24`); `startWork()` passes `plannedRoundMs` as
  `plannedDurationMs` for `round` only, and nothing else reads the default. It exists because the shared capture fixture must reproduce a 300 s period
  (D-1315) while D-1305 removes the dialable length row; it is also the seam 21b feeds from `preferences_down`. Every existing caller passes nothing and keeps
  the 3:00 default, so no caller's meaning changes.
- **D-1315** (appended) The F-CAP timeline (`watch/contract/watch_capture_contract.json`) is migrated to the Start → Log flow: each `timed`/`round` effort in
  the three cases is preceded by a `{"op": "startWork"}` at its own `startedAt` (four per case: `e-run`, `e-r1`, `e-r2`, `e-r3`), the six `dial` ops that set
  `duration`/`round-duration` are deleted, each case gains `periodSeconds: 300` (beside `sensorPermissions`) which `CaptureReplay.build()` passes as
  `roundPresetMs`, `CaptureReplay.apply` learns `startWork` → `surface.startWork()`, and `CaptureReplay.log(_:)` stops replaying O-13. **No number moves**:
  every `expectedEvents` value, every `expectedImport` value and the whole Dart half stay as they are — the Dart consumer reads only `preferences` and `answer`
  from a timeline (`test/watch_capture_contract_conformance_test.dart:248-256`) and nothing else, so the op vocabulary is the Swift replay's alone. The
  `description`'s `dial`/follow-on sentence and the two `derivation` sentences that read "loggedAt minus the dialled N s" are reworded to name the Start instant.
- **D-1316** (appended) `WatchLoggingModel` carries the button's and the readout's **rules**, so they are testable on the desktop toolchain and
  `WatchLoggingView` only renders them (D-1307's rules, D-1308's shape): `primaryTitle` = `"Log"` while `state.isWorkRunning`, else `"Start"`, and always
  `"Log"` for a `set`; `primaryAction()` awaits Start when nothing runs, else `log()`; `workReadout` = nil for a `set`, else `WatchLoggingState.clock(…)` of the
  elapsed time (timed, drill) or of the remaining time (round; the preset before Start).

## Core scenarios (seeded fixtures; each states why it is red without the change)

Fixture helpers are the ones `WatchLoggingSurfacesTests` already uses (`surface`, a fixed clock, `FakeWatchConnectivitySession`). Times are UTC, same day.

- **S-1300 Cardio Start → Log.** Slot `timed` (capabilities `time`, `distance`), no sensors. Start at 10:00:00, Log at 10:12:34. Expect one `timed` observation: `startedAt` 10:00:00,
  `endedAt` 10:12:34, **no** `distanceMeters`; `fields.isEmpty`; `workTimer` stopped after the log. *Red today:* `fields` holds duration + distance and Log writes a zero-length window.
- **S-1301 Log before Start.** Same slot, nothing started: `log()` throws, `engine.entries` unchanged, no frame emitted. After `startWork()` a second `startWork()` leaves one timer row.
  *Red today:* Log succeeds with a zero window.
- **S-1302 Drill keeps Extra load.** Slot `drill` (Plank: `hold`, `time`). `fields.map(\.metricKey) == [extraWeight]`; dial −4 detents, Start 10:00:00, Log 10:01:00 → `hold` event, 60 s window, `extraLoadKg`
  at the stepped value. *Red today:* `fields` also holds duration.
- **S-1303 Period is a countdown and Log is not +round.** Session modality `sports`, slot `round`. Start 10:00:00 → `workRemainingSeconds` at 10:01:30 is 90; Log at 10:01:30 → one `round`
  observation, `roundNumber` 1, window 10:00:00–10:01:30; afterwards the round timer is **stopped** and no new countdown row exists; `fields.isEmpty`; a second Start/Log gives `roundNumber` 2.
  *Red today:* Log starts the next countdown and a rounds stepper exists.
- **S-1304 Late Log on a period.** Same fixture, Log at 10:05:00 → `endedAt` 10:03:00 (completion instant), exactly one `WatchTimerMilestone` for the round at 10:03:00 across polls. *Passes today for the
  window; red for the missing Start (guard against regression of the haptic and the window under the new flow).*
- **S-1305 Start ends a rest.** Set logged 10:00:00 (rest running), user jumps to the cardio slot, Start at 10:00:40 → rest timer stopped at 10:00:40 and a `rest` observation 10:00:00–10:00:40
  hung on the set entry. *Red today:* no Start exists, the rest runs on.
- **S-1306 Derived, not counted.** After Start at 10:00:00 a new `WatchLoggingState` over the same engine at 10:03:00 reads `workElapsedSeconds == 180` and `isWorkRunning`; a stopped timer reports not running.
- **S-1307 Menu lock.** With a work timer running, `WatchMenuState.jump(to: otherSlot)` returns false, `isLocked == true`, the current exercise is unchanged; after Log it jumps. *Red today:* no lock.
- **S-1308 Set exercise unchanged.** The existing set tests (reps/load steppers, rest after a set, rest ends at the next log, band-assist signs) pass **unchanged** (negative guard; mutation: route `set` through `isTimedWork`).
- **S-1309 Wire accepts the work clocks.** A `timer_state` row of kind `elapsed` and one of kind `hold`, no `plannedDurationMs`, validates in `SyncProtocolValidator` (Swift) and `message_validator.dart` (Dart), and
  the phone's importer tolerates them (the planner reports the file:line behind this; if the phone rejects them the plan stops and says so — it is a contract change).

### Scenarios appended by the planner (S-1310…S-1312)

- **S-1310 A phone snapshot cannot stop the wrist's work clock.** Fixture: `sx-run` (`time`, `distance`) on the ladder with a second slot `sx-bjj` (`time`, `rounds`);
  the wrist's own Start at 10:00:00 (`elapsed` running); a phone snapshot at 10:00:30 that moves `currentExerciseIndex` to `sx-bjj` and carries the phone's own
  `round` timer row (id `tms-…`). Trigger: `engine.applyMessage(snapshot)`. Expected: the wrist's `elapsed` row is still `running` at 10:00:30 — the phone wrote
  no row of that kind, so `adoptTimers` (`WatchSessionEngine.swift:683`) leaves it alone, and `senderWroteTimer` (`:1717`) is false because the wrist's row id is
  a UUID, not a `tms-` id; the phone's `round` row is the one stopped. Edge case of: S-1306. *Green before the change* (guard): the same rule is proved for
  `round` by `WatchLoggingTimersTests.testS79ASnapshotLeavesTheWristsCountdownRunningAndStopsThePhones` (:601); this adds the `elapsed` kind the new flow starts.
- **S-1311 Finish leaves the work clock running and takes the readout.** Fixture: `sx-run`, Start at 10:00:00, Finish at 10:05:00. Trigger: `WatchMenuState.finish()`.
  Expected: the `session_end` (10:00:00–10:05:00) is appended as today, `canLog` is false, `fields` is empty, `workTimer` is nil and `isWorkRunning` false on the
  surface — while `engine.timerFor(.elapsed)` is still `running` in storage, because the terminal transition stops only `WatchTimerKind.rest`
  (`WatchSessionEngine.swift:340` `finishSession` → `transitionTo(status:)`). Edge case of: S-1306. Recorded, not changed (D-1309); the guard is that no later
  phase may let `workTimer` outlive `canLog`.
- **S-1312 The clock is the storage, not the screen.** Fixture: `sx-run`, Start at 10:00:00 through one `WatchLoggingState`; a *second* state and
  `WatchLoggingModel` over the same engine at 10:03:00 (a relaunch: new objects, same store). Expected: `isWorkRunning` true, `workElapsedSeconds == 180`,
  `model.primaryTitle == "Log"` (not `"Start"`), `model.workReadout == "3:00"`, and Log at 10:03:00 saves the window 10:00:00–10:03:00. *Red today:* there is no
  Start, no title and no readout.

## Phase outline (planner expands into items with file + symbol, Done Criteria, Predicted Files; none over 8 items)

- **Phase 1A — state (developer):** D-1301…D-1306, D-1308 in `WatchLoggingState.swift` and `WatchLoggingModel.swift`; new tests S-1300…S-1306 in a new `WatchTimedWorkTests.swift`.
- **Phase 1B — migrate the existing tests (developer):** every test that dials duration / distance / rounds for a timed kind (`WatchLoggingSurfacesTests.swift` ~265, 291, 391, 418, 606;
  `WatchSensorSummaryTests.swift` ~220, 239, 266; `WatchSensorRecordingTests.swift`; `WatchCaptureContractTests.swift`; `WatchLoggingTimersTests.swift` S-003 round tests) is rewritten to Start → Log
  with the same asserted values; list each by name in the evidence; no test deleted without a replacement.
- **Phase 2 — menu lock (developer):** D-1309 in `WatchMenu.swift` / `WatchMenuView.swift`; S-1307.
- **Phase 3 — surface + docs (developer):** D-1307 in `WatchLoggingView.swift` (and `ios/OmniTrain Watch App/ContentView.swift` only if its call needs to change); D-1312 docs; S-1308/S-1309 evidence. The governor runs `xcodebuild`.

**Expansion (planner).** The phases are written out in `## Iteration 1`: 1A, then 1B split into **1B-i** (the shared capture fixture, the replay and the
surface/timer tests) and **1B-ii** (the summary, recording and phone-entry tests), then 2 and 3 — five phase blocks, none over 8 items. The red list each
phase leaves behind is named in that phase's Done Criteria, so a phase is finished when its own suites are green *and* nothing outside the predicted list fails.

## Code pointers

`WatchLoggingState.swift`: `fields` :337, `metricKeysByKind` :149, `targetsByKind` :157, `log` :568, `metricPayload` :606, `windowPayload` :647, `roundWindow` :662, `startFollowOnTimer` :731, `nextRoundNumber` :325, `roundsLabel` :316.
`WatchLoggingModel.swift` :48-84 (`start`, `poll`, `countdown`, `log`). `WatchLoggingView.swift` :73-94 body, :191 `logButton`. `WatchMenu.swift` :109-140. `WatchSessionEngine.swift` :1524 `startTimer`, :1581 `stopTimer`, :179 `timerFor`.
`WatchTimerMath.swift` `activeElapsedMs`, `remainingMs`, `completionInstant`.

## Feature invariants (only the ones that bite here)

- The wrist's metric vocabulary and stepping are the shared contract: `WatchMetricKey.all` and `WatchMetricStepping` stay equal to
  `watch/contract/watch_logging_contract.json` (asserted on both platforms). D-1305 removes *rows*, never vocabulary or stepping.
- A rest is a count-up that owes no haptic (D-160); a work clock owes its haptic only when it has a plan (D-1310), and only a `round` has one.
- An ended session is not a surface to log into (`canLog`): no work clock readout may outlive it.
- The engine owns time. Every readout and every window is derived from stored rows and the injected clock, never from a ticker's own count.
- The Dart Wear client is **not** migrated (D-1300), so no Swift test may assert that the two surfaces show the same rows.
- `MockWorkoutRepository`/`HiveWorkoutRepository` parity is a phone concern and nothing here touches it: no Dart file moves.

## Existing-Functionality Impact

Each row: touched surface → what already reads it (the grep that found it) → effect → guarded by.

| Touched surface | Existing readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchLoggingState.fields` | `WatchLoggingView.body` (`ForEach(model.state.fields)`); `CaptureReplay.dial` (`WatchCaptureContractTests.swift:157`); `WatchLoggingSurfacesTests` :128, :308, :503, :532, :575; `WatchSensorRecordingTests` :897; `WatchPhoneEntriesTests` :380; `WatchLoggingTimersTests` :319/:324/:329 | a `timed`/`round` field list becomes empty, `drill` keeps only Extra load | S-1300, S-1302, S-1303, S-1308, D-1305; the timed readers are rewritten in 1B-i/1B-ii |
| `metricKeysByKind` / `targetsByKind` (`:149`, `:157`) | only `WatchLoggingState.swift:366` and `:480` (grep `metricKeysByKind|targetsByKind` → 2 code hits, 0 test hits) | rows drop `duration`, `distance`, `rounds`, `roundDuration` for those kinds | D-1305; `testSteppingMatchesTheSharedContract` (`WatchLoggingTimersTests.swift:247`) still green |
| `startFollowOnTimer` (`:731`) | only `log()` calls it (grep `startFollowOnTimer` → 2 hits) | the round follow-on disappears; the `set` → rest path is all that is left | S-1308 (mutation: route `set` through the new flow) |
| `WatchTimerKind.round` timers | `WatchLoggingModel.countdown` (`:60`), `WatchTimerHaptics.poll`, `CaptureReplay.pauseRound`/`resumeRound` (`:186`/`:198`), `WatchLoggingTimersTests` S-003/S-79 | the round timer is now started by Start and stopped by Log; `poll` and the milestone rule are untouched (D-1310) | S-1303, S-1304, S-1310 |
| `WatchSessionEngine.adoptTimers` (`:683`) / `senderWroteTimer` (`:1717`) | the two S-79 tests (`WatchLoggingTimersTests.swift:601`, `:642`) | unchanged; wrist rows carry UUID ids, so a phone snapshot cannot stop a wrist-started work clock | S-1310 (guard, green before and after) |
| `WatchSessionEngine.finishSession` (`:340`) → `transitionTo(status:)` | `WatchMenuTests` finish tests, `WatchLoggingSurfacesTests` :503/:532 | stops only `rest`; a work timer survives a Finish in storage while the readout goes with `canLog` | S-1311 (recorded, D-1309; no code change) |
| `WatchMenu.swift` / `WatchMenuView.swift` source text | two source-guard greps: `WatchMenuTests.testS1108TheMenuSourceNamesNoRestEditOrDelete` (:502) forbids `plannedDurationMs`, `restSeconds`, `deleteEntry`, `removeExercise`; `testS1202…` (:515) forbids the picker tokens | the lock must read timer **states** (`engine.timerFor`), never `plannedDurationMs` | Phase 2 items 1–3; those guards stay green |
| `watch/contract/watch_capture_contract.json` timeline | `CaptureReplay.run` (Swift) and `test/watch_capture_contract_conformance_test.dart:248-256` (Dart: `preferences`, `answer` only) | the op vocabulary changes (D-1315) with no Dart edit | D-1315; the Dart suite's pass count is unchanged |
| `watch/contract/watch_logging_contract.json` | `Fixtures.loggingContract()`, `test/watch_logging_stepping_test.dart`, `test/watch_logging_surfaces_test.dart` | not edited | D-1305 keeps the vocabulary; D-1300 keeps the Dart surface's dials (the documented divergence) |
| `WatchLoggingState.init` (`:167`) | `CaptureReplay.build` (`WatchCaptureContractTests.swift:189`), every test that constructs a state, the shell | a defaulted `roundPresetMs` parameter: no caller's meaning changes | D-1314; S-1300…S-1306 read the 3:00 default |
| `docs/state_management/watch_surface.md` (:428–483) | `test/docs_indexing_contract_test.dart` (bans walkthrough narration and roadmap phrasing), the 64 KiB ceiling, the 51.2 KB split band | the value-rows paragraph is reworded | D-1312; Phase 3 item 5 is net-neutral |

## Iteration 1

Item shape: `<imperative> — <file> · <symbol>`. Each implementer runs its phase's Done Criteria until green, then writes that phase's
rows into `2026-10-09-21-watch-timed-work-plan.evidence.md` (pass counts, never a claim of success). `swift-test` is
`.github/copilot/scripts/macos/gateway.sh swift-test`.

### Phase 1A: the work clock and the surface state (@developer)

1. [ ] Add the work-clock accessors — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `isTimedWork`, `workTimerKind`, `workTimer`,
   `isWorkRunning`, `workElapsedSeconds(now:)`, `workRemainingSeconds(now:)` (D-1301, D-1302). `workTimerKind` maps `timed`→`WatchTimerKind.elapsed`,
   `drill`→`.hold`, `round`→`.round`, `set`→nil; `workTimer` is the newest `engine.timerFor(kind)` row whose state is not `.stopped`, and nil unless `canLog`;
   `workElapsedSeconds` reads `activeElapsedMs` and `workRemainingSeconds` reads `remainingMs` (`WatchTimerMath.swift`).
2. [ ] Add `startWork() async` and the preset seam — same file · `startWork()`, `init` (`:167`) (D-1301, D-1302, D-1303, D-1311, D-1314). One clock read; end a
   running rest with `endRest(at: now)`; then `engine.startTimer(workTimerKind, plannedDurationMs: kind == .round ? roundPresetMs : nil)` (`WatchSessionEngine.swift:1524`).
   No-op when `!canLog`, when `!isTimedWork`, or when `isWorkRunning`. `init` gains `roundPresetMs: Int? = nil`, which initialises the stored
   `plannedRoundMs` (D-1303) to the argument `?? WatchLoggingDefaults.roundDurationSeconds * 1000` (`:24`); nothing else reads the default.
3. [ ] Rewrite the timed-kind payload and its guard — same file · `log(now:)` (`:568`), `metricPayload` (`:606`), `windowPayload` (`:647`) (D-1304). No running
   work timer → throw `WatchRecordError.malformed` and store nothing. `timed`: `startedAt` = the timer's start, `endedAt` = the log instant, `distanceMeters`
   only when `sensors?.isMeasuringDistance == true` and the reading > 0. `drill`: the same window plus `extraLoadKg` when the dialled value is not 0. `round`:
   `roundWindow` (`:662`) as today, `roundNumber = nextRoundNumber` (`:325`), `pausedMs` as today. Stop the timer at the log instant after the append.
4. [ ] Prune the rows and the follow-on — same file · `fields` (`:337`), `metricKeysByKind` (`:149`), `targetsByKind` (`:157`), `startFollowOnTimer` (`:731`)
   (D-1305, D-1306). `fields` is `[]` for `timed`/`round`, `[extraWeight]` for `drill`, unchanged for `set`; drop `duration`, `distance`, `rounds` and
   `roundDuration` from both tables for those kinds; `startFollowOnTimer` keeps only the `set` → rest case. `WatchMetricKey.all` and `WatchMetricStepping` are
   not touched.
5. [ ] Give the model the button and the readout — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` · `startWork()`, `primaryTitle`,
   `primaryAction()`, `workReadout` (D-1308, D-1316), each followed by `poll()`.
6. [ ] New `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` — the suite · `testS1300TimedWorkIsLoggedAsTheWindowFromStartToLog`,
   `testS1301LogBeforeStartStoresNothing`, `testS1302ADrillKeepsItsExtraLoadRow`, `testS1303APeriodCountsDownAndLogIsNotARoundButton`,
   `testS1304ALateLogOnAPeriodEndsWhereTheCountdownDid`, `testS1305StartEndsARunningRest`, `testS1306TheClockIsTheStoredTimers`,
   `testS1310APhoneSnapshotLeavesTheWristsWorkClockRunning`, `testS1311FinishLeavesTheWorkClockRunningAndTakesTheReadout`,
   `testS1312ARelaunchKeepsTheButtonOnLog` (S-1300…S-1306 and the guards S-1310…S-1312). Fixtures exactly as the scenarios give them, on the
   `Harness`/`TestClock` of `WatchSessionEngineTests.swift:32`; slots `sx-run` (`time`,`distance`), `sx-plank` (`hold`,`time`), a `rounds` slot.
   S-1303 must assert the milestone count across polls (`WatchTimerHaptics.poll`), not just the window.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` — green in `WatchTimedWorkTests` and everywhere else, with
**exactly** this red list, and no other failure: the five `testFCap*` cases in `WatchCaptureContractTests` plus the 20 tests named in Phase 1B-i (13: the
surface file's 10 and the timer file's 3) and 1B-ii (7). Any failure outside that list blocks the phase; record the actual list in the evidence.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` (new).

### Phase 1B-i: the shared capture fixture and the surface/timer tests (@developer)

1. [ ] Migrate the F-CAP timeline — `watch/contract/watch_capture_contract.json` · the `timeline` of all three cases (D-1315). Insert
   `{"at": <the entry's startedAt>, "op": "startWork"}` before each `log` of a `timed`/`round` entry — `full`/`no-sensors`/`prompt-off` each get four, at
   10:00:00 (`e-run`), 10:25:00 (`e-r1`), 10:30:00 (`e-r2`), 10:37:05 (`e-r3`) — and delete the six `dial` ops that set `duration` (1200) and `round-duration`
   (300). Keep every other op, every `at`, and the array's order: a `startWork` at 10:30:00 or 10:37:05 sits **after** the `log` at that instant.
2. [ ] Add the period and fix the prose — same file · each case's keys, `description`, `derivation` (D-1315). Add `"periodSeconds": 300` beside
   `sensorPermissions`; reword the `description`'s dial/follow-on sentence and the `derivation` sentences that read "loggedAt minus the dialled N s" to name
   the Start instant. **No number in `expectedEvents` or `expectedImport` may move.**
3. [ ] Teach the replay the new flow — `watch/watchos/Tests/WatchSessionEngineTests/WatchCaptureContractTests.swift` · `CaptureReplay.apply` (`:92`),
   `build()` (`:189`), `log(_:)` (`:168`) (D-1315). `apply` gains `case "startWork": try await surface.startWork()`; `build()` passes
   `roundPresetMs: periodSeconds * 1000`; `log(_:)` drops the O-13 block (no follow-on countdown) and keeps only its entry-id assertion. `dial` (`:157`) stays
   exactly as it is — it is now the guard.
4. [ ] Add the dial guard — same file · `testS1303ATimedSurfaceHasNoLengthToDial` (S-1303, D-1305). A surface on the `timed` slot throws from
   `dial("duration", to: 1200)` and one on the `round` slot throws from `dial("round-duration", to: 300)`, each with the replay's own message.
5. [ ] Migrate the surface file — `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` · `:255` and `:282` drop their
   `duration`/`distance` dials and Start at the instant the old dial implied (`:255`: Start 10:00:00, Log 10:06:00, window unchanged at 300 s; `:282`: the
   fresh-period read becomes the next period's own Start); `:299` becomes "a `time`-only slot shows no row at all" (`fields.isEmpty`); `:326` becomes
   `testS003StartStartsTheRoundCountdown` (Start creates the countdown at `plannedDurationMs == 180_000`, Log **stops** it and bumps `nextRoundNumber` to 2 —
   today it relies on the follow-on countdown and asserts nothing about Start); `:348` inserts a Start at 10:00:00 and keeps every assertion (window
   10:00:00 → the completion instant 10:03:00, logged at 10:03:20); `:381` drops the `duration` dial, Starts 60 s before the log and keeps `extraWeight` and
   `extraLoadKg == -10`; `:409` becomes `testS006AManualDistanceNeverReachesTheObservation`; `:592` routes its distance through a `WatchSensorRecorder`
   (`FakeSensorSource`, `WatchSensorRecordingTests.swift:72`) instead of a dial — see the evidence's check 4. `:313` and `:429` read the contract and need
   **no change**: verify, do not edit.
6. [ ] Migrate the timer file — `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` · `:185`
   (`testS003LoggingARoundStartsTheNextRoundCountdown` → `testS003StartStartsTheRoundCountdown`, asserting Start's `plannedDurationMs == 180_000` — the
   wrist's own preset, D-1303 — and that Log stops the row), `:200` and `:219`: none of the three dials; all three rely on the follow-on countdown, so each
   drives Start → poll → Log → Start again and keeps its milestone instants. The timer-math tests at :356–:406 drive `engine.startTimer` directly and must
   stay untouched.
7. [ ] Re-verify and record — `swift-test`: green in `WatchCaptureContractTests` (its five case tests and the new dial guard), in
   `WatchLoggingSurfacesTests` and in `WatchLoggingTimersTests`; the only remaining red is Phase 1B-ii's list. Write this phase's rows into the evidence file.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` — the four files above green, red only in `WatchSensorSummaryTests`,
`WatchSensorRecordingTests`, `WatchPhoneEntriesTests` (the 7 tests named in 1B-ii).

**Predicted Files**: `watch/contract/watch_capture_contract.json`, `watch/watchos/Tests/WatchSessionEngineTests/WatchCaptureContractTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`.

### Phase 1B-ii: the summary, recording and phone-entry tests (@developer)

1. [ ] Migrate the summary tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSummaryTests.swift` ·
   `testS235HeartRateWithoutAStepCountSendsNoStepTotal` (:209), `testS235AStepCountThatDidNotMoveIsAMeasuredZero` (:227),
   `testS236AHoldIsSummarisedOverItsOwnWindow` (:252): Start at the window's opening instant, keep the log instant, keep every asserted number.
2. [ ] Migrate the recording tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` ·
   `testS004TheLoggedEffortCarriesTheGpsTotal` (:277, no dial today — it logs with no running timer, so it Starts 1200 s before the log and keeps
   `distanceMeters == 3000`), `testS004WithoutAFixTheDistanceRowIsTheUsersToFill` (:295, dials `distance`; replaced by
   `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow`), `testAMeasuredDistanceOutranksTheDial` (:883, reads the measured distance **row**; becomes "the
   measured distance is what the logged observation carries and the surface shows no distance row" — the dial it outranked no longer exists). Route a measured
   distance through `FakeSensorSource.fix(_:)` (`:72`) plus `eventually` (`:106`).
3. [ ] Migrate the phone-entry test — `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift` ·
   `testS145APhoneEntryOfEveryKindIsTheWristsOwn` (:303): replace the `value(surface, .rounds)` (:346) and `value(surface, .duration)` (:363) reads with
   `state.nextRoundNumber` and the engine's own rows, then Start → Log at the same instants.
4. [ ] Re-verify, sweep and record — `swift-test` **fully green**; then re-run the `fields` reads that must be unaffected
   (`WatchLoggingSurfacesTests` :128/:503/:532/:575) and write the red→green table for 1A, 1B-i and 1B-ii into the evidence file, with the pass counts.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (no filter, no expected red), plus
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (docs unchanged so far — it must already be green).

**Predicted Files**: `WatchSensorSummaryTests.swift`, `WatchSensorRecordingTests.swift`, `WatchPhoneEntriesTests.swift` (all under
`watch/watchos/Tests/WatchSessionEngineTests/`), and the evidence file.

### Phase 2: the menu lock (@developer)

1. [ ] Add the lock — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuState.isLocked` (D-1309): true when the engine holds a running
   timer of kind `elapsed`, `hold` or `round` — read `engine.timerFor(kind)?.state`, never `plannedDurationMs` and never the entries
   (`WatchMenuTests.testS1108TheMenuSourceNamesNoRestEditOrDelete` :502 greps this file for that token).
2. [ ] Refuse the jump — same file · `jump(to:)`: return false and change nothing while `isLocked`, before the slot lookup (a locked menu also refuses a slot
   that has vanished).
3. [ ] Show it — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `rowButton` (:69), `finishRow` (:101): rows are inert while `state.isLocked`
   (`.disabled`), with one caption row naming why ("An effort is running"); **Finish stays live** (D-1309) and `rowLabel` (:87) is unchanged.
4. [ ] Test it — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS1307TheMenuDoesNotJumpWhileAWorkClockRuns` (S-1307): on the
   `WatchMenuHarness` (:70), Start a `timed` slot through a `WatchLoggingState` over the harness engine, then `isLocked` is true, `jump(to:)` returns false and
   `currentExerciseIndex` is unchanged; after Log the jump returns true and `isLocked` is false. Add a case for a `round` slot's countdown and one for a `rest`
   (a rest must **not** lock).

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (fully green; `testS1108…` and `testS1202…` still green).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`, `…/WatchMenuView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`.

### Phase 3: the surface and the docs (@developer)

1. [ ] Render the clock — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` · `body` (:50): a `timed`/`drill`/`round` effort renders one readout
   from `model.workReadout` (the elapsed time counting up, the remaining time for a round, the preset before Start) instead of `ForEach(model.state.fields)`;
   a `set` keeps its rows exactly as they are (D-1307, S-1308).
2. [ ] One button — same file · `logButton` (:191) → `primaryButton` reading `model.primaryTitle` and calling `model.primaryAction()`; `.disabled(!model.state.canLog)`
   stays (D-1307).
3. [ ] Header — same file · `header` (:104): the name and sensor line stay; a `round` adds "Period 2" / "Interval 2" / "Round 2" from `state.roundsLabel` (:316)
   and `state.nextRoundNumber` (:325) (D-1307).
4. [ ] Check the shell — `ios/OmniTrain Watch App/ContentView.swift`: change it **only** if its construction of the state/view needs it (it should not, since the
   state is injected as it is); record the check, and the fact that it needed nothing, in the evidence file.
5. [ ] Docs — `docs/state_management/watch_surface.md` · "The wrist shell's second surface" (:428–483) (D-1312): reword the paragraph that lists "the value rows
   that effort needs" so it says a set keeps its rows while a timed/drill/round effort shows one Start/Log button and a clock, and that the period's length is
   the phone's (21b). The file is about 50.6 KB against its 51.2 KB split band, and `test/docs_indexing_contract_test.dart` **fails** above 0.80 of
   the 64 KiB ceiling: reword the same paragraph, cut a redundant clause, add no heading and no arrow chain that names a user action (the contract
   test greps for both).
6. [ ] Docs — `docs/watch-app-setup-and-qa.md` · "The wrist's own logging" (:563–616): add one numbered QA step for the timed/round flow (Start, the readout
   counts up or down, Log saves one period, no duration/distance/rounds/length row, Finish still works) and trim a redundant sentence in the same
   section to stay net-neutral. This file is a `_recordFile` for the indexing contract, so it is exempt from the size ceiling and the content guards —
   keep it tight anyway.
7. [ ] Docs — `docs/plans/2026-10-08-18-watch-qa-index.md` · row 21 (:23): replace the placeholder cells with the plan path, the one-line scope, the track
   `watch client`, the phase count, `D-1300…D-1316, S-1300…S-1312` and the status `planned — @developer Phase 1A`.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (fully green);
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`; the governor runs `xcodebuild` for the watch scheme and reports it in the
evidence file. Both docs stay inside the 51.2 KB band.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift`, `ios/OmniTrain Watch App/ContentView.swift` (only if item 4 needs it),
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-08-18-watch-qa-index.md`.

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/`: `WatchLoggingState.swift`, `WatchLoggingModel.swift`, `WatchLoggingView.swift`, `WatchMenu.swift`,
  `WatchMenuView.swift`.
- `watch/watchos/Tests/WatchSessionEngineTests/`: `WatchTimedWorkTests.swift` (new), `WatchCaptureContractTests.swift`, `WatchLoggingSurfacesTests.swift`,
  `WatchLoggingTimersTests.swift`, `WatchSensorSummaryTests.swift`, `WatchSensorRecordingTests.swift`, `WatchPhoneEntriesTests.swift`, `WatchMenuTests.swift`.
- `watch/contract/watch_capture_contract.json` (the timeline's op vocabulary and one new case key).
- `ios/OmniTrain Watch App/ContentView.swift` (only if the shell's call needs it).
- `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-08-18-watch-qa-index.md`.
- Dependents that only *read* a touched surface and must stay green without edits: `WatchSensorSummaryTests`' `CaptureReplay`-driven tests,
  `WatchSensorRecordingTests.capturedSession()`-driven tests, `WatchLoggingTimersTests` :356–:406, `WatchRestSurfaceTests`, `WatchEmitForwarderTests`,
  and every Dart test (no Dart file moves).

## Notes

- **Dependency graph.** 1A → 1B-i → 1B-ii (each later phase's tests read the fixture 1B-i owns). Phase 2 needs only 1A's `workTimerKind`/`isWorkRunning` (its
  S-1307 test starts a clock through the state), so it may run in parallel with 1B-i/1B-ii. Phase 3 needs 1A only. A re-ordering that lands the visible lock
  earlier is 1A → 2 → 1B-i → 1B-ii → 3, at the cost of showing a lock that guards an effort the user cannot yet start on the surface.
- **Intermediate states.** After 1A the state and model speak Start/Log while the view still renders the (now empty) rows: the wrist shows a bare Log button
  until Phase 3. That is why the suite's red list is explicit per phase rather than "green at 1A".
- **Red by design.** After 1A, `WatchCaptureContractTests` is red because its timeline still dials a length the surface no longer has; 1B-i turns it green.
  The 20 tests 1B-i/1B-ii migrate are red from 1A's `fields`/`log` change until their own phase. Nothing else may be red at any checkpoint.
- **The preset.** 3:00 stays the wrist's own until 21b (D-1303); `roundPresetMs` (D-1314) is where 21b plugs in, and the F-CAP fixture is the only caller that
  passes something else.
- **Legacy.** `WatchLoggingTimersTests` :356–:406 drive `engine.startTimer` with no surface and are unaffected; the `set` surface, the rest surface, the
  stepping tests and the whole Dart half are untouched by construction.

## Open questions (seeded)

- Pressing Start by accident cannot be undone (owner answered: no Discard). The user ends it with Log and deletes the entry on the phone.
- Until 21b ships, every period counts down from 3:00 whatever the phone says.
- A snapshot from the phone that moves the wrist to another exercise while a work timer runs is not handled here.

### Appended by the planner (each with the default taken)

- **The F-CAP fixture gains a `startWork` op and loses its length `dial`s** (D-1315). Default taken: migrate it, because the replay can no longer dial a length
  and the fixture must exercise the same entry point the button uses. The rejected alternative — keep the dials and let `CaptureReplay` call
  `engine.startTimer` directly — would bypass the surface and prove nothing about D-1302. A `"plannedDurationMs"` field on the `startWork` op was also rejected:
  it would put a dialable length back into the fixture's vocabulary, and `WatchMenuTests.testS1108…` (:502) forbids that token in the menu sources.
- **The round preset becomes an injectable seam** (D-1314, derived from the seed and vetoable). Default taken: keep the seeded stored property
  `plannedRoundMs` exactly as D-1303 names it and only make its *initialisation* injectable (`init(roundPresetMs: Int? = nil)`), so no existing caller changes
  meaning and 21b feeds it from `preferences_down`. Alternative: read the default inside `startWork()` and let the fixture keep a case-level key the state reads —
  rejected, it would give the state a second source for the same number.
- **`docs/state_management/watch_surface.md` sits near its split band** (about 50.6 KB of the 51.2 KB ceiling, D-1312). Default taken: reword the existing
  paragraph, net-neutral or shorter. If the reviewer's diff pushes the file past 51.2 KB, split the page before adding rather than after.
- **The Dart Wear client keeps its duration/distance/rounds dials** (D-1300): the two wrists will look different until a later PR. Default taken: state the
  divergence in `watch_surface.md` (Phase 3 item 5) and leave the Dart client alone. No test asserts cross-platform field parity today.
- **`xcodebuild` for the watch scheme is the governor's.** Default taken: Phase 3's view items are verified by `swift-test` compiling the module plus the
  governor's build; a build failure in the view is a Phase 3 remediation, not a re-plan.

## Progress

| Phase | Status |
|---|---|
| 1A | Not started |
| 1B | Not started — split into 1B-i and 1B-ii (the by-name list is 20 tests over 6 files; the brief allows 8 items per run) |
| 1B-i | Not started |
| 1B-ii | Not started |
| 2 | Not started |
| 3 | Not started |

## Assumption Log

- (governor) The menu lock (D-1309) and "no automatic next countdown" (D-1306) are the governor's reading of the owner's answers; both are observable and are listed for the owner to confirm at QA.
- (planner) The F-CAP numbers survive the migration unchanged: each inserted Start instant *is* today's `startedAt`, so no `expectedEvents` or `expectedImport`
  value moves and the Dart half is untouched (D-1315). Options: regenerate the fixture's numbers, or choose Start instants that keep them — kept, because the
  phone's import is what the fixture pins and it must not move. The arithmetic is in the evidence file.
- (planner) The button title and the readout live in `WatchLoggingModel` rather than the view (D-1316). Options: view-only, which cannot be tested without a watch
  target — rejected; the model is the part that builds and is tested on the desktop toolchain.
- (planner) `startWork` is a replay op rather than a replay-side engine call (D-1315): the fixture must exercise the same entry point the button uses.
- (planner) S-1310 and S-1311 are guards, not changes: both behaviours already hold (`adoptTimers` :683, `transitionTo` in `finishSession` :340). Options: make a
  Finish stop the work clock — rejected, D-1309 records the behaviour and the owner has not asked for it.
- (planner) Phase 2's lock reads timer states (`engine.timerFor`), never `plannedDurationMs`: the menu sources are greped by
  `WatchMenuTests.testS1108…` (:502) for exactly that token. Options: read the row's plan — rejected, it is a source-guard violation.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]
