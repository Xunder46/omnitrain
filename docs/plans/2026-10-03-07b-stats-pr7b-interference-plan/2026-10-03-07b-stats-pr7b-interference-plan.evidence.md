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
| Red run (rule + copy) | `flutter test test/interference_test.dart` | `+14 -12` — S-2001, S-2003 (b/d/e), S-2004 (a/c), S-2007 (a/c), S-2009, S-2010 (b), S-2015, fewer-than-8 |
| Green run | `flutter test test/interference_test.dart` | `+26 -0: All tests passed!` |
| Analyze | `flutter analyze` | `196 issues found. (ran in 2.9s)` |
| Docs indexing contract | `flutter test test/docs_indexing_contract_test.dart` | `+9 -0: All tests passed!` |
| Full suite | `flutter test` | `+3608 ~1: All tests passed!` |

The red run's twelve failures were all test-side: the named scenarios exercise *stages* of the rule
(follow-up detection, per-follow-up dips) that a one-follow-up fixture can never carry through the
top-level function, which requires `kInterferenceMinDippedFollowUps` dipped follow-ups. The fix exposed
`analyseInterference` / `InterferenceAnalysis` and moved those eight tests onto it; the fixture
corrections are listed under "Assumption Log entries raised in this PR" below. Full suite delta vs the
plan's baseline (`+3582 ~1` → `+3608 ~1`) is exactly this file's `+26`.

**Mutation (a) — D-1304's `<= endMs + 36 h` → `< endMs + 36 h`:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/interference.dart:215`, `if (candidate.startMs > upperMs) continue;` → `>=` | applied, then restored |
| Red | `flutter test test/interference_test.dart` | `+25 -1` — S-2003(b) failed, as predicted |
| Restore | verbatim, re-read at line 215 to confirm | done |
| Green | `flutter test test/interference_test.dart` | `+26 -0: All tests passed!` |

**Mutation (b) — D-1308's tolerance removed (`> kInterferenceMinDip`):**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/interference.dart:268`, `if (mean >= kInterferenceMinDip - 1e-9) {` → `if (mean > kInterferenceMinDip) {` | applied, then restored |
| Red | `flutter test test/interference_test.dart` | `+23 -3` — S-2004(a), S-2004(c), S-2006 failed; S-2004(a) as predicted |
| Restore | verbatim, re-read at line 268 to confirm | done |
| Green | `flutter test test/interference_test.dart` | `+26 -0: All tests passed!` |

**Plan line count re-measured:** 676 lines — unchanged in kind from the Conductor's plan; this phase
added the Phase 1 status block and the two Assumption Log entries. The plan already exceeded the
"few hundred lines" budget before this phase, and the split is the Conductor's call, not this
executor's.

### Phase 2 (@dba)

| Item | Command | Result |
|---|---|---|
| Red run (walk) | `flutter test test/interference_sessions_service_test.dart` | **Red** — compile error: `The method 'interferenceSessions' isn't defined for the type 'StatsProgressService'` at 6 call sites, plus 2 `StatsWindow` arg-type errors in the test's own `_window` helper (fixed before the green run). `+0 -1: Some tests failed.` |
| Green run | `flutter test test/interference_sessions_service_test.dart` | **Green** — `+14 -0: All tests passed!` (7 tests × Mock/Hive) |
| Mix suites unchanged | `flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart` | **Green** — `+96 -0: All tests passed!` (both files unedited) |
| Analyze | `flutter analyze` | `196 issues found. (ran in 1.6s)` — matches baseline |
| Full suite | `flutter test` | `+3622 ~1: All tests passed!` — baseline `+3608 ~1` + 14 new |

