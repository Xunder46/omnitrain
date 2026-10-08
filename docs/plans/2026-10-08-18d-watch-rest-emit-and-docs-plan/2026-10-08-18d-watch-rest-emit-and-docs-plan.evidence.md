# Evidence — 18d: the watch emits its rests, and the totals and docs follow

Plan: `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`
Review findings live beside this file, in `…-plan.review.md`. This plan carries the wrist half of 18c's moved scope
(18c: `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/…`), and its baselines are 18c's, unchanged.

This file holds what a reader cannot get from the plan: the base-commit baselines, the pasted red evidence and the green
counts for every guard. Implementers append; the reviewer re-runs the commands and checks the numbers. **No claim of
success without a pasted count** — "it passes" is not evidence; `flutter test`'s `+N ~M` line, `swift test`'s
executed/failed counts and `flutter analyze`'s issue count are.

## Baselines at the base commit

Same numbers 18c recorded; 18d must hold or rise, never fall.

| Check | Command | Baseline |
|---|---|---|
| Flutter suites | `.github/copilot/scripts/macos/gateway.sh test` | +4181 passed, ~1 skipped |
| Watch package | `.github/copilot/scripts/macos/gateway.sh swift-test` | 376 executed, 0 failed |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing infos) |
| Watch app | `xcodebuild` for a watchOS simulator, `OmniTrain Watch App` | governor-run, once per PR |

A phase's Done Criteria are green only if its own suites pass **and** the analyzer's issue count has not risen above 196
without a stated reason.

## Red → green (fill in per phase; one row per guard)

