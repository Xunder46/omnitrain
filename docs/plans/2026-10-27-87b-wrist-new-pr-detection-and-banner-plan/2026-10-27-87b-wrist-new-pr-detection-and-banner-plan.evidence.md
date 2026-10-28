# 87b evidence — planner research (2026-10-27)

Baselines carried from 87a (its evidence file): full Dart suite **5761 passed / 2 skipped**; `swift test` **1073 passed**; lint **180 pre-existing info notices**.

## (a) D-1 negative loadKg → phone toast axis

- `lib/core/services/watch_session_importer.dart:1421-1435` (`_createEntry`): exercise WITHOUT `load` capability → wire `loadKg` (incl. negative assist) goes to `extraWeightKg`, weight row = 0.0; WITH `load` → `weightKg = entry.loadKg ?? 0.0` (negative stays in the weight row).
- `lib/features/session/workout_session_screen.dart:967` toast reads `currentEntry['weight']`; `:1075` `hasAddedWeight = weight > 0` → negative weight takes the REPS path; `:1075-1113` the reps path updates `_sessionRunningBestReps` — so the phone's in-session throttle updates for assisted sets too. D-1's seeded default (loadKg <= 0 → reps axis) matches the phone; D-15 pins the matching throttle behaviour.
- The phone's bests BUILDER (`getAllTimeBests`, 87a phase 2) skips `weight != 0` on the reps axis, so assisted sets never raise a standing best — the wrist mirrors the toast's comparison, not the builder's filter.

## (b) D-11 readers of StoredWatchRecord / store protocol

- `WatchRecords.swift:686-828`: `StoredWatchRecord`, 10 cases; exhaustive switches at `recordType` :711-728, `recordId` :735, `sessionId` :750, `recordedAt` :765, `sequence` :780, `withSequence` :795, `toJson` :810, `fromJson` :819-828 (unknown type → `unknownRecordType`).
- `WatchSessionStore.swift`: `WatchStoreContents` :25-83 (per-kind arrays + `isEmpty`); protocol :90 (exactly append/readAll/pruneConfirmed/pruneSensorSamples/pruneExerciseBatches); `InMemoryWatchSessionStore` :153+, `readAll` switch :186-199, prune filters :245-251.
- `FileWatchSessionStore.swift`: `readAllLocked` :127-141, `pruneExerciseBatches` :79/:205-211, `compact` :344; append dedupes on (recordId, recordType).
- S-004 guard `WatchSessionEngineTests.swift:320-415`: `allowed` set of exactly 5 store method names :329-335; module-wide mutation-verb regex — `pruneBests` is safe ("prune" not a banned verb) but MUST be added to `allowed`.
- Dart twin `lib/watch/session/watch_records.dart:168-184`: `WatchRecord.fromJson` throws on unknown recordType, but the twin never appends or receives bests rows → no twin change (D-14).

## (c) D-4 / S-87b-8 — paths a set enters wrist state

- `WatchSessionEngine.applyMessage` :484-518: `session_snapshot` → `applySnapshot` → `storeSnapshotEntry` :958-992 (appends observation records, recordId = phone entryId) + `confirmObservations` :608; `structure_change` → session row only; `exercise_push` → slot only.
- Only `WatchLoggingState.log` :908 (→ `engine.appendObservation` :966) is the wrist's own log path; detection hooks there, so snapshot sets never reach it.

## (d) D-12 pruneConfirmed timing

- `confirmObservations` :1943 appends a `WatchConfirmationRecord`; `pruneConfirmed` :1978 drops confirmed rows — **no production caller** (grep over `watch/watchos/Sources` + `ios/`: tests only). Observations persist indefinitely, so the launch rebuild covers unreceipted sets trivially. Race (receipted + pruned before the frame arrives) stated as a known limit.

## (e) D-7 deployment target / accessibility

- `watch/watchos/Package.swift`: `platforms: [.macOS(.v13), .watchOS(.v9)]`.
- In-repo accessibility: SwiftUI modifiers only (`.accessibilityLabel`, `.accessibilityValue`, `.accessibilityAddTraits`, `.accessibilityElement(children: .combine)`); `WatchLoggingView.swift:282-298, :350, :365` carry existing labels; `.overlay` :287 is the banner site. Zero `Announcement`/`UIAccessibility` uses in sources (grep) → D-19's best-effort stance.

## (f) Phase 4 wiring file verification

- `Fixtures.swift:16-22` (`repositoryRoot`) resolves the repo root from `#filePath`; `WatchLoggedHapticTests.swift:205-212` reads `ios/OmniTrain Watch App/ContentView.swift` directly under `swift test`; ~20 source-scan test files do the same (e.g. `WatchSyncProgressWiringTests.swift` :110, :137, :167, :230, :362; `WatchMenuTests.swift:1020`; `WatchAccessibilitySourceTests.swift`). New wiring guard: `WatchPersonalBestsWiringSourceTests.swift` (S-87b-22). The app target itself needs the governor's xcodebuild.
- Permissions: `developer.flags` writes anywhere except `common.flags` denials; `crew-builder-watch.flags` explicitly allows `ios/OmniTrain Watch App/**`.