**Mutation — the Sports component of the shared split replaced by the session's whole load:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/services/stats_progress_service.dart` | `sportsLoadMinutes: split.loadBySection[ExerciseSection.sports] ?? 0.0` → `split.loadBySection.values.fold<double>(0, (a, b) => a + b)`. Pre-mutation `git-diff --stat`: `164 ++++---, 138 insertions(+), 26 deletions(-)` |
| Red | `flutter test test/interference_sessions_service_test.dart` | **Red** — `+4 -10: Some tests failed.` 5 of 7 tests fail per harness: D-1316 payloads (`Expected: <0.0> Actual: <240.0>`), S-2005 (`Expected: not null Actual: <null>`), S-2011 (`Expected: within <1e-9> of <0.16> Actual: <null>`), **S-2012 parity (`Expected: within <1e-9> of <187.0> Actual: <3307.0>` — differs by 3120.0)**, S-2009 (`Expected: not null Actual: <null>`) |
| Restore | — | Reverted to the exact pre-mutation line; `git-diff --stat` back to `164 ++++---, 138 insertions(+), 26 deletions(-)` |
| Green | `flutter test test/interference_sessions_service_test.dart` | **Green** — `+14 -0: All tests passed!` |

### Phase 3 (@developer)

**Part A — steps 1–5 (this run).** Steps 6–9 (guards, residue sweep, docs, close) are the next run.

| Item | Command | Result |
|---|---|---|
| Red run (card absent) | `flutter test test/interference_signal_screen_test.dart` | **Red** — `+2 -3: Some tests failed.` Stage (a) service assertion passed on Mock and Hive (`+2`); the three widget tests failed because the card key `signal_card_cross-modality-interference` was absent (registry had no such signal). |
| Green run | `flutter test test/interference_signal_screen_test.dart` | **Green** — `+5 -0: All tests passed!` |
| Framework + surface suites | `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart` | **Green** — `+442 -0: All tests passed!` (after the registry-guard update below) |
| PR path untouched | `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` | **Green** — `+41 -0: All tests passed!`; neither file edited |
| Guards added | the three test files | _pending_ (step 6) |
| Residue sweep | search every name this PR introduces | _pending_ (step 7) — every hit's file listed below |
| Framework + PR path no diff | `git diff --name-only` via the gateway | **Confirmed** — `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` absent from the diff; no framework file edited |
| Analyze | `flutter analyze` | `196 issues found.` — matches baseline |
| Full suite | `flutter test` | `+3627 ~1: All tests passed!` — Phase 2's `+3622 ~1` + 5 new (the S-2013 screen test) |
| Docs re-read | `docs/signals.md`, `docs/stats_screen.md` | _pending_ (step 8) |

**Registry-guard update (step 3 consequence).** `test/modality_mix_shift_signal_screen_test.dart`
asserted the registry "lists exactly the two shipped signals". Step 3 mandates a third entry, so the
guard was updated to list three (`progression-rate`, `modality-mix-shift`,
`cross-modality-interference`). This is a registry-content update, not a surface-height
re-stabilisation — the plan's Predicted Files explicitly allow editing this file. It is the only
pre-existing test that step 3 reddened.

**Part B — steps 6–9 (this run).**

| Item | Command | Result |
|---|---|---|
| Guards added | `test/interference_test.dart` (the `the structural guards` group, 6 tests) | **Green** — `+32 -0: All tests passed!` (26 pre-existing + 6 new) |
| Mutation (a) — priority lowered below the Mix Shift's | `lib/core/models/interference.dart` | **Red** — `the caution order holds and the registry is ordered by it` failed; restored, green |
| Mutation (b) — an unrated session counted as hard | `lib/core/models/interference.dart` | **Red** — `the hard rule counts no unrated session` failed; restored, green |
| Residue sweep | search every name this PR introduces | **Clean** — every hit expected; framework files and `watch/` absent (table below) |
| Framework files unchanged | `git-diff --stat -- lib/core/models/signals.dart lib/core/services/signals/signal.dart lib/core/services/signals_service.dart lib/features/stats/widgets/signals_layer.dart lib/features/stats/stats_screen.dart` | **No output** (step 6(e)) |
| Registry diff | `git-diff -- lib/core/services/signals/signal_registry.dart` | one import + one list entry |
| Docs | `docs/signals.md`, `docs/stats_screen.md` | **Updated** — 21,529 B and 28,094 B, both under 64 KiB |
| Docs indexing contract | `flutter test test/docs_indexing_contract_test.dart` | **Green** — `+9 -0: All tests passed!` |
| Done Criteria suites | `flutter test test/interference_test.dart test/interference_sessions_service_test.dart test/interference_signal_screen_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart` | **Green** — `+91 -0: All tests passed!` |
| Analyze | `flutter analyze` | `196 issues found.` — matches baseline |
| Full suite | `flutter test` | `+3633 ~1: All tests passed!` — Phase 2's `+3627 ~1` + 6 new guards |

