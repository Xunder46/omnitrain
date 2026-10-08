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
| S-155 red at base | | _(pending)_ |
| S-155 green after | | _(pending)_ |
| The `endedAtMs:` writer sweep: every writer and its rule | | _(pending)_ |

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
| S-155 | `endedAtMs >= startedAtMs` fails after `resetSessionTimerStart()` | _(pending)_ |
| S-156 | the repaired `endedAtMs` still precedes `startedAtMs` | _(pending)_ |

## Reviewer findings

_(empty — the reviewer writes its table in `2026-10-08-18a-phone-hardening-plan.review.md` and links
the phase here)_
