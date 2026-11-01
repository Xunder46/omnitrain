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

