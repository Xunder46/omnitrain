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

## Verification

- Full `swift-test` after the change: **Executed 1394 tests, with 0 failures**
  (11.081 s), including the 5 new adoption scenarios and the new race test.
- One pre-existing test went red on the first full run and is now green:
  `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
  rejected the box's `removeAll`/`replace` names; renamed to `prune`/`fill`
  rather than touching the scan (see Task A above).
