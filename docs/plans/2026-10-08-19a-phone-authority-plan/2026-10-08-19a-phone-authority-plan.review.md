# Review — 19a, the phone is the authority for the shared session

Companion to `2026-10-08-19a-phone-authority-plan.md` and its `.evidence.md`. The code reviewer
fills this file; the verdict line is what the governor reads.

Scope checked against `.github/copilot/pr-scope-budget.md`: one track's worth of production code
plus the sync contract; four phases (the seeded shape) against the budget's soft "more than
three" threshold — the governor measures, the planner keeps the seeded outline. Hard limits
(>800 lines, >5 phases, >1500 production lines) are not approached.

## 1. Diff versus Predicted Files

| Phase | Predicted files | Touched | Out of bounds | Untouched but predicted |
| --- | --- | --- | --- | --- |
| 1 | 4 production (2 Dart, 2 Swift) + 3 test files | | | |
| 2 | 3 `lib/state/watch/` files + 3 test files | | | |
| 3 | 1 screen file + 3 test files | | | |
| 4 | 4 doc files | | | |

A file outside the list, or a predicted file untouched without an Assumption Log entry, is a
finding. `lib/state/watch/watch_session_adoption_bridge.dart`, the wrist's engine and
`workout_session_finish.dart` are read-only surfaces this plan expects to find unchanged except
where Phase 3's item 5 says otherwise.

## 2. Ledger conformance

| Entry | Check (the mechanical question) | Result |
| --- | --- | --- |
| D-170 (supersedes D-10) | no feature page still states a both-hold-a-session rule older than D-170 | |
| D-171 | `createSession` refuses on both stacks, in both engines | |
| D-172 | one pass sends `abandoned(W)` then P's snapshot; the wrist ends on P | |
| D-173 | the phone's importer ignores an end for a session it does not hold (mutation reddens S-173) | |
| D-174 | the screen follows the end and shows the rating without a second prompt | |
| D-175 | the contract amendment is additive, dated, and changes no fixture | |
| D-176 | the predicate is `sessionId != null && sessionId != composedId && sessionId != placeholder`; the snapshot is sent even on an unchanged baseline; one reset per pass | |
| D-177 | the refusal's exit shape and the absorb, identical for `exercises: []` and a non-empty ladder | |
| D-178 | exactly two triggers (`_pushOnce`, `WatchSyncGraph.sync()`), no timer, no queue | |
| D-179 | the listener ignores foreign ids, `_isFinishingSession`, `editMode` and post-leave; leaves once | |
| D-180 | no rating prompt is owed for a phone-sent abandoned | |
| D-181 | 17b's D-95/S-115 superseded by record; the rest-timer line at `docs/watch_session_sync.md:497` untouched | |

Seeded entries D-170 … D-175 and S-170 … S-175 must appear word for word as seeded; any edit
to them is a finding.

## 3. Scenario conformance (S-170 … S-185)

For each scenario: the fixture exists as enumerated, the test name carries the S-id, and the
scenario is either red at base (`prove-red`) or paired with a mutation that makes it red.

| Scenario | Home | Fixture as enumerated | Red-at-base or mutation | Verdict |
| --- | --- | --- | --- | --- |
| S-170, S-171 (seeded) | Phase 1 suites | | | |
| S-172, S-173, S-174, S-175 (seeded) | Phases 2–3 | | | |
| S-176, S-177, S-178 | Phase 1 | | | |
| S-180, S-181, S-182, S-183 | Phase 2 | | | |
| S-184, S-185 | Phase 3 | | | |

AC coverage: AC-1 → S-170/S-171/S-176/S-177/S-178; AC-2 → S-172/S-175/S-180/S-181/S-182;
AC-3 → S-173/S-174/S-183; AC-4 → the Phase 4 doc table.

## 4. Impact Check, re-run

Each row of the plan's Impact table names a grep. Re-run all of them and compare with the diff.

| Surface | Grep re-run | New readers found | Verdict |
| --- | --- | --- | --- |
| `createSession` callers | | | |
| phone-sent lifecycle importers | | | |
| `WatchSyncGraph.sync()` callers | | | |
| `_pushOnce` and the push baseline | | | |
| `endSession` / `discardCurrentSession` readers | | | |
| docs consumers of the superseded rule | | | |
| the wrist's prompt queue | | | |
| S-109's `graph.sync()` cases | | | |

An unlisted reader is a finding, not a shrug. Every dependent named in the table must have its
own suite green (S-109 A/B/C, S-5, S-70 … S-84, S-73, S-78, S-81 in particular).

