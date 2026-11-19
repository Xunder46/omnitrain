# Plan 171 — Discard Workout on the watch: evidence

Developer run, 2026-11-14. Swift-only; no Dart file touched.

## Baseline

- `swift test` before the change: 1456 tests, 0 failures (plan's recorded baseline).
- `flutter analyze` baseline: unchanged by this run (no Dart file touched).

## Red at HEAD — why it cannot be an assertion failure

`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --filter WatchMenuDiscardTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift`

Verdict: **compile failure at HEAD**, not RED AT — the tests name symbols this
change introduces, so the HEAD tree cannot build them. Paste:

```
error: type 'WatchMenuCopy' has no member 'discardLabel'
error: type 'WatchMenuCopy' has no member 'discardConfirmTitle'
error: type 'WatchMenuCopy' has no member 'discardConfirmBody'
error: type 'WatchMenuCopy' has no member 'discardConfirmCancel'
error: type 'WatchMenuCopy' has no member 'discardConfirmDiscard'
error: value of type 'WatchMenuState' has no member 'discard'
```

Per the standing rules, each guard was then proved by mutation (below), which
shows the failing assertion and the reason it guards.

## Mutation proofs (original → mutant → assertion)

Each step: record the original line, apply the mutant, run the filtered test,
restore the EXACT original, re-run green (`WatchMenuDiscardTests` 13/13 passed).

| # | File / original line | Mutant | Failing assertion |
|---|---|---|---|
| M1 | `WatchMenu.swift`: `return await engine.abandonSession()` | `return engine.session` | `S-17102 a discard hands back the ended record` / `("Optional("active")") is not equal to ("Optional("abandoned")")`, plus S-17103, S-17104 (`the rest is stopped`), S-17108 (`endSavings [] != [false]`), S-17109 |
| M2 | `WatchMenu.swift`: `guard hasLoggedEfforts else { await discard(); return }` | guard removed, `await rating.end()` alone | S-17109 `("Optional("completed")") is not equal to ("Optional("abandoned")")` and `("[true]") is not equal to ("[false]")` |
| M3 | `WatchMenu.swift`: `engine.entries.contains { WatchObservationKind.efforts.contains($0.kind) }` | `!engine.entries.isEmpty` | S-17109 `XCTAssertFalse failed - S-17109 water and food are not an effort`, then `completed != abandoned` |
| M4 | `WatchMenuView.swift` body: `finishRow` then `discardRow` | the two swapped | S-17101 `("119") is not greater than ("121") - S-17101 Discard is below End Session` |
| M5 | `WatchMenuView.swift` `discardRow`: `Button(WatchMenuCopy.discardLabel) { confirmingDiscard = true }` | the discard `Task` also placed in the row's action | S-17102 `("2") is not equal to ("1") - S-17102 the model's discard runs once` |
| M6 | `WatchMenuView.swift` `finishRow`: `if state.hasLoggedEfforts { confirmingFinish = true } else { confirmingDiscard = true }` | both flags set in the non-empty branch | S-17109 `("3") is not greater than ("4") - S-17109 and an empty one asks Discard instead` |
| M7 | `ContentView.swift` `onDiscard`: `{ isPresented… = false; host.noteSurfaceChange() }` | `noteSurfaceChange()` dropped | `testTheShellPassesTheDiscardClosure` `XCTAssertTrue failed - and tells the host the surface changed` |
| M8 | `WatchMenuView.swift`: `Button(WatchMenuCopy.discardConfirmDiscard, role: .destructive) {` | `role: .destructive` dropped | S-17112 `XCTAssertTrue failed - S-17112 Discard reads its word and is destructive` |

## Green runs

- `swift-test --filter WatchMenuDiscardTests`: **13 tests, 0 failures**.
- `swift-test --filter testS17112TheDiscardRowAndItsConfirmationSpeak`: 1 passed.
- Full `swift-test`: **1470 tests, 0 failures** in 25.9 s (baseline 1456 + 14 new:
  13 in `WatchMenuDiscardTests`, 1 in `WatchAccessibilitySourceTests`). Re-run
  after the shell-scan test was renamed to `testTheShellPassesTheDiscardClosure`
  (it carries no scenario id — the wiring is Phase 2 item 5, S-17115 is the docs
  scenario): `WatchMenuDiscardTests` 13 tests, 0 failures.
- `test test/docs_indexing_contract_test.dart`: **13 tests, all passed** after the
  two doc edits (ceiling, warning band, links, reachability).
- Full `test` (flutter, 900 s): **7648 passed, 4 skipped, 5 failed**. None of the
  five can come from this run (it changes no Dart file, and the Swift package is
  not compiled by `flutter test`):
  - 4 in `test/pre_release_gate_*_artifact_test.dart` — §11q/§11r inspect an AAB
    (`build/app/outputs/bundle/release`) and an IPA, which this host has no
    release build for; they fail for the absent artifact, not for a code change.
  - 1 in `test/watch_session_import_test.dart` (`S-17406 A a merge's start
    correction is noted`) — the concurrent plan-174 run's in-flight Dart work in
    `lib/core/services/watch_session_importer.dart` / `lib/state/watch/*`.
- `lint` (flutter analyze): **181 issues**, all pre-existing `info`
  deprecations/warnings in `test/`; Swift is outside `flutter analyze` and no
  Dart file is touched, so the count is unchanged by this run.

## Scenario → test map

| Scenario | Test |
|---|---|
| S-17101 | `testS17101TheDiscardRowIsTheMenusLastRow` |
| S-17102 | `testS17102DiscardAbandonsAtTheWristsInstantAndTellsThePhone`, `testS17102TheViewDiscardsOnlyFromTheAlertsDiscardButton` |
| S-17103 | `testS17103DiscardIsReachableMidSet` |
| S-17104 | `testS17104DiscardDuringARestStopsTheRest` |
| S-17105 | `testS17105ADiscardOwesNoRatingPrompt` |
| S-17106 | phone half — plan 174 / the Dart run (not this one) |
| S-17107 | `testS17107TheFirstEndingIsFinalForDiscard` |
| S-17108 | `testS17108TheDiscardedRecordEndsThePlatformWorkoutUnsaved` |
| S-17109 | `testS17109AnEmptyEndBehavesAsADiscard`, `testS17109TheEmptyEndRaisesTheDiscardAlert` |
| S-17110 | `testS17110DiscardKeepsTheLoggedEntriesAndShowsNoSummary` |
| S-17111 | `testS17111DiscardLeavesWaterAndFoodUntouched` |
| S-17112 | `WatchAccessibilitySourceTests.testS17112TheDiscardRowAndItsConfirmationSpeak` |
| S-17113 | covered by the untouched full `swift test` run (replay + soak green, no corpus edit) |
| S-17115 (docs) | `test/docs_indexing_contract_test.dart` 13 passed; both docs name this run's tests |
| Phase 2 item 5 (no S-id) | `testTheShellPassesTheDiscardClosure` |

## Footprint

`git-diff --stat` for this run's files (the working tree also carries the
concurrent plan-174 Dart run's changes — `lib/core/services/watch_session_importer.dart`,
`lib/state/watch/*`, `test/watch_session_*`, `test/diagnostics_wiring_source_test.dart`
and `docs/state_management/watch_diagnostics.md` — which are not this run's):

- `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` +58/−13
- `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` +64/−8
- `ios/OmniTrain Watch App/ContentView.swift` +4
- `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` +489
- `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` +32
- `docs/state_management/watch_surface_wrist_logging.md` +32/−2
- `docs/watch-app-qa-wrist-logging.md` +28
- `docs/plans/2026-11-14-171-watch-discard-workout-plan/*.md` +22 (plan) plus this evidence file (new)

Second full `swift-test` after the test rename: **1470 tests, 0 failures**
(26.6 s). No mutation is left applied (the same run is green).

