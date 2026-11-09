# Evidence — plan 46b (swipe between exercises on the wrist logging screen)

## Swift package full run

- Re-verified by the docs keeper this run: `swift test --package-path watch/watchos` — **Executed 669 tests, with 0 failures (0 unexpected)**.

## Governor mutation pass

- Governor-reported: **10 of 10 mutants red**. Governor-reported, not re-verified by the docs keeper.

## Watch target build and simulator

- Governor-reported: the watch target builds with `xcodebuild`; on the Apple Watch SE 3 (40 mm) simulator the logging screen shows the counter "1/3" beside the exercise name with Log fully visible. Not re-verified by the docs keeper.
- NOT verified on any simulator: an actual swipe, the preview card, the locked notice and the haptic — the Simulator could not be driven. Owner checks on a real watch (the plan's Owner checks, and QA steps 18–19 in `docs/watch-app-setup-and-qa.md`).

## Docs

- `docs/state_management/watch_surface_wrist.md`: new subsection "The logging screen pages the session's exercises" citing `WatchPagerModelTests.swift` (S-6601..S-6608) and `WatchPagerSourceTests.swift` (S-6610..S-6612). All named symbols and tests grepped in the sources this run.
- `docs/watch-app-setup-and-qa.md`: two on-device steps added to the wrist logging walkthrough — step 18 (swipe left: the next exercise becomes current, the counter changes, the phone does not move) and step 19 (a swipe during a timed effort: failure tap + notice, no change; the Crown unchanged).
- `flutter test test/docs_indexing_contract_test.dart`: run once after the edits — **+13, all passed** (count pasted in `.work/crew/2026-10-20-46b/report-docs.md`).

## Governor re-runs

- Swift package full run: Executed 669 tests, 0 failures. Full `flutter test`: +5323 ~2, all passed (two earlier full runs showed S-144 and S-5115 failing; both pass alone and in the green runs; Dart code untouched by 46b/46c).
- Mutations: 10 of 10 red (model: range guard, same-index arm, lock arm, notice length, notice boundary, pager shown while locked, label for one exercise, index ignoring the engine; views: dots returning, a Crown/focus token in the pager).
- Simulator: counter 1/3 beside the name with Log visible; a session whose current exercise is the third (a hold) mounts on its own live page showing 3/3.
