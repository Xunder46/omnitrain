# Review: 2026-10-10-19e watch-distance-tracking · phases 1A/2A/1B/3P/3D · f4b4bc0..HEAD (working tree)
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 2 · tests: governor-run (swift test 480/0; flutter analyze 196 info; Dart import test 7 passed; docs guards 19/19) + reviewer spot-check `swift-test --filter WatchEffortDistanceTests` → Executed 10 tests, with 0 failures
Diff vs Predicted Files: conforms; outside: `.github/copilot/crew-rules.md` (commit 7ad7f97, the brief says to ignore it — a shell-rule wording fix, no code)

## Findings

1. [Major] `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:768` — a recorder stop/restart
   *inside* an effort silently deletes the effort's distance. Trace with real data: Start at t0 while the
   session's `gps` total is 3000; the recorder stops and restarts mid-effort (19f will re-subscribe on
   foreground/background transitions); the fresh subscription's tracker starts at 0 (D-2203), so the next
   stored `gps` sample is e.g. 111.195. At Log: start = `cumulativeMeters(at: startedAt)` = 3000 (the old
   subscription's sample), end = 111.195, `covered = max(0, 111.195 − 3000)` = 0 → the payload carries no
   `distanceMeters` at all, although the user covered 111 m after the restart and the live readout showed
   them. No scenario covers a restart between Start and Log: S-3215 restarts *before* Start, S-3216
   *between* efforts. The green tests cannot show it. Fix (smallest): pin the behaviour with a scenario in
   `WatchEffortDistanceTests` (restart mid-window → no `distanceMeters`) and one sentence in
   `docs/state_management/watch_sensors.md` naming the limitation; escalate the design question (treat a
   total that went backwards mid-window as the new baseline) to 19f's planner. Guard: a
   `WatchEffortDistanceTests` fixture that stops and restarts the recorder between `startWork()` and `log()`.
2. [Minor] `docs/distance_source.md:177` — stray apostrophe after the link: ``[Watch Sensors](state_management/watch_sensors.md)';`` reads as broken markdown in the rendered page. Fix: delete the `'`.
3. [Minor] `docs/plans/2026-10-10-19e-watch-distance-tracking-plan.md` (Assumption Log section) — the log
   was seeded "(empty — filled during the build)" and was never filled, although the build had three phases
   and at least two assumption-shaped events (the third changed test D-2210, the prover's out-of-scope
   S-3219 source mutation, the prover's denied shell). The substance lives in Open questions 1–11 and the
   evidence file, so nothing is lost — but a maintainer reading the log alone sees an empty build. Fix: one
   sentence in the log pointing at Open questions 1–11 and the evidence file's prover section.

## Assumption Log rulings

The plan's Assumption Log section is empty (finding 3). Rulings on the assumptions actually made, as
recorded in Open questions 1–11 and the evidence file:

1. `storedSensorSamples` private, builder reads `engine.sensorSamples` — **ratify** (verified this run:
   `WatchSessionEngine.swift:55` private, `:149` public).
2. A third existing test changes (D-2210) — **ratify**; the shape test's change is strengthening (it now
   also asserts `logged.rejections.isEmpty`).
3. No schema change needed for `distanceSource` — **ratify**; the fixture
   `observations_up_distance_source.json` carries `distanceSource: "gps"` on a timed event and S-3210
   asserts the validator accepts the wrist's event.
4. Haversine arithmetic drifts (5003.772 vs 5003.779; 111.195 vs 111.19493) — **ratify**; immaterial at
   every ±0.01 assertion, and S-3202 asserts the rejection, not the number.
5. S-3211's mutation replaced ("use the end value alone") — **ratify**; E1/E2 in the governor's table
   covered the observable forms.
6. The combined boundary (accuracy 30 AND speed 20 together) untested on purpose — **ratify**; each gate's
   boundary is pinned alone (S-3201, S-3202) and a combined fixture discriminates nothing further.
7. Seed code-pointer drift, symbols authoritative — **ratify**; the numbers I measured this run match the
   architect's (`windowPayload` :759 region, `cumulativeMeters` added below it).
8. Two fixes on one clock instant are one stored row (D-2211) — **ratify**; verified
   `WatchSessionEngine.swift:1281-1288` and the fixtures advance the clock between fixes.
9. The Dart twin diverges (D-2213) — **ratify as recorded**; `lib/watch/logging/` is untouched in this
   diff, and the divergence is the Wear half's to mirror.
10. The prover's S-3219 mutation touched `Sources/` outside its write scope — **ratify with the governor's
    caveat**: applied and reverted inside one run, never committed; the working tree's
    `WatchLoggingState.swift` contains only the phase-1B change. For 19f, move such mutations to a scratch
    copy.
11. `xcodebuild` and full `flutter test` not run by the crew — **ratify**; the governor's read-backs cover
    them (swift test 480/0 after the prover; the Dart suite 4240 passed/1 skipped in phase 2A's report).

Also ratified without a number: the origin is whatever the first accurate fix says, even if its position is
wrong (D-2202 names the on-wrist run as the calibration, 19f's QA step); the tracker's gates are tuning
values, not promises.

## Scenario coverage

- S-3200 → `WatchDistanceTrackerTests.testS3200AcceptedFixesAccumulateTheGreatCircleTotal` (mutation T1 RED)
- S-3201 → `testS3201AnInaccurateFixIsNeverAnOriginAndNeverAdds` (T2a, T2b RED)
- S-3202 → `testS3202AJumpIsIgnoredAndLeavesTheReferenceWhereItWas` (T3 RED)
- S-3203 → `testS3203AStillWristsDriftNeverAccumulates` (T4 RED)
- S-3204 → `testS3204ASlowCreepClearsTheFloorAndMovesTheReference` + S-3220/T4b, T5 (the architect's noted
  gap — a fixed 2 m floor — is closed by `testS3220TheFloorScalesWithTheFixesOwnAccuracy`)
- S-3205 → `testS3205AFixNotAfterTheLastAcceptedOneIsIgnored` (T6 RED)
- S-3206 → `testS3206TheAdapterPassesTheSourcesPermissionThrough`, `...MapsTheSourcesFixesIntoOneMonotonicTotal` (A2b RED), `...FinishesWhenTheRawOneDoes` (A3 RED), `...CancellingTheMappedStreamStopsConsumingTheRawOne` (A4 RED)
- S-3207 → `testS3207TheRecorderCarriesTheTrackedTotalAndSettlesIt` (R1 RED), `testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn` (A1 RED)
- S-3208 → `WatchEffortDistanceTests.testS3208AnEffortCarriesItsOwnWindowsMetres` (E1 RED)
- S-3209 → `testS3209MetresBeforeStartAreNotTheEfforts` (E2 RED)
- S-3210 → `testS3210TheSourceTravelsAndOnlyBesideADistance` (E3 RED)
- S-3211 → `testS3211AWindowThatMovedNothingCarriesNoDistance` (E1/E2 RED)
- S-3212 → `testS3212ARelaunchedStateLogsTheSameWindow` — regression guard, no failing mutation (the rule
  keeps no state outside stored samples; verified `Harness.runningEngine()` builds a fresh engine over the
  same store and restores it)
- S-3213 → `WatchSensorRecordingTests.testS004TheLoggedEffortCarriesTheGpsTotal`, `testAMeasuredDistanceIsWhatTheObservationCarries` (both strengthened: fix after Start, `distanceSource` asserted; the dialled-distance assertion in the second is intact)
- S-3214 → `testS3214ASampleExactlyAtStartCountsAsBeforeIt` (E4 RED)
- S-3215 → `testS3215TheNewestQualifyingSampleWinsNotTheLargestNorTheFirst` (E5 RED)
- S-3216 → `testS3216ASettledDistanceSampleIsNotTheEffortsDistance` (E6 RED after the prover's strengthening: a stored `distance` sample of 5000 that differs from the last fix)
- S-3217 → `testS3217AFixStampedAtTheLogInstantCounts` (E4 RED)
- S-3218 → `WatchLoggingSurfacesTests.testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (fixture `observations_up_distance_source.json`, whose first timed event carries `distanceMeters` + `distanceSource: "gps"` — verified in the fixture; E3 RED)
- S-3219 → `testS3219AHoldLoggedWhileMeasuringCarriesNoDistance` (E7 RED)
- S-3220 → `testS3220TheFloorScalesWithTheFixesOwnAccuracy` (T4b, T5 RED)

## Checked with real data, no finding

- Tracker: first fix inaccurate (origin waits for an accurate one), a long gap then a fix (large dt dilutes
  the speed gate — the metres are real), a fix stamped before the last accepted one (ignored), accuracy
  exactly 30 accepted / 31 refused, speed exactly 20 accepted, NaN/∞ coordinates and accuracy refused, the
  haversine stays finite (`asin(min(1, √a))`), the total never decreases, the floor is measured from the
  last *accepted* point so slow movement with a high-rate feed still accumulates once the displacement
  clears it, longitude wrap is harmless (squared terms).
- `windowPayload`: two efforts in one session (S-3208), a relaunch (S-3212, real fresh engine over the same
  store), an effort with no fix (S-3210's bare effort, S-3211), the settled `distance` sample never read
  (S-3216), two samples on one instant resolved by the later stored row (the store assigns increasing
  sequences, `WatchSessionStore.swift:145-146`), `startedAt` falling back to `loggedAt` yields 0 → absence.
- Pause: the logging surface has no pause for the work timer (`startWork`/`log` only; `pausedAt` machinery
  exists for timers but nothing in `WatchLoggingState` pauses the work timer), so there is no pause path
  that could split the window. If a later unit adds one, the window rule must exclude paused metres.
- Dormant claim: `WatchDistanceTracker`/`WatchTrackedLocation`/`WatchRawFix` appear only in their own two
  source files and `WatchDistanceTrackerTests` (searched `watch/watchos`, `lib`, `ios`); no `import
  CoreLocation`, nothing under `ios/` touched.
- Phone import: `_knownDistanceSource` admits `gps` (`EffortObservation.valueSources`,
  `lib/data/models/models.dart:573`), a distance without a source still reads `entered`, the two rewritten
  comments match the code's behaviour.
- Docs: every cited test exists and asserts the sentence it is named in (all 20 cited tests opened this
  run, including `WatchSensorSourceSourceTests.testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes`,
  which asserts the location probe answers `.unavailable`); the remaining "never run GPS" hits in `docs/`
  are 03b's plan/evidence files, which stay as history; no stale GPS claim left in the three changed docs.

## Round 1 outcome

- Finding 1 (Major) → fixed: D-2215 + S-3221
  (`testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart`), mutation E8 proven RED.
- Finding 2 (Minor) → fixed: the stray apostrophe at `docs/distance_source.md:177` removed.
- Finding 3 (Minor) → fixed: the Assumption Log filled (A-1…A-5, pointing at Open questions 1–11).