**Mutation (a) — `kCrossModalityInterferencePriority` lowered below `kModalityMixShiftPriority`.**

`lib/core/models/interference.dart` is untracked, so the original line is copied here before the
mutation.

Original line (`lib/core/models/interference.dart`, the priority constant):

```dart
const int kCrossModalityInterferencePriority = 500;
```

| Step | Command | Result |
|---|---|---|
| Apply the edit | `500` → `300` | applied, then restored |
| Red | `flutter test test/interference_test.dart` | **Red** — `+31 -1`; `the structural guards the caution order holds and the registry is ordered by it [E]` — `Expected: a value greater than <400> Actual: <300>` |
| Restore | verbatim, re-read the line to confirm | done |
| Green | `flutter test test/interference_test.dart` | **Green** — `+32 -0: All tests passed!` |

**Mutation (b) — an unrated session counted as hard (the population's rating gate removed).**

Original line (`lib/core/models/interference.dart`, the population filter):

```dart
            s.rating != null &&
```

| Step | Command | Result |
|---|---|---|
| Apply the edit | the `s.rating != null &&` clause removed from the population filter | applied, then restored |
| Red | `flutter test test/interference_test.dart` | **Red** — `+31 -1`; `the structural guards the hard rule counts no unrated session [E]` — the unrated sessions entered the population and moved the threshold |
| Restore | verbatim, re-read at line 180 to confirm | done |
| Green | `flutter test test/interference_test.dart` | **Green** — `+32 -0: All tests passed!` |

The guard's fixture gives the three unrated sessions a positive Sports load (200 each) so the
mutation is observable: with a zero load they would be filtered by the `sportsLoadMinutes > 0` clause
regardless of the rating gate, and the guard would pass under the mutation. The shipped S-2009
fixture keeps its zero loads, because the service walk reports an unrated session's Sports load as 0
(D-1302).

## Residue sweep — every hit, by file

Step 7. Every name this PR introduces, the files that mention it, and the verdict. `docs/plans/` is
excluded from the verdict column: the plan and its evidence are the PR's own working documents, not
shipped surface.

| Name | Files | Verdict |
|---|---|---|
| `InterferenceSignal` | `lib/core/services/signals/interference_signal.dart`, `lib/core/services/signals/signal_registry.dart` | expected — the class and its one registry line |
| `cross-modality-interference` | `lib/core/services/signals/interference_signal.dart`, `test/interference_signal_screen_test.dart`, `test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` | expected — the id, its card key and the registry guard |
| `interferenceSessions` | `lib/core/services/stats_progress_service.dart`, `lib/core/services/signals/interference_signal.dart`, `test/interference_sessions_service_test.dart`, `test/interference_signal_screen_test.dart`, `test/interference_test.dart`, `docs/state_management/services_and_utils.md`, `docs/training_load.md` | expected — the walk, its one caller and its docs |
| `InterferenceSession` | `lib/core/models/interference.dart`, `lib/core/services/stats_progress_service.dart`, `test/interference_sessions_service_test.dart`, `test/interference_test.dart`, `docs/state_management/services_and_utils.md` | expected — the payload type and its producers/consumers |
| `crossModalityInterference` | `lib/core/models/interference.dart`, `lib/core/services/signals/interference_signal.dart`, `test/interference_sessions_service_test.dart`, `test/interference_signal_screen_test.dart`, `test/interference_test.dart` | expected — the rule and its callers |
| `kInterference*` (all ten) | `lib/core/models/interference.dart`, `test/interference_test.dart`, `docs/constants_reference.md` | expected — the constants, their contract test and their doc table |
| `kCrossModalityInterferencePriority` | `lib/core/models/interference.dart`, `lib/core/services/signals/interference_signal.dart`, `test/interference_test.dart`, `docs/constants_reference.md` | expected — the priority, its reader, its contract test and its doc row |
| the observation's opening words (`After … of your last … hard sports sessions`) | `lib/core/models/interference.dart`, `test/interference_signal_screen_test.dart`, `test/interference_test.dart` | expected — the copy builder and the two tests that pin it verbatim |

**Framework files absent from the sweep.** `lib/core/models/signals.dart`,
`lib/core/services/signals/signal.dart`, `lib/core/services/signals_service.dart`,
`lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/stats_screen.dart` and
`lib/features/stats/widgets/signals/*` name none of the introduced identifiers. `watch/` names none
either.

**Untouched files show no diff.** `git-diff --stat -- lib/core/models/signals.dart
lib/core/services/signals/signal.dart lib/core/services/signals_service.dart
lib/features/stats/widgets/signals_layer.dart lib/features/stats/stats_screen.dart` printed nothing
(step 6(e)). `git-diff --stat -- test/pr_toast_test.dart test/in_session_pr_toast_test.dart
test/helpers/repository_harness.dart` printed nothing. `git-diff --
lib/core/services/signals/signal_registry.dart` shows exactly one import and one list entry.

## Doc claim → test that fails when the claim goes false

_To be filled in Phase 3. Every behaviour sentence this PR adds to `docs/signals.md`,
`docs/stats_screen.md`, `docs/training_load.md` or `docs/constants_reference.md` gets a row: the claim,
the file, and the test that fails if the claim stops being true. A claim with no test is deleted, not
documented._

**Phase 1's rows (the `## Interference Constants` section in `docs/constants_reference.md`):**

| Claim | File | Test that fails when it goes false |
|---|---|---|
| Each `kInterference*` constant and `kCrossModalityInterferencePriority` governs the rule its row names | `docs/constants_reference.md` | `test/interference_test.dart` — mutation (a) reddens S-2003(b) on the 36-hour bound, mutation (b) reddens S-2004(a)/(c) and S-2006 on the dip tolerance; the remaining constants are pinned by S-2007 (rise), S-2010 (45-day pattern and the 3-follow-up floor) and S-2015 (the 90-day population floor) |

**Phase 3 part B's rows (the Interference paragraph in `docs/signals.md` and the third-signal
paragraph in `docs/stats_screen.md`):**