## (g) Doc sizes

- `docs/watch-app-qa-wrist-logging.md` ~336 lines (view did not truncate at 20 KB) — far under the 64 KiB ceiling and the ~52 KB split band; one QA step (35) safe. `docs/state_management/watch_surface_wrist.md` similar. Sizes inferred from view truncation (no `stat` — shell denied); implementer measures before/after; `test/docs_indexing_contract_test.dart` fails loudly.

## (h) Tests D-6/D-8 could break

- `WatchLoggedHapticTests.swift`: counts `haptics.logged` :87, :92, :107, :111, :122, :139, :142; source-scans `WristHaptics` :182-190 (`playLogged` → `.success` within 120 chars; `playNext` → `.directionUp`). Extension-default `playPersonalRecord()` keeps conformers compiling; existing count tests hold (no frame held → D-3 → logged tap); the model must call `playPersonalRecord()` INSTEAD of `playLogged()` on a PR (S-87b-21).
- `WatchSyncProgressTests.swift` :44-200 uses `noteArrival(type:)` literals; NO test asserts the exact `replyTypes` set (grep over the test tree) → D-8 breaks nothing there.
- `WatchAccessibilitySourceTests.swift:245-275`: ratchet floor 8 named files; `WatchLoggingView.swift` already named → banner modifiers cannot shrink it.
- `WatchTimerCueTests.swift:23`: scans for haptic cue mappings; a new mapping satisfies it — Phase 4 runs the full suite to confirm.

## Key line references

- Detection hook: `WatchLoggingState.swift:908 log`, `:979 metricPayload` (reps/loadKg, negative = assist), `:966` appendObservation call.
- Haptics: `WatchLoggingModel.swift:173 primaryAction`, `:206 log`, `:216 RecordingHaptics`, `:244 WatchHaptics`, `:262 playFinished` default pattern; `WatchLoggingView.swift:32 WristHaptics` (taken types: notification, stop, retry, click, success, directionUp, failure → D-18 pins `.start`).
- Holder pattern: `WatchPhonePreferences.swift:157 current`, `:196 restore`, `:206 applyPreferencesDown` (newest-wins, tie → later received).
- Prune-caller pattern: `WatchSessionStartPaths.swift:489` (`pruneExerciseBatches` after a frame settles).
- Routing: `WatchSyncOrchestrator.swift:161 receive`; spinner: `WatchSyncProgress.swift:31 replyTypes`; ContentView wiring: `:23 let preferences`, `:155` built, `:230` replyTypes clear, `:317` restore.

# Phase 1 evidence — store support (2026-10-27, developer)

## Phase 0 — red before implementation

New file `watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalBestsStoreTests.swift` (6 tests) was written first; `gateway.sh swift-test` then failed to COMPILE against the unmodified sources — the test file names `WatchBestsRecord`, `contents.bests` and `pruneBests(keepingRecordId:)`, none of which existed. `prove-red` cannot be used for this phase for the same reason: at base `d0189d6` the carried-over test file does not compile, so there is no assertion verdict to read. The brief prescribes mutations instead (below).

## Green

```
Test Suite 'WatchSessionEnginePackageTests.xctest' passed
     Executed 1079 tests, with 0 failures (0 unexpected) in 5.287 (5.388) seconds
```

Baseline was 1073 passed; 1073 + 6 new = 1079. The six new cases:

| Test | Scenario |
|---|---|
| `testS87b11AStoredBestsRowReadsBackAfterRelaunch` | S-87b-11 restore |
| `testS87b11TheSameFrameStoredTwiceIsOneRow` | S-87b-11 duplicate append |
| `testS87b11ThreeFramesLeaveTheNewestOneAfterThePrune` | S-87b-11 three frames → newest |
| `testS87b11ABestsRowAloneMakesTheStoreNotEmpty` | S-87b-11 `isEmpty` conjunct |
| `testS87b19APruneKeepsExactlyTheNamedRow` | S-87b-19 |
| `testS87b19APruneNamingAnAbsentRowDropsNothing` | S-87b-19 edge |

## Mutation proof (both restored exactly, suite green after each restore)

| Mutant | Where | Result |
|---|---|---|
| `pruneBests` returns `[]` without filtering | `FileWatchSessionStore.pruneBestsLocked` | 2 tests failed, 8 assertion failures (S-87b-11 three-frames, S-87b-19 keeps-the-row) |
| `readAllLocked` omits the `.bests` arm (no rows appended) | `FileWatchSessionStore.readAllLocked` | 4 tests failed, 7 assertion failures |

`grep MUTANT` over `watch/` after the restores: no matches. `gateway.sh swift-test` after the second restore: 1079 passed, 0 failures.

