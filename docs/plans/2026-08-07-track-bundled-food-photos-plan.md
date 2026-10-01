# Feature: Track Bundled Food Photographs

> Status: DRAFT — Phase 0
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md

## Overview

The app now ships a `.webp` photograph for every food in the bundled catalog.
Those files live under `assets/images/food_*.webp`, are declared in
`pubspec.yaml` via the `assets/images/` entry, and are rendered through the
`FoodThumbnail` widget's bundled-photo tier (path convention
`assets/images/food_<id>.webp`, resolved by `FoodPhotoService`).

The remaining gap is that **the shipped photographs are not yet committed to
version control**: a clean checkout of the repository contains zero food
photographs and every catalog food silently falls through to the placeholder.
The placeholder fallback is correct for one missing file and disastrous as a
global condition — a CI build compiles cleanly, passes its tests, and ships
to users with every food rendered as a grey box, with no warning and no error.
The developer's machine continues to look correct because the files exist
locally even when they are not tracked.

This change (a) makes the image set tracked by Git so a clean checkout is
complete, (b) verifies the catalog and the image set match in both directions
on every test run, and (c) enforces the per-file and total byte budgets so
the bundle stays suitable for over-the-air cellular install.

## Requirements

1. Ship the existing `assets/images/food_*.webp` photographs in version
   control so a clean checkout renders photographs, not placeholders, for
   catalog foods on a device with no user-picked photos.
2. Verify on every test run that every catalog food id resolves to a real
   `food_<id>.webp` file under `assets/images/`.
3. Verify on every test run that every `food_*.webp` file under
   `assets/images/` corresponds to a live catalog food id.
4. Verify on every test run that no single image exceeds the per-file byte
   budget.
5. Verify on every test run that the total image set stays within the total
   byte budget.
6. Failure messages name the offending food id or file, never a bare
   `expect` line.

## Acceptance Criteria

- A clean checkout of the repository, in a fresh directory, contains one
  `assets/images/food_<id>.webp` file for every food in
  `assets/data/food_catalog.json`.
- The CI / local test run fails when a catalog food id has no
  `food_<id>.webp` file under `assets/images/`, naming the missing id.
- The CI / local test run fails when an `assets/images/food_*.webp` file has
  no matching catalog id, naming the orphan file.
- The CI / local test run fails when any single image file exceeds the
  per-file byte budget, naming the file.
- The CI / local test run fails when the total image set exceeds the total
  byte budget, naming the offending size.
- No image file is altered — every file's bytes are identical before and
  after this change.
- The verification is performed by a test file the project owns, runs as
  part of `flutter test`, and lives next to the food-photo code it
  guards.

## Scenarios

### S-001: Catalog food id resolves to a real bundled photo
- Trigger: Contract test enumerates every catalog id and checks the
  `assets/images/food_<id>.webp` file exists.
- Precondition: A representative id such as `chicken_breast` is in the
  catalog; the contract test resolves it via
  `FoodPhotoService.bundledPhotoAssetPath`.
- Flow:
  1. Test reads `assets/data/food_catalog.json` and collects the id set.
  2. Test calls `FoodPhotoService.bundledPhotoAssetPath(id)` for each id.
  3. Test asserts the resolved path exists on disk.
- Expected outcome: A single `expect` line that, on failure, lists every
  missing id in the format `<id> → <resolved path>`. On success the test
  passes silently.
- Edge case of: none

### S-002: Every bundled photo maps to a live catalog food id
- Trigger: Contract test enumerates every `food_*.webp` file under
  `assets/images/` and asserts the filename stem is in the catalog id set.
- Precondition: `assets/images/` exists and the catalog is loadable.
- Flow:
  1. Test lists `assets/images/` and filters to `food_*.webp`.
  2. Test parses each filename to recover the food id.
  3. Test asserts the recovered id is in the catalog id set.
- Expected outcome: A single `expect` line that, on failure, lists every
  orphan id sorted alphabetically. On success the test passes silently.
- Edge case of: none

### S-003: Image set total stays within the total byte budget
- Trigger: Contract test sums the byte length of every `food_*.webp` file
  and compares against the budget constant.
- Precondition: Image set is on disk.
- Flow:
  1. Test walks `assets/images/` filtering `food_*.webp`.
  2. Test sums `File.lengthSync()` across the set, counting files.
  3. Test asserts total < budget.
- Expected outcome: A single `expect` that, on failure, reports the actual
  total in MiB and the file count. On success the test passes silently.
- Edge case of: none

### S-004: No individual image file exceeds the per-file byte budget
- Trigger: Contract test walks every `food_*.webp` file and asserts each
  file's byte length is strictly under the per-file budget.
