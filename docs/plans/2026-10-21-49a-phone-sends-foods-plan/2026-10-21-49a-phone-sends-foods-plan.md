# Feature: 49a — the phone sends the food list to the watch

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE). Handler tests S-7101..S-7105; 12 of 12 series mutants red. Swift 688/0, Flutter +5411 (one unrelated flaky test, S-5115, fails in some full runs and passes alone), analyze 180 (baseline). Series: `docs/plans/2026-10-21-49-watch-food-and-rest-series.md`. Scout: `.work/crew/2026-10-21-49/scout-food.md` Q2.

## Decision Ledger

- D-1 `WatchSyncRequestHandler` (`lib/state/watch/watch_sync_request_handler.dart`) gains a required `FoodLibraryState foodLibrary` and, in `_sendRoutines`, sends `WatchReferenceSync.buildFoodsDown(foods: foodLibrary.foods, groups: foodLibrary.foodGroups, generatedAt: _clock())` after `routines_down` and BEFORE the exercise batches and their version early return (so a wrist that already holds the exercise list still gets the foods). The send result is not awaited for success: a refused foods frame must not stop the exercise batches (the next sync re-sends).
- D-2 If the phone has no foods (`foods` empty) nothing is sent for foods (the wrist keeps what it has; check `watch/sync_protocol/schemas/messages/foods_down.schema.json` for `minItems` and say which rule you found).
- D-3 `createWatchSync` (`lib/state/watch/watch_sync_wiring.dart:~271`) passes `foodLibrary: foodLibraryState` (already a parameter of `createWatchSync`).
- D-4 Not in scope: the wrist (49b), a separate `foods` request, caps or favourites filters (the phone's Foods-I-Eat order decides), the wire.

## Scenarios (ids S-7101.. checked free)
In `test/watch_sync_request_handler_test.dart` (its harness; add a `FoodLibraryState` built the way `test/watch_nutrition_quick_log_test.dart:~177` builds its library, over `MockWorkoutRepository`):
- S-7101 a `routines` request is answered with `preferences_down`, `routines_down`, then `foods_down`, then the exercise batches, in that order (assert the sent types in order).
- S-7102 the `foods_down` payload carries the library's foods in the Foods-I-Eat order with `foodId`, `name`, `caloriesPerServing`, `defaultServings` (compare with `buildFoodsDown` called directly with the same inputs: equal after stripping `generatedAt`/`messageId`), and it validates (`SyncProtocolValidator`).
- S-7103 a wrist that already holds the exercise version still receives the foods (version early return does not skip them).
- S-7104 a phone with no foods sends no `foods_down` and still sends the rest.
- S-7105 an undelivered `foods_down` does not stop the exercise batches.
Mutation list: foods sent after the early return, foods always sent when empty, a foods failure breaking the batch loop.

## Phases
P1 (crew-builder-app, 5 items): tests first, handler, wiring, existing tests' constructor calls, docs-free. Scope: `lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_sync_request_handler_test.dart`, every test file that constructs `WatchSyncRequestHandler(` (grep). Docs keeper after 50b (one run for the series).