## Other checks

- S-004 (`testS004NoMutatingOperationExistsAnywhereInTheModule`) alone: passed with the `allowed` set at six names.
- `gateway.sh lint`: 180 issues found — the plan's baseline, none in the files this phase touched.
- `gateway.sh test test/docs_indexing_contract_test.dart` (the `docs/state_management/watch_sensors.md` correction): 13 passed.
- `gateway.sh git-diff --stat`: 9 files, 200 insertions, 15 deletions — proportional to the edits (no reformatting of tracked files).

# Phase 2 evidence — detection holder (2026-10-27, developer)

## Phase 0 — red before implementation

`WatchPersonalBests.swift` does not exist at base `d0189d6`, so `prove-red HEAD swift-test …` cannot compile the tests that name `WatchPersonalBests`: there is no assertion verdict to read (same situation as Phase 1). The brief prescribes mutations in that case; all six are below, each applied to the finished holder, seen RED for the reason the test guards, then restored exactly.

## Green

New file `watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalBestsTests.swift`, 21 cases:

| Test | Scenario |
|---|---|
| `testS87b1AnEqualSetIsNotARecordAndAHeavierOneIs` | S-87b-1 |
| `testS87b1TheWireFixtureCarriesTheSameEstimate` | S-87b-1 (wire fixture, bit-equal estimate) |
| `testS87b2AWristThatNeverReceivedAFrameSaysNothing` | S-87b-2 (D-3) |
| `testS87b2AHeldEmptyFrameMakesEveryFirstSetARecord` | S-87b-2 (empty frame ≠ no frame) |
| `testS87b3AnExerciseAbsentFromTheFrameIsAFirstEverRecord` | S-87b-3 |
| `testS87b4BodyweightSetsCompareReps` | S-87b-4 |
| `testS87b5TheSameSetTwiceIsOneRecordAndAHeavierOneIsTheNext` | S-87b-5 |
| `testS87b6TheWristsOwnSetSilencesItsRepeatAfterARelaunch` | S-87b-6 |
| `testS87b7OnlySetEffortsGetAVerdictOrMoveTheOwnBest` | S-87b-7 |
| `testS87b11ThreeFramesLeaveOnlyTheNewestAndARestoreReadsIt` | S-87b-11 (prune + restore) |
| `testS87b11EqualEntriesTwiceAppendOnce` | S-87b-11 (D-11 nothing-to-write) |
| `testS87b11AnOlderFrameIsUnderstoodAndDropped` | S-87b-11 (older frame) |
| `testS87b13AMalformedFrameIsRefusedWholeAndThePreviousCopyStillDecides` | S-87b-13 (invalid fixture through the validator) |
| `testS87b13AnEntryWithNoAxisIsRefusedWithoutAValidator` | S-87b-13 (no both-axes entry) |
| `testS87b15DetectionComparesKilogramsWhateverThePhoneDisplays` | S-87b-15 |
| `testS87b16AnAssistedSetWinsOnTheRepsAxis` | S-87b-16 |
| `testS87b17AReceiptedSetStillSilencesItsRepeatAfterARelaunch` | S-87b-17 |
| `testS87b18ASnapshotBroughtPhoneSetFoldsIntoTheRebuild` | S-87b-18 |
| `testS87b23ASecondIdenticalAssistedSetIsNotARecord` | S-87b-23 |
| `testABestsDownFrameReachesTheHolderThroughTheOrchestrator` | routing (`bests_down` → holder) |
| `testABestsDownFrameIsRefusedWhenTheWatchKeepsNoHolder` | routing (no holder → not handled) |

```
Test Suite 'Selected tests' passed
     Executed 21 tests, with 0 failures (0 unexpected) in 0.039 (0.044) seconds
```

## Mutation proof (each restored exactly, `grep MUTANT` clean afterwards)

| Mutant | Where | RED AT (real assertion output) |
|---|---|---|
| strict `>` → `>=` on the weight axis | `beatsStandingBest` verdict | `testS87b1AnEqualSetIsNotARecord…` "S-87b-1 100 x 5 is exactly the held 116.6667, so …"; `testS87b1TheWireFixtureCarriesTheSameEstimate`; also S-87b-11 three-frames and S-87b-17 (4 failures / 11 run) |
| own fold-in removed from `noteLogged` | `noteLogged` | S-87b-2 held-empty-frame, S-87b-4, S-87b-5, S-87b-23 (4 failures / 21 run) |
| no-frame guard dropped (`frame ?? [:]`) | `beatsStandingBest` | `testS87b2AWristThatNeverReceivedAFrameSaysNothing` "with no frame held a set gets no verdict" (1 failure / 1 run) |
| equal-entries early return skipped | `applyBestsDown` | `testS87b11EqualEntriesTwiceAppendOnce` 3 assertion failures, incl. stored ids `["bests-msg-f-3"]` vs `["bests-msg-f-1"]` |
| `pruneBests` call removed | `applyBestsDown` | `testS87b11ThreeFramesLeaveOnlyTheNewestAndARestoreReadsIt` 2 failures — three rows kept |
| restore's observation rebuild skipped (`own = [:]`) | `restore()` | S-87b-6, S-87b-17, S-87b-18 (3 failures / 21 run) |

