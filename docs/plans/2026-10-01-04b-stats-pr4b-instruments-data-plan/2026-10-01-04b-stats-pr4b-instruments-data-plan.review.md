# Code Review — Stats PR 4b (the Instruments data)

Reviewed: the uncommitted change on `develop` against base `HEAD` — 11 modified
tracked files, 4 new untracked files. Plan:
`2026-10-01-04b-stats-pr4b-instruments-data-plan.md`. Evidence:
`…-plan.evidence.md`.

**Layers in scope:** models (`lib/core/models/instrument_list.dart`), repositories
(interface + Hive + Mock), core services (`stats_progress_service.dart`), features
(`lib/features/stats/`, one label lookup moved), test helpers.
**Layers skipped:** state, widgets, core/constants, `lib/watch/` (no changes).

Bar: `gateway.sh lint` → `199 issues found. (ran in 2.5s)` (0 errors, equal to
baseline) — **MET**. `gateway.sh test` → `01:11 +3183 ~1: All tests passed!` —
**MET** (matches last known `+3183 ~1`).

---

## Findings

**1. `docs/data_models.md:583` — blocker — false claim about the current product.**
The new sentence says the two value types "exist only for the Instruments list
the Stats screen renders". No such list exists: nothing under `lib/features/stats/`
references `InstrumentRow`, `InstrumentSectionData` or
`computeInstrumentSections`, and `docs/stats_screen.md`'s "What the Screen
Displays" inventory (ALL TIME / STRENGTH / CARDIO / ISOMETRIC / SPORTS /
NUTRITION) has no such section. The plan states this PR changes nothing on
screen. This is a §3.7-species annotation asserting an unshipped surface as
current, and it makes the doc false — the same failure mode that produced
`docs/plans/docs-standard-audit-2026-07-30.md`. **Fix:** delete the clause
`", and they exist only for the Instruments list the Stats screen renders"`; the
rest of the paragraph (derived-never-persisted, ownership) is within §6.2's
exemption and stays. → @developer (doc-only; no code change, no re-test).

