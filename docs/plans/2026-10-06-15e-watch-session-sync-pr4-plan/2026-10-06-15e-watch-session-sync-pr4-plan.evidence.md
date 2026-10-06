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