## Suite and checks

- Full `gateway.sh swift-test` after the last restore: **Executed 1100 tests, with 0 failures (0 unexpected) in 5.524 (5.632) seconds**. Baseline 1079 + 21 new = 1100.
- `gateway.sh lint`: **180 issues found**, the plan's baseline; no Dart file touched.
- `gateway.sh test` (full Dart suite, no Dart source changed): `07:20 +5761 ~2: All tests passed!` — 5761 passed / 2 skipped, the documented baseline.
- `gateway.sh test test/docs_indexing_contract_test.dart` (plan and evidence edited): 13 passed.
- `gateway.sh git-diff --stat` (tracked): unchanged from Phase 1 at 10 files — this phase adds the untracked `WatchPersonalBests.swift` (+~440 lines) and `WatchPersonalBestsTests.swift` (+~600 lines) and 12 added lines in `WatchSyncOrchestrator.swift` (property, init parameter, one `case`). No reformatting of tracked files.
- Invariant sweep `import .*hive_workout_repository` over `lib/state`, `lib/features`, `lib/widgets`, `lib/core`: no Dart file touched this phase.

## Docs

No doc change: the holder is a watch-package internal with no route, screen or widget, and `docs/state_management/` was not given a page for the wrist's preferences holder either. Phase 4 wires it into the logging model and updates the wrist docs then.

# Phase 3 evidence — detection wired into `log`, banner state, record haptic (2026-10-27, developer)

## Phase 0 — red before implementation

The scenario tests name `personalBests:`, `lastLogWasPersonalRecord`, `personalRecordBannerUntil`, `isPersonalRecordBannerVisible(at:)` and `haptics.personalRecords`, none of which exist at base `d0189d6`: `prove-red HEAD swift-test …` cannot compile the file, so there is no assertion verdict to read (same situation as Phases 1 and 2). The brief prescribes mutations instead; all five are below, each applied to the finished code, seen RED for the reason the guard exists, then restored exactly.

## Green

New file `watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalRecordBannerTests.swift`, 11 cases:

| Test | Scenario |
|---|---|
| `testS87b9ARecordLogPlaysTheRecordTapAndNotTheLoggedOne` | S-87b-9 (record: one record tap, no logged tap) |
| `testS87b9ANonRecordLogPlaysTheLoggedTapOnly` | S-87b-9 (non-record) |
| `testS87b9ARefusedLogPlaysNeitherTap` | S-87b-9 (refused log) |
| `testS87b9AWatchWithNoHolderPlaysTheLoggedTapForABeatingSet` | S-87b-9 / D-3 (no holder) |
| `testS87b21EachLogPlaysExactlyOneTap` | S-87b-21 (two logs, two taps; verdict cleared) |
| `testS87b10TheBannerIsVisibleUntilTheWindowEnds` | S-87b-10 (visible at +3.9 s, gone at +4.0 s) |
| `testS87b10ASecondRecordRestartsTheWindow` | S-87b-10 (second record → t0+6.0 s) |
| `testS87b10ANonRecordLogLeavesTheWindowAlone` | S-87b-10 (non-record never clears) |
| `testS87b8ASnapshotSetRaisesNoBannerAndNoTap` | S-87b-8 / D-4 (snapshot path bypasses detection) |
| `testS87b7ATimedEffortNeverRaisesTheBanner` | S-87b-7 (timed effort) |
| `testS87b7AHoldNeverRaisesTheBanner` | S-87b-7 (hold) |

```
Test Suite 'WatchPersonalRecordBannerTests' passed
     Executed 11 tests, with 0 failures (0 unexpected) in 0.045 (0.047) seconds
```

`WatchLoggedHapticTests.swift` needed no line: `RecordingHaptics.logged` still counts only `playLogged()`, and every existing assertion there still holds.

## Mutation proof (each restored exactly, `grep MUTANT watch` clean afterwards)

