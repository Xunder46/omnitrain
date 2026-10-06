# Evidence — Stats PR 10a: signals test isolation

Companion to `2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.md`. Evidence only. Review
findings go in `2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.review.md`; neither goes into the
plan.

---

## 1. Baselines

| Check | Command | Expected | Observed |
|---|---|---|---|
| Analyze | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found.`, 0 errors | `196 issues found. (ran in 3.2s)`, 0 errors — matches |
| Full suite | `.github/copilot/scripts/macos/gateway.sh test` | `+3852 ~1: All tests passed!` | `01:48 +3852 ~1: All tests passed!` — matches |
| Interference file, pre-change | `gateway.sh test test/interference_signal_screen_test.dart` | green, two quiet-line assertions absent from the file | green as part of the baseline full run (`+3852 ~1`); pre-change file read confirms neither `S-2013 the card is dismissible` frame carries a `signals_quiet_line` assertion (only the `S-2013 the card on the layer` test has one, asserting `findsNothing`) |

One pre-existing timing-sensitive test may fail once in a full run. If it does: re-run once, and record
**both** summary lines here rather than only the green one.

---

## 2. Pre-recorded originals (copy these here before mutating)

Every mutation in step 2(e), 9(a) and 9(b) replaces a line that already exists. The line as it stands
before the mutation goes here first.

### M-(c) — `test/interference_signal_screen_test.dart`

Injected line inside `pumpStats`, in the `StatsScreen(...)` construction:

```
              signals: const [InterferenceSignal()],
```

Mutation: this line → `signals: null`.

Fallback mutation (used only if the above does not go red): this line → `signals: const []`.

### M-(a) — `test/progression_rate_signal_screen_test.dart`

Injected line inside `pumpStats`, in the `StatsScreen(...)` construction:

```
              signals: const [ProgressionRateSignal()],
```

Mutation: this line → `signals: const []`.

### M-(b) — `test/protein_consistency_signal_screen_test.dart`

The first call in `S-2215 two cautions qualifying`, under the opening
`'renders the higher-priority caution above the protein card', (tester) async {`:

```
            await pumpStats(
              tester,
              signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()],
            );
