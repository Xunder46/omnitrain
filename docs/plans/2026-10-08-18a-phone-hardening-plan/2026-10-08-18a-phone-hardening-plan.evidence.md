# Evidence — 18a: phone hardening (two crashes)

Implementers and the reviewer append here. One row per checklist item: command, result, and the raw
counts (pasted, not summarised). Baselines for this plan (measured 2026-10-08, pre-change):

| Check | Baseline |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (full suite) | 4061 passing, ~1 failure |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 passing, 0 failures |

**Baseline correction.** The first row's "~1 failure" is the `flutter test` *skip* marker, not a
failure: the raw summary line was `+4061 ~1: All tests passed!`. The full suite was green before this
phase, and the phase's own run ends in `All tests passed!` too.

## Phase 1 — the build-phase notify

| Item | Command | Result |
|---|---|---|
| S-150 / S-151 / S-152 red at base | `prove-red 1665f64 test test/session_screen_build_phase_notify_test.dart` | RED AT 1665f64 (exit 1), `+1 -3`: S-150 and S-152 fail `Expected: [SchedulerPhase:SchedulerPhase.postFrameCallbacks] / Actual: [SchedulerPhase:SchedulerPhase.persistentCallbacks]`; S-150 also `Expected: null / Actual: FlutterError:<setState() or markNeedsBuild() called during build.>` "thrown while dispatching notifications for WorkoutState"; S-151(a) fails the same phase assertion; S-151(b) passes at base by design — see the mutation row |
| S-150 / S-151 / S-152 green after | `test test/session_screen_build_phase_notify_test.dart` | `+4: All tests passed!` |
| R-2 (the routines site) red at base | `prove-red 1665f64 test test/my_routines_screen_build_phase_notify_test.dart` | RED AT 1665f64 (exit 1), `+0 -1`: `Expected: [SchedulerPhase:SchedulerPhase.postFrameCallbacks] / Actual: [SchedulerPhase:SchedulerPhase.persistentCallbacks]` |
| R-2 green after | `test test/my_routines_screen_build_phase_notify_test.dart` | `+1: All tests passed!` |
| `initstate_notify_contract_test` red at base | `prove-red 1665f64 test test/initstate_notify_contract_test.dart` | RED AT 1665f64 (exit 1), `+1 -1`, naming exactly the three real sites: `lib/features/routine/my_routines_screen.dart: initState -> loadRoutines()`; `lib/features/session/session_overview_screen.dart: initState -> _initializeSession -> createNewSession()` and `-> loadSessionData()`; `lib/features/session/workout_session_screen.dart: initState -> _loadExercises -> createNewSession()` and `-> loadSessionData()` |
| `initstate_notify_contract_test` green after | `test test/initstate_notify_contract_test.dart` | `+2: All tests passed!` |
| S-151(b) non-vacuous (negative guard) | mutation: `_RefusingInboxRepository`'s `throw StateError(...)` -> `return super.getWatchInboxEntriesForSession(watchSessionId);` | RED: `Expected: exactly one matching candidate / Actual: Found 0 widgets with text "Error Loading Session": []`. Original line restored exactly, then `test test/session_screen_build_phase_notify_test.dart` -> `+4: All tests passed!` |
| The three new files together | `test test/initstate_notify_contract_test.dart test/session_screen_build_phase_notify_test.dart test/my_routines_screen_build_phase_notify_test.dart` | `+7: All tests passed!` |
| The Done-Criteria regression trio | `test test/screen_widget_test.dart test/pr4_session_controls_test.dart test/exercise_detail_emphasis_tier_test.dart` | `+235: All tests passed!`, 0 failure lines |
| Full suite | `test` | `01:40 +4068 ~1: All tests passed!` (exit 0) — baseline was `+4061 ~1`; +7 are the three new files' tests, no regression. Re-run after the lint fix: `01:42 +4068 ~1: All tests passed!`, again exit 0 |
| `lint` | `lint` | `196 issues found. (ran in 3.2s)`, 0 errors, `lines that look like failures (0)` — identical to the baseline, and none in a file this phase touched. An intermediate run showed 198 with 2 `unnecessary_underscores` infos in the two new test files; both fixed (`(_, __)` -> `(_, _)`) and the lint re-run gives the 196 above |
| The item-6 audit: every checked site and its verdict | see "The item-6 audit" below | 3 real traps (all three fixed and guarded), 2 sites left as pure readers |

