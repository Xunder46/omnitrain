# Evidence — 2026-10-06-15e watch-session-sync PR 4a (Phases 1–3)

Every number below is observed output from a gateway check, not inference.

## Baselines

| Check | Baseline | After Phase 1 |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 275 passing / 0 failing | **284 passing / 0 failing** (9 new cases in `WatchFileStoreTests`) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors | **196 issues / 0 errors** (unchanged; no Dart file touched) |

`lint` exits non-zero on the repo's pre-existing info notices; the count is identical to the baseline
and none of the notices names a file this phase touched.

## Footprint

`.github/copilot/scripts/macos/gateway.sh git-status`:

```
?? watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift
?? watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift
```

Two new files, both named in the plan's Predicted Files. No existing file is modified — no Dart file,
no shell file, no doc, no existing Swift source, and no test file.

## S-004 (unchanged test, extended reach)

`testS004NoMutatingOperationExistsAnywhereInTheModule` passed in the green run
(`.work/gateway/swift-test-20261006-123850-70556.log`). It walks `Sources/WatchSessionEngine` itself,
so it picked up the new `FileWatchSessionStore.swift` with no edit to the test: the file's only
exposed members are `append`, `readAll`, `pruneConfirmed`, `pruneSensorSamples`, and no method name at
member indentation matches the mutating-verb pattern.

## New cases

| Test | Scenario |
|---|---|
| `testS49ATornLastRecordCostsThatRecordOnly` | S-49 |
| `testS50AFirstLaunchOnAnEmptyStoreWritesOneMarker` | S-50 |
| `testS51TwoRelaunchesKeepEveryRowAndItsSequence` | S-51 |
| `testS53AVersionThisBinaryDoesNotKnowIsNeverDamaged` | S-53 |
| `testS54TheTwoStoresAgreeOnOneSequence` | S-54 |
| `testS44ALoggedSetSurvivesTheProcess` | S-44 |
| `testS45ExactlyOneDeliveryAfterARelaunch` | S-45 |
| `testS46ACountdownThatWasRunningIsStillRight` | S-46 |
| `testS47TheOwedRatingQuestionSurvivesTheKill` | S-47 |

## Red → green (mutation checks)

Each mutation was applied to the exact line named, the file-store suite was run
(`swift-test --filter WatchFileStoreTests`), the EXACT original line was restored, and the suite was
re-run green. No step ends with a mutation applied.

| # | Original line | Mutation | Observed red |
|---|---|---|---|
| a | `timers: timers,` in `readAllLocked` | `timers: [],` | **3 failures** — S-44 (`S-44 the rest timer survived with its startedAt`), S-46 (`XCTUnwrap failed: expected non-nil value of type "WatchTimerRecord"`), S-54 (family parity) |
| b | `where row.recordId == record.recordId && row.recordType == record.recordType` in `appendLocked` | `where false && …` | **1 test, 2 failures** — S-51 (`("6") is not equal to ("3")`, `("7") is not equal to ("6")`) |
| c | `if let record = parseLine(line) { loaded.append(record) }` in `loadRows` | `guard let record = parseLine(line) else { loaded = []; break }` | **1 test, 2 failures** — S-49 (`("[]") is not equal to ("["s-1", "s-2"]")` and `("[]") is not equal to ("["s-1", "s-2", "s-4"]")`) |
| d | `guard !unsupported else { return record }` in `appendLocked` | removed | **1 test, 3 failures** — S-53 (returned record differs, `("1") is not equal to ("0")`, `("565 bytes") is not equal to ("306 bytes")`) |
| e | `(rows?.map(\.sequence).max() ?? 0) + 1` in `nextSequence` | `1` | **3 tests, 4 failures** — S-51 (`("[1, 1, 1, 1, 1]") is not equal to ("[1, 2, 3, 4, 5]")`, `("1") is not equal to ("3")`), S-44 (ladder position), S-54 (parity) |
| f | `(rows?.map(\.sequence).max() ?? 0) + 1` in `nextSequence` | `(rows?.count ?? 0) + 1` | **1 failure** — S-51 (`("9") is not equal to ("10")`): the count-based sequence collides with a row a prune left behind |

