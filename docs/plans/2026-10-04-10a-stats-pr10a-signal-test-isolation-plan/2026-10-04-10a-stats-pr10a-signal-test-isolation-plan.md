# Feature: Signals test isolation — every per-signal screen test injects its own signal (Stats PR 10a)

> **Status:** DONE: `c4bdd7c` (the isolation) and `9b5cc25` (comment-only follow-up).
> **Next handoff:** none. This plan has no data-layer phase: it changes test files only.
> **Note:** scenarios that need a neighbouring card use an explicit two-signal list (governor override A-1).
> **Source of scope:** `.work/stats-pr10/brief-plan-10a.md`.
> **Base:** `develop` after Stats PR 9 (seven signals registered in `buildSignalRegistry()`).
> **Binding conventions:** `docs/global_conventions.md`. Read before Phase 1: `docs/signals.md`,
> `docs/stats_screen.md`, `docs/modality_based_exercise_ui.md` (the Signals layer section),
> `docs/design_system.md` (only if a card's copy is touched — it is not).
> **Evidence:** `2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.evidence.md` (this folder).
> Review findings: `.review.md`. Neither is written into this file.
> **Budget:** `.github/agents/pr_scope_budget.md`.

## Scope (one paragraph)

`StatsScreen` already takes an optional `signals:` argument and hands it to `SignalsService`
(`signals ?? buildSignalRegistry()`), so a test can decide exactly which signals the screen
evaluates. Today every per-signal screen test passes no argument and therefore evaluates the whole
registry, so a fixture built to make one signal fire can also make another fire — which is what broke
when Sustained High Load was registered. This PR is a test-only change: each per-signal screen
scenario passes `signals: const [ItsOwnSignal()]` so its assertions hold however many signals ship
later; the scenarios whose subject *is* the interaction (the two-caution groups, and the scenarios
that assert a named neighbour's card is absent) keep the real registry; and the two quiet-line
assertions that PR 9a had to drop in the Interference dismissal test come back, because Interference
now runs alone there. No production code changes, no new tests, no renames, no doc edits.

## Why this is worth doing

The failure mode is observed, not hypothetical. Registering a seventh signal turned three already-green
PR 7b tests red (two cards where one was expected) and forced PR 9a to weaken an assertion set rather
than fix it: `S-2013 the card is dismissible` lost the two lines that prove the layer goes quiet once
the only card is dismissed, because on that fixture a second signal also qualified. Both symptoms have
the same cause — a screen test that reads the whole registry when it means to test one signal.

## Out of scope

- Any change to `lib/` — the seam, `SignalsService`, `resolveSignals`, the registry, the card cap, the
  priority rule and the dismissal store are all frozen for this PR.
- The two registry guards (`test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`):
  they call `buildSignalRegistry()` directly and stay on the real registry.
- The service-level, rule-level and adapter-level tests in the seven signal files, and
  `test/signals_layer_screen_test.dart` (the seam's own file, already isolated by stub signals).
- Renaming any test. Every changed file keeps its test count and its test names.
- Any doc edit. See D-1909.

## Findings from research

- **F-1 — the seam is already exercised.** `test/signals_layer_screen_test.dart` passes
  `signals:` with stub signals in every scenario, so the argument is proven to reach the screen. Nothing
  in this PR invents a mechanism.
- **F-2 — the per-signal files differ, and the difference matters.** Four of the seven reference only
  their own card key (`interference`, `fuel_vs_load`, `progression_rate`, `modality_mix_shift`); every
  screen scenario in them is single-signal. Three reference a second signal's card key
  (`protein_consistency`, `sustained_high_load`, `cardio_efficiency_drift`) — both in their two-caution
  group **and** in a scenario whose stated point is that the neighbour abstains on that fixture
  ("… so no other signal can qualify: this fixture isolates the card"). Those absence assertions are
  interaction claims; injecting one signal would make them vacuous.
- **F-3 — the three dismissal tests that assert the quiet line are already single-signal in intent.**
  `S-2216`, `S-2412` and `S-2511` "the card is dismissible" each assert `signals_quiet_line`
  `findsOneWidget` after the tap and again after a reopen. They pass today only because their fixtures
  happen to leave every other signal abstaining. Injection makes that a property of the test instead of
  a property of the fixture.
- **F-4 — nothing under `docs/` cites a name this PR changes.** `docs/signals.md` and
  `docs/stats_screen.md` cite `S-2013`, `S-2215`, `S-2412` and `S-2511` group names, plus the full name
  of the *protein* dismissal test (`… the next open is still quiet`), which is untouched. No doc cites
  the Interference dismissal test's current name, so it is left as it is (D-1905).
- **F-5 — `docs/plans/` is a record folder.** `test/docs_indexing_contract_test.dart` exempts it from
  the size ceiling, the link checks and the content guards, so this plan and its evidence file cannot
  break that suite.
- **F-6 — the nine other `StatsScreen(` tests.** Eight of them never satisfy the Signals gate at all
  (`signalsGateMet` needs `ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks`, and their fixtures carry
  no rated weeks), so no signals layer renders in them. The ninth, `mix_layer_screen_test.dart`, does
  meet the gate, and its assertions are all scoped to `mix_*` keys, the Mix layer's own copy, or the
  absence of legacy titles; its only whole-screen assertions are `takeException()` and an overflow
  sweep. See the second table for the per-file verdict.

## Scenario classification — which scenarios inject, which keep the real registry

Rule: a scenario keeps the real registry **only** when one of its own assertions names a second
signal's card key. Everything else injects its own signal. No group's assertions change.

### The seven per-signal screen files

| File | Scenario group | `signals:` | Why |
|---|---|---|---|
| `interference_signal_screen_test.dart` | all screen groups (`S-2013 the card on the layer`, `S-2013 the card is dismissible`) | `const [InterferenceSignal()]` | no scenario names another card key |
| `fuel_vs_load_signal_screen_test.dart` | all screen groups | `const [FuelVsLoadSignal()]` | ditto |
| `progression_rate_signal_screen_test.dart` | all screen groups (`S-1801`, `S-1812`, `S-1813`) | `const [ProgressionRateSignal()]` | ditto; `_cardKeys()` asserts the exact list |
| `modality_mix_shift_signal_screen_test.dart` | all in-harness screen groups | `const [ModalityMixShiftSignal()]` | ditto; the out-of-loop `the registry` guard never pumps the screen |
| `protein_consistency_signal_screen_test.dart` | `S-2216 the card on the layer` | real registry (`signals: null`) | asserts `signal_card_fuel-vs-load` **absent** |
| " | `S-2215 two cautions qualifying` (both tests, incl. the Mock-only dismissal and its reopen) | real registry (`signals: null`) | asserts the Fuel card present and orders the two cards against each other |
| " | `S-2216 the card is dismissible`; `S-2206 the own-baseline card`; `S-2207 with no bodyweight`; `the rule abstains` (both cases) | `const [ProteinConsistencySignal()]` | no second-signal reference |
| `sustained_high_load_signal_screen_test.dart` | `S-2412 the card on the layer` | real registry (`signals: null`) | asserts `signal_card_protein-consistency` **absent** |
| " | `S-2412 two cautions qualifying` | real registry (`signals: null`) | interaction |
| " | `S-2412 the card is dismissible`; `S-2410(b) the streak period measures time`; `the rule abstains` (both cases) | `const [SustainedHighLoadSignal()]` | no second-signal reference |
| `cardio_efficiency_drift_signal_screen_test.dart` | `S-2501 the card on the layer` | real registry (`signals: null`) | asserts `signal_card_sustained-high-load` **absent** |
| " | `S-2509 the lifting sentence` | real registry (`signals: null`) | asserts `signal_card_sustained-high-load` **absent** |
| " | `S-2511 two cautions qualifying` | real registry (`signals: null`) | interaction |
| " | `S-2511 the card is dismissible`; `the rule abstains` (both cases) | `const [CardioEfficiencyDriftSignal()]` | no second-signal reference |

The three files in the middle of that table therefore need `pumpStats` and `reopen` to take an optional
`List<Signal>? signals` whose default is their own signal, so a group can opt back into the registry
with `signals: null`. The four files at the top do not: their `pumpStats` hard-codes its own list
(D-1902).

### The nine `StatsScreen(` tests that never pass `signals:`

| File | Signals gate | Verdict |
|---|---|---|
| `screen_overflow_contract_test.dart` | unmet — its `seed` writes three **unrated** sessions | unaffected — leave |
| `header_standardization_test.dart` | n/a — asserts only `OmniBackHeader` and the back icon | unaffected — leave |
| `nutrition_trend_screen_test.dart` | unmet — the zero-session empty state | unaffected — leave |
| `fuel_row_screen_test.dart` | unmet — no fixture stores a rating, so `ratedBaselineWeeks` is 0 | unaffected — leave |
| `instrument_list_screen_test.dart` | unmet — no fixture stores a rating | unaffected — leave |
| `records_and_trends_screen_test.dart` | unmet — no fixture stores a rating | unaffected — leave |
| `stats_legacy_removal_test.dart` | unmet — no fixture stores a rating | unaffected — leave |
| `entry_identity_summary_test.dart` | unmet — no fixture stores a rating | unaffected — leave |
| `mix_layer_screen_test.dart` | **met** — its fixtures seed a rated baseline | unaffected — leave. Every assertion is scoped to a `mix_*` key, the Mix layer's own copy (`TRAINING MIX`, `usual`), or the absence of legacy titles; a signal card renders *below* the Mix layer, so no Mix geometry moves. The two whole-screen assertions are `takeException()` and the S-1615 overflow sweep, and the card's own overflow safety at the narrowest viewport and the largest text scale is pinned in `test/signals_layer_screen_test.dart`. The suite is green today with all seven signals registered, so no card currently renders on these fixtures |

No file in either table is edited except the seven in the first one.

## Decision Ledger

**D-1901 — The seam is the only mechanism.** Every per-signal screen scenario passes `signals:`
explicitly. No new test helper, no stub signal, no change to `SignalsService` or `StatsScreen`. The
argument already exists and is already proven by `test/signals_layer_screen_test.dart`.

**D-1902 — The four single-signal files hard-code their list.** In `interference`,
`fuel_vs_load`, `progression_rate` and `modality_mix_shift`, `pumpStats` passes
`signals: const [XSignal()]` at its one `StatsScreen(...)` construction site. No new parameter, no
`Signal` import: the list literal's type comes from the parameter's declared type. Options considered:
adding the optional parameter to all seven files for uniformity. Rejected — it is four extra edits per
file for a switch no scenario in those files uses.

**D-1903 — The three mixed files get the parameter and forward it.** `pumpStats` gains
`List<Signal>? signals = const [XSignal()],` after `Size size = _kTallViewport,`, passes `signals:
signals` to `StatsScreen`, and `reopen` gains the same parameter and forwards it. An explicit `null`
argument overrides the default in Dart, so `signals: null` means "the real registry" at the call site.

**D-1904 — Which scenarios keep the real registry.** Only those whose own assertions name a second
signal's card key, plus the two registry guards (which never pump the screen). The rule is mechanical
and is applied in the classification table above; it is the reason the three "isolates the card"
scenarios are *not* injected even though they are single-card scenarios.

**D-1905 — The Interference dismissal test keeps its name.** It currently reads `… and the next open
still hides it`; the other six read `… and the next open is still quiet`. The plan restores the two
dropped assertions and leaves the name alone: no doc cites it (`docs/stats_screen.md` cites the
Interference test only by its `S-2013` group name), and a rename is a change with no behavioural
consequence. The uniform wording is noted as a possible future tidy-up, not part of this PR.

**D-1906 — The scoped label check stays as it is.** `find.descendant(of: find.byKey(const Key(_kCardKey)),
matching: find.text(_kCautionLabel))` is harmless once Interference runs alone and is left untouched.

**D-1907 — The nine non-signal files are not edited.** Their verdicts and the evidence for each are in
the second table. A file is given `signals: const []` only if an extra card could change one of its
assertions; none can.

**D-1908 — No test is added, removed or renamed.** Every file keeps its test count and its test names.
The two restored assertions live inside the existing `S-2013 the card is dismissible` test.

**D-1909 — No documentation changes.** `docs/signals.md` and `docs/stats_screen.md` cite the `S-2013`,
`S-2215`, `S-2412` and `S-2511` group names and the protein dismissal test's full name — all four
survive unchanged. A doc that cites a name still cites an existing name.

**D-1910 — Proof is three mutations, and each is stated with what it does and does not show.** (a) one
mutation in a single-signal file shows the injected list, not the registry, decides what renders; (b) one
mutation in a mixed file shows the two-caution group really does read the registry; (c) the
Interference red→green shows the two restored assertions are valid exactly when the signal runs alone.
No claim is made that (a) or (b) reproduces a cross-signal interference.

**D-1911 — Injections are `const` lists of `const` constructors**, so no test gains a runtime cost and
no `Signal` import is added where the list literal's type is inferred from the parameter.

**D-1912 — The opt-in is `signals: null`, not an explicit multi-signal list.** The brief permits "the
real registry (or a stated explicit list)". `null` is chosen because the registry is the thing those
scenarios test: an explicit list would freeze the two-caution scenarios to today's seven signals and
would hide a future signal that changes their ordering.

## Scenarios

Behaviour is asserted in four places, one per file class. Each names the test that carries it.

### S-2601: the Interference card is dismissed and the layer goes quiet

- **Fixture:** `_seedFInt` — the history the Interference rule fires on, with the Mix gate met.
- **Trigger:** the existing `S-2013 the card is dismissible` test: open the screen, tap the card's
  dismiss control, settle the store, reopen.
- **Expected outcome:** the card is present on the first open; in the frame after the tap the card is
  gone **and `signals_quiet_line` is on screen**; the store holds `cross-modality-interference` with an
  integer timestamp; after the reopen the card is gone **and `signals_quiet_line` is on screen again**.
  The two bolded assertions are the lines PR 9a dropped and this PR restores.
- **Carried by:** `test/interference_signal_screen_test.dart` › `S-2013 the card is dismissible`.
- **Edge case of:** none.

### S-2602: the injected list, not the registry, decides what renders (single-signal files)

- **Fixture:** any of the four single-signal files' own card fixture.
- **Trigger:** open the screen with `signals: const [XSignal()]`.
- **Expected outcome:** exactly the own card renders — `_cardKeys()` is `['signal_card_<id>']` where the
  file asserts the list, `signal_card_<id>` is `findsOneWidget` where it asserts the key, and no other
  signal's card can appear because no other signal is evaluated. A temporary mutation that changes the
  injected list changes what renders; the registry does not.
- **Carried by:** `test/progression_rate_signal_screen_test.dart` › `S-1801 the card, end to end`
  (`_cardKeys()`), and the equivalent scenario in each of the four files.
- **Edge case of:** none.

### S-2603: the interaction scenarios still read the real registry (mixed files)

- **Fixture:** the mixed files' two-caution fixtures (`_seedFMerged`, `_seedFTwo`) and the fixtures
  whose isolation claim names a neighbour (`_seedFProt`, `_seedFCard`, `_seedFLift`).
- **Trigger:** open the screen with `signals: null` in those groups and with the injected default
  everywhere else in the same file.
- **Expected outcome:** the two-caution groups render both cards and order them as they do today; the
  isolation scenarios still show their own card and still show the named neighbour's card absent; the
  file's other scenarios show only their own card and go quiet on dismissal.
- **Carried by:** `S-2215 two cautions qualifying` (protein), `S-2412 the card on the layer` and
  `S-2412 two cautions qualifying` (sustained), `S-2501 the card on the layer`, `S-2509 the lifting
  sentence` and `S-2511 two cautions qualifying` (cardio).
- **Edge case of:** none.

### S-2604: the nine non-signal screen tests are unchanged and still pass

- **Fixture:** each of the nine files' existing fixtures.
- **Trigger:** run the nine files unedited.
- **Expected outcome:** every test passes with the same counts as before this PR; in the eight whose
  fixtures store no rated week, no signals layer renders at all; in `mix_layer_screen_test.dart` the Mix
  layer renders as before and no assertion reads a signal card.
- **Carried by:** the nine files, unedited.
- **Edge case of:** none.

## Iteration 1

### Executor block (applies to the whole plan)

- **Branch:** work on `develop`. Never create a branch, never commit, never stage, never push — the owner
  commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <file paths>|pub-get|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell — use the gateway's `git-*`
  verbs and your file tools. A denied command is never retried. A gateway `test` command over 3 minutes
  is a hang: stop and report it.
- **Formatting:** run the gateway's `format` verb **only on files you created**; it refuses tracked
  files, and the repository is not format-clean, so no existing test file is ever formatted.
- **No scratch files.** Mutations are applied to the test file itself and reverted; nothing is written
  outside `docs/plans/2026-10-04-10a-stats-pr10a-signal-test-isolation-plan/`.
- **Red first:** the two restored assertions are written and then shown to fail (step 2's mutation)
  before they are shown to pass.
- **Mutations:** every mutation is one line, is applied to a file that already exists, is run against a
  named test, and is recorded in `.evidence.md` with the original line copied there first. Restore the
  file, re-run to confirm green, and never end a step with a mutation applied.
- **No real-clock thresholds.** Nothing in this PR asserts on a wall-clock duration or a real `now`
  window; the fixtures already own their own time anchors.
- **Step budget:** at most 8–10 steps. Read at most ~100 lines of a file at a time.
- **Evidence:** the baselines, the per-file suite summaries, the red→green pairs and the three mutation
  records go to
  `docs/plans/2026-10-04-10a-stats-pr10a-signal-test-isolation-plan/2026-10-04-10a-stats-pr10a-signal-test-isolation-plan.evidence.md`.
  Never into this plan. Findings go to `...review.md`.
- **Ambiguity:** never stop. Pick the option most consistent with the Ledger, log it in the Assumption
  Log (decision, options considered, rationale) and continue.
- **Baselines (stated by the brief):** `flutter analyze` → `196 issues found.` with 0 errors;
  full `flutter test` → `+3852 ~1: All tests passed!`. One pre-existing timing-sensitive test may fail
  once in a full run: re-run once and record both lines.

### Phase 1: inject per file, restore the two lines, prove it (@developer)

1. [ ] **Baseline.** Record in `.evidence.md`: `flutter analyze` (expect `196 issues found.`, 0 errors)
   and the full-suite summary line (expect `+3852 ~1: All tests passed!`). Then record the pre-change
   state of the Interference dismissal test by running
   `flutter test test/interference_signal_screen_test.dart` — green, and the two quiet-line assertions
   are absent from the file.

2. [ ] **`test/interference_signal_screen_test.dart`** — the restore, and the red-first proof.
   (a) Add `import 'package:omnitrain/core/services/signals/interference_signal.dart';` immediately
   after the existing `import 'package:omnitrain/core/models/signals.dart';`. Do **not** add a
   `signal.dart` import: no declaration in this file needs the `Signal` type.
   (b) In `pumpStats`, the `StatsScreen(...)` construction gains one line, so it reads:
   ```
            home: StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              signals: const [InterferenceSignal()],
            ),
   ```
   (c) In `S-2013 the card is dismissible`, restore the two dropped assertions verbatim — one directly
   after the tap-frame `expect(find.byKey(const Key(_kCardKey)), findsNothing);`, and one directly after
   the reopen's `expect(find.byKey(const Key(_kCardKey)), findsNothing);`:
   ```
            expect(find.byKey(const Key('signals_quiet_line')), findsOneWidget);
   ```
   Nothing else in the test changes — not its name, not the scoped label check.
   (d) Run `flutter test test/interference_signal_screen_test.dart` → green. Record the count.
   (e) **Mutation (c), the red-first proof.** Copy the injected list line into `.evidence.md`, then
   temporarily change it to `signals: null` — the pre-change behaviour — and run the same file. The
   `S-2013 the card is dismissible` test must fail on `signals_quiet_line`, because a second registered
   signal also qualifies on this fixture. Record the exact failure output. Restore the injected line and
   re-run → green. *If the mutation does not go red*, record the observed output as a finding and use the
   fallback mutation instead: temporarily set the list to `signals: const []`, which must fail the test's
   opening `expect(find.byKey(const Key(_kCardKey)), findsOneWidget);`; record, restore, re-run green.

3. [ ] **`test/fuel_vs_load_signal_screen_test.dart`** — no import needed (the file already imports
   `fuel_vs_load_signal.dart`). In `pumpStats`, add `signals: const [FuelVsLoadSignal()],` after
   `settingsState: settingsState,`. Run `flutter test test/fuel_vs_load_signal_screen_test.dart` → green.

4. [ ] **`test/progression_rate_signal_screen_test.dart`** — add
   `import 'package:omnitrain/core/services/signals/progression_rate_signal.dart';` after the existing
   `import 'package:omnitrain/core/models/signals.dart';`; add
   `signals: const [ProgressionRateSignal()],` to the `StatsScreen(...)` construction in `pumpStats`.
   Run the file → green, including the `_cardKeys()` assertions.

5. [ ] **`test/modality_mix_shift_signal_screen_test.dart`** — no import needed. Add
   `signals: const [ModalityMixShiftSignal()],` to the `StatsScreen(...)` construction in `pumpStats`.
   Run the file → green, including the out-of-loop `the registry` guard (untouched).

6. [ ] **`test/protein_consistency_signal_screen_test.dart`** — the parameter form.
   (a) `pumpStats` gains `List<Signal>? signals = const [ProteinConsistencySignal()],` after
   `Size size = _kTallViewport,`, and its `StatsScreen(...)` construction gains `signals: signals,`.
   (b) `reopen` gains the same parameter and forwards it:
   ```
      Future<void> reopen(
        WidgetTester tester, {
        List<Signal>? signals = const [ProteinConsistencySignal()],
      }) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await pumpStats(tester, signals: signals);
      }
   ```
   (c) `S-2216 the card on the layer` — change its single `await pumpStats(tester);` (the line directly
   after the `'label and its key, below the Mix layer', (tester) async {` opening) to
   `await pumpStats(tester, signals: null);`. It asserts `signal_card_fuel-vs-load` absent, so it must
   read the registry.
   (d) `S-2215 two cautions qualifying` — change both `await pumpStats(tester);` calls (the one under
   `'renders the higher-priority caution above the protein card',` and the one under
   `'layer', (tester) async {`) to `await pumpStats(tester, signals: null);`, and change
   `await reopen(tester);` in the Mock-only test to `await reopen(tester, signals: null);`.
   (e) Every other call site keeps its default. Run the file → green.

7. [ ] **`test/sustained_high_load_signal_screen_test.dart`** — the parameter form, plus two imports.
   (a) Add, in this order after `import 'package:omnitrain/core/models/training_load.dart';`:
   `import 'package:omnitrain/core/services/signals/signal.dart';` and
   `import 'package:omnitrain/core/services/signals/sustained_high_load_signal.dart';`.
   (b) `pumpStats` gains `List<Signal>? signals = const [SustainedHighLoadSignal()],` and passes
   `signals: signals,` to `StatsScreen`; `reopen` gains the same parameter and forwards it.
   (c) `S-2412 the card on the layer` — its `await pumpStats(tester);` becomes
   `await pumpStats(tester, signals: null);` (it asserts `signal_card_protein-consistency` absent).
   (d) `S-2412 two cautions qualifying` — its `await pumpStats(tester);` becomes
   `await pumpStats(tester, signals: null);`.
   (e) Every other call site keeps its default. Run the file → green.

8. [ ] **`test/cardio_efficiency_drift_signal_screen_test.dart`** — the parameter form; the file
   already imports `signal.dart` and `cardio_efficiency_drift_signal.dart`.
   (a) `pumpStats` gains `List<Signal>? signals = const [CardioEfficiencyDriftSignal()],` and passes
   `signals: signals,` to `StatsScreen`; `reopen` gains the same parameter and forwards it.
   (b) Change to `signals: null`: the `await pumpStats(tester);` in `S-2501 the card on the layer`, the
   one in `S-2509 the lifting sentence`, and the one in `S-2511 two cautions qualifying` (all three
   assert `signal_card_sustained-high-load`).
   (c) Every other call site keeps its default — including `S-2511 the card is dismissible` and its
   `await reopen(tester);`, which stay injected. Run the file → green.

9. [ ] **The two remaining mutations, and the close.**
   (a) **Mutation (a) — a single-signal file.** In `test/progression_rate_signal_screen_test.dart`, copy
   the injected list line into `.evidence.md`, temporarily set it to `signals: const []`, and run
   `flutter test test/progression_rate_signal_screen_test.dart`. `S-1801 the card, end to end` must fail
   on `_cardKeys()` with `Expected: ['signal_card_progression-rate']` and `Actual: []` — the injected
   list, not the registry, decides what renders. Restore and re-run → green.
   (b) **Mutation (b) — a mixed file.** In `test/protein_consistency_signal_screen_test.dart`, copy the
   line into `.evidence.md`, temporarily change `S-2215 two cautions qualifying`'s first call back to
   `await pumpStats(tester);` (dropping the `signals: null`), and run the file. The scenario must fail on
   `expect(fuel, findsOneWidget)` — the two-caution group really does read the registry. Restore and
   re-run → green.
   (c) **The nine non-signal files, unedited.** Run
   `flutter test test/mix_layer_screen_test.dart test/screen_overflow_contract_test.dart test/fuel_row_screen_test.dart test/instrument_list_screen_test.dart test/records_and_trends_screen_test.dart test/stats_legacy_removal_test.dart test/header_standardization_test.dart test/nutrition_trend_screen_test.dart test/entry_identity_summary_test.dart`
   → green, with the counts recorded. Record that no file in the list was modified
   (`gateway.sh git-status`).
   (d) Run the whole surface in one command:
   `flutter test test/interference_signal_screen_test.dart test/interference_test.dart test/fuel_vs_load_signal_screen_test.dart test/progression_rate_signal_screen_test.dart test/modality_mix_shift_signal_screen_test.dart test/protein_consistency_signal_screen_test.dart test/sustained_high_load_signal_screen_test.dart test/cardio_efficiency_drift_signal_screen_test.dart test/signals_layer_screen_test.dart`
   → green.
   (e) Full `flutter test`; the summary line must be the baseline `+3852 ~1: All tests passed!` — no
   test was added or removed. `flutter analyze` → `196 issues found.`, 0 errors. Paste both lines into
   `.evidence.md`, and confirm with `gateway.sh git-status` that the only modified files are the seven
   test files in the classification table.

**Done Criteria** (run until green):

- `flutter analyze` → `196 issues found.` with 0 errors, and no new issue in any of the seven touched
  files.
- The four-file single-signal set is green:
  `flutter test test/interference_signal_screen_test.dart test/fuel_vs_load_signal_screen_test.dart test/progression_rate_signal_screen_test.dart test/modality_mix_shift_signal_screen_test.dart`.
- The three mixed files are green, and in each of them at least one scenario keeps `signals: null`:
  `flutter test test/protein_consistency_signal_screen_test.dart test/sustained_high_load_signal_screen_test.dart test/cardio_efficiency_drift_signal_screen_test.dart`.
- `S-2013 the card is dismissible` contains the two restored `signals_quiet_line` `findsOneWidget`
  assertions, and that test is red when the injected list is replaced by `null` and green when it is
  restored.
- The two registry guards are green and unedited:
  `flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart`.
- The nine non-signal files are green and unedited, run as one command.
- `test/signals_layer_screen_test.dart` is green.
- Full `flutter test` → `+3852 ~1: All tests passed!`, the same count as the baseline.
- `gateway.sh git-status` shows exactly the seven test files modified and nothing else.

**Predicted Files:** the seven test files — `test/interference_signal_screen_test.dart`,
`test/fuel_vs_load_signal_screen_test.dart`, `test/progression_rate_signal_screen_test.dart`,
`test/modality_mix_shift_signal_screen_test.dart`, `test/protein_consistency_signal_screen_test.dart`,
`test/sustained_high_load_signal_screen_test.dart`, `test/cardio_efficiency_drift_signal_screen_test.dart`
(EDIT — test-only). No file under `lib/`, no file under `docs/` outside this plan folder, and none of the
nine non-signal test files.

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan written | **Complete** | this file |
| Phase 1 — steps run in the plan's order, seven test files edited | **Complete** | `.evidence.md` §4 (change inventory, incl. the override's neighbour imports) |
| Phase 1 — every edited file re-run green after its edit | **Complete** | `.evidence.md` §6 — per file: interference 5, fuel_vs_load 9, progression_rate 5, modality_mix_shift 10, protein_consistency 16, sustained_high_load 13, cardio_efficiency_drift 17 |
| Phase 1 — three mutation pairs: original copied, red observed, exact original restored, green | **Complete** | `.evidence.md` §2 (originals) and §3 (records) |
| Phase 1 — nine non-signal files run unedited | **Complete** | `.evidence.md` §5 — one command, `+277: All tests passed!` |
| Phase 1 — full suite, lint and git-status at baseline | **Complete** | `.evidence.md` §6 — `+3852 ~1: All tests passed!`, `196 issues found.` with 0 errors, exactly the seven test files plus this folder modified |
| Follow-up (PR 10a fix) — the seven files' stale "real registry" prose corrected | **Complete** | comment-only edits in the seven test files; `gateway.sh lint` `196 issues found.` 0 errors; the seven files `+75: All tests passed!` |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-0 (planner) —** The brief says the plan folder "exists"; it exists and is empty. The two files are
  created, nothing else in it is touched.
- **A-1 (developer) — the governor override is applied, so no call site passes `signals: null`.**
  D-1904 and its table keep the real registry for the nine scenarios whose own assertions name a
  neighbouring card. The brief overrides that: each of those scenarios now gets an explicit
  `const [OwnSignal(), NeighbourSignal()]`. Options: keep `null` (the plan's text, and the plan's own
  O-1 alternative), or inject the pair. Injected — the brief is binding and the pair is the
  registry-independent form the PR exists to reach. Consequences: three neighbour imports are added
  (`fuel_vs_load_signal.dart` → protein, `protein_consistency_signal.dart` → sustained,
  `sustained_high_load_signal.dart` → cardio); the `List<Signal>?` parameter type is kept per D-1903
  even though nothing now passes `null`; the two whole-registry guards are untouched.
- **A-2 (developer) — the seven files' now-stale registry prose is left unchanged, and reported.**
  Each of the seven carries a file-header sentence ("The card is produced by the app's real registry
  (`buildSignalRegistry()`), which the screen falls back to when no `signals:` seam is passed …") and a
  `pumpStats` doc comment ("Pumps the Stats screen with no `signals:` seam, so the layer evaluates the
  app's real registry") that the override made false; the load-bearing claims ("the shipped signal, the
  shipped walk and the shipped copy — nothing here is stubbed") stay true. Options: correct all fourteen
  comment sites, or leave them and report. Left — the brief fixes the change inventory ("implement
  Phase 1, exactly", "undo the extra and report") and this is the first item that falls outside it.
  Raised as a follow-up in the handoff.
- **A-3 (developer) — the plan's M-(b) pre-recorded original was corrected to the override's line.**
  The plan writes it as `await pumpStats(tester, signals: null);`; under A-1 the original is the explicit
  `signals: const [ProteinConsistencySignal(), FuelVsLoadSignal()]`. The mutation itself is unchanged —
  the call falls back to the injected default either way — and the observed red is identical in kind to
  the plan's prediction. Recorded in `.evidence.md` §2.
- **A-4 (developer, PR 10a fix) — A-2's stale prose is now corrected, comment-only.** The follow-up
  brief supersedes A-2's "leave and report": the file-header sentence, the `pumpStats` doc comment and
  the "The real registry also holds …" sentence in each of the seven files now say the screen is given
  only this signal through the `signals:` seam (and, in the three mixed files, that a scenario can pass
  an explicit list). No code, import, test name or assertion changed; `modality_mix_shift`'s
  `buildSignalRegistry()` guard line is untouched. Options: rewrite the prose, or leave it. Rewritten —
  the brief is binding and the old text was false. Verified: `git-diff` shows only `//` and `///` lines,
  lint `196 issues found.` 0 errors, the seven files `+75: All tests passed!`.

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1904's rule keeps the real registry in the three "isolates the card" scenarios because they assert a named neighbour's card is absent. The alternative — injecting the own signal and the named neighbour explicitly — would make the absence assertion meaningful without coupling to future signals, at the cost of an extra import and a frozen pair. The real registry is chosen because it is today's behaviour and the smaller edit | Owner | Defaulted — owner may confirm |
| O-2 | D-1905 keeps the Interference dismissal test's name (`… still hides it`) even though the six other files read `… is still quiet`. No doc cites it, so nothing breaks either way; a rename is a cosmetic follow-up | Owner | Defaulted — owner may confirm |
| O-3 | Step 2(e)'s mutation (c) is expected to go red because a second registered signal qualifies on the Interference fixture — the same fact that forced PR 9a to drop the two lines. If it does not go red on the current `develop`, the fallback mutation in the same step is used and the observation is logged as a finding rather than treated as a failure | Executor | Open — resolved inside step 2(e) |
| O-4 | The nine non-signal files are left unedited on the strength of the second table's reasoning (the gate is unmet in eight of them; the ninth's assertions are key-scoped). If a future signal change makes one of them fail, that failure is the correct alarm and belongs to that change, not to this PR | Owner | Defaulted — owner may confirm |
