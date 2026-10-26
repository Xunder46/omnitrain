# Feature: 65 — a run, row or ride on the wrist takes a distance you dial in when GPS measured nothing

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; owner device checks open, QA step 27). Owner: watch audit 3 (2026-10-23), fix order item 9, in chat; the owner left the "when does the watch offer a distance to dial?" question to the lead (decision below). Series: with 63, 64, 66a, 66b. Base commit: `.work/2026-10-23-65/base.txt` (the tree also carries uncommitted plans 61 and 62; `WatchLoggingState.swift` has plan 61's edits). Working branch: the one checked out (`claude_develop`); never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Decision (lead, for the owner to veto): **every timed exercise that counts distance (runs, rows, rides, a treadmill, an erg) shows a Distance tile on the wrist from before Start until Log. While the watch's GPS has measured movement in this effort, the tile shows that measurement and cannot be turned. Until it has (indoors, no signal, location access refused, a rowing machine), you can turn the Crown or tap − / + to enter the distance yourself.** At Log, GPS wins if it measured anything; otherwise the number you dialled is sent, marked "entered" (the phone already stores that source).

| What you do | Now | After 65 |
|---|---|---|
| Treadmill run, GPS permission refused or no fix: Start, run, Log | the run is logged with no distance; no way to add one on the wrist | a Distance tile (0.00 km or mi in the phone's unit) is on the screen; you dial 5.00 km before Log and the phone shows the run as 5.00 km, entered by hand |
| Outdoor run with GPS moving | no distance tile; GPS metres ride the log | the tile shows the effort's GPS distance live and is read-only; the log carries the GPS metres as today (source gps) |
| Rowing machine with GPS on but nothing measured | no distance | the tile stays turnable until GPS measures movement; dial 2000 m, Log: entered, 2000 m |
| You dial a distance, then GPS starts measuring | n/a | GPS wins from then on (a measurement outranks a dial, as for every other measured value); your dialled number is not sent |
| An exercise without the distance capability (a plank, a squat) | no tile | no tile (unchanged) |
| Log, then start the next effort of the same exercise | n/a | the tile starts at 0 again (a distance belongs to one effort) |
| A set exercise (reps/weight), a hold, a sports period | no distance | unchanged |

How to SEE it (owner): on the watch, start a Free workout, add a run or row exercise (any with distance), press Start: the Distance tile is below the clock. Turn the Crown. On the simulator GPS is off, so the dial is what you see; outdoors with a real watch you see the GPS value instead.

Not in this plan: the Dart wrist twin (`lib/watch`, documented divergence); a distance on rounds/holds; editing a distance after Log; a "paused GPS" notice. Known: on a 40 mm watch the new tile adds a row above the Log button: **owner check** (layout), the rows come from the generic field list so no view code changes.

## Facts from the scout (`.work/crew/2026-10-23-65/scout-distance.md`; lines spot-checked by the lead in `WatchLoggingState.swift`)

- Timed efforts carry NO metric rows: `metricKeysByKind[timed] = []` (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` ~l.209). `metricKeys` filters a kind's keys by `capability(for:)`, and only `WatchMetricKey.distance` maps to the capability `"distance"` (the dormant code path for exactly this row).
- `windowPayload(loggedAt:coversDistance:)` (~l.976) attaches `distanceMeters` + `distanceSource: "gps"` only when `isMeasuringDistance` and `windowMeters(...) > 0`. `windowMeters(from:through:)` (~l.1003) is the effort-window GPS chain; `isMeasuringDistance` is `sensors?.isMeasuringDistance` (location subscription running).
- `field(for:)` / `isMeasured(_:)` (~l.668/683): a distance field is measured (read-only) iff `isMeasuringDistance`; its value is `readings.distanceMeters` (the whole-session live total, NOT one effort's window) else the dialled value (`dialled[slotId][metricKey]`, metres) else `initialValue` (0 for timed). `adjust(_:detents:fine:)` ignores a measured field. Stepping for distance is already defined (`WatchMetricStepping`, 0.1 of the unit per detent; value stored in metres).
- Wire: PROTOCOL allows `distanceSource` `gps | entered | estimated` on `timed` beside `distanceMeters`; the phone importer stores `entered` as sent (`lib/core/services/watch_session_importer.dart` ~l.1400; `test/distance_source_import_test.dart` S-876); the validator only requires `distanceMeters` beside a source.
- `WatchGpsPolicy.isRequired(session)` starts the location subscription whenever the session modality or the current exercise has the distance capability, so every distance exercise has `isMeasuringDistance` true once GPS is allowed: the old "measured iff subscription running" test would lock the tile for an indoor run. Hence D-2.

## Decision Ledger

- D-1 `WatchLoggingState.metricKeysByKind` (~l.209): `WatchEffortKind.timed: [WatchMetricKey.distance]` (the `metricKeys` capability filter still hides it from exercises without `distance`). The doc comment above the table (currently "Timed work has no row at all …") is rewritten: a timed effort's length is its clock; its only row is a distance, offered when the exercise counts distance.
- D-2 `isMeasured(_:)` becomes: `metricKey == WatchMetricKey.distance && isMeasuringDistance && windowDistanceMeters() > 0`, where `private func windowDistanceMeters() -> Double` = `windowMeters(from: workTimer?.startedAt ?? clock(), through: clock())` when a work timer is running, else 0 (before Start nothing is measured yet). `measuredValue(for:)` for distance returns `windowDistanceMeters()` (the EFFORT's metres, not `readings.distanceMeters`'s session total). Function names avoid the append-only guard's verbs (checklist r, ac).
- D-3 `windowPayload(loggedAt:coversDistance:)` (~l.976-990): replace the `if coversDistance, isMeasuringDistance { … }` block by: `if coversDistance { let covered = isMeasuringDistance ? windowMeters(from: startedAt, through: loggedAt) : 0; if covered > 0 { payload["distanceMeters"] = covered; payload["distanceSource"] = "gps" } else if let entered = dialled[dialledKey]?[WatchMetricKey.distance], entered > 0 { payload["distanceMeters"] = entered; payload["distanceSource"] = "entered" } }`. `dialledKey` is read BEFORE `dialled` is cleared by `log` (builder checks the order in `log(now:)`, ~l.897 `loggedKey`; if the clear happens first, read through `loggedKey`).
- D-4 `initialValue(for: distance)` stays 0 for timed; the existing `log` clears the exercise's dialled values, so the next effort starts at 0 (S-9505 pins it).
- D-5 Wire/phone: no change (the `entered` source is already accepted and stored). `watch/sync_protocol/PROTOCOL.md` l.~155 already says "Distance is entered by hand whenever the watch has no fix": add one sentence naming the wrist's rule (GPS wins when it measured movement) in a docs-only builder-watch run.
- D-6 Tests that pin the old shape change on purpose, with the reason in the report: `WatchLoggingSurfacesTests.testS006AManualDistanceNeverReachesTheObservation` (becomes S-9503's "dialled distance reaches the observation"), and any timed-surface assertion that lists no fields for a distance exercise (the builder finds them with the filtered runs; known readers: `WatchLoggingSurfacesTests` l.129/335/549/578/621, `testEveryValidObservationsEventIsReproducedByTheSurfaceShape`, `WatchEffortDistanceTests`, `WatchGpsByExerciseTests`, `WatchLoggingTimersTests`, `WatchPlannedSetsTests`, `WatchRestLabelsTests`, `WatchCaptureContractTests`, `WatchSessionStartPathsTests`). `testS002AnExerciseThatCannotCoverDistanceOffersNoDistance` must stay green unchanged.

## Readers listed

- Producers of the wire `distanceSource`: only `windowPayload`. Consumers on the phone: unchanged.
- Everything that lists `fields` of a timed surface: the tests above, and the views (generic: `WatchLoggingView` renders `fields`; `WatchLoggingModel.turn(to:)` drives `adjust`). `armedMetricKey` defaults to the first field, so the Crown drives the Distance tile with no new view code (the builder confirms in `WatchLoggingModel`).
- Scenario ids S-9501..S-9515 checked free (grep `S-95`, 2026-10-23).

## Core scenarios

New `watch/watchos/Tests/WatchSessionEngineTests/WatchHandDistanceTests.swift`, built on the harness of `WatchEffortDistanceTests.swift` (copy its sensor/GPS sample helper block; it already stores `gps` samples with sequence numbers and an injected clock).
- S-9501 exercise with `["time","distance"]`, cardio session: before Start the surface offers a `distance` field, value 0, not measured. An exercise with `["time"]` offers none (also pinned by the old S-002 test).
- S-9502 manual dial: Start, advance 120 s, dial +3 detents fine (value unlike the fixtures: in metres whatever the unit gives for 0.3 of the unit; the test computes it from `WatchMetricStepping`, not a hard-coded number), Log: the event carries `distanceMeters` equal to the dialled metres and `distanceSource == "entered"`.
- S-9503 `testS006…` rewritten: a dialled distance reaches the observation (replaces "never reaches").
- S-9504 GPS wins: GPS samples stored inside the window summing 1,234 m while a distance of 5,000 m was dialled: the event carries 1,234 and `"gps"`; the dialled value is not sent. And the field is `isMeasured` once the first sample lands (a dial then changes nothing: `adjust` returns without effect).
- S-9505 per-effort: Log with a dialled distance, start the next effort of the SAME exercise: the field is 0 and not measured; Log it with nothing dialled: the event has NO `distanceMeters` and no `distanceSource`.
- S-9506 one test per arm of the "measured" test: (a) location subscription running with NO sample in the window -> field not measured, dial works, Log sends `entered`; (b) subscription running with samples whose window total is 0 (a still watch) -> same; (c) subscription not running (access refused) -> same; (d) subscription running with movement -> measured. Stale samples from BEFORE Start must not count (a sample at the Start instant is the baseline: S-3214/S-3217 rule).
- S-9507 dial of zero or never touched: no distance keys in the event (a zero is not sent).
- S-9508 the wire: the produced `timed` event with `entered` passes `SyncProtocolValidator`-equivalent checks on the wrist side: the package's own event validation (the way `WatchEffortDistanceTests` S-3210 checks `rejections.isEmpty`) reports none, and a hand event without metres but with a source cannot be produced (S-3210 stays).
- S-9509 hold and round efforts with a distance-capable exercise (a sports period) do not get the tile: `metricKeysByKind` is only changed for timed.
- S-9510 units: with the phone's unit miles the dialled value displays in miles and is sent in metres (1.00 mi -> 1609.344 m, to the existing rounding of the metres field); with km, 1.00 km -> 1000 m.

## Phases

- P1 `crew-builder-watch` (6 items): D-1, D-2, D-3, D-4, D-6 and S-9501..S-9510. One concern, one file of production code plus tests. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchHandDistanceTests.swift` (new) and the existing test files of D-6 (minimal edits, named in the report). Brief: report first as a skeleton; never the full `flutter test`; Done: `swift test --filter WatchHandDistanceTests`, `--filter WatchEffortDistanceTests`, `--filter WatchGpsByExerciseTests`, `--filter WatchLoggingSurfacesTests`, `--filter WatchSessionEngineTests` (the append-only guard only runs there). Serial after 63 P2 and before 66a (one Swift package). Plan 61 also edits `WatchLoggingState.swift` (uncommitted): the builder touches only the lines named above.
- P2 `crew-builder-watch` (docs-only, one file): D-5 in `watch/sync_protocol/PROTOCOL.md`.
- P3 `crew-docs-keeper`: the doc that owns the wrist logging screens (grep `isMeasuringDistance`, `distanceSource`, `timed surface` in `docs/`), `docs/watch-app-setup-and-qa.md` (a QA step: the 40 mm layout and a real run indoors/outdoors are owner checks; the brief names the list to append to). Run no test.

## Verify (governor)

`swift test` full, `xcodebuild` (checklist an form; the view code is generic but the package's field list changed), `flutter test test/distance_source_import_test.dart test/watch_session_projection_test.dart` (phone side unchanged; confirms `entered` still imports), `flutter analyze` count. Mutations: `[distance]` -> `[]`; `isMeasured` ignoring the window total; window total without the baseline sample; GPS preferred only when `> 0` -> `>= 0`; `entered` source string changed; `entered > 0` -> `>= 0`; the dialled value read after `log` clears it; miles/km conversion removed; `measuredValue` back to `readings.distanceMeters`; the tile offered on hold/round. Simulator: seed `watch-session.jsonl` with a distance exercise and open the logging screen (checklist ae): the tile and the Crown; measure the new row's position at the 40 mm size. Owner checks: a real indoor row/run and a real outdoor run.

## Progress

Done 2026-10-23: P1 (13 tests) + fix 1 (eight existing tests pinned "a timed effort has no rows"; seven edited with their intent kept: time-only fixtures or the new shape) + fix 2 (a second effort's measured value is its own window, killing the `measuredValue` session-total mutant) + P2 PROTOCOL.md sentence (found missing by the reviewer) + docs. Lead: full `swift test` 916/0, `xcodebuild` BUILD SUCCEEDED, 12 of 12 mutants killed after fix 2. Simulator (Apple Watch SE 40 mm, location refused): the Distance tile shows `0.0 km`, + twice -> `0.2 km`, Start keeps it, Log goes to the rest screen; the logged effort reaches the summary. Known/owner (owner): on the 40 mm screen the Start/Log button sits partly below the fold with the two notice lines and the tile (scrolls; not changed here); a real outdoor run and a real indoor row.
