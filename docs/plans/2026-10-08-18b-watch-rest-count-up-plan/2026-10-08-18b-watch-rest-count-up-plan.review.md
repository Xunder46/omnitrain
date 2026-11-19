# Review — 18b the watch's rest is a count-up

The verification agent fills this file. It is the reviewer's checklist, not the implementer's: the
implementer's baselines and pasted counts belong in
`2026-10-08-18b-watch-rest-count-up-plan.evidence.md`. Nothing here is run by the planner.

## Scope check

Reviewed range: `d79dd8c` (base) → `c9bed74` (phase 4); 4 commits, 49 changed files (`git-diff d79dd8c --name-only`).

| Check | Result |
|---|---|
| Diff versus `## Files Affected` / each phase's **Predicted Files** (out-of-bounds files are findings) | ⚠️ 4 unplanned files: `lib/watch/session/watch_records.dart` + `WatchRecords.swift` (their `toTimerJson` must omit a rest's plan — *required* by Phase 3's own assertions, recorded only in the evidence file, F5); `docs/modality_based_exercise_ui.md` (F5); `lib/watch/debug/watch_session_debug_surface.dart` + `test/watch_debug_surface_test.dart` (assigned by Phase 1's Assumption Log 4 and recorded in Phase 4's Assumption Log 2 — legitimate) |
| Every predicted file actually touched (untouched predictions are findings) | ⚠️ `docs/constants_reference.md` is listed in `## Files Affected` but untouched — correct, the plan's own Phase 4 item 8 classifies its one hit as a round timer (F5) |
| No file under `.github/agents/**`, `.github/copilot/**`, `.claude/**`, `CLAUDE.md`, `AGENTS.md` | ✅ none in the diff (the only `.github/`-adjacent writes are this plan folder's own `.md`/`.evidence.md`/`.review.md`) |

## Per-phase evidence table

| Phase | Checklist item | Evidence (command + pasted counts) | Verdict |
|---|---|---|---|
| 1 | `restSeconds` gone in both stacks | `prove-red d79dd8c test test/rest_is_count_up_contract_test.dart` → RED AT d79dd8c `+4 -3`, the failing scanner assertion naming `WatchLoggingState.swift`'s `restSeconds`; no `restSeconds` left in `lib/watch`, `lib/state/watch`, `watch/watchos/Sources` | ✅ |
| 1 | rest timer has no `plannedDurationMs` | both `startFollowOnTimer`s call `startTimer(WatchTimerKind.rest)` with no plan; S-160 assert `plannedDurationMs == nil` | ✅ |
| 1 | `WatchRestIsCountUpTests.swift` red at base, green now | `swift-test` 357/0. Not independently provable: the file does not exist at the base, so `prove-red` cannot compile it — Phase 1's Assumption Log 2's mutation proofs stand in, and the Dart twin's scan is verified red at base | ✅ (mutations, not prove-red) |
| 2 | `isResting` / `endRest()` / `log()` ends the rest | read both stacks: `isResting` = active session + non-stopped rest; `log()` ends a running rest before the follow-on timer (D-162) | ✅ |
| 2 | rest screen with exactly one control | `WatchRestView.swift` (one bordered-prominent Next, `TimelineView(.periodic(by: 1))`) and `lib/watch/logging/watch_rest_screen.dart` (one `FilledButton`, explicit `shape:`, `OmniTheme` radius/height tokens) | ✅ |
| 2 | `ContentView` branch (governor's build) | not built by any check: `swift-test` compiles the package only. Branch order read at `ContentView.swift:179-186` (owed rating → rest → active session → start). **Governor still owes the watchOS-simulator `xcodebuild`** | ⚠️ stated, unbuilt |
| 3 | both validators refuse a rest length | clause present in `SyncProtocolValidator.swift:209-222` and `message_validator.dart:309-322` — but it is reachable only for `timer_state`; a `session_snapshot` accepts a rest + plan (F2) | ⚠️ partial |
| 3 | fixtures additive; `PROTOCOL.md` row dated | new `fixtures/invalid/timer_state_rest_with_planned_duration.json` registered in `manifest.json`; the three reconciliation fixtures lost five rest plans; one `1 (amended) \| 2026-10-08` row | ✅ |
| 4 | conventions row verbatim | `docs/global_conventions.md:17` is the owner's sentence verbatim, naming the contract test and D-168 | ✅ |
| 4 | `watch_surface.md` shrank, still under 51.2 KB | the diff is 9 changed lines, net-negative (countdown prose removed). **Exact bytes unmeasurable in this run** — `wc`/`stat` are denied by policy; the trend is down, the ceiling is not numerically verified | ⚠️ unverified size |
| 4 | contract test's failure message names why | `_why(...)` in `test/rest_is_count_up_contract_test.dart` states the rule, the owner's words, `global_conventions.md`, D-160/164/168 | ✅ |
| 4 | residue sweep grep has no hit outside D-168's exclusions | evidence-file rows re-read; independently re-grepped `docs/` outside `plans/` for rest-countdown wording: clean; `restSeconds` in `lib/` is the routine prescription only (D-168) | ✅ |

## Scenario conformance (S-160 … S-168)

| Scenario | Test file | Fixture matches the plan's enumeration | Verdict |
|---|---|---|---|
| S-160 | `test/watch_logging_timers_test.dart`, `WatchLoggingTimersTests.swift` | ✅ rest from `10:00:00`, read at 0 s / 7 s | ✅ |
| S-161 | `test/watch_rest_surface_test.dart`, `WatchRestSurfaceTests.swift` | ✅ 4 minutes after the log instant, across a relaunch | ✅ |
| S-162 | same two | ✅ Next's `stoppedAt` is the tap instant; the next log does not move it | ✅ |
| S-163 | same two | ✅ a log while resting ends the rest | ✅ |
| S-164 | `test/watch_logging_timers_test.dart` (`S-164`), `WatchLoggingTimersTests.swift` | ❌ **the fixture has no plan**, so "nothing with `kind == .rest` at any instant" is proven only for a clean row; a stored rest row carrying a stale plan still yields a `rest` milestone (F1) | ❌ F1 |
| S-165 | `test/sync_protocol_fixtures_test.dart`, `SyncProtocolValidatorTests.swift` (4 cases) | ✅ three fixtures, both validators; the fixture set has no `session_snapshot` case, which is exactly F2's hole | ⚠️ F2 |
| S-166 | `test/rest_is_count_up_contract_test.dart` (7 cases), `WatchRestIsCountUpTests.swift` | ⚠️ Red at base verified (`+4 -3`, three guarded assertions). The shipped scan covers the five source roots only: no `docs/` root (S-166's own outcome predicts the doc wording is caught), no app-target root, and two literal spellings (F4) | ⚠️ F4 |
| S-167 | `test/watch_logging_timers_test.dart` (S-79 group), `test/watch_session_rest_timer_append_test.dart`, `WatchLoggingTimersTests.swift` | ✅ a snapshot clears the kinds its sender wrote and leaves the wrist's own | ✅ |
| S-168 | `test/rest_is_count_up_contract_test.dart` (`S-168`) | ✅ the routine prescription keeps `restSeconds` and stays out of the scan's roots | ✅ |

## Impact Check re-run

Every row of the plan's `## Existing-Functionality Impact` table: re-run its grep, confirm the named
dependents' tests are still green, and treat an unlisted reader as a finding. The `WorkoutRepository`
parity check does not apply to 18b (no repository change) — state that explicitly rather than leaving
it blank: **N/A — 18b changes no repository, no model and no SQL contract.**

| Row | Grep re-run | Dependent tests | Verdict |
|---|---|---|---|
| `restSeconds` readers | ✅ no hit outside the routine prescription (D-168) | reach the whole suite green | ✅ |
| `WatchTimerKind.rest` readers | ⚠️ the row names `WatchTimerHaptics` and states its effect as "only its `plannedDurationMs` goes" — that understates it: `poll` reads a *stale* row's plan and fires | green, but the effect claim is stale | ⚠️ F1 |
| `countdown` / `_countdown()` call sites | ✅ both read the round timer only | green | ✅ |
| `plannedDurationMs` on the timer shape | ✅ round/timed planners and the two `invalid/` fixtures only; the serializers omit a rest's plan | green | ✅ |
| `log()` callers | ✅ the logging surface, the debug surfaces, both test files | green | ✅ |
| `ContentView` branch chain | ✅ only the app target reads `loggingSurface`; no package test can reach it | n/a — built by the governor | ⚠️ stated, unbuilt |
| countdown prose in the docs | ✅ no stale rest-countdown prose survives outside `docs/plans/**` | `test/docs_indexing_contract_test.dart` green | ✅ |
| `TemplateEffort.restSeconds` (excluded, D-168) | ✅ untouched, still read by the routine prescription surfaces | green | ✅ |
| the phone's `EntryRest` write path (untouched) | ✅ no writer, reader, schema or repository change in the range | phone suites green | ✅ |

No unlisted reader was found on the touched surfaces. `watch/sync_protocol/PROTOCOL.md` is *not* covered by
`test/docs_indexing_contract_test.dart` (that test scans `docs/` only), so its 64 KiB-style ceiling is unguarded.

## Cross-stack agreement

| Behaviour | Swift package | Dart twin | Agree? |
|---|---|---|---|
| rest row has no plan | `startFollowOnTimer` with no plan | same | ✅ |
| count-up value at 0 s / 7 s / 240 s | S-161 tests | S-161 tests | ✅ |
| Next sets `stoppedAt`, returns to logging | S-162 | S-162 | ✅ |
| a log ends a running rest | S-163 | S-163 | ✅ |
| no milestone ever owed for a rest | ❌ fires for a stored/legacy rest row with a plan (`WatchTimerHaptics.swift:45-58`) | ❌ same (`watch_timer_haptics.dart:53-65`) | ❌ F1 |
| a `rest` timer with a plan is refused | ✅ for `timer_state`; ❌ for `session_snapshot` | ✅ for `timer_state`; ❌ for `session_snapshot` | ⚠️ F2 |

Negative guards (S-161, S-167, S-168) must state their mutation and show it fails the guard; a
negative guard without its mutation is a finding.

## Defects

Quantified reports only: count, examples, root-cause line (file:line). Each defect opens a Phase X.Y
sub-phase that must include a structural guard — a permanent test making that defect class impossible
to reintroduce.

| # | Severity | Count | Examples | Root cause | Remediation | Guard |
|---|---|---|---|---|---|---|
| F1 | blocker | 2 stacks × 1 path | the wrist buzzes once for a rest after Next when a pre-18b rest row with a 90 s plan is still stored | `WatchTimerHaptics.poll`/`watch_timer_haptics.dart poll` walk `WatchTimerKind.all` and fire on `remainingMs == 0`; `remainingMs` clamps to 0 for a row that carries a plan, and every appended copy keeps the plan (`WatchSessionEngine.swift:1598`, `watch_session_engine.dart:1461`) | skip `WatchTimerKind.rest` in both `poll`s (the R-13 wording), or refuse a plan on a rest row at the engine/store boundary | a test with a stored/legacy `rest` row carrying `plannedDurationMs`, asserting no `rest` milestone ever |
| F2 | blocker | 2 validators × 1 message type | a `session_snapshot` with `timers.rest.plannedDurationMs` is accepted and adopted (plan copied at `WatchSessionEngine.swift:733`) | the rest clause lives in the `timer_state`-only rejection branch; the snapshot branch has none, and `PROTOCOL.md:216-229` claims both validators enforce it without naming `timer_state` | add the clause to the snapshot branch of both validators (+ fixture), or scope the PROTOCOL sentence and R-15/D-164's wording to `timer_state` | a `session_snapshot` fixture carrying a rest + plan that both validators must refuse |
| F3 | major | 11 sites | `WatchFileStoreTests.swift:545` still asserts a rest's remaining time; `watch_session_engine_test.dart:309,352,1454`, `WatchSessionEngineTests.swift:194,224,952,1412` start a rest with a plan | Phase 3's fix converted the *incidental* rest plans and left the rest, but only two of them are about disposal; the others assert a rest's remaining/end, which is the model this PR retires | re-point the ones whose subject is remaining time at a round/hold timer (S-005's precedent); keep the disposal cases assert-only-stopped | extend the scan (or a focused test) so no test in `test/` or `Tests/` starts a rest with a plan |
| F4 | warning | 3 gaps | the scan has no `docs/` root, no `ios/OmniTrain Watch App` root, and matches only `restSeconds` + `rest…plannedDurationMs` within 3 lines | the scanner is a tripwire, narrower than S-166's stated outcome ("the 'countdown' rest wording in the docs … and fails") | widen the token regex (case-insensitive rest-length spellings), add the app-target root and the seven doc roots (minus `plans/`) | the widened scan itself |
| F5 | warning | 4 files | plan hygiene: `docs/modality_based_exercise_ui.md`, `watch_records.dart`/`WatchRecords.swift` unplanned; `docs/constants_reference.md` listed but untouched | `## Files Affected` and four Predicted Files lists were not updated as Phases 3/4 discovered work | add the four files to `## Files Affected` with one line each on why | n/a — bookkeeping |
| F6 | suggest | 2 | `lib/watch/logging/watch_rest_screen.dart` is mounted by nothing; `docs/rest_tracking.md:227` cites it as what the wrist runs | the twin exists for parity and tests, and `lib/watch/debug/watch_logging_debug_main.dart` has no surface switch (Phase 2's Assumption Log 1) | cite `WatchRestView.swift` alongside the twin, or note in the doc that the twin is the test/dev mirror | n/a |

## Assumption Log adjudication

| Entry | RATIFY (promote to D-x) / REVERT / escalate to `## Feedback` | Reason |
|---|---|---|
| Phase 1.1 base ref `HEAD` = `d79dd8c` | RATIFY | confirmed by `git-log`: `3cab789` sits directly on `d79dd8c` |
| Phase 1.2 deleting the Dart `WatchLoggingDefaults` | RATIFY | its only member was `restSeconds`; nothing references it (lint 196/0) |
| Phase 1.3 no doc in Phase 1 | RATIFY | Phase 4 owns those docs; none of Phase 1's commits touched one |
| Phase 1.4 survivors left to Phase 4 | RATIFY for the debug surface (Phase 4 fixed it); **REVERT** for the rest-remaining tests it also named — see F3 |
| Phase 1.5 two base tests changed subject | RATIFY | a rest can no longer be owed a haptic, so the case moved to a round timer; the guard survives |
| Phase 2.1 the Dart debug harness is not wired | RATIFY, escalate the doc wording | recorded and true; `docs/rest_tracking.md:227` should say the twin is the test/dev mirror (F6) |
| Phase 2.2 mutation proofs instead of `prove-red` | RATIFY | the symbols do not exist at the base; the brief prescribes the mutation form and names all three |
| Phase 2.3 the two stacks tick differently | RATIFY | neither ticker is the source of the time; both re-read the persisted row |
| Phase 2.4 `ContentView`'s branch order stated, not proved | RATIFY | `swift-test` compiles the package only; promote the "governor owes an `xcodebuild` on a watchOS simulator" sentence to a numbered decision so no future phase claims a green app build |
| Phase 3 FIX.1 S-005 moved from a rest to a round | RATIFY | the premise ("the phone's end moment reaches the wrist's rest") is gone; the cross-stack agreement it pinned survives |
| Phase 3 FIX.2 the fixtures that kept their plan | **REVERT (subset)** | the `advanceExercise` rationale covers only the disposal cases; the others (F3's list) assert a rest's remaining time, which retires with D-160 |
| Phase 3 FIX.3 the `session_snapshot` gap, deferred to "Phase 4/the owner" | **REVERT — escalate now** | Phase 4 did not do it and `## Feedback` was left empty, so the deferral never reached the owner; it is F2, and either the validators widen or `PROTOCOL.md:227` narrows |
| Phase 4.1 S-166's base-ref expectation was stale | RATIFY | the failure at `HEAD` was the debug surface; fixing it rather than exempting it matches "the rule has no debug exemption" |
| Phase 4.2 the debug test edited outside the Predicted Files | RATIFY | Phase 1's Assumption Log 4 assigned exactly that survivor; the mutation ran on the rule |
| Phase 4.3 the Swift guard re-worded only | RATIFY | `prove-red HEAD swift-test` would be GREEN AT for committed behaviour; nothing behavioural changed |
| Phase 4.4 `prove-red` takes files, not directories | RATIFY | correct reading of the check; adding a directory's files explicitly is the workaround if a per-file red is ever needed |
| Phase 4.5 identifier debt left (`RestTimerStrip`, `RestNotificationService`, …) | RATIFY as recorded debt | phone vocabulary, not a preset-length or countdown claim; renaming is its own PR — put it in `## Feedback` so it is not lost |
| Phase 4.6 the debug-surface "countdown" comment | RATIFY | it is the round timer's remaining time and the debug surface still renders it |

## Verdict

❌ **blocked** — one reachable rest alarm survives (F1: a stored/legacy rest row with a plan makes
`poll` fire a `rest` milestone on the wrist) and the wire's refusal does not hold for a
`session_snapshot` while `PROTOCOL.md` says both validators enforce it (F2); each fix is one small
change plus one guard. F3/F4 are warnings that should ride the same round; F5/F6 are bookkeeping.


---

# Code review 1 (18b)

Scope: the committed 18b commits `3cab789..c9bed74` (phase 1–4); plan folder
`docs/plans/2026-10-08-18b-watch-rest-count-up-plan/`. Findings are appended as they are found;
`F1`… with a severity of blocker / major / minor.

_(findings below — appended during the review)_

Commands run this round (each once, verbatim):

- `.github/copilot/scripts/macos/gateway.sh test` → `01:47 +4148 ~1: All tests passed!` (log `.work/gateway/test-20261008-110455-38730.log`)
- `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 357 tests, with 0 failures` (log `.work/gateway/swift-test-20261008-111005-44146.log`)
- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found.` / 0 errors, exit 1 as expected (log `.work/gateway/lint-20261008-111127-44878.log`)
- `.github/copilot/scripts/macos/gateway.sh prove-red d79dd8c test test/rest_is_count_up_contract_test.dart` → `RED AT d79dd8c (exit 1)`, `+4 -3` (log `.work/gateway/test-20261008-111007-44334.log`)

The handoff's counts are true: Dart `+4148 ~1`, Swift 357/0, analyze 196/0.

## Findings

**F1 — blocker — the rest alarm is not gone from every path; a stored rest row with a plan still fires one.**
`watch/watchos/Sources/WatchSessionEngine/WatchTimerHaptics.swift:45-58` · `lib/watch/logging/watch_timer_haptics.dart:53-65` — `poll` walks `WatchTimerKind.all`, which includes `rest`, and fires whenever `remainingMs(timer, now) == 0`; `remainingMs`/`TimerInstants` clamp to 0 when a row carries a plan (`watch/watchos/Sources/WatchSessionEngine/WatchTimerMath.swift:26-43`). Pre-18b rests were written with `plannedDurationMs: 90_000`, and **every appended copy keeps the plan** (`WatchSessionEngine.swift:1598`, `watch_session_engine.dart:1461`), so after an upgrade: the shell shows the rest screen for the stored row → Next → `endRest()` appends a stopped copy that still carries 90 s → the logging surface's 1 s ticker (`WatchLoggingModel.swift:47-56`, `poll()` at `:60`) polls → `remainingMs` is 0 because more than the stale plan has passed → one `rest` milestone is played on the wrist. That contradicts R-13/AC-14 ("No timer milestone is owed for a rest at any point"), the conventions row the PR itself adds, and the plan's Notes claim that a stale plan "is harmless and needs no migration" — harmless for rendering, false for haptics.
Fix: skip `WatchTimerKind.rest` in both `poll`s (R-13's own wording: no rest alert anywhere, whatever the row holds), or refuse a plan on a rest row at the engine/store boundary so no rest row can carry one at all. Guard: a test that stores a `rest` row with `plannedDurationMs` and asserts no milestone is ever owed — the fixture S-164 enumerates but does not build. → `@developer`

**F2 — blocker — the wire's refusal is `timer_state`-only, and `PROTOCOL.md` says it is not.**
`watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:209-222` · `lib/core/sync_protocol/message_validator.dart:309-322` — the clause sits in the kind-rejection branch, which only `timer_state` reaches; `session_snapshot` goes through the snapshot branch (`_snapshotRejections` / `snapshotRejections`), so `timers.rest.plannedDurationMs` inside a snapshot is accepted, and `adoptTimer` (`WatchSessionEngine.swift:733`, `watch_session_engine.dart` equivalent) then copies the plan into the wrist's own row — the data F1 shows is harmful. `watch/sync_protocol/PROTOCOL.md:216-229` (new normative paragraph, D-169) states the rule "is … enforced by both validators … which answer `semantic_violation` at `$.payload.timers.rest.plannedDurationMs`" without scoping it to `timer_state`, and D-164/R-15 say "both validators" unqualified. Phase 3 FIX's Assumption Log 3 found exactly this, deferred it to "Phase 4/the owner", and Phase 4 neither did it nor put it in `## Feedback`, so the deferral never reached the owner — no `session_snapshot` fixture carries the case either (S-165's set is `timer_state` only).
Fix: add the clause to the snapshot branch of both validators plus one snapshot fixture that must be refused; or narrow the `PROTOCOL.md` sentence and R-15/D-164's wording to a `timer_state` and record the narrower reading as a decision. Guard: the snapshot fixture asserted through both validators. → `@dba`

**F3 — warning — eleven test sites still teach that a rest has a length and a remaining time.**
`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift:545` (S-46 asserts a rest's remaining time from the 90 s plan at `:151`) · `test/watch_session_engine_test.dart:309,352,1454,1562` · `WatchSessionEngineTests.swift:194,224,952,1412` · `phone_manage_bridge_test.dart:361` — Phase 3 FIX's Assumption Log 2 left them because "converting them would change what they exercise (`advanceExercise` disposes a rest, not a round")", but that rationale covers only the disposal cases; the others assert "a rest's remaining time" verbatim, which is the model this PR retires, and two documents (`docs/state_management/watch_surface.md`, `docs/watch_session_sync.md`) had this very test's citation removed while the test kept teaching it.
Fix: re-point the remaining-time cases at a round or hold timer, as S-005 and S-78 were, and shrink the disposal cases to `state == stopped`; then guard with the widened scan (F4) rather than by inspection. → `@developer`

**F4 — warning — the S-166 scan is narrower than S-166's own expected outcome.**
`test/rest_is_count_up_contract_test.dart:29-35` — the roots are the five source trees: no `docs/` root, though the scenario predicts "the 'countdown' rest wording in the docs — and fails"; no `ios/OmniTrain Watch App` root, though that is where the branch that decides the whole surface lives; and the tokens are `restSeconds` plus a rest `plannedDurationMs` inside a 3-line window, so `kRestSeconds`, `rest_seconds`, `restLengthMs`, `defaultRestSeconds` or a plan passed through a variable slip through. Both halves are line-based, so a rest length restored in a shape the scanner does not spell is invisible.
Fix: make the token match case-insensitive over a small spelling set, add the app-target root and the seven docs the PR edited (minus `plans/`). → `@developer`

**F5 — warning — plan hygiene.** `docs/modality_based_exercise_ui.md` was edited (rest-countdown prose corrected — a correct edit) although no phase's Predicted Files or `## Files Affected` names it; `lib/watch/session/watch_records.dart` and `WatchRecords.swift` were changed, which Phase 3's own assertions *require* (the wire form must omit a rest's plan) but which only the evidence file records; and `docs/constants_reference.md` is listed in `## Files Affected` yet untouched, correctly, since its single hit is a round timer the plan's own item 8 exempts. Also the plan header still reads `Status: DRAFT — Next handoff: @developer (Phase 1)`, and Phase 4's progress line says "the six docs rewritten" where the phase's Predicted Files name seven and the diff shows eight. → the planner, in `## Feedback`.

**F6 — suggestion.** `lib/watch/logging/watch_rest_screen.dart` is mounted by no runtime harness (`lib/watch/debug/watch_logging_debug_main.dart` renders `WatchLoggingScreen` with no surface switch — Phase 2's Assumption Log 1), yet `docs/rest_tracking.md:227` cites it as the screen "the watch runs"; the shipped wrist screen is `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift`. Cite both, or say the Dart file is the twin. → `@developer`

## The brief's six questions

**Q1 — is the rule actually true now?** Yes on every path except one. Re-derived: `restSeconds` and the rest branch's `plannedDurationMs` are gone from both stacks; `startFollowOnTimer` starts a rest with no plan; `countdown`/`_countdown()` read the round timer only, so no rest "m:ss left" line exists anywhere; `log()` ends a running rest first; the rest screen's elapsed is derived from the persisted row, so nothing counts down; the serializers omit a rest's plan on the wire (so even a stale row cannot carry one to the phone); both validators refuse a rest with a plan **for `timer_state`**. The one surviving path is F1: a row written before this change keeps its plan locally and `poll` still reads it, so the wrist can buzz for a rest once. The failure is not in the rendering or the sync — it is in the one consumer nobody re-checked. **Also worth the owner's confirmation**: D-163 keeps the phone's "rest ping" as a count-up nudge while the conventions row says "no rest alarm anywhere, on any device". The PR's reading — the ping is a nudge about the phone's own open rest, not a timer or an alarm — is defensible and now documented in `docs/theme_and_settings.md`, but it is a judgement call the rule's own words do not settle. No other `rest`-shaped alert remains.

**Q2 — the rest screen.** One control, and only one: `WatchRestView.swift` (bordered-prominent Next, `TimelineView(.periodic(…, by: 1))`) and its Dart twin (one `FilledButton` with an explicit `shape:` and `OmniTheme.buttonPrimaryHeight`/`buttonBorderRadius`). The branch order is `owedRating` → `isResting` → active session → start (`ios/OmniTrain Watch App/ContentView.swift:179-186`), and its rebuild is driven by the callback the logging view fires after a successful log/Next (`WatchLoggingView.swift:186`, `:226`). No trap: End is not on the rest screen, so the session can only be ended after Next — deliberate, and the plan's Open question 1 records it as the owner's call. Empty ladder: `isResting` requires an active session and a non-stopped rest row, so a finished or stopped session falls through to the start surface. Relaunch and screen-off: the elapsed comes from the persisted `startedAt`, proven by S-161's four-minute relaunch case on both stacks. Answering "no" to the brief: the Dart twin screen is mounted by nothing (F6), and the only other rest reader on the wrist is `poll` (F1).

**Q3 — the wire.** The refusal is real but partial. `timer_state` is refused with a message naming the rule in both validators; a `session_snapshot` is **not** (F2) — its branch has no rest clause, so a snapshot's rest plan is accepted and adopted into the wrist's own row, and the new `PROTOCOL.md` paragraph overstates the enforcement. The schema conditional in `$defs.timer` is documentation, not enforcement: neither hand-written validator executes conditionals, and the contract test checks the conditional structurally rather than by running it — honest, and the version row says so. The stale-row round trip is right: a stored rest row with a plan still saves and restores locally without a crash, and its wire form omits the plan (asserted on both stacks). Fixtures are additive: one new `invalid/` fixture registered in the manifest, three reconciliation fixtures lost five rest plans, and no fixture asserts a length that is now refused.

**Q4 — tests and guards.** The count I ran: Dart `+4148 ~1` all passed, Swift 357/0. Mutations I could verify directly: the Dart contract test is RED at the base for its own reasons — `prove-red d79dd8c test test/rest_is_count_up_contract_test.dart` gives `+4 -3`, the three failing assertions naming the base `restSeconds`, the missing schema conditional and the missing validator clause. The S-005 and S-78 repairs keep their guards while dropping the false premise (the cross-stack disagreement they pin moved to a round timer, so the guard is intact). What the guards do **not** cover: S-164's fixture has no plan, so the legacy row F1 describes is untested; the behavioural guards S-161/162/163/164 cannot be `prove-red`'d at the base because the API does not exist there (the implementers' mutation proofs are the honest substitute, and they name each mutation); the scan's allow-list is a tripwire, not a proof (F4), and it is narrower than S-166's own stated outcome; and the Swift twin can only ever see `watch/watchos/Sources`, never the app target where the screen is chosen.

**Q5 — docs.** Every test a document cites by name exists verbatim, in both languages, and I found no stale rest-countdown prose in `docs/` outside `docs/plans/**`. `docs/state_management/watch_surface.md` shrank (9 changed lines, countdown prose removed), so the 51.2 KB ceiling holds by trend — exact bytes are unmeasurable here (`wc`/`stat` are denied). `docs/global_conventions.md:17` is the owner's sentence verbatim, first place a reader looks, and `docs/README.md`'s Rest Tracking row now says Hive-backed. One document is false: `watch/sync_protocol/PROTOCOL.md:227`'s blanket "enforced by both validators" (F2). One doc is guarded by nothing: `watch/sync_protocol/PROTOCOL.md` sits outside `test/docs_indexing_contract_test.dart`'s `docs/` root, so the size and hex-literal guards do not reach it.

**Q6 — plan hygiene.** The four phase rows are ticked, the commits are clean and each names its phase, and `18c` is recorded as planned and correctly unticked. Left open: the stale `DRAFT` status line, the empty `## Feedback` (I have filled it with a pointer), the two file-list gaps and the "six docs" miscount (F5), Phase 3 FIX's Assumption Log 3's deferral that reached nobody (F2), and Phase 3 FIX's Assumption Log 2's "left, because their assertion *is* a rest's remaining/end" (F3).

## Documentation checks

```
DOC FALSIFICATION: ✅ PASS (8 implicated) — docs/README.md, docs/global_conventions.md, docs/rest_tracking.md,
  docs/watch_session_sync.md, docs/state_management/watch_surface.md, docs/watch-app-setup-and-qa.md,
  docs/theme_and_settings.md, docs/modality_based_exercise_ui.md (every cited test name exists; no claim
  describes removed behaviour; the routine prescription's `restSeconds` claim still holds)
DOC FALSIFICATION: ❌ REJECT — watch/sync_protocol/PROTOCOL.md:227 — "enforced by both validators …
  at $.payload.timers.rest.plannedDurationMs" is false for a `session_snapshot`, whose branch has no rest
  clause → either add the clause to the snapshot branch of both validators, or scope the sentence to a
  `timer_state` (F2)
DOC STANDARD: 💡 borderline — docs/rest_tracking.md:228-229 — class 3 (control inventory): the sentence
  inventories the one control and what it triggers, immediately before the tests that verify exactly that
  → delete the sentence and keep the pointers
DOC STANDARD: ✅ PASS — otherwise: no numeric restated from a constant, no pasted code, no roadmap or
  unshipped-change wording, no arrow-chain walkthrough added
```

## Conventions

```
PASS: the rest rule itself (global_conventions.md:17) holds on every path but F1's legacy row; every
  applicable architecture rule for state/screens/components; the docs-trail rule (each phase's doc edits
  land in the same phase); tests placed by the repo's own convention (models/utils/state/screen files);
  explicit `shape:` + `OmniTheme` tokens on the one new Dart button.
FAIL: R-13 / AC-14 (no milestone is ever owed for a rest) — WatchTimerHaptics.swift:45-58 and
  watch_timer_haptics.dart:53-65 → skip `rest` in both polls, add the legacy-row guard → @developer
FAIL: R-15 / D-164 (both validators refuse a rest with a plan) for `session_snapshot` —
  SyncProtocolValidator.swift:209-222, message_validator.dart:309-322 → widen or narrow, and fix
  PROTOCOL.md:227 → @dba
N/A (design system, routing, theming rest of the checklist): no theme token, no route and no phone
  screen changed by this PR — the one new Dart button uses existing tokens.
```

## Routing

→ `@developer`: F1 (the poll guard + its test), F3 (move the remaining-time assertions to a round timer), F4 (widen the scan), F6 (cite the shipped screen).
→ `@dba`: F2 (the snapshot branch of both validators + a snapshot fixture), or the plan's one-line narrowing of `PROTOCOL.md:227` and R-15/D-164 if the owner prefers the narrower reading.
Same round, no re-review loop: every blocking finding has a one-line fix and a named guard, and the two warnings ride the same commit.

## Fix round 1

Every finding is answered below, one line each; the guards are named by the test that holds them, and
the mutations are pasted in the evidence file.

- **F1 — fixed, with the guard the finding asked for.** Both polls now skip `WatchTimerKind.rest`
  outright (the finding's first option: no rest alert anywhere, whatever the row holds), so the stale
  plan on a pre-18b row cannot fire one. Guard: `test/watch_logging_timers_test.dart:194` (group
  `S-160 / S-161 / S-164 the wrist's rest is a count-up`, test "S-164 a stored rest row with a stale
  plan owes no alert") and `WatchLoggingTimersTests.swift:152`
  (`testS164AStoredRestRowWithAStalePlanOwesNoAlert`). Proved RED at HEAD through the gateway:
  `prove-red HEAD test test/watch_logging_timers_test.dart` → `RED AT HEAD (exit 1)`, the failure
  naming the extra `WatchTimerMilestone(rest at …)`; `prove-red HEAD swift-test --filter
  WatchLoggingTimersTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`
  → `RED AT HEAD (exit 1)`, `Executed 27 tests, with 1 failure`.
- **F2 — fixed by widening, and `PROTOCOL.md:227` is now true as written.** The clause is a separate
  function (`_restLengthRejections` / `restLengthRejections`) called from the kind branch *and* the
  snapshot branch of both validators, so `$.payload.timers.rest.plannedDurationMs` inside a
  `session_snapshot` answers `semantic_violation` and the plan is never adopted into the wrist's own
  row. Guard: the new `watch/sync_protocol/fixtures/invalid/session_snapshot_rest_with_planned_duration.json`,
  registered in `manifest.json` and asserted through both validators — `test/sync_protocol_fixtures_test.dart`
  (manifest case + `S-165 the wire refuses a rest length`) and
  `SyncProtocolValidatorTests.swift:76 testS165ASnapshotThatCarriesARestPlanIsRefused`. Proved by
  mutation on both stacks: removing the snapshot call gives `+37 -1` / `+61 -2` on the Dart file and
  `Executed 5 tests, with 3 failures` on `SyncProtocolValidatorTests`; restored, `+88` green.
- **F3 — fixed at all eleven sites, and none was shrunk.** Every one of the eleven asserted a rest's
  remaining time or its plan, so each moved to `WatchTimerKind.round` (which still has a length) rather
  than being weakened: `test/watch_session_engine_test.dart:309,352,1454,1562`,
  `test/phone_manage_bridge_test.dart:361`, `WatchSessionEngineTests.swift:194,224,952,1412`,
  `WatchFileStoreTests.swift:151` and `:545`. No S-id or assertion message changed, so each site still
  guards what it guarded; `WatchFileStoreTests.swift:419` is outside the finding's list and stays.
  Result: `gateway.sh test test/watch_session_engine_test.dart test/phone_manage_bridge_test.dart` →
  `+67: All tests passed!`; `swift-test --filter WatchSessionEngineTests` → `Executed 359 tests, with 0
  failures`.
- **F4 — fixed: the scan is wider on both axes, and prose is held to the countdown wording.** The
  tokens are case-insensitive over a spelling set (`restSeconds`/`rest_seconds`/`REST_SECONDS`,
  `restLengthMs`, `restDurationMs`/`restDurationSeconds`, `defaultRestSeconds`/`defaultRestMs`,
  `kRestSeconds`/`kRestMs`), the roots now include `ios/OmniTrain Watch App` and the eight documents
  this change edited, and a `.md` line is a finding for countdown wording only — because the
  documents that state the rule and define the routine prescription must be able to name
  `restSeconds` in order to say it is never a timer (D-168). Guards: the two new self-tests in
  `test/rest_is_count_up_contract_test.dart` (`S-166 the scanner flags a stored rest length under any
  spelling`, `…the scan reaches the app target and the documents, and prose is held to the countdown
  wording`) plus the tree scan. Mutations: narrowing the spelling to `rest_?seconds` → `+2 -1`, the
  failing assertion naming `restLengthMs`; removing the prose allowance → `+4 -2`, the tree scan
  printing exactly the four rule-stating lines (`docs/global_conventions.md:17`,
  `docs/rest_tracking.md:12,21`, `docs/watch-app-setup-and-qa.md:490`); both restored, green.
  The finding said seven documents; the PR edited eight (`docs/modality_based_exercise_ui.md` is the
  eighth), and all eight are roots.
- **F5 — fixed.** The header is no longer `DRAFT` (`Status: Phases 1–4 complete … awaiting re-review`,
  next handoff `@code-reviewer`); `docs/modality_based_exercise_ui.md` is in `## Files Affected`;
  `lib/watch/session/watch_records.dart` and `WatchRecords.swift` are recorded there with the note
  that Phase 3's assertions require them; `docs/constants_reference.md` is out (untouched, and its one
  hit is a round timer the plan exempts); "the six docs rewritten" is now "the eight docs rewritten".
- **F6 — fixed.** `docs/rest_tracking.md` cites `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift`
  as the screen the wrist runs and names `lib/watch/logging/watch_rest_screen.dart` as its twin, which
  no runtime harness mounts; the control-inventory sentence is gone and the test pointers stay.
- **DOC FALSIFICATION — ✅ PASS (9 implicated).** `watch/sync_protocol/PROTOCOL.md:227` is true as
  written now that both branches refuse a rest plan; the other eight documents are unchanged and
  still true, and `docs/rest_tracking.md`'s new sentences name the tests that verify them.
- **DOC STANDARD — ✅ PASS.** The `docs/rest_tracking.md` control inventory is deleted (class 3); no
  new numeric restates a constant, no code is pasted, no roadmap wording, no arrow-chain walkthrough.
- **Left open for the owner (not a finding).** The phone's "rest ping" stays a count-up nudge while
  the conventions row says "no rest alarm anywhere, on any device"; the reading is the PR's and it is
  now the plan's Open question 7.


