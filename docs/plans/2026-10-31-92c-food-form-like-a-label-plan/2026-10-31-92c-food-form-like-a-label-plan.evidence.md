# Evidence — 92c food-form-like-a-label (planner research, base `3ed09c3f`)

Collected by the planner (conductor-v2) before Iteration 1. Implementers append their own run outputs below each section; never edit the planner's baseline rows.

## Baselines at base `3ed09c3f`

- `lint`: 180 issues, 0 errors (92b evidence, same base commit).
- Full suite: 5918 pass / 2 skipped (92b evidence, same base commit).
- Gateway checks available: `lint` 300s, `test` 900s, `build` 900s, `codegen` 300s, `pub-get` 300s, `format` 120s (new-files-only), `swift-test` 900s, `base-setup` 300s; git views `git-status` / `git-diff` / `git-log` / `git-show`; `prove-red <ref> <check> [args] [-- <files>]`.
- Gateway quirks (from 92b): `git-show` refuses `--` options; `git-log` refuses `--stat`; `wc`, `ls`, `head` pipes denied; `format` refuses tracked files (A-92b.11).

## `calculateCalories` readers (grep `calculateCalories` over `lib/` + `test/` + `docs/`)

Production:
- `lib/core/utils/food_helpers.dart:11` — the definition: `(protein*4 + carbs*4 + fat*9).round()`.
- `lib/features/nutrition/widgets/log_food_row.dart:339`
- `lib/features/nutrition/add_food_screen.dart:897` — macroText `'$cal cal · ...'`
- `lib/features/nutrition/add_food_screen.dart:1212-1213` — Library row `'$cal cal per ${foodServingLabel(shown)}'`
- `lib/core/utils/watch_reference_sync.dart:648`

Tests:
- `test/library_row_toggle_test.dart:379,406`
- `test/library_merge_test.dart:171`
- `test/food_library_state_test.dart:1459-1575` — the `Food Helper Functions` group: two `calculateCalories` unit tests + the `Food.calories` getter parity test

Docs:
- `docs/widget_catalog/nutrition_widgets.md:80`
- `docs/state_management/watch_surface.md:365`

All readers keep their values: the refactor only moves the body into `caloriesFromMacros` and delegates.

## Tests whose assertions change (complete list)

- `test/food_form_decimals_and_autofocus_test.dart` S-003 (L286-341): types `abc` into carbs, expects `find.text('Required')` at L341 → becomes `.` / `find.text('Must be a number')`.
- `test/food_form_decimals_and_autofocus_test.dart` S-004 (L399): `expect(controller.text, '4.0')` → `'4'` (the only prefilled-macro-text assertion in the suite).

Verified unaffected (greps):
- `Required` in `test/`: only the two files above touch FoodForm macros; `food_form_serving_test.dart:397` is the package amount's `_validatePositiveDouble` (keeps `Required`); `utils_test.dart`, `watch_sensor_recording_test.dart`, `settings_sounds_test.dart`, `nutrition_data_audit_test.dart` are unrelated features.
- `find.text('0.0')` in `test/`: `screen_widget_test.dart:1857`, `interaction_flow_test.dart:280`, `crown_control_tap_to_edit_test.dart:430`, `tap_to_edit_unification_test.dart:493` — all routine-setup / value-stepper screens, contexts read, none is `FoodForm`.
- Macro-key typing: `nutrition_test.dart:1963-1967, 2096-2098` and `food_form_serving_test.dart:85-87, 305-309, 751-766` type into the keys and read texts without literals — stay green.
- `screen_widget_test.dart:9481-9483` asserts key presence only.
- `food_form_pick_saves_test.dart:79,226,450` and `edit_food_save_test.dart:42,75,89,91` are fixture `Food(...)` constructions, not assertions on form-saved fiber/sodium.
- `test/food_form_orphan_category_test.dart:130-240` asserts key presence + dropdown value/label, not position — unaffected by the photo-tile move.

