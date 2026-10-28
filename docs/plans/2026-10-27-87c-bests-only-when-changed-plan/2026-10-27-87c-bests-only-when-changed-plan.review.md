# Code Review: plan 87c, PR 87c-1 (phone half: Phases 1A + 1B)

Base: 403d96d98b996f8bbafe0b7dae85e7c911e76b3d
Reviewer: code-reviewer (Copilot CLI)
Findings appended as found. Numbering: F1, F2, …

## Verification log

1. **Send rule** (`watch_sync_request_handler.dart` `_sendBests`, :249-284) — PASS. The revision is the block's first statement, before `StatsProgressService` is created; branch (b) returns with no walk; the compared text is `jsonEncode` of the payload's `bests` entries only (`buildBestsDown` puts `generatedAt` beside, not inside, `bests`; entries sorted by exerciseId — equal bests give equal text); branch (c) refreshes the remembered revision to the start-read; remember ONLY on `WatchDelivery.delivered`, `_bestsHeld = null` on anything else; a throwing walk propagates before any remember (no catch added — today's behaviour, S-87a-7 green); `_sendBests` is awaited after `_sendExerciseList` (frame still last) and `_sendRoutines` still returns `true` regardless of the send result. Write landing mid-request: the remembered revision is the start-read, older than the data → the next request re-walks (S-87c-12). Null-revision repository: branch (b) can never fire, the text comparison still stops a second send, every request walks (S-87c-7).
2. **`historyRevision`** — PASS. The four listened boxes (`_sessionsBox`, `_segmentsBox`, `_effortsBox`, `_observationsBox`) are exactly what `getAllTimeBests` consumes (stats_progress_service.dart:2264+ reads sessions, segmentsOf, effortsOf, observationsOf; timed/round instances and sensor summaries are loaded into the index but contribute nothing). `_listenForHistoryWrites` cancels-then-clears before re-adding (a second `initialize()` does not stack), uses its own `_historyListeners` list, and is called from `initialize()` beside `_listenForReferenceWrites`. Mock answers `null`. Implementers: exactly `HiveWorkoutRepository` and `MockWorkoutRepository` (`implements WorkoutRepository`); every test fake `extends MockWorkoutRepository` and inherits null.
3. **Request parsing** — PASS. `holdsBestsOf` is `frame['holdsBests'] == true` (string `"true"`, `1`, `false`, absent → not held); `routinesFrame` adds the key only when `holdsBests: true`, default false → every existing frame byte-identical; S-87c-9 pins the contract rows (`routines`, `routinesSince`) and the not-held spellings.
4. **Tests / mutations** — PASS. All six planned mutations have observed reds for the right reasons (evidence M1–M6: ignore flag → S-87c-4/14; skip revision compare → S-87c-1 on `sessionReads`; skip text compare → S-87c-3/7/12; remember on any result → S-87c-5 both arms + S-87c-13; read revision after walk → S-87c-12 via `bumpHistoryOnRead`; include `generatedAt` → S-87c-3/7 with the clock moved between raises). prove-red at the base is compile-red (the new API does not exist there) — re-confirmed by this review's own run; assertion-level reds come from the mutations, as the gateway's rule requires. No assertion loosened: the only changed line in an existing test is S-10411's needle; all five of its assertions are intact, comments are stripped before matching so the widened needle still uniquely locates the declaration, and the new block's ordering is guarded behaviourally by S-87c-12. **A-87c-7: RATIFY.**
5. **Seams and conventions** — PASS. `grep import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` → no matches (re-run by this review); the wiring is the one production call site and passes `holdsBestsOf(frame)`; the clock is injected (`_clock()`); the new groups are plain `test()` (the Hive group settles with a zero-duration delay, no `testWidgets`); `test/helpers/revisioned_repository.dart` keeps every counter and override of the old `_RevisionedRepo` and adds only the history side — faithful.
6. **Docs** — PASS for this PR. `watch_reference_data.md` and `watch_surface.md`: the sentences the change made false are replaced with the D-5 rule; every test named exists (S-87c-1, S-87c-3, S-87a-6/7/13, S-9202); nothing unshipped is named. Other implicated docs re-checked: `services_and_utils.md:275`, `nutrition_state.md:180`, `db_integration.md:201` — all still true (the `historyRevision` row is Phase 3's, not a finding here).

## Findings

- F1 | minor | docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md:27 | the 87c-row rewrite + 87d split is outside this PR's Predicted Files (Phase 3 item 6 owns the file, for a status move only) — justified, since the seeded plan redefined 87c and the old row would now be false, but the row's "being planned" status is already stale (1A/1B are complete) | refresh the status when Phase 3 closes, or accept as series bookkeeping | @planner
- F2 | minor | watch_sync_wiring.dart:323 | the wiring's `holdsBestsOf(frame)` pass has no test in this PR, and A-87c-8 defers one to Phase 2 — but no Phase 2 item lands it (item 8 tests the frame builder, not the pass) | add a wiring-level test (the `radio.fromWrist` harness) to Phase 2's items, or accept Phase 3 QA step 36 as the only end-to-end guard | @planner
- F3 | minor | docs/state_management/watch_surface_wrist.md:258 | "the phone sends the bests last on every answer" is true for THIS PR but Phase 2 makes it false, and the plan's Phase 3 residue sweep (item 7) checks only the handler header and the two edited docs — this file is missing from that sweep | add the file to the Phase 3 residue sweep or reword the sentence then | @planner

None of the three blocks this PR: F2/F3 are plan gaps for the NEXT PR, F1 is bookkeeping that keeps the index truthful.

## Assumption Log adjudication

- A-87c-6 (observations counted via `deleteObservationsForEffort`): **RATIFY** — the test asserts +2 for a two-row delete through the public API, the same per-key listener semantics the scenario names.
- A-87c-7 (S-10411 needle widened): **RATIFY** — see verification log 4; the guard's subject is untouched and no assertion moved.
- A-87c-8 (wiring pass untested, deferred): **RATIFY the deferral, with F2** — the deferred test has no Phase 2 item to land it; the planner must give it a home.
- A-87c-9 (the two doc corrections in this PR): **RATIFY** — both sentences are true post-change and name existing tests; the remaining watch-doc sweep stays with Phase 3.

## Test run (this review's own)

`.github/copilot/scripts/macos/gateway.sh test` → `06:05 +5779 ~2: All tests passed!` — **5779 passed, 2 skipped, 0 failures** (matches the plan's Progress entry and the brief's expectation).

## Verdict

No blockers, no majors; 3 minor findings (all forward-looking or bookkeeping).

**VERDICT: APPROVE**

---

# Code Review: PR 87c-2 (wrist half + docs: Phases 2 and 3)

Base: 2c64ffa52e1de489cd8c84b8edff89edf34c33a5 (PR 87c-1's commit)
Reviewer: code-reviewer (Copilot CLI), 2026-10-28
Findings appended as found. Numbering continues: F4, F5, …

## Verification log

(appended as verified)

1. **Swift wrist (D-2/D-7)** — PASS. `routinesFrame(since:exercisesVersion:holdsBests:)` adds `holdsBests: true` only when true, never `false`/null (WatchConnectivityBridge.swift:97-112); `WatchConnectivityBridge.requestRoutines` (:173) forwards the flag into the builder; `WatchSyncOrchestrator.sync` (:104-112) passes `bests?.hasFrame ?? false`. Grep `func requestRoutines` over the repo: exactly the protocol (:38), the bridge (:173) and the four doubles (WireLog :206, GatedTransport :1426, GatedRequestTransport :1488, RecordingTransport WatchSessionStartPathsTests.swift:54), all on the new signature — no old signature left. `ios/` (incl. `OmniTrain Watch App/OmniTrainWatchConnectivity.swift`) has no `WatchSyncTransport` conformer — confirmed. The app-target build is the governor's; taken as given.
2. **Contract** — PASS. `watch_start_paths_contract.json` gains exactly ONE line, the `routinesBests` row (`{"request": "routines", "holdsBests": true}`); the `routines`, `routinesSince`, `routinesExercises` and `snapshot` rows are byte-identical (the diff shows no other change). Both stacks pin the new row exactly: Dart `S-87c-16 a wrist that holds the bests says so` (watch_transport_test.dart:1638, `_contract()` equality, plus the key-less `routines` arm) and Swift `testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne` (NSDictionary exact equality, both arms).
3. **End to end** — PASS. Fresh wrist: `hasFrame` false → key absent → phone D-5(a) walks and sends → the wrist's `receive` stores it (87b, untouched). Next request: key true → phone D-5(b) skips, reads nothing. Completed workout: the revision moves → walk → entries differ → frame sent. Phone relaunch: `_bestsHeld` is memory-only → sends once. The wrist diff adds one key and nothing else — no timer, no extra frame, no store change. The Dart twin (`lib/watch/start/watch_sync_orchestrator.dart`) is untouched, as q-c/A-87c-5 record.
4. **Tests and mutations** — PASS. The evidence's four Phase-2 mutations (M1 always-on key, M2 `false` for a non-holder, M3 `sync()` flag hard-false, M4 wiring argument dropped) each have an observed red for the right reason, and the S-87c-16 Dart guard is RED at this PR's base for the right reason (this review's own prove-red: `type 'Null' is not a subtype of type 'Map<dynamic, dynamic>'` — the `routinesBests` row does not exist at 2c64ffa5). S-87c-18 is GREEN at base and correctly so: the wiring pass it guards landed in 87c-1 (the base); its red proof is mutation M4, not prove-red. No existing assertion removed or loosened: the only changed lines in `test/` and `watch/watchos/Tests` are the doubles' signatures and additions.
5. **Docs** — one REJECT (F4 below). `watch_reference_data.md` states D-5 correctly INCLUDING the identical-bests arm; `db_integration.md`'s `historyRevision` row names the S-87c-15 group and both tests (they exist); `watch_surface.md`'s "Last, … unless" and skip rule are true; `watch_surface_wrist.md`'s F3 reword keeps the claim and the file shrank (governor: 52200 → 52196 B, band 52428); QA step 36 is plain owner language, runnable, and names existing tests; the plan and series-index statuses are true. Every test or file a doc names exists (S-87c-1/2/3/4/5/15/16/18, S-87a-6, S-87b-12 ×2, S-87b-14, S-3818/3819/3820 all verified on disk). Nothing unshipped is named.
6. **Residue** — the recorded A-87c-13 comment is a defect to fix in THIS PR (F6), and the sweep missed its twin in Sources (F5). The 87a-era test reason strings (`S-3850`, `S-7103`, `S-87a-7`, `S-003`, the idle/changed-only reasons) are NOT stale: they describe flag-less requests, where the frame is sent exactly as 87a D-4 says, and S-87c-11 keeps those tests unedited. The handler's own comments state the 87c rule.
7. **Standing focus** — PASS. No new seam (the orchestrator's `bests` is 87b's injected holder); the diff touches no allowlist entry, no ratchet, no `lib/features/` or widget file; every hunk in `git diff --stat` is explained by the items above.

## Findings (PR 87c-2)

- F4 | major | watch/sync_protocol/PROTOCOL.md:143-147 and the 2026-10-28 version-history row (:786) | the omit rule says the phone MAY omit `bests_down` only while "no workout-history row has been written since then" and MUST send "whenever its history changed" — it lacks D-5(c)'s identical-bests arm, so the protocol forbids the very omission S-87c-3 pins (a write that leaves the bests identical costs one walk and no frame) and contradicts `watch_reference_data.md`:241-247, which states the disjunction correctly | add the arm to both places ("or the phone looked and the bests came out identical"), pointing at S-87c-3 — the test pointer is the standing guard | @developer
- F5 | minor | watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift:32 | "`bests_down` belongs here because the phone sends it last on every request (plan 87b D-8)" states the old rule in production Sources and is missing from the evidence's residue sweep, which lists only the test-file twin | one-line comment fix: "last in an answer that needs one (87c, D-5)"; add to the residue table | @developer
- F6 | minor | watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift:214 | A-87c-13's recorded residue ("The phone sends the bests last on every request") — ruling: it IS a defect to fix in this PR; the change that made the sentence false should not leave it standing when the fix is one line, and Phase 2 already had Swift on the tree | same one-line fix as F5, same pass | @developer

## Assumption Log adjudication (this phase)

- A-87c-10 (relaunch arm rebuilds the holder over the same store): **RATIFY** — the S-87b-11 shape; the claim under test is that the held copy survives a relaunch, and the test asserts exactly that.
- A-87c-11 (version-history row dated 2026-10-28): **RATIFY** — the row states the day it was written, like every other row in the table.
- A-87c-12 (watch_surface_wrist.md reword paid for by trimming the same paragraph): **RATIFY** — the claim is kept, the file shrank 4 B, and the band assertion is green in this review's own suite run.
- A-87c-13 (the stale test-file comment left for a later phase): **REVERT** — see F6; fix it in this PR together with F5.

## Test run (this review's own)

- `.github/copilot/scripts/macos/gateway.sh swift-test` → **1124 tests, 0 failures** (matches the brief's expectation).
- `.github/copilot/scripts/macos/gateway.sh test` → `05:35 +5781 ~2: All tests passed!` — **5781 passed, 2 skipped, 0 failures** (matches the brief's expectation).
- `.github/copilot/scripts/macos/gateway.sh prove-red 2c64ffa5 test test/watch_transport_test.dart test/watch_session_projection_test.dart` → RED at base, 1 failure, the S-87c-16 contract guard, for the right reason.

## Verdict (PR 87c-2)

One major (F4, a protocol sentence that misstates the send rule this PR introduces) and two minors (F5/F6, stale comments, one of them unrecorded residue). The Swift, contract and test work itself is conformant and fully guarded.

**VERDICT: CHANGES_REQUESTED**

---

# Re-review of PR 87c-2 after fix 3

Base: 2c64ffa52e1de489cd8c84b8edff89edf34c33a5 (unchanged). Scope: findings F4, F5, F6 of "Review of PR 87c-2" only. Fix brief: `.work/87c/brief-fix-3.md`.

## Verification log

1. **F4 — PROTOCOL.md** — PASS. The request-rules bullet (:141-152) now states the MAY-omit condition as "the key is the boolean `true`, the last `bests_down` it sent was delivered, and either no workout-history row has been written since or the bests it computes now are identical to that frame's" — the identical-bests arm is present, worded as the fix brief specified. The MUST-send arms are intact and unchanged: "when the key is absent or anything but the boolean `true`, whenever its history changed, and after a frame the radio did not carry". The 2026-10-28 version-history row (:787) carries the same disjunction ("either no workout-history row was written since or the bests it computes now are identical to that frame's"), keeps its MUST-send arms, and now names `S-87c-3` beside the existing test pointers ("S-87c-3 a write that leaves the bests identical costs one walk and no frame"). `git-diff` for the file shows exactly three hunks: the :104 `bests_down` note reword (PR 87c-2's own docs work, reviewed and passed last round), the new `holdsBests` bullet, and the appended version row — nothing else in the file changed, and within the two fixed hunks only the omit condition and the S-87c-3 pointer moved. The wording matches the phone's code (`WatchSyncRequestHandler._sendBests`, D-5 a–d, verified in the previous review's log 1) and `docs/state_management/watch_reference_data.md`:241-249, which states the same three-condition skip with the identical-bests arm — the three documents now agree.
2. **F5/F6 — Swift comments** — PASS. `git-diff` of `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift` shows one hunk, the `replyTypes` doc comment, now "the phone sends it last in an answer whenever the bests changed or the wrist does not hold them (plan 87b D-8, plan 87c)", the rest of the sentence unchanged. `git-diff` of `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift` shows one hunk, the S-87b-12 doc comment, now "When the phone sends the bests it sends them last (plan 87b D-8)". Both diffs are comment lines only — no code, no assertion, no test body touched — so `swift-test` was not re-run (the brief runs it only on doubt; the diff leaves none).
3. **Evidence file** — PASS. It carries the heading "Review fix 3 (developer, 2026-10-28) — observed output" with F4/F5/F6 ticked and the suite counts pasted (docs contract 13 passed; full suite 5781 passed, 2 skipped; swift-test 1124, 0 failures; lint at the 180-issue baseline), and the Residue-sweep table (:254-268) has one row per Swift comment, each naming its finding, the new wording and "comment only".

## Findings

None. F4, F5 and F6 are closed exactly as specified; nothing outside the four named places moved.

VERDICT: APPROVE

