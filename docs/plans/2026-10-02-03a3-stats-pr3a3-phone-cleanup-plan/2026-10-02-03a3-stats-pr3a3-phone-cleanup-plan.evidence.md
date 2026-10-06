# Evidence — Stats PR 3a3 phone cleanup

Collected by the planner before any code change. Baselines, greps and the doc-claim → code/test
table the plan's steps depend on. Executors append their own runs under § Executor evidence.

## Baselines (this tree, `develop`, before any change)

`gateway.sh lint` — final line, verbatim:

```
196 issues found. (ran in 3.0s)
```

0 errors. Matches the brief's 196. The series index's "241 issues" line is stale.

`gateway.sh test` — final line, verbatim:

```
01:18 +3227 ~1: All tests passed!
```

Matches the brief's `+3227 ~1`. `~1` is one skipped test.

## Dead code: proof by caller

| Symbol | `lib/` callers | Live alternative | Evidence |
|--------|----------------|------------------|----------|
| `DistanceSource.resolve` | 0 | `DistanceSource.isEstimated` (`stats_progress_service.dart`, `session_summary_screen.dart`) | only callers are `test/distance_source_test.dart` (S-801) and `test/distance_source_import_test.dart` `_readDistances` |
| `EntryRows.distanceEntries(…, timed:)` non-timed arm | 0 writers produce a non-timed distance row | the timed arm (`getEffortDistanceEntries`) | `LoggedEntryRows.setObservations`/`timedObservations`/`drillObservations` write no distance on a `set`, `round` or `drill` effort; only `test/session_summary_distance_test.dart` `_seedSession` seeds one |
| `_idPattern`'s `(?:-\d+)?` | 0 minters | `EntryRows.parseId` / `numberInId` | no writer appends a suffix; only `test/entry_rows_test.dart` fixtures hold suffixed ids |
| `_sequentialGroups` | reached only from `setGroups` when a row has no number | numbered grouping | `test/utils_test.dart`'s `_obs` helper mints `obs-${metricId.hashCode}` — an unnumbered id — so all 8 set-grouping tests go through it today |
| `_entriesAreNumbered` | `_rowIndexEntryOwns`'s positional branch | the numbered branch | a `round` effort holds no rows, so `_setRowsAt(rows, k)` is already null for it |
| `_fillEntriesBefore` | **live** — `updateEntryValue`'s extra-weight branch and `setEntryDistance` | — | it is what keeps a later entry's value on its own row when an earlier entry holds no row of that metric (`S-807`, `S-864`, `S-883`). **Not dead code**: D-707 was wrong and is superseded by D-712 |
| `SessionCore._getMetricsPerEntry` | `session_core_entry.dart` positional delete fallback | `EntryRows.setGroups` | sole caller is the fallback `deleteEntry` loses |
| `_groupTimedObservations` / `_groupDrillObservations` | **live** — `groupByEffortKind` is called with `'timed'`/`'drill'` from `session_summary_builder.dart` (`_buildEntriesForEffort`, `buildTemplateDraftExercises`), `session_summary_service.dart` (`_computeVolumeFromObservations`) and `stats_progress_service.dart` | `EntryRows.companions` (a separate PR) | these arms pair rows by position (`i += 2`), ignoring the entry rule — they are the brief's item 8 "outside the entry rule" surface; out of scope, recorded |
| `_groupRoundObservations` | 0 | the `set` groupers | a `round` effort's entries come from `RoundInstance` records, so no caller reaches it with rows; out of scope, recorded |

## The three writer paths (what a phone write produces)

`lib/core/utils/logged_entry_rows.dart` builds the rows for every phone write:

- `setObservations` writes reps + weight, plus extra weight when the exercise has no `load`
  capability — one full row set per set, every row carrying the entry's number.
- `timedObservations` always writes a distance row (0.0 or the carried value) **and** an extra-weight
  row — never a partial set.
- `drillObservations` writes extra weight — no distance row.

A *new* entry always gets a full row set, but a stored effort can still hold an entry with no row of
a given metric — a hold added before any extra weight was typed, or an entry whose row a delete
removed. That is when `_fillEntriesBefore` runs, and it is why the fill is live (D-712).

`lib/state/workout/session_core_io.dart` assigns `_observations[effort.id] = await
_repository.getEffortObservations(...)` with no re-sorting, so `_observations[effort.id].first` is
whatever the store returns first: Hive's key order (`obs-…-10-…` before `obs-…-2-…`), Mock's
insertion order. That is the store-order dependency 3a2 O-7 / 3b S-1 describes.

## Doc claims vs. code (every disagreement this PR resolves)

