# Plan 91 — evidence

## Phase 1 (@developer, 2026-10-29)

### Baseline (before any edit)

`flutter analyze` (300 s wrapper): `180 issues found.` — all `info`, 0 errors, 0 warnings.

### Phase 0 — red run (tests written, piece stubbed to `SizedBox.shrink()`, scan stubbed to `const []`)

`flutter test test/omni_header_add_button_test.dart test/ui_standards_contract_test.dart test/header_standardization_test.dart test/pr8_exercise_library_test.dart test/calendar_layout_responsive_test.dart`
→ `+160 -12: Some tests failed.`

| Scenario | Test | Red reason (observed) |
|---|---|---|
| S-9151 | piece: one "+", label, colour | `Found 0 widgets with icon Icons.add` |
| S-9152 | piece: same size | `Found 0 widgets with key [<'a'>]` |
| S-9153 | piece: press shrink | `Found 0 widgets with key [<'k'>]` |
| S-9158 | F1, F2, F3, F4, F10, line-number test (6 tests) | `Expected: an object with length of <1>, Actual: []` |
| S-9154 | Exercise Library header uses the piece | `Found 0 widgets with type "OmniHeaderAddButton" that are ancestors` |
| S-9155 | Calendar header icon | `Found 0 widgets with icon Icons.date_range descending from OmniBackHeader` |
| S-9156 | icon opens Periodization | `tap(): Found 0 widgets with key calendar_training_periods_button` |
| S-9157 | tightened `+N` finder | green before and after: the badge really shows (no hidden failure) |

F5–F9 (0 expected) pass against the stub by construction; they go green-and-meaningful once the scan finds F1–F4.

### S-9159 red → green

Red — scan implemented, screen edits (items 3–4) not yet made (`flutter test test/ui_standards_contract_test.dart --plain-name "S-915"` → `+11 -1: Some tests failed.`), exactly 2 findings:

```
· lib/features/calendar/calendar_screen.dart:93 OmniBackHeader builds a raw "+" (use OmniHeaderAddButton)
· lib/features/exercise/exercise_library_screen.dart:117 OmniBackHeader builds a raw "+" (use OmniHeaderAddButton)
```

Green — after items 3–4: S-9159 passes (0 findings) inside the Done Criteria run below.

### Done Criteria

