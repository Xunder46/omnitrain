# Review: 2026-11-05-121a-watch-hold-stuck-after-phone-log · P0-P2 · ecf2d050..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · tests: 6758 passed / 1 failed / 2 skipped (full `gateway.sh test`; the failure is `test/logger_feedback_controls_test.dart` S-5115 `rest-overlay-chip`, a file this plan does not touch — sibling work, governor's call)
Diff vs Predicted Files: conforms for this plan (lib/state/watch/watch_timer_push.dart, lib/state/watch/watch_sync_wiring.dart, test/watch_logged_hold_stays_stopped_test.dart untracked, docs/state_management/watch_surface.md, docs/watch_session_sync.md, plan + evidence file). The working tree carries 23 further changed files from sibling plans on the shared base (plan 120's ScreenAwakePort set, 121b/122 work); none of them is named by this plan.

## Findings

1. [Major] plan file `## Assumption Log` — the log is "(empty)" after a complex phase that made a deliberate deviation from D-4 (v) (the one-sided start match). The evidence file itself points at it: "S-6329 forced the one-sided match, see Assumption Log" (evidence, Phase 1 red→green) — but there is no entry to see. A maintainer reading the plan sees D-4 state a two-sided 1000 ms match while the code is one-sided, with no recorded ratification. Fix: append one entry (≤3 lines): one-sided reconcile start match, reason S-6329 pins a later wrist start wins, details in evidence M8/M15. Guard: none (process).
2. [Minor] plan file `## Progress` — P0, P1, P2 and the governor boxes are all unchecked although the evidence file records the gate, red→green, dependents, docs and mutations as done. Fix: tick P0-P2 (leave the governor box to the governor).
3. [Minor] docs/watch_session_sync.md:493-496 — the invariant bullet's second behaviour sentence ("A wrist clock the phone has already logged is cleared by a live `timer_state` clear") is cited only to S-12101/S-12103, which test the snapshot half; the test that pins the clear half is S-12107 (S-12106 for the reachable case). Fix: add S-12107 to the citation.
4. [Minor] docs/state_management/watch_surface.md:302-304 — the S-id group "the reconcile clear `S-12106` to `S-12108`" includes S-12106, which asserts the 43c live clear, not the D-4 reconcile. Fix: reword to "the clears `S-12106` to `S-12108`" or move S-12106 to its own clause.

## Assumption Log rulings

- One-sided reconcile start match (deviation from D-4 (v)): RATIFY as a code fact — the code, S-12108g/h and the killed mutants M8/M15 support it — but it must be entered in the plan's Assumption Log (finding 1).
- No other entries exist to rule on.

## Scenario coverage

S-12101 → watch_logged_hold_stays_stopped_test.dart `S-12101 the queued snapshot after the log names no hold…` | S-12102 → `S-12102 …` | S-12103 → `S-12103a …` + `S-12103b …` | S-12104 → `S-12104 …` | S-12105 → `S-12105 …` | S-12105b → `S-12105b …` | S-12106 → `S-12106 …` | S-12107 → `S-12107 …` | S-12108 → `S-12108a`…`S-12108h` (plan names a..g; h is the added one-sided guard) | S-12109 → `S-12109 …` | S-12110 → `S-12110 …` | S-12111 → `S-12111 …` | S-12112 → `S-12112 …` | S-12113 → `S-12113 …` | S-12114 → `S-12114 …` | S-12115 → `S-12115 …`. None MISSING.

## Brief questions

1. `snapshotTimers()` (watch_timer_push.dart:139-176) — no case the tests miss that this diff introduces. A paused or paused-then-resumed delivered timer is still named as the delivered running JSON: D-3, pre-existing (`deliveredTimers()` did the same), declared in the plan (Noticed item 3). A replaced timer fails (iii)/(iv). Before a graph's first `_pushOnce`, `_sessionId` is null so the snapshot names nothing — identical to the old empty `_delivered`, not a regression.
2. No (watch_timer_push.dart:537-633). `rest` is never reconciled (`_workKinds`, :537). A different interval of the same slot: the one-sided `near` (gap = intervalStart − copyStart ∈ [0, 1000], :580-583) clears only a copy at or before a logged start; a later copy is left (S-12108h). A round runs the same guards via `getRoundsForEffort` (:596). A copy ≤1000 ms earlier than a logged interval IS cleared (S-12108g) — the ratified deviation.
3. No post-delivery repeat. `_stale` is written only after `_send` returns true (watch_timer_push.dart:366-382); on failure the pass returns and the next pass recomposes the same clear — the intended retry. `reconciled` is populated in the same pass as its clears, so a delivered reconcile clear always finds its entry; a kind already in `clears` from the retired/`_delivered` loops is skipped by the reconcile, so the two `_stale` sources never collide.
4. Yes. `_loggedStartToleranceMs` = 1000 (watch_timer_push.dart:543) and `_restStartToleranceMs` = 500 (:637) both exist and are named correctly; the watch_surface sentence "at or within `_loggedStartToleranceMs` after the copy's start" matches the one-sided `near`. Every S-id named in either doc exists in the test file. Minors 3 and 4 are the only wording gaps.
5. See "Diff vs Predicted Files" above: conforms for this plan; 23 outside files belong to sibling plans on the shared base (verified sample: docs/state_management.md and services_and_utils.md changes are plan 120's ScreenAwakePort, not 121a's).

## Docs delta

The plan has no `## Docs delta` table; Phase 2 names two docs.
- docs/state_management/watch_surface.md D-1/D-4/D-5 + tolerance-drift fix -> applied
- docs/watch_session_sync.md invariant bullet -> applied
- No doc edit outside the named two was made by this plan (the state_management.md edits are plan 120's).
