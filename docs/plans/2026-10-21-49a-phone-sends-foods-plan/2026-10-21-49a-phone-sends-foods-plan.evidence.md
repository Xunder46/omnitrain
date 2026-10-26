# Evidence — plan 49a (the phone sends the food list)

Proof date: 2026-10-21 (lead: unit tests, mutation pass, watch build). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7101 a `routines` request is answered with `preferences_down`, `routines_down`, `foods_down`, then the exercise batches, in that order | group `S-7101…S-7105 the phone sends the food list with the routines` · `S-7101 the preferences, the routines, the foods, then the exercise batches travel in that order` | `test/watch_sync_request_handler_test.dart` |
| S-7102 the `foods_down` payload carries the library's foods in the Foods-I-Eat order with `foodId`, `name`, `caloriesPerServing`, `defaultServings`, and validates | same group · `S-7102 the foods travel in the Foods-I-Eat order, with the phone's own serving values, and the frame validates` | `test/watch_sync_request_handler_test.dart` |
| S-7103 a wrist that already holds the exercise version still receives the foods | same group · `S-7103 a wrist that holds the exercise list still receives the foods` | `test/watch_sync_request_handler_test.dart` |
| S-7104 a phone with no foods sends no `foods_down` and still sends the rest | same group · `S-7104 a phone with no foods sends no foods frame and still sends the rest` | `test/watch_sync_request_handler_test.dart` |
| S-7105 an undelivered `foods_down` does not stop the exercise batches | same group · `S-7105 a foods frame the radio refuses does not stop the exercise batches` | `test/watch_sync_request_handler_test.dart` |

Count: 5 tests, one group.

## Verified

- The five tests above green (lead, 2026-10-21), as part of the series' unit-test run.
- Governor mutation pass over the series: 12 of 12 mutants red.
- `WatchSyncRequestHandler` takes a required `FoodLibraryState foodLibrary` and `createWatchSync` passes it (seen in `lib/state/watch/watch_sync_request_handler.dart` and `watch_sync_wiring.dart` this run, working tree).

## Not verified

- The two devices live: the Simulator could not be driven. Owner checks: the food list arriving on the watch, and a watch log reaching the phone's day log.

## Docs

- `docs/state_management/watch_surface.md`, `WatchSyncRequestHandler` section: the answer now names `foods_down` (only with foods; before the version early return; a refused frame does not stop the batches) and cites S-7101..S-7105.
