# Evidence — Stats PR 10b: the Stats explanation sheet and a friendlier first-use screen

Companion to `2026-10-04-10b-stats-pr10b-primer-sheet-plan.md`. Evidence only. Review findings go in
`2026-10-04-10b-stats-pr10b-primer-sheet-plan.review.md`; neither goes into the plan.

> **Revised design (pre-approval).** The auto-open is hosted by `HomeScreen`, the shipped Nutrition
> pattern, and the seen flag is marked when the sheet's `showModalBottomSheet` future completes — by
> any means (D-2022). Sections 3 and 3A below are Phase 2A and 2B; the dropped scenarios
> S-2702 / S-2709 / S-2712 / S-2713 and the rejected in-screen mutations are gone. Section 5's
> unaffected set is unchanged.

---

## 1. Baselines

| Check | Command | Expected | Observed |
|---|---|---|---|
| Analyze | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found.`, 0 errors | `196 issues found. (ran in 3.3s)` — 0 errors, measured on the clean tree before Phase 1 |
| Full suite | `.github/copilot/scripts/macos/gateway.sh test` | `+3852 ~1: All tests passed!` | Phase-1 close run: `+3858 ~1: All tests passed!`. Six tests are new in Phase 1 and `git-diff` shows no tracked file changed, so the pre-Phase-1 count is `3858 − 6 = 3852`, matching the brief. The baseline was not run separately before the change (the untracked new test file cannot be excluded from a run); the arithmetic above is the re-measurement. |

PR 10a (a test-only isolation refactor) may have landed before this PR started. **Re-measure both
baselines before Phase 1** and record the numbers actually observed; the values above are the
brief's, not a promise.

One pre-existing timing-sensitive test may fail once in a full run. If it does: re-run once and record
**both** summary lines here rather than only the green one.

---

## 2. Phase 1 — `StatsPrimerState` (@dba)

### 2.1 Red run before the code

| Command | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_state_test.dart` (before `lib/state/stats/stats_primer_state.dart` exists) | compile failure — `Target of URI doesn't exist` / `Undefined name 'StatsPrimerState'` | `Error when reading 'lib/state/stats/stats_primer_state.dart': No such file or directory` + 8 `Method not found` / `Undefined name 'StatsPrimerState'` errors → `00:00 +0 -1: Some tests failed.` |
| `gateway.sh test test/stats_primer_state_test.dart` (after) | `All tests passed!` | `00:00 +6: All tests passed!` |

The test file is created first (so the red run compiles the test), then the state class. The new
directory `lib/state/stats/` cannot be created by the gateway's menu, so it was created by a
throwaway `test/zz_mkdir_stats.dart` probe run through `gateway.sh test` and then removed with
`gateway.sh delete-scratch test/zz_mkdir_stats.dart` (see Assumption Log A-9).

### 2.2 Scenario coverage

| Scenario | Test name | Mock | Hive |
|---|---|---|---|
| S-2705 | `Mock — S-2705: the seen flag survives a restart` › `a marked-seen Stats primer is seen again after a Hive restart` | green | green |
| S-2705 | `Hive — S-2705: the seen flag survives a restart` › `a marked-seen Stats primer is seen again after a Hive restart` | green | green |
| S-2706 | `Mock — S-2706: the two primer keys are independent` › `marking the Stats primer seen leaves the Nutrition primer unseen` | green | green |
| S-2706 | `Hive — S-2706: the two primer keys are independent` › `marking the Stats primer seen leaves the Nutrition primer unseen` | green | green |
| S-2710 | `S-2710: markSeen is idempotent` › `two markSeen calls write the flag once and notify once` | green | — |
| S-2711 | `S-2711: a hydration failure falls back to unseen` › `a throwing getPreferenceBool leaves the primer unseen` | green | — |

The two persistence scenarios run once per `harnessFactories` entry, so the group name is prefixed
`Mock — ` / `Hive — ` (the `test/entry_identity_test.dart` and
`test/protein_consistency_service_test.dart` convention); the pinned scenario name and test name are
kept verbatim after the prefix (Assumption Log A-10).

