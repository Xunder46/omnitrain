# The Watch Surface — Nutrition and Water

**Scope.** The phone↔watch food and water logging half of the live mirror:
`WatchNutritionState`, the wrist's food list, `WatchWaterState` and
`WatchNutritionLogBridge`.

> Part of [State Management & Services](../state_management.md), split from
> [The Watch Surface](watch_surface.md) on 2026-11-02 to keep that page under
> the size band. Nothing was dropped: the four sections below moved verbatim.

### `WatchNutritionState`

**Files**: `lib/watch/nutrition/watch_nutrition_state.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`

The wrist's quick-log: the food list the phone sent down, the food and portion
the user has picked, and the observation confirming them produces. It owns no
storage of its own — the synced list is a `WatchFoodCatalogRecord`, the
wrist's own usage is derived from `WatchSessionEngine.nutritionLog`, and the
log itself goes through `WatchSessionEngine.logNutrition`, so a quick-log is an
observation rather than a parallel pipeline.

A quick-log is the one log on the wrist that needs no session: eating is not a
training event, and `observations_up` requires a `sessionId`, so a log taken
with no workout running carries the day's nutrition-log id
(`WatchNutritionSession`) while one taken mid-session rides that session. It is
not acknowledged by a snapshot: the phone's mirror does not hold a nutrition
session, so the entry never comes back that way, and confirmation comes from
the `receipt` message the phone sends instead. The portion control's detents
and bounds are not the wrist's to choose:
`watch/contract/watch_nutrition_contract.json` carries them and both clients'
suites assert against it.

`select` starts a food at its own starting amount: the `defaultServings` of the
wrist's newest `engine.nutritionLog` observation for that food when the log's
`loggedAt` is later than the held catalog's `generatedAt`, and the catalog's
value otherwise — compared on every read rather than stored beside the list, so
a relaunch keeps it and a list the phone generated after the log wins
(`WatchNutritionFreshnessTests.testS8302ALogBecomesTheFoodsStartingAmount`,
`…testS8303ANewerListWinsAndAnOlderOneDoesNotRevertALog`,
`…testS8304ARelaunchKeepsTheDerivedStartingAmount`,
`…testS8306ALogOlderThanTheCatalogKeepsTheCatalogsAmount`,
`…testS8315ASelectionClampsTheListedAmount`). `deselect()` clears the selection,
puts the portion back to `minServings` and drops the confirmation, so the next
food opens at its own amount
(`…testS8301LeavingAFoodClearsItAndTheNextOneOpensAtItsOwnAmount`,
`…testS8313DeselectingNothingChangesNothing`); a list that no longer carries the
selected food clears it the same way
(`…testS8314ANewerListThatDropsTheSelectedFoodClearsTheSelection`).
`onFoodsChanged` is called at the end of `restore()`, on a `foods_down` that was
applied and on no other — a dropped, refused or unreadable one stays quiet —
and after a log that becomes a new starting amount
(`…testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges`); the model holding
it is the host's one, so the observer survives a body pass
(`WatchNutritionWiringSourceTests.testS8311TheHostOwnsTheOneNutritionModel`,
`…testS8318TheMenuPushesTheHostsNutritionModel`).

Verified by `test/watch_nutrition_quick_log_test.dart` (S-001 to S-006) and by
watchOS `WatchNutritionQuickLogTests` and `WatchNutritionFreshnessTests`.

### The wrist's food list, and why its order is the phone's rule

The watch shows the phone's Foods I Eat list in the phone's order — categories
alphabetically, foods the phone files under nothing last, foods alphabetically
inside each — because the phone owns the catalog and the cut of it the user
eats. That rule lives once, in `lib/core/utils/foods_i_eat_order.dart`, as the
`foodsIEatSections` function the phone's `NutritionScreen` renders; the wrist's
`deriveWatchFoodList` applies the same rule to the synced rows and then lifts
what the wrist itself logged most recently to the front, the same shape
`deriveFallbackExercises` uses for the offline exercise list.

Two implementations rather than one because the inputs differ: the phone has
`Food` and `FoodGroup` rows, the wrist has the protocol's row maps. The values
they must agree on are pinned by `watch/contract/watch_nutrition_contract.json`
— phone order, wrist order after a known log history, and the portion bounds —
which `test/watch_nutrition_quick_log_test.dart` (S-003) and watchOS
`WatchNutritionQuickLogTests.testTheWristDerivesTheContractsOrder` both read.
A change to the ordering on either platform therefore fails the other's suite.

### `WatchWaterState`

**File**: `watch/watchos/Sources/WatchSessionEngine/WatchWater.swift` (wrist
only; the Dart twin emits no taps)

The day's glasses on the wrist. It stores no count: `glasses` is computed on
every read — the newest `water_down` frame's count when its `day` is the wrist's
local today, else 0, plus the wrist's own taps of that day the frame's
`appliedTapIds` does not list, never below 0
(`WatchWaterStateTests.testS94b7ThePhonesCountPlusTheWristsUncountedTaps`). A
receipt does not take a tap out; the frame's list does
(`…testS94b12TheReceiptArrivesTheFrameIsLost`). `press(_:)` stores one
`water_glass` tap under the day's nutrition id, never a workout's
(`WatchWaterStoreTests.testS94b2APressWhileASessionIsHeldNeverJoinsIt`), and
none once the day's taps reach `WatchWaterLimits.tapsPerDay`
(`…testS94b15TapsPastTheCap`). The host owns one state and one
`WatchWaterModel` (`WatchWaterBarSourceTests.testS94b23TheHostOwnsOneWaterStateAndOneModel`);
the watch's Nutrition screen carries the water count
(`…testS94b22TheBarIsOnTheListOnlyEmptyListIncluded`).


### `WatchNutritionLogBridge`

**File**: `lib/state/watch/watch_nutrition_log_bridge.dart`

The phone's half of a quick-log: it turns the wrist's `nutrition_quick_log`
events into the phone's own day log through `NutritionState.logConsumedFoodAt`,
or through `NutritionState.logConsumedFoodOnDay` when the wrist's `loggedAt` lies on an
earlier local day than the bridge's clock (a log tapped at 23:55 and delivered after
midnight keeps the day it was tapped).
A quick-log is filed by the phone's rule, not the bridge's — one row per food
per day means a redelivered message updates the row it made the first time, so
"exactly once" needs no ledger of its own. A food the library no longer holds is
reported rather than guessed at: with no food there are no macros to freeze onto
a row.

It is also the sender of the `receipt` that acknowledges those observations —
including the ones it could not place, since what a receipt asserts is that the
phone holds the observation, not that the day log changed. It answers a message
it refused to read with nothing at all. What the wrist does with the receipt is
`WatchSessionEngine.confirmObservations` — an append of its own, so a relaunch
can still tell what it may drop. The Swift wrist does not prune after a
receipt: `pruneConfirmed` has no production caller there
(`WatchWaterBarSourceTests.testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps`). The receipt, and that a
confirmed row is then droppable, are exercised by
`test/watch_nutrition_quick_log_test.dart` ("the phone’s receipt is what lets the
watch drop the row", "a food the phone cannot place is not owed forever") and by
`WatchNutritionQuickLogTests.testThePhonesReceiptIsWhatLetsTheWatchDropTheRow`.

The other half of the same problem is on the mirror: `LiveSessionMirrorState`
ignores any message it consumes whose `sessionId` is not the session it holds
(`session_snapshot` excepted), because a quick-log taken with no workout running
names the day, and filing a meal under a workout is worse than dropping it.
