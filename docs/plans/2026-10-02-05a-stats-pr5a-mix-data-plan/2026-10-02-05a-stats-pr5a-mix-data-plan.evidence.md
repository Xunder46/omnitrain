# Evidence — Stats PR 5a (the training-load definitions and the Mix layer's data)

> Companion to `2026-10-02-05a-stats-pr5a-mix-data-plan.md`. **Evidence only.** No decisions, no
> findings, no plan text. Executors append here; the reviewer reads here. Findings go in
> `2026-10-02-05a-stats-pr5a-mix-data-plan.review.md`.

## 1. Baselines (Step 0b)

Recorded by the planner against `develop`; the executor re-runs them and quotes the real lines.

| Command | Recorded baseline (planner) | Executor's run | Verbatim final line |
|---|---|---|---|
| `gateway.sh lint` | 0 errors, 196 issues | 0 errors, 196 issues | `196 issues found. (ran in 3.1s)` |
| `gateway.sh test` | `+3227 ~1: All tests passed!` | `+3277 ~1: All tests passed!` | `01:21 +3277 ~1: All tests passed!` |

The executor's test count differs from the planner's recorded `+3227`: the executor observed
`+3277 ~1: All tests passed!` on `develop` HEAD `8be0918`. The executor's number is quoted; the
planner's is stale. The lint count matches exactly.

## 2. Red runs (Step 0c) — required, per phase

A test that has never failed proves nothing. Paste the failing output, not a summary.

| Phase | Test file | Command | Observed failure (paste) | Then green (paste) |
|---|---|---|---|---|
| 1 | `test/training_load_test.dart` | `gateway.sh test test/training_load_test.dart` | `test/training_load_test.dart:14:8: Error: Error when reading 'lib/core/models/training_load.dart': No such file or directory` … `test/training_load_test.dart:20:1: Error: Type 'MixSegment' not found.` … `test/training_load_test.dart:429:35: Error: Member not found: 'OmniDateUtils.startOfWeek'.` … `00:00 +0 -1: Some tests failed.` | `00:00 +49: All tests passed!` |
| 2 | `test/mix_layer_service_test.dart` | `gateway.sh test test/mix_layer_service_test.dart` | PENDING | |

The Phase 1 red is a compile failure, which the brief accepts for a missing API. Three behavioural
reds follow in §3, one per rule the phase adds.

## 3. Inverse-edit mutations — required, on tracked files

Each mutation is applied, the named test is shown to fail, and the mutation is reverted. Record
the diff line and the failure line.

| # | Tracked file | Mutation | Test that must fail | Observed | Reverted |
|---|---|---|---|---|---|
| M1 | `lib/core/models/training_load.dart` (the phase's home of the rule; the plan's file, `stats_progress_service.dart`, does not compute the mix until Phase 2) | Resistance's remainder forced to 0 (treat Resistance as measured): `ExerciseSection.resistance: remainder > 0 ? remainder : 0.0` → `ExerciseSection.resistance: 0.0` | S-1503 / S-1505 in `test/training_load_test.dart` | `00:00 +5 -1: … S-1503 20 minutes of holds leaves Resistance the 40-minute remainder [E]`, `+5 -2: … S-1504 … [E]`, `+5 -3: … S-1505 … [E]`, `+10 -4: … S-1515 … [E]`, `+10 -5: … S-1516 … [E]`, `00:00 +44 -5: Some tests failed.` | yes — `grep -n MUTATION` empty; `gateway.sh test test/training_load_test.dart` → `00:00 +49: All tests passed!` |
| M2 | `lib/core/utils/date_utils.dart` | week-start helper ignores its `startOfWeek` argument: the `'sunday'` ternary replaced by `final daysSinceStart = day.weekday - 1;` | the strip's Sunday-start assertion (`S-1513`'s twin) — in Phase 1 the twin is `OmniDateUtils.startOfWeek`'s `sunday start: every weekday resolves to the same Sunday` in `test/training_load_test.dart` | `00:00 +36 -1: OmniDateUtils.startOfWeek (D-910, D-935) sunday start: every weekday resolves to the same Sunday [E]` / `Expected: DateTime:<2026-01-04 00:00:00.000>` / `Actual: DateTime:<2026-01-05 00:00:00.000>` / `00:00 +48 -1: Some tests failed.` | yes — `gateway.sh git-diff --stat -- lib/core/utils/date_utils.dart` back to `1 file changed, 16 insertions(+)`; suite → `00:00 +49: All tests passed!` |
| M3 | `lib/core/models/training_load.dart` | `baselineBlockStarts` steps by `Duration(days: 7)` instead of calendar arithmetic: the `DateTime(y, m, d − n)` term replaced by `day.subtract(Duration(days: (kTrainingLoadBaselineWeeks - i) * 7))` | the DST assertion in `S-1511`'s pure half — `baselineBlockStarts`'s `the blocks are unshifted across a DST transition` in `test/training_load_test.dart` | `+39 -1: … exactly 12 blocks of 7 calendar days tile the period [E]` (`Expected: DateTime:<2026-02-11 00:00:00.000>` / `Actual: DateTime:<2026-02-10 23:00:00.000>`), `+39 -2: … no gap … [E]`, `+40 -3: … anchored at fromDay … [E]`, `+40 -4: … the blocks are unshifted across a DST transition [E]` (`Expected: <0>` / `Actual: <23>`), `00:00 +45 -4: Some tests failed.` | yes — `grep -n MUTATION` empty; suite → `00:00 +49: All tests passed!` |