### 2.3 Mutation records

Each record: the original line, the mutated line, the command, the observed output, and the restore.
Both mutations ran before step 6's `dart format`, so the `test/stats_primer_state_test.dart:NN`
line numbers in the pasted output are those of the pre-format file; the current file wraps the
`test(` calls and the assertions sit at different lines.

#### Mutation A — the key is not the Nutrition key

- **File:** `lib/state/stats/stats_primer_state.dart`
- **Original:** `static const String preferenceKey = 'primer_seen_stats';`
- **Mutated:** `static const String preferenceKey = 'primer_seen_nutrition';`
- **Test that must go red:** `S-2706: the two primer keys are independent` ›
  `marking the Stats primer seen leaves the Nutrition primer unseen`
- **Command:** `gateway.sh test test/stats_primer_state_test.dart`
- **Expected red:** the assertion on `getPreferenceBool('primer_seen_nutrition') == false` fails — the
  Stats write lands on the Nutrition key.
- **Observed:** red, both harnesses:
  ```
  00:00 +1 -1: Mock — S-2706: the two primer keys are independent marking the Stats primer seen leaves the Nutrition primer unseen [E]
    Expected: false
      Actual: <true>
    test/stats_primer_state_test.dart 84:9              main.<fn>.<fn>
  00:00 +2 -2: Hive — S-2706: ... [E]  (same)
  00:00 +4 -2: Some tests failed.
  ```
  S-2705 stayed green (it never reads the Nutrition key), so the mutant is isolated to S-2706.
- **Restore → re-run:** the original line restored verbatim →
  `00:00 +6: All tests passed!`

#### Mutation B — `markSeen` really writes

- **File:** `lib/state/stats/stats_primer_state.dart`
- **Original:** `await _repository.setPreferenceBool(preferenceKey, true);`
- **Mutated:** the line deleted
- **Test that must go red:** `S-2705: the seen flag survives a restart` ›
  `a marked-seen Stats primer is seen again after a Hive restart`
- **Command:** `gateway.sh test test/stats_primer_state_test.dart`
- **Expected red:** the fresh state's `hasSeen` is `false` after the restart — the flag was never
  persisted.
