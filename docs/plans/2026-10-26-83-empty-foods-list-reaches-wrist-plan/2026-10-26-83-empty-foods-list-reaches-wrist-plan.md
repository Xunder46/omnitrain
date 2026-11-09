# Feature: 83 — a phone whose Foods I Eat list was emptied tells the wrist, so the wrist stops offering foods the phone no longer has

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Mutations: drop the `_foodsReadOk` guard (S-8310 red), `_foodsFrame` always null (S-15203/S-15204/S-3850… red), schema `minItems` restored (S-15201, S-15204, S-15209 red). Accepted risk (review minor 1): a food load that fails inside the UI while a sync request is between its reload and its frame build could make the phone send an empty list once; the next sync corrects it. Fixing it means changing `FoodLibraryState`'s empty-on-failure behaviour, out of scope. Earlier status: PLANNED 2026-10-26 (seeded by the lead, architect complete — run P2 first, then P1). Base commit: `.work/2026-10-26-83/base.txt`. Team: the crew. Owner request (chat, 2026-10-26, "I'll go with your suggestions", audit finding W4). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## What the owner sees

| Moment | Today | After |
|---|---|---|
| The phone's Foods I Eat list is emptied (all foods removed or archived), then the wrist syncs | the wrist keeps showing, and logging, the old foods; entries land on days that show nothing on the phone | the wrist's food list becomes empty and shows the existing empty line that points at the phone's "Choose foods" button (plan 78) |
| A phone that never had foods | wrist: empty list | unchanged |
| The phone cannot read its foods at that moment (storage read throws) | the wrist keeps what it had | unchanged: nothing is sent; the next successful read corrects it |
| Foods unchanged since the wrist's last sync | nothing sent | nothing sent (the empty frame is not repeated every time) |

(owner) To see it on a device: phone, Nutrition, remove all of Foods I Eat, then raise the wrist: the wrist food list is empty with the "Choose foods" line.

## Decision Ledger

