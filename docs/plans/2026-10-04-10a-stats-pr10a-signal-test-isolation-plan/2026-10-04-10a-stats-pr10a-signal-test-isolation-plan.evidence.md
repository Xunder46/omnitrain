# Evidence — Stats PR 10a: signals test isolation

Companion to `2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.md`. Evidence only. Review
findings go in `2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.review.md`; neither goes into the
plan.

---

## 1. Baselines

| Check | Command | Expected | Observed |
|---|---|---|---|
| Analyze | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found.`, 0 errors | _pending_ |
| Full suite | `.github/copilot/scripts/macos/gateway.sh test` | `+3852 ~1: All tests passed!` | _pending_ |
| Interference file, pre-change | `gateway.sh test test/interference_signal_screen_test.dart` | green, two quiet-line assertions absent from the file | _pending_ |

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
              await pumpStats(tester, signals: null);
```

Mutation: this line → `await pumpStats(tester);` (i.e. fall back to the injected default).

---

## 3. Mutation records

Each record: the original line, the mutated line, the command, the observed output, and the restore.

### Mutation (a) — the injected list, not the registry, decides what renders

- **File:** `test/progression_rate_signal_screen_test.dart`
- **Test that must go red:** `S-1801 the card, end to end`
- **Command:** `gateway.sh test test/progression_rate_signal_screen_test.dart`
- **Expected red:** the `_cardKeys()` assertion fails with
  `Expected: ['signal_card_progression-rate']` and `Actual: []`.
- **Observed:** _pending_
- **Restore → re-run:** _pending_

### Mutation (b) — the two-caution group really reads the registry

- **File:** `test/protein_consistency_signal_screen_test.dart`
- **Test that must go red:** `S-2215 two cautions qualifying` › `renders the higher-priority caution above the protein card`
- **Command:** `gateway.sh test test/protein_consistency_signal_screen_test.dart`
- **Expected red:** fails on `expect(fuel, findsOneWidget)` — with only Protein injected, the Fuel card
  is absent.
- **Observed:** _pending_
- **Restore → re-run:** _pending_

### Mutation (c) — the two restored assertions need Interference to run alone

- **File:** `test/interference_signal_screen_test.dart`
- **Test that must go red:** `S-2013 the card is dismissible`
- **Command:** `gateway.sh test test/interference_signal_screen_test.dart`
- **Expected red:** fails on `expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget)` —
  a second registered signal also qualifies on this fixture, which is exactly why PR 9a dropped these
  two lines.
- **Observed:** _pending_
- **Restore → re-run:** _pending_
- **If not red:** record the observed output, apply the fallback mutation in section 2, record it, and
  log the observation as a finding. Do not treat it as a failure of the plan.

---

## 4. Change inventory (verify after Phase 1)

Every entry is an edit inside a test file. No `lib/` file, no doc outside this folder, and none of the
nine non-signal test files is edited.

| File | Import added | `pumpStats` / `reopen` change | Scenarios opted back to the registry |
|---|---|---|---|
| `interference_signal_screen_test.dart` | `signals/interference_signal.dart` | hard-coded `signals: const [InterferenceSignal()],` | none |
| `fuel_vs_load_signal_screen_test.dart` | none (already present) | hard-coded `signals: const [FuelVsLoadSignal()],` | none |
| `progression_rate_signal_screen_test.dart` | `signals/progression_rate_signal.dart` | hard-coded `signals: const [ProgressionRateSignal()],` | none |
| `modality_mix_shift_signal_screen_test.dart` | none (already present) | hard-coded `signals: const [ModalityMixShiftSignal()],` | none |
| `protein_consistency_signal_screen_test.dart` | none (already present) | `List<Signal>? signals = const [ProteinConsistencySignal()],` + `signals: signals,`; `reopen` forwards it | `S-2216 the card on the layer`; `S-2215 two cautions qualifying` (both tests and the Mock-only `reopen`) |
| `sustained_high_load_signal_screen_test.dart` | `signals/signal.dart`, `signals/sustained_high_load_signal.dart` | `List<Signal>? signals = const [SustainedHighLoadSignal()],` + `signals: signals,`; `reopen` forwards it | `S-2412 the card on the layer`; `S-2412 two cautions qualifying` |
| `cardio_efficiency_drift_signal_screen_test.dart` | none (already present) | `List<Signal>? signals = const [CardioEfficiencyDriftSignal()],` + `signals: signals,`; `reopen` forwards it | `S-2501 the card on the layer`; `S-2509 the lifting sentence`; `S-2511 two cautions qualifying` |

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
| `screen_overflow_contract_test.dart` | its seed writes three unrated sessions, so `signalsGateMet` is false and no signals layer renders | _pending_ |
| `header_standardization_test.dart` | asserts only the header and the back icon | _pending_ |
| `nutrition_trend_screen_test.dart` | exercises the zero-session empty state | _pending_ |
| `fuel_row_screen_test.dart` | no fixture stores a rating, so no rated baseline week and the gate is unmet | _pending_ |
| `instrument_list_screen_test.dart` | no fixture stores a rating | _pending_ |
| `records_and_trends_screen_test.dart` | no fixture stores a rating | _pending_ |
| `stats_legacy_removal_test.dart` | no fixture stores a rating | _pending_ |
| `entry_identity_summary_test.dart` | no fixture stores a rating | _pending_ |
| `mix_layer_screen_test.dart` | the gate is met, but every assertion is scoped to a `mix_*` key, the Mix layer's own copy, or the absence of legacy titles; the card renders below the Mix layer and the suite is green today with all seven signals registered | _pending_ |

One command:

```
gateway.sh test test/mix_layer_screen_test.dart test/screen_overflow_contract_test.dart test/fuel_row_screen_test.dart test/instrument_list_screen_test.dart test/records_and_trends_screen_test.dart test/stats_legacy_removal_test.dart test/header_standardization_test.dart test/nutrition_trend_screen_test.dart test/entry_identity_summary_test.dart
```

---

## 6. Close

| Check | Expected | Observed |
|---|---|---|
| Signal surface, one command | green | _pending_ |
| `test/signals_layer_screen_test.dart` | green | _pending_ |
| Full suite | `+3852 ~1: All tests passed!` — same count as the baseline | _pending_ |
| `gateway.sh lint` | `196 issues found.`, 0 errors | _pending_ |
| `gateway.sh git-status` | exactly the seven test files modified, nothing else | _pending_ |
