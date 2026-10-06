# Evidence — Stats PR 6b, Progression Rate

Executors append here. **Nothing in this file goes into the plan file.**

## Baselines (quote your own run)

| Command | Expected | Executor's value (fill in) |
|---|---|---|
| `flutter analyze` | the 6a Phase 3 value, 0 errors | `196 issues found. (ran in 2.9s)` — 0 errors, matches the brief's baseline |
| `flutter test` | the 6a Phase 3 summary line | `01:31 +3537 ~1: All tests passed!` (post-Phase-1; the pre-change baseline quoted in the brief is `+3509 ~1`) |

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| 1 | `flutter analyze` | `196 issues found.` — 0 errors, no new issue | |
| 1 | `flutter test test/progression_rate_test.dart test/progression_samples_service_test.dart` | `+28: All tests passed!` (14 + 14) | |
| 1 | `flutter test test/mix_layer_service_test.dart test/records_and_trends_screen_test.dart` | `+141: All tests passed!` when run together with the two new suites and `test/stats_progress_test.dart` | the service file changed |
| 1 | `flutter test` | `01:31 +3537 ~1: All tests passed!` | +28 vs the brief's `+3509 ~1` baseline = exactly the two new suites |
| 1 | `flutter test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` | after the forced split of `services_and_utils.md` |
| 2 | `flutter analyze` | `196 issues found.` — 0 errors, at the baseline | a first pass read `197`; the one new `unused_import` (`dart:convert` in the new test file) was removed |
| 2 | `flutter test test/progression_rate_signal_screen_test.dart` | `+5: All tests passed!` — S-1801 and S-1812 on both harnesses, S-1813 Mock only | the Mock-only red run before the registry line was `-3` |
| 2 | `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/mix_layer_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart` | `+425: All tests passed!` | `test/mix_layer_screen_test.dart` needed no re-stabilisation |
| 2 | `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` (run with `test/stats_progress_test.dart`) | `+98: All tests passed!` | all three passed unmodified |
| 2 | `flutter test test/palette_legibility_contract_test.dart` (run with `test/docs_indexing_contract_test.dart`) | `+10: All tests passed!` | after the `docs/stats_screen.md` edit |
| 2 | `flutter test` | `01:25 +3542 ~1: All tests passed!` | +5 vs Phase 1's `+3537 ~1` = exactly the five new tests |
| 3 | `flutter analyze` | `196 issues found.` — 0 errors, 1 warning (`routine_setup_screen.dart:1046`, pre-existing), 195 info; identical count to the Phase 1/2 baseline | |
| 3 | `flutter test test/progression_rate_test.dart` | `+18: All tests passed!` | 14 (Phase 1) → 17 after the three guards → 18 after the contract guard |
| 3 | `flutter test` | `01:30 +3546 ~1: All tests passed!` | +4 vs Phase 2's `+3542 ~1` = exactly the four new tests |
| 3 | `flutter test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` | `docs/signals.md` is 11 363 bytes, well under the 64 KiB ceiling |

### Phase 3 residue sweep

Every name this PR introduced, searched across `lib/`, `test/` and `docs/`:

`ProgressionRateSignal`, `progression-rate`, `progressionSamples`, `ProgressionSample`,
`ProgressionRate`, `progressionRate`, `kProgressionRateWindowDays`,
`kProgressionRateMinCounted`, `kProgressionRateMinRate`, `kProgressionRateMinImprovement`,
`kProgressionRatePriority`, `Resistance progression rate`.

| Hit file | Expected |
|---|---|
| `lib/core/models/progression_rate.dart` | yes — the definition |
| `lib/core/services/signals/progression_rate_signal.dart` | yes — the signal |
| `lib/core/services/signals/signal_registry.dart` | yes — the registration line |
| `lib/core/services/stats_progress_service.dart` | yes — the sample walk |
| `test/progression_rate_test.dart` | yes — the pure suite |
| `test/progression_samples_service_test.dart` | yes — the walk's suite |
| `test/progression_rate_signal_screen_test.dart` | yes — the card's suite |
| `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/data_models.md` | yes — this PR's docs |
| `docs/state_management/services_and_utils.md` | yes — the added service method |
| `docs/plans/…06b…plan.md`, `…06b…plan.evidence.md` | yes — this plan |
| `docs/plans/2026-10-03-06-stats-pr6-index.md` | yes — the pack index |
| `docs/plans/2026-10-03-06a-…/…evidence.md` | yes — 6a's evidence names this PR's signal |
| `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` | yes — the pack's own text |

