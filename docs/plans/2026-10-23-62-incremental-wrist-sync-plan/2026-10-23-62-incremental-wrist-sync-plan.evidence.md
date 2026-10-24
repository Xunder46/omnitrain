# Evidence: 62 — a wrist raise no longer re-sends what the watch already holds

## Phases

| Phase | Run | What |
|---|---|---|
| P1 | crew-builder-app | `WatchTransportRequest.sinceOf` (D-2), the `since` hand-off in `watch_sync_wiring.dart` (D-3), the bundle stamp and new frame order in `WatchSyncRequestHandler` (D-4), `test/watch_sync_changed_only_test.dart` S-9201..S-9212, S-7101/S-7103/S-7105 updated |
| P2 | crew-builder-watch | the Sync button asks for everything, `requestSync` -> `sync(reconnect: false)` (D-5), `watch/sync_protocol/PROTOCOL.md` (D-6), `WatchManualSyncSourceTests` S-9220 |
| P3 | crew-docs-keeper | `watch_surface.md` (the handler section), `watch_reference_data.md` ("Where the two ends stand"), `watch-app-setup-and-qa.md` (QA step 23), this evidence file |

## Governor read-backs (observed by the lead)

- Dart tests of the 7 touched files: 190 passed.

## Mutation pass (observed by the lead)

15 mutants: 13 killed, 1 equivalent (an empty string parses to null anyway), 1 alive — the `since:` hand-off in `watch_sync_wiring.dart` — closed by fix 1 (S-9213) and then killed.

## Fix 2 (D-8) — no spinner on an incremental catch-up

Plan 62 made the phone send nothing when the wrist already holds the current
bundle. The wrist's "syncing" window (plan 55) ends only when `routines_down`
arrives (cap 20 s), so a wrist that already holds a routines catalog
(`paths.syncedAt != nil`) no longer opens the window on its automatic catch-ups
(activation, reachability edge): there is nothing to wait for, and data that did
change arrives silently. A wrist that holds nothing (first sync) still shows the
spinner, and the Sync button always opens the window and always asks for
everything. Tests: `WatchSyncProgressWiringTests.testS8508CatchUpBeginsOnlyWhenReachable`
(updated to the new exact statements) and
`…testS9221AnIncrementalCatchUpOpensNoWindow`. Evidence (observed by the lead):
swift package suite 874 tests, 0 failures (it includes other sessions' new
tests); 5 mutants of the gates (edge ungated, activation ungated, both inverted,
button gated) all killed; the spinner defect was found by the lead reading
`WatchSyncProgress.swift` after the first build, before review.

## Not verified (owner)

- Both plans' device checks: raise twice, change a setting then raise twice, add a routine, tap Sync — QA step 23 in the PR 2b list (`docs/watch-app-setup-and-qa.md`). The iOS simulator does not deliver watch-to-phone transfers, so the end-to-end is an owner check.