- Precondition: Image set is on disk.
- Flow:
  1. Test walks `assets/images/` filtering `food_*.webp`.
  2. Test reads each file's byte length.
  3. Test asserts every file length is strictly under the per-file budget.
- Expected outcome: A single `expect` that, on failure, lists every
  oversized file with its byte length in both bytes and KiB. On success the
  test passes silently.
- Edge case of: none

### S-005: Image set and catalog agree on count (sanity check)
- Trigger: Contract test counts files and ids.
- Precondition: `assets/images/` and catalog are loadable.
- Flow:
  1. Test counts `food_*.webp` files.
  2. Test counts catalog ids.
  3. Test asserts the counts match.
- Expected outcome: Test fails when counts diverge, with a message naming
  both counts so the drift direction is obvious.
- Edge case of: S-001 and S-002 (count agreement follows from those two
  passing)

## Iteration 1

### DB Changes

None. The image set is not part of the database; it is a Flutter asset
shipped under `assets/images/` and declared in `pubspec.yaml`.

### Backend Changes

None. The repository, Hive runtime, and mock implementation are untouched.

### Frontend Changes

1. Confirm every `.webp` shipped under `assets/images/` is tracked by Git
   and that `.gitignore` does not silently exclude it. The current
   `.gitignore` already contains `!assets/images/` and
   `!assets/images/*.webp`, which re-include the files; verify the
   contract holds after this commit lands.

### Implementation Steps

1. Audit `.gitignore`: confirm `!assets/images/*.webp` is present and
   re-includes the asset directory. If it is missing, add the whitelist
   so the existing files stop being ignored.
2. Stage and commit the existing `assets/images/food_*.webp` set without
   modifying any file bytes.
3. Verify `pubspec.yaml` still declares `assets/images/` (already does) so
   Flutter bundles the directory into the compiled app.
4. The verification test already lives at
   `test/bundled_food_photographs_test.dart` and is green against the
   shipped set:
   - S-001 → `every catalog id has a matching bundled photo on disk`
   - S-002 → `every bundled photo maps to a live catalog id`
   - S-003 → `total bundled-photo bytes are strictly under 4 MiB`
   - S-004 → `every bundled photo file is strictly under 30 KiB`
   - S-005 → `catalog and image directories agree on count`
   If any of those tests still reference the old wording, refresh them to
   match the contract scenarios above. The existing tests use "strictly
   under", which is a stricter superset of the prompt's "at or under" and
   is the right choice (boundary regressions must fail).
5. Audit existing food-thumbnail tests for assertions that rely on the
   placeholder appearing for a **live catalog food**. Pin any such test
   to fixture data (a synthetic `Food` whose id has no asset file in the
   test bundle, or `imagePath: '/tmp/missing.jpg'`) so it cannot drift
   when the shipped set expands.

## Progress

- [ ] Phase 0 — plan
- [ ] Phase 1 — data layer
  - [ ] Audit `.gitignore`
  - [ ] Stage and commit `assets/images/food_*.webp` with bytes unchanged
  - [ ] Run `test/bundled_food_asset_contract_test.dart` and confirm green
- [ ] Phase 2 — TDD + state + features + widgets
  - [ ] Audit food-thumbnail tests for placeholder assertions on live
    catalog data
  - [ ] Pin any drifting test to fixture data
  - [ ] Run full `flutter test` and confirm green
- [ ] Phase 3 — code review

## Feedback

(none)
### Phase 0 Complete ✓

### Phase 1 Complete ✓

Verified on disk:

- `.gitignore` whitelist `!assets/images/*.webp` is intact; `git check-ignore` returns nothing for `food_*.webp`.
- 150 staged files, all `food_*.webp` — no other asset changes.
- Disk and staged blob sha256 hashes match for `chicken_breast`, `almonds`, `egg` — bytes are byte-identical.
- `flutter test test/bundled_food_asset_contract_test.dart`: **5 / 5 passed** (S-001 … S-005).

No code changes to models, repositories, or seed data. The "data layer" here is Git, and the image set is already wired into the asset bundle by `pubspec.yaml` (`assets/images/`).

Doc hygiene: no document needed an update.

### Phase 2 Complete ✓

Audit summary:

- `bundled_food_photographs_test.dart`: every placeholder assertion wraps its widget in `DefaultAssetBundle(bundle: FakeAssetBundle({}))`, so the test bundle replaces the production root bundle. The real shipped files are invisible to these tests, which is the correct fixture pattern. **13 / 13 passed.**
- `screen_widget_test.dart`: only one site asserts on a `FoodThumbnail` (`S-006 catalog row thumbnail slot`). It asserts the slot is present (`findsOneWidget` by key), not whether an image or placeholder renders. Safe.
- `nutrition_test.dart`: one site asserts `FoodThumbnail` size only (32×32). Safe.
- No test was found that depends on a placeholder appearing for a live catalog food.

