# Evidence — Cross-Modality Interference (Stats PR 7b)

> Plan: `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md`
> Review findings go in `2026-10-03-07b-stats-pr7b-interference-plan.review.md`. Nothing in this file
> is ever copied into the plan.

## Baselines

| Command | Output |
|---|---|
| `flutter analyze` (planner, on `develop`, before 7a) | `196 issues found.` (0 errors) |
| `flutter test` (planner, on `develop`, before 7a) | `+3548 ~1: All tests passed!` |
| `flutter analyze` (executor, after 7a, start of Phase 1) | _pending_ |
| `flutter test` (executor, after 7a, start of Phase 1) | _pending_ |

## Per-phase results

### Phase 1 (@dba)

| Item | Command | Result |
|---|---|---|
| Red run (rule + copy) | `flutter test test/interference_test.dart` | _pending_ |
| Green run | `flutter test test/interference_test.dart` | _pending_ |
| Analyze | `flutter analyze` | _pending_ |
| Full suite | `flutter test` | _pending_ |

**Mutation (a) — D-1304's `<= endMs + 36 h` → `< endMs + 36 h`:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/interference.dart` | _pending_ |
| Red | `flutter test test/interference_test.dart` | _pending_ — S-2003(b) must fail |
| Restore | — | _pending_ |
| Green | `flutter test test/interference_test.dart` | _pending_ |

**Mutation (b) — D-1308's tolerance removed (`> kInterferenceMinDip`):**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/interference.dart` | _pending_ |
| Red | `flutter test test/interference_test.dart` | _pending_ — S-2004(a) must fail |
| Restore | — | _pending_ |
| Green | `flutter test test/interference_test.dart` | _pending_ |

**Plan line count re-measured:** _pending_.

### Phase 2 (@dba)

| Item | Command | Result |
|---|---|---|
| Red run (walk) | `flutter test test/interference_sessions_service_test.dart` | _pending_ |
| Green run | `flutter test test/interference_sessions_service_test.dart` | _pending_ |
| Mix suites unchanged | `flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart` | _pending_ |
| Analyze | `flutter analyze` | _pending_ |
| Full suite | `flutter test` | _pending_ |

**Mutation — the Sports component of the shared split replaced by the session's whole load:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/services/stats_progress_service.dart` | _pending_ |
| Red | `flutter test test/interference_sessions_service_test.dart` | _pending_ — S-2012's parity assertion must fail |
| Restore | — | _pending_ |
| Green | `flutter test test/interference_sessions_service_test.dart test/mix_layer_service_test.dart` | _pending_ |

### Phase 3 (@developer)

| Item | Command | Result |
|---|---|---|
| Red run (card absent) | `flutter test test/interference_signal_screen_test.dart` | _pending_ |
| Green run | `flutter test test/interference_signal_screen_test.dart` | _pending_ |
| Framework + surface suites | `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart` | _pending_ |
| PR path untouched | `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` | _pending_ |
| Guards added | the three test files | _pending_ |
| Residue sweep | search every name this PR introduces | _pending_ — every hit's file listed below |
| Framework + PR path no diff | `git diff --name-only` via the gateway | _pending_ |
| Analyze | `flutter analyze` | _pending_ |
| Full suite | `flutter test` | _pending_ — compare with Phase 2's summary line and explain every delta |
| Docs re-read | `docs/signals.md`, `docs/stats_screen.md` | _pending_ |

## Residue sweep — every hit, by file

_To be filled in Phase 3. One row per name introduced by this PR: name → file(s) that mention it →
verdict (expected / unexpected)._

## Doc claim → test that fails when the claim goes false

_To be filled in Phase 3. Every behaviour sentence this PR adds to `docs/signals.md`,
`docs/stats_screen.md`, `docs/training_load.md` or `docs/constants_reference.md` gets a row: the claim,
the file, and the test that fails if the claim stops being true. A claim with no test is deleted, not
documented._

## Hand-computed values used by the assertions

Kept here so a reviewer can re-derive them without re-reading the plan.

**F-2001 (pure, S-2001).** Sorted sports loads `4, 8, 12, 20, 24, 28, 30, 41, 50, 50, 55, 83`;
`n = 12`; `ceil(0.75 × 12) = 9`; `threshold = sorted[8] = 50`; hard = days 34, 28, 18, 8. Follow-up
shortfalls 16%, 0%, 11%, 12% → `k = 3`, `n = 4`, `lo = 11`, `hi = 16`. Sports load `[day 21, now]` =
138, `[day 42, day 21)` = 100 → `10 × 138 >= 13 × 100` → `p = 38`.

**F-INT (service, S-2005/S-2011/S-2012).** Sorted sports loads `4, 8, 12, 20, 24, 28, 41, 50`;
`n = 8`; `ceil(6) = 6`; `threshold = sorted[5] = 28`; hard = days 30, 20, 10 (day 20 exactly on the
threshold; day 44 at 24 just below). Follow-up shortfalls 16%, `0.09999999999999998`, 11% →
`k = 3`, `n = 3`, `lo = 10`, `hi = 16`. Sports load `[day 21, now]` = 28 + 41 = 69,
`[day 42, day 21)` = 50 → `10 × 69 = 690 >= 13 × 50 = 650` → `p = round(38) = 38`. Parity sum over
`[day 89, now]` = 4 + 8 + 12 + 20 + 24 + 28 + 41 + 50 = 187.

## Assumption Log entries raised in this PR

_One row per entry appended to the plan's Assumption Log: phase, decision, options considered, choice,
rationale. The Conductor ratifies or reverts each at verification._
