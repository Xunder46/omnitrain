# Evidence — 19e (the wrist's distance model, the package half of GPS)

The plan: `2026-10-10-19e-watch-distance-tracking-plan.md`. Base commit: `f4b4bc0`. Filled in by the phase
that runs; nothing here is pre-filled.

## Baselines

Measured at base commit `f4b4bc0` (D-2214) and after each build phase:

- `gateway.sh swift-test` at `f4b4bc0`: **457 tests, 0 failures**.
- After Phase 1A: **469 tests, 0 failures** (457 + 12 new `WatchDistanceTrackerTests`).
- After Phase 1B: **479 tests, 0 failures** (469 + 10 new `WatchEffortDistanceTests`).
- `gateway.sh lint` (flutter analyze): **196 issues**, all pre-existing `info` notices; no file this unit
  touched carries one.
- `gateway.sh test test/distance_source_import_test.dart`: **7 passed** (part of the measured 95/0
  Dart baseline, D-2214).

## Phase 1A

Report: `.work/crew/19e-gps/report-1A.md`. All 8 items done.

- `WatchRawFix`, `WatchDistanceTracker` (the four named constants, the gates in D-2202's order, the
  haversine step, the jitter floor `max(2, 0.5 × accuracy)`, the monotonic total) — new file
  `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift`.
- `WatchRawFixSource`, `WatchTrackedLocation` (permission passthrough, a fresh tracker per `fixes()`
  call, the mapped stream finishes and cancels with the raw one) — new file
  `watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift`.
- S-3200…S-3207 written with the arithmetic inline (±0.01) — new file
  `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` (12 tests).
- Checks seen: `swift-test --filter WatchDistanceTrackerTests` → `Executed 12 tests, with 0 failures`;
  full `swift-test` → `Executed 469 tests, with 0 failures (0 unexpected) in 1.680 (1.711) seconds`;
  `testS004NoMutatingOperationExistsAnywhereInTheModule` green; lint 196 (pre-existing info only);
  the `import .*hive_workout_repository` invariant clean; no existing test turned red.

## Phase 2A

Report: `.work/crew/19e-gps/report-2A.md`. All 3 items done, comments only.

- `lib/core/services/watch_session_importer.dart` (the comment above the `distanceSource:` argument of
  `_knownDistanceSource`) and the header of `test/distance_source_import_test.dart`: the claim "watch
  sessions never run GPS" replaced by an absent source means a hand-entered distance; a wrist that
  measured it names `gps` (D-2206); `gps` and `estimated` are stored as sent.
- `grep "never run GPS|never runs GPS"` over `lib/` and `test/` → nothing else asserts the claim.
- Checks seen: `test test/distance_source_import_test.dart` → `00:00 +7: All tests passed!`; lint 196;
  the full Dart suite once → `01:58 +4240 ~1: All tests passed!` (4240 passed, 1 skipped, 0 failed).

## Phase 1B

Report: `.work/crew/19e-gps/report-1B.md`. All 8 items done.

- `WatchLoggingState.windowPayload` keeps `coversDistance, isMeasuringDistance`;
  `covered = max(0, cumulativeMeters(at: loggedAt) − cumulativeMeters(at: startedAt))`;
  `distanceMeters` and `distanceSource: "gps"` written together and only when `covered > 0`. New
  private `cumulativeMeters(at:)` reads `engine.sensorSamples`, `kind == WatchSensorKind.gps &&
  value.isFinite && recordedAt <= instant`, newest `sequence` wins, 0 when none. Rounds and drills
  still pass `coversDistance: false`.
- New `WatchEffortDistanceTests.swift`, 10 tests: S-3208, S-3209, S-3210, S-3211, S-3212, S-3214,
  S-3215, S-3216, S-3217, S-3219. Seen red before the source change: `Executed 10 tests, with 12
  failures` (S-3219 green from the start — a hold already carried nothing); after: 0 failures.
