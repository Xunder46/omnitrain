# Review — watch-session-sync PR 2b (the wrist logs its own session)

Reviewed: `612b356..worktree` — phase 1 `634a967`, phase 2 `8f02e21`, uncommitted phase 3 docs.
Reviewer: `@code-reviewer` (Copilot edition). No product code was edited.

**Layers in scope:** watch package (`watch/watchos/Sources/WatchSessionEngine/`), watch app shell
(`ios/OmniTrain Watch App/`), docs.
**Layers skipped:** Dart `lib/` (unchanged — `git-diff --stat` shows no `lib/` or `proto/` path),
`android/`, `scripts/`, shared widgets/core.

**Diff vs Predicted Files:** conforms. Every changed path is predicted; no predicted path is
untouched. No `lib/`, protocol, plist or schema change — D-28 holds.

**Test run (observed, this review):**
`gateway.sh test` → `01:41 +3913 ~1: All tests passed!` exit 0 —
`.work/gateway/test-20261005-225018-88467.log`.
`gateway.sh swift-test` → `Executed 267 tests, with 0 failures` exit 0 —
`.work/gateway/swift-test-20261005-225018-88466.log`.
Handoff pasted real counts; the Docs section exists. 4c passes on evidence.

---

## Findings

| # | Severity | Location | Reason |
|---|---|---|---|
| F-1 | **blocker** | `docs/watch-app-setup-and-qa.md:452` | The new PR 2b walkthrough's step 2 — the only manual procedure that exercises **AC-1 / D-22** ("a set logged while the phone is reachable is handed over as it is logged", no timer) — tells the owner to "Tap **Sync** on the wrist" and then check the phone. `WatchSyncOrchestrator.sync` re-sends everything the phone has not acknowledged (`watch/start/watch_sync_orchestrator.dart:89-90`, `engine.pendingObservations()` before the snapshot), so the step passes whether or not the sink is wired: it cannot fail, so it cannot accept the PR's central claim. The plan's own owner walkthrough says the opposite at step 5 (`…-plan.md:370`, "Phone, without syncing anything … *(If it does not, the sink is not wired.)*"). Fix: drop the Sync tap from step 2 and read the phone with the wrist untouched; keep Sync only where a re-send is the point (step 4). |
| F-2 | **blocker** | `docs/watch_session_sync.md:141` | "**Nothing starts, changes or finishes without a sync.**" is untrue about the product as of this PR: with the phone reachable, a logged set, `session_end` and the completing `session_lifecycle` reach the phone from the sink at the moment they happen. It is also contradicted by the paragraph this PR added twelve lines above (`:121-129`), which states exactly that. Two claims in one document cannot both hold. Fix: delete the bullet and point at the test that verifies the new behaviour (`WatchEmitForwarderTests` / the inbox acceptance tests) rather than restating it in prose. |
| F-3 | **major** | `docs/watch-app-setup-and-qa.md:245` | "Expected: **3881 passed, 1 skipped** (2026-10-04)." is stale: the suite now reports `+3913 ~1` (this review's run). A dated number is banned by `documentation_standard.md` (§3.4 restated values) and, stale, it reads as a regression to whoever runs QA. Fix: delete the count and point at the check (`gateway.sh test`, "all passed, no failures"), keeping `:251`'s "0 failures" form. |
| F-4 | **major** | `docs/plans/2026-10-05-15b-watch-session-sync-pr2-plan.md:389` | The PR 2a correction note (`:379-386`) records the sweeps it fixed, but the bullet at `:389` still reads "give the engine the `onEmit` sink it does not have today" — the exact state this PR removes. So scenario **S-28a** / **AC-10**'s second half ("the plan's cited grep returns clean", plan `:210-212`) is **unmet**: the grep the plan cites still hits. Fix: correct the clause in the 15b plan and record the sweep result honestly rather than leaving a hit that contradicts its own correction note. |
| F-5 | **major** | `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift:392` | Scenario **S-29a** (an active session ended by the *phone's* `completed` lifecycle) is enumerated in the plan (`:232`) but has no test. The only S-029 test drives the wrist's own `finishSession()`, so the guard added by D-23 is proved for one of the two ways a session ends — the branch the phone can drive at any moment is unproven. Fix: add the fixture (apply a `session_lifecycle(completed)` frame, then assert `canLog` is false and `log()` refuses). |
| F-6 | **major** | `ios/OmniTrain Watch App/ContentView.swift:106-109` | The re-render after End / after a rating answer rides a `Task` queued from `rating.objectWillChange` *before* `end()` / `confirm()` have mutated the state it reads (`rating.prompts` is not `@Published`, `WatchEffortRating.swift:104`; the notification is sent at `:144` before `finishSession()`). It happens to be correct today only because `InMemoryWatchSessionStore`'s async methods never suspend, so the queued `Task` cannot run early. When PR 4's durable store suspends, the bump can land before the prompt is owed — the wrist then shows the logging surface after End with nothing further to re-render it, or stays on a question the user has already answered. Latent, but this PR ships the shell around it and no simulator tap-through was run (F-1 is the procedure that would have caught it). Fix: bump `revision` from a host method *after* `await rating.end()` / `await rating.confirm()` returns, or publish the prompt state. |
| F-7 | **minor** | `ios/OmniTrain Watch App/ContentView.swift:150,203-208` | `pickingExercise` is set by the start screen but never cleared when the session ends or the surface switches, so a picker opened before the session finished can reappear over the next surface. Verify against the sheet's own binding and clear it when the session becomes inactive. |
| F-8 | **minor** | `docs/watch_session_sync.md:155-166,464-466` | The four new limit sentences and the two "known gaps" state behaviour with no pointer to what verifies it, which `documentation_standard.md` §4.2 requires; the phase-3 evidence file itself calls them "plain". The added section heading `*(owner, not yet run)*` and the `*(needs the durable store — PR 4)*` / `*(needs Phase 8)*` tags (`docs/watch-app-setup-and-qa.md:416,428,436`) are §3.7 scheduled-change annotations that will invert the moment PR 4 lands. Fix: point the gaps at the tests that hold them, and name the limit without a future-PR tag (the tags at 416-436 are pre-existing; only the new section's are this PR's). |
| F-9 | **minor** | `lib/watch/logging/watch_logging_state.dart:183` | The Dart twin of the wrist logging state still has the pre-D-23 guard (`session != null && slot != null`, no active-status check). It is reachable only from the debug entrypoints (`lib/watch/debug/`, `lib/state/watch/live_session_mirror_debug_main.dart`) — no shipping route, and no `lib/` change belongs in this PR — but the two implementations now disagree about the same question, which is the divergence this series relies on not existing. Fix (follow-up): bring the twin to the same rule, or record that the debug surfaces are frozen. |

---

## 4a — Acceptance criteria

AC-1…AC-4, AC-6…AC-9: met in code (see the verification list below). AC-5, AC-10: see F-4.
No criterion is unimplemented; AC-10's second half is the exception noted in F-4.

## 4b — Scenario register

S-20…S-28 have tests that assert the stated outcome, and the package halves build the fixtures the
scenarios enumerate. **S-29a has no test (F-5).** The phone halves are covered by the Dart suite
(green, above).

## 4c — Test run verification

Pasted counts present and real; the re-run confirms them (header block). No defect fix was in scope,
so the "fails without the fix" rule does not apply. No hang, no timeout.

## 4d — Documentation falsification

```
DOC FALSIFICATION: ❌ REJECT — docs/watch_session_sync.md:141 — "Nothing starts, changes or finishes without a sync" is false and contradicts :121-129 → delete prose, point at WatchEmitForwarderTests
DOC FALSIFICATION: ❌ REJECT — docs/watch-app-setup-and-qa.md:245 — "Expected: 3881 passed, 1 skipped" vs observed +3913 ~1 → delete the number, point at the check
DOC FALSIFICATION: ❌ REJECT — docs/watch-app-setup-and-qa.md:452 — the walkthrough's stated expectation is not decidable as written; it contradicts the plan's own step 5 → remove the Sync tap
DOC FALSIFICATION: ⚠️ CONFLICT — docs/watch_session_sync.md:141 vs :121-129 — do not pick a winner; delete the false half
DOC FALSIFICATION: 🟡 WARNING — docs/plans/2026-10-05-15b-…-plan.md:389 — stale claim in the neighbouring plan (F-4)
DOC FALSIFICATION: ✅ PASS (3 implicated) — docs/state_management/watch_surface.md (§362-384 names real tests and states the limits), series index :30, this plan's Phase 3 / Progress / Assumption Log
```

No scope declarations exist in the `docs/` set, so every changed path implicates the set; the three
documents above are the only ones whose claims this change can have made false. `docs/design_system.md`,
`docs/data_models.md`, `docs/db_integration.md`, `docs/rest_tracking.md` and the screen inventory were
read and carry nothing about the wrist surfaces that this change reaches.

## 4e — Documentation standard

```
DOC STANDARD: 🟡 WARNING — docs/watch-app-setup-and-qa.md:441+ — §3.7 annotations naming a pending PR/phase (F-8)
DOC STANDARD: 🟡 WARNING — docs/watch_session_sync.md:155-166,464-466 — behaviour restated without a verification pointer (F-8)
DOC STANDARD: ✅ PASS — no §3.1 step numbers, §3.2 presentation values, §3.4 restated constants, §3.5 copied code or hex literals were added
```

The walkthrough genre is pre-existing in this file and the plan mandates it (A-13), so it is reported
as a pattern note, not as newly-added prohibited content.

## 4f — Conventions

```
PASS (11): plan is the contract and was read; decisions D-21…D-30 respected; no `lib/`/protocol
change (D-28); repository interface untouched; state is injected and screens observe the state they
were given; the shell hosts the package's own views and sink rather than a second implementation
(no parallel pattern); no timer-driven send (D-22); Swift 6.2 isolation handled explicitly
(nonisolated `enqueue` + NSLock, `@concurrent` callbacks); knobs named from constants, no literal
duplication; tests added beside the code they cover; docs updated in the same change; no formatter run
on the tree.
N/A (5): model/persistence layers, theme and design tokens, analytics/ranking, timestamps and
wall-clock records, the SQL schema/seed contract — no Dart change in this diff.
FAIL: none against the rule source. The findings above are against the plan, the doc standard and the
scenario register, not `global_conventions.md`.
```

## 4g — Impact Check

3 rows checked, all greps re-run. `onEmit` readers: the six harnesses named in the plan plus
`WatchEmitForwarderTests.swift:104` — the new file is a reader the table implies but does not name,
which is expected for the phase's own test file. `asksForEffortRating`: `WatchEffortRatingState` only —
**no unlisted reader**. `canLog`: `WatchLoggingView.swift:185`, `fields`/`log()` in
`WatchLoggingState.swift` and two assertions in `WatchLoggingSurfacesTests.swift` — **no unlisted
reader**. One drift: the table's line citations inside `WatchLoggingState.swift` are off by the seven
lines the new guard added (`canLog` 193→198, `fields` 317→324, `log()` 547→554); a citation that no
longer resolves is what makes the next reader distrust the whole table.
**Unlisted readers: 0** (F-9's Dart twin is a divergence of rule, not a reader of a changed surface).

## Assumption Log adjudication

- **RATIFY A-1…A-13** as recorded; every one is consistent with the recorded decisions and with the
  code as reviewed. Promote **A-8** (the three-surface branch order) and **A-10** (D-23's active-session
  guard) to numbered decisions — both bind PR 4's shell work. A-10's line citations are the drift noted
  in 4g; A-13's walkthrough choice is what produced F-1, so promote F-1's correction with it.
- No silent guesses were found: the empty-log case is written down, and the phase-3 doc decisions are
  all in the log.

## Scope triage (§1 "At review", `.github/copilot/pr-scope-budget.md`)

Nine findings, none spanning layers, two of them blockers, and no second review round is needed if the
split below is respected.

- **This PR, one round:** F-1, F-2, F-3, F-4, F-8 — all doc edits, each a deletion plus a test pointer —
  and F-5, one test file's worth of fixture.
- **Follow-up PR:** F-6 (the re-render bump is a shell-shape change whose guard needs the simulator, so
  it belongs with the PR that makes the store suspend — PR 4), F-7, F-9 (reaches `lib/`, which this PR
  deliberately does not).

Each remediation item carries a guard: F-1's is the plan's owner step 5 as written (no Sync tap) plus a
QA-guide line that the phone's session must show the set with the wrist untouched; F-2's and F-3's is
the doc-standard rule itself (a claim about *what happens without a sync* must cite a test; a restated
suite count is banned by §3.4); F-4's is running the grep the plan cites as part of the phase's
evidence; F-5's is the fixture at `WatchLoggingSurfacesTests.swift:392`; F-6's is a shell test built on
a suspending store stub.

## Verified clean (no finding)

Build order and lifetime in `ContentView.swift:57-76` (the host strongly holds the forwarder; the
engine's `sink` is weak); the branch order matches D-24 + A-8; `canLog` requires an active session
(`WatchLoggingState.swift:198`) and both `fields` (`:324`) and `log()` (`:554`) guard on it; the
forwarder keeps order with a serial `tail` under `NSLock`, never blocks the caller, reports and drops a
refused frame, and cannot stall the chain — `OmniTrainWatchConnectivity.send` throws synchronously
(`notActivated` / `phoneNotReachable`) and passes `replyHandler: nil`, so a stuck send is not possible;
a frame emitted while unreachable is re-sent from storage at the next Sync, including after End; End
twice is a no-op (`WatchEffortRating.swift:148` guards on status); End with no logged set owes no
prompt (S-24); the owed question has no exit but an answer; the wire is conformant — a wrist
`timer_state` is an accepted and allowed type (`lib/core/sync_protocol/message_validator.dart:115`,
handled by the inbox), the forwarder does not mutate frames so the no-null / ints-stay-ints rule holds
by construction, and the phone's "only the ender asks" rule (PR 1 D-8) is preserved; I-1 holds — the
phone routes a wrist `session_lifecycle` (`lib/state/watch/watch_incoming_router.dart:115`); no new
screen, no plist, schema or protocol change.

---

## Recommendation

`CHANGES_REQUESTED`. The code is sound and both suites are green; the blockers are documentation that
states something untrue about the shipped behaviour, which is the one thing this pipeline rejects
regardless of how correct the change is. F-1, F-2, F-3, F-4, F-8 and F-5 are one bounded round. F-6, F-7
and F-9 should be planned as a follow-up PR rather than absorbed.