## Macro-key / decoration greps

- The five `_macroField` calls in `food_form.dart` ~L766-805, order protein → carbs → fiber → fat → sodium; `_macroField` ~L843-880 (validator: empty required → `'Required'`, unparsable → `'Must be a number'`; no `onChanged` today).
- Select-all bindings (`bindSelectAllOnFocus`) cover the five macro fields only; name/notes excluded.
- `docs/design_system.md` (730 lines): no `hintText` / `floatingLabelBehavior` rule found.
- `test/ui_standards_contract_test.dart`: scans buttons (S-2601 `shape:`), raw Cards, hex colours, dialogs, sheets — no hint/label scan → no allowlist entry needed for `hintText: '0'` / `FloatingLabelBehavior.always`.

## Doc sizes (planner-measured; Phase 3 re-measures against the 52 KB band)

- `docs/widget_catalog/nutrition_widgets.md`: full read without truncation → under 20 KB. FoodForm section ~L90-245.
- `docs/nutrition.md`: 31.6 KB (92b evidence); 630 lines.
- `docs/state_management/nutrition_state.md`: 26.9 KB (92b evidence).
- `wc`/`ls` are outside the gateway's allowed commands, so byte sizes could not be re-measured this run.

## Fixture correction

- S-92c.8 names `Oats, rolled`; the shipped seed has `Oats, dry` (`lib/mock/food_catalog_seed.dart:931`). Grep `Oats` over the seed finds no `rolled`. The Phase 2B test uses `Oats, dry`; the seeded scenario text stays verbatim (Open question 1 in the plan).
- `Chicken breast, skinless` exists (seed L33) — S-92c.8's first leg is fine as written.

## Uncommitted work in the tree (git-status at planning time)

- `lib/state/food_library_state.dart`: +1 line — `'chicken_thigh_skin_on',` added to a bundled-id list (~L1495). NOT on the hands-off list, but Phase 1 edits this file → Phase 1 item 5 preserves the line.
- `lib/mock/food_catalog_seed.dart`: +18 lines (169th food `Chicken thigh, with skin`).
- `assets/data/food_catalog.json`: +14 lines.
- The nine hands-off files from the plan header are untouched.

## Prove-red rationale per phase

- **Phase 1**: the new symbols (`caloriesFromMacros`, `nameExistsInLibrary`) do not exist at base, so carrying `test/food_library_state_test.dart` to HEAD cannot compile — a compile failure is not a valid red (92b convention). Mutation proofs instead, run and restored verbatim: (a) `caloriesFromMacros` returns sum + 1 → the new unit tests FAIL; (b) `nameExistsInLibrary` drops the archived skip → the S-92c.9 archived leg FAILs. Restore check: `git-diff HEAD --stat -- lib/core/utils/food_helpers.dart lib/state/food_library_state.dart` shows only the feature's additions.
- **Phase 2A**: `test/food_form_label_test.dart` uses only existing keys and APIs, so it compiles at base → `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_label_test.dart` must FAIL on base (S-92c.2/3/4/5/6/14/15 red for the reasons the seed states).
- **Phase 2B**: same file, now covering S-92c.1/7/8/10-13, all red at base → the same prove-red command must still FAIL on base.

## Planner process notes

- Research order: brief → seeded plan → series index → 92b plan (expansion pattern) + 92b evidence (evidence format) → 92a plan (pattern) → `food_form.dart` (full) → `food_helpers.dart` (full) → reader greps → `food_library_state.dart` (targeted) → test greps (`Required`, `0.0`, macro keys, select-all, fiber/sodium expectations) → docs (nutrition_widgets.md full; nutrition.md, nutrition_state.md, design_system.md targeted) → ui_standards_contract_test.dart scan list → seed fixture check.
- Derived decisions flagged vetoable: D-92c.9 (slot conflict resolution), D-92c.13 (legacy twins). All other appended decisions restate or mechanically follow the seed.
- The seed's phase outline is preserved verbatim above the `---`; the expansion's Phases 1/2A/2B/3 expand it without reordering.

