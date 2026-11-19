# Evidence — plan 96 (watch water follow-up, PR 94c)

Implementers write baselines, suite outputs, red→green tables, mutation records and doc sizes here, one section per phase. The plan keeps one-line Progress items only.

## Phase 1

Run 2026-11-01 by @developer (Claude Code). Predicted files were clean (`git status`) before the first edit.

### Baseline
- `swift test --package-path watch/watchos` (with-timeout 900): `Executed 1181 tests, with 0 failures (0 unexpected)`.

### Red run (tests first, before the implementation)
A compiling skeleton was added first (`WatchWaterSnapshot`, the D-45 seams, `snapshot`/`model.snapshot` built from the OLD multi-pass accessors, model accessors and bar untouched), so the red is behavioural, not a compile error.
- `swift test`: `Executed 1186 tests, with 36 failures (0 unexpected)`. All 36 in Phase 1 tests:
  - S-94c-1: `reads` 5/1/1/2/5 (want 1), `parses` 14620/2924/2924/5848/14620 (want ≤ 12); values (2, true, true, "2 glasses") already equal.
  - S-94c-2: every zone `reads` 5, `parses` 1545 (want 1, ≤ 9/4/9/4/9); every glasses value already equal.
  - S-94c-3: `reads` 4, `parses` 13680 (want 1, ≤ 508). S-94c-4: `reads` 5.
  - S-94c-5: `model.snapshot` 0×, first line `HStack {`, four `model.<accessor>` reads, four `var` accessors on the model.
  - S-94b-22/24 (needles moved to `snapshot.`): 5 failures on the old bar.