| Claim | File | Test that fails when it goes false |
|---|---|---|
| A sports session is the shared split's Sports component, never the whole load or the raw duration | `docs/signals.md` | `test/interference_sessions_service_test.dart` (`S-2012` parity) |
| The hard window is `kInterferenceHardWindowDays` local days, both ends inclusive | `docs/signals.md` | `test/interference_test.dart` (`S-2015`) |
| The population is the rated sports sessions; below `kInterferenceMinRatedSportsSessions` the signal abstains | `docs/signals.md` | `test/interference_test.dart` (`S-2009`, `fewer than 8 rated sports sessions abstains`); `test/interference_sessions_service_test.dart` (`S-2005(b)`) |
| The threshold is nearest-rank at `kInterferenceHardPercentile`, inclusive | `docs/signals.md` | `test/interference_test.dart` (`S-2008`) |
| The follow-up starts strictly after the end and at most `kInterferenceFollowUpHours` later, earliest first, ties by id | `docs/signals.md` | `test/interference_test.dart` (`S-2003`) |
| A comparable exercise needs a best above zero and a prior in `[start − kInterferenceDipWindowDays, start)`; the average excludes every follow-up | `docs/signals.md` | `test/interference_test.dart` (`S-2006`); `test/interference_sessions_service_test.dart` (`S-2011`) |
| The dip is the unweighted mean shortfall at `kInterferenceMinDip` within the `1e-9` tolerance | `docs/signals.md` | `test/interference_test.dart` (`S-2004`) |
| The pattern counts dipped follow-ups in `[now − kInterferencePatternWindowDays, now]` and needs `kInterferenceMinDippedFollowUps` | `docs/signals.md` | `test/interference_test.dart` (`S-2002`, `S-2010`) |
| The range's ends are the counted follow-ups' mean shortfalls as whole percents | `docs/signals.md` | `test/interference_test.dart` (`S-2010(b)`) |
| The kind is caution and the priority is `kCrossModalityInterferencePriority`, the top of the caution order | `docs/signals.md`, `docs/stats_screen.md` | `test/interference_test.dart` (`the caution order holds and the registry is ordered by it`); `test/interference_signal_screen_test.dart` (`S-2013`) |
| The copy collapses the range when its ends are equal and appends the second sentence only at `kInterferenceSportsLoadRisePercent` over `kInterferenceSportsLoadWindowDays` | `docs/signals.md` | `test/interference_test.dart` (`S-2001`, `S-2007`) |
| The suggestion is `'A lighter or isometric-focused day after hard sports sessions is one option.'` | `docs/signals.md` | `test/interference_test.dart` (`S-2001`); `test/interference_signal_screen_test.dart` (`S-2013`) |
| The adapter walks no history and calls no PR API | `docs/signals.md` | `test/interference_test.dart` (`the adapter walks no history and calls no PR API`) |
| The registry lists three signals and the card renders on the layer | `docs/stats_screen.md` | `test/interference_signal_screen_test.dart` (`S-2013`); `test/modality_mix_shift_signal_screen_test.dart` (the registry guard) |

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