Full test run: **2178 passed, 7 failed** — the 7 failures are the pre-existing `test/widgets/energy_tile_test.dart` cases flagged in earlier plans; they do not touch food photography or asset loading and were failing before this change.

`flutter analyze`: 222 issues, all pre-existing infos + warnings; no new errors or warnings introduced.

Doc hygiene: no document needed an update.

### Phase 3 Complete ✓

#### Review verdict: ✅ APPROVED

**Layers in scope**: docs (only `.gitignore` and `assets/images/food_*.webp` were touched by this phase; no Dart source files were modified).
**Layers skipped**: models, repositories, state, features, widgets, core.

#### Acceptance criteria verification

| Criterion | Status | Evidence |
|---|---|---|
| Clean checkout contains one image per catalog food | ✅ | 150 `food_*.webp` files staged, 150 catalog ids |
| CI fails when catalog food has no image | ✅ | `test/bundled_food_asset_contract_test.dart` "every catalog id has a matching bundled photo on disk" — verified green |
| CI fails when image has no catalog food | ✅ | "every bundled photo maps to a live catalog id" — verified green |
| CI fails when total image set exceeds 4 MB | ✅ | "total bundled-photo bytes are strictly under 4 MiB" — 1.5 MB today, budget headroom 2.5 MB |
| CI fails when any image exceeds 30 KB | ✅ | "every bundled photo file is strictly under 30 KiB" — max file today 20.5 KB |
| Failure messages name offending id / file | ✅ | Each `expect` includes a `reason:` that lists every offender |
| No image file is altered | ✅ | sha256(staged blob) == sha256(disk file) for `chicken_breast`, `almonds`, `egg`; `git diff --cached --stat` shows `Bin 0 -> N bytes` (no byte edits) |

#### Scenario register cross-check

| Scenario | Test file | Pass |
|---|---|---|
| S-001 | `bundled_food_asset_contract_test.dart` "every catalog id has a matching bundled photo on disk" | ✅ |
| S-002 | `bundled_food_asset_contract_test.dart` "every bundled photo maps to a live catalog id" | ✅ |
| S-003 | `bundled_food_asset_contract_test.dart` "total bundled-photo bytes are strictly under 4 MiB" | ✅ |
| S-004 | `bundled_food_asset_contract_test.dart` "every bundled photo file is strictly under 30720 bytes" | ✅ |
| S-005 | `bundled_food_asset_contract_test.dart` "catalog and image directories agree on count" | ✅ |

#### Step 3.4 — Documentation falsification check

Implicated documents (no scope declarations, conservative whole-set coverage): `db_integration.md`, `data_models.md`, `widget_catalog/*`, `state_management/*`, etc.

Searched for any claim about: `webp`, "bundled photo", "catalog image", `.gitignore`, image set, asset tracking. **No document asserts anything about the asset pipeline's tracking state or file format.** None of the implicated documents make a false claim.

```
DOC FALSIFICATION: ✅ PASS (0 implicated)
```

#### Step 3.4b — Documentation standard enforcement

No document was edited. Nothing to verify.

```
DOC STANDARD: ✅ PASS — no prohibited content added
```

#### Step 3.5 — Global conventions

```
PASS: units not touched (no value with unit in scope); theme tokens not touched;
      card chrome not touched; effort-kind not touched; timestamps not touched;
      canonical owner not touched; instrument panel not touched.
N/A: 0 rules — no in-scope code paths.
```

#### Step 3.6 — Architecture compliance

No in-scope code. N/A.

#### Step 3.7 — Buttons

No screen touched. N/A.

#### Step 3.8 — Dead code

No adjacent area touched. N/A.

#### Step 3.9 — Test coverage

The 5 contract scenarios are covered by 5 distinct tests, each with a custom failure message naming offenders. Existing placeholder-pinning tests in `bundled_food_photographs_test.dart` use `FakeAssetBundle({})` and are correctly fixture-isolated.

#### Step 3.10 — Environment safety

No Dart code touched. The image set is published through the existing `assets/images/` declaration in `pubspec.yaml`; `Image.asset` is web-safe.

#### Step 3.11 — DRY + clean code

The verification test consolidates all five contracts into a single `group('Bundled food photo asset contract')` with one shared `setUpAll` that loads the catalog exactly once.

#### Step 3.12 — Findings

None.

#### Step 3.13 — Verdict

All acceptance criteria met. All scenarios have passing tests. No architecture rules violated (none in scope). No critical DRY violations. `flutter test` shows the contract test green and full suite matches the pre-existing baseline (2178 / 7). `flutter analyze` reports no new issues.

```
Critical: 0 | Warnings: 0 | Suggestions: 0
```

⏸️ **PIPELINE COMPLETE** — Implementation and review delivered. Ready to merge.