---

# Developer runs

## Phase 1 — the two rules (developer, base `3ed09c3f`)

### Red before implementation

`.github/copilot/scripts/macos/gateway.sh test test/food_library_state_test.dart` → exit 1, compilation failed (the new symbols do not exist yet):

- `test/food_library_state_test.dart:1765:14: Error: Method not found: 'caloriesFromMacros'.` (and :1770, :1790)
- `test/food_library_state_test.dart:1497:20: Error: The method 'nameExistsInLibrary' isn't defined for the type 'FoodLibraryState'.` (12 sites)
- `00:00 +0 -1: Some tests failed.`

### Green

- `test test/food_library_state_test.dart` → `00:00 +72: All tests passed!` (72 passed, 0 failed).
- Same command after each mutation restore → `00:00 +72: All tests passed!` again.

### Mutation proofs (restored verbatim; `grep -rn MUTANT lib test` empty at the end)

- **(a) `caloriesFromMacros` returns `(protein * 4 + carbs * 4 + fat * 9).round() + 1`** → `00:00 +66 -6: Some tests failed.`:
  - `S-92c.9 caloriesFromMacros computes whole-number macros` — `Expected: <124> Actual: <125>`
  - `S-92c.9 caloriesFromMacros rounds half away from zero` — `Expected: <5> Actual: <6>`
  - `S-92c.9 caloriesFromMacros matches calculateCalories` — `Expected: <239> Actual: <240>`
  - the three pre-existing `calculateCalories` legs also moved (151→152, 370→371, `Food.calories` parity)
  - Original restored: `}) => (protein * 4 + carbs * 4 + fat * 9).round();`
- **(b) archived skip removed from `nameExistsInLibrary`'s `matches`** → `00:00 +71 -1: Some tests failed.`:
  - `S-92c.9 returns false for an archived food` — `Expected: false Actual: <true>` (the only failure)
  - Original restored: `if (candidate.isArchived) return false;`

### Restore check

`.github/copilot/scripts/macos/gateway.sh git-diff HEAD --stat -- lib/core/utils/food_helpers.dart lib/state/food_library_state.dart test/food_library_state_test.dart`

```
lib/core/utils/food_helpers.dart  |  24 ++++-
lib/state/food_library_state.dart |  62 ++++++++++++
test/food_library_state_test.dart | 203 ++++++++++++++++++++++++++++++++++++++
3 files changed, 287 insertions(+), 2 deletions(-)
```

The 2 deletions are `calculateCalories`'s old body line and the doc line it replaced; `food_library_state.dart` and the test file are additions only. The other unit's `'chicken_thigh_skin_on',` line is still present in the bundled-id list (grep finds it).

### Lint and contracts