#### Phase 1 resume 2 — the stages exposed, the fixtures corrected (@developer)

The model file is untracked, so the two original lines are copied here before each mutation.

Original line, mutation (a) site (`lib/core/models/interference.dart:215`):

```dart
      if (candidate.startMs > upperMs) continue;
```

Original line, mutation (b) site (`lib/core/models/interference.dart:268`):

```dart
    if (mean >= kInterferenceMinDip - 1e-9) {
```

| Fix | Command | Result |
|---|---|---|
| Red run before any fix | `flutter test test/interference_test.dart` | `+14 -12` (S-2001, S-2003 b/d/e, S-2004 a/c, S-2007 a/c, S-2009, S-2010 b, S-2015, fewer-than-8) |
| Green run after the fixes | `flutter test test/interference_test.dart` | `+26 -0: All tests passed!` |

#### Phase 3 part B — the guards, the sweep, the docs, the close (@developer)

| Fix | Command | Result |
|---|---|---|
| Guards added | `flutter test test/interference_test.dart` | `+32 -0: All tests passed!` (26 pre-existing + 6 new) |
| Mutation (a) red | `flutter test test/interference_test.dart` | `+31 -1` — `the structural guards the caution order holds and the registry is ordered by it [E]` |
| Mutation (a) green | `flutter test test/interference_test.dart` | `+32 -0: All tests passed!` |
| Mutation (b) red | `flutter test test/interference_test.dart` | `+31 -1` — `the structural guards the hard rule counts no unrated session [E]` |
| Mutation (b) green | `flutter test test/interference_test.dart` | `+32 -0: All tests passed!` |
| Done Criteria suites | `flutter test test/interference_test.dart test/interference_sessions_service_test.dart test/interference_signal_screen_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart` | `+91 -0: All tests passed!` |
| Analyze | `flutter analyze` | `196 issues found.` |
| Full suite | `flutter test` | `+3633 ~1: All tests passed!` |

## Final table — Done Criteria

| Done Criterion | Command | Observed result |
|---|---|---|
| Analyze clean against the baseline | `flutter analyze` | `196 issues found.` — matches the baseline exactly |
| The pure rule, the walk, the card and the framework | `flutter test test/interference_test.dart test/interference_sessions_service_test.dart test/interference_signal_screen_test.dart test/signals_framework_test.dart` | `+82 -0` (within the `+91 -0` Done Criteria run) |
| Docs under the 64 KiB ceiling | `flutter test test/docs_indexing_contract_test.dart` | `+9 -0: All tests passed!` |
| Full suite green | `flutter test` | `+3633 ~1: All tests passed!` — Phase 2's `+3627 ~1` + 6 new guards; no other delta |
| Guards fail under an inverse edit | two mutation pairs | both red→green, restored verbatim |
| Framework files unchanged | `git-diff --stat -- <five framework files>` | no output |
| Residue sweep clean | name search over `lib/`, `test/`, `docs/` | every hit expected; `watch/` absent |

