# Plan 156 — the watch's stored readings stop growing and stop costing more each hour

Source: item 1 of the owner's Fable review (2026-11-13), re-measured here. Triage: memory `fable-watch-review-triage-2026-11-13`.
Swift only (`watch/watchos`, one call in `ios/OmniTrain Watch App/ContentView.swift`). Three phases, one PR each or one PR if small.

## What is wrong (measured, see the evidence file)

- Every heart-rate, GPS, step and energy reading is stored as a row and kept forever. `pruneSettledSensorSamples()` and the store's `pruneConfirmed()` exist and are tested, but nothing in the app calls them (only water-tap pruning runs, at launch).
- Cost grows with everything stored, not with the workout: the file store scans every row to see if an id is already held, the engine's list does the same again, and the one-second screen tick copies and filters the whole list. Measured on a Mac in a debug build: one stored outdoor hour costs 2.8 ms per new reading and 0.16 s at launch; ten hours cost 28.7 ms per reading, 6.5 ms per screen tick and 1.7 s at launch. Appending 57,000 readings through the file store took 585 s (the cost is quadratic). A real watch is slower than a Mac.
- Nothing else on the screen reads old workouts' readings: the summaries went to the phone inside the workout's end entry.

## Scope

- **A** — wire the existing prunes: at launch, and after the phone confirms entries, so a finished, acknowledged workout's readings are removed. Plus a retention valve for a workout the phone never confirms.
- **B** — constant-time appends and reads: an id index in the three lists and in the file store, and the current workout's readings kept by workout with the newest reading per kind cached.
- **C** — a regression test and a doc sentence so the cost cannot creep back.

## Decisions

