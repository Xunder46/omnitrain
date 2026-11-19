# Evidence: plan 157c — Sustained High Load stops counting unrated weeks as zero load

Base commit `cd117f79`. Docs-only unit (Phase 2); the code (Phase 1) was built and verified by the lead before this run.

## Tests

- New: `test/sustained_high_load_unrated_weeks_test.dart` — 8 plain tests plus S-15906 on Mock and Hive (`S-15901`..`S-15906`, `S-15902b`).
- Existing, green unedited: `test/sustained_high_load_test.dart`, `test/sustained_high_load_service_test.dart`, `test/sustained_high_load_signal_screen_test.dart`, `test/training_load_test.dart`, `test/signals_service_test.dart`.
- Fixture change by the lead: `_seedFTwo` in `test/cardio_efficiency_drift_signal_screen_test.dart` (S-2511) now seeds a rated zero-minute session in F-9A's two quiet weeks, because its unrated cardio sessions can land in them and would make them unrated weeks.
- Lead's mutation pass: 9 mutants, 9 killed (two after tests-only additions: a pinned divisor guard and a streak case).

## Docs delta executed

| Doc | Change | Verdict | Test read this run |
|---|---|---|---|
| `docs/training_load.md` | row 1, MODIFIED: divisor leaves unrated weeks | done | `test/sustained_high_load_unrated_weeks_test.dart` (`S-15901 unrated weeks are left out of the baseline divisor`) |
| `docs/signals_registered.md` | row 2, MODIFIED: baseline divisor | done | same as row 1 |
| `docs/signals_registered.md` | row 3, MODIFIED: easier-week fact | done | same file (`S-15904 an unrated week is not an easier week`) |
| `docs/signals_registered.md` | `Verified by` sentence of the baseline bullet gains the new test file | done (fits the 400-byte budget) | the new test file exists with `S-15901`..`S-15906` |
| `docs/state_management/services_and_utils.md` | row 4, ADDED bullet on `hasSessions` | done (marker `each entry also says whether the week held any session` inside it, one line) | `test/sustained_high_load_unrated_weeks_test.dart` (`S-15906 ${harness.name}: weeklyLoads marks which weeks held sessions`) |

## Stale-term sweep

`grep -rIn "empty week\|÷ twelve\|counting as zero\|counts as zero" docs` minus `docs/plans`, `docs/history`, `docs/releases`: 53 hits, all either the rows above (now updated), test names (`S-2406`, `D-1702` citations in `docs/training_load.md:187-188`, `docs/signals_registered.md:33`, `services_and_utils.md:538`), or true statements about the series/measure that keep empty weeks at zero (`docs/training_load.md:174`, `:234`; `services_and_utils.md:478`, `:531`). No stale divisor claim outside `docs/plans`. Full list in the report.

No test was run in this unit (brief: run NO test).