| Mutant | Where | Verdict (real assertion output) |
|---|---|---|
| (1) `playLogged()` played after `playPersonalRecord()` on a record | `playLogCue()` | RED — `testS87b9ARecordLogPlaysTheRecordTap…` (logged 1 vs 0), `testS87b21EachLogPlaysExactlyOneTap`, `testS87b8…`; 5 failures / 11 run |
| (2) `isPersonalRecordBannerVisible` returns true whenever a window exists | `isPersonalRecordBannerVisible` | RED — `testS87b10TheBannerIsVisibleUntilTheWindowEnds` "S-87b-10 gone exactly at the window …" (`WatchPersonalRecordBannerTests.swift:302`), `testS87b10ASecondRecordRestartsTheWindow` "S-87b-10 and gone at its own end" (`:343`); 2 failures / 11 run |
| (3) a record does not overwrite an existing `personalRecordBannerUntil` | `log` | RED — `testS87b10ASecondRecordRestartsTheWindow` `("4.0") is not equal to ("6.0")` (`:334`) and "the restarted window is still up" (`:339`); 2 failures / 11 run |
| (4) `lastLogWasPersonalRecord` only ever set true, never reset | `log` | RED — `testS87b21EachLogPlaysExactlyOneTap` "the second log …" (`:267`), "it plays …" (`:268`), "S-87b-9 a non-record log clears the verdict" (`:269`); 1 failure / 11 run |
| (5) detection called for non-set kinds | `log` (`kind: WatchObservationKind.set`) | GREEN alone — see below; with the missing-`reps` default also dropped (`?? 0` → `?? 1`) it is RED on both S-87b-7 tests (`:433`–`:436`, `:454`–`:457`), 2 failures / 11 run |

Mutant (5) is not observable on its own: a timed or held effort's event carries no `reps` at all (`metricPayload` emits `reps` only for `WatchEffortKind.set`), so the holder's own `reps >= 1` guard refuses it whatever kind the state passes. The S-87b-7 tests therefore pin the joint rule — real kind **and** a real reps value — which the composite mutant above shows red; the state's kind argument alone cannot be told apart by any fixture the public surface can produce. Both halves were restored exactly.

## Suite and checks

- Full `gateway.sh swift-test` after the last restore: **Executed 1111 tests, with 0 failures (0 unexpected) in 5.447 (5.556) seconds**. Baseline 1100 + 11 new = 1111.
- `gateway.sh lint`: **180 issues found**, the plan's baseline; no Dart file touched.
- `gateway.sh git-diff --stat`: `WatchLoggingState.swift` +53/−1, `WatchLoggingModel.swift` +31/−2 — the edits this phase made, no reformatting; the remaining tracked files are Phases 1–2.
- Invariant sweep `import .*hive_workout_repository` over `lib/state`, `lib/features`, `lib/widgets`, `lib/core`: no Dart file touched this phase.

## Docs

No doc change this phase: the brief restricts the diff to the two sources, the new test file and the plan, and the wrist's haptics/banner prose belongs to Phase 4 with the view. `docs/state_management/watch_sensors.md` (Phase 1) still describes the store only.

# Phase 4 evidence — surface: banner, spoken text, spinner, app wiring (2026-10-27, developer)

## Phase 0-equivalent — every new guard proved by mutation

`WatchLoggingView.swift` (and the app target) compile only under xcodebuild, so the source scans assert the text and the mutations below stand in for a red run against HEAD: `prove-red HEAD swift-test` cannot even compile the new `WatchSpokenText.personalRecord` reference at base `d0189d6d` (same situation as Phases 1–3, see their evidence). Each mutant was applied to the finished code, seen RED for the reason the guard exists, then restored exactly.

| Mutant | Where | Verdict (real assertion output) |
|---|---|---|
| (1) remove `"bests_down"` from `replyTypes` | `WatchSyncProgress.swift` | RED — `testS87b12TheBestsReplyKeepsTheSyncRunningUntilItsOwnQuietWindow` "S-87b-12 a tenth before the bests …" (`WatchSyncProgressTests.swift:226`); 1 failure / 2 run |
| (2) remove `await personalBests.restore()` | `ContentView.swift` `restore()` | RED — `testS87b22TheRestoreSequenceRestoresTheHolderAfterTheSettings` `XCTUnwrap failed: expected non-nil …` (`WatchPersonalBestsWiringSourceTests.swift:182`) |
| (3) `playPersonalRecord` plays `.success` | `WatchLoggingView.swift` `WristHaptics` | RED — `testS87b22TheRecordCueIsTheUnusedBuiltInType` `("1475") is greater than (120)` (`:238`) and `("0") is not equal to ("1")` (`:243`); 2 failures / 1 run |
| (4) delete `.accessibilityLabel(WatchSpokenText.personalRecord)` | `WatchLoggingView.swift` banner | RED — `testS87b14TheBannerCarriesTheLabelAndOneGuardedAnnouncement` "S-87b-14 the …" (`:258`) |
| (5) `WatchSpokenText.personalRecord` = "New PR" | `WatchSpokenText.swift` | RED — `testS87b14TheRecordBannerSpeaksTheWholeSentence` `("New PR") is not equal to ("New personal record")` (`WatchSpokenTextTests.swift:52`) |

`grep MUTANT *.swift` after the last restore: no matches.

## Green