- `lint` → **181 issues, 0 errors** vs the 180 baseline. The one extra is `test/food_catalog_load_test.dart:270` `unnecessary_non_null_assertion` in a file the concurrent food-catalog unit has modified (`git-status`: `M test/food_catalog_load_test.dart`), not one of this phase's files. No issue names `food_helpers.dart`, `food_library_state.dart` or `food_library_state_test.dart`.
- `test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → `00:02 +54: All tests passed!`.

### Test inventory added (S-92c.9)

`test/food_library_state_test.dart`, group `nameExistsInLibrary` (10 tests): catalog food true; library-only food true; archived false; excluded library row itself false; excluded catalog row itself false; library copy excludes its catalog twin; catalog row excludes its library copies; legacy row without `catalogId` is separate (D-92c.13); blank false; case + surrounding spaces ignored. Group `Food Helper Functions` adds 3: whole-number 31/0/0 → 124; fractional 0/0/0.5 → 5; delegation parity with `calculateCalories` (238.5 → 239).

### Full suite after Phase 1

`.github/copilot/scripts/macos/gateway.sh test` → `07:22 +5932 ~2: All tests passed!` (5932 passed, 2 skipped, 0 failed; baseline was 5918 pass / 2 skipped — the delta is this phase's 13 new tests plus the concurrent unit's catalog tests).

## Phase 2A — the boxes (developer, base for proof `da266e05`)

### Red before implementation

`test/food_form_label_test.dart` written first (10 tests), then
`.github/copilot/scripts/macos/gateway.sh test test/food_form_label_test.dart` → exit 1,
`00:01 +2 -8: Some tests failed.` Eight failures, each for its scenario's seeded reason:

| Test | Red failure at base |
| --- | --- |
| S-92c.2 order | `Expected: a value less than <484.0> Actual: <612.0>` (protein sits above fat) |
| S-92c.3 blank boxes + hint | `Expected: empty Actual: '0.0'` |
| S-92c.4 blank save | `Expected: null Actual: <0.0>` (fiber/sodium saved as 0.0) |
| S-92c.5 prefill | `Expected: '31' Actual: '31.0'` |
| S-92c.14 stored 0.0 fiber | `Expected: '0' Actual: '0.0'` |
| S-92c.14 unrecorded fiber/sodium | `Expected: empty Actual: '0.0'` |
| S-92c.15 select-all text | `Expected: '4' Actual: '4.0'` |
| S-92c.16 faint 0 | `Found 0 widgets with text "0"` |

The two passes are the red-independent legs: S-92c.6 (a lone `.` already returned
`Must be a number` at base) and S-92c.14's type-then-clear leg. A first attempt failed to
compile (`TextFormField.decoration` is private); the assertion was rewritten to read the
descendant `InputDecorator.decoration`, which compiles at base, so the red above is behavioural.

### Green

- `test test/food_form_label_test.dart` → `00:00 +10: All tests passed!`
- `test test/food_form_label_test.dart test/food_form_decimals_and_autofocus_test.dart test/food_form_serving_test.dart test/food_form_orphan_category_test.dart test/food_form_pick_saves_test.dart test/edit_food_save_test.dart test/nutrition_test.dart` → `00:17 +154: All tests passed!` (154 passed, 0 failed).
- `test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → `00:01 +54: All tests passed!`

### Prove-red

`.github/copilot/scripts/macos/gateway.sh prove-red da266e05 test test/food_form_label_test.dart` (Phase 1 commit, per the brief) →

`gateway: prove-red: RED AT da266e05 (exit 1).` `00:01 +2 -8: Some tests failed.` with the
eight assertion failures listed in the red table above (order, `0.0`, null fiber, `31.0`,
`4.0`, no hint). Not a compile or load error.

### Test inventory added (S-92c.2..6, 14..16)

`test/food_form_label_test.dart` (10 `testWidgets`, Mock-first, 800×3000 surface):
S-92c.2 order; S-92c.3 blank boxes + five `0` hints + no `0.0`; S-92c.4 blank save
(0.0/0.0/0.0, fiber/sodium null); S-92c.5 edit prefill (`31`, `0`, `3.6`, empty, `74`) and
untouched save; S-92c.6 lone `.` → `Must be a number`, no save; S-92c.14 three legs (stored
0.0 stays 0.0, null stays empty/null, type-then-clear sodium saves null); S-92c.15 `4` +
full selection; S-92c.16 five labels visible, five `0` hints, and the name/group decorations
carry neither a hint nor `FloatingLabelBehavior.always` (the `InputDecorator` resolves an
unset behaviour to `auto`, so the assertion is `isNot(always)`).

### Existing test rewritten

`test/food_form_decimals_and_autofocus_test.dart`:
- S-003 now types `.` into carbs and expects `Must be a number` with `saveCalled` false (was `abc` → `Required`).
- S-004 expects the prefilled fat `'4'` (was `'4.0'`).
- S-001's stale comment ("Required macros default to 0") now says blanks save 0.0. No assertion changed.
No other assertion in that file depended on the blank/prefill text.

### Lint