**2. `docs/state_management/services_and_utils.md:274` — minor — same species,
weaker.** "It is the Instruments list's read" asserts a rendered list in the
present tense. **Fix:** reword to the service's purpose without asserting a
surface (e.g. "It produces the window's sections and rows for the Stats list's
data read"), or fold into finding 1's edit. → @developer.

**3. `docs/state_management/services_and_utils.md:281` — minor — imprecise, not
false.** "Row order is the exercise's training-day count descending" does not hold
for the zero-fallback row: D-505 empties its `points`, so its sort key is 0 and it
sorts last even though it was trained. **Fix:** state that the rank is the count of
days carrying a *readable* value. → @developer.

**4. `docs/db_integration.md:63` — minor — diff-scoped annotation.** "No model,
schema or seed file changed: … are untouched" describes this PR's diff, not a
durable property; it is meaningless after merge. **Fix:** restate as the durable
contract — the read adds no schema or seed requirement. → @developer.

**5. `lib/core/services/stats_progress_service.dart:752` — minor (perf, not a
blocker).** `_sensorFiguresFor` is awaited inside the per-row loop and each call
re-walks the whole `history.sessions` list (skipping out-of-window sessions),
making `computeInstrumentSections` O(rows × all sessions) against
`_HistoryIndex`'s stated "one pass, then map hits" design
(`stats_progress_service.dart:81-83`). Windows are small, so no user-visible cost
today. **Suggestion:** one pre-pass grouping instance sensors by exercise, then
per-row map hits. → @developer (suggestion only; non-blocking).

**6. `docs/data_models.md:583` — nit — grammar.** "A `InstrumentSectionData`" →
"An". → @developer.

**7. `test/instrument_list_service_test.dart:897` — nit.** The pure calendar test
(`S-1009 the previous range is calendar arithmetic`) sits inside
`for (final factory in harnessFactories)`, so it runs twice although it touches no
repository. Harmless; moving it out would halve a redundant run.

**8. Process note (not a defect).** Phase 2's red run was never captured (the
implementer's run was interrupted); red-ness is carried instead by M1–M3. This
does not literally satisfy the plan's "Red first" rule but is honestly recorded and
the substitute proofs do bite (check 8 below). No action.

Findings: **1 blocker, 4 minor, 2 nit, 1 note.** Within the ≤6 substantive budget —
no split signal, and no review → fix → review loop is needed: finding 1 is a
one-clause deletion and findings 2–4, 6 are the same single doc-edit pass.

---

## Check results

**1. Scenarios bite — PASS.** All 11 plan-owned scenarios have a test asserting a
non-vacuous outcome, and each would fail if the behaviour were wrong:
S-1002 (`sensor_summaries_by_session_test.dart:116` — asserts `keys.toSet() ==
{'s-x','s-z'}`, so a grouping or empty-key regression fails), S-1003 (`:132`),
S-1004 (`:141` — Hive vs Mock value-for-value against a hard-coded expectation),
S-1005 (`instrument_list_service_test.dart:220`), S-1006 (`:291`), S-1007 (`:433`),
S-1008 (`:616`), S-1009 (`:789` and `:897`), S-1010 (`:913`), S-1013 (`:979` —
`hasLength(1)` on sections, so a section leak fails), S-1018 (`:1029`). No vacuous
passes found: the only `isEmpty` assertion (`:973`) is the zero-fallback row's
sparkline, paired with `hasLength(7)` on the row list.

**2. D-504/D-506 ordering; D-505 — PASS.** Sections sort by
`trainingDayCount` desc then `a.section.index` (declaration order) —
`stats_progress_service.dart:797-800`; rows by `points.length` desc, then name,
then id — `:776-783`. S-1005 (cardio 3 days beats resistance 1) and S-1013 (equal
counts fall to the name) bite. On D-505: the zero-fallback row losing its points
and sorting last does **not** contradict "most frequently trained first" — the
plan decided it (D-505, S-1010 expects `ex-0` last), the row has no readable value
so no meaningful rank, and the assertion at `:965-975` pins the exact order. It is
acceptable and intentional; the only cost is the doc imprecision in finding 3.

**3. D-508/D-509 — PASS.** `previousRangeFor` (`:808-825`) computes `dayCount` from
the window's local-midnight bounds inclusive and returns
`DateTime(y, m, d − dayCount)` … `fromMs − 1` — calendar arithmetic, no `Duration`.
S-1009 (`:897`) asserts it directly. The comparison is suppressed when the previous
range has no summary or the metric differs (`:745-748`), asserted at `:789`. Pace
follows the raw sign: `formatNativeChange(NativeMetric.pace, 30, km) == '↑ +0:30
/km'` (`instrument_change_format_test.dart:85`), matching the owner's 2026-10-01
confirmation.

**4. D-511/D-512 — PASS.** Cadence sums `sensor.steps` over timed instances that
carry a step count and divides by those same instances' `actualDurationSecs`
(`:890-899`, `:925-929`); heart rate is the unweighted mean of `avgHeartRateBpm`
(`:915-920`) — 145 for 140+150, so a max-based implementation fails. Both return
`null` when nothing carries the figure, never 0 (`:930-935`); Resistance/Isometric
early-return null (`:864-869`). S-1008 asserts 120 / 145 / 148 and the nulls for a
summary-less cardio row, Sports cadence, and both Isometric and Resistance HR. The
claim "the row shows nothing rather than 0" is genuinely tested — M2 (moving the
duration accumulation above the steps guard) fails it with `Expected: null /
Actual: <0>`.

**5. D-513 — PASS.** `getSensorSummariesBySession()` is on the interface
(`workout_repository.dart:790`) and both implementations
(`hive_workout_repository.dart:3192`, `mock_workout_repository.dart:2337`); each
shares one comparator with its single-session read, and a session with no summaries
gets no key. S-1002/1003/1004 cover order, the empty case and Hive↔Mock equality.

**6. 4a reuse, no behaviour drift — PASS.** `computeInstrumentSections` calls
`computeExerciseMetrics` twice rather than re-deriving values, and
`nativeSecondaryLabel` was moved byte-identically out of
`exercise_progress_screen.dart` into `native_value_format.dart` with its one call
site updated — the only feature-file change. `stats_screen.dart`,
`records_and_trends*`, the PR path and the PR-toast tests are untouched, and
`test/helpers/repository_harness.dart` changed additively only (three new seed
helpers), so no existing test's fixtures moved.

**7. Layering and docs — one FAIL (finding 1), rest PASS.** The service holds a
`WorkoutRepository` only and reaches the bulk read through the interface;
`instrument_list.dart` imports only `exercise_metric.dart` (no Flutter); no schema,
seed or `db_seed_test.dart` change. Every type, file, constant and test named by
the three doc diffs exists — checked individually: `InstrumentSectionData`,
`InstrumentRow`, `ExerciseMetricSummary`, `computeInstrumentSections`,
`getSensorSummariesBySession`, `getSensorSummariesForSession`, `SensorSummary.scopes`,
`formatNativeChange`, `formatNativeMetric`, `nativeSecondaryLabel`,
`ExerciseSection`, `computeProgressData`, and all three new test files. No hex, line
numbers, hashes or walkthroughs were added. The 64 KiB ceiling holds (largest touched
doc: 49.7 KB). The one accuracy failure is finding 1.

**8. Evidence plausibility — PASS.** Spot-checked two mutation proofs by reading the
cited assertions. M2: the S-1008 null assertions are exactly what the denominator
mutation breaks (`Expected: null / Actual: <0>` at `:750`), so the citation is
accurate and the proof bites. M1: replacing the section sort with plain
`section.index` order makes resistance first, and S-1005 asserts cardio at `[0]`
(`:220`), so it bites too. M0's cited `Actual: Set:['']` is consistent with the
grouping key being dropped. M4 is reported honestly as *no red run observed*, with
the reason (the 02:00 local transition is after the fixture's midnight boundary) —
correctly not claimed as proof. No leftover scratch or probe file in `test/` or
`lib/` (4a's `zz_probe_hive_widget_test.dart` is gone; the only `zz_*`/probe
matches are pre-existing "placeholder" strings in food/crash tests), and no
unrelated formatter churn in any changed file.

---

## Documentation

```
DOC FALSIFICATION: ❌ REJECT — docs/data_models.md:583 — "they exist only for the
  Instruments list the Stats screen renders" — no such list exists in
  lib/features/stats/, and docs/stats_screen.md's display inventory has no such
  section → delete the clause; the type's purpose needs no surface claim (its
  behaviour is already pointed at by test/instrument_list_service_test.dart S-1007)
DOC FALSIFICATION: 🟡 WARNING — docs/state_management/services_and_utils.md — the
  cadence/HR and ordering claims are accurate, but the row-order sentence omits the
  zero-fallback exception (finding 3)
DOC FALSIFICATION: ✅ PASS (implicated, no false claim) — docs/db_integration.md,
  docs/global_conventions.md, docs/stats_screen.md, docs/design_system.md,
  docs/documentation_standard.md, docs/navigation_and_screens.md,
  docs/records_and_trends.md, docs/widget_catalog.md, docs/state_management.md
DOC STANDARD: ❌ REJECT — docs/data_models.md:583 — class 7 (unshipped-change note)
  / §3.7 — remove the clause; the remaining paragraph is within §6.2's exemption
DOC STANDARD: ❌ REJECT — docs/db_integration.md:63 — class 7 (diff-scoped
  annotation) — restate as a durable contract (finding 4)
DOC STANDARD: ✅ PASS — no hex literals, line numbers, hashes, control inventories,
  copied code, restated constants or roadmap headings added
```

## Global Conventions

```
PASS (4 rules): Units + canonical storage; Effort-kind drives analytics;
  Timestamps are source data; Reuse the canonical owner
N/A (3 rules): Theme tokens only; Card chrome via OmniSurface/OmniCardHeader;
  Instrument panel, not influencer — no styling, card or header change in this diff
FAIL: none
```

Units: the change indicator and the secondary label go through `formatNativeMetric`
+ `SettingsState` (`native_value_format.dart:63-96`), and cadence/HR are stored
canonical figures, never display-unit values — no hardcoded unit label anywhere in
the service. Effort-kind: both section ranking and sensor figures key off
`_sectionForKind(effort.effortKind)`, asserted by S-1006. Timestamps: both ranges
derive from persisted window bounds. Reuse: 4a's metric computation and formatter
are reused, not rebuilt, and `nativeSecondaryLabel` now has one owner.

## Tests

No missing or stale tests. New public behaviour is covered: `getSensorSummariesBySession`
on both implementations (S-1002/1003/1004), `computeInstrumentSections`
(S-1005…S-1010, S-1013, S-1018), `previousRangeFor` (S-1009), `formatNativeChange`
and `nativeSecondaryLabel` (`instrument_change_format_test.dart`). No test references
removed or renamed code, and the suite is green at `+3183 ~1`.

---

**Blocker: 1 | Minor: 4 | Nit: 2.** Required: findings 1, 2, 3, 4, 6 — documentation
only, one pass. Findings 5 and 7 are non-blocking suggestions and may be deferred to
the next PR in this series.
