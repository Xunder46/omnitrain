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
| Analyze | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found.`, 0 errors | _pending_ |
| Full suite | `.github/copilot/scripts/macos/gateway.sh test` | `+3852 ~1: All tests passed!` | _pending_ |

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
| `gateway.sh test test/stats_primer_state_test.dart` (before `lib/state/stats/stats_primer_state.dart` exists) | compile failure — `Target of URI doesn't exist` / `Undefined name 'StatsPrimerState'` | _pending_ |
| `gateway.sh test test/stats_primer_state_test.dart` (after) | `All tests passed!` | _pending_ |

### 2.2 Scenario coverage

| Scenario | Test name | Mock | Hive |
|---|---|---|---|
| S-2705 | `S-2705: the seen flag survives a restart` › `a marked-seen Stats primer is seen again after a Hive restart` | _pending_ | _pending_ |
| S-2706 | `S-2706: the two primer keys are independent` › `marking the Stats primer seen leaves the Nutrition primer unseen` | _pending_ | _pending_ |
| S-2710 | `S-2710: markSeen is idempotent` › `two markSeen calls write the flag once and notify once` | _pending_ | — |
| S-2711 | `S-2711: a hydration failure falls back to unseen` › `a throwing getPreferenceBool leaves the primer unseen` | _pending_ | — |

### 2.3 Mutation records

Each record: the original line, the mutated line, the command, the observed output, and the restore.

#### Mutation A — the key is not the Nutrition key

- **File:** `lib/state/stats/stats_primer_state.dart`
- **Original:** `static const String preferenceKey = 'primer_seen_stats';`
- **Mutated:** `static const String preferenceKey = 'primer_seen_nutrition';`
- **Test that must go red:** `S-2706: the two primer keys are independent` ›
  `marking the Stats primer seen leaves the Nutrition primer unseen`
- **Command:** `gateway.sh test test/stats_primer_state_test.dart`
- **Expected red:** the assertion on `getPreferenceBool('primer_seen_nutrition') == false` fails — the
  Stats write lands on the Nutrition key.
- **Observed:** _pending_
- **Restore → re-run:** _pending_

#### Mutation B — `markSeen` really writes

- **File:** `lib/state/stats/stats_primer_state.dart`
- **Original:** `await _repository.setPreferenceBool(preferenceKey, true);`
- **Mutated:** the line deleted
- **Test that must go red:** `S-2705: the seen flag survives a restart` ›
  `a marked-seen Stats primer is seen again after a Hive restart`
- **Command:** `gateway.sh test test/stats_primer_state_test.dart`
- **Expected red:** the fresh state's `hasSeen` is `false` after the restart — the flag was never
  persisted.
- **Observed:** _pending_
- **Restore → re-run:** _pending_

### 2.4 Phase 1 close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_state_test.dart` | green | _pending_ |
| `gateway.sh lint` | baseline issue count, 0 errors | _pending_ |
| `gateway.sh git-status` | exactly the two new files | _pending_ |

---

## 3. Phase 2A — the sheet, the `showPrimerHelp` flag, the "?" and the first-use card (@developer)

### 3.1 Red run before the code

| Command | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_screen_test.dart` (before `stats_primer_sheet.dart` exists) | compile failure — `Target of URI doesn't exist` / `Undefined name 'StatsPrimerSheet'` | _pending_ |
| `gateway.sh test test/stats_primer_screen_test.dart` (after) | `All tests passed!` | _pending_ |

### 3.2 Scenario coverage

| Scenario | Test name | Result |
|---|---|---|
| S-2703 | `S-2703: with showPrimerHelp omitted the Stats primer feature is off` › `no help action, no empty-state button and the chart action still renders` | _pending_ |
| S-2704 (a) | `S-2704: the header "?" reopens the primer and never marks it` › `reopening with an unseen state leaves it unseen` | _pending_ |
| S-2704 (b) | `S-2704: the header "?" reopens the primer and never marks it` › `reopening with a seen state still opens the sheet` | _pending_ |
| S-2707 (a) | `S-2707: the first-use card explains what will appear` › `the empty state keeps its title and body and adds the explanation and the button` | _pending_ |
| S-2707 (b) | `S-2707: the first-use card explains what will appear` › `the empty-state button opens the sheet without marking it seen` | _pending_ |
| S-2708 | `S-2708: the "?" and the chart icon coexist` › `the chart icon stays the only way into Records & Trends` | _pending_ |
| S-2714 | `S-2714: the taller first-use card fits a small viewport` › `the card lays out at 320x568 without an overflow` | _pending_ |