### Green
- `swift test`: `Executed 1186 tests, with 0 failures (0 unexpected)` = baseline 1181 + 5 new (4 in `WatchWaterSnapshotTests`, S-94c-5). S-94b-3..16 unedited (the `WatchWaterStateTests` diff touches only S-94b-21).
- `gateway.sh swift-test`: `Executed 1186 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-232016-63328.log`).
- `flutter test test/watch_logging_surfaces_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: `+87: All tests passed!`
- Hive import grep: empty (exit 1).
- Watch target: `xcodebuild build -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator -configuration Debug SYMROOT/OBJROOT=<fresh scratch dir> CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`; log shows `SwiftCompile` of `WatchNutritionView.swift` and `WatchWater.swift` (arm64 and x86_64); no warning in either file. No simulator booted, nothing installed.

### Mutations (hand edit from a byte copy, run, restore, `cmp` identical; never `git stash`)
| # | Scenario | Original line | Mutant | Result | Restored |
|---|---|---|---|---|---|
| M1 | S-94c-1 no candidate filter | `if let candidates, !candidates.contains(record.sessionId) { return nil }` (WatchWater.swift) | `_ = candidates` | red, 10 failures: S-94c-1 parses 2924 > 12 (×4), S-94c-2 parses 309 (×5), S-94c-3 3420 > 508 | cmp identical |
| M2 | S-94c-1 separate passes | `public var canRemove: Bool { snapshot.canRemove }` | `{ canAdd && glasses > 0 }` | red: canRemove reads 2 ≠ 1, parses 24 > 12 | cmp identical |
| M3 | S-94c-5 second read | `.disabled(!snapshot.canAdd)` (bar) | `.disabled(!model.snapshot.canAdd)` | red: `model.snapshot` 2 ≠ 1 (and S-94b-24 needle) | cmp identical |
| M4 | S-94c-5 `model.glasses` read | `.accessibilityValue(snapshot.spokenCount)` | `.accessibilityValue(WatchWaterCopy.spokenCount(model.glasses))` | red: "reads model.glasses" (and S-94b-24 needle) | cmp identical |
| M5 | S-94b-18a | `guard isActive(at: now), WatchSyncProgressCopy.replyTypes.contains(type) else { return }` (WatchSyncProgress.swift) | guard without `isActive(at: now),` | red: `isActive(t0+5)` and `isActive(t0+6)` true | cmp identical (`git status` clean for the file) |
| M6 | S-94c-6 | `public static let countLabel = "Water"` | `"Water, try to drink"` | red: `…/WatchWater.swift carries banned framing "try to"`; after restore `+1: All tests passed!` | cmp identical |
| M6b | S-94c-6 missing file | `'WatchWater.swift',` (Dart list) | `'WatchWaterMissing.swift',` | red: `PathNotFoundException` | cmp identical |

### Footprint
`git diff --numstat` (+/−): WatchWater.swift 100/29, WatchNutritionView.swift 7/5, WatchWaterBarSourceTests 59/6, WatchWaterStateTests 9/9, WatchWaterSyncTests 6/4, watch_logging_surfaces_test.dart 2/0; new WatchWaterSnapshotTests.swift 341 lines. No other file left changed (M5's temporary edit of WatchSyncProgress.swift restored byte-identical).

## Phase 2

Run 2026-11-01 by @developer (Claude Code). The ten tracked Phase 2 predicted files had no diff before the first edit (`git diff --stat` empty); Phase 1's `WatchWater.swift`, `WatchWaterBarSourceTests.swift` and `WatchWaterSnapshotTests.swift` were built on. Byte copies of all 13 predicted files were taken first.

### Baseline
- `swift test --package-path watch/watchos`: `Executed 1186 tests, with 0 failures (0 unexpected)` (Phase 1's close).

### Red run (tests first, before the implementation)
Tests written first: `WatchWaterPruneTests.swift` (new: S-94c-10 in memory, on file, the retention margin; S-94c-11; S-94c-12), S-94b-25 → S-94b-25a, S-004's allowed set + `pruneWaterTaps`, the forward in the four test stores. A compiling skeleton followed: the protocol requirement, both stores' `pruneWaterTaps` returning `[]` (drop nothing), the engine delegating, `confirmedTapRetention`; `restore()` unchanged.
- `swift test`: `Executed 1191 tests, with 11 failures (0 unexpected)`, all in Phase 2 tests:
  - S-94c-10 in memory (2) and on file (3): `waterLog`, the store and the file still hold w-1..w-8 (want w-3..w-8). Red on BOTH stores.
  - S-94c-11 (3): after the first launch w-1..w-8 remain; (c) drops nothing.
  - S-94b-25a (3): no `pruneWaterTaps(` caller (0 ≠ 1), none in `WatchWater.swift`, none inside `restore()`.
- Green before the implementation by design: S-94c-12 (asserts that a zone change drops nothing and counts per D-25, already true) and the retention-margin test (the constant is part of the skeleton; M11 shows it bites).

### Green
- `swift test`: `Executed 1191 tests, with 0 failures (0 unexpected)` = 1186 + 5 new (3 × S-94c-10, S-94c-11, S-94c-12; S-94b-25a replaces S-94b-25). No warning in any touched file.
- `gateway.sh swift-test`: `Executed 1191 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-233033-67792.log`).
- Passed and unedited: `testS005UnconfirmedEntriesAreNeverPruned`, `testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing`, `testS94b4ThePruneTouchesNoOtherKindOfRow`, S-94b-3..16 (`WatchWaterStoreTests`, `WatchWaterStateTests`, `WatchWaterSyncTests`; the last two carry only Phase 1's diff). `testS004…` passes with the allowed set + `pruneWaterTaps`.
- `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart test/watch_logging_surfaces_test.dart`: `+87: All tests passed!` (log `.work/gateway/test-20261101-233053-68208.log`).
- Hive import grep: empty (exit 1).
- Full `flutter test` (900 s cap), run once each at the end, 2026-11-01 ~23:30 EST:
  - local time (America/New_York): `+6003 ~2 -21: Some tests failed.` All 21 are wall-clock day tests that take `now − 24 h` as "yesterday" or count days back from now: on 2026-11-01 (DST end, a 25 h day) after 23:00 local that instant is still today. Files: `utils_test` (3), `state_test` (2, incl. A-8), `nutrition_test` (1), `edge_case_test` (1, streakDays), `instrument_list_service_test` (2), `instrument_list_screen_test` (8), `fuel_row_screen_test` (4). Phase 2 changes no Dart file (Swift and three docs only).
  - `TZ=UTC`: `+6024 ~2: All tests passed!` (6003 + 21 = 6024: the same tests, all green).
  - `test/delete_focused_timer_test.dart` did not fail in either run.
- Watch target build: not run. No watchOS-only file changed in this phase (`WatchNutritionView.swift` untouched since Phase 1); every touched source compiles under `swift test`.

### Mutations (hand edit from a byte copy, `swift test --filter "WatchWaterPruneTests|WatchWaterBarSourceTests|WatchWaterStoreTests|WatchSessionEngineTests.testS00"`, restore, `cmp` identical; never `git stash`)
| # | Scenario | Original line | Mutant | Result | Restored |
|---|---|---|---|---|---|
| M7 | S-94c-10 unconfirmed dropped | `observation.confirmedAt != nil,` (`confirmedWaterTapIds`, WatchSessionStore.swift) | line deleted | red, 12 failures: both stores keep [w-3, w-4, w-7, w-8], unconfirmed [w-8]; S-94c-11 pending [msg-w-8] | cmp identical |
| M8 | S-94c-10 `<=` | `loggedAt < cutoff` | `loggedAt <= cutoff` | red, 6 failures: w-3 dropped on both stores and in S-94c-11 | cmp identical |
| M9 | S-94c-10 kind ignored | `guard observation.kind == WatchObservationKind.waterGlass,` | `guard true,` | red, 4 failures: w-9 and s-1 dropped, both stores | cmp identical |
| M10 | S-94c-10 engine memory not trimmed | `trimPrunedObservations(pruned)` in engine `pruneWaterTaps` | line deleted | red, 3 failures: w-1, w-2 still in `engine.waterLog` (in memory, on file, S-94c-11 (c)) | cmp identical |
| M11 | S-94c-10 retention 24 h | `confirmedTapRetention: TimeInterval = 72 * 3600` | `24 * 3600` | red, 7 failures: margin 86400 < 176400; w-3 dropped on both stores | cmp identical |
| M12 | S-94c-11 compact when nothing drops | `guard !dropped.isEmpty else { return [] }` (4th, `pruneWaterTapsLocked`) | line deleted | red: (b) file 3128 ≠ 3146 bytes (torn tail rewritten) | cmp identical |
| M13 | S-94b-25a second caller | `_ = await store.pruneWater(keepingRecordId: row.recordId)` (`applyWaterDown`) | + `_ = await engine.pruneWaterTaps(loggedBefore: clock())` | red, 14 failures: S-94b-25a 2 ≠ 1 callers (plus S-94c-10/11/12 counts) | cmp identical |

Fixture note: S-94c-10's set s-1 is logged at 2026-10-20T08:00:00Z (the scenario gives no instant) so M9 drops it as well as the food; the file-store launch uses a fresh `FileWatchSessionStore` over the same directory (a real relaunch).

### Docs (D-47)
| Doc | Before | After | Budget |
|---|---|---|---|
| `docs/state_management/watch_reference_data.md` | 22,557 | 22,911 (+354) | ≤ +450 |
| `docs/state_management/watch_sensors.md` | 31,559 | 31,751 (+192) | ≤ +300 |
| `docs/state_management/watch_surface.md` | 52,167 | 52,147 (−20) | ≤ 0 |

- Residue: `grep -rn "TapsAreNeverPruned\|five ways\|never pruned — the count" watch/watchos/Sources watch/watchos/Tests "ios/OmniTrain Watch App" docs --exclude-dir=plans --exclude-dir=history --exclude-dir=.build` → no hits (exit 1).
- `D-37` (word-bounded `D-37([^0-9]|$)`, same paths) → 2 hits, both in `WatchWaterBarSourceTests.swift` and both "D-43 (supersedes … D-37)". The unbounded grep also lists `D-3704`/`D-3705`/`D-3709` (accent decisions), unrelated.

### Footprint
Lines +/− against the pre-phase copies: WatchSessionStore.swift 44/4, FileWatchSessionStore.swift 34/0, WatchSessionEngine.swift 17/2, WatchWater.swift 20/4, WatchSessionEngineTests 7/3, WatchWaterBarSourceTests 45/16, WatchNutritionQuickLogTests/WatchEffortRatingTests/WatchSensorRecordingTests/WatchWaterSnapshotTests 4/0 each, three docs 8/3, 4/1, 2/3; new WatchWaterPruneTests.swift 320 lines. No file outside the Predicted Files touched.
