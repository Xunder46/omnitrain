# Plan 305 — Calories on the Wear wrist, the Dart half (plan 280 leftover; the Apple wrist's plans 134c2, 134e, 135)

Plan 300 left calories out (D-30006). The Apple wrist counts the platform workout's active energy, stores it as `energy` sensor samples, shows `N kcal burned` on the rest screen, sends the phone a live `energy_live` frame, and puts the session's total on the `session_end` entry as `activeEnergyKcal`. The phone already reads all of that (plans 134c1, 135: `WatchLiveEnergy`, the importer, the message validator), so nothing on the phone changes. The Dart wrist has none of it (the `energy` kind is vocabulary only). This plan builds the whole wrist-side logic in Dart behind a new optional source; plan 306 builds the Kotlin that feeds it (Health Services calories + the permission). Split per the PR scope budget. Until 306 every Wear build reports the energy source as `unavailable`, so the wrist behaves as before. Base commit: `ee076b16`. Analyze baseline: 174 issues, 0 errors. Lead-built (gateway hangs for builders on this PC).

## Goal and acceptance

With a source that reports energy: the wrist stores each reading, sends the phone a live running total (at most one frame per half a kilocalorie and five seconds), shows `N kcal burned` under the rest clock once at least half a kilocalorie is measured, and writes the session's total on its `session_end` entry. With no source, a denied permission, or no reading, nothing changes. The Workout done screen gets no calories row (the Apple summary has none: matching it).

Acceptance: S-30501..S-30509 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; Docs delta applied. Not provable without the native half: owner check 22 (after 306).

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30501 | A separate optional `WatchEnergySource` interface (`activeEnergyPermission()`, `activeEnergy()`: cumulative kilocalories as numbers) in `watch_sensor_recording.dart`. The recorder uses it only when the source `is WatchEnergySource`, so the existing `WatchSensorSource` and its five test doubles stay unchanged (Apple adds the two calls to its protocol with a default extension; Dart has no such default). | `WatchSensorRecording.swift` 76-88 |
| D-30502 | `WatchSensorRecorder.start` also starts energy for every session whatever its modality (permission `granted` only); each reading is stored as an `energy` sample at the instant it arrived, THEN announced to the engine with that instant; `stop` cancels it. `readings` gains `activeEnergyKcal` (the newest stored `energy` sample of the current session). | Apple D-13471, D-13480, D-13511 |
| D-30503 | `WatchSensorSummaries.activeEnergy(samples, from:, through:)` (new `lib/watch/session/watch_sensor_summaries.dart`), a port: the cumulative counter's chain inside the window, a smaller count means the counter restarted (the new count is the energy since), finite and non-negative counts only, total rounded to one decimal, null when no count is inside the window or the total rounds to zero. | Apple `WatchSensorSummaries.activeEnergy` |
| D-30504 | `WatchSessionEngine.announceEnergy({kilocalories, at})`: nothing unless the current session is `active`, and for a finite value of at least 0; the total is the chain over the session's stored samples (a recovered workout's restarted counter never pulls the phone's chip down), else the raw value; a frame goes out the first time for a session, when the total fell, or when it rose by at least 0.5 kcal and at least 5 s passed since the last frame; anything else sends nothing. The envelope is `energy_live`, origin `watch`, id `msg-energy-<session>-<ms>`, payload `activeEnergyKcal` and `at`; the validator's refusal records no mark. Live only, never stored. | Apple `announceEnergy`, `energyAnnouncement` |
| D-30505 | `_sessionEndEvent` adds `activeEnergyKcal` from the summaries over `[creation.startedAt, endedAt]`, for a wrist-created end and a followed end alike; absent when nothing was measured. | Apple `WatchSessionEngine.swift` 2228 |
| D-30506 | `WatchSensorLabels.activeEnergy` = `<rounded> kcal burned` when the newest reading is at least 0.5, else null; `WatchLoggingState.activeEnergyLabel`. The rest screen shows it as one small secondary line under the clock, one line, scaled down rather than overflowing, spoken as `Calories burned` plus `N kilocalories burned` (`1 kilocalorie burned` for one). Not on the logging screen (the Apple wrist shows it on rest only). | Apple D-13481..D-13483 |
| D-30507 | `WearSensorSource` also implements `WatchEnergySource`: method `activeEnergyPermission` on the sensors method channel and `EventChannel('omnitrain/wear_sensors/energy')` of numbers. Same failure rule as the other calls: a missing native half reads `unavailable` and an empty stream. This fixes the contract plan 306 implements. | plan 297 D-29701 |
| D-30508 | The wrist's diagnostics log coalesces live `energy_live` sends to one `frame_sent` line a minute (the phone never sends the wrist such a frame, so receiving is not coalesced), as the Apple bridge's `chattyTypes` does; an energy frame the radio refuses is dropped (not durable), as every live-state frame is. | Apple D-14203 |
| D-30509 | Not in scope: the Kotlin source (plan 306); the heart-rate fields on `session_end` (the Dart wrist sends none: a separate gap noted in the progress file); a calories row on the Workout done screen. | |

