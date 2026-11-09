# Review: 2026-10-23-65-wrist-hand-distance-plan · P1 (builder-watch), P3 (docs) · working tree vs HEAD
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 0 · tests: governor-run — full `swift test` 916 passed / 0 failed; `xcodebuild` BUILD SUCCEEDED; full `flutter test` green except one known flaky unrelated to this plan (green alone); lead mutations 11 of 12 red after a tests-only fix (the survivor was killed by that fix)
Diff vs Predicted Files: conforms except `watch/sync_protocol/PROTOCOL.md` (P2, D-5) is absent from the diff — see finding 1. Every other predicted file is present; nothing outside the plan's list is in the diff (the plan-61 rest additions in `WatchLoggingState.swift` are per the brief not under review).

## Findings

1. [Major] `watch/sync_protocol/PROTOCOL.md:156` — plan 65 P2 (D-5) is not in the tree: the doc still says only "Distance is entered by hand whenever the watch has no fix" and does not carry the one sentence naming the wrist's rule that this plan made true (GPS wins when it measured movement in the effort's own window; a dial travels as `entered` only when nothing was measured). A maintainer reading the protocol doc cannot tell that a `timed` event's `entered` distance now competes with a GPS measurement, or which wins. Fix: append the planned sentence at l.156 (docs-only, P2 as written). Guard: none needed (docs-only; the plan's P2 names no test).

## Answers to the brief's questions

Q1 (edited tests kept or weakened): all seven kept what they protected; no assertion was dropped without a replacement.
- `WatchBodyweightLoadTests.swift:93` — fixture `sx-run` switched `["time","distance"]` → `["time"]`; the timed-no-rows case is preserved on a time-only exercise.
- `WatchCaptureContractTests.swift:316` (S-1303) — `fields.isEmpty` moved to the new shape `fields == [distance]`; the protected property (no LENGTH row to dial) is kept and the `assertMalformed` duration-dial refusal stays.
- `WatchLoggingSurfacesTests.swift:447` — S-006 → S-9503 is the plan's named D-6 inversion: `distanceMeters == nil` is replaced by `distanceMeters == 5 steps` + `distanceSource == "entered"`; `rejections.isEmpty` is kept; the header map and the l.648 fixture comment updated.
- `WatchTimedWorkTests.swift:142,770` — two fixture switches to time-only, same reason.
- `WatchSensorRecordingTests.swift:368` — S-004 renamed, assertions moved to the new shape (row exists, unmeasured, 0). The old pre-Start `adjust(detents: 15)` call was removed of necessity: under the new behaviour that dial would travel as `entered` and falsify the test's no-distance log expectation; the dial-works-when-unmeasured property is covered by the same file's `testAMeasuredDistanceIsWhatTheObservationCarries` (l.979), which also gained a read-only-dial assertion.
- `WatchLoggingStatusTests.swift:138,173` — fixture switch; the measured-row test moved the fix after Start (required: a pre-Start sample is the baseline, not movement) and kept + strengthened the stepper-cannot-change-a-measured-value property (new value-stays-400 assertion).
- `WatchCrownArmingTests.swift:182,255` — test 1 strengthened (row measured, not armed, turn changes nothing, value stays 400). Test 2's property switched from "a measured row is not armable" to "a metric the exercise does not carry is refused"; the dropped assertion is replaced in the same file's test 1 (`model.arm(WatchMetricKey.distance)` → nil with a measured row), so nothing is lost.

Q2 (slot change between the two reads; leak into a later effort): no and no. In `log(now:)` (`WatchLoggingState.swift:896-940`) `loggedKey` is captured at l.913, `metricPayload`/`windowPayload` run synchronously at l.920-931 reading `dialled[dialledKey]`, and the first `await` is l.933 (`endRest`) — no await between the read and the event build, so the slot cannot change. `dialled[loggedKey] = nil` at l.936 runs only after a successful `appendObservation`, so the next effort of the same exercise starts at 0 (pinned by `WatchHandDistanceTests.testS9505TheNextEffortStartsFromZeroAgain`); if the append throws the dial surviving is correct (the effort was not logged).

Q3–Q5 for plan 66a are in that plan's review file.

## Assumption Log rulings
The plan has no Assumption Log entries; its Decision Ledger decisions were all carried out as written and are ratified: D-1, D-2, D-3, D-4 as implemented (verified in the diff); D-6's named test edits verified (see Q1); D-5 NOT ratified — not implemented (finding 1).

## Scenario coverage
S-9501 → `WatchHandDistanceTests.testS9501ATimedSurfaceOffersADistanceRowOnlyWhenTheExerciseCoversDistance`
S-9502 → `WatchHandDistanceTests.testS9502ADialledDistanceIsLoggedAsEntered`
S-9503 → `WatchLoggingSurfacesTests.testS9503ADialledDistanceReachesTheObservation`
S-9504 → `WatchHandDistanceTests.testS9504AMeasurementOutranksADial`
S-9504b (extra, kills the `measuredValue` session-total mutation) → `testS9504bASecondEffortMeasuresItsOwnWindowNotTheSessionTotal`
S-9505 → `testS9505TheNextEffortStartsFromZeroAgain`
S-9506 a–e → `testS9506a…`, `testS9506b…`, `testS9506c…`, `testS9506d…`, `testS9506eASampleExactlyAtStartIsTheBaselineNotMovement`
S-9507 → `testS9507AZeroOrUntouchedDialSendsNoDistanceKeys`
S-9508 → `testS9508TheEnteredEventPassesThePackageValidation`
S-9509 → `testS9509AHoldAndAPeriodGetNoDistanceTile`
S-9510 → `testS9510TheDialIsReadInThePhonesUnitAndSentInMetres`
No scenario without a test.
