# Review: plan 53 — watch food screen and fresh foods

Reviewer: code-reviewer (Copilot CLI) — 2026-10-23
Base: `a01be76d05e6a4807b21a6a97a3dc38dc06abba0` — diff reviewed: phases P1–P3 committed, P4 docs in the working tree.

Findings appended below as found.

## Verdict

**APPROVE** — one minor finding, no blockers.

## Scope

Layers touched: watch Swift state/views/host (`watch/watchos/Sources/`, `ios/OmniTrain Watch App/`), phone Dart (`lib/state/watch/`, `lib/watch/nutrition/`), tests (Dart + Swift), docs (`docs/state_management/` ×3), plan + evidence. No `lib/features/`, `lib/widgets/`, `lib/data/` or `lib/core/` file changed — those layers are skipped.

## Diff vs Predicted Files

Conforms exactly: all 17 changed files are in the plan's Predicted Files (plus the plan and evidence files themselves). No out-of-bounds file, no unfinished predicted file. The two untracked sibling plan folders (54, 55) were ignored as instructed.

## Test runs (this review, pasted counts)

- `gateway.sh test` (full Flutter suite) → **5434 passed, 2 skipped, 0 failed** (`All tests passed!`, `.work/gateway/test-20261023-001326-21816.log`).
- `gateway.sh swift-test` (full watch package) → **756 executed, 0 failures** (`.work/gateway/swift-test-20261023-001642-27257.log`).
- `gateway.sh prove-red a01be76… test test/watch_sync_request_handler_test.dart` → **RED AT base, 4 assertion failures** — S-8308 (no foods frame from an empty cache), S-8309 (0.00833 where 0.025 expected), S-8310 (a foods frame sent despite the throwing read), S-8316 (categories present despite the throwing group read). Each fails for the reason its test guards. GREEN AT base would have been a blocker; it is not.
- `gateway.sh prove-red a01be76… swift-test --filter WatchNutritionWiringSourceTests -- …WatchNutritionWiringSourceTests.swift` → **RED AT base, 7 executed / 14 assertion failures** (S-7201, S-7203, S-8311, S-8312, S-8318 red; S-7202, S-7205 green), all assertion failures, no compile error — exactly as the evidence file records.

The freshness tests (S-8301..S-8306, S-8313..S-8315) and the Dart twin group cannot compile at the base commit (new APIs); the evidence file carries seven Swift mutations and two Dart mutations with originals restored and re-runs green — acceptable proof per the gateway's own rule.

## Brief-specific checks

- **(a) One `WatchNutritionModel`.** Grep over `ios/` and `watch/`: the only production construction is `ios/OmniTrain Watch App/ContentView.swift:109` in `WatchAppHost.init`; every other hit is the S-8311/S-8318 guard text itself. The sheet (ContentView ~341) and the menu row (`WatchMenuView.logFoodRow`) both consume `host.nutritionModel`. The only `WatchMenuView(` call site passes the new parameter. ✓
- **(b) Deselect paths.** Leaving via back or swipe runs the `navigationDestination` binding's `set(false)` → `model.deselect()` (state deselect + `crownPosition = 0`). A `foods_down` that drops the selected food: `selected` is derived (`selectedFoodId.flatMap { food($0) }`), so it becomes nil, `isShowingFood` goes false, the screen pops, and `onFoodsChanged` (fired on the applied path only) drives the redraw; `select` on the next food overwrites the stale id. S-8314 pins the state side; S-8312 pins the view side. ✓
- **(c) Clock rule agreement.** Swift `effectiveFood`: log wins iff `loggedAt > catalog.generatedAt` (`<=` returns the catalog food). Dart `_effectiveFood`: log wins iff `parseUtcIso(loggedAt).isAfter(catalog.generatedAt)`. Identical rule, identical tie-break (equal timestamps → catalog wins), both comparing the log's `loggedAt` against the catalog's `generatedAt`, both falling back to the catalog value on an unreadable payload. ✓
- **(d) Handler reload on throw.** `watch_sync_request_handler.dart:127-134` reloads groups then foods inside one try/catch before the `foods.isNotEmpty` check, every request. `FoodLibraryState.loadFoods`' catch sets `_foods = {}` then rethrows (lib/state/food_library_state.dart:470-472) → a throwing foods read sends no foods frame; `loadFoodGroups`' catch empties only `_foodGroups` (l.196-198) → foods still travel with `categoryId: null`. Preferences and routines are sent before the reload, the exercise batches after — all still travel, `handle` returns true. This is exactly what plan Open question 2 pins and what S-8310/S-8316 assert. ✓
- **(e) Removed tests.** Grep of the full test diff for removed `func test` / `test(` / `testWidgets(` lines: none. No test name was removed; S-7101..S-7105, S-7201..S-7205, S-7206 and the contract-order tests all still exist and pass in the full runs. ✓

## Acceptance criteria and scenarios

Every criterion maps to implemented, tested behavior: S-8301..S-8306 + S-8313..S-8315 in `WatchNutritionFreshnessTests.swift` (9 tests, fixture-conformant — they build the two-food lists, the older/newer envelopes and the relaunch the scenarios enumerate); S-8307/S-8317 in the Dart twin group; S-8308..S-8310 + S-8316 in the handler group; S-8311/S-8312/S-8318 as source guards. R-1's kcal on the food screen is the portion row's `model.state.calories` line. No criterion without an implementation.

## Documentation falsification (4d)

Three docs implicated (all edited by P4); checked against the post-change code:

- `docs/state_management/watch_surface.md` — `deselect()`, the `loggedAt` vs `generatedAt` rule, `onFoodsChanged`'s three call sites: all match the code; every named test exists with the exact name (`testS8301…` … `testS8315ASelectionClampsTheListedAmount`, `testS8311…`, `testS8318…`). ✓
- `docs/state_management/watch_surface_wrist.md` — one host-owned model, food screen push, derived amount, parity gap naming `lib/watch/nutrition/watch_nutrition_screen.dart` (exists, unchanged). ✓
- `docs/state_management/nutrition_state.md` — the per-request reload and the `_writeThroughLastAmount` rationale (the method exists at `lib/state/nutrition_state.dart:479`); the named test group `S-8308…S-8310, S-8316 the handler reloads the food library per request` exists verbatim. ✓

The docs point at tests rather than restating behavior — the required form. No false claim, no conflict between documents.

DOC FALSIFICATION: ✅ PASS (3 implicated) — watch_surface.md, watch_surface_wrist.md, nutrition_state.md

## UI standards

No `lib/` UI file changed; `test/helpers/ui_standards_allowlist.dart` is not in the diff (no new entry, no ratchet change). The watch views reuse `.bordered`, `watchProminent()` and `.secondary` — moved, not restyled; no colour literal added. `ui_standards_contract_test.dart` green inside the full suite.

## Findings

- 🟡 MINOR | `watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift:54` | the model's `select` doc comment still says "its portion starts where the phone left it", which D-2 made only half the rule (the wrist's own newer log can be the source; the state's and twin's comments were rewritten, this one was missed) | rewrite the one sentence to name both sources, as `WatchNutritionState.select`'s comment now does | @developer

Critical: 0 | Major: 0 | Minor: 1

## Notes

- Test footprint (~905 added test lines) is about double the plan's ~450 estimate, but every added test maps to a planned scenario id and the file set matches Predicted Files exactly — estimate drift, not scope creep. No split needed (0 substantive findings above the nit threshold).
- Still the governor's, per the plan: the watch scheme's `xcodebuild` (the views compile only there), `flutter analyze` against the 180-info baseline, and the two owner checks on device.