| Test | Scenario |
|---|---|
| `testS87b12TheBestsReplyKeepsTheSyncRunningUntilItsOwnQuietWindow` | S-87b-12 (active at t0+3.4, finished at t0+3.5) |
| `testS87b12AStragglingBestsReplyDoesNotReviveTheSync` | S-87b-12 (straggler after the end) |
| `testS87b14TheRecordBannerSpeaksTheWholeSentence` | S-87b-14 (the spoken text) |
| `testS87b22TheHostBuildsTheHolderBesideThePhoneSettings` | S-87b-22 |
| `testS87b22TheOrchestratorAndTheLoggingStateBothTakeTheHolder` | S-87b-22 |
| `testS87b22TheRestoreSequenceRestoresTheHolderAfterTheSettings` | S-87b-22 |
| `testS87b22TheBannerIsANonBlockingOverlayWithNoTimer` | S-87b-22 (overlay, `allowsHitTesting(false)`, no new `Timer`, count pinned at 0) |
| `testS87b22TheRecordCueIsTheUnusedBuiltInType` | S-87b-22 / D-18 (`.start` only) |
| `testS87b14TheBannerCarriesTheLabelAndOneGuardedAnnouncement` | S-87b-14 / D-19 (label, one post, `#available` first) |
| `testS87b14TheAnnouncementIsHookedToTheRecordWindow` | S-87b-14 (the `.onChange` hook and the nil guard) |

```
Test Suite 'WatchPersonalBestsWiringSourceTests' passed
     Executed 7 tests, with 0 failures (0 unexpected) in 0.018 (0.019) seconds
Test Suite 'WatchSyncProgressTests' passed
     Executed 10 tests, with 0 failures (0 unexpected) in 0.002 (0.003) seconds
Test Suite 'WatchSpokenTextTests' passed
     Executed 4 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
```

## Suite and checks

- Full `gateway.sh swift-test` after the last restore and the final comment fix: **Executed 1121 tests, with 0 failures (0 unexpected) in 5.351 (5.449) seconds**, zero warnings. Baseline 1111 + 10 new = 1121.
- S-87b-24: `--filter WatchAccessibilitySourceTests` **6 tests, 0 failures**, the eight-file ratchet among them; `--filter WatchTimerCueTests` **4 tests, 0 failures**.
- `gateway.sh lint`: **180 issues found**, the plan's baseline; no Dart file touched.
- `gateway.sh git-diff --stat`: `WatchLoggingView.swift` +55, `WatchSyncProgress.swift` +11/−5, `WatchSpokenText.swift` +5, `ContentView.swift` +25/−4, `WatchSpokenTextTests.swift` +12, `WatchSyncProgressTests.swift` +47 — the edits this phase made, no reformatting; the remaining tracked files are Phases 1–3.
- Invariant sweep `import .*hive_workout_repository` over `lib/state`, `lib/features`, `lib/widgets`, `lib/core`: no matches (no Dart file touched).
- Not run here: the watch app build (`xcodebuild`) — `swift test` cannot compile `ios/OmniTrain Watch App`. Governor action.

## Docs

No doc change this phase: Phase 5 owns the wrist docs (`watch_surface_wrist.md`, the QA walkthrough, `services_and_utils.md`), and the brief restricts this diff to the named sources and tests. No `docs/` file changed, so `test/docs_indexing_contract_test.dart` has nothing new to index.

## Phase 5 — Docs and QA

Benchmark before the phase: `docs/state_management/watch_surface_wrist.md` 49,159 bytes; `docs/watch-app-qa-wrist-logging.md` 23,337 bytes; `docs/state_management/watch_reference_data.md` and `services_and_utils.md` well clear of the band (`docs_indexing_contract_test.dart`, `_maxDocBytes` 65,536 with the 80 % warning band at 52,428).