## 5. Cross-stack and repository parity

- The S-176/S-177/S-178 fixtures are byte-identical between `test/watch_session_start_test.dart`
  and `WatchSessionStartPathsTests.swift`; the evidence file's parity table has one row per
  fixture and reports both stacks' outcomes.
- The reset's frames are the same kinds both stacks already implement; the wrist's answer is
  produced by the twin under test, not by a stub the test wrote to fit.
- Phase 3's tests stay Mock-first; a Hive harness inside `testWidgets`, or a real
  `Future.delayed`, is a defect (it hangs rather than fails).

## 6. Assumption Log adjudication

| Entry (phase) | Ledger-consistent? | Ratify / Revert | Follow-up |
| --- | --- | --- | --- |
| | | | |

Expected entries: Phase 1's test repairs (each file), Phase 2's predicate and helper names,
Phase 3's helper placement, Phase 4's one known-limit wording. An empty log after Phases 1–3 is
itself suspicious.

## 7. Defects

| # | Defect | Count and examples | Root-cause line | Remediation phase | Structural guard |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

Every remediation sub-phase must include a permanent guard: a test that makes the defect class
impossible to reintroduce (this is the only check that gets cheaper over time).

## 8. Docs

- Every added or rewritten sentence appears in the evidence file's doc-sentence → test table
  with a test that exists by file and name.
- `watch/sync_protocol/PROTOCOL.md` gains exactly one dated row after the last one (`:565`); the
  row is additive, changes no fixture and no version.
- `docs/state_management/watch_surface.md` stays under the 80% band of
  `test/docs_indexing_contract_test.dart`; the before/after byte counts are in the evidence file.
- The residue sweep's grep output is pasted; a surviving "keeps its own" for a session (as
  opposed to the rest timer) is a finding.

## Verdict

`<PASS | PASS WITH REMEDIATION | FAIL — one line, dated, naming the open phases>`

## Open questions for the Conductor

<only items that genuinely need a planner decision; everything else is a remediation phase>

---

# Code review 1 (19a) — whole PR, phases 1, 2, 3, 4, 5a, 5b

Reviewed range: `git diff 996130a..HEAD` (committed). Reviewer run 2026-10-08 (brief `.work/watch-19/brief-review-19a.md`).

Findings: F1..F8 below, severities blocker/major/minor.

## The brief's eight questions

