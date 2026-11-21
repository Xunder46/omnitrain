# Evidence: plan 283a, the Wear wrist reads the phone's settings (2026-11-21)

Base commit `ed659a57`, committed at the end of the unit.

## Suites (observed output)

- Full suite after the last change: `flutter test` -> `+8759 ~4: All tests passed!`, exit 0 (plan 282's last run was +8736; 23 tests added).
- `test/watch_phone_preferences_test.dart` + `test/wear_phone_settings_test.dart`: `+23: All tests passed!` (re-run by the lead after the fix round).
- `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart`: `+54: All tests passed!`.
- `flutter analyze`: 174 issues (the baseline), 0 errors. Invariant grep: no output. `plan-lint before` and `after`: clean.

## Mutation pass (the lead's, scripted: one-line mutant, run the plan's test files, restore, `cmp`)

24 mutants over the owner class (tie, ordering, negative and late copies, absent keys, defaults, restore, record id, return value, type check, validator), both stores (copies dropped, Hive row type missing), the logging state getter, the orchestrator route, the shell provider and the boot restore. First pass: 21 killed, 3 survived (return value `true` always, the type check, the validator verdict). A tests-only fix round added S-28309b, S-28308f and S-28308g; all three re-killed. Final: 24 of 24 killed.

## Not verified here

- A real phone and watch pair: that the phone's `preferences_down` actually arrives on a Wear watch and the units flip (owner check 6 in `docs/wear_os_app.md`).
- The accent colour and the effort-rating flag are stored and readable but nothing reads them yet (plans 283b/283c and the accent item).
- No separate reviewer run (about 210 production lines, a close mirror of the Apple `WatchPhonePreferences.swift` and of the food-catalog plumbing); the lead read the production diff: no finding.