| Doc claim | Reality | Resolution |
|-----------|---------|------------|
| `docs/distance_source.md` — "`resolve` maps a missing source to `entered`", verified by S-801 | `resolve` has no `lib/` caller; the phone writes a source for every positive distance | D-701, Phase 1 step 1 |
| `docs/distance_source.md` — "On an effort that is not timed, the entries are the distance rows themselves" | no writer stores a distance on a non-timed effort | D-703, Phase 1 step 3 |
| `docs/distance_source.md` — "When the edited entry has no row of its own, the write first fills every earlier unpaired entry…" | **true** — the fill is live and is what keeps a later entry's value on its own row | kept; D-712, Phase 1 step 15 (names `S-807`, `S-864`, `S-883`) |
| `docs/distance_source.md` — invariant "a reader of a distance resolves its source through `DistanceSource`" | readers read the stored source and call `isEstimated` only | D-701, Phase 1 step 15 |
| `docs/data_models.md` `valueSource` — "an absent source … reads as `entered`" | nothing resolves it; a positive distance always has a source | D-701, Phase 1 step 17 |
| `docs/data_models.md` § Entry Identity — "optionally followed by `-<digits>`", "an existing suffixed id reads as its number" | no writer mints a suffix | D-704, Phase 1 step 7 |
| `docs/data_models.md` § Entry Identity — "on an effort any of whose rows has no number, the sequential grouping of the legacy data applies instead" | unnumbered rows cannot occur from a phone write | D-705, Phase 2 step 10 |
| `docs/data_models.md` § Entry Identity — "**The routine-template defaults read rows without the rule.**" | true today, fixed by D-708 | D-708, Phase 3 step 3 |
| `docs/session_summary.md` — "**A stored distance is never hidden**", `S-818d`, `S-819` | the fixture stores a distance on a `drill` effort, unreachable | D-703, Phase 1 step 16 |
| `docs/session_summary.md` / `docs/state_management/workout_state.md` — `S-859` | its fixture is a `drill` effort with a lone unnumbered distance row | retired, Phase 1 steps 13/18 |
| `docs/state_management/workout_state.md` `setEntryDistance` — "earlier unpaired entries are filled first, numbered upward" | **true** — the fill is live | kept; D-712, Phase 1 step 18 (names `S-807`, `S-883`) |
| `docs/stats_best_load_investigation.md` — "the number in the id (a 3a suffix included)" | no suffix exists after D-704 | Phase 2 step 12 |
| `lib/widgets/chart/scrollable_trend_chart.dart` — "every stats chart on `StatsScreen` (strength e1RM, strength volume, cardio pace, cardio duration, nutrition calories, nutrition macros) and the profile measurement history sheet" | the chart's callers are `measurement_history_chart_sheet.dart`, `nutrition_trend_card.dart`, `exercise_progress_screen.dart` | D-710, Phase 3 step 5 |
| `lib/data/datasources/food_catalog_loader.dart` — "Both the Hive-backed production repository and the in-memory Mock repository go through this loader" | only `hive_workout_repository.dart` calls `loadFromAsset()`; Mock reads the generated `lib/mock/food_catalog_seed.dart` | D-710, Phase 3 step 6 |
| `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` — 3b READY, "241 issues", scope check 2026-09-27 | 3a/3a2/3b committed, PR 4 done, baseline 196 | D-710, Phase 3 step 7 |

## "leftover" / "legacy" occurrences in scope (from a full search)

In scope (distance / entry-identity vocabulary): `lib/core/utils/entry_rows.dart` (`companions` doc),
`lib/core/utils/distance_source.dart` (`DistancePairing.forEntries` doc), `docs/distance_source.md`
(Structure, Invariants, Vocabulary — the **Legacy distance** and **Leftover row** entries),
`docs/data_models.md` (§ Entry Identity "leftover"; `valueSource` "legacy" in the resolve sense),
`docs/session_summary.md` (the S-858/S-859 test-list sentence).

Out of scope (different meanings or test names): `lib/widgets/tile_artwork_metrics.dart`,
`lib/widgets/charts/macro_donut_chart.dart`, `lib/widgets/session/workout_session_global_timer.dart`,
`docs/create_new_exercise.md`, `docs/db_integration.md`, `docs/profile_and_measurements.md`,
`docs/nutrition.md`, `docs/stats_screen.md` (`stats_legacy_removal_test.dart`, a different feature),
`docs/widget_catalog/*`, `docs/memories/*`, every `docs/plans/**` and `docs/history/**` occurrence,
and `S-858`'s test name.

## Retired tests (named, with the reason)

| Test | Reason |
|------|--------|
| `test/session_summary_distance_test.dart` `S-818d` | its fixture stores a distance row on a `drill` effort; D-703 makes such a row unshowable |
| `test/session_summary_distance_test.dart` `S-819` | same fixture — it removes a distance the Summary no longer shows |
| `test/entry_identity_summary_test.dart` `S-859` | same `drill` shape plus an unnumbered row; both are gone under D-703/D-704 |
| `test/utils_test.dart` "odd number of observations drops the trailing one" | asserts the sequential rule; a lone reps row is now an entry with weight 0.0 (D-705) |

Kept, with why: `S-815` (zero-removal on a Cardio entry — the removal rule survives),
`S-844`/`S-845` (numbered grouping and the entry's own row), `S-855`/`S-856`/`S-858` (set and
Cardio-tracked fixtures), `S-802`–`S-808` (source survival, copies, order independence — `S-807` is
the fill's own guard and is restored to its HEAD text, D-712), `S-864` and `S-883` (the fill's
guards, D-712),
`S-823` (a plank tracked through Cardio), the 8 set-grouping tests in `test/utils_test.dart`
(numbered once `_obs` mints numbered ids), the "unknown effortKind falls back to set grouping" test
(the `default:` branch stays), and the existing `buildTemplateDraftExercises includes extra-weight
target for timed` test (S-1311's happy path).

## Executor evidence

*(Executors append Done Criteria output, the two inverse-edit runs per phase, and the Phase 3 residue
sweep here. Never in the plan file.)*

### Phase 1 — Step 0 red run (before any `lib/` change)

Command: `gateway.sh test test/distance_source_test.dart test/entry_rows_test.dart
test/row_invariants_guard_test.dart test/entry_identity_summary_test.dart
test/session_summary_distance_test.dart test/distance_source_import_test.dart`

Result: `00:02 +52 -12: Some tests failed.`

| Failing test | Observed failure | Satisfied by step |
|---|---|---|
| `distance_source_test.dart` `S-807 a write on a later entry fills no earlier row` (Mock + Hive) | `Expected: Set:['obs-e-gap-0-distance', 'obs-e-gap-1-distance'] Actual: Set:[…, 'obs-e-gap-2-distance']` — the executor had rewritten S-807 to the withdrawn D-707 rule; at HEAD the fill writes rows 0 and 1 and the value lands on row 2 | **withdrawn** — restore S-807 to its HEAD text (Phase 1 step 9, D-712) |
| `distance_source_test.dart` `S-1303 a non-timed effort has no distance entries` (Mock + Hive) | `Expected: empty Actual: [Instance of 'DistanceEntry', Instance of 'DistanceEntry']` | 3, 4 |
| `entry_rows_test.dart` `S-841 every id shape reads its number…` | `numberInId('obs-e1-4-distance-1727000000123')` still reads `4` | 7 |
| `entry_rows_test.dart` `S-1305 a suffixed row pairs with nothing and stays stored` (Mock + Hive) | the suffixed row still pairs with entry 1 | 7 |
| `entry_rows_test.dart` `S-1306 a copied suffixed row gets a fresh id` (Mock + Hive) | the copy keeps `obs-<clone>-1-distance-9000` | 7 |
| `session_summary_distance_test.dart` `S-1303 a non-timed effort shows no DISTANCE section` | `Found 1 widget with key 'omni_session_distance_card'` | 3, 4 |
| `row_invariants_guard_test.dart` `S-883 a phone timed sequence` (Mock + Hive) | `2c addEntry(run, previousValues: {distance: 2500}): effort … (timed) holds an unsourced distance of 2500.0 m (I-c)` | 5 |

`S-1301`'s source scan and `S-1316` passed at HEAD (they assert the absence of a reader and the
idempotence of a second confirm, both already true); they are regression guards for steps 1 and 6.