| File | What changed | Verified by |
|---|---|---|
| `docs/state_management/watch_surface_wrist.md` | `bests_down` named in the reply-type paragraph and in the `syncNoAnswer` clearing sentence; two paragraphs on the logging surface (the banner and its own tap; the phone's toast rule, mirrored) | `WatchSyncProgressTests.testS87b12TheBestsReplyKeepsTheSyncRunningUntilItsOwnQuietWindow`, `…testS87b12AStragglingBestsReplyDoesNotReviveTheSync`; `WatchPersonalRecordBannerTests.testS87b9ARecordLogPlaysTheRecordTapAndNotTheLoggedOne`, `…testS87b10TheBannerIsVisibleUntilTheWindowEnds`, `…testS87b10ASecondRecordRestartsTheWindow`; `WatchSpokenTextTests.testS87b14TheRecordBannerSpeaksTheWholeSentence`; `WatchPersonalBestsWiringSourceTests.testS87b22TheBannerIsANonBlockingOverlayWithNoTimer`; `WatchPersonalBestsTests.testS87b1AnEqualSetIsNotARecordAndAHeavierOneIs`, `…testS87b2AWristThatNeverReceivedAFrameSaysNothing`, `…testS87b5TheSameSetTwiceIsOneRecordAndAHeavierOneIsTheNext`, `…testS87b7OnlySetEffortsGetAVerdictOrMoveTheOwnBest`, `…testS87b16AnAssistedSetWinsOnTheRepsAxis` |
| `docs/state_management/watch_reference_data.md` | new `### The wrist keeps one copy` beside the bests paragraph: one copy, the older frame dropped, a same-numbers frame writing nothing, the old copy dropped after the new one is stored, ≤300 plus one own best per logged exercise, a malformed frame refused whole, never-received silence | `WatchPersonalBestsTests.testS87b11ThreeFramesLeaveOnlyTheNewestAndARestoreReadsIt`, `…testS87b11EqualEntriesTwiceAppendOnce`, `…testS87b11AnOlderFrameIsUnderstoodAndDropped`, `…testS87b13AMalformedFrameIsRefusedWholeAndThePreviousCopyStillDecides`; `WatchPersonalBestsStoreTests.testS87b19APruneKeepsExactlyTheNamedRow`, `…testS87b11AStoredBestsRowReadsBackAfterRelaunch` |
| `docs/state_management/services_and_utils.md` | `StatsProgressService`'s bests paragraph names `getAllTimeBests()` beside the two per-exercise methods (87a review minor) | `test/stats_bests_builder_test.dart`, group `StatsProgressService.getAllTimeBests`, `S-87a-5 parity: every exercise equals getAllTimeBestE1RM and getAllTimeBestReps` |
| `docs/watch-app-qa-wrist-logging.md` | QA step 35 (banner, the wrist's own repeat, the second record restarting a phone-logged set, the no-frame wrist) and the closing gaps paragraph gained the two 87b limits | `WatchPersonalRecordBannerTests.testS87b8ASnapshotSetRaisesNoBannerAndNoTap`, `WatchPersonalBestsTests.testS87b18ASnapshotBroughtPhoneSetFoldsIntoTheRebuild`, `…testS87b17AReceiptedSetStillSilencesItsRepeatAfterARelaunch` |
| `docs/watch_session_capture.md` (35,060 bytes before) | new paragraph in "The wrist half": the two limits of the wrist's record banner stated plainly, with the rule itself left in `watch_surface_wrist.md` (the brief's rule: text that would push the wrist doc past its band goes here, with a one-line pointer back) | the same three Swift tests as the row above |

Size, observed rather than asserted: the first draft of `watch_surface_wrist.md` measured **53,185 bytes (81 % of ceiling)** and turned the warning-band test red — exactly the failure the plan predicted for the tightest file. The banner and rule paragraphs were tightened, and the plain statement of the two limits went to `docs/watch_session_capture.md` with a one-line pointer from the wrist doc, which brought `watch_surface_wrist.md` back under the band; the same test is green in the run below.

```
00:00 +13: All tests passed!
```
`gateway.sh test test/docs_indexing_contract_test.dart` — 13 passed, 0 failed (the band test among them; the first run of this phase was `+12 -1` on it with the 53,185-byte reading above).

```
00:00 +29: All tests passed!
```
`gateway.sh test test/ui_standards_contract_test.dart` — 29 passed, 0 failed; no allowlist entry added or changed, no ratchet touched (this phase changed docs, plans and no Dart source).

`gateway.sh lint`: **180 issues found**, the plan's baseline, nothing in a file this phase touched (docs and Markdown only).

Full `gateway.sh test` after all edits: **07:13 +5761 ~2: All tests passed!** — 5761 passed, 2 skipped, exactly the plan's baseline (no Dart source or test file changed in this phase).

Invariant sweep `import .*hive_workout_repository` over `lib/state`, `lib/features`, `lib/widgets`, `lib/core`: no matches.

Residue sweep (item 6):

- Doc copies of `replyTypes`: `docs/state_management/watch_surface_wrist.md:257` (now names the four types including `bests_down`) and `:296` (generic "a type in `replyTypes`"). No third copy; no doc sentence says the wrist ignores `bests_down`, and the only surviving "a wrist that does not know the type ignores it" prose is 87a's acceptance record of its landing-time property (`2026-10-26-87a-…-plan.md:13`, `:23`, `:70`) and the index row's ordering note — history, not a live claim.
- No store or switch is missing the case: `bests_down` is read in `WatchSyncOrchestrator.swift` (`applyBestsDown`) and gated in `WatchSyncProgressCopy.replyTypes`, both exercised by the green suites above.

`git-diff --stat` for this phase: the four docs (+48, +19, +12, +33 lines), the 87b plan, the 87a plan (+1 status line) and the series index (−21/+ … rewrite). No source or test file touched.


## Fix 1 — the watch app did not compile (D-19)

The governor's `xcodebuild` of the "OmniTrain Watch App" scheme for the watchOS Simulator failed where `swift test` cannot reach (`#if os(watchOS)` view body): `WatchLoggingView.swift:210:13: error: no exact matches in call to initializer — AccessibilityNotification.Announcement(Text(WatchSpokenText.personalRecord))`, because `Announcement` takes an `AttributedString` or a `String`, not a `Text`. Changed that one call to `AccessibilityNotification.Announcement(WatchSpokenText.personalRecord).post()`, keeping the `#available(watchOS 10.0, *)` guard. No test pinned `Announcement(Text(` (`WatchPersonalBestsWiringSourceTests.swift:272,287` match only `AccessibilityNotification.Announcement(`), so no test changed. `gateway.sh swift-test` after the fix: **Executed 1121 tests, with 0 failures (0 unexpected) in 5.252 (5.355) seconds** — the baseline above. The governor re-runs `xcodebuild` to confirm the app target builds.

# Review fix 2 — findings 1–4 (2026-10-27, developer)

## Finding 1 — the snapshot mutant, replaced by a structural guard

The plan's mutation "run detection on snapshot-applied sets (S-87b-8)" cannot be built: `WatchSessionEngine.storeSnapshotEntry` takes no `WatchPersonalBests`, so a snapshot path has no call to add. The guarantee is instead that `noteLogged(` has exactly one caller, `WatchLoggingState.log`. New guard in `WatchPersonalBestsWiringSourceTests.swift` — `testS87b8NoteLoggedIsCalledFromTheLoggingStateAlone` — scans every `.swift` file under `watch/watchos/Sources/WatchSessionEngine/` and `ios/OmniTrain Watch App/`, comment-stripped, and asserts zero occurrences outside `WatchPersonalBests.swift`/`WatchLoggingState.swift`, one in `WatchLoggingState.swift`, and the holder's single own declaration.

Mutation (duplicate the `noteLogged` call in `WatchLoggingState.log`, `// MUTANT` marker), then filtered run:

```
Building for debugging...
Test Case '-[...WatchPersonalBestsWiringSourceTests testS87b8NoteLoggedIsCalledFromTheLoggingStateAlone]' started.
WatchPersonalBestsWiringSourceTests.swift:377: error: ... : XCTAssertEqual failed: ("2") is not equal to ...
Test Case '... testS87b8NoteLoggedIsCalledFromTheLoggingStateAlone]' failed (1.935 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 1.935 (1.935) seconds
Test Suite 'Selected tests' failed ...
[gateway exit 1]
```

RED for the reason the guard exists: the logging state asked the holder twice. Restore: the exact original statement, no marker left (`grep -rn MUTANT watch ios` → no matches; the restored `log` region read back line for line). Green runs: the class before the mutation (`Executed 8 tests, with 0 failures`) and the full suite after the restore, below.

## Findings 2–4 — record only

- Finding 2: `docs/state_management/watch_reference_data.md` "The wrist keeps one copy" now names `WatchSessionStore.pruneBests(keepingRecordId:)`, which the holder calls on its store — the method the code has (`WatchSessionStore.swift:130`, called from `WatchPersonalBests.swift:216`). Wording only.
- Finding 3: the plan's "Files Affected" gained `WatchRoutineRecords.swift`, the three store test doubles (`WatchEffortRatingTests`, `WatchNutritionQuickLogTests`, `WatchSensorRecordingTests`), `WatchSpokenTextTests`, `WatchSyncProgressTests`, `docs/state_management/watch_sensors.md`, `docs/state_management/watch_reference_data.md` and the 87a plan header. Ledger, scenarios and phases untouched.
- Finding 4: one line under the plan's Open questions — two records at one clock instant share one banner end time, so the second announcement is skipped; revisit only with 87c.

## Checks

- `gateway.sh swift-test` (full): **Executed 1122 tests, with 0 failures (0 unexpected) in 6.459 (6.590) seconds** — 1121 at base plus the one new structural guard, green after the exact restore (`WatchPersonalBestsWiringSourceTests` alone: `Executed 8 tests, with 0 failures`). Log: `.work/gateway/swift-test-20261027-221625-39486.log`.
- `gateway.sh test test/docs_indexing_contract_test.dart`: **13 passed** (`00:00 +13: All tests passed!`) — the corrected sentence stays inside the ceiling and every link resolves.
- `gateway.sh test` (full Dart suite, because a doc changed): **5761 passed / 2 skipped, All tests passed** at `07:11` — the plan's baseline holds. Log: `.work/gateway/test-20261027-221652-40951.log`.
- `gateway.sh lint`: **180 issues found** — the plan's baseline, none new. Log: `.work/gateway/lint-20261027-221639-40166.log`.
- No Dart source touched, so the `import .*hive_workout_repository` invariant is unaffected (grep returns nothing).
- Files this fix touched: `WatchPersonalBestsWiringSourceTests.swift` (header line + the new guard and two helpers), `docs/state_management/watch_reference_data.md` (the one method name), the plan (Files Affected, one Progress line, A-20, Open question 9) and this evidence file. `WatchLoggingState.swift` carries only the feature's own lines after the restore; `grep -rn MUTANT watch ios` → no matches.

