# The Wear OS App: calories

> Calories on the Android wrist, in two parts: the wrist's own logic in Dart (plan 305, below) and the native source that feeds it (plan 306, not built yet). A separate page from [The Wear OS App](wear_os_app.md) to keep that page under the indexing band. The Apple wrist's version is plans 134c2, 134e and 135; the phone's half (plans 134c1 and 135) needs no change.

## What the wrist does with a calorie count

The platform workout's active energy (kilocalories, cumulative since the workout began) reaches the wrist through an optional interface, `WatchEnergySource` (`lib/watch/sensors/watch_sensor_recording.dart`: `activeEnergyPermission()` and `activeEnergy()`), kept apart from `WatchSensorSource` so every existing source and test double stays as it was. When the source also implements it, `WatchSensorRecorder.start` asks the permission and, on `granted`, listens for every session whatever its modality. A refused permission, a source without energy, or no reading changes nothing.

Each reading does three things, in this order:

1. **Stored** as an `energy` sensor sample stamped with the instant it arrived (the same append-only store as heart rate).
2. **Announced** to the phone as a live `energy_live` frame (`WatchSessionEngine.announceEnergy`): the running total, live only, never stored and never queued (a frame the radio refuses is dropped and the next reading replaces it). The total is the restart-aware chain over the stored counts (`WatchSensorSummaries.activeEnergy`, `lib/watch/session/watch_sensor_summaries.dart`): a count smaller than the one before means the counter restarted, as after a recovered workout, so it adds whole and the total never falls. A frame goes out the first time for a session, when the total fell (only possible with no stored count to chain), or when it rose by at least half a kilocalorie and at least five seconds passed since the last frame. A non-finite or negative value sends nothing; so does a session that is not active. A frame the protocol refuses leaves no mark, so the next reading may go.
3. **Shown** on the rest screen: `N kcal burned` as one small line under the rest clock, once at least half a kilocalorie is measured (`WatchSensorLabels.activeEnergy`, `WatchLoggingState.activeEnergyLabel`). It scales down rather than overflowing and is spoken as `Calories burned`, `N kilocalories burned`. The logging screen and the Workout done screen show no calories (the Apple wrist shows them on rest only).

The session's total also rides the `session_end` entry as `activeEnergyKcal` (wrist-created and followed ends alike), absent when nothing was measured; a zero total is never sent.

The wrist's diagnostics log coalesces live `energy_live` sends to one `frame_sent` line a minute (`WearWatchTransport.chattyTypes`), as the Apple bridge does, so a reading every few seconds does not push everything else out of the log.

## The contract the native half implements (plan 306)

`WearSensorSource` (`lib/watch/sensors/wear_sensor_source.dart`) implements `WatchEnergySource`: method `activeEnergyPermission` on `omnitrain/wear_sensors/methods` (`granted`, `denied` or `unavailable`, asking the user first when undetermined) and `EventChannel('omnitrain/wear_sensors/energy')` of numbers, cumulative kilocalories. Until the native half exists every call fails with a missing-plugin error and reads `unavailable`, so a Wear build today behaves as it did before calories.

## Verified by

`test/wear_calories_test.dart` (plan 305): the summaries chain (restart, window ends, base count, filters, rounding), the recorder (store, instants, denial, no energy source, stop, every modality), the announce rule (first, half a kilocalorie, five seconds, equal, fall, invalid, ended, new session), a recovered counter, the frame against the shared fixture and the validator, a refused frame leaving no mark, the session end (wrist-created, followed, absent, restart, conformant), the label, the rest screen (line, spoken form, 192 and 227 dp), the Wear source's channels and the transport's log coalescing. Not seen on a watch: owner check 22 (after plan 306).

> **Doc freshness** — Derived from `lib/watch/` on 2026-11-22. If a claim here disagrees with the source, the source wins.
