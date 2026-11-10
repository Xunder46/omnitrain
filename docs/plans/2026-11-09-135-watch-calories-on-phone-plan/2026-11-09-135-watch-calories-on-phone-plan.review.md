# Review: 135 (the watch's calories reach the phone while a session runs) · P1–P4 · ff398e1a..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: not run (brief item 5: "Do not run tests"; the lead's runs — full Swift package 1293 green, xcodebuild BUILD SUCCEEDED, phone tests green, 25-mutant pass with 2 accepted equivalents — stand as stated)
Diff vs Predicted Files: conforms — every hunk attributable to 135 sits in the plan's Predicted Files (wire, wrist, phone lists); the other files in `git-diff --stat` are plans 134a–e / 136 / the Summary pens in the shared tree, scoped out per the brief. The proof (`new file`) files match: `energy_live.schema.json`, `fixtures/valid/energy_live.json`, `fixtures/invalid/energy_live_negative.json`, `fixtures/invalid/energy_live_phone_origin.json`, `watch_live_energy_test.dart`, `test/session_live_calories_test.dart` (a new 134d file that carries the 135 group), `WatchEnergyLiveTests.swift`, `test/watch_live_energy_test.dart`; `WatchSensorSourceSourceTests.swift` gains the S-13515 guard.

## Answers to the brief's questions