**Framework files absent from the list**, as required: `lib/core/models/signals.dart`,
`lib/core/services/signals/signal.dart`, `lib/core/services/signals_service.dart`,
`lib/features/stats/widgets/signals_layer.dart`, `test/signals_framework_test.dart`,
`test/signals_service_test.dart`, `test/signals_layer_screen_test.dart`,
`lib/features/stats/stats_screen.dart` (its only hits are 6a's).

The docs' copy matches the shipped copy character for character:
`Resistance progression rate is ${rate.recentPercent}% over the last 4 weeks, up from
${rate.priorPercent}%.` with `The current approach is working.` — read from
`progressionRateCopy` (`lib/core/models/progression_rate.dart`) and quoted in
`docs/stats_screen.md`.

## F-PR hand-computation, checked against the shipped walk

| Exercise | Prior progressions | Recent progressions |
|---|---|---|
| ex-a | 4/4 | 4/4 |
| ex-b | 3/4 | 3/4 |
| ex-c | 3/4 | 3/4 |
| ex-d | 2/4 | 3/4 |
| ex-e | 1/4 | 3/4 |
| **Total** | **13/20 = 65%** | **16/20 = 80%** |

Observed from the shipped code (fill in):

| Reading | Expected | Observed |
|---|---|---|
| prior counted | 20 | 20 |
| recent counted | 20 | 20 |
| prior percent | 65 | 65 |
| recent percent | 80 | 80 |
| card shown | yes | yes — `progressionRate(...)` returns non-null |
| observation | `Resistance progression rate is 80% over the last 4 weeks, up from 65%.` | identical |
| suggestion | `The current approach is working.` | identical |

The walk returns 45 samples for this fixture (9 sessions × 5 exercises, minus each
exercise's first sample, which has no predecessor). Asserted by
`test/progression_samples_service_test.dart` → "F-PR matches the plan's per-exercise
hand-computation", run against both harnesses.

## Red runs and inverse-edit mutations

| Phase | Mutation or red run | Expected failure | Observed | Restored |
|---|---|---|---|---|
| 1 | the improvement test changed from `>=` to `>` | S-1805 fails | S-1805 fixtures 1 and 2 failed: `Expected: not null / Actual: <null>` | yes — re-ran green |
| 1 | the first-ever sample included in the walk | S-1808 fails | S-1808 failed in **both** harnesses: `Expected: <21> / Actual: <22>` | yes — re-ran green |
| 1 | pure-math tests written before the math (red run) | the new suite fails | compile errors: `Method not found: 'progressionRate'`, `'ProgressionSample' isn't a type`, `Undefined name 'ProgressionRate'`, `Method not found: 'progressionRateCopy'` | yes — 14/14 green after the model landed |
| 2 | the exact strings asserted before the registry line (red run) | S-1801 fails | the three Mock tests failed with `Expected: ['signal_card_progression-rate'] / Actual: []` — the layer rendered the quiet line, not the card | yes — `+3: All tests passed!` once the registry line landed |
| 2 | the zero-value sample counted as a zero (the walk's guard relaxed from `<= 0` to `< 0`) | S-1810 fails | `D-1104 a session with no readable value is not counted` failed: `Expected: <9> / Actual: <10>` | yes — `+19: All tests passed!` across the math and the screen suites |
| 3 | the qualification test compares the **rounded percentages** instead of the exact fractions | the exact-fraction guard fails | `D-1108 the qualification test compares exact fractions, not the rounded percentages` failed: `Expected: null / Actual: <Instance of 'ProgressionRate'>` | yes — `+17: All tests passed!` |
| 3 | a local estimated-1RM slope added to the signal (`const double _kLocalEpleySlope = 0.0333;`) | the shared-helper guard fails | `the new files compute no estimated 1RM of their own` failed: `Expected: false / Actual: <true>`, reason naming `0.0333` | yes — `+17: All tests passed!` |
| 3 | the signal's priority dropped to `kProgressionRatePriority - 1` | the contract guard fails | `the registered signal declares the contract the docs describe` failed: `Expected: <100> / Actual: <99>` | yes — `+18: All tests passed!` |
| 3 | the signal calling a personal-record API (`getAllTimeBestE1RM`) | the no-PR-API guard fails | `the new files call no personal-record API` failed: `Expected: false / Actual: <true>` | yes — `+18: All tests passed!` |

Mutation (b) was applied in the **math** (`progressionRate`), not in the walk: D-1112
and Phase 1 step 4 require the walk to return every sample including zero-value ones,
so the drop has to live in the math. The mutation still produced the required S-1808
failure.

The original lines, recorded before each mutation was applied and read back after the
restore (every mutation file is untracked, so `git diff` cannot show them):

| File | Original line (read back after the restore) |
|---|---|
| `lib/core/models/progression_rate.dart:164` | `if (rate.recentProgressions * _minRateDenominator < _minRateNumerator * rate.recentCounted) {` |
| `lib/core/services/signals/progression_rate_signal.dart:29` | `int get priority => kProgressionRatePriority;` |
| `lib/core/services/signals/progression_rate_signal.dart:33` | `final samples = await context.progressService.progressionSamples();` |

The Phase 1 mutations were made in the same two files before they had a tracked
counterpart either; each was restored and re-run green in the action that followed it,
and the Phase 1 `+28: All tests passed!` line is that re-run.

## Re-stabilisation

None needed. `test/mix_layer_screen_test.dart` passes no `signals:` seam, so the app's
real registry did evaluate there — but each of its fixtures holds a single session per
exercise, so the signal abstained and the layer kept rendering the quiet line. The file
is unmodified and its suite ran `+425: All tests passed!` in step 4.

| File | Test | Change | Reason |
|---|---|---|---|
| — | — | none | no fixture moved a lower block |

## Phase 2 framework files (rule 4)

No framework file changed in this phase. `git diff` cannot show this: 6a is uncommitted,
so `signals.dart`, `signals_service.dart`, `signals_layer.dart` and the whole
`lib/core/services/signals/` directory are untracked and `stats_screen.dart`'s diff is
6a's. The modification times are the record — every 6a file is at or before 16:11, and
every Phase 2 edit landed at 16:48–16:51.

| File | mtime | Phase 2 edit |
|---|---|---|
| `lib/core/models/signals.dart` | 16:10:09 | none |
| `lib/core/services/signals/signal.dart` | 14:03:28 | none |
| `lib/core/services/signals_service.dart` | 14:51:58 | none |
| `lib/features/stats/widgets/signals_layer.dart` | 16:11:13 | none |
| `lib/features/stats/stats_screen.dart` | 16:10:51 | none |
| `test/mix_layer_screen_test.dart` | 13:48:56 | none |
| `lib/core/services/signals/signal_registry.dart` | 16:49:08 | the one registration line |
| `lib/core/services/signals/progression_rate_signal.dart` | 16:48:24 | new |
| `test/progression_rate_signal_screen_test.dart` | 16:51:25 | new |
| `docs/stats_screen.md` | 16:50:54 | the Signals-section paragraph |

## Doc checklist

| Name | Files mentioning it | Doc | Test named in the doc |
|---|---|---|---|
| `ProgressionRateSignal` | `lib/core/services/signals/progression_rate_signal.dart`, `lib/core/services/signals/signal_registry.dart`, `test/progression_rate_signal_screen_test.dart` | `docs/signals.md`, `docs/stats_screen.md` | `test/progression_rate_signal_screen_test.dart` |
| `progression-rate` | `lib/core/services/signals/progression_rate_signal.dart`, `test/progression_rate_signal_screen_test.dart` | `docs/signals.md`, `docs/stats_screen.md` | `test/progression_rate_signal_screen_test.dart` |
| `progressionSamples` | `lib/core/services/stats_progress_service.dart`, `test/progression_samples_service_test.dart` | `docs/state_management/services_and_utils.md` | `test/progression_samples_service_test.dart` |
| `ProgressionSample` / `ProgressionRate` | `lib/core/models/progression_rate.dart`, `lib/core/services/stats_progress_service.dart`, `test/progression_rate_test.dart`, `test/progression_samples_service_test.dart` | `docs/data_models.md` | `test/progression_rate_test.dart` |
| `kProgressionRate*` | `lib/core/models/progression_rate.dart` | `docs/constants_reference.md` | `test/progression_rate_test.dart` |
| the observation and the suggestion copy | `lib/core/models/progression_rate.dart`, `test/progression_rate_test.dart` | `docs/signals.md`, `docs/stats_screen.md` | `test/progression_rate_test.dart` (Phase 1); `test/progression_rate_signal_screen_test.dart` (Phase 2) |

Phase 2 (step 7) added the registered signal to `docs/stats_screen.md`'s Signals section: it
names the Progression Rate as the first signal in `buildSignalRegistry()`, links
`docs/signals.md#registered-signals` for the rules rather than restating them, names
`progressionRateCopy` as the only builder so the copy and the qualification test cannot
disagree, restates no threshold value, and points at
`test/progression_rate_signal_screen_test.dart` and `test/progression_rate_test.dart`. The
observation is written as the shipped template and equals the source's two concatenated
literals character for character; so does the suggestion. `docs/stats_screen.md` is 26591
bytes, well under the ceiling, and `test/docs_indexing_contract_test.dart` passes.

Phase 3 re-read `docs/signals.md`'s registered-signal section against the shipped code.
Every claim matched the source (`kProgressionRateWindowDays`, `kProgressionRateMinCounted`,
`kProgressionRateMinRate`, `kProgressionRateMinImprovement` and `kProgressionRatePriority`
all exist as described). One non-conformance was corrected: the section carried a single
section-level verification pointer, so four of its six behaviour claims named no test. Each
claim now ends with its own pointer — `test/progression_samples_service_test.dart`
(`D-1101`), `test/progression_rate_test.dart` (`D-1106`, `S-1806`/`D-1105`/`S-1808`,
`D-1104`/`S-1810`, `S-1802`–`S-1805`/`D-1108`, `D-1109`) and
`test/progression_rate_signal_screen_test.dart` (`S-1801`). The kind-and-priority claim had
no test at all, so Phase 3 added one; the file is 11 363 bytes and
`test/docs_indexing_contract_test.dart` is green.

Residue sweep (`grep -rl` over `*.dart`, `*.md`, `*.sql` for `ProgressionSample`,
`ProgressionRate`, `progressionRate`, `progressionSamples`, `progressionRateCopy`,
`kProgressionRate`, and the observation's opening words) found hits only in: the two
new test files, `lib/core/models/progression_rate.dart`,
`lib/core/services/stats_progress_service.dart`, the four updated docs
(`docs/data_models.md`, `docs/constants_reference.md`, `docs/signals.md`,
`docs/state_management/services_and_utils.md`), and plan/evidence files. No stale
reference anywhere else.

## Doc-ceiling split (unplanned, forced)

`docs/state_management/services_and_utils.md` was 52382 bytes at HEAD — 46 bytes under
the warning band (`round(65536 × 0.80) = 52429`) enforced by
`test/docs_indexing_contract_test.dart`. Documenting `progressionSamples()` there
tripped the band. The test's own message prescribes splitting into part pages while
keeping the original path. The file's tail (the watch mirroring + watch sensors
sections, which share one Vocabulary block) was moved verbatim to a new part page
`docs/state_management/watch_surface.md` (32008 bytes, 48% of the ceiling); the
original path keeps an index pointer. `docs/state_management.md` (Pages table + 19
Class→Page rows), `docs/watch_session_capture.md` (3 links), `docs/README.md`,
`docs/state_management/nutrition_state.md` and `docs/docs-audit-2026-07-26.md` were
retargeted. `test/docs_indexing_contract_test.dart` → `+9: All tests passed!`.

## Files with no diff (asserted at Phase 3)

| File | Verified |
|---|---|
| `lib/core/models/signals.dart` | no diff — `git-diff --stat` empty (untracked, 6a); mtime 16:10:09, unchanged since 6a, and absent from the residue sweep |
| `lib/core/services/signals/signal.dart` | no diff — untracked (6a); mtime 14:03:28, unchanged since 6a, and absent from the residue sweep |
| `lib/core/services/signals_service.dart` | no diff — untracked (6a); mtime 14:51:58, unchanged since 6a, and absent from the residue sweep |
| `lib/features/stats/widgets/signals_layer.dart` | no diff — untracked (6a); mtime 16:11:13, unchanged since 6a, and absent from the residue sweep |
| `docs/session_summary.md` | `git-diff --stat -- docs/session_summary.md` empty |
| `test/in_session_pr_toast_test.dart` | `git-diff --stat -- test/in_session_pr_toast_test.dart` empty |
| `test/pr_toast_test.dart` | `git-diff --stat -- test/pr_toast_test.dart` empty |

`lib/core/services/signals/signal_registry.dart` is the one framework file this PR touches
(one registration line, Phase 2). `lib/core/models/progression_rate.dart` and
`lib/core/services/signals/progression_rate_signal.dart` carry Phase 3 mtimes because the
mutation-restore cycle rewrote them; their content is the Phase 2 content, which the green
guards and the green full suite assert — the exact-fraction guard pins the math, the
shared-helper and no-PR-API guards pin both files' source, and the contract guard pins the
signal's declared id, kind and priority.

## Final full-suite line per phase

| Phase | Summary line | Delta vs baseline | Explained |
|---|---|---|---|
| 1 | `01:31 +3537 ~1: All tests passed!` | +28 | exactly the two new suites (14 + 14); no other suite changed count |
| 2 | `01:25 +3542 ~1: All tests passed!` | +5 | exactly the five new tests (S-1801 and S-1812 on both harnesses, S-1813 Mock only); no other suite changed count |
| 3 | `01:30 +3546 ~1: All tests passed!` | +4 | exactly the four new guards in `test/progression_rate_test.dart`; no other suite changed count |