### The item-6 audit — every `initState` under `lib/features/**` that reaches a notifying state method

| Site | What its `initState` called | Verdict |
|---|---|---|
| `lib/features/session/workout_session_screen.dart` (`initState`) | `_loadExercises()` -> `createNewSession()` / `loadSessionData()` -> `SessionCore._setLoading` -> `notifyListeners()` (`session_core_io.dart:137`) | **real trap** — deferred to `addPostFrameCallback` (item 1); guarded by S-150 / S-151 |
| `lib/features/session/session_overview_screen.dart` (`initState`) | `_initializeSession()` -> the same two methods (`session_overview_screen.dart:60-62`) | **real trap** — deferred (item 5); guarded by S-152 |
| `lib/features/routine/my_routines_screen.dart` (`initState`) | `widget.routineState.loadRoutines()` -> `routine_state.dart:107-113` sets `_isLoading` and notifies before it reads | **real trap** — deferred (item 6); guarded by R-2 in `test/my_routines_screen_build_phase_notify_test.dart` |
| `lib/features/exercise_library/exercise_library_detail_screen.dart` (`initState`) | `_loadReference()` -> `ExerciseLibraryState` readers; that state notifies only after an `await`, i.e. after the build phase | left as is — no synchronous notify |
| `lib/features/profile/widgets/measurement_sparkline.dart` (`initState`) | `_loadEntries()` -> its own element's `setState` + repository/profile readers (pure pass-throughs) | left as is — marks no listener dirty mid-build |
| the sweep: `loadSessionData` / `createNewSession` / `resetSessionTimerStart` / `loadHistoricalSession` / `endSession` / `loadRoutines` across `lib/features/**/*.dart` | 25 hits in 8 files; every hit sits in an event handler, an async continuation or a post-frame callback — none in an `initState` | no other trap |
| the contract test's scan of every `initState` under `lib/features/**/*.dart` | all sites | only the three named above reach a notifying method; the scan is the mechanical half of this table |

**The plan's prove-red command is not the one that proves this phase.** `prove-red <ref> test
<file> -- lib/features/session/workout_session_screen.dart` copies the *carried* paths into the base
worktree, so it puts my fixed source back and never copies the new, untracked test file; `flutter
test` then fails to load it (`Failed to load … Does not exist.`), which the gateway itself labels "a
compile or load error … use a mutation instead". The proofs above carry the *test* file instead (a
plain file argument is carried over automatically) and leave every `lib/` source at `1665f64`. Phases
2–4 list the same command shape in their Done Criteria.

All three proofs were re-run against the final content of the test files (the lint fix and the added
rule line changed them after the first round): session file `+1 -3`, routines file `+0 -1`, contract
test `+1 -1` — each `RED AT 1665f64 (exit 1)`.

## Phase 2 — the summary guard

| Item | Command | Result |
|---|---|---|
| S-153 / S-154 red at base | `prove-red 15bab66 test test/session_summary_inverted_window_test.dart` | RED AT 15bab66 (exit 1), `+1 -1`: S-153 fails `ArgumentError: Invalid argument(s): 1791419191803`, stack `#0 int.clamp #1 SessionSummaryService.computeSessionRestTimeMs (session_summary_service.dart:33:42)` — byte for byte the owner's log line; S-154 passes at base by design (a negative guard) — see the mutation row |
| S-153 / S-154 green after | `test test/session_summary_inverted_window_test.dart` | `+2: All tests passed!` |
| S-153 non-vacuous (the `math.max` is the fix) | mutation: `windowEnd` -> `session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch` (the pre-fix form) | RED: the same `ArgumentError: Invalid argument(s): 1791419191803`, stack now at `session_summary_service.dart:35`. Original `math.max(windowStart, …)` restored exactly, then `test test/session_summary_inverted_window_test.dart` -> `+2: All tests passed!` |
| S-154 non-vacuous (the merge is still observed) | mutation: the merge condition `if (iv.$1 <= mergedEnd)` -> `if (false)` | RED: `Expected: <100000> / Actual: <130000>` (130000 = the three overlapping rests counted once each). Original line restored exactly, then -> `+2: All tests passed!` |
| Every existing suite whose name mentions the summary | `test test/session_summary_inverted_window_test.dart test/session_summary_distance_test.dart test/session_summary_effort_row_test.dart test/watch_session_edit_restore_summaries_test.dart test/watch_session_summary_integration_test.dart test/calendar_summary_screen_bugs_test.dart test/home_nutrition_summary_card_test.dart test/sensor_summaries_by_session_test.dart test/entry_identity_summary_test.dart` | `+87: All tests passed!`, 0 failure lines |
| Full suite | `test` | `01:41 +4070 ~1: All tests passed!` (exit 0) — the Phase-1 run ended `+4068 ~1`; the +2 are this file's tests, no regression |
| `lint` | `lint` | `196 issues found. (ran in 2.9s)`, 0 errors, `lines that look like failures (0)` — identical to the baseline; a search of the log for `session_summary_service|session_summary_inverted_window` finds no issue, so nothing this phase touched is named |
| the `hive_workout_repository` import invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` (run with the file-tool grep, same pattern and paths — the gateway has no grep check) | no matches; nothing under those four trees imports a concrete repository |
| Item 5 — the doc update | `docs/session_summary.md`, three places that stated the old rule | each updated to `max(startedAtMs, endedAtMs)` and to name `test/session_summary_inverted_window_test.dart` / `S-153` |
| The docs contract after the four doc edits | `test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — the page is ~23 KB against the 64 KiB ceiling and sits below the 52 KB warning band |
| the `.clamp(` audit: every session-window clamp and its verdict | see "The `.clamp(` audit" below | 50 `.clamp(` sites in 28 files under `lib/`; only `session_summary_service.dart:33-34` takes session-data bounds — that is the defect this phase fixes. Every other site is a constant pair, a list index/length, a layout metric or a single-value cap with a constant lower bound, so `lower > upper` is unreachable |