### D-712 inverse edit — observed by the executor, confirmed by the governor

Deleting `_fillEntriesBefore` (the withdrawn D-707) makes two existing tests fail on **both**
repositories, in normal phone flows:

| Test | Observed failure |
|---|---|
| `test/entry_identity_test.dart` `S-864 the later of two row-less holds keeps its value` | `Actual: {'obs-e-side-1-extra-weight': 5.0}` vs `Expected: {'obs-e-side-1-extra-weight': 0.0, 'obs-e-side-2-extra-weight': 5.0}` — with no fill the write takes number 1, and positional pairing reads hold 2's value back on hold 1 |
| `test/row_invariants_guard_test.dart` `S-883 a phone timed sequence` | the same cause for `setEntryDistance` on a later entry: the 3000 m distance lands on the wrong entry (governor's observation; the executor's Step 0 run stopped earlier, at 2c) |

This is the evidence for D-712: the fill is live behaviour, not old-data handling. Phase 1's
"must fail if" (c) re-runs it.

### Phase 1 — resume run (this executor)

The previous run was stopped mid-phase. This run restored `_fillEntriesBefore` and both call sites
to their HEAD text, restored `S-807` to its HEAD text, implemented D-713, finished the doc steps and
ran the four inverse edits below.

**Restored to HEAD (byte-identical):** `_fillEntriesBefore` and its two call sites in
`lib/state/workout/session_core_entry.dart`; `S-807` in `test/distance_source_test.dart`. The
remaining diff in `session_core_entry.dart` is D-702 (`distanceMeters: 0.0` in `addEntry`) and D-703
(`getEffortDistanceEntries` timed-only) only.

**D-713 implementation.** `EntryRows.companions` filters the metric's rows to those whose id carries
a number before `ordered`; `ordered` keeps its total order (an unnumbered row sorts last).
`_fillEntriesBefore` needed no change: its `number` comes from `EntryRows.nextNumber`, which already
ignores unnumbered rows.

**One test correction.** The S-1304 guard step's first assertion in
`test/row_invariants_guard_test.dart` expected a four-element distance list; the effort holds five
entries at that point (`[0.0, 0.0, 3000.0, 0.0, 0.0]`). It now asserts the last entry's distance is
0.0 plus the no-positive-unsourced-row check, which is what S-1304 states.

**One added assertion.** S-883 step 5 now asserts `_extraWeights(state, run, entries: 3) ==
[0.0, 5.0, 0.0]` — the fill's own guard inside the guard file, so inverse edit (c) fails there too.

#### Phase 1 targeted suite (green)

Command: `gateway.sh test test/distance_source_test.dart test/distance_source_import_test.dart
test/session_summary_distance_test.dart test/entry_rows_test.dart test/entry_identity_summary_test.dart
test/entry_identity_test.dart test/row_invariants_guard_test.dart`

Result, verbatim: `00:04 +101: All tests passed!`

#### Inverse edits — every "must fail if" line, observed

Each edit was applied, the named suite run, the failure read, and the edit reverted.

**(a) restore the non-timed arm of `distanceEntries`** — removed the
`if (effort.effortKind != 'timed') return const <DistanceEntry>[];` guard in
`getEffortDistanceEntries`.

Command: `gateway.sh test test/session_summary_distance_test.dart`

Result: `00:01 +14 -1: Some tests failed.`

```
00:01 +10 -1: S-1303 a non-timed effort shows no DISTANCE section [E]
  Test failed. See exception logs above.
  The test description was: S-1303 a non-timed effort shows no DISTANCE section
```

**(b) restore `previousValues?['distance']` in `addEntry`** — `distanceMeters: 0.0` became
`distanceMeters: (previousValues?['distance'] as double?) ?? 0.0`.

Command: `gateway.sh test test/row_invariants_guard_test.dart`

Result: `00:01 +8 -2: Some tests failed.`

```
00:00 +4 -2: Hive — the row guard S-883 a phone timed sequence [E]
  Expected: not null
    Actual: <null>
  2c addEntry(run, previousValues: {distance: 2500}): effort effort-1790946313839-0 (timed) holds an unsourced distance of 2500.0 m (I-c)
```

Both repositories fail (Mock at `+0 -1`, Hive at `+4 -2`).

**(c) delete `_fillEntriesBefore` again** — the method body reduced to
`return EntryRows.nextNumber(observations);`.

Command: `gateway.sh test test/entry_identity_test.dart test/row_invariants_guard_test.dart
test/distance_source_test.dart`

Result: `00:01 +54 -4: Some tests failed.`

```
00:00 +15 -1: entry_identity_test.dart: Mock — writes and deletes S-864 the later of two row-less holds keeps its value [E]
00:00 +22 -2: distance_source_test.dart: Mock S-807 missing rows are filled in position (Mock) [E]
00:00 +35 -3: distance_source_test.dart: Hive S-807 missing rows are filled in position (Hive) [E]
00:01 +53 -4: entry_identity_test.dart: Hive — writes and deletes S-864 the later of two row-less holds keeps its value [E]
```