- `flutter test test/omni_header_add_button_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart test/header_standardization_test.dart test/pr8_exercise_library_test.dart test/calendar_layout_responsive_test.dart test/screen_overflow_contract_test.dart` → `00:06 +233: All tests passed!`
- `flutter analyze` after → `180 issues found.` (baseline 180; the sorted issue lists, line numbers stripped, are identical; 0 errors).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- Full `flutter test` (900 s wrapper, exit 0): `03:45 +5868 ~2: All tests passed!` (0 failed, 2 skipped; the tree also carries other units' uncommitted watch/summary edits).

### Footprint

New: `lib/widgets/buttons/omni_header_add_button.dart` (86 lines), `test/omni_header_add_button_test.dart` (163 lines).
`git diff --stat` of the edited files: 12 files, 336 insertions, 52 deletions (`ui_standards_contract_test.dart` +162, `header_standardization_test.dart` +46/−13, `pr8_exercise_library_test.dart` +50, `calendar_screen.dart` +13/−20, `exercise_library_screen.dart` +6/−7, docs +61/−6 across six files).
Doc sizes after: `design_system.md` 44,235 B, `layout_and_inputs.md` 17,533 B, `navigation_and_screens.md` 29,192 B, `calendar_periods.md` 12,440 B — all under the 52 KB band.

## Phase 2 (@developer, 2026-10-29)

### Baseline (before any edit)

`flutter analyze` (300 s wrapper): `180 issues found.` — 0 errors.

### Phase 0 — red run (tests written, `add_food_screen.dart` untouched)

`flutter test test/nutrition_test.dart test/library_merge_test.dart test/picker_polish_test.dart test/screen_widget_test.dart` → `+345 -7: Some tests failed.`

| Scenario | Test | Red reason (observed) |
|---|---|---|
| S-9161 | Library tab has the header + and no bottom button | `Found 0 widgets with type "OmniHeaderAddButton"` |
| S-9163 | Categories tab: New Category, twice | `type 'FilledButton' is not a subtype of type 'IconButton'` (key still on the bottom button) |
| S-9164 | a tab round trip keeps exactly one header + | `Found 0 widgets with type "OmniHeaderAddButton"` |
| S-9166 | the list end leaves no room for the old button | `Expected: <16> Actual: <112.0>` |
| S-9165a | S-13113 / S-9165a (picker_polish) | `type 'FilledButton' is not a subtype of type 'IconButton'` |
| S-12814 | library_merge tooltip check | `type 'FilledButton' is not a subtype of type 'IconButton'` |
| S-12818 | library_merge source guard | `Expected: not contains '\'+ New Food\''` |

S-9165 passed in that run (the old bottom button carries the same key); it was then tightened to require `new_food_button` inside the `AppBar`. Mutation check: removed the line `        actions: [_buildHeaderAdd(context)],` → `--plain-name "S-9165"` `+0 -1` (`Found 0 widgets with key [<'new_food_button'>]`); exact line restored → `+1: All tests passed!`.
S-9162 (`screen_widget_test.dart`, tap by key) is "as today" by design and passed both before and after.

### Plan 78 override (S-9165a)

Plan 91 D-91.10 intentionally supersedes plan 78 D-3 ("Library CTA label `+ New Food`"): test `S-13113` in `test/picker_polish_test.dart` is renamed `S-13113 / S-9165a: the Library create action is the header + labelled New Food` and now asserts tooltip `New Food` with `+ New Food` / `+ Create new food` text absent. `S-12818` in `test/library_merge_test.dart` likewise inverts its `label: '+ New Food',` assertion.

### Done Criteria

- `flutter test test/nutrition_test.dart test/library_merge_test.dart test/picker_polish_test.dart test/screen_widget_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart test/library_grouping_test.dart test/library_row_toggle_test.dart test/confirmation_dialog_guard_test.dart test/my_foods_unification_test.dart test/food_group_membership_test.dart test/food_photo_clear_legacy_edit_test.dart` → `00:15 +444: All tests passed!`
- Item 6 readers alone → `00:03 +38: All tests passed!`
- `flutter analyze` after → `180 issues found.` (baseline 180; sorted issue lists with line numbers stripped are identical; 0 errors).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- Full `flutter test` (900 s wrapper, exit 0): `03:39 +5870 ~2: All tests passed!` (Phase 1 was +5868: the 3-test bottom-CTA group became the 5-test header group).

### Residue sweep (item 8)

1. `grep -rn "_buildBottomCTA\|'+ New Food'\|'+ New Category'" lib test` → `lib`: none. `test`: 6 hits, all absence assertions the plan's items 4–5 require (`library_merge_test.dart:283,297` `findsNothing`; `:541-543` the S-12818 "is gone" list; `nutrition_test.dart:4271,4272` S-9161 `findsNothing`; `picker_polish_test.dart:292` S-9165a `findsNothing`). See A-4.
2. `grep -rn "new_food_button\|new_group_button" lib` → only `add_food_screen.dart:160,167` (the header call).
3. `grep -rnE "\+ New (Food|Category)" docs --exclude-dir=plans --exclude-dir=history --exclude-dir=releases` → no hits.
4. `grep -rnE "Text\('\+'\)" lib` → no hits.

### Footprint

`git diff --numstat` (Phase 2 files): `add_food_screen.dart` +26/−35, `nutrition_test.dart` +157/−181, `library_merge_test.dart` +27/−5, `picker_polish_test.dart` +19/−6, `screen_widget_test.dart` +7/−7, `docs/nutrition.md` +8/−5, `nutrition_widgets.md` +2/−2, `my_routines.md` +1/−1; one-line edits in `design_system.md` and `navigation_and_screens.md` (on top of Phase 1's uncommitted edits). No file outside Predicted Files.
`dart format --output=none` on `add_food_screen.dart` reports pre-existing drift only (lines 404, 602, 641, 925, 1347, 1833 — none in Phase 2 edits); not formatted, per the rule on existing files.
Doc sizes after: `design_system.md` 44,258 B, `nutrition.md` 30,568 B, `navigation_and_screens.md` 29,215 B, `my_routines.md` 27,400 B, `nutrition_widgets.md` 15,685 B — all under the 52 KB band.

## Review fixes (@developer, 2026-10-29)

Findings 1–6 of the `.review.md` (Suggestions skipped, by the owner's call).

| # | Fix |
|---|---|
| 1 | `docs/README.md` tree: `widgets/buttons/` names `OmniHeaderAddButton`. |
| 2 | `docs/state_management/nutrition_state.md`, `docs/data_models.md`: "+ New Item tab" → the header "+" (`New Food` on Library, `New Category` on Categories), citing S-9161 / S-9165 / S-12814. |
| 3 | New test `test/header_standardization_test.dart` "S-9156: returning from the Training periods list refreshes the calendar" (a period saved while the list is open is absent from `calendarState.periods`, present after back); cited in `docs/calendar_periods.md`. |
| 4 | Icon/size/colour prose removed from `docs/calendar_periods.md` and `docs/widget_catalog/layout_and_inputs.md`; pointers to `design_system.md` ("Buttons" `Header add` row, "Header actions"). |
| 5 | Outer `Semantics` wrapper removed from `OmniHeaderAddButton` (covers Exercise Library and Manage Food Library, which use the piece unwrapped) and from the Calendar Training periods `IconButton`. S-9151 and S-9155 now assert exactly one semantics node carries the words (label or tooltip) and it has the tap action. A-5. |
| 6 | New test `test/nutrition_test.dart` "S-9166: on a phone with a home indicator the list end clears it (16 + the bottom inset)" (`viewPadding` bottom 34 logical px). |

### Item 5 red → green

Tests tightened first; source untouched → `flutter test test/omni_header_add_button_test.dart test/header_standardization_test.dart --plain-name "S-915"` → `+4 -2: Some tests failed.` (S-9151, S-9155: `Expected: exactly one matching candidate … Found 2 matching … Which: is too many`). The probe output from that run (S-9151):

```
SemanticsNode#7(Rect.fromLTRB(752.0, 4.0, 800.0, 52.0), flags: [isButton], label: "New Thing", textDirection: ltr),
SemanticsNode#8(Rect.fromLTRB(0.0, 0.0, 48.0, 48.0), actions: [focus, tap], flags: [isButton, hasEnabledState, isEnabled, isFocusable], ..., tooltip: "New Thing", textDirection: ltr),
```

After removing both wrappers → same command `+6: All tests passed!` (one node: tooltip, button, tap).

### Item 6 red → green (mutation)

Original lines `add_food_screen.dart:667` `                    16 + MediaQuery.viewPaddingOf(context).bottom,` and `:1734` `            16 + MediaQuery.viewPaddingOf(context).bottom,`. Mutated both to `16,` → `--plain-name "S-9166"` `+5 -1` (`Expected: <50.0> Actual: <16.0>` on the new inset case; the zero-inset case stays green). Exact originals restored from a copy → `+6: All tests passed!`.

### Item 3 mutation (extra proof)

`calendar_screen.dart:169` `      widget.calendarState.refresh();` commented out → the refresh test `+0 -1` (`Expected: contains 'Plan 91 refresh block' Actual: []`); exact line restored → `+1: All tests passed!`.

### Runs after the fixes

- Done Criteria files of both phases plus item 6 readers in one run (`omni_header_add_button`, `ui_standards_contract`, `docs_indexing_contract`, `header_standardization`, `pr8_exercise_library`, `calendar_layout_responsive`, `screen_overflow_contract`, `nutrition`, `library_merge`, `picker_polish`, `screen_widget`, `library_grouping`, `library_row_toggle`, `confirmation_dialog_guard`, `my_foods_unification`, `food_group_membership`, `food_photo_clear_legacy_edit`) → `00:21 +625: All tests passed!`
- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` → `00:01 +54: All tests passed!`
- Full `flutter test` (900 s wrapper) → `03:51 +5872 ~2: All tests passed!` (+2 new tests over +5870).
- `flutter analyze` → `180 issues found.` (baseline 180, 0 errors).
- Invariant grep → empty (exit 1).
- Doc sizes: `data_models.md` 46,764 B, `nutrition_state.md` 27,570 B, `README.md` 20,832 B, `layout_and_inputs.md` 17,509 B, `calendar_periods.md` 12,475 B.