```

Mutation: this call → `await pumpStats(tester);` (i.e. fall back to the injected default).

> The plan wrote this original as `await pumpStats(tester, signals: null);`. Under the governor
> override (see the Assumption Log) no call site passes `null`; the explicit neighbour list replaces
> it, and the mutation still falls back to the injected default — so the mutation is unchanged.

---

## 3. Mutation records

Each record: the original line, the mutated line, the command, the observed output, and the restore.

### Mutation (a) — the injected list, not the registry, decides what renders

- **File:** `test/progression_rate_signal_screen_test.dart`
- **Test that must go red:** `S-1801 the card, end to end`
- **Command:** `gateway.sh test test/progression_rate_signal_screen_test.dart`
- **Expected red:** the `_cardKeys()` assertion fails with
  `Expected: ['signal_card_progression-rate']` and `Actual: []`.
- **Observed:** RED. `signals: const [ProgressionRateSignal()],` → `signals: const [],` and the file
  went to `+0 -5: Some tests failed.` — five failures, each `Expected: ['signal_card_progression-rate']`
  / `Actual: []` on the `_cardKeys()` assertion: Mock `S-1801 the card, end to end`, Mock `S-1812 the
  card disappears when the condition clears`, Mock `S-1813 the real card is dismissible`, and the same
  `S-1801` and `S-1812` under Hive. Nothing else in the file failed.
- **Restore → re-run:** line restored to `signals: const [ProgressionRateSignal()],`; re-run green —
  `test/progression_rate_signal_screen_test.dart` + `test/protein_consistency_signal_screen_test.dart`
  together `+21: All tests passed!` (5 + 16).

- **File:** `test/protein_consistency_signal_screen_test.dart`
- **Test that must go red:** `S-2215 two cautions qualifying` › `renders the higher-priority caution above the protein card`
- **Command:** `gateway.sh test test/protein_consistency_signal_screen_test.dart`
- **Expected red:** fails on `expect(fuel, findsOneWidget)` — with only Protein injected, the Fuel card
  is absent.
- **Observed:** RED. The explicit list → `await pumpStats(tester);` (injected default: Protein only)
  and the file went to `+14 -2: Some tests failed.` — the two failures are exactly the `S-2215 two
  cautions qualifying` › `renders the higher-priority caution above the protein card` test, once under
  Mock and once under Hive, each failing at `expect(fuel, findsOneWidget)` with
  `Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'signal_card_fuel-vs-load'>]: []>` /
  `Which: means none were found but one was expected`.
- **Restore → re-run:** call restored to the explicit
  `signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()]`; re-run green —
  `test/progression_rate_signal_screen_test.dart` + `test/protein_consistency_signal_screen_test.dart`
  together `+21: All tests passed!` (5 + 16).

### Mutation (c) — the two restored assertions need Interference to run alone

- **File:** `test/interference_signal_screen_test.dart`
- **Test that must go red:** `S-2013 the card is dismissible`
- **Command:** `gateway.sh test test/interference_signal_screen_test.dart`
- **Expected red:** fails on `expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget)` —
  a second registered signal also qualifies on this fixture, which is exactly why PR 9a dropped these
  two lines.
- **Observed:** RED at `test/interference_signal_screen_test.dart:502` — the tap-frame
  `expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);` failed with
  `Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'signals_quiet_line'>]: []>`, i.e. a second
  registered signal also qualified on F-INT and kept the layer non-quiet. This is exactly why PR 9a
  dropped the two lines.
- **Restore → re-run:** line restored to `signals: const [InterferenceSignal()],`; re-run green,
  `+5: All tests passed!`

---

## 4. Change inventory (verify after Phase 1)

Every entry is an edit inside a test file. No `lib/` file, no doc outside this folder, and none of the
nine non-signal test files is edited.

| File | Import added | `pumpStats` / `reopen` change | Scenarios given an explicit list |
|---|---|---|---|
| `interference_signal_screen_test.dart` | `signals/interference_signal.dart` | hard-coded `signals: const [InterferenceSignal()],` | none — the default covers every scenario |
| `fuel_vs_load_signal_screen_test.dart` | none (already present) | hard-coded `signals: const [FuelVsLoadSignal()],` | none — the default covers every scenario |
| `progression_rate_signal_screen_test.dart` | `signals/progression_rate_signal.dart` | hard-coded `signals: const [ProgressionRateSignal()],` | none — the default covers every scenario |
| `modality_mix_shift_signal_screen_test.dart` | none (already present) | hard-coded `signals: const [ModalityMixShiftSignal()],` | none — the default covers every scenario |
| `protein_consistency_signal_screen_test.dart` | `signals/fuel_vs_load_signal.dart` (neighbour, for the override) | `List<Signal>? signals = const [ProteinConsistencySignal()],` + `signals: signals,`; `reopen` forwards it | `S-2216 the card on the layer`; `S-2215 two cautions qualifying` (both tests and the Mock-only `reopen`) — each `const [ProteinConsistencySignal(), FuelVsLoadSignal()]` |
| `sustained_high_load_signal_screen_test.dart` | `signals/protein_consistency_signal.dart` (neighbour, for the override), `signals/signal.dart`, `signals/sustained_high_load_signal.dart` | `List<Signal>? signals = const [SustainedHighLoadSignal()],` + `signals: signals,`; `reopen` forwards it | `S-2412 the card on the layer`; `S-2412 two cautions qualifying` — each `const [SustainedHighLoadSignal(), ProteinConsistencySignal()]` |
| `cardio_efficiency_drift_signal_screen_test.dart` | `signals/sustained_high_load_signal.dart` (neighbour, for the override) | `List<Signal>? signals = const [CardioEfficiencyDriftSignal()],` + `signals: signals,`; `reopen` forwards it | `S-2501 the card on the layer`; `S-2509 the lifting sentence`; `S-2511 two cautions qualifying` — each `const [CardioEfficiencyDriftSignal(), SustainedHighLoadSignal()]` |

### Assertions restored

`test/interference_signal_screen_test.dart` › `S-2013 the card is dismissible` — two occurrences of:

```
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
```

One directly after the tap-frame `expect(find.byKey(const Key(_kCardKey)), findsNothing);`, one directly
after the reopen's `expect(find.byKey(const Key(_kCardKey)), findsNothing);`.

### Invariants to confirm

- No test count changes anywhere: full suite stays at the baseline count.
- No test is added, removed or renamed.
- The two registry guards are unedited: `test/interference_test.dart` ›
  `the caution order holds and the registry is ordered by it`;
  `test/modality_mix_shift_signal_screen_test.dart` › `the registry` ›
  `lists exactly the seven shipped signals, in order`.
- The nine non-signal files are unedited (see section 5).
- The scoped label check in the Interference dismissal test is unchanged.

---

## 5. The nine non-signal files (run unedited)

| File | Why no edit | Green |
|---|---|---|
| `screen_overflow_contract_test.dart` | its seed writes three unrated sessions, so `signalsGateMet` is false and no signals layer renders | green, unedited |
| `header_standardization_test.dart` | asserts only the header and the back icon | green, unedited |
| `nutrition_trend_screen_test.dart` | exercises the zero-session empty state | green, unedited |
| `fuel_row_screen_test.dart` | no fixture stores a rating, so no rated baseline week and the gate is unmet | green, unedited |
| `instrument_list_screen_test.dart` | no fixture stores a rating | green, unedited |
| `records_and_trends_screen_test.dart` | no fixture stores a rating | green, unedited |
| `stats_legacy_removal_test.dart` | no fixture stores a rating | green, unedited |
| `entry_identity_summary_test.dart` | no fixture stores a rating | green, unedited |
| `mix_layer_screen_test.dart` | the gate is met, but every assertion is scoped to a `mix_*` key, the Mix layer's own copy, or the absence of legacy titles; the card renders below the Mix layer and the suite is green today with all seven signals registered | green, unedited |

One command, run unedited — `+277: All tests passed!`:

```
gateway.sh test test/mix_layer_screen_test.dart test/screen_overflow_contract_test.dart test/fuel_row_screen_test.dart test/instrument_list_screen_test.dart test/records_and_trends_screen_test.dart test/stats_legacy_removal_test.dart test/header_standardization_test.dart test/nutrition_trend_screen_test.dart test/entry_identity_summary_test.dart
```

`gateway.sh git-status` afterwards lists only the seven signal files plus this plan folder — none of the
nine appears, so all nine are unedited.

---

## 6. Close

| Check | Expected | Observed |
|---|---|---|
| Signal surface, one command | green | `+155: All tests passed!` — the nine-file command below (the seven signal files + both registry-guard files + `test/signals_layer_screen_test.dart`) |
| `test/signals_layer_screen_test.dart` | green | green inside that `+155` run (`Signals layer — Hive Structural guard …`) |
| Full suite | `+3852 ~1: All tests passed!` — same count as the baseline | `01:44 +3852 ~1: All tests passed!` — identical to the baseline, so no test was added, removed or renamed |
| `gateway.sh lint` | `196 issues found.`, 0 errors | `196 issues found. (ran in 3.0s)`, `error •` count `0` — identical to the baseline |
| `gateway.sh git-status` | exactly the seven test files modified, nothing else | exactly the seven test files plus this plan folder (the plan `.md` and this `.evidence.md`); the only other entry is the untracked `2026-10-04-10b-…` plan folder, which predates this work. Nothing staged, no commit, no push |

Footprint per file (`gateway.sh git-diff --stat`):

```
 ...stats-pr10a-signal-test-isolation-plan.evidence.md | 17 ++++++-----
 ...cardio_efficiency_drift_signal_screen_test.dart    | 34 ++++++++++++++++++----
 test/fuel_vs_load_signal_screen_test.dart             |  1 +
 test/interference_signal_screen_test.dart             |  4 +++
 test/modality_mix_shift_signal_screen_test.dart       |  1 +
 test/progression_rate_signal_screen_test.dart         |  2 ++
 test/protein_consistency_signal_screen_test.dart      | 30 +++++++++++++++----
 test/sustained_high_load_signal_screen_test.dart      | 22 +++++++++++---
```

Per-file green counts after the edits: interference `+5`, fuel_vs_load `+9`, progression_rate `+5`,
modality_mix_shift `+10`, protein_consistency `+16`, sustained_high_load `+13`, cardio `+17`.