S-864's observed failure:

```
  Expected: {'obs-e-side-1-extra-weight': 0.0, 'obs-e-side-2-extra-weight': 5.0}
    Actual: {'obs-e-side-1-extra-weight': 5.0}
     Which: has different length and is missing map key 'obs-e-side-2-extra-weight'
  the fill row joins hold 1, so hold 2 is the second row
```

S-883 did **not** fail under this edit until the step-5 assertion was added; with it in place the
guard file fails on both repositories. That is why the assertion was added (above).

**(d) drop the numbered-only filter from `companions`** — the `numberInId(row.id) != null` clause
removed from the `where`.

Command: `gateway.sh test test/entry_rows_test.dart`

Result: `00:00 +14 -4: Some tests failed.`

```
00:00 +8 -1: Mock — the rule S-1305 a suffixed row pairs with nothing and stays stored [E]
  Expected: [0.0, 0.0]
    Actual: [0.0, 2000.0]
00:00 +8 -2: Mock — the rule S-1306 a copied suffixed row gets a fresh id [E]
  Expected: [0.0, 0.0]
    Actual: [0.0, 2000.0]
00:00 +14 -3: Hive — the rule S-1305 a suffixed row pairs with nothing and stays stored [E]
00:00 +14 -4: Hive — the rule S-1306 a copied suffixed row gets a fresh id [E]
```

#### Residue sweep (Phase 1 scope)

| Symbol / wording | `lib/` hits | Verdict |
|---|---|---|
| `DistanceSource.resolve` | 0 | gone; the only remaining mentions are the S-1301 scan in `test/distance_source_test.dart`, which asserts its absence |
| `previousValues?['distance']` | 0 | gone (D-702) |
| `distanceEntries(` callers passing a kind | 0 | the only caller is `getEffortDistanceEntries`, which passes rows and a count |
| `_sequentialGroups` | `entry_rows.dart` (definition + `setGroups` early return) | **Phase 2** (D-705) — not this phase |
| `_entriesAreNumbered` | `session_core_entry.dart` (definition + 2 callers) | **Phase 2** (D-706) — not this phase |
| `_getMetricsPerEntry` | `session_core.dart` + `session_core_entry.dart` | **Phase 2** (D-706) — not this phase |
| `_buildEntriesForEffort` | `session_summary_builder.dart` | live, out of scope |
| "leftover" in the distance/entry-identity vocabulary | 0 in `lib/`; 0 in the four docs this phase edits | gone (D-709). Remaining `leftover` hits are test *names* (`S-858`), which D-709 keeps, and unrelated UI prose |
| "legacy" in the distance/entry-identity vocabulary | 0 in the four docs this phase edits | gone (D-709). Remaining `legacy` hits are the sequential-grouping fallback (Phase 2, D-705), nutrition/measurement back-compat, and test helper names |

#### Retired tests (this phase)

| Test | Reason |
|------|--------|
| `test/session_summary_distance_test.dart` `S-818d` | its fixture stores a distance row on a `drill` effort; D-703 makes such a row unshowable |
| `test/session_summary_distance_test.dart` `S-819` | same fixture — it removes a distance the Summary no longer shows |
| `test/entry_identity_summary_test.dart` `S-859` | same `drill` shape plus an unnumbered row; both are gone under D-703/D-704 |

`test/utils_test.dart` "odd number of observations drops the trailing one" is **Phase 2** (D-705),
not this phase.

#### Doc steps 15–18

| Doc | Change |
|---|---|
| `docs/distance_source.md` | `DistanceSource` paragraph rewritten (no `resolve`, `S-1301`); fill paragraph, its rationale and its invariant kept and now naming `S-807`/`S-864`/`S-883`; non-timed sentence replaced by the timed-only rule (`S-1303`); the resolve invariant and the "resolves its source through `DistanceSource`" invariant rewritten; the "missing source reads as `entered`" rationale narrowed to the import's wire rule (`S-1302`); **Legacy distance** deleted; **Leftover row** renamed **Unpaired row** |
| `docs/session_summary.md` | "A stored distance is never hidden" bullet dropped; `S-818d`/`S-819` replaced by `S-1303`; the `S-858`/`S-859` sentence replaced by "a row that belongs to no entry (`S-858`)" |
| `docs/data_models.md` | `valueSource` paragraph is the D-701 rule with `S-1301`; the optional-suffix sentence and the "an existing suffixed id reads as its number" sentence dropped; `S-859` dropped from the phone's test list |
| `docs/state_management/workout_state.md` | `addEntry` states no distance carry-forward (`S-1304`); `setEntryDistance` keeps the fill and names `S-807`/`S-864`/`S-883`; `updateEntryValue` keeps the fill and names `S-864`; `getEffortDistanceEntries` gains the timed-only rule and loses `S-859` |

**N/A, recorded.** Phase 1 step 9 also asks to delete a "resolves to `entered`" invariant line from
`test/distance_source_test.dart`'s doc comment. No such line exists in the file at HEAD or in the
working tree (confirmed by `git-diff`), so there was nothing to delete.

### Phase 1 — finish run (this executor)

The one remaining full-suite failure was fixed: `test/watch_session_import_test.dart`, A-51 "a late
wrist run is placed after the user's own timed entry, which keeps its distance". Its fixture gave the
user's timed entry its 5000 m with `previousValues: {'distance': 5000.0}` — the exact shape D-702
retired — so the distance read 0.0. It now goes through the live path, `setEntryDistance(run, 1,
5000.0)`. Every assertion and its meaning are unchanged.

Command: `gateway.sh test test/watch_session_import_test.dart`
Result, verbatim: `00:00 +45: All tests passed!`

#### Files outside the plan's Predicted Files

| File | Why | Action |
|---|---|---|
| `test/watch_session_import_test.dart` | its A-51 test seeded the user's timed distance with `previousValues: {'distance': 5000.0}` — the shape D-702 removed — and it is the only other `test/` caller of that shape | re-pointed through `setEntryDistance`; added to the plan's Phase 1 Predicted Files |

