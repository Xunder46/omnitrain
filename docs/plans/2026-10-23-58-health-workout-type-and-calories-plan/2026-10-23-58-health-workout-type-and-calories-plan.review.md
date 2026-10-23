# Review: 2026-10-23-58-health-workout-type-and-calories-plan · P1-P3 · 83c933a8..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: swift 814/0 failures · xcodebuild BUILD SUCCEEDED · flutter 5437 passed, 2 skipped, 0 failed (governor's runs, per brief; not re-run here)
Diff vs Predicted Files: conforms — exactly the 8 files the plan names; `WatchOutdoorWorkoutTests`, `WatchLoggingSurfacesTests`, `WatchWorkoutCoordinatorTests` untouched, as the plan allows ("touch one only where it breaks").
## Findings

None.

Checked and clean, per decision:

- D-1 `forExercise` (WatchPlatformWorkout.swift:117-124): hold → distance → reps/sets/load → generic, hold first exactly as written; the three types are private static lets used only in the new functions; `byModality` literals untouched (S-007 still pins them).
- D-2 `forExercises`/`forSession` (l.126-150): nil for empty, counts per `watchOs` name, tie via `types.first { counts[$0.watchOs] == best }` — the earliest exercise that reaches the top count, matching the plan text verbatim; modality still wins and keeps the unmapped → generic fallback.
- D-3 `start` (l.264): `forSession(session) ?? generic`; still directly callable (S-8802 uses it).
- D-4 lifecycle (l.329-336): active + running nil + type known → `.start`; unknown → `.none`; every other branch unchanged in behaviour.
- D-5 store: one `requestAuthorization`, energy in both the share and the read part, `enableCollection(for: .activeEnergyBurned)` added after the stepCount line, header and `resolveAuthorization` doc comment refreshed; the `workoutType() == .sharingAuthorized` gate unchanged.
- S-8812 asserts statements, not type-name substrings (plan 56 lesson), and pins the exact `enableCollection` statement.
- Edited tests strengthen, none weaken: S-4807/S-4813 expectations go `other` → `running`/`traditionalStrengthTraining` with the `outdoors` assertions untouched; S-007 keeps its `health.begun == [generic.watchOs]` guard and now exercises a genuinely capability-less slot via the helper's existing `capabilities:` parameter (WatchSensorRecordingTests.swift:159-173).
- Docs name only tests that exist (each verified in its file this run: `testS4803…` WatchGpsByExerciseTests.swift:370, `testS4807…` l.187, `testS007EveryMappedModality…` WatchSensorRecordingTests.swift:503, all `testS88xx` in the new file and `testS8812…` in WatchSensorSourceSourceTests.swift) and claim nothing the code does not do; the contract-JSON paragraph matches D-7 (contract untouched, rule lives in Swift alone).

## Brief questions

1. No. An empty free session answers `.none` and `openedForSessionId` stays nil (WatchPlatformWorkout.swift:373-390); the first exercise reaches refresh either through the watch pick (announce → snapshot) or a phone push (the `onIncoming` frame bumps the host revision after the receive, ContentView.swift:190), and the `$revision` sink (ContentView.swift:224-231) then refreshes. Refreshes are serialized by the coordinator's `enqueue` (WatchPlatformWorkout.swift:400-411), the action keys on `running == nil`, and a third refresh sees `running != nil` → `.none`: one begin, never two. A begin that never lands retries on the next refresh exactly as before.
2. No other caller. `workout.refresh` has one production caller (ContentView.swift:228); `WatchWorkoutLifecycle.action` one (WatchPlatformWorkout.swift:379) plus tests. The sensor coordinator starts on session status alone (WatchSensorCoordinator.swift:69-77) and already tolerates a missing workout — the denied-authorization path predates this change — so the sensors' refresh after the workout's in the same sink is unaffected.
3. Yes, exact, including hold-first (WatchPlatformWorkout.swift:117-124, 143).
4. Strong. S-8804's second arm `[run, run, lift]` → `running` kills a "first exercise decides" mutant; S-8805 asserts both tie arms separately; S-8803 asserts hold and plank separately; S-8807/S-8808 pin one-begin and unchanged type. No edited test weakened what it guarded (see Findings). `RecordingGpsOutdoorStore.begins` carries `(activityType, outdoors)` (WatchGpsByExerciseTests.swift:81-84), so S-8802's outdoors assertion is real.
5. No.

## Assumption Log rulings

The plan has no separate Assumption Log; its deferrals live in D-7. Rulings: D-7 items (no ask-before-workout, no distance-to-Health, Dart twin and contract JSON parked) — ratified, owner-scoped to plans 59/60 and the parked drift, and the brief states the contract is deliberately untouched. Owner majority decision and the Free-workout first-exercise rule — ratified (brief, "Facts already established"). Known limit (distance field with no modality → Running, cycling/rowing included) — ratified, stated in the plan's acceptance table and not contradicted by any doc sentence.

## Scenario coverage

S-8801 → WatchWorkoutTypeFromExercisesTests.testS8801ALiftSessionRegistersAsStrengthTraining
S-8802 → …testS8802ARunSessionRegistersAsRunningAndOutdoors
S-8803 → …testS8803AHoldRegistersAsFlexibilityAndAPlankStaysOne
S-8804 → …testS8804TheMajorityDecides
S-8805 → …testS8805ATieGoesToTheEarliestExercise
S-8806 → …testS8806ATimedSlotIsGenericAndAMajorityIsNot
S-8807 → …testS8807AFreeWorkoutWaitsForItsFirstExercise
S-8808 → …testS8808ALaterExerciseNeverChangesTheOpenWorkout
S-8809 → …testS8809AModalityWinsOverTheExercises
S-8810 → …testS8810TheLifecycleWaitsForAKnownType
S-8811 → …testS8811EmptyIsUnknownAndACapabilityLessSlotIsGeneric
S-8812 → WatchSensorSourceSourceTests.testS8812TheStoreSharesAndReadsActiveEnergySoTheWorkoutSavesCalories

No scenario without a test that would fail without the change.