**1. Ping-pong / loops — no loop.** The router's row-2 answer sends `abandoned(W)` + P and **no**
`requestSnapshot()`, so it cannot provoke a second answer. The push's reset (D-176) sends
`abandoned(W)` (skipped when the same pass's `_announceEnd` already named W), then `sendState(composed)`,
then one `requestSnapshot()`; the wrist's answer names P, which is row 1 — silence. A converged pass
sends nothing (S-180 pass 3 asserts the empty frame list). A wrist holding an *ended* session
re-announces it on every wake and each answer is benign (rows 2/3/4) and terminal, so the echo is one
reset per divergence, not per wake.

**2. `owesResetFor` — correct, with two doc issues.** `lib/state/watch/live_session_mirror_state.dart:607`:
`composedId != null && held != null && held != composedId && held != watchSessionPlaceholderId && status != completed`.
The `status != completed` clause suppresses the reset only where the *phone* announced the end (the
Phase 2 log entry's reason); a wrist that ended W itself with the frame lost leaves the mirror active,
so the reset still fires, and the phone-relaunch placeholder window is rescued by the wrist's next
announcement (row 2). No permanent split found. F1, F2 below.

**3. Watch refusal — holds on both stacks.** The refusal lives in `createSession` while the held status
is `active` (Dart `lib/watch/session/watch_session_engine.dart:292`, Swift `WatchSessionEngine.swift:272`):
the held record returned, no session row, no `started` lifecycle, no snapshot. `startFreeWorkout` is
byte-identical to base; `startFromRoutine` absorbs an active *empty* session in place (Dart
`lib/watch/start/watch_session_start_paths.dart:193`, Swift `WatchStartPaths.swift:363`). Proven red at
996130a on both stacks (table below).

**4. Screen follow — holds; two edges.** The listener subscribes only when `!editMode`, is removed in
`dispose`, and guards `!mounted || _leaving || _isFinishingSession || editMode`, a null expected id and
the mounted session id; it acts only on its own session's `null`/`endedAtMs != null`. S-174 is red at
base; S-174/S-184/S-185 are green. F3 and F5 below.

**5. Wake trigger — one gate, one in-flight guard, no queue.** Dart `catchUp`
(`lib/watch/start/watch_sync_orchestrator.dart:67`) and Swift `WatchSyncOrchestrator.catchUp(reachable:)`
keep the reachability gate and the in-flight guard (Swift `NSLock`, Dart a flag set before the first
`await`, cleared in `finally`); the dropped `engine.session != nil` gate is the change. Hooks:
`ios/OmniTrain Watch App/ContentView.swift:162` on `scenePhase == .active` (not on initial appearance —
launch goes through `host.restore()`) and `lib/watch/debug/watch_start_debug_main.dart:294` on `resumed`.
Both hooks are glue with no agent-runnable check, which D-183 records; the accepted cost (routines
re-asked on every wake) is stated in the doc.

**6. Test claims — verified.** `.github/copilot/scripts/macos/gateway.sh test` →
`01:48 +4106 ~1: All tests passed!` (the `~1` skip is the pre-existing
`food_form_decimals_and_autofocus_test.dart`). The handoff's counts (`+4083`, `+4099 -3` → `+4103`,
`+4106`) grow consistently. Every test the docs cite exists by file and name, on both stacks. Every
scenario test read asserts its own stated outcome on a real fixture; S-181/S-183/S-192 are the
documented negative guards, proved by mutation.

**7. Docs.** F1 (blocker), F2. Otherwise: the residue sweep leaves only the rest-timer "each keeps its
own" (`docs/watch_session_sync.md:549`), which D-181 excludes; `watch/sync_protocol/PROTOCOL.md` gains
one dated row at `:566` after the previous last (`:565`), additive, no version or fixture change;
`docs/state_management/watch_surface.md` stays ~600 B under the 80 % band with the size gate green
(Phase 4's +505 B deviation ratified below).

**8. Plan hygiene.** Seeded D-170 … D-175 and S-170 … S-175 appear word for word as in
`.work/watch-19/seed.md` (compared). The Assumption Log is complete and adjudicated below. Every
Predicted-Files deviation is recorded (F8). The Impact table is the weak spot (F3, F4).

## Findings

| # | Severity | Finding (file:line — one sentence) | Fix | Agent |
| --- | --- | --- | --- | --- |
| F1 | blocker | `docs/watch_session_sync.md:255-256` (a line this PR added) claims an empty-ladder wrist "takes the phone's session without the lifecycle", but the reset is owed on the mirror's session id alone (`live_session_mirror_state.dart:607` takes no ladder input), so `abandoned(W)` precedes P in the ordinary path; the claim holds only in the phone-relaunch/placeholder window (S-181 B) | delete the parenthetical — do not rewrite it into corrected prose; the paragraph already points at S-172/S-183 and `WatchSessionEngineTests.testS77AWristWithAnEmptyLadderReservesNothing` | @developer |
| F2 | minor | `docs/watch_session_sync.md:104-112`: the D-10 paragraph's mechanism sentence is unconditional ("the phone's own state is preceded by a `session_lifecycle` naming the wrist's session `abandoned`") while the reset excludes the placeholder, so after a phone relaunch the split survives until the wrist's next activation (S-181 B) | scope the sentence the way the QA page does ("a phone that has not sent the reset") or cite S-181 | @developer |
| F3 | major | the plan's Impact row 5 omits the bridge as a reader of `WorkoutState.endSession`/`discardCurrentSession` (`lib/state/watch/watch_session_adoption_bridge.dart:660,662`), and with D-179 the mounted screen now follows an *adoption-driven* end too; no scenario covers "the bridge adopts a wrist session while the phone's session screen is open" | add that scenario plus a Mock-first widget test asserting one summary and no double push (the test is the structural guard) | @developer |
| F4 | minor | Impact rows 1/7/10 omit readers their own greps find: `lib/state/watch/live_session_mirror_debug_main.dart:233` (`createSession`), `lib/watch/debug/watch_start_debug_main.dart:294` (`catchUp`, itself changed by 5a), `test/watch_session_projection_test.dart:3154`, `test/phone_manage_bridge_test.dart:709`, `test/live_mirroring_test.dart:801` (`reportLifecycle`) — all green, no divergence observed | extend those rows when 19b's plan copies them; no code change | @developer |
| F5 | minor | `lib/features/session/workout_session_finish.dart:92` (`_pushSessionReplacement` → `OmniNavigator.pushReplacement`) replaces the navigator's topmost route, and the session screen opens sheets/dialogs (routes) over itself, so an external end delivered while one is open replaces that route and leaves the ended session route in the stack | pop to the session route (or dismiss) before replacing; guard with a widget test that delivers an external end with a sheet open | @developer |
| F6 | minor | `lib/state/watch/live_session_mirror_state.dart:602`'s comment describes the announcement ("A `W` this phone already announced as `completed` is not reset either") while the predicate at `:607` reads the mirror's own status for the session it holds | tighten the comment, or point it at the test that pins the exclusion | @developer |
| F7 | minor | Phase 2's guard cannot be proved by prove-red: at `6c5da29` the suite fails to compile (`Undefined name 'watchSessionPlaceholderId'`), so the evidence file's mutation table is the substitute (S-181's placeholder clause; the S-180/S-182 mutants) and S-183 is a documented negative guard — honest and adequate | none; keep the substitution recorded | none |
| F8 | minor | touched files outside the phase Predicted Files, all recorded in the log: `lib/features/session/workout_session_list_view.dart` (brief-mandated), `lib/features/session/workout_session_finish.dart` (Phase 3 item 5's conditional), `test/watch_session_projection_test.dart` S-6 (the 5a fix run, out-of-brief, brief's finish condition), plus the range's non-19a commits (18a's review-fix docs, the governor's 19b seed) | ratify | none |

## Verification evidence

**Test run.** `gateway.sh test` → `01:48 +4106 ~1: All tests passed!` (4106 passed, 1 skipped,
0 failed). Two ~1-minute stalls (`pr2_launch_quality_hotfix_test.dart`,
`startup_failure_screen_test.dart`) are pre-existing.

**prove-red spot checks** (base `996130a` unless noted):

| Guard | Command | Verdict |
| --- | --- | --- |
| Phase 1 Dart (S-176 ×2, S-177, S-170, S-178) | `prove-red 996130a test test/watch_session_engine_test.dart test/watch_session_start_test.dart` | RED, guarded assertions |
| Phase 1 Swift S-176 | `prove-red 996130a swift-test --filter WatchSessionEngineTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` | RED — 10 failures, both S-176 cases |
| Phase 1 Swift S-170/S-177/S-178 | `prove-red 996130a swift-test --filter WatchSessionStartPathsTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` | RED — 13 failures, exactly those three cases |
| Phase 2 (S-180/S-181/S-182) | `prove-red 6c5da29 test test/watch_session_auto_push_test.dart` | RED by **compile error** (`watchSessionPlaceholderId`) — not a guard proof; mutation table instead (F7) |
| Phase 3 (S-174, S-184) | `prove-red 9851765 test test/pr4_session_controls_test.dart` | RED, guarded assertions |
| Phase 5a (S-189/S-190/S-193) | `prove-red e47e331 test test/watch_session_finish_test.dart` | RED, guarded assertions |
| Phase 5b (S-186/S-187/S-188) | `prove-red 82eab68 swift-test --filter WatchConnectivityBridgeTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` | RED — 8 failures |

**Doc falsification.** ❌ REJECT — `docs/watch_session_sync.md:255-256` (F1). 🟡 WARNING — the same
page's D-10 mechanism sentence (F2). Implicated documents read and checked against post-change code:
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`,
`docs/watch-app-setup-and-qa.md`, `watch/sync_protocol/PROTOCOL.md`.

**Doc standard.** ✅ PASS — no prohibited content added: the added lines are prose plus test
citations; no new numbered walkthrough (the QA page's steps are pre-existing and rewritten in place),
no hex literal, no control inventory, no constant restated from source (all four changed pages
spot-checked; `test/docs_indexing_contract_test.dart` green).

**Impact (4g).** 11 rows re-grepped; every row's named readers still match and their suites are green
(S-109 A/B/C, S-5, S-70 … S-84, S-73/S-78/S-81, S-107, S-108-as-S-186). Unlisted readers: F3
(production), F4 (debug mains, test files). Resolved: the three reds row (b) caused (S-6, S-86, S-180)
are in the log and were repaired in the 5a fix run.

**Assumption Log adjudication.** All entries RATIFY, none REVERT or ESCALATE. Phase 1: refusal shape,
trap-1 repairs, S-178's field set, inline fixtures, "no doc update" scoping. Phase 2: the
`owesResetFor` clauses (**recommend promoting to a numbered decision** — load-bearing, and the clause
F1/F2's page must not contradict), the constant's home, S-86's three edits, the S-175 → S-180/S-182
mapping. Phase 3: rating 4, `_leaving` placement (the list-view file), S-185 B's home, the
`!editMode` pairing. Phase 4: tool-run sweep, `watch_surface.md` +505 B (**ratified — I name no
sentence to cut; ~600 B headroom, gate green**), the labelled byte estimate, the S-86 rename repairs,
`watch_surface.md:180`'s "no queue, no retry" (**keep — D-178's predicate is recomposed each pass, not
a queue**), the freshness bump. Phase 5a: the fate sources, row (b)'s repair. Phase 5b: harness choice,
reachability expression, bare-launch twin, scoped discard heads-up, group naming.

**Counts.** Blocker 1 · Major 1 · Minor 6 · 6 guard groups proved red, 1 impossible at base (F7).
AC-1 … AC-4 each have their scenarios and passing tests; the single blocker is documentation.

→ @developer: fix F1 (delete the false parenthetical) and F2, then F3's scenario + test; F4, F5, F6 are
one-round mechanical items. No @dba item.

⏸️ **PIPELINE PAUSED** — human checkpoint. Approve, send F1–F6 back for a fix round, or re-plan.

VERDICT: CHANGES_REQUESTED

## Fix round 1 (developer) — F1–F6 addressed, F7/F8 no action

| # | Action taken |
| --- | --- |
| F1 | **Fixed** — the empty-ladder parenthetical is deleted from `docs/watch_session_sync.md`'s D-102 paragraph (deleted, not rewritten); the paragraph keeps its S-172/S-183 and `testS77AWristWithAnEmptyLadderReservesNothing` pins. |
| F2 | **Fixed** — the D-10 mechanism sentence is scoped ("a phone that still knows the wrist's session sends its own state preceded by …"), the placeholder window is named, and it is cited to `test/watch_session_auto_push_test.dart` group `S-172 the phone resets the wrist's live session, then asserts its own`, test `S-181 case B a phone holding its own session over a wrist that holds nothing sends no lifecycle and never names the placeholder`. |
| F3 | **Fixed** — new Mock-first case `S-174 via the adoption path the bridge's end takes the screen to one summary` in `test/pr4_session_controls_test.dart` (the bridge adopts a wrist session while the phone's session screen is mounted; the bridge's own end arrives: exactly one summary, the rating rendered, no second navigation), proved by the `_leaving = true;` mutation (`Expected: <3> Actual: <4>`); Impact row 5 now names the bridge as a reader of `WorkoutState.endSession`/`discardCurrentSession`. |
| F4 | **Fixed, with a mapping note** — the rows the readers' own greps find are extended: row 1 gains `lib/state/watch/live_session_mirror_debug_main.dart:233` and `test/watch_session_projection_test.dart:3146` (`createSession`), row 9 gains `lib/watch/debug/watch_start_debug_main.dart:294` (`catchUp`), row 12 gains `test/phone_manage_bridge_test.dart:709` and `test/live_mirroring_test.dart:801` (`reportLifecycle`). The finding's "rows 1/7/10" does not match the table (7 is the `WatchEffortRating` queue and 10 is `projectedSession`, neither with a reader in the list), so the rows the greps land in were extended instead; recorded in the plan's Assumption Log. |
| F5 | **Fixed** — `_onWorkoutStateChanged`'s ended branch pops to this screen's own route before `_pushSessionReplacement`, guarded by the new case `S-174 an end delivered while a dialog is open over the screen replaces the session route`; `prove-red HEAD` is **RED AT** with the ended screen found beneath the summary (`skipOffstage: false`), and the mutation that removes the pop reddens the same assertion. |
| F6 | **Fixed** — the `owesResetFor` comment now states that the clause reads the mirror's own status for the session it holds and names the case that pins the exclusion (`test/watch_session_auto_push_test.dart`, `S-85 two finishes and a discard are announced once each, under each session's own id`). |
| F7 | **No action** — Phase 2's guard keeps its mutation table as the substitute for prove-red, as recorded. |
| F8 | **No action** — the three out-of-prediction files stand as recorded, for ratification. |

Round's verification: targeted `gateway.sh test` over the five touched suites `+87` all passed; full
`gateway.sh test` `01:45 +4108 ~1` (0 failures); `lint` `196 issues found.` = baseline (none in a line
this round authored); the invariant sweep empty; no `.swift` file changed, so `swift-test` was not
re-run. The mutation outputs, the prove-red verdict and the counts are in
`2026-10-08-19a-phone-authority-plan.evidence.md`'s "Fix round 1" block.
