# Feature: Navigation Contract — Self-Enforcing Build Check

## Overview

The navigation contract — that all screen navigation in OmniTrain goes through `OmniNavigator` in `lib/core/navigation/`, and that raw `MaterialPageRoute` / `PageRouteBuilder` outside that module is a code-review blocker — exists today as written guidance plus the manually-maintained `route-migration-audit.md`. The contract has drifted out of compliance twice (nutrition Add Food, Hub sheet), and was rescued each time by hand. This effort converts the written rule into an automated build-time guard: a Dart test that scans `lib/`, fails if any application feature or UI file constructs a `MaterialPageRoute` or `PageRouteBuilder` outside the navigation module, and reports the offending file with a pointer to the standard navigation path.

## Requirements

- A new Dart test under `test/` that runs as part of the standard `flutter test` suite.
- The test scans all `.dart` files under `lib/`.
- The test excludes `lib/core/navigation/` (which legitimately defines the standard route primitive).
- The test excludes `test/` (where one-off `MaterialPageRoute` usage as harness setup is acceptable, per the existing audit).
- The test excludes `tool/`, `integration_test/`, `build/`, `.dart_tool/`, `web/`, and any non-source directories.
- A test failure names the offending file path and references the standard navigation path (`OmniNavigator` in `lib/core/navigation/`) as the required fix.
- The test passes on the current codebase once Items 1 and 2 are merged (Add Food alignment + Hub sheet alignment). Both are merged at the time this item lands.
- No new linting infrastructure or external tooling; the check is plain Dart using `dart:io` `Directory` / `File` reads (mirroring the existing pattern in `test/emphasis_tier_contract_test.dart`).
- No application navigation behavior is changed.

## Acceptance Criteria

- [ ] A new test `test/navigation_contract_enforcement_test.dart` exists.
- [ ] Running `flutter test test/navigation_contract_enforcement_test.dart` passes on the current codebase (zero violations outside the navigation module).
- [ ] Temporarily inserting `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SizedBox.shrink()));` into an arbitrary `lib/features/` file makes the test fail with a message that names the file and references `OmniNavigator` as the required fix.
- [ ] The test does not flag `lib/core/navigation/omni_route.dart` (which legitimately constructs `PageRoute<T>` and references `MaterialPageRoute` in doc comments).
- [ ] The test does not flag any file under `test/`.
- [ ] The test does not flag generated files, build output, or web assets.
- [ ] The failure message contains the offending file path and a pointer to `OmniNavigator` / `lib/core/navigation/`.

## Scenarios

### S-001: All application code uses OmniNavigator (green path)
- Trigger: `flutter test test/navigation_contract_enforcement_test.dart`
- Precondition: Items 1 and 2 (nutrition Add Food alignment, Hub sheet alignment) are merged; no other application file constructs `MaterialPageRoute` or `PageRouteBuilder` outside the navigation module.
- Flow: the test scans `lib/` recursively, skipping `lib/core/navigation/`, and reports zero hits.
- Expected outcome: the test passes with all assertions satisfied.
- Edge case of: none.

### S-002: A new feature file introduces a one-off route (red path)
- Trigger: a developer adds `Navigator.of(context).push(MaterialPageRoute(builder: (_) => SomeScreen()));` to a file under `lib/features/something/`.
- Precondition: production codebase otherwise clean.
- Flow: the test scans `lib/`, finds the hit, builds a clear failure report.
- Expected outcome: the test fails with a message naming the offending file and pointing to `OmniNavigator` (in `lib/core/navigation/`) as the required fix.
- Edge case of: S-001.

### S-003: Doc comments and type references in the navigation module are ignored
- Trigger: the navigation module itself contains `MaterialPageRoute` and `PageRouteBuilder` references in doc comments and code (defining `OmniRoute<T> extends PageRoute<T>`).
- Precondition: S-001 satisfied.
- Flow: the test excludes `lib/core/navigation/` from the scan; no false positives.
- Expected outcome: the test passes.
- Edge case of: S-001.

### S-004: Test files use one-off routes as harness setup
- Trigger: test files under `test/` use `MaterialPageRoute` for `pumpWidget` setup (existing convention — see `test/header_standardization_test.dart`, `test/unsaved_changes_dialog_test.dart`, etc.).
- Precondition: S-001 satisfied.
- Flow: the test excludes `test/` from the scan; no false positives.
- Expected outcome: the test passes.
- Edge case of: S-001.

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

**New file:** `test/navigation_contract_enforcement_test.dart`

Single test (or small group of tests) that:

1. Walks `lib/` recursively using `Directory('lib').list(recursive: true, followLinks: false)`.
2. Skips any path under `lib/core/navigation/`.
3. For each `.dart` file, reads its contents via `File.readAsString()`.
4. Searches for raw `MaterialPageRoute(` and `PageRouteBuilder(` constructions.
5. Skips commented-out code and doc-comment occurrences that reference the class name without constructing it (regex matches `MaterialPageRoute(` / `PageRouteBuilder(` with the open paren so it only fires on construction sites, not bare type references).
6. Skips `isA<MaterialPageRoute<...>>` / `isA<PageRouteBuilder<...>>` references inside test code or doc strings — but since the test already excludes `lib/core/navigation/` and `test/`, these patterns won't be hit in application code.
7. Asserts the collected hits list is empty, with a message that lists every offending file path and a pointer to `OmniNavigator` (in `lib/core/navigation/omni_navigator.dart`) as the required fix.

