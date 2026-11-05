# Review: 2026-10-10-19f-watch-gps-feed-plan · phases 1A, 2A, gov, 2B, 3 · 14c868d..HEAD (working tree)
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 3 · minor 4 · tests: governor-run — `swift test` 493 tests / 0 failures; docs guards 19/19; `flutter analyze` 196 issues, 0 errors (the D-2311 baseline); `xcodebuild` watch scheme BUILD SUCCEEDED, zero warnings in the changed app files, the built Info.plist carries the Location string. Not re-run by this review (the brief says the governor ran every suite after the last code commit).
Diff vs Predicted Files: conforms — the 16 files are exactly the phases' write scopes (1A's four + the evidence file, 2A's four, the governor's pbxproj, 2B's guard file, the four docs) plus the plan and evidence files themselves, which the plan names.

## Findings

1. [Blocker] `ios/OmniTrain Watch App/CoreLocationRawSource.swift:212-216` — the `hasRequestedAuthorization` latch assumes every request produces exactly one authorization change. If the first answer is a temporary grant ("Allow Once" — the brief's own scenario) the status returns to `.notDetermined` when it expires; the next cardio/sports session in the same process reads `.notDetermined`, registers a waiter, but `guard shouldAsk else { return }` never dispatches a request, no change can ever arrive, and the caller parks forever — and since `WatchSensorCoordinator` runs one serial tail, every later session's sensor start is stuck behind it for the life of the process. The latch's own rationale ("a second request would be silently dropped") is true only while the prompt is up, where re-dispatching is harmless. Fix: always dispatch `requestWhenInUseAuthorization()` for a parked waiter (CoreLocation coalesces during an open prompt and re-prompts after a temporary grant expires); S-3310 counts call sites (text occurrences), not calls, so it stays green. Guard: owner-verified only (app target, no test target; a text guard cannot see it).
2. [Major] `watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift:63-77` with `CoreLocationRawSource.swift:87,208` — a session that ends while the Location question is on screen cannot stop its sensors: the end refresh's `recorder.stop()` is enqueued behind the parked `recorder.start` on the serial tail and waits for the user's answer. Until the answer, the stop that cancels all three sensor tasks and settles the `distance` row never runs (HR/steps keep recording past the session end, the radio stays on, the distance is never settled), and every later sensor refresh queues behind the same parked task. If the answer is "Allow", the start then subscribes location for a session that has already ended. The workout still ends (a separate coordinator). Fix: make the permission wait cancellation-aware (`withTaskCancellationHandler`, resume `.denied` on cancel) and have the coordinator cancel the in-flight tail task when a stop is due, or re-check the session status inside `recorder.start` after the answer. Guard: a package test is writable — a coordinator test whose source parks `locationPermission()` until released, asserting a following `refresh(nil)` completes without waiting for the release (fails today).
3. [Major] `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.evidence.md` (Prover verdicts) and the plan's Progress table — the prover's round is committed (6cc4229 repairs `testS3306`: the t0+100 fix is now fed to the second call, exactly what F5's MISS said was missing; this review re-derived the arithmetic and the repaired test does go red under the init-clock mutant), but the evidence file's `## Prover verdicts` reads "pending", the Progress table shows phase 3 "pending", and the Assumption Log's last entry says "to be recorded here after it runs". A maintainer cannot see the post-repair F5 verdict, and the brief's "17 mutations red" cannot be reconciled with the 13 rows in the governor's table. Fix: record the prover's verdicts (F5 re-run RED AT, the per-fix variant, the reconciliation to 17) and tick the Progress row. Guard: the evidence file itself.
4. [Major] `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` (testS3306) — the prover's second named mutation for S-3306 (the clock read per fix instead of per call) has no test that would fail under it: the clock moves only between calls, and under the per-fix mutant the committed test behaves identically. The real difference is a batched delivery — a fix stamped after the call's start but arriving more than 10 s later (the second fix of a batch) is kept by the real gate and dropped by the mutant. Verdict: unproven. Fix: extend testS3306 with a case that advances the clock mid-stream and asserts a fix stamped after the call's start is still kept.
5. [Minor] `ios/OmniTrain Watch App/CoreLocationRawSource.swift:187-199` — the waiter race: the status can settle between `permission()`'s read of `manager.authorizationStatus` and the waiter's registration (the user flips the setting in Settings at that instant); `locationManagerDidChangeAuthorization` fires with no waiters registered, the dispatched request produces no further change, and the caller parks forever. Small window, permanent hang. Fix: after registering, re-read the status and resume the waiter immediately if it is no longer `.notDetermined` (remove it under the lock so the delegate cannot double-resume). Guard: owner-verified only.
6. [Minor] `ios/OmniTrain Watch App/CoreLocationRawSource.swift:187-199` — mid-session revocation: if the user revokes Location in Settings while a subscription is live, `didChangeAuthorization` fires with no waiters, nothing stops the radio, and the stream goes silently empty until the session ends — the distance freezes with no signal, and the radio drains battery for the rest of the session. Fix: in `didChangeAuthorization`, on `.denied`/`.restricted`, dispatch `stopUpdatingLocation()` to the main queue. Guard: owner-verified only (a source guard could assert the branch).
7. [Minor] `scripts/pre_release_check.sh:274` — the diff made the sentence false: "OmniTrain has no location feature; remove it." The check stays correct (it greps only the phone's Info.plist, which still declares no location), but the sentence a release engineer reads now contradicts the wrist. Fix: reword to name the phone target. Governor action (the script is outside every crew scope). Guard: none (text).
8. [Minor] `docs/state_management/watch_sensors.md` (the "Refused or unavailable location" sentence) — the unavailable half cites testS3315, which is a source guard over the `.unavailable` text, not a behaviour test; the test that asserts the unavailable path end to end is `WatchSensorRecordingTests.testS006HardwareThatIsNotThereIsNotAFailure` (verified this run: both grants `.unavailable`, no subscriptions, no samples). Fix: add testS006 to the citation. Guard: exists.

## Assumption Log rulings
- Architect model (glm-5.3-flash; DeepSeek died twice): RATIFY — process fact, no code claim.
- D-2309 (the second default): RATIFY — verified in `WatchPlatformWorkout.swift`: both forwarding defaults exist; S-3300's outdoor-only store and S-3301's legacy store compile and pass.
- D-2310 (the five fixed-clock constructions): RATIFY — verified in the diff; the two constructions that never consume fixes are untouched.
- D-2312 (`trackedLocation`): RATIFY — verified in the feed.
- D-2313 (`@preconcurrency import CoreLocation`): RATIFY — verified at `CoreLocationRawSource.swift:33`.
- "The prover's S-3306 repair … to be recorded here after it runs": ESCALATE — the repair is committed but no verdict is recorded anywhere (finding 3).

## Scenario coverage
S-3300 → `WatchOutdoorWorkoutTests.testS3300OutdoorsFollowsTheCapabilityProfile` (F1 RED)
S-3301 → `…testS3301TheDefaultKeepsOldShapeStoresWorking` (F2 RED)
S-3302 → the 19c coordinator suites, named, no new test; green inside the 493/0 run (not read individually this run)
S-3303 → `WatchDistanceTrackerTests.testS3303ACachedFixNeverBecomesTheOrigin` (F3 RED)
S-3304 → `…testS3304TheGateBoundaryIsInclusive` (F4 RED)
S-3305 → the two untouched constructions (`testS3206TheAdapterPassesTheSourcesPermissionThrough`, `testS3206CancellingTheMappedStreamStopsConsumingTheRawOne`), named, no mutation per plan
S-3306 → `…testS3306TheClockIsReadOncePerCall` (F5 MISS pre-repair; post-repair verdict unrecorded — finding 3; the per-fix variant uncovered — finding 4)
S-3310 → `WatchSensorSourceSourceTests.testS3310TheRawSourceAsksWhenInUseAndNeverAlways` (F6, F7 RED)
S-3311 → `…testS3311TheFeedDelegatesItsLocationToTheAdapter` (F8 RED)
S-3312 → `…testS3312TheStoreTakesTheAdapterAndRegistersOutdoors` (F9 RED)
S-3313 → `…testS3313TheHostBuildsTheSourceAndTheAdapterOnce` (F10 RED)
S-3314 → `…testS3314TheWatchTargetAsksForLocationInOneSentenceAndNeverAlways` (F11 RED)
S-3315 → `…testS3315LocationOffAnswersUnavailableBeforeAnyStatusIsRead` (F12 RED)
S-3316 → `…testS3316TheRadioFollowsTheSubscribersOnTheMainQueue` (F13 RED)

## Traced and held (no finding)
- The manager is created on the main actor: `WatchAppHost` is `@MainActor` and is built as `@StateObject` in `OmniTrainApp.swift:17`; D-2303's premise holds.
- The gate reads the clock inside the Task before `source.rawFixes()` is evaluated, so no fix can slip past an un-gated window; the boundary is inclusive; a restart re-reads the clock (S-3306's real meaning).
- The subscription life: first subscriber starts, last termination stops, both under the lock; `onTermination` is assigned after registration but AsyncStream invokes it immediately if already terminated; the stop chain (recorder.stop → mapped stream cancelled → inner task cancelled → raw terminated → radio stopped) is intact.
- Batched delivery yields one `WatchRawFix` per `CLLocation`; a negative accuracy reaches the tracker, which refuses it.
- `begin(_:outdoors:)` changes nothing for a lift, a hold or free training (`.unknown`, as before); the recovery path ends a recovered workout and a re-begun one carries the session's own outdoors answer.
- The prompt order (Health then Location) is the host's `$revision` sink: workout refresh before sensors (S-3110).
- The changed existing tests are not weakened: S-3109 now asserts delegation and keeps the no-import/no-`.granted` assertions; S-3110 keeps its four original strings and gains the construction; the 19e constructions' fixed clock reproduces the pre-gate behaviour they always tested.
- The docs' cited tests exist: testS3210 (`WatchEffortDistanceTests.swift:150`), `test/distance_source_import_test.dart`, `WatchLoggingView.sensorLine` (shows distance and pace, `WatchLoggingView.swift:136-145`); `docs/watch_session_capture.md` carries no stale wrist-measuring sentence; `watch-app-setup-and-qa.md`'s "What the wrist cannot do yet" lists load labelling and timers, not distance.

## Round 1 outcome

From `.work/crew/19f/governor-mutations-fix1.md`:

- Finding 1 (Blocker, latched ask): FIXED — G1 RED.
- Finding 5 (waiter race): FIXED — the fix introduced a double resume the governor found by reading and had fixed, G3 RED.
- Finding 6 (revocation mid-session): FIXED — G2 RED.
- Finding 4 (per-fix clock): FIXED — testS3307, G4 RED (S-3306 is not meant to catch it).
- Finding 2 (Major): known limitation, NOT changed — a session that ends while the Location question is on screen keeps its sensors until the user answers (the stop waits behind the parked start on the sensors' serial tail); governor ruling: a wait on a pending modal, not a deadlock; proper fix = a cancellable permission wait plus a coordinator that cancels an in-flight start, a follow-up that reworks the 19d coordinator and its S-3111 guard.
- Finding 3 (verdicts not recorded): recorded in the docs (evidence file, plan Progress and Assumption Log).
- Finding 8 (a citation): recorded in the docs (`watch_sensors.md` cites `WatchSensorRecordingTests.testS006HardwareThatIsNotThereIsNotAFailure`).
- Finding 7 (`scripts/pre_release_check.sh:274`): owner item — reported, not edited.

Mutations this round: P1–P3 and the F5 re-run (4) + G1–G4 (4); total across the unit 21 runs plus the earlier F5 MISS. Suite 496 tests, 0 failures; `xcodebuild` BUILD SUCCEEDED, zero warnings in the changed app files.
