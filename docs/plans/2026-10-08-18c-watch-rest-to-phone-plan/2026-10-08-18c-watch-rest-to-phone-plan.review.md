# Review — 18c (the wire + the phone writes a rest)

Base commit: cd1830f. Phase 1A committed as dc69aa3; Phase 2 uncommitted on the tree.
Scope: Phase 1A (the wire) and Phase 2 (the importer). Plan 18d's work is out of scope.

Layers in scope: sync protocol (schemas, both validators, fixtures, PROTOCOL.md),
state/watch (inbox), core/services (importer), data/models (WatchInboxEntry).
Layers skipped: none relevant — no repository/model/table change claimed.

## Findings

Diff vs Predicted Files: conforms. Phase 1A (dc69aa3) touched exactly the wire files the plan's
`## Files Affected` names; Phase 2 touched `watch_session_importer.dart` and the three test files. The
only unpredicted touches are inside predicted files. No predicted file is untouched except
`test/sync_protocol_fixtures_test.dart` and `SyncProtocolFixturesTests.swift`, which the plan marks
"(no edit)".

F-1 🟡 WARNING | `lib/core/services/watch_session_importer.dart:791-796` | the `_placed` fill for rows the
effort already holds resolves the index with `rows.indexOf(entry)`, which returns null on the
same-stamp ambiguity, so a rest naming one of two same-millisecond sets in a user-row effort is
dropped **and** consumed with no test pinning it | add one test to the `the wrist's rests (D-210)` group
in `test/watch_session_import_test.dart`: an effort with a user row, two same-stamp sets and a rest →
the rest is absent and the row is consumed (not retried) | @developer

F-2 🟡 WARNING | `lib/state/watch/watch_session_inbox.dart:192` | the new `kindRest` entry in
`_requiredFields` has no negative test — the `what the inbox stages (D-132)` group's "a snapshot entry
missing its kind's fields is not staged" case covers `effort_rating` and `session_end` only | extend
that case (or add one) with a rest missing `afterEntryId`, staged through `stageWatchInboxEntry` as A-11
does, since the wire refuses such a row | @developer

F-3 🟡 WARNING (4g) | `docs/plans/…-18c-watch-rest-to-phone-plan.md:211` | the Impact row's reader list is
incomplete and its line drifted: `workout_session_list_view.dart:607` is now a doc comment (the read is
via `_getMostRecentOpenRestKey`), and the rows omit `workout_session_global_timer.dart:45,81`,
`lib/features/session/session_core_io.dart:104,175,247`, `lib/state/workout/timer_manager.dart:49` and
`lib/state/workout/workout_state.dart:90`, all of which read `getEntryRests` | I checked every one: each
filters `rest.restEndMs != null` out before using a row, so an imported closed rest cannot enter the
global rest chip, and `test/watch_capture_repository_parity_test.dart:1210` iterates `watchKinds` and is
green — but add the reader set to the Impact table, and pin the closed-rest invariant with one assertion
on the global timer path | @developer / planner

F-4 💡 SUGGEST | plan `:68`, `:389`, `:450` | three lines assert "18c changes no Swift" / "No Swift change in
this plan", yet `:399` lists `SyncProtocolValidator.swift` in Production and Phase 1A changed it (+27); the
plan's own `:347` also requires `swift-test` | correct the three sentences — AC7 holds empirically (the
governor's `swift-test` at dc69aa3 → 376 / 0, recorded in the evidence file), so only the rationale is
wrong | planner

F-5 💡 SUGGEST (4d) | `docs/rest_tracking.md:240-241` | "no rest row is imported from the wrist" now
understates the phone — the importer writes one (S-320 in `test/watch_session_import_test.dart`) — but
nothing arrives end-to-end until 18d, so the sentence is narrowly true today and the governor
deliberately restored it | no action in 18c; 18d's R-6 must make it true, and its remedy then is delete
the prose and point at the test, not rewrite it | planner (18d)

## Assumption Log adjudication

A-7 RATIFY · A-8 RATIFY (verified: `_mergeHeld` names each written rest's effort in `changedEffortIds`,
`_Pass.run` reports it through `historyChanged`) · A-9 RATIFY (S-326 pins `kindRest` out of `_effortKinds`)
· A-11 RATIFY. A-10 **REVERT in part**: `docs/watch_session_capture.md` was corrected, but the third
sentence — in `docs/rest_tracking.md` — was not; the governor restored that file and plan 18d owns it.
Record the governor's scope decision in the Assumption Log so the entry stops claiming a correction that
did not happen.

## Guards proved red at the base

`prove-red dc69aa3 test test/watch_session_merge_test.dart` → RED AT dc69aa3, +28 -12 (all six D-210
scenarios fail on both Mock and Hive). `prove-red dc69aa3 test test/watch_session_rest_timer_append_test.dart`
→ RED AT dc69aa3, +1 -1 (S-320 fails, S-110 passes). The import group's guard cannot be proved red by
`prove-red` because `kindRest` does not exist at the base; the implementer's two mutation proofs in
`.evidence.md` stand in. Tree verified restored after both runs.

