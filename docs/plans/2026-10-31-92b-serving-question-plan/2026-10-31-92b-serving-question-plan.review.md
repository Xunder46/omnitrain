# Review: 92b serving question (round 1)

Reviewer: code-reviewer (Copilot CLI). Base commit: 5bcdbd97. Diff scope: `git diff 5bcdbd97..HEAD -- lib test docs`.

Findings appended below as found.

## Verdict

**APPROVE.** Critical: 0 · Warnings: 0 · Suggestions: 2.

## Scope

Layers in scope: core/utils (new mapper), features (food_form), state (food_library_state), tests, docs.
Layers skipped: models, persistence, components, watch (no 92b changes; the hands-off unit's files excluded).

Diff vs Predicted Files: conforms — exactly the plan's Files Affected plus the plan/evidence docs. No out-of-bounds file, no unfinished predicted file.

## Test run (mine)

- Full `.github/copilot/scripts/macos/gateway.sh test` → **5918 passed / 2 skipped / 0 failed, "All tests passed!"** (log `.work/gateway/test-20261031-231959-63444.log`; the 134 "failure-looking" lines are the pre-release gate's intentional RED probes).
- prove-red spot-check 1: `prove-red 5bcdbd97 test test/food_library_copy_edit_test.dart test/food_library_edit_test.dart` → **RED AT 5bcdbd97**, 6 failures, every one `Expected: null / Actual: <150.0|100.0|200.0>` — the guarded stale-keep reason. Guard proven.
- prove-red spot-check 2: `prove-red 5bcdbd97 test test/food_form_serving_test.dart` → **RED AT 5bcdbd97**, 16/16 fail with `Found 0 widgets with key [<'food_form_basis'>]` — the guarded reason (the control does not exist at base). Guard proven.
- Mutation proofs sampled from the evidence file (4): S-92b.1 `ml`→`Per100G` (Phase 1, red, restored, 0 MUTANT residue); S-92b.13 `> 0` removal and S-92b.12 trim removal (2A-ii, red); S-92b.7 `amount.toString()` → `28.0` and S-92b.8 As-saved non-restore (2B, red). All restored verbatim.

## Acceptance criteria

- AC-1 PASS — grep `lib/` for the three old keys and the four strings: only the three `models.dart` ~L1946-1953 doc comments remain, the recorded D-92b.10 exception.
- AC-2 PASS — `test/food_serving_test.dart` iterates every distinct catalog triple and asserts `hasLength(28)` (not a hard-coded subset), plus the odd cases incl. `(count,1,' slice')` and NaN; hand walk confirms byte-identical round trips.
- AC-3 PASS — hand walk (below).
- AC-4 PASS — S-92b.6 both directions, S-92b.9 note appear/hide, S-92b.19 note hidden at equality.
- AC-5 PASS — all three `FoodLibraryState` paths conditional; keep path guarded by S-12702/S-12704 with serving-preserving drafts (D-92b.12 honoured; no test removed or renamed in either state test file).
- AC-6 PASS — `git-diff 5bcdbd97 -- test/helpers` empty; both contract tests green in the full run.

## Check 1 — AC-3 hand walk (no text box reaches the stored fields)

`_onSave` writes only `storedServingFrom(_currentChoice)`; `_currentChoice` is built from `_servingChoice` + the two controllers, and the controllers are read only through the mapper's `PackageServing`/`NamedServing` with a parse+`> 0` guard and a base fallback.

| Opened triple | Load | Untouched save |
|---|---|---|
| grams/100/g | Per100G, `_packageOpen`=false | (grams, 100, `g`) ✓ |
| grams/100/ml | Per100Ml | (grams, 100, `ml`) ✓ |
| grams/28/g | PackageServing, row open, text `formatGrams(28)`=`28` | (grams, 28, `g`) ✓ |
| grams/100.5/g | PackageServing, text `100.5` (`formatGrams` = `toString` for non-integers) | (grams, 100.5, `g`) ✓ |
| count/1/egg | NamedServing, field `egg` | (count, 1, `egg`) ✓ |
| count/3/tbsp | AsSavedServing carried verbatim | (count, 3, `tbsp`) ✓ |
| grams/100/`per 100g` | AsSavedServing | verbatim ✓ |
| count/1/`` | AsSavedServing (empty label fails rule 4) | verbatim ✓ |

## Check 2 — one computation

Heading, note and save all read the single `_currentChoice` getter (`food_form.dart` `_perNote`, build heading, `_onSave`). The note's `<X>` is `servingHeading(choice)` minus the `Nutrition per ` prefix, so note, heading and saved draft cannot disagree — matches D-92b.6 and A-92b.16. The `As saved` segment label and the heading both format the same carried triple with the same `formatGrams`. Validation computes no triple.

## Check 3 — AC-5 paths

- `editLibraryFood` compares the **cached row** (`current = _foods[libraryCopy.id]!`), not the argument — correct per the plan's note.
- Both propagation loops use `_servingTripleChanged(libFood|legacyFood, updatedCatalogFood)`; `resetLibraryFood` uses `_servingTripleChanged(copy, catalog)`.
- `_servingChanged` / `_servingTripleChanged` compare exactly the three stored fields — the same rule the mapper encodes, on different types (Food/FoodDraft vs ServingChoice); acceptable, not a divergent duplicate.
- Other writers (grep `lastAmountConsumed` in `lib/state`, `lib/data`): `NutritionState._writeThroughLastAmount` (sets a logged amount — different feature, not a serving path), `catalog_refresh_service.dart` (explicitly must not touch), `watch_reference_sync.dart` (read-only). No unlisted writer.

## Check 4 — edge cases

- `.` / `0` package amount: formatter allows them, `_validatePositiveDouble` rejects both on save; while invalid, `_currentChoice` falls back to the 100 g / 100 ml base (A-92b.10) — consistent.
- Very long digit strings parse as finite doubles and store verbatim.
- Switching segments with the package row open: `_packageOpen` is state, the row hides off the g/ml segments and restores with its typed amount (S-92b.18).
- Spaces-only serving label: validator trims and rejects; heading reads `Nutrition per 1 serving`.
- Hot rebuild: the `ListenableBuilder` re-runs `build` only; controllers, `_packageOpen`, `_servingChoice`, `_asSaved`, `_openedServing` are State fields and survive (S-92b.14 covers it).

## Check 5 — accessibility/interaction

`SegmentedButton` and the `FilterChip`s are tapped as real controls in the tests (`tester.tap(find.text('100 ml'))`, chip by key); `Nutrition facts are per` reads sensibly; the package link is a `TextButton` with an explicit `shape:` and `OmniTheme.buttonUtilityRadius`.

## Check 6 — UI standards

`test/helpers` diff empty (no allowlist entry, no ratchet). No raw `Card`/`SnackBar`/`StadiumBorder`/colour literal added; `food_form.dart:1124` `Colors.transparent` is pre-existing, outside this diff. Theme tokens only in the new style code.

## Check 7 — tests

- Mutation proofs sampled: see above; all red for the guarded reason, restored, 0 `MUTANT` residue.
- `test/nutrition_test.dart` and `test/food_library_copy_edit_test.dart`: no test removed or renamed between `5bcdbd97` and HEAD; both old-key tests rewritten to the new control, the 50 g case now asserts the stored triple; S-12702/S-12704 keep their `lastAmountConsumed` keep assertions with serving-preserving drafts.
- S-92b.1 iterates all 28 catalog triples (`hasLength(28)` asserted) — not a subset.

## Check 8 — docs

All keys, test names (verbatim, group included) and types cited in the three edited docs exist: 16 `FoodForm serving (S-92b)` test names, 6 `food_serving` test names, the S-92b.10/S-92b.17 state test names, `food_form_*` keys, and the mapper's three functions. `grep "Unit type|Reference amount|Reference label"` over `docs/` hits only `docs/plans/**` — 0 outside plans. No stale prose found about the removed boxes or heading.

## Check 9 — anything missed

- `referenceLabel` in `lib/features`: only pass-through plumbing (`add_food_screen.dart` draft → `updateCustomFood`) and the `_FoodIdentity` dedup mirror — no second computation of the triple.
- The watch reads the stored fields only; they are unchanged.
- All 63 seeded `count` foods in `food_catalog_seed.dart` have `referenceAmount: 1` — no seeded count food with amount != 1.

## Findings

1. `lib/features/nutrition/widgets/food_form.dart` (`_packageChoiceOrBase` via `_onBasisChanged`) — minor — switching 100 g ↔ 100 ml keeps the typed package amount and re-labels it (30 g becomes 30 ml) — intended by D-92b.5's "keeps the typed package amount" but untested — suggest a one-line assertion in S-92b.18's file if the owner wants it pinned. @developer
2. `lib/features/nutrition/widgets/food_form.dart` (build, package field) — minor — while an invalid amount (`0`, `.`) is typed, the heading falls back to `Nutrition per 100 g` until save surfaces the error — cosmetic, consistent with A-92b.10 — no action needed unless the owner disagrees. @owner

## Copy changes for the owner

New user-visible strings: `Nutrition facts are per`; segments `100 g`, `100 ml`, `1 serving`, `As saved: <amount> <label>`; `Enter package serving instead (e.g. 30 g)`; `Back to per 100 g` / `Back to per 100 ml`; `Serving size (g)` / `Serving size (ml)` with hint `30`; `Called a…` with hint `slice`; error `Name the serving, e.g. slice`; chips `slice`, `scoop`, `bar`, `piece`, `cup`; headings `Nutrition per …`; note `Check these numbers are per <X>`.

## Assumption Log adjudication

A-92b.1..A-92b.19 reviewed against the code: all consistent with the recorded decisions. RATIFY A-92b.6, A-92b.7, A-92b.10, A-92b.12, A-92b.16, A-92b.17 (each is load-bearing and verified above); the rest are procedural and ratified with them. No silent guesses found.