Mutation (f) is beyond the brief's list; it was added after (e) showed the brief's five mutations do
not distinguish "one more than the highest stored row" from "one more than the row count". S-51 gained
the prune-then-append stage that tells them apart (see the Assumption Log).

## First red run (before the store existed)

The test file was written first and run against the incomplete store. The first `swift-test` run
compiled and reported:

```
Executed 284 tests, with 1 failure (0 unexpected) in 1.118 (1.137) seconds
testS49ATornLastRecordCostsThatRecordOnly : XCTAssertEqual failed: ("["s-1", "s-2"]") is not equal to ("["s-1", "s-2", "s-4"]")
```

That failure was a real defect the test caught: a torn tail has no trailing newline, so the next
append was glued onto the torn fragment. The fix writes a line boundary first (`tornTail` in
`FileWatchSessionStore`), and the case is red under mutation (c) and green after it.

## Invariant

`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns
nothing. No Dart file was touched in this phase, so the invariant is unchanged — confirmed by reading
the four trees with the file-search tool.

## Not run

- `gateway.sh build` / `codegen` / `pub-get` / `format`: not implicated — no Dart file, no dependency
  manifest, and no new Dart file to format.

## Full Flutter suite (standing rule)

`.github/copilot/scripts/macos/gateway.sh test` — run even though no Dart file changed, because the
standing rules require it before finishing:

```
01:33 +3945 ~1: All tests passed!
```

3945 passing, 1 skipped, 0 failing, exit 0. Identical to what a Dart change would have to preserve:
this phase cannot move a Dart test.

## Phase 2 — the shell and the rating surface

### Baselines

| Check | Baseline | After Phase 2 |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 284 passing / 0 failing | **286 passing / 0 failing** (2 new S-55 cases) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors | **196 issues / 0 errors** (unchanged; no Dart file touched) |

### Footprint

`.github/copilot/scripts/macos/gateway.sh git-diff --stat`:

```
ios/OmniTrain Watch App/ContentView.swift          |  12 +-
 .../WatchSessionEngine/WatchEffortRating.swift     |   4 +-
 .../WatchEffortRatingTests.swift                   | 215 ++++++++++++++++++++-
 3 files changed, 223 insertions(+), 8 deletions(-)
