# Evidence — 99b, the rated-weeks count

Executors append here. **Nothing in this file goes into the plan file**, and nothing in the plan file
is restated here beyond the commands and the counts.

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| P1 | `flutter test test/stats_rated_weeks_service_test.dart` | `+12` | the new service file: S-17101–S-17105 and its twin, S-17106, over both harnesses |
| P2 | `flutter test test/mix_layer_service_test.dart` | `+42` | adapted fixtures (S-1501, S-1503, S-1510, S-1511) |
| P2 | `flutter test test/mix_layer_screen_test.dart` | `+116` | adapted fixtures (S-1605, S-3204) |
| P2 | `flutter test test/modality_mix_period_service_test.dart` | `+6` | adapted fixtures (S-1904a, S-1907, S-1913) |
| P3 | `flutter test test/stats_rated_weeks_screen_test.dart` | `+8` | the new screen file: S-17107 and twin, S-17108 and twin |
| P4 | `flutter analyze` | `181 issues found.` | equals the plan's lint baseline; no new notice |

## Red runs and inverse-edit mutations

The lead's mutation runs: 5 of the 6 mutants were killed on the first pass. The survivor was the
upper-bound mutant (`startMs < ratedEndMs`); the twin test added in fix round 1
(`test/stats_rated_weeks_service_test.dart`, `S-17105 twin a rated session after the period does not
count`) now kills it.