Pattern mirrors `test/emphasis_tier_contract_test.dart` ("no frozen theme constants remain outside omni_theme.dart") which already does exactly this kind of filesystem scan against `lib/`.

### Implementation Steps
1. Write `test/navigation_contract_enforcement_test.dart` with the scan logic.
2. Run `flutter analyze test/navigation_contract_enforcement_test.dart` to confirm no analyzer warnings.
3. Run `flutter test test/navigation_contract_enforcement_test.dart` to confirm green on the current codebase.
4. Negative verification: temporarily insert a `MaterialPageRoute` push into a `lib/features/` file, run the test, confirm it fails with a clear file path + `OmniNavigator` pointer; revert.
5. Confirm `flutter test` still passes for the full suite (no regressions).

## Progress

- [x] Phase 0 Complete ✓
- [x] Phase 1 Complete ✓
- [x] Phase 2 Complete ✓
- [x] Phase 3 Complete ✓

### Phase 3 Complete ✓

Layers in scope: test
Layers skipped: models, repositories, state, features, widgets, core, most docs (only `navigation_contract.md` + `route-migration-audit.md` touched, both for a status note)

Doc hygiene:

| Doc | Status |
|---|---|
| navigation_and_screens.md | N/A — no new screen, no new route, no new navigation entry point |
| state_management.md | N/A — no new state class or method |
| widget_catalog.md | N/A — no new reusable widget |
| data_models.md | N/A — no model change |
| db_integration.md | N/A — no repository change |
| navigation_contract.md | ✅ updated — added `## Enforcement` section pointing at the new automated test; noted the audit doc is no longer the enforcement mechanism |
| route-migration-audit.md | ✅ updated — added top-of-file status note: audit is no longer the enforcement mechanism; the automated test wins if they ever disagree |

PASS (1 rule): reuse the canonical owner (mirrors the existing file-system-scan pattern in `test/emphasis_tier_contract_test.dart` rather than inventing a new mechanism)
N/A (6 rules): units + canonical storage, theme tokens only, card chrome via OmniSurface/OmniCardHeader, effort-kind drives analytics, timestamps are source data, instrument panel not influencer

Review verdict: ✅ APPROVED. Zero critical issues, zero warnings, zero suggestions. See the structured review below.

### Phase 2 Complete ✓

**New file:** `test/navigation_contract_enforcement_test.dart` (~75 lines).

**TDD evidence (negative-verify pass-then-revert):**

1. **Green run** (clean codebase): `flutter test test/navigation_contract_enforcement_test.dart` → `+1: All tests passed!`
2. **Red run** with `MaterialPageRoute(builder: ...)` injected at `lib/features/home/home_screen.dart:274` → test failed with message naming `lib/features/home/home_screen.dart` and pointing to `OmniNavigator (in lib/core/navigation/omni_navigator.dart)`.
3. **Red run** with `PageRouteBuilder(pageBuilder: ...)` injected → test failed with message naming the file. Doc-comment reference to `MaterialPageRoute` and bare `isA<MaterialPageRoute<void>>` were correctly **not** flagged (the `(` requirement filters construction sites only).
4. **Green run after revert** → `+1: All tests passed!`

**Negative-verify edits reverted to clean state.** Confirmed by `grep` — no remnants of `_navigateViolationTest`, `_bareTypeRefDoc`, `PageRouteBuilder(`, or `MaterialPageRoute(` in `home_screen.dart`.

**No regressions:** `flutter test` across `navigation_contract_enforcement_test.dart`, `omni_route_test.dart`, `hub_interaction_test.dart`, `screen_widget_test.dart` → 202 passed, 4 skipped, 0 failed.

**Doc hygiene:**
- `docs/navigation_contract.md` — added `## Enforcement` section pointing at the new automated test and noting that the audit doc is no longer the enforcement mechanism.
- `docs/route-migration-audit.md` — added status note at top: "no longer the enforcement mechanism ... if audit and test disagree, the test wins."
- `docs/navigation_and_screens.md`, `docs/state_management.md`, `docs/widget_catalog.md`, `docs/data_models.md`, `docs/db_integration.md` — **not touched** (no new screen, no new state class, no new widget, no new model, no repository change).

### Phase 1 Complete ✓
Data layer untouched. Grep for `MaterialPageRoute(` and `PageRouteBuilder(` against `lib/**/*.dart` returns zero matches (the only matches are doc-comment references in `lib/core/navigation/omni_route.dart` lines 13–14). Items 1 (Add Food alignment) and 2 (Hub sheet alignment) confirmed merged via inspection of `lib/features/nutrition/add_food_screen.dart` (uses `OmniNavigator.push<void>`) and `lib/widgets/hub/hub_sheet.dart` (uses `OmniNavigator.push` for all five tiles). `docs/data_models.md` and `docs/db_integration.md` not touched — no schema or model changes.

### Phase 0 Complete ✓
Plan file created at `.github/agents/plans/navigation-contract-enforcement-plan.md`. Scope classified as TRIVIAL-aligned (one new test file, no schema/state/UI behavior changes). Lean Iteration 1 block; full scenario register written for completeness.

## Feedback

(empty)