`lint` → **181 issues, 0 errors**, equal to the brief's 181 baseline (the one warning is the
concurrent unit's `test/food_catalog_load_test.dart:270`). No issue names this phase's files.

### Full suite

`.github/copilot/scripts/macos/gateway.sh test` → `03:52 +5942 ~2: All tests passed!`
(5942 passed, 2 skipped, 0 failed; Phase 1 left 5932, +10 from this phase's new file).

### Residue sweeps

- `grep '?? 0.0).toString()' lib/` → no matches.
- `grep 'Required' lib/features/nutrition/widgets/food_form.dart` → the class doc's English
  "Required" and `_validatePositiveDouble`'s `'Required'` (package amount) only.
- `grep "find.text('Required')" test/` → `test/food_form_serving_test.dart` only (the package
  amount leg).
- `grep floatingLabelBehavior lib/features/nutrition/widgets/` → `_macroField` only.
- `grep -r "hive_workout_repository" lib/` → `lib/main.dart` only (composition root, outside
  the `lib/state`/`lib/features`/`lib/widgets`/`lib/core` invariant).

### Diff footprint

`git-diff --stat` → `lib/features/nutrition/widgets/food_form.dart | 96 +++---` and
`test/food_form_decimals_and_autofocus_test.dart | 28 +++---`; `test/food_form_label_test.dart`
is new. No formatter pass was run on the tracked files.

## Phase 2B — calories, photo, duplicate note (developer, proof base `9ce61a07`)

Nine `testWidgets` added to `test/food_form_label_test.dart` (Mock-first, 800×3000): S-92c.1
calories line, S-92c.7 tile order, S-92c.8 three legs (catalog-name duplicate, user-food rename,
library copy of a bundled food), S-92c.10 padded/case-insensitive match, S-92c.11 clearing hides
the note, S-92c.12 near-duplicate twin, S-92c.13 fractional-agreement. The file now holds 19 tests.

### Prove-red

`.github/copilot/scripts/macos/gateway.sh prove-red 9ce61a07 test test/food_form_label_test.dart` →

`gateway: prove-red: RED AT 9ce61a07 (exit 1).` `00:02 +10 -9: Some tests failed.` — all nine
new tests fail on assertions, none on load or compile:

| Scenario | Base assertion |
|---|---|
| S-92c.1 calories line | no `food_form_calories` widget |
| S-92c.7 tile order | `Expected: a value less than <16.0> Actual: <128.0>` (tile above the name) |
| S-92c.8 ×3 | `Found 0 widgets with key [<'food_form_duplicate_note'>]` |
| S-92c.10 padded/cased | `Found 0 widgets with text "There's already a food called "chicken breast, skinless" in the Library"` |
| S-92c.11 clearing hides | `Found 0 widgets with key [<'food_form_duplicate_note'>]` |
| S-92c.12 twin | `Found 0 widgets with key [<'food_form_duplicate_note'>]` |
| S-92c.13 fractions | `Bad state: No element` (no line to read) |

### Mutation proofs (restored verbatim; `MUTANT` grep over `lib/` and `test/` empty at the end)

| # | Original line | Mutant | Red |
|---|---|---|---|
| a | `fat: _parsed(_fat),` | `fat: 0, // MUTANT (a)` | S-92c.1 `Expected: '= 220 cal' Actual: '= 112 cal'`; S-92c.13 `Expected: '= 5 cal' Actual: '= 0 cal'` |
| b | `_name.text.trim(),` (inside `nameExistsInLibrary`) | `_name.text, // MUTANT (b)` | **GREEN** — `FoodLibraryState.nameExistsInLibrary` trims its own argument, so this mutation changes nothing observable. The brief's mutation (b) proves nothing; see b'. |
| b' | `'"${_name.text.trim()}" in the Library',` | `'"${_name.text}" in the Library', // MUTANT (b')` | S-92c.10 `Found 0 widgets with text "... "chicken breast, skinless" ..."` (note keeps the padding) |
| c | tile block after the name/note, before the category dropdown | tile moved to first child, `// MUTANT (c)` | S-92c.7 `Expected: a value less than <16.0> Actual: <128.0>` |