| Phase | S-id / guard | Test (file · name) | Red evidence (paste) | Green (counts) |
|---|---|---|---|---|
| 1 | S-320, S-322, S-331, S-332, S-333, S-334, S-336 (Swift) | `WatchSessionEngineTests.swift`, `WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift` | the new tests run before the emitter — paste the failing names | |
| 1 | S-321 (Swift) | `WatchLoggingTimersTests.swift` (the pre-entry stop's instant) | | |
| 1 | S-339 (Swift) | `WatchFileStoreTests.swift` (the lookup survives a relaunch) | | |
| 1 | S-320 closed kind (Swift) | `WatchNutritionQuickLogTests.swift` · `testTheKindsTheWristCanEmitAreAClosedSet` | add `rest` to `rest` only — the test fails until it names the kind | |
| 1 | S-320, S-322, S-332, S-333, S-334, S-336 (Dart) | `test/watch_session_engine_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_rest_surface_test.dart` | `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_engine_test.dart -- lib/watch/session/watch_records.dart lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart` must **fail** (`prove-red` takes files, not directories) | |
| 1 | S-321 (Dart) | `test/watch_logging_timers_test.dart` | | |
| 1 | S-320 rest row + emission (Dart) | `test/watch_session_rest_timer_append_test.dart` | the same `prove-red` invocation with this test file substituted must **fail** | |
| 1 | S-335 parity | `test/watch_reconciliation_cross_stack_test.dart` + the same five-step fixture in `WatchSessionEngineTests.swift` | | |
| 1 | S-320 closed kind (Dart) | `test/watch_nutrition_quick_log_test.dart` · `the kinds the wrist can emit are a closed set` (`:1338`) | | |
| 2 | S-329 total | `test/watch_session_summary_integration_test.dart` (one imported fixture, one phone-counted control) | `.github/copilot/scripts/macos/gateway.sh prove-red <the commit 18c was built on> test test/watch_session_summary_integration_test.dart -- lib/watch/session/watch_records.dart lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart` must **fail** there — the `rest` kind does not exist at that ref, so the fixture cannot be built | |
| 2 | S-340 views | `test/unified_rest_overlay_test.dart` + `test/watch_rest_ping_test.dart` (Mock-first) | the same `prove-red` on `test/unified_rest_overlay_test.dart` (the imported row cannot exist before 18c) | |
| 2 | S-341 rest rule + docs size | `test/rest_is_count_up_contract_test.dart`, `test/docs_indexing_contract_test.dart` | the two doc size numbers: `watch_surface.md` before → after, `watch-app-setup-and-qa.md` before → after | |
| 2 | S-341 residue | the two greps in Phase 2 item 8 | paste both outputs | |

## Phase 1 fixture ledger (the scenarios' populations, in one place)

| Fixture | Session | Stored observations before | Clock values | Expected emission |
|---|---|---|---|---|
| S-320 | `s1`, `se1`/`'e1'` | none | `T0`, `T0`, `T0+70s` | one rest `T0→T0+70s`, after `entry-1` |
| S-321 | `s1`, `se1`/`'e1'` | A | `T0`, `T0`, `T0+45s`, `T0+45s` | one rest `T0→T0+45s`, after A; B after it |
| S-322 / S-331 | `s1`, `se1`/`'e1'` | A | `T0`, `T0`, `T0+30s` | one rest `T0→T0+30s`, after A |
| S-323 | `s1`, `se1` | none | `T0`, `T0` | none (`endedAt == startedAt`) |
| S-332 | `s1`, `se1` | A | `T0`, `T0`, `T0+70s`, `T0+70s` | one rest, then silence |
| S-333 | `s1`, `se1`, adopted rest | A | `T0`, `T0`, `T0+5s`, `T0+20s` | none (the stop came from the phone) |
| S-334 | `s1`, no effort row | none | `T0+5s`, `T0+5s`, `T0+40s` | none (no after-entry) |
| S-336 | `s1`, `se1`, adopted rest from `T0+8s` | A | `T0`, `T0`, `T0+10s`, `T0+40s` | one rest `T0+8s→T0+40s`, after A |
| S-339 | `s1`, fresh engine over the same store | A (persisted) | `T0`, `T0`, `T0+40s` | one rest `T0→T0+40s`, after A |
| S-335 | `s1`, three logged sets | A, then B, then C | `T0`, `T0`, `T0+45s`, `T0+45s`, `T0+60s`, `T0+60s`, `T0+90s`, `T0+90s`, `T0+120s` | three rests: 45 s, 15 s, 30 s — the arithmetic is in S-335 |

## Reproducing the planner's verification answers

| Answer | Command |
|---|---|
| V-1 the finish path stops nothing (`WatchSessionEngine.swift` `transitionTo` `:1071`, `finishSession` `:340`, `abandonSession` `:349`, `captureSessionEnd` `:1381`; Dart `_transitionTo` `:1148`, `:341`/`:347`) | `grep -n "transitionTo\|captureSessionEnd\|stopTimer" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` |
| V-2 the lookup is positional, on the store's `sequence` order (D-221) | `grep -n "sequence" watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift` (`WatchObservationRecord` `:318`) + `stopTimer` `:1569` |
| V-3 the log's pre-entry stop uses the log's own instant, before the entry is appended (D-223) | `grep -n "isResting\|await endRest()\|appendObservation" watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (`:589`) and `grep -n "isResting\|endRest()\|Future<void> log" lib/watch/logging/watch_logging_state.dart` (`log` `:607`, the stop `:629`; `endRest` `:197`) |
| V-4 the emission path already stores-then-emits and skips a stored id | `grep -n "appendObservation\|storedObservations\|_emittedMessageIds" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift lib/watch/session/watch_session_engine.dart` (Swift `:1167`/`:1225`; Dart `:1236`/`:1288`, `:1314`) |
| V-5 the twin has no `session_end` observation **and no `efforts` list** (Phase 1 adds it) | `grep -n "enum WatchObservationKind" -A 22 lib/watch/session/watch_records.dart` (`:58-68`; `grep -n efforts lib/watch/session/watch_records.dart` finds only the comment at `:644`) vs `WatchRecords.swift` (`:50-77`, `efforts` `:76`) |
| V-6 both stacks pin the kind list | `grep -n "closed set\|all ==\|unorderedEquals" watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift test/watch_nutrition_quick_log_test.dart` (`:583`, `:1338`) |
| D-220 the rest timer row carries its own start | `grep -n "func timerRowFrom\|stoppedAt\|startedAt" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (`stopTimer` `:1569`, `timerRowFrom`) |
| D-224 the timer frame's id comes from the row's `recordId` | `grep -n "messageId(for:\|appendTimer" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (`:1776`, `:1574`) |

## Environment notes that decide how a phase is run

- `flutter test` (full suite) takes minutes: run it with the gateway's 900 s timeout, and run widget tests Mock-first.
  A widget test that opens the Hive harness or awaits a real `Future.delayed` inside `testWidgets` hangs forever at ~0%
  CPU (FakeAsync never advances real time); seed Hive in `setUp` and keep persisting taps Mock-only.
- A test file whose Mock group is red can leave its Hive group hanging: fix the red group rather than re-running the file.
- `flutter analyze` exits non-zero while the repo carries pre-existing info notices — compare the count with 196.
- `swift test --package-path watch/watchos` compiles the watch package; the watch app target needs `xcodebuild` for a
  watchOS simulator, which only the governor runs. The Swift side has no `prove-red` gate, so Phase 1's Swift red evidence
  is the pasted failing-test list from the red run before the emitter lands.
- Between 18c's merge and Phase 1 there is no wrist emission at all (the phone's writer is idle): a correct, expected
  intermediate state. After Phase 1 the wrist emits; the phone is already able to write it, so there is no window in which
  the wrist re-offers an unsettled row.
- Two facts the planner corrected on its final read (A-7): the Dart twin has no `efforts` list, so Phase 1 adds one
  (`lib/watch/session/watch_records.dart:58-68`); and `prove-red` names source files after `--`, not directories — every
  row above spells the full invocation for that reason.
