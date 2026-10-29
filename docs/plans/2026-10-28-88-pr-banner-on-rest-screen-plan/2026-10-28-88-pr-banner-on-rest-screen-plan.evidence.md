# Plan 88 evidence — the "New PR" banner on the rest screen

Base commit for every red proof: `1ddf5679` (as the plan states: `HEAD` when the run started).
All checks run through `.github/copilot/scripts/macos/gateway.sh`.

## Baselines

| Check | Baseline (before this plan) | After |
|---|---|---|
| `swift-test` | 1124 passed, 0 failed | 1127 passed, 0 failed (the three new S-88 tests) |
| `test` (full Flutter suite) | see below | see below |
| `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | — | 42 passed, 0 failed |
| `lint` (`flutter analyze`) | repo-wide info notices, non-zero exit (see below) | no new issues in the files touched |

## Red proofs on the base commit

### S-88-3 (source scan) — genuine assertion red

```
gateway: prove-red: 'swift-test' on HEAD with your versions of: watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalBestsWiringSourceTests.swift
gateway: swift-test (timeout 900s): swift test --package-path watch/watchos --filter WatchPersonalBestsWiringSourceTests.testS88
--- lines that look like failures (11)
   330: ...WatchPersonalBestsWiringSourceTests.swift:430: error: ... testS88_3TheRestSurfaceHostsTheBannerInsideItsTimeline] : XCTAssertTrue fa ...
   331: ...:435: error: ... XCTestTrue fa ...
   332: ...:439: XCTAssertTrue fa ...
   333: ...:444: XCTAssertTrue fa ...
   334: ...:448: XCTAssertTrue fa ...
   335: ...:452: XCTAssertTrue fa ...
   336: ...:457: XCTUnwrap failed ...
gateway: prove-red: RED AT HEAD (exit 1).
```

The first six assertions are the ones this plan's guard rests on ("the rest surface hosts the
banner inside its timeline", "… calls the announcement gate", "the capsule markup is in exactly one
file"); they fail at base because `WatchRestView.swift` hosts no banner there. Full log:
`.work/gateway/swift-test-20261028-202306-22050.log`.

The earlier class-wide proof (`--filter WatchPersonalBestsWiringSourceTests`) said
`RED AT HEAD (exit 1)` with three failures: S-87b14's label scan, S-87b22's overlay scan (both
followed the markup into the new banner file) and S-88-3. That run predates the reorder that reads
`WatchPersonalRecordBanner.swift` last, which is why the single-test proof above is the one kept.

### S-88-1 / S-88-2 (state) — new API, so the guard is a mutation

The base tree cannot compile these tests: `value of type 'WatchLoggingState' has no member
'takePersonalRecordAnnouncement'` (7 compile errors). A compile error is not an assertion red, so
mutations 1 and 2 below are the proof that the two state tests discriminate.

## Mutations (each: original line recorded, mutation shown red, original restored exactly, green again)

| # | Mutation | Observed | Restored |
|---|---|---|---|
| 1 | `takePersonalRecordAnnouncement()` always returns `true` | `testS88_1TheAnnouncementIsTakenOncePerRecordAndNeverForANonRecord` failed (second call for the same record answered true) | restored → `--filter WatchPersonalRecordBannerTests.testS88` green |
| 2 | the handed-out stamp is never remembered | `testS88_1…` failed (the second call re-announced the same record) | restored → green |
| 3 | the banner host removed from `WatchRestView` | `testS88_3TheRestSurfaceHostsTheBannerInsideItsTimeline` failed on two `XCTAssertTrue` (the rest surface carries the banner, and the `onAppear` / `onChange` announcement) | restored → `--filter testS88` green (15 executed, 0 failures) |
| 4 | `let tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in } // MUTANT` added inside `WatchRestView.body` | `testS88_3…:485: error: … XCTAssertFalse failed - S-88-3 the rest s …` (the rest surface carries no timer) | restored → `--filter testS88` green (15 executed, 0 failures) |

Mutation 4 was the only change written with a marker; `grep -rln MUTANT watch lib test` returns
nothing on the finished tree.

## Suite runs

- `swift-test` after the change: `Executed 1127 tests, with 0 failures` (log
  `.work/gateway/swift-test-20261028-202233-20586.log`).
- `swift-test --filter WatchPersonalRecordBannerTests`: 13 executed, 0 failures.
- `swift-test --filter WatchPersonalBestsWiringSourceTests`: 9 executed, 0 failures.
- `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: 42 passed.
- Full `test` run 1 (with a `prove-red` worktree being created underneath it): 5783 passed, 2
  skipped, 1 failed — `pre_release_gate_upload_destination_test.dart` S-003, "Bad state: cp/rsync
  failed: … .work/gateway/base-21784/.claudeignore: open (2) … No such file or directory". That file
  rsyncs the repository and collided with the concurrent base worktree, not with any file this plan
  touched.
- Same file alone afterwards: `+8: All tests passed!` (8 passed).
- Full `test` run 2 (nothing else running): 5783 passed, 2 skipped, 1 failed —
  `logger_feedback_controls_test.dart` "S-5115: the rest chip keeps its running look on the rolling
  list view", `Found 0 widgets with key [<'rest-overlay-chip'>]`. Alone: `+10: All tests passed!`
  (10 passed). This plan touches no Dart file, so both single failures are the suite's
  parallel-order flakiness, a different test each run, each green in isolation; no file under test
  was edited and no ratchet moved.
- `lint`: 180 issues, all `info` (pre-existing `deprecated_member_use` notices in `test/`), 0
  warnings, 0 errors, none in `lib/` and none in a file this plan changed. The exit code is non-zero
  for those pre-existing notices, as the plan's baseline describes.


## Docs (D-5)

| File | Before | After | Ceiling |
|---|---|---|---|
| `docs/state_management/watch_surface_wrist.md` | 52196 bytes | 52346 bytes | 52428 (warning band) |

The paragraph "A record logged on the wrist is announced with a banner and its own tap." was
measured at 1276 bytes before and 1426 bytes after, so the file grows by exactly 150 bytes to
52346, inside the band. `wc -c` is not reachable through the gateway in this run (see the report's
Governor actions), so the figure is the measured paragraph delta applied to the recorded 52196.

`docs/watch-app-qa-wrist-logging.md` step 35 (b) now says the banner shows on the rest screen
straight after the log and goes after about four seconds, and its held-off-device list names
`…testS88_1…` and `…testS88_3…`.

## Invariants

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty.
- No file was deleted or moved; the new banner file is the only new source file.