A full `test/` scan for `previousValues` with a `'distance'` key returns only this test and the
deliberate S-1304 guard in `test/row_invariants_guard_test.dart` (which asserts the new rule).

#### Inverse edits — re-run on the finished tree

| # | Edit applied | Named file run | Observed failure | Reverted |
|---|---|---|---|---|
| (a) | remove the `effortKind != 'timed'` guard in `getEffortDistanceEntries` | `test/session_summary_distance_test.dart` | `00:01 +10 -1: S-1303 a non-timed effort shows no DISTANCE section [E]` | `--stat` back to `15 ++-`; `00:01 +15: All tests passed!` |
| (b) | `distanceMeters: 0.0` → `(previousValues?['distance'] as double?) ?? 0.0` | `test/row_invariants_guard_test.dart` | `00:00 +0 -1: Mock — the row guard S-883 a phone timed sequence [E]` and `00:00 +4 -2: Hive — the row guard S-883 … [E]`; `2c addEntry(run, previousValues: {distance: 2500}): effort … (timed) holds an unsourced distance of 2500.0 m (I-c)` | `--stat` back to `15 ++-`; `00:01 +10: All tests passed!` |
| (c) | `_fillEntriesBefore` body reduced to `return EntryRows.nextNumber(observations);` | `test/entry_identity_test.dart test/row_invariants_guard_test.dart test/distance_source_test.dart` | `00:00 +17 -1: … Mock … S-864 the later of two row-less holds keeps its value [E]`; `00:00 +21 -2: … Mock S-807 missing rows are filled in position (Mock) [E]`; `00:00 +34 -3: … Hive S-807 … (Hive) [E]`; `00:01 +53 -4: … Hive … S-864 … [E]` → `00:01 +54 -4: Some tests failed.` | `--stat` back; `00:01 +58: All tests passed!` |
| (d) | drop `numberInId(row.id) != null` from `companions`'s `where` | `test/entry_rows_test.dart` | `00:00 +8 -1: Mock — the rule S-1305 a suffixed row pairs with nothing and stays stored [E]`; `00:00 +8 -2: Mock — the rule S-1306 a copied suffixed row gets a fresh id [E]`; `00:00 +14 -3: Hive — … S-1305 … [E]`; `00:00 +14 -4: Hive — … S-1306 … [E]`; `Expected: [0.0, 0.0] Actual: [0.0, 2000.0]` | `--stat` back to `42 ++++---`; `00:01 +18: All tests passed!` |

**Correction to the plan's must-fail-if (c).** The plan (and the earlier evidence note) claims S-864,
S-883 *and* S-807 fail when `_fillEntriesBefore` is deleted. Observed: only S-864 (both repositories)
and S-807 (both repositories) fail; **S-883 passes on both**. At S-883's step 5 the entry already
owns an extra-weight row, so the fill never runs and the write lands on the same row either way.
S-883 remains a live guard for its distance-source and delete assertions. Recorded as
A-3a3-P1-2 in the plan's Assumption Log.

Every inverse edit was applied and reverted by hand — no `git stash`/`checkout`/`restore`. Each
mutated spot was re-read after reverting and the `--stat` returned to its pre-edit value; no residue.

#### Red → green (this phase)

| Test | Red (Step 0, before any `lib/` change) | Green (Phase 1) |
|---|---|---|
| `S-1301 a stored distance with no source reads with no source` (rewrite of `S-801`) | source scan already green (regression guard for step 1) | `+101` targeted suite |
| `S-1303 a non-timed effort has no distance entries` (Mock + Hive) | `Expected: empty Actual: [Instance of 'DistanceEntry', …]` | passes |
| `S-1303 a non-timed effort shows no DISTANCE section` | `Found 1 widget with key 'omni_session_distance_card'` | passes |
| `S-1304`'s guard step (`2c addEntry(… distance: 2500)`) | `holds an unsourced distance of 2500.0 m (I-c)` | passes |
| `S-1305 a suffixed row pairs with nothing and stays stored` (Mock + Hive) | the suffixed row still paired with entry 1 | passes |
| `S-1306 a copied suffixed row gets a fresh id` (Mock + Hive) | the copy kept `obs-<clone>-1-distance-9000` | passes |
| `S-807 missing rows are filled in position` (restored to HEAD) | `Expected: Set:['obs-e-gap-0-distance', 'obs-e-gap-1-distance'] Actual: Set:[…, 'obs-e-gap-2-distance']` | passes |
| `S-883 a phone timed sequence` (new step-5 assertion) | (green from the start; see the correction above) | passes |

