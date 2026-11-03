# Review: plan 98 fixes (rest ends on any timer start; refused timer starts are sent again) · D-1..D-5 · base..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 1 · minor 2 · tests: 6018 passed, 2 skipped, 47 failed (none in review scope; see Tests note)
Diff vs Predicted Files: conforms — every working-tree change is a plan-predicted file (timer_manager.dart, watch_timer_push.dart, watch_sync_wiring.dart, 5 docs, 3 test files). Extra S-9931..S-9934 groups are additions inside the predicted test file. Untracked `docs/state_management/watch_surface_nutrition.md` is the plan's new page.

Tests note: full `flutter test` run by this review (gateway test, 900 s, log `.work/gateway/test-20261102-204336-76419.log`): `05:18 +6018 ~2 -47: Some tests failed.` All 47 failures are in files owned by other in-flight sessions (state_test.dart ×2 NutritionState — brief states these fail on base too; nutrition_test.dart ×1; protein_consistency_service_test.dart ×3; protein_consistency_signal_screen_test.dart ×3; instrument_list_screen_test.dart ×18; mix_layer_screen_test.dart ×16; modality_mix_shift_signal_screen_test.dart ×2; edge_case_test.dart ×2). No review-scope test file failed.

## Findings
1. [Blocker] lib/state/watch/watch_timer_push.dart:367,378 (with :361, :408) — a wrist-ended timer can become owed and be restarted by a later wrist frame. Sequence: timer adopted by the phone (recorded in `_adopted`, `_delivered` empty); wrist stops it (mirror holds state `stopped`, so `_wristHolds` returns `no` at :408 and adoption skips stopped kinds, leaving the phone state holding the timer); the phone state then changes while unreachable → full pass composes the still-running kind, send fails → `_owed.addAll(next)` at :367/:378 unconditionally; a later wrist frame triggers a clears-only pass, the kind is owed so the filter at :361 keeps it, and the phone re-sends a start the wrist already ended. This contradicts the plan's D-2 claim and the code comment (~:109-117) and `docs/state_management/watch_surface.md` (~:256-290) that a wrist-ended timer is "delivered or adopted, never owed". Fix: when adding to `_owed` (or at the top of `_pushOnce`), prune kinds whose mirror copy holds state `stopped`. Guard: extend S-9927a (test/watch_timer_push_test.dart) with a failed full pass between the wrist stop frame and the next wrist frame, asserting no start frame is sent.
2. [Major] docs/plans/...plan.md S-9930 vs test/watch_timer_push_test.dart (S-9930 group, ~:3170-3200) — the plan's S-9930 is the round/hold arm of S-9925: an owed start for kind `round` is re-sent on a later wrist frame. The implemented S-9930 test is a different scenario ("a refused clear and a refused start travel in order", kind elapsed). The round-kind owed start has no test; a regression that drops owed round starts would pass the suite. Fix: add the round-kind case to the S-9930 group (or rename the implemented test and add the planned one). Guard: the planned S-9930 itself.
3. [Minor] lib/state/watch/watch_timer_push.dart:167-169 — stale comment: "the start it owed waits for the next phone-state trigger" is no longer true; with `_owed`, the follow-up clears-only pass sends it (the behaviour D-2 wants). Doc-only fix.
4. [Minor] docs/rest_tracking.md ~:176 and ~:187 — the flow diagram and lifecycle paragraph name `_persistClosedRests(closedRests)` as the persist step when a timer starts, but `startTimedEntry`/`startRound` persist closed rests via an inline per-rest loop (lib/state/workout/timer_manager.dart ~:930-940 and ~:566-576); `_persistClosedRests` (:446) is called only by the two adopt paths (:387, :426). Behaviourally identical (unawaited `updateEntryRest` + `catchError`), but the doc names a method the start paths do not call. Fix: say "persists closed rests (same per-rest update as `_persistClosedRests`)" or have the start paths call the helper.

## Assumption Log rulings
- Fake-radio probe assumption (plan :114-115): ratify. The probes' `unreachable → undelivered` mapping matches the observed `_owed` behaviour in the new tests.
- Scout sheet C correction (plan :116-118): ratify. `watch_session_importer.dart` skips rests with no end; the phone's open rest comes from the wrist set's arrival.

## Scenario coverage
- S-9921, S-9921b, S-9921c → test/timer_start_closes_session_rests_test.dart (Mock + Hive parity groups) · covered
- S-9922, S-9923, S-9923b → test/timer_start_closes_session_rests_test.dart · covered
- S-9924 → test/watch_timer_push_test.dart S-9924 group · covered (fails without D-1: no `{rest: null}` clear frame)
- S-9925 → test/watch_timer_push_test.dart S-9925 group · covered (fails without `_owed` + the :361 filter)
- S-9926 → test/watch_timer_push_test.dart S-9926 group · covered (fails without the owed mechanism)
- S-9927, S-9927a → test/watch_timer_push_test.dart S-9927 group · covered, but see finding 1: the guard does not cover a failed full pass between stop and next wrist frame
- S-9928, S-9929 → test/watch_timer_push_test.dart · covered
- S-9930 → test/watch_timer_push_test.dart S-9930 group · covered as a different scenario; the plan's round-kind arm MISSING (finding 2)
- S-9931..S-9934 → test/watch_timer_push_test.dart · covered (additions beyond the plan's list)
- S-002b → test/unified_rest_overlay_test.dart (~:336-370) · covered (premise change: chip never reappears; documented owner decision 2026-11-02)