- **D-15601** Calls: `ContentView` calls `engine.pruneSettledSensorSamples()` and `engine.pruneConfirmed()` once after `restore()` (before the first workout starts), and the engine calls the settled prune after each receipt batch that confirms entries (`confirmObservations`) and after a session-end acknowledgement, fire-and-forget off the hot path. No call while a workout is active in a way that touches the active workout (the existing gate already keeps a running or unacknowledged session's readings).
- **D-15602** Retention valve: readings of a workout that has ended but was never acknowledged by the
  phone are dropped 14 days after it ended (`WatchSessionEngine.unacknowledgedReadingsRetention`); the
  workout's entries and its end entry are never dropped by this. Phase 1 first confirms the end entry
  carries the summaries (it is built from the readings at the end, `sessionEndEvent`); if it does not,
  the valve is removed and the plan says so.
- **D-15603** `pruneConfirmed` compacts the file only when it drops something (today it rewrites the file on every call); the same for the sample prune.
- **D-15604** An id index: `Set<String>` beside each list (`WatchSensorSampleLog`, `WatchObservationLog`, `WatchTimerLog`) kept under the existing lock, and a `[key: row]` map in `FileWatchSessionStore` for its duplicate check, so an append is constant-time. Public behaviour unchanged ("the same reading twice is one row").
- **D-15605** `WatchSensorSampleLog` also keeps rows by session id and the newest row per kind for the current session, updated on append; `sensorSamples`, `newestSensorSamples()` and the per-second readout read only the current workout's rows, not the whole log. The pace window's sort of all GPS rows moves to the same per-session store (computed once per new GPS row, not per tick).
- **D-15606** Out of scope, recorded in the evidence: the file store still holds its rows in memory (a second copy beside the engine's lists) — bounded once A lands; session, timer and confirmation rows (small, tens per workout) are not pruned.
- **D-15607** No wire, protocol or phone change; no behaviour the user sees changes.

## Scenarios

- **S-15601** Ten finished workouts with every entry and end acknowledged, in a file store: after a relaunch and the launch prune, none of their readings are in the file or in memory; a running workout's readings and an unacknowledged workout's readings stay.
- **S-15602** A receipt that confirms the last entry of a finished workout removes that workout's readings without a relaunch.
- **S-15603** An ended, never-acknowledged workout keeps its readings at 13 days and loses them at 15 (D-15602); its entries stay.
- **S-15604** A file with nothing to drop is not rewritten by the prunes (D-15603).
- **S-15605** 20,000 readings appended through the file store and the engine finish within 8 seconds (before: about 70 s on the same Mac), and a repeated reading is still one row.
- **S-15606** With 50,000 stored readings from old workouts, the current workout's `newestSensorSamples()` does not read them: 1,000 ticks finish within a bound that old workouts' size cannot change (measured with a count of rows visited, not wall time).
- **S-15607** The existing sensor, pace, header-distance, race (TSan) and replay suites stay green.

## Phases

1. **A** — D-15601..15603, S-15601..15604. Done Criteria: `swift test --package-path watch/watchos --filter` the new tests, red at HEAD with the failing line pasted; `swift test` full; `swift test --sanitize=thread --filter WatchSensorSampleRaceTests|WatchEngineListRaceTests`.
2. **B** — D-15604, D-15605, S-15605, S-15606 (rows-visited counters in the logs for the test). Done Criteria: as above plus a re-measurement table in the evidence file at 1, 5 and 10 hours.
3. **C** — doc sentence in `docs/state_management/watch_sensors.md`, evidence, review.

Predicted files: `WatchSessionEngine.swift`, `WatchSensorSampleLog.swift`, `WatchEngineRowLogs.swift`, `FileWatchSessionStore.swift`, `WatchSessionStore.swift` (in-memory twin), `ios/OmniTrain Watch App/ContentView.swift` (one call), new tests `WatchStoreGrowthTests.swift`, the doc.
Owner device check after build: a watch that has recorded since October launches in a few seconds and a new workout's readout does not lag; (the owner's current store is the real test, and its first launch parses the big file once before pruning).

## Progress

| Phase | Item | Status |
|---|---|---|
| A | D-15601 launch prune in `ContentView.restore()` | Done — settled prune only; `pruneConfirmed()` stays out (A-156-02). Guard `testS15601TheLaunchRestoreAsksForThePrunes`, red at HEAD |
| A | D-15601 release on the phone's receipt | Done — in `applyReceipt`, not `confirmObservations` (A-156-01). Guard `testS15602TheLastReceiptReleasesTheReadingsInPlace`, red at HEAD |
| A | D-15602 14-day retention valve | Done. Guard `testS15603AnUnacknowledgedWorkoutKeepsItsReadingsForFourteenDays`, red at HEAD |
| A | D-15603 compact only when dropping | Done. Guard `testS15604APruneThatDropsNothingDoesNotRewriteTheFile`, red at HEAD |
| A | S-15601 launch behaviour | Done — `testS15601TheLaunchPruneReleasesFinishedReadingsOnly` (green at HEAD too: it drives the pre-existing gate) |
| A | Phase gate | Complete — 5/5 growth, 39/39 sensor, full `swift-test` 1425/0 |
| B | D-15604 id index (three logs + file store) | Done. Guard `testS15605TwentyThousandAppendsStayInsideTheBound`, red at HEAD at 98.2 s |
| B | S-15605 20,000 appends inside the bound | Done — 6.55 s / 6.48 s against 8 s, counts and duplicate behaviour asserted |
| B | D-15605 per-session reads, S-15606 rows-visited | **Not done** — left for the next run; nothing half-built |
| B | Re-measurement table at 1, 5, 10 stored hours | **Not done** — belongs with D-15605, whose effect it would show |
| C | doc sentence in `docs/state_management/watch_sensors.md` | Done — the bounded-readings bullet, naming all five S-156 tests |
| C | evidence + review | Evidence done (this run); review not started |

## Assumption Log

- **A-156-01** The receipt trigger sits in `applyReceipt` (the receipt frame), not in
  `confirmObservations` as D-15601 words it. A release on `confirmObservations` turned two existing
  plan-150 pins in `WatchSensorRecordingTests` (`testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged`,
  `testS237AnEndAcknowledgedAndPrunedStillReleasesTheLog`) red or order-dependent: they assert the
  count a later explicit `pruneSettledSensorSamples()` reports, which a receipt-time release empties
  first. Every real receipt arrives as a receipt frame, so the production path is unchanged, S-15602
  still holds, and the release is awaited on the frame's own turn (receipts are rare; the per-second
  path stays clear), which also keeps the test from polling.
- **A-156-02** `ContentView.restore()` does not call `pruneConfirmed()`, contrary to D-15601's second
  call. Plan 96 D-43 pins that it has no production caller: it drops water taps the water count still
  reads (`WatchWaterBarSourceTests.testS94b25a…`). Confirmed observation rows staying is D-15606's
  recorded scope.
- **A-156-03** `InMemoryWatchSessionStore` is now `NSLock`-protected, method for method. It had no
  synchronisation at all and the receipt-triggered prune racing an engine turn crashed the full suite
  (`Fatal error: Index out of range`). `WatchSessionStore.swift` is a predicted file.
- **A-156-04** D-15602's clock is the newest session row's own `recordedAt` (the completion row),
  not the end entry's `loggedAt`: both are written in the same finish path, and the row is what
  `newestSessionRows()` already returns.
- **A-156-05** S-15605 keeps the plan's 8 s bound although the fixed run measures 6.5 s: the rest is
  the per-append fsync, which D-15604 does not touch, and HEAD measures 98 s, so 8 s still separates
  the two by an order of magnitude. The bound is the plan's; a device or loaded-CI margin is the
  owner's call.

