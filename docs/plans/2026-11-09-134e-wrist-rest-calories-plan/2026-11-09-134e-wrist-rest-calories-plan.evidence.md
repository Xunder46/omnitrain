# Evidence — plans 134b, 134c1, 134c2, 134d, 134e (calories burned, the rest of the units)

Observed by the lead on 2026-11-09, base commit `ff398e1a7ec18409d9fc8c890bf35d2fde656e69`, branch `claude_develop`, nothing committed. One evidence file for the five plans, which were built in one batch on top of the uncommitted 134a (`docs/plans/2026-11-08-134-calories-burned-plan/`).

## Counts

| Check | Result |
|---|---|
| Full `flutter test` | `+7257 ~2: All tests passed!`, 0 failures (134a ended at `+7168 ~2`) |
| Full Swift package (`swift test --package-path watch/watchos`) | `Executed 1286 tests, with 0 failures` |
| Watch app target (`xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App"`, Apple Watch Series 11 42 mm simulator) | `** BUILD SUCCEEDED **` |
| `flutter analyze` | 181 issues = baseline, 0 errors |
| Invariant grep (no `hive_workout_repository` import in `lib/state`, `lib/features`, `lib/widgets`, `lib/core`) | no hit |
| `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `plan-lint after` | clean on all five plans |
| New test files | `fuel_burned_summary_test` 12 (6 x Mock and Hive), `active_energy_live_test` 26, `session_live_calories_test` 8, `watch_energy_import_test` 34, `WatchActiveEnergyTests` 15, `WatchRestEnergyTests` 5 (each run by the lead or seen in the builder's report and again in the full runs) |

## Phases

| Plan | Phase | Agent | Result |
|---|---|---|---|
| 134b | P1 model + service | crew-builder-app | red (compile) then green; lead re-ran |
| 134b | P2 card + tests | crew-builder-app | red 4 of 12, green; lead read the production diff |
| 134c1 | P1 contract + Swift validator | crew-builder-watch | red then `Executed 6 tests, 0 failures`; lead re-ran |
| 134c1 | P2 Dart validator + importer | crew-builder-app | `+32` new, `+176` neighbours; one deviation (a NaN cannot reach the importer: the inbox refuses non-JSON payloads) |
| 134d | P1 service + state | crew-builder-app | `+26`, neighbours green; lead re-ran |
| 134d | P2 screen | crew-builder-app | one deviation: a `FittedBox` + `Flexible` because the plain bar overflowed the 320 dp guard by 2 dp (accepted, plan updated) |
| 134c2 | P1 package | crew-builder-watch | red (18 compile errors) then 13 tests green; production diff matches the seed line for line |
| 134c2 | P2 feed | crew-builder-watch | `testS13474...` green; the app target built by the lead |
| 134e | P1 package | crew-builder-watch | red (17 compile errors) then 5 tests green; the rest-source guards still green |
| docs | two docs-keeper runs | crew-docs-keeper | every row applied; the lead realigned three New markers the keeper wrapped over two lines |
| review | two reviewers | crew-reviewer | both APPROVE: phone 0/0/1 minor, watch 0/0/2 minors |

## Lead mutation pass

64 runs (37 phone-side, 27 watch-side, plus one extra). First pass: 6 survived. Closed by two tests-only fix runs (a held-path abandoned end, an edit-mode empty-state chip, the 60th-tick weight re-read, a negative count before the window, two counts before the window, the feed's permission body), after which all were killed. Two stay as equivalent by design: the importer's idempotence check behind the outer `appliedAtMs` guard, and a one-day widening of the Fuel window start, which cannot be seen on 2026-11-09 because the US clocks changed on 2026-11-01 (a two-day widening is killed). Every mutated file was restored and compared byte for byte.

## Known gaps (for the owner)

- No live watch-to-phone energy feed: the phone's active-session bar shows an estimate (`~`) while a session runs; the watch's measured total reaches the phone with the session end. The wrist's rest screen shows the watch's own running total, so the two numbers can differ during a session.
- A Free Training session's live figure uses the resistance MET for the whole elapsed time, so it can step when the session ends if it had timed cardio or holds.
- After a recovered workout (the app was killed mid-session) the wrist's running line restarts from the new counter; the total sent on the end keeps the chain.
- `(owner)` a real-watch session: the Calories pill reads a plain number (no `~`) on the phone's Session Summary, and the wrist's rest screen shows `N kcal burned` (QA step 35). The simulator has no workout sensors.
- `(owner)` the rest-screen line's fit on a 40 mm watch (the reviewer's estimate is marginal).
- `(owner)` the Effort row and the new Calories chip on a real phone at 390 pt and on the smallest phone.
- The MET numbers are still the lead's defaults (resistance 3.5, cardio 7.0, isometric 2.3, sports 6.0).
