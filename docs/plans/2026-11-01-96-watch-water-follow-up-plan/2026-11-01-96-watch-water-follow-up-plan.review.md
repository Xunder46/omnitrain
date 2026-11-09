# Review: plan 96, PR 94c (watch water follow-up) · phases 1–2 · 2144d42a..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: swift 1191/0, flutter TZ=UTC +6024 ~2 (governor ran; see Checks run)
Diff vs Predicted Files: conforms, outside: `docs/plans/2026-11-01-94-watch-water-logging-plan/2026-11-01-94-watch-water-logging-plan.md` (+1 series-index row for 94c, finding 1)

## Findings

1. [Minor · mechanical] `docs/plans/2026-11-01-94-watch-water-logging-plan/2026-11-01-94-watch-water-logging-plan.md:19` — the diff adds a 94c row to plan 94's series table, but that file is in neither phase's Predicted Files list, so a future scope check counts it as out of bounds. The row itself is true (94c, depends on 94b, points at this plan). Fix: the planner adds the file to this plan's Predicted Files (or records the index row as sanctioned plan maintenance). Guard: none needed (plan text, not code).
2. [Minor · design] `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:16-18` — the header now says "data is dropped only through `pruneConfirmed()` and the launch's `pruneWaterTaps(loggedBefore:)`, both gated on the phone's receipt". The engine also drops through `pruneSensorSamples`, `pruneExerciseBatches`, `pruneBests` and `pruneWater`, which are gated on the session or the newest copy, not a receipt; the store header (WatchSessionStore.swift:10-18) lists all six. The sentence was already partial before this diff ("only through `pruneConfirmed()`"), and the plan's Phase 2 step 4 prescribed exactly this edit, so the implementer followed the plan. Fix (one line): "data is dropped only through the store's prunes — `WatchSessionStore.swift`'s header lists all six". Guard: none (comment text; the wording scan does not cover it).

No Blocker, no Major. Every behaviour claim I checked against the code holds; every test name the docs cite exists.

## Answers to the brief's five questions

1. **D-40/D-41/D-42 — yes.** `WatchWaterState.snapshot` (WatchWater.swift:222-241) reads the clock once (`let now = clock()`), the held frame once, and the tap list once (`let taps = todaysTaps(now)`, one `tapLog()` call); `glasses`/`canAdd`/`canRemove` are one-line delegates to a fresh snapshot (l.248-255) and `press(_:)` decides on one `let current = snapshot` (l.265-271). `todaysTaps` (l.293-310) filters on `record.sessionId` against `sessionIds(on: now)` *before* `parseLoggedAt`, so a non-candidate is never parsed; `sessionIds` (l.315-330) walks UTC midnights across `calendar.dateInterval(of: .day)` (A-1) and returns nil (no filter) when the calendar gives no interval. `WatchWaterBar` binds `let snapshot = model.snapshot` as the first statement inside `TimelineView(.everyMinute)` (WatchNutritionView.swift:188) and all four controls read `snapshot.`; grep over Sources and `ios/OmniTrain Watch App` finds zero `model.glasses/canAdd/canRemove/spokenCount` and no other reader of the state's accessors. `WatchWaterModel` declares only `snapshot` and `press`.
2. **D-43/D-44 — yes.** One row rule for both stores: the free `confirmedWaterTapIds(in:loggedBefore:)` (WatchSessionStore.swift:169-183) requires kind `waterGlass`, `confirmedAt != nil` (a receipt), a parseable `loggedAt`, and `loggedAt < cutoff` (strict). InMemory feeds it `readAll().observations`, which folds confirmations (WatchSessionStore.swift:283); the file store folds with the same `applyConfirmations` (FileWatchSessionStore.swift:312-317). Non-observation rows and confirmation rows are never removed by either store's filter; an unparseable `loggedAt` fails the guard and stays. The file store compacts only when `!dropped.isEmpty` (l.326-328) and writes nothing otherwise (M12 red). `WatchWaterState.restore()` calls `engine.pruneWaterTaps(loggedBefore: clock() − retention)` inside `gate.exclusive` and before `store.readAll().water` (WatchWater.swift:105-109); S-94b-25a enforces exactly one caller, in `restore()`, and M13 shows a second caller goes red. The engine trims memory and lens maps through `trimPrunedObservations`, shared with `pruneConfirmed` (WatchSessionEngine.swift:2020-2040; M10 red).
3. **Fixtures — conform; no scenario on a trivial fixture.** S-94c-1 seeds H (asserts n == 2920) plus today's 4 taps and counts five reads (snapshot, glasses, canAdd, canRemove, model.snapshot), each `reads == 1`, `storeReads == 0`, `parses ≤ 12`. S-94c-2 seeds p1..p9 exactly as tabulated plus 300 distractors and runs all five calendars with the plan's glasses and parse caps. S-94c-3 seeds H + 500 adds at 1 s steps and checks both presses store nothing. S-94c-4 is empty by the plan's own specification. S-94c-10 builds all ten rows on both stores (s-1 logged at 2026-10-20T08:00Z per A-5, so the kind-ignored mutant bites), asserts the dropped set, store order, food/set survival, confirmation count, unconfirmed ids, count 5 and one `onWaterChanged`. S-94c-11 covers (a) byte-identical relaunch, (b) torn tail + no-write prune, (c) the 11-04 launch dropping {w-3, w-4, w-7}. S-94c-12 runs UTC+3 / UTC−10 / UTC+14 with A, B, C and the frame. S-94b-18a moves the straggler to t0+5 with the true/false/false/false sequence. S-94b-25a and S-94c-6 are the prescribed source/scan guards.
4. **Docs — no false claim found.** `watch_reference_data.md:322-331`, `watch_sensors.md:427-432` and `watch_surface.md:759-762` state the D-43 rule in words and cite `WatchWaterPruneTests.testS94c10TheLaunchDropsOnlyOldConfirmedTapsInMemory`/`…OnFile` and `WatchWaterBarSourceTests.testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps` — all exist; `WatchWaterLimits.confirmedTapRetention` exists (WatchWater.swift:39-47); `watch_surface_wrist.md:258` and `watch_reference_data.md:316` cite `testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`, whose name D-46 kept. Residue greps over `docs/` (plans excluded) and `watch/watchos`: no `TapsAreNeverPruned`, no `five ways`, no `Four prunes`, no stale "never pruned" about taps (the only "never pruned" left in Sources is WatchSessionStore.swift:35 about sensor samples, true and pre-existing); the only `D-37` hits in `watch/watchos` both say "supersedes D-37". Sizes per the evidence: +354 / +192 / −20 B, within D-47's budgets; `docs_indexing_contract_test` (the 52,429 B line) passed.
5. **Diff vs Predicted Files.** Both directions conform for every Swift file, the Dart test and the three docs; the plan and evidence files are new/untracked as predicted. The one extra file is finding 1. New names in `watch/watchos/Sources`: `pruneWaterTaps`, `pruneWaterTapsLocked`, `confirmedWaterTapIds`, `trimPrunedObservations`, `sessionIds(on:)`, type `WatchWaterSnapshot` — none starts with a verb S-004 bans; S-004's allowed set gains `pruneWaterTaps` with the "sixth" comment citing D-43/D-44 (WatchSessionEngineTests.swift:323-348).