**Q1 — `announceEnergy` concurrency: OK.**
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:1588` is `public func announceEnergy(kilocalories: Double, at: Date)` on the non-isolated `public final class WatchSessionEngine: ObservableObject` (:37). There is no await anywhere in its body: one synchronous read of `current` (:1590), the throttle fields' read-modify-write (:1593–1612) and `emit(envelope)` (:1612) run as one indivisible synchronous turn, so no intra-call tearing is possible.
- The mutex (`WatchSessionEngine.swift:44`, comment :41–45) exists for the *five session-row writers* whose read of `current`, awaited store append and write of `current` span suspensions (`createSession` :328, snapshot :542, structure :651, lifecycle :692, timers :1264). `announceEnergy` needs none of that: it builds no row and appends nothing.
- The other non-mutex reader of `current` predates this plan: `requireSession()` (:2234) called from `appendSensorSample` (:1543, reached from the recorder's background write chain, `WatchSensorRecording.swift:295–322`), and `restore()` writes `current` with no mutex at all (:150–170, a launch-only path). `announceEnergy` is consistent with that established pattern.
- The throttle fields `energyAnnouncedSession/Kcal/At` (:1573–1575) have exactly one production writer: `WatchSensorRecorder.recordEnergy` (`WatchSensorRecording.swift:294–298`), called from the one `energyTask` consumer loop (:268–270, a sequential `for await`). Sequential single-writer — no race.
- Worst reachable interleaving: an energy turn lands between two mutex-protected turns and reads a `current` the writer is about to replace (a session just ended elsewhere). The frame names the session id it read; the phone's holder keeps it keyed by that id (`watch_live_energy.dart:24–28`), and the chip shows it only for the open session id (`workout_session_screen.dart:186–191`). No invariant the plan states is broken. The class compiles and runs green under the package's own concurrency settings (xcodebuild and 1293 tests per the lead), which would have flagged a sendability breach of a `@Sendable`-checked surface.

**Q2 — skipping the handler's tail: OK, nothing else needs every frame.**
The energies' early `return` (`watch_sync_wiring.dart:376–380`) skips exactly: the request routing (`requests.handle`, :386), `router.receive` (:397), the `push.rebaseline()` (:404) and, when not owed, `push.flush()` + `timerPush.flushClears()` (:410–411) — the D-192(c) "this frame proves the radio works, so the owed goes out now" trigger. What other consumers rely on is driven by the *transport*, not by this handler:
- the "last heard" stamp: `WatchLinkState._heard` subscribes to `_source.heard` (`watch_link_state.dart:98`), and `heard` fires in the transport's `_dispatch` for every arriving frame *before* the handler runs (`watch_transport.dart:440`), so an `energy_live` still refreshes "Last synced".
- reachability/link status: `_source.linkChanges` (`watch_link_state.dart:97`) — transport level.
- the debt flush is per-handler-frame opportunism, not a per-frame consumer: a missed trigger only delays the owed send to the next non-energy wrist frame or phone change; the debt itself stays owed (D-202) and the flush runs again. Energy frames arrive at most every 5 s, so the added delay is bounded by the next frame.
No other consumer of `resolved.onIncoming` exists: the handler at :377 is the only handler bound (S-13510b's "a wrist that named none is sent the whole list" path is inside it, and energy frames are not request frames).

**Q3 — the receiver's strictly-newer `at` gate: OK.**
`watch_live_energy.dart:24–26` ignores a frame whose `at` is not strictly after the held one for the same session. The sender cannot produce the two worry cases from inside the protocol:
- an equal-`at` restart: `announceEnergy` sends a fall only when it can actually send, and its own gate requires `at.timeIntervalSince(lastAt) >= 5` (`WatchSessionEngine.swift:1597`) — a restarted counter with an `at` equal to the last announced never passes the sender's gate either.
- a wrist clock corrected backwards mid-session: the same `>= 5 s` gate goes negative, so the sender itself stops until the corrected clock re-passes the last announced instant — while silent, it is silent on both ends and recovers by itself rather than diverging.
The wrist's `at` is `clock()`'s own stamp (`WatchSensorRecording.swift:295–297`, the same instant the stored row gets), and neither side ever compares clocks across devices (plan, Input-reality §4). The gate therefore only drops genuine late/replayed copies.

**Q4 — the screen: OK with one Minor (finding 2).**
- Listener hygiene: added in `initState` (`workout_session_screen.dart:275`), removed in `dispose` (:1889).
- `mounted`: `_onWristEnergy` ends in `_updateUi` (:191), whose first line is `if (!mounted) return;` (:186 in `_updateUi`'s body, screen file :184–192 region); a frame landing after dispose updates nothing.
- Cross-session staleness: `_onWristEnergy` nulls the chip for any frame whose `sessionId` differs from `widget.workoutState.currentSession?.id` (:186–190), and the initial read applies the same check (:277–282). On the normal paths a session change remounts the screen, which re-derives from the held value (tested by S-13510b/c). The only live-screen id change (`loadHistoricalSession`) is finding 2.
- `0 kcal`: `_liveCaloriesLabel` (`workout_session_global_timer.dart:60–65`) returns `'${wrist.round()} kcal'` for `_wristKcal != null`, so a 0.0 wrist total renders `0 kcal` with no `~`; `_wristKcal` is a `double?` distinguished by null, not truthiness. No falsy collapse.

## Findings
1. [Minor] `lib/state/watch/watch_live_energy.dart:31–35` — D-13520 says the `at` must be "a parsable `at` (use `lib/core/sync_protocol/wire_timestamps.dart`)"; the wire shape is `YYYY-MM-DDTHH:MM:SS(.sss)Z` (`envelope.schema.json:55`, `wire_timestamps.dart` header). `_parseAt` accepts anything `DateTime.tryParse` + `isUtc` accept, which includes `2026-11-09 12:00:00Z` (space separator): a string the schemas refuse is folded into `latest`. What a maintainer sees: the receiver's own gate is laxer than the register the plan pins, so a future writer passing a hand-built frame would get the slack accepted here instead of the schema's refusal. No shipped writer can produce it (`utcIso` always writes `T…Z`), so behaviour on every real frame is identical. Fix: require the `T` separator in `_parseAt` (one condition). Guard: the existing `S-13504h an at without a UTC marker is ignored` (`test/watch_live_energy_test.dart`) — a space-separator case would pin the shape gate.
2. [Minor] `lib/features/session/workout_session_screen.dart:175,184–192` — `_wristKcal` is re-validated against the open session's id only when a wrist frame arrives or the screen mounts. The one library path that changes `currentSession` under a live screen state is `WatchSessionAdoptionBridge`'s `loadHistoricalSession` (`watch_session_adoption_bridge.dart:785`); until the wrist's next frame for that id (up to 5 s + first reading), the chip shows the previous session's total while the estimate beside it (`_liveKcal`) is already recomputed from the new session on each tick (`workout_session_global_timer.dart:32–39`). Fix: re-derive `_wristKcal` from `wristEnergy` inside `_tick`/`_computeLiveKcal` (two lines, the id check `_onWristEnergy` already performs). Guard: a screen test that swaps the session id without a new wrist frame and expects `—`.

## Assumption Log rulings
- **A-1** (5 s / 0.5 kcal throttle as the lead's default): **ratify** — implemented verbatim (`WatchSessionEngine.swift:1593–1597`) and pinned by `WatchEnergyLiveTests` S-13511 (+ `testS13511B/C` for the no-news repeat and the per-session reset).
- **A-2** (a new live message type is the least invasive carrier): **ratify** — the sender/engine, receiver/holder and validator lists all follow the existing live-family pattern; no existing live frame gained a field.
- **A-3** (cardio estimate is plan 137): **ratify** — this diff contains no MET/pace logic; the chip on the phone stays exactly the 134d estimate until a wrist frame lands.
- **A-4** (the 1 kcal First Reading is Health's genuine early total, device QA only): **ratify** — the code-side cause the plan named is removed (the wake + pull reads exist: `HealthKitSensorFeed.swift` `refreshActiveEnergy(from:)`, the pull loop, `HealthKitWorkoutStore.refreshHeartRate()`), the rest is device-only.
- **A-5** (architect phase skipped, exact seeds): **ratify** — the implementations match the decisions line by line; no decision was contradicted in the diff read.

## Docs delta
- `docs/modality_based_exercise_ui.md` sentence 1 (`The live figure is the watch's own number once the wrist has sent one (plan 135, no "~")…`) -> applied (:383; true, backed by `session_live_calories_test.dart` group `plan 135`)
- `docs/modality_based_exercise_ui.md` sentence 2 (`chip shows the wrist's running total as soon as an energy_live frame arrives…`) -> applied (:387; true, backed by S-13508/S-13509)
- `docs/state_management/watch_surface.md` ADDED `WatchLiveEnergy` -> applied (:559–570; every symbol named exists — `watch_live_energy.dart`, `WatchSyncGraph.liveEnergy`, `main.dart` wiring, `wristEnergy:` — and the claimed test exists)
- `docs/state_management/watch_sensors.md` ADDED `announceEnergy` -> applied (:294–303; symbols and both named Swift tests exist)
- `docs/watch_session_sync.md` ADDED `energy_live` -> applied (:567–578; includes the named Dart test, `S-13505`, and `testS13516EnergyLiveIsNeverDurable`)
- `docs/watch-app-setup-and-qa.md` ADDED `Live calories on the phone` -> applied (:802–811; the QA step as decided, no product-behaviour claim beyond the scenarios' assertions)
- Doc edits the table does not name: `docs/state_management/services_and_utils.md` (:92 was refreshed by 134d, not 135) — nothing stale found. No stale old wording (`always an estimate`) remains where the change implicates it.

## Scenario coverage
S-13501 -> `test/sync_protocol_fixtures_test.dart` (`gives every message type a schema and a valid fixture`, manifest-driven) and `SyncProtocolFixturesTests.swift` (`testEveryValidFixtureConforms`) | covered
S-13502 -> both the same walks' invalid groups with the manifest's `expectedCode`/`expectedReasonContains` rows (`fixtures/manifest.json:916+`) | covered
S-13503 -> `test/watch_live_energy_test.dart` · `S-13503 a valid frame sets latest` | covered
S-13504 -> same file · `S-13504a`–`S-13504h` (one arm per guard, plus the instant-shape arm) | covered
S-13505 -> same file · `S-13505 an older frame for the same session is ignored, another session replaces` (also pins the equal-`at` arm) | covered
S-13506 -> same file · `S-13506 an energy frame while a phone change is owed sends nothing back and leaves the mirror alone` (asserts no re-attempted send and an untouched mirror) | covered
S-13507 -> same file · `S-13507 an energy frame on the transport reaches the holder and gets no answer` | covered
S-13508 -> `test/session_live_calories_test.dart` · `S-13508 a wrist frame for the open session replaces the estimate` | covered
S-13509 -> same file · `S-13509 the chip stays at the wrist kcal while the clock ticks` | covered
S-13510 -> same file · `S-13510 a wrist kcal shows with no body weight, and only for the open session` (+ `S-13510b/c` for the initial read both ways) | covered
S-13511 -> `WatchEnergyLiveTests.swift` · `testS13511TheCadenceIsFirstThenHalfAKilocalorieInFiveSecondsThenAFall` (+ `B` no-news repeat, `C` new session id) including the per-frame validator pass | covered
S-13512 -> same file · `testS13512WithNoSessionEnergyIsAnnouncedIntoNothing` + `testS13512AEndedSessionCarriesNoMoreEnergyFrames` | covered
S-13513 -> same file · `testS13513TheFirstFrameNamesTheSessionAndTheInstant` | covered
S-13514 -> same file · `testS13514TheRecorderStoresAndAnnouncesEachCount` | covered
S-13515 -> `WatchSensorSourceSourceTests.swift:341–390` · `testS13515ThePullAndTheWakeReadTheEnergyTheBuilderHolds` (brace-checked bodies via `functionBody`) | covered
S-13516 -> `WatchEnergyLiveTests.swift` · `testS13516EnergyLiveIsNeverDurable` | covered
No gaps.