### The `.clamp(` audit — every `clamp` site under `lib/` and why its bounds cannot invert

The sweep: `grep -n "\.clamp("` over `lib/` -> 50 hits in 28 files (read with the file tools; run with
the file tools because the gateway has no grep check). Each hit was opened at its call site and
classified by where its bounds come from. `num.clamp` throws `ArgumentError(lower)` exactly when
`lower > upper`, so the only question per row is whether the upper bound can come out below the lower.

| Class | Sites (representative) | Why the bounds cannot invert |
|---|---|---|
| **session-data bounds — the only class that can invert** | `session_summary_service.dart:33-34` (the `DateTime`-derived `windowStart` / `windowEnd`) | **the defect**: with `endedAtMs < startedAtMs` the upper bound was the smaller one. Fixed by `math.max`, guarded by S-153 |
| constants, lower < upper by inspection | `0, 86400000`; `0, 99999`; `-200.0, 999.0`; `0.0, 1.0`; `1, 10`; `0.05, 0.95`; `0, 255`; `0, 999`; `0, 3600`; `kTextScaleMin, kTextScaleMax` | both bounds are literals or `const`s with the lower strictly below the upper; no input reaches them |
| list indices and lengths | `clamp(0, _exercises.length - 1)`; `clamp(0, _exercises.length)`; `clamp(0, exercises.length - 1)`; `clamp(1, _maxRows)` with `_maxRows = 3` | each index clamp sits behind an `isEmpty` guard on the same list, so its upper bound is `>= 0` at the call; `_maxRows` is the constant `3` |
| layout metrics | `clamp(0.0, maxScrollExtent)`; `clamp(0.5, 0.95)`; `clamp(0, size.width)`; `clamp(screenMargin, maxLabelLeft)` | `maxScrollExtent`, `size.width` and `maxLabelLeft` are framework/geometry non-negatives, and the last call is guarded by `maxLabelLeft <= screenMargin` |
| single-value caps (constant lower bound) | `(…).clamp(0, plannedDurationSecs * 2000 / 86400000)`; `clamp(0, effectiveTarget)`; `clamp(0, 999)` reps; `clamp(0.0, maxDistanceUnits)` with `maxDistanceUnits = 999.99` | the lower bound is the literal `0` (or `0.0`) and each upper bound is a duration, target, reps or unit cap that cannot go negative |

## Phase 3 — the writer rule