`lib/core/models/training_load.dart` and `test/training_load_test.dart` are new untracked files, so
`git-diff --stat` reports nothing for them; the mutation spot was read back with a `grep -n MUTATION`
instead. No `git stash`, `checkout` or `restore` was used.

## 4. Per-scenario results

One row per scenario in the plan. "Where" is the test that asserts it.

| Scenario | Where | Harness | Result |
|---|---|---|---|
| S-1501 (60 min × 4 = 240) | `test/training_load_test.dart` (`sessionLoadMinutes`, `mixSegments`); `test/mix_layer_service_test.dart` in Phase 2 | — (pure) | PASS (function level) |
| S-1502 (unrated: no load, +1 unrated) | `test/training_load_test.dart` (`sessionLoadMinutes`, `sessionLoadByModality`); the count is Phase 2 | — (pure) | PASS (load half); count deferred |
| S-1503 (20 min holds, rated 3 → 120 R / 60 I) | `test/training_load_test.dart` (`sessionTimeByModality`, `sessionLoadByModality`, `mixSegments`) | — (pure) | PASS |
| S-1504 (same geometry in minutes) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1505 (75 min, 15 min warm-up) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1506 (measured > duration → dominant) | `test/training_load_test.dart` (A and B) | — (pure) | PASS |
| S-1507 (tie → declaration order) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1508 (rolling: measured only) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1509 (sets-only rolling contributes nothing) | `test/training_load_test.dart` (`S-1509 A`) | — (pure) | PASS |
| S-1510 (4 weeks / 25% boundaries) | `test/mix_layer_service_test.dart` | both | PENDING (Phase 2) |
| S-1511 (baseline period: no gap, start-of-week does not move it) | `test/training_load_test.dart` (`baselineBlockStarts`); the service half in Phase 2 | — (pure) | PASS (pure half); service half deferred |
| S-1512 (percentages sum to 100) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1513 (8 weeks, empty kept, window-independent) | `test/mix_layer_service_test.dart`; its week-start twin is `test/training_load_test.dart` (`OmniDateUtils.startOfWeek`) | — (pure for the twin) | twin PASS; strip deferred |
| S-1514 (Instruments parity) | `test/mix_layer_service_test.dart` | both | PENDING (Phase 2) |
| S-1515 (lifting-only: one 100% segment) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1516 (every modality: 4 segments, 50/17/17/16) | `test/training_load_test.dart` | — (pure) | PASS |
| S-1517 (a session crossing midnight and a week boundary) | `test/mix_layer_service_test.dart` | both | PENDING (Phase 2) |