S-92c.10's case-insensitivity leg has no mutation inside the permitted files: the fold lives in
`lib/state/food_library_state.dart` (out of scope for this phase) and the form only forwards the
name. That leg is proved by the prove-red above, where no note exists at all.

`test test/food_form_label_test.dart` after the restores → `00:01 +19: All tests passed!`

### Green (Phase 2B)

- `test test/food_form_label_test.dart` → `00:01 +19: All tests passed!`
- Neighbours (`food_form_decimals_and_autofocus`, `food_form_serving`, `food_form_orphan_category`,
  `food_form_pick_saves`, `edit_food_save`, `nutrition`) → `00:17 +144: All tests passed!`
- `test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` →
  `00:01 +54: All tests passed!`

### Residue sweeps (Phase 2B)

- `grep 'Required|food_form_calories|food_form_duplicate_note|floatingLabelBehavior' lib/` →
  each new key at its single site in `food_form.dart`, `floatingLabelBehavior` in `_macroField`
  only, `'Required'` in `_macroField` only (the rest is unrelated features and English prose).
- `grep '?? 0.0).toString()' lib/` → no matches (the line formats from a number, not from text).
- `grep "find.text('Required')" test/` → `test/food_form_serving_test.dart` only (package amount).
- `grep 'hive_workout_repository' lib/` → `lib/main.dart` only (composition root).

### Lint and full suite (Phase 2B)

- `lint` → **181 issues, 0 errors**, equal to the plan baseline; no issue names `food_form.dart`
  or `test/food_form_label_test.dart`.
- `test` (full suite) → `03:58 +5951 ~2: All tests passed!` (5951 passed, 2 skipped, 0 failed).

### Diff footprint (Phase 2B)

`git-diff --stat` → `lib/features/nutrition/widgets/food_form.dart | 91 ++--` and
`test/food_form_label_test.dart | 363 ++++` (cumulative for Phases 2A+2B against `3ed09c3f`).
No other file in this phase's diff. No formatter pass was run on the tracked files.

## Phase 3 — docs (developer)

Docs only; no source or test file was touched. Facts were read from
`lib/features/nutrition/widgets/food_form.dart` (build order, `_macroField`,
`_onSave`, `_parsed`), `lib/core/utils/food_helpers.dart`
(`caloriesFromMacros`, `calculateCalories`, `formatGrams`) and
`lib/state/food_library_state.dart` (`nameExistsInLibrary`, read-only).

### Edits

- `docs/widget_catalog/nutrition_widgets.md` · `### FoodForm`: the
  "serving control is stated in full" hedge now covers the macro block too; a
  new **Label-like macro block** paragraph states the order Fat, Carbs, Fiber,
  Protein, Sodium (unchanged keys `food_form_fat`, `food_form_carbs`,
  `food_form_fiber`, `food_form_protein`, `food_form_sodium`), the blank boxes
  and faint `0` hint (`FloatingLabelBehavior.always`, macro boxes only), the
  `formatGrams` prefill, the blank-save contract (blank P/C/F → `0`, blank
  fiber/sodium → `null`, a lone `.` → `Must be a number`), the live
  `food_form_calories` line and its `caloriesFromMacros` owner (the function
  `calculateCalories` delegates to), and the photo tile below the name. A new
  **Duplicate-name note** paragraph states `food_form_duplicate_note` +
  `nameExistsInLibrary` (name-only, trimmed, case-folded, own food and
  `catalogId` twin skipped, never blocks).
- `docs/nutrition.md` · `### AddFoodScreen` New Food paragraph: one sentence on
  the label-like form (blank faint-`0` boxes, package order, live calories line,
  photo below the name, quiet duplicate note). `### EditFoodScreen`: one
  paragraph covering the same block for edit mode.