## Fix round 1 — review findings 1–4 and the carried item

| Item | File | Change | Evidence |
|---|---|---|---|
| 1 | `docs/signals.md`, `docs/stats_screen.md` | Deleted every numeric restatement of an `kInterference*` value: "three times" → `kInterferenceMinDippedFollowUps`; "the top quartile" → the share the percentile names; the `1e-9` / `0.9` / `0.09999999999999998` / "one tenth" / "nine per cent" sentence → "the comparison tolerates floating-point representation error". Test pointers kept; shipped copy untouched | grep for `three times`, `top quartile`, `1e-9`, `one tenth`, `nine per cent`, `36`, `28`, `45`, `90`, `21`, `10%`, `30%` over both docs: no `kInterference*` value remains |
| 2 | `docs/signals.md`, `lib/core/models/interference.dart`, plan D-1302/D-1321 | Hard window prose and the constant's comment now say exact durations back from `now`; D-1321 added and D-1302 marked SUPERSEDED; no arithmetic changed | `test/interference_test.dart` S-2015 green; analyzer `196 issues found.` |
| 3 | `test/interference_test.dart` | Added S-2008's 9-session variant (`ceil(0.75 × 9) = 7` → `sorted[6] = 7`; loads 7/8/9 hard) and strengthened the 12-session assertion to the hard ids | `test/interference_test.dart` `+33` green; rank mutation reddens the new test only (`+32 -1`); restored |
| 4 | `lib/core/models/interference.dart`, `docs/signals.md`, plan O-5 | `k` and `n` now count each follow-up session once, however many hard sessions it follows | `test/interference_test.dart` `+34` green; distinct-id mutation reddens the new test only (`+33 -1`); restored |
| 5 | `lib/core/models/interference.dart` | The rise comparison is rewritten from `kInterferenceSportsLoadRisePercent` as `100 * recent < (100 + kInterferenceSportsLoadRisePercent) * prior` | S-2007 boundary tests green; `<` → `<=` reddens S-2007(a) |

### Fix round 1 — mutation pairs (originals copied before each edit; restored verbatim)

Original line, item 3 mutation site (`lib/core/models/interference.dart`, rank formula):

```dart
  final rank = (kInterferenceHardPercentile * sortedLoads.length).ceil();
```

Original line, item 5 mutation site (`lib/core/models/interference.dart`, rise comparison):

```dart
  if (100 * recent < (100 + kInterferenceSportsLoadRisePercent) * prior) {
    return null;
  }
```

Original line, item 4 mutation site (`lib/core/models/interference.dart`, distinct follow-up ids):

```dart
  final countedFollowUpIds = followUps.map((s) => s.id).toSet();
```

### Fix round 1 — mutation pairs, observed

Each pair is: mutate → run `test/interference_test.dart` → restore → re-run.

| Item | Mutation | Red | Green after restore |
|---|---|---|---|
| 3 | `.ceil()` → `.floor()` in the rank formula | `+32 -1` (the new 9-session test only) | `+33` |
| 4 | `.toSet()` → `.toList()` for `countedFollowUpIds` | `+33 -1` (the shared-follow-up test only) | `+34` |
| 5 | `<` → `<=` in the rise comparison | `+33 -1` (S-2007(a) only) | `+34` |

### Fix round 1 — validation runs

| Command | Observed |
|---|---|
| `gateway.sh test test/interference_test.dart test/interference_sessions_service_test.dart test/interference_signal_screen_test.dart test/docs_indexing_contract_test.dart` | `+62: All tests passed!` |
| `gateway.sh lint` | `196 issues found. (ran in 2.9s)` |
| `gateway.sh test` (full) | `+3635 ~1: All tests passed!` (pre-fix baseline `+3633 ~1`; +2 new tests) |