- D-1 The schema allows an empty list: `watch/sync_protocol/schemas/messages/foods_down.schema.json` `payload.foods` loses `"minItems": 1` (becomes `0`, i.e. the key is removed or set to 0). Both validators read this one file (the generic array-constraint readers `lib/core/sync_protocol/message_validator.dart:900-905`, `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:773-776`), so no validator code changes. The report's claim "the schema already tolerates empty arrays" was true for `categories` only; this decision is the real work.
- D-2 `watch/sync_protocol/PROTOCOL.md` gets an amendment row dated 2026-10-26 in the style of the 2026-10-11 row for `routines_down` (`:731`): `foods_down.payload.foods` MAY be empty, no new field, no version change; nothing a v1 client sends correctly becomes invalid; names the new valid fixture and the walks (`test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift`). The message-table row (`:70`) is unchanged except it no longer implies a non-empty list. `PROTOCOL.md` is outside the docs keeper's ceiling: it goes to `crew-builder-watch` in a one-file docs-only run (crew rule s).
- D-3 New valid fixture `watch/sync_protocol/fixtures/valid/foods_down_empty.json` (copy of `valid/foods_down.json` with `"foods": []` and `"categories": []`) registered in `watch/sync_protocol/fixtures/manifest.json` (crew rule bh: the manifest is in the builder's scope). Is there an invalid fixture that asserts an empty list is refused? The architect greps `fixtures/invalid` and `foods_down` in both fixture walkers and lists it; if one exists it is removed in this unit.
- D-4 Phone handler `lib/state/watch/watch_sync_request_handler.dart`: `_foodsFrame(at)` (`:262`) returns today `null` when `_foodLibrary.foods.isEmpty`. It becomes: non-empty -> the frame as today; empty AND the last `_reloadFoods()` succeeded -> `WatchReferenceSync.buildFoodsDown(foods: const [], groups: const [], generatedAt: at)` (the builder `lib/core/utils/watch_reference_sync.dart` must accept empty lists; the architect checks and names any guard); empty AND the last read failed (or none was done) -> `null`. A new private field `_foodsReadOk` is written by `_reloadFoods()` (`:223-231`: `true` after the two loads return at `:225-226`, `false` in the `catch` at `:228-230`). Rule: never tell the wrist "no foods" from a cache the phone could not read.
- D-5 Every bundle build reloads the foods first (`_sendRoutines`: `:139-145` when storage changed, `:180` when the wrist lacks the bundle). The architect confirms there is no path to `_bundle` / `_foodsFrame` that skips a reload, and otherwise adds the reload there.
- D-6 `_held.referenceText` (`:149-157`) is built from `_foodsFrame(DateTime.utc(1970))` (the arm at `:156`). With D-4 an empty-and-readable library now contributes an empty frame to that text, so the stamp changes once when a phone first runs this build (the same as a relaunch, S-9212). Re-sends are still gated by `since.isBefore(stamp)` and `_held` (S-15207).
- D-7 The wrist applies an empty `foods_down` through the existing path (`WatchNutritionState.applyFoodsDown`, `WatchNutritionState.swift:160-193`, `applyCatalog` at `:195-202`; `WatchFoodsDown(envelope:)`, `WatchFoodCatalog.swift:130-160`, `init(envelope:)` at `:143`, parses `foods` with `?? []` at `:153`). The stale-frame guard `sent.generatedAt < catalog.generatedAt` stays. The Dart Wear twin (`lib/watch/nutrition/watch_nutrition_state.dart`, `lib/watch/nutrition/watch_food_catalog.dart`) must also apply an empty list; the architect checks and adds a test only if it differs.
- D-8 Not in scope: any change to which foods the phone counts as Foods I Eat; the exercise or routine frames; the wrist's empty-state wording (plan 78); the `readFailed` memo semantics (`:151`, `revision: readFailed ? null : revision`) stay as they are.

## Scenarios (exact fixtures; re-derive in the first run)

- S-15201 fixture `valid/foods_down_empty.json` conforms to `foods_down` in Dart (`test/sync_protocol_fixtures_test.dart`, the walk over `fixtures/valid`) and in Swift (`SyncProtocolFixturesTests.testEveryValidFixtureConforms`). Fails today with `constraint_violation` at `$.payload.foods`.
- S-15202 `valid/foods_down.json` with one food mutated to drop `foodId` is still refused (`invalid/foods_down_missing_food_id.json` unchanged and green): the guard on a food's fields did not loosen.
- S-15203 handler, phone had foods and has none now: harness of `test/watch_sync_changed_only_test.dart` (`libraryWithFoods`, a revision bump after removing every food): the next `routines` request from a wrist holding the old stamp sends `preferences_down`, THEN `foods_down` with `payload.foods == []`, THEN `routines_down` (order `_referenceFrames`). Fails today: no `foods_down` is sent.
- S-15204 handler, phone that never had foods and whose read succeeded: one empty `foods_down` frame in the bundle (replaces the premise of S-7104 below).
- S-15205 handler, the food read throws (`throwOnFoods` in `test/watch_sync_request_handler_test.dart:153-158`) on a phone whose cache is empty: NO `foods_down`; `preferences_down` and `routines_down` are still sent (the stamped bundle is carried without foods). Guard for the data-loss trap: fails if `_foodsReadOk` is dropped.
- S-15206 handler, the same throw AFTER a successful read that had foods: the cache (non-empty) is what is sent, as today (`S-8316` premise stays).
- S-15207 an unchanged phone answers a wrist whose `since` equals the stamp with none of the three frames (the empty one included), and a second `routines` request with a null `since` re-sends the empty frame once.
- S-15208 wrist (Swift): `WatchNutritionState` holding a non-empty synced catalog applies the `valid/foods_down_empty.json` envelope restamped newer: `syncedFoods == []`, `categories == []`, `onFoodsChanged` called once; an OLDER-stamped empty frame is dropped and the catalog is unchanged.
- S-15209 Dart Wear twin applies the same envelope (add only if the twin lacks a test).

Readers of the contracts this changes (grepped 2026-10-26; the architect re-greps): `test/watch_sync_request_handler_test.dart` — **S-7104 "a phone with no foods sends no foods frame" encodes the OLD rule and is rewritten to S-15204**; S-8308, S-8316 and the `throwOnFoods` harness (`_ThrowingOnceRepository` `:147-166`, field `:150`, throw `:158-161`) read the foods path; `test/watch_sync_changed_only_test.dart` (`_referenceFrames`, S-9206a/b, `libraryWithFoods`); `test/watch_session_projection_test.dart:838-866` (S-9213, `foods_down` isEmpty after a current `since`: still holds); `test/watch_sync_idle_reads_test.dart` (S-10406); `test/watch_link_package_test.dart:225`, `test/watch_connectivity_channel_test.dart:78` (bare `{'type': 'foods_down'}`, unaffected); `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift`, `WatchNutritionQuickLogTests.swift`, `WatchSyncProgressTests.swift`, `SyncProtocolValidatorTests.swift`; `watch/contract/watch_nutrition_contract.json`; `docs/state_management/watch_surface_wrist.md`, `docs/phone_watch_sync` docs (the architect names which docs mention "no foods sends no frame").

## Phases

- P1 `crew-builder-app` — phone: D-4..D-6, S-15203..S-15207, rewrite S-7104. Scope: `lib/state/watch/watch_sync_request_handler.dart`, `lib/core/utils/watch_reference_sync.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_changed_only_test.dart`. Run the changed test files under Mock only (nothing here is stored); no full suite.
- P2 `crew-builder-watch` — contract: D-1..D-3, D-7, S-15201, S-15202, S-15208, S-15209. Scope: `watch/sync_protocol/schemas/messages/foods_down.schema.json`, `watch/sync_protocol/fixtures/valid/foods_down_empty.json`, `watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift`, `test/sync_protocol_fixtures_test.dart`. Serial BEFORE P1's tests can go green (S-15203 needs the schema); the lead runs P2 first, then P1.
- P3 lead — full `flutter test` (900 s timeout), `swift test`, mutation pass (drop `_foodsReadOk`; return `null` always; restore `minItems`), invariant grep.
- P4 `crew-docs-keeper` — `docs/state_management/*` and the sync doc that says "no foods, no frame"; then `crew-reviewer`.

## Assumption Log

- An empty `foods_down` for a phone that never had foods is accepted as harmless (one small frame per bundle, only when the wrist lacks the bundle).
- If the architect finds the Dart builder `buildFoodsDown` cannot take empty lists without a change outside P1's scope, the scope is extended by that one file and said so here.
- RESOLVED (architect, 2026-10-26): `buildFoodsDown` takes empty lists unchanged — see D-9. The conditional scope extension above is not needed.
- RESOLVED (architect, 2026-10-26): no invalid fixture asserts an empty `foods` list is refused — see "Seed open questions, answered" (a). D-3's conditional removal does not apply.

---

## Code pointers (read 2026-10-26; the lines below are the current ones)

`lib/state/watch/watch_sync_request_handler.dart` — `_foodsFrame` `:262-268`:

```dart
Map<String, Object?>? _foodsFrame(DateTime at) => _foodLibrary.foods.isEmpty
    ? null
    : WatchReferenceSync.buildFoodsDown(
        foods: _foodLibrary.foods,
        groups: _foodLibrary.foodGroups,
        generatedAt: at,
      );
```

`_reloadFoods` `:223-231`:

```dart
Future<bool> _reloadFoods() async {
  try {
    await _foodLibrary.loadFoodGroups(includeArchived: true);
    await _foodLibrary.loadFoods();
    return true;
  } catch (_) {
    // Deliberately swallowed — a failed read is no reason to withhold the rest.
    return false;
  }
}
```

`_sendRoutines` `:134-218` — the `_held` memo and the bundle send (key lines):

```dart
139:    final held = _held;
140:    final storageUnchanged =
141:        revision != null && held != null && held.revision == revision;
143:    var readFailed = false;
144:    if (!storageUnchanged) {
145:      readFailed = !await _reloadFoods();
146:    }
149:    final referenceText = storageUnchanged
150:        ? held.referenceText
151:        : jsonEncode([
152:            await WatchReferenceSync.buildRoutinesDown(
153:              repository: _repository,
154:              generatedAt: DateTime.utc(1970),
155:            ),
156:            _foodsFrame(DateTime.utc(1970)),
157:          ]);
170:    _held = (
171:      preferencesText: preferencesText,
172:      referenceText: referenceText,
173:      stamp: stamp,
174:      revision: readFailed ? null : revision,
175:    );
177:    if (since == null || since.isBefore(stamp)) {
180:      if (storageUnchanged) await _reloadFoods();
181:      final bundle = await _bundle(stamp);
182:      final preferences = await _transport.send(bundle.preferences);
184:      final foods = bundle.foods;
185:      if (foods != null &&
186:          await _transport.send(foods) == WatchDelivery.undelivered) {
187:        carried = false;
188:      }
191:      if (carried) await _transport.send(bundle.routines);
```

`_bundle` `:239-247` (`foods: _foodsFrame(at)` at `:246`).

`lib/core/utils/watch_reference_sync.dart` — `buildFoodsDown` `:542-571`: no `isEmpty` guard, no `assert`; `foodsIEatSections(foods: foods, groups: groups)` over empty inputs returns no sections (`lib/core/utils/foods_i_eat_order.dart:32-70`), so empty inputs yield `'foods': []` and `'categories': []`. Accepts empty lists unchanged (D-9).

`watch/sync_protocol/schemas/messages/foods_down.schema.json` — payload `:20-33`; `"foods": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/food" } }` at `:26`; `categories` (`:21-24`) carries no `minItems`. Both validators read the bound generically: `lib/core/sync_protocol/message_validator.dart:900-905`, `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:773-776`.

`watch/watchos/Sources/WatchSessionEngine/WatchFoodCatalog.swift` — `WatchFoodsDown` `:130-160`; `init(envelope:)` `:143-147`; `init(payload:)` `:149-160` parses `foods: try (payload["foods"] as? [[String: Any]] ?? []).map { try WatchFood(json: $0) }` at `:153` — an empty array parses to `[]`.

`watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift` — `applyFoodsDown` `:160-193`: validator gate `:161-163`, stale-frame guard `:172-176` (`sent.generatedAt < catalog.generatedAt` → dropped, `rejections: []`), store + `applyCatalog()` + `onFoodsChanged?()` `:178-192`; `applyCatalog` `:195-202` (`syncedFoods = synced.foods` at `:200`). No empty-list guard anywhere.

Dart twin — `lib/watch/nutrition/watch_nutrition_state.dart` `applyFoodsDown` `:147-192` (stale guard `:160`, record `:174-180`, `_syncedFoods = synced.foods` at `:196`); `lib/watch/nutrition/watch_food_catalog.dart` `WatchFoodsDown.fromPayload` `:118-131` iterates `payload['foods']! as List` — an empty list parses to `[]`. No guard. No existing test applies an empty `foods_down` to the twin (grep `applyFoodsDown` under `test/`: every call in `test/watch_nutrition_quick_log_test.dart` uses `_foodsDown()` — the 5-food fixture — or the bare `{'type': 'foods_down'}` refusal at `:872`), so S-15209's test is added.

## Seed open questions, answered

**(a) No invalid fixture asserts an empty `foods` list is refused.** `watch/sync_protocol/fixtures/invalid/` holds exactly one foods fixture, `foods_down_missing_food_id.json` (manifest `:217-221`, `expectedCode: missing_required_field` on `foodId`). Grep `minItems` under `watch/sync_protocol`: the only `foods_down` bound is `foods_down.schema.json:26`; the other `minItems` hits belong to other messages (`envelope.schema.json:88,126,322`, `routines_down.schema.json`, `exercises_down.schema.json:50`, `observations_up.schema.json:20`, `receipt.schema.json:19`, `structure_change.schema.json`). Neither walker has a foods-specific empty case (`test/sync_protocol_fixtures_test.dart:213-233` walks the manifest; `SyncProtocolFixturesTests.swift:31-63` same). Nothing to remove; D-3's conditional is resolved as "none exists".

**(b) No path to `_bundle`/`_foodsFrame` skips a reload (D-5 holds as written).** `_bundle` is called only at `:181`, inside the `since` gate (`:177`), which re-runs `_reloadFoods()` at `:180` when `storageUnchanged`; when `!storageUnchanged` the reload already ran at `:145`, before `referenceText` (`:149-157`) is built. `_foodsFrame`'s only callers are `:156` (reached only when `!storageUnchanged`, so the reload ran) and `:246` (inside `_bundle`). No added reload.

**(c) The Dart twin handles an empty list; no existing test covers it.** Parse and apply go through plain list iteration (`watch_food_catalog.dart:118-131`, `watch_nutrition_state.dart:196`) — S-15209's test is added in P2 (the twin lacks the test, so per S-15209 it is added).

**(d) Docs that say a phone without foods sends no foods frame (docs keeper, P4):**
- `docs/state_management/watch_surface.md:537-538` — "`foods_down` (only when the phone holds foods; the schema requires at least one, so a phone with none sends no foods frame and the wrist keeps the list it has)"; `:581` lists "no foods" among the pinned behaviours.
- `docs/state_management/watch_reference_data.md:175` — "then `foods_down` when it holds foods".
- `docs/state_management/watch_surface_wrist.md` — no such sentence (grep `foods`: `:256`, `:622`, `:633` are cap/redraw/restore statements). The seed's pointer to it is dropped.
- `watch/sync_protocol/PROTOCOL.md:124` — "`foods_down` (omitted when the phone holds no foods)" — amended in P2 (D-2), not P4.
- `docs/state_management/nutrition_state.md:180` describes only the per-request reload; no empty-list claim; untouched.

## Feature invariants

- The wrist's food list mirrors the phone's Foods I Eat as of the last successful reload; the phone never tells the wrist "no foods" from a cache it could not read (D-4).
- An empty `foods_down` is a first-class frame: it travels in the bundle's middle slot, stamped like its siblings, gated by the same `since` rule (D-2, D-6).
- The routines frame stays the commit marker: it is sent only after the preferences and foods frames were carried, empty or not (S-9206b unchanged).
- Nothing here is stored: P1's tests run Mock-only; `MockWorkoutRepository` and `HiveWorkoutRepository` keep identical output (no repository change in this plan).

## Existing-functionality impact

| Touched surface | What already reads it (search run this run) | Effect | Guarded by |
|---|---|---|---|
| `foods_down.schema.json` `payload.foods` | both validators, generically (`message_validator.dart:900-905`, `SyncProtocolValidator.swift:773-776`); walkers `test/sync_protocol_fixtures_test.dart:213-233`, `SyncProtocolFixturesTests.swift:31-63` | empty arrays become valid; no validator code change | S-15201, S-15202 |
| `WatchSyncRequestHandler._foodsFrame` | callers `:156`, `:246`; `test/watch_sync_request_handler_test.dart` (S-3850/3851/3857 `:259-345`, S-7101..S-7105 `:454-618`, S-8308..S-8316 `:620-795`), `test/watch_sync_changed_only_test.dart` (S-9201..S-9212), `test/watch_session_projection_test.dart:814-895` (S-9213), `test/watch_sync_idle_reads_test.dart:292` (S-10406, 2 foods — unaffected) | empty + read-ok now yields a frame | S-15203..S-15207, S-15210 |
| S-7104 | `watch_sync_request_handler_test.dart:568-587` | encodes the old rule; rewritten to S-15204 | S-15204 |
| S-3850, S-3851, S-3857 | `watch_sync_request_handler_test.dart:259-345` (bare `FoodLibraryState`, exact `transport.types` assertions) | encode the old rule; assertions updated to the three-frame bundle (test-only) | S-15204 |
| S-9210 | `watch_sync_changed_only_test.dart:787-825` ("no foods is no foods frame") | first arm encodes the old rule; rewritten (test-only); the "first food changes the signature" arm stands | S-15204 |
| S-9213 | `watch_session_projection_test.dart:815-895`, harness library bare (`:565`) | first arm now also carries an empty `foods_down` (asserts only preferences/routines counts — stays green); "sends none" arm unaffected (the `since` gate precedes any frame) | S-15207 |
| S-8310 / S-8316 | `watch_sync_request_handler_test.dart:700-745` / `:747-795` | unchanged and green: a foods-read throw empties the foods cache before rethrowing (`food_library_state.dart:469-471`) → null; a groups throw empties only `_foodGroups` (`:196-198`) → the non-empty foods cache is sent | S-15205, S-15210 |
| `watch/contract/watch_nutrition_contract.json` | `datasetFixture` `:9` → `valid/foods_down.json` | unchanged (the non-empty fixture stays the ordering dataset) | — |
| bare `{'type': 'foods_down'}` frames | `test/watch_link_package_test.dart:225`, `test/watch_connectivity_channel_test.dart:78` | unaffected (no payload) | — |
| Swift freshness / quick-log suites | `WatchNutritionFreshnessTests.swift:49`, `WatchNutritionQuickLogTests.swift:44,145` build from `valid/foods_down.json` | unaffected (the non-empty fixture is unchanged) | S-15208 |

## New decisions and scenarios

- D-9 No change to `lib/core/utils/watch_reference_sync.dart`: `buildFoodsDown` (`:542-571`) has no `isEmpty` guard or assert, and `foodsIEatSections` over empty inputs returns no sections (`foods_i_eat_order.dart:32-70`), so `buildFoodsDown(foods: const [], groups: const [], generatedAt: at)` returns a valid envelope with empty `categories` and `foods`. D-4's parenthetical is resolved: there is no guard to name. The file is dropped from P1's write scope.
- S-15210 handler, the group read throws (`throwOnGroups`, `_ThrowingOnceRepository` `:152`) after a successful foods read that held foods: the non-empty foods cache is what is sent, uncategorised — S-8316 (`watch_sync_request_handler_test.dart:747-795`) restated as D-4's branch-order guard: the non-empty branch is answered before `_foodsReadOk` is consulted. No new test (S-8316 is the guard); the prover's mutation "a failed read forces null even when the cache is non-empty" turns S-8316 red.

## Phases (expanded)

- P2 `crew-builder-watch` — contract: D-1..D-3, D-7, S-15201, S-15202, S-15208, S-15209. Scope: `watch/sync_protocol/schemas/messages/foods_down.schema.json`, `watch/sync_protocol/fixtures/valid/foods_down_empty.json`, `watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift`, `test/sync_protocol_fixtures_test.dart`. Serial BEFORE P1's tests can go green (S-15203 needs the schema); the lead runs P2 first, then P1.
- P1 `crew-builder-app` — phone: D-4..D-6, S-15203..S-15207, rewrite S-7104. Scope: `lib/state/watch/watch_sync_request_handler.dart`, `lib/core/utils/watch_reference_sync.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_changed_only_test.dart`. Run the changed test files under Mock only (nothing here is stored); no full suite.
- P3 lead — full `flutter test` (900 s timeout), `swift test`, mutation pass (drop `_foodsReadOk`; return `null` always; restore `minItems`), invariant grep.
- P4 `crew-docs-keeper` — `docs/state_management/*` and the sync doc that says "no foods, no frame"; then `crew-reviewer`.

### P2 — crew-builder-watch (contract). Runs FIRST; P1's tests cannot go green before it (S-15203's and S-15204's `validateEnvelope` assertions, and the twin's `_validator()` gate at `test/watch_nutrition_quick_log_test.dart:63-76`, refuse `foods: []` while `minItems: 1` stands).

Write scope: `"watch/sync_protocol/**"`, `"test/sync_protocol_fixtures_test.dart"`, `"test/watch_nutrition_quick_log_test.dart"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift"`.

Items:
1. [ ] Remove `"minItems": 1` from `payload.foods` — `watch/sync_protocol/schemas/messages/foods_down.schema.json` · `payload.foods` (D-1).
2. [ ] Add `watch/sync_protocol/fixtures/valid/foods_down_empty.json` — copy of `valid/foods_down.json` with `"foods": []` and `"categories": []` — and register it in `watch/sync_protocol/fixtures/manifest.json` · `valid` list, beside the `valid/foods_down.json` entry at `:6` (D-3, S-15201).
3. [ ] Add the 2026-10-26 amendment row after `:741` in `watch/sync_protocol/PROTOCOL.md`, in the style of the `:731` row, and replace the `:124` parenthetical "(omitted when the phone holds no foods)" with the empty-frame rule (D-2).
4. [ ] S-15208 test — `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift` · new test beside `testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges` (`:257`), reusing `foodsDown(generatedAt:messageId:foods:)` (`:49-59`) with `foods: []` over the `NutritionHarness`.
5. [ ] S-15209 test — `test/watch_nutrition_quick_log_test.dart` · new test beside the older/newer `applyFoodsDown` tests (`:832-860`, `:1390-1415`), envelope derived from `_foodsDown()` (`:76-79`) with `payload.foods: []` and `payload.categories: []`.
6. [ ] Run the walkers — `test/sync_protocol_fixtures_test.dart` (the manifest walk `:213-233` picks the new fixture up; S-15202's invalid fixture stays green) and `swift test`.

Done criteria: `flutter test test/sync_protocol_fixtures_test.dart test/watch_nutrition_quick_log_test.dart` green; `swift test` green; S-15201, S-15202, S-15208, S-15209 named green.

Predicted files: `watch/sync_protocol/schemas/messages/foods_down.schema.json`, `watch/sync_protocol/fixtures/valid/foods_down_empty.json` (new), `watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift`, `test/watch_nutrition_quick_log_test.dart`. `test/sync_protocol_fixtures_test.dart` is predicted unchanged (the walk is generic) — it must pass, not change.

### P1 — crew-builder-app (phone). After P2.

Write scope: `"lib/state/watch/watch_sync_request_handler.dart"`, `"test/watch_sync_request_handler_test.dart"`, `"test/watch_sync_changed_only_test.dart"`.

Items:
1. [ ] Add the `_foodsReadOk` field and write it in `_reloadFoods()` (`true` after both loads, `false` in the catch) — `lib/state/watch/watch_sync_request_handler.dart` · `_reloadFoods` `:223-231` (D-4).
2. [ ] Make `_foodsFrame` three-branch: non-empty → frame as today; empty && `_foodsReadOk` → `WatchReferenceSync.buildFoodsDown(foods: const [], groups: const [], generatedAt: at)`; empty && !`_foodsReadOk` → `null` — same file · `_foodsFrame` `:262-268` (D-4).
3. [ ] Update the doc comments that state the old rule — same file · `_sendRoutines` doc ("the foods (when the phone has any)", `:121-133`) and `_bundle` doc ("the foods frame is null for a phone with no foods", `:237-239`) (D-4).
4. [ ] Rewrite S-7104 to S-15204 — `test/watch_sync_request_handler_test.dart` · `S-7104` `:568-587`: the bare `FoodLibraryState` (read succeeds, empty) now sends three frames, the middle one `foods_down` with `payload.foods == []` and `payload.categories == []`, `loadProtocolValidator().validateEnvelope(frame)` isEmpty; keep the `batchIndices == [0, 1, 2]` arm.
5. [ ] Update S-3850 (`:276`), S-3857 (`:301`) and S-3851 (`:314`, `:326`) to the three-frame bundle (test-only; each keeps its own reason, the empty frame is now part of every bundle) — same file.
6. [ ] S-15203 — `test/watch_sync_changed_only_test.dart` · new test in the changed-only suite: `libraryWithFoods()` (`:225-243`), first `handle(routines)`, `sentStamp()` (`:257-260`); then `repository.removeFood(id)` for the four ids `food-protein-lamb`, `food-veg-broccoli`, `food-protein-beef`, `food-veg-asparagus` (Mock hard-deletes library foods, `mock_workout_repository.dart:1472-1480`; `getFoods(includeArchived: false)` then returns `[]`, `:1414-1421`); `clock.advance(const Duration(seconds: 7))`, `transport.sent.clear()`, `handle(routines, since: oldStamp)` → `transport.types.take(3) == _referenceFrames`, the middle frame's `payload.foods == []`, `sentStamp().isAfter(oldStamp)`. Red today: the second request sends only two frames.
7. [ ] S-15207 — same file · new test: after the empty bundle, `handle(routines, since: sentStamp())` sends none of the three; then `handle(routines)` (null `since`) re-sends the empty `foods_down` once (`ofType('foods_down')` hasLength 1, `payload.foods == []`).
8. [ ] Rewrite S-9210's first arm — same file · `S-9210` `:787-825`: the empty phone's bundle is now three frames with an empty middle (the "first food changes the signature" arm stands unchanged).

Done criteria: `flutter test test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart` green (Mock only); S-15203, S-15204, S-15205 (= S-8310, `:700-745`, unchanged), S-15206 (see Architect notes 1), S-15207, S-15210 (= S-8316, `:747-795`, unchanged) named green.

Predicted files: `lib/state/watch/watch_sync_request_handler.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_changed_only_test.dart`. Nothing else.

### P3 — lead. After P1 and P2.

Full `flutter test` (900 s timeout), `swift test`, then the mutation pass, each mutation proven red by the named guard:
- drop `_foodsReadOk` (empty always sends the frame) → S-8310/S-15205 red (`watch_sync_request_handler_test.dart:730`);
- `_foodsFrame` returns `null` always → S-15203, S-15204 and the rewritten S-3850 red;
- restore `"minItems": 1` → S-15201 red and the handler tests' `validateEnvelope` assertions red (`:488`, `:648`, `:791` pattern).
Invariant grep: no `foods.isEmpty` branch left that returns `null` without consulting `_foodsReadOk`.

### P4 — crew-docs-keeper. After P1 and P2; then crew-reviewer.

`docs/state_management/watch_surface.md:537-538` and `:581`, `docs/state_management/watch_reference_data.md:175` to the new rule, every behaviour sentence naming an existing test (S-15204, S-15203, S-15207). `watch_surface_wrist.md` untouched (no such sentence — see (d)). Files under `docs/` stay below 52 KB.

Parallelism: no phase runs in parallel. P2 → P1 serial (the schema gate); P3 after both; P4 after P1+P2 (the docs cite P1's tests). P1 and P2 touch disjoint files, but the order is serial because P1's Done Criteria need P2's schema.

## Progress

| Item | Phase | Status |
|---|---|---|
| D-1 schema `minItems` removed | P2 | [ ] |
| `foods_down_empty.json` + manifest | P2 | [ ] |
| PROTOCOL.md amendment + `:124` | P2 | [ ] |
| S-15208 Swift test | P2 | [ ] |
| S-15209 Dart twin test | P2 | [ ] |
| walkers green | P2 | [ ] |
| `_foodsReadOk` + `_reloadFoods` | P1 | [ ] |
| `_foodsFrame` three-branch | P1 | [ ] |
| doc comments | P1 | [ ] |
| S-7104 → S-15204 | P1 | [ ] |
| S-3850/S-3851/S-3857 updated | P1 | [ ] |
| S-15203 | P1 | [ ] |
| S-15207 | P1 | [ ] |
| S-9210 first arm | P1 | [ ] |
| full suite + swift test + mutations | P3 | [ ] |
| docs + review | P4 | [ ] |

## Architect notes

1. **S-15206's "the same throw" must be read as the group read (`throwOnGroups`).** A foods-read throw does not leave a non-empty cache: `FoodLibraryState.loadFoods` empties `_foods` and rethrows (`lib/state/food_library_state.dart:469-471`), so after a `throwOnFoods` throw the cache is empty and nothing is sent — that is S-8310's pinned behaviour and S-15205's premise, and it stays. The case where a failed read coexists with a non-empty foods cache is the groups throw: `loadFoodGroups` empties only `_foodGroups` (`:196-198`), the foods cache survives, and the foods travel uncategorised — S-8316. S-15210 pins that reading; S-15206's seeded text stands with this note.
2. **S-15203's "a repository revision bump after removing the foods" — there is none in the Mock harness.** `MockWorkoutRepository.referenceRevision` is `null` (`mock_workout_repository.dart:1858`), so `storageUnchanged` is always false and every request reloads (`watch_sync_request_handler.dart:140-145`). The removal is produced by `repository.removeFood(id)` per food (hard-deletes library foods, `:1472-1480`; `getFoods(includeArchived: false)` then returns `[]`, `:1414-1421`). `repository.archiveFood(id)` works equally (archived rows are filtered at `:1417-1418`).
3. **The seed's reader list missed four red tests.** S-3850, S-3851, S-3857 (`test/watch_sync_request_handler_test.dart:259-345`, bare library, exact `transport.types` assertions) and S-9210's first arm (`test/watch_sync_changed_only_test.dart:787-825`) all encode "no foods → no foods frame" and are updated in P1 (items 5 and 8). They are test-only updates; no production change beyond D-4.
4. **`lib/core/utils/watch_reference_sync.dart` needs no change** (D-9); dropped from P1's write scope.
5. **`test/watch_nutrition_quick_log_test.dart` is added to P2's write scope** for S-15209 — it is the Dart twin's test file and the seeded P2 scope omitted it.
6. **`docs/state_management/watch_surface_wrist.md` is dropped from P4's targets** (no "no foods sends no frame" sentence there); the targets are `watch_surface.md:537-538,581` and `watch_reference_data.md:175`.
7. **Line-number corrections applied to the seeded text:** D-1 validators (`message_validator.dart:900-905`, `SyncProtocolValidator.swift:773-776`), D-4 `_reloadFoods` arms (`:225-226`, `:228-230`), D-5 (`:139-145`), D-6 (`:149-157`, arm `:156`), D-7 (`WatchNutritionState.swift:160-193`/`:195-202`, `WatchFoodCatalog.swift:130-160`, `?? []` at `:153`), the readers paragraph (`_ThrowingOnceRepository` `:147-166`, S-9213 `:838-866`). Verified correct as seeded: `_foodsFrame` `:262`, `_reloadFoods` `:223-231`, the `:180` reload, PROTOCOL.md `:70` and `:731`.

## Open questions

- `watch/sync_protocol/fixtures/manifest.json:3` says a Wear OS suite walks the manifest; no Wear walker was found (grep `manifest.json` across the repo: only `test/sync_protocol_fixtures_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift`, `SyncProtocolFixturesTests.swift`). If a Wear suite exists outside the searched paths, the new fixture must be registered there too — not checked further.
- The `messageId` of `foods_down_empty.json`: the walkers check conformance per fixture, not cross-fixture uniqueness (not checked beyond the manifest walk); keeping the copy's `msg-foods-1` passes the walk. The builder may give it a distinct id.
- `FoodLibraryState.loadFoods` emptying the cache before rethrowing (`:469-471`) is pre-existing behaviour S-15205 relies on; if it ever changes, S-15205's premise changes with it. Not in scope here.