- Existing tests changed on purpose (D-2207, D-2210): `testS004TheLoggedEffortCarriesTheGpsTotal`,
  `testAMeasuredDistanceIsWhatTheObservationCarries` (fix moved after `startWork()`, +
  `distanceSource == "gps"`), `testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (fixture
  now `fixtures/valid/observations_up_distance_source.json`, fix after `surface.startWork()`,
  `logged.rejections.isEmpty`). Absence tests untouched and green.
- Checks seen: `--filter WatchSensorRecordingTests` → `Executed 38 tests, with 0 failures`;
  `--filter WatchLoggingSurfacesTests` → `Executed 24 tests, with 0 failures`; full `swift-test` →
  `Executed 479 tests, with 0 failures (0 unexpected) in 1.880 (1.913) seconds`; lint 196; the
  `hive_workout_repository` invariant clean.

## Prover verdicts

Report: `.work/crew/19e-gps/report-prover.md`. The prover derived every predicted value from the
haversine in `WatchDistanceTracker.swift` (R = 6,371,008.8 → 111,195.080 m per degree of latitude;
the plan's 111,194.93 figure differs by 0.14 m/deg, immaterial at every ±0.01 assertion) and wrote
the mutation table the governor applied. It changed three tests and added one:

- `testS3216ASettledDistanceSampleIsNotTheEffortsDistance` strengthened: after `recorder.stop()`
  and the second `startWork()`, the test appends a stored `distance` sample of 5000 directly via
  `engine.appendSensorSample(kind: WatchSensorKind.distance, value: 5000, recordedAt:)`, so the
  settled-kind mutation (E6) now fails at `XCTAssertNil` showing 2000 instead of staying green.
- `testS3206TheAdapterMapsTheSourcesFixesIntoOneMonotonicTotal` strengthened: the second feed's
  stamps moved to t0+90/t0+120, so the shared-tracker mutation fails with an assertion (444.780)
  instead of hanging on `await second.next()` (the time-order guard rejects the back-dated fixes).
- `testS3206TheMappedStreamFinishesWhenTheRawOneDoes` strengthened: the direct `await
  iterator.next()` is replaced by a Task consumed with `for await` and observed through
  `eventually({ ended.isCompleted })`, so the removed-`finish()` mutation fails at the deadline
  instead of hanging.
- NEW `testS3220TheFloorScalesWithTheFixesOwnAccuracy`: an accuracy-20 fix 5.560 m away is under
  the max(2, 0.5 × 20) = 10 m floor (nil, total 0); the next fix 33.358 m from the unmoved
  reference is accepted (total 33.358 ±0.01). Discriminates the scaled floor from a fixed 2 m one.

The prover could not run any check (its shell calls were denied) and its first edit to the
"finishes" test did not compile; a closed fix run corrected it. S-3212 (relaunch) is confirmed a
regression guard with no failing mutation of its own: the rule's inputs are all rebuilt from
storage. The mutation table below is `.work/crew/19e-gps/governor-mutations-3P.md`, verbatim:

| # | Guard (test) | Mutation | Result |
|---|---|---|---|
| T1 | testS3200 | `totalMeters += distance` -> `= distance` | RED |
| T2a | testS3201 | accuracy limit 30 -> 100 | RED (3 failures overall incl. S-3201) |
| T2b | testS3201 | negative accuracy no longer rejected | RED |
| T3 | testS3202 | speed gate removed | RED |
| T4 | testS3203, testS3220 | stillness floor removed | RED (both) |
| T4b | testS3220 | floor fixed at 2 m (accuracy ignored) | RED (S-3220 and S-3203): the case the architect said S-3204 could not tell apart |
| T5 | testS3220 | reference moved on every fix | RED (S-3220, S-3202) |
| T6 | testS3205 | time order not checked | RED |
| A1 | testS3206 (permission), testS3207 (denied) | permission always `.granted` | RED (both) |
| A2b | testS3206 (monotonic total) | one tracker shared across subscriptions | RED, 1 failure (applied by hand after the harness mislabeled it) |
| A3 | testS3206 (finishes) | `continuation.finish()` removed | RED (the deadline-based wait, not a hang) |
| A4 | testS3206 (cancelling) | `onTermination` no longer cancels | RED |
| R1 | testS3207 (carried and settled) | `WatchSensorRecorder.stop()` no longer settles the distance | RED (S-3207 and the older S-002) |
| E6 | testS3216 (strengthened) | the settled `distance` kind read in an effort window | RED (was MISS before the strengthening) |

S-3204: with the mutation "reference moved on every fix" S-3204 itself stays green (every fix in
its fixture is accepted); S-3220 and S-3202 carry it. S-3212 (relaunch) is a regression guard with
no failing mutation: the rule keeps no state outside the stored samples.

## Governor read-backs

- `gateway.sh swift-test` after 1A: **469 tests, 0 failures** — reproduced by the governor.
- `gateway.sh swift-test` after 1B: **479 tests, 0 failures** — reproduced by the governor.
- `gateway.sh lint` (flutter analyze): **196 issues** — matches the baseline.
- `gateway.sh test test/distance_source_import_test.dart`: **passed** (7 tests).
- `swift test` after the prover's changes and the mutation run: **480 tests, 0 failures** (governor).
- Mutation results, phase 1B (harness `.work/2026-10-10-19e/mutate4.py`; each restored
  byte-identical; suite before: 479 tests, 0 failures) — from
  `.work/crew/19e-gps/governor-mutations-1B.md`, verbatim:

| # | Guard | Mutation (WatchLoggingState.swift) | Result |
|---|---|---|---|
| E1 | S-3208, S-3209 | effort distance = `readings.distanceMeters` (session total) | RED (11 failures) |
| E2 | S-3209, S-3208 | no subtraction of the metres before Start | RED (11) |
| E3 | S-3210 (+ the two changed old tests and the shape test) | `distanceSource` line dropped | RED (9) |
| E4 | S-3214, S-3217 | boundary instant excluded (`<` instead of `<=`) | RED (3) |
| E5 | S-3215 | largest qualifying sample instead of newest | RED (1) |
| E6 | S-3216 | the settled `distance` kind read as well | **MISS**: green. Cause: the settled total equals the last fix, so both readings agree. Needs a settled sample that differs from the last fix. |
| E7 | S-3219 | a hold covers distance | RED (1) |

E6's fix (a settled sample that differs from the last fix) is assigned to the prover.
S-3212 (relaunch) has no failing mutation in the current design: the rule keeps no state outside the
stored samples, so there is nothing to cache. It is a regression guard, not a mutation-proven one.

## Review round 1 and fix round

Review: `2026-10-10-19e-watch-distance-tracking-plan.review.md` — **APPROVE WITH FIXES**
(blocker 0 · major 1 · minor 2). Fix round run by the governor (commit
`fix(watch): review round 1 of plan 19e`).

- **Finding 1 (Major) fixed by D-2215 and S-3221**: a restart of the location feed inside an effort
  made the effort lose its distance. An effort's metres are now a chain over the stored `gps`
  samples inside its window (Start, Log], starting from the baseline total at Start; a total below
  the previous one means the subscription restarted and counts as the metres since the restart
  (the same rule the steps summary uses). New test
  `WatchEffortDistanceTests.testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart`.
- **Finding 2 (Minor) fixed**: the stray apostrophe after the Watch Sensors link in
  `docs/distance_source.md` removed (docs keeper, this fold).
- **Finding 3 (Minor) fixed**: the Assumption Log filled (A-1…A-5, pointing at Open questions 1–11
  and the evidence file) (docs keeper, this fold).
- Governor verification: `swift test` **481 tests, 0 failures**; mutations E1–E8 all RED —
  `.work/crew/19e-gps/governor-mutations-fix1.md`, verbatim:

| # | Guard | Mutation | Result |
|---|---|---|---|
| E1 | S-3208, S-3209 | effort distance = the newest reading (session total) | RED |
| E2 | S-3209 | no baseline: the end total alone | RED |
| E3 | S-3210 (+ the two changed old tests, the shape test) | `distanceSource` dropped | RED |
| E4a | S-3214 | baseline excludes a sample AT the start instant | RED |
| E4b | S-3217 | window excludes a sample AT the log instant | RED |
| E5 | S-3215 | baseline = largest qualifying sample | RED |
| E6 | S-3216 | the settled `distance` kind read inside the window | RED |
| E7 | S-3219 | a hold covers distance | RED |
| E8 | S-3221 (new) | a restarted total is read as no movement | RED |