| Item | Command | Result |
|---|---|---|
| S-155 red at base | `prove-red 323fcfe test test/session_window_never_inverted_test.dart` | `RED AT 323fcfe (exit 1)`, `+3 -2`. Both failures are the guarded order, not a load error: the headline test fails `endedAtMs >= startedAtMs must hold for the stored row` (`Expected: a value greater than or equal to <1791428252523> / Actual: <1791428252518>` — the post-end reset moved the start 5 ms past the stored end) and the writer-table row fails `endSession (future start) stored an end (1791428252555) before its start (1791431852554)` |
| S-155 green after | `test test/session_window_never_inverted_test.dart` | `+5: All tests passed!` |
| The neighbouring suites that pin the old writers | `test test/pr4_session_controls_test.dart test/watch_session_edit_restore_summaries_test.dart` | `+19: All tests passed!` |
| Full suite | `test` | `02:09 +4075 ~1: All tests passed!` (exit 0) — baseline `+4070 ~1`; the +5 are the new file's tests, nothing else moved. Re-run on the final tree after the three doc clauses: `01:58 +4075 ~1: All tests passed!`, again exit 0 |
| The doc clauses (item 6's fallout) | `test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — the two edited docs stay under the indexing ceiling and keep every link and hex rule intact |
| `lint` | `lint` | `196 issues found. (ran in 2.9s)`, 0 errors, `lines that look like failures (0)` — identical to the baseline; searching the log for `session_core` / `session_window_never_inverted` finds nothing, so no file this phase touched carries a notice |
| The `endedAtMs:` writer sweep | `grep -n "endedAtMs\s*:"` over `lib/` with the file tools (the gateway has no grep check) | 16 sites in 9 files; the classification is in "The `endedAtMs:` writer sweep" below |
| The D-153 invariant grep | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches |

### The `endedAtMs:` writer sweep — every site under `lib/` and its rule (item 6)

| Site(s) | Class | Rule |
|---|---|---|
| `session_core_lifecycle.dart:23` `endSession` | **phone writer — fixed** | stores `math.max(_currentSession!.startedAtMs, now)` (item 2); guarded by S-155 |
| `session_core_lifecycle.dart:78` `resetSessionTimerStart` | **phone writer — fixed** | carries the stored value and now writes nothing at all when an end exists (item 1); guarded by S-155 |
| `session_core_lifecycle.dart:162` `updateSessionEndTime` | **phone writer — fixed** | stores `math.max(startedAtMs, startedAtMs + durationSecs * 1000)` (item 3); the pre-existing `durationSecs <= 0` early return makes a non-positive duration a no-op |
| `session_core_lifecycle.dart:125` `updateSessionNote`, `:198` `updateSessionFeeling`, `:232` `updateSessionRpe` | phone writers that carry the end | write `_currentSession!.endedAtMs` unchanged, so they cannot invert a row they were handed ordered |
| `hive_workout_repository.dart:953`, `mock_workout_repository.dart:437` (`updateSessionFeeling`) | repository carry-through | copy `existing.endedAtMs`; the same value in, the same value out, on both implementations |
| `watch_session_importer.dart:517` `_createSession` | **exempt (D-153)** | the wrist owns that clock: the phone stores the window the wire carries, so an inverted pair from a watch with a skewed clock is still written. D-152's summary guard keeps it from crashing the summary and D-154 repairs the stored row |
| `watch_session_importer.dart:1538`, `:1614`, `:1642` | wire-payload parse helpers (`_Entry` / `_End` / `_SetBlock`) | not session-row writers; they build the decoded payload the row is made from |
| `models.dart:232` (`TrainingSession.fromMap`) | deserialization | reads the stored column; a reader, not a writer |
| `session_summary_builder.dart:199` | `SessionSummary` view model | a reader over the session row |
| `mock/seed_data.dart:5643` | demo seed literal | one literal pair, ordered by construction (`startedAtMs < endedAtMs`) |

The sweep's plain conclusion: no phone-owned writer can store an end before its start any more, and a
watch-owned row still can — which is exactly the split D-153 describes.

**The end-before-start mechanism this fixes.** The wrist can end a session the phone adopted:
`WatchSessionAdoptionBridge.onLifecycle` (`lib/state/watch/watch_session_adoption_bridge.dart:646-660`)
calls `target.endSession()` on a `completed` lifecycle event, and that is the writer item 2 clamps. The
brief cites this file as `lib/core/services/…`; the real path is `lib/state/watch/…`, and both the
`completed` and the `abandoned` branches were read at that path.

### The guard mutations (item 3's clamp cannot be isolated — see the third row)

| Guard | Mutation | Verdict |
|---|---|---|
| `resetSessionTimerStart`'s early return (item 1) | delete `if (_currentSession!.endedAtMs != null) return;` | RED — the S-155 invariant assertion at test line 67 (`endedAtMs >= startedAtMs must hold for the stored row`); original restored exactly, then `+5: All tests passed!` |
| `endSession`'s clamp (item 2) | `math.max(_currentSession!.startedAtMs, now)` -> `now` | RED — the future-start writer-table row at test line 131 (`endSession (future start) stored an end … before its start …`); original restored exactly, then `+5: All tests passed!` |
| `updateSessionEndTime`'s clamp (item 3) | `math.max(started, started + durationSecs * 1000)` -> `started + durationSecs * 1000` | **GREEN — the mutant is unobservable, and the test says so.** The pre-existing `if (durationSecs <= 0) return;` (pinned by `test/state_test.dart:1576` and `test/session_edit_duration_test.dart`) makes every non-positive duration write nothing, and any admissible positive duration puts the candidate strictly above `startedAtMs` on both native and web ints, so no fixture can tell the two apart. The clamp stays because D-153 states the rule for every writer and because it survives the guard moving; removing the guard instead would turn those two existing suites red, which the plan did not predict. Also re-run as a whole-file check: `+5: All tests passed!` with the clamp gone |
| the control row's own non-vacuity (item 5) | `if (_currentSession!.endedAtMs != null) return;` followed by an unconditional `return;` | RED — the control row `resetSessionTimerStart still moves a running session start` at test line 180 (`Expected: a value greater than <1791428341525> / Actual: <1791428341525>`: a live session's start must still move); original restored exactly, then `+5: All tests passed!` |

