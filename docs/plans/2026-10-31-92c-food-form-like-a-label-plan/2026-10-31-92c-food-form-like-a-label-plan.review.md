# Code Review: 92c food form like a label (round 1)

Reviewer: code-reviewer (Copilot CLI). Base commit `3ed09c3f`, review range `3ed09c3f..HEAD` (lib, test, docs).

## Verification record

- Full suite (run by reviewer): `.github/copilot/scripts/macos/gateway.sh test` → `03:51 +5951 ~2: All tests passed!` — **5951 passed, 2 skipped, 0 failed**. Matches the handoff's pasted counts.
- Prove-red spot-check (reviewer-run): `.github/copilot/scripts/macos/gateway.sh prove-red 3ed09c3f test test/food_form_label_test.dart` → **RED AT 3ed09c3f**, `+2 -17: Some tests failed` — every scenario fails at base for its seeded reason (order, `0.0` prefill, blank save blocked, `31.0`/`4.0` prefill, no hint, no calories line, tile first, no duplicate note). No guard is green at base.
- Mutation proofs sampled from the evidence (Phase 1): (a) `caloriesFromMacros` +1 → 6 failures incl. all three new unit tests; (b) archived skip dropped → exactly the S-92c.9 archived leg fails. Phase 2B table: (a) `fat: 0` → S-92c.1/S-92c.13 red; (b) untrimmed `_name.text` → GREEN (state trims its own argument — correctly replaced by b', the display-trim mutant, which is red); (c) tile moved first → S-92c.7 red. Restores verified by the evidence's `MUTANT` grep and re-runs.
- `git-diff 3ed09c3f -- test/helpers` → empty (AC-8 first half); `test/ui_standards_contract_test.dart` green inside the full suite (AC-8 second half).

## Acceptance criteria

- AC-1 ✅ `caloriesFromMacros` is the only formula in the touched code; `calculateCalories` delegates (food_helpers.dart:11-33); the form's line calls it via `_parsed` (food_form.dart:617-622, 855); line sits below Sodium, above Notes (pinned by S-92c.1's dy assertions). No new `* 4`/`* 9` copy added by this change — see finding 1 for pre-existing copies.
- AC-2 ✅ Order fat → carbs → fiber → protein → sodium, keys/labels unchanged (food_form.dart:809-846); pinned by S-92c.2.
- AC-3 ✅ New food: five empty controllers (food_form.dart:289-306), `hintText: '0'` + `FloatingLabelBehavior.always` in `_macroField` only (food_form.dart:913-918); pinned by S-92c.3/S-92c.16.
- AC-4 ✅ Edit prefill through `formatGrams`; null fiber/sodium stay empty and save null (food_form.dart:289-306, 472-476); pinned by S-92c.5/S-92c.14 (three legs incl. type-then-clear → null).
- AC-5 ✅ Blank P/C/F → 0.0, blank fiber/sodium → null (`double.tryParse(...) ?? 0.0` / `isEmpty ? null : tryParse`, food_form.dart:472-476); lone `.` → `Must be a number` and Save blocked (validator food_form.dart:924-929; S-92c.6). No `double.parse` remains anywhere in food_form.dart — nothing can throw on a blank or `.`.
- AC-6 ✅ name → note → tile → category (food_form.dart:636-690); pinned by S-92c.7.
- AC-7 ✅ Note from live `_name.text` through `nameExistsInLibrary(_name.text.trim(), excluding: widget.initial)` (food_form.dart:652-668); never blocks Save (S-92c.8/S-92c.10/S-92c.12 assert saves go through).
- AC-8 ✅ No allowlist entry, no ratchet raise; both contract tests green.

## Brief checklist

