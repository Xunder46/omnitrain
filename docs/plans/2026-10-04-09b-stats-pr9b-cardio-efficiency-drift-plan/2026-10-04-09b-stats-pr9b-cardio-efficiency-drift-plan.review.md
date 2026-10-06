# Review: Stats PR 9b

Status: complete

## Scope

Base `91295d2`. PR 9b = `aa059ed`, `3959938`, `f156927` plus the uncommitted Phase 3B working tree.
`git-diff 91295d2 --stat` = 17 files, 3298 insertions / 86 deletions.

Layers in scope: `lib/core/models`, `lib/core/services` (+ `signals/`), `test/`, `docs/`.
Layers skipped: `lib/data/`, `lib/state/`, `lib/features/`, `lib/widgets/`, `lib/core/constants`,
`lib/core/utils` — no file in those trees appears in the diff.

Observed in this review (gateway only, never piped): `flutter test` =
`04:53 +3852 ~1: All tests passed!`; `flutter analyze` = `196 issues found. (ran in 7.2s)`, 0
errors, and no touched file appears in the output. Both match the evidence file's closing figures.

## Findings

### (a) DOC CLAIMS — six docs

1. `docs/stats_screen.md`, "The registered signals" paragraph — **minor** — "The seventh is the
   Cardio Efficiency Drift" reads as a registry position under the paragraph's own
   "`buildSignalRegistry()` lists seven" framing, but `CardioEfficiencyDriftSignal()` is the
   registry's **first** entry (`lib/core/services/signals/signal_registry.dart:16`). The paragraph's
   ordinals (1st Progression Rate … 7th Cardio Efficiency Drift) are the shipping/documentation
   order, which the doc never says. Fix: name the registry order explicitly, or drop the ordinals.
   Non-blocking; the pattern is pre-existing (9a added "the sixth" the same way).
2. `docs/signals.md`, Scope block — **minor** — it enumerates the signal-definition files but lists
   only five of the seven the doc now documents: `lib/core/models/sustained_high_load.dart` (9a) and
   `lib/core/models/cardio_efficiency_drift.dart` (9b) are absent while "Registered signals"
   documents both. An under-claiming scope block fails silently, so add the two paths. Non-blocking
   (the adapters are covered by the generic "the adapters under `lib/core/services/signals/`").
3. Everything else in (a) — **checked, no finding**. Verified by reading the named files:
   - Every cited test name exists **exactly** as written: `test/cardio_efficiency_drift_test.dart`
     (the 15 named cases plus the group `the copy structural guards` and its three cases),
     `test/cardio_efficiency_service_test.dart` (the eight named cases, `the eligibility table`
     under `Mock — cardioEfforts`, and the top-level parity case), `test/interference_test.dart`
     (`the caution order holds and the registry is ordered by it`),
     `test/modality_mix_shift_signal_screen_test.dart` (`the registry` › `lists exactly the seven
     shipped signals, in order`), `test/modality_mix_shift_test.dart` (`the constant contracts`),
     `test/protein_consistency_test.dart` (`the constant contracts`),
     `test/protein_consistency_service_test.dart` (`S-2214 Mock and Hive give the same figures for
     all four reads`), `test/sustained_high_load_test.dart` (`the registry lists the cautions in
     strictly ascending priority`), `test/sustained_high_load_signal_screen_test.dart` (`S-2412 two
     cautions qualifying` › `renders the higher-priority caution above the Sustained High Load
     card`), and the two pre-existing citations the diff's context carries
     (`test/distance_source_test.dart` `S-1301`, `test/instrument_list_screen_test.dart` `S-1001`).
     The screen file's citations resolve too, with `Cardio Efficiency Drift signal — <harness>` as
     the runtime group prefix from `harness.name`: `S-2501 the card on the layer`, `S-2511 two
     cautions qualifying`, `S-2511 the card is dismissible`, and `the payload's own measure` with
     its two nested groups. The docs flatten the two nested group levels into one `›` chain; the
     concatenated name is unique in the file, so the citation still resolves (noted, not a finding).
   - Every named type, constant and function exists in `lib/`: `cardioEfficiencyDrift`,
     `cardioEfficiencyDriftCopy`, `CardioEfficiencyDriftSignal`, `cardioEfforts`, `CardioEffort`,
     the nine `kCardioEfficiency…` constants, the shared `kTrainingLoadBaselineWeeks`,
     `DistancePairing.forEntries`, `StatsProgressService.computeMixPeriod`, `MixMeasure`,
     `ExerciseSection`.
   - The required higher-priority sentence is present and true: `docs/signals.md` says "when two
     cautions qualify together the framework draws the higher priority first, so Protein Consistency
     renders above Sustained High Load, and Sustained High Load renders above Cardio Efficiency
     Drift" — which matches `resolveSignals` (descending priority within a kind) and the pinned
     screen cases.
   - The count sentences are right: `docs/signals.md` "Six cautions … in ascending priority" names
     exactly the six caution entries of `buildSignalRegistry()` (`signal_registry.dart:16-22`) in
     registry order, and `docs/stats_screen.md` "lists seven" matches the seven entries. The
     ascending claim is proved by `test/sustained_high_load_test.dart`'s guard.
   - The doc-claim-to-test table in the evidence file holds on every row I re-checked by reading the
     test it points at.

