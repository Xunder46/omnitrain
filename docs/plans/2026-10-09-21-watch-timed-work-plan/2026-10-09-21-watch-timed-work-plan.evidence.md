# Evidence — plan 21, timed work on the watch (one Start button that turns into Log)

Companion to `2026-10-09-21-watch-timed-work-plan.md`. Implementers append their phase's rows here (pass counts, never a claim of
success); the planner's research sections (2–6) are read-only ground truth with file:line. All times are UTC on 2026-09-25, the fixture's own day.

## 1. Baselines — first run of Phase 1A

| Check | Command | Baseline | After the PR |
|---|---|---|---|
| Watch package | `.github/copilot/scripts/macos/gateway.sh swift-test` | to capture (900 s timeout; compiles `watch/watchos`) | fully green after 1B-ii |
| Phone lint | `.github/copilot/scripts/macos/gateway.sh lint` | to capture the pre-existing info-notice count (`flutter analyze` exits non-zero on them) | **identical** — no Dart file moves |
| Phone tests | `.github/copilot/scripts/macos/gateway.sh test` | to capture the pass count | **identical** — no Dart file moves |
| Watch scheme | `xcodebuild` (governor only) | to capture | Phase 3's view items |

No Dart file is touched by this plan (`grep` the diff: every path is under `watch/`, `ios/OmniTrain Watch App/` or `docs/`), so the two
phone checks must be byte-identical at the end; the reviewer re-runs them once and compares counts.

Docs contract facts (`test/docs_indexing_contract_test.dart`): `docs/plans/**` is a `_recordFolder`, so this plan and this evidence file are exempt
from the size ceiling and the content guards. `docs/watch-app-setup-and-qa.md` is a `_recordFile` (exempt too). `docs/state_management/watch_surface.md`
is a real doc page: it fails the suite above **0.80 × 64 KiB = 51.2 KB**, not just above 64 KiB, and the guards ban hex colour literals, flow
headings and user-action arrow chains in it — hence Phase 3 item 5's net-neutral rewording.

## 2. Brief check 1 — what a phone snapshot does to a wrist-started work clock

**It cannot stop one.** `WatchSessionEngine.adoptTimers` (`WatchSessionEngine.swift:683`) stops a timer of an unnamed kind only when
`timers.keys.contains(kind) || (authoritative && senderWroteTimer(kind))`, and `senderWroteTimer` (`:1717`) is true only when the newest row
of that kind has a record id with the `tms-` prefix. A wrist-started row carries a UUID id, so a phone snapshot that names no `elapsed`/`hold`
row leaves the wrist's clock running.

Proved for the `round` kind by `WatchLoggingTimersTests.testS79ASnapshotLeavesTheWristsCountdownRunningAndStopsThePhones` (:601) and
`…testS79AKindNamedNullIsStillCleared` (:642). S-1310 adds the `elapsed` kind the new flow starts. **No new decision; no code change.**

## 3. Brief check 2 — every existing test that dials a length for a timed kind (by name)

`dial` here means `surface.adjust(…)` / a `CaptureReplay` `dial` op on `duration`, `distance`, `rounds` or `round-duration`. The table lists every
test that touches the surface D-1305 removes — not only the dialers, because a test can also reach the same window through the follow-on countdown or
by reading a row that is going away. Twenty tests over six files (plus the replay itself), more than one 8-item run, so Phase 1B splits into 1B-i
and 1B-ii. Group column = the phase that migrates it.

| File | Test | Line | What it does today | Group |
|---|---|---|---|---|
| `WatchLoggingSurfacesTests.swift` | `testS002DurationIsLoggedAsTheWindowThatEndedAtTheLog` | 255 | dials `duration` (60 → 300 s) | 1B-i |
| " | `testS002TheNextEffortPresentsAFreshDuration` | 282 | dials `duration` + `distance`, then reads both back | 1B-i |
| " | `testS002AnExerciseThatCannotCoverDistanceOffersNoDistance` | 299 | no dial — asserts `fields == [duration]` on a `time`-only slot | 1B-i |
| " | `testS003TheRoundCarriesTheTerminologyThePhoneUses` | 313 | no dial — reads the contract's round labels | **no change** (verify) |
| " | `testS003LoggingARoundNumbersItAndStartsTheNextCountdown` | 326 | no dial — logs with no running timer, relies on the follow-on countdown | 1B-i |
| " | `testS003ARoundThatRanItsCountdownEndsWhereTheCountdownDid` | 348 | no dial — same follow-on countdown, then asserts the next window | 1B-i |
| " | `testS004HoldDurationAndExtraLoadAreLoggedTogether` | 381 | dials `duration` (12 → 60 s) + `extraWeight` | 1B-i |
| " | `testS006AManualDistanceReachesTheObservationWithNoFixNeeded` | 409 | dials `duration` + `distance` (4 → 400 m) | 1B-i |
| " | `testS008EveryModalityKeepsThePhonesRoundTermOnTheWrist` | 429 | no dial — reads the contract | **no change** (verify) |
| " | `testEveryValidObservationsEventIsReproducedByTheSurfaceShape` | 592 | dials `duration` + `distance`, compares against the `timed` fixture | 1B-i (see check 4) |
| `WatchLoggingTimersTests.swift` | `testS003LoggingARoundStartsTheNextRoundCountdown` | 185 | no dial — the follow-on countdown is what it asserts | 1B-i |
| " | `testS003TheRoundHapticFiresAtTheInstantTheRoundEnds` | 200 | no dial — logs, then polls to `now + 180` | 1B-i |
| " | `testS003ANewRoundIsANewCountdownSoItFiresAgain` | 219 | no dial — two follow-on countdowns, two milestones | 1B-i |
| `WatchSensorSummaryTests.swift` | `testS235HeartRateWithoutAStepCountSendsNoStepTotal` | 209 | dials `duration` (120 → 1200 s) to place the window | 1B-ii |
| " | `testS235AStepCountThatDidNotMoveIsAMeasuredZero` | 227 | dials `duration` (96 → 960 s, "an 8-minute window from 10:02") | 1B-ii |
| " | `testS236AHoldIsSummarisedOverItsOwnWindow` | 252 | dials `duration` (12 → 60 s) | 1B-ii |
| `WatchSensorRecordingTests.swift` | `testS004TheLoggedEffortCarriesTheGpsTotal` | 277 | **no dial and no timer** — advances 1200 s and logs | 1B-ii |
| " | `testS004WithoutAFixTheDistanceRowIsTheUsersToFill` | 295 | dials `distance` (15 → 1500 m) | 1B-ii |
| " | `testAMeasuredDistanceOutranksTheDial` | 883 | no dial — reads the measured `distance` **row** and its `isMeasured` | 1B-ii |
| `WatchPhoneEntriesTests.swift` | `testS145APhoneEntryOfEveryKindIsTheWristsOwn` | 303 | no dial — reads `value(surface, .rounds)` :346 and `.duration` :363 | 1B-ii |
| `WatchCaptureContractTests.swift` | `CaptureReplay` + its five `testFCap*` cases | 29–265, 271–310 | dials `duration` (1200) + `round-duration` (300) in three cases | 1B-i |