Phase 1 covers the pure half of every scenario that has one; the nine scenarios with no pure half
(S-1510, S-1513, S-1514, S-1517 and the counts in S-1502, S-1511, S-1506's service parity) belong
to Phase 2's `test/mix_layer_service_test.dart`.

## 5. Hive ↔ Mock parity

`test/mix_layer_service_test.dart` runs its body over both harness factories. Record the two
outputs for the two parity scenarios and the equality assertion.

| Scenario | Mock output | Hive output | Equal |
|---|---|---|---|
| S-1503 | PENDING | PENDING | |
| S-1513 | PENDING | PENDING | |

## 6. Doc-claim → test table

Every behaviour sentence this PR adds to `docs/` names the test that asserts it. This table is
the audit of that rule; the reviewer checks it line by line.

| Doc | Claim (abbreviated) | Test that asserts it |
|---|---|---|
| `docs/training_load.md` | load = time × rating; unrated is 0 and is never estimated; zero time is 0 | `test/training_load_test.dart` (`sessionLoadMinutes (D-901)`: S-1501, S-1502, "each rating 1 through 5", "zero duration", "a negative duration") |
| `docs/training_load.md` | an effort's modality follows its kind, never the session's | `docs/global_conventions.md` (the invariant's owner); the tie-break order is `test/training_load_test.dart` (S-1506 B, S-1512) |
| `docs/training_load.md` | the definitions take a measured map and never derive it | `test/training_load_test.dart` (`sessionTimeByModality` call shape, S-1503) |
| `docs/training_load.md` | the remainder goes to Resistance, never below zero | `test/training_load_test.dart` (S-1503, S-1504, S-1505, "the remainder is never below zero") |
| `docs/training_load.md` | over-measured sessions go to the dominant modality; a session with no mapping effort contributes nothing | `test/training_load_test.dart` (S-1506 A, S-1507, "a session with no effort that maps to a section contributes nothing") |
| `docs/training_load.md` | rolling sessions use measured time only and sets add no time | `test/training_load_test.dart` (S-1508, S-1509 A) |
| `docs/training_load.md` | the load splits in proportion to the time; zero when the time is zero or the session is unrated | `test/training_load_test.dart` (`sessionLoadByModality (D-907)`) |
| `docs/training_load.md` | only positive measures are segments; order is descending measure then declaration order | `test/training_load_test.dart` (`mixSegments (D-912, D-913)`: S-1501, S-1503, S-1512, "a zero-measure modality is never a segment") |
| `docs/training_load.md` | percentages sum to 100 and a positive measure keeps a segment at 0% | `test/training_load_test.dart` (S-1512, S-1515, S-1516, "a positive measure always gets a segment, even at 0%") |
| `docs/training_load.md` | the baseline is `kTrainingLoadBaselineWeeks` blocks of 7 calendar days, anchored at the window's start day, no gap, DST-safe, independent of the start-of-week setting | `test/training_load_test.dart` (`baselineBlockStarts (D-934)`: the count, "no gap", "the last block ends the instant before fromDay", "anchored at fromDay, not at a week boundary", "unshifted across a DST transition"; independence is structural — the function takes no setting) |
| `docs/training_load.md` | the strip holds `kMixStripWeeks` weeks; a week's start honours the setting and any value other than `'sunday'` is Monday | `test/training_load_test.dart` (`OmniDateUtils.startOfWeek (D-910, D-935)` and the constant contract) |
| `docs/training_load.md` | the four constants and the rule each governs | `test/training_load_test.dart` (`the constants (D-908, D-917, D-934)`) |
| `docs/data_models.md` | the value types, their file, and that they are never persisted | `test/training_load_test.dart` (compile-time import of `lib/core/models/training_load.dart`) |
| `docs/constants_reference.md` | the four constants and the file that owns them | `test/training_load_test.dart` (`the constants (D-908, D-917, D-934)`) |
| `docs/README.md` | the index row resolves and the file is under the size ceiling | `test/docs_indexing_contract_test.dart` |

Planner's table listed Phase 2 claims here (the `computeMixLayer` history-walk row, the
`state_management/services_and_utils.md` row, the switch row). Phase 1 may not name
`computeMixLayer` and does not touch `services_and_utils.md`, so those rows were replaced with
the claims this phase's doc actually makes. They return in Phase 2's evidence.

## 7. Name collision sweep

Every name this PR introduces, searched across `docs/`, `lib/` and `test/` before writing.

| Name | Hits found | Files |
|---|---|---|
| `computeMixLayer` | 0 | — |
| `MixLayerData` | 0 | — |
| `MixSegment` | 0 | — |
| `MixWeek` | 0 | — |
| `MixMeasure` | 0 | — |
| `kMixStripWeeks` | 0 | — |
| `kTrainingLoadBaselineWeeks` | 0 | — |
| `kTrainingLoadMinRatedWeeks` | 0 | — |
| `kTrainingLoadMaxUnratedShare` | 0 | — |
| `training_load` | 0 | — |
| `startOfWeek` (pre-existing) | 10 | `docs/plans/settings-account-removal-plan.md`, `docs/state_management/app_state.md`, `lib/core/utils/date_utils.dart`, `lib/features/calendar/calendar_screen.dart`, `lib/features/session/session_summary_screen.dart`, `lib/features/settings/settings_screen.dart`, `lib/state/settings/settings_state.dart`, `test/calendar_layout_responsive_test.dart`, `test/interaction_flow_test.dart`, `test/settings_state_test.dart` |

Sweep run 2026-10-03 by the executor over `docs/`, `lib/` and `test/` (excluding the two
untracked 05a/05b plan folders). Every new name is free; `startOfWeek` already exists as a
parameter name on `OmniDateUtils.buildMonthGrid` and in `SettingsState`, so the new helper reuses
that vocabulary rather than inventing a second one.

Planner's pre-check (2026-10-02): only
`docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` mentions the concepts
("training load", "by time", "by load", "Load baseline"); no `lib/` or `test/` file carries any
of the names above.

## 8. Footprint

`gateway.sh git-status` must list nothing outside the plan's Predicted Files.

| Phase | Files touched | Out-of-bounds | Notes |
|---|---|---|---|
| 1 | `lib/core/models/training_load.dart` (new), `lib/core/utils/date_utils.dart`, `test/training_load_test.dart` (new), `docs/training_load.md` (new), `docs/README.md`, `docs/data_models.md`, `docs/constants_reference.md`, the evidence file, the plan file | none | every file is in the plan's Phase 1 Predicted Files |
| 2 | PENDING | | |

## 9. Suite output

Quote the final line of each run verbatim. A partial run, a hang or a timeout is a failure —
say so rather than omitting it.

| Phase | Command | Final line |
|---|---|---|
| 1 | `gateway.sh lint` | `196 issues found. (ran in 2.9s)` — identical count to the Step 0b baseline (`196 issues found. (ran in 3.1s)`), so no new issue |
| 1 | `gateway.sh test test/training_load_test.dart` | `00:00 +49: All tests passed!` |
| 1 | `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart test/training_load_test.dart` | `00:00 +59: All tests passed!` |
| 1 | `gateway.sh test` (full) | `01:29 +3326 ~1: All tests passed!` |
| 2 | `gateway.sh test test/training_load_test.dart test/mix_layer_service_test.dart` | PENDING |
| 2 | `gateway.sh test` | PENDING |

The full suite's baseline was `+3277`; this phase adds 49 tests, all in `test/training_load_test.dart`,
for `+3326`. The skip count (`~1`) is unchanged.

---

# Phase 2 evidence

## P2.1 Baselines re-run (Step 0b)

| Command | Baseline (Phase 1 close) | Phase 2 run | Verbatim final line |
|---|---|---|---|
| `gateway.sh lint` | `196 issues found.` | `196 issues found.` | `196 issues found. (ran in 2.7s)` |
| `gateway.sh test` (full) | `+3326 ~1: All tests passed!` | `+3364 ~1: All tests passed!` | `01:20 +3364 ~1: All tests passed!` |

The count grew by exactly 38 — the tests `test/mix_layer_service_test.dart` adds. The skip count
(`~1`) is unchanged and the lint count is identical, so no new issue.

## P2.2 Red run (Step 0c) — required

| Phase | Test file | Command | Observed failure (paste) | Then green (paste) |
|---|---|---|---|---|
| 2 | `test/mix_layer_service_test.dart` | `gateway.sh test test/mix_layer_service_test.dart` | `test/mix_layer_service_test.dart:130:34: Error: The method 'computeMixLayer' isn't defined for the type 'StatsProgressService'.` … `Failed to load "…/test/mix_layer_service_test.dart": Compilation failed` … `00:00 +0 -1: Some tests failed.` | `00:00 +38: All tests passed!` |

The red is a compile failure for the missing API, which the brief accepts. Three behavioural reds
follow in §P2.3, one per rule the phase adds.

## P2.3 Inverse-edit mutations — required, on tracked files

Each mutation is applied, the named test is shown to fail, and the mutation is reverted. No
`git stash`, `checkout` or `restore` was used; the mutation spot was read back with
`gateway.sh git-diff --stat -- <file>`.

| # | Tracked file | Mutation | Test that must fail | Observed | Reverted |
|---|---|---|---|---|---|
| M1 | `lib/core/services/stats_progress_service.dart`'s rule home, `lib/core/models/training_load.dart` (the service calls `sessionTimeByModality`, so the remainder rule has one home) | Resistance's remainder forced to 0 (treat Resistance as measured): `final remainder = durationSecs - totalMeasured;` → `final remainder = 0.0;` | S-1503 / S-1505 in `test/mix_layer_service_test.dart` | `00:00 +0 -1: Mock — computeMixLayer S-1503 a rated free-training session is 67/33 in load [E]` / `Expected: [` / `Actual: [ExerciseSection:ExerciseSection.isometric]` / `test/mix_layer_service_test.dart 288:9`; `+0 -2: Hive — … S-1503 … [E]`; `+0 -3: Mock and Hive — value-for-value parity S-1503 the two stores agree [E]` / `Expected: ['resistance:120.0:67', 'isometric:60.0:33']` / `Actual: ['isometric:60.0:100']`; and `S-1505 … [E]` / `Actual: [ExerciseSection:ExerciseSection.cardio]`; `00:00 +0 -2: Some tests failed.` | yes — `gateway.sh git-diff --stat -- lib/core/models/training_load.dart` empty; `gateway.sh test test/mix_layer_service_test.dart` → `00:00 +38: All tests passed!` |
| M2 | `lib/core/utils/date_utils.dart` | week-start helper ignores its `startOfWeek` argument: the `'sunday'` ternary replaced by `final daysSinceStart = day.weekday - 1;` | the strip's Sunday-start assertion — `S-1513 twin a Sunday start shifts every week` in `test/mix_layer_service_test.dart` | `00:00 +0 -1: Mock — computeMixLayer S-1513 twin a Sunday start shifts every week [E]` / `Expected: <7>` / `Actual: <1>` / `test/mix_layer_service_test.dart 653:11`; `+0 -2: Hive — … [E]`; `00:00 +0 -2: Some tests failed.` | yes — `gateway.sh git-diff --stat -- lib/core/utils/date_utils.dart` back to `1 file changed, 16 insertions(+)`; `gateway.sh test test/mix_layer_service_test.dart test/training_load_test.dart` → `00:01 +87: All tests passed!` |
| M3 | `lib/core/models/training_load.dart` | `baselineBlockStarts` steps by `Duration(days: 7)` instead of calendar arithmetic: the `DateTime(y, m, d − n)` term replaced by `day.subtract(Duration(days: (kTrainingLoadBaselineWeeks - i) * 7))` | the DST assertion in `S-1511`'s pure half — `baselineBlockStarts`'s `the blocks are unshifted across a DST transition` in `test/training_load_test.dart` | `+39 -1: … exactly 12 blocks of 7 calendar days tile the period [E]` (`Expected: DateTime:<2026-02-11 00:00:00.000>` / `Actual: DateTime:<2026-02-10 23:00:00.000>`), `+39 -2: … no gap … [E]`, `+40 -3: … anchored at fromDay, not at a week boundary [E]`, `+40 -4: … the blocks are unshifted across a DST transition [E]` (`Expected: <0>` / `Actual: <23>`), `00:00 +45 -4: Some tests failed.` | yes — `gateway.sh git-diff --stat -- lib/core/models/training_load.dart` empty; `gateway.sh test test/training_load_test.dart test/mix_layer_service_test.dart` → `00:01 +87: All tests passed!` |

M1's first attempt used `final remainder = 0;`, which is a compile error (`num` to `double`) rather
than a test failure; the mutation was corrected to `0.0` so the named tests fail behaviourally.

## P2.4 Per-scenario results (Phase 2 half)

| Scenario | Where | Harness | Result |
|---|---|---|---|
| S-1501 | `test/mix_layer_service_test.dart` (`S-1501 a 60-minute session rated 4 is 240 load`) | both | PASS |
| S-1502 | `… S-1502 an unrated 60-minute session adds no load and one unrated count` | both | PASS |
| S-1503 | `… S-1503 a rated free-training session is 67/33 in load` | both | PASS |
| S-1505 | `… S-1505 a 75-minute lifting session with a 15-minute timed warm-up` | both | PASS |
| S-1509 | `… S-1509 a sets-only rolling session contributes nothing` | both | PASS |
| S-1510 A | `… S-1510 A exactly 4 rated baseline weeks shows load` | both | PASS |
| S-1510 B | `… S-1510 B three rated baseline weeks shows time` | both | PASS |
| S-1510 C | `… S-1510 C exactly 25% unrated still shows load` | both | PASS |
| S-1510 D | `… S-1510 D a third of the window unrated shows time` | both | PASS |
| S-1510 E | `… S-1510 E a wholly unrated window never reads as load` | both | PASS |
| S-1511 | `… S-1511 the baseline is the 12 blocks before the window, with no gap` | both | PASS |
| S-1511 twin | `… S-1511 twin the start-of-week setting never moves a baseline boundary` | both | PASS |
| S-1513 | `… S-1513 the strip is 8 weeks, keeps empty weeks and ignores the window` | both | PASS |
| S-1513 twin | `… S-1513 twin a Sunday start shifts every week` | both | PASS |
| S-1514 | `… S-1514 the mix and the Instruments list agree on the modality` | both | PASS |
| S-1515 | `… S-1515 a lifting-only window is one full-width Resistance segment` | both | PASS |
| S-1516 | `… S-1516 a session holding every modality splits four ways and sums to 100` | both | PASS |
| S-1517 | `… S-1517 a session crossing midnight belongs to the week it started in` | both | PASS |

## P2.5 Hive ↔ Mock parity

| Scenario | Mock output | Hive output | Equal |
|---|---|---|---|
| S-1503 | `measure=load`; `segments=[resistance:120.0:67, isometric:60.0:33]`; `baseline=[resistance:240.0:100]`; `unrated=0`; `ratedBaselineWeeks=4` | identical | yes — `expect(_layerShape(hiveData), _layerShape(mockData))` |
| S-1513 | `measure=time`; `segments=[resistance:60.0:100]`; `baseline=[]`; `unrated=1`; `ratedBaselineWeeks=0`; 8 weeks, total `240.0` | identical | yes — `expect(_layerShape(hiveData), _layerShape(mockData))` |

Both parity tests assert the whole payload shape — measure, bar, baseline, both counts and every
week's start, measure, in-progress flag and segments — so a divergence in any field fails.

## P2.6 Doc-claim → test table (Phase 2 additions)

| Doc | Claim (abbreviated) | Test that asserts it |
|---|---|---|
| `docs/training_load.md` | `computeMixLayer` is the only history walk behind these figures and serves the window, the baseline and the strip from one cached snapshot | `test/mix_layer_service_test.dart` (the whole file runs against a real repository; the parity group proves one payload per store) |
| `docs/training_load.md` | it returns `null` when the window holds no time | `test/mix_layer_service_test.dart` (`S-1509 a sets-only rolling session contributes nothing`) |
| `docs/training_load.md` | the measure is load only when the baseline is rated enough and the window is rated enough | `test/mix_layer_service_test.dart` (`S-1510 A`, `S-1510 B`, `S-1510 C`, `S-1510 D`, `S-1510 E`) |
| `docs/training_load.md` | the baseline's segments are built in the load measure only, and only when the baseline's total load is above zero | `test/mix_layer_service_test.dart` (`S-1501`, `S-1502`, `S-1510 B`, `S-1510 E`, `S-1511`) |
| `docs/training_load.md` | the strip is the `kMixStripWeeks` weeks ending with the week containing the current instant, oldest first, last marked in progress | `test/mix_layer_service_test.dart` (`S-1513`, `S-1513 twin`) |
| `docs/training_load.md` | an empty week is present with a zero measure rather than dropped | `test/mix_layer_service_test.dart` (`S-1513`, `S-1517`) |
| `docs/training_load.md` | a session belongs to the week it started in | `test/mix_layer_service_test.dart` (`S-1517`) |
| `docs/training_load.md` | the strip is selected against each week's own bounds, never the window | `test/mix_layer_service_test.dart` (`S-1513` — the `now−30d` session is outside the window and still in its week) |
| `docs/training_load.md` | the baseline never uses the start-of-week setting; that setting moves the strip's weeks and nothing else | `test/mix_layer_service_test.dart` (`S-1511 twin`) |
| `docs/state_management/services_and_utils.md` | the entry point's signature, its `null` case and its one-walk cost | `test/mix_layer_service_test.dart` (the file compiles against the signature; `S-1509` for the `null` case) |
| `docs/state_management/services_and_utils.md` | the effort-to-modality mapping is the service's own, so the mix and the Instruments list cannot disagree | `test/mix_layer_service_test.dart` (`S-1514`) |
| `docs/state_management/services_and_utils.md` | the rules live in `lib/core/models/training_load.dart` | `test/training_load_test.dart` (Phase 1) |

## P2.7 Name collision sweep (Phase 2)

Sweep run 2026-10-03 by the executor over `docs/` and `test/` for every name this phase adds.

| Name | Files |
|---|---|
| `computeMixLayer` | `docs/training_load.md`, `docs/state_management/services_and_utils.md`, `test/mix_layer_service_test.dart`, the plan and evidence files, `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/…` (5b's contract) |
| `MixLayerData` | `docs/data_models.md`, `docs/training_load.md`, `test/mix_layer_service_test.dart`, the plan/evidence files, 5b's plan |
| `MixSegment` | `docs/data_models.md`, `test/mix_layer_service_test.dart`, `test/training_load_test.dart`, the plan/evidence files, 5b's plan |
| `MixWeek` | `docs/data_models.md`, `docs/training_load.md`, `test/mix_layer_service_test.dart`, the plan/evidence files, 5b's plan |
| `MixMeasure` | `docs/data_models.md`, `test/mix_layer_service_test.dart`, the plan/evidence files, 5b's plan |
| `kMixStripWeeks` | `docs/constants_reference.md`, `docs/training_load.md`, `test/mix_layer_service_test.dart`, `test/training_load_test.dart`, the plan/evidence files |
| `kTrainingLoadBaselineWeeks` | `docs/constants_reference.md`, `docs/training_load.md`, `test/training_load_test.dart`, the plan/evidence files |
| `kTrainingLoadMinRatedWeeks` | `docs/constants_reference.md`, `docs/training_load.md`, `test/training_load_test.dart`, the plan/evidence files, 5b's plan |
| `kTrainingLoadMaxUnratedShare` | `docs/constants_reference.md`, `docs/training_load.md`, `test/training_load_test.dart`, the plan/evidence files |
| `training_load` | `docs/README.md`, `docs/constants_reference.md`, `docs/data_models.md`, `docs/training_load.md`, `docs/state_management/services_and_utils.md`, `test/mix_layer_service_test.dart`, `test/training_load_test.dart`, the plan/evidence files, 5b's plan |

Every hit is a file this PR owns or a planning artefact. No `lib/` file outside
`lib/core/models/training_load.dart`, `lib/core/utils/date_utils.dart` and
`lib/core/services/stats_progress_service.dart` carries any of these names.

## P2.8 Footprint

| Phase | Files touched | Out-of-bounds | Notes |
|---|---|---|---|
| 2 | `lib/core/services/stats_progress_service.dart`, `test/mix_layer_service_test.dart` (new), `docs/training_load.md`, `docs/state_management/services_and_utils.md`, the evidence file, the plan file | none | every file is in the plan's Phase 2 Predicted Files |

`lib/core/models/training_load.dart` and `lib/core/utils/date_utils.dart` were touched only
transiently for M1/M2/M3 and are byte-identical to their Phase 1 state (`git-diff --stat` empty for
the former, `16 insertions(+)` for the latter — its Phase 1 change).

## P2.9 Suite output

| Phase | Command | Final line |
|---|---|---|
| 2 | `gateway.sh lint` | `196 issues found. (ran in 2.7s)` — identical count to the Step 0b baseline, so no new issue |
| 2 | `gateway.sh test test/mix_layer_service_test.dart` | `00:00 +38: All tests passed!` |
| 2 | `gateway.sh test test/training_load_test.dart test/mix_layer_service_test.dart test/docs_indexing_contract_test.dart` | `00:00 +96: All tests passed!` |
| 2 | `gateway.sh test test/docs_indexing_contract_test.dart` | `00:00 +9: All tests passed!` |
| 2 | `gateway.sh test` (full) | `01:20 +3364 ~1: All tests passed!` |

The full suite's Phase 1 close was `+3326`; this phase adds 38 tests, all in
`test/mix_layer_service_test.dart`, for `+3364`. The skip count (`~1`) is unchanged.

## Fix round 1

Companion to `2026-10-02-05a-stats-pr5a-mix-data-plan.review.md`. One line per finding.

| Finding | What changed | Where |
|---|---|---|
| 1 (major) | S-1511 fixture B is tested on both stores: the window comes from `StatsProgressService.resolveWindow(periods: [period], …)` with `isPeriodScoped == true`, the bar covers the period's sessions, the baseline ends at `fromDay`, the payload equals an equivalent hand-built non-period window's, and the same period pulled back one day to `W−1d` leaves one rated block | `test/mix_layer_service_test.dart` (the `S-1511 fixture B` test); the plan's S-1511 register entry |
| 2 (minor) | The register's S-1511 expected outcome now states the measure there is time, so `baselineSegments` is empty and the baseline counts are what is asserted; the test's divergence comment points at the plan's Assumption Log entry 2 rather than here | the plan's S-1511 register entry; `test/mix_layer_service_test.dart` |
| 3 (minor) | The four training-load rows name their verifier | `docs/constants_reference.md` |
| 4 (minor) | `sessionLoadMinutes`'s doc comment states that the caller guarantees a rating of 1 to 5, the stored rating's range, and that values outside it are not clamped there — comment only, no behaviour change | `lib/core/models/training_load.dart` |
| 5 (nit) | The S-1513 parity row records `unrated=1` (the parity window holds one of the fixture's five sessions) | §P2.5 above |
| 6 (nit) | No change requested: measured/dominant stay in the one pass over the cached snapshot (D-919) | — |

### Fix-round mutation proof (finding 1's test)

`gateway.sh git-diff --stat -- lib/core/services/stats_progress_service.dart` before and after the
mutation: `1 file changed, 265 insertions(+)`.

| Tracked file | Mutation | Command | Tests that failed | Reverted |
|---|---|---|---|---|
| `lib/core/services/stats_progress_service.dart` | the baseline's end moved off the window's start day: `final baselineEndMs = fromDay.millisecondsSinceEpoch;` → `final baselineEndMs = window.toMs.millisecondsSinceEpoch;` | `gateway.sh test test/mix_layer_service_test.dart` | `00:00 +0 -1: Mock — computeMixLayer S-1501 a 60-minute session rated 4 is 240 load [E]`; `+4 -2: Mock — … S-1510 A exactly 4 rated baseline weeks shows load [E]`; `+4 -3: Mock — … S-1510 B three rated baseline weeks shows time [E]`; `+5 -4: Mock — … S-1510 D a third of the window unrated shows time [E]`; `+7 -5: Mock — … S-1511 fixture B a period-scoped window keeps the same baseline and the same bar [E]`; `+14 -6: Hive — … S-1501 … [E]`; `+18 -7: Hive — … S-1510 A … [E]`; `+18 -8: Hive — … S-1510 B … [E]`; `+19 -9: Hive — … S-1510 D … [E]`; `+21 -10: Hive — … S-1511 fixture B … [E]`; `+28 -11: Mock and Hive — value-for-value parity S-1503 the two stores agree [E]`; `00:00 +29 -11: Some tests failed.` | yes — `grep -n baselineEndMs` read the line back at 488 as `final baselineEndMs = fromDay.millisecondsSinceEpoch;`, `git-diff --stat` returned to `1 file changed, 265 insertions(+)`, and the file ran `00:00 +40: All tests passed!` |

The mutation's first attempt left fixture B passing. `_baselineBlockFor` returns the last block
start at or before a session's start with no upper bound, so the mutation clamps the four in-period
sessions into the block holding `W−1d` — a block the fixture already rates, leaving
`ratedBaselineWeeks` at 2. The test gained the `W−1d` boundary window, which the mutation reports as
2 rated blocks instead of 1, so the assertion now fails under the mutation and passes without it.

### Fix-round suite output

| Command | Final line |
|---|---|
| `gateway.sh test test/mix_layer_service_test.dart` (mutation reverted) | `00:00 +40: All tests passed!` |
| `gateway.sh lint` | `196 issues found. (ran in 3.2s)` |
| `gateway.sh test test/mix_layer_service_test.dart test/training_load_test.dart test/docs_indexing_contract_test.dart` | `00:01 +98: All tests passed!` |

The two tests the fix round adds are fixture B's second store case and its boundary window; the
phase's 38 become 40 in `test/mix_layer_service_test.dart`.