## Assumption Log rulings

- A-1 — **ratify.** `sessionIds(on:)` walks UTC midnights across the day interval; exact for any day length, and S-94c-2 exercises UTC+3, UTC+14, UTC−12, a 25 h DST day and a +5:45 zone, including taps exactly at local midnight and 1 s either side.
- A-2 — **ratify.** The public init is a convenience init passing the defaults; `ContentView.swift:181` still calls `WatchWaterState(engine:store:)` and S-94b-23 passes unedited.
- A-3 — **ratify.** `press(_:)`'s post-store check stays a direct engine read; S-94c-3 counts per snapshot only and passes.
- A-4 — **ratify.** One row rule in `confirmedWaterTapIds` for both stores; `trimPrunedObservations` shared with `pruneConfirmed`; M9 (kind ignored) and M10 (memory not trimmed) are red on both stores.
- A-5 — **ratify.** s-1 is logged at 2026-10-20T08:00Z so M9 drops it too; the file-store launch is a fresh store over the same directory.

## Scenario coverage

- S-94c-1 → `WatchWaterSnapshotTests.testS94c1OneTapLogReadAndCandidateOnlyParsesOn2924Taps` (M1, M2 red)
- S-94c-2 → `WatchWaterSnapshotTests.testS94c2TheFilterIsExactAcrossZonesDstAndLocalMidnight` (M1 red)
- S-94c-3 → `WatchWaterSnapshotTests.testS94c3TheCapHoldsWithALongHistory` (M1 red)
- S-94c-4 → `WatchWaterSnapshotTests.testS94c4AnEmptyStore`
- S-94c-5 → `WatchWaterBarSourceTests.testS94c5TheBarReadsOneSnapshotPerRedraw` (M3, M4 red)
- S-94c-6 → `test/watch_logging_surfaces_test.dart` S-901 list gains `WatchWater.swift` (M6, M6b red)
- S-94c-10 → `WatchWaterPruneTests.testS94c10TheLaunchDropsOnlyOldConfirmedTapsInMemory` / `…OnFile` + `testS94c10TheRetentionOutlastsTheLongestLocalDayByADay` (M7-M11 red)
- S-94c-11 → `WatchWaterPruneTests.testS94c11RelaunchAfterPruning` (M12 red)
- S-94c-12 → `WatchWaterPruneTests.testS94c12ATimeZoneChangeAcrossARelaunch`
- S-94b-18a → `WatchWaterSyncTests.testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply` (M5 red)
- S-94b-25a → `WatchWaterBarSourceTests.testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps` (M13 red)

No scenario without a test that would fail without the change.

## Checks run

- `gateway.sh git-diff --stat 2144d42a…` and the full diff, read file by file, once each (26 files; the other session's files — workout state, adoption bridge, `lib/core/utils/macro_*`, `food_helpers.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_merge_test.dart`, `scripts/*.sh`, `workout_state.md` — ignored per the brief).
- Greps (read-only file tools): accessor readers over `watch/watchos/Sources` and `ios/OmniTrain Watch App`; `readAll`'s confirmation fold; residue terms over `docs/` and `watch/watchos`; cited test names.
- No mutation run (the brief forbids it; the implementer's M1-M13 records are in the evidence and the governor runs his own pass).

## Checks not run

- `swift test`, `flutter test`, the three Dart contract tests, `xcodebuild` of the watch target: the brief states the governor re-ran them (swift 1191/0; flutter TZ=UTC +6024 ~2; contracts +87 pass; build SUCCEEDED after Phase 1). Counts pasted from the brief and the evidence file, not re-run here.
- Doc byte sizes not re-measured (no `wc` outside the gateway; the sizes above are the evidence's, and the enforcing `docs_indexing_contract_test` passed).
