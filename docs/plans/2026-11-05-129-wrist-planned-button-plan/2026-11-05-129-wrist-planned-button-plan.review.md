# Review: 2026-11-05-129-wrist-planned-button-plan · P1a, P1b, P2, P3, P4 · 22376d7e81ff98ecf6ba72e4f76a992390185d22..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 0 · minor 2 · tests: lead ran them — `flutter test`: All tests passed! (+6783, ~2 skipped); `swift test`: Executed 1220 tests, with 0 failures; watch app target xcodebuild: BUILD SUCCEEDED. This run did not re-run them (brief: the lead already did); `flutter analyze` not re-run per the brief (lead: 181 issues, pre-existing).
Diff vs Predicted Files: conforms. The plan names every modified file and every untracked file (2 schemas, 1 new Swift source, fixtures, 2 new test files, docs) inside its write scopes; no file outside them appears in the diff stat.

## Findings

1. [Blocker] lib/state/watch/watch_session_adoption_bridge.dart:819 — `onSessionStarted` never judges the report
   before writing: no `SyncProtocolValidator`/`evaluateOrAccept` call exists in the bridge's path and the router forwards
   the raw envelope straight through (`watch_incoming_router.dart:178`–`:180`), so a non-conformant `session_started`
   frame — from a surface that bypasses the wrist's own `emitSessionStarted` gate, or a replayed durable frame — reaches
   the write path with defaults filled in. Plan D-8972 says "The report is judged conformant before anything is written";
   P1b item 4 says "conformant first" — the decision's guard is missing on the only receive path this unit added.
   Fix: before the `_namedSession` step, run the envelope through the receiver-side conformance check the phone's other
   wrist-frame receive surfaces use (the shape `session_started.schema.json` declares), return on refusal, keep the
   try/`_onFailure` wrapper. Guard: a Dart test feeding the S-8968 reject shapes (extra field / missing `sessionId` /
   phone origin) to the bridge or a live `WatchSyncGraph` asserting no row is written and no plan link changes —
   `test/watch_session_adoption_bridge_test.dart` or `test/watch_session_import_test.dart`.

2. [Minor] docs/state_management/watch_surface.md (~:362, the buildPlannedDown paragraph) — "a tap starts it through the
   same routine path the rows use": only a routine plan takes `startFromRoutine`; a free plan takes `startFreeWorkout`
   (D-8964; the paragraph's own cited `testS8967StartPlannedStartsTheRoutineAndReportsPlanAndRoutine` covers the routine
   case only). A maintainer would wire a free-plan start on the routine path.
   Fix: one clause ("a routine plan takes the same routine path the rows use, a free plan the free start"). Guard: none
   (docs sentence).

3. [Minor] watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:443 — `applyPlannedDown` leaves `storedPlans`
   unchanged when the just-written catalog row fails to re-parse (`try? WatchPlannedDown(catalog:)` → nil), while
   `restore` (:405) empties `storedPlans` on the same failure. On a corrupt row the surface keeps showing a plan the
   store can no longer read back. Unreachable today (the row was written by the same parser), so a recovery-shape
   inconsistency, not a user-visible bug.
   Fix: on that nil branch also clear `storedPlans` (one line, matching `restore`), or state the choice in a comment.
   Guard: extends `WatchPlannedRecordsTests`' relaunch row with a corrupt `plannedCatalog` row.

## Docs delta
`watch/sync_protocol/PROTOCOL.md` planned_down row -> applied (message-table row plus notes sentence names the fixtures and the since-gate exemption; ties to S-8960/S-8972, both covered)
`watch/sync_protocol/PROTOCOL.md` 1 (amended) -> applied (the 2026-11-06 amendment row names the five fixtures, the exemption and the closed payloads)
`docs/state_management/watch_surface.md` buildPlannedDown -> applied (names the testS8965 source tests and the same-path start test; wording gap -> finding 2)
`docs/state_management/watch_surface_wrist.md` "Today's planned workout is the surface's first control." -> applied (names the five planned source tests; the "revision refresh" clause cites two pre-existing tests — names not verified this run)
`docs/watch_session_sync.md` WatchSessionAdoptionBridge.onSessionStarted -> applied (Structure row names the seam and four test/watch_session_import_test.dart test names, all seen in that file's diff; D-8977's "no efforts in the row" placed as a parenthetical — true of `_startSessionRow`)
`docs/watch-app-setup-and-qa.md` "The Planned button's" -> applied (names `WatchSessionStartPathsTests.testS8967ATapWhileASessionIsLiveEmitsNothingAndReturnsTheHeld`, seen in the Swift test diff)
`watch/contract/watch_start_paths_contract.json` plannedStart -> applied (read by both suites)
`watch/contract/watch_start_paths_contract.json` routinesPlans -> applied ("planned": true, read by both suites)