1. One calories computation ✅ (see AC-1; pre-existing copies listed below).
2. Save contract walked by hand: fiber/sodium null → empty → null; fiber 0.0 → `0` → 0.0; all-blank and name-only new food → 0.0/0.0/0.0/null/null. An unrecorded fiber/sodium is never overwritten by 0.0. No other `double.parse` reader of the macro controllers exists.
3. Validation ✅: blank valid for all five macros; lone `.` blocks; `_validatePositiveDouble` (package amount, `Required`/`Must be a number`/`Must be greater than 0`) and the serving label are untouched.
4. Faint 0 ✅: hint + always-label on the five macro fields only (`floatingLabelBehavior` appears once in the file); name/category/notes/package keep base decoration (S-92c.16 asserts the resolved decorations); colours are `OmniTheme.colors.textSecondary` only.
5. Duplicate rule ✅: `nameExistsInLibrary` (food_library_state.dart:663-720) is name-only, trimmed, case-folded, skips archived, skips `excluding` and its catalogId twins both directions, and a legacy row without `catalogId` still counts (D-92c.13, tested). All three hosts pass `initial` (New Food null; Edit Food and the legacy edit shim the food being edited), and the form forwards it as `excluding`.
6. Rebuild safety ✅: typed text lives in controllers; the note and calories line are recomputed from controller text on every `ListenableBuilder` rebuild; `_name` listener added in `initState`, removed in `dispose`, `mounted`-guarded; no setState during build.
7. 92a/92b interaction ✅: the probe baselines first-seen values, so blank boxes start clean and typing still dirties; existing tests `nutrition_test.dart:2990` and `:3205` ("an untouched form pops with no dialog") cover the clean open-and-back for New Food and the legacy shim.
8. Tests ✅: S-003 now types `.` → `Must be a number`, S-004 expects `'4'` — the only assertion changes in `food_form_decimals_and_autofocus_test.dart`; no test asserts the old `0.0`/`Required` macro behaviour (`food_form_serving_test.dart:397` is the package amount; the other `find.text('0.0')` hits are routine/stepper screens).
9. UI standards ✅: `test/helpers` diff empty; the changed lib files add only themed `Text`s and `InputDecoration` properties — no raw `Card`/`SnackBar`/colour literal/shapeless button.
10. Docs ✅: every key, test name, group, type and file named in `nutrition_widgets.md`, `nutrition.md`, `nutrition_state.md` exists (checked against the test files); no product doc still describes the old order or `Required` macros (old-order mentions survive only in historical plan files).

## Findings

1. minor | lib/data/models/models.dart (Food.calories getter), lib/core/utils/macro_targets.dart, lib/features/nutrition/widgets/calorie_ring_card.dart, lib/state/nutrition_state.dart | pre-existing copies of the `* 4 / * 9` formula survive outside `caloriesFromMacros` (none introduced by 92c; the `Food.calories` parity test guards the getter) | out of 92c's scope — list for the owner as a future consolidation candidate | @planner
2. minor | docs/plans/...92c...evidence.md:275 | the Phase 2B residue sweep says `'Required'` is "in `_macroField` only", but the string lives in `_validatePositiveDouble` (food_form.dart:938) and `_macroField` no longer contains it | evidence bookkeeping only; correct the line when the evidence file is next touched | @developer
3. minor | docs/nutrition.md:120 | the edit joined two lines and dropped a space: "`test/library_merge_test.dart`(`S-12810`" | insert the missing space | @developer
4. minor | test/food_form_label_test.dart (S-92c.13) | the scenario's "open the Library list and find the row" leg is verified as `calculateCalories` over the captured draft rather than by opening the Library row — a faithful proxy (the row's code path is that same function) but not the literal flow | acceptable as-is; note for the owner if a literal row assertion is ever wanted | @developer

No blocker or major findings. Critical: 0 | Major: 0 | Minor: 4.

## Copy changes for the owner

- `= N cal` — the derived calories line (`food_form_calories`).
- `There's already a food called "<trimmed name>" in the Library` — the duplicate-name note (`food_form_duplicate_note`).
- Hint `0` — the faint placeholder in the five macro boxes.

## Assumption Log adjudication

A-92c.P1.1, A-92c.2A.1..4, A-92c.2B.1..5 — all RATIFY (each is consistent with the recorded decisions; A-92c.2B.4/5 are correctly scoped caveats, not silent guesses). Log is complete for a four-phase change.

## Open questions

None — the brief was unambiguous; the plan's own open questions 1–5 were already resolved with recorded defaults and none recurred.