```

All three files are named in the plan's Predicted Files. The shell's 12 changed lines are the three
briefed edits and nothing else — the doc paragraph, the store construction, and `await engine.restore()`
first in `restore()` — confirmed by reading the diff. `WatchEffortRating.swift`'s 4 changed lines are
the two `objectWillChange.send()` moves, one line out and one line in each.

### The shell (not compilable by any agent)

`swift test` cannot compile `ios/OmniTrain Watch App/` — the source is outside the Swift package — so
the three shell edits are verified only by reading the diff above. A search of the file for
`InMemoryWatchSessionStore` returns nothing; its only store construction is
`FileWatchSessionStore(directory:)` over `Application Support/watch-session/` (D-57). The governor's
`xcodebuild` is what compiles it.

### Red first (before the fix)

The two S-55 cases were written before `WatchEffortRating.swift` changed and run with
`swift-test --filter WatchEffortRatingTests/testS55`:

```
Executed 2 tests, with 5 failures (0 unexpected) in 0.087 (0.087) seconds
testS55ASlowAnswerNotifiesAfterTheRatingIsRecorded : XCTAssertTrue failed - S-55 the notification must wait for the answer t ...
testS55ASlowAnswerNotifiesAfterTheRatingIsRecorded : XCTAssertFalse failed - S-55 every notification sees the rating recorde ...
testS55ASlowCommitStillShowsTheOwedQuestion : XCTAssertTrue failed - S-55 the notification must wait for the commit it annou ...
testS55ASlowCommitStillShowsTheOwedQuestion : XCTAssertTrue failed - S-55 every notification sees the session ended
testS55ASlowCommitStillShowsTheOwedQuestion : XCTAssertTrue failed - S-55 every notification sees the prompt owed
```

### Mutation checks

Each mutation put that method's `objectWillChange.send()` back where it was; the file was run with a
filter, the EXACT original was restored, and the case re-ran green. No step ends with a mutation
applied.

| # | Original (step 2/3's position) | Mutation | Observed red |
|---|---|---|---|
| a | `objectWillChange.send()` after `if owed { await noteOwedPrompt(...) }` in `end()` | moved back before `let ended = await engine.finishSession()` | **1 test, 3 failures** — `testS55ASlowCommitStillShowsTheOwedQuestion` (a notification while suspended; observations saw the session not ended and the prompt not owed) |
| b | `objectWillChange.send()` after the crown resets in `confirm()` | moved back before `let recorded = try await engine.recordEffortRating(...)` | **1 test, 2 failures** — `testS55ASlowAnswerNotifiesAfterTheRatingIsRecorded` (a notification while suspended; the observation saw the rating not recorded) |

### The suspending stub

`SuspendingStore` wraps `InMemoryWatchSessionStore`: `arm()` makes the next `append` wait on a
`CheckedContinuation`, `resume()` releases it, and a `resume()` that arrives before the append
registers is handled by a `resumeRequested` flag under an `NSLock`. The lock is only ever taken from
synchronous helpers, so no lock spans a suspension point (the direct form drew Swift 6 availability
warnings). The tests poll `store.suspended` with `Task.yield()` in a bounded loop — no timer, no
unbounded wait.

The armed append is the *first* append after `arm()`: for End that is inside
`engine.finishSession()`, not the prompt's own append. That still proves S-55 — the notification's
position relative to the whole commit is what the scenario asserts, and both mutations show the old
order delivering one while that commit is in flight.

### Final green

```
Executed 286 tests, with 0 failures (0 unexpected) in 1.037 (1.057) seconds
```

Full run `.work/gateway/swift-test-20261006-125451-80844.log`, exit 0.

### Not run

- `gateway.sh test` (the Flutter suite): the Phase 2 brief waives it — no Dart file changed.
- `gateway.sh build` / `codegen` / `pub-get` / `format`: not implicated — no Dart file, no dependency
  manifest, and no new Dart file to format.
- `xcodebuild` (the watch app target): the governor's step; the shell file is outside the package.

### Invariant

A search of `lib/state`, `lib/features`, `lib/widgets` and `lib/core` for
`import .*hive_workout_repository` returns nothing. No Dart file was touched, so the invariant is
unchanged.

---

## Phase 3 — docs, walkthrough and the residue sweep for 4a

### Baselines at this phase's base (fa1c4ff)

`swift test` 286 / 0 failing · `flutter test` +3945 / ~1 / 0 failing · `flutter analyze` 196 issues,
0 errors.

### New case (Part A — D-50 pinned)

`WatchFileStoreTests.testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`, in
`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`. Two private builders
(`entry(…)`, `snapshot(…)`) were copied from `WatchPhoneEntriesTests.swift` (`:294`, `:307`) and left
private there and here. The case pins the limit D-50 names: a phone `session_snapshot` that re-states
a held `entryId` folds into the projection lens, so `engine.entries` shows the restated value while
the stored row (`engine.observations`) keeps the first; a **new** engine over the same directory
loses the lens, so it shows the stored first value until the next Sync re-states it, still over one
row.

The mutation is not meaningful here (the case pins a limit, it does not guard a fix), so
non-vacuity was proven by changing the case's own expectation, per the brief.

### Mutation (non-vacuity proof)

| Step | Change | Result |
|---|---|---|
| 1 | expected relaunch value `60` → `65` | **red**: `testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync` failed — `XCTAssertEqual` on the relaunched engine's first entry load: `Optional(60.0)` is not equal to `Optional(65.0)` |
| 2 | restored the exact original (`60`) | `git-diff --stat` shows the test file with insertions only |
| 3 | re-ran the filtered case | **green** |

### Final green

```
Executed 287 tests, with 0 failures (0 unexpected) in 1.060 (1.079) seconds
```

Full run `.work/gateway/swift-test-20261006-131233-87598.log`, exit 0 (286 baseline + 1 new case).

`docs_indexing_contract_test.dart` — 9 cases, 0 failing, exit 0:

```
00:00 +8: Docs indexing contract no document carries a scheduling or roadmap annotation
00:00 +9: All tests passed!
```

`flutter analyze` — 196 issues, 0 errors, exit 1 (the repo's pre-existing info notices; the same
196 as the baseline, and no file this phase touched is among them). Full run
`.work/gateway/lint-20261006-131237-87649.log`.

`gateway.sh test` (the full Flutter suite, run because the standing rule requires it before
finishing) — 3945 passing / 1 skipped / 0 failing, exit 0:

```
01:35 +3945 ~1: All tests passed!
```

Full run `.work/gateway/test-20261006-131509-88459.log`. No Dart file changed this phase, so the
count is the baseline exactly.

### Residue sweeps

| Sweep | Result |
|---|---|
| `InMemoryWatchSessionStore` under `ios/OmniTrain Watch App` | **nothing** — the shell constructs `FileWatchSessionStore`; the remaining `InMemoryWatchSessionStore` hits are `Sources/WatchSessionEngine/WatchSessionStore.swift:133` (the class itself), the Swift test suite's harness defaults, and `docs/plans/` |
| `in-memory only\|Nothing logged on the wrist survives\|The store is in memory\|keeps an in-memory store` over `docs/**/*.md` | **nothing outside `docs/plans/`** — the single live-doc hit is `docs/state_management/nutrition_state.md:198` ("the maintenance hint is in-memory only"), which is about the nutrition primer's seen-flag, not the wrist store |
| `needs PR 4\|needs the durable store\|durable store lands` (with `not runnable yet`, `store is in memory`) over `docs/**/*.md` | **nothing outside `docs/plans/`** — the hits are this plan's own Phase 3 step text and PR 2b's plan/evidence/review records |

### Doc sizes

Not measured: `wc -c` is denied by policy and the guard reports sizes only as a pass/fail band. The
guard's band case (`no documentation file is within the warning band of the ceiling`) passed, and the
ceiling case (`no documentation file exceeds the indexing ceiling`) passed, so no touched doc is
within 12 KB of the 64 KiB ceiling or over it. See A-39.

### Not run

- `xcodebuild` (the watch app target): the governor's step — `ContentView.swift` is outside the Swift
  package, so this phase's comment-only edit there is compiled by nobody but the governor's build.
- `flutter run`: not available to a Copilot agent; the owner exercises steps 11 and 17.

---

## Fix 1 — a failed disk write must not look durable (review F1–F4)

### Baselines at this fix's base

`swift test` 287 / 0 failing · `flutter analyze` 196 issues, 0 errors · `docs_indexing_contract_test.dart`
9 / 0.

### The mechanism: making a write actually fail

The brief's guard makes the containing directory read-only (`chmod 0o500`). This host may run as
root, where a directory's permission bits do not block a write (`docs/docs-audit-2026-07-26.md:273`;
`test/image_storage_service_test.dart` carries two known environmental failures from exactly that), so
the two failing guards add `UF_IMMUTABLE` on top — the **file** for F1 (a read-only directory does not
stop a write to an existing, writable file) and the **directory** for F2 — and each restores both in an
`addTeardownBlock`. Each guard first asserts the path is genuinely unwritable, so a guard that could not
produce a failure fails loudly instead of passing vacuously:

```
XCTAssertThrowsError(try FileHandle(forWritingTo: fileURL),
    "F1 the file must actually be unwritable, or this case proves nothing")