### (b) THE RULE — `lib/core/models/cardio_efficiency_drift.dart` vs D-1801…D-1808

**checked, no finding.** The file matches the ledger as written: the two windows are local calendar
spans (`[day(13), tomorrow)` and `[day(42), day(28))`) built from calendar components rather than a
`Duration`; efforts are filtered into the two windows **before** grouping, so a gap effort changes
nothing; grouping is anchored at the shortest member and greedy, `dur × 100 <= anchor × 110`, with
no chaining; a group needs ≥ 3 efforts in **each** window; the fire test is exact
cross-multiplication, `recentMean × 100 <= referenceMean × 95`; one card carries the largest drift,
ties broken by exercise id then shorter anchor; the lifting sentence needs `liftMeasure == load`,
`liftUsualLoad > 0` and `liftRecentLoad × 84 × 100 >= liftUsualLoad × 28 × 115`. It imports
`training_load.dart` only — the plan's "and `signals.dart`" text is neither needed nor followed
(already logged as the plan's Assumption Log item 10); the rule never names `Signal`/`SignalKind`.

### (c) THE SERVICE READ — `cardioEfforts`

**checked, no finding.** A completed session's `timed` effort whose instance is finished with
`actualDurationSecs > 0`; distance through the shipped `DistancePairing.forEntries`; `valueReal > 0`
and **not** `DistanceSource.isEstimated`; heart rate from the instance-scope summary
(`SensorSummary.scopeTimedInstance`, `avgHeartRateBpm > 0`). It reuses the memoised `_loadHistory()`
snapshot and `_exerciseCache`, adds no second pairing and no repository method
(`StatsProgressService` gains only the one method; the class's field set is unchanged).

### (d) THE ADAPTER

**checked, no finding.** `cardio_efficiency_drift_signal.dart` reads only `context.progressService`;
both lifting sums come from **one** `computeMixPeriod` payload (`MixSegment.section ==
ExerciseSection.resistance` over `segments` and `baselineSegments`); `liftMeasure` is the payload's
own measure. The mutation-6 seam is sound: `_TimeMeasuredPayload` (class at
`test/cardio_efficiency_drift_signal_screen_test.dart:441`) is a `StatsProgressService` subclass
that relabels the **real** payload's measure and leaves every other field — including both
resistance figures — untouched, which is the only shape where the adapter's pass-through is
observable. The `// ignore: use_super_parameters` on the next line is justified and necessary:
`StatsProgressService(this._repository)` (`lib/core/services/stats_progress_service.dart:87`) is a
private field formal, so another library cannot write `super._repository` and the lint's suggestion
is unsatisfiable. The comment states exactly that. The seam depends on public API only
(`MixLayerData`'s named constructor).

### (e) SCOPE

**checked, no finding.** The diff is exactly the plan's Predicted Files plus the plan and evidence
artefacts: 4 production files (the rule, the service read, the adapter, the one-line registry
entry), 5 test files (3 new, 2 guard edits), 6 docs. No framework file (`signals.dart`,
`signal.dart`, `signals_service.dart` are untouched), no 8a/8b/9a file, no `lib/data/`, no `watch/`.
`CardioEfficiencyDriftSignal()` is **first** in the registry (`signal_registry.dart:16`). The two
guards changed by a handful of lines: `test/interference_test.dart` +1 (`:1092`),
`test/modality_mix_shift_signal_screen_test.dart` +3/-1 (`:621`). Registering the signal did **not**
turn any existing screen test red: the full suite is green at `+3852 ~1` both in the evidence file
and in my own run, with no test file removed or skipped beyond the one pre-existing `~1`.

### (f) TESTS CAN FAIL

**checked, one finding.** Every new suite and guard has a recorded red run or mutation in the
evidence file, and the records are internally consistent with the code I read:

- Red runs: Phase 1 (compile failure — the rule file did not exist), Phase 2 (`cardioEfforts` not
  defined), Phase 3A (five card cases fail on the missing card key; the two abstain cases pass, as
  controls must), Phase 3B (both new guards written red-first).
- Mutations 1–9 are each recorded with the failing assertion, and each was reverted and re-run
  green. Mutation 6's first run **not** catching the mutant is stated plainly, logged as an Open
  Item, and then closed by a new case whose arithmetic is hand-computed before the test was written.
  That is the honest form this check exists to require.
- **An assertion that cannot fail:** `expect(payload!.measure, MixMeasure.time)` in
  `test/cardio_efficiency_drift_signal_screen_test.dart` › `the payload's own measure` › `a
  time-measured payload that still carries a baseline` › `never earns the lifting sentence`. Its
  subject is forced by the test-local override in the same file, so it holds whatever the production
  code does; it documents the fixture rather than checking it. The case's real check is the pair of
  `isNot(contains('Lifting load'))`/`_kObservation` assertions below it, which do fail under
  mutation 6. No action needed — named only because the brief asks for it.
- Pre-existing, not this PR: the loop in `test/sustained_high_load_test.dart:270` is vacuous if the
  caution list ever shrinks to one entry (a `for` from index 1 with nothing to compare). It has six
  to walk today, and mutation 5 shows it fails when the order changes.

## Global conventions (`docs/global_conventions.md`)

`PASS (3 rules): Effort-kind drives analytics` (the read keys on `effortKind == 'timed'` and the
instance's own metrics, not session labels or modality); `Timestamps are source data` (both windows
derive from persisted instance start times by local calendar arithmetic — no local counters); `Reuse
the canonical owner` (the shipped `DistancePairing.forEntries`, the `timed_instance` sensor summary,
`computeMixPeriod` and `kTrainingLoadBaselineWeeks` are reused; no second pairing, no second sensor
index, no repository method added).

`N/A (4 rules): Units + canonical storage`, `Theme tokens only`, `Card chrome via OmniSurface /
OmniCardHeader`, `Instrument panel, not influencer` — the diff adds no user-visible unit, no colour
or styling, no card widget (the card is drawn by the shared signals layer) and no motion or chrome;
the copy is observation-only, and its no-amount/no-causal-word guards pin that.

`FAIL: none.`

## Doc falsification / doc standard

- `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
  `docs/state_management/services_and_utils.md`, `docs/distance_source.md`,
  `docs/training_load.md` — read against the post-change code. **PASS** except the two minors above
  (ordinal wording; Scope under-claim). The new `docs/constants_reference.md` section is the
  compliant form: it names each constant and the rule it governs and restates **no** value.
- `docs/signals.md` remains below the indexing ceiling (47,366 bytes per the evidence, and
  `test/docs_indexing_contract_test.dart` — including the warning-band case — is green in my run).
- The rest of the `docs/` set was not re-read in full: the brief scopes (a) to these six docs, the
  gateway exposes no search, and no other doc describes the Cardio Efficiency Drift. The two docs
  that describe the signal counts and order (`signals.md`, `stats_screen.md`) are the ones checked
  above.
- One judgement call, recorded rather than rejected: `docs/stats_screen.md` says the card reports a
  pace "worse than it was four to six weeks ago", and `docs/signals.md` says the payload's period
  "spans four" weeks. Both restate a duration that lives in a constant
  (`kCardioEfficiencyReferenceWeeksFrom/To`, `kCardioEfficiencyLiftLoadWindowDays`). I did not treat
  them as blocking: the first mirrors the user-visible copy verbatim, and the second is a rationale
  clause beside the constant it explains. If the doc standard is read strictly, both are candidates
  for the constant's name instead of the number.

## Verdict

`VERDICT: APPROVE`

All six mandated checks pass. The rule implements D-1801–D-1808 as written, the service read reuses
the shipped pairing and sensor paths, the adapter reads one payload and passes the measure through,
the diff is exactly the predicted file set, and every cited test name exists while the red runs and
mutations 1–9 are recorded with restores. I re-ran the suite and the linter myself and saw
`+3852 ~1: All tests passed!` and `196 issues found.` with 0 errors and no touched file named.

The only findings are two **minor** documentation issues — an ordinal in `docs/stats_screen.md` that
reads as a registry position but is the shipping order, and a `docs/signals.md` Scope block that
lists five of the seven signal-definition files it documents. Neither changes what the app does and
neither blocks the merge; both are one-line edits and can ride along with the next doc touch. Two
further items are recorded for information only: one assertion in the screen test that cannot fail
because its subject is forced by the test-local fixture (its case still fails under mutation 6), and
two doc sentences that restate a duration that lives in a constant.
