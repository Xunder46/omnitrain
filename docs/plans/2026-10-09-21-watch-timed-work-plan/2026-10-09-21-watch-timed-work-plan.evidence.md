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