Every mutation was reversed before the next step; the final `git-diff --stat` after all four is
`lib/state/workout/session_core.dart | 2 ++` and `lib/state/workout/session_core_lifecycle.dart | 14
++++++++++--`, i.e. the intended change and nothing else.

## Phase 4 — the repair migration

| Item | Command | Result |
|---|---|---|
| S-156 red at base | | _(pending)_ |
| S-156 green after | | _(pending)_ |
| Hive↔Mock parity on the repaired rows | | _(pending)_ |
| `docs/db_integration.md` reading: does it enumerate steps? | | _(pending)_ |

## Red → green table

| Scenario | Assertion that fails at the base | Test name |
|---|---|---|
| S-150 | the first `WorkoutState` notification lands in `SchedulerPhase.persistentCallbacks`, and `tester.takeException()` returns `FlutterError: setState() or markNeedsBuild() called during build.` | `S-150 the session screen notifies nobody while the frame builds` |
| S-151 | (a) the first frame is the spinner and the notification phase is `persistentCallbacks` (so this is a positive guard, not the negative one the scenario text predicted); (b) passes at base — proven non-vacuously by the mutation row above | `S-151 the spinner is the first frame and the seeded set follows`, `S-151 a first load that fails reports on screen and throws nothing` |
| S-152 | the same phase assertion with the overview screen pumped in the same frame as the session screen | `S-152 the overview screen pumped in the same frame notifies nobody` |
| S-153 | `computeSessionRestTimeMs` throws `ArgumentError(1791419191803)` from `int.clamp` at `session_summary_service.dart:33`, so the summary screen never renders | `S-153: an inverted session window contributes no rest and the summary still renders` |
| S-154 | (passes at base by design — a negative guard: an ordinary session's total is 100000 with or without the fix; its non-vacuity is proven by the merge mutation instead) | `S-154: an ordinary session merges overlapping rests once and keeps its total` |
| S-155 | `endedAtMs >= startedAtMs` fails after the post-end `resetSessionTimerStart()` (Actual `1791428252518` < Expected `1791428252523`: the reset moved the start 5 ms past the stored end), and `endSession` on a start ahead of the phone clock stores an end 1 h before its start (`1791428252555` < `1791431852554`) | `S-155: the reset after an end writes nothing and the stored window stays ordered`; `S-155 writer table — every phone-owned writer leaves an ordered window endSession clamps a start that lies ahead of the phone clock` |
| S-156 | the repaired `endedAtMs` still precedes `startedAtMs` | _(pending)_ |

## Reviewer findings

_(empty — the reviewer writes its table in `2026-10-08-18a-phone-hardening-plan.review.md` and links
the phase here)_