- `docs/state_management/nutrition_state.md` · library method table: a
  `nameExistsInLibrary` row after `libraryIdFor` (read-only predicate,
  name-only, twin exclusion, never blocks, `_matchesIdentity` not reused).

Old-state sweeps on the three docs: `grep '0\.0|Required'` finds only the test
names that contain `0.0` and the one clause saying amount fields keep
`Required`; no sentence implies the old protein-first order, `0.0`-prefilled
boxes or `Required` on the macro boxes.

### Test names and keys written into the docs (each grepped)

- `test/food_form_label_test.dart` (no group; top-level `testWidgets`): all 19
  names quoted exist — S-92c.1/.2/.3/.4/.5/.6/.7/.8×3/.10/.11/.12/.13/.14×3/
  .15/.16.
- `test/food_library_state_test.dart`: groups `Food Helper Functions` and
  `nameExistsInLibrary`; quoted S-92c.9 names (3 + 10) exist, including
  `S-92c.9 a legacy row with no catalogId is a separate food (D-92c.13)`.
- Keys quoted: `food_form_calories`, `food_form_duplicate_note`,
  `food_form_image_tile`, the five macro keys — each has exactly one `Key(...)`
  site in `food_form.dart`.

### Checked-no-edit (recorded, no change made)

- `docs/design_system.md` — `grep 'hintText|floatingLabel|hint|InputDecoration'`
  finds one prose "hint" (the empty-state line), no hint/label decoration rule;
  the form follows no rule this doc owns.
- `docs/data_models.md` — no `FoodForm` / `caloriesFromMacros` /
  `nameExistsInLibrary` mention, and no stored field changed (D-92c.8): the
  form writes the same `FoodDraft` fields as before.
- `docs/db_integration.md` — no `FoodForm` / `food_form` / `FoodDraft` mention;
  no repository, box, schema or snapshot change (form-local until Save, same
  write path).

### Doc size band (52 KiB)

`test test/docs_indexing_contract_test.dart` → `00:00 +13: All tests passed!`,
including `no documentation file exceeds the indexing ceiling` and
`no documentation file is within the warning band of the ceiling` — all three
edited docs remain under the band, so no split. Exact byte counts could not be
printed (`wc`/`ls` are outside the gateway's allowed commands); the two size
guards are the measurement.

### Contracts and lint

- `test test/ui_standards_contract_test.dart` → `00:01 +41: All tests passed!`.
- `test test/docs_indexing_contract_test.dart` → `00:01 +13: All tests passed!`.
- `lint` → **181 issues, 0 errors**, equal to the brief's baseline (the one
  warning is the concurrent unit's `test/food_catalog_load_test.dart:270`);
  no issue names a doc or this phase's files.

### Plan statuses updated

- This plan (92c): `> Status: implementation complete, pending review. Next
  handoff: @code-reviewer.`; Phase 3 ticked **Complete**.
- 92b plan: status set to
  `CLOSED — implemented and reviewed (APPROVE; 2 minor findings left: untested
  g/ml package-amount carry-over, cosmetic heading fallback while an invalid
  package amount is typed), committed`. Its Progress boxes were already all
  `[x]` (Phases 1, 2A, 2B, 3 and the Status box) — `grep '\[ \]'` found none,
  so nothing needed ticking.
- Series index: `> Status: 92a CLOSED, 92b CLOSED, 92c implemented, pending
  review; owner device checks pending.` The owner-approved-defaults sentence is
  unchanged.

### Diff footprint (Phase 3)

`gateway.sh git-diff HEAD --stat` for this phase: `docs/nutrition.md +28`,
`docs/widget_catalog/nutrition_widgets.md +76`, `docs/state_management/
nutrition_state.md +1`, the three plan files `+2/+2/+4`, plus this evidence
file. Other modified paths in the overall workspace diff belong to concurrent
units (catalog seed/assets, session summary, watch bridge, constants reference)
and were not touched.



