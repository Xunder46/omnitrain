# Plan 150 — evidence

Swift only. Baselines and every run below are `swift-test` (the gateway's
`swift test --package-path watch/watchos`).

## Baselines

- Bare `swift-test` before the change: **1394 tests, 0 failures** (11 s of test
  time). The package suite is the baseline for this plan; `lint` (Dart) is
  untouched by a Swift-only change and is run at the end for the record.
- `WatchWorkoutCoordinatorTests` (pre-existing, S-1500…S-1510): 9 tests, 0
  failures — the fake platform/store this plan extends.

## Task A — the sensor sample race

### Red before the fix (Thread Sanitizer)

`prove-red HEAD swift-test --sanitize=thread --filter WatchSensorSampleRaceTests
-- watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSampleRaceTests.swift`

```
gateway: RED AT HEAD (exit 1)
SUMMARY: ThreadSanitizer: Swift access race WatchSessionEngine.swift:209 in WatchSessionEngine.sensorSamples.getter
SUMMARY: ThreadSanitizer: Swift access race WatchSessionEngine.swift:227 in WatchSessionEngine.newestSensorSamples()
```

Writer thread: the sensor stream's write chain (`WatchSensorRecorder.record` →
`appendSensorSample`, task per sensor). Reader thread: main (`WatchLoggingState`
→ SwiftUI distance tile). Exit 1 comes from TSan's warnings; in the same run the
lost-row assertion also tripped once (`1999 != 2000`), which is what the plain
array's grow-under-a-reader does when it does not trap outright.

### Green after the fix

`swift-test --sanitize=thread --filter WatchSensorSampleRaceTests` → 1 test, 0
failures, no TSan report from `WatchSessionEngine`. Non-sanitized, the same test
is part of the full-suite run below.

### Design (`WatchSensorSampleLog.swift`)

`private let lock = NSLock()`, one `private var rows: [WatchSensorRecord]`.
`snapshot()`, `append(_:)`, `contains(where:)`, `prune(where:)`, `fill(with:)`.
The lock wraps the array operation and nothing else — **no lock is held across
an `await`**: `appendSensorSample` awaits `store.appendSensorSample` first and
appends to the log after it returns, and `restore` fills the log after the store
read has completed.

`append` de-duplicates by `recordId` (D-15002), which is the store's own rule and
lets `appendSensorSample` drop its read-then-append `contains` check — that pair
was itself the racy window.