Targeted suite, verbatim: `00:04 +101: All tests passed!`
Full suite, verbatim: `01:20 +3234 ~1: All tests passed!` (baseline `+3227 ~1`; the growth is this
phase's tests).

#### Tests removed, renamed or rewritten (this phase)

| Test | Change |
|---|---|
| `test/distance_source_test.dart` `S-801 a legacy distance reads as entered` | **renamed + rewritten** → `S-1301 a stored distance with no source reads with no source`; its resolve assertions became the S-1301 source scan ("nothing in `lib/` calls `DistanceSource.resolve`") |
| `test/distance_source_test.dart` `S-1303 a non-timed effort has no distance entries` | **added** |
| `test/distance_source_test.dart` `S-1316 confirming a distance twice is idempotent` | **added** |
| `test/distance_source_test.dart` `S-807` | **restored to its HEAD text and title** (`missing rows are filled in position`); the executor's D-707 rewrite was undone |
| `test/session_summary_distance_test.dart` `S-818d a non-Cardio entry with a stored distance gets one row` | **retired** → replaced by `S-1303 a non-timed effort shows no DISTANCE section` |
| `test/session_summary_distance_test.dart` `S-819 removing a legacy distance hides its row` | **retired** |
| `test/entry_identity_summary_test.dart` `S-859 the Summary names a lone legacy row without a number` | **retired** |
| `test/entry_rows_test.dart` `S-841 every id shape reads its number…` | **rewritten**: `numberInId('obs-e1-4-distance-1727000000123')` now `isNull` (was `4`) |
| `test/entry_rows_test.dart` `S-846 a 3a suffixed id sits at its number` | **fixture/assertions rewritten**: dropped the `obs-e-f5-3-distance-9000` row and its assertions; distances now `[0.0, 0.0, 0.0, 0.0, 0.0]` |
| `test/entry_rows_test.dart` `S-847 duplicated blocks stay addressable` | **fixture/assertions rewritten**: dropped `obs-e-d-3-distance-9000` and the clone's suffixed id; clone assertions for the numbered rows kept |
| `test/entry_rows_test.dart` `S-1305 a suffixed row pairs with nothing and stays stored` | **added** (Mock + Hive) |
| `test/entry_rows_test.dart` `S-1306 a copied suffixed row gets a fresh id` | **added** (Mock + Hive) |
| `test/row_invariants_guard_test.dart` `S-883 a phone timed sequence` | **step added**: `2c addEntry(run, previousValues: {distance: 2500})` asserts no positive unsourced distance row (S-1304) |
| `test/distance_source_import_test.dart` `_readDistances` helper | **rewritten** to `(double, String?)`; `S-876`/`S-877` expectations unchanged |
| `test/watch_session_import_test.dart` A-51 "a late wrist run…" | **rewritten**: `addEntry` + `setEntryDistance(run, 1, 5000.0)` replaces the `previousValues` carry-forward |

#### Residue greps (Phase 1 scope)

| Search | Command | Result |
|---|---|---|
| `DistanceSource.resolve` in `lib/` | grep `lib/` | 0 hits; the only mention is the S-1301 scan in `test/distance_source_test.dart`, which asserts its absence |
| `resolve(` in `lib/core/utils/distance_source.dart` | grep the file | 0 hits |
| `leftover` in `distance_source.dart`, `entry_rows.dart`, `docs/distance_source.md`, `docs/data_models.md`, `docs/session_summary.md`, `docs/state_management/workout_state.md` | grep the six files | 0 hits (the S-858 test *name* is out of scope, D-709) |
| `legacy` in the same six files | grep the six files | `lib/core/utils/entry_rows.dart` (3 hits — the sequential-grouping fallback) and `docs/data_models.md` (nutrition back-compat ×2, § Entry Identity sequential grouping ×1). All are **Phase 2** (D-705) or unrelated meanings — none is the distance vocabulary |
| `previousValues` with `'distance'` in `test/` | grep `test/` | only the S-1304 guard and the A-51 test now routed through `setEntryDistance` |

#### Doc-claim rows (steps 15–18)

The four rows are in § Doc steps 15–18 above; each claim the phase retired is also a row in the
planner's § Doc claims vs. code table. No row remains whose "Reality" column still reads "true" for a
retired claim.

#### Final verification (this run, verbatim)

`gateway.sh lint`:

```
196 issues found. (ran in 2.7s)
```

0 errors (`grep -c "error •"` → `0`).

`gateway.sh test`:

```
01:20 +3234 ~1: All tests passed!
```

---

# Phase 2 — entry identity is the number, never a position

Theme: remove the sequential/positional grouping fallbacks (D-705, D-706, D-711). A row whose id
carries no number belongs to no entry; every entry is addressed by its number.

## Code steps 1–6 (applied)

| Step | File | Change |
|---|---|---|
| 1 | `lib/core/utils/entry_rows.dart` | `SetRows.number` is now non-nullable `int`; class doc is "One set entry: the rows that carry its number." |
| 2 | `lib/core/utils/entry_rows.dart` | `setGroups` groups numbered rows only (`if (number == null) continue;`); `_sequentialGroups` deleted; `ordered` doc explains the total order (unnumbered sorts last). |
| 3 | `lib/state/workout/session_core_entry.dart` | `_entriesAreNumbered` deleted; `_rowIndexEntryOwns` is `timed`/`drill` → own companion row, else → the set numbered *k*. |
| 4 | `lib/state/workout/session_core_entry.dart` | `deleteEntry` positional fallback deleted; returns when `_setRowsAt` is null. |
| 5 | `lib/state/workout/session_core.dart` | `_getMetricsPerEntry` deleted (its only caller was the fallback removed in step 4). |
| 6 | `lib/core/utils/observation_grouper.dart`, `lib/state/workout/session_summary_builder.dart` | `default:` comment corrected (branch stays, D-711); "legacy fallback" comment above `EntryRows.setGroups` corrected (D-709). |

`_fillEntriesBefore` is untouched (D-712), with both call sites unchanged.

## Red-first

**Deviation, stated plainly.** Code steps 1–6 were applied before the red runs were captured. The
red state is therefore demonstrated by the plan's own two inverse edits, applied to the tracked
files, run, and reverted exactly. Both are recorded below with the failing test name and `[E]` line.

### Inverse edit (a) — restore the `_sequentialGroups` early return in `setGroups`

`gateway.sh test test/utils_test.dart`:

```
00:00 +22 -1: ObservationGrouper set grouping S-1307 an unnumbered row is in no entry [E]
00:00 +138 -1: Some tests failed.
```

Reverted exactly; `gateway.sh test test/utils_test.dart` → `00:00 +139: All tests passed!`

### Inverse edit (b) — restore the positional branch of `_rowIndexEntryOwns` and `deleteEntry`

The plan's S-1308 fixture is a **numbered** 3-set effort, so the positional branch is skipped
(`_entriesAreNumbered` is true) and the plan's literal claim — "restore the positional branch of
`_rowIndexEntryOwns` → S-1308 fails" — does **not** hold for that fixture. The branch only changes
behaviour on an **unnumbered** effort, which is exactly the case D-706 removes. S-1308 was therefore
extended with a second test, `S-1308 an unnumbered set effort has no entry to delete`, which pins the
removed fallback. With the inverse applied:

```
00:00 +8 -1: Mock — writes and deletes S-1308 an unnumbered set effort has no entry to delete [E]
00:00 +22 -2: Hive — writes and deletes S-1308 an unnumbered set effort has no entry to delete [E]
00:01 +29 -2: Some tests failed.
```

Reverted exactly; `gateway.sh test test/entry_identity_test.dart` → `00:01 +31: All tests passed!`
Residue sweep after both reverts: `grep -n "_entriesAreNumbered\|_getMetricsPerEntry"` over
`session_core_entry.dart` and `session_core.dart` → 0 hits; `git-diff --stat` for
`session_core_entry.dart` back to 79 changed lines.

### S-1309 and S-1310 are regression guards, not red-first

S-1309 (delete a timed entry, then `addEntry` → the new entry is empty) pins D-702, which Phase 1
established; S-1310 (a write on a later entry creates no earlier rows) pins D-712, whose
`_fillEntriesBefore` is untouched by this phase and does not run in the fixture (every earlier entry
already holds a distance row). Neither can be made red by reverting a Phase 2 change, and both are
green at the Phase 2 baseline. They are recorded here as guards, not as red-first tests.

## Retired / rewritten tests

| Test | File | Disposition | Reason |
|---|---|---|---|
| `odd number of observations drops the trailing one` | `test/utils_test.dart` | retired | It asserted the sequential rule; a lone reps row is now an entry with weight 0.0. Replaced by S-1307. |
| `_obs` helper | `test/utils_test.dart` | rewritten | Now takes `entryIndex` (default 0) and mints `obs-e-1-<entryIndex>-<metricKey>` ids, so the grouper suite exercises numbered grouping. |
| `multiple pairs` | `test/utils_test.dart` | updated | Second pair now uses `entryIndex` 1. |

## Fixture repairs (unnumbered ids that now belong to no entry)

Every fixture below built rows with ids carrying no entry number. They were given numbered ids; no
assertion was weakened.

| File | Fixture | Change |
|---|---|---|
| `test/state_test.dart` | `_seedCompletedSetSession` | `obs-reps-$sessionId` / `obs-weight-$sessionId` → `obs-$effortId-0-reps` / `obs-$effortId-0-weight` |
| `test/services_test.dart` | `_seedCompletedSetSession` | same |
| `test/data_tracking_fixes_test.dart` | `_seedCompletedSetSession` | same |
| `test/in_session_pr_toast_test.dart` | `_seedCompletedSetSession` (×2), the S-009 loop, the round/cardio negative fixtures, the zero-weight fixture | all `obs-…` ids → `obs-$effortId-0-…` |

`test/in_session_pr_toast_test.dart` and `test/data_tracking_fixes_test.dart` are **not** in the
plan's Phase 2 Predicted Files; they are added there.

## Doc steps 10–12

| Step | File | Change |
|---|---|---|
| 10 | `docs/data_models.md` § Entry Identity | The sequential-grouping sentence is replaced by the D-705 rule ("a row with no number is in no group, is ignored by every reader and stays stored — there is no sequential grouping of unnumbered rows"); "rows with no number follow in the store's own order" is now explained as the total order for unowned rows; the verification sentence names S-1307 and S-1308. |
| 11 | `docs/distance_source.md` | No change required. `grep -n "leftover\|legacy\|sequential"` → 0 hits; the "Why the write fills earlier gaps" rationale and the "Entries with no row of their own are filled in position" invariant stay (live, D-712). |
| 12 | `docs/stats_best_load_investigation.md` | "(a 3a suffix included)" dropped from the `ObservationGrouper` resolution note. |

## Residue sweep

| Search | Result |
|---|---|
| `obs-` ids in `lib/` | only the writers (`logged_entry_rows.dart`, `watch_session_importer.dart`, the two repositories' clone renamers) — all numbered |
| unnumbered `obs-` fixtures in `test/` | 0 after the repairs above |
| `_entriesAreNumbered`, `_getMetricsPerEntry` | 0 hits in `lib/` |
| `_sequentialGroups` | 0 hits in `lib/` |

## Final verification (this run, verbatim)

`gateway.sh lint`:

```
196 issues found. (ran in 1.5s)
```

0 errors — the same count as the Phase 1 baseline.

`gateway.sh test` (full):

```
01:18 +3242 ~1: All tests passed!
```

Targeted suites (`test/utils_test.dart test/entry_rows_test.dart test/entry_identity_test.dart
test/entry_identity_summary_test.dart test/state_test.dart test/services_test.dart
test/distance_source_test.dart test/data_tracking_fixes_test.dart test/in_session_pr_toast_test.dart`):

```
00:02 +536: All tests passed!
```

## Leftover the owner must remove

None. `test/tmp_probe_inverse_b_test.dart` (a Phase 2 scratch probe) is no longer present on disk and
does not appear in `git-status`; nothing to delete.

---

# Phase 3 — routine drafts, housekeeping, residue sweep

## Baseline at Phase 3 start

`gateway.sh lint`:

```
196 issues found.
```

`gateway.sh test` (full):

```
01:19 +3242 ~1: All tests passed!
```

Targeted suites (`test/state_test.dart test/services_test.dart test/session_summary_distance_test.dart
test/distance_source_test.dart test/docs_indexing_contract_test.dart`):

```
00:04 +335: All tests passed!
```

## Red-first runs

S-1311 and S-1312 were written into `test/state_test.dart` and shown failing before step 1's code
change. `gateway.sh test test/state_test.dart`:

```
00:02 +... -2: Some tests failed.
  routine draft reads the entry its row belongs to S-1311 a timed draft reads each entry's own
  extra-weight row
    Expected: <5.0>
      Actual: <12.0>
  routine draft reads the entry its row belongs to S-1312 a drill draft reads each entry's own
  extra-weight row
    Expected: <-20.0>
      Actual: <-10.0>
```

Both failures are the defect itself: the draft read the first row of the metric rather than the row
belonging to the entry.

S-1313, S-1314, S-1315, S-1316 and S-1317 were green at the Phase 3 baseline and are **guards**, not
red-first. See A-3a3-P3-1 and A-3a3-P3-4.

## Inverse edits

**(a) restore the raw first-row read in the `timed`/`drill` draft branch.** `gateway.sh test
test/state_test.dart test/session_summary_distance_test.dart`:

```
00:03 +... -3: Some tests failed.
  S-1311 ... Expected: <5.0>   Actual: <12.0>
  S-1312 ... Expected: <-20.0> Actual: <-10.0>
  S-1317 ... Expected: <4.0>   Actual: <1000.0>
```

Reverted exactly; the same suites returned `+246: All tests passed!`.

**(b) pass `createdAtMs`-sorted rows into the set draft branch.** `gateway.sh test
test/state_test.dart`:

```
00:02 +230: All tests passed!
```

S-1313 stays green, as A-3a3-P3-1 predicts: `EntryRows.setGroups` re-sorts by number, so the sort
cannot reach the draft's set output. Reverted exactly; `git-diff --stat` after both reverts matches
the pre-inverse baseline (27 files, 1347 insertions, 488 deletions).

## Residue sweep (step 9)

| Search | `lib/` | `test/` |
|---|---|---|
| `DistanceSource.resolve` | 0 | 1 — the guard test's own name and marker list (`distance_source_test.dart:776,785`) |
| `_sequentialGroups` | 0 | 0 |
| `_entriesAreNumbered` | 0 | 0 |
| `_getMetricsPerEntry` | 0 | 0 |
| `previousValues?['distance']` | 0 | 0 |
| `distanceEntries(` with a kind argument | 0 — the only caller (`session_core_entry.dart:411`) passes rows and a count | 0 |
| `_buildEntriesForEffort` | 3 — its definition and its two call sites in `session_summary_builder.dart` (60, 443, 480); live, not retired | 0 |
| `leftover` | 0 in the distance/entry-identity vocabulary; 4 unrelated layout hits (`tile_artwork_metrics.dart`, `macro_donut_chart.dart`, `workout_session_global_timer.dart`) | test names and comments in `entry_identity_test.dart`, `entry_identity_summary_test.dart`, `row_invariants_guard_test.dart` (D-709: the `S-` id is the handle) plus unrelated layout tests |
| `legacy` in the distance/entry-identity vocabulary | 0 — `observation_grouper.dart:51` was the last one and step 1 fixed it. Remaining `lib/` hits are other domains: `modality.dart`, `modality_config.dart`, `data_version.dart`, `data_migration_service.dart`, `image_storage_service_io.dart`, `profile_avatar_image_io.dart`, `measurement_sparkline.dart`, `exercise_editor_screen.dart`, `my_routines_screen.dart`, `seed_data.dart`, nutrition rows, `models.dart` | 0 in the distance vocabulary after the sweep renamed `_legacyDistanceRow` → `_sourcelessDistanceRow` and `legacyMapEfforts` → `sourcelessMapEfforts` in `distance_source_test.dart` and `session_summary_distance_test.dart`, and retitled the `state_test.dart` extra-weight test. Remaining hits are other domains (nutrition, profile, models, layout) |

`_fillEntriesBefore` was not searched: it stays (D-712).

## Step 10 — `ObservationGrouper` positional pairers

Verified present in § Out of scope (lines 611–620): the `timed`/`drill` arms are recorded as live
positional pairers called with those kinds from `session_summary_builder.dart`,
`session_summary_service.dart` and `stats_progress_service.dart`; the `round` arm is recorded as the
only dead one. No code changed.

## Final verification

`gateway.sh lint`:

```
196 issues found.
```

`gateway.sh test` (full):

```
01:16 +3250 ~1: All tests passed!
```

Targeted suites (`test/state_test.dart test/services_test.dart test/session_summary_distance_test.dart
test/distance_source_test.dart test/docs_indexing_contract_test.dart`):

```
00:04 +335: All tests passed!
```

---

# Fix round 1 — review findings F-1..F-6, F-8 (comments, docs, plan text only)

Review: `2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.review.md`. No behaviour change; no new test.

- **F-1** — `lib/data/datasources/food_catalog_loader.dart`: deleted the false claim that
  `scripts/generate_food_catalog_seed.dart` uses `parseCatalogJson`; the class doc now names the two
  real readers (Hive via `loadFromAsset`, Mock via `lib/mock/food_catalog_seed.dart`) and the
  `parseCatalogJson` doc says it is exposed for `test/food_catalog_load_test.dart`.
- **F-2** — `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`: status line now marks 3d
  PLANNED (plan READY, not implemented) with its plan path, keeps 3c "not planned yet", the PR 4 row
  drops its stale `3a3` dependency, and the Scope check says the same.
- **F-3** — plan trimmed 818 → 779 lines: Assumption Log entries to ≤3 lines each (detail stays in
  this file), `A-3a3-P2-4` deleted (F-6), raw suite counts removed from the Progress notes, and the
  Feedback section reduced to the review pointer plus the F-1..F-8 checklist.
- **F-4** — plan scenario registers amended to the asserted outcomes: S-1315 (no distance target, no
  distance row), S-1317 (`SessionDistanceCard.absentValue` for an entry with no distance; entry 0's
  extra weight), S-1304 (dropped the extra-weight-12.0 claim).
- **F-5** — plan S-1302 marked "Retained existing test: S-876 / S-877 in
  `test/distance_source_import_test.dart`"; `test/distance_source_test.dart`'s header now lists
  S-1310 instead of S-1302 (comment only).
- **F-6** — deleted stale Assumption Log entry `A-3a3-P2-4` (tmp probe; already absent from disk).
- **F-8** — `lib/data/models/models.dart`: the comment now reads "a distance that holds a value
  always carries a source" (the rule D-701 states), replacing the "never an entry" typo.

Verification (this round):

- `gateway.sh lint` — `196 issues found.` (0 errors).
- `gateway.sh test test/distance_source_test.dart` — `All tests passed!`
- `gateway.sh test test/docs_indexing_contract_test.dart` — `All tests passed!`
- `gateway.sh test` (full) — `All tests passed!`
