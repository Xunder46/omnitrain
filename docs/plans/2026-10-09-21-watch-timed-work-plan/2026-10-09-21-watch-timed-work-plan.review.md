# Review 1 — plan 21 (timed work on the watch)

Base commit: `42ceda2`. Commits: `7fdafbb` (plan), `c843fcb` (1A+1B), `9aa6c08` (Phase 2), working tree (Phase 3).

Layers in scope: watch client — `watch/watchos/Sources/WatchSessionEngine/` (`WatchLoggingState`,
`WatchLoggingModel`, `WatchLoggingView`, `WatchMenu`, `WatchMenuView`), `watch/watchos/Tests/`, the
F-CAP fixture, `docs/` prose about the wrist surface.
Layers skipped: Dart `lib/data/models`, `lib/data/repositories`, `lib/state`, `lib/features`,
`lib/widgets`, `lib/core` (no file in them changed — `git-diff 42ceda2 --name-only`).

Diff vs Predicted Files: **conforms** — 19 paths, all inside the plan's predicted set;
`ios/OmniTrain Watch App/ContentView.swift` is absent, which the plan allows ("only if its call needs
to change").

Checks run (this review, real output):

| Check | Result |
|---|---|
| `gateway.sh swift-test` | **418 tests, 0 failures** |
| `gateway.sh test` (full phone suite) | **4226 passed, 1 skipped, 0 failed** — `+4226 ~1: All tests passed!` |
| `gateway.sh test test/docs_indexing_contract_test.dart` | **9/9 passed** (size band, link, hex, walkthrough, roadmap guards) |
| `gateway.sh prove-red 42ceda2 swift-test -- WatchTimedWorkTests.swift` | **RED, but by compile error** (26 errors: no member `startWork`, extra argument `roundPresetMs`) — proves nothing, see below |
| `gateway.sh lint` | not re-run by this review; no Dart file is in the diff, evidence records 196 issues = the plan's baseline |

## Findings

1. 🟡 WARNING — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:749-752` — the
   `value(of: WatchMetricKey.roundDuration) ?? 0` fallback in `roundWindow` is unreachable: its only
   caller is `metricPayload` (`:690`), itself called only from `log()` (`:666`) after the D-1304 guard
   (`:652-654`), so a `round` effort always has a non-stopped round row and `engine.timerFor(.round)`
   is never nil; and `round` has no `fields` row (`metricKeysByKind`), so `value(of:)` is nil even if
   the branch were reached. A dead branch that reads like a supported "no countdown" path and would
   silently write a zero-length window. **Fix:** delete the fallback (end the window at `loggedAt`
   both sides, or `assertionFailure`) → @developer.
2. 🟡 WARNING — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift:129-137` — `roundLine`
   and `singular` are the only *rule* this change puts in the view, and no test on this toolchain
   compiles that file's body; D-1316 moved `primaryTitle`/`workReadout` into the model for exactly
   this reason. `singular` drops a trailing "s", which is right for all five `roundsLabels` today
   (Periods/Intervals/Rounds) but is a silent no-op for any future label that does not end in one.
   **Fix:** move the label transform into `WatchLoggingModel` and assert `"Period 2"` in
   `WatchTimedWorkTests` → @developer.
3. 🟡 WARNING (record) — `…-plan.md:3` — `Status: SEEDED — governor seed written; the planner expands
   the phases` is now false: all five phases are Complete, the ledger runs to D-1316 and the register
   to S-1312. Repo convention is a close-out status (plan 20 / 20b read `CLOSED — …`). **Fix:** set the
   status line to the review outcome → @planner.
4. 💡 SUGGEST — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` — `isTimedWork &&
   !isWorkRunning` is spelled out in both `primaryTitle` and `primaryAction`; one private
   `isAwaitingStart` keeps the button's two halves from drifting apart → @developer.
5. 💡 SUGGEST (record) — `…-plan.md:257` says the migrated S-003 test "keeps every assertion", but
   `WatchLoggingSurfacesTests.swift:385` now asserts `roundNumber == 1` where it asserted 2. The new
   value is right under D-1303/D-1306 and S-1303 covers the second round, but the plan sentence should
   name the one altered assertion → @planner.
6. 💡 SUGGEST (standard) — `docs/watch-app-setup-and-qa.md:565-616` — the new step 6 is a numbered QA
   walkthrough (standard §3.1), the form the whole file already has; the plan (D-1312) directs the
   update and every claim in it names a test (§4.2 in spirit), so this is not a rejection — but the
   standard's §6 "exactly two" named exceptions does not cover this `_recordFile`, and a QA script
   cannot conform to §3.1 by construction. **Fix:** name `watch-app-setup-and-qa.md` in §6, or state
   that a human QA script is outside §3.1 → @planner.

No blocker found.

## 4a — Acceptance criteria

Every criterion located in code, none missing. The load-bearing ones and where they hold:
one Start/Log button (`WatchLoggingModel.primaryTitle`/`primaryAction`, rendered by
`WatchLoggingView.primaryButton`); no length/distance/rounds row or dial on a timed or drill surface
(`metricKeysByKind`/`targetsByKind`, `testS1303ATimedSurfaceHasNoLengthToDial`); the logged window is
Start→Log (`log()`'s `windowPayload`, S-1300); a period counts down from the wrist's preset and Log is
not a `+round` (`workRemainingSeconds`, `startFollowOnTimer`, S-1303/S-1304); the menu is inert while
an effort runs while **Finish** never is (`WatchMenuState.isLocked`, `WatchMenuView:87,94`); no wire or
schema change (`WatchTimerKind.all` already carried `elapsed`/`hold`).

## 4b — Scenario register

13 scenarios (S-1300…S-1312), each with a test that asserts its stated outcome:

- S-1300/1301/1302/1303/1304/1305/1306/1310/1311/1312 → `WatchTimedWorkTests` (10 tests, 418/0 run);
  S-1303 additionally pinned by `WatchCaptureContractTests.testS1303ATimedSurfaceHasNoLengthToDial`.
- S-1307 → `WatchMenuTests.testS1307…` (3 tests: elapsed locks, round countdown locks, a running rest
  does not).
- S-1308 (set unchanged) and S-1309 (wire accepts plan-less `elapsed`/`hold`) are declared guards, and
  they are real: the valid `timer_state` fixture carries plan-less `elapsed` and `hold` rows and
  `SyncProtocolValidatorTests.testS165ARestCarriesNoPlannedLengthAndStillConforms` asserts the whole
  envelope conforms; the Dart half reads the same fixture at
  `test/sync_protocol_fixtures_test.dart:595`; the set tests are green unchanged.

## 4c — Test run verification

Counts above are this review's own runs, not the handoff's. The handoff summary does carry pasted
counts (§8.2/§8.4/§9/§10/§11/§12.3) and a Docs section naming each implicated doc as updated or "no
update required". Not a bug fix, so no red-first requirement applies; the guards are the mutation
tables.

**Guard proof — the one structural gap.** `prove-red 42ceda2 swift-test` cannot prove any of these
guards: the new API does not exist at base, so the run is RED in the compiler (26 errors) — exactly
what the developer records in evidence §8.1 and §11.3, then substitutes with per-mutation tables:
1A's nine mutations (each recorded original → mutant → red verdict → exact restore), of which
mutation 8 *found an uncovered guard* and closed it with a new assertion in S-1303, plus Phase 2's
`guard !isLocked` removal (`3 tests, 5 failures`, discriminating — the rest test stayed green). That
is honest and is real evidence the tests bind to the code, but it is not mechanical: nothing fails
automatically if a later change makes these Swift guards vacuous. Recorded, not a finding against this
diff.

## 4d — Documentation falsification

Method: the changed files were derived from `git-diff`, then the three documents whose declared scope
covers `lib/watch/`/`watch/watchos/` were read (`docs/state_management/watch_surface.md:3-14` declares
that scope; `docs/watch-app-setup-and-qa.md` and the QA index carry no scope block, so rule (4)
implicates them). Because most documents in `docs/` carry no scope declaration, rule (4) implicates
the whole set; the rest were falsified by grep for the vocabulary this change moves — the wrist's
value rows, the length/distance/rounds dials, Start/Log, and the four renamed test names — plus the
`docs_indexing_contract_test.dart` guards. Residual risk of that method is stated rather than hidden.

`DOC FALSIFICATION: ✅ PASS (3 implicated by scope + the rest by rule (4)) — no false claim found.`
`watch_surface.md:429-446` is the only prose describing the changed surface and it was rewritten, each
claim naming a real test; the QA index row 21 says "built — Phases 1A–3; review pending", which is
accurate; no doc page names a renamed test (the old names survive only in this plan and its evidence,
as the migration register). No conflict between documents.

## 4e — Documentation standard

`DOC STANDARD: ⚠️ SCOPE — docs/watch-app-setup-and-qa.md:565-616 — class 1 (step-by-step user flow),
pre-existing file form, plan-directed, every claim test-backed → see finding 6, not a rejection.`
No other prohibited content added: no numeric value restated from a constant, no pasted code, no
control inventory, no roadmap or "not yet shipped" note in the three diffs.

## 4f — Conventions

`PASS (6):` persistence interface untouched; no platform branch added to shared code; dependencies
injected (the view takes its model, the model its state); no direct storage access from the view; the
engine stays the only owner of timer rows; docs point at tests rather than restating behaviour.
`N/A (grouped, 1):` Dart-side rules (models, repositories, state, screens, components, core, design
system) — no Dart file is in the diff. `FAIL: none.`

## 4g — Impact Check

The plan's `## Existing-Functionality Impact` rows were re-grepped: `startFollowOnTimer` still has its
single call site (`log()` `:683`), `metricPayload`/`roundWindow` are single-caller as the plan says, `WatchLoggingState.fields`
readers are all migrated (`WatchLoggingView` `ForEach`, `CaptureReplay.dial`, and the eight test
files), `WatchMenuView`'s Finish is still never disabled. Readers **not** listed by the plan were
searched for on the touched surfaces (`fields`, `roundWindow`, `startFollowOnTimer`,
`WatchTimerKind.elapsed`, `isLocked`): none found beyond the migrated set. One row-level correction:
the plan's `:257` sentence about S-003's assertions (finding 5). `IMPACT: 8 rows checked, 0 unlisted
readers.`

## Assumption Log adjudication

RATIFY: the 1A red-count deviation (37 names, not 25 — the extras are the same two files failing only
for D-1304/D-1305's two messages, and 1B-i's 39→15 arithmetic reconciles it; the final 418/0 is the
proof); `workRemainingSeconds` returning the preset before Start; S-1310 driven through a real
`timer_state` + snapshot; `CaptureReplay.dial` made `internal`; the fixture rest-id +2 shift; the
S-237 id shift (realism, not a guard — noted, now unguarded); the two renamed tests; the brief's
1-vs-2 failure miscount; the lock caption as a named constant; "the wrist's preset" wording in
`watch_surface.md`; both "no doc update required" entries (independently confirmed by grep).
Recommend promoting the red-count entry to a numbered decision. ESCALATE: none. REVERT: none.

## Fix checklist (one round, no re-review loop)

Cheap and mechanical, all non-blocking: findings 1, 2, 4 (`@developer`), findings 3, 5, 6
(`@planner`). Nothing here needs a second review round; the human may approve as-is.

