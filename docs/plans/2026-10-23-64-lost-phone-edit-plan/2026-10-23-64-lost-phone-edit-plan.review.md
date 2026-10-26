# Review: plan 64 (phone edit not lost) · phases per plan · HEAD..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: governor-run green (+5483, 2 skipped) per brief; lead mutations 5/5 red (sixth equivalent)
Diff vs Predicted Files: conforms (plan-64 paths only; the other working-tree files carry plans 61/62/63/65/66a and are not under review)

## Findings
None.

## Answers to the brief's questions
1. `hasUnsentChange()` is the first statement of the `resolved.onIncoming` closure (`lib/state/watch/watch_sync_wiring.dart:307`), before the request branch and before `router.receive`, so it reads the pre-frame composed state and cannot see the wrist frame's own effect. `owedBefore` is used on every path: both branches fall through to the single `if (!owedBefore) await push.rebaseline();` (line 321) with no early return between the read and the use, so it is neither unused nor stale.
2. The replacement assertion (test/watch_session_auto_push_test.dart:3790-3800, no snapshot carries `doomed`) guards the re-offer's content; alone it would pass vacuously without the fix, but the fix is guarded by the preceding `deletions hasLength(1)` assertion (line 3775) — without plan 64 the frame's `rebaseline` swallows the owed deletion and that assertion fails. The echo pin (lines 3801-3812: no non-receipt sent frame contains `_wristEntryId2`) is intact and still protects D-82.
3. n/a (plan 66b).
4. n/a.
5. `docs/state_management/watch_surface.md:190-196, 224-231`: every claim matches the code — the guard, the two covered cases (debounce-window edit, undelivered push), and the named tests (`S-9400` group with `S-9401`, `S-9405`; the re-pinned `S-205 (S-209)` name matches the test verbatim). `forgetBaseline()`, used by S-9404/S-9407, exists (`lib/state/watch/watch_session_auto_push.dart:247`).

## Assumption Log rulings
Neither the plan nor the diff carries Assumption Log entries; nothing to rule on.

## Scenario coverage
S-9401 -> test/watch_session_auto_push_test.dart · `S-9401 the phone's own set, logged before the wrist's frame, rides the snapshot sent after the frame is handled`
S-9402 -> same file · `S-9402 the phone's own set survives a ROUTINES request from the wrist`
S-9403 -> same file · `S-9403 nothing owed before the frame: the wrist's own set is not echoed back`
S-9404 -> same file · `S-9404 no baseline and no edit: the wrist's frame pushes nothing back`
S-9405 -> same file · `S-9405 a push the radio did not carry is offered again once the wrist's frame proves the link`
S-9406 -> same file · `S-9406a …` and `S-9406b …` (both arms)
S-9407 -> same file · `S-9407 hasUnsentChange answers the phone's owed state directly`
S-205 re-pin -> same file · `S-205 (S-209) the wrist's own set arrives while a deletion is owed: the owed state is re-offered after it (plan 64), and the wrist's own row is still not echoed`