## Input-reality checklist

- **Writers/units.** One recorder subscription writes samples; the engine's announce reads them under no await between reading the marks and emitting (Dart is single-threaded, so the check-and-mark is one synchronous section). Units: kilocalories, cumulative since the platform workout began.
- **Lifecycle.** A recovered workout restarts the counter: the chain adds the new count whole, so neither the live total nor the session total drops. A session that ends with no reading sends no field. A reading arriving after the session ended announces nothing (status check).
- **Settings changing while open.** Permission is asked once at the session's sensor start; a later change takes effect at the next session.
- **Time.** Samples are keyed by their instant (idempotent ids); the end window is the session's own start and end.
- **Load.** One sample per platform update (about one a second) is a store append like heart rate; at most one frame per 5 s.
- **Wording.** `N kcal burned`; spoken `Calories burned` / `N kilocalories burned`.
- **Slot competition.** One line on the rest screen between the clock and Next; at 192/227 dp it must not overflow and the clock stays whole.

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30501 | the summaries: counts `[40, 95.5]` in the window; a restart `[100, 160, 20, 50]`; a count before the window as the base; non-finite/negative ignored; none inside; total rounds to 0 | 95.5; 100-0, 60, then restart adds 20 and 30 = 210; base subtracted; ignored; null; null |
| S-30502 | recorder with a fake energy source granted; readings `5, 12.5`; then denied; then a plain `WatchSensorSource` | two `energy` samples stamped with their arrival instants and `readings.activeEnergyKcal == 12.5`; no sample when denied or not an energy source; `stop` cancels (a later reading stores nothing) |
| S-30503 | engine announce: first reading; +0.3 kcal after 10 s; +1 kcal after 2 s; +1 kcal after 6 s; a fall; NaN, negative; a completed session | frame; none; none; frame; frame; none; none |
| S-30504 | announce after a recovered counter (samples 100 then 20) | the frame's total is the chain (120), not 20 |
| S-30505 | announce frame shape | equals `watch/sync_protocol/fixtures/valid/energy_live.json`'s keys and passes the engine's validator; a validator refusal records no mark (the next call may send) |
| S-30506 | session end with samples: wrist-created and followed; with none | `activeEnergyKcal` equals the chain total; absent |
| S-30507 | labels | `96 kcal burned`, none for 0.3, `1234 kcal burned`, `1 kcal burned` for 0.5, none with no sample |
| S-30508 | rest screen at 192/227 dp with a reading and without | the line is present with a reading, absent without; no overflow; the clock and Next stay |
| S-30509 | `WearSensorSource` and transport | method name and stream channel exact, `unavailable` on a missing method; energy frames coalesce to one diagnostics line a minute, other frames do not |

Mutation pass by the lead over every guard family.

## Phases

Single phase by the lead.

## Docs delta

New page `docs/wear_os_app_calories.md` (indexed in `docs/README.md`) and one pointer line in `docs/wear_os_app.md` (50 KB, near its band, so the details live on the new page). Owner check 22 is reserved for after plan 306.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| build, tests, mutation (39/39), docs | Done (evidence file) |
| commit | Done |
| owner check 22 | Open, after plan 306 |