So: nine tests plus the replay dial a length, six reach the same window without dialing, three read a row that disappears, and two need no change
at all — the split is by file, so no run mixes the replay with the sensor files.

**Reading `fields` on a kind that keeps them** (must keep working, not migrated): `WatchLoggingSurfacesTests` :128 (a resistance slot's `reps` row),
:503 (`testNoSessionMeansNothingToLog`, `fields.isEmpty` either way), :532 (S-029) and :575 (S-062) — the last three assert an empty list or a refusal, so
they stay green on a surface that has no length to show.
**Staying green, verify only:** `testTheFirstCapabilityPresentDecidesTheEffortKind` :455, `testS008FreeTrainingFallsBackToASetSurface` :474,
`testNoSessionMeansNothingToLog` :494, the S-029/S-062 tests, `WatchMenuTests.testS1108…` :502, `testS1202…` :515.

## 4. Brief check 3 — what `finishSession()` does to a running work timer

`WatchSessionEngine.finishSession` (`:340`) appends the `session_end` and transitions the session through `transitionTo(status:)`, which stops
**only** `WatchTimerKind.rest` at the terminal instant; a running `elapsed`/`hold`/`round` row stays `running` in storage. On the surface the
readout disappears anyway, because `workTimer` is guarded by `canLog` (D-1302) and an ended session is not a surface to log into.
`WatchTimerHaptics.poll` would still fire a `round` milestone from the leftover row if a plan remained. **Recorded only (D-1309); no code
change.** S-1311 is the guard that `workTimer` never outlives `canLog`.

## 5. Brief check 4 — tests that could also satisfy a new scenario, or go red when two results appear

The shared-registry rule: when a new fixture or a new case lands, list the existing tests it could also satisfy, and the ones that go red when
a second source produces the same result.

- `WatchLoggingSurfacesTests.testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (:592) compares the surface's logged event with the
  `timed` event of `fixtures/valid/observations_up_distance_and_load.json` (which carries `distanceMeters`), by dialing `duration` and
  `distance`. Under D-1305 `adjust` (`WatchLoggingState.swift:547`) guards on `fields`, so on a timed surface both dials become **silent
  no-ops** and the logged key set loses `distanceMeters`. The assertion can then only be satisfied through a **measured** distance (a
  `WatchSensorRecorder` with a fix) — a second mechanism for the same key set, which is why 1B-i re-expresses it that way rather than deleting it.
- `CaptureReplay.dial` (`WatchCaptureContractTests.swift:157`) and `CaptureReplay.log(_:)` (`:168`) read the removed `fields`/follow-on; the
  five `testFCap*` cases therefore go red the moment `fields` shrinks, and go green only with the migrated fixture (1B-i).
- `WatchSensorSummaryTests` :209/:227/:252 and `WatchSensorRecordingTests` :277/:883 read the same removed window source through their own
  harness: three files' worth of tests read one removed surface, so a change to it is never "just" a contract change.
- Registering the new `startWork` op in the shared timeline can satisfy the `testFCap*` cases only through the button — the replay must not call
  `engine.startTimer` itself, or the fixture would stop proving D-1302.

## 6. The F-CAP migration, with its arithmetic

Today the three cases dial the window; after the change each `timed`/`round` effort is started. The Start instants are chosen so **every
`expectedEvents` number and every `expectedImport` number is unchanged** — which is why the Dart half needs no edit (it reads only
`preferences`/`answer` from a timeline: `test/watch_capture_contract_conformance_test.dart:248-256`).

| Case | Entry | Inserted Start | Log op | Window today (dialled) | Window after (Start → Log) | `endedAt` after |
|---|---|---|---|---|---|---|
| all three | `e-run` (`sx-run`, `timed`) | 10:00:00 | 10:20:00 | 1200 s (`dial duration`) | 10:00:00 → 10:20:00 = 1200 s | 10:20:00 |
| all three | `e-r1` (`sx-bjj`, `round`) | 10:25:00 | 10:30:00 | 300 s (`dial round-duration`) | countdown 10:25:00 → 0 at 10:30:00 | 10:30:00 (completion instant) |
| all three | `e-r2` | 10:30:00 | 10:37:05 | 300 s + 120 s pause | start 10:30:00, pause 10:32:00–10:34:00 → 0 at 10:37:00 | 10:37:00, `pausedMs` 120000 |
| all three | `e-r3` | 10:37:05 | 10:42:10 | 300 s | start 10:37:05 → 0 at 10:42:05 | 10:42:05 |

- Inserted ops (4 per case, 12 total): `{"at": …, "op": "startWork"}`. Order matters — the replay applies the array in order. `full` and
  `prompt-off` have `hr` samples at 10:24:30, 10:26:00 and 10:28:00, so the 10:25:00 `startWork` sits **between** the 10:24:30 and 10:26:00
  `hr` ops; at 10:00:00 it comes **after** the `start` op (the session exists first); at 10:30:00 and 10:37:05 it comes **after** the `log` op
  at that instant (the user logs, then starts the next period).
- Deleted ops (6 total): `dial duration` at `full:122`, `no-sensors:658`, `prompt-off:1075`; `dial round-duration` at `full:138`,
  `no-sensors:674`, `prompt-off:1091`. The two `dial`s at 10:43:00 in each case are the *set* slot's reps/load dials and stay.
- New key: `"periodSeconds": 300` per case, passed by `CaptureReplay.build()` as `roundPresetMs`. It is **required**, not cosmetic: the wrist's
  default is 180 s (`WatchLoggingDefaults.roundDurationSeconds`, `WatchLoggingState.swift:24`), and a 180 s period would put `e-r1`'s countdown
  at 10:28:00 and move `endedAt` off the fixture's 10:30:00.
- `CaptureReplay` changes: `apply` gains `case "startWork"`, `build()` passes the preset, `log(_:)` drops the O-13 block (no follow-on
  countdown). `dial` (`:157`) is untouched and becomes the guard: `testS1303ATimedSurfaceHasNoLengthToDial`.

## 7. prove-red / mutation notes

- **Red before the change, green after:** S-1300…S-1306 and S-1312 are red on the pre-change tree (no Start, no title, no readout, a zero-length
  window, a rounds stepper). S-1303 also asserts the milestone count across `poll()`s, so a window-only assertion cannot pass it.
- **Green before and after (guards):** S-1310, S-1311, S-1308, S-1309 and the two menu source-guard tests. Run them on the pre-change tree
  first; a guard that is red before the change is a plan defect, not an implementer's.
- **Mutation for S-1308:** route `set` through `isTimedWork` and the set tests (reps/load steppers, rest after a set, band-assist signs) must go
  red — if they stay green, the guard is not wired to the code path it claims.
- **Mutation for D-1304's guard:** remove the `canLog`/no-timer throw and S-1301 must go red.
- **Mutation for Phase 2's lock:** make `isLocked` read `plannedDurationMs` and `WatchMenuTests.testS1108…` (:502) goes red on the source grep.

## 8. Phase 1A — results (@developer, run of 2026-10-09 17:44–17:49 UTC)

Logs: `.work/gateway/swift-test-20261009-174342-42914.log` (first full run), `…-174117-42008.log` (filtered red build),
`…-174658-44740.log` (full run at the end of the run), `.work/gateway/lint-20261009-174811-45091.log`.

### 8.1 Phase 0.3 — red before implementation

`.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchTimedWorkTests` on the pre-change tree:
**build failed, 26 compile errors**, every one of them "no member `startWork`/`isWorkRunning`/`workElapsedSeconds`/`workRemainingSeconds`/`workTimer`/
`workTimerKind`" or "extra argument `roundPresetMs` in call". The suite cannot compile without the change, so `prove-red HEAD` is RED for a compile
reason and proves nothing: every guard below is proved by mutation instead (recorded original → mutant → verdict → restore).

### 8.2 The new suite, green

| Run | Command | Result |
|---|---|---|
| S-1300…S-1306, S-1310…S-1312 | `swift-test --filter WatchTimedWorkTests` | **10 tests, 0 failures** |

The last filtered run (after every mutation was restored) is `Executed 10 tests, with 0 failures (0 unexpected) in 0.023 s`.

### 8.3 Mutation table — each guard, proved

One mutation at a time; the original text was restored exactly and the suite re-run green before the next one. No step ended with a mutation applied.

| # | Guard | Mutation (the mutant) | Verdict |
|---|---|---|---|
| 1 | D-1304 "no running clock → nothing stored" | `if isTimedWork, workTimer == nil, engine.session == nil` | **RED AT S-1301** (lines 144/148/149) — `1 tests, 3 failures` |
| 2 | the window's start instant | `"startedAt": utcIso(loggedAt)` | **RED AT S-1300, S-1302, S-1312** — `3 failures` |
| 3 | `workTimer` is nil unless `canLog` | dropped `canLog` from its guard | **RED AT S-1311** (lines 459/460) — `2 failures` |
| 4 | D-1305 no dialable row for a drill | `metricKeysByKind[.drill] += duration` | **RED AT S-1302** (line 171) — `1 failure` |
| 5 | D-1303 the preset before Start | `workRemainingSeconds`: `guard let timer = workTimer else { return nil }` | **RED AT S-1303** (lines 205/207) — `2 failures` |
| 6 | D-1302 a second Start does not stack | dropped `!isWorkRunning` from `startWork()` | **RED AT S-1301** (line 154) — `1 failure` |
| 7 | D-1304 Log ends the clock | `if false, let kind = workTimerKind { … stopTimer … }` | **RED AT S-1300, S-1303** — `6 failures` |
| 8 | D-1306 only a set starts a rest | `startFollowOnTimer`: rest started for every kind | **GREEN — no test covered it**; S-1303 gained `engine.timerRows(WatchTimerKind.rest).isEmpty` and then went **RED** at line 241 |
| 9 | D-1306 the round follow-on is gone | `startFollowOnTimer` restored to set→rest, round→countdown | **RED AT S-1303 (5 assertions) and S-1304** — `6 failures` |

Mutations 8 and 9 are the two halves of the same guard: 8 is the "nothing else starts a timer" half (it found the gap and the assertion that closes it),
9 is the exact pre-change behaviour the plan deletes.

### 8.4 The full suite at the end of Phase 1A

`swift-test` (no filter): **414 tests executed, 39 failures (33 unexpected)**, 37 distinct failing test names. Unchanged by the two assertion
additions to S-1303 (identical counts before and after).

| File | Failing tests | Reason (all intended by D-1304/D-1305) |
|---|---|---|
| `WatchCaptureContractTests` | 5 `testFCap*` | `malformed("the surface has no duration to dial")` — the fixture still dials a length (1B-i migrates it) |
| `WatchLoggingSurfacesTests` | 9 | 7 × "start the effort first, then log it"; 2 stale assertions (`fields` has no `duration` row) |
| `WatchLoggingTimersTests` | 3 | "start the effort first, then log it" (the follow-on countdown they relied on is gone) |
| `WatchPhoneEntriesTests` | 1 | 2 stale assertions reading a `rounds`/`duration` dial that no longer exists |
| `WatchSensorSummaryTests` | 9 | 5 × no-duration-to-dial; 4 × start-the-effort-first |
| `WatchSensorRecordingTests` + `WatchSensorRecordingStepsDeniedTests` | 5 + 5 | 6 × no-duration-to-dial; 4 × start-the-effort-first |
| **total** | **37 names / 39 failures** | 33 thrown errors with those two messages, 6 stale assertions |

**Done-Criteria deviation, recorded:** the plan predicts exactly 25 red (the 5 `testFCap*` + 1B-i's 13 + 1B-ii's 7). The actual list is 37 names:
the extras are 12 more tests in `WatchSensorSummaryTests` (9 actual vs 3 predicted) and `WatchSensorRecordingTests`/its `…StepsDenied` subclass
(10 actual vs 3 predicted) — the same two files, failing only for the two intended reasons. No failure falls outside the plan's Predicted Files, and
nothing fails for a reason the decisions do not require. `WatchLoggingSurfacesTests` is 9, not the predicted 10. Flagged for the planner to ratify the
count before 1B (see the plan's Assumption Log).

### 8.5 The other end-of-run checks

| Check | Command | Result |
|---|---|---|
| Phone lint | `lint` | **196 issues, 0 errors, 0 warnings** — all pre-existing `info` notices (`deprecated_member_use`, `constant_identifier_names`, …); no Dart file is in this diff, so the baseline is unchanged. This is the number the plan's row 1 asked to capture |
| Persistence invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | **no matches** |
| Phone tests | `test` | **4226 passed, 1 skipped, "All tests passed!"** — byte-identical to the plan's "no Dart file moves" expectation (`.work/gateway/test-20261009-174822-45226.log`) |
| Watch scheme | `xcodebuild` (governor only) | not run here — Phase 3's view items; the package compiles under `swift-test` |

## 9. Phase 1B-i — the F-CAP fixture and the surface/timer tests (@developer, run of 2026-10-09 18:29–18:39 UTC)

Logs: `.work/gateway/swift-test-20261009-183611-63837.log` (the full run at the end), `.work/gateway/test-20261009-183656-64114.log` (Dart),
`.work/gateway/lint-20261009-183908-64739.log` (phone lint). Filtered and mutation runs stayed under the gateway's line limit, so they are quoted inline.

### 9.1 The red this phase had to clear (same source, pre-migration fixture)

| Suite | Command | Before |
|---|---|---|
| `WatchCaptureContractTests` | `swift-test --filter WatchCaptureContractTests` | **5 red** — the five `testFCap*` replays |
| `WatchLoggingSurfacesTests` | `… --filter WatchLoggingSurfacesTests` | **9 red** — `testEveryValidObservationsEventIsReproducedByTheSurfaceShape`, `testS002AnExerciseThatCannotCoverDistanceOffersNoDistance`, `testS002DurationIsLoggedAsTheWindowThatEndedAtTheLog`, `testS002TheNextEffortPresentsAFreshDuration`, `testS003ARoundThatRanItsCountdownEndsWhereTheCountdownDid`, `testS003LoggingARoundNumbersItAndStartsTheNextCountdown`, `testS004HoldDurationAndExtraLoadAreLoggedTogether`, `testS006AManualDistanceReachesTheObservationWithNoFixNeeded`, `testS062ADrillSendsItsExtraLoadAndNeverALoadKg` |
| `WatchLoggingTimersTests` | `… --filter WatchLoggingTimersTests` | **3 red** — `testS003ANewRoundIsANewCountdownSoItFiresAgain`, `testS003LoggingARoundStartsTheNextRoundCountdown`, `testS003TheRoundHapticFiresAtTheInstantTheRoundEnds` |

### 9.2 The same four files green

| Run | Command | Result |
|---|---|---|
| Contract | `swift-test --filter WatchCaptureContractTests` | **Executed 6 tests, with 0 failures** (5 migrated + the new guard) |
| Surfaces | `swift-test --filter WatchLoggingSurfacesTests` | **Executed 24 tests, with 0 failures** |
| Timers | `swift-test --filter WatchLoggingTimersTests` | **Executed 28 tests, with 0 failures** |

Red → green, test by test (the rename is the only name change; `:line` are the pre-edit lines of the evidence §3 register):

| File | Test | Was red for | Now |
|---|---|---|---|
| `WatchCaptureContractTests` | the five `testFCap*` | the fixture dialled a length (`malformed("the surface has no duration to dial")`) | the timeline Starts each effort, so the replay never dials; the numbers are unchanged |
| `WatchCaptureContractTests` | `testS1303ATimedSurfaceHasNoLengthToDial` (new) | — | asserts a timed surface has no row at all *and* that the replay's `dial` op is refused |
| `WatchLoggingSurfacesTests` | `testS002DurationIsLoggedAsTheWindowThatEndedAtTheLog` (:255) | logged with no running clock | Start at the instant the old dial implied, 300 s to the log; window and numbers unchanged |
| `WatchLoggingSurfacesTests` | `testS002TheNextEffortPresentsAFreshDuration` (:282) | read a fresh *dial* | the next period is its own Start; the second window is `loggedAt − 60` |
| `WatchLoggingSurfacesTests` | `testS002AnExerciseThatCannotCoverDistanceOffersNoDistance` (:299) | expected a `duration` row | asserts `fields.isEmpty` — a timed surface shows nothing to dial (D-1305) |
| `WatchLoggingSurfacesTests` | `testS003LoggingARoundNumbersItAndStartsTheNextCountdown` (:326) → `testS003StartStartsTheRoundCountdown` | relied on the follow-on countdown | Start plans 180 000 ms, Log stops the row and bumps `nextRoundNumber` (D-1303/D-1306) |
| `WatchLoggingSurfacesTests` | `testS003ARoundThatRanItsCountdownEndsWhereTheCountdownDid` (:348) | the second log had no clock | Start opens the countdown, one Log reads it; every asserted instant unchanged |
| `WatchLoggingSurfacesTests` | `testS004HoldDurationAndExtraLoadAreLoggedTogether` (:381) | dialled `duration` | Start 60 s before the log; `extraLoadKg == -10` and the drill's row unchanged |
| `WatchLoggingSurfacesTests` | `testS006AManualDistanceReachesTheObservationWithNoFixNeeded` (:409) → `testS006AManualDistanceNeverReachesTheObservation` | dialled `distance` (4 → 400 m) | a timed surface offers no distance row, so the observation carries none |
| `WatchLoggingSurfacesTests` | `testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (:592) | dialled the fixture's distance | the distance now arrives as a `FakeSensorSource` fix through a `WatchSensorRecorder`; the field set is unchanged |
| `WatchLoggingSurfacesTests` | `testS062ADrillSendsItsExtraLoadAndNeverALoadKg` (:173) | logged with no running clock | Start before Log |
| `WatchLoggingTimersTests` | `testS003LoggingARoundStartsTheNextRoundCountdown` (:185) → `testS003StartStartsTheRoundCountdown` | the follow-on countdown was what it asserted | Start plans the countdown, Log stops it |
| `WatchLoggingTimersTests` | `testS003ANewRoundIsANewCountdownSoItFiresAgain` (:200) | logged to get a countdown | Start opens it; milestone instants unchanged |
| `WatchLoggingTimersTests` | `testS003TheRoundHapticFiresAtTheInstantTheRoundEnds` (:219) | two logs, two follow-on countdowns | Start → 180 s → poll → Log → Start → 180 s → poll; both milestone instants unchanged |

Untouched and re-verified: `testS003TheRoundCarriesTheTerminologyThePhoneUses` (:313) and `testS004HoldDurationAndExtraLoadAreLoggedTogether`'s siblings
that read the contract; `testSteppingMatchesTheSharedContract`; the timer-math tests (:356–:406) and the two S-79 snapshot tests (:601/:642).

### 9.3 The fixture's rest record ids moved +2, by arithmetic

The replay's `idFactory` mints `rec-1`, `rec-2`, … per engine record. The migrated timeline Starts each effort, and a Start mints a work-timer row, so
the two efforts that previously relied on the follow-on countdown now mint two more rows: every `rec-N` after the second Start shifts by two. The three
rest ids therefore move `rec-13-rest → rec-15-rest`, `rec-15-rest → rec-17-rest`, `rec-17-rest → rec-19-rest` — in `expectedEvents` (both `entryId` and
`eventId`), in `receiptedEntryIds`, and in the three derivations (whose time ranges do not move). **No `expectedEvents` or `expectedImport` value moved**,
exactly as evidence §6 predicted. The Dart half reads no record id from a timeline: `test/watch_capture_contract_conformance_test.dart` takes
`preferences`/`answer` only (:248–:256).

### 9.4 prove-red, and the two mutations

`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter WatchCaptureContractTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchCaptureContractTests.swift`
→ **RED AT HEAD (exit 1) for a compile reason**, not an assertion: `error: value of type 'WatchLoggingState' has no member 'startWork'` (:125) and
`error: extra argument 'roundPresetMs' in call` (:204). The 1A source is uncommitted, so HEAD is the pre-1A tree and no guard in these four files can
compile there — the gateway's own verdict line says "use a mutation instead". Every guard is therefore proved by mutation, one at a time, with the
original restored exactly and re-run green (no step ended with a mutation applied).

| # | Guard | Mutant (the exact edit, on the working tree) | Verdict |
|---|---|---|---|
| 1 | D-1303 the round period's 3:00 plan, and D-1306 that Log ends it | `WatchLoggingState.swift:356` `plannedDurationMs: kind == WatchTimerKind.round ? plannedRoundMs : nil` → `plannedDurationMs: nil` | **RED**: surfaces `24 tests, 2 failures` — `testS003StartStartsTheRoundCountdown` (:365 `("nil") is not equal to ("Optional(180000)")`), `testS003ARoundThatRanItsCountdownEndsWhereTheCountdownDid` (:396 XCTUnwrap nil `Date`); timers `28 tests, 4 failures` — `testS003StartStartsTheRoundCountdown` (:197), `testS003ANewRoundIsANewCountdownSoItFiresAgain` (:244/:249), `testS003TheRoundHapticFiresAtTheInstantTheRoundEnds` (:224) |
| 2 | D-1305 a timed surface has no row to dial | `WatchLoggingState.swift:159` `WatchEffortKind.timed: []` → `[WatchMetricKey.duration]` | **RED**: contract `6 tests, 2 failures` — `testS1303ATimedSurfaceHasNoLengthToDial` (:325/:326); surfaces `24 tests, 1 failure` — `testS002AnExerciseThatCannotCoverDistanceOffersNoDistance` (:329) |

Restore verified by `grep` on the source: `:159` is `WatchEffortKind.timed: [],` and `:356` is the round preset again, with no `plannedDurationMs: nil`
anywhere in the file; the full run in §9.5 is the green re-run. S-006's own guard (no distance row ⇒ no manual distance) cannot be told apart from
mutation 2's sibling by a mutant, so it rests on §9.1's red baseline: the pre-migration test dialled a distance and the observation carried 400 m.

### 9.5 The full suite at the end of Phase 1B-i

`swift-test` (no filter): **415 tests executed, 15 failures (7 unexpected), 12 distinct names** — every one inside the three files 1B-ii owns.

| Suite | Executed | Failures | Names |
|---|---|---|---|
| `WatchCaptureContractTests` | 6 | 0 | — |
| `WatchLoggingSurfacesTests` | 24 | 0 | — |
| `WatchLoggingTimersTests` | 28 | 0 | — |
| `WatchTimedWorkTests` (1A's suite) | 10 | 0 | — |
| `WatchPhoneEntriesTests` | 8 | 2 | 1 — `testS145APhoneEntryOfEveryKindIsTheWristsOwn` |
| `WatchSensorRecordingTests` | 38 | 5 | 4 — `testAMeasuredDistanceOutranksTheDial`, `testS004TheLoggedEffortCarriesTheGpsTotal`, `testS004WithoutAFixTheDistanceRowIsTheUsersToFill`, `testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` |
| `WatchSensorRecordingStepsDeniedTests` | 38 | 5 | the same four |
| `WatchSensorSummaryTests` | 17 | 3 | `testS235AStepCountThatDidNotMoveIsAMeasuredZero`, `testS235HeartRateWithoutAStepCountSendsNoStepTotal`, `testS236AHoldIsSummarisedOverItsOwnWindow` |
| every other suite | — | 0 | — |

**Reconciles with §8.4 (39 failures → 15):** −5 contract, −10 surfaces, −3 timers (this phase's own files) and −6 in `WatchSensorSummaryTests`. Those six
were red in 1A because they replay the fixture (`…-174658-44740.log:686–713` shows the error thrown from `WatchCaptureContractTests.swift:159`), so
migrating the timeline fixed them without a test edit. The recording file (5 + 5) and the phone file (2) are unchanged, and both are 1B-ii's. **Done
Criteria met:** green in the four Predicted Files, red only in the three files 1B-ii names.

### 9.6 The other end-of-run checks

| Check | Command | Result |
|---|---|---|
| Phone lint | `lint` | **196 issues** — identical to §8.5's baseline; no Dart file is in this diff |
| Phone tests | `test test/watch_capture_contract_conformance_test.dart test/watch_capture_contract_test.dart test/watch_session_import_test.dart` | **88 passed, "All tests passed!"** — the migrated fixture imports value-for-value on both repositories |
| Persistence invariant | `grep` for `import .*hive_workout_repository` under `lib/state`, `lib/features`, `lib/widgets`, `lib/core` | **no matches** (only `lib/main.dart`, the composition root, imports it) |
| Footprint | `git-diff --stat` | 4 test/fixture files + the two plan records; nothing under `lib/` |
| Watch scheme | `xcodebuild` (governor only) | not run here — Phase 3's view items |

## 10. Phase 1B-ii — the three remaining test files (@developer, run of 2026-10-09 18:48–18:51 UTC)

Logs: `.work/gateway/swift-test-20261009-185015-69866.log` (the full run at the end), `…-184955-69614.log` (mutation 2, red),
`…-185008-69745.log` (green after both restores), `…-184857-69206.log` (the first full run, green), `.work/gateway/lint-20261009-184909-69353.log` (phone
lint). The filtered, mutation and Dart runs stayed under the gateway's line limit, so they are quoted inline.

### 10.1 The red this phase had to clear

| Suite | Command | Before |
|---|---|---|
| `WatchSensorSummaryTests` | `swift-test --filter WatchSensorSummaryTests` | **3 red** — `testS235AStepCountThatDidNotMoveIsAMeasuredZero`, `testS235HeartRateWithoutAStepCountSendsNoStepTotal`, `testS236AHoldIsSummarisedOverItsOwnWindow` |
| `WatchSensorRecordingTests` | `… --filter WatchSensorRecordingTests` | **5 failures / 4 names** — `testAMeasuredDistanceOutranksTheDial`, `testS004TheLoggedEffortCarriesTheGpsTotal`, `testS004WithoutAFixTheDistanceRowIsTheUsersToFill`, `testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` |
| `WatchSensorRecordingStepsDeniedTests` | `… --filter WatchSensorRecordingStepsDeniedTests` | **5 failures / the same 4 names** |
| `WatchPhoneEntriesTests` | `… --filter WatchPhoneEntriesTests` | **2 failures / 1 name** — `testS145APhoneEntryOfEveryKindIsTheWristsOwn` (the brief names 1 failure; §9.5 also shows 2. Both assertions are the same stale read of a `rounds`/`duration` dial, so the migration clears both and the discrepancy is moot) |

### 10.2 The same three files green

| Run | Command | Result |
|---|---|---|
| Summary | `swift-test --filter WatchSensorSummaryTests` | **Executed 17 tests, with 0 failures** |
| Recording | `swift-test --filter WatchSensorRecordingTests` | **Executed 38 tests, with 0 failures** |
| Steps denied | `… --filter WatchSensorRecordingStepsDeniedTests` | **Executed 38 tests, with 0 failures** |
| Phone | `… --filter WatchPhoneEntriesTests` | **Executed 8 tests, with 0 failures** |
| All four together | `… --filter 'WatchSensorRecordingTests\|WatchSensorRecordingStepsDeniedTests\|WatchPhoneEntriesTests\|WatchSensorSummaryTests'` | **Executed 101 tests, with 0 failures** — the run after both mutations were restored |

### 10.3 Red → green, test by test

Every migration follows the brief's rule: Start at the instant the old dial implied (the window's opening instant), the log instant and every asserted
number unchanged. Detent sizes: duration/round-duration 5 s, distance 0.1 unit = 100 m.

| File | Test | Was red for | Now |
|---|---|---|---|
| `WatchSensorSummaryTests` | `testS235HeartRateWithoutAStepCountSendsNoStepTotal` (:227) | dialled 120 × 5 s for the window | `startWork()` at 10:04:00, Log at 10:10:00 — the same 6-minute window; `avgHeartRateBpm` unchanged |
| `WatchSensorSummaryTests` | `testS235AStepCountThatDidNotMoveIsAMeasuredZero` (:248) | dialled 96 × 5 s | `startWork()` at 10:02:00, Log at 10:10:00 — the same 8-minute window; the measured `0.0` unchanged |
| `WatchSensorSummaryTests` | `testS236AHoldIsSummarisedOverItsOwnWindow` (:279/:280) | dialled 12 × 5 s | `startWork()` at 11:00:00, Log at 11:01:00 — the same window; the summary instant and `135.0`/`130.0` unchanged |
| `WatchSensorRecordingTests` | `testS004TheLoggedEffortCarriesTheGpsTotal` (:279) | logged with no running clock | `startWork()` before `clock.advance(1200)`; the fix is latched before Start, so the log still carries 3000 m |
| `WatchSensorRecordingTests` | `testS004WithoutAFixTheDistanceRowIsTheUsersToFill` (:292) → `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow` | expected the dialled 1500 m | asserts `!isMeasuringDistance`, `fields.isEmpty`, that `adjust(distance, 15)` is a no-op, and that the log carries no `distanceMeters` (D-1305 + S-006) |
| `WatchSensorRecordingTests` | `testAMeasuredDistanceOutranksTheDial` (:886) → `testAMeasuredDistanceIsWhatTheObservationCarries` | read a measured distance **row** | asserts `isMeasuringDistance`, `fields.isEmpty`, and that the log carries the measured 3200 m |
| `WatchSensorRecordingTests` | `testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` (:596) | the fixture's rest ids | the three ids shift +2 (`rec-15/17/19-rest`), mirroring the fixture §9.3 |
| `WatchPhoneEntriesTests` | `testS145APhoneEntryOfEveryKindIsTheWristsOwn` (:343) | read the phone's `rounds`/`duration` as dials | `nextRoundNumber == 2`, the phone's own hold rows (`entry-sx-plank-0` 06:00:00–06:01:00Z), `extraWeight == 12`, then the wrist's own `startWork()` → +60 s → Log over the same minute (`startedAt` 06:00:00.000Z, `endedAt` 06:01:00.000Z, `extraLoadKg == 12`), and `engine.entries.count == 4` |

The two renames are the only name changes; no other test file was edited. `value(_:_:)` in `WatchPhoneEntriesTests` stays — the extra-load row still
reads through it.

### 10.4 prove-red, and the two mutations

`prove-red HEAD swift-test -- <these files>` cannot be used: HEAD is the pre-1A tree, so the files do not compile there (no `startWork`, no
`roundPresetMs`), exactly as §9.4 records. Every guard is therefore proved by mutation, one at a time, with the original restored exactly and re-run
green.

| # | Guard | Mutant (the exact edit, on the working tree) | Verdict |
|---|---|---|---|
| 1 | D-1305 a timed surface has no row to dial, so nothing measured and nothing dialled reaches the observation | `WatchLoggingState.swift:159` `WatchEffortKind.timed: []` → `[WatchMetricKey.distance]` | **RED**: recording `38 tests, 2 failures` — `testAMeasuredDistanceIsWhatTheObservationCarries` (:912) and `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow` (:310), both "a timed surface has no … row"; steps-denied `38 tests, 2 failures` — the same two |
| 2 | D-1304 the window is the work clock's own start → the log instant | `WatchLoggingState.swift:736` `"startedAt": utcIso(workTimer?.startedAt ?? loggedAt)` → `"startedAt": utcIso(loggedAt)` | **RED**: summary `17 tests, 9 failures` — `testS236AHoldIsSummarisedOverItsOwnWindow` (:279/:280, the window instant and `135.0` vs `130.0`), `testS235AStepCountThatDidNotMoveIsAMeasuredZero` (:248), `testS235HeartRateWithoutAStepCountSendsNoStepTotal` (:227); phone `8 tests, 1 failure` — `testS145APhoneEntryOfEveryKindIsTheWristsOwn` (:394, the wrist's own hold window) |

Restore verified by `grep` on the source and by `git-diff --stat`: `:159` is `WatchEffortKind.timed: [],`, `:736` is
`utcIso(workTimer?.startedAt ?? loggedAt)`, and the file's footprint is back to **104 insertions / 28 deletions** — the same as before the first
mutation. §10.2's 101-test run and §10.5's full run are the green re-runs.

`testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow`'s *last* assertion (nothing measured ⇒ the observation carries no distance) cannot be told
apart from the rest by a mutant: with the location denied there are no readings at all, so `readings.distanceMeters` is nil whatever the row set is.
That half rests on §8.4's red baseline (the pre-migration test dialled 1500 m and the observation carried it) and on the existing S-006 guard.

### 10.5 The full suite, and the red → green table across the three phases

`swift-test` (no filter, the run after both mutations were restored): **Executed 415 tests, with 0 failures (0 unexpected)** — no expected red left,
no filter, `All tests' passed`. Per suite: contract 6/0, surfaces 24/0, timers 28/0, summary 17/0, recording 38/0, steps-denied 38/0, phone 8/0,
timed work 10/0, start paths 37/0, everything else 0 failures.

| Phase | Suites it owned | Red before the phase | Green after the phase | Full suite at the phase's end |
|---|---|---|---|---|
| 1A | `WatchTimedWorkTests` (new, 10 tests) | 26 compile errors on the pre-change tree (§8.1) | 10 / 0 (§8.2) | 414 executed, **39 failures** (§8.4) |
| 1B-i | `WatchCaptureContractTests`, `WatchLoggingSurfacesTests`, `WatchLoggingTimersTests` + the fixture | contract 5, surfaces 9, timers 3 (§9.1) | contract 6 / 0, surfaces 24 / 0, timers 28 / 0 (§9.2) | 415 executed, **15 failures** (§9.5) |
| 1B-ii | `WatchSensorSummaryTests`, `WatchSensorRecordingTests` + `…StepsDenied`, `WatchPhoneEntriesTests` | summary 3, recording 5, steps-denied 5, phone 2 (§10.1) | summary 17 / 0, recording 38 / 0, steps-denied 38 / 0, phone 8 / 0 (§10.2) | 415 executed, **0 failures** |

**Done Criteria met:** the whole watch package is green with no filter; nothing is red and nothing is filtered out.

### 10.6 The other end-of-run checks

| Check | Command | Result |
|---|---|---|
| Phone lint | `lint` | **196 issues** — identical to §8.5's and §9.6's baseline; no Dart file is in this diff |
| Phone tests | `test test/docs_indexing_contract_test.dart` | **9 passed, "All tests passed!"** — no doc page changed in this phase, so the indexing contract is byte-identical |
| Persistence invariant | `grep` for `import .*hive_workout_repository` under `lib/state`, `lib/features`, `lib/widgets`, `lib/core` | **no matches** |
| Docs naming the renamed tests | `grep` for `testAMeasuredDistanceOutranksTheDial`, `testS004WithoutAFixTheDistanceRowIsTheUsersToFill` across `docs/` and `watch/` | only this plan and this evidence file (the migration register, §3) — **no doc page names a test name, so no doc update is required** |
| Footprint | `git-diff --stat` | the three test files (**43 / 43 / 21** changed lines, matching the edits) + the plan and evidence records; the other eight paths are 1A's and 1B-i's |
| Watch scheme | `xcodebuild` (governor only) | not run here — Phase 3's view items; the package compiles under `swift-test` |