Naming note: `removeAll`/`replace` were rejected by the module's own append-only
scan (`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
forbids a `func` named for a mutation), so the box names them `prune`/`fill`.

## Task B — the adopted workout discarded

`WatchWorkoutAdoptBeforeRestoreTests` (new, on the existing
`ScriptedPlatformStore`) plus `WatchWorkoutCoordinatorTests`.

| Scenario | Before the fix | After the fix |
|---|---|---|
| S-15002 adoption + `refresh(nil)` before restore | **red** — `XCTAssertEqual failed: ("1") is not equal to ("0")` (`ended` 1, expected 0) and `("nil") is not equal to ...` (`running` nil) | green |
| S-15003 then `refresh(same-id session)` | **red** — `XCTAssertEqual failed: ("["running"]") is not equal to ...` (a begin after the end) and `("1") is not equal to ("0")` | green |
| S-15004 `restoreFinished(nil)` after adoption | parity guard — passes in both, because it needs the flag to be cleared | green |
| S-15005 different session id after adoption | parity guard, green in both | green |
| S-15006 `refresh(nil)` with no adoption | parity guard, green in both | green |

S-15004 and S-15005 cannot be red without the change (they are the "as today"
arms, and `restoreFinished` is new code), so both are proved by mutation:

- Original line `adoptedBeforeRestore = true` (recover's adoption) changed to
  `= false` → S-15002 and S-15003 fail exactly as in the table above; restored,
  green.
- Original line `self.adoptedBeforeRestore = false` in `restoreFinished`
  deleted → S-15004 fails (`0` end calls, `[]`, `XCTAssertNil failed`,
  `[]`); restored, `Executed 5 tests, with 0 failures`.

Focused run after the fix: `swift-test --filter WatchWorkoutAdoptBeforeRestoreTests`
→ 5 tests, 0 failures. With the 9 pre-existing coordinator tests:
`--filter "WatchWorkoutAdoptBeforeRestoreTests|WatchWorkoutCoordinatorTests"` →
14 tests, 0 failures.

### Design (`WatchPlatformWorkout.swift`)

`private var adoptedBeforeRestore`, set in `recover` when the store takes the
workout over, cleared by `apply` on the first non-nil session and by the new
`public func restoreFinished(session:)`, which enqueues on the same serial tail
as `refresh` (so it cannot interleave with an in-flight `apply`).
`apply` returns early **only** while the flag is set and the session is nil —
every other answer, including a different session id, is today's rule.
`WatchWorkoutLifecycle.action` is unchanged and still pure.

`ContentView.restore()` calls `await workout.restoreFinished(session: engine.session)`
straight after `engine.restore()`. **App-target code: `swift test` cannot compile
it**, so the wiring itself is unverified by this suite; the coordinator contract
it calls is covered by S-15004.

## Findings not fixed

### A — other engine arrays (D-15003)

Same unsynchronized read-while-write pattern, same two thread roles (writer: the
async engine entry points; reader: main via `WatchLoggingState`/SwiftUI):

| Array | Declared | Written | Read on main |
|---|---|---|---|
| `storedObservations` | `WatchSessionEngine.swift:70` | `:1202`, `:1765`, `:2368`, `:2397` | `:203`, `:692`, `:697`, `:1679`, `:1710`, `:1877`, `:1937`, `:2087`, `:2346` |
| `storedTimers` | `:76` | `:1055`, `:1127`, `:2277` | `:1015`, `:1113` |
| `sessionRows` | `:69` | `:1526-1527` | `current` (`:203` path), every `session` read |

The sensor list was the one the crash hit because two streaming tasks append to
it while the logging screen redraws on main without an intervening suspension.
These three are written by awited entry points the app calls from its own
serial paths, so the window is narrower — but it exists, and the same box is the
fix when it costs a phase.

### B — the second relaunch logged `workout_recovered running saving`

Read, not changed. `WatchWorkoutCoordinator.recover` adopts only when
`platform.continueInProgress()` answers true, i.e. when
`HealthKitWorkoutStore.adoptInProgress()` (`HealthKitWorkoutStore.swift:~270`)
returns the type of a session whose state is `.running` or `.paused`. Any other
state is refused on purpose (`pendingRecoveryName` is set and nil is returned),
and the launch then takes the ordinary recovery: `inProgressActivityTypes()`
hands back `pendingRecoveryName`, so `recoverInProgress(saving: true)` closes it
with `saving: true` and notes `workout_recovered … saving`.

The second relaunch is in that state **because of the first one**: the first
launch adopted the running workout and then discarded it (the Task B defect) —
`end(saving: false)` ends the `HKWorkoutSession` and calls
`discardWorkout()` on its builder. Ending the session is a state change HealthKit
keeps, so the next `recoverActiveWorkoutSession()` hands that same half-closed
session back, `adoptInProgress` correctly refuses a session that is no longer
running, and the ordinary recovery path takes it. So the `workout_recovered`
line is a symptom of the Task B discard, not a second defect; fixing B removes
the trigger. Residual risk, listed not fixed: that final `end(saving: true)` is
asked of a builder already discarded, so `finishWorkout()` throws and `saved`
stays nil (nothing is saved — harmless), but a store that answered instead would
save a workout the first launch had decided to discard.

### C — pace `6:38:33 /mi` (look only)

`WatchLoggingState.paceLabel(for:)` (`WatchLoggingState.swift:449`) divides
**the session's whole elapsed time** by **the session's cumulative distance**:

```swift
let elapsed = clock().timeIntervalSince(startedAt)      // session.startedAt
let unitsCovered = metres / metresPerUnit(units.distanceUnit)
return "\(Self.clock(elapsed / unitsCovered)) /\(unit)"
```

Three things make that print hours per mile:

1. The numerator is wall-clock elapsed since `session.startedAt` — rests,
   dialogs, time before the location subscription ran and time standing still
   are all in it. There is no moving-time notion anywhere in the engine.
2. The denominator is a distance, so the quotient is *minutes* per unit, and it
   has no ceiling: a session left open for six hours over 0.9 mi is 398 min/mi.
3. `Self.clock(_:)` (`WatchLoggingState.swift:987`) is a duration formatter: past
   59:59 it prints an hours field, so 398 minutes renders as `6:38` + `:33` —
   `6:38:33`. The unit suffix is honest (`/mi`), the field layout is not: an
   hours-per-mile reading is a clock overflowing, not a unit error.

The screenshot's numbers fit (a long-open session at 0.9 mi total). Note also
that the distance row beside it is the **effort's own window**
(`measuredValue` → `windowDistanceMeters`, D-2205), while the pace denominator is
the **session total** (`readings.distanceMeters` = newest `gps`/`distance`
sample) — so the pace is computed from numbers the screen does not show
together.

Existing convention for an unavailable pace: nil, never a placeholder —
`paceLabel` returns nil with no session start and below
`WatchSensorPace.minDistanceMeters` (50 m, `WatchLoggingState.swift:137`); the
label is simply absent from `WatchSensorLabels` and the row is not drawn, the
way `activeEnergyLabel` gates on 0.5 kcal. What is missing is a *ceiling*, not a
floor, and a format that cannot grow an hours field.

## Task D — the pace (2026-11-13)

The owner's outdoor walk read `127 bpm · 0.1 mi · 6:38:33 /mi` beside a Distance row of
`0.9 mi`. Task C found the cause: the numerator was the whole session's clock since
`session.startedAt`, the denominator the newest stored distance reading — two different
windows — and `WatchLoggingState.clock(_:)` grew an hours field.

### Where the numbers come from

- The header's distance is `WatchLoggingState.sensorLabels` (`distanceLabel(for:)`) over
  `readings.distanceMeters` = `WatchSensorRecorder.readings` (`WatchSensorRecording.swift`):
  the newest stored `gps` sample, else the settled `distance` sample. It carries no window.
- The distance FIELD beside it is the effort's own window (`windowDistanceMeters()`,
  `workTimer.startedAt` → now, D-2205) — a third value, which is why the header and the
  field disagreed before the fix as well.
- Task D reads the stored `gps` samples (the same rows the reading's value belongs to) to
  recover the window: the first fix of the counter's newest run, where a total below the
  one before it marks a restart (the steps rule, D-125). Elapsed = `clock()` − that fix.

### Red before the change

`prove-red HEAD swift-test --filter WatchSensorPaceTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchSensorPaceTests.swift`

```
gateway: prove-red: RED AT HEAD (exit 1)
WatchSensorPaceTests.swift:96: error: XCTAssertEqual failed: ("Optional("3:50:00 /mi")") is not equal to ("Optional("20:00 /mi")") - S-15007 …
WatchSensorPaceTests.swift:101: error: XCTAssertEqual failed: ("Optional(2)") is not equal to ("Optional(1)") - S-15007 a pace is minutes and seconds …
WatchSensorPaceTests.swift:129: error: XCTAssertNil failed: "12:36:15 /km" - S-15008 standing still has no pace to show
WatchSensorPaceTests.swift:150: error: XCTAssertNil failed: "1:00:00 /km" - S-15010 exactly one hour a kilometre is the ceiling…
```

Same fixture, before → after:

| Scenario | Before | After |
|---|---|---|
| S-15007 restart (0.1 mi, 120 s since the restart, session 23 min old) | `3:50:00 /mi` (two colons) | `20:00 /mi` |
| S-15008 160 m over 2 h | `12:36:15 /km` | nil |
| S-15009 existing 5:00 /km (`WatchSensorRecordingTests` S-003) | `5:00 /km` | `5:00 /km` |
| S-15010 exactly 3600 s/km | `1:00:00 /km` | nil |
| S-15010 3599 s/km | `59:59 /km` (unchanged) | `59:59 /km` |

### Green after the change

- `swift-test --filter WatchSensorPaceTests` → **3 tests, 0 failures**.
- `swift-test --filter "WatchSensorRecordingTests|WatchGpsDistanceTileTests|WatchGpsByExerciseTests|WatchLoggingStatusTests|WatchSensorSummaryTests"` → **93 tests, 0 failures** (the S-003 5:00 /km case among them).
- Full `swift-test` → **Executed 1397 tests, with 0 failures** (11.090 s); baseline was 1394,
  the three new scenarios are the difference.

### Design (D-15007, D-15008)

`paceLabel(for:)` no longer reads `engine.session?.startedAt`. `paceWindowStart()` walks the
stored `gps` samples in `(recordedAt, sequence)` order and keeps the first fix of the newest
run — the sample after the last total that went backwards. Elapsed is `clock()` minus that
instant; metres stay the value the header prints, so the two describe one window.

`WatchSensorPace.maxSecondsPerUnit = 3600` is the ceiling and is **exclusive**: the label is
formatted minutes:seconds directly (not through the duration formatter), so the minutes part
is always below 60 and an hours field is impossible; an `assert` states it. Sample count is
unchanged: the pace still appears only at or above the 50 m floor.

Not changed: the header's distance is still the session reading and the Distance row is still
the effort's window (D-2205). Making the header print the effort window too is a product
decision for the owner, not part of "pace first".

## Task E — the header's distance (2026-11-14)

The owner decided the two numbers must match ("Yes, match them"): after a restart the header
read `0.1 mi` beside a field of `0.9 mi`. The header now prints the Distance row's own figure
and the pace divides that same window (D-15011); where no such row exists it keeps Task D's
pairing exactly (D-15012).

### Where the numbers come from

- The field is `measuredValue(distance)` → `windowDistanceMeters()` (`workTimer.startedAt` →
  now, D-2205), printed by `displayValue` as `%.1f` of the unit's metres.
- The header was `readings.distanceMeters` — `WatchSensorRecorder.readings`, the newest `gps`
  row — a different window, so a restart made them disagree.
- Task E introduces one private accessor, `distanceWindow(for:)`, that answers both labels:
  the effort window when `isMeasured(distance)` and a work clock exist, else the counter
  total plus `paceWindowStart()`. `distanceLabel` and `displayValue` format the same metres
  with the same `%.1f`, so header and field cannot drift.

### Fixture

The owner's walk, with the counter restarting inside the effort window: Start, 800 m, the
counter restarts, 0.1 mi since. The window covers 960.9 m in 240 s. Old header: the newest
run's `0.1 mi`, paced over its two minutes — `20:00 /mi`. New: `0.6 mi`, `6:42 /mi`.

### Red before the change

`prove-red HEAD swift-test --filter WatchHeaderDistanceTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchHeaderDistanceTests.swift`

```
gateway: prove-red: RED AT HEAD (exit 1)
WatchHeaderDistanceTests.swift:120: error: … XCTAssertEqual failed: ("Optional("0.1")") is not equal to ("Optional("0.6")") - S-15011 the header's distance is the Distance field's own figure, got "0.1" beside "0.6"
WatchHeaderDistanceTests.swift:126: error: … XCTAssertEqual failed: ("Optional("0.1")") is not equal to ("Optional("0.6")") - S-15011 the effort's 960.9 m window, not the counter's newest 0.1 mi run
WatchHeaderDistanceTests.swift:147: error: … XCTAssertEqual failed: ("Optional("20:00 /mi")") is not equal to ("Optional("6:42 /mi")") - S-15012 240 s over the window's 0.597 mi, not the restart's own 20:00 /mi
WatchHeaderDistanceTests.swift:219: error: … XCTAssertEqual failed: ("Optional("0.2")") is not equal to ("Optional("1.0")") - S-15014 kilometres: header and field are one number
WatchHeaderDistanceTests.swift:225: error: … XCTAssertEqual failed: ("Optional("12:26 /km")") is not equal to ("Optional("4:10 /km")") - S-15014 the same window's time per kilometre
Executed 4 tests, with 7 failures
```

S-15013 passes at HEAD because it guards the *preserved* fallback; a mutation proves it —
`distanceWindow`'s fallback line changed from `return (sessionMetres, paceWindowStart())` to
`return (windowDistanceMeters(), workTimer?.startedAt)`:

```
WatchHeaderDistanceTests.swift:186: error: … XCTAssertEqual failed: ("Optional("0.0")") is not equal to ("Optional("0.1")")
WatchHeaderDistanceTests.swift:191: error: … XCTAssertNil/Equal failed: ("nil") is not equal to ("Optional("20:00 /mi"))
Executed 1 test, with 2 failures
```

The exact original line was restored and the four tests re-ran green.

### Green after the change

- `swift-test --filter WatchHeaderDistanceTests` → **4 tests, 0 failures**.
- `WatchSensorPaceTests` and `WatchSensorRecordingTests` (the 5:00 /km S-003 case) stayed
  green unchanged in the full run.
- Full `swift-test` → **Executed 1401 tests, with 0 failures** (11.303 s); baseline was 1397,
  the four new scenarios are the difference. Re-run after the mutation was restored:
  **1401 tests, 0 failures** (10.974 s).

### Not changed

- The heart-rate and energy parts of the header, the Distance row, `WatchSensorPace`'s floor
  and ceiling, and the log payload all keep their rules.
- No doc page states the header's distance or pace rule (`docs/state_management/watch_sensors.md`
  describes the readout's storage, not its window; `docs/navigation_and_screens.md` and the
  wrist QA walkthrough name no header figure), so no doc changed.

## Verification

- Latest full `swift-test` after Task E: **Executed 1401 tests, with 0 failures**
  (11.303 s) — 1394 after Task A, 1397 after Task D, 1401 after Task E.
- One pre-existing test went red during Task A's first full run and is now green:
  `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
  rejected the box's `removeAll`/`replace` names; renamed to `prune`/`fill`
  rather than touching the scan (see Task A above).

## Task F — the engine's other lists under Thread Sanitizer (2026-11-12)

`WatchSensorSampleRaceTests` was written for the sensor list alone. The audit below
covers every mutable stored property of `WatchSessionEngine` (line numbers at
`34e3e809`), then a TSan stress test per list that has two reachable threads.

| Property | Writers (entry point) | Readers | Thread class | Overlap possible |
|---|---|---|---|---|
| `storedSensorSamples` | `restore`, `appendSensorSample`, `pruneSettledSensorSamples` | `sensorSamples`, `newestSensorSamples`, energy/session-end summaries | sensor stream task; main-thread screens | Yes — **already boxed** (Task A, `WatchSensorSampleLog`) |
| `storedObservations` | `restore`, `storeSnapshotEntry`, `appendObservation`, `confirmObservations`, `trimPrunedObservations` | `observations`, `entries`/`projectedEntries`, `nutritionLog`, `waterLog`, `pendingObservations()`, `unconfirmedObservations`, `knowsObservation`, `restFollowOnEntryId`, `pruneSettledSensorSamples`, `mergeLateEntries`, `heldRecord` | phone delivery task, logging tap, receipt task, launch restore; main-thread screens | Yes — **proven, fixed** |
| `inflightEntries` | `storeSnapshotEntry`, `appendObservation` (claim, then remove) | same two, before their append | phone delivery task, logging tap | Yes — **proven, fixed** (folded into the log's claim) |
| `storedTimers` | `restore`, `adoptTimer`, `stopTimerFromMessage`, `appendTimer` | `timerRows`, `newestTimer` (feeds `timerFor`, `sessionSnapshot()`), `adoptTimer`/`stopTimerFromMessage` dedup | phone delivery task, logging taps, main-thread screens | Yes — **proven, fixed** |
| `sessionRows` | `restore`, `mirrored` | `newestSessionRows()`, `creationRow`, `holdsTerminalRow` | mutex-serialised writers incl. phone frames; main-read screens via `session` | Yes in principle — **not proven** (S-15023) |
| `current` | `restore`, `storeSessionRow`, `mirrored` | every `engine.session`, `requireSession`, `guardSession`, `currentExercise` | as above | Yes in principle — **not proven** (S-15023) |
| `entryCorrections`, `deletedEntryIds`, `replacedEntryIds` | `storeSnapshotEntry`, `unhideTheIdTheSnapshotNames`, `applyStructureChange`'s lens, `trimPrunedObservations`, `restore` | `projectedEntries`, `carryingLens`, `heldPayload` | phone frames vs main-thread projections | Yes in principle — **not proven** (S-15023) |
| `appliedChangeIds`, `newestSnapshotAt` | `restore`, the snapshot/apply paths | the apply paths | mutex-serialised writers; launch | No reachable reader outside those paths — **not proven** |
| `acknowledgedObservationIds` | `restore`, `confirmObservations` | `knowsObservation`, `isEndAcknowledgedWhereOwed` | receipt task vs main-thread `hasEffortRating` | Yes in principle — **not proven** |
| `energyAnnouncedSession/Kcal/At` | `announceEnergy` only | `announceEnergy` only | the energy stream's chained write task | No — one writer and one reader, the same call (`WatchSensorWrites` chains it) |
| `announcedCountdownKeys` | `WatchTimerHaptics` | `WatchLoggingState` | main thread only | No |

No property is `@MainActor`: nothing in the package is actor-isolated, so the thread
classes above are the entry points' own, read off their call sites.

### Proven at HEAD (TSan, current sources before the fix)

`swift-test --sanitize=thread --filter WatchEngineListRaceTests` (three tests, the first
report aborts the process, so each list was run on its own filter):

```
S-15021 — testS15021ObservationListSurvivesConcurrentWritersAndReaders
SUMMARY: ThreadSanitizer: Swift access race WatchSessionEngine.swift:1760 in WatchSessionEngine.appendObservation(_:sessionId:)
SUMMARY: ThreadSanitizer: Swift access race WatchSessionEngine.swift:1755 in WatchSessionEngine.appendObservation(_:sessionId:)
SUMMARY: ThreadSanitizer: BUS (libsystem_malloc.dylib:arm64e+0x1e658) in _malloc_type_malloc_outlined+0x40
    #12 WatchSessionEngine.observations.getter WatchSessionEngine.swift:203
S-15022 — testS15022TimerListSurvivesConcurrentWritersAndReaders
WARNING: ThreadSanitizer: Swift access race
  Modifying access: #0 WatchSessionEngine.appendTimer(_:) WatchSessionEngine.swift
  Previous read:    #0 WatchSessionEngine.newestTimer(kind:) WatchSessionEngine.swift:2297
                    #1 WatchSessionEngine.timersJson()  WatchSessionEngine.swift:1432
                    #2 WatchSessionEngine.sessionSnapshot(messageId:) WatchSessionEngine.swift:312
SUMMARY: ThreadSanitizer: Swift access race WatchSessionEngine.swift in WatchSessionEngine.appendTimer(_:)
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
```

Without TSan the same two tests trap at HEAD
(`Object … _ContiguousArrayStorage deallocated with non-zero retain count 2`, then
`Fatal error: Index out of range`), which is the owner's SIGABRT shape.

`gateway.sh prove-red HEAD swift-test --filter WatchEngineListRaceTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchEngineListRaceTests.swift`:

```
Test Case … testS15021ObservationListSurvivesConcurrentWritersAndReaders]' started.
Object 0xbf73a0000 of class _ContiguousArrayStorage deallocated with non-zero retain count 2 …
gateway: prove-red: RED AT HEAD (exit 1).
```

S-15023 is green at HEAD and green after: no TSan report, no trap, no lost row. The
session mirror is only written inside `WatchAsyncMutex` and the readers ran between
writes, so TSan found no overlapping pair in 80 advances and 40 frames.

### The change

New `watch/watchos/Sources/WatchSessionEngine/WatchEngineRowLogs.swift`:
`WatchObservationLog` (rows + in-flight claims) and `WatchTimerLog` (rows), each an
`NSLock` box in `WatchSensorSampleLog`'s shape — `snapshot` for every read, `append`
that ignores an id already held, `contains`, `prune`, `map`, `fill`. The claim is one
operation with the "already held?" check (`claim` returns the claim to wait on or nil
when this writer owns it, `finishClaim` removes and resumes), so two copies of one
entry can no longer both store (F-7); the lock is never taken across an `await`.
`storedObservations` and `storedTimers` became `observationLog` and `timerLog`, and
`EntryClaim` moved to the new file as an internal class.

### Green after

- `swift-test --sanitize=thread --filter WatchEngineListRaceTests` →
  **Executed 3 tests, with 0 failures**; no TSan report, no trap.
- Whole suite under TSan (`swift-test --sanitize=thread`) →
  **Executed 1404 tests, with 0 failures**, `ThreadSanitizer: reported 17 warnings`,
  **none of them in `Sources/`**: `WatchConnectivityBridgeTests.swift:1464` and `:1528`
  (the gated transports' own locals), `WatchDistanceTrackerTests.swift` ×14 in
  `ScriptedRawFixSource.rawFixes()` and ×1 at `:322` in the stream-finish test. The
  remaining reports are test doubles' state, not the engine's.
- Whole suite without the sanitizer → **Executed 1404 tests, with 0 failures**
  (11.785 s); baseline 1401, the three new scenarios are the difference.
- `docs/state_management/watch_sensors.md` "One writer" paragraph now names the two
  boxes and the two tests that prove them.

### Not fixed, and why

`sessionRows`, `current`, the correction/deletion lens and `acknowledgedObservationIds`
keep their plain fields: S-15023 could not make TSan report them, and D-15003's rule is
that an unproven race is reported, not rewritten. A main-actor isolation pass over the
engine would close them and is a separate plan.