- **Observed:** red, both harnesses (S-2705's `hasSeen` assertion is line 61); S-2706 and S-2710 go
  red with it because the flag never lands:
  ```
  00:00 +0 -3: Hive — S-2705: the seen flag survives a restart ... [E]
    Expected: true
      Actual: <false>
    test/stats_primer_state_test.dart 61:9              main.<fn>.<fn>
  00:00 +0 -4: Hive — S-2706: ... [E]  (Expected: true / Actual: <false>, line 80)
  00:00 +0 -5: S-2710: markSeen is idempotent ... [E]  (Expected: an object with length of <1> / Actual: [])
  00:00 +1 -5: Some tests failed.
  ```
- **Restore → re-run:** the original line restored verbatim →
  `00:00 +6: All tests passed!`

### 2.4 Phase 1 close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_state_test.dart` | green | `00:00 +6: All tests passed!` |
| `gateway.sh lint` | baseline issue count, 0 errors | `196 issues found. (ran in 3.0s)` — 0 errors, no issue in either new file |
| `gateway.sh git-status` | exactly the two new files | `?? lib/state/stats/` and `?? test/stats_primer_state_test.dart`; `git-diff --stat` empty (no tracked file touched) |

Full suite at Phase 1 close: `+3858 ~1: All tests passed!` (`gateway.sh test`).

---

## 3. Phase 2A — the sheet, the `showPrimerHelp` flag, the "?" and the first-use card (@developer)

### 3.1 Red run before the code

The new test file was authored after the production surface in this run, so the "before step 1 exists" red
was produced by **temporarily reverting the new constructor surface** rather than by an absent file: the
`showPrimerHelp` field was given an initializer and the constructor parameter was deleted, so the screen
still compiled while the test's named argument no longer resolved. The compile failure below is the
observed red; the exact original lines were then restored (the diff returned to 89 insertions, 0 deletions)
and the file went green.

| Command | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_screen_test.dart` (new constructor surface temporarily reverted) | compile failure — the test's `showPrimerHelp:` named argument does not resolve | `test/stats_primer_screen_test.dart:51:15: Error: No named parameter with the name 'showPrimerHelp'.` + `lib/features/stats/stats_screen.dart:49:9: Context: Found this candidate, but the arguments don't match.` → `00:00 +0 -1: Some tests failed.` |
| `gateway.sh test test/stats_primer_screen_test.dart` (after the surface is restored) | `All tests passed!` | `00:00 +7: All tests passed!` |

### 3.2 Scenario coverage

| Scenario | Test name | Result |
|---|---|---|
| S-2703 | `S-2703: with showPrimerHelp omitted the Stats primer feature is off` › `no help action, no empty-state button and the chart action still renders` | green |
| S-2704 (a) | `S-2704: the header "?" reopens the primer and never marks it` › `reopening with an unseen state leaves it unseen` | green |
| S-2704 (b) | `S-2704: the header "?" reopens the primer and never marks it` › `reopening with a seen state still opens the sheet` | green |
| S-2707 (a) | `S-2707: the first-use card explains what will appear` › `the empty state keeps its title and body and adds the explanation and the button` | green |
| S-2707 (b) | `S-2707: the first-use card explains what will appear` › `the empty-state button opens the sheet without marking it seen` | green |
| S-2708 | `S-2708: the "?" and the chart icon coexist` › `the chart icon stays the only way into Records & Trends` | green |
| S-2714 | `S-2714: the taller first-use card fits a small viewport` › `the card lays out at 320x568 without an overflow` | green |

**Honesty note (as the plan pre-declared).** The two S-2704 cases and the S-2707 (b) "still `false`"
assertion hold a test-owned `StatsPrimerState` that the screen never receives (D-2019), so they cannot go
red from any screen mutation — the "reopen never marks" property is structural, held by the Phase 3A
guard `the Stats screen holds no StatsPrimerState`, and its cross-phase behavioural mutation is 2B
mutation B. What these cases do prove is the positive half: the sheet opens from both hosts and closes
cleanly. Mutation A below is the one screen-level mutant this run can turn red.

S-2702, S-2709, S-2712 and S-2713 were dropped before approval (the auto-open is no longer in this
screen). S-2701, S-2716, S-2717 and S-2718 are covered in section 3A.

### 3.3 Existing tests: does any need an edit?

**Expected: none.** Record the observed answer per file, with the reason it is unaffected.

| File | Why it is unaffected | Green |
|---|---|---|
| `test/header_standardization_test.dart` | pumps `StatsScreen` with `showPrimerHelp` omitted; asserts the header title, the back icon and the empty-state copy — never an action count | green |
| `test/records_and_trends_screen_test.dart` | S-913 keys off `find.byTooltip('Records & Trends')`; the static scan still finds one construction site | green |
| `test/stats_legacy_removal_test.dart` | `showPrimerHelp` omitted; asserts the empty state and the legacy-title absence | green |
| `test/screen_widget_test.dart` | `showPrimerHelp` omitted; asserts the empty-state copy | green |
| `test/fuel_row_screen_test.dart` | S-1107; `showPrimerHelp` omitted | green |
| `test/screen_overflow_contract_test.dart` | seeds sessions, so the empty card is never built | green |
| `test/nutrition_trend_screen_test.dart` | exercises the zero-session empty state with `showPrimerHelp` omitted | green |
| `test/mix_layer_screen_test.dart` | `showPrimerHelp` omitted; every assertion is scoped to a `mix_*` key or the Mix layer's own copy | green |
| `test/signals_layer_screen_test.dart` | `showPrimerHelp` omitted | green |
| the remaining `StatsScreen`-pumping files (18 total) | `showPrimerHelp` omitted | green |

**Observed answer: none needs an edit.** One command for the whole unaffected set is in section 5; it
reported `00:11 +525: All tests passed!` with no tracked `test/` file modified
(`gateway.sh git-status` lists only `stats_screen.dart` modified and the two new untracked files).

### 3.4 Mutation records

#### Mutation A — the flag really defaults to off

- **File:** `lib/features/stats/stats_screen.dart`
- **Original:** `    this.showPrimerHelp = false,` (the constructor parameter's default)
- **Mutated:** `    this.showPrimerHelp = true,`
- **Test that must go red:** `S-2703: with showPrimerHelp omitted the Stats primer feature is off` ›
  `no help action, no empty-state button and the chart action still renders`
- **Command:** `gateway.sh test test/stats_primer_screen_test.dart`
- **Expected red:** the "?" and the empty-state button render on a screen that omitted the flag
- **Observed:** red — the `stats_primer_help` `findsNothing` assertion at test line 69 failed:
  ```
  00:00 +0 -1: S-2703: with showPrimerHelp omitted the Stats primer feature is off no help action, no empty-state button and the chart action still renders [E]
    Test failed. See exception logs above.
  ...
  00:00 +6 -1: Some tests failed.
  ```
  The other six cases stayed green: they all pass `showPrimerHelp: true`, which the mutant renders
  identically to the correct code, so the mutant is isolated to S-2703.
- **Restore → re-run:** the original line restored verbatim → `00:00 +7: All tests passed!` (the
  `git-diff --stat` on `stats_screen.dart` reads `89 insertions(+)`, the pre-mutation shape).

The "reopen never marks" half of S-2704 / S-2707 cannot go red in this run: the screen holds no
state, so there is nothing to mutate here. It is held by the Phase 3A guard that `StatsScreen` never
references `StatsPrimerState`, and its cross-phase mutation is 2B mutation B.

### 3.5 Phase 2A close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_screen_test.dart test/stats_primer_state_test.dart` | green | `00:00 +13: All tests passed!` (7 screen + 6 state) |
| `gateway.sh test` (full suite) | the re-measured baseline count, `All tests passed!` | `01:43 +3865 ~1: All tests passed!` (baseline `+3858 ~1` + 7 new screen cases) |
| `gateway.sh lint` | baseline issue count, 0 errors | `196 issues found. (ran in 3.7s)` — 0 errors, 0 issues in `stats_screen.dart`, `stats_primer_sheet.dart` or `stats_primer_screen_test.dart` |
| `gateway.sh git-status` | exactly the three Predicted Files | `M lib/features/stats/stats_screen.dart`, `?? lib/features/stats/widgets/stats_primer_sheet.dart`, `?? test/stats_primer_screen_test.dart`; `git-diff --stat` = `89 insertions(+)`, 0 deletions |

**Residue sweep pre-check** (Phase 3A formalises these; run here so the phase ends with the sweeps
empty): (a) `primer_seen_stats` in `lib/` → only `lib/state/stats/stats_primer_state.dart`; (b)
`StatsPrimerSheet(` in `lib/` → `lib/features/stats/stats_screen.dart:351` (the host) and the
constructor declaration in the sheet itself (`home_screen.dart` is Phase 2B); (c) the Records & Trends
empty-state string → exactly one occurrence, file otherwise unmodified; (d) no `TODO` /
`UnimplementedError` in either new file; (e) no `Color(0x` in either new file; (f) no
`_primerAutoShown` / `AnimationStatusListener` in `lib/features/stats/`.

**Phase 3A risk to flag (not acted on — out of 2A scope).** The Phase 3A guard `no unfinished-feature
wording reaches the Stats feature` scans all of `lib/features/stats/` for the D-2011 banned strings,
and the pre-existing comment at `lib/features/stats/widgets/mix_layer.dart:11` contains the phrase
"load baseline". A naive substring scan will hit it; the guard will need to scope to the files this
PR adds or to user-facing strings only.

---

## 3A. Phase 2B — HomeScreen hosting, DI threading and the Home test (@developer)

### 3A.1 Red run before the code

| Command | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_home_test.dart` (before the Home changes exist) | compile failure — `Undefined name 'StatsPrimerState'` / no `statsPrimerState` parameter | _pending_ |
| `gateway.sh test test/stats_primer_home_test.dart` (after) | `All tests passed!` | _pending_ |

### 3A.2 Scenario coverage

| Scenario | Test name | Result |
|---|---|---|
| S-2701 | `S-2701: the first Stats tap from Home shows the primer once` › `an unseen state shows the sheet on the first tap and marks it seen when the sheet closes` | _pending_ |
| S-2716 | `S-2716: a second Stats tap pushes Stats directly` › `a seen state pushes Stats with no sheet` | _pending_ |
| S-2717 | `S-2717: a Home with no state pushes Stats directly and Stats has no "?"` › `a null state pushes Stats with showPrimerHelp false` | _pending_ |
| S-2718 | `S-2718: dismissing the auto-shown sheet by an outside tap still marks it seen` › `the flag is false while the sheet shows and true after an outside tap` | _pending_ |

### 3A.3 Mutation records

#### Mutation A — the auto-open really is one-shot

- **File:** `lib/features/home/home_screen.dart`
- **Original:** the `widget.statsPrimerState?.shouldShowPrimer == true` condition in `_openStatsScreen`
- **Mutated:** the condition deleted, so the sheet shows on every tap
- **Test that must go red:** `S-2716: a second Stats tap pushes Stats directly` ›
  `a seen state pushes Stats with no sheet`
- **Seed that turns it red:** a Mock repository with `primer_seen_stats` already `true` before the
  pump
- **Command:** `gateway.sh test test/stats_primer_home_test.dart`
- **Expected red:** a `StatsPrimerSheet` is on screen after the second tap
- **Observed:** _pending_
- **Restore → re-run:** _pending_

#### Mutation B — the auto-shown sheet marks when it closes

- **File:** `lib/features/home/home_screen.dart`
- **Original:** `unawaited(widget.statsPrimerState!.markSeen());` on the line after the awaited
  `showModalBottomSheet` in `_showStatsPrimer()`
- **Mutated:** that line deleted
- **Test that must go red:** `S-2718: dismissing the auto-shown sheet by an outside tap still marks it seen` ›
  `the flag is false while the sheet shows and true after an outside tap` (and S-2701's
  `marks it seen when the sheet closes`)
- **Command:** `gateway.sh test test/stats_primer_home_test.dart`
- **Expected red:** the flag stays `false` after the sheet closes
- **Observed:** _pending_
- **Restore → re-run:** _pending_

### 3A.4 Phase 2B close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_home_test.dart test/stats_primer_screen_test.dart test/stats_primer_state_test.dart test/nutrition_primer_test.dart test/header_standardization_test.dart test/records_and_trends_screen_test.dart` | green | _pending_ |
| `gateway.sh test` (full suite) | the re-measured baseline count, `All tests passed!` | _pending_ |
| `gateway.sh lint` | baseline issue count, 0 errors | _pending_ |
| `gateway.sh git-status` | exactly the six Predicted Files | _pending_ |

---

## 4. Phase 3A — guards and residue sweep (@developer)

### 4.1 Guards

| Guard test | What it makes impossible | Green |
|---|---|---|
| `the Stats primer key is written in exactly one file` | a second reader/writer of `primer_seen_stats` drifting away from `StatsPrimerState` | _pending_ |
| `the Home screen's primer state stays optional and nullable` | a refactor to a required parameter, which would break every existing `HomeScreen` consumer | _pending_ |
| `the Stats screen holds no StatsPrimerState` | the state creeping back into the screen, which is what re-opens the "reopen marks seen" hole | _pending_ |
| `no unfinished-feature wording reaches the Stats feature` | the banned wording from D-2011 re-entering the Stats feature | _pending_ |

### 4.2 Mutation records

#### Mutation A — the nullability guard bites

- **File:** `lib/features/home/home_screen.dart`
- **Original:** `final StatsPrimerState? statsPrimerState;`
- **Mutated:** `final StatsPrimerState statsPrimerState;` (the `?` dropped)
- **Test that must go red:** `the Home screen's primer state stays optional and nullable`
- **Command:** `gateway.sh test test/stats_primer_contract_test.dart`
- **Observed:** _pending_
- **Restore → re-run:** _pending_

#### Mutation B — the no-state-in-the-screen guard bites

- **File:** `lib/features/stats/stats_screen.dart`
- **Original:** no `StatsPrimerState` reference
- **Mutated:** a temporary `final StatsPrimerState? statsPrimerState;` field plus its import
- **Test that must go red:** `the Stats screen holds no StatsPrimerState`
- **Command:** `gateway.sh test test/stats_primer_contract_test.dart`
- **Observed:** _pending_
- **Restore → re-run:** _pending_

### 4.3 Residue sweep (paste the raw output of each)

| # | Sweep | Command | Expected | Observed |
|---|---|---|---|---|
| a | `primer_seen_stats` outside the state file | gateway `list` / source scan | only `lib/state/stats/stats_primer_state.dart` | _pending_ |
| b | `StatsPrimerSheet(` construction sites | source scan over `lib/` | only `lib/features/stats/stats_screen.dart` and `lib/features/home/home_screen.dart` | _pending_ |
| c | Records & Trends' own empty state untouched | `gateway.sh git-diff lib/features/stats/records_and_trends_screen.dart` | empty diff; one occurrence of `Complete your first session to see stats here.` | _pending_ |
| d | no placeholders in the new files | source scan | no `TODO`, no `UnimplementedError`, no placeholder text | _pending_ |
| e | no new colour or token value | source scan | no `Color(0x`, no new token literal in either new file | _pending_ |
| f | no leftover in-screen auto-open machinery | source scan over `lib/features/stats/` | no `_primerAutoShown`, no `AnimationStatusListener`, no post-frame auto-open | _pending_ |

### 4.4 Docs guards

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart` | green; every touched doc under the 64 KiB ceiling | _pending_ |
| `gateway.sh test` (other `test/docs_*_test.dart` files the gateway `list` shows) | green | _pending_ |
| `gateway.sh git-status` on `docs/` | only the five Predicted Files; `docs/signals.md` untouched | _pending_ |

### 4.5 Phase 3A / 3B close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_contract_test.dart test/stats_primer_screen_test.dart test/stats_primer_home_test.dart test/stats_primer_state_test.dart` | green | _pending_ |
| `gateway.sh test` (full suite) | the re-measured baseline count, `All tests passed!` | _pending_ |
| `gateway.sh lint` | the re-measured baseline issue count, 0 errors | _pending_ |
| `gateway.sh git-status` | exactly the seventeen Predicted Files across all five runs; nothing deleted | _pending_ |

---

## 5. The unaffected set — one command

The 18 `StatsScreen`-pumping files and the 9 `HomeScreen`-constructing files must all stay green with
no edits. Record the observed line for each command.

| Command | Expected | Observed |
|---|---|---|
| `gateway.sh test test/header_standardization_test.dart test/records_and_trends_screen_test.dart test/stats_legacy_removal_test.dart test/screen_widget_test.dart test/fuel_row_screen_test.dart test/screen_overflow_contract_test.dart test/nutrition_trend_screen_test.dart test/mix_layer_screen_test.dart test/signals_layer_screen_test.dart` | green, no edits | `00:11 +525: All tests passed!` |
| `gateway.sh test test/nutrition_primer_test.dart test/home_logo_hub_open_test.dart` | green, no edits | deferred to Phase 2B (those files construct `HomeScreen`; nothing in 2A touches them) |
| `gateway.sh git-status` | no `test/` file outside the Predicted Files is modified | `M lib/features/stats/stats_screen.dart` only; the two untracked files are the Predicted Files |
