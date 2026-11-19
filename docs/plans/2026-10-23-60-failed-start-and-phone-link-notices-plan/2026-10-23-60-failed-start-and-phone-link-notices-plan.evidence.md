# Evidence: 60 — failed routine start and phone-link lines

## Baselines (2026-10-23)

- `swift test` in `watch/watchos` before this plan: 832 tests, 0 failures (plan 59 built).
- `flutter analyze`: 180 issues, all `info` in `test/`, 0 errors; Dart untouched.

## Phases

| Phase | Run | What | Builder's counts |
|---|---|---|---|
| P1 | crew-builder-watch, 2.9 min, 23 requests | `WatchSyncProgress.endedWithoutAnswer`, three Start-screen labels, 11 tests (S-9001..S-9003) | `WatchSessionEngineTests` 843 tests, 0 failures |
| P2 | crew-builder-watch, 4.7 min, 30 requests | `WatchStartView` (routine line, problem line, catch, clear on revision), `ContentView` host flags and wiring, `OmniTrainWatchConnectivity` link-problem report, S-9004 (3 tests) | `WatchSessionEngineTests` 846 tests, 0 failures |
| Fix 1 | crew-builder-watch, 1.1 min, 15 requests | `.onChange(of:)` two-parameter form is watchOS 10 only; the package targets watchOS 9, so one-parameter form | found by the governor's `xcodebuild` (BUILD FAILED), not by any test |
| Fix 2 | crew-builder-watch, 2.8 min, 17 requests | tests only: the two view-wiring source tests asserted a substring (`if let phoneProblem`) and not the rendered `Text(...)` or the init assignment | 3 + 4 tests, 0 failures |
| P3 | crew-docs-keeper, 5.9 min, 25 requests | `watch_surface_wrist.md` (three paragraphs), `watch-app-setup-and-qa.md` (step 21, "What QA passed") | did not run the suite |
| Review | crew-reviewer, 6.8 min (plans 59 and 60 together) | APPROVE for both, no findings (see `.review.md`) | |

## Governor read-backs

- `swift test` (full): 846 tests, 0 failures, after Fix 1 and again after Fix 2.
- `xcodebuild` (workspace `ios/Runner.xcworkspace`, scheme "OmniTrain Watch App", watchOS Simulator 42mm, scratch derived data): BUILD FAILED after P2 (the `onChange` form), BUILD SUCCEEDED after Fix 1.
- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: 42 passed; the docs contract test alone passes after the plan 60 docs.
- Simulator (Apple Watch SE 3 40 mm, watchOS 26.4), fresh install: the Health sheet rises over the Start screen at launch; dismissing it shows, at the bottom of the scrolling Start screen, "Health access is off. Turn it on in Health on your iPhone." (below the Sync button; visible only after scrolling on the 40 mm screen). Free workout opened the picker (no exercises on a fresh simulator) and closing it cancelled the workout, as plan 57 does. Not observed on the simulator: the logging-screen lines (no seeded session), the vanished-routine line, the no-answer line, the link-unavailable line.

## Mutation pass (governor, scripted, `cmp` restore after each)

Pass 1: 18 mutants (`endedWithoutAnswer` conjuncts x3, the three label texts x3, view catch/clear/line x3, host flag/no-answer/clear/link handler/order/view argument x6, connectivity x3): 17 killed, 1 survived (`if let phoneProblem {` renamed: the guard was a substring). Fix 2 tightened the guards; pass 2, 8 mutants (renamed block, blank `Text` x3 for problem/routine/off line/logging notice, init forgets problem, init forgets access, default access `.off`): 8 killed. Total over plans 59/60: every mutant killed after the tightening.

## Not verified (owner)

- Everything visual beyond the Start-screen Health line: logging-screen lines, the vanished-routine line (needs a routine removed on the phone without a sync), the 20 s no-answer line (phone app force-quit but reachable), and the link-unavailable line (unit-tested only) — QA step 21 in the PR 2b list.
- The Start-screen Health line sits below the fold on a 40 mm screen; moving it above the routine buttons is a product call for the owner.
- `docs/watch-app-setup-and-qa.md` is 58.6 KB (about 91% of the 64 KiB ceiling; it was 83% before this series): split it before the next watch unit adds a step.