S-2702, S-2709, S-2712 and S-2713 were dropped before approval (the auto-open is no longer in this
screen). S-2701, S-2716, S-2717 and S-2718 are covered in section 3A.

### 3.3 Existing tests: does any need an edit?

**Expected: none.** Record the observed answer per file, with the reason it is unaffected.

| File | Why it is unaffected | Green |
|---|---|---|
| `test/header_standardization_test.dart` | pumps `StatsScreen` with `showPrimerHelp` omitted; asserts the header title, the back icon and the empty-state copy — never an action count | _pending_ |
| `test/records_and_trends_screen_test.dart` | S-913 keys off `find.byTooltip('Records & Trends')`; the static scan still finds one construction site | _pending_ |
| `test/stats_legacy_removal_test.dart` | `showPrimerHelp` omitted; asserts the empty state and the legacy-title absence | _pending_ |
| `test/screen_widget_test.dart` | `showPrimerHelp` omitted; asserts the empty-state copy | _pending_ |
| `test/fuel_row_screen_test.dart` | S-1107; `showPrimerHelp` omitted | _pending_ |
| `test/screen_overflow_contract_test.dart` | seeds sessions, so the empty card is never built | _pending_ |
| `test/nutrition_trend_screen_test.dart` | exercises the zero-session empty state with `showPrimerHelp` omitted | _pending_ |
| `test/mix_layer_screen_test.dart` | `showPrimerHelp` omitted; every assertion is scoped to a `mix_*` key or the Mix layer's own copy | _pending_ |
| `test/signals_layer_screen_test.dart` | `showPrimerHelp` omitted | _pending_ |
| the remaining `StatsScreen`-pumping files (18 total) | `showPrimerHelp` omitted | _pending_ |

One command for the whole unaffected set is in section 5.

### 3.4 Mutation records

#### Mutation A — the flag really defaults to off

- **File:** `lib/features/stats/stats_screen.dart`
- **Original:** the `showPrimerHelp` constructor parameter's `= false` default
- **Mutated:** the default changed to `true`
- **Test that must go red:** `S-2703: with showPrimerHelp omitted the Stats primer feature is off` ›
  `no help action, no empty-state button and the chart action still renders`
- **Command:** `gateway.sh test test/stats_primer_screen_test.dart`
- **Expected red:** the "?" and the empty-state button render on a screen that omitted the flag
- **Observed:** _pending_
- **Restore → re-run:** _pending_

The "reopen never marks" half of S-2704 / S-2707 cannot go red in this run: the screen holds no
state, so there is nothing to mutate here. It is held by the Phase 3A guard that `StatsScreen` never
references `StatsPrimerState`, and its cross-phase mutation is 2B mutation B.

### 3.5 Phase 2A close

| Check | Expected | Observed |
|---|---|---|
| `gateway.sh test test/stats_primer_screen_test.dart test/stats_primer_state_test.dart` | green | _pending_ |
| `gateway.sh test` (full suite) | the re-measured baseline count, `All tests passed!` | _pending_ |
| `gateway.sh lint` | baseline issue count, 0 errors | _pending_ |
| `gateway.sh git-status` | exactly the three Predicted Files | _pending_ |

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
| `gateway.sh test test/header_standardization_test.dart test/records_and_trends_screen_test.dart test/stats_legacy_removal_test.dart test/screen_widget_test.dart test/fuel_row_screen_test.dart test/screen_overflow_contract_test.dart test/nutrition_trend_screen_test.dart test/mix_layer_screen_test.dart test/signals_layer_screen_test.dart` | green, no edits | _pending_ |
| `gateway.sh test test/nutrition_primer_test.dart test/home_logo_hub_open_test.dart` | green, no edits | _pending_ |
| `gateway.sh git-status` | no `test/` file outside the Predicted Files is modified | _pending_ |
