# Plan 242 — A comma works as the decimal point in every number box

Series: nutrition/calendar/summary pre-launch review (2026-11-16), item "no decimal-comma handling anywhere in lib". Phone only. One shared parser and one shared key filter (`lib/core/utils/decimal_input.dart`), wired into the seven places that read typed decimals. The production edits are exact and already applied by the lead; one builder run writes the tests; then docs. Status: COMMITTED (built, mutation-checked (all effective mutants killed), docs applied; full suite +7989 ~4 green, analyze 181

## Goal and acceptance

A phone set to a comma-decimal language (German, French, Spanish, Russian, Portuguese...) shows a comma on the decimal keypad. Today: the food form's macro and package-size boxes and the food row's amount box filter their keys with a pattern that drops the comma, so `12,5` becomes `125` (ten times too much, silently). The measurement sheet, the height dialog, the logger's value popup and the nutrition target boxes accept the comma but read it as "not a number" (`Enter a valid number.`, or the edit is ignored). After this change `12,5` means 12.5 in all of them. The text on screen stays as typed; display of stored numbers (always a point) is unchanged.

Acceptance: S-24201..S-24206 green; the ones marked "fails without" are killed by the lead's mutation; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Type `12,5` in a food's fat box: it stays `12,5` and saves 12.5 g (today it becomes 125 g).
- Type `1,5` in a food row's amount box and tap log: 1.5 servings are logged (today the comma key does nothing).
- Type `72,5` in a body-measurement value or `182,5` in the height dialog: it saves 72.5 / 182.5 (today: "Enter a valid number.").
- Type `72,5` in the logger's weight popup: 72.5 (today the edit is ignored).
- Nothing changes for point typists. A number with both a point and a comma (`1,234.5`) or two commas is still rejected as "not a number" (it is ambiguous).
- To SEE it: any phone with a comma-decimal system language, open + New Item, type `0,5` in Fat. On an English phone, paste/type a comma with a hardware keyboard.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `parseDecimal(String)` in `lib/core/utils/decimal_input.dart`: trim; one comma and no point becomes a point; more than one comma, or comma plus point, is `null`; else `double.tryParse`. | `decimal_input.dart` |
| D-2 | `DecimalInputFormatter({maxFractionDigits})`: allows `^\d*[.,]?\d*$`, rejects an edit that breaks it (old text stays), optional cap on digits after the separator. Replaces the two `FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))` in the food form and the private `_AmountInputFormatter` (cap 3) in the food row. | `food_form.dart:770,950`, `log_food_row.dart` |
| D-3 | Every read of a typed decimal goes through `parseDecimal`: food form (macros, fiber, sodium, package size, calories-line reader, both validators), food row amount, measurement sheet and height dialog `_save`, nutrition target boxes (reader and validator), `MetricStepCalc.parseAndClamp`. Non-user parses (`weight_trend`, `food_helpers` legacy-label check, summary rounding) stay. | grep `double.tryParse` in `lib` |
| D-4 | The field text is never rewritten (no comma-to-point swap on typing), so the caret never jumps. | scope |
| D-5 | Product call, stated not asked: the comma is read as the decimal point, never as a thousands separator. Typing grouping separators was never supported. | owner rule: behaviour calls in one line |
| D-6 | The measurement sheet and height dialog have no key filter today; they are not given one here (only the read changes). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24201 | Pure test of `parseDecimal`: `2,5`, `2.5`, `12`, `,5`, `5,`, ` 2,5 `, `-2,5`, `` , `abc`, `1,2,3`, `1,234.5`, `1.234,5`. | 2.5, 2.5, 12.0, 0.5, 5.0, 2.5, -2.5, null, null, null, null, null. Formatter cases (call `formatEditUpdate` directly): `12,5` and `12.5` accepted; `1,2,3`, `1.2,3`, `a` rejected (old value kept); with `maxFractionDigits: 3`, `1,2345` rejected and `1,234` accepted. | comma not replaced (mutation) |
| S-24202 | Mock, `testWidgets`, the harness of `test/food_form_decimals_and_autofocus_test.dart`: add form, enter name, `12,5` in Fat, `3,25` in Protein, save. | the `FoodDraft` handed to the form's save callback has `fat == 12.5` and `protein == 3.25`; the Fat box still shows `12,5`. | the form's formatter drops the comma (`125`) |
| S-24203 | Same harness: open the package-size link, enter `30,5` in `food_form_package_amount`. | the serving choice reads `30.5` (read the draft's `referenceAmount`). | formatter drops the comma |
| S-24204 | Food row: the harness of `test/nutrition_log_from_library_test.dart`: enter `1,5` in `log_food_amount_<id>`, tap log. | one consumed row with `amount == 1.5`. | formatter rejects the comma |
| S-24205 | `MetricStepCalc.parseAndClamp`: `('weight','72,5')`, `('distance','5,25')`, `('reps','8')`, `('weight','+72,5')`, `('weight','1,2,3')`. | 72.5, 5.25, 8, 72.5, null. | `double.tryParse('72,5')` is null |
| S-24206 | Screen: the profile height dialog (cm mode): enter `182,5`, save; and the measurement log sheet for a weight measurement: enter `72,5`, save. | no "Enter a valid number." error; the dialog pops 182.5; the sheet saves 72.5. If the screens cannot be driven reasonably under Mock, test the nutrition target screen instead (`calories_field` boxes `150,5` shows no "valid number" error) and report which. | `double.tryParse` returns null: error shown |

## Input-reality checklist

1. Writers and units: the only writers of the numbers are these boxes; units (g, kg, cm) are unchanged; the parse yields the same double a point would.
2. Lifecycle: stateless parser and formatter; no state.
3. Settings changing while open: the system language does not matter; both separators are accepted at all times.
4. Time: none.
5. Cost: one `contains`/`replaceFirst` per read.
6. Words: no copy change. Error texts stay ("Must be a number", "Enter a valid number.").
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `test/decimal_comma_input_test.dart` (new, all six scenarios in one file; S-24204 and S-24206 may use their harness copied from the named file). No production code, no full suite.
2. **P2 lead**: mutation pass, docs, full suite.

## Readers

`grep -rln "food_form_package_amount\|food_form_protein\|log_food_amount_\|height_dialog_value_field\|parseAndClamp\|_AmountInputFormatter" test`: `food_form_decimals_and_autofocus_test`, `food_form_serving_test`, `nutrition_log_from_library_test`, `crown_control_tap_to_edit_test`, `screen_widget_test`, `nutrition_test`, `picker_polish_test`: reported if red, not edited.

## Mutation list (lead)

(a) `parseDecimal` does not replace the comma (S-24201, 02, 03, 04, 05, 06); (b) `parseDecimal` accepts comma plus point (S-24201); (c) the formatter allows only `.` (S-24201, 02, 03, 04); (d) the formatter's fraction cap removed (S-24201 cap case); (e) the food form's macro reader back to `double.tryParse` (S-24202); (f) the profile `_save` back to `double.tryParse` (S-24206); (g) the crown popup back to `double.tryParse` (S-24205).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/global_conventions.md` | ADDED | - | Typed decimals accept a comma | S-24201 |
| `docs/widget_catalog/nutrition_widgets.md` | ADDED | - | `A comma is accepted as the` | S-24202, S-24203, S-24204 |

(Stale-term sweep for `\d*\.?\d*`, `digitsOnly`, `_AmountInputFormatter` in `docs` outside plans/history/releases: no hits.)

## Lead notes

- Mutants (b) comma plus point accepted and (b2) two commas accepted were equivalent: with only the first comma replaced, `double.tryParse` already rejects a second separator. The two guards were removed from `parseDecimal` instead of kept as dead code.
- The nutrition target boxes (`TextInputType.number`, no comma key) are read through `parseDecimal` but no scenario drives them (S-24206's fallback was not needed); a pasted `150,5` there is covered only by the shared parser's own test.
- Mutant (h) (point-only filter on the fat box alone) was a compile error under the removed `services.dart` import; the shared formatter mutation (c) covers the wiring.

## Open items

1. Display: stored numbers are always shown with a point, even on a comma-language phone (a separate, larger change: localized number formatting).
2. (owner) On a phone set to a comma language, type `0,5` in Fat in + New Item and save; reopen: 0.5.

## Predicted files

`decimal_input.dart` (new, 62), five edited sources (+26 -60), one new test (~250), one doc line.

## Progress

- [x] Seeded
- [x] Production edit (lead; analyze 181)
- [x] P1 test (11 tests)
- [x] Mutation pass, docs
- [x] Full suite (+7989 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-242/base.txt` (b94a549a); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-242xx (five digits): none found; `S-242` (three digits, `watch_rest_ping_test`) is a different series.

## Feedback

(none yet)