Doc edit the table does not name: docs/README.md gained the index link for the new part page
(docs/state_management/watch_surface_wrist_logging.md, whose header says "Split out 2026-11-06 (plan 129)"). Unlisted
but needed — the parent page lost ~477 lines to the split, so the index had to name the new file; no false sentence in
the new page's spot checks this run. Flag for the owner: the split itself was not a Docs delta row.

## Assumption Log rulings
Plan's Assumption Log is empty; none raised this run. Nothing to ratify, revert or escalate.

## Scenario coverage
S-8960, S-8961, S-8962 -> test/watch_reference_sync_test.dart (the builder's tests, seen in the diff, matching the
  plan's expectations; exact test-name spellings not copied verbatim — not checked)
S-8963 -> test/watch_session_import_test.dart · "S-8963 a startable plan opens the row and reports the link, Mock and Hive"
S-8964 -> test/watch_session_import_test.dart · "S-8964 a free start is adopted with nothing linked";
  "S-8964 a missing plan, an empty id and a held session behave (Mock and Hive)"
S-8964b -> test/watch_session_import_test.dart (the Hive sibling group, seen in the diff)
S-8965 -> WatchSessionStartPathsTests.swift (the D-8963 table) + WatchPlannedSurfaceSourceTests.swift ·
  testS8965ThePlannedButtonComesBeforeTheRoutineList, testS8965ThePlannedButtonWearsBorderedAndTheRoutineStaysProminent,
  testS8965ThePlannedCaptionCountsThePlans, testS8965ThePlanPickerSheetAndItsStateExist
S-8966 -> watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedRecordsTests.swift (newest-wins on the down frame, the
  second frame's "B" wins, relaunch via restore() on the injected clock, both reject shapes before storing)
S-8967 -> WatchSessionStartPathsTests.swift · testS8967StartPlannedStartsTheRoutineAndReportsPlanAndRoutine,
  testS8967ATapWhileASessionIsLiveEmitsNothingAndReturnsTheHeld
S-8968 -> WatchSessionEngineTests (the emitted frame passes validateEnvelope; the three reject shapes each fail)
S-8969 -> WatchPlannedSurfaceSourceTests.swift · testS8969ThePlannedCopyLivesInWatchStartSurfaceCopy, plus the
  first-button/bordered/caption/picker source assertions
S-8970 -> WatchBridgeQueueTests (the queue row behind live session frames, delivered in order)
S-8971 -> test/watch_session_import_test.dart · "S-8971 last write wins, and the store reads the link back after a restart, Mock and Hive"
S-8972 -> test/watch_sync_request_handler_test.dart · "S-8972 a since-current wrist is still sent the plans frame, and
  the frame rides the answer the request built"; "S-8972 the plans frame is never served from referenceText: a plan
  started between two since-current requests is gone on the second"; "S-8972 a wayside plans frame the radio refused
  still lets the exercise list through"

Premise-moved tests (verified in their diffs, legitimate): test/watch_transport_test.dart (S-003's frame order gains
planned_down after the bundle, before the exercise batches); test/watch_sync_changed_only_test.dart S-9202 and
test/watch_sync_idle_reads_test.dart S-10405 (an idle/since-current answer carries plans + bests; the idle raise's
templateReads count moves 0 -> 1 because the plans frame reads the plan's template for its name, per D-8961);
watch_sync_idle_reads_test.dart S-87c-17 ("only the plans travel").
