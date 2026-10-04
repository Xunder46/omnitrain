# Stats PR 9 — series index

> Two cautions from the modality-lens prompt pack
> (`docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`): item 14, Sustained High
> Load, and item 15, Cardio Efficiency Drift. Each is one pure definition file, one thin adapter
> and one registry line; neither changes the framework, the schema, the watch capture or any stored
> field. Budget: `.github/agents/pr_scope_budget.md`. Conventions: `docs/global_conventions.md`.

## The PRs, in order

| Order | Plan | Scope (one line) |
|---|---|---|
| 1 | `2026-10-04-09a-stats-pr9a-sustained-high-load-plan/…plan.md` | A caution when the user has run five or more consecutive completed weeks above 110% of their usual weekly training load with no easier week, optionally noting how often easier weeks used to recur. |
| 2 | `2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan/…plan.md` | A caution when one cardio exercise's measured pace at the same average heart rate is 5% or more worse over the last fourteen days than 28–42 days ago, over comparable-duration efforts, optionally noting that lifting load is up over the same period. |

**Merge order: 9a first, then 9b.** They are independent in production code — they share no file
except `signal_registry.dart` and its two whole-list guards — but the registry lists cautions in
**ascending** priority, so both entries are inserted **first**, each above the other; landing 9a
first makes 9b's insertion a single line above it, and landing them the other way round only changes
which edit has to be re-based. Either way the guards' whole-list counts rise by one per PR, the
lower priority number ends up on top, and 9b's guards read the count 9a leaves behind.

## Shared decisions

These are pinned identically in both plans; neither PR may change one alone.

- **One new signal = one pure definition file + one thin adapter + one registry line.** No framework
  change, no new widget, no new colour, no new token, no `SignalContext` member, no stored field.
  Template: `fuel_vs_load.dart` + `fuel_vs_load_signal.dart`.
- **Card shape.** `SignalKind.caution`, the framework's neutral card and label `Worth a look`, the
  framework's two-card cap, the framework's fourteen-local-calendar-day dismissal, gated by
  `signalsGateMet`.
- **Priorities.** Sustained High Load 100, Cardio Efficiency Drift 50. Registry order is ascending
  priority, so each entry is inserted first.
- **No causal, medical, prescriptive or quantified-intake language.** Both pack suggestions contain
  a causal clause; both are dropped (owner to confirm in each plan's Open Items).
- **Boundaries are inclusive and exact.** Every threshold is an exact integer comparison, never a
  rounded percentage, and every threshold has a scenario exactly on the boundary and one just
  across it.
- **Repository parity.** Every read goes through `StatsProgressService`, so Hive and Mock must agree
  value-for-value.
- **One release, no user data.** No migration, no legacy path, no flag, no back-compatibility shim.
- **Both whole-list registry guards are extended in place**, minimally, without reformatting:
  `test/interference_test.dart`'s caution order and
  `test/modality_mix_shift_signal_screen_test.dart`'s whole-list test.
- **Doc freshness.** Each PR updates the docs it invalidates and names, for every behavioural
  sentence it adds, the test that proves it.

## Registry after both PRs

```dart
List<Signal> _build() => const [
  CardioEfficiencyDriftSignal(),  //  50
  SustainedHighLoadSignal(),      // 100
  ProteinConsistencySignal(),     // 200
  FuelVsLoadSignal(),             // 300
  ProgressionRateSignal(),        // 100 (positive)
  ModalityMixShiftSignal(),       // 400
  InterferenceSignal(),           // 500
];
```

`docs/signals.md` carries a third, prose representation of that list. Its byte count is measured
after **each** PR (34,099 bytes before either; the 64 KiB indexing ceiling's warning band is 52,428
bytes). If a PR would push the file to 52,428 bytes, that PR splits the registered-signals section
into a part page and turns `docs/signals.md` into an index, as `widget_catalog.md` and
`state_management.md` were split.

## Scope check (both PRs against `.github/agents/pr_scope_budget.md`)

| Measure | 9a | 9b | Soft | Hard |
|---|---|---|---|---|
| Plan lines (measured) | 756 | 748 | 500 | 800 |
| Phases | 4 (1, 2, 3A, 3B) | 4 (1, 2, 3A, 3B) | >3 | >5 |
| Tracks | 1 | 1 | >1 | — |
| Ledger decisions | 15 (D-1701…D-1715) | 17 (D-1801…D-1817) | >20 | — |
| Scenarios | 14 (S-2401…S-2414) | 12 (S-2501…S-2512) | >30 | — |
| Predicted production lines | ~400 | ~390 | — | ~1,500 |

**Verdict: both plans sit over the soft line and over the soft phase count; neither reaches a hard
limit, and the two-PR split this index describes is the split the rule asks for.** The extra soft
signal is the brief's own phase-splitting instruction (Phase 3 runs as 3A then 3B so no single
agent run carries more than ten concerns); the length is scenario-bound, and the previous PR's
accepted single-signal plan (`2026-10-03-08b-…-plan.md`) is 671 lines. Each plan's own scope-check
section carries the full statement.
## Files to delete

**None.** No file is deleted by either PR: no representation is replaced, no path is superseded and
nothing is renamed. The files either PR edits that it does not create are
`lib/core/models/training_load.dart` (9a, one type), `lib/core/services/stats_progress_service.dart`
(one method each), `lib/core/services/signals/signal_registry.dart` (one line each),
`test/training_load_test.dart` (9a), `test/interference_test.dart` and
`test/modality_mix_shift_signal_screen_test.dart` (one list each, count raised by one), and the docs
each PR invalidates. No schema file changes: the SQL files document the stored model and neither PR
stores anything.

## Evidence and review

Each plan's folder holds its `<stem>.evidence.md` (baselines, suite outputs, mutation red→green
tables, residue sweeps, doc-claim-to-test tables) and its `<stem>.review.md` (the reviewer's
findings). Neither is written into the plan file.