XCTAssertThrowsError(try Data("probe".utf8).write(to: directory.appendingPathComponent("probe")),
    "F2 the directory must actually be unwritable, or this case proves nothing")
```

Both preconditions passed in the red run **and** in the green run, so the mechanism blocks writes on
this host. See A-40.

### Red before the fix — three new cases, 6 failures

```
WatchFileStoreTests.swift:666: error: … testF1AnAppendThatCannotBeWrittenIsNotStoredAndKeepsItsSequence :
    XCTAssertFalse failed - F1 the row that could not be written is  ...
WatchFileStoreTests.swift:737: error: … testF2APruneThatCannotBeWrittenPrunesNothing :
    XCTAssertEqual failed: ("["o-1"]") is not equal to ("[]") - F2 a prune that cannot  ...
WatchFileStoreTests.swift:739: error: … testF2APruneThatCannotBeWrittenPrunesNothing :
    XCTAssertEqual failed: ("[["{currentExerciseIndex":0,…
WatchFileStoreTests.swift:755: error: … testF2APruneThatCannotBeWrittenPrunesNothing :
    XCTAssertEqual failed: ("[]") is not equal to ("["o-1"]") - F2 once the directory i ...
WatchFileStoreTests.swift:790: error: … testF3AFileWithoutAMarkerGetsOneAtTheTop :
    XCTAssertEqual failed: ("Optional("{currentExerciseIndex":0,…
WatchFileStoreTests.swift:795: error: … testF3AFileWithoutAMarkerGetsOneAtTheTop :
    XCTAssertEqual failed: ("2") is not equal to ("1") - F3 exactly one marker line

Executed 13 tests, with 6 failures (0 unexpected) in 0.114 (0.115) seconds
```

Exactly three cases failed and every other `WatchFileStoreTests` case stayed green, so the new cases
are red for their own reasons. The failures name the defect: the row that could not be written is in
the cache (F1), the prune drops `o-1` it could not write and the cache then reads differently from the
file (F2), and the marker is not first while a second marker is appended (F3).

One red detail is itself the proof that the write failed rather than the guard's mechanism being
inert: F1's `XCTAssertEqual(onDisk.sessions.map(\.recordId), ["s-1"])` — a fresh instance over the
directory — did **not** fail. Had the second append reached the disk, that assertion would have read
`["s-1", "s-2"]` and failed too.

### The fix

`appendLine` and `ensureDirectory` report success; `compact` reports whether the file was replaced;
`appendLocked` updates its cache only when the write succeeded and otherwise returns the row with its
assigned sequence, so the engine still keeps it; both prunes return an empty dropped list when
`compact` fails and leave the cache alone; `loadRows` records whether the file holds bytes and the
highest sequence in it, and `nextSequence` advances that counter (never `max(rows) + 1`), so a sequence
is never handed out twice; and a marker-less non-empty file — and a torn-tail file — is rewritten
through `compact` so the marker ends up first and the torn fragment is dropped rather than separated.

Files: `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` (five regions),
`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift` (three cases). The file-level
`git-diff --stat` counts (116 and 290) include the uncommitted Phases 1–3 work the tree still carries,
not this fix alone.

### Mutation proofs

Each mutation was applied alone, the failing case run, then the **exact** original restored and the run
repeated green. `git-diff --stat` after each restore shows no residue.

| # | Mutation | Result |
|---|---|---|
| a | `guard prepareFile(), appendLine(line) else { return stored }` → `_ = prepareFile()` + `_ = appendLine(line)` (cache updated even when the write failed) | **F1 red, F2 and F3 green** — 1 failure: `XCTAssertFalse failed - F1 the row that could not be written is …` |
| b | in `pruneConfirmedLocked`: `guard compact(survivors) else { return [] }` → `_ = compact(survivors)` | **F2 red** — 3 failures inside the one case: `["o-1"]` is not `[]`; the cache's JSON differs; `[]` is not `["o-1"]` once the directory is writable again |
| c | in `prepareFile`: `needsMarker && fileHasContent` → `needsMarker && !fileHasContent` (marker appended at the end again) | **F3 red** — 2 failures: the first line is a row; `2` is not `1` marker lines |
| d | `nextSequence()` → `(rows?.map(\.sequence).max() ?? 0) + 1` | **F1 red at its last assertion** — `XCTAssertGreaterThan failed: ("2") is not greater than ("2") - F1 a sequence is never reused` |

### Final green

Filtered to the file store's cases:

```
Executed 13 tests, with 0 failures (0 unexpected) in 0.034 (0.035) seconds
```

The whole watch package:

```
Executed 290 tests, with 0 failures (0 unexpected) in 1.043 (1.063) seconds
```

Full run `.work/gateway/swift-test-20261006-133044-9799.log`, exit 0 (287 baseline + 3 guards). No
previously passing case went red.

`docs_indexing_contract_test.dart` — 9 cases, 0 failing, exit 0 (the one doc sentence below is inside
the 64 KiB ceiling and its link-free text changes no link).

`flutter analyze` — 196 issues, 0 errors, exit 1 (the repo's pre-existing info notices; the same 196 as
the baseline; no file this fix touched is among them). Full run
`.work/gateway/lint-20261006-133325-10739.log`.

The invariant grep over `lib/state`, `lib/features`, `lib/widgets` and `lib/core` for
`import .*hive_workout_repository` returns nothing; no Dart file was touched.

The full Flutter suite was not run: the brief scopes this fix to Swift and the plan, and no Dart file
changed.

### The doc sentence

In `docs/watch_session_sync.md`, in the "A relaunch keeps what the wrist logged, with two gaps" bullet,
after the S-53 sentence:

> A wrist that cannot write to its storage keeps working in memory and every row already on disk still
> reads, but the row whose write failed is not treated as stored, so what was logged since the writes
> began failing is lost if the app is killed before the next Sync
> (`…testF1AnAppendThatCannotBeWrittenIsNotStoredAndKeepsItsSequence`).

It states only the F1 fact the brief asks for; the prune paths have no production caller yet (D-51), so
their failure mode is not documented (A-42).

## PR 4b — a pruned row takes its lens with it (G3) and the Dart twin refuses an ended session (F-9)

Every number below is observed output from a gateway check, not inference.

### Baselines (before this PR's edits)

| Check | Baseline | After |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 290 passing / 0 failing | **294 passing / 0 failing** (+4) |
| `.github/copilot/scripts/macos/gateway.sh test` | 3945 passing / 1 skipped / 0 failing | **3949 passing / 1 skipped / 0 failing** (+4) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors | **196 issues / 0 errors** (unchanged) |

### The three fixes

| # | Defect | File | Change |
|---|---|---|---|
| G3 | a pruned row left its correction behind, so a re-carried id read through a lens from a row that is gone | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `pruneConfirmed()` | for each dropped id: `entryCorrections.removeValue(forKey:)` and `deletedEntryIds.remove(_:)`, with the D-52 comment (+7 lines) |
| G3 | the same defect on the Dart engine | `lib/watch/session/watch_session_engine.dart`, `pruneConfirmed()` | the same per-id loop (+7 lines) |
| F-9 | the Dart logging surface accepted a session that was no longer active | `lib/watch/logging/watch_logging_state.dart`, `canLog` | `_engine.session?.status == WatchSessionStatus.active && _slot != null` (D-55); 6 lines changed, 2 deleted |

`FileWatchSessionStore.swift` is **absent from the diff** — byte-identical to HEAD. G1's and G2's
behaviours (a prune that cannot be written returns an empty dropped list and leaves the cache alone;
`compact` removes its staging file when the replace fails, `:336`) already existed; they gained guards,
not code (A-47).

### New cases (8)

watchOS, 4: `testS48APrunedRowTakesItsCorrectionWithIt`, `testS48APrunedRowTakesItsDeletionMarkerWithIt`
(`WatchSessionEngineTests.swift`), `testG1APruneOfSensorSamplesThatCannotBeWrittenPrunesNothing`,
`testG2AFailedReplaceLeavesNoTemporaryFile` (`WatchFileStoreTests.swift`).

Dart, 4: two in the new group `S-48 a pruned row takes its lens with it (G3)`
(`test/watch_session_engine_test.dart`), and `S-52 the wrist's own End closes the logging surface` with
`S-52 a session the phone ended is not a surface to log into` (`test/watch_logging_surfaces_test.dart`).

The two S-48 watchOS cases are the mirror of the Dart pair, and the two S-52 Dart cases the mirror of
`WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto` / `…testS029aAPhoneCompletionClosesTheLoggingSurface`.

### Red → green (mutation round)

G3's and F-9's guards are new tests over code that was then fixed, and G1/G2 pin behaviour the store
already had, so the red evidence is a mutation round on the fixed tree: each mutation applied alone,
the affected cases run, the **exact** original restored, the run repeated green. No step ends with a
mutation applied.

| # | Mutation | Observed red |
|---|---|---|
| Swift a | the `for id in dropped` lens loop removed from `pruneConfirmed()` | **2 failures** — S-48 correction at `:422` (`"70.0" is not equal to "60.0"`), S-48 deletion at `:456` (`"[]" is not equal to "[\"e-1\"]"`) |
| Swift b | `guard compact(survivors) else { return [] }` reverted to `_ = compact(survivors)` in the sensor prune | **3 failures** — G1 at `:814`, `:816`, `:836` |
| Swift c | `try? FileManager.default.removeItem(at: tempURL)` removed from `compact` (the G2 site) | **1 failure** — G2 at `:902` |
| Dart a | the lens loop removed from `pruneConfirmed()` | **2 failures** — S-48 correction at `:623`, S-48 deletion at `:670` |
| Dart b | `canLog` back to the slot-only rule | **2 failures** — S-52 wrist End at `:538`, S-52 phone completion at `:575` |

With all three Swift mutations in place the package reported `Executed 294 tests, with 6 failures` (the
290 others green); with both Dart mutations in place the two test files reported 4 failures out of 39
cases. The first Swift attempt at mutation b was itself a no-op and was corrected before the run that
produced the 3 failures above — a mutation that changes nothing is not evidence.

Restores verified by `git-diff --stat`: `FileWatchSessionStore.swift` absent (0 diff vs HEAD),
`watch_session_engine.dart` +7, `watch_logging_state.dart` 6 changed / 2 deleted, and the Swift engine
+7.

### Final green (after the doc and plan edits)

`swift-test` — `Executed 294 tests, with 0 failures (0 unexpected) in 1.054 (1.074) seconds`, exit 0,
log `.work/gateway/swift-test-20261006-143625-40875.log`.

`test` (the whole Flutter suite) — `01:39 +3949 ~1: All tests passed!`, exit 0. Run twice: once after
the doc bullet and plan edits (`.work/gateway/test-20261006-143639-41081.log`) and again over the
finished tree after the last doc sentence and the evidence file itself
(`.work/gateway/test-20261006-144121-46732.log`) — both `+3949 ~1`. Baseline 3945, so +4 and no
previously passing case red.

Targeted, the brief's three files — `test/watch_session_engine_test.dart`,
`test/watch_logging_surfaces_test.dart`, `test/watch_session_projection_test.dart`: `+71: All tests
passed!`, exit 0 (0 failing).

`lint` — `196 issues found. (ran in 3.0s)`, exit 1 on the repo's pre-existing info notices, the same
196 as the baseline; none of the four Dart files this PR touched appears in the log
(`.work/gateway/lint-20261006-143837-45907.log`).

`docs_indexing_contract_test.dart` — 9 cases, 0 failing, exit 0, run alone both before and after the
last doc edit (the new bullet and the appended sentence are inside the 64 KiB ceiling and add no link).

The invariant grep for `import .*hive_workout_repository` under `lib/state`, `lib/features`,
`lib/widgets` and `lib/core` returns nothing — the four paths were checked, and this PR's Dart edits
are in `lib/watch/`.

### Footprint

`.github/copilot/scripts/macos/gateway.sh git-diff --stat`, whole tree including the plan and the doc:

```
 ...-06-15e-watch-session-sync-pr4-plan.evidence.md | 121 +++++++++++++++
 .../2026-10-06-15e-watch-session-sync-pr4-plan.md  |  95 ++++++------
 docs/state_management/watch_surface.md             |  16 +-
 lib/watch/logging/watch_logging_state.dart         |   6 +-
 lib/watch/session/watch_session_engine.dart        |   7 +
 test/watch_logging_surfaces_test.dart              |  90 +++++++++++
 test/watch_session_engine_test.dart                | 172 +++++++++++++++++++++
 .../WatchSessionEngine/WatchSessionEngine.swift    |   7 +
 .../WatchFileStoreTests.swift                      | 147 ++++++++++++++++++
 .../WatchSessionEngineTests.swift                  | 139 +++++++++++++++++
 10 files changed, 753 insertions(+), 47 deletions(-)
```

Read before the plan edit this run the tree showed 9 files / 628 insertions, the difference being the
evidence file and the plan's own lines. `FileWatchSessionStore.swift` is absent from both lists.

### Residue sweeps

`canLog` across `docs/` returns only plan and review files: no live feature doc ever claimed the Dart
twin's old rule. The one live sentence that states the rule — "An ended session is no longer a logging
surface" in `docs/state_management/watch_surface.md` — cited the Swift shell's test alone, so the three
lines added there now name the Dart pair as well; F-9 makes that sentence true of both stacks, and the
doc rule wants a test per platform.

`lens` across `docs/` returns the plan folder's three files, the unrelated
`docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`, the D-50 sentence at
`docs/state_management/watch_surface.md:407`, and the new bullet's own citations. Nothing in `docs/`
still describes a prune as keeping the corrected row's lens.

### Not run

`flutter run` and an `xcodebuild` watchOS-simulator launch are unavailable to a Copilot-mode agent, so
nothing here is a statement about feel or about the app target compiling; the governor or the owner
exercises the wrist surface.